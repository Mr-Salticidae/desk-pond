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
var collection_window: Window
var collection_list: VBoxContainer

func _ready() -> void:
	get_window().min_size = Vector2i(640, 520)
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

	var collection_button := Button.new()
	collection_button.text = "图鉴"
	collection_button.tooltip_text = "查看钓获收藏"
	collection_button.pressed.connect(_open_collection_window)
	top_bar.add_child(collection_button)

	always_on_top_button = CheckButton.new()
	always_on_top_button.text = "置顶"
	always_on_top_button.button_pressed = bool(save_data["settings"].get("always_on_top", false))
	always_on_top_button.toggled.connect(_on_always_on_top_toggled)
	top_bar.add_child(always_on_top_button)

	pixel_world = PixelWorldScene.instantiate()
	pixel_world.custom_minimum_size = Vector2(640, 200)
	pixel_world.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pixel_world.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(pixel_world)

	var bottom_margin := MarginContainer.new()
	bottom_margin.custom_minimum_size = Vector2(0, 280)
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
	pomodoro_panel.custom_minimum_size = Vector2(230, 0)
	pomodoro_panel.size_flags_horizontal = Control.SIZE_FILL
	bottom.add_child(pomodoro_panel)

	task_panel = TaskPanelScene.instantiate()
	task_panel.custom_minimum_size = Vector2(390, 0)
	task_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	task_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.add_child(task_panel)

	reward_popup = RewardPopupScene.instantiate()
	add_child(reward_popup)
	_build_collection_window()

func _setup_modules() -> void:
	fishing_manager.set_fish_count(save_data.get("fish_count", {}))
	tree_manager.set_growth_points(int(save_data.get("tree_growth_points", 0)))

	pomodoro_panel.setup(save_data.get("settings", {}))
	task_panel.setup(save_data.get("tasks", []), int(save_data.get("tasks_completed", 0)), save_manager)

	pomodoro_panel.focus_completed.connect(_on_focus_completed)
	pomodoro_panel.state_changed.connect(_on_timer_state_changed)
	pomodoro_panel.settings_changed.connect(_on_timer_settings_changed)
	pixel_world.cast_requested.connect(_on_cast_requested)
	task_panel.tasks_changed.connect(_on_tasks_changed)
	task_panel.task_completed.connect(_on_task_completed)
	task_panel.task_added.connect(func(_task: Dictionary): _save_now())
	task_panel.task_deleted.connect(func(_task_id: String): _save_now())
	tree_manager.growth_changed.connect(_on_tree_growth_changed)

	_on_tree_growth_changed(tree_manager.growth_points, tree_manager.tree_stage)
	_update_stats()
	_render_collection()

func _on_focus_completed() -> void:
	save_data["pomodoro_completed"] = int(save_data.get("pomodoro_completed", 0)) + 1
	var fish := fishing_manager.roll_fish()
	save_data["fish_count"] = fishing_manager.get_fish_count()
	pixel_world.play_focus_feedback()
	reward_popup.show_reward(fish)
	_render_collection()
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
		pixel_world.set_activity_state(state)

func _on_timer_settings_changed(settings: Dictionary) -> void:
	save_data["settings"]["focus_minutes"] = int(settings.get("focus_minutes", save_data["settings"].get("focus_minutes", 25)))
	save_data["settings"]["break_minutes"] = int(settings.get("break_minutes", save_data["settings"].get("break_minutes", 5)))
	_save_now()

func _on_cast_requested() -> void:
	if pomodoro_panel:
		pomodoro_panel.start_focus()

func _on_always_on_top_toggled(enabled: bool) -> void:
	save_data["settings"]["always_on_top"] = enabled
	_apply_window_settings()
	_save_now()

func _apply_window_settings() -> void:
	get_window().always_on_top = bool(save_data["settings"].get("always_on_top", false))

func _open_collection_window() -> void:
	if collection_window == null:
		_build_collection_window()
	_render_collection()
	collection_window.popup_centered()

func _build_collection_window() -> void:
	if collection_window != null:
		return
	collection_window = Window.new()
	collection_window.title = "钓获图鉴"
	collection_window.size = Vector2i(420, 360)
	collection_window.visible = false
	collection_window.close_requested.connect(collection_window.hide)
	add_child(collection_window)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _make_stylebox(Color(0.90, 0.93, 0.83), Color(0.24, 0.39, 0.37), 2, 6))
	collection_window.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	var title := Label.new()
	title.text = "钓获图鉴"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.10, 0.25, 0.25))
	root.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	collection_list = VBoxContainer.new()
	collection_list.add_theme_constant_override("separation", 6)
	collection_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(collection_list)

func _render_collection() -> void:
	if collection_list == null or fishing_manager == null:
		return
	for child in collection_list.get_children():
		child.queue_free()
	var counts := fishing_manager.get_fish_count()
	for fish in fishing_manager.get_fish_data():
		var fish_id := String(fish.get("id", ""))
		var count := int(counts.get(fish_id, 0))
		var row := VBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 54)
		row.add_theme_constant_override("separation", 2)
		collection_list.add_child(row)

		var top_row := HBoxContainer.new()
		top_row.add_theme_constant_override("separation", 8)
		row.add_child(top_row)

		var name_label := Label.new()
		name_label.text = String(fish.get("name", "神秘小鱼")) if count > 0 else "未知钓获"
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_color_override("font_color", Color(0.13, 0.20, 0.19) if count > 0 else Color(0.43, 0.48, 0.44))
		top_row.add_child(name_label)

		var rarity_label := Label.new()
		rarity_label.text = _rarity_name(String(fish.get("rarity", "common")))
		rarity_label.custom_minimum_size = Vector2(64, 0)
		rarity_label.add_theme_color_override("font_color", _rarity_color(String(fish.get("rarity", "common"))))
		top_row.add_child(rarity_label)

		var count_label := Label.new()
		count_label.text = "x%d" % count
		count_label.custom_minimum_size = Vector2(44, 0)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.add_theme_color_override("font_color", Color(0.08, 0.35, 0.38) if count > 0 else Color(0.46, 0.50, 0.48))
		top_row.add_child(count_label)

		var description_label := Label.new()
		description_label.text = String(fish.get("description", "")) if count > 0 else "完成专注，看看池塘里会不会遇到它。"
		description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description_label.add_theme_font_size_override("font_size", 12)
		description_label.add_theme_color_override("font_color", Color(0.30, 0.39, 0.37) if count > 0 else Color(0.48, 0.52, 0.49))
		row.add_child(description_label)

func _rarity_name(rarity: String) -> String:
	match rarity:
		"uncommon":
			return "少见"
		"rare":
			return "稀有"
		_:
			return "常见"

func _rarity_color(rarity: String) -> Color:
	match rarity:
		"uncommon":
			return Color(0.22, 0.45, 0.21)
		"rare":
			return Color(0.55, 0.27, 0.63)
		_:
			return Color(0.35, 0.36, 0.30)

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
