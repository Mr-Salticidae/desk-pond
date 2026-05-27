extends HBoxContainer
class_name TaskItem

signal toggled(task_id: String, done: bool)
signal delete_requested(task_id: String)

var task_id := ""
var checkbox: CheckBox
var title_label: Label
var is_done := false

func setup(task: Dictionary) -> void:
	custom_minimum_size = Vector2(0, 34)
	add_theme_constant_override("separation", 8)
	alignment = BoxContainer.ALIGNMENT_CENTER
	task_id = String(task.get("id", ""))
	is_done = bool(task.get("done", false))
	checkbox = CheckBox.new()
	checkbox.button_pressed = is_done
	checkbox.tooltip_text = "完成任务"
	checkbox.toggled.connect(func(done: bool): toggled.emit(task_id, done))
	add_child(checkbox)

	title_label = Label.new()
	title_label.text = String(task.get("title", ""))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color(0.12, 0.17, 0.15))
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if is_done:
		title_label.add_theme_color_override("font_color", Color(0.42, 0.50, 0.40))
	add_child(title_label)

	var delete_button := Button.new()
	delete_button.text = "×"
	delete_button.tooltip_text = "删除"
	delete_button.custom_minimum_size = Vector2(30, 26)
	delete_button.pressed.connect(func(): delete_requested.emit(task_id))
	add_child(delete_button)

func _draw() -> void:
	var fill := Color(0.95, 0.94, 0.82) if not is_done else Color(0.78, 0.87, 0.70)
	var border := Color(0.50, 0.56, 0.43) if not is_done else Color(0.35, 0.53, 0.32)
	draw_rect(Rect2(Vector2(0, 1), size - Vector2(0, 2)), fill)
	draw_rect(Rect2(Vector2(0, 1), size - Vector2(0, 2)), border, false, 1.0)
