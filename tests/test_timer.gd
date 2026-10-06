extends SceneTree
# 番茄钟（倒计时 / 正计时）的无头测试：
#   godot --headless --path . --script tests/test_timer.gd
# 直接调用每秒的 tick，不用真等。全部通过时退出码 0，否则 1。

var failures := 0
var checks := 0
var completed := 0
var last_settings: Dictionary = {}

func _initialize() -> void:
	# 等 root 进入场景树，计时器节点才能 start()
	await process_frame
	_test_countdown_still_works()
	_test_count_up_finish()
	_test_count_up_too_short()
	_test_count_up_pause_and_resume()
	_test_count_up_cap()
	_test_mode_locked_while_running()
	_test_settings_roundtrip()
	_test_count_up_wall_clock()
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", what)

func _timer(settings: Dictionary = {}) -> PomodoroTimer:
	var t: PomodoroTimer = load("res://scenes/PomodoroPanel.tscn").instantiate()
	root.add_child(t)
	t.setup(settings)
	t._wall_clock = false
	completed = 0
	t.focus_completed.connect(func(): completed += 1)
	t.settings_changed.connect(func(s: Dictionary): last_settings = s)
	return t

func _tick(t: PomodoroTimer, n: int) -> void:
	for i in range(n):
		t._on_timeout()

func _test_countdown_still_works() -> void:
	var t := _timer({"focus_minutes": 1, "break_minutes": 1})
	t.start_focus()
	_check(t.time_label.text == "01:00", "倒计时从设定时长开始")
	_tick(t, 59)
	_check(completed == 0 and t.display_seconds() == 1, "倒计时还剩 1 秒")
	_tick(t, 1)
	_check(completed == 1, "倒计时走完算一次专注")
	_check(t.last_focus_seconds == 60, "倒计时按设定时长结算")
	_check(t.state == "break", "倒计时完成后进入休息")
	t.free()

func _test_count_up_finish() -> void:
	var t := _timer({"count_up": true, "break_minutes": 2})
	_check(t.time_label.text == "00:00", "正计时待机显示 00:00")
	_check(not t.focus_spin.visible, "正计时收起专注时长")
	t.start_focus()
	_tick(t, 125)
	_check(t.display_seconds() == 125 and t.time_label.text == "02:05", "正计时往上数")
	_check(t.start_button.text == "收竿" and not t.start_button.disabled, "正计时专注中主按钮是「收竿」")
	t.start_focus()   # 点池塘：专注中不能把这一竿收掉
	_check(t.state == "focusing" and completed == 0, "点池塘不会结束正计时")
	t._on_start_pressed()
	_check(completed == 1, "收竿算一次专注")
	_check(t.last_focus_seconds == 125, "正计时按实际时长结算")
	_check(t.state == "break" and t.display_seconds() == 120, "收竿后进入休息倒计时")
	_tick(t, 120)
	_check(t.state == "idle" and t.time_label.text == "00:00", "休息结束回到正计时待机")
	t.free()

func _test_count_up_too_short() -> void:
	var t := _timer({"count_up": true})
	t.start_focus()
	_tick(t, PomodoroTimer.COUNT_UP_MIN_SECONDS - 1)
	t.finish_count_up()
	_check(completed == 0, "不满 1 分钟收竿没有收获")
	_check(t.state == "idle" and t.display_seconds() == 0, "空竿回到待机")
	t.free()

func _test_count_up_pause_and_resume() -> void:
	var t := _timer({"count_up": true})
	t.start_focus()
	_tick(t, 70)
	t.pause_or_resume()
	_tick(t, 30)
	_check(t.state == "paused" and t.display_seconds() == 70, "暂停时不走")
	_check(t.start_button.text == "收竿" and not t.start_button.disabled, "暂停中也能收竿")
	t.start_focus()   # 暂停中点池塘 = 继续
	_check(t.state == "focusing", "暂停中甩杆等同继续")
	_tick(t, 5)
	_check(t.display_seconds() == 75, "继续后接着往上数")
	t.pause_or_resume()
	t._on_start_pressed()
	_check(completed == 1 and t.last_focus_seconds == 75, "暂停中收竿按已走时长结算")
	t.free()

func _test_count_up_cap() -> void:
	var t := _timer({"count_up": true})
	t.start_focus()
	t.elapsed_seconds = PomodoroTimer.COUNT_UP_CAP_SECONDS - 1
	_tick(t, 1)
	_check(completed == 1, "数到上限自动收竿")
	_check(t.last_focus_seconds == PomodoroTimer.COUNT_UP_CAP_SECONDS, "上限按 180 分钟结算")
	t.free()

func _test_mode_locked_while_running() -> void:
	var t := _timer({"count_up": true})
	t.start_focus()
	t.set_count_up(false)
	_check(t.count_up and t.mode_button.disabled, "专注中不能切换计时方式")
	t.reset_timer()
	t.set_count_up(false)
	_check(not t.count_up and t.focus_spin.visible, "待机时可以切回倒计时")
	_check(last_settings.get("count_up") == false, "切换会发出设置变更")
	t.free()

func _test_settings_roundtrip() -> void:
	var t := _timer({"focus_minutes": 30, "break_minutes": 7})
	t.set_count_up(true)
	_check(last_settings == {"focus_minutes": 30, "break_minutes": 7, "count_up": true}, "设置里带上计时方式")
	t.free()
	var t2 := _timer(last_settings)
	_check(t2.count_up and t2.mode_button.button_pressed and t2.mode_button.text == "正计时", "按存档恢复正计时")
	t2.free()

# Web 切后台会冻结 tick：按真实时钟补算已走的秒数
func _test_count_up_wall_clock() -> void:
	var t := _timer({"count_up": true})
	t._wall_clock = true
	t.start_focus()
	t._start_unix -= 100.0
	_tick(t, 1)
	_check(t.display_seconds() == 100, "Web 按真实时钟补算正计时")
	t.free()
