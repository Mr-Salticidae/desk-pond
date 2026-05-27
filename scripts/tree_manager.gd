extends RefCounted
class_name TreeManager

signal growth_changed(growth_points: int, tree_stage: int)

var growth_points := 0
var tree_stage := 0

func set_growth_points(value: int) -> void:
	growth_points = max(value, 0)
	tree_stage = _calculate_stage(growth_points)
	growth_changed.emit(growth_points, tree_stage)

func add_growth_point(amount: int = 1) -> void:
	set_growth_points(growth_points + amount)

func get_tree_stage() -> int:
	return tree_stage

func update_tree_visual() -> void:
	growth_changed.emit(growth_points, tree_stage)

func _calculate_stage(points: int) -> int:
	if points <= 0:
		return 0
	if points < 3:
		return 1
	if points < 5:
		return 2
	return 3
