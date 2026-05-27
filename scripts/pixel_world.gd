extends Control
class_name PixelWorld

signal cast_requested

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
	fishing_active = active
	if status_label:
		status_label.text = "已甩杆，专注中" if active else "点击池塘甩杆"
	queue_redraw()

func update_tree_visual(stage: int, growth_points: int = 0) -> void:
	tree_stage = int(clamp(stage, 0, 3))
	self.growth_points = growth_points
	if tree_label == null:
		return
	var names := ["种子", "小树苗", "小树", "大树"]
	tree_label.text = "%s  Lv.%d" % [names[tree_stage], growth_points]
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
	water_frame = fmod(water_frame + 1.0, 1000.0)
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
	_draw_cast_hint(w, h)

func _draw_clouds(w: float) -> void:
	var drift := fmod(water_frame * 2.0, 48.0)
	_pixel_rect(Vector2(54 + drift, 38), Vector2(46, 10), Color(0.92, 0.95, 0.91))
	_pixel_rect(Vector2(82 + drift, 28), Vector2(34, 12), Color(0.92, 0.95, 0.91))
	_pixel_rect(Vector2(w - 148 - drift, 42), Vector2(60, 10), Color(0.91, 0.94, 0.88))

func _draw_pond(w: float, h: float) -> void:
	var pond := _get_pond_rect()
	draw_rect(Rect2(pond.position + Vector2(12, -8), pond.size - Vector2(24, -16)), Color(0.19, 0.47, 0.58))
	draw_rect(Rect2(pond.position + Vector2(0, 10), pond.size), Color(0.23, 0.58, 0.70))
	draw_rect(Rect2(pond.position + Vector2(18, 24), pond.size - Vector2(36, 42)), Color(0.37, 0.74, 0.80))
	if cast_hovered and not fishing_active:
		draw_rect(Rect2(pond.position + Vector2(18, 18), pond.size - Vector2(36, 36)), Color(1.0, 0.96, 0.62, 0.16))
	for i in range(4):
		var x := pond.position.x + 32 + i * 58 + fmod(water_frame * 5.0, 28.0)
		var y := pond.position.y + 38 + (i % 2) * 18
		_pixel_rect(Vector2(x, y), Vector2(32, 4), Color(0.78, 0.93, 0.91, 0.78))
	for i in range(3):
		var fish_x := pond.position.x + 46 + i * 74 + sin((water_frame + i * 7.0) * 0.2) * 12.0
		var fish_y := pond.position.y + 62 + i % 2 * 26
		_pixel_rect(Vector2(fish_x, fish_y), Vector2(14, 5), Color(0.09, 0.34, 0.43, 0.42))
	if reward_flash > 0.0:
		var flash_color := Color(1.0, 0.95, 0.46, reward_flash)
		_pixel_rect(pond.position + Vector2(pond.size.x * 0.46, 12), Vector2(34, 6), flash_color)
		_pixel_rect(pond.position + Vector2(pond.size.x * 0.51, 0), Vector2(6, 30), flash_color)

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
		var rod_end := Vector2(w * 0.45, h * 0.48 + sin(water_frame * 0.35) * 5.0)
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

func _draw_cast_hint(w: float, h: float) -> void:
	if fishing_active:
		return
	var hint_pos := Vector2(w * 0.38, h * 0.76)
	var hint_color := Color(0.95, 0.79, 0.32) if cast_hovered else Color(0.18, 0.32, 0.31)
	_pixel_rect(hint_pos, Vector2(76, 6), hint_color)
	_pixel_rect(hint_pos + Vector2(70, -6), Vector2(6, 18), hint_color)

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
