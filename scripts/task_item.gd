extends HBoxContainer
class_name TaskItem

signal toggled(task_id: String, done: bool)
signal delete_requested(task_id: String)

var task_id := ""
var checkbox: CheckBox
var title_label: Label

func setup(task: Dictionary) -> void:
	task_id = String(task.get("id", ""))
	checkbox = CheckBox.new()
	checkbox.button_pressed = bool(task.get("done", false))
	checkbox.toggled.connect(func(done: bool): toggled.emit(task_id, done))
	add_child(checkbox)

	title_label = Label.new()
	title_label.text = String(task.get("title", ""))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	add_child(title_label)

	var delete_button := Button.new()
	delete_button.text = "删"
	delete_button.tooltip_text = "删除"
	delete_button.pressed.connect(func(): delete_requested.emit(task_id))
	add_child(delete_button)
