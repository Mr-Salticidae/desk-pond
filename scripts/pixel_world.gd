extends Control
class_name PixelWorld

var status_label: Label
var tree_label: Label
var pond_label: Label
var fishing_active := false

func _ready() -> void:
	_build_ui()

func set_fishing_active(active: bool) -> void:
	fishing_active = active
	if status_label:
		status_label.text = "小人正在钓鱼" if active else "小人在池边待机"

func update_tree_visual(stage: int, growth_points: int = 0) -> void:
	if tree_label == null:
		return
	var names := ["种子", "小树苗", "小树", "大树"]
	tree_label.text = "树：%s\n成长值 %d" % [names[clamp(stage, 0, 3)], growth_points]

func play_focus_feedback() -> void:
	if pond_label:
		pond_label.text = "池塘泛起了涟漪"
		var timer := get_tree().create_timer(1.2)
		timer.timeout.connect(func(): pond_label.text = "池塘")

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.72, 0.88, 0.83)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "Desk Pond"
	title.position = Vector2(16, 12)
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)

	status_label = Label.new()
	status_label.text = "小人在池边待机"
	status_label.position = Vector2(64, 88)
	status_label.add_theme_font_size_override("font_size", 18)
	add_child(status_label)

	pond_label = Label.new()
	pond_label.text = "池塘"
	pond_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pond_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pond_label.position = Vector2(270, 78)
	pond_label.size = Vector2(120, 64)
	pond_label.add_theme_color_override("font_color", Color(0.05, 0.33, 0.48))
	add_child(pond_label)

	var pond_bg := ColorRect.new()
	pond_bg.color = Color(0.34, 0.66, 0.78)
	pond_bg.position = Vector2(256, 104)
	pond_bg.size = Vector2(150, 42)
	add_child(pond_bg)
	move_child(pond_bg, 1)

	tree_label = Label.new()
	tree_label.position = Vector2(500, 78)
	tree_label.add_theme_font_size_override("font_size", 16)
	add_child(tree_label)
	update_tree_visual(0, 0)
