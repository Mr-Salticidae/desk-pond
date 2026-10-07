extends RefCounted
class_name DailyLog

# 每日记录：每天一行，只增不减。设计见 docs/设计_v0.7_小窗与昼夜.md 第一节。
# 和 EcoTank 一样纯逻辑、不挂节点：绑定存档里的 "daily" 字典按引用修改，方便无头测试。
#   "daily": { "2026-10-07": { "m": 专注分钟, "n": 专注次数, "t": 完成任务, "s": 贝壳, "f": { 鱼种: 条数 } } }
# 键名压短：日后接云存档时单值有大小上限。
# 只记从 v0.7 起的日子（"daily_since"），更早的历史补不回来，界面上也不假装有。

var days: Dictionary = {}
var since := ""

func bind(daily: Dictionary, since_date: String) -> void:
	days = daily
	since = since_date

# v0.7 第一次打开：给今天补一行（专注分钟无从得知，记 0）。返回记录起始日，由 main 写回存档。
static func start(save_data: Dictionary, today: String) -> String:
	var since_date := String(save_data.get("daily_since", ""))
	if since_date != "":
		return since_date
	var daily: Dictionary = save_data.get("daily", {})
	if not daily.has(today):
		var n := int(save_data.get("pomodoro_completed", 0))
		var t := int(save_data.get("tasks_completed", 0))
		if n > 0 or t > 0:
			daily[today] = {"m": 0, "n": n, "t": t, "s": 0, "f": {}}
	save_data["daily"] = daily
	save_data["daily_since"] = today
	return today

func _row(date: String) -> Dictionary:
	if not days.has(date) or typeof(days[date]) != TYPE_DICTIONARY:
		days[date] = {"m": 0, "n": 0, "t": 0, "s": 0, "f": {}}
	var row: Dictionary = days[date]
	for k in ["m", "n", "t", "s"]:
		if not row.has(k):
			row[k] = 0
	if typeof(row.get("f")) != TYPE_DICTIONARY:
		row["f"] = {}
	return row

func add_focus(date: String, minutes: int, fish_id: String = "") -> void:
	var row := _row(date)
	row["m"] = int(row["m"]) + maxi(minutes, 0)
	row["n"] = int(row["n"]) + 1
	if fish_id != "":
		var f: Dictionary = row["f"]
		f[fish_id] = int(f.get(fish_id, 0)) + 1

# 只在任务第一次完成时调用（和 total_tasks_completed 同口径）：取消勾选不扣，反复勾选刷不了
func add_task(date: String) -> void:
	var row := _row(date)
	row["t"] = int(row["t"]) + 1

func add_shells(date: String, amount: int) -> void:
	if amount <= 0:
		return
	var row := _row(date)
	row["s"] = int(row["s"]) + amount

static func fish_total(row: Dictionary) -> int:
	var total := 0
	var f: Variant = row.get("f", {})
	if typeof(f) == TYPE_DICTIONARY:
		for v in f.values():
			total += int(v)
	return total

# 以 today 结尾的最近 count 天（旧 → 新），没记录的日子补空行。
# recorded = false 表示那天在开始记录之前，界面上留白、不画柱子。
func recent(today: String, count: int) -> Array:
	var out: Array = []
	var base := _to_unix(today)
	for i in range(count - 1, -1, -1):
		var date := Time.get_date_string_from_unix_time(base - i * 86400)
		var row: Dictionary = days.get(date, {}) if typeof(days.get(date, {})) == TYPE_DICTIONARY else {}
		out.append({
			"date": date,
			"m": int(row.get("m", 0)),
			"n": int(row.get("n", 0)),
			"t": int(row.get("t", 0)),
			"s": int(row.get("s", 0)),
			"fish": fish_total(row),
			"recorded": since == "" or date >= since,
		})
	return out

# 本周（周一起）到今天为止的合计
func week_totals(today: String) -> Dictionary:
	var base := _to_unix(today)
	var weekday := int(Time.get_datetime_dict_from_unix_time(base).get("weekday", 1))   # 0 = 周日
	var days_since_monday := (weekday + 6) % 7
	var total := {"m": 0, "n": 0, "t": 0, "s": 0, "fish": 0}
	for row in recent(today, days_since_monday + 1):
		for k in total.keys():
			total[k] = int(total[k]) + int(row[k])
	return total

static func _to_unix(date: String) -> int:
	var parts := date.split("-")
	if parts.size() != 3:
		return int(Time.get_unix_time_from_system())
	return int(Time.get_unix_time_from_datetime_dict({
		"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]),
		"hour": 12, "minute": 0, "second": 0,
	}))
