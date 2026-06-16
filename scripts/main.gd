extends Control

const SaveManagerScript = preload("res://scripts/save_manager.gd")
const FishingManagerScript = preload("res://scripts/fishing_manager.gd")
const TreeManagerScript = preload("res://scripts/tree_manager.gd")
const PixelWorldScene = preload("res://scenes/PixelWorld.tscn")
const PomodoroPanelScene = preload("res://scenes/PomodoroPanel.tscn")
const TaskPanelScene = preload("res://scenes/TaskPanel.tscn")

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
var help_window: Window

var _dragging_window: bool = false
var _drag_anchor: Vector2i = Vector2i.ZERO

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
	bg.color = UITheme.BG_DEEP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	var top_bar_panel := PanelContainer.new()
	top_bar_panel.custom_minimum_size = Vector2(0, 36)
	top_bar_panel.add_theme_stylebox_override("panel", UITheme.chrome_bar_style())
	top_bar_panel.gui_input.connect(_on_title_bar_input)
	top_bar_panel.mouse_default_cursor_shape = Control.CURSOR_MOVE
	top_bar_panel.tooltip_text = "拖动可移动窗口"
	root.add_child(top_bar_panel)

	var top_bar := HBoxContainer.new()
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_theme_constant_override("separation", 6)
	top_bar_panel.add_child(top_bar)

	var app_title := Label.new()
	app_title.text = "工位池塘 Desk Pond"
	app_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app_title.add_theme_font_size_override("font_size", 15)
	app_title.add_theme_color_override("font_color", UITheme.INK_ON_CHROME)
	top_bar.add_child(app_title)

	stats_label = Label.new()
	stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_label.add_theme_font_size_override("font_size", 13)
	stats_label.add_theme_color_override("font_color", Color(0.878, 0.902, 0.855, 0.66))
	top_bar.add_child(stats_label)

	var collection_button := Button.new()
	collection_button.text = "图鉴"
	collection_button.focus_mode = Control.FOCUS_NONE
	collection_button.tooltip_text = "查看钓获收藏"
	UITheme.style_chrome(collection_button)
	collection_button.pressed.connect(_open_collection_window)
	top_bar.add_child(collection_button)

	var help_button := Button.new()
	help_button.text = "?"
	help_button.focus_mode = Control.FOCUS_NONE
	help_button.tooltip_text = "查看玩法说明"
	UITheme.style_chrome(help_button)
	help_button.pressed.connect(_open_help_window)
	top_bar.add_child(help_button)

	always_on_top_button = CheckButton.new()
	always_on_top_button.text = "置顶"
	always_on_top_button.focus_mode = Control.FOCUS_NONE
	always_on_top_button.add_theme_color_override("font_color", UITheme.INK_ON_CHROME)
	always_on_top_button.button_pressed = bool(save_data["settings"].get("always_on_top", false))
	always_on_top_button.toggled.connect(_on_always_on_top_toggled)
	top_bar.add_child(always_on_top_button)

	var minimize_button := Button.new()
	minimize_button.text = "—"
	minimize_button.focus_mode = Control.FOCUS_NONE
	minimize_button.tooltip_text = "最小化"
	UITheme.style_chrome(minimize_button)
	minimize_button.pressed.connect(_on_minimize_pressed)
	top_bar.add_child(minimize_button)

	var close_button := Button.new()
	close_button.text = "×"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.tooltip_text = "关闭"
	UITheme.style_chrome(close_button, true)
	close_button.pressed.connect(_on_close_pressed)
	top_bar.add_child(close_button)

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

	reward_popup = RewardPopup.new()
	add_child(reward_popup)
	_build_collection_window()
	_build_help_window()

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

func _on_title_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging_window = event.pressed
		if event.pressed:
			_drag_anchor = DisplayServer.mouse_get_position() - get_window().position
	elif event is InputEventMouseMotion and _dragging_window:
		get_window().position = DisplayServer.mouse_get_position() - _drag_anchor

func _on_minimize_pressed() -> void:
	get_window().mode = Window.MODE_MINIMIZED

func _on_close_pressed() -> void:
	_save_now()
	get_tree().quit()

func _open_collection_window() -> void:
	if collection_window == null:
		_build_collection_window()
	_render_collection()
	collection_window.popup_centered()

func _build_collection_window() -> void:
	if collection_window != null:
		return
	var card := UICard.new()
	card.configure("钓获图鉴", Vector2i(420, 388))
	add_child(card)
	collection_window = card

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.body.add_child(scroll)

	collection_list = VBoxContainer.new()
	collection_list.add_theme_constant_override("separation", 4)
	collection_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(collection_list)

func _open_help_window() -> void:
	if help_window == null:
		_build_help_window()
	help_window.popup_centered()

func _build_help_window() -> void:
	if help_window != null:
		return
	var card := UICard.new()
	card.configure("玩法说明", Vector2i(420, 360))
	add_child(card)
	help_window = card

	var intro := Label.new()
	intro.text = "工位池塘，慢慢养成一天。"
	intro.add_theme_font_size_override("font_size", 15)
	intro.add_theme_color_override("font_color", UITheme.INK)
	card.body.add_child(intro)

	var tips := [
		"点击池塘水面，或按“甩杆”，开始一次专注。",
		"专注和休息时间可以在左侧直接调整，开始后会锁定。",
		"专注完成会自动钓获奖励，并进入休息倒计时。",
		"写下今日任务，完成任务会让右侧的小树成长。",
		"任务多时点“展开”，打开完整代办清单。",
		"点“图鉴”查看钓到过的鱼和收集进度。"
	]
	for tip in tips:
		var label := Label.new()
		label.text = "·  %s" % tip
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color", UITheme.INK_SOFT)
		card.body.add_child(label)

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
		name_label.add_theme_color_override("font_color", UITheme.INK if count > 0 else UITheme.INK_FAINT)
		top_row.add_child(name_label)

		var rarity_label := Label.new()
		rarity_label.text = _rarity_name(String(fish.get("rarity", "common")))
		rarity_label.custom_minimum_size = Vector2(64, 0)
		rarity_label.add_theme_color_override("font_color", _rarity_color(String(fish.get("rarity", "common"))))
		top_row.add_child(rarity_label)

		var count_label := Label.new()
		count_label.text = "×%d" % count
		count_label.custom_minimum_size = Vector2(44, 0)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.add_theme_color_override("font_color", UITheme.POND if count > 0 else UITheme.INK_FAINT)
		top_row.add_child(count_label)

		var description_label := Label.new()
		description_label.text = String(fish.get("description", "")) if count > 0 else "完成专注，看看池塘里会不会遇到它。"
		description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description_label.add_theme_font_size_override("font_size", 12)
		description_label.add_theme_color_override("font_color", UITheme.INK_SOFT if count > 0 else UITheme.INK_FAINT)
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
	theme = UITheme.make_theme()

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
