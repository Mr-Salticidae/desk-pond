extends Control
class_name DailyChart

# 档案里的「最近 14 天」：一排小柱，高度 = 当天专注分钟。
# 不做连胜、不标红：空白的日子只是一根没有高度的柱子；开始记录之前的日子只留一条虚线底。
# 点一根柱子（或悬停）看那天的专注、任务和钓获。

signal day_selected(row: Dictionary)

const BAR_GAP := 4.0
const LABEL_H := 16.0
const BAR := Color(0.227, 0.560, 0.639)            # UITheme.POND
const BAR_TODAY := Color(0.819, 0.510, 0.346)      # UITheme.ACCENT
const BASELINE := Color(0.157, 0.200, 0.200, 0.18)
const NOT_RECORDED := Color(0.157, 0.200, 0.200, 0.10)
const SELECT := Color(0.157, 0.200, 0.200, 0.08)

var rows: Array = []
var selected := -1

func _init() -> void:
	custom_minimum_size = Vector2(0, 96)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 有内容才会触发 _get_tooltip
	tooltip_text = " "

func set_rows(new_rows: Array) -> void:
	rows = new_rows
	selected = rows.size() - 1
	queue_redraw()

func _bar_rect(i: int) -> Rect2:
	var n := maxi(rows.size(), 1)
	var w := (size.x - BAR_GAP * (n - 1)) / n
	return Rect2(Vector2(i * (w + BAR_GAP), 0), Vector2(w, size.y - LABEL_H))

func _index_at(pos: Vector2) -> int:
	for i in range(rows.size()):
		var r := _bar_rect(i)
		if pos.x >= r.position.x - BAR_GAP * 0.5 and pos.x <= r.end.x + BAR_GAP * 0.5:
			return i
	return -1

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := _index_at(event.position)
		if i >= 0:
			selected = i
			queue_redraw()
			day_selected.emit(rows[i])
			accept_event()

func _get_tooltip(at_position: Vector2) -> String:
	var i := _index_at(at_position)
	return describe(rows[i]) if i >= 0 else ""

static func describe(row: Dictionary) -> String:
	var date := String(row.get("date", ""))
	var parts := date.split("-")
	var day := "%d月%d日" % [int(parts[1]), int(parts[2])] if parts.size() == 3 else date
	if not bool(row.get("recorded", true)):
		return "%s · 这天还没开始记录" % day
	if int(row.get("n", 0)) == 0 and int(row.get("t", 0)) == 0:
		return "%s · 这天池塘在休息" % day
	var bits: Array = []
	if int(row.get("n", 0)) > 0:
		var m := int(row.get("m", 0))
		bits.append("专注 %d 分钟（%d 次）" % [m, int(row["n"])] if m > 0 else "专注 %d 次" % int(row["n"]))
	if int(row.get("t", 0)) > 0:
		bits.append("完成 %d 个任务" % int(row["t"]))
	if int(row.get("fish", 0)) > 0:
		bits.append("钓到 %d 条鱼" % int(row["fish"]))
	if int(row.get("s", 0)) > 0:
		bits.append("贝壳 +%d" % int(row["s"]))
	return "%s · %s" % [day, " · ".join(bits)]

func _draw() -> void:
	if rows.is_empty():
		return
	var peak := 1
	for row in rows:
		peak = maxi(peak, _height_value(row))
	var font := get_theme_default_font()
	var font_size := 10
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var r := _bar_rect(i)
		var base_y := r.end.y
		if i == selected:
			draw_rect(Rect2(r.position - Vector2(BAR_GAP * 0.5, 0), r.size + Vector2(BAR_GAP, LABEL_H)), SELECT)
		if not bool(row.get("recorded", true)):
			# 开始记录之前：一截虚线底，不画柱子
			var x := r.position.x
			while x < r.end.x:
				draw_rect(Rect2(Vector2(x, base_y - 1), Vector2(minf(3.0, r.end.x - x), 1)), NOT_RECORDED)
				x += 5.0
		else:
			draw_rect(Rect2(Vector2(r.position.x, base_y - 1), Vector2(r.size.x, 1)), BASELINE)
			var v := _height_value(row)
			if v > 0:
				var h := maxf(3.0, (r.size.y - 4.0) * float(v) / float(peak))
				var color := BAR_TODAY if i == rows.size() - 1 else BAR
				draw_rect(Rect2(Vector2(r.position.x, base_y - h), Vector2(r.size.x, h)), color)
		# 日期：只写「几号」；1 号和今天写成「月/日」
		var parts := String(row.get("date", "")).split("-")
		if parts.size() == 3:
			var label := str(int(parts[2]))
			if int(parts[2]) == 1 or i == rows.size() - 1:
				label = "%d/%d" % [int(parts[1]), int(parts[2])]
			var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			draw_string(font, Vector2(r.get_center().x - tw * 0.5, size.y - 3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.451, 0.482, 0.455))

# 柱高按专注分钟；旧存档补的那一天只知道次数，按每次 25 分钟估一个高度，不至于空着
func _height_value(row: Dictionary) -> int:
	var m := int(row.get("m", 0))
	if m > 0:
		return m
	return int(row.get("n", 0)) * 25
