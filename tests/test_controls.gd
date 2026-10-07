extends SceneTree
# 苹果式控件的无头测试：
#   godot --headless --path . --script tests/test_controls.gd
# 步进器（− 数值 +）替代了 SpinBox，分段控件替代了「倒计时」小开关，
# 这里确认它们保留了原来的用法：加减、上下限、手动输入、滚轮、锁定，以及接回钓竿面板后设置照常保存。
# 全部通过时退出码 0，否则 1。

var failures := 0
var checks := 0

func _initialize() -> void:
	await process_frame
	_test_stepper()
	_test_segmented()
	await _test_timer_panel()
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", what)

func _test_stepper() -> void:
	var s := Stepper.new()
	s.min_value = 1
	s.max_value = 10
	s.suffix = " 分钟"
	s.set_value_no_signal(5)
	root.add_child(s)
	var got: Array = []
	s.value_changed.connect(func(v: float): got.append(v))
	_check(s.field.text == "5 分钟", "数值带单位显示：%s" % s.field.text)
	s.plus_button.button_down.emit()
	s.plus_button.button_up.emit()
	_check(is_equal_approx(s.value, 6) and got == [6.0], "点 + 加 1 并发信号 %s" % [got])
	s.minus_button.button_down.emit()
	s.minus_button.button_up.emit()
	_check(is_equal_approx(s.value, 5), "点 − 减 1")
	s.set_value_no_signal(10)
	_check(s.plus_button.disabled and not s.minus_button.disabled, "到上限：+ 变灰")
	s.plus_button.button_down.emit()
	s.plus_button.button_up.emit()
	_check(is_equal_approx(s.value, 10), "到上限不再加")
	s.set_value_no_signal(1)
	_check(s.minus_button.disabled, "到下限：− 变灰")
	got.clear()
	s.set_value_no_signal(3)
	_check(got.is_empty(), "set_value_no_signal 不发信号")
	# 手动输入：只认数字、越界夹紧、乱输入恢复原值
	s.field.text = "8"
	s._commit_text()
	_check(is_equal_approx(s.value, 8) and s.field.text == "8 分钟", "手动输入 8")
	s.field.text = "99 分钟"
	s._commit_text()
	_check(is_equal_approx(s.value, 10), "输入超过上限被夹到 10")
	s.field.text = "abc"
	s._commit_text()
	_check(is_equal_approx(s.value, 10) and s.field.text == "10 分钟", "乱输入恢复原值")
	# 滚轮
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	s._gui_input(wheel)
	_check(is_equal_approx(s.value, 9), "滚轮向下减 1")
	# 锁定
	s.editable = false
	_check(s.minus_button.disabled and s.plus_button.disabled and not s.field.editable, "锁定后 ± 和输入都不可用")
	s.plus_button.button_down.emit()
	s.plus_button.button_up.emit()
	s._gui_input(wheel)
	_check(is_equal_approx(s.value, 9), "锁定时加减、滚轮都不改值")
	s.editable = true
	_check(not s.plus_button.disabled and s.field.editable, "解锁后恢复")
	# 一体：减号、数值、加号都在同一块底里（同一个父容器），不再有悬在框外的箭头
	_check(s.minus_button.get_parent() == s.field.get_parent() and s.field.get_parent() == s.plus_button.get_parent(), "− 数值 + 在同一行容器里")
	s.queue_free()

func _test_segmented() -> void:
	var seg := SegmentedControl.new()
	seg.setup(["倒计时", "正计时"])
	root.add_child(seg)
	var got: Array = []
	seg.changed.connect(func(i: int): got.append(i))
	_check(seg.selected == 0 and seg.buttons[0].button_pressed and not seg.buttons[1].button_pressed, "默认选中第一段")
	seg.buttons[1].button_pressed = true
	_check(seg.selected == 1 and got == [1] and not seg.buttons[0].button_pressed, "点第二段：选中切换并发信号")
	seg.set_selected_no_signal(0)
	_check(seg.selected == 0 and got == [1], "set_selected_no_signal 不发信号")
	seg.set_enabled(false)
	_check(seg.buttons[0].button_pressed, "锁定后仍看得出选中的是哪一段（不走 disabled，按下样式保留）")
	_check(seg.buttons[1].mouse_filter == Control.MOUSE_FILTER_IGNORE and seg.modulate.a < 1.0, "锁定后点不动、整体变淡")
	seg.set_enabled(true)
	_check(seg.buttons[1].mouse_filter == Control.MOUSE_FILTER_STOP and is_equal_approx(seg.modulate.a, 1.0), "解锁后恢复")
	seg.queue_free()

func _test_timer_panel() -> void:
	var p = load("res://scenes/PomodoroPanel.tscn").instantiate()
	root.add_child(p)
	await process_frame
	var saved: Array = []
	p.settings_changed.connect(func(s: Dictionary): saved.append(s))
	p.setup({"focus_minutes": 30, "break_minutes": 10, "count_up": false})
	_check(is_equal_approx(p.focus_spin.value, 30) and is_equal_approx(p.break_spin.value, 10), "按存档恢复专注 / 休息时长")
	p.focus_spin.plus_button.button_down.emit()
	p.focus_spin.plus_button.button_up.emit()
	_check(p.focus_seconds == 31 * 60 and p.seconds_left == 31 * 60, "专注步进器 +1：专注时长变 31 分钟")
	_check(not saved.is_empty() and int(saved.back()["focus_minutes"]) == 31, "改时长后发出设置（存档）")
	p.break_spin.field.text = "15"
	p.break_spin._commit_text()
	_check(p.break_seconds == 15 * 60, "休息时长手动输入 15")
	p.mode_switch.buttons[1].button_pressed = true
	_check(p.count_up and not p.focus_spin.visible, "分段切到正计时：收起专注时长")
	p.start_focus()
	_check(not p.mode_switch.enabled and not p.break_spin.editable, "计时中：分段和步进器都锁住")
	p.reset_timer()
	_check(p.mode_switch.enabled and p.break_spin.editable, "回到待机：解锁")
	p.mode_switch.buttons[0].button_pressed = true
	_check(not p.count_up and p.focus_spin.visible, "切回倒计时")
	p.queue_free()
	await process_frame
