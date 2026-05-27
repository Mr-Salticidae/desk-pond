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
	_build_ui()

func show_reward(fish: Dictionary) -> void:
	if title_label == null:
		_build_ui()
	title_label.text = "专注完成"
	reward_label.text = "你钓到了一条「%s」。" % String(fish.get("name", "神秘小鱼"))
	flavor_label.text = flavor_texts.pick_random()
	popup_centered()

func _build_ui() -> void:
	if title_label != null:
		return
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(root)

	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 22)
	root.add_child(title_label)

	reward_label = Label.new()
	reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(reward_label)

	flavor_label = Label.new()
	flavor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flavor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(flavor_label)

	confirm_button = Button.new()
	confirm_button.text = "知道了"
	confirm_button.pressed.connect(hide)
	root.add_child(confirm_button)
