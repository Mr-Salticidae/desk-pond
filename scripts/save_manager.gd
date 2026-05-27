extends RefCounted
class_name SaveManager

const SAVE_PATH = "user://save_data.json"

func load_save() -> Dictionary:
	var data := get_default_save()
	if FileAccess.file_exists(SAVE_PATH):
		var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				data = _merge_defaults(parsed, data)
	return check_new_day(data)

func save_game(data: Dictionary) -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))

func get_default_save() -> Dictionary:
	return {
		"date": _today(),
		"pomodoro_completed": 0,
		"tasks_completed": 0,
		"tree_growth_points": 0,
		"tree_stage": 0,
		"tasks": [],
		"fish_count": {
			"slacking_crucian": 0,
			"meeting_carp": 0,
			"deadline_goldfish": 0,
			"overtime_eel": 0,
			"drift_bottle": 0
		},
		"settings": {
			"always_on_top": false,
			"focus_minutes": 25,
			"break_minutes": 5,
			"sound_enabled": true
		}
	}

func check_new_day(data: Dictionary) -> Dictionary:
	var today := _today()
	if data.get("date", today) != today:
		data["date"] = today
		data["pomodoro_completed"] = 0
		data["tasks_completed"] = 0
		data["tasks"] = []
	return data

func current_datetime() -> String:
	var d := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02dT%02d:%02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute, d.second]

func _today() -> String:
	var d := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

func _merge_defaults(saved: Dictionary, defaults: Dictionary) -> Dictionary:
	for key in defaults.keys():
		if not saved.has(key):
			saved[key] = defaults[key]
		elif typeof(saved[key]) == TYPE_DICTIONARY and typeof(defaults[key]) == TYPE_DICTIONARY:
			saved[key] = _merge_defaults(saved[key], defaults[key])
	return saved
