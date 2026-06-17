extends Window
class_name UICard

# 统一的无边框弹出卡片：纸面卡身 + 深色标题栏（可拖动 + 关闭）。
# 所有弹窗共用这一外观，内容放进 body 即可。

var body: VBoxContainer
var _title_label: Label
var _dragging := false

func configure(card_title: String, card_size: Vector2i) -> void:
	title = card_title
	size = card_size
	borderless = true
	unresizable = true
	visible = false
	transparent_bg = true
	close_requested.connect(hide)
	_build()

func set_card_title(text: String) -> void:
	title = text
	if _title_label:
		_title_label.text = text

func _build() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", UITheme.card_style())
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)

	# 标题栏：可拖动 + 关闭
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", UITheme.header_style())
	header.gui_input.connect(_on_header_input)
	header.mouse_default_cursor_shape = Control.CURSOR_MOVE
	col.add_child(header)

	var header_row := HBoxContainer.new()
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_theme_constant_override("separation", 8)
	header.add_child(header_row)

	_title_label = Label.new()
	_title_label.text = title
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", 15)
	_title_label.add_theme_color_override("font_color", UITheme.INK_ON_CHROME)
	header_row.add_child(_title_label)

	var close_button := Button.new()
	close_button.text = "×"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.tooltip_text = "关闭"
	UITheme.style_chrome(close_button, true)
	close_button.pressed.connect(hide)
	header_row.add_child(close_button)

	# 内容区
	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 16)
	col.add_child(margin)

	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(body)

func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		position = _clamp_to_screen(position + Vector2i(event.relative))

# 约束拖动位置，避免弹窗被拖丢后再也找不回来（exclusive 弹窗拖丢会阻塞主窗口）。
# 弹窗默认是嵌入主窗口的子窗口，position 相对父视口——必须约束在父窗口可见区内，
# 而不是屏幕坐标（否则副屏在左/上时合并矩形起点为负，反而能把弹窗拖出主窗口）。
func _clamp_to_screen(pos: Vector2i) -> Vector2i:
	if is_embedded():
		var parent := get_parent()
		if parent != null:
			var limit := parent.get_viewport().get_visible_rect().size
			pos.x = clampi(pos.x, 0, maxi(0, int(limit.x) - size.x))
			pos.y = clampi(pos.y, 0, maxi(0, int(limit.y) - size.y))
			return pos
	# 独立原生窗口：约束在整个虚拟桌面（所有屏幕合并）范围内，可跨屏不卡边。
	var area := _virtual_usable_rect()
	var max_x := area.position.x + area.size.x - size.x
	var max_y := area.position.y + area.size.y - size.y
	pos.x = clampi(pos.x, area.position.x, maxi(area.position.x, max_x))
	pos.y = clampi(pos.y, area.position.y, maxi(area.position.y, max_y))
	return pos

func _virtual_usable_rect() -> Rect2i:
	var rect := DisplayServer.screen_get_usable_rect(0)
	for i in range(1, DisplayServer.get_screen_count()):
		rect = rect.merge(DisplayServer.screen_get_usable_rect(i))
	return rect
