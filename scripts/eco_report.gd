extends UICard
class_name EcoReport

# 生态报告：把缸的评分拆开讲清楚——氧气 / 水质 / 美观 / 生机分别从哪来、下一步做什么。
# 数值都来自 EcoTank.evaluate，这里只负责展示。

signal share_requested

var content: VBoxContainer

func _ready() -> void:
	configure("生态报告", Vector2i(380, 470))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)

func show_report(ev: Dictionary, visitor_names: Dictionary) -> void:
	for child in content.get_children():
		child.queue_free()
	var stars := int(ev.get("stars", 0))
	_line("当前 %d 星 · 评分 %d" % [stars, int(ev.get("score", 0))], 16, UITheme.INK)
	var next := int(ev.get("next_star_score", 0))
	if next > 0:
		var prev := int(ev.get("prev_star_score", 0))
		_bar(float(int(ev.get("score", 0)) - prev) / float(maxi(next - prev, 1)) * 100.0, UITheme.ACCENT)
		_line("再得 %d 分升到 %d 星（历史最佳 %d 星，解锁只看最佳）" % [next - int(ev.get("score", 0)), stars + 1, int(ev.get("best_stars", 0))], 12, UITheme.INK_SOFT)
	else:
		_line("满星了！往后是扩缸、集访客、把每种鱼养到 Lv.5。", 12, UITheme.INK_SOFT)

	_section("水质平衡")
	_line("氧气 %d%%" % int(ev.get("oxygen", 100)), 13, UITheme.INK)
	_bar(float(ev.get("oxygen", 100)), UITheme.POND)
	_line("水质 %d%%" % int(ev.get("clean", 100)), 13, UITheme.INK)
	_bar(float(ev.get("clean", 100)), UITheme.POND)
	_line("鱼越多越大，耗氧和排泄越多；水草、气泡石造氧，螺、虾、过滤器净水。失衡时评分打折（最多打五折），鱼不会有事。", 12, UITheme.INK_SOFT, true)

	_section("评分构成")
	_line("美观 %d 分 · 生机 %d 分 · 平衡系数 ×%.2f" % [int(ev.get("beauty", 0)), int(ev.get("life", 0)), float(ev.get("balance", 1.0))], 13, UITheme.INK)
	var sets: Array = ev.get("sets", [])
	if sets.is_empty():
		_line("主题套组：还没有集齐的。凑齐一组（比如「沉船 + 宝箱」）有额外美观分。", 12, UITheme.INK_SOFT, true)
	else:
		var names: Array = sets.map(func(s): return "%s +%d" % [String(s.get("name", "")), int(s.get("bonus", 0))])
		_line("主题套组：" + "、".join(names), 12, UITheme.INK_SOFT, true)
	for note in ev.get("trait_notes", []):
		_line("· " + String(note), 12, UITheme.INK_SOFT, true)

	var present: Array = ev.get("visitors_present", [])
	if not present.is_empty():
		_section("在缸里的访客")
		_line("、".join(present.map(func(id): return String(visitor_names.get(id, id)))), 13, UITheme.INK, true)

	var hints: Array = ev.get("hints", [])
	if not hints.is_empty():
		_section("小建议")
		for h in hints:
			_line("· " + String(h), 12, UITheme.INK_SOFT, true)

	content.add_child(HSeparator.new())
	var share := Button.new()
	share.text = "分享我的缸"
	share.focus_mode = Control.FOCUS_NONE
	share.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UITheme.style_primary(share)
	share.pressed.connect(func(): share_requested.emit())
	content.add_child(share)
	popup_centered()

func _section(title: String) -> void:
	var sep := HSeparator.new()
	content.add_child(sep)
	_line(title, 14, UITheme.INK)

func _line(text: String, font_size: int, color: Color, wrap := false) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(l)

func _bar(value: float, color: Color) -> void:
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = clampf(value, 0.0, 100.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 6)
	UITheme.style_progress(bar)
	bar.add_theme_stylebox_override("fill", UITheme._flat(color, Color(0, 0, 0, 0), 0, 6, Vector4i.ZERO))
	content.add_child(bar)
