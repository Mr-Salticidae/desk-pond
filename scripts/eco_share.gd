extends RefCounted
class_name EcoShare

# 分享码：把一只生态缸（摆件 / 缸里的鱼 / 访客 / 星级 / 缸名）压成一段短码，
# 放进链接的 ?tank= 参数里，朋友点开就能逛你的缸——不需要服务器，也不用截图。
#
# 二进制格式 v1（最后 base64url 编码，不带 =）：
#   [0] 版本 = 1
#   [1] 缸级(bit0-1) | 星级(bit2-4)
#   [2] 氧气%  [3] 水质%
#   [4] 缸名字节数 N，随后 N 字节 UTF-8
#   鱼：种数 F，随后 F × [鱼种下标, 缸内条数, 等级]
#   访客：2 字节位图（小端）
#   摆件：件数 P，随后 P × [物件下标, x(0-255), 景深(0-127) | 翻转(bit7)]
#   [末] 校验和 = 之前所有字节之和 & 0xFF
# 下标取自 data/tank_items.json 的 items / visitors 与 data/fish_data.json 的顺序，
# 所以新物件 / 访客 / 鱼种只能追加到末尾，不能调换已有顺序，否则旧分享码会错位。
# 解码的输入来自别人，一律当不可信数据：校验和、长度、下标都要检查，越界的条目直接跳过。

const VERSION := 1
const MAX_NAME_CHARS := 12
const MAX_PLACED := 80
const MAX_FISH_IN_TANK := 40
const PARAM := "tank"
# 分享链接的固定落地页：B站 Toy 外层地址。桌面版靠它给出可点开的链接（留空则只给分享码）；
# Web 版也优先用它——Toy 把游戏套在带版本号的 iframe 里（…/<id>-v18577/index.html），
# 从页面 location 拼出来的链接会随每次 Toy 更新失效。外层地址会把 ?tank= 原样转给 iframe（2026-09-29 实测）。
const SHARE_WEB_URL := "https://www.bilibili.com/toy/6BterUHrdJEq8SiW/index.html"

# 从当前缸拍一张「快照」，缸名为空时用默认名
static func snapshot(eco: EcoTank, ev: Dictionary, levels: Dictionary, tank_name: String) -> Dictionary:
	var fish := {}
	for fid in (ev.get("per_species", {}) as Dictionary):
		fish[String(fid)] = int(ev["per_species"][fid])
	var lv := {}
	for fid in fish:
		lv[fid] = clampi(int(levels.get(fid, 1)), 1, 5)
	var placed: Array = []
	for e in eco.placed():
		if placed.size() >= MAX_PLACED:
			break
		placed.append({"id": String(e["id"]), "x": float(e["x"]), "d": float(e["d"]), "flip": bool(e.get("flip", false))})
	return {
		"name": clean_name(tank_name),
		"tank_level": eco.tank_level(),
		"stars": int(ev.get("stars", 0)),
		"oxygen": int(ev.get("oxygen", 100)),
		"clean": int(ev.get("clean", 100)),
		"fish": fish,
		"levels": lv,
		"visitors": (ev.get("visitors_present", []) as Array).duplicate(),
		"placed": placed,
	}

# 缸名：去掉首尾空白与控制字符，最多 12 个字
static func clean_name(text: String) -> String:
	var out := ""
	for ch in text.strip_edges():
		if ch.unicode_at(0) >= 0x20 and ch.unicode_at(0) != 0x7F:
			out += ch
	return out.substr(0, MAX_NAME_CHARS)

static func encode(snap: Dictionary, eco: EcoTank) -> String:
	var b := PackedByteArray()
	b.append(VERSION)
	b.append((clampi(int(snap.get("tank_level", 0)), 0, 3)) | (clampi(int(snap.get("stars", 0)), 0, 5) << 2))
	b.append(clampi(int(snap.get("oxygen", 100)), 0, 100))
	b.append(clampi(int(snap.get("clean", 100)), 0, 100))
	var name_bytes := clean_name(String(snap.get("name", ""))).to_utf8_buffer()
	b.append(name_bytes.size())
	b.append_array(name_bytes)

	var fish_entries: Array = []
	var fish: Dictionary = snap.get("fish", {})
	var levels: Dictionary = snap.get("levels", {})
	for i in range(mini(eco.fish_order.size(), 256)):
		var fid := String(eco.fish_order[i])
		var n := clampi(int(fish.get(fid, 0)), 0, MAX_FISH_IN_TANK)
		if n > 0:
			fish_entries.append([i, n, clampi(int(levels.get(fid, 1)), 1, 5)])
	b.append(fish_entries.size())
	for e in fish_entries:
		b.append(int(e[0]))
		b.append(int(e[1]))
		b.append(int(e[2]))

	var mask := 0
	var present: Array = snap.get("visitors", [])
	for i in range(mini(eco.visitors.size(), 16)):
		if present.has(String(eco.visitors[i]["id"])):
			mask |= 1 << i
	b.append(mask & 0xFF)
	b.append((mask >> 8) & 0xFF)

	var item_index := {}
	for i in range(mini(eco.items.size(), 256)):
		item_index[String(eco.items[i]["id"])] = i
	var entries: Array = []
	for e in snap.get("placed", []):
		var id := String(e.get("id", ""))
		if item_index.has(id) and entries.size() < MAX_PLACED:
			entries.append(e)
	b.append(entries.size())
	for e in entries:
		b.append(int(item_index[String(e["id"])]))
		b.append(clampi(int(round(float(e.get("x", 0.5)) * 255.0)), 0, 255))
		b.append(clampi(int(round(float(e.get("d", 0.5)) * 127.0)), 0, 127) | (0x80 if bool(e.get("flip", false)) else 0))

	b.append(_checksum(b))
	return Marshalls.raw_to_base64(b).replace("+", "-").replace("/", "_").replace("=", "")

# 解码：可以是纯分享码，也可以是带 ?tank= 的整条链接或一段含链接的分享文案。失败返回 {}。
static func decode(text: String, eco: EcoTank) -> Dictionary:
	var code := extract_code(text)
	# 长度模 4 余 1 不可能是合法 base64，提前拒绝，免得引擎报解码错误
	if code == "" or code.length() > 2048 or code.length() % 4 == 1:
		return {}
	var b64 := code.replace("-", "+").replace("_", "/")
	while b64.length() % 4 != 0:
		b64 += "="
	var b := Marshalls.base64_to_raw(b64)
	if b.size() < 9 or b[0] != VERSION:
		return {}
	if _checksum(b.slice(0, b.size() - 1)) != b[b.size() - 1]:
		return {}
	var r := _Reader.new(b.slice(0, b.size() - 1))
	r.u8()   # 版本字节，上面已校验
	var head := r.u8()
	var snap := {
		"tank_level": head & 0x3,
		"stars": mini((head >> 2) & 0x7, 5),
		"oxygen": mini(r.u8(), 100),
		"clean": mini(r.u8(), 100),
	}
	var name_len := r.u8()
	snap["name"] = clean_name(r.bytes(name_len).get_string_from_utf8())

	var fish := {}
	var levels := {}
	var total := 0
	for _i in range(r.u8()):
		var idx := r.u8()
		var n := r.u8()
		var lv := clampi(r.u8(), 1, 5)
		if idx >= eco.fish_order.size() or n <= 0 or total >= MAX_FISH_IN_TANK:
			continue
		n = mini(n, MAX_FISH_IN_TANK - total)
		total += n
		var fid := String(eco.fish_order[idx])
		fish[fid] = n
		levels[fid] = lv
	snap["fish"] = fish
	snap["levels"] = levels

	var mask := r.u8() | (r.u8() << 8)
	var visitors: Array = []
	for i in range(mini(eco.visitors.size(), 16)):
		if mask & (1 << i):
			visitors.append(String(eco.visitors[i]["id"]))
	snap["visitors"] = visitors

	var placed: Array = []
	for _i in range(r.u8()):
		var idx := r.u8()
		var xb := r.u8()
		var db := r.u8()
		if idx >= eco.items.size() or placed.size() >= MAX_PLACED:
			continue
		placed.append({"id": String(eco.items[idx]["id"]), "x": xb / 255.0, "d": (db & 0x7F) / 127.0, "flip": (db & 0x80) != 0})
	snap["placed"] = placed
	if r.overrun:
		return {}
	return snap

# 从一段文字里找出分享码：优先认 tank= 参数，否则整段当分享码
static func extract_code(text: String) -> String:
	var t := text.strip_edges()
	var at := t.find(PARAM + "=")
	if at >= 0:
		t = t.substr(at + PARAM.length() + 1)
	var out := ""
	for ch in t:
		if (ch >= "A" and ch <= "Z") or (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "-" or ch == "_":
			out += ch
		elif out != "":
			break
	return out

static func share_path(code: String) -> String:
	return "index.html?%s=%s" % [PARAM, code]

# 朋友的缸：拼一只只读的 EcoTank（只有摆件与缸级），交给 AquariumView 画
static func build_tank(snap: Dictionary, fish_data: Array) -> EcoTank:
	var state := EcoTank.default_state()
	var owned := {}
	var placed: Array = []
	var uid := 1
	for e in snap.get("placed", []):
		var id := String(e["id"])
		owned[id] = int(owned.get(id, 0)) + 1
		placed.append({"uid": uid, "id": id, "x": float(e["x"]), "d": float(e["d"]), "flip": bool(e["flip"])})
		uid += 1
	state["owned"] = owned
	state["placed"] = placed
	state["tank_level"] = int(snap.get("tank_level", 0))
	state["migrated"] = true
	var t := EcoTank.new()
	t.bind(state, fish_data)
	return t

# 按快照原样还原评估结果（不重新计算：朋友看到的就是分享时的样子）
static func build_eval(snap: Dictionary, tank: EcoTank) -> Dictionary:
	var fish: Array = []
	var per_species := {}
	for fid in tank.fish_order:
		var n := int((snap.get("fish", {}) as Dictionary).get(fid, 0))
		if n > 0:
			per_species[fid] = n
	# 轮转展开，和自己缸里的排布方式一致
	var remaining := per_species.duplicate()
	var any := true
	while any:
		any = false
		for fid in tank.fish_order:
			if int(remaining.get(fid, 0)) > 0:
				fish.append(fid)
				remaining[fid] = int(remaining[fid]) - 1
				any = true
	var stars := int(snap.get("stars", 0))
	return {
		"fish": fish,
		"per_species": per_species,
		"capacity": tank.capacity(),
		"total_caught": fish.size(),
		"oxygen": float(snap.get("oxygen", 100)),
		"clean": float(snap.get("clean", 100)),
		"stars": stars,
		"score": int(EcoTank.STAR_SCORES[stars - 1]) if stars > 0 else 0,
		"prev_star_score": int(EcoTank.STAR_SCORES[stars - 1]) if stars > 0 else 0,
		"next_star_score": 0,
		"visitors_present": (snap.get("visitors", []) as Array).duplicate(),
		"visitors_ready": (snap.get("visitors", []) as Array).duplicate(),
	}

static func summary(snap: Dictionary) -> String:
	var n := 0
	for fid in (snap.get("fish", {}) as Dictionary):
		n += int(snap["fish"][fid])
	return "%d 条鱼 · %d 种 · %d 位访客 · %d 件摆设" % [n, (snap.get("fish", {}) as Dictionary).size(), (snap.get("visitors", []) as Array).size(), (snap.get("placed", []) as Array).size()]

static func display_name(snap: Dictionary) -> String:
	var n := String(snap.get("name", ""))
	return n if n != "" else "一只生态缸"

static func _checksum(b: PackedByteArray) -> int:
	var s := 0
	for v in b:
		s += v
	return s & 0xFF

# 带越界保护的字节读取器：读过头返回 0 并记下 overrun
class _Reader:
	var data: PackedByteArray
	var pos := 0
	var overrun := false

	func _init(d: PackedByteArray) -> void:
		data = d

	func u8() -> int:
		if pos >= data.size():
			overrun = true
			return 0
		pos += 1
		return data[pos - 1]

	func bytes(n: int) -> PackedByteArray:
		if pos + n > data.size():
			overrun = true
			pos = data.size()
			return PackedByteArray()
		pos += n
		return data.slice(pos - n, pos)
