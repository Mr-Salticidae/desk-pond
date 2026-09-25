extends RefCounted
class_name EcoTank

# 生态缸：贝壳经济 + 自由布置 + 轻量生态模拟 + 访客。设计见 docs/设计_生态缸.md。
# - 生态值只由「比例」算出（借 Orb.Farm 的氧气 / 废物循环，但全部夹紧）：
#   失衡只是少拿加成、水色发浑，鱼永远不会死，缸也不会崩。
# - 解锁看「历史最佳星级」：拆掉装饰也不会把已解锁的东西收回去。
# - 纯逻辑、不挂节点，存档里的 "eco" 字典按引用直接修改，方便无头测试。

const ITEMS_PATH := "res://data/tank_items.json"

const STAR_SCORES := [20, 60, 130, 230, 360]   # 评分达到即得对应星级
const PRICE_GROWTH := 1.15      # 同款每多拥有一件，再买贵 15%：永不封顶，又不会一路刷同一件
const COPY_BEAUTY_CAP := 3      # 同款超过 3 件不再加美观
const VARIETY_BONUS := 2        # 每多一种不同的物件 +2 美观
const BASE_SUPPLY := 6          # 水面交换带来的基础氧气 / 自净，缸越大越多
const LEVEL_SUPPLY := 2

const FOCUS_MINUTES_PER_SHELL := 5
const FOCUS_SHELL_CAP := 24
const TASK_SHELL := 2
const TASK_SHELL_DAILY_CAP := 12
const PEARL_VALUE := 2
const PEARL_PENDING_CAP := 15
const WELCOME_SHELLS := 30      # 开缸礼：第一次打开就能进商店试试手

# 鱼种等级：同一种鱼累计钓到 N 条升到 Lv.(i+1)，重复钓获因此也有意义
const LEVEL_THRESHOLDS := [1, 3, 6, 10, 20]

const CATEGORY_NAMES := {
	"plant": "水草",
	"scape": "造景",
	"decor": "装饰",
	"gear": "设备",
	"critter": "生物",
}

var items: Array = []
var item_by_id: Dictionary = {}
var tank_levels: Array = []
var sets: Array = []
var visitors: Array = []
var visitor_by_id: Dictionary = {}
var fish_by_id: Dictionary = {}
var fish_order: Array = []

var state: Dictionary = {}

func _init() -> void:
	_load_catalog()

static func default_state() -> Dictionary:
	return {
		"shells": 0,
		"shells_earned": 0,
		"owned": {},
		"placed": [],
		"next_uid": 1,
		"tank_level": 0,
		"best_stars": 0,
		"last_stars": 0,
		"excluded": {},
		"visitors_arrived": {},
		"visitors_first": {},
		"gifts_given": {},
		"pearls": 0,
		"pearl_date": "",
		"task_shell_date": "",
		"task_shell_count": 0,
		"migrated": false,
		"seen_guide": false,
	}

func _load_catalog() -> void:
	var file := FileAccess.open(ITEMS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	items = parsed.get("items", [])
	tank_levels = parsed.get("tank_levels", [])
	sets = parsed.get("sets", [])
	visitors = parsed.get("visitors", [])
	for it in items:
		item_by_id[String(it.get("id", ""))] = it
	for v in visitors:
		visitor_by_id[String(v.get("id", ""))] = v

# 绑定存档里的 eco 字典与鱼种表。state 按引用保存，之后的修改直接落进存档。
func bind(eco_state: Dictionary, fish_data: Array) -> void:
	state = eco_state
	for key in default_state().keys():
		if not state.has(key):
			state[key] = default_state()[key]
	fish_by_id = {}
	fish_order = []
	for f in fish_data:
		var fid := String(f.get("id", ""))
		if fid == "":
			continue
		fish_by_id[fid] = f
		fish_order.append(fid)
	_sanitize()

# 旧档 / 手改存档的防御：未知物件、摆出去的比拥有的多，都剔掉。
func _sanitize() -> void:
	var owned: Dictionary = state["owned"]
	for key in owned.keys():
		if not item_by_id.has(key):
			owned.erase(key)
	var kept: Array = []
	var used := {}
	var max_uid := 0
	for entry in state["placed"]:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var id := String(entry.get("id", ""))
		if not item_by_id.has(id):
			continue
		if int(used.get(id, 0)) >= owned_count(id):
			continue
		used[id] = int(used.get(id, 0)) + 1
		var uid := int(entry.get("uid", 0))
		max_uid = maxi(max_uid, uid)
		kept.append({
			"uid": uid,
			"id": id,
			"x": clampf(float(entry.get("x", 0.5)), 0.0, 1.0),
			"d": clampf(float(entry.get("d", 0.5)), 0.0, 1.0),
			"flip": bool(entry.get("flip", false)),
		})
	state["placed"] = kept
	state["next_uid"] = maxi(int(state.get("next_uid", 1)), max_uid + 1)

# ---------- 贝壳 ----------

func shells() -> int:
	return int(state.get("shells", 0))

func earn(amount: int) -> int:
	if amount <= 0:
		return 0
	state["shells"] = shells() + amount
	state["shells_earned"] = int(state.get("shells_earned", 0)) + amount
	return amount

func _spend(amount: int) -> bool:
	if amount > shells():
		return false
	state["shells"] = shells() - amount
	return true

# 专注按分钟给贝壳：短于 5 分钟不给，防止用 1 分钟番茄刷；单次封顶。
func focus_reward(minutes: int) -> int:
	return earn(clampi(minutes / FOCUS_MINUTES_PER_SHELL, 0, FOCUS_SHELL_CAP))

# 完成任务给贝壳：每天前 TASK_SHELL_DAILY_CAP 个有效。
func task_reward(today: String) -> int:
	if String(state.get("task_shell_date", "")) != today:
		state["task_shell_date"] = today
		state["task_shell_count"] = 0
	if int(state["task_shell_count"]) >= TASK_SHELL_DAILY_CAP:
		return 0
	state["task_shell_count"] = int(state["task_shell_count"]) + 1
	return earn(TASK_SHELL)

# ---------- 物件 / 库存 ----------

func item(id: String) -> Dictionary:
	return item_by_id.get(id, {})

func owned_count(id: String) -> int:
	return int((state["owned"] as Dictionary).get(id, 0))

func placed_count(id: String) -> int:
	var n := 0
	for entry in state["placed"]:
		if String(entry["id"]) == id:
			n += 1
	return n

func spare_count(id: String) -> int:
	return maxi(owned_count(id) - placed_count(id), 0)

func price_of(id: String) -> int:
	var base := int(item(id).get("price", 0))
	return int(round(base * pow(PRICE_GROWTH, owned_count(id))))

func _grant(id: String, n: int = 1) -> void:
	var owned: Dictionary = state["owned"]
	owned[id] = owned_count(id) + n

# 物件能否在商店购买：{ok, label}。赠礼类要先拿到赠礼，才能再买。
func unlock_state(id: String, ctx: Dictionary) -> Dictionary:
	var it := item(id)
	if it.has("gift"):
		var gift: Dictionary = it["gift"]
		if bool((state["gifts_given"] as Dictionary).get(id, false)):
			return {"ok": true, "label": ""}
		return {"ok": false, "label": "赠礼 · " + _condition_label(gift)}
	if it.has("unlock"):
		var unlock: Dictionary = it["unlock"]
		if not _condition_met(unlock, ctx):
			return {"ok": false, "label": _condition_label(unlock)}
	return {"ok": true, "label": ""}

func _condition_met(cond: Dictionary, ctx: Dictionary) -> bool:
	var value = cond.get("value", 0)
	match String(cond.get("type", "")):
		"stars":
			return int(state.get("best_stars", 0)) >= int(value)
		"trees":
			return int(ctx.get("mature_trees", 0)) >= int(value)
		"sessions":
			return int(ctx.get("total_sessions", 0)) >= int(value)
		"fish":
			var counts: Dictionary = ctx.get("fish_counts", {})
			return int(counts.get(String(value), 0)) > 0
	return true

func _condition_label(cond: Dictionary) -> String:
	var value = cond.get("value", 0)
	match String(cond.get("type", "")):
		"stars":
			return "生态 %d 星解锁" % int(value)
		"trees":
			return "森林长出 %d 棵树" % int(value)
		"sessions":
			return "累计专注 %d 次" % int(value)
		"fish":
			var f: Dictionary = fish_by_id.get(String(value), {})
			return "钓到%s" % String(f.get("name", "神秘的鱼"))
	return ""

# 购买：成功返回 ""，失败返回原因（直接给 UI 显示）。
func buy(id: String, ctx: Dictionary) -> String:
	if not item_by_id.has(id):
		return "没有这件东西"
	var lock := unlock_state(id, ctx)
	if not bool(lock["ok"]):
		return String(lock["label"])
	var price := price_of(id)
	if not _spend(price):
		return "贝壳还差 %d 个" % (price - shells())
	_grant(id)
	return ""

# 里程碑赠礼（原「珊瑚 / 沉船 / 宝箱」解锁）：达成即送一件并自动摆进缸里。
func grant_gifts(ctx: Dictionary) -> Array:
	var granted: Array = []
	var given: Dictionary = state["gifts_given"]
	for it in items:
		if not it.has("gift"):
			continue
		var id := String(it["id"])
		if bool(given.get(id, false)):
			continue
		if _condition_met(it["gift"], ctx):
			given[id] = true
			_grant(id)
			place(id, _free_spot(), 0.55)
			granted.append(it)
	return granted

# 找一个离已有摆件最远的横向位置，给自动摆放用。
func _free_spot() -> float:
	var best_x := 0.5
	var best_gap := -1.0
	for cand in [0.5, 0.22, 0.78, 0.36, 0.64, 0.12, 0.88]:
		var gap := 1.0
		for entry in state["placed"]:
			gap = minf(gap, absf(float(entry["x"]) - float(cand)))
		if gap > best_gap + 0.001:
			best_gap = gap
			best_x = float(cand)
	return best_x

# ---------- 摆放 ----------

func placed() -> Array:
	return state["placed"]

func find_placed(uid: int) -> Dictionary:
	for entry in state["placed"]:
		if int(entry["uid"]) == uid:
			return entry
	return {}

func place(id: String, x: float, d: float) -> int:
	if spare_count(id) <= 0:
		return -1
	var uid := int(state["next_uid"])
	state["next_uid"] = uid + 1
	(state["placed"] as Array).append({
		"uid": uid, "id": id,
		"x": clampf(x, 0.0, 1.0), "d": clampf(d, 0.0, 1.0),
		"flip": false,
	})
	return uid

func move(uid: int, x: float, d: float) -> void:
	var entry := find_placed(uid)
	if entry.is_empty():
		return
	entry["x"] = clampf(x, 0.0, 1.0)
	entry["d"] = clampf(d, 0.0, 1.0)

func flip(uid: int) -> void:
	var entry := find_placed(uid)
	if not entry.is_empty():
		entry["flip"] = not bool(entry.get("flip", false))

# 收回库存：东西从不丢，只是不摆。
func remove(uid: int) -> void:
	var arr: Array = state["placed"]
	for i in range(arr.size()):
		if int(arr[i]["uid"]) == uid:
			arr.remove_at(i)
			return

# 库存里还没摆出去的物件：[{id, count}]，按目录顺序。
func inventory() -> Array:
	var out: Array = []
	for it in items:
		var id := String(it["id"])
		var n := spare_count(id)
		if n > 0:
			out.append({"id": id, "count": n})
	return out

# ---------- 缸体 ----------

func tank_level() -> int:
	return clampi(int(state.get("tank_level", 0)), 0, maxi(tank_levels.size() - 1, 0))

func level_info(level: int) -> Dictionary:
	if level < 0 or level >= tank_levels.size():
		return {}
	return tank_levels[level]

func capacity() -> int:
	return int(level_info(tank_level()).get("capacity", 12))

func upgrade_tank() -> String:
	var next := level_info(tank_level() + 1)
	if next.is_empty():
		return "已经是最大的缸了"
	if int(state.get("best_stars", 0)) < int(next.get("stars", 0)):
		return "生态 %d 星解锁" % int(next.get("stars", 0))
	var price := int(next.get("price", 0))
	if not _spend(price):
		return "贝壳还差 %d 个" % (price - shells())
	state["tank_level"] = tank_level() + 1
	return ""

# ---------- 鱼 ----------

func is_excluded(fish_id: String) -> bool:
	return bool((state["excluded"] as Dictionary).get(fish_id, false))

func set_excluded(fish_id: String, excluded: bool) -> void:
	var ex: Dictionary = state["excluded"]
	if excluded:
		ex[fish_id] = true
	else:
		ex.erase(fish_id)

static func species_level(count: int) -> int:
	var lv := 0
	for t in LEVEL_THRESHOLDS:
		if count >= int(t):
			lv += 1
	return lv

static func next_level_at(count: int) -> int:
	for t in LEVEL_THRESHOLDS:
		if count < int(t):
			return int(t)
	return 0

# 缸里住哪些鱼：按鱼种轮转，每轮各取一条，直到缸满。
# 稀有鱼因此总能露面；没进缸的在池塘里自由游。
func tank_fish(fish_counts: Dictionary) -> Array:
	var remaining: Array = []
	for fid in fish_order:
		var c := int(fish_counts.get(fid, 0))
		if c > 0 and not is_excluded(fid):
			remaining.append([fid, c])
	var out: Array = []
	var cap := capacity()
	var any := true
	while any and out.size() < cap:
		any = false
		for entry in remaining:
			if int(entry[1]) > 0 and out.size() < cap:
				out.append(String(entry[0]))
				entry[1] = int(entry[1]) - 1
				any = true
	return out

func fish_eco(fish_id: String) -> Dictionary:
	return (fish_by_id.get(fish_id, {}) as Dictionary).get("eco", {})

# ---------- 生态评估 ----------

# ctx: {fish_counts, total_sessions, mature_trees}
# 返回 UI 与访客判定需要的全部数值；同时刷新 best_stars / last_stars。
func evaluate(ctx: Dictionary) -> Dictionary:
	var counts: Dictionary = ctx.get("fish_counts", {})
	var fish := tank_fish(counts)
	var per_species := {}
	for fid in fish:
		per_species[fid] = int(per_species.get(fid, 0)) + 1

	var placed_counts := {}
	var plants := 0
	var plant_kinds := {}
	var critters := 0
	var oxygen_supply := float(BASE_SUPPLY + LEVEL_SUPPLY * tank_level())
	var clean_supply := oxygen_supply
	for entry in state["placed"]:
		var id := String(entry["id"])
		var it := item(id)
		placed_counts[id] = int(placed_counts.get(id, 0)) + 1
		oxygen_supply += float(it.get("oxygen", 0))
		clean_supply += float(it.get("clean", 0))
		match String(it.get("category", "")):
			"plant":
				plants += 1
				plant_kinds[id] = true
			"critter":
				critters += 1

	# 美观：同款封顶 3 件 + 种类多样 + 主题套组 + 鱼的喜好
	var beauty := 0.0
	for id in placed_counts:
		beauty += float(item(id).get("beauty", 0)) * mini(int(placed_counts[id]), COPY_BEAUTY_CAP)
	beauty += VARIETY_BONUS * placed_counts.size()
	var done_sets: Array = []
	for s in sets:
		if _set_complete(s, placed_counts, plants, plant_kinds.size()):
			done_sets.append(s)
			beauty += float(s.get("bonus", 0))

	# 生机：鱼种多样、数量、等级、特性
	var demand := 0.0
	var life := 4.0 * per_species.size() + fish.size() * 1.0 + critters * 2.0
	var trait_notes: Array = []
	for fid in per_species:
		var eco := fish_eco(fid)
		var n := int(per_species[fid])
		demand += float(eco.get("bioload", 1)) * n
		life += species_level(int(counts.get(fid, 0)))
		match String(eco.get("trait", "")):
			"cleaner":
				clean_supply += 2.0 * n
			"school":
				if n >= 5:
					beauty += 8.0
					trait_notes.append("通勤沙丁鱼结成了鱼群")
			"likes":
				for like in eco.get("likes", []):
					if placed_counts.has(String(like)):
						beauty += 5.0
						break
			"lucky":
				life += 10.0

	var oxygen := 100.0 if demand <= 0.0 else clampf(oxygen_supply / demand * 100.0, 0.0, 100.0)
	var clean := 100.0 if demand <= 0.0 else clampf(clean_supply / demand * 100.0, 0.0, 100.0)
	var balance := 0.5 + 0.5 * minf(oxygen, clean) / 100.0

	# 访客条件用「未计访客」的星级判断，避免循环依赖
	var base_score := int(round((beauty + life) * balance))
	var probe := {
		"placed_counts": placed_counts, "plants": plants,
		"stars": stars_for(base_score), "tank_level": tank_level(),
	}
	var ready: Array = []
	var present: Array = []
	var arrived: Dictionary = state["visitors_arrived"]
	for v in visitors:
		if _visitor_needs_met(v, probe):
			ready.append(String(v["id"]))
			if bool(arrived.get(String(v["id"]), false)):
				present.append(String(v["id"]))
	life += 6.0 * present.size()

	var score := int(round((beauty + life) * balance))
	var stars := stars_for(score)
	state["last_stars"] = stars
	state["best_stars"] = maxi(int(state.get("best_stars", 0)), stars)

	var total_caught := 0
	for fid in counts:
		total_caught += int(counts[fid])

	var result := {
		"fish": fish,
		"per_species": per_species,
		"capacity": capacity(),
		"total_caught": total_caught,
		"oxygen": oxygen,
		"clean": clean,
		"beauty": beauty,
		"life": life,
		"balance": balance,
		"score": score,
		"stars": stars,
		"best_stars": int(state["best_stars"]),
		"next_star_score": int(STAR_SCORES[stars]) if stars < STAR_SCORES.size() else 0,
		"prev_star_score": int(STAR_SCORES[stars - 1]) if stars > 0 else 0,
		"placed_counts": placed_counts,
		"plants": plants,
		"sets": done_sets,
		"trait_notes": trait_notes,
		"visitors_ready": ready,
		"visitors_present": present,
	}
	result["hints"] = _hints(result)
	return result

static func stars_for(score: int) -> int:
	var s := 0
	for t in STAR_SCORES:
		if score >= int(t):
			s += 1
	return s

func _set_complete(s: Dictionary, placed_counts: Dictionary, plants: int, plant_kinds: int) -> bool:
	if s.has("plant_kinds"):
		return plant_kinds >= int(s["plant_kinds"]) and plants >= int(s.get("plant_count", 0))
	for id in s.get("items", []):
		if not placed_counts.has(String(id)):
			return false
	return true

func _visitor_needs_met(v: Dictionary, probe: Dictionary) -> bool:
	var placed_counts: Dictionary = probe["placed_counts"]
	for need in v.get("needs", []):
		var need_min := int(need.get("min", 1))
		if need.has("items"):
			var n := 0
			for id in need["items"]:
				n += int(placed_counts.get(String(id), 0))
			if n < need_min:
				return false
		elif need.has("stat"):
			if int(probe.get(String(need["stat"]), 0)) < need_min:
				return false
	return true

func _hints(r: Dictionary) -> Array:
	var hints: Array = []
	var fish: Array = r["fish"]
	if fish.is_empty():
		hints.append("完成一次专注钓到鱼，它们会住进这里")
	if float(r["oxygen"]) < 80.0:
		hints.append("氧气只有 %d%%：种些水草，或放个气泡石" % int(r["oxygen"]))
	if float(r["clean"]) < 80.0:
		hints.append("水质只有 %d%%：苹果螺、过滤器、键盘泥鳅都能帮忙" % int(r["clean"]))
	if (state["placed"] as Array).is_empty():
		hints.append("点「布置」，把买来的东西摆进缸里")
	var waiting := 0
	for id in r["visitors_ready"]:
		if not (r["visitors_present"] as Array).has(id):
			waiting += 1
	if waiting > 0:
		hints.append("有客人在缸外徘徊……完成一次专注看看")
	var overflow := int(r["total_caught"]) - fish.size()
	if overflow > 0 and fish.size() >= int(r["capacity"]):
		hints.append("还有 %d 条鱼在池塘里，扩缸就能接它们进来" % overflow)
	if int(r["next_star_score"]) > 0:
		hints.append("再得 %d 分升到 %d 星" % [int(r["next_star_score"]) - int(r["score"]), int(r["stars"]) + 1])
	return hints

# ---------- 访客 ----------

# 专注完成时调用（Spirit City 式：专注是发现访客的途径）。
# 条件已满足、但还没来过的访客在此刻「游进来」；首次到访送一份谢礼。
func arrive_visitors(eval: Dictionary, today: String) -> Array:
	var arrived: Dictionary = state["visitors_arrived"]
	var first: Dictionary = state["visitors_first"]
	var newcomers: Array = []
	for id in eval.get("visitors_ready", []):
		if bool(arrived.get(id, false)):
			continue
		arrived[id] = true
		var v: Dictionary = visitor_by_id.get(id, {})
		if not first.has(id):
			first[id] = today
			earn(int(v.get("gift", 0)))
		newcomers.append(v)
	return newcomers

func visitor_seen(id: String) -> bool:
	return (state["visitors_first"] as Dictionary).has(id)

# ---------- 珍珠（生态红利）----------

# 每个打开应用的新一天，缸按上次星级产出珍珠；没领的会一直等着（有上限）。
func accrue_pearls(today: String) -> void:
	var last := String(state.get("pearl_date", ""))
	if last == today:
		return
	if last != "":
		state["pearls"] = mini(int(state.get("pearls", 0)) + int(state.get("last_stars", 0)), PEARL_PENDING_CAP)
	state["pearl_date"] = today

func pearls() -> int:
	return int(state.get("pearls", 0))

func take_pearl() -> int:
	if pearls() <= 0:
		return 0
	state["pearls"] = pearls() - 1
	return earn(PEARL_VALUE)

# ---------- 旧档迁移 ----------

# 生态缸上线前的存档：把过去的努力折成贝壳，按已有鱼数给够缸位，
# 旧版三件里程碑装饰按原开关 / 槽位摆回缸里。所有人都有一份开缸礼（贝壳 + 入门水草）。
func migrate_legacy(save: Dictionary, ctx: Dictionary) -> int:
	if bool(state.get("migrated", false)):
		return 0
	state["migrated"] = true
	var back_pay := WELCOME_SHELLS + int(save.get("total_focus_sessions", 0)) * 5 + int(save.get("total_tasks_completed", 0)) * 2
	earn(back_pay)

	var total := 0
	var counts: Dictionary = ctx.get("fish_counts", {})
	for fid in counts:
		total += int(counts[fid])
	var level := 0
	while level < tank_levels.size() - 1 and int(level_info(level).get("capacity", 0)) < mini(total, 40):
		level += 1
	state["tank_level"] = level

	_grant("grass", 2)
	_grant("rock", 1)
	place("grass", 0.12, 0.25)
	place("grass", 0.88, 0.35)
	place("rock", 0.30, 0.85)

	const LEGACY_SLOTS := [0.20, 0.50, 0.80]
	var prefs: Dictionary = save.get("aquarium_decor", {})
	var given: Dictionary = state["gifts_given"]
	for id in ["coral", "shipwreck", "chest"]:
		var it := item(id)
		if it.is_empty() or not _condition_met(it["gift"], ctx):
			continue
		given[id] = true
		_grant(id)
		var pref: Dictionary = prefs.get(id, {})
		if bool(pref.get("on", true)):
			var slot := clampi(int(pref.get("slot", 0)), 0, LEGACY_SLOTS.size() - 1)
			place(id, float(LEGACY_SLOTS[slot]), 0.55)
	return back_pay
