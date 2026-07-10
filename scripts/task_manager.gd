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
var edit_window: Window
var edit_input: LineEdit
var editing_task_id := ""
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
		"id": _new_task_id(),
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

# 旧实现用 ticks_msec（自启动毫秒数）当 id，跨会话可能撞车导致
# 勾选 / 删除找错任务。改为 unix 秒 + 随机后缀，并与现有任务查重。
func _new_task_id() -> String:
	for _attempt in range(100):
		var id := "task_%d_%04d" % [int(Time.get_unix_time_from_system()), randi() % 10000]
		var taken := false
		for task in tasks:
			if String(task.get("id", "")) == id:
				taken = true
				break
		if not taken:
			return id
	return "task_%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]

func delete_task(task_id: String) -> void:
	for i in range(tasks.size()):
		if String(tasks[i].get("id", "")) == task_id:
			tasks.remove_at(i)
			break
	_render_tasks()
	_show_feedback("任务已移除")
	task_deleted.emit(task_id)
	tasks_changed.emit(get_tasks())

func update_task_title(task_id: String, new_title: String) -> bool:
	var clean_title := new_title.strip_edges()
	if clean_title == "":
		_show_feedback("任务标题不能为空")
		return false
	for i in range(tasks.size()):
		var task: Dictionary = tasks[i]
		if String(task.get("id", "")) == task_id:
			task["title"] = clean_title
			tasks[i] = task
			break
	_render_tasks()
	_show_feedback("任务已更新")
	tasks_changed.emit(get_tasks())
	return true

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
				# 每个任务只在第一次完成时计成长，反复勾选刷不了树
				if bool(task.get("rewarded", false)):
					_show_feedback("任务完成")
				else:
					task["rewarded"] = true
					tasks[i] = task
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
	add_theme_stylebox_override("panel", UITheme.panel_style())

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)

	var title := Label.new()
	title.text = "今日任务苗圃"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", UITheme.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var expand_button := Button.new()
	expand_button.text = "展开"
	expand_button.tooltip_text = "打开完整代办清单"
	expand_button.pressed.connect(_open_full_task_window)
	header.add_child(expand_button)

	progress_label = Label.new()
	progress_label.add_theme_color_override("font_color", UITheme.INK_SOFT)
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
	WebInput.attach("task", task_input)

	var add_button := Button.new()
	add_button.text = "播种"
	add_button.tooltip_text = "添加任务"
	UITheme.style_primary(add_button)
	add_button.pressed.connect(func(): add_task(task_input.text))
	input_row.add_child(add_button)

	feedback_label = Label.new()
	feedback_label.text = "完成任务会让树成长"
	feedback_label.add_theme_color_override("font_color", UITheme.INK_SOFT)
	feedback_label.add_theme_font_size_override("font_size", 13)
	root.add_child(feedback_label)

	var scroll := ScrollContainer.new()
	# 只给一个很小的最小高度，让滚动区随面板伸缩、不把面板撑出窗口外；
	# 任务超过可见行数时由滚动条承接，避免末尾被窗口边缘截断。
	scroll.custom_minimum_size = Vector2(0, 64)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	task_list = VBoxContainer.new()
	task_list.add_theme_constant_override("separation", 6)
	task_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(task_list)

	_build_full_task_window()
	_build_edit_window()
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
	item.edit_requested.connect(_open_edit_window)
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
	_set_feedback_text(message, UITheme.POND)
	var timer := get_tree().create_timer(1.8)
	timer.timeout.connect(func():
		_set_feedback_text("完成任务会让树成长", UITheme.INK_SOFT)
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

func _open_edit_window(task_id: String, current_title: String) -> void:
	if edit_window == null:
		_build_edit_window()
	editing_task_id = task_id
	edit_input.text = current_title
	edit_window.popup_centered()
	edit_input.grab_focus()
	edit_input.select_all()

func _save_edit_window() -> void:
	if editing_task_id == "":
		return
	if not update_task_title(editing_task_id, edit_input.text):
		edit_input.grab_focus()
		return
	editing_task_id = ""
	edit_window.hide()

func _build_edit_window() -> void:
	if edit_window != null:
		return
	var card := UICard.new()
	card.configure("编辑任务", Vector2i(420, 172))
	add_child(card)
	edit_window = card

	var hint := Label.new()
	hint.text = "改个名字，重新种下。"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", UITheme.INK_SOFT)
	card.body.add_child(hint)

	edit_input = LineEdit.new()
	edit_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_input_theme(edit_input)
	edit_input.text_submitted.connect(func(_text: String): _save_edit_window())
	card.body.add_child(edit_input)
	WebInput.attach("task_edit", edit_input)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	card.body.add_child(buttons)

	var cancel_button := Button.new()
	cancel_button.text = "取消"
	cancel_button.pressed.connect(edit_window.hide)
	buttons.add_child(cancel_button)

	var save_button := Button.new()
	save_button.text = "保存"
	UITheme.style_primary(save_button)
	save_button.pressed.connect(_save_edit_window)
	buttons.add_child(save_button)

func _build_full_task_window() -> void:
	if full_task_window != null:
		return
	var card := UICard.new()
	card.configure("完整代办清单", Vector2i(520, 496))
	add_child(card)
	full_task_window = card

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	card.body.add_child(top_row)

	full_progress_label = Label.new()
	full_progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	full_progress_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	full_progress_label.add_theme_color_override("font_color", UITheme.INK_SOFT)
	top_row.add_child(full_progress_label)

	var clear_button := Button.new()
	clear_button.text = "清理完成"
	clear_button.tooltip_text = "移除已经完成的任务"
	clear_button.pressed.connect(clear_completed_tasks)
	top_row.add_child(clear_button)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 6)
	card.body.add_child(input_row)

	full_task_input = LineEdit.new()
	full_task_input.placeholder_text = "继续写下今天要做的事"
	full_task_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_input_theme(full_task_input)
	full_task_input.text_submitted.connect(func(text: String): add_task(text))
	input_row.add_child(full_task_input)
	WebInput.attach("task_full", full_task_input)

	var add_button := Button.new()
	add_button.text = "播种"
	add_button.tooltip_text = "添加任务"
	UITheme.style_primary(add_button)
	add_button.pressed.connect(func(): add_task(full_task_input.text))
	input_row.add_child(add_button)

	full_feedback_label = Label.new()
	full_feedback_label.text = "完成任务会让树成长"
	full_feedback_label.add_theme_color_override("font_color", UITheme.INK_SOFT)
	full_feedback_label.add_theme_font_size_override("font_size", 13)
	card.body.add_child(full_feedback_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.body.add_child(scroll)

	full_task_list = VBoxContainer.new()
	full_task_list.add_theme_constant_override("separation", 6)
	full_task_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(full_task_list)

func _apply_input_theme(line_edit: LineEdit) -> void:
	UITheme.style_input(line_edit)
