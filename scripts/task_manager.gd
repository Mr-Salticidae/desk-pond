extends PanelContainer
class_name TaskManager

signal task_added(task: Dictionary)
signal task_completed(task: Dictionary)
signal task_deleted(task_id: String)
signal tasks_changed(tasks: Array)

var save_manager: SaveManager
var tasks: Array = []
var task_input: LineEdit
var task_list: VBoxContainer
var progress_label: Label
var feedback_label: Label
var tasks_completed_today := 0

func _ready() -> void:
	_build_ui()

func setup(initial_tasks: Array, completed_count: int, manager: SaveManager) -> void:
	save_manager = manager
	tasks = initial_tasks.duplicate(true)
	tasks_completed_today = completed_count
	if task_list == null:
		_build_ui()
	_render_tasks()

func get_tasks() -> Array:
	return tasks.duplicate(true)

func get_tasks_completed_today() -> int:
	return tasks_completed_today

func add_task(title: String) -> void:
	var clean_title := title.strip_edges()
	if clean_title == "":
		return
	var now := save_manager.current_datetime() if save_manager else ""
	var task := {
		"id": "task_%d" % Time.get_ticks_msec(),
		"title": clean_title,
		"done": false,
		"created_at": now,
		"completed_at": null
	}
	tasks.append(task)
	task_input.clear()
	_render_tasks()
	_show_feedback("新的种子埋好了")
	task_added.emit(task)
	tasks_changed.emit(get_tasks())

func delete_task(task_id: String) -> void:
	for i in range(tasks.size()):
		if String(tasks[i].get("id", "")) == task_id:
			tasks.remove_at(i)
			break
	_render_tasks()
	task_deleted.emit(task_id)
	tasks_changed.emit(get_tasks())

func toggle_task(task_id: String, done: bool) -> void:
	for i in range(tasks.size()):
		var task: Dictionary = tasks[i]
		if String(task.get("id", "")) == task_id:
			var was_done := bool(task.get("done", false))
			task["done"] = done
			task["completed_at"] = save_manager.current_datetime() if done and save_manager else null
			tasks[i] = task
			if done and not was_done:
				tasks_completed_today += 1
				_show_feedback("完成任务，树获得 1 点成长")
				task_completed.emit(task)
			elif not done and was_done:
				tasks_completed_today = max(tasks_completed_today - 1, 0)
				_show_feedback("任务重新放回土里")
			break
	_render_tasks()
	tasks_changed.emit(get_tasks())

func _build_ui() -> void:
	if task_input != null:
		return
	add_theme_stylebox_override("panel", _panel_style(Color(0.88, 0.91, 0.78), Color(0.30, 0.40, 0.31)))

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := Label.new()
	title.text = "今日任务苗圃"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.17, 0.27, 0.18))
	root.add_child(title)

	progress_label = Label.new()
	progress_label.add_theme_color_override("font_color", Color(0.32, 0.39, 0.30))
	root.add_child(progress_label)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 6)
	root.add_child(input_row)

	task_input = LineEdit.new()
	task_input.placeholder_text = "写下要种进今天的事"
	task_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	task_input.add_theme_color_override("font_color", Color(0.07, 0.10, 0.10))
	task_input.add_theme_color_override("font_placeholder_color", Color(0.30, 0.36, 0.33))
	task_input.add_theme_color_override("caret_color", Color(0.08, 0.36, 0.43))
	task_input.add_theme_color_override("selection_color", Color(0.95, 0.72, 0.34, 0.50))
	task_input.add_theme_stylebox_override("normal", _input_style(Color(1.0, 0.98, 0.87), Color(0.39, 0.46, 0.39), 2))
	task_input.add_theme_stylebox_override("focus", _input_style(Color(1.0, 0.99, 0.90), Color(0.08, 0.38, 0.44), 3))
	task_input.text_submitted.connect(func(text: String): add_task(text))
	input_row.add_child(task_input)

	var add_button := Button.new()
	add_button.text = "播种"
	add_button.tooltip_text = "添加任务"
	add_button.pressed.connect(func(): add_task(task_input.text))
	input_row.add_child(add_button)

	feedback_label = Label.new()
	feedback_label.text = "完成任务会让树成长"
	feedback_label.add_theme_color_override("font_color", Color(0.25, 0.42, 0.25))
	feedback_label.add_theme_font_size_override("font_size", 13)
	root.add_child(feedback_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 150)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	task_list = VBoxContainer.new()
	task_list.add_theme_constant_override("separation", 6)
	task_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(task_list)
	_update_progress()

func _render_tasks() -> void:
	if task_list == null:
		return
	for child in task_list.get_children():
		child.queue_free()
	for task in tasks:
		var item := TaskItem.new()
		item.setup(task)
		item.toggled.connect(toggle_task)
		item.delete_requested.connect(delete_task)
		task_list.add_child(item)
	_update_progress()

func _update_progress() -> void:
	if progress_label == null:
		return
	var open_count := 0
	for task in tasks:
		if not bool(task.get("done", false)):
			open_count += 1
	progress_label.text = "已完成 %d  /  待办 %d" % [tasks_completed_today, open_count]

func _show_feedback(message: String) -> void:
	if feedback_label == null:
		return
	feedback_label.text = message
	feedback_label.add_theme_color_override("font_color", Color(0.08, 0.42, 0.25))
	var timer := get_tree().create_timer(1.8)
	timer.timeout.connect(func():
		if feedback_label:
			feedback_label.text = "完成任务会让树成长"
			feedback_label.add_theme_color_override("font_color", Color(0.25, 0.42, 0.25))
	)

func _panel_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _input_style(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style
