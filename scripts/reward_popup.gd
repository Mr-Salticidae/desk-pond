extends Window
class_name RewardPopup

var title_label: Label
var reward_label: Label
var flavor_label: Label
var confirm_button: Button

var flavor_texts := [
	"今天的池塘又热闹了一点。",
	"你没有浪费今天，你只是慢慢把它种下来了。",
	"工作在继续，水面也在继续。",
	"这不是摸鱼，这是生态建设。",
	"树长高了一点，你也是。"
]

func _ready() -> void:
	close_requested.connect(hide)
	title = "专注完成"
	size = Vector2i(360, 210)
	_build_ui()

func show_reward(fish: Dictionary) -> void:
	if title_label == null:
		_build_ui()
	title_label.text = "钓获成功"
	reward_label.text = "你钓到了「%s」。" % String(fish.get("name", "神秘小鱼"))
	flavor_label.text = flavor_texts.pick_random()
	popup_centered()

func _build_ui() -> void:
	if title_label != null:
		return
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(root)

	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color(0.19, 0.25, 0.24))
	root.add_child(title_label)

	reward_label = Label.new()
	reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_label.add_theme_font_size_override("font_size", 16)
	reward_label.add_theme_color_override("font_color", Color(0.08, 0.36, 0.43))
	root.add_child(reward_label)

	flavor_label = Label.new()
	flavor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flavor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor_label.custom_minimum_size = Vector2(280, 0)
	flavor_label.add_theme_color_override("font_color", Color(0.33, 0.38, 0.34))
	root.add_child(flavor_label)

	confirm_button = Button.new()
	confirm_button.text = "收进图鉴"
	confirm_button.pressed.connect(hide)
	root.add_child(confirm_button)

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.94, 0.92, 0.78)
	style.border_color = Color(0.27, 0.35, 0.31)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style
