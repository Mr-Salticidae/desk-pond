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
	get_window().min_size = Vector2i(640, 460)
	save_manager = SaveManagerScript.new()
	fishing_manager = FishingManagerScript.new()
	tree_manager = TreeManagerScript.new()
	save_data = save_manager.load_save()
	_apply_theme()
	_build_ui()
	_setup_modules()
	_apply_window_settings()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_now()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.16, 0.18)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	var top_bar_panel := PanelContainer.new()
	top_bar_panel.custom_minimum_size = Vector2(0, 34)
	top_bar_panel.add_theme_stylebox_override("panel", _make_stylebox(Color(0.15, 0.21, 0.22), Color(0.29, 0.42, 0.41), 0, 0))
	root.add_child(top_bar_panel)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("margin_left", 10)
	top_bar.add_theme_constant_override("margin_right", 10)
	top_bar.add_theme_constant_override("margin_top", 4)
	top_bar.add_theme_constant_override("margin_bottom", 4)
	top_bar.add_theme_constant_override("separation", 8)
	top_bar_panel.add_child(top_bar)

	var app_title := Label.new()
	app_title.text = "工位池塘 Desk Pond"
	app_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app_title.add_theme_font_size_override("font_size", 16)
	app_title.add_theme_color_override("font_color", Color(0.92, 0.95, 0.86))
	top_bar.add_child(app_title)

	stats_label = Label.new()
	stats_label.add_theme_color_override("font_color", Color(0.86, 0.91, 0.78))
	top_bar.add_child(stats_label)

	always_on_top_button = CheckButton.new()
	always_on_top_button.text = "置顶"
	always_on_top_button.button_pressed = bool(save_data["settings"].get("always_on_top", false))
	always_on_top_button.toggled.connect(_on_always_on_top_toggled)
	top_bar.add_child(always_on_top_button)

	pixel_world = PixelWorldScene.instantiate()
	pixel_world.custom_minimum_size = Vector2(640, 210)
	pixel_world.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pixel_world.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(pixel_world)

	var bottom_margin := MarginContainer.new()
	bottom_margin.custom_minimum_size = Vector2(0, 220)
	bottom_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_margin.add_theme_constant_override("margin_left", 8)
	bottom_margin.add_theme_constant_override("margin_right", 8)
	bottom_margin.add_theme_constant_override("margin_top", 8)
	bottom_margin.add_theme_constant_override("margin_bottom", 8)
	root.add_child(bottom_margin)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	bottom_margin.add_child(bottom)

	pomodoro_panel = PomodoroPanelScene.instantiate()
	pomodoro_panel.custom_minimum_size = Vector2(220, 0)
	pomodoro_panel.size_flags_horizontal = Control.SIZE_FILL
	bottom.add_child(pomodoro_panel)

	task_panel = TaskPanelScene.instantiate()
	task_panel.custom_minimum_size = Vector2(390, 0)
	task_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	task_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	pixel_world.cast_requested.connect(_on_cast_requested)
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

func _on_cast_requested() -> void:
	if pomodoro_panel:
		pomodoro_panel.start_focus()

func _on_always_on_top_toggled(enabled: bool) -> void:
	save_data["settings"]["always_on_top"] = enabled
	_apply_window_settings()
	_save_now()

func _apply_window_settings() -> void:
	get_window().always_on_top = bool(save_data["settings"].get("always_on_top", false))

func _apply_theme() -> void:
	var game_theme := Theme.new()
	game_theme.set_color("font_color", "Label", Color(0.17, 0.22, 0.22))
	game_theme.set_color("font_color", "LineEdit", Color(0.08, 0.12, 0.12))
	game_theme.set_color("font_placeholder_color", "LineEdit", Color(0.28, 0.34, 0.32))
	game_theme.set_color("caret_color", "LineEdit", Color(0.08, 0.36, 0.43))
	game_theme.set_color("selection_color", "LineEdit", Color(0.95, 0.72, 0.34, 0.45))
	game_theme.set_stylebox("panel", "PanelContainer", _make_stylebox(Color(0.91, 0.89, 0.78), Color(0.28, 0.36, 0.31), 2, 6))
	game_theme.set_stylebox("normal", "Button", _make_stylebox(Color(0.88, 0.58, 0.31), Color(0.43, 0.24, 0.15), 2, 5))
	game_theme.set_stylebox("hover", "Button", _make_stylebox(Color(0.95, 0.70, 0.40), Color(0.43, 0.24, 0.15), 2, 5))
	game_theme.set_stylebox("pressed", "Button", _make_stylebox(Color(0.66, 0.38, 0.24), Color(0.27, 0.15, 0.11), 2, 5))
	game_theme.set_stylebox("normal", "LineEdit", _make_stylebox(Color(0.98, 0.96, 0.86), Color(0.45, 0.50, 0.42), 2, 5))
	game_theme.set_stylebox("focus", "LineEdit", _make_stylebox(Color(1.0, 0.98, 0.88), Color(0.09, 0.42, 0.48), 3, 5))
	game_theme.set_color("font_color", "Button", Color(0.18, 0.13, 0.10))
	game_theme.set_color("font_hover_color", "Button", Color(0.18, 0.13, 0.10))
	game_theme.set_color("font_pressed_color", "Button", Color(0.98, 0.93, 0.82))
	theme = game_theme

func _make_stylebox(fill: Color, border: Color, border_width: int = 1, radius: int = 4) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

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
