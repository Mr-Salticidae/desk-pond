extends RefCounted
class_name SaveManager

# 测试会改成临时文件，避免读写玩家的真实存档
static var save_path := "user://save_data.json"

func load_save() -> Dictionary:
	var data := get_default_save()
	if FileAccess.file_exists(save_path):
		var file := FileAccess.open(save_path, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				data = _merge_defaults(parsed, data)
	return check_new_day(data)

func save_game(data: Dictionary) -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))

func get_default_save() -> Dictionary:
	return {
		"date": _today(),
		"seen_intro": false,
		"pomodoro_completed": 0,
		"total_focus_sessions": 0,
		"tasks_completed": 0,
		"total_tasks_completed": 0,
		"active_days": 1,
		"first_caught": {},
		# 生态缸（贝壳 / 摆件 / 访客……），结构见 EcoTank.default_state
		"eco": EcoTank.default_state(),
		"tree_growth_points": 0,
		"tree_stage": 0,
		# 每日记录（只增不减），结构见 DailyLog；daily_since = 开始记录的那天，之前的日子没有数据
		"daily": {},
		"daily_since": "",
		# 新版本检查：上次检查的日期、查到的最新版本（{version, url, notes}，没有更新时为空）
		"update": {
			"last_check": "",
			"latest": {}
		},
		"tasks": [],
		"fish_count": {
			"slacking_crucian": 0,
			"salted_fish": 0,
			"meeting_carp": 0,
			"commute_sardine": 0,
			"keyboard_loach": 0,
			"deadline_goldfish": 0,
			"weekly_pufferfish": 0,
			"overtime_eel": 0,
			"drift_bottle": 0,
			"annual_koi": 0,
			"slacking_legend": 0
		},
		"settings": {
			"always_on_top": false,
			"focus_minutes": 25,
			"break_minutes": 5,
			"muted": false,
			"count_up": false,
			# 桌面窗口大小 [宽, 高]，空 = 默认 640×520
			"window_size": [],
			# 角落小窗：是否处于小窗、小窗位置、进小窗前完整窗口的位置（[x, y]，空 = 未记录）
			"mini": {
				"on": false,
				"pos": [],
				"full_pos": []
			},
			# 昼夜："auto" 跟随本地时间 / "day" 一直白天
			"day_cycle": "auto",
			# 桌面版启动时检查新版本
			"update_check": true
		}
	}

func check_new_day(data: Dictionary) -> Dictionary:
	var today := _today()
	if data.get("date", today) != today:
		data["tasks"] = _carry_open_tasks(data.get("tasks", []), today)
		data["date"] = today
		data["pomodoro_completed"] = 0
		data["tasks_completed"] = 0
		# 活跃天数：只增不减的计数（非连胜，漏天不清零）
		data["active_days"] = int(data.get("active_days", 1)) + 1
	return data

func current_datetime() -> String:
	var d := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02dT%02d:%02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute, d.second]

func _today() -> String:
	var d := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

func _carry_open_tasks(saved_tasks: Variant, today: String) -> Array:
	if typeof(saved_tasks) != TYPE_ARRAY:
		return []
	var carried: Array = []
	for item in saved_tasks:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var task: Dictionary = item.duplicate(true)
		if bool(task.get("done", false)):
			continue
		task["done"] = false
		task["completed_at"] = null
		task["carried_to"] = today
		carried.append(task)
	return carried

func _merge_defaults(saved: Dictionary, defaults: Dictionary) -> Dictionary:
	for key in defaults.keys():
		if not saved.has(key):
			saved[key] = defaults[key]
		elif typeof(saved[key]) == TYPE_DICTIONARY and typeof(defaults[key]) == TYPE_DICTIONARY:
			saved[key] = _merge_defaults(saved[key], defaults[key])
	return saved
