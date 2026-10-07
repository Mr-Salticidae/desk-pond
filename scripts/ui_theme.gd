extends RefCounted
class_name UITheme

# 极简调色板：温润纸面 + 墨色文字 + 一抹陶土暖色。
# 设计意图：让 UI 外壳后退，把视觉重心留给像素池塘。
const BG_DEEP := Color(0.114, 0.149, 0.161)        # 应用最底层背景
const SURFACE := Color(0.957, 0.945, 0.910)        # 主纸面（面板）
const SURFACE_2 := Color(0.922, 0.906, 0.863)      # 次级纸面（输入框 / 行）
const SURFACE_3 := Color(0.886, 0.867, 0.820)      # 按下态
const CHROME := Color(0.137, 0.180, 0.192)         # 深色外壳（顶栏 / 卡片标题栏）
const INK := Color(0.157, 0.200, 0.200)            # 主文字
const INK_SOFT := Color(0.451, 0.482, 0.455)       # 次要文字
const INK_FAINT := Color(0.600, 0.624, 0.592)      # 弱化文字（占位 / 提示）
const INK_ON_CHROME := Color(0.878, 0.902, 0.855)  # 深色外壳上的文字
const LINE := Color(0.157, 0.200, 0.200, 0.12)     # 纸面发丝描边
const LINE_CHROME := Color(0.878, 0.902, 0.855, 0.16) # 深色外壳上的发丝描边
const ACCENT := Color(0.819, 0.510, 0.346)         # 陶土暖色（每个界面仅留给一个主操作）
const ACCENT_DEEP := Color(0.702, 0.416, 0.271)    # 暖色按下态
const ACCENT_INK := Color(0.169, 0.114, 0.082)     # 暖色上的文字
const POND := Color(0.227, 0.560, 0.639)           # 冷色点缀（进度 / 高亮）
const DANGER := Color(0.776, 0.380, 0.318)         # 关闭 / 删除的危险提示

const RADIUS := 6

# ---- 苹果式控件（v0.7）：控件不描边，只靠一层很淡的墨色底区分；圆角统一 ----
# 底色用带透明度的墨色叠在纸面上（≈ iOS 的 tertiarySystemFill），放在任何浅色面板上都协调。
const CONTROL_RADIUS := 8
const PANEL_RADIUS := 10
const FILL := Color(0.157, 0.200, 0.200, 0.065)          # 控件底
const FILL_HOVER := Color(0.157, 0.200, 0.200, 0.10)     # 悬停
const FILL_PRESSED := Color(0.157, 0.200, 0.200, 0.15)   # 按下
const FILL_DISABLED := Color(0.157, 0.200, 0.200, 0.04)  # 禁用：形状不变，只是更淡
const SEGMENT_ON := Color(1.0, 0.996, 0.984)             # 分段控件选中块（近白，浮起）
const CLEAR := Color(0, 0, 0, 0)

# ---- StyleBox 工厂 ----

static func _flat(fill: Color, border: Color, border_width: int, radius: int, pad: Vector4i) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = pad.x
	style.content_margin_top = pad.y
	style.content_margin_right = pad.z
	style.content_margin_bottom = pad.w
	return style

# 面板：纸面实底、不描边（深色背景上本来就分得清），圆角放大一点更柔和
static func panel_style(fill: Color = SURFACE) -> StyleBoxFlat:
	return _flat(fill, CLEAR, 0, PANEL_RADIUS, Vector4i(14, 12, 14, 12))

static func card_style() -> StyleBoxFlat:
	# 卡片整体外框：纸面 + 极淡描边，无圆角顶部由标题栏盖住
	return _flat(SURFACE, Color(0.157, 0.200, 0.200, 0.22), 1, RADIUS, Vector4i(0, 0, 0, 0))

static func header_style() -> StyleBoxFlat:
	var s := _flat(CHROME, CHROME, 0, RADIUS, Vector4i(14, 8, 10, 8))
	# 仅上方两角圆，与卡片贴合
	s.corner_radius_bottom_left = 0
	s.corner_radius_bottom_right = 0
	return s

static func chrome_bar_style() -> StyleBoxFlat:
	return _flat(CHROME, CHROME, 0, 0, Vector4i(12, 6, 10, 6))

# 悬浮在场景上的小胶囊（全屏按钮 / 迷你计时），半透明深色，压得住任何背景
static func chip_style() -> StyleBoxFlat:
	var c := CHROME
	c.a = 0.86
	return _flat(c, LINE_CHROME, 1, RADIUS, Vector4i(8, 4, 8, 4))

# 输入框：平时只是一块浅底；聚焦时底色提亮、外圈一道淡淡的水色光环（苹果的 focus ring）
static func input_style(focused: bool = false) -> StyleBoxFlat:
	if not focused:
		return _flat(FILL, CLEAR, 0, CONTROL_RADIUS, Vector4i(10, 7, 10, 7))
	return _flat(Color(1.0, 0.996, 0.984), Color(POND, 0.55), 2, CONTROL_RADIUS, Vector4i(10, 7, 10, 7))

# ---- 按钮风格 ----

static func _button_set(target: Control, normal: StyleBoxFlat, hover: StyleBoxFlat, pressed: StyleBoxFlat, disabled: StyleBoxFlat) -> void:
	target.add_theme_stylebox_override("normal", normal)
	target.add_theme_stylebox_override("hover", hover)
	target.add_theme_stylebox_override("pressed", pressed)
	target.add_theme_stylebox_override("disabled", disabled)
	target.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

# 次要按钮：纸面上的一块浅底，不描边；悬停 / 按下只是底色加深；
# 禁用时形状不变、只是更淡（不再换成另一种带框的灰盒子）
static func _ghost_boxes(pad: Vector4i) -> Array:
	return [
		_flat(FILL, CLEAR, 0, CONTROL_RADIUS, pad),
		_flat(FILL_HOVER, CLEAR, 0, CONTROL_RADIUS, pad),
		_flat(FILL_PRESSED, CLEAR, 0, CONTROL_RADIUS, pad),
		_flat(FILL_DISABLED, CLEAR, 0, CONTROL_RADIUS, pad),
	]

static func style_ghost(target: Control) -> void:
	var b := _ghost_boxes(Vector4i(12, 7, 12, 7))
	_button_set(target, b[0], b[1], b[2], b[3])
	target.add_theme_color_override("font_color", INK)
	target.add_theme_color_override("font_hover_color", INK)
	target.add_theme_color_override("font_pressed_color", INK)
	target.add_theme_color_override("font_disabled_color", INK_FAINT)

# 小号次要按钮：嵌在标题行里，内边距和字号都压小，不把行高撑高
static func style_pill(target: Control) -> void:
	style_ghost(target)
	var b := _ghost_boxes(Vector4i(8, 1, 8, 1))
	_button_set(target, b[0], b[1], b[2], b[3])
	target.add_theme_font_size_override("font_size", 12)

# 主操作按钮：陶土暖色实底，每个界面仅用于最重要的一个动作；禁用时和次要按钮的禁用态一致
static func style_primary(target: Control) -> void:
	var pad := Vector4i(14, 7, 14, 7)
	_button_set(
		target,
		_flat(ACCENT, CLEAR, 0, CONTROL_RADIUS, pad),
		_flat(Color(0.867, 0.561, 0.396), CLEAR, 0, CONTROL_RADIUS, pad),
		_flat(ACCENT_DEEP, CLEAR, 0, CONTROL_RADIUS, pad),
		_flat(FILL_DISABLED, CLEAR, 0, CONTROL_RADIUS, pad)
	)
	target.add_theme_color_override("font_color", ACCENT_INK)
	target.add_theme_color_override("font_hover_color", ACCENT_INK)
	target.add_theme_color_override("font_pressed_color", Color(0.984, 0.945, 0.886))
	target.add_theme_color_override("font_disabled_color", INK_FAINT)

# ---- 分段控件 / 步进器（见 ui_segmented.gd / ui_stepper.gd） ----

# 分段控件的底槽：一条浅底，内缩 2 px 让选中块「嵌」在里面
static func segment_track_style() -> StyleBoxFlat:
	return _flat(FILL, CLEAR, 0, CONTROL_RADIUS, Vector4i(2, 2, 2, 2))

# 分段：未选中透明、文字偏灰；选中是浮起的近白块（带一点点阴影），文字转深
static func style_segment(target: Button, font_size := 12) -> void:
	var pad := Vector4i(9, 2, 9, 2)
	var on := _flat(SEGMENT_ON, CLEAR, 0, CONTROL_RADIUS - 2, pad)
	on.shadow_color = Color(0.157, 0.200, 0.200, 0.14)
	on.shadow_size = 2
	on.shadow_offset = Vector2(0, 1)
	target.add_theme_stylebox_override("normal", _flat(CLEAR, CLEAR, 0, CONTROL_RADIUS - 2, pad))
	target.add_theme_stylebox_override("hover", _flat(Color(0.157, 0.200, 0.200, 0.05), CLEAR, 0, CONTROL_RADIUS - 2, pad))
	target.add_theme_stylebox_override("pressed", on)
	target.add_theme_stylebox_override("hover_pressed", on)
	target.add_theme_stylebox_override("disabled", _flat(CLEAR, CLEAR, 0, CONTROL_RADIUS - 2, pad))
	target.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	target.add_theme_color_override("font_color", INK_SOFT)
	target.add_theme_color_override("font_hover_color", INK)
	target.add_theme_color_override("font_pressed_color", INK)
	target.add_theme_color_override("font_hover_pressed_color", INK)
	target.add_theme_font_size_override("font_size", font_size)

# 步进器整体：一块浅底装下「− 数值 +」
static func stepper_track_style() -> StyleBoxFlat:
	return _flat(FILL, CLEAR, 0, CONTROL_RADIUS, Vector4i(0, 0, 0, 0))

# 步进器两端的 − / +：透明底，悬停 / 按下才浮出一块更深的底
static func style_stepper_button(target: Button) -> void:
	var pad := Vector4i(6, 2, 6, 2)
	_button_set(
		target,
		_flat(CLEAR, CLEAR, 0, CONTROL_RADIUS, pad),
		_flat(FILL_HOVER, CLEAR, 0, CONTROL_RADIUS, pad),
		_flat(FILL_PRESSED, CLEAR, 0, CONTROL_RADIUS, pad),
		_flat(CLEAR, CLEAR, 0, CONTROL_RADIUS, pad)
	)
	target.add_theme_color_override("font_color", INK_SOFT)
	target.add_theme_color_override("font_hover_color", INK)
	target.add_theme_color_override("font_pressed_color", INK)
	target.add_theme_color_override("font_disabled_color", Color(INK_FAINT, 0.5))
	target.add_theme_font_size_override("font_size", 16)

# 步进器中间的数值：没有自己的底和框（和两端共用外面那块浅底），聚焦输入时才亮一圈
static func style_stepper_field(field: LineEdit) -> void:
	var pad := Vector4i(2, 5, 2, 5)
	field.add_theme_stylebox_override("normal", _flat(CLEAR, CLEAR, 0, CONTROL_RADIUS, pad))
	field.add_theme_stylebox_override("read_only", _flat(CLEAR, CLEAR, 0, CONTROL_RADIUS, pad))
	field.add_theme_stylebox_override("focus", _flat(Color(1.0, 0.996, 0.984), Color(POND, 0.55), 2, CONTROL_RADIUS, pad))
	field.add_theme_color_override("font_color", INK)
	field.add_theme_color_override("font_uneditable_color", INK_SOFT)
	field.add_theme_color_override("caret_color", POND)
	field.add_theme_color_override("selection_color", Color(0.819, 0.510, 0.346, 0.35))

# 深色外壳上的按钮：透明底 + 浅色文字，悬停才浮现淡描边。
# compact：手机竖屏顶栏只有 400 设计像素宽，收窄左右内边距。
static func style_chrome(target: Control, danger_hover: bool = false, compact: bool = false) -> void:
	var pad := Vector4i(6, 6, 6, 6) if compact else Vector4i(10, 6, 10, 6)
	var hover_fill := Color(0.776, 0.380, 0.318, 0.20) if danger_hover else Color(0.878, 0.902, 0.855, 0.12)
	var hover_border := Color(0.776, 0.380, 0.318, 0.55) if danger_hover else LINE_CHROME
	_button_set(
		target,
		_flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 5, pad),
		_flat(hover_fill, hover_border, 1, 5, pad),
		_flat(Color(0.878, 0.902, 0.855, 0.18), LINE_CHROME, 1, 5, pad),
		_flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 5, pad)
	)
	var on := Color(0.878, 0.502, 0.443) if danger_hover else INK_ON_CHROME
	target.add_theme_color_override("font_color", INK_ON_CHROME)
	target.add_theme_color_override("font_hover_color", on)
	target.add_theme_color_override("font_pressed_color", on)

# ---- 输入框 ----

static func style_input(line_edit: LineEdit) -> void:
	line_edit.add_theme_color_override("font_color", INK)
	line_edit.add_theme_color_override("font_placeholder_color", INK_FAINT)
	line_edit.add_theme_color_override("caret_color", POND)
	line_edit.add_theme_color_override("selection_color", Color(0.819, 0.510, 0.346, 0.35))
	line_edit.add_theme_stylebox_override("normal", input_style(false))
	line_edit.add_theme_stylebox_override("focus", input_style(true))

# ---- 进度条 ----

# 列表行里的小操作（任务的「改」「×」）：平时透明只留文字，悬停才浮出一块浅底；删除悬停转红
static func style_row_action(target: Button, danger := false) -> void:
	var pad := Vector4i(6, 2, 6, 2)
	_button_set(
		target,
		_flat(CLEAR, CLEAR, 0, CONTROL_RADIUS - 2, pad),
		_flat(Color(DANGER, 0.12) if danger else FILL_HOVER, CLEAR, 0, CONTROL_RADIUS - 2, pad),
		_flat(Color(DANGER, 0.2) if danger else FILL_PRESSED, CLEAR, 0, CONTROL_RADIUS - 2, pad),
		_flat(CLEAR, CLEAR, 0, CONTROL_RADIUS - 2, pad)
	)
	target.add_theme_color_override("font_color", INK_FAINT)
	target.add_theme_color_override("font_hover_color", DANGER if danger else INK)
	target.add_theme_color_override("font_pressed_color", DANGER if danger else INK)

# ---- 勾选圈 / 开关：逐像素画（带抗锯齿），替代引擎默认的灰方块和深灰开关 ----

static var _icons := {}

static func _icon(key: String, w: int, h: int, sample: Callable) -> ImageTexture:
	if _icons.has(key):
		return _icons[key]
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, sample.call(Vector2(x + 0.5, y + 0.5)))
	var tex := ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex

# src 叠在 dst 上（预乘前的普通 alpha 混合）
static func _over(dst: Color, src: Color) -> Color:
	var a := src.a + dst.a * (1.0 - src.a)
	if a <= 0.0:
		return CLEAR
	var k := dst.a * (1.0 - src.a)
	return Color((src.r * src.a + dst.r * k) / a, (src.g * src.a + dst.g * k) / a, (src.b * src.a + dst.b * k) / a, a)

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)

# 任务勾选：没勾是一圈淡墨色细环，勾上是水色实心圆 + 白勾（苹果「提醒事项」的样子）
static func check_icon(checked: bool, disabled := false) -> ImageTexture:
	var fade := 0.5 if disabled else 1.0
	return _icon("check_%s_%s" % [checked, disabled], 18, 18, func(p: Vector2) -> Color:
		var d := p.distance_to(Vector2(9, 9))
		if not checked:
			return Color(INK, 0.38 * fade * clampf(0.8 - absf(d - 7.2), 0.0, 1.0))
		var c := Color(POND, fade * clampf(8.0 - d, 0.0, 1.0))
		var m := minf(_seg_dist(p, Vector2(5.2, 9.3), Vector2(7.8, 11.9)), _seg_dist(p, Vector2(7.8, 11.9), Vector2(12.9, 6.6)))
		return _over(c, Color(1, 1, 1, fade * clampf(1.9 - m, 0.0, 1.0) * clampf(8.0 - d, 0.0, 1.0)))
	)

# 开关：胶囊底槽 + 白色圆钮；开 = 水色、钮在右，关 = 浅墨色、钮在左
static func switch_icon(on: bool, disabled := false) -> ImageTexture:
	var fade := 0.5 if disabled else 1.0
	return _icon("switch_%s_%s" % [on, disabled], 36, 20, func(p: Vector2) -> Color:
		var cover := clampf(0.5 - (_seg_dist(p, Vector2(10, 10), Vector2(26, 10)) - 9.0), 0.0, 1.0)
		var track := Color(POND, fade * cover) if on else Color(INK, 0.18 * fade * cover)
		var knob_c := Vector2(26, 10) if on else Vector2(10, 10)
		var kd := p.distance_to(knob_c)
		var shadow := Color(INK, 0.16 * fade * clampf(8.6 - p.distance_to(knob_c + Vector2(0, 0.6)), 0.0, 1.0))
		var knob := Color(1, 1, 1, fade * clampf(7.6 - kd, 0.0, 1.0))
		return _over(_over(track, shadow), knob)
	)

# 进度条：细长胶囊，底槽和控件同一层浅底
static func style_progress(bar: ProgressBar) -> void:
	bar.add_theme_stylebox_override("background", _flat(FILL, CLEAR, 0, 3, Vector4i.ZERO))
	bar.add_theme_stylebox_override("fill", _flat(POND, CLEAR, 0, 3, Vector4i.ZERO))

# ---- 全局主题：让整棵 UI 树共享极简底色 ----

const PIXEL_FONT := "res://assets/fonts/fusion-pixel-12px-proportional-zh_hans.otf.woff2"

# 桌面非 Windows 的默认字体：引擎自带字体画拉丁 / 数字，中文一律由打包的像素字体补（与 Web / 手机版一致）。
# 不依赖任何系统字体查找：GitHub Actions macOS 实测，自动系统回退给中文出豆腐块，
# 显式 SystemFont（苹方等）更是连数字都画不出来。
static func desktop_cjk_font() -> Font:
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	var fb: Array[Font] = [load(PIXEL_FONT)]
	f.fallbacks = fb
	return f

# 排查用：--font-debug 时打印字体解析情况（CI 日志里看）
static func font_debug_report() -> String:
	var lines := PackedStringArray()
	var d := desktop_cjk_font()
	lines.append("desktop_cjk_font has 中=%s A=%s" % [d.has_char("中".unicode_at(0)), d.has_char(65)])
	var pixel: Font = load(PIXEL_FONT)
	lines.append("pixel_font loaded=%s has 中=%s" % [pixel != null, pixel != null and pixel.has_char("中".unicode_at(0))])
	for n in ["PingFang SC", "Hiragino Sans GB", "Heiti SC", "Helvetica"]:
		var s := SystemFont.new()
		s.font_names = PackedStringArray([n])
		lines.append("SystemFont %s -> name=%s faces=%d has 中=%s" % [n, s.get_font_name(), s.get_face_count(), s.has_char("中".unicode_at(0))])
	lines.append("OS system fonts: %d" % OS.get_system_fonts().size())
	return "\n".join(lines)

static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	# Web 导出没有系统字体可回退，中文会整体缺字；
	# 打包的缝合像素字体（OFL）只在 Web 上启用，桌面端保持系统字体的既有观感。
	if OS.has_feature("web"):
		t.default_font = load(PIXEL_FONT)
	elif OS.get_name() != "Windows":
		# macOS / Linux：不能指望引擎自动借系统字体补中文——2026-09-29 GitHub Actions macOS 实测，
		# 导出版的中文全是豆腐块（Windows 上的自动回退一直正常，所以 Windows 保持原样不动）。
		t.default_font = desktop_cjk_font()

	# 文本
	t.set_color("font_color", "Label", INK)

	# 默认按钮 = 次要按钮：浅底、不描边，禁用时只是更淡
	var b := _ghost_boxes(Vector4i(12, 7, 12, 7))
	t.set_stylebox("normal", "Button", b[0])
	t.set_stylebox("hover", "Button", b[1])
	t.set_stylebox("pressed", "Button", b[2])
	t.set_stylebox("disabled", "Button", b[3])
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", INK_FAINT)

	# 输入框
	t.set_stylebox("normal", "LineEdit", input_style(false))
	t.set_stylebox("focus", "LineEdit", input_style(true))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", INK_FAINT)
	t.set_color("caret_color", "LineEdit", POND)
	t.set_color("selection_color", "LineEdit", Color(0.819, 0.510, 0.346, 0.35))

	# 面板
	t.set_stylebox("panel", "PanelContainer", panel_style())

	# 勾选类：勾选圈 / 胶囊开关用逐像素画的图标；勾选框本身不要底和框
	var empty := _flat(CLEAR, CLEAR, 0, CONTROL_RADIUS, Vector4i(2, 2, 2, 2))
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(st, "CheckBox", empty)
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	t.set_icon("checked", "CheckBox", check_icon(true))
	t.set_icon("unchecked", "CheckBox", check_icon(false))
	t.set_icon("checked_disabled", "CheckBox", check_icon(true, true))
	t.set_icon("unchecked_disabled", "CheckBox", check_icon(false, true))
	# 开关做成设置列表里的一行：浅底圆角，开 / 关不改底色
	var row := _ghost_boxes(Vector4i(10, 6, 10, 6))
	t.set_stylebox("normal", "CheckButton", row[0])
	t.set_stylebox("hover", "CheckButton", row[1])
	t.set_stylebox("pressed", "CheckButton", row[0])
	t.set_stylebox("hover_pressed", "CheckButton", row[1])
	t.set_stylebox("disabled", "CheckButton", row[3])
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	t.set_icon("checked", "CheckButton", switch_icon(true))
	t.set_icon("unchecked", "CheckButton", switch_icon(false))
	t.set_icon("checked_disabled", "CheckButton", switch_icon(true, true))
	t.set_icon("unchecked_disabled", "CheckButton", switch_icon(false, true))
	t.set_color("font_color", "CheckBox", INK)
	t.set_color("font_hover_color", "CheckBox", INK)
	t.set_color("font_pressed_color", "CheckBox", INK)
	t.set_color("font_color", "CheckButton", INK_ON_CHROME)
	t.set_color("font_hover_color", "CheckButton", INK_ON_CHROME)
	t.set_color("font_pressed_color", "CheckButton", INK_ON_CHROME)

	return t
