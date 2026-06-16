extends Control
class_name PixelWorld

signal cast_requested

# 一次完整动画循环的帧数（anim_timer 每 0.12s 一帧），所有周期动画都以它为基准做到无缝循环。
const LOOP := 360.0
const CLOUD_COLOR := Color(0.93, 0.95, 0.92, 0.95)
const POND_RIM := Color(0.17, 0.42, 0.52)
const POND_BODY := Color(0.24, 0.58, 0.70)
const POND_SHEEN := Color(0.36, 0.72, 0.80)
const RIPPLE_COLOR := Color(0.82, 0.94, 0.93, 0.70)
const FISH_SHADOW := Color(0.10, 0.34, 0.43, 0.40)
const HOVER_TINT := Color(1.0, 0.96, 0.62, 0.16)

var status_label: Label
var tree_label: Label
var pond_label: Label
var fishing_active := false
var cast_hovered := false
var mouse_over_pond := false
var tree_stage := 0
var growth_points := 0
var water_frame := 0.0
var reward_flash := 0.0
var anim_timer: Timer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "点击池塘甩杆"
	mouse_exited.connect(func():
		cast_hovered = false
		mouse_over_pond = false
		queue_redraw()
	)
	_build_ui()
	anim_timer = Timer.new()
	anim_timer.wait_time = 0.12
	anim_timer.timeout.connect(_on_anim_tick)
	add_child(anim_timer)
	anim_timer.start()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_labels()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion_event := event as InputEventMouseMotion
		_update_pond_hover(motion_event.position)
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		_update_pond_hover(mouse_event.position)
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed and mouse_over_pond:
			reward_flash = 0.35
			cast_requested.emit()
			accept_event()
			queue_redraw()

func set_fishing_active(active: bool) -> void:
	set_activity_state("focusing" if active else "idle")

func set_activity_state(timer_state: String) -> void:
	fishing_active = timer_state == "focusing"
	if status_label:
		match timer_state:
			"focusing":
				status_label.text = "已甩杆，专注中"
			"break":
				status_label.text = "收竿休息中"
			"paused":
				status_label.text = "时间暂停中"
			_:
				status_label.text = "点击池塘甩杆"
	queue_redraw()

func update_tree_visual(stage: int, forest_count: int = 0) -> void:
	tree_stage = int(clamp(stage, 0, 3))
	self.growth_points = forest_count
	if tree_label == null:
		return
	if forest_count > 0:
		tree_label.text = "林 · %d 棵" % forest_count
	else:
		var names := ["种子", "小树苗", "小树", "大树"]
		tree_label.text = names[tree_stage]
	queue_redraw()

func play_focus_feedback() -> void:
	if pond_label:
		reward_flash = 1.0
		pond_label.text = "水面闪光"
		var timer := get_tree().create_timer(1.2)
		timer.timeout.connect(func(): pond_label.text = "Desk Pond")
	queue_redraw()

func _build_ui() -> void:
	status_label = Label.new()
	status_label.text = "点击池塘甩杆"
	status_label.position = Vector2(18, 16)
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color(0.15, 0.20, 0.24))
	add_child(status_label)

	pond_label = Label.new()
	pond_label.text = "Desk Pond"
	pond_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pond_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pond_label.position = Vector2(236, 18)
	pond_label.size = Vector2(168, 24)
	pond_label.add_theme_font_size_override("font_size", 18)
	pond_label.add_theme_color_override("font_color", Color(0.12, 0.26, 0.32))
	add_child(pond_label)

	tree_label = Label.new()
	tree_label.position = Vector2(500, 18)
	tree_label.add_theme_font_size_override("font_size", 14)
	tree_label.add_theme_color_override("font_color", Color(0.17, 0.29, 0.20))
	add_child(tree_label)
	update_tree_visual(0, 0)
	_layout_labels()

func _layout_labels() -> void:
	if status_label:
		status_label.position = Vector2(18, 16)
	if pond_label:
		pond_label.position = Vector2(max(size.x * 0.5 - 84.0, 138.0), 18)
	if tree_label:
		tree_label.position = Vector2(max(size.x - 142.0, 338.0), 18)

func _on_anim_tick() -> void:
	water_frame = fmod(water_frame + 1.0, LOOP)
	if reward_flash > 0.0:
		reward_flash = max(reward_flash - 0.1, 0.0)
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.78, 0.89, 0.86))
	draw_rect(Rect2(Vector2(0, h * 0.62), Vector2(w, h * 0.38)), Color(0.42, 0.66, 0.43))
	draw_rect(Rect2(Vector2(0, h * 0.72), Vector2(w, h * 0.28)), Color(0.33, 0.55, 0.36))
	_draw_clouds(w)
	_draw_pond(w, h)
	_draw_desk(w, h)
	_draw_fisher(w, h)
	_draw_tree(w, h)
	_draw_grass(w, h)

func _draw_clouds(w: float) -> void:
	# 云层向右匀速漂移，按 span 取模并画两份（相隔一个 span），
	# 当一朵从右侧滑出时左侧无缝接上，循环不跳变。
	var span := w + 140.0
	var shift := fmod(water_frame / LOOP * span, span)
	var clouds := [
		[Vector2(70.0, 36.0), Vector2(46.0, 10.0)],
		[Vector2(150.0, 26.0), Vector2(34.0, 12.0)],
		[Vector2(360.0, 44.0), Vector2(58.0, 10.0)],
		[Vector2(520.0, 30.0), Vector2(40.0, 10.0)],
	]
	for c in clouds:
		var pos: Vector2 = c[0]
		var csize: Vector2 = c[1]
		var x := fmod(pos.x + shift, span)
		_pixel_rect(Vector2(x, pos.y), csize, CLOUD_COLOR)
		_pixel_rect(Vector2(x - span, pos.y), csize, CLOUD_COLOR)

func _draw_pond(w: float, h: float) -> void:
	var pond := _get_pond_rect()
	var phase := water_frame / LOOP * TAU
	# 所有水体图层逐层向内收，全部内嵌在 pond 矩形内，避免任何一层突出造成“溢出”。
	draw_rect(pond, POND_RIM)
	var water := pond.grow(-6.0)
	draw_rect(water, POND_BODY)
	draw_rect(Rect2(water.position, Vector2(water.size.x, water.size.y * 0.40)), POND_SHEEN)
	if cast_hovered and not fishing_active:
		draw_rect(water.grow(-4.0), HOVER_TINT)
	# 水面波光：原地用 sin 轻轻摆动，无缝循环。
	var lane := water.size.x - 52.0
	for i in range(4):
		var rx := water.position.x + 18.0 + lane * (i / 3.0) + sin(phase * 2.0 + i * 1.2) * 4.0
		var ry := water.position.y + water.size.y * 0.34 + (i % 2) * 14.0
		_pixel_rect(Vector2(rx, ry), Vector2(24, 4), RIPPLE_COLOR)
	# 鱼影：以水体中心为轴用 sin 往返游动，振幅限制在水体内。
	for i in range(3):
		var fx := water.position.x + water.size.x * 0.5 + sin(phase + i * 2.1) * (water.size.x * 0.30)
		var fy := water.position.y + water.size.y * (0.46 + 0.16 * i)
		_pixel_rect(Vector2(fx - 7.0, fy), Vector2(14, 5), FISH_SHADOW)
	if reward_flash > 0.0:
		var flash_color := Color(1.0, 0.95, 0.46, reward_flash)
		_pixel_rect(water.position + Vector2(water.size.x * 0.46, water.size.y * 0.16), Vector2(30, 6), flash_color)
		_pixel_rect(water.position + Vector2(water.size.x * 0.50, water.size.y * 0.04), Vector2(6, 26), flash_color)

func _draw_desk(w: float, h: float) -> void:
	var base := Vector2(w * 0.12, h * 0.60)
	_pixel_rect(base, Vector2(108, 14), Color(0.48, 0.31, 0.21))
	_pixel_rect(base + Vector2(8, 14), Vector2(10, 42), Color(0.33, 0.22, 0.16))
	_pixel_rect(base + Vector2(88, 14), Vector2(10, 42), Color(0.33, 0.22, 0.16))
	_pixel_rect(base + Vector2(26, -24), Vector2(42, 24), Color(0.74, 0.82, 0.78))
	_pixel_rect(base + Vector2(30, -20), Vector2(34, 14), Color(0.25, 0.34, 0.37))

func _draw_fisher(w: float, h: float) -> void:
	var p := Vector2(w * 0.24, h * 0.56)
	_pixel_rect(p + Vector2(0, -30), Vector2(18, 18), Color(0.98, 0.76, 0.54))
	_pixel_rect(p + Vector2(-5, -36), Vector2(28, 8), Color(0.20, 0.28, 0.30))
	_pixel_rect(p + Vector2(-4, -12), Vector2(28, 30), Color(0.84, 0.36, 0.27))
	_pixel_rect(p + Vector2(0, 18), Vector2(8, 20), Color(0.16, 0.25, 0.31))
	_pixel_rect(p + Vector2(18, 18), Vector2(8, 20), Color(0.16, 0.25, 0.31))
	if fishing_active:
		var rod_end := Vector2(w * 0.45, h * 0.48 + sin(water_frame / LOOP * TAU * 4.0) * 5.0)
		draw_line(p + Vector2(24, -12), rod_end, Color(0.22, 0.17, 0.12), 3.0)
		draw_line(rod_end, rod_end + Vector2(0, 38), Color(0.12, 0.18, 0.19, 0.55), 1.0)
	else:
		draw_line(p + Vector2(24, -12), p + Vector2(78, -32), Color(0.22, 0.17, 0.12), 3.0)

func _draw_tree(w: float, h: float) -> void:
	var base := Vector2(w * 0.82, h * 0.66)
	if tree_stage == 0:
		_pixel_rect(base + Vector2(0, 8), Vector2(24, 8), Color(0.40, 0.24, 0.14))
		_pixel_rect(base + Vector2(8, 0), Vector2(8, 8), Color(0.43, 0.64, 0.28))
		return
	var trunk_h := 28 + tree_stage * 12
	_pixel_rect(base + Vector2(6, -trunk_h), Vector2(14, trunk_h + 14), Color(0.44, 0.28, 0.16))
	var crown := 26 + tree_stage * 12
	var crown_pos := base + Vector2(13 - crown * 0.5, -trunk_h - crown * 0.70)
	_pixel_rect(crown_pos + Vector2(8, 0), Vector2(crown, crown * 0.55), Color(0.25, 0.55, 0.30))
	_pixel_rect(crown_pos, Vector2(crown * 0.72, crown * 0.52), Color(0.34, 0.68, 0.36))
	_pixel_rect(crown_pos + Vector2(crown * 0.42, crown * 0.35), Vector2(crown * 0.70, crown * 0.46), Color(0.20, 0.47, 0.28))

func _draw_grass(w: float, h: float) -> void:
	for i in range(18):
		var x := fmod(i * 43.0 + 19.0, w)
		var y := h * 0.77 + (i % 4) * 8
		_pixel_rect(Vector2(x, y), Vector2(6, 18), Color(0.24, 0.48, 0.28, 0.75))
		_pixel_rect(Vector2(x + 7, y + 6), Vector2(5, 12), Color(0.55, 0.68, 0.32, 0.75))

func _update_pond_hover(local_position: Vector2) -> void:
	var is_over := _get_pond_click_rect().has_point(local_position)
	if is_over == mouse_over_pond:
		return
	mouse_over_pond = is_over
	cast_hovered = is_over
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if is_over else Control.CURSOR_ARROW
	tooltip_text = "点击池塘甩杆" if is_over else ""
	queue_redraw()

func _get_pond_rect() -> Rect2:
	return Rect2(Vector2(size.x * 0.30, size.y * 0.40), Vector2(size.x * 0.40, size.y * 0.34))

func _get_pond_click_rect() -> Rect2:
	var pond := _get_pond_rect()
	return Rect2(pond.position + Vector2(0, -8), pond.size + Vector2(0, 18))

func _pixel_rect(pos: Vector2, rect_size: Vector2, color: Color) -> void:
	draw_rect(Rect2(pos.round(), rect_size.round()), color)
