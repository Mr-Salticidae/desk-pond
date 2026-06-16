extends UICard
class_name RewardPopup

var reward_label: Label
var rarity_label: Label
var description_label: Label
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
	configure("钓获成功", Vector2i(360, 300))
	exclusive = true
	_build_content()

func show_reward(fish: Dictionary) -> void:
	if reward_label == null:
		_build_content()
	reward_label.text = "你钓到了「%s」" % String(fish.get("name", "神秘小鱼"))
	rarity_label.text = _rarity_name(String(fish.get("rarity", "common")))
	rarity_label.add_theme_color_override("font_color", _rarity_color(String(fish.get("rarity", "common"))))
	description_label.text = String(fish.get("description", "这条鱼还没有写进图鉴。"))
	flavor_label.text = flavor_texts.pick_random()
	popup_centered()

func _build_content() -> void:
	if reward_label != null:
		return
	body.add_theme_constant_override("separation", 12)
	body.alignment = BoxContainer.ALIGNMENT_CENTER

	reward_label = _centered_label(18, UITheme.INK)
	body.add_child(reward_label)

	rarity_label = _centered_label(14, UITheme.INK_SOFT)
	body.add_child(rarity_label)

	description_label = _centered_label(14, UITheme.INK_SOFT)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.custom_minimum_size = Vector2(300, 0)
	body.add_child(description_label)

	flavor_label = _centered_label(13, UITheme.INK_FAINT)
	flavor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor_label.custom_minimum_size = Vector2(290, 0)
	body.add_child(flavor_label)

	confirm_button = Button.new()
	confirm_button.text = "收进图鉴"
	confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UITheme.style_primary(confirm_button)
	confirm_button.pressed.connect(hide)
	body.add_child(confirm_button)

func _centered_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _rarity_name(rarity: String) -> String:
	match rarity:
		"uncommon":
			return "少见钓获"
		"rare":
			return "稀有钓获"
		_:
			return "常见钓获"

func _rarity_color(rarity: String) -> Color:
	match rarity:
		"uncommon":
			return Color(0.31, 0.52, 0.33)
		"rare":
			return Color(0.55, 0.36, 0.62)
		_:
			return UITheme.INK_SOFT
