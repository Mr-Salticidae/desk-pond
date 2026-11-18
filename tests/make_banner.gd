extends Node
# 生成 TapTap 16:9 宣传图（1920×1080）。
# 构图：标题放在画面左上，背景天空色从实机截图里取样，底部接实机像素场景，
# 让标题像是「长在这片天空里」，避免深色留白显得空。
# 底图来自 capture_shots 的 --banner 实机渲染，不做虚构画面。
# 用法：godot --path . res://tests/make_banner.tscn

const W := 1920
const H := 1080
const ART_H := 400

func _ready() -> void:
	# 关掉项目里的画布缩放，让视口 1:1 等于像素尺寸，排版坐标才和出图一致
	get_window().content_scale_size = Vector2i(0, 0)
	get_window().size = Vector2i(W, H)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# promo/ 不进导入流水线，直接从磁盘读图，避免依赖 .import 缓存
	var art_img := Image.load_from_file(ProjectSettings.globalize_path("res://promo/taptap/04-banner.png"))
	var art_tex: Texture2D = ImageTexture.create_from_image(art_img) if art_img != null else null

	# 天空色取自实机截图的左上角，保证与场景里那片天无缝
	var sky := Color(0.85, 0.92, 0.88)
	if art_img != null:
		sky = art_img.get_pixel(6, 6)

	var grad := Gradient.new()
	grad.set_color(0, sky.darkened(0.10))
	grad.set_color(1, sky)
	grad.set_offset(0, 0.0)
	grad.set_offset(1, 1.0)
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1)
	gtex.width = W
	gtex.height = H - ART_H
	var bg := TextureRect.new()
	bg.texture = gtex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.position = Vector2(0, 0)
	bg.size = Vector2(W, H - ART_H)
	root.add_child(bg)

	if art_tex != null:
		var atlas := AtlasTexture.new()
		atlas.atlas = art_tex
		atlas.region = Rect2(0, 0, art_tex.get_width(), ART_H)
		var art := TextureRect.new()
		art.texture = atlas
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.position = Vector2(0, H - ART_H)
		art.size = Vector2(W, ART_H)
		root.add_child(art)

	var font: Font = load(UITheme.PIXEL_FONT)

	var title := Label.new()
	title.text = "工位池塘"
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 168)
	title.add_theme_color_override("font_color", UITheme.INK)
	title.position = Vector2(150, 300)
	root.add_child(title)

	# 标题下的一道细陶土色线，压住左下角的空
	var rule := ColorRect.new()
	rule.color = UITheme.ACCENT
	rule.position = Vector2(158, 512)
	rule.size = Vector2(210, 12)
	root.add_child(rule)

	for i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://promo/taptap/banner-1920x1080.png")
	img.save_png(out)
	print("BANNER ", out, " ", img.get_width(), "x", img.get_height())
	get_tree().quit()
