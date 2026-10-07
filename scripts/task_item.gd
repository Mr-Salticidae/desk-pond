extends HBoxContainer
class_name TaskItem

signal toggled(task_id: String, done: bool)
signal edit_requested(task_id: String, current_title: String)
signal delete_requested(task_id: String)

var task_id := ""
var checkbox: CheckBox
var title_label: Label
var task_title := ""
var is_done := false

func setup(task: Dictionary) -> void:
	custom_minimum_size = Vector2(0, 34)
	add_theme_constant_override("separation", 8)
	alignment = BoxContainer.ALIGNMENT_CENTER
	task_id = String(task.get("id", ""))
	task_title = String(task.get("title", ""))
	is_done = bool(task.get("done", false))
	checkbox = CheckBox.new()
	checkbox.button_pressed = is_done
	checkbox.tooltip_text = "完成任务"
	checkbox.toggled.connect(func(done: bool): toggled.emit(task_id, done))
	add_child(checkbox)

	title_label = Label.new()
	title_label.text = task_title
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", UITheme.INK if not is_done else UITheme.INK_FAINT)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(title_label)

	# 行内小操作：平时只留淡淡的文字，悬停才浮出底色，不再一行两个带框的小方块
	var edit_button := Button.new()
	edit_button.text = "改"
	edit_button.tooltip_text = "编辑任务"
	edit_button.custom_minimum_size = Vector2(30, 26)
	edit_button.focus_mode = Control.FOCUS_NONE
	UITheme.style_row_action(edit_button)
	edit_button.pressed.connect(func(): edit_requested.emit(task_id, task_title))
	add_child(edit_button)

	var delete_button := Button.new()
	delete_button.text = "×"
	delete_button.tooltip_text = "删除"
	delete_button.custom_minimum_size = Vector2(30, 26)
	delete_button.focus_mode = Control.FOCUS_NONE
	UITheme.style_row_action(delete_button, true)
	delete_button.pressed.connect(func(): delete_requested.emit(task_id))
	add_child(delete_button)

# 每一行是一块圆角浅底（和输入框、按钮同一层底色），不描边；完成的行更淡
func _draw() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = UITheme.FILL if not is_done else UITheme.FILL_DISABLED
	box.set_corner_radius_all(UITheme.CONTROL_RADIUS)
	box.draw(get_canvas_item(), Rect2(Vector2(0, 1), size - Vector2(0, 2)))
	if is_done:
		# 完成的任务画一道淡淡的删除线
		var mid := size.y * 0.5
		draw_line(Vector2(36, mid), Vector2(size.x - 70, mid), UITheme.INK_FAINT, 1.0)
