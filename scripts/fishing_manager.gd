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
