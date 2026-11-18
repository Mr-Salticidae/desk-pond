extends Node
# 截图工具：按手机竖屏比例渲染主场景并抓帧，产出 TapTap 商店用图。
# 用法：godot --path . res://tests/capture_shots.tscn -- --web-layout --web-size=800x1440
# 产物：promo/taptap/*.png（真实游戏画面，不做合成）

var _main: Node

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(3.0).timeout
	print("WINDOW=", get_window().size)

	# 宣传图模式：只留像素池塘场景，按 16:9 出图
	if OS.get_cmdline_user_args().has("--banner"):
		get_window().size = Vector2i(1920, 1080)
		_main.top_bar_panel.hide()
		_main.bottom_box.hide()
		if _main.pixel_world and _main.pixel_world.status_label:
			_main.pixel_world.status_label.hide()
		await get_tree().create_timer(1.6).timeout
		await _shot("04-banner")
		get_tree().quit()
		return

	await _shot("01-pond")

	if _main.has_method("_goto_aquarium"):
		_main._goto_aquarium("tank")
		await get_tree().create_timer(1.6).timeout
		_hide_cards()
		await get_tree().create_timer(0.4).timeout
		await _shot("02-tank")

	if _main.has_method("_open_shop"):
		_main._open_shop()
		await get_tree().create_timer(1.4).timeout
		await _shot("03-shop")

	get_tree().quit()

# 关掉首次进入的引导弹窗，避免遮住商店 / 缸
func _hide_cards() -> void:
	for child in _main.get_children():
		if child is Window:
			child.hide()

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://promo/taptap/%s.png" % shot_name)
	img.save_png(path)
	print("SHOT ", path, " ", img.get_width(), "x", img.get_height())
