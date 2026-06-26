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
var always_on_top_button: Button
var mute_button: Button
var catalog_view: Control
var collection_list: VBoxContainer
var help_window: Window
var ledger_window: Window
var ledger_body: VBoxContainer

var scene_area: Control
var forest_view: ForestView
var aquarium_view: AquariumView
var current_room := "pond"
var room_tabs: Dictionary = {}
var aqua_subtab_bar: HBoxContainer
var aqua_subtabs: Dictionary = {}
var aquarium_submode := "tank"

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
	_maybe_show_intro()

# 第一次打开时自动弹一次玩法说明，之后不再打扰。
func _maybe_show_intro() -> void:
	if bool(save_data.get("seen_intro", false)):
		return
	save_data["seen_intro"] = true
	_save_now()
	call_deferred("_open_help_window")

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

	var room_group := ButtonGroup.new()
	_make_room_tab("池塘", "pond", room_group, top_bar)
	_make_room_tab("森林", "forest", room_group, top_bar)
	_make_room_tab("水族馆", "aquarium", room_group, top_bar)

	# 水族馆内的子标签：鱼缸 / 图鉴（仅在水族馆房间显示）
	aqua_subtab_bar = HBoxContainer.new()
	aqua_subtab_bar.add_theme_constant_override("separation", 4)
	aqua_subtab_bar.visible = false
	top_bar.add_child(aqua_subtab_bar)
	var sub_group := ButtonGroup.new()
	_make_aqua_subtab("鱼缸", "tank", sub_group, aqua_subtab_bar)
	_make_aqua_subtab("图鉴", "catalog", sub_group, aqua_subtab_bar)
	aqua_subtabs["tank"].set_pressed_no_signal(true)

	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)

	stats_label = Label.new()
	stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_label.add_theme_font_size_override("font_size", 13)
	stats_label.add_theme_color_override("font_color", Color(0.878, 0.902, 0.855, 0.66))
	top_bar.add_child(stats_label)

	var ledger_button := Button.new()
	ledger_button.text = "档案"
	ledger_button.focus_mode = Control.FOCUS_NONE
	ledger_button.tooltip_text = "查看成长档案与水缸布置"
	UITheme.style_chrome(ledger_button)
	ledger_button.pressed.connect(_open_ledger_window)
	top_bar.add_child(ledger_button)

	var help_button := Button.new()
	help_button.text = "?"
	help_button.focus_mode = Control.FOCUS_NONE
	help_button.tooltip_text = "查看玩法说明"
	UITheme.style_chrome(help_button)
	help_button.pressed.connect(_open_help_window)
	top_bar.add_child(help_button)

	mute_button = Button.new()
	mute_button.toggle_mode = true
	mute_button.focus_mode = Control.FOCUS_NONE
	mute_button.tooltip_text = "开关声音"
	UITheme.style_chrome(mute_button)
	var start_muted := bool(save_data["settings"].get("muted", false))
	mute_button.set_pressed_no_signal(start_muted)
	mute_button.text = "静" if start_muted else "声"
	mute_button.toggled.connect(_on_mute_toggled)
	top_bar.add_child(mute_button)

	always_on_top_button = Button.new()
	always_on_top_button.text = "置顶"
	always_on_top_button.toggle_mode = true
	always_on_top_button.focus_mode = Control.FOCUS_NONE
	always_on_top_button.tooltip_text = "窗口置顶"
	UITheme.style_chrome(always_on_top_button)
	always_on_top_button.set_pressed_no_signal(bool(save_data["settings"].get("always_on_top", false)))
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

	scene_area = Control.new()
	scene_area.custom_minimum_size = Vector2(640, 200)
	scene_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scene_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scene_area.clip_contents = true
	root.add_child(scene_area)

	pixel_world = PixelWorldScene.instantiate()
	pixel_world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene_area.add_child(pixel_world)

	forest_view = ForestView.new()
	forest_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	forest_view.visible = false
	scene_area.add_child(forest_view)

	aquarium_view = AquariumView.new()
	aquarium_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	aquarium_view.visible = false
	scene_area.add_child(aquarium_view)

	_build_catalog_view()

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
	_build_help_window()
	_build_ledger_window()

	room_tabs["pond"].set_pressed_no_signal(true)
	_switch_room("pond")

func _setup_modules() -> void:
	fishing_manager.set_fish_count(save_data.get("fish_count", {}))
	tree_manager.set_growth_points(int(save_data.get("tree_growth_points", 0)))

	pomodoro_panel.setup(save_data.get("settings", {}))
	task_panel.setup(save_data.get("tasks", []), int(save_data.get("tasks_completed", 0)), save_manager)

	Audio.init_muted(bool(save_data["settings"].get("muted", false)))

	pomodoro_panel.focus_completed.connect(_on_focus_completed)
	pomodoro_panel.state_changed.connect(_on_timer_state_changed)
	pomodoro_panel.settings_changed.connect(_on_timer_settings_changed)
	pixel_world.cast_requested.connect(_on_cast_requested)
	task_panel.tasks_changed.connect(_on_tasks_changed)
	task_panel.task_completed.connect(_on_task_completed)
	task_panel.task_added.connect(func(_task: Dictionary): _save_now())
	task_panel.task_deleted.connect(func(_task_id: String): _save_now())
	tree_manager.growth_changed.connect(_on_tree_growth_changed)

	_on_tree_growth_changed(tree_manager.growth_points)
	_update_stats()
	_render_collection()

func _on_focus_completed() -> void:
	save_data["pomodoro_completed"] = int(save_data.get("pomodoro_completed", 0)) + 1
	save_data["total_focus_sessions"] = int(save_data.get("total_focus_sessions", 0)) + 1
	var fish := fishing_manager.roll_reward({
		"total_sessions": int(save_data["total_focus_sessions"])
	})
	save_data["fish_count"] = fishing_manager.get_fish_count()
	_record_first_caught(String(fish.get("id", "")))
	pixel_world.play_focus_feedback()
	reward_popup.show_reward(fish)
	Audio.play_chime()
	get_tree().create_timer(0.28).timeout.connect(Audio.play_catch, CONNECT_ONE_SHOT)
	_render_collection()
	_refresh_aquarium()
	_save_now()

func _record_first_caught(fish_id: String) -> void:
	if fish_id == "":
		return
	var first: Dictionary = save_data.get("first_caught", {})
	if not first.has(fish_id):
		first[fish_id] = save_manager.current_datetime().substr(0, 10)
		save_data["first_caught"] = first

func _on_task_completed(_task: Dictionary) -> void:
	Audio.play_task_done()
	tree_manager.add_growth_point(1)
	save_data["tree_growth_points"] = tree_manager.growth_points
	save_data["tree_stage"] = tree_manager.pond_tree_stage()
	save_data["total_tasks_completed"] = int(save_data.get("total_tasks_completed", 0)) + 1
	_save_now()

func _on_tasks_changed(tasks: Array) -> void:
	save_data["tasks"] = tasks
	save_data["tasks_completed"] = task_panel.get_tasks_completed_today()
	_save_now()

func _on_tree_growth_changed(growth_points: int) -> void:
	save_data["tree_growth_points"] = growth_points
	save_data["tree_stage"] = tree_manager.pond_tree_stage()
	if pixel_world:
		pixel_world.update_tree_visual(tree_manager.pond_tree_stage(), tree_manager.mature_count())
	if forest_view:
		forest_view.update_forest(tree_manager)
	_update_stats()

func _make_room_tab(text: String, room_id: String, group: ButtonGroup, parent: Control) -> Button:
	var tab := Button.new()
	tab.text = text
	tab.toggle_mode = true
	tab.button_group = group
	tab.focus_mode = Control.FOCUS_NONE
	UITheme.style_chrome(tab)
	tab.toggled.connect(func(on: bool):
		if on:
			_switch_room(room_id)
	)
	parent.add_child(tab)
	room_tabs[room_id] = tab
	return tab

func _make_aqua_subtab(text: String, mode: String, group: ButtonGroup, parent: Control) -> Button:
	var tab := Button.new()
	tab.text = text
	tab.toggle_mode = true
	tab.button_group = group
	tab.focus_mode = Control.FOCUS_NONE
	UITheme.style_chrome(tab)
	tab.toggled.connect(func(on: bool):
		if on:
			_set_aqua_submode(mode)
	)
	parent.add_child(tab)
	aqua_subtabs[mode] = tab
	return tab

func _switch_room(room: String) -> void:
	current_room = room
	if pixel_world:
		pixel_world.visible = room == "pond"
	if forest_view:
		forest_view.visible = room == "forest"
		if room == "forest":
			forest_view.update_forest(tree_manager)
	var in_aqua := room == "aquarium"
	if aqua_subtab_bar:
		aqua_subtab_bar.visible = in_aqua
	if in_aqua:
		_set_aqua_submode(aquarium_submode)
	else:
		if aquarium_view:
			aquarium_view.visible = false
		if catalog_view:
			catalog_view.visible = false

func _set_aqua_submode(mode: String) -> void:
	aquarium_submode = mode
	var show_tank := mode == "tank"
	if aquarium_view:
		aquarium_view.visible = show_tank
		if show_tank:
			_refresh_aquarium()
	if catalog_view:
		catalog_view.visible = not show_tank
		if not show_tank:
			_render_collection()

func _refresh_aquarium() -> void:
	if aquarium_view == null:
		return
	aquarium_view.update_tank(fishing_manager, {
		"total_sessions": int(save_data.get("total_focus_sessions", 0)),
		"decor": save_data.get("aquarium_decor", {})
	})

func _on_timer_state_changed(state: String) -> void:
	if state == "focusing":
		Audio.play_cast()
	if pixel_world:
		pixel_world.set_activity_state(state)

func _on_timer_settings_changed(settings: Dictionary) -> void:
	save_data["settings"]["focus_minutes"] = int(settings.get("focus_minutes", save_data["settings"].get("focus_minutes", 25)))
	save_data["settings"]["break_minutes"] = int(settings.get("break_minutes", save_data["settings"].get("break_minutes", 5)))
	_save_now()

func _on_cast_requested() -> void:
	if pomodoro_panel:
		pomodoro_panel.start_focus()

func _on_mute_toggled(muted: bool) -> void:
	mute_button.text = "静" if muted else "声"
	save_data["settings"]["muted"] = muted
	Audio.set_muted(muted)
	_save_now()

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
		get_window().position = _clamp_window_to_screen(DisplayServer.mouse_get_position() - _drag_anchor)

# 把主窗口约束在整个虚拟桌面（所有屏幕合并）范围内：既不会被拖出桌面外丢失，
# 又能在多显示器之间自由拖动，不会卡在屏幕交界处。
func _clamp_window_to_screen(pos: Vector2i) -> Vector2i:
	var win := get_window()
	var area := _virtual_usable_rect()
	var max_x := area.position.x + area.size.x - win.size.x
	var max_y := area.position.y + area.size.y - win.size.y
	pos.x = clampi(pos.x, area.position.x, maxi(area.position.x, max_x))
	pos.y = clampi(pos.y, area.position.y, maxi(area.position.y, max_y))
	return pos

func _virtual_usable_rect() -> Rect2i:
	var rect := DisplayServer.screen_get_usable_rect(0)
	for i in range(1, DisplayServer.get_screen_count()):
		rect = rect.merge(DisplayServer.screen_get_usable_rect(i))
	return rect

func _on_minimize_pressed() -> void:
	get_window().mode = Window.MODE_MINIMIZED

func _on_close_pressed() -> void:
	_save_now()
	get_tree().quit()

# 图鉴已并入水族馆：作为缸内「图鉴」子标签的内容，铺在场景区里。
func _build_catalog_view() -> void:
	if catalog_view != null:
		return
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", UITheme.card_style())
	panel.visible = false
	scene_area.add_child(panel)
	catalog_view = panel

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

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
		"写下今日任务，完成任务会让森林里多长一棵树。",
		"任务多时点“展开”，打开完整代办清单。",
		"切到“水族馆”，钓到的鱼会在缸里游；点缸内“图鉴”看收集进度。",
		"点“档案”查看累计成长，并布置水缸里解锁的装饰。"
	]
	for tip in tips:
		var label := Label.new()
		label.text = "·  %s" % tip
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color", UITheme.INK_SOFT)
		card.body.add_child(label)

func _open_ledger_window() -> void:
	if ledger_window == null:
		_build_ledger_window()
	_render_ledger()
	ledger_window.popup_centered()

func _build_ledger_window() -> void:
	if ledger_window != null:
		return
	var card := UICard.new()
	card.configure("成长档案", Vector2i(360, 440))
	add_child(card)
	ledger_window = card

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.body.add_child(scroll)

	ledger_body = VBoxContainer.new()
	ledger_body.add_theme_constant_override("separation", 8)
	ledger_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(ledger_body)

func _render_ledger() -> void:
	if ledger_body == null:
		return
	for child in ledger_body.get_children():
		child.queue_free()

	# —— 累计成长（只增不减）——
	var caught_species := 0
	for value in fishing_manager.get_fish_count().values():
		if int(value) > 0:
			caught_species += 1
	var total_species := fishing_manager.get_fish_data().size()
	var stat_lines := [
		"累计专注  %d 次" % int(save_data.get("total_focus_sessions", 0)),
		"累计完成  %d 个任务" % int(save_data.get("total_tasks_completed", 0)),
		"活跃天数  %d 天" % int(save_data.get("active_days", 1)),
		"已集鱼种  %d / %d" % [caught_species, total_species],
	]
	for line in stat_lines:
		var label := Label.new()
		label.text = line
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", UITheme.INK)
		ledger_body.add_child(label)

	var note := Label.new()
	note.text = "这些只会往上走，漏了哪天也不会清零。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", UITheme.INK_FAINT)
	ledger_body.add_child(note)

	var sep := HSeparator.new()
	ledger_body.add_child(sep)

	# —— 水缸布置 ——
	var decor_title := Label.new()
	decor_title.text = "水缸布置"
	decor_title.add_theme_font_size_override("font_size", 15)
	decor_title.add_theme_color_override("font_color", UITheme.INK)
	ledger_body.add_child(decor_title)

	var stats := {
		"total_sessions": int(save_data.get("total_focus_sessions", 0)),
		"fish_counts": fishing_manager.get_fish_count()
	}
	var prefs: Dictionary = save_data.get("aquarium_decor", {})
	for decor in AquariumView.DECOR:
		var decor_id := String(decor["id"])
		var unlocked := AquariumView.decor_unlocked(decor, stats)
		var pref: Dictionary = prefs.get(decor_id, {})

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		ledger_body.add_child(row)

		var name_label := Label.new()
		name_label.text = String(decor["name"])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_color_override("font_color", UITheme.INK if unlocked else UITheme.INK_FAINT)
		row.add_child(name_label)

		if not unlocked:
			var lock_label := Label.new()
			lock_label.text = "未解锁 · %s" % String(decor.get("unlock_label", ""))
			lock_label.add_theme_font_size_override("font_size", 12)
			lock_label.add_theme_color_override("font_color", UITheme.INK_FAINT)
			row.add_child(lock_label)
			continue

		var on := bool(pref.get("on", true))
		var toggle_button := Button.new()
		toggle_button.text = "显示" if on else "隐藏"
		toggle_button.focus_mode = Control.FOCUS_NONE
		UITheme.style_chrome(toggle_button)
		toggle_button.pressed.connect(_on_decor_toggle.bind(decor_id))
		row.add_child(toggle_button)

		var slot_button := Button.new()
		slot_button.text = "换位"
		slot_button.focus_mode = Control.FOCUS_NONE
		slot_button.tooltip_text = "在左 / 中 / 右之间切换"
		UITheme.style_chrome(slot_button)
		slot_button.pressed.connect(_on_decor_move.bind(decor_id))
		row.add_child(slot_button)

func _decor_pref(decor_id: String) -> Dictionary:
	var prefs: Dictionary = save_data.get("aquarium_decor", {})
	var pref: Dictionary = prefs.get(decor_id, {"on": true, "slot": 0})
	prefs[decor_id] = pref
	save_data["aquarium_decor"] = prefs
	return pref

func _on_decor_toggle(decor_id: String) -> void:
	var pref := _decor_pref(decor_id)
	pref["on"] = not bool(pref.get("on", true))
	_save_now()
	_refresh_aquarium()
	_render_ledger()

func _on_decor_move(decor_id: String) -> void:
	var pref := _decor_pref(decor_id)
	pref["slot"] = (int(pref.get("slot", 0)) + 1) % AquariumView.DECOR_SLOTS.size()
	_save_now()
	_refresh_aquarium()
	_render_ledger()

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

		var first := String((save_data.get("first_caught", {}) as Dictionary).get(fish_id, ""))
		if count > 0 and first != "":
			var first_label := Label.new()
			first_label.text = "首次钓获 %s" % first
			first_label.add_theme_font_size_override("font_size", 11)
			first_label.add_theme_color_override("font_color", UITheme.INK_FAINT)
			row.add_child(first_label)
			row.custom_minimum_size = Vector2(0, 68)

func _rarity_name(rarity: String) -> String:
	match rarity:
		"uncommon":
			return "少见"
		"rare":
			return "稀有"
		"milestone":
			return "限定"
		_:
			return "常见"

func _rarity_color(rarity: String) -> Color:
	match rarity:
		"uncommon":
			return Color(0.22, 0.45, 0.21)
		"rare":
			return Color(0.55, 0.27, 0.63)
		"milestone":
			return Color(0.85, 0.62, 0.15)
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
		save_data["tree_stage"] = tree_manager.pond_tree_stage()
	_update_stats()
	save_manager.save_game(save_data)
