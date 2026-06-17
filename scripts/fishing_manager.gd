extends RefCounted
class_name FishingManager

const FISH_DATA_PATH = "res://data/fish_data.json"

var fish_data: Array = []
var fish_count: Dictionary = {}
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.randomize()
	load_fish_data()

func load_fish_data() -> void:
	fish_data = []
	var file := FileAccess.open(FISH_DATA_PATH, FileAccess.READ)
	if file:
		var parsed = JSON.parse_string(file.get_as_text())
		if typeof(parsed) == TYPE_ARRAY:
			fish_data = parsed

func set_fish_count(value: Dictionary) -> void:
	fish_count = value.duplicate(true)
	for fish in fish_data:
		var fish_id := String(fish.get("id", ""))
		if fish_id != "" and not fish_count.has(fish_id):
			fish_count[fish_id] = 0

# 一次专注完成的奖励：先看有没有刚达成、尚未获得的里程碑鱼，有则直接奖励它
# （取代随机，做成"达成时刻"）；否则按权重随机钓一条。
func roll_reward(stats: Dictionary) -> Dictionary:
	for fish in fish_data:
		var unlock = fish.get("unlock", null)
		if typeof(unlock) != TYPE_DICTIONARY:
			continue
		var fish_id := String(fish.get("id", ""))
		if fish_id == "" or int(fish_count.get(fish_id, 0)) > 0:
			continue  # 已获得，不重复奖励
		if _milestone_met(unlock, stats):
			add_fish(fish_id)
			return fish
	return roll_fish()

func _milestone_met(unlock: Dictionary, stats: Dictionary) -> bool:
	match String(unlock.get("type", "")):
		"total_sessions":
			return int(stats.get("total_sessions", 0)) >= int(unlock.get("value", 0))
		"total_catches":
			return _total_catches() >= int(unlock.get("value", 0))
	return false

func _total_catches() -> int:
	var total := 0
	for value in fish_count.values():
		total += int(value)
	return total

func roll_fish() -> Dictionary:
	if fish_data.is_empty():
		return {}
	var total_weight := 0
	for fish in fish_data:
		total_weight += int(fish.get("weight", 0))
	var roll := rng.randi_range(1, max(total_weight, 1))
	var cursor := 0
	for fish in fish_data:
		cursor += int(fish.get("weight", 0))
		if roll <= cursor:
			add_fish(String(fish.get("id", "")))
			return fish
	return fish_data[0]

func add_fish(fish_id: String) -> void:
	if fish_id == "":
		return
	fish_count[fish_id] = int(fish_count.get(fish_id, 0)) + 1

func get_fish_count() -> Dictionary:
	return fish_count.duplicate(true)

func get_fish_data() -> Array:
	return fish_data.duplicate(true)
