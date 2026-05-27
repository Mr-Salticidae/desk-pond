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
				task_completed.emit(task)
			elif not done and was_done:
				tasks_completed_today = max(tasks_completed_today - 1, 0)
			break
	_render_tasks()
	tasks_changed.emit(get_tasks())

func _build_ui() -> void:
	if task_input != null:
		return
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var title := Label.new()
	title.text = "今日计划"
	title.add_theme_font_size_override("font_size", 16)
	root.add_child(title)

	var input_row := HBoxContainer.new()
	root.add_child(input_row)

	task_input = LineEdit.new()
	task_input.placeholder_text = "写下今天要做的事"
	task_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	task_input.text_submitted.connect(func(text: String): add_task(text))
	input_row.add_child(task_input)

	var add_button := Button.new()
	add_button.text = "添加"
	add_button.pressed.connect(func(): add_task(task_input.text))
	input_row.add_child(add_button)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 90)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	task_list = VBoxContainer.new()
	task_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(task_list)

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
