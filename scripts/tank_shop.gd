extends UICard
class_name TankShop

# 水族商店：用贝壳买水草 / 造景 / 装饰 / 设备 / 小生物，或扩缸。
# 每件东西都标出对生态的贡献（氧 / 净 / 美），让「买什么」本身就是一次小决策。

signal changed   # 买了东西或扩了缸：main 负责存档、刷新缸体

const CATEGORIES := [
	["plant", "水草"],
	["scape", "造景"],
	["decor", "装饰"],
	["gear", "设备"],
	["critter", "生物"],
	["tank", "扩缸"],
]

var eco: EcoTank
var ctx: Dictionary = {}
var category := "plant"
var header_label: Label
var tabs: Dictionary = {}
var list: VBoxContainer
var feedback: Label

func _ready() -> void:
	configure("水族商店", Vector2i(470, 480))
	_build_content()

func open_shop(tank: EcoTank, context: Dictionary) -> void:
	eco = tank
	ctx = context
	feedback.text = "专注满 5 分钟、完成任务、收集珍珠都能得到贝壳"
	feedback.add_theme_color_override("font_color", UITheme.INK_FAINT)
	_render()
	popup_centered()

# 外部数据变化（钓到鱼、树长大……）时刷新解锁状态
func refresh(context: Dictionary) -> void:
	ctx = context
	if visible:
		_render()

func _build_content() -> void:
	header_label = Label.new()
	header_label.add_theme_font_size_override("font_size", 14)
	header_label.add_theme_color_override("font_color", UITheme.INK)
	body.add_child(header_label)

	var tab_row := HFlowContainer.new()
	tab_row.add_theme_constant_override("h_separation", 4)
	tab_row.add_theme_constant_override("v_separation", 4)
	body.add_child(tab_row)
	var group := ButtonGroup.new()
	for c in CATEGORIES:
		var tab := Button.new()
		tab.text = String(c[1])
		tab.toggle_mode = true
		tab.button_group = group
		tab.focus_mode = Control.FOCUS_NONE
		var cat := String(c[0])
		tab.toggled.connect(func(on: bool):
			if on:
				category = cat
				_render()
		)
		tab_row.add_child(tab)
		tabs[cat] = tab
	tabs[category].set_pressed_no_signal(true)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_font_size_override("font_size", 12)
	body.add_child(feedback)

func _render() -> void:
	if eco == null or list == null:
		return
	header_label.text = "贝壳 %d    生态最佳 %d 星    %s" % [eco.shells(), int(eco.state.get("best_stars", 0)), String(eco.level_info(eco.tank_level()).get("name", ""))]
	for child in list.get_children():
		child.queue_free()
	if category == "tank":
		_render_tanks()
		return
	for it in eco.items:
		if String(it.get("category", "")) == category:
			list.add_child(_item_row(it))

func _item_row(it: Dictionary) -> Control:
	var id := String(it["id"])
	var row := _row_shell()
	var hbox: HBoxContainer = row.get_child(0)

	var icon := TankIcon.new().setup("item", id)
	icon.custom_minimum_size = Vector2(56, 46)
	hbox.add_child(icon)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	hbox.add_child(info)
	var owned := eco.owned_count(id)
	var name_label := _label(String(it.get("name", id)) + ("   已有 %d" % owned if owned > 0 else ""), 14, UITheme.INK)
	info.add_child(name_label)
	info.add_child(_label(_stats_text(it), 12, UITheme.POND))
	var desc := _label(String(it.get("desc", "")), 12, UITheme.INK_SOFT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc)

	var lock := eco.unlock_state(id, ctx)
	var buy := Button.new()
	buy.focus_mode = Control.FOCUS_NONE
	buy.custom_minimum_size = Vector2(76, 0)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if bool(lock["ok"]):
		var price := eco.price_of(id)
		buy.text = "%d 贝壳" % price
		UITheme.style_primary(buy)
		buy.disabled = price > eco.shells()
		buy.tooltip_text = "买一件放进库存"
		buy.pressed.connect(_on_buy.bind(id))
	else:
		buy.text = "未解锁"
		buy.disabled = true
		buy.tooltip_text = String(lock["label"])
		var why := _label(String(lock["label"]), 11, UITheme.INK_FAINT)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(why)
	hbox.add_child(buy)
	return row

func _render_tanks() -> void:
	var cur := eco.tank_level()
	for i in range(eco.tank_levels.size()):
		var lv := eco.level_info(i)
		var row := _row_shell()
		var hbox: HBoxContainer = row.get_child(0)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(info)
		info.add_child(_label("%s · 住得下 %d 条鱼" % [String(lv.get("name", "")), int(lv.get("capacity", 0))], 14, UITheme.INK))
		var note := "缸越大，基础氧气和自净越多；鱼多了也更需要照料。"
		if i == 0:
			note = "最初的小缸，一切从这里开始。"
		# 不换行的 Label 会按整行文字撑出最小宽度，Web 竖屏卡片只有 384 宽，会把右侧按钮挤出卡片
		var note_label := _label(note, 12, UITheme.INK_SOFT)
		note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(note_label)
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(88, 0)
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if i < cur:
			btn.text = "已换过"
			btn.disabled = true
		elif i == cur:
			btn.text = "使用中"
			btn.disabled = true
		elif i == cur + 1:
			var need := int(lv.get("stars", 0))
			if int(eco.state.get("best_stars", 0)) < need:
				btn.text = "未解锁"
				btn.disabled = true
				var why := _label("生态 %d 星解锁" % need, 11, UITheme.INK_FAINT)
				why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				info.add_child(why)
			else:
				btn.text = "%d 贝壳" % int(lv.get("price", 0))
				UITheme.style_primary(btn)
				btn.disabled = int(lv.get("price", 0)) > eco.shells()
				btn.pressed.connect(_on_upgrade)
		else:
			btn.text = "先换上一级"
			btn.disabled = true
		hbox.add_child(btn)
		list.add_child(row)

func _row_shell() -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.SURFACE_2))
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)
	return row

func _stats_text(it: Dictionary) -> String:
	var parts: Array = []
	for pair in [["oxygen", "氧"], ["clean", "净"], ["beauty", "美"]]:
		var v := int(it.get(String(pair[0]), 0))
		if v != 0:
			parts.append("%s +%d" % [String(pair[1]), v])
	return " · ".join(parts) if not parts.is_empty() else "纯观赏"

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

func _on_buy(id: String) -> void:
	var err := eco.buy(id, ctx)
	if err == "":
		_say("买好了！去水族馆点「布置」，把%s摆进缸里" % String(eco.item(id).get("name", "")), UITheme.POND)
		Audio.play_task_done()
		changed.emit()
	else:
		_say(err, UITheme.DANGER)
	_render()

func _on_upgrade() -> void:
	var err := eco.upgrade_tank()
	if err == "":
		_say("换上了%s，池塘里的鱼可以多搬几条进来了" % String(eco.level_info(eco.tank_level()).get("name", "")), UITheme.POND)
		Audio.play_chime()
		changed.emit()
	else:
		_say(err, UITheme.DANGER)
	_render()

func _say(text: String, color: Color) -> void:
	feedback.text = text
	feedback.add_theme_color_override("font_color", color)
