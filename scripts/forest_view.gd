extends Control
class_name ForestView

# 森林房间：把累计完成的任务画成一片越来越茂密、越来越多样的林子。
# 白天无逐帧动画，仅在成长变化 / 昼夜变化时重绘——静态、零性能负担；
# 只有夜里亮起萤火虫时才开一个低频动画计时器。

const MAX_DRAW := 60  # 绘制上限（计数标签仍显示真实棵数）

const GRASS_FAR := Color(0.42, 0.66, 0.43)
const GRASS_NEAR := Color(0.33, 0.55, 0.36)
const TRUNK := Color(0.44, 0.28, 0.16)
const BROAD_1 := Color(0.34, 0.68, 0.36)
const BROAD_2 := Color(0.25, 0.55, 0.30)
const PINE := Color(0.21, 0.47, 0.30)
const BLOSSOM_1 := Color(0.93, 0.68, 0.76)
const BLOSSOM_2 := Color(0.86, 0.54, 0.64)
const FRUIT_DOT := Color(0.86, 0.31, 0.26)
const MAPLE_1 := Color(0.87, 0.47, 0.23)
const MAPLE_2 := Color(0.74, 0.35, 0.17)

const FIREFLY := Color(0.86, 1.0, 0.45)
const TITLE_INK := Color(0.15, 0.27, 0.18)
const COUNT_INK := Color(0.26, 0.39, 0.27)
const HINT_INK := Color(0.30, 0.40, 0.30)

var title_label: Label
var count_label: Label
var hint_label: Label
var firefly_timer: Timer
var firefly_t := 0.0

var species_list: Array = []
var mature := 0
var distinct := 1
var cur_stage := 0
var to_next := 4
var total_points := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label = _make_label(18, TITLE_INK, true)
	title_label.text = "你的森林"
	title_label.position = Vector2(18, 14)
	count_label = _make_label(13, COUNT_INK, false)
	count_label.position = Vector2(18, 40)
	hint_label = _make_label(13, HINT_INK, false)
	hint_label.position = Vector2(18, 62)
	firefly_timer = Timer.new()
	firefly_timer.wait_time = 0.15
	firefly_timer.timeout.connect(func():
		firefly_t += firefly_timer.wait_time
		queue_redraw()
	)
	add_child(firefly_timer)
	DayCycle.changed.connect(_on_day_changed)
	_on_day_changed()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
	elif what == NOTIFICATION_VISIBILITY_CHANGED:
		_sync_firefly_timer()

# 昼夜变了：重绘、文字换色；萤火虫只在夜里、森林可见时动
func _on_day_changed() -> void:
	var n := DayCycle.night
	title_label.add_theme_color_override("font_color", DayCycle.ink_for(n, TITLE_INK))
	count_label.add_theme_color_override("font_color", DayCycle.ink_for(n, COUNT_INK))
	hint_label.add_theme_color_override("font_color", DayCycle.ink_for(n, HINT_INK))
	_sync_firefly_timer()
	queue_redraw()

func _sync_firefly_timer() -> void:
	if firefly_timer == null or not firefly_timer.is_inside_tree():
		return
	var want := DayCycle.night > 0.05 and is_visible_in_tree()
	if want and firefly_timer.is_stopped():
		firefly_timer.start()
	elif not want and not firefly_timer.is_stopped():
		firefly_timer.stop()

func _make_label(font_size: int, color: Color, bold: bool) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	add_child(l)
	return l

func update_forest(tree_manager: TreeManager) -> void:
	total_points = tree_manager.growth_points
	mature = tree_manager.mature_count()
	cur_stage = tree_manager.current_stage()
	to_next = tree_manager.points_to_next_tree()
	distinct = tree_manager.distinct_species(mature)
	species_list = []
	for i in range(min(mature, MAX_DRAW)):
		species_list.append(tree_manager.species_for_index(i))
	if count_label:
		count_label.text = "%d 棵 · %d 树种" % [mature, distinct]
	if hint_label:
		if total_points == 0:
			hint_label.text = "完成任务，这里会长出你的第一棵树"
		else:
			hint_label.text = "再完成 %d 个任务，下一棵就成材" % to_next
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), DayCycle.sky)
	var grass_top := h * 0.50
	draw_rect(Rect2(Vector2(0, grass_top), Vector2(w, h - grass_top)), GRASS_FAR)
	draw_rect(Rect2(Vector2(0, h * 0.70), Vector2(w, h * 0.30)), GRASS_NEAR)

	# 成材的树：用确定性散列布点，按景深从后往前画
	var items: Array = []
	for i in range(species_list.size()):
		var depth := _hash(i * 2 + 2)
		items.append({
			"x": 22.0 + _hash(i * 2 + 1) * (w - 44.0),
			"y": grass_top + 12.0 + depth * (h - grass_top - 30.0),
			"scale": 0.55 + depth * 0.6,
			"sp": int(species_list[i]),
			"depth": depth,
		})
	items.sort_custom(func(a, b): return a["depth"] < b["depth"])
	for it in items:
		_draw_tree(Vector2(it["x"], it["y"]), it["scale"], it["sp"])

	# 正在长的那棵苗：前景居中，作为"下一棵在这里"的焦点
	_draw_sapling(Vector2(w * 0.5, h * 0.95), cur_stage)

	# 昼夜：整体压一层天色；夜里亮起萤火虫（设计_森林与水族馆.md 里留待打磨的「夜萤」）
	if DayCycle.overlay.a > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), DayCycle.overlay)
	if DayCycle.night > 0.05:
		_draw_fireflies(w, h, DayCycle.night)

# 萤火虫：林子越大越多（至少 6 只、最多 24 只），各自绕一个点慢慢飘、明灭
func _draw_fireflies(w: float, h: float, night: float) -> void:
	var count := clampi(6 + mature, 6, 24)
	for i in range(count):
		var ax := 20.0 + _hash(i * 7 + 101) * (w - 40.0)
		var ay := h * 0.40 + _hash(i * 7 + 102) * h * 0.50
		var sp := 0.4 + _hash(i * 7 + 103) * 0.5
		var p := Vector2(ax + sin(firefly_t * sp + i) * 14.0, ay + cos(firefly_t * sp * 1.3 + i * 2.0) * 8.0)
		var blink := clampf(0.5 + 0.6 * sin(firefly_t * (1.2 + sp) + i * 1.9), 0.0, 1.0)
		var c := FIREFLY
		c.a = night * blink * 0.25
		_px(p.x - 2.0, p.y - 2.0, 6.0, 6.0, c)
		c.a = night * blink
		_px(p.x, p.y, 2.0, 2.0, c)

func _draw_tree(base: Vector2, s: float, species: int) -> void:
	var tw := maxf(7.0 * s, 3.0)
	var th := maxf(20.0 * s, 8.0)
	_px(base.x - tw * 0.5, base.y - th, tw, th, TRUNK)
	var cx := base.x
	var cy := base.y - th
	var cw := 30.0 * s
	var ch := 24.0 * s
	match species:
		TreeManager.SPECIES_PINE:
			_px(cx - cw * 0.45, cy - ch * 0.55, cw * 0.9, ch * 0.45, PINE)
			_px(cx - cw * 0.33, cy - ch * 1.0, cw * 0.66, ch * 0.45, PINE)
			_px(cx - cw * 0.2, cy - ch * 1.4, cw * 0.4, ch * 0.45, PINE)
		TreeManager.SPECIES_BLOSSOM:
			_px(cx - cw * 0.5, cy - ch, cw, ch, BLOSSOM_1)
			_px(cx - cw * 0.3, cy - ch * 1.22, cw * 0.6, ch * 0.6, BLOSSOM_2)
		TreeManager.SPECIES_FRUIT:
			_px(cx - cw * 0.5, cy - ch, cw, ch, BROAD_1)
			_px(cx - cw * 0.32, cy - ch * 1.2, cw * 0.62, ch * 0.6, BROAD_2)
			_px(cx - cw * 0.26, cy - ch * 0.62, 3.0 * s, 3.0 * s, FRUIT_DOT)
			_px(cx + cw * 0.12, cy - ch * 0.82, 3.0 * s, 3.0 * s, FRUIT_DOT)
		TreeManager.SPECIES_MAPLE:
			_px(cx - cw * 0.5, cy - ch, cw, ch, MAPLE_1)
			_px(cx - cw * 0.3, cy - ch * 1.22, cw * 0.6, ch * 0.6, MAPLE_2)
		_:
			_px(cx - cw * 0.5, cy - ch, cw, ch, BROAD_1)
			_px(cx - cw * 0.3, cy - ch * 1.22, cw * 0.6, ch * 0.6, BROAD_2)

func _draw_sapling(base: Vector2, stage: int) -> void:
	if stage <= 0:
		# 刚种下：一对嫩芽
		_px(base.x - 6.0, base.y - 8.0, 5.0, 5.0, BROAD_1)
		_px(base.x + 1.0, base.y - 10.0, 5.0, 6.0, BROAD_2)
		_px(base.x - 1.0, base.y - 6.0, 3.0, 8.0, TRUNK)
		return
	_draw_tree(base, 0.32 + stage * 0.18, TreeManager.SPECIES_BROADLEAF)

func _px(x: float, y: float, w: float, h: float, color: Color) -> void:
	draw_rect(Rect2(Vector2(x, y).round(), Vector2(maxf(w, 1.0), maxf(h, 1.0)).round()), color)

func _hash(n: int) -> float:
	var v := sin(float(n) * 12.9898 + 78.233) * 43758.5453
	return v - floor(v)
