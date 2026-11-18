extends Node
# 生成 TapTap 16:9 宣传图（1920×1080）：深色底 + 像素池塘实机横幅 + 标题排版。
# 底图来自 capture_shots 的 --banner 实机渲染，不做虚构画面。
# 用法：godot --path . res://tests/make_banner.tscn

const W := 1920
const H := 1080
const ART_H := 320

func _ready() -> void:
	# 关掉项目里的画布缩放，让视口 1:1 等于像素尺寸，排版坐标才和出图一致
	get_window().content_scale_size = Vector2i(0, 0)
	get_window().size = Vector2i(W, H)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var bg := ColorRect.new()
	bg.color = UITheme.BG_DEEP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	# 实机横幅：取 04-banner 的像素场景带（顶部 320px），等比放大到整幅宽
	# promo/ 不进导入流水线，直接从磁盘读图，避免依赖 .import 缓存
	var art_img := Image.load_from_file(ProjectSettings.globalize_path("res://promo/taptap/04-banner.png"))
	var art_tex: Texture2D = ImageTexture.create_from_image(art_img) if art_img != null else null
	if art_tex != null:
		var atlas := AtlasTexture.new()
		atlas.atlas = art_tex
		atlas.region = Rect2(0, 0, art_tex.get_width(), 320)
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
	title.add_theme_font_size_override("font_size", 132)
	title.add_theme_color_override("font_color", UITheme.INK_ON_CHROME)
	title.position = Vector2(140, 190)
	root.add_child(title)

	var sub := Label.new()
	sub.text = "你专注，它钓鱼"
	sub.add_theme_font_override("font", font)
	sub.add_theme_font_size_override("font_size", 52)
	sub.add_theme_color_override("font_color", UITheme.ACCENT)
	sub.position = Vector2(146, 360)
	root.add_child(sub)

	var note := Label.new()
	note.text = "番茄钟 · 自动钓鱼 · 生态缸"
	note.add_theme_font_override("font", font)
	note.add_theme_font_size_override("font_size", 34)
	note.add_theme_color_override("font_color", Color(0.72, 0.74, 0.70))
	note.position = Vector2(146, 440)
	root.add_child(note)

	for i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://promo/taptap/banner-1920x1080.png")
	img.save_png(out)
	print("BANNER ", out, " ", img.get_width(), "x", img.get_height())
	get_tree().quit()
