extends PanelContainer
class_name PomodoroTimer

signal focus_completed
signal break_completed
signal timer_tick(seconds_shown: int)
signal state_changed(state: String)
signal settings_changed(settings: Dictionary)

const MIN_FOCUS_MINUTES = 1
const MAX_FOCUS_MINUTES = 180
const MIN_BREAK_MINUTES = 1
const MAX_BREAK_MINUTES = 60
# 正计时：不设目标，甩杆后从 0 往上数，自己点「收竿」结算。
# 和倒计时的下限 / 上限一致：满 1 分钟才算一次专注，数到 180 分钟自动收竿。
const COUNT_UP_MIN_SECONDS = MIN_FOCUS_MINUTES * 60
const COUNT_UP_CAP_SECONDS = MAX_FOCUS_MINUTES * 60

var state := "idle"
var paused_from_state := "idle"
# Web 上页面切后台会被浏览器整体冻结，逐秒递减会丢时间；
# 记录截止时间戳，每次 tick 按真实时钟重算剩余秒数。桌面端保持原逻辑不变。
var _wall_clock := OS.has_feature("web")
var _deadline_unix := 0.0
var _start_unix := 0.0
var focus_seconds := 25 * 60
var break_seconds := 5 * 60
var seconds_left := focus_seconds
var active_duration_seconds := focus_seconds
var count_up := false
var elapsed_seconds := 0
# 最近一次完成的专注有多长（秒）：倒计时 = 设定时长，正计时 = 实际时长。贝壳按它算。
var last_focus_seconds := 0
var mode_label: Label
var mode_switch: SegmentedControl
var time_label: Label
var progress_bar: ProgressBar
var focus_label: Label
var focus_spin: Stepper
var break_spin: Stepper
var start_button: Button
var pause_button: Button
var reset_button: Button
var countdown_timer: Timer

func _ready() -> void:
	_build_ui()
	_apply_state("idle")

func setup(settings: Dictionary) -> void:
	var focus_minutes: int = clamp(int(settings.get("focus_minutes", 25)), MIN_FOCUS_MINUTES, MAX_FOCUS_MINUTES)
	var break_minutes: int = clamp(int(settings.get("break_minutes", 5)), MIN_BREAK_MINUTES, MAX_BREAK_MINUTES)
	focus_seconds = focus_minutes * 60
	break_seconds = break_minutes * 60
	seconds_left = focus_seconds
	active_duration_seconds = focus_seconds
	count_up = bool(settings.get("count_up", false))
	elapsed_seconds = 0
	if time_label == null:
		_build_ui()
	_set_spin_values(focus_minutes, break_minutes)
	_apply_state(state)
	_update_time_label()

func start_focus() -> void:
	if state == "focusing" or state == "break":
		return
	if state == "paused":
		# 专注中暂停的：甩杆等同「继续」，保留已走的进度
		if paused_from_state == "focusing":
			pause_or_resume()
			return
		# 休息中暂停的：视为放弃休息，开启一次全新专注；
		# 不能沿用剩余的休息秒数，否则几分钟就能白拿一次专注奖励
		seconds_left = focus_seconds
		active_duration_seconds = focus_seconds
	if state == "idle" or state == "completed":
		seconds_left = focus_seconds
		active_duration_seconds = focus_seconds
	elapsed_seconds = 0
	_arm_clock()
	_apply_state("focusing")
	_update_time_label()
	countdown_timer.start()

# 正计时专注中（含暂停）：点「收竿」结算。不满 1 分钟算空竿，回到待机、没有收获。
func finish_count_up() -> void:
	if not count_up or _focus_state() != "focusing":
		return
	countdown_timer.stop()
	if elapsed_seconds < COUNT_UP_MIN_SECONDS:
		reset_timer()
		mode_label.text = "不满 1 分钟，空竿了"
		return
	_complete_focus(elapsed_seconds)

func set_count_up(on: bool) -> void:
	# 跑起来以后不许换方式，和专注 / 休息时长一样锁定
	if on == count_up or not (state == "idle" or state == "completed"):
		if mode_switch:
			mode_switch.set_selected_no_signal(1 if count_up else 0)
		return
	count_up = on
	elapsed_seconds = 0
	_apply_state(state)
	_update_time_label()
	_emit_settings()

# 时间框里显示的秒数：正计时专注显示已走的，其余（倒计时 / 休息）显示剩下的。
func display_seconds() -> int:
	return elapsed_seconds if _counting_up() else seconds_left

func pause_or_resume() -> void:
	if state == "focusing" or state == "break":
		paused_from_state = state
		countdown_timer.stop()
		_apply_state("paused")
	elif state == "paused":
		_arm_clock()
		_apply_state(paused_from_state)
		countdown_timer.start()

func reset_timer() -> void:
	countdown_timer.stop()
	seconds_left = focus_seconds
	active_duration_seconds = focus_seconds
	elapsed_seconds = 0
	_apply_state("idle")
	_update_time_label()

func _on_timeout() -> void:
	if state != "focusing" and state != "break":
		return
	if _counting_up():
		if _wall_clock:
			elapsed_seconds = maxi(0, int(Time.get_unix_time_from_system() - _start_unix))
		else:
			elapsed_seconds += 1
		elapsed_seconds = mini(elapsed_seconds, COUNT_UP_CAP_SECONDS)
		timer_tick.emit(elapsed_seconds)
		_update_time_label()
		if elapsed_seconds >= COUNT_UP_CAP_SECONDS:
			countdown_timer.stop()
			_complete_focus(elapsed_seconds)
		return
	if _wall_clock:
		seconds_left = maxi(0, int(ceil(_deadline_unix - Time.get_unix_time_from_system())))
	else:
		seconds_left -= 1
	timer_tick.emit(seconds_left)
	_update_time_label()
	if seconds_left <= 0:
		countdown_timer.stop()
		if state == "focusing":
			_complete_focus(active_duration_seconds)
		else:
			break_completed.emit()
			seconds_left = focus_seconds
			elapsed_seconds = 0
			# 同步基准时长，否则休息比专注长时，回到待机后进度条会残留一截
			active_duration_seconds = focus_seconds
			_apply_state("idle")
			_update_time_label()

func _complete_focus(duration_seconds: int) -> void:
	last_focus_seconds = duration_seconds
	_apply_state("completed")
	focus_completed.emit()
	_start_break()

# 开始 / 继续计时前记下真实时钟：倒计时记截止时刻，正计时记起点（已走的秒数折算回去）
func _arm_clock() -> void:
	var now := Time.get_unix_time_from_system()
	_deadline_unix = now + seconds_left
	_start_unix = now - elapsed_seconds

# 暂停时按暂停前的状态算：专注中暂停的仍属于专注
func _focus_state() -> String:
	return paused_from_state if state == "paused" else state

func _counting_up() -> bool:
	return count_up and _focus_state() != "break"

func _start_break() -> void:
	seconds_left = break_seconds
	active_duration_seconds = break_seconds
	_deadline_unix = Time.get_unix_time_from_system() + seconds_left
	_apply_state("break")
	_update_time_label()
	countdown_timer.start()

func _build_ui() -> void:
	if countdown_timer != null:
		return
	add_theme_stylebox_override("panel", UITheme.panel_style())

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var title_row := HBoxContainer.new()
	root.add_child(title_row)

	var title := Label.new()
	title.text = "专注钓竿"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", UITheme.INK)
	title_row.add_child(title)

	# 倒计时 / 正计时：苹果式分段控件嵌在标题行里，不额外占一行高度
	mode_switch = SegmentedControl.new()
	mode_switch.setup(["倒计时", "正计时"])
	mode_switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mode_switch.changed.connect(func(i: int): set_count_up(i == 1))
	title_row.add_child(mode_switch)

	mode_label = Label.new()
	mode_label.add_theme_color_override("font_color", UITheme.INK_SOFT)
	# 提示文字长短不一，放不下就省略，不能撑宽面板把任务区挤出窗口
	mode_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(mode_label)

	var settings_grid := GridContainer.new()
	settings_grid.columns = 2
	settings_grid.add_theme_constant_override("h_separation", 8)
	settings_grid.add_theme_constant_override("v_separation", 4)
	root.add_child(settings_grid)

	focus_label = Label.new()
	focus_label.text = "专注"
	focus_label.add_theme_color_override("font_color", UITheme.INK_SOFT)
	settings_grid.add_child(focus_label)

	# 「− 25 分钟 +」步进器：加减和数值在同一块浅底里；中间能直接输入，滚轮 / 按住 ± 也能调
	focus_spin = Stepper.new()
	focus_spin.min_value = MIN_FOCUS_MINUTES
	focus_spin.max_value = MAX_FOCUS_MINUTES
	focus_spin.suffix = " 分钟"
	focus_spin.set_value_no_signal(25)
	focus_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_spin.value_changed.connect(func(_value: float): _on_duration_changed())
	settings_grid.add_child(focus_spin)

	var break_label := Label.new()
	break_label.text = "休息"
	break_label.add_theme_color_override("font_color", UITheme.INK_SOFT)
	settings_grid.add_child(break_label)

	break_spin = Stepper.new()
	break_spin.min_value = MIN_BREAK_MINUTES
	break_spin.max_value = MAX_BREAK_MINUTES
	break_spin.suffix = " 分钟"
	break_spin.set_value_no_signal(5)
	break_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	break_spin.value_changed.connect(func(_value: float): _on_duration_changed())
	settings_grid.add_child(break_spin)

	time_label = Label.new()
	time_label.add_theme_font_size_override("font_size", 34)
	time_label.add_theme_color_override("font_color", UITheme.INK)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(time_label)

	progress_bar = ProgressBar.new()
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.value = 0
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(0, 6)
	UITheme.style_progress(progress_bar)
	root.add_child(progress_bar)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	root.add_child(buttons)

	start_button = Button.new()
	start_button.text = "甩杆"
	start_button.tooltip_text = "甩杆并开始一次专注"
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_primary(start_button)
	start_button.pressed.connect(_on_start_pressed)
	buttons.add_child(start_button)

	pause_button = Button.new()
	pause_button.text = "暂停"
	pause_button.tooltip_text = "暂停或继续"
	pause_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pause_button.pressed.connect(pause_or_resume)
	buttons.add_child(pause_button)

	reset_button = Button.new()
	reset_button.text = "重置"
	reset_button.tooltip_text = "收竿重来"
	reset_button.pressed.connect(reset_timer)
	buttons.add_child(reset_button)

	countdown_timer = Timer.new()
	countdown_timer.wait_time = 1.0
	countdown_timer.one_shot = false
	countdown_timer.timeout.connect(_on_timeout)
	add_child(countdown_timer)
	_update_time_label()

func _apply_state(new_state: String) -> void:
	state = new_state
	if mode_label:
		match state:
			"focusing":
				mode_label.text = "正计时专注中" if count_up else "专注中"
			"paused":
				mode_label.text = "暂停中"
			"break":
				mode_label.text = "休息中"
			"completed":
				mode_label.text = "已完成"
			_:
				mode_label.text = "准备开始（正计时）" if count_up else "准备开始"
	var settings_editable := state == "idle" or state == "completed"
	# 正计时专注中（含暂停）主按钮变成「收竿」：没有终点，得自己喊停
	var can_reel := count_up and _focus_state() == "focusing"
	if pause_button:
		pause_button.text = "继续" if state == "paused" else "暂停"
		pause_button.disabled = state == "idle" or state == "completed"
	if start_button:
		start_button.disabled = state == "break" or (state == "focusing" and not can_reel)
		start_button.text = "休息中" if state == "break" else ("收竿" if can_reel else "甩杆")
		start_button.tooltip_text = "结束这次专注并结算（满 1 分钟才有收获）" if can_reel else "甩杆并开始一次专注"
	if reset_button:
		reset_button.disabled = state == "idle"
	if mode_switch:
		mode_switch.set_selected_no_signal(1 if count_up else 0)
		mode_switch.set_tooltip(("正计时：从 0 往上数，自己收竿" if count_up else "倒计时：按设定的专注时长") + ("" if settings_editable else "\n（计时中不能切换）"))
		mode_switch.set_enabled(settings_editable)
	# 正计时没有目标时长，专注分钟数用不上，先收起来
	if focus_label:
		focus_label.visible = not count_up
	if focus_spin:
		focus_spin.visible = not count_up
		focus_spin.editable = settings_editable
	if break_spin:
		break_spin.editable = settings_editable
	state_changed.emit(state)

func _on_start_pressed() -> void:
	if count_up and _focus_state() == "focusing":
		finish_count_up()
	else:
		start_focus()

func _update_time_label() -> void:
	if time_label:
		var shown := display_seconds()
		var minutes := int(shown / 60)
		var seconds := shown % 60
		time_label.text = "%02d:%02d" % [minutes, seconds]
	if progress_bar:
		if _counting_up():
			# 正计时没有终点：进度条每分钟走满一圈，看得出钟在走
			progress_bar.value = float(elapsed_seconds % 60) / 60.0 * 100.0
		elif active_duration_seconds <= 0:
			progress_bar.value = 0
		else:
			var elapsed := active_duration_seconds - seconds_left
			progress_bar.value = clamp(float(elapsed) / float(active_duration_seconds) * 100.0, 0.0, 100.0)

func _set_spin_values(focus_minutes: int, break_minutes: int) -> void:
	if focus_spin:
		focus_spin.set_value_no_signal(focus_minutes)
	if break_spin:
		break_spin.set_value_no_signal(break_minutes)

func _on_duration_changed() -> void:
	if focus_spin == null or break_spin == null:
		return
	var focus_minutes: int = clamp(int(focus_spin.value), MIN_FOCUS_MINUTES, MAX_FOCUS_MINUTES)
	var break_minutes: int = clamp(int(break_spin.value), MIN_BREAK_MINUTES, MAX_BREAK_MINUTES)
	focus_seconds = focus_minutes * 60
	break_seconds = break_minutes * 60
	if state == "idle" or state == "completed":
		seconds_left = focus_seconds
		active_duration_seconds = focus_seconds
		_update_time_label()
	_emit_settings()

func _emit_settings() -> void:
	settings_changed.emit({
		"focus_minutes": focus_seconds / 60,
		"break_minutes": break_seconds / 60,
		"count_up": count_up
	})
