extends SceneTree
# 新版本提示的无头测试（不联网）：
#   godot --headless --path . --script tests/test_update.gd
# 版本号比较、latest.json 解析，以及「?」上的小点 / 提示条什么时候出现。
# 真的从自有站读到文件、点「去下载」打开浏览器，留给作者真机终验。
# 用临时存档，不碰真实存档。全部通过时退出码 0，否则 1。

const TEST_SAVE := "user://test_update_save.json"

var failures := 0
var checks := 0

func _initialize() -> void:
	await process_frame
	_test_compare()
	_test_parse()
	await _test_badge()
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", what)

func _test_compare() -> void:
	var newer := [
		["0.7.1", "0.7.0"], ["0.10.0", "0.9.9"], ["1.0.0", "0.99.99"], ["v0.7.0", "0.6.2"],
		["0.7.0", "0.7.0-beta"], ["0.7.0-rc", "0.7.0-beta"], ["0.7.0.1", "0.7.0"],
	]
	for pair in newer:
		_check(UpdateCheck.is_newer(pair[0], pair[1]), "%s 比 %s 新" % pair)
		_check(not UpdateCheck.is_newer(pair[1], pair[0]), "%s 不比 %s 新" % [pair[1], pair[0]])
	_check(not UpdateCheck.is_newer("0.7.0", "0.7.0"), "同版本不算新")
	_check(not UpdateCheck.is_newer("0.7", "0.7.0"), "0.7 和 0.7.0 一样")
	_check(not UpdateCheck.is_newer("", "0.6.2") and not UpdateCheck.is_newer("abc", "0.6.2"), "格式不对的版本号不算新")
	_check(UpdateCheck.current_version() != "" and UpdateCheck.current_version() != "0.0.0", "读得到自己的版本号（%s）" % UpdateCheck.current_version())

func _test_parse() -> void:
	var ok := UpdateCheck.parse_latest('{"version": "v0.7.1", "url": "https://tiaozhuxiansheng.com/desk-pond/", "notes": "小窗可以记住位置了"}')
	_check(ok.get("version") == "0.7.1" and String(ok.get("url")).begins_with("https://") and ok.get("notes") == "小窗可以记住位置了", "正常的 latest.json %s" % ok)
	_check(UpdateCheck.parse_latest("<html>404</html>").is_empty(), "不是 JSON（例如 404 页面）→ 当作没有")
	_check(UpdateCheck.parse_latest('{"version": "最新版"}').is_empty(), "版本号格式不对 → 当作没有")
	var odd := UpdateCheck.parse_latest('{"version": "0.8.0", "url": "file:///C:/evil.exe"}')
	_check(odd.get("url") == UpdateCheck.DEFAULT_PAGE, "非 https 链接一律换成官网下载页")
	var long := UpdateCheck.parse_latest('{"version": "0.8.0", "notes": "%s"}' % "很长".repeat(100))
	_check(String(long.get("notes")).length() <= 60, "说明文字截到 60 字以内")

func _test_badge() -> void:
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
	_check(not main.update_dot.visible and not main.update_banner.visible, "没有新版本：不亮小点、不出提示条")
	main.save_data["update"]["latest"] = {"version": "99.0.0", "url": "https://tiaozhuxiansheng.com/desk-pond/", "notes": "测试"}
	main._refresh_update_badge()
	_check(main.update_dot.visible and main.update_banner.visible, "有新版本：「?」亮小点，玩法说明顶部出提示条")
	_check(main.update_label.text.find("v99.0.0") >= 0 and main.update_label.text.find("测试") >= 0, "提示条写版本号和说明：%s" % main.update_label.text)
	main.save_data["settings"]["update_check"] = false
	main._refresh_update_badge()
	_check(not main.update_dot.visible and not main.update_banner.visible, "关掉检查：小点和提示条都收起")
	main.save_data["settings"]["update_check"] = true
	main.save_data["update"]["latest"] = {"version": UpdateCheck.current_version()}
	main._refresh_update_badge()
	_check(not main.update_dot.visible, "已经装了这一版：小点自动消失")
	# 模拟一次成功的响应（不联网）：比当前新 → 记下；不新 → 清空；网络失败 → 不记检查日期，下次启动再试
	main._update_http = HTTPRequest.new()
	main.add_child(main._update_http)
	main._on_update_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), '{"version": "98.0.0"}'.to_utf8_buffer())
	_check(String(main.save_data["update"]["latest"].get("version", "")) == "98.0.0" and main.update_dot.visible, "查到新版：记下并亮小点")
	_check(String(main.save_data["update"]["last_check"]) == main._today(), "记下今天查过，今天不再查")
	main._update_http = HTTPRequest.new()
	main.add_child(main._update_http)
	main._on_update_response(HTTPRequest.RESULT_SUCCESS, 404, PackedStringArray(), PackedByteArray())
	_check((main.save_data["update"]["latest"] as Dictionary).is_empty() and not main.update_dot.visible, "文件不在（404）：当作没有新版")
	main.save_data["update"]["last_check"] = ""
	main._update_http = HTTPRequest.new()
	main.add_child(main._update_http)
	main._on_update_response(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	_check(String(main.save_data["update"]["last_check"]) == "", "连不上：不记检查日期，下次启动再试")
	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
