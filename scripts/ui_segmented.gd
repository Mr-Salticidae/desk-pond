extends PanelContainer
class_name SegmentedControl

# 苹果式分段控件：一条浅色底槽，选中的那段是浮起来的近白色块。
# 用来替代「带描边的小开关」，例如钓竿面板的「倒计时 / 正计时」。
# 锁定（enabled = false）时整体变淡、点不动，但仍看得出选中的是哪一段——
# Godot 按钮一旦 disabled 就不再画「按下」样式，所以这里不用 disabled，改为忽略鼠标。

signal changed(index: int)

var buttons: Array[Button] = []
var selected := 0
var enabled := true

func setup(labels: Array, font_size := 12) -> void:
	add_theme_stylebox_override("panel", UITheme.segment_track_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	var group := ButtonGroup.new()
	for i in range(labels.size()):
		var b := Button.new()
		b.text = String(labels[i])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.style_segment(b, font_size)
		b.toggled.connect(func(on: bool):
			if on and selected != i:
				selected = i
				changed.emit(i)
		)
		row.add_child(b)
		buttons.append(b)
	set_selected_no_signal(selected)

func set_selected_no_signal(index: int) -> void:
	selected = clampi(index, 0, maxi(buttons.size() - 1, 0))
	for i in range(buttons.size()):
		buttons[i].set_pressed_no_signal(i == selected)

func set_enabled(on: bool) -> void:
	enabled = on
	modulate.a = 1.0 if on else 0.55
	for b in buttons:
		b.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE

func set_tooltip(text: String) -> void:
	tooltip_text = text
	for b in buttons:
		b.tooltip_text = text
