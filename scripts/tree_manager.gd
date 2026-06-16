extends RefCounted
class_name TreeManager

signal growth_changed(growth_points: int)

# 每完成 POINTS_PER_TREE 个任务，长成一棵成材的树。growth_points 只增不减，
# 整片林子由它确定性推导——不封顶、不清零，越用越茂密。
const POINTS_PER_TREE := 4

# 树种（按"已成材棵数"阶梯解锁，越多越多样）
const SPECIES_BROADLEAF := 0
const SPECIES_PINE := 1
const SPECIES_BLOSSOM := 2
const SPECIES_FRUIT := 3
const SPECIES_MAPLE := 4
# 第几棵树开始可能出现对应树种（index 阈值，下标即树种 id）
const SPECIES_UNLOCK := [0, 5, 12, 20, 30]

var growth_points := 0

func set_growth_points(value: int) -> void:
	growth_points = max(value, 0)
	growth_changed.emit(growth_points)

func add_growth_point(amount: int = 1) -> void:
	set_growth_points(growth_points + amount)

func mature_count() -> int:
	return growth_points / POINTS_PER_TREE

func current_progress() -> int:
	return growth_points % POINTS_PER_TREE

func current_stage() -> int:
	# 当前正在长的那棵苗：进度 0..POINTS_PER_TREE-1 映射到 0..3 视觉阶段
	if POINTS_PER_TREE <= 1:
		return 3
	return int(round(float(current_progress()) / float(POINTS_PER_TREE - 1) * 3.0))

func pond_tree_stage() -> int:
	# 池塘角落那棵树：一旦有成材的树就稳定显示为大树，不再"缩回去"
	return 3 if mature_count() > 0 else current_stage()

func points_to_next_tree() -> int:
	return POINTS_PER_TREE - (growth_points % POINTS_PER_TREE)

func species_for_index(i: int) -> int:
	# 第 i 棵树的树种：随 index 增大，可选树种逐级变多，但每棵树的树种稳定不变
	var unlocked := 1
	for tier in range(1, SPECIES_UNLOCK.size()):
		if i >= SPECIES_UNLOCK[tier]:
			unlocked = tier + 1
	return i % unlocked

func distinct_species(count: int) -> int:
	var seen := {}
	for i in range(count):
		seen[species_for_index(i)] = true
	return max(seen.size(), 1)
