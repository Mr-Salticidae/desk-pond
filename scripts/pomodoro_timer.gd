extends PanelContainer
class_name PomodoroTimer

signal focus_completed
signal break_completed
signal timer_tick(seconds_left: int)
signal state_changed(state: String)
signal settings_changed(settings: Dictionary)

const MIN_FOCUS_MINUTES = 1
const MAX_FOCUS_MINUTES = 180
const MIN_BREAK_MINUTES = 1
const MAX_BREAK_MINUTES = 60

var state := "idle"
var paused_from_state := "idle"
var focus_seconds := 25 * 60
var break_seconds := 5 * 60
var seconds_left := focus_seconds
var active_duration_seconds := focus_seconds
var mode_label: Label
var time_label: Label
var progress_bar: ProgressBar
var focus_spin: SpinBox
var break_spin: SpinBox
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
	if time_label == null:
		_build_ui()
	_set_spin_values(focus_minutes, break_minutes)
	_update_time_label()

func start_focus() -> void:
	if state == "focusing" or state == "break":
		return
	if state == "idle" or state == "completed":
		seconds_left = focus_seconds
		active_duration_seconds = focus_seconds
	_apply_state("focusing")
	countdown_timer.start()

func pause_or_resume() -> void:
	if state == "focusing" or state == "break":
		paused_from_state = state
		countdown_timer.stop()
		_apply_state("paused")
	elif state == "paused":
		_apply_state(paused_from_state)
		countdown_timer.start()

func reset_timer() -> void:
	countdown_timer.stop()
	seconds_left = focus_seconds
	active_duration_seconds = focus_seconds
	_apply_state("idle")
	_update_time_label()

func _on_timeout() -> void:
	if state != "focusing" and state != "break":
		return
	seconds_left -= 1
	timer_tick.emit(seconds_left)
	_update_time_label()
	if seconds_left <= 0:
		countdown_timer.stop()
		if state == "focusing":
			_apply_state("completed")
			focus_completed.emit()
			_start_break()
		else:
			break_completed.emit()
			seconds_left = focus_seconds
			_apply_state("idle")
			_update_time_label()

func _start_break() -> void:
	seconds_left = break_seconds
	active_duration_seconds = break_seconds
	_apply_state("break")
	_update_time_label()
	countdown_timer.start()

func _build_ui() -> void:
	if countdown_timer != null:
		return
	add_theme_stylebox_override("panel", _panel_style(Color(0.92, 0.88, 0.72), Color(0.37, 0.31, 0.25)))

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var title := Label.new()
	title.text = "专注钓竿"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.22, 0.17, 0.13))
	root.add_child(title)

	mode_label = Label.new()
	mode_label.add_theme_color_override("font_color", Color(0.42, 0.31, 0.23))
	root.add_child(mode_label)

	var settings_grid := GridContainer.new()
	settings_grid.columns = 2
	settings_grid.add_theme_constant_override("h_separation", 8)
	settings_grid.add_theme_constant_override("v_separation", 4)
	root.add_child(settings_grid)

	var focus_label := Label.new()
	focus_label.text = "专注"
	focus_label.add_theme_color_override("font_color", Color(0.35, 0.27, 0.20))
	settings_grid.add_child(focus_label)

	focus_spin = SpinBox.new()
	focus_spin.min_value = MIN_FOCUS_MINUTES
	focus_spin.max_value = MAX_FOCUS_MINUTES
	focus_spin.step = 1
	focus_spin.value = 25
	focus_spin.suffix = " 分钟"
	focus_spin.custom_minimum_size = Vector2(102, 0)
	focus_spin.value_changed.connect(func(_value: float): _on_duration_changed())
	settings_grid.add_child(focus_spin)

	var break_label := Label.new()
	break_label.text = "休息"
	break_label.add_theme_color_override("font_color", Color(0.35, 0.27, 0.20))
	settings_grid.add_child(break_label)

	break_spin = SpinBox.new()
	break_spin.min_value = MIN_BREAK_MINUTES
	break_spin.max_value = MAX_BREAK_MINUTES
	break_spin.step = 1
	break_spin.value = 5
	break_spin.suffix = " 分钟"
	break_spin.custom_minimum_size = Vector2(102, 0)
	break_spin.value_changed.connect(func(_value: float): _on_duration_changed())
	settings_grid.add_child(break_spin)

	time_label = Label.new()
	time_label.add_theme_font_size_override("font_size", 32)
	time_label.add_theme_color_override("font_color", Color(0.14, 0.23, 0.24))
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(time_label)

	progress_bar = ProgressBar.new()
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.value = 0
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(0, 12)
	progress_bar.add_theme_stylebox_override("background", _bar_style(Color(0.73, 0.66, 0.50), Color(0.42, 0.32, 0.23)))
	progress_bar.add_theme_stylebox_override("fill", _bar_style(Color(0.26, 0.58, 0.60), Color(0.26, 0.58, 0.60)))
	root.add_child(progress_bar)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	root.add_child(buttons)

	start_button = Button.new()
	start_button.text = "甩杆"
	start_button.tooltip_text = "甩杆并开始一次专注"
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button.pressed.connect(start_focus)
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
				mode_label.text = "专注中"
			"paused":
				mode_label.text = "暂停中"
			"break":
				mode_label.text = "休息中"
			"completed":
				mode_label.text = "已完成"
			_:
				mode_label.text = "准备开始"
	if pause_button:
		pause_button.text = "继续" if state == "paused" else "暂停"
		pause_button.disabled = state == "idle" or state == "completed"
	if start_button:
		start_button.disabled = state == "focusing" or state == "break"
		start_button.text = "休息中" if state == "break" else "甩杆"
	if reset_button:
		reset_button.disabled = state == "idle"
	if focus_spin:
		focus_spin.editable = state == "idle" or state == "completed"
	if break_spin:
		break_spin.editable = state == "idle" or state == "completed"
	state_changed.emit(state)

func _update_time_label() -> void:
	if time_label:
		var minutes := int(seconds_left / 60)
		var seconds := seconds_left % 60
		time_label.text = "%02d:%02d" % [minutes, seconds]
	if progress_bar:
		if active_duration_seconds <= 0:
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
	settings_changed.emit({
		"focus_minutes": focus_minutes,
		"break_minutes": break_minutes
	})

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

func _bar_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style
