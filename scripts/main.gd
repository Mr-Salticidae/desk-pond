extends Control

const SaveManagerScript = preload("res://scripts/save_manager.gd")
const FishingManagerScript = preload("res://scripts/fishing_manager.gd")
const TreeManagerScript = preload("res://scripts/tree_manager.gd")
const PixelWorldScene = preload("res://scenes/PixelWorld.tscn")
const PomodoroPanelScene = preload("res://scenes/PomodoroPanel.tscn")
const TaskPanelScene = preload("res://scenes/TaskPanel.tscn")
const RewardPopupScene = preload("res://scenes/RewardPopup.tscn")

var save_manager: SaveManager
var fishing_manager: FishingManager
var tree_manager: TreeManager
var save_data: Dictionary

var pixel_world: PixelWorld
var pomodoro_panel: PomodoroTimer
var task_panel: TaskManager
var reward_popup: RewardPopup
var stats_label: Label
var always_on_top_button: CheckButton

func _ready() -> void:
	get_window().min_size = Vector2i(480, 270)
	save_manager = SaveManagerScript.new()
	fishing_manager = FishingManagerScript.new()
	tree_manager = TreeManagerScript.new()
	save_data = save_manager.load_save()
	_build_ui()
	_setup_modules()
	_apply_window_settings()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_now()

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	var top_bar := HBoxContainer.new()
	top_bar.custom_minimum_size = Vector2(0, 28)
	top_bar.add_theme_constant_override("separation", 8)
	root.add_child(top_bar)

	var app_title := Label.new()
	app_title.text = "工位池塘 Desk Pond"
	app_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(app_title)

	stats_label = Label.new()
	top_bar.add_child(stats_label)

	always_on_top_button = CheckButton.new()
	always_on_top_button.text = "置顶"
	always_on_top_button.button_pressed = bool(save_data["settings"].get("always_on_top", false))
	always_on_top_button.toggled.connect(_on_always_on_top_toggled)
	top_bar.add_child(always_on_top_button)

	pixel_world = PixelWorldScene.instantiate()
	pixel_world.custom_minimum_size = Vector2(640, 190)
	pixel_world.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pixel_world.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(pixel_world)

	var bottom := HBoxContainer.new()
	bottom.custom_minimum_size = Vector2(0, 142)
	bottom.add_theme_constant_override("separation", 0)
	root.add_child(bottom)

	pomodoro_panel = PomodoroPanelScene.instantiate()
	pomodoro_panel.custom_minimum_size = Vector2(260, 0)
	pomodoro_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(pomodoro_panel)

	task_panel = TaskPanelScene.instantiate()
	task_panel.custom_minimum_size = Vector2(360, 0)
	task_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(task_panel)

	reward_popup = RewardPopupScene.instantiate()
	add_child(reward_popup)

func _setup_modules() -> void:
	fishing_manager.set_fish_count(save_data.get("fish_count", {}))
	tree_manager.set_growth_points(int(save_data.get("tree_growth_points", 0)))

	pomodoro_panel.setup(save_data.get("settings", {}))
	task_panel.setup(save_data.get("tasks", []), int(save_data.get("tasks_completed", 0)), save_manager)

	pomodoro_panel.focus_completed.connect(_on_focus_completed)
	pomodoro_panel.state_changed.connect(_on_timer_state_changed)
	task_panel.tasks_changed.connect(_on_tasks_changed)
	task_panel.task_completed.connect(_on_task_completed)
	task_panel.task_added.connect(func(_task: Dictionary): _save_now())
	task_panel.task_deleted.connect(func(_task_id: String): _save_now())
	tree_manager.growth_changed.connect(_on_tree_growth_changed)

	_on_tree_growth_changed(tree_manager.growth_points, tree_manager.tree_stage)
	_update_stats()

func _on_focus_completed() -> void:
	save_data["pomodoro_completed"] = int(save_data.get("pomodoro_completed", 0)) + 1
	var fish := fishing_manager.roll_fish()
	save_data["fish_count"] = fishing_manager.get_fish_count()
	pixel_world.play_focus_feedback()
	reward_popup.show_reward(fish)
	_save_now()

func _on_task_completed(_task: Dictionary) -> void:
	tree_manager.add_growth_point(1)
	save_data["tree_growth_points"] = tree_manager.growth_points
	save_data["tree_stage"] = tree_manager.tree_stage
	_save_now()

func _on_tasks_changed(tasks: Array) -> void:
	save_data["tasks"] = tasks
	save_data["tasks_completed"] = task_panel.get_tasks_completed_today()
	_save_now()

func _on_tree_growth_changed(growth_points: int, tree_stage: int) -> void:
	save_data["tree_growth_points"] = growth_points
	save_data["tree_stage"] = tree_stage
	if pixel_world:
		pixel_world.update_tree_visual(tree_stage, growth_points)
	_update_stats()

func _on_timer_state_changed(state: String) -> void:
	if pixel_world:
		pixel_world.set_fishing_active(state == "focusing")

func _on_always_on_top_toggled(enabled: bool) -> void:
	save_data["settings"]["always_on_top"] = enabled
	_apply_window_settings()
	_save_now()

func _apply_window_settings() -> void:
	get_window().always_on_top = bool(save_data["settings"].get("always_on_top", false))

func _update_stats() -> void:
	if stats_label == null:
		return
	var fish_total := 0
	for value in fishing_manager.get_fish_count().values():
		fish_total += int(value)
	stats_label.text = "番茄 %d  任务 %d  鱼 %d" % [
		int(save_data.get("pomodoro_completed", 0)),
		int(save_data.get("tasks_completed", 0)),
		fish_total
	]

func _save_now() -> void:
	if save_manager == null:
		return
	if task_panel:
		save_data["tasks"] = task_panel.get_tasks()
		save_data["tasks_completed"] = task_panel.get_tasks_completed_today()
	if fishing_manager:
		save_data["fish_count"] = fishing_manager.get_fish_count()
	if tree_manager:
		save_data["tree_growth_points"] = tree_manager.growth_points
		save_data["tree_stage"] = tree_manager.tree_stage
	_update_stats()
	save_manager.save_game(save_data)
