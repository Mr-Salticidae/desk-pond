extends Control
class_name AquariumView

# 水族馆房间 = 玩家自己搭的生态缸。
# 数据（摆件 / 贝壳 / 生态值）都在 EcoTank，这里只管画、动和交互：
# - 平时：鱼按简单的转向行为游（Reynolds steering；沙丁鱼成群），点水面投喂，
#   点鱼看它是谁，缸里冒出的珍珠泡泡点一下收集贝壳。氧气不足时鱼会「浮头」，
#   水质差时水色发浑——只是看得见的提示，不会有鱼死掉。
# - 布置：拖动摆件（左右 = 位置，上下 = 前后景深），从底部库存条放新东西进来。
# 动画由 anim_timer 驱动，不可见时自动暂停，零浪费。

signal layout_changed
signal pearl_tapped(pos: Vector2)
signal shop_requested
signal report_requested
signal edit_mode_changed(on: bool)

const TICK := 0.05
const MAX_FOOD := 12
const MAX_PEARLS_SHOWN := 3
const STRIP_H := 64.0
const LOW_OXYGEN := 50.0
const MURKY_CLEAN := 70.0
const ITEM_MARGIN := 14.0
const DROP_SPOTS := [0.5, 0.4, 0.6, 0.3, 0.7, 0.2, 0.8]

# 缸体配色
const TANK_BG := Color(0.10, 0.14, 0.17)
const GLASS_RIM := Color(0.16, 0.30, 0.38)
const WATER_TOP := Color(0.20, 0.52, 0.62)
const WATER_BOTTOM := Color(0.13, 0.36, 0.48)
const SHEEN := Color(0.50, 0.78, 0.82, 0.32)
const SAND := Color(0.82, 0.74, 0.52)
const SAND_BACK := Color(0.74, 0.66, 0.46)
const SAND_DARK := Color(0.70, 0.62, 0.42)
const BUBBLE := Color(0.85, 0.94, 0.96, 0.55)
const MURK := Color(0.36, 0.44, 0.22)
const INK_LIGHT := Color(0.93, 0.97, 0.98)
const INK_SOFT := Color(0.80, 0.90, 0.93)
const STAR_ON := Color(0.98, 0.80, 0.30)
const STAR_OFF := Color(0.93, 0.97, 0.98, 0.25)
const BAR_BG := Color(0.93, 0.97, 0.98, 0.18)
const SELECT := Color(1.0, 0.90, 0.50)

# 一条鱼 / 一位访客的运动状态。位置按游动区归一化（0..1），尺寸变了也不会跑出缸。
class Agent:
	var kind := ""
	var visitor := false
	var move := "swim"      # swim / floor / hover / drift / home / cruise
	var level := 1
	var school := false
	var pos := Vector2(0.5, 0.5)
	var vel := Vector2.ZERO  # 像素 / 秒
	var target := Vector2(0.5, 0.5)
	var depth := 0.5
	var speed := 30.0        # 1 倍像素 / 秒
	var retarget := 0.0
	var flee := 0.0
	var heart := 0.0
	var left := false
	var seed := 0

var eco: EcoTank
var eval: Dictionary = {}
var names: Dictionary = {}
var levels: Dictionary = {}

var agents: Array = []
var school_goals: Dictionary = {}   # kind -> {"target": Vector2, "t": float}
var food: Array = []                # [{pos, vy, life}]（像素坐标）
var floats: Array = []              # 飘字 [{text, pos, t, color}]
var pearls: Array = []              # 可见的珍珠泡泡 [{x, y, stop, seed}]（按水体归一化）
var pending_pearls := 0
var pearl_timer := 0.0
var name_tag: Dictionary = {}       # {text, agent, t}
var time := 0.0
var anim_timer: Timer
var _seed_counter := 0
var _synced_once := false

var edit_mode := false
# 只读展示（朋友的缸 / 分享卡片）：不能布置、没有珍珠、不开生态报告；喂鱼、点鱼照常
var read_only := false
var show_hud := true
# 跟随昼夜（水色变深、萤光水母发光、加班鳗鱼夜里更勤）。分享卡片是一张「照片」，关掉保持白天
var use_day_cycle := true
var selected_uid := -1
var hover_uid := -1
var dragging := false
var drag_offset := Vector2.ZERO
var _strip_sig := ""
var _drop_count := 0

var title_label: Label
var info_label: Label
var hud_button: Button
var tools_panel: PanelContainer
var tools_label: Label
var flip_button: Button
var stow_button: Button
var strip_panel: PanelContainer
var strip_row: HBoxContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	title_label = _make_label(18, INK_LIGHT)
	title_label.text = "你的水族馆"
	title_label.position = Vector2(18, 12)
	info_label = _make_label(13, INK_SOFT)
	info_label.position = Vector2(18, 38)

	# 左上角整块 HUD 可点，打开生态报告
	hud_button = Button.new()
	hud_button.flat = true
	hud_button.focus_mode = Control.FOCUS_NONE
	hud_button.tooltip_text = "查看生态报告"
	hud_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hud_button.position = Vector2(10, 8)
	hud_button.size = Vector2(220, 76)
	hud_button.pressed.connect(func(): report_requested.emit())
	add_child(hud_button)

	_build_edit_ui()
	_layout_overlays()
	_refresh_labels()

	anim_timer = Timer.new()
	anim_timer.wait_time = TICK
	anim_timer.timeout.connect(_on_anim_tick)
	add_child(anim_timer)
	_sync_timer()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		food.clear()
		_layout_overlays()
		queue_redraw()
	elif what == NOTIFICATION_VISIBILITY_CHANGED:
		_sync_timer()
		if not is_visible_in_tree() and edit_mode:
			set_edit_mode(false)

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

func _build_edit_ui() -> void:
	tools_panel = PanelContainer.new()
	tools_panel.add_theme_stylebox_override("panel", UITheme.chrome_bar_style())
	tools_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 10)
	tools_panel.visible = false
	add_child(tools_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	tools_panel.add_child(row)
	tools_label = Label.new()
	tools_label.custom_minimum_size = Vector2(52, 0)
	tools_label.add_theme_font_size_override("font_size", 13)
	tools_label.add_theme_color_override("font_color", UITheme.INK_ON_CHROME)
	tools_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(tools_label)
	flip_button = _tool_button("翻转", "左右镜像", _flip_selected)
	row.add_child(flip_button)
	stow_button = _tool_button("收回", "放回库存（东西不会丢）", _stow_selected)
	row.add_child(stow_button)
	var done := _tool_button("完成", "结束布置", func(): set_edit_mode(false))
	UITheme.style_primary(done)
	row.add_child(done)

	strip_panel = PanelContainer.new()
	strip_panel.add_theme_stylebox_override("panel", UITheme.chrome_bar_style())
	strip_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip_panel.offset_top = -STRIP_H
	strip_panel.visible = false
	add_child(strip_panel)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 8)
	strip_panel.add_child(strip)
	var shop_button := Button.new()
	shop_button.text = "商店"
	shop_button.focus_mode = Control.FOCUS_NONE
	shop_button.tooltip_text = "用贝壳买水草、装饰和设备"
	UITheme.style_primary(shop_button)
	shop_button.pressed.connect(func(): shop_requested.emit())
	strip.add_child(shop_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	strip.add_child(scroll)
	strip_row = HBoxContainer.new()
	strip_row.add_theme_constant_override("separation", 6)
	scroll.add_child(strip_row)

func _tool_button(text: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	UITheme.style_chrome(b)
	b.pressed.connect(action)
	return b

# ---------- 外部接口 ----------

# main 在任何会影响缸的事件后调用：钓到鱼、买东西、布置变化、换天……
func update_tank(tank: EcoTank, evaluation: Dictionary, fish_names: Dictionary, species_levels: Dictionary) -> void:
	eco = tank
	eval = evaluation
	names = fish_names
	levels = species_levels
	_sync_agents()
	set_pending_pearls(eco.pearls())
	_refresh_labels()
	if edit_mode:
		_rebuild_strip(false)
		_refresh_tools()
	queue_redraw()

func set_pending_pearls(n: int) -> void:
	pending_pearls = maxi(n, 0)
	while pearls.size() > pending_pearls:
		pearls.pop_back()

func float_text(pos: Vector2, text: String, color := Color(1.0, 0.92, 0.60)) -> void:
	floats.append({"text": text, "pos": pos, "t": 1.4, "color": color})

func set_presentation(read_only_mode: bool, hud: bool, title: String) -> void:
	read_only = read_only_mode
	show_hud = hud
	title_label.text = title
	title_label.visible = hud
	info_label.visible = hud
	hud_button.visible = hud and not read_only
	_layout_overlays()
	queue_redraw()

func set_edit_mode(on: bool) -> void:
	if read_only and on:
		return
	if edit_mode == on:
		return
	edit_mode = on
	selected_uid = -1
	hover_uid = -1
	dragging = false
	food.clear()
	name_tag = {}
	tools_panel.visible = on
	strip_panel.visible = on
	title_label.visible = not on and show_hud
	info_label.visible = not on and show_hud
	hud_button.visible = not on and show_hud and not read_only
	if on:
		_rebuild_strip(true)
	_refresh_tools()
	_layout_overlays()
	edit_mode_changed.emit(on)
	queue_redraw()

func _refresh_labels() -> void:
	if info_label == null:
		return
	var fish: Array = eval.get("fish", [])
	if fish.is_empty():
		info_label.text = "完成专注钓到鱼，它们会住进这里"
		return
	var species := (eval.get("per_species", {}) as Dictionary).size()
	info_label.text = "%d 条 · %d 种 · 缸位 %d/%d" % [fish.size(), species, fish.size(), int(eval.get("capacity", 0))]

# ---------- 鱼群同步 ----------

func _sync_agents() -> void:
	var pool := {}
	for a in agents:
		if not pool.has(a.kind):
			pool[a.kind] = []
		pool[a.kind].append(a)
	var next: Array = []
	for fid in eval.get("fish", []):
		next.append(_reuse_or_new(pool, String(fid), false))
	for vid in eval.get("visitors_present", []):
		next.append(_reuse_or_new(pool, String(vid), true))
	agents = next
	_synced_once = true

func _reuse_or_new(pool: Dictionary, kind: String, is_visitor: bool) -> Agent:
	var a: Agent
	if pool.has(kind) and not (pool[kind] as Array).is_empty():
		a = (pool[kind] as Array).pop_back()
	else:
		a = Agent.new()
		a.kind = kind
		a.visitor = is_visitor
		a.seed = _seed_counter
		_seed_counter += 1
		a.depth = TankArt.hash01(a.seed * 7 + 3)
		# 首次打开时鱼散在缸里；之后新来的鱼从水面落进来
		a.pos = Vector2(randf_range(0.1, 0.9), 0.0 if _synced_once else randf_range(0.1, 0.9))
		if is_visitor:
			var v: Dictionary = eco.visitor_by_id.get(kind, {})
			a.move = String(v.get("move", "swim"))
			a.speed = {"floor": 8.0, "hover": 5.0, "drift": 5.0, "home": 12.0, "cruise": 9.0}.get(a.move, 20.0)
			if a.move == "floor":
				a.depth = 0.3 + a.depth * 0.6
			a.pos.y = 1.0 if a.move == "floor" else a.pos.y
		else:
			a.speed = 22.0 + TankArt.hash01(a.seed * 3 + 1) * 18.0
			a.school = String(eco.fish_eco(kind).get("trait", "")) == "school"
		a.target = a.pos
	a.level = int(levels.get(kind, 1))
	return a

# ---------- 几何 ----------

func _water_rect() -> Rect2:
	var bottom := STRIP_H + 4.0 if edit_mode else 0.0
	return Rect2(Vector2(6, 6), Vector2(maxf(size.x - 12.0, 8.0), maxf(size.y - 12.0 - bottom, 8.0)))

# 像素倍率：缸大（全屏 / 竖屏长屏）时物件跟着放大，但保持 0.5 的整齐步进
func _ps() -> float:
	var water := _water_rect()
	return clampf(snappedf(minf(water.size.y / 190.0, water.size.x / 300.0), 0.5), 1.0, 3.0)

func _sand_h(water: Rect2) -> float:
	return clampf(water.size.y * 0.15, 16.0, 60.0 * _ps())

# 窄屏（手机竖屏）：场景区横向放不下左右两条浮层
const NARROW_W := 520.0

func is_narrow() -> bool:
	return size.x < NARROW_W

# 窄屏时右上角的「鱼缸 / 图鉴 / 布置 / 分享」条会压住左上角，HUD 让到它下面。
# 布置时 main 会把那条收起（布置是独立模式，靠「完成」退出），布置工具条就留在最顶上——
# 否则两条深色条一左一右错开叠在水面上，提示字再压第三层（2026-09-29 手机实测反馈）。
func _top_offset() -> float:
	return 44.0 if is_narrow() and not read_only and not edit_mode else 0.0

func _layout_overlays() -> void:
	var y := _top_offset()
	if title_label:
		title_label.position = Vector2(18, 12 + y)
		info_label.position = Vector2(18, 38 + y)
		hud_button.position = Vector2(10, 8 + y)
	if tools_panel:
		tools_panel.position = Vector2(10, 10 + y)

func _sand_top(water: Rect2) -> float:
	return water.end.y - _sand_h(water)

func _swim_rect(water: Rect2) -> Rect2:
	var top := water.position.y + 12.0
	return Rect2(Vector2(water.position.x + 10.0, top), Vector2(maxf(water.size.x - 20.0, 4.0), maxf(_sand_top(water) - top - 4.0, 4.0)))

func _item_base(entry: Dictionary, water: Rect2) -> Vector2:
	var x := water.position.x + ITEM_MARGIN + float(entry["x"]) * (water.size.x - ITEM_MARGIN * 2.0)
	if TankArt.is_surface(String(entry["id"])):
		return Vector2(x, water.position.y + 3.0)
	return Vector2(x, _sand_top(water) + 3.0 + float(entry["d"]) * (_sand_h(water) - 5.0))

func _item_scale(entry: Dictionary) -> float:
	if TankArt.is_surface(String(entry["id"])):
		return _ps()
	return _ps() * (0.8 + 0.2 * float(entry["d"]))

func _is_critter(id: String) -> bool:
	return eco != null and String(eco.item(id).get("category", "")) == "critter" or id == "moss_ball"

func _item_offset(entry: Dictionary) -> Vector2:
	var id := String(entry["id"])
	if edit_mode or not _is_critter(id):
		return Vector2.ZERO
	return TankArt.critter_offset(id, int(entry["uid"]), time) * _item_scale(entry)

func _item_rect(entry: Dictionary, water: Rect2) -> Rect2:
	var s := _item_scale(entry)
	var sz := TankArt.item_size(String(entry["id"])) * s
	var base := _item_base(entry, water) + _item_offset(entry)
	if TankArt.is_surface(String(entry["id"])):
		return Rect2(Vector2(base.x - sz.x * 0.5, base.y - 1.0 * s), sz)
	return Rect2(Vector2(base.x - sz.x * 0.5, base.y - sz.y), sz)

func _agent_scale(a: Agent) -> float:
	if a.visitor:
		return _ps() * (0.85 + a.depth * 0.3)
	return _ps() * (0.65 + a.depth * 0.5)

func _agent_center(a: Agent, water: Rect2, zone: Rect2) -> Vector2:
	var p := zone.position + a.pos * zone.size
	if a.move == "floor":
		var s := _agent_scale(a)
		var base_y := _sand_top(water) + 3.0 + a.depth * (_sand_h(water) - 5.0)
		p.y = base_y - TankArt.visitor_size(a.kind).y * s * 0.5
	return p

# ---------- 动画 ----------

func _on_anim_tick() -> void:
	time += TICK
	_update_agents(TICK)
	if not edit_mode:
		_update_food(TICK)
		if not read_only:
			_update_pearls(TICK)
	for i in range(floats.size() - 1, -1, -1):
		floats[i]["t"] = float(floats[i]["t"]) - TICK
		floats[i]["pos"] = (floats[i]["pos"] as Vector2) + Vector2(0, -18.0 * TICK)
		if float(floats[i]["t"]) <= 0.0:
			floats.remove_at(i)
	if not name_tag.is_empty():
		name_tag["t"] = float(name_tag["t"]) - TICK
		if float(name_tag["t"]) <= 0.0:
			name_tag = {}
	queue_redraw()

func _pick_target(a: Agent) -> Vector2:
	match a.move:
		"floor":
			return Vector2(randf_range(0.05, 0.95), 1.0)
		"hover":
			var xs := _placed_x_where(func(it): return String(it.get("category", "")) == "plant")
			var hx: float = xs.pick_random() if not xs.is_empty() else randf()
			return Vector2(clampf(hx + randf_range(-0.04, 0.04), 0.0, 1.0), randf_range(0.45, 0.85))
		"drift":
			return Vector2(randf_range(0.1, 0.9), randf_range(0.05, 0.55))
		"home":
			var homes: Array = (eco.visitor_by_id.get(a.kind, {}) as Dictionary).get("home", [])
			var xs := _placed_x_where(func(it): return homes.has(String(it.get("id", ""))))
			var hx: float = xs.pick_random() if not xs.is_empty() else 0.5
			return Vector2(clampf(hx + randf_range(-0.07, 0.07), 0.0, 1.0), randf_range(0.72, 1.0))
		"cruise":
			return Vector2(0.92 if a.pos.x < 0.5 else 0.08, randf_range(0.25, 0.7))
	# 普通的鱼：氧气不够时聚到水面「浮头」——真实鱼缸的缺氧信号
	if float(eval.get("oxygen", 100.0)) < LOW_OXYGEN:
		return Vector2(randf_range(0.05, 0.95), randf_range(0.0, 0.22))
	return Vector2(randf_range(0.04, 0.96), randf_range(0.04, 0.96))

func _placed_x_where(pred: Callable) -> Array:
	var xs: Array = []
	if eco == null:
		return xs
	for e in eco.placed():
		if pred.call(eco.item(String(e["id"]))):
			xs.append(float(e["x"]))
	return xs

func _update_agents(dt: float) -> void:
	var water := _water_rect()
	var zone := _swim_rect(water)
	var ps := _ps()
	# 群游：同一种「school」鱼共享一个目标点，各自带一点偏移
	for kind in school_goals.keys():
		var g: Dictionary = school_goals[kind]
		g["t"] = float(g["t"]) - dt
	for a in agents:
		var p: Vector2 = zone.position + a.pos * zone.size
		var goal := p
		var max_speed: float = a.speed * ps
		# 加班鳗鱼是夜猫子：夜里游得更快、换方向更勤
		if a.kind == "overtime_eel" and use_day_cycle:
			max_speed *= 1.0 + 0.6 * DayCycle.night
			a.retarget -= dt * DayCycle.night
		var food_i := -1
		if a.flee > 0.0:
			a.flee -= dt
			max_speed *= 2.6
			var away: Vector2 = a.vel.normalized() if a.vel.length() > 0.1 else Vector2.RIGHT
			goal = p + away * 60.0 * ps
		elif not a.visitor and not food.is_empty():
			food_i = _nearest_food(p)
			goal = food[food_i]["pos"]
			max_speed *= 1.7
		elif a.school and float(eval.get("oxygen", 100.0)) >= LOW_OXYGEN:
			if not school_goals.has(a.kind) or float(school_goals[a.kind]["t"]) <= 0.0:
				school_goals[a.kind] = {"target": Vector2(randf_range(0.1, 0.9), randf_range(0.1, 0.8)), "t": randf_range(4.0, 8.0)}
			var offset := Vector2(TankArt.hash01(a.seed * 5) - 0.5, TankArt.hash01(a.seed * 5 + 1) - 0.5) * Vector2(0.16, 0.14)
			goal = zone.position + ((school_goals[a.kind]["target"] as Vector2) + offset) * zone.size
		else:
			a.retarget -= dt
			var tp: Vector2 = zone.position + a.target * zone.size
			if a.retarget <= 0.0 or p.distance_to(tp) < 6.0 * ps:
				a.target = _pick_target(a)
				a.retarget = randf_range(4.0, 9.0)
				tp = zone.position + a.target * zone.size
			goal = tp
		var to_goal := goal - p
		var dist := to_goal.length()
		var desired := Vector2.ZERO
		if dist > 0.5:
			desired = to_goal / dist * max_speed * clampf(dist / (24.0 * ps), 0.15, 1.0)
		var steer := 6.0 if a.flee > 0.0 else (1.6 if a.visitor else 2.8)
		a.vel = a.vel.lerp(desired, clampf(dt * steer, 0.0, 1.0))
		p += a.vel * dt
		p = p.clamp(zone.position, zone.end)
		a.pos = ((p - zone.position) / zone.size).clamp(Vector2.ZERO, Vector2.ONE)
		if a.move == "floor":
			a.pos.y = 1.0
		if absf(a.vel.x) > 2.0 * ps:
			a.left = a.vel.x < 0.0
		a.heart = maxf(a.heart - dt, 0.0)
		if food_i >= 0 and p.distance_to(food[food_i]["pos"]) < 5.0 * ps:
			food.remove_at(food_i)
			a.heart = 1.4

func _nearest_food(p: Vector2) -> int:
	var best := 0
	var best_d := INF
	for i in range(food.size()):
		var d := p.distance_squared_to(food[i]["pos"])
		if d < best_d:
			best_d = d
			best = i
	return best

func _update_food(dt: float) -> void:
	var water := _water_rect()
	var floor_y := _sand_top(water) + 2.0
	for i in range(food.size() - 1, -1, -1):
		var f: Dictionary = food[i]
		f["life"] = float(f["life"]) - dt
		var pos: Vector2 = f["pos"]
		if pos.y < floor_y:
			pos.y += float(f["vy"]) * dt
			pos.x += sin(time * 2.0 + i) * 0.3
			f["pos"] = pos
		if float(f["life"]) <= 0.0:
			food.remove_at(i)

func _update_pearls(dt: float) -> void:
	pearl_timer -= dt
	if pearl_timer <= 0.0 and pearls.size() < mini(pending_pearls, MAX_PEARLS_SHOWN):
		pearls.append({"x": randf_range(0.15, 0.85), "y": 1.0, "stop": randf_range(0.18, 0.45), "seed": randi() % 97})
		pearl_timer = 2.5
	for p in pearls:
		if float(p["y"]) > float(p["stop"]):
			p["y"] = maxf(float(p["stop"]), float(p["y"]) - dt * 0.12)

func _pearl_pos(p: Dictionary, water: Rect2) -> Vector2:
	var usable := _sand_top(water) - water.position.y
	return Vector2(water.position.x + float(p["x"]) * water.size.x,
		water.position.y + float(p["y"]) * usable + sin(time * 1.5 + int(p["seed"])) * 2.0 * _ps())

# ---------- 输入 ----------

func _gui_input(event: InputEvent) -> void:
	if eco == null:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if edit_mode:
				_edit_press(mb.position)
			else:
				_play_tap(mb.position)
			accept_event()
		elif dragging:
			# 以松手位置收尾：Web 上移动事件可能被合帧丢掉，保证东西落在手指离开的地方
			_edit_drag(mb.position)
			dragging = false
			layout_changed.emit()
			accept_event()
	elif event is InputEventMouseMotion and edit_mode:
		var mm := event as InputEventMouseMotion
		if dragging:
			_edit_drag(mm.position)
		else:
			var uid := _item_at(mm.position)
			if uid != hover_uid:
				hover_uid = uid
				mouse_default_cursor_shape = Control.CURSOR_MOVE if uid >= 0 else Control.CURSOR_ARROW
				queue_redraw()

func _play_tap(pos: Vector2) -> void:
	var water := _water_rect()
	var ps := _ps()
	# 1) 珍珠泡泡
	for i in range(pearls.size()):
		var pp := _pearl_pos(pearls[i], water)
		if pp.distance_to(pos) < 14.0 * ps:
			pearls.remove_at(i)
			pearl_tapped.emit(pp)
			return
	# 2) 鱼：显示名字，受惊窜开，附近的也吓一跳
	var zone := _swim_rect(water)
	var hit: Agent = null
	var hit_d := INF
	for a in agents:
		var c := _agent_center(a, water, zone)
		var d := c.distance_to(pos)
		if d < 13.0 * _agent_scale(a) and d < hit_d:
			hit = a
			hit_d = d
	if hit != null:
		var hc := _agent_center(hit, water, zone)
		var lv := "" if hit.visitor else "  Lv.%d" % hit.level
		name_tag = {"text": String(names.get(hit.kind, "?")) + lv, "agent": hit, "t": 2.2}
		for a in agents:
			var c := _agent_center(a, water, zone)
			if c.distance_to(pos) < 45.0 * ps and a.move != "floor":
				a.flee = 0.5 if a != hit else 0.7
				var away := c - pos
				a.vel = (away.normalized() if away.length() > 0.1 else Vector2.RIGHT) * a.speed * ps * 2.0
		if hit.move == "floor":
			hit.heart = 1.0
		queue_redraw()
		return
	# 3) 水面：投喂
	if water.has_point(pos) and pos.y < _sand_top(water):
		for i in range(3):
			if food.size() >= MAX_FOOD:
				food.pop_front()
			food.append({
				"pos": pos + Vector2(randf_range(-8.0, 8.0), randf_range(-3.0, 3.0)) * ps,
				"vy": randf_range(10.0, 16.0) * ps,
				"life": 9.0,
			})
		Audio.play_feed()

func _item_at(pos: Vector2) -> int:
	var water := _water_rect()
	var ordered := _placed_sorted()
	ordered.reverse()   # 前景先命中
	for e in ordered:
		if _item_rect(e, water).grow(4.0).has_point(pos):
			return int(e["uid"])
	return -1

func _edit_press(pos: Vector2) -> void:
	var uid := _item_at(pos)
	selected_uid = uid
	if uid >= 0:
		dragging = true
		drag_offset = _item_base(eco.find_placed(uid), _water_rect()) - pos
	_refresh_tools()
	queue_redraw()

func _edit_drag(pos: Vector2) -> void:
	var entry := eco.find_placed(selected_uid)
	if entry.is_empty():
		return
	var water := _water_rect()
	var base := pos + drag_offset
	var x := (base.x - water.position.x - ITEM_MARGIN) / maxf(water.size.x - ITEM_MARGIN * 2.0, 1.0)
	var d := float(entry["d"])
	if not TankArt.is_surface(String(entry["id"])):
		d = (base.y - _sand_top(water) - 3.0) / maxf(_sand_h(water) - 5.0, 1.0)
	eco.move(selected_uid, x, d)
	queue_redraw()

func _flip_selected() -> void:
	if selected_uid < 0:
		return
	eco.flip(selected_uid)
	layout_changed.emit()
	queue_redraw()

func _stow_selected() -> void:
	if selected_uid < 0:
		return
	eco.remove(selected_uid)
	selected_uid = -1
	_refresh_tools()
	layout_changed.emit()

func _place_from_inventory(id: String) -> void:
	# 新放进来的东西落在中间附近，依次错开，连放几件也不会叠成一摞
	var x: float = DROP_SPOTS[_drop_count % DROP_SPOTS.size()]
	_drop_count += 1
	var uid := eco.place(id, x, 0.65)
	if uid < 0:
		return
	selected_uid = uid
	_refresh_tools()
	layout_changed.emit()

func _refresh_tools() -> void:
	if tools_label == null:
		return
	var entry: Dictionary = eco.find_placed(selected_uid) if eco != null and selected_uid >= 0 else {}
	tools_label.text = String(eco.item(String(entry["id"])).get("name", "")) if not entry.is_empty() else "布置"
	flip_button.disabled = entry.is_empty()
	stow_button.disabled = entry.is_empty()

func _rebuild_strip(force: bool) -> void:
	if eco == null or strip_row == null:
		return
	var inv := eco.inventory()
	var sig := str(inv)
	if not force and sig == _strip_sig:
		return
	_strip_sig = sig
	for child in strip_row.get_children():
		child.queue_free()
	if inv.is_empty():
		var empty := Label.new()
		empty.text = "库存空了，去商店挑点东西"
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", UITheme.INK_ON_CHROME)
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		strip_row.add_child(empty)
		return
	for e in inv:
		var id := String(e["id"])
		var card := Button.new()
		card.custom_minimum_size = Vector2(54, 48)
		card.focus_mode = Control.FOCUS_NONE
		card.tooltip_text = "%s：点一下放进缸里" % String(eco.item(id).get("name", id))
		UITheme.style_ghost(card)
		card.pressed.connect(_place_from_inventory.bind(id))
		var icon := TankIcon.new().setup("item", id)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_bottom = -8
		card.add_child(icon)
		var count := Label.new()
		count.text = "×%d" % int(e["count"])
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count.add_theme_font_size_override("font_size", 11)
		count.add_theme_color_override("font_color", UITheme.INK_SOFT)
		count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 3)
		count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		count.grow_vertical = Control.GROW_DIRECTION_BEGIN
		card.add_child(count)
		strip_row.add_child(card)

# ---------- 绘制 ----------

func _draw() -> void:
	var water := _water_rect()
	_draw_tank(water)
	if eco != null:
		_draw_scene(water)
	_draw_food()
	if use_day_cycle and DayCycle.overlay.a > 0.0:
		_draw_night(water)
	if not edit_mode and not read_only:
		_draw_pearls(water)
	_draw_bubbles(water)
	var clean := float(eval.get("clean", 100.0))
	if clean < MURKY_CLEAN:
		var murk := MURK
		murk.a = (MURKY_CLEAN - clean) / MURKY_CLEAN * 0.3
		draw_rect(water, murk)
	if edit_mode:
		_draw_edit_overlay(water)
	elif show_hud:
		_draw_hud()
	_draw_name_tag(water)
	_draw_floats()

# 昼夜：只压暗水体（缸在室内，比池塘暗得少；布置时再减半，好看清摆件）。
# 珍珠、气泡画在这层之后，夜里反而更显眼；萤光水母在夜里亮起一圈光晕。
func _draw_night(water: Rect2) -> void:
	var shade := DayCycle.overlay
	shade.a *= 0.4 if edit_mode else 0.8
	draw_rect(water, shade)
	var night := DayCycle.night
	if night <= 0.05:
		return
	var zone := _swim_rect(water)
	for a in agents:
		if a.kind != "jellyfish":
			continue
		var c := _agent_center(a, water, zone)
		var r := 12.0 * _agent_scale(a)
		draw_circle(c, r * 1.6, Color(0.70, 0.95, 1.0, 0.07 * night))
		draw_circle(c, r, Color(0.70, 0.95, 1.0, 0.12 * night))

func _draw_tank(water: Rect2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), TANK_BG)
	draw_rect(water.grow(2.0), GLASS_RIM)
	var bands := 6
	for i in range(bands):
		var t := i / float(bands - 1)
		var y := water.position.y + water.size.y * (i / float(bands))
		draw_rect(Rect2(Vector2(water.position.x, y), Vector2(water.size.x, water.size.y / bands + 1.0)), WATER_TOP.lerp(WATER_BOTTOM, t))
	# 顶部光纹：横向缓移，画两份做无缝循环
	var drift := fmod(time * 0.08, 1.0)
	for i in range(3):
		var cx := fmod(drift * water.size.x + i * water.size.x / 3.0, water.size.x)
		TankArt.px(self, water.position.x + cx, water.position.y + 4.0, 26, 5, SHEEN)
		TankArt.px(self, water.position.x + cx - water.size.x, water.position.y + 4.0, 26, 5, SHEEN)
	draw_rect(Rect2(water.position, Vector2(6, water.size.y)), TANK_BG)
	draw_rect(Rect2(Vector2(water.end.x - 6, water.position.y), Vector2(6, water.size.y)), TANK_BG)
	# 缸底沙：后半略暗，给「前后」一点纵深
	var sh := _sand_h(water)
	var sy := _sand_top(water)
	draw_rect(Rect2(Vector2(water.position.x, sy), Vector2(water.size.x, sh)), SAND)
	draw_rect(Rect2(Vector2(water.position.x, sy), Vector2(water.size.x, sh * 0.35)), SAND_BACK)
	for i in range(14):
		var px := water.position.x + 10.0 + TankArt.hash01(i + 1) * (water.size.x - 20.0)
		TankArt.px(self, px, sy + 4.0 + (i % 4) * sh * 0.2, 4, 2, SAND_DARK)

func _placed_sorted() -> Array:
	if eco == null:
		return []
	var arr: Array = eco.placed().duplicate()
	arr.sort_custom(func(a, b): return _z_of(a) < _z_of(b))
	return arr

func _z_of(entry: Dictionary) -> float:
	return 2.0 if TankArt.is_surface(String(entry["id"])) else float(entry["d"])

func _draw_scene(water: Rect2) -> void:
	var zone := _swim_rect(water)
	var list: Array = []
	for e in eco.placed():
		list.append({"z": _z_of(e), "e": e})
	for a in agents:
		list.append({"z": a.depth if a.move != "floor" else 0.1 + a.depth, "a": a})
	list.sort_custom(func(p, q): return float(p["z"]) < float(q["z"]))
	var surface := water.position.y + 2.0
	for entry in list:
		if entry.has("e"):
			var e: Dictionary = entry["e"]
			var id := String(e["id"])
			var d := float(e["d"])
			var flip := bool(e.get("flip", false))
			if not edit_mode and _is_critter(id) and id != "moss_ball":
				flip = TankArt.critter_facing_left(id, int(e["uid"]), time)
			var tint := Color(WATER_BOTTOM.r, WATER_BOTTOM.g, WATER_BOTTOM.b, (1.0 - d) * 0.25)
			if TankArt.is_surface(id):
				tint.a = 0.0
			TankArt.draw_item(self, id, _item_base(e, water) + _item_offset(e), _item_scale(e), time + int(e["uid"]) * 0.7, flip, tint, 1.0, surface)
		else:
			var a: Agent = entry["a"]
			var c := _agent_center(a, water, zone)
			var s := _agent_scale(a)
			var tint := Color(WATER_BOTTOM.r, WATER_BOTTOM.g, WATER_BOTTOM.b, (1.0 - a.depth) * 0.2)
			var alpha := 0.35 if edit_mode else 1.0
			if a.visitor:
				TankArt.draw_visitor(self, a.kind, c, s, a.left, time + a.seed, alpha, tint)
			else:
				TankArt.draw_fish(self, a.kind, c, s, a.left, time + a.seed * 0.37, alpha, a.level, tint)
			if a.heart > 0.0:
				TankArt.draw_heart(self, c + Vector2(0, -9.0 * s - (1.4 - a.heart) * 8.0), _ps(), clampf(a.heart, 0.0, 1.0))

func _draw_food() -> void:
	var ps := _ps()
	for f in food:
		TankArt.draw_food(self, f["pos"], ps)

func _draw_pearls(water: Rect2) -> void:
	for p in pearls:
		TankArt.draw_pearl(self, _pearl_pos(p, water), _ps() * 1.3, time + int(p["seed"]))

func _draw_bubbles(water: Rect2) -> void:
	var cols := [0.22, 0.55, 0.80]
	var usable := _sand_top(water) - water.position.y - 8.0
	for c_i in range(cols.size()):
		var bx: float = water.position.x + water.size.x * float(cols[c_i])
		for b in range(3):
			var prog := fmod(time / 48.0 + b / 3.0 + c_i * 0.13, 1.0)
			var by := _sand_top(water) - prog * usable
			var r := 2.0 + b
			TankArt.px(self, bx, by, r, r, BUBBLE)

func _draw_star(pos: Vector2, on: bool) -> void:
	TankArt.draw_star(self, pos, 1.0, STAR_ON if on else STAR_OFF)

func _draw_hud() -> void:
	if eval.is_empty():
		return
	var x := 18.0
	var y := 62.0 + _top_offset()
	var stars := int(eval.get("stars", 0))
	for i in range(5):
		_draw_star(Vector2(x + i * 11.0, y), i < stars)
	# 星级下方一条细进度：距离下一星
	var prev := float(eval.get("prev_star_score", 0))
	var next := float(eval.get("next_star_score", 0))
	var prog := 1.0 if next <= prev else clampf((float(eval.get("score", 0)) - prev) / (next - prev), 0.0, 1.0)
	draw_rect(Rect2(Vector2(x, y + 10.0), Vector2(53, 2)), BAR_BG)
	draw_rect(Rect2(Vector2(x, y + 10.0), Vector2(53.0 * prog, 2)), STAR_ON)
	var font := get_theme_default_font()
	var bx := x + 66.0
	for pair in [["氧", float(eval.get("oxygen", 100.0))], ["净", float(eval.get("clean", 100.0))]]:
		var v: float = pair[1]
		draw_string(font, Vector2(bx, y + 9.0), String(pair[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK_SOFT)
		var col := Color(0.55, 0.85, 0.60) if v >= 80.0 else (Color(0.95, 0.80, 0.40) if v >= 50.0 else Color(0.95, 0.55, 0.45))
		draw_rect(Rect2(Vector2(bx + 15.0, y + 3.0), Vector2(30, 4)), BAR_BG)
		draw_rect(Rect2(Vector2(bx + 15.0, y + 3.0), Vector2(30.0 * v / 100.0, 4)), col)
		bx += 54.0

func _draw_edit_overlay(water: Rect2) -> void:
	# 可摆放的沙地带：淡淡提亮，告诉玩家「上下拖 = 前后」
	var sy := _sand_top(water)
	draw_rect(Rect2(Vector2(water.position.x, sy), Vector2(water.size.x, _sand_h(water))), Color(1, 1, 1, 0.10))
	for i in range(int(water.size.x / 12.0)):
		draw_rect(Rect2(Vector2(water.position.x + i * 12.0 + 4.0, sy + 1.0), Vector2(4, 1)), Color(1, 1, 1, 0.35))
	for e in eco.placed():
		var uid := int(e["uid"])
		if uid == selected_uid:
			draw_rect(_item_rect(e, water).grow(3.0), SELECT, false, 1.0)
		elif uid == hover_uid:
			draw_rect(_item_rect(e, water).grow(3.0), Color(1, 1, 1, 0.45), false, 1.0)
	var font := get_theme_default_font()
	var hint := "拖动摆放 · 上下拖改前后 · 点空白处取消选择" if water.size.x > 330.0 else "拖动摆放 · 上下拖改前后"
	var hint_y := tools_panel.get_rect().end.y + 18.0 if tools_panel else water.position.y + 60.0
	draw_string(font, Vector2(water.position.x + 8.0, hint_y), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))

func _draw_name_tag(water: Rect2) -> void:
	if name_tag.is_empty():
		return
	var a: Agent = name_tag["agent"]
	if not agents.has(a):
		return
	var c := _agent_center(a, water, _swim_rect(water))
	var font := get_theme_default_font()
	var text := String(name_tag["text"])
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var box := Rect2(Vector2(c.x - tw * 0.5 - 6.0, c.y - 16.0 * _agent_scale(a) - 18.0), Vector2(tw + 12.0, 18.0))
	box.position.x = clampf(box.position.x, water.position.x, water.end.x - box.size.x)
	box.position.y = maxf(box.position.y, water.position.y)
	var alpha := clampf(float(name_tag["t"]) / 0.4, 0.0, 1.0)
	draw_rect(box, Color(0.08, 0.11, 0.13, 0.78 * alpha))
	draw_string(font, box.position + Vector2(6.0, 13.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, alpha))

func _draw_floats() -> void:
	var font := get_theme_default_font()
	for f in floats:
		var col: Color = f["color"]
		col.a = clampf(float(f["t"]) / 0.6, 0.0, 1.0)
		var text := String(f["text"])
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(font, (f["pos"] as Vector2) - Vector2(tw * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
