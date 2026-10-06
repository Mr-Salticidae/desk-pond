extends Control

const SaveManagerScript = preload("res://scripts/save_manager.gd")
const FishingManagerScript = preload("res://scripts/fishing_manager.gd")
const TreeManagerScript = preload("res://scripts/tree_manager.gd")
const PixelWorldScene = preload("res://scenes/PixelWorld.tscn")
const PomodoroPanelScene = preload("res://scenes/PomodoroPanel.tscn")
const TaskPanelScene = preload("res://scenes/TaskPanel.tscn")
const ICON_SPEAKER_ON := preload("res://assets/speaker_on.png")
const ICON_SPEAKER_OFF := preload("res://assets/speaker_off.png")
const ICON_PIN_ON := preload("res://assets/pin_on.png")
const ICON_PIN_OFF := preload("res://assets/pin_off.png")

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
var aqua_subtab_panel: PanelContainer
var aqua_subtab_bar: HBoxContainer
var aqua_subtabs: Dictionary = {}
var aquarium_submode := "tank"

# 生态缸：贝壳 / 布置 / 商店 / 生态报告
var eco: EcoTank
var eco_eval: Dictionary = {}
var _eco_back_pay := 0
var shells_button: Button
var shop: TankShop
var eco_report: EcoReport
var eco_guide: UICard
var share_card: ShareCard

# 逛朋友的缸（打开分享链接 / 粘贴分享码）
var visit_layer: Control
var visit_box: VBoxContainer
var visit_header: PanelContainer
var visit_view: AquariumView
var visit_title: Label
var visit_sub: Label
var _intro_pending := false

# 全屏（收起底部控制台，让房间占满窗口 / 手机整屏）
var root_box: VBoxContainer
var top_bar_panel: PanelContainer
var bottom_margin: MarginContainer
var full_view := false
var _full_view_before_edit := false
var full_view_button: Button
var aqua_full_button: Button
var timer_chip: PanelContainer
var timer_chip_label: Label

var _dragging_window: bool = false
var _drag_anchor: Vector2i = Vector2i.ZERO

# 无边框窗口没有系统边框可拖：右边、下边、右下角各留一条拖拽区来调整大小。
# 内容按 640×520 设计尺寸等比放大（project.godot 里 stretch aspect = expand），
# 比例不一致时多出来的宽 / 高留给场景。
const RESIZE_BAND := 5.0
const RESIZE_GRIP := 14.0
var _resizing := false
var _resize_dir := Vector2i.ZERO      # (1, 0) 拖右边，(0, 1) 拖下边，(1, 1) 拖右下角
var _resize_anchor := Vector2i.ZERO   # 按下时鼠标的屏幕坐标
var _resize_start_size := Vector2i.ZERO

# Web 版（B站 toy / 手机浏览器）：竖屏布局，去掉桌面窗口专属功能。
# 桌面端调试手机布局：godot --path . -- --web-layout [--web-size=390x844] [--safe-area=44,0,34,0]
var is_web := OS.has_feature("web") or OS.get_cmdline_user_args().has("--web-layout")
const WEB_DESIGN_SIZE := Vector2i(400, 720)
# 可见宽度达到这个值（平板横屏 / 桌面浏览器）时，控制台改回左右并排
const WEB_WIDE_LAYOUT := 600.0

var bottom_box: BoxContainer

func _ready() -> void:
	if is_web:
		get_window().content_scale_size = WEB_DESIGN_SIZE
		# 全面屏：按设计宽度铺满任意长宽比，多出来的高度留给场景（缸更高），不再上下留黑边
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		if not OS.has_feature("web"):
			get_window().size = _debug_web_size()
	else:
		get_window().min_size = Vector2i(640, 520)
	if OS.get_cmdline_user_args().has("--font-debug"):
		print("FONT_DEBUG\n" + UITheme.font_debug_report())
	save_manager = SaveManagerScript.new()
	fishing_manager = FishingManagerScript.new()
	tree_manager = TreeManagerScript.new()
	save_data = save_manager.load_save()
	_apply_theme()
	_build_ui()
	_setup_modules()
	_apply_window_settings()
	_restore_window_size()
	_start_day_watch()
	# 从朋友的分享链接进来：先带他逛朋友的缸，玩法说明等回到自己池塘再弹
	var incoming := WebShell.take_incoming_code()
	var friend := EcoShare.decode(incoming, eco) if incoming != "" else {}
	if not friend.is_empty():
		_intro_pending = true
		call_deferred("_open_visit", friend)
	else:
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
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_check_day_rollover()

# ================= 跨天 =================

# 工位池塘常常整天开着：存档只在启动时判断换天，开过午夜就不会重置当日计数、
# 不结转未完成的任务、活跃天数也不加。这里每分钟（以及切回窗口、专注 / 任务完成时）检查一次。
func _start_day_watch() -> void:
	var timer := Timer.new()
	timer.wait_time = 60.0
	timer.timeout.connect(_check_day_rollover)
	add_child(timer)
	timer.start()

func _check_day_rollover() -> void:
	if save_manager == null or task_panel == null:
		return
	if String(save_data.get("date", "")) == _today():
		return
	# 以面板里的实时任务为准再换天：结转未完成的、清掉已完成的
	save_data["tasks"] = task_panel.get_tasks()
	save_manager.check_new_day(save_data)
	task_panel.setup(save_data.get("tasks", []), 0, save_manager)
	_update_stats()
	_refresh_aquarium()
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
	root_box = root

	top_bar_panel = PanelContainer.new()
	top_bar_panel.custom_minimum_size = Vector2(0, 36)
	top_bar_panel.add_theme_stylebox_override("panel", UITheme.chrome_bar_style())
	if not is_web:
		top_bar_panel.gui_input.connect(_on_title_bar_input)
		top_bar_panel.mouse_default_cursor_shape = Control.CURSOR_MOVE
		top_bar_panel.tooltip_text = "拖动可移动窗口"
	root.add_child(top_bar_panel)

	var top_bar := HBoxContainer.new()
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_theme_constant_override("separation", 2 if is_web else 6)
	top_bar_panel.add_child(top_bar)

	var room_group := ButtonGroup.new()
	_make_room_tab("池塘", "pond", room_group, top_bar)
	_make_room_tab("森林", "forest", room_group, top_bar)
	_make_room_tab("水族馆", "aquarium", room_group, top_bar)

	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 桌面端由 stats_label 充当弹性间隔；Web 上统计隐藏，才需要这个占位
	spacer.visible = is_web
	top_bar.add_child(spacer)

	stats_label = Label.new()
	stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_label.add_theme_font_size_override("font_size", 13)
	stats_label.add_theme_color_override("font_color", Color(0.878, 0.902, 0.855, 0.66))
	# 统计文字同时是顶栏的弹性区：空间不足时先压缩它，
	# 绝不把右侧的最小化 / 关闭按钮挤出窗口
	stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# 竖屏顶栏放不下统计文字，数字都能在「档案」里看到
	stats_label.visible = not is_web
	top_bar.add_child(stats_label)

	shells_button = Button.new()
	shells_button.icon = _shell_texture()
	shells_button.focus_mode = Control.FOCUS_NONE
	shells_button.tooltip_text = "贝壳：专注和完成任务获得，点开水族商店"
	UITheme.style_chrome(shells_button, false, is_web)
	shells_button.pressed.connect(_open_shop)
	top_bar.add_child(shells_button)

	var ledger_button := Button.new()
	ledger_button.text = "档案"
	ledger_button.focus_mode = Control.FOCUS_NONE
	ledger_button.tooltip_text = "查看成长档案与生态缸"
	UITheme.style_chrome(ledger_button, false, is_web)
	ledger_button.pressed.connect(_open_ledger_window)
	top_bar.add_child(ledger_button)

	var help_button := Button.new()
	help_button.text = "?"
	help_button.focus_mode = Control.FOCUS_NONE
	help_button.tooltip_text = "查看玩法说明"
	UITheme.style_chrome(help_button, false, is_web)
	help_button.pressed.connect(_open_help_window)
	top_bar.add_child(help_button)

	mute_button = Button.new()
	mute_button.toggle_mode = true
	mute_button.focus_mode = Control.FOCUS_NONE
	mute_button.tooltip_text = "开关声音"
	UITheme.style_chrome(mute_button, false, is_web)
	var start_muted := bool(save_data["settings"].get("muted", false))
	mute_button.set_pressed_no_signal(start_muted)
	_update_mute_icon(start_muted)
	mute_button.toggled.connect(_on_mute_toggled)
	top_bar.add_child(mute_button)

	# 置顶 / 最小化 / 关闭都是桌面窗口概念，Web 里没有意义
	if not is_web:
		always_on_top_button = Button.new()
		always_on_top_button.toggle_mode = true
		always_on_top_button.focus_mode = Control.FOCUS_NONE
		always_on_top_button.tooltip_text = "窗口置顶"
		UITheme.style_chrome(always_on_top_button)
		var start_pinned := bool(save_data["settings"].get("always_on_top", false))
		always_on_top_button.set_pressed_no_signal(start_pinned)
		_update_pin_icon(start_pinned)
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
	# 桌面高度预算：顶栏 48 + 场景 + 控制台 280 ≤ 窗口最小高度 520。
	# 场景最小高度再大，整列就会比窗口高，控制台底边被裁掉
	scene_area.custom_minimum_size = Vector2(0, 200) if is_web else Vector2(0, 180)
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

	# 水族馆内的子标签：鱼缸 / 图鉴。悬浮在场景区右上角，
	# 不占顶栏——顶栏一旦放不下，会把最右侧的窗口按钮挤出屏幕。
	aqua_subtab_panel = PanelContainer.new()
	aqua_subtab_panel.add_theme_stylebox_override("panel", UITheme.chrome_bar_style())
	aqua_subtab_panel.visible = false
	aqua_subtab_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
	aqua_subtab_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	aqua_subtab_panel.grow_vertical = Control.GROW_DIRECTION_END
	scene_area.add_child(aqua_subtab_panel)

	aqua_subtab_bar = HBoxContainer.new()
	aqua_subtab_bar.add_theme_constant_override("separation", 4)
	aqua_subtab_panel.add_child(aqua_subtab_bar)
	var sub_group := ButtonGroup.new()
	_make_aqua_subtab("鱼缸", "tank", sub_group, aqua_subtab_bar)
	_make_aqua_subtab("图鉴", "catalog", sub_group, aqua_subtab_bar)
	_make_aqua_subtab("布置", "edit", sub_group, aqua_subtab_bar)
	aqua_subtabs["edit"].tooltip_text = "摆放水草和装饰、逛商店"
	var share_button := Button.new()
	share_button.text = "分享"
	share_button.focus_mode = Control.FOCUS_NONE
	share_button.tooltip_text = "生成缸的卡片和链接，发给朋友来逛；也能去朋友家看看"
	UITheme.style_chrome(share_button)
	share_button.pressed.connect(_open_share)
	aqua_subtab_bar.add_child(share_button)
	aqua_full_button = Button.new()
	aqua_full_button.text = "全屏"
	aqua_full_button.focus_mode = Control.FOCUS_NONE
	UITheme.style_chrome(aqua_full_button)
	aqua_full_button.pressed.connect(func(): _set_full_view(not full_view))
	aqua_subtab_bar.add_child(aqua_full_button)

	_build_full_view_ui()
	aqua_subtabs["tank"].set_pressed_no_signal(true)

	bottom_margin = MarginContainer.new()
	bottom_margin.custom_minimum_size = Vector2(0, 280)
	# 桌面窗口拉高时，多出来的高度全给场景（池塘 / 鱼缸更大），控制台保持原高
	bottom_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL if is_web else Control.SIZE_FILL
	bottom_margin.add_theme_constant_override("margin_left", 8)
	bottom_margin.add_theme_constant_override("margin_right", 8)
	bottom_margin.add_theme_constant_override("margin_top", 8)
	bottom_margin.add_theme_constant_override("margin_bottom", 8)
	root.add_child(bottom_margin)

	# 桌面横排：钓竿 | 任务；Web 竖屏改为上下堆叠（横屏够宽时再并排，见 _apply_web_layout）
	var bottom := BoxContainer.new()
	bottom_box = bottom
	bottom.vertical = is_web
	bottom.add_theme_constant_override("separation", 8)
	bottom_margin.add_child(bottom)

	pomodoro_panel = PomodoroPanelScene.instantiate()
	pomodoro_panel.custom_minimum_size = Vector2.ZERO if is_web else Vector2(230, 0)
	pomodoro_panel.size_flags_horizontal = Control.SIZE_FILL
	bottom.add_child(pomodoro_panel)

	task_panel = TaskPanelScene.instantiate()
	# 桌面宽度预算：边距 8 + 钓竿 230 + 间隔 8 + 任务 386 + 边距 8 = 窗口最小宽度 640。
	# 超过一点整列就比窗口宽，任务区右侧的按钮会被裁掉（issue #1 同类问题）
	task_panel.custom_minimum_size = Vector2.ZERO if is_web else Vector2(386, 0)
	task_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL if not is_web else Control.SIZE_FILL
	task_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.add_child(task_panel)

	reward_popup = RewardPopup.new()
	add_child(reward_popup)
	_build_help_window()
	_build_ledger_window()
	_build_eco_windows()
	_build_visit_layer()
	_build_resize_handles()

	room_tabs["pond"].set_pressed_no_signal(true)
	_switch_room("pond")

	if is_web:
		WebShell.safe_area_changed.connect(func(_i: Dictionary): _apply_web_layout())
		get_tree().root.size_changed.connect(_apply_web_layout)
		_apply_web_layout()

func _setup_modules() -> void:
	fishing_manager.set_fish_count(save_data.get("fish_count", {}))
	tree_manager.set_growth_points(int(save_data.get("tree_growth_points", 0)))

	# 生态缸绑定存档里的 eco 字典（按引用修改）；老玩家第一次打开时把过去的努力折成贝壳
	eco = EcoTank.new()
	eco.bind(save_data["eco"], fishing_manager.get_fish_data())
	_eco_back_pay = eco.migrate_legacy(save_data, _eco_ctx())
	eco.grant_gifts(_eco_ctx())
	eco.accrue_pearls(_today())

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
	pomodoro_panel.timer_tick.connect(func(_s: int): _update_timer_chip())
	aquarium_view.layout_changed.connect(_on_tank_layout_changed)
	aquarium_view.pearl_tapped.connect(_on_pearl_tapped)
	aquarium_view.shop_requested.connect(_open_shop)
	aquarium_view.report_requested.connect(_open_eco_report)
	aquarium_view.edit_mode_changed.connect(_on_tank_edit_mode_changed)
	aquarium_view.resized.connect(_sync_aqua_subtab)   # 布置途中转屏：宽窄变了，标签条跟着收 / 放
	shop.changed.connect(_on_shop_changed)

	_on_tree_growth_changed(tree_manager.growth_points)
	_update_stats()
	_render_collection()
	_refresh_aquarium()
	_save_now()

func _on_focus_completed() -> void:
	_check_day_rollover()
	save_data["pomodoro_completed"] = int(save_data.get("pomodoro_completed", 0)) + 1
	save_data["total_focus_sessions"] = int(save_data.get("total_focus_sessions", 0)) + 1
	var fish := fishing_manager.roll_reward({
		"total_sessions": int(save_data["total_focus_sessions"])
	})
	save_data["fish_count"] = fishing_manager.get_fish_count()
	_record_first_caught(String(fish.get("id", "")))

	# 生态缸：按专注分钟给贝壳；达成里程碑送装饰；条件满足的访客趁这次专注游进来
	var extras: Array = []
	var shells := eco.focus_reward(pomodoro_panel.last_focus_seconds / 60)
	if shells > 0:
		extras.append("+%d 贝壳" % shells)
	else:
		extras.append("专注满 5 分钟才会有贝壳哦")
	var ctx := _eco_ctx()
	for gift in eco.grant_gifts(ctx):
		extras.append("里程碑赠礼：%s，已经摆进缸里" % String(gift.get("name", "")))
	for v in eco.arrive_visitors(eco.evaluate(ctx), _today()):
		extras.append("%s游进了你的缸！谢礼 +%d 贝壳" % [String(v.get("name", "")), int(v.get("gift", 0))])
	eco.accrue_pearls(_today())

	pixel_world.play_focus_feedback()
	reward_popup.show_reward(fish, extras)
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
	if eco.task_reward(_today()) > 0:
		_flash_shells()
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
	# 树长大可能解锁沉木 / 苔藓球，商店开着就顺手刷新
	if shop and eco:
		shop.refresh(_eco_ctx())
	_update_stats()

func _make_room_tab(text: String, room_id: String, group: ButtonGroup, parent: Control) -> Button:
	var tab := Button.new()
	tab.text = text
	tab.toggle_mode = true
	tab.button_group = group
	tab.focus_mode = Control.FOCUS_NONE
	UITheme.style_chrome(tab, false, is_web)
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
		if not on:
			return
		# 不在水族馆时只记下子模式（例如布置中直接切去池塘，会回落到「鱼缸」），不要把缸显示出来
		if current_room == "aquarium":
			_set_aqua_submode(mode)
		else:
			aquarium_submode = mode
	)
	parent.add_child(tab)
	aqua_subtabs[mode] = tab
	return tab

func _switch_room(room: String) -> void:
	current_room = room
	_update_full_view_chip()
	if pixel_world:
		pixel_world.visible = room == "pond"
	if forest_view:
		forest_view.visible = room == "forest"
		if room == "forest":
			forest_view.update_forest(tree_manager)
	var in_aqua := room == "aquarium"
	_sync_aqua_subtab()
	if in_aqua:
		_set_aqua_submode(aquarium_submode)
		_maybe_show_eco_guide()
	else:
		if aquarium_view:
			aquarium_view.visible = false
		if catalog_view:
			catalog_view.visible = false

# 水族馆子标签条只在水族馆显示；手机竖屏布置时收起，把顶部让给布置工具条（「完成」退出后恢复）
func _sync_aqua_subtab() -> void:
	if aqua_subtab_panel == null:
		return
	var editing_narrow := aquarium_view != null and aquarium_view.edit_mode and aquarium_view.is_narrow()
	aqua_subtab_panel.visible = current_room == "aquarium" and not editing_narrow

func _set_aqua_submode(mode: String) -> void:
	aquarium_submode = mode
	var show_tank := mode != "catalog"
	if aquarium_view:
		aquarium_view.visible = show_tank
		if show_tank:
			_refresh_aquarium()
			aquarium_view.set_edit_mode(mode == "edit")
	if catalog_view:
		catalog_view.visible = not show_tank
		if not show_tank:
			_render_collection()

func _refresh_aquarium() -> void:
	if aquarium_view == null or eco == null:
		return
	eco.accrue_pearls(_today())
	eco_eval = eco.evaluate(_eco_ctx())
	aquarium_view.update_tank(eco, eco_eval, _eco_names(), _species_levels())
	_update_shells()

func _on_timer_state_changed(state: String) -> void:
	if state == "focusing":
		Audio.play_cast()
	if pixel_world:
		pixel_world.set_activity_state(state)
	_update_timer_chip()

func _on_timer_settings_changed(settings: Dictionary) -> void:
	save_data["settings"]["focus_minutes"] = int(settings.get("focus_minutes", save_data["settings"].get("focus_minutes", 25)))
	save_data["settings"]["break_minutes"] = int(settings.get("break_minutes", save_data["settings"].get("break_minutes", 5)))
	save_data["settings"]["count_up"] = bool(settings.get("count_up", save_data["settings"].get("count_up", false)))
	_save_now()

func _on_cast_requested() -> void:
	if pomodoro_panel:
		pomodoro_panel.start_focus()

func _on_mute_toggled(muted: bool) -> void:
	_update_mute_icon(muted)
	save_data["settings"]["muted"] = muted
	Audio.set_muted(muted)
	_save_now()

func _update_mute_icon(muted: bool) -> void:
	if mute_button:
		mute_button.icon = ICON_SPEAKER_OFF if muted else ICON_SPEAKER_ON

func _on_always_on_top_toggled(enabled: bool) -> void:
	_update_pin_icon(enabled)
	save_data["settings"]["always_on_top"] = enabled
	_apply_window_settings()
	_save_now()

# 置顶用颜色区分：未置顶=灰图钉，已置顶=彩色红图钉（点亮）
func _update_pin_icon(pinned: bool) -> void:
	if always_on_top_button:
		always_on_top_button.icon = ICON_PIN_ON if pinned else ICON_PIN_OFF

func _apply_window_settings() -> void:
	if is_web:
		return
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

# ================= 窗口缩放 =================

func _build_resize_handles() -> void:
	if is_web:
		return
	var right := _make_resize_handle(Vector2i(1, 0), Control.CURSOR_HSIZE)
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.anchor_bottom = 1.0
	right.offset_left = -RESIZE_BAND
	var bottom := _make_resize_handle(Vector2i(0, 1), Control.CURSOR_VSIZE)
	bottom.anchor_top = 1.0
	bottom.anchor_right = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_top = -RESIZE_BAND
	# 右下角：带三道斜纹的小手柄，看得出这里能拖
	var grip := _make_resize_handle(Vector2i(1, 1), Control.CURSOR_FDIAGSIZE)
	grip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	grip.offset_left = -RESIZE_GRIP
	grip.offset_top = -RESIZE_GRIP
	grip.draw.connect(func():
		var c := Color(UITheme.INK_FAINT, 0.8)
		for i in range(3):
			var d := 4.0 + i * 4.0
			grip.draw_line(Vector2(RESIZE_GRIP - d, RESIZE_GRIP - 2.0), Vector2(RESIZE_GRIP - 2.0, RESIZE_GRIP - d), c, 1.0)
	)

func _make_resize_handle(dir: Vector2i, cursor: Control.CursorShape) -> Control:
	var handle := Control.new()
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = cursor
	handle.gui_input.connect(_on_resize_input.bind(dir))
	add_child(handle)
	return handle

func _on_resize_input(event: InputEvent, dir: Vector2i) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_resizing = event.pressed
		if event.pressed:
			_resize_dir = dir
			_resize_anchor = DisplayServer.mouse_get_position()
			_resize_start_size = get_window().size
		else:
			_remember_window_size()
	elif event is InputEventMouseMotion and _resizing:
		var delta := DisplayServer.mouse_get_position() - _resize_anchor
		var target := _resize_start_size + Vector2i(delta.x * _resize_dir.x, delta.y * _resize_dir.y)
		get_window().size = _clamp_window_size(target)

# 不小于设计尺寸，也不超出桌面：窗口右下角最多拉到所在桌面区域的边上
func _clamp_window_size(target: Vector2i) -> Vector2i:
	var win := get_window()
	var area := _virtual_usable_rect()
	var max_size := (area.end - win.position).max(win.min_size)
	return target.clamp(win.min_size, max_size)

func _remember_window_size() -> void:
	var s := get_window().size
	save_data["settings"]["window_size"] = [s.x, s.y]
	_save_now()

func _restore_window_size() -> void:
	if is_web:
		return
	var saved: Variant = save_data["settings"].get("window_size", [])
	if typeof(saved) != TYPE_ARRAY or saved.size() != 2:
		return
	var win := get_window()
	var area := DisplayServer.screen_get_usable_rect(win.current_screen)
	var target := Vector2i(int(saved[0]), int(saved[1])).clamp(win.min_size, area.size.max(win.min_size))
	if target == win.size:
		return
	win.size = target
	win.move_to_center()

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
	# 上边距避开悬浮在场景区右上角的「鱼缸 / 图鉴」子标签条
	margin.add_theme_constant_override("margin_top", 52)
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
	card.configure("玩法说明", Vector2i(440, 470))
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
		"钓竿右上角可切换“倒计时 / 正计时”：正计时从 0 往上数，想停时点“收竿”，满 1 分钟就有收获。",
		"专注完成会自动钓获奖励，并进入休息倒计时。",
		"写下今日任务，完成任务会让森林里多长一棵树。",
		"专注（满 5 分钟）和完成任务都会得到贝壳，顶栏点贝壳就能逛商店。",
		"水族馆点“布置”：把买来的水草、石头、装饰拖进缸里，上下拖改前后。",
		"缸里的氧气、水质、美观决定生态星级；星级越高，解锁越多，还会引来访客。",
		"点水面喂鱼，点鱼看它是谁；缸里冒出的珍珠泡泡，点一下收集贝壳。",
		"“全屏”收起下方控制台，让场景占满屏幕（水族馆在右上角，池塘 / 森林在右下角）。",
	]
	if not is_web:
		tips.append("拖动窗口的右边、下边或右下角可以调整窗口大小，下次打开会记住。")
	# 条目多了，手机竖屏（卡片限高 560）放不下，交给滚动容器
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for tip in tips:
		var label := Label.new()
		label.text = "·  %s" % tip
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color", UITheme.INK_SOFT)
		list.add_child(label)

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

	# —— 生态缸 ——
	var eco_title := Label.new()
	eco_title.text = "生态缸"
	eco_title.add_theme_font_size_override("font_size", 15)
	eco_title.add_theme_color_override("font_color", UITheme.INK)
	ledger_body.add_child(eco_title)

	var seen := 0
	for v in eco.visitors:
		if eco.visitor_seen(String(v["id"])):
			seen += 1
	var eco_lines := [
		"贝壳  %d（累计获得 %d）" % [eco.shells(), int(eco.state.get("shells_earned", 0))],
		"鱼缸  %s · 住得下 %d 条" % [String(eco.level_info(eco.tank_level()).get("name", "")), eco.capacity()],
		"生态  当前 %d 星 · 历史最佳 %d 星" % [int(eco_eval.get("stars", 0)), int(eco.state.get("best_stars", 0))],
		"访客  来过 %d / %d 位" % [seen, eco.visitors.size()],
	]
	for line in eco_lines:
		var label := Label.new()
		label.text = line
		label.add_theme_color_override("font_color", UITheme.INK_SOFT)
		ledger_body.add_child(label)

	var go := Button.new()
	go.text = "去布置水缸"
	go.focus_mode = Control.FOCUS_NONE
	UITheme.style_primary(go)
	go.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	go.pressed.connect(func():
		ledger_window.hide()
		_goto_aquarium("edit")
	)
	ledger_body.add_child(go)

func _render_collection() -> void:
	if collection_list == null or fishing_manager == null or eco == null:
		return
	for child in collection_list.get_children():
		child.queue_free()
	var counts := fishing_manager.get_fish_count()
	var caught := 0
	for fish in fishing_manager.get_fish_data():
		if int(counts.get(String(fish.get("id", "")), 0)) > 0:
			caught += 1
	var seen := 0
	for v in eco.visitors:
		if eco.visitor_seen(String(v["id"])):
			seen += 1
	collection_list.add_child(_catalog_header("鱼  %d / %d 种" % [caught, fishing_manager.get_fish_data().size()], "同一种鱼钓得越多等级越高，缸里的它也越大"))

	for fish in fishing_manager.get_fish_data():
		var fish_id := String(fish.get("id", ""))
		var count := int(counts.get(fish_id, 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		collection_list.add_child(row)

		var icon := TankIcon.new().setup("fish", fish_id, count == 0, EcoTank.species_level(count))
		icon.custom_minimum_size = Vector2(46, 34)
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(icon)

		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		row.add_child(col)

		var top_row := HBoxContainer.new()
		top_row.add_theme_constant_override("separation", 8)
		col.add_child(top_row)

		var name_label := Label.new()
		name_label.text = String(fish.get("name", "神秘小鱼")) if count > 0 else "未知钓获"
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_color_override("font_color", UITheme.INK if count > 0 else UITheme.INK_FAINT)
		top_row.add_child(name_label)

		var rarity_label := Label.new()
		rarity_label.text = _rarity_name(String(fish.get("rarity", "common")))
		rarity_label.add_theme_color_override("font_color", _rarity_color(String(fish.get("rarity", "common"))))
		top_row.add_child(rarity_label)

		var count_label := Label.new()
		count_label.text = "×%d" % count
		count_label.custom_minimum_size = Vector2(40, 0)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.add_theme_color_override("font_color", UITheme.POND if count > 0 else UITheme.INK_FAINT)
		top_row.add_child(count_label)

		var description_label := Label.new()
		description_label.text = String(fish.get("description", "")) if count > 0 else "完成专注，看看池塘里会不会遇到它。"
		description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description_label.add_theme_font_size_override("font_size", 12)
		description_label.add_theme_color_override("font_color", UITheme.INK_SOFT if count > 0 else UITheme.INK_FAINT)
		col.add_child(description_label)

		if count == 0:
			continue
		var eco_info: Dictionary = fish.get("eco", {})
		var lv := EcoTank.species_level(count)
		var next := EcoTank.next_level_at(count)
		var meta := "Lv.%d%s · %s" % [lv, "（再钓 %d 条升级）" % (next - count) if next > 0 else "（满级）", String(eco_info.get("trait_desc", ""))]
		var first := String((save_data.get("first_caught", {}) as Dictionary).get(fish_id, ""))
		if first != "":
			meta += " · 首次钓获 " + first
		var meta_label := Label.new()
		meta_label.text = meta
		meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		meta_label.add_theme_font_size_override("font_size", 11)
		meta_label.add_theme_color_override("font_color", UITheme.INK_FAINT)
		col.add_child(meta_label)

		# 入缸开关：让玩家自己决定缸里养谁（影响耗氧 / 水质 / 鱼群）
		var excluded := eco.is_excluded(fish_id)
		var stock := Button.new()
		stock.text = "留池塘" if excluded else "入缸"
		stock.focus_mode = Control.FOCUS_NONE
		stock.tooltip_text = "点一下切换：这种鱼住进水族馆，还是留在池塘里自由游"
		stock.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		if not excluded:
			UITheme.style_primary(stock)
		stock.pressed.connect(func():
			eco.set_excluded(fish_id, not eco.is_excluded(fish_id))
			_save_now()
			_refresh_aquarium()
			_render_collection()
		)
		row.add_child(stock)

	collection_list.add_child(HSeparator.new())
	collection_list.add_child(_catalog_header("访客  %d / %d 位" % [seen, eco.visitors.size()], "布置出它们喜欢的缸，完成专注时就会有客人游进来"))
	var present: Array = eco_eval.get("visitors_present", [])
	for v in eco.visitors:
		var vid := String(v["id"])
		var met := eco.visitor_seen(vid)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		collection_list.add_child(row)
		var icon := TankIcon.new().setup("visitor", vid, not met)
		icon.custom_minimum_size = Vector2(46, 34)
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(icon)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		row.add_child(col)
		var name_label := Label.new()
		if met:
			name_label.text = "%s · %s" % [String(v.get("name", "")), "在缸里" if present.has(vid) else "出门溜达了"]
		else:
			name_label.text = "？？？"
		name_label.add_theme_color_override("font_color", UITheme.INK if met else UITheme.INK_FAINT)
		col.add_child(name_label)
		var desc := Label.new()
		desc.text = String(v.get("desc", "")) if met else "线索：" + String(v.get("hint", ""))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", UITheme.INK_SOFT if met else UITheme.INK_FAINT)
		col.add_child(desc)
		if met:
			var first_visit := Label.new()
			first_visit.text = "初次来访 " + String((eco.state["visitors_first"] as Dictionary).get(vid, ""))
			first_visit.add_theme_font_size_override("font_size", 11)
			first_visit.add_theme_color_override("font_color", UITheme.INK_FAINT)
			col.add_child(first_visit)

func _catalog_header(title: String, note: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 15)
	t.add_theme_color_override("font_color", UITheme.INK)
	box.add_child(t)
	var n := Label.new()
	n.text = note
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.add_theme_font_size_override("font_size", 11)
	n.add_theme_color_override("font_color", UITheme.INK_FAINT)
	box.add_child(n)
	return box

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

# ================= 生态缸 =================

func _today() -> String:
	return save_manager.current_datetime().substr(0, 10)

func _eco_ctx() -> Dictionary:
	return {
		"fish_counts": fishing_manager.get_fish_count(),
		"total_sessions": int(save_data.get("total_focus_sessions", 0)),
		"mature_trees": tree_manager.mature_count(),
	}

func _eco_names() -> Dictionary:
	var out := {}
	for fish in fishing_manager.get_fish_data():
		out[String(fish.get("id", ""))] = String(fish.get("name", ""))
	for v in eco.visitors:
		out[String(v["id"])] = String(v.get("name", ""))
	return out

func _species_levels() -> Dictionary:
	var out := {}
	var counts := fishing_manager.get_fish_count()
	for fid in counts:
		out[fid] = EcoTank.species_level(int(counts[fid]))
	return out

# 顶栏贝壳图标：用 TankArt 同款扇贝，逐像素生成一张小贴图（Web 字体没有 emoji）
func _shell_texture() -> ImageTexture:
	var rows := [
		"....###....",
		"..#######..",
		".##.#.#.##.",
		"###.#.#.###",
		"###.#.#.###",
		".#########.",
		"...#####...",
		"....###....",
	]
	var body := Color(0.96, 0.78, 0.60)
	var rib := Color(0.84, 0.58, 0.42)
	var img := Image.create(rows[0].length(), rows.size(), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(rows.size()):
		var row: String = rows[y]
		for x in range(row.length()):
			if row[x] == "#":
				img.set_pixel(x, y, body)
			elif row[x] == "." and y >= 2 and y <= 4 and x > 0 and x < row.length() - 1:
				img.set_pixel(x, y, rib)
	img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)

func _update_shells() -> void:
	if shells_button and eco:
		shells_button.text = str(eco.shells())

func _flash_shells() -> void:
	_update_shells()
	if shells_button == null:
		return
	shells_button.modulate = Color(1.0, 0.85, 0.45)
	var tw := create_tween()
	tw.tween_property(shells_button, "modulate", Color.WHITE, 0.8)

func _build_eco_windows() -> void:
	shop = TankShop.new()
	add_child(shop)
	eco_report = EcoReport.new()
	add_child(eco_report)
	eco_report.share_requested.connect(func():
		eco_report.hide()
		_open_share()
	)
	share_card = ShareCard.new()
	add_child(share_card)
	share_card.name_changed.connect(func(n: String): eco.state["tank_name"] = n)
	share_card.visit_requested.connect(_on_visit_requested)
	share_card.visibility_changed.connect(func():
		if not share_card.visible:
			_save_now()
	)

func _open_shop() -> void:
	if eco == null:
		return
	shop.open_shop(eco, _eco_ctx())

func _on_shop_changed() -> void:
	_flash_shells()
	_save_now()
	_refresh_aquarium()

func _open_eco_report() -> void:
	if eco_eval.is_empty():
		_refresh_aquarium()
	eco_report.show_report(eco_eval, _eco_names())

func _on_tank_layout_changed() -> void:
	_save_now()
	_refresh_aquarium()

func _on_pearl_tapped(pos: Vector2) -> void:
	var amount := eco.take_pearl()
	if amount <= 0:
		return
	aquarium_view.float_text(pos, "+%d 贝壳" % amount)
	aquarium_view.set_pending_pearls(eco.pearls())
	Audio.play_pearl()
	_flash_shells()
	_save_now()

# 布置时自动全屏（缸越大越好摆），退出布置时恢复原来的样子
func _on_tank_edit_mode_changed(on: bool) -> void:
	if on:
		_full_view_before_edit = full_view
		_set_full_view(true)
	else:
		_set_full_view(_full_view_before_edit)
		if aquarium_submode == "edit":
			aquarium_submode = "tank"
			if aqua_subtabs.has("tank"):
				# 用 button_pressed 而非 set_pressed_no_signal：后者不会让同组其它按钮弹起
				aqua_subtabs["tank"].button_pressed = true
	if aqua_full_button:
		aqua_full_button.visible = not on
	_sync_aqua_subtab()

func _goto_aquarium(mode: String) -> void:
	aquarium_submode = mode
	if current_room == "aquarium":
		_set_aqua_submode(mode)
	room_tabs["aquarium"].button_pressed = true
	aqua_subtabs[mode].button_pressed = true

# 第一次走进水族馆：讲清楚生态缸怎么玩；老玩家额外告知补发的贝壳。
func _maybe_show_eco_guide() -> void:
	if eco == null or bool(eco.state.get("seen_guide", false)):
		return
	eco.state["seen_guide"] = true
	_save_now()
	var card := UICard.new()
	card.configure("生态缸开张啦", Vector2i(400, 400))
	add_child(card)
	eco_guide = card
	var lines: Array = []
	if _eco_back_pay > EcoTank.WELCOME_SHELLS:
		lines.append("你之前的每一次专注和完成的任务，连同开缸礼，一共折成了 %d 个贝壳。" % _eco_back_pay)
	elif _eco_back_pay > 0:
		lines.append("送你 %d 个贝壳当开缸礼，先去商店挑点东西吧。" % _eco_back_pay)
	lines.append_array([
		"这只缸现在归你布置：点「布置」摆放，点「商店」用贝壳买水草、石头、装饰和小生物。",
		"左上角的星星是生态评分：氧气和水质要跟得上鱼的数量，美观来自摆件和主题套组。",
		"星级越高解锁越多；布置出特定的缸，专注完成时还会有访客游进来。",
		"点水面喂鱼，点鱼看名字，珍珠泡泡点一下就能收下。什么都不会死，放心折腾。",
	])
	for line in lines:
		var l := Label.new()
		l.text = "·  " + String(line)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", UITheme.INK_SOFT)
		card.body.add_child(l)
	var ok := Button.new()
	ok.text = "去布置"
	UITheme.style_primary(ok)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func():
		card.hide()
		_goto_aquarium("edit")
	)
	card.body.add_child(ok)
	card.call_deferred("popup_centered")

# ================= 全屏 =================

func _build_full_view_ui() -> void:
	var fv_panel := PanelContainer.new()
	fv_panel.add_theme_stylebox_override("panel", UITheme.chip_style())
	fv_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	fv_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	fv_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	scene_area.add_child(fv_panel)
	full_view_button = Button.new()
	full_view_button.text = "全屏"
	full_view_button.focus_mode = Control.FOCUS_NONE
	full_view_button.tooltip_text = "收起下方控制台，让场景占满窗口"
	UITheme.style_chrome(full_view_button)
	full_view_button.pressed.connect(func(): _set_full_view(not full_view))
	fv_panel.add_child(full_view_button)

	timer_chip = PanelContainer.new()
	timer_chip.add_theme_stylebox_override("panel", UITheme.chip_style())
	timer_chip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 8)
	timer_chip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	timer_chip.visible = false
	timer_chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	timer_chip.tooltip_text = "点这里回到专注台"
	timer_chip.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_set_full_view(false)
	)
	scene_area.add_child(timer_chip)
	timer_chip_label = Label.new()
	timer_chip_label.add_theme_font_size_override("font_size", 13)
	timer_chip_label.add_theme_color_override("font_color", UITheme.INK_ON_CHROME)
	timer_chip.add_child(timer_chip_label)

func _set_full_view(on: bool) -> void:
	full_view = on
	if bottom_margin:
		bottom_margin.visible = not on
	for b in [full_view_button, aqua_full_button]:
		if b:
			b.text = "还原" if on else "全屏"
			b.tooltip_text = "展开专注钓竿和任务" if on else "收起下方控制台，让场景占满窗口"
	_update_full_view_chip()
	_update_timer_chip()

# 浮动的「全屏」胶囊只在池塘 / 森林出现：水族馆的开关在右上角标签条里，
# 否则会压住图鉴的按钮和布置时的库存条。
func _update_full_view_chip() -> void:
	if full_view_button:
		full_view_button.get_parent().visible = current_room != "aquarium"

# 全屏时控制台被收起，用一枚小计时胶囊告诉你专注还剩多久
func _update_timer_chip() -> void:
	if timer_chip == null or pomodoro_panel == null:
		return
	var state := pomodoro_panel.state
	var active := state == "focusing" or state == "break" or state == "paused"
	var editing := aquarium_view != null and aquarium_view.edit_mode
	timer_chip.visible = full_view and active and not editing
	if not timer_chip.visible:
		return
	var names := {"focusing": "专注中", "break": "休息中", "paused": "暂停中"}
	var secs := pomodoro_panel.display_seconds()
	timer_chip_label.text = "%s %02d:%02d" % [String(names.get(state, "")), secs / 60, secs % 60]

# ================= Web 全面屏 =================

func _debug_web_size() -> Vector2i:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--web-size="):
			var parts := arg.trim_prefix("--web-size=").split("x")
			if parts.size() == 2:
				return Vector2i(int(parts[0]), int(parts[1]))
	return WEB_DESIGN_SIZE

# 让出刘海 / 状态栏 / 手势条：顶栏向下加高并保持深色（与状态栏连成一片），
# 其余三边整体内缩；可见区够宽时控制台改为左右并排。
func _apply_web_layout() -> void:
	var inset: Dictionary = WebShell.insets
	if root_box:
		root_box.offset_left = float(inset["left"])
		root_box.offset_right = -float(inset["right"])
		root_box.offset_bottom = -float(inset["bottom"])
	if top_bar_panel:
		var bar := UITheme.chrome_bar_style()
		bar.content_margin_left = 6
		bar.content_margin_right = 4
		bar.content_margin_top += float(inset["top"])
		top_bar_panel.add_theme_stylebox_override("panel", bar)
		top_bar_panel.custom_minimum_size = Vector2(0, 36.0 + float(inset["top"]))
	if visit_box:
		visit_box.offset_left = float(inset["left"])
		visit_box.offset_right = -float(inset["right"])
		visit_box.offset_bottom = -float(inset["bottom"])
		var vbar := UITheme.chrome_bar_style()
		vbar.content_margin_top += float(inset["top"])
		visit_header.add_theme_stylebox_override("panel", vbar)
	if bottom_box:
		var wide := get_viewport().get_visible_rect().size.x >= WEB_WIDE_LAYOUT
		bottom_box.vertical = not wide
		pomodoro_panel.custom_minimum_size = Vector2(230, 0) if wide else Vector2.ZERO
		task_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

# ================= 分享 / 逛朋友的缸 =================

func _open_share() -> void:
	if eco == null:
		return
	_refresh_aquarium()
	share_card.open_card(eco,
		func(tank_name: String) -> Dictionary: return EcoShare.snapshot(eco, eco_eval, _species_levels(), tank_name),
		_eco_names(), fishing_manager.get_fish_data(), String(eco.state.get("tank_name", "")))

func _on_visit_requested(text: String) -> void:
	var friend := EcoShare.decode(text, eco)
	if friend.is_empty():
		share_card.say("这段分享码看不懂……检查一下是不是复制完整了", UITheme.DANGER)
		return
	share_card.hide()
	_open_visit(friend)

func _build_visit_layer() -> void:
	visit_layer = Control.new()
	visit_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visit_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	visit_layer.visible = false
	add_child(visit_layer)
	var bg := ColorRect.new()
	bg.color = UITheme.BG_DEEP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visit_layer.add_child(bg)

	visit_box = VBoxContainer.new()
	visit_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visit_box.add_theme_constant_override("separation", 0)
	visit_layer.add_child(visit_box)

	visit_header = PanelContainer.new()
	visit_header.add_theme_stylebox_override("panel", UITheme.chrome_bar_style())
	visit_box.add_child(visit_header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	visit_header.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	visit_title = Label.new()
	visit_title.text = "来逛朋友的生态缸"
	visit_title.add_theme_font_size_override("font_size", 15)
	visit_title.add_theme_color_override("font_color", UITheme.INK_ON_CHROME)
	col.add_child(visit_title)
	visit_sub = Label.new()
	visit_sub.add_theme_font_size_override("font_size", 12)
	visit_sub.add_theme_color_override("font_color", Color(UITheme.INK_ON_CHROME, 0.66))
	visit_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(visit_sub)
	var back := Button.new()
	back.text = "回我的池塘"
	back.focus_mode = Control.FOCUS_NONE
	UITheme.style_chrome(back)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_close_visit.bind(false))
	row.add_child(back)

	visit_view = AquariumView.new()
	visit_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	visit_box.add_child(visit_view)
	visit_view.set_presentation(true, true, "")

	var footer := PanelContainer.new()
	footer.add_theme_stylebox_override("panel", UITheme.chrome_bar_style())
	visit_box.add_child(footer)
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 8)
	footer.add_child(frow)
	var tip := Label.new()
	tip.text = "点水面帮朋友喂鱼，点鱼看看它是谁"
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 12)
	tip.add_theme_color_override("font_color", UITheme.INK_ON_CHROME)
	frow.add_child(tip)
	var build := Button.new()
	build.text = "我也去搭一只"
	build.focus_mode = Control.FOCUS_NONE
	UITheme.style_primary(build)
	build.pressed.connect(_close_visit.bind(true))
	frow.add_child(build)

func _open_visit(friend: Dictionary) -> void:
	var tank := EcoShare.build_tank(friend, fishing_manager.get_fish_data())
	visit_view.set_presentation(true, true, "「%s」" % EcoShare.display_name(friend))
	visit_view.update_tank(tank, EcoShare.build_eval(friend, tank), _eco_names(), friend.get("levels", {}))
	visit_sub.text = "%d 星 · %s" % [int(friend.get("stars", 0)), EcoShare.summary(friend)]
	visit_layer.visible = true
	if is_web:
		_apply_web_layout()

# build = 「我也去搭一只」：直接带去自己的水族馆（第一次会弹生态缸引导，玩法说明留到下次）
func _close_visit(build: bool) -> void:
	visit_layer.visible = false
	if build:
		_intro_pending = false
		_goto_aquarium("tank")
	elif _intro_pending:
		_intro_pending = false
		_maybe_show_intro()
