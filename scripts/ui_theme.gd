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

static func panel_style(fill: Color = SURFACE) -> StyleBoxFlat:
	return _flat(fill, LINE, 1, RADIUS, Vector4i(14, 12, 14, 12))

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

static func input_style(focused: bool = false) -> StyleBoxFlat:
	var border := POND if focused else LINE
	return _flat(Color(1.0, 0.992, 0.965) if focused else SURFACE_2, border, 1 if not focused else 2, 5, Vector4i(10, 7, 10, 7))

# ---- 按钮风格 ----

static func _button_set(target: Control, normal: StyleBoxFlat, hover: StyleBoxFlat, pressed: StyleBoxFlat, disabled: StyleBoxFlat) -> void:
	target.add_theme_stylebox_override("normal", normal)
	target.add_theme_stylebox_override("hover", hover)
	target.add_theme_stylebox_override("pressed", pressed)
	target.add_theme_stylebox_override("disabled", disabled)
	target.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

# 幽灵按钮：纸面上的次要操作，扁平 + 发丝描边
static func style_ghost(target: Control) -> void:
	var pad := Vector4i(12, 7, 12, 7)
	_button_set(
		target,
		_flat(SURFACE_2, LINE, 1, 5, pad),
		_flat(Color(0.945, 0.933, 0.898), Color(0.157, 0.200, 0.200, 0.30), 1, 5, pad),
		_flat(SURFACE_3, Color(0.157, 0.200, 0.200, 0.30), 1, 5, pad),
		_flat(SURFACE_2, LINE, 1, 5, pad)
	)
	target.add_theme_color_override("font_color", INK)
	target.add_theme_color_override("font_hover_color", INK)
	target.add_theme_color_override("font_pressed_color", INK)
	target.add_theme_color_override("font_disabled_color", INK_FAINT)

# 主操作按钮：陶土暖色实底，每个界面仅用于最重要的一个动作
static func style_primary(target: Control) -> void:
	var pad := Vector4i(14, 7, 14, 7)
	_button_set(
		target,
		_flat(ACCENT, ACCENT, 0, 5, pad),
		_flat(Color(0.867, 0.561, 0.396), ACCENT, 0, 5, pad),
		_flat(ACCENT_DEEP, ACCENT_DEEP, 0, 5, pad),
		_flat(Color(0.812, 0.776, 0.741), Color(0.812, 0.776, 0.741), 0, 5, pad)
	)
	target.add_theme_color_override("font_color", ACCENT_INK)
	target.add_theme_color_override("font_hover_color", ACCENT_INK)
	target.add_theme_color_override("font_pressed_color", Color(0.984, 0.945, 0.886))
	target.add_theme_color_override("font_disabled_color", Color(0.953, 0.945, 0.918, 0.7))

# 深色外壳上的按钮：透明底 + 浅色文字，悬停才浮现淡描边
static func style_chrome(target: Control, danger_hover: bool = false) -> void:
	var pad := Vector4i(10, 6, 10, 6)
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

static func style_progress(bar: ProgressBar) -> void:
	bar.add_theme_stylebox_override("background", _flat(SURFACE_3, Color(0, 0, 0, 0), 0, 6, Vector4i.ZERO))
	bar.add_theme_stylebox_override("fill", _flat(POND, Color(0, 0, 0, 0), 0, 6, Vector4i.ZERO))

# ---- 全局主题：让整棵 UI 树共享极简底色 ----

static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	# Web 导出没有系统字体可回退，中文会整体缺字；
	# 打包的缝合像素字体（OFL）只在 Web 上启用，桌面端保持系统字体的既有观感。
	if OS.has_feature("web"):
		t.default_font = load("res://assets/fonts/fusion-pixel-12px-proportional-zh_hans.otf.woff2")

	# 文本
	t.set_color("font_color", "Label", INK)

	# 默认按钮 = 幽灵风格
	var pad := Vector4i(12, 7, 12, 7)
	t.set_stylebox("normal", "Button", _flat(SURFACE_2, LINE, 1, 5, pad))
	t.set_stylebox("hover", "Button", _flat(Color(0.945, 0.933, 0.898), Color(0.157, 0.200, 0.200, 0.30), 1, 5, pad))
	t.set_stylebox("pressed", "Button", _flat(SURFACE_3, Color(0.157, 0.200, 0.200, 0.30), 1, 5, pad))
	t.set_stylebox("disabled", "Button", _flat(Color(0.918, 0.906, 0.882), LINE, 1, 5, pad))
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

	# 勾选类
	t.set_color("font_color", "CheckBox", INK)
	t.set_color("font_hover_color", "CheckBox", INK)
	t.set_color("font_pressed_color", "CheckBox", INK)
	t.set_color("font_color", "CheckButton", INK_ON_CHROME)
	t.set_color("font_hover_color", "CheckButton", INK_ON_CHROME)
	t.set_color("font_pressed_color", "CheckButton", INK_ON_CHROME)

	return t
