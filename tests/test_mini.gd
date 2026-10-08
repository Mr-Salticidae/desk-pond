extends SceneTree
# 角落小窗 + 到点提醒的无头测试：
#   godot --headless --path . --script tests/test_mini.gd
# 进出小窗、小窗里的按钮都在窗口内、主按钮驱动计时、小窗里报喜不弹大窗、展开补弹、
# 休息结束的提示、上次在小窗里关掉下次直接是小窗。
# 贴角位置、拖动手感、任务栏闪烁这些要真窗口和真鼠标，留给作者真机终验。
# 用临时存档，不碰真实存档。全部通过时退出码 0，否则 1。

const TEST_SAVE := "user://test_mini_save.json"
const MINI := Vector2i(300, 84)
const FULL := Vector2i(640, 520)

var failures := 0
var checks := 0
var main: Control

func _initialize() -> void:
	SaveManager.save_path = TEST_SAVE
	_seed_save(false)
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	await _test_enter_and_layout()
	await _test_action_button()
	await _test_reward_in_mini()
	await _test_break_end_reminder()
	await _test_exit_restores()
	main.queue_free()
	await _settle()
	await _test_start_in_mini()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", what)

func _settle() -> void:
	for i in range(4):
		await process_frame

func _seed_save(start_in_mini: bool) -> void:
	var data := SaveManager.new().get_default_save()
	data["seen_intro"] = true
	data["eco"]["migrated"] = true
	data["eco"]["seen_guide"] = true
	data["settings"]["mini"]["on"] = start_in_mini
	SaveManager.new().save_game(data)

func _test_enter_and_layout() -> void:
	root.size = FULL
	await _settle()
	main._enter_mini()
	root.size = MINI   # 无头模式下窗口尺寸以视口为准，与真窗口一致
	await _settle()
	var win := main.get_window()
	_check(main.in_mini, "进入小窗")
	_check(main.mini_bar.visible and not main.root_box.visible, "小窗显示，完整界面收起")
	_check(win.content_scale_size == MINI, "小窗内容 1:1 绘制（设计尺寸 = 小窗尺寸）%s" % win.content_scale_size)
	_check(win.min_size == MINI, "小窗的最小尺寸降到 300×84")
	# 无头模式下根窗口存不住置顶标记（设了也读回 false），这一项只在真窗口里跑时检查
	if DisplayServer.get_name() != "headless":
		_check(win.always_on_top, "小窗自动置顶")
	_check(bool(main.save_data["settings"]["mini"]["on"]), "存档记下处于小窗")
	for h in main._resize_handles:
		_check(not h.visible, "小窗里不显示调整大小的手柄")
	var visible: Rect2 = main.get_viewport().get_visible_rect()
	for b in [main.mini_bar.action_button, main.mini_bar.expand_button]:
		var r: Rect2 = b.get_global_rect()
		_check(visible.encloses(r.grow(-0.5)), "小窗按钮「%s」%s 在窗口 %s 内" % [b.text, r, visible.size])
	for l in [main.mini_bar.status_label, main.mini_bar.time_label]:
		var r: Rect2 = l.get_global_rect()
		_check(visible.encloses(r.grow(-0.5)), "小窗文字「%s」%s 在窗口内" % [l.text, r])
	# 计时文字和按钮不重叠
	var t: Rect2 = main.mini_bar.time_label.get_global_rect()
	var a: Rect2 = main.mini_bar.action_button.get_global_rect()
	_check(t.end.y <= a.position.y + 0.5, "计时数字在按钮上方，不重叠 %s / %s" % [t, a])

func _test_action_button() -> void:
	var p = main.pomodoro_panel
	var bar = main.mini_bar
	_check(bar.action_button.text == "甩杆", "待机时主按钮是「甩杆」")
	bar._on_action()
	_check(p.state == "focusing" and bar.action_button.text == "暂停", "点甩杆开始专注，按钮变「暂停」")
	_check(bar.status_label.text == "专注中", "状态：专注中")
	bar._on_action()
	_check(p.state == "paused" and bar.action_button.text == "继续", "暂停后按钮变「继续」")
	bar._on_action()
	_check(p.state == "focusing", "继续专注")
	p.reset_timer()
	p.set_count_up(true)
	bar._on_action()
	_check(p.state == "focusing" and bar.action_button.text == "收竿", "正计时专注中，主按钮是「收竿」")
	p.reset_timer()
	p.set_count_up(false)
	bar.refresh()
	_check(bar.time_label.text == "25:00", "待机时显示专注时长 %s" % bar.time_label.text)

func _test_reward_in_mini() -> void:
	main.pomodoro_panel.last_focus_seconds = 25 * 60
	main._on_focus_completed()
	await _settle()
	_check(not main.reward_popup.visible, "小窗里专注完成不弹完整奖励窗")
	_check(main.mini_bar.toast_panel.visible and main.mini_bar.toast_label.text.begins_with("钓到「"), "小窗里冒报喜气泡：%s" % main.mini_bar.toast_label.text)
	_check(main.mini_bar.toast_label.text.find("贝壳") >= 0, "气泡里带上贝壳数")
	_check_toast_fits("真实钓获")
	# 鱼名最长的那种、以及一个故意超长的字符串：都要折行留在水面里（v0.7.0 一行写完，盖住了「休息中」）
	main.mini_bar.show_toast("钓到「通勤沙丁鱼」\n+5 贝壳")
	await _settle()
	_check_toast_fits("最长鱼名")
	main.mini_bar.show_toast("钓到「" + "特别特别长的名字".repeat(3) + "」  +24 贝壳")
	await _settle()
	_check_toast_fits("超长文字（折行）")
	main.pomodoro_panel.reset_timer()
	main._on_focus_completed()
	_check(main._pending_rewards.size() == 2, "两次收获都记下，等展开时补弹")
	main.pomodoro_panel.reset_timer()

# 气泡只占左边水面：右边缘不超过水面宽度，也不压到右边的状态文字和计时数字
func _check_toast_fits(where: String) -> void:
	var bar = main.mini_bar
	var toast: Rect2 = bar.toast_panel.get_global_rect()
	var scene_right: float = bar.get_global_rect().position.x + bar.SCENE_W
	_check(toast.end.x <= scene_right + 0.5, "%s：气泡右边缘 %.1f 不超出水面（%.1f）" % [where, toast.end.x, scene_right])
	for l in [bar.status_label, bar.time_label]:
		_check(not toast.intersects(l.get_global_rect()), "%s：气泡不压到「%s」" % [where, l.text])
	_check(toast.end.y <= bar.get_global_rect().end.y + 0.5, "%s：气泡不超出小窗底边（%.1f）" % [where, toast.end.y])

func _test_break_end_reminder() -> void:
	var p = main.pomodoro_panel
	p._start_break()
	p.seconds_left = 1
	p._on_timeout()
	await _settle()
	_check(p.state == "idle", "休息结束回到待机")
	_check(main.pixel_world.status_label.text == "休息好了，点池塘再甩一杆", "池塘提示休息好了：%s" % main.pixel_world.status_label.text)
	_check(main.mini_bar.status_label.text == "休息好了，再甩一杆", "小窗提示休息好了：%s" % main.mini_bar.status_label.text)
	var sl: Rect2 = main.mini_bar.status_label.get_global_rect()
	var font: Font = main.mini_bar.status_label.get_theme_font("font")
	var need := font.get_string_size(main.mini_bar.status_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	_check(need <= sl.size.x + 0.5, "「休息好了，再甩一杆」放得下，不被截断（要 %.0f，有 %.0f）" % [need, sl.size.x])
	p.start_focus()
	_check(main.pixel_world.status_label.text == "已甩杆，专注中", "再甩一杆后提示复原")
	p.reset_timer()
	_check(main.pixel_world.status_label.text == "点击池塘甩杆", "没有休息过的待机，还是原来的提示")

func _test_exit_restores() -> void:
	main._exit_mini()
	root.size = FULL
	await _settle()
	await _settle()
	var win := main.get_window()
	_check(not main.in_mini and main.root_box.visible and not main.mini_bar.visible, "展开回完整窗口")
	_check(win.content_scale_size == FULL and win.min_size == FULL, "设计尺寸和最小尺寸恢复 640×520")
	_check(not win.always_on_top, "置顶恢复成进小窗前的设置（未置顶）")
	_check(not bool(main.save_data["settings"]["mini"]["on"]), "存档记下已离开小窗")
	_check(main.reward_popup.visible, "展开时补弹小窗期间的奖励")
	_check(main.reward_popup.extra_label.text.find("小窗期间一共钓到 2 条") >= 0, "补弹的奖励里汇总小窗期间的收获：%s" % main.reward_popup.extra_label.text)
	_check(main._pending_rewards.is_empty(), "补弹后清空")
	main.reward_popup.hide()
	var visible: Rect2 = main.get_viewport().get_visible_rect()
	var col: Control = main.root_box
	_check(col.size.x <= visible.size.x + 0.5 and col.size.y <= visible.size.y + 0.5, "展开后整列不超出窗口 %s" % col.size)

func _test_start_in_mini() -> void:
	_seed_save(true)
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	_check(main.in_mini, "上次在小窗里关掉，这次启动直接是小窗")
	var full_pos: Array = main.save_data["settings"]["mini"]["full_pos"]
	_check(full_pos.is_empty(), "启动进小窗不把刚居中的窗口当成完整窗口的位置")
	main._exit_mini()
	await _settle()
	_check(not main.in_mini, "启动进的小窗也能展开")
	main.queue_free()
	await _settle()
