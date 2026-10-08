extends Control
class_name MiniBar

# 角落小窗：一条约 300×84 的迷你窗，左边一小块水面（钓鱼人 + 鱼影），右边计时和一个主按钮。
# 设计见 docs/设计_v0.7_小窗与昼夜.md 第三节。
# 不复用 PixelWorld：那边桌子、钓鱼人用固定像素尺寸，压到 84 高会画乱；这里单独画一个简化版。
# 计时仍由（隐藏着的）钓竿面板驱动，这里只订阅它的信号、调用它的方法，和全屏计时胶囊同一做法。

signal expand_requested

const SIZE := Vector2i(300, 84)
const SCENE_W := 150.0
const LOOP := 360.0
const WATER := Color(0.24, 0.58, 0.70)
const WATER_DEEP := Color(0.17, 0.42, 0.52)
const SHEEN := Color(0.36, 0.72, 0.80)
const RIPPLE := Color(0.82, 0.94, 0.93, 0.70)
const FISH_SHADOW := Color(0.10, 0.34, 0.43, 0.40)
const BANK := Color(0.42, 0.66, 0.43)
const BANK_DARK := Color(0.33, 0.55, 0.36)

var pomodoro: PomodoroTimer
var status_label: Label
var time_label: Label
var action_button: Button
var expand_button: Button
var toast_panel: PanelContainer
var toast_label: Label

var frame := 0.0
var flash := 0.0
var rested := false
var anim_timer: Timer
var _toast_left := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_MOVE
	tooltip_text = "拖动可移动小窗，双击展开"
	_build_ui()
	anim_timer = Timer.new()
	anim_timer.wait_time = 0.12
	anim_timer.timeout.connect(_on_tick)
	add_child(anim_timer)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and anim_timer:
		if is_visible_in_tree():
			anim_timer.start()
			refresh()
		else:
			anim_timer.stop()

func bind(timer: PomodoroTimer) -> void:
	pomodoro = timer
	pomodoro.timer_tick.connect(func(_s: int): refresh())
	pomodoro.state_changed.connect(func(state: String):
		if state == "focusing":
			rested = false
		refresh()
	)
	pomodoro.break_completed.connect(func(): rested = true)
	refresh()

func _build_ui() -> void:
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", UITheme.chrome_bar_style())
	add_child(bg)
	# 场景画在本控件的 _draw 里；背景面板只铺右半边，免得盖住水面
	bg.offset_left = SCENE_W

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 高度预算：边距 4 + 状态 17 + 计时 28 + 按钮 26 + 边距 4 ≤ 84，一点都不能多（tests/test_mini.gd 守着）
	col.add_theme_constant_override("separation", 0)
	col.anchor_left = 0.0
	col.anchor_right = 1.0
	col.anchor_bottom = 1.0
	col.offset_left = SCENE_W + 10.0
	col.offset_right = -8.0
	col.offset_top = 4.0
	col.offset_bottom = -4.0
	add_child(col)

	status_label = Label.new()
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color(UITheme.INK_ON_CHROME, 0.72))
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.clip_text = true
	col.add_child(status_label)

	time_label = Label.new()
	time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_label.add_theme_font_size_override("font_size", 20)
	time_label.add_theme_color_override("font_color", UITheme.INK_ON_CHROME)
	time_label.text = "25:00"
	col.add_child(time_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)

	action_button = Button.new()
	action_button.focus_mode = Control.FOCUS_NONE
	action_button.text = "甩杆"
	action_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_primary(action_button)
	action_button.add_theme_font_size_override("font_size", 13)
	action_button.pressed.connect(_on_action)
	row.add_child(action_button)

	expand_button = Button.new()
	expand_button.focus_mode = Control.FOCUS_NONE
	expand_button.text = "展开"
	expand_button.tooltip_text = "回到完整窗口"
	UITheme.style_chrome(expand_button)
	expand_button.add_theme_font_size_override("font_size", 13)
	expand_button.pressed.connect(func(): expand_requested.emit())
	row.add_child(expand_button)
	for b in [action_button, expand_button]:
		_tighten(b)

	# 小窗里专注完成：不弹完整奖励窗（会把小窗撑开、挡住别的窗口），水面上冒一个 3 秒的气泡
	toast_panel = PanelContainer.new()
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.add_theme_stylebox_override("panel", UITheme.chip_style())
	toast_panel.visible = false
	toast_panel.position = Vector2(6, 6)
	add_child(toast_panel)
	toast_label = Label.new()
	toast_label.add_theme_font_size_override("font_size", 12)
	toast_label.max_lines_visible = 3   # 折行最多 3 行，再长也不超出 84 高的小窗
	toast_label.add_theme_color_override("font_color", UITheme.INK_ON_CHROME)
	toast_panel.add_child(toast_label)

# 小窗里的按钮上下内边距收到 4（主题默认 6–7），省出来的高度给计时数字
func _tighten(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := b.get_theme_stylebox(state)
		if sb == null:
			continue
		sb = sb.duplicate()
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		b.add_theme_stylebox_override(state, sb)

func refresh() -> void:
	if pomodoro == null or status_label == null:
		return
	var state := pomodoro.state
	var names := {"focusing": "正计时专注中" if pomodoro.count_up else "专注中", "break": "休息中", "paused": "暂停中"}
	if names.has(state):
		status_label.text = String(names[state])
	else:
		status_label.text = "休息好了，再甩一杆" if rested else "点甩杆开始专注"
	var secs := pomodoro.display_seconds()
	time_label.text = "%02d:%02d" % [secs / 60, secs % 60]
	match state:
		"focusing":
			action_button.text = "收竿" if pomodoro.count_up else "暂停"
		"break":
			action_button.text = "暂停"
		"paused":
			action_button.text = "继续"
		_:
			action_button.text = "甩杆"
	queue_redraw()

func _on_action() -> void:
	if pomodoro == null:
		return
	match pomodoro.state:
		"focusing":
			if pomodoro.count_up:
				pomodoro.finish_count_up()
			else:
				pomodoro.pause_or_resume()
		"break", "paused":
			pomodoro.pause_or_resume()
		_:
			pomodoro.start_focus()
	refresh()

## 气泡只占左边的水面：比水面宽就在水面宽度内折行，不盖住右边的状态和计时
## （v0.7.0 一行写完「钓到「周报河豚」 +5 贝壳」，盖住了「休息中」的「休」字）
func show_toast(text: String, seconds := 3.0) -> void:
	flash = 1.0
	toast_label.text = text
	toast_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	toast_label.custom_minimum_size = Vector2.ZERO
	toast_panel.visible = true
	toast_panel.reset_size()
	var max_w := SCENE_W - toast_panel.position.x - 6.0
	if toast_panel.size.x > max_w:
		var pad := toast_panel.size.x - toast_label.get_combined_minimum_size().x
		toast_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		toast_label.custom_minimum_size = Vector2(max_w - pad, 0)
		toast_panel.reset_size()
	_toast_left = seconds

func _on_tick() -> void:
	frame = fmod(frame + 1.0, LOOP)
	flash = maxf(flash - 0.08, 0.0)
	if _toast_left > 0.0:
		_toast_left -= anim_timer.wait_time
		if _toast_left <= 0.0:
			toast_panel.visible = false
	queue_redraw()

func _draw() -> void:
	var h := size.y
	var phase := frame / LOOP * TAU
	var night := DayCycle.night
	var sky_h := 30.0
	# 天 + 星
	draw_rect(Rect2(0, 0, SCENE_W, sky_h), DayCycle.sky)
	if night > 0.05:
		for i in range(6):
			var twinkle := 0.55 + 0.45 * sin(phase * 3.0 + i * 1.7)
			_px(Vector2(fmod(i * 41.0 + 17.0, SCENE_W - 4.0), 4.0 + fmod(i * 13.0, sky_h - 10.0)), Vector2(2, 2), Color(1.0, 0.97, 0.85, night * twinkle))
	# 水
	draw_rect(Rect2(0, sky_h, SCENE_W, h - sky_h), WATER)
	draw_rect(Rect2(0, sky_h, SCENE_W, 8), SHEEN)
	draw_rect(Rect2(0, h - 10, SCENE_W, 10), WATER_DEEP)
	for i in range(3):
		var rx := 52.0 + i * 30.0 + sin(phase * 2.0 + i * 1.2) * 3.0
		_px(Vector2(rx, sky_h + 14.0 + (i % 2) * 10.0), Vector2(16, 3), RIPPLE)
	for i in range(3):
		var fx := 96.0 + sin(phase + i * 2.1) * 40.0
		_px(Vector2(fx - 6.0, sky_h + 22.0 + i * 9.0), Vector2(12, 4), FISH_SHADOW)
	# 岸 + 钓鱼人
	draw_rect(Rect2(0, sky_h - 4, 36, h - sky_h + 4), BANK)
	draw_rect(Rect2(0, sky_h + 10, 36, h - sky_h - 10), BANK_DARK)
	var p := Vector2(12, sky_h - 4)
	_px(p + Vector2(0, -20), Vector2(10, 10), Color(0.98, 0.76, 0.54))
	_px(p + Vector2(-2, -23), Vector2(14, 5), Color(0.20, 0.28, 0.30))
	_px(p + Vector2(-2, -10), Vector2(14, 12), Color(0.84, 0.36, 0.27))
	_px(p + Vector2(0, 2), Vector2(4, 6), Color(0.16, 0.25, 0.31))
	_px(p + Vector2(7, 2), Vector2(4, 6), Color(0.16, 0.25, 0.31))
	var focusing := pomodoro != null and pomodoro.state == "focusing"
	if focusing:
		var rod_end := Vector2(58, sky_h - 8 + sin(phase * 4.0) * 3.0)
		draw_line(p + Vector2(12, -8), rod_end, Color(0.22, 0.17, 0.12), 2.0)
		draw_line(rod_end, rod_end + Vector2(0, 22), Color(0.12, 0.18, 0.19, 0.55), 1.0)
	else:
		draw_line(p + Vector2(12, -8), p + Vector2(40, -20), Color(0.22, 0.17, 0.12), 2.0)
	# 钓到鱼：水面闪一下
	if flash > 0.0:
		var c := Color(1.0, 0.95, 0.46, flash)
		_px(Vector2(52, sky_h + 4), Vector2(22, 4), c)
		_px(Vector2(61, sky_h - 4), Vector2(4, 18), c)
	if DayCycle.overlay.a > 0.0:
		draw_rect(Rect2(0, 0, SCENE_W, h), DayCycle.overlay)

func _px(pos: Vector2, rect_size: Vector2, color: Color) -> void:
	draw_rect(Rect2(pos.round(), rect_size.round()), color)
