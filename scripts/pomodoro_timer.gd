extends PanelContainer
class_name PomodoroTimer

signal focus_completed
signal timer_tick(seconds_left: int)
signal state_changed(state: String)

const DEBUG_FAST_TIMER = true

var state := "idle"
var focus_seconds := 25 * 60
var break_seconds := 5 * 60
var seconds_left := focus_seconds
var mode_label: Label
var time_label: Label
var start_button: Button
var pause_button: Button
var reset_button: Button
var countdown_timer: Timer

func _ready() -> void:
	_build_ui()
	_apply_state("idle")

func setup(settings: Dictionary) -> void:
	if DEBUG_FAST_TIMER:
		focus_seconds = 10
		break_seconds = 5
	else:
		focus_seconds = int(settings.get("focus_minutes", 25)) * 60
		break_seconds = int(settings.get("break_minutes", 5)) * 60
	seconds_left = focus_seconds
	if time_label == null:
		_build_ui()
	_update_time_label()

func start_focus() -> void:
	if state == "focusing":
		return
	if state == "idle" or state == "completed":
		seconds_left = focus_seconds
	_apply_state("focusing")
	countdown_timer.start()

func pause_or_resume() -> void:
	if state == "focusing":
		countdown_timer.stop()
		_apply_state("paused")
	elif state == "paused":
		_apply_state("focusing")
		countdown_timer.start()

func reset_timer() -> void:
	countdown_timer.stop()
	seconds_left = focus_seconds
	_apply_state("idle")
	_update_time_label()

func _on_timeout() -> void:
	if state != "focusing":
		return
	seconds_left -= 1
	timer_tick.emit(seconds_left)
	_update_time_label()
	if seconds_left <= 0:
		countdown_timer.stop()
		_apply_state("completed")
		focus_completed.emit()
		seconds_left = focus_seconds
		_apply_state("idle")
		_update_time_label()

func _build_ui() -> void:
	if countdown_timer != null:
		return
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var title := Label.new()
	title.text = "番茄钟"
	title.add_theme_font_size_override("font_size", 16)
	root.add_child(title)

	mode_label = Label.new()
	root.add_child(mode_label)

	time_label = Label.new()
	time_label.add_theme_font_size_override("font_size", 34)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(time_label)

	var buttons := HBoxContainer.new()
	root.add_child(buttons)

	start_button = Button.new()
	start_button.text = "开始"
	start_button.pressed.connect(start_focus)
	buttons.add_child(start_button)

	pause_button = Button.new()
	pause_button.text = "暂停"
	pause_button.pressed.connect(pause_or_resume)
	buttons.add_child(pause_button)

	reset_button = Button.new()
	reset_button.text = "重置"
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
	state_changed.emit(state)

func _update_time_label() -> void:
	if time_label:
		var minutes := int(seconds_left / 60)
		var seconds := seconds_left % 60
		time_label.text = "%02d:%02d" % [minutes, seconds]
