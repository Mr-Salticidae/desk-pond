extends SceneTree
# 把 assets/icon.png（256×256 像素画）整数倍放大到 1024×1024，供 TapTap 图标（要求 ≥512、1:1）。
# 像素画用最近邻放大，不做插值，边缘保持硬朗。
# 用法：godot --headless --path . --script tests/make_icon.gd

const SRC := "res://assets/icon.png"
const OUT := "res://promo/taptap/icon-1024.png"
const TARGET := 1024

func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	if img == null:
		printerr("图标读取失败")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != img.get_height():
		var side := mini(img.get_width(), img.get_height())
		img.crop(side, side)
	var scale := maxi(1, int(round(float(TARGET) / float(img.get_width()))))
	img.resize(img.get_width() * scale, img.get_height() * scale, Image.INTERPOLATE_NEAREST)
	if img.get_width() != TARGET:
		img.resize(TARGET, TARGET, Image.INTERPOLATE_NEAREST)
	var out := ProjectSettings.globalize_path(OUT)
	img.save_png(out)
	print("ICON ", out, " ", img.get_width(), "x", img.get_height(), " scale=", scale)
	quit(0)
