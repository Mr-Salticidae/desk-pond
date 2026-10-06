extends SceneTree
# 桌面布局的无头回归测试：
#   godot --headless --path . --script tests/test_layout.gd
# issue #1：水族馆模式下顶栏变宽，把整列撑得比窗口宽，任务苗圃右侧的按钮显示不全。
# 这里在默认大小和拉大后的窗口里逐个房间检查：整列不超出窗口，顶栏 / 钓竿 / 任务区的按钮都在窗口内。
# 用临时存档，不碰真实存档。全部通过时退出码 0，否则 1。

const TEST_SAVE := "user://test_layout_save.json"
const WINDOW_SIZES := [Vector2i(640, 520), Vector2i(1000, 520), Vector2i(640, 900), Vector2i(1280, 1040)]

var failures := 0
var checks := 0
var main: Control

func _initialize() -> void:
	SaveManager.save_path = TEST_SAVE
	_seed_save()
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	for window_size in WINDOW_SIZES:
		root.size = window_size
		await _settle()
		await _check_rooms(window_size)
	await _check_count_up_mode()
	main.queue_free()
	await process_frame
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

# 往存档里塞会撑宽界面的内容：一堆任务（含超长标题）、五位数贝壳
func _seed_save() -> void:
	var data := SaveManager.new().get_default_save()
	data["seen_intro"] = true
	data["eco"]["shells"] = 99999
	data["eco"]["migrated"] = true
	data["eco"]["seen_guide"] = true
	var tasks: Array = []
	for i in range(6):
		tasks.append({"id": "t%d" % i, "title": "任务 %d" % i, "done": i % 2 == 0, "created_at": "", "completed_at": null})
	tasks.append({"id": "long", "title": "一个特别特别长的任务标题，用来确认它不会把任务区撑宽到窗口外面去".repeat(2), "done": false, "created_at": "", "completed_at": null})
	data["tasks"] = tasks
	SaveManager.new().save_game(data)

func _check_rooms(window_size: Vector2i) -> void:
	var views := [["pond", ""], ["forest", ""], ["aquarium", "tank"], ["aquarium", "catalog"], ["aquarium", "edit"]]
	for v in views:
		main._switch_room(v[0])
		if v[1] != "":
			main._set_aqua_submode(v[1])
		await _settle()
		_check_fits("%s %s/%s" % [window_size, v[0], v[1]])
	main._set_aqua_submode("tank")
	main._switch_room("pond")
	await _settle()

# 切到正计时后钓竿面板多了开关、少了专注时长一行，同样不能撑出窗口
func _check_count_up_mode() -> void:
	root.size = WINDOW_SIZES[0]
	main.pomodoro_panel.set_count_up(true)
	main.pomodoro_panel.start_focus()
	await _settle()
	_check_fits("count-up focusing")
	main.pomodoro_panel.reset_timer()
	main.pomodoro_panel.set_count_up(false)

func _check_fits(where: String) -> void:
	var visible := main.get_viewport().get_visible_rect()
	var col: Control = main.root_box
	_check(col.size.x <= visible.size.x + 0.5 and col.size.y <= visible.size.y + 0.5,
		"%s: 整列 %s 超出窗口 %s" % [where, col.size, visible.size])
	for panel in [main.top_bar_panel, main.pomodoro_panel, main.task_panel]:
		for b in _buttons(panel):
			var r: Rect2 = b.get_global_rect()
			var ok_x := r.position.x >= visible.position.x - 0.5 and r.end.x <= visible.end.x + 0.5
			# 滚动列表里的按钮纵向可以藏在可视区下面，只查横向
			var ok_y := _in_scroll(b, panel) or (r.position.y >= visible.position.y - 0.5 and r.end.y <= visible.end.y + 0.5)
			_check(ok_x and ok_y, "%s: 按钮「%s」%s 超出窗口 %s" % [where, b.text, r, visible.size])

func _buttons(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Window:
			continue
		if c is Button and c.is_visible_in_tree():
			out.append(c)
		out.append_array(_buttons(c))
	return out

func _in_scroll(node: Node, stop: Node) -> bool:
	var p := node.get_parent()
	while p != null and p != stop:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false
