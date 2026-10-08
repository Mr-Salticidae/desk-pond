extends SceneTree
# 网页 / 手机版字体的缺字检查：
#   godot --headless --path . --script tests/test_glyphs.gd
# Web 导出没有系统字体可回退，界面全靠打包的像素字体；字体里没有的字会画成方框。
# v0.7.0 的步进器减号「−」（U+2212）就这样在 B站 Toy 上变成了方框，桌面端（系统字体）看不出来。
# 这里把 scripts/ 里每个非 ASCII 字符都拿去问像素字体；确实要用、且代码里已经做了退路的字，登记在 ALLOWED。
# 全部通过时退出码 0，否则 1。

const PIXEL_FONT := "res://assets/fonts/fusion-pixel-12px-proportional-zh_hans.otf.woff2"
# 文件名 → 允许缺的字：都必须在代码里有退路
const ALLOWED := {
	"ui_stepper.gd": [0x2212],   # Stepper.minus_glyph：字体没有「−」时退回「-」
}

var failures := 0
var checks := 0

func _initialize() -> void:
	await process_frame
	var font: Font = load(PIXEL_FONT)
	_check(font != null, "像素字体能加载")
	_scan_scripts(font)
	await _test_stepper_fallback(font)
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", what)

func _scan_scripts(font: Font) -> void:
	var dir := DirAccess.open("res://scripts")
	var scanned := 0
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		scanned += 1
		var allowed: Array = ALLOWED.get(f, [])
		var line_no := 0
		for line in FileAccess.get_file_as_string("res://scripts/" + f).split("\n"):
			line_no += 1
			var stripped := line.strip_edges()
			if stripped.begins_with("#"):
				continue   # 注释不上屏
			for i in range(line.length()):
				var c := line.unicode_at(i)
				if c <= 127 or c in allowed:
					continue
				if not font.has_char(c):
					_check(false, "%s:%d 用了像素字体里没有的字 U+%04X「%s」" % [f, line_no, c, String.chr(c)])
	_check(scanned >= 20, "扫到了 scripts/ 下的脚本（%d 个）" % scanned)

# 步进器在像素字体下用「-」，在有「−」的字体下用「−」
func _test_stepper_fallback(font: Font) -> void:
	_check(Stepper.minus_glyph(font) == "-", "像素字体下减号退回「-」")
	_check(font.has_char("-".unicode_at(0)), "像素字体有「-」")
	var s := Stepper.new()
	s.add_theme_font_override("font", font)
	s.minus_button.add_theme_font_override("font", font)
	root.add_child(s)
	await process_frame
	var glyph := s.minus_button.text
	_check(font.has_char(glyph.unicode_at(0)), "步进器减号「%s」在当前字体里画得出来" % glyph)
	s.queue_free()
