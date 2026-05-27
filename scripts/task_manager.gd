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
var full_task_window: Window
var full_task_input: LineEdit
var full_task_list: VBoxContainer
var full_progress_label: Label
var full_feedback_label: Label
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
		_show_feedback("先写下一个任务")
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
	if task_input:
		task_input.clear()
	if full_task_input:
		full_task_input.clear()
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
	_show_feedback("任务已移除")
	task_deleted.emit(task_id)
	tasks_changed.emit(get_tasks())

func clear_completed_tasks() -> void:
	var remaining: Array = []
	var removed_count := 0
	for task in tasks:
		if bool(task.get("done", false)):
			removed_count += 1
		else:
			remaining.append(task)
	tasks = remaining
	_render_tasks()
	_show_feedback("已清理 %d 个完成任务" % removed_count if removed_count > 0 else "没有需要清理的完成任务")
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

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)

	var title := Label.new()
	title.text = "今日任务苗圃"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.17, 0.27, 0.18))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var expand_button := Button.new()
	expand_button.text = "展开"
	expand_button.tooltip_text = "打开完整代办清单"
	expand_button.pressed.connect(_open_full_task_window)
	header.add_child(expand_button)

	progress_label = Label.new()
	progress_label.add_theme_color_override("font_color", Color(0.32, 0.39, 0.30))
	root.add_child(progress_label)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 6)
	root.add_child(input_row)

	task_input = LineEdit.new()
	task_input.placeholder_text = "写下要种进今天的事"
	task_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_input_theme(task_input)
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
	scroll.custom_minimum_size = Vector2(0, 130)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	task_list = VBoxContainer.new()
	task_list.add_theme_constant_override("separation", 6)
	task_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(task_list)

	_build_full_task_window()
	_update_progress()

func _render_tasks() -> void:
	if task_list == null:
		return
	_clear_task_list(task_list)
	if tasks.is_empty():
		task_list.add_child(_make_empty_label("今天还没有种下任务"))
	else:
		for task in tasks:
			task_list.add_child(_make_task_item(task))
	if full_task_list:
		_clear_task_list(full_task_list)
		if tasks.is_empty():
			full_task_list.add_child(_make_empty_label("先写下一个今天想完成的小目标"))
		else:
			for task in tasks:
				full_task_list.add_child(_make_task_item(task))
	_update_progress()

func _make_task_item(task: Dictionary) -> TaskItem:
	var item := TaskItem.new()
	item.setup(task)
	item.toggled.connect(toggle_task)
	item.delete_requested.connect(delete_task)
	return item

func _clear_task_list(list: VBoxContainer) -> void:
	for child in list.get_children():
		child.queue_free()

func _make_empty_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(0, 42)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.40, 0.47, 0.38))
	return label

func _update_progress() -> void:
	var done_count := 0
	var open_count := 0
	for task in tasks:
		if bool(task.get("done", false)):
			done_count += 1
		else:
			open_count += 1
	var text := "已完成 %d  /  待办 %d" % [done_count, open_count]
	if progress_label:
		progress_label.text = text
	if full_progress_label:
		full_progress_label.text = text

func _show_feedback(message: String) -> void:
	_set_feedback_text(message, Color(0.08, 0.42, 0.25))
	var timer := get_tree().create_timer(1.8)
	timer.timeout.connect(func():
		_set_feedback_text("完成任务会让树成长", Color(0.25, 0.42, 0.25))
	)

func _set_feedback_text(message: String, color: Color) -> void:
	if feedback_label:
		feedback_label.text = message
		feedback_label.add_theme_color_override("font_color", color)
	if full_feedback_label:
		full_feedback_label.text = message
		full_feedback_label.add_theme_color_override("font_color", color)

func _open_full_task_window() -> void:
	if full_task_window == null:
		_build_full_task_window()
	_render_tasks()
	full_task_window.popup_centered()
	if full_task_input:
		full_task_input.grab_focus()

func _build_full_task_window() -> void:
	if full_task_window != null:
		return
	full_task_window = Window.new()
	full_task_window.title = "完整代办清单"
	full_task_window.size = Vector2i(520, 520)
	full_task_window.visible = false
	full_task_window.close_requested.connect(full_task_window.hide)
	add_child(full_task_window)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.91, 0.93, 0.80), Color(0.26, 0.38, 0.29)))
	full_task_window.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	var title := Label.new()
	title.text = "完整代办清单"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.12, 0.24, 0.15))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)
	header.add_child(title)

	var clear_button := Button.new()
	clear_button.text = "清理完成"
	clear_button.tooltip_text = "移除已经完成的任务"
	clear_button.pressed.connect(clear_completed_tasks)
	header.add_child(clear_button)

	full_progress_label = Label.new()
	full_progress_label.add_theme_color_override("font_color", Color(0.32, 0.39, 0.30))
	root.add_child(full_progress_label)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 6)
	root.add_child(input_row)

	full_task_input = LineEdit.new()
	full_task_input.placeholder_text = "继续写下今天要做的事"
	full_task_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_input_theme(full_task_input)
	full_task_input.text_submitted.connect(func(text: String): add_task(text))
	input_row.add_child(full_task_input)

	var add_button := Button.new()
	add_button.text = "播种"
	add_button.tooltip_text = "添加任务"
	add_button.pressed.connect(func(): add_task(full_task_input.text))
	input_row.add_child(add_button)

	full_feedback_label = Label.new()
	full_feedback_label.text = "完成任务会让树成长"
	full_feedback_label.add_theme_color_override("font_color", Color(0.25, 0.42, 0.25))
	full_feedback_label.add_theme_font_size_override("font_size", 13)
	root.add_child(full_feedback_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 350)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	full_task_list = VBoxContainer.new()
	full_task_list.add_theme_constant_override("separation", 6)
	full_task_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(full_task_list)

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

func _apply_input_theme(line_edit: LineEdit) -> void:
	line_edit.add_theme_color_override("font_color", Color(0.07, 0.10, 0.10))
	line_edit.add_theme_color_override("font_placeholder_color", Color(0.30, 0.36, 0.33))
	line_edit.add_theme_color_override("caret_color", Color(0.08, 0.36, 0.43))
	line_edit.add_theme_color_override("selection_color", Color(0.95, 0.72, 0.34, 0.50))
	line_edit.add_theme_stylebox_override("normal", _input_style(Color(1.0, 0.98, 0.87), Color(0.39, 0.46, 0.39), 2))
	line_edit.add_theme_stylebox_override("focus", _input_style(Color(1.0, 0.99, 0.90), Color(0.08, 0.38, 0.44), 3))
