extends Node
# 生成 TapTap PC 端商店素材（4 张），全部基于实机渲染，不合成虚构画面。
# - logo 1280×720（16:9，透明底，仅标题）
# - cover 920×430（460:215 ×2，含标题）
# - cover_vertical 600×900（2:3，实机竖屏截图 + 标题）
# - library_hero 3840×1240（无文字，1920×620 渲染后整数倍放大）
# 用法：godot --path . res://tests/make_pc_assets.tscn

const ART := "res://promo/taptap/04-banner.png"      # 1920×1080 实机场景（顶部 400px 是池塘带）
const SHOT := "res://promo/taptap/01-pond.png"       # 800×1440 实机竖屏截图
const OUT_DIR := "res://promo/taptap/pc"

var _root: Control

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_window().content_scale_size = Vector2i(0, 0)

	await _make_logo()
	await _make_cover()
	await _make_vertical()
	await _make_hero()
	print("PC ASSETS DONE")
	get_tree().quit()

# ---------- 公共部件 ----------

func _begin(w: int, h: int) -> void:
	if _root != null:
		_root.queue_free()
	get_window().size = Vector2i(w, h)
	await get_tree().process_frame
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

func _art_texture(region_h: int) -> Texture2D:
	var img := Image.load_from_file(ProjectSettings.globalize_path(ART))
	if img == null:
		return null
	var tex := ImageTexture.create_from_image(img)
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(0, 0, img.get_width(), region_h)
	return atlas

func _sky_fill(sky: Color, w: int, h: int) -> void:
	var bg := ColorRect.new()
	bg.color = sky
	bg.size = Vector2(w, h)
	_root.add_child(bg)

func _label(text: String, size: int, color: Color, pos: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", load(UITheme.PIXEL_FONT))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.position = pos
	_root.add_child(l)
	return l

func _save(name: String, scale := 1) -> void:
	for i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if scale > 1:
		img.resize(img.get_width() * scale, img.get_height() * scale, Image.INTERPOLATE_NEAREST)
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name])
	img.save_png(path)
	print("PC ", name, " ", img.get_width(), "x", img.get_height())

# ---------- 四张素材 ----------

func _make_logo() -> void:
	await _begin(1280, 720)
	# 透明底：窗口背景透明 + 清屏透明，只留标题
	get_window().transparent_bg = true
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	var title := _label("工位池塘", 150, UITheme.INK, Vector2(0, 270))
	title.size = Vector2(1280, 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	await _save("logo-1280x720")

func _make_cover() -> void:
	await _begin(920, 430)
	var img := Image.load_from_file(ProjectSettings.globalize_path(ART))
	var sky := img.get_pixel(6, 6) if img else Color(0.85, 0.92, 0.88)
	_sky_fill(sky, 920, 430)

	var art := TextureRect.new()
	art.texture = _art_texture(400)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.position = Vector2(0, 430 - 192)
	art.size = Vector2(920, 192)
	_root.add_child(art)

	_label("工位池塘", 72, UITheme.INK, Vector2(46, 92))
	var rule := ColorRect.new()
	rule.color = UITheme.ACCENT
	rule.position = Vector2(50, 196)
	rule.size = Vector2(96, 6)
	_root.add_child(rule)
	await _save("cover-920x430")

func _make_vertical() -> void:
	await _begin(600, 900)
	# 竖版封面只保留美术画面 + 标题：上方天空、底部池塘实机场景。
	# 不用带界面文字的整屏截图（审核要求清理 UI 文案）。
	var img := Image.load_from_file(ProjectSettings.globalize_path(ART))
	const BAND_H := 250
	const BAND_Y := 900 - BAND_H
	var sky := Color(0.85, 0.92, 0.88)
	if img != null:
		sky = img.get_pixel(500, 8)

	var sky_rect := ColorRect.new()
	sky_rect.color = sky
	sky_rect.position = Vector2(0, 0)
	sky_rect.size = Vector2(600, BAND_Y)
	_root.add_child(sky_rect)

	if img != null:
		# 取 960×400 的实机场景带等比缩到 600 宽（缩小，不做像素放大），画面干净
		var band := img.get_region(Rect2i(360, 0, 960, 400))
		band.resize(600, BAND_H, Image.INTERPOLATE_BILINEAR)
		var art := TextureRect.new()
		art.texture = ImageTexture.create_from_image(band)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.position = Vector2(0, BAND_Y)
		art.size = Vector2(600, BAND_H)
		_root.add_child(art)

	_label("工位池塘", 88, UITheme.INK, Vector2(52, 210))
	var rule := ColorRect.new()
	rule.color = UITheme.ACCENT
	rule.position = Vector2(56, 340)
	rule.size = Vector2(120, 9)
	_root.add_child(rule)
	await _save("cover-vertical-600x900")

func _make_hero() -> void:
	await _begin(1920, 620)
	var img := Image.load_from_file(ProjectSettings.globalize_path(ART))
	var sky := img.get_pixel(6, 6) if img else Color(0.85, 0.92, 0.88)
	_sky_fill(sky, 1920, 620)

	var art := TextureRect.new()
	art.texture = _art_texture(400)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.position = Vector2(0, 620 - 320)
	art.size = Vector2(1920, 320)
	_root.add_child(art)
	# 库壁纸禁止文字：这里只出场景，不叠标题
	await _save("library-hero-3840x1240", 2)
