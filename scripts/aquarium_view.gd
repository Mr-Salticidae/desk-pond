extends Control
class_name AquariumView

# 水族馆房间：把累计钓获的鱼放进缸里游动，越钓越热闹。
# 鱼的数量与种类由 fish_count 确定性推导（只增不减、不封顶）。
# 与森林不同，这里有逐帧动画（鱼在游），用 anim_timer 驱动；
# 不可见时自动暂停，零浪费。

const MAX_FISH := 40       # 同时绘制的鱼上限（计数标签仍显示真实条数）
const LOOP := 480.0        # 动画循环帧数（anim_timer 每 0.1s 一帧 → 约 48s 一圈）

# 缸体配色
const TANK_BG := Color(0.10, 0.14, 0.17)
const GLASS_RIM := Color(0.16, 0.30, 0.38)
const WATER_TOP := Color(0.20, 0.52, 0.62)
const WATER_BOTTOM := Color(0.13, 0.36, 0.48)
const SHEEN := Color(0.50, 0.78, 0.82, 0.32)
const SAND := Color(0.82, 0.74, 0.52)
const SAND_DARK := Color(0.70, 0.62, 0.42)
const PLANT := Color(0.24, 0.55, 0.33)
const PLANT_SOFT := Color(0.33, 0.66, 0.40)
const BUBBLE := Color(0.85, 0.94, 0.96, 0.55)
const INK_LIGHT := Color(0.93, 0.97, 0.98)
const INK_SOFT := Color(0.80, 0.90, 0.93)

# 每种鱼的体色（按 fish id）：[主色, 鳍/尾色]
const FISH_COLORS := {
	"slacking_crucian": [Color(0.55, 0.62, 0.42), Color(0.42, 0.50, 0.32)],
	"salted_fish": [Color(0.78, 0.74, 0.70), Color(0.62, 0.58, 0.55)],
	"meeting_carp": [Color(0.85, 0.55, 0.30), Color(0.70, 0.42, 0.22)],
	"commute_sardine": [Color(0.62, 0.70, 0.78), Color(0.48, 0.56, 0.66)],
	"keyboard_loach": [Color(0.50, 0.42, 0.30), Color(0.38, 0.32, 0.22)],
	"deadline_goldfish": [Color(0.97, 0.66, 0.22), Color(0.88, 0.46, 0.16)],
	"weekly_pufferfish": [Color(0.86, 0.78, 0.45), Color(0.70, 0.62, 0.34)],
	"overtime_eel": [Color(0.34, 0.30, 0.42), Color(0.24, 0.22, 0.30)],
	"annual_koi": [Color(0.97, 0.55, 0.30), Color(0.95, 0.95, 0.95)],
	"slacking_legend": [Color(0.95, 0.80, 0.30), Color(0.80, 0.62, 0.18)],
}

# 里程碑解锁的装饰：达标后入缸，玩家可在「档案」里开关 / 换位。
# unlock_type: total_sessions(累计专注次数) / fish(钓到某条鱼)
const DECOR := [
	{"id": "coral", "name": "珊瑚", "unlock_type": "total_sessions", "unlock_value": 10, "unlock_label": "累计专注 10 次"},
	{"id": "shipwreck", "name": "沉船", "unlock_type": "total_sessions", "unlock_value": 40, "unlock_label": "累计专注 40 次"},
	{"id": "chest", "name": "宝箱", "unlock_type": "fish", "unlock_value": "annual_koi", "unlock_label": "钓到年度锦鲤"},
]
# 装饰槽位（缸底，0/1/2 = 左/中/右）
const DECOR_SLOTS := [0.20, 0.50, 0.80]

var title_label: Label
var count_label: Label
var hint_label: Label

var anim_timer: Timer
var tank_frame := 0.0

var fish_list: Array = []   # 已展开到实例级：[{id, depth} ...]，最多 MAX_FISH
var total_fish := 0
var distinct := 0
var active_decor: Array = []   # 当前已解锁且开启的装饰：[{id, slot} ...]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label = _make_label(18, INK_LIGHT)
	title_label.text = "你的水族馆"
	title_label.position = Vector2(18, 14)
	count_label = _make_label(13, INK_SOFT)
	count_label.position = Vector2(18, 40)
	hint_label = _make_label(13, INK_SOFT)
	hint_label.position = Vector2(18, 62)
	_refresh_labels()

	anim_timer = Timer.new()
	anim_timer.wait_time = 0.1
	anim_timer.timeout.connect(_on_anim_tick)
	add_child(anim_timer)
	_sync_timer()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
	elif what == NOTIFICATION_VISIBILITY_CHANGED:
		_sync_timer()

# 只在可见时跑动画，省 CPU。
func _sync_timer() -> void:
	if anim_timer == null:
		return
	if is_visible_in_tree():
		if anim_timer.is_stopped():
			anim_timer.start()
	else:
		anim_timer.stop()

func _make_label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	add_child(l)
	return l

# 某装饰是否已按里程碑解锁；main 也用它来渲染「布置」界面。
static func decor_unlocked(decor: Dictionary, stats: Dictionary) -> bool:
	match String(decor.get("unlock_type", "")):
		"total_sessions":
			return int(stats.get("total_sessions", 0)) >= int(decor.get("unlock_value", 0))
		"fish":
			var fc: Dictionary = stats.get("fish_counts", {})
			return int(fc.get(String(decor.get("unlock_value", "")), 0)) > 0
	return false

func update_tank(fishing_manager: FishingManager, ctx: Dictionary = {}) -> void:
	var counts := fishing_manager.get_fish_count()
	var data := fishing_manager.get_fish_data()
	total_fish = 0
	var seen := {}
	var remaining: Array = []   # [[id, 剩余数] ...]
	for fish in data:
		var fish_id := String(fish.get("id", ""))
		var c := int(counts.get(fish_id, 0))
		if fish_id == "" or c <= 0:
			continue
		total_fish += c
		seen[fish_id] = true
		remaining.append([fish_id, c])
	distinct = seen.size()

	# 轮转展开：每轮各取一条，保证稀有鱼也露面、分布大致按数量，封顶 MAX_FISH。
	fish_list = []
	var any := true
	while any and fish_list.size() < MAX_FISH:
		any = false
		for entry in remaining:
			if int(entry[1]) > 0 and fish_list.size() < MAX_FISH:
				fish_list.append({"id": String(entry[0])})
				entry[1] = int(entry[1]) - 1
				any = true

	# 给每条鱼定一个确定性的景深（用于分层、缩放、排序）
	for i in range(fish_list.size()):
		fish_list[i]["depth"] = _hash(i * 2 + 3)
	fish_list.sort_custom(func(a, b): return float(a["depth"]) < float(b["depth"]))

	# 装饰：解锁且开启的才入缸
	var stats := {"total_sessions": int(ctx.get("total_sessions", 0)), "fish_counts": counts}
	var prefs: Dictionary = ctx.get("decor", {})
	active_decor = []
	for decor in DECOR:
		if not decor_unlocked(decor, stats):
			continue
		var pref: Dictionary = prefs.get(String(decor["id"]), {})
		if not bool(pref.get("on", true)):
			continue
		active_decor.append({"id": String(decor["id"]), "slot": int(pref.get("slot", 0))})

	_refresh_labels()
	queue_redraw()

func _refresh_labels() -> void:
	if count_label:
		count_label.text = "%d 条 · %d 种" % [total_fish, distinct]
	if hint_label:
		if total_fish == 0:
			hint_label.text = "完成专注，钓到的鱼会在这里游"
		else:
			hint_label.text = "钓到的鱼都在这里，越钓越热闹"

func _on_anim_tick() -> void:
	tank_frame = fmod(tank_frame + 1.0, LOOP)
	queue_redraw()

func _water_rect() -> Rect2:
	return Rect2(Vector2(6, 6), Vector2(maxf(size.x - 12.0, 8.0), maxf(size.y - 12.0, 8.0)))

func _draw() -> void:
	var phase := tank_frame / LOOP * TAU
	_draw_tank(phase)
	_draw_plants(phase)
	_draw_decor()
	_draw_fish_all(phase)
	_draw_bubbles()

func _draw_tank(phase: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), TANK_BG)
	var water := _water_rect()
	draw_rect(water.grow(2.0), GLASS_RIM)
	# 水体竖向渐变：几条横带由浅入深
	var bands := 6
	for i in range(bands):
		var t := i / float(bands - 1)
		var col := WATER_TOP.lerp(WATER_BOTTOM, t)
		var y := water.position.y + water.size.y * (i / float(bands))
		draw_rect(Rect2(Vector2(water.position.x, y), Vector2(water.size.x, water.size.y / bands + 1.0)), col)
	# 顶部光纹：横向缓移的亮带，画两份做无缝循环
	var caustics := 3
	for i in range(caustics):
		var cx := fmod(phase / TAU * water.size.x + i * water.size.x / caustics, water.size.x)
		_px(water.position.x + cx, water.position.y + 4.0, 26, 5, SHEEN)
		_px(water.position.x + cx - water.size.x, water.position.y + 4.0, 26, 5, SHEEN)
	# 缸底沙
	var sand_h := 14.0
	var sy := water.position.y + water.size.y - sand_h
	draw_rect(Rect2(Vector2(water.position.x, sy), Vector2(water.size.x, sand_h)), SAND)
	for i in range(10):
		var px := water.position.x + 10.0 + _hash(i + 1) * (water.size.x - 20.0)
		_px(px, sy + 4.0 + (i % 3) * 3.0, 4, 3, SAND_DARK)

func _draw_plants(phase: float) -> void:
	var water := _water_rect()
	var base_y := water.position.y + water.size.y - 14.0
	var spots := [0.12, 0.30, 0.70, 0.88]
	for s_i in range(spots.size()):
		var bx: float = water.position.x + water.size.x * float(spots[s_i])
		var segs := 4 + (s_i % 2)
		for j in range(segs):
			var sway := sin(phase * 1.5 + j * 0.6 + s_i) * (2.0 + j * 1.2)
			var y := base_y - j * 9.0
			var col: Color = PLANT if j % 2 == 0 else PLANT_SOFT
			_px(bx + sway - 2.0, y - 9.0, 5, 10, col)

func _draw_bubbles() -> void:
	var water := _water_rect()
	var cols := [0.22, 0.55, 0.80]
	for c_i in range(cols.size()):
		var bx: float = water.position.x + water.size.x * float(cols[c_i])
		for b in range(3):
			var prog := fmod(tank_frame / LOOP + b / 3.0 + c_i * 0.13, 1.0)
			var by := water.position.y + water.size.y - 14.0 - prog * (water.size.y - 22.0)
			var r := 2.0 + b
			_px(bx, by, r, r, BUBBLE)

func _draw_fish_all(phase: float) -> void:
	if fish_list.is_empty():
		return
	var water := _water_rect()
	var top := water.position.y + 16.0
	var sand_top := water.position.y + water.size.y - 16.0
	var margin := 24.0
	for i in range(fish_list.size()):
		var f: Dictionary = fish_list[i]
		var depth := float(f["depth"])
		var scale := 0.7 + depth * 0.6
		var speed := 0.8 + _hash(i * 3 + 1) * 0.8
		var phase_off := _hash(i * 3 + 2) * TAU
		var swing := phase * speed + phase_off
		var cx := water.position.x + margin + (water.size.x - margin * 2.0) * (0.5 + 0.5 * sin(swing))
		var cy := top + depth * (sand_top - top) + sin(phase * 2.0 + phase_off) * 3.0
		var facing := 1.0 if cos(swing) >= 0.0 else -1.0
		_draw_fish(Vector2(cx, cy), scale, String(f["id"]), facing, phase + phase_off)

func _draw_fish(c: Vector2, s: float, fish_id: String, facing: float, ph: float) -> void:
	if fish_id == "drift_bottle":
		_draw_bottle(c, s, ph)
		return
	if fish_id == "overtime_eel":
		_draw_eel(c, s, facing, ph)
		return
	if fish_id == "weekly_pufferfish":
		_draw_puffer(c, s, facing)
		return
	var cols: Array = FISH_COLORS.get(fish_id, [Color(0.6, 0.6, 0.6), Color(0.45, 0.45, 0.45)])
	var body: Color = cols[0]
	var fin: Color = cols[1]
	var bw := 14.0 * s
	var bh := 7.0 * s
	# 身体 + 背鳍
	_px(c.x - bw * 0.5, c.y - bh * 0.5, bw, bh, body)
	_px(c.x - bw * 0.32, c.y - bh * 0.5 - 2.0 * s, bw * 0.5, 2.0 * s, fin)
	# 尾巴：在身体后方（与朝向相反）
	var tail_x := c.x - facing * (bw * 0.5)
	_px(tail_x - (3.0 * s if facing > 0.0 else 0.0), c.y - bh * 0.5, 3.0 * s, bh, fin)
	# 眼睛：靠近前方；咸鱼用一对小叉，致敬"咸鱼"梗
	var eye := maxf(1.5 * s, 1.0)
	var ex := c.x + facing * (bw * 0.30)
	if fish_id == "salted_fish":
		_px(ex - eye * 0.5, c.y - 1.5 * s, eye * 1.6, maxf(s, 1.0), Color(0.20, 0.22, 0.24))
		_px(ex, c.y - 2.0 * s, maxf(s, 1.0), eye * 1.6, Color(0.20, 0.22, 0.24))
	else:
		_px(ex, c.y - 1.0 * s, eye, eye, Color(0.08, 0.10, 0.12))

func _draw_puffer(c: Vector2, s: float, facing: float) -> void:
	var cols: Array = FISH_COLORS["weekly_pufferfish"]
	var body: Color = cols[0]
	var fin: Color = cols[1]
	var d := 12.0 * s   # 近乎圆球
	_px(c.x - d * 0.5, c.y - d * 0.5, d, d, body)
	# 四向小刺
	_px(c.x - d * 0.5 - 2.0 * s, c.y - 1.0 * s, 2.0 * s, 2.0 * s, fin)
	_px(c.x + d * 0.5, c.y - 1.0 * s, 2.0 * s, 2.0 * s, fin)
	_px(c.x - 1.0 * s, c.y - d * 0.5 - 2.0 * s, 2.0 * s, 2.0 * s, fin)
	_px(c.x - 1.0 * s, c.y + d * 0.5, 2.0 * s, 2.0 * s, fin)
	# 小尾
	var tail_x := c.x - facing * (d * 0.5)
	_px(tail_x - (3.0 * s if facing > 0.0 else 0.0), c.y - 2.0 * s, 3.0 * s, 4.0 * s, fin)
	# 眼睛
	var eye := maxf(1.5 * s, 1.0)
	_px(c.x + facing * (d * 0.22), c.y - 2.0 * s, eye, eye, Color(0.08, 0.10, 0.12))

func _draw_eel(c: Vector2, s: float, facing: float, ph: float) -> void:
	var cols: Array = FISH_COLORS["overtime_eel"]
	var dark: Color = cols[0]
	var segs := 7
	var seg_w := 5.0 * s
	for i in range(segs):
		var t := i - (segs - 1) / 2.0
		var x := c.x + facing * t * seg_w
		var y := c.y + sin(ph * 1.5 + i * 0.7) * 4.0 * s
		var hh := (4.0 if i < segs - 2 else 2.5) * s
		_px(x - seg_w * 0.5, y - hh * 0.5, seg_w + 1.0, hh, dark)
	# 头部眼睛
	var hx := c.x + facing * ((segs - 1) / 2.0) * seg_w
	var eye := maxf(1.5 * s, 1.0)
	_px(hx, c.y - 1.0 * s, eye, eye, Color(0.85, 0.85, 0.90))

func _draw_bottle(c: Vector2, s: float, _ph: float) -> void:
	var glass := Color(0.55, 0.78, 0.70, 0.85)
	var cork := Color(0.70, 0.52, 0.32)
	var bw := 8.0 * s
	var bh := 14.0 * s
	_px(c.x - bw * 0.5, c.y - bh * 0.5, bw, bh, glass)                       # 瓶身
	_px(c.x - 2.0 * s, c.y - bh * 0.5 - 4.0 * s, 4.0 * s, 4.0 * s, glass)    # 瓶颈
	_px(c.x - 1.5 * s, c.y - bh * 0.5 - 6.0 * s, 3.0 * s, 2.0 * s, cork)     # 瓶塞
	_px(c.x - bw * 0.35, c.y - 1.0 * s, bw * 0.7, 3.0 * s, Color(0.93, 0.90, 0.80))  # 标签

func _draw_decor() -> void:
	if active_decor.is_empty():
		return
	var water := _water_rect()
	var base_y := water.position.y + water.size.y - 13.0   # 落在沙面上
	for d in active_decor:
		var slot := clampi(int(d["slot"]), 0, DECOR_SLOTS.size() - 1)
		var bx: float = water.position.x + water.size.x * float(DECOR_SLOTS[slot])
		match String(d["id"]):
			"coral":
				_draw_coral(Vector2(bx, base_y))
			"shipwreck":
				_draw_shipwreck(Vector2(bx, base_y))
			"chest":
				_draw_chest(Vector2(bx, base_y))

func _draw_coral(base: Vector2) -> void:
	var c1 := Color(0.86, 0.42, 0.46)
	var c2 := Color(0.93, 0.60, 0.50)
	_px(base.x - 3.0, base.y - 18.0, 6, 18, c1)         # 主干
	_px(base.x - 10.0, base.y - 14.0, 5, 12, c2)        # 左枝
	_px(base.x + 6.0, base.y - 16.0, 5, 14, c2)         # 右枝
	_px(base.x - 11.0, base.y - 20.0, 5, 7, c1)         # 左枝顶
	_px(base.x + 7.0, base.y - 23.0, 5, 8, c1)          # 右枝顶

func _draw_shipwreck(base: Vector2) -> void:
	var hull := Color(0.42, 0.30, 0.22)
	var hull_dark := Color(0.32, 0.22, 0.16)
	var mast := Color(0.50, 0.38, 0.26)
	_px(base.x - 22.0, base.y - 12.0, 44, 12, hull)     # 船身
	_px(base.x - 22.0, base.y - 4.0, 44, 4, hull_dark)  # 船底阴影
	_px(base.x - 6.0, base.y - 30.0, 4, 20, mast)       # 断桅（微倾）
	_px(base.x - 14.0, base.y - 16.0, 6, 5, hull_dark)  # 破洞

func _draw_chest(base: Vector2) -> void:
	var wood := Color(0.55, 0.38, 0.22)
	var lid := Color(0.46, 0.31, 0.18)
	var gold := Color(0.95, 0.80, 0.30)
	_px(base.x - 9.0, base.y - 11.0, 18, 11, wood)      # 箱体
	_px(base.x - 9.0, base.y - 16.0, 18, 5, lid)        # 箱盖
	_px(base.x - 2.0, base.y - 13.0, 4, 5, gold)        # 锁扣
	_px(base.x - 9.0, base.y - 8.0, 18, 2, lid)         # 箱箍

func _px(x: float, y: float, w: float, h: float, color: Color) -> void:
	draw_rect(Rect2(Vector2(x, y).round(), Vector2(maxf(w, 1.0), maxf(h, 1.0)).round()), color)

func _hash(n: int) -> float:
	var v := sin(float(n) * 12.9898 + 78.233) * 43758.5453
	return v - floor(v)
