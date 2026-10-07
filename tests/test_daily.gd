extends SceneTree
# 每日记录的无头测试：
#   godot --headless --path . --script tests/test_daily.gd
# 纯逻辑部分直接测 DailyLog；最后把主场景跑起来，确认专注 / 任务 / 贝壳都记进当天那一行。
# 用临时存档，不碰真实存档。全部通过时退出码 0，否则 1。

const TEST_SAVE := "user://test_daily_save.json"

var failures := 0
var checks := 0

func _initialize() -> void:
	await process_frame
	_test_start_fresh()
	_test_start_seeds_today()
	_test_accumulate()
	_test_recent_padding_and_month_boundary()
	_test_week_totals()
	_test_eco_earn_hook()
	_test_describe()
	await _test_main_integration()
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", what)

func _test_start_fresh() -> void:
	var data := SaveManager.new().get_default_save()
	var since := DailyLog.start(data, "2026-10-07")
	_check(since == "2026-10-07", "新存档：从今天开始记录")
	_check(String(data["daily_since"]) == "2026-10-07", "daily_since 写回存档")
	_check((data["daily"] as Dictionary).is_empty(), "新存档今天还什么都没做，不补空行")
	# 第二次调用不改起始日
	_check(DailyLog.start(data, "2026-10-09") == "2026-10-07", "已开始记录的存档不再重置起始日")

func _test_start_seeds_today() -> void:
	var data := SaveManager.new().get_default_save()
	data["pomodoro_completed"] = 3
	data["tasks_completed"] = 2
	DailyLog.start(data, "2026-10-07")
	var row: Dictionary = data["daily"].get("2026-10-07", {})
	_check(int(row.get("n", -1)) == 3 and int(row.get("t", -1)) == 2, "旧存档：今天补一行，次数和任务取当天计数 %s" % row)
	_check(int(row.get("m", -1)) == 0, "旧存档：今天的专注分钟无从得知，记 0")

func _make_log(since := "2026-10-01") -> DailyLog:
	var log := DailyLog.new()
	log.bind({}, since)
	return log

func _test_accumulate() -> void:
	var log := _make_log()
	log.add_focus("2026-10-07", 25, "salted_fish")
	log.add_focus("2026-10-07", 50, "salted_fish")
	log.add_focus("2026-10-07", 30, "weekly_pufferfish")
	log.add_task("2026-10-07")
	log.add_shells("2026-10-07", 5)
	log.add_shells("2026-10-07", 0)
	log.add_shells("2026-10-07", -3)
	var row: Dictionary = log.days["2026-10-07"]
	_check(int(row["m"]) == 105 and int(row["n"]) == 3, "专注分钟与次数累加 %s" % row)
	_check(int(row["t"]) == 1, "任务累加")
	_check(int(row["s"]) == 5, "贝壳只记正数")
	_check(int(row["f"]["salted_fish"]) == 2 and int(row["f"]["weekly_pufferfish"]) == 1, "按鱼种记钓获")
	_check(DailyLog.fish_total(row) == 3, "当天钓获合计")
	# 零点前开始、零点后结束：记在完成那一刻的日期上（调用方传入的日期）
	log.add_focus("2026-10-08", 25, "")
	_check(int(log.days["2026-10-08"]["n"]) == 1 and int(log.days["2026-10-07"]["n"]) == 3, "跨零点的专注记到新的一天")
	_check((log.days["2026-10-08"]["f"] as Dictionary).is_empty(), "没有鱼种时不记钓获")

func _test_recent_padding_and_month_boundary() -> void:
	var log := _make_log("2026-09-25")
	log.add_focus("2026-09-30", 25, "salted_fish")
	log.add_task("2026-10-02")
	var rows := log.recent("2026-10-03", 14)
	_check(rows.size() == 14, "最近 14 天正好 14 行")
	_check(String(rows[0]["date"]) == "2026-09-20" and String(rows[13]["date"]) == "2026-10-03", "跨月的日期顺序：%s … %s" % [rows[0]["date"], rows[13]["date"]])
	var ok_order := true
	for i in range(1, rows.size()):
		if String(rows[i]["date"]) <= String(rows[i - 1]["date"]):
			ok_order = false
	_check(ok_order, "旧 → 新，逐日递增")
	_check(int(rows[10]["m"]) == 25 and String(rows[10]["date"]) == "2026-09-30", "9 月 30 日的专注落在对的格子")
	_check(int(rows[12]["t"]) == 1, "10 月 2 日的任务落在对的格子")
	_check(int(rows[11]["n"]) == 0 and bool(rows[11]["recorded"]), "没做事的日子补空行，但算已记录")
	_check(not bool(rows[4]["recorded"]) and bool(rows[5]["recorded"]), "开始记录（9/25）之前的日子标为未记录")
	# 闰年 2 月底
	var leap := _make_log("2028-01-01").recent("2028-03-01", 3)
	_check(String(leap[0]["date"]) == "2028-02-28" and String(leap[1]["date"]) == "2028-02-29", "闰年 2 月 29 日")

func _test_week_totals() -> void:
	var log := _make_log("2026-09-01")
	log.add_focus("2026-10-04", 60, "salted_fish")   # 周日：上一周
	log.add_focus("2026-10-05", 25, "salted_fish")   # 周一：本周第一天
	log.add_focus("2026-10-07", 30, "meeting_carp")  # 周三：今天
	log.add_task("2026-10-06")
	var w := log.week_totals("2026-10-07")
	_check(int(w["m"]) == 55 and int(w["n"]) == 2, "本周从周一算，不含上周日 %s" % w)
	_check(int(w["t"]) == 1 and int(w["fish"]) == 2, "本周任务与钓获合计")
	var sunday := log.week_totals("2026-10-04")
	_check(int(sunday["m"]) == 60, "周日看的是周一到周日这一周")

func _test_eco_earn_hook() -> void:
	var log := _make_log()
	var eco := EcoTank.new()
	eco.bind(EcoTank.default_state(), [])
	eco.on_earn = func(amount: int): log.add_shells("2026-10-07", amount)
	eco.earn(7)
	eco.earn(0)
	_check(int(log.days["2026-10-07"]["s"]) == 7, "贝壳经 EcoTank.earn 入账时记进当天")
	_check(eco.shells() == 7, "回调不影响贝壳本身")

func _test_describe() -> void:
	var text := DailyChart.describe({"date": "2026-10-07", "m": 75, "n": 3, "t": 4, "s": 21, "fish": 3, "recorded": true})
	_check(text.find("10月7日") >= 0 and text.find("75 分钟") >= 0 and text.find("4 个任务") >= 0, "柱子说明：%s" % text)
	_check(DailyChart.describe({"date": "2026-10-01", "recorded": false}).find("还没开始记录") >= 0, "未记录的日子不假装有数据")
	var idle := DailyChart.describe({"date": "2026-10-02", "m": 0, "n": 0, "t": 0, "s": 0, "fish": 0, "recorded": true})
	_check(idle.find("休息") >= 0 and idle.find("未完成") < 0 and idle.find("断") < 0, "空白的日子不写断签 / 未完成：%s" % idle)

func _test_main_integration() -> void:
	SaveManager.save_path = TEST_SAVE
	var data := SaveManager.new().get_default_save()
	data["seen_intro"] = true
	data["eco"]["migrated"] = true
	data["eco"]["seen_guide"] = true
	SaveManager.new().save_game(data)
	var main: Control = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	for i in range(4):
		await process_frame
	var today: String = main._today()
	_check(String(main.save_data["daily_since"]) == today, "主场景：从今天开始记录")

	main.pomodoro_panel.last_focus_seconds = 25 * 60
	main._on_focus_completed()
	var row: Dictionary = main.save_data["daily"].get(today, {})
	_check(int(row.get("m", 0)) == 25 and int(row.get("n", 0)) == 1, "主场景：专注完成记分钟和次数 %s" % row)
	_check(DailyLog.fish_total(row) == 1, "主场景：钓到的鱼记进当天")
	_check(int(row.get("s", 0)) >= 5, "主场景：专注的贝壳（25 分钟 = 5 个）记进当天")

	# 不写 TaskManager 类型：它引用了 autoload（WebInput），测试脚本编译时还解析不到
	var tasks = main.task_panel
	tasks.add_task("写周报")
	var id := String(tasks.get_tasks()[-1]["id"])
	tasks.toggle_task(id, true)
	tasks.toggle_task(id, false)
	tasks.toggle_task(id, true)
	row = main.save_data["daily"].get(today, {})
	_check(int(row.get("t", 0)) == 1, "主场景：同一个任务反复勾选只记一次 %s" % row)

	# 档案能画出来（14 天柱图 + 本周合计）
	main._build_ledger_window()
	main._render_ledger()
	for i in range(2):
		await process_frame
	var charts: Array = main.ledger_body.find_children("*", "DailyChart", true, false)
	_check(charts.size() == 1 and (charts[0] as DailyChart).rows.size() == 14, "档案里有一张 14 天的柱图")

	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
