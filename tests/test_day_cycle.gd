extends SceneTree
# 昼夜的无头测试：
#   godot --headless --path . --script tests/test_day_cycle.gd
# 时段划分、相邻分钟不跳变（含 23:59 → 00:00）、「一直白天」开关、夜里文字换浅色，
# 以及接进三个房间以后：森林萤火虫只在夜里动、分享卡片永远是白天。
# 夜色好不好看要人眼看，留给作者真机终验。
# 用临时存档，不碰真实存档。全部通过时退出码 0，否则 1。

const TEST_SAVE := "user://test_day_cycle_save.json"
const DayCycleScript := preload("res://scripts/day_cycle.gd")

var failures := 0
var checks := 0
var dc: Node

func _initialize() -> void:
	await process_frame
	dc = root.get_node("DayCycle")
	_test_phases()
	_test_day_is_unchanged()
	_test_continuity()
	_test_mode_and_signal()
	_test_ink()
	await _test_rooms()
	dc.fixed_hour = -1.0
	dc.set_mode("auto")
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", what)

func _test_phases() -> void:
	var expect := {0.0: "night", 4.9: "night", 5.0: "dawn", 7.9: "dawn", 8.0: "day", 12.0: "day", 16.9: "day", 17.0: "dusk", 18.9: "dusk", 19.0: "night", 23.9: "night"}
	for h in expect:
		_check(DayCycleScript.phase_of(h) == expect[h], "%.1f 点是 %s（实际 %s）" % [h, expect[h], DayCycleScript.phase_of(h)])
	_check(is_equal_approx(float(dc.sample(2.0)["night"]), 1.0), "凌晨两点是深夜")
	_check(is_equal_approx(float(dc.sample(22.0)["night"]), 1.0), "晚上十点是深夜")
	var dawn := float(dc.sample(6.0)["night"])
	_check(dawn > 0.0 and dawn < 1.0, "清晨六点在过渡中（%.2f）" % dawn)
	var dusk := float(dc.sample(18.0)["night"])
	_check(dusk > 0.0 and dusk < 1.0, "傍晚六点在过渡中（%.2f）" % dusk)

# 白天和 v0.6 一模一样：天色就是原来的常量，没有遮罩
func _test_day_is_unchanged() -> void:
	for h in [8.0, 12.0, 16.5]:
		var s: Dictionary = dc.sample(h)
		_check((s["sky"] as Color).is_equal_approx(DayCycleScript.DAY_SKY), "%.1f 点天色 = 原配色" % h)
		_check(is_zero_approx((s["overlay"] as Color).a) and is_zero_approx(float(s["night"])), "%.1f 点没有夜色遮罩" % h)

func _test_continuity() -> void:
	var worst := 0.0
	var worst_at := 0
	for m in range(0, 24 * 60):
		var a: Dictionary = dc.sample(m / 60.0)
		var b: Dictionary = dc.sample((m + 1) / 60.0)
		var d := _diff(a, b)
		if d > worst:
			worst = d
			worst_at = m
	_check(worst < 0.03, "相邻两分钟的颜色变化都很小（最大 %.3f，在 %02d:%02d）" % [worst, worst_at / 60, worst_at % 60])
	_check(_diff(dc.sample(23.99), dc.sample(0.0)) < 0.01, "23:59 → 00:00 连续")

func _diff(a: Dictionary, b: Dictionary) -> float:
	var d := absf(float(a["night"]) - float(b["night"]))
	for key in ["sky", "overlay"]:
		var ca: Color = a[key]
		var cb: Color = b[key]
		d = maxf(d, maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), maxf(absf(ca.b - cb.b), absf(ca.a - cb.a))))
	return d

func _test_mode_and_signal() -> void:
	var hits := [0]
	var cb := func(): hits[0] += 1
	dc.changed.connect(cb)
	dc.fixed_hour = 12.0
	dc.set_mode("auto")
	hits[0] = 0
	dc.refresh()
	_check(hits[0] == 0, "颜色没变时不发 changed（静态的森林不白白重绘）")
	dc.fixed_hour = 22.0
	dc.refresh()
	_check(hits[0] == 1 and is_equal_approx(dc.night, 1.0), "到了夜里发一次 changed")
	dc.set_mode("day")
	_check(is_zero_approx(dc.night) and dc.sky.is_equal_approx(DayCycleScript.DAY_SKY), "「一直白天」：夜里也是白天的样子")
	dc.set_mode("nonsense")
	_check(dc.mode == "auto", "未知的设置值按「跟随本地时间」处理")
	dc.changed.disconnect(cb)

func _test_ink() -> void:
	var day_ink := Color(0.15, 0.20, 0.24)
	_check(DayCycleScript.ink_for(0.0, day_ink).is_equal_approx(day_ink), "白天文字颜色不变")
	var night_ink: Color = DayCycleScript.ink_for(1.0, day_ink)
	_check(night_ink.get_luminance() > 0.7, "夜里文字换成浅色（亮度 %.2f）" % night_ink.get_luminance())

func _test_rooms() -> void:
	SaveManager.save_path = TEST_SAVE
	var data := SaveManager.new().get_default_save()
	data["seen_intro"] = true
	data["eco"]["migrated"] = true
	data["eco"]["seen_guide"] = true
	data["tree_growth_points"] = 40
	SaveManager.new().save_game(data)
	var main: Control = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	for i in range(4):
		await process_frame
	dc.set_mode("auto")
	dc.fixed_hour = 22.0
	dc.refresh()
	main._switch_room("forest")
	await process_frame
	_check(not main.forest_view.firefly_timer.is_stopped(), "夜里看森林：萤火虫在动")
	main._switch_room("pond")
	await process_frame
	_check(main.forest_view.firefly_timer.is_stopped(), "离开森林：萤火虫计时器停下，不白耗电")
	for i in range(3):
		await process_frame
	var ink: Color = main.pixel_world.status_label.get_theme_color("font_color")
	_check(ink.get_luminance() > 0.6, "夜里池塘的状态文字是浅色（亮度 %.2f）" % ink.get_luminance())
	main._switch_room("forest")
	dc.fixed_hour = 12.0
	dc.refresh()
	await process_frame
	_check(main.forest_view.firefly_timer.is_stopped(), "白天看森林：没有萤火虫，计时器停着")
	_check(main.aquarium_view.use_day_cycle, "自己的缸跟随昼夜")
	_check(not main.share_card.card_tank.use_day_cycle, "分享卡片里的缸永远是白天（卡片是一张照片）")
	# 设置开关：玩法说明底部「昼夜跟随本地时间」
	var toggles: Array = main.help_window.find_children("*", "CheckButton", true, false)
	_check(toggles.size() >= 1, "玩法说明里有昼夜开关")
	if toggles.size() >= 1:
		dc.fixed_hour = 22.0
		toggles[0].button_pressed = false
		_check(String(main.save_data["settings"]["day_cycle"]) == "day" and is_zero_approx(dc.night), "关掉开关：存档记「一直白天」，夜里也亮")
		toggles[0].button_pressed = true
		_check(String(main.save_data["settings"]["day_cycle"]) == "auto" and is_equal_approx(dc.night, 1.0), "打开开关：回到跟随本地时间")
	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
