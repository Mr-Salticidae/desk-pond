extends PanelContainer
class_name Stepper

# 苹果式步进器：「− 25 分钟 +」装在同一个圆角浅底里，替代 Godot 默认的 SpinBox
# （那个的上下箭头悬在输入框外面，看着不是一体的）。
# 保留 SpinBox 的用法：中间能直接输入、鼠标滚轮 ±1、按住 − / + 连续加减；
# 接口也照 SpinBox 起名（value_changed / set_value_no_signal / editable），调用方几乎不用改。
# 加减按钮做得够大，手机上也点得到。

signal value_changed(value: float)

const REPEAT_DELAY := 0.4
const REPEAT_RATE := 0.06

var min_value := 0.0
var max_value := 100.0
var step := 1.0
var value := 0.0
var suffix := ""
var editable := true:
	set(on):
		editable = on
		_apply_editable()

var minus_button: Button
var plus_button: Button
var field: LineEdit
var _repeat: Timer
var _repeat_dir := 0

func _init() -> void:
	add_theme_stylebox_override("panel", UITheme.stepper_track_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	minus_button = _make_button("−", -1)
	row.add_child(minus_button)
	field = LineEdit.new()
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.context_menu_enabled = false
	field.select_all_on_focus = true
	UITheme.style_stepper_field(field)
	field.text_submitted.connect(func(_t: String): _commit_text(); field.release_focus())
	field.focus_exited.connect(_commit_text)
	field.focus_entered.connect(func(): field.text = _num(value))
	row.add_child(field)
	plus_button = _make_button("+", 1)
	row.add_child(plus_button)
	_repeat = Timer.new()
	_repeat.timeout.connect(_on_repeat)
	add_child(_repeat)
	_refresh_text()

# 减号用数学减号「−」（和「+」等宽、居中）；网页 / 手机版打包的像素字体里没有这个字，
# 会画成方框，所以先问一下实际用的字体，没有就退回普通连字符「-」。
func _notification(what: int) -> void:
	if (what == NOTIFICATION_READY or what == NOTIFICATION_THEME_CHANGED) and minus_button and minus_button.is_inside_tree():
		minus_button.text = minus_glyph(minus_button.get_theme_font("font"))

static func minus_glyph(font: Font) -> String:
	return "−" if font == null or font.has_char(0x2212) else "-"

func _make_button(text: String, dir: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(26, 0)
	UITheme.style_stepper_button(b)
	b.button_down.connect(func():
		_step_by(dir)
		_repeat_dir = dir
		_repeat.start(REPEAT_DELAY)
	)
	b.button_up.connect(func(): _repeat.stop())
	return b

func _on_repeat() -> void:
	_step_by(_repeat_dir)
	_repeat.start(REPEAT_RATE)

func _gui_input(event: InputEvent) -> void:
	if not editable or not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_step_by(1)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_step_by(-1)
		accept_event()

func _step_by(dir: int) -> void:
	if editable:
		_set_value(value + dir * step, true)

func set_value_no_signal(v: float) -> void:
	_set_value(v, false)

func _set_value(v: float, emit: bool) -> void:
	v = clampf(snappedf(v, step), min_value, max_value)
	var changed_now := not is_equal_approx(v, value)
	value = v
	_refresh_text()
	if emit and changed_now:
		value_changed.emit(value)

# 手动输入：只认数字，越界夹紧；乱输入就恢复原值
func _commit_text() -> void:
	var digits := ""
	for ch in field.text:
		if ch >= "0" and ch <= "9":
			digits += ch
	if digits != "":
		_set_value(float(int(digits)), true)
	_refresh_text()

func _refresh_text() -> void:
	if field and not field.has_focus():
		field.text = _num(value) + suffix
	if minus_button:
		minus_button.disabled = not editable or value <= min_value
		plus_button.disabled = not editable or value >= max_value

func _apply_editable() -> void:
	if field == null:
		return
	field.editable = editable
	field.mouse_filter = Control.MOUSE_FILTER_STOP if editable else Control.MOUSE_FILTER_IGNORE
	if not editable:
		_repeat.stop()
		if field.has_focus():
			field.release_focus()
	_refresh_text()

static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else str(v)
