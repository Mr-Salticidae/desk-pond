extends UICard
class_name ShareCard

# 分享我的缸：实时生成一张卡片图（缸 + 缸名 + 星级 + 统计，App 内再加一枚二维码），
# 一键分享 / 保存 / 复制链接，不用再手动截图裁剪；也能粘贴朋友的分享码去他家看看。
# 卡片里的缸是用「分享码解出来的数据」画的——朋友点开看到的，就是这里预览的样子。

signal name_changed(new_name: String)
signal visit_requested(text: String)

const CARD_SIZE := Vector2i(600, 800)
const INK_LIGHT := Color(0.93, 0.97, 0.98)
const INK_SOFT := Color(0.80, 0.90, 0.93)
const STAR_ON := Color(0.98, 0.80, 0.30)
const STAR_OFF := Color(0.93, 0.97, 0.98, 0.22)
const DEFAULT_NAME := "我的生态缸"

var eco: EcoTank
var make_snapshot: Callable
var names: Dictionary = {}
var fish_data: Array = []
var snap: Dictionary = {}
var code := ""
var has_qr := false
var _copy_is_fallback := false

var card_vp: SubViewport
var card_title: Label
var card_stars: Control
var card_summary: Label
var card_tank: AquariumView
var card_hint: Label
var card_date: Label
var card_qr: TextureRect
var card_qr_bg: ColorRect

var preview: TextureRect
var name_edit: LineEdit
var share_button: Button
var save_button: Button
var copy_button: Button
var visit_edit: LineEdit
var status: Label
var qr_timer: Timer

func _ready() -> void:
	configure("分享我的缸", Vector2i(600, 490))
	_build_card()
	_build_content()
	WebShell.share_result.connect(_on_share_result)
	WebShell.qr_ready.connect(_on_qr)
	# 只在窗口开着时渲染卡片，关掉就停，不白白多跑一只缸
	visibility_changed.connect(func():
		card_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
	)

# ---------- 卡片图（离屏渲染）----------

func _build_card() -> void:
	card_vp = SubViewport.new()
	card_vp.size = CARD_SIZE
	card_vp.transparent_bg = false
	card_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(card_vp)

	var root := Control.new()
	root.theme = UITheme.make_theme()
	root.size = Vector2(CARD_SIZE)
	card_vp.add_child(root)

	var bg := ColorRect.new()
	bg.color = UITheme.BG_DEEP
	bg.size = Vector2(CARD_SIZE)
	root.add_child(bg)
	var band := ColorRect.new()
	band.color = UITheme.CHROME
	band.size = Vector2(CARD_SIZE.x, 136)
	root.add_child(band)

	card_title = _card_label(root, 30, INK_LIGHT, Vector2(32, 22))
	card_stars = Control.new()
	card_stars.position = Vector2(34, 72)
	card_stars.size = Vector2(160, 24)
	card_stars.draw.connect(func():
		var n := int(snap.get("stars", 0))
		for i in range(5):
			TankArt.draw_star(card_stars, Vector2(i * 32, 0), 3.0, STAR_ON if i < n else STAR_OFF)
	)
	root.add_child(card_stars)
	card_summary = _card_label(root, 15, INK_SOFT, Vector2(34, 102))

	card_tank = AquariumView.new()
	card_tank.position = Vector2(20, 148)
	card_tank.size = Vector2(560, 500)
	root.add_child(card_tank)
	card_tank.set_presentation(true, false, "")

	_card_label(root, 17, INK_LIGHT, Vector2(32, 666)).text = "工位池塘 · 你专注，它钓鱼"
	card_hint = _card_label(root, 13, INK_SOFT, Vector2(32, 696))
	card_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_hint.size = Vector2(390, 60)
	card_date = _card_label(root, 12, Color(INK_SOFT, 0.6), Vector2(32, 762))

	card_qr_bg = ColorRect.new()
	card_qr_bg.color = Color(0.98, 0.97, 0.94)
	card_qr_bg.position = Vector2(448, 660)
	card_qr_bg.size = Vector2(124, 124)
	card_qr_bg.visible = false
	root.add_child(card_qr_bg)
	card_qr = TextureRect.new()
	card_qr.position = Vector2(452, 664)
	card_qr.size = Vector2(116, 116)
	card_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_qr.visible = false
	root.add_child(card_qr)

func _card_label(parent: Control, font_size: int, color: Color, pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l

# ---------- 窗口内容 ----------

func _build_content() -> void:
	var narrow := size.x < 480
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var box := BoxContainer.new()
	box.vertical = narrow
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 14)
	scroll.add_child(box)

	preview = TextureRect.new()
	preview.texture = card_vp.get_texture()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(0, 230) if narrow else Vector2(240, 320)
	box.add_child(preview)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	box.add_child(col)

	col.add_child(_label("给你的缸起个名字", 13, UITheme.INK_SOFT))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = DEFAULT_NAME
	name_edit.max_length = EcoShare.MAX_NAME_CHARS
	UITheme.style_input(name_edit)
	name_edit.text_changed.connect(_on_name_edited)
	col.add_child(name_edit)
	WebInput.attach("tank_name", name_edit)

	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 6)
	col.add_child(buttons)
	share_button = _action("分享给朋友", _on_share_pressed, true)
	buttons.add_child(share_button)
	save_button = _action("保存图片", _on_save_pressed, false)
	buttons.add_child(save_button)
	copy_button = _action("复制链接", _on_copy_pressed, false)
	buttons.add_child(copy_button)

	# 操作结果紧跟在按钮下面：手机上卡片要滚动，放在底部会看不到
	status = _label("", 12, UITheme.POND)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(status)

	var link_share := OS.has_feature("web") or EcoShare.SHARE_WEB_URL != ""
	var note := _label("朋友打开链接就能逛你的缸、帮你喂鱼，不用装任何东西。" if link_share
		else "朋友在工位池塘（电脑版或 B站 手机版）里粘贴分享码，就能逛你的缸、帮你喂鱼。", 12, UITheme.INK_FAINT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)

	col.add_child(HSeparator.new())
	col.add_child(_label("去朋友家看看", 13, UITheme.INK_SOFT))
	var visit_row := HBoxContainer.new()
	visit_row.add_theme_constant_override("separation", 6)
	col.add_child(visit_row)
	visit_edit = LineEdit.new()
	visit_edit.placeholder_text = "粘贴朋友的分享码或链接"
	visit_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_input(visit_edit)
	visit_edit.text_submitted.connect(func(t: String): visit_requested.emit(t))
	visit_row.add_child(visit_edit)
	WebInput.attach("visit_code", visit_edit)
	visit_row.add_child(_action("去看看", func(): visit_requested.emit(visit_edit.text), false))

	qr_timer = Timer.new()
	qr_timer.one_shot = true
	qr_timer.wait_time = 0.8
	qr_timer.timeout.connect(_request_qr)
	add_child(qr_timer)

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

func _action(text: String, cb: Callable, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if primary:
		UITheme.style_primary(b)
	b.pressed.connect(cb)
	return b

# ---------- 打开 / 刷新 ----------

# snapshot_fn(name) -> 快照字典（EcoShare.snapshot），由 main 提供，保证用的是最新的缸
func open_card(tank: EcoTank, snapshot_fn: Callable, fish_names: Dictionary, fish_list: Array, tank_name: String) -> void:
	eco = tank
	make_snapshot = snapshot_fn
	names = fish_names
	fish_data = fish_list
	name_edit.text = tank_name
	visit_edit.text = ""
	say("", UITheme.POND)
	_regen()
	_update_buttons()
	popup_centered()
	_request_qr()

func say(text: String, color: Color = UITheme.POND) -> void:
	status.text = text
	status.add_theme_color_override("font_color", color)

func _on_name_edited(text: String) -> void:
	name_changed.emit(EcoShare.clean_name(text))
	_regen()
	qr_timer.start()

func _regen() -> void:
	var tank_name := EcoShare.clean_name(name_edit.text)
	snap = make_snapshot.call(tank_name if tank_name != "" else DEFAULT_NAME)
	code = EcoShare.encode(snap, eco)
	card_title.text = String(snap.get("name", DEFAULT_NAME))
	card_summary.text = EcoShare.summary(snap)
	card_stars.queue_redraw()
	var tank := EcoShare.build_tank(snap, fish_data)
	card_tank.update_tank(tank, EcoShare.build_eval(snap, tank), names, snap.get("levels", {}))
	card_date.text = Time.get_date_string_from_system()
	_update_hint()

func _update_hint() -> void:
	if has_qr:
		card_hint.text = "扫码逛我的缸，还能帮我喂鱼。"
	elif _share_url() != "":
		# 桌面版没有二维码（B站 App 的 getQrCode 只在 Toy 里有），但分享文字里带可点开的链接
		card_hint.text = "点开我发的链接，就能逛我的缸、帮我喂鱼。"
	else:
		card_hint.text = "打开「工位池塘」→ 水族馆 → 分享 → 去朋友家看看，粘贴分享码就能逛我的缸。"

func _update_buttons() -> void:
	var web := OS.has_feature("web")
	share_button.visible = web and (WebShell.can_toy_share or WebShell.can_native_share)
	if web:
		save_button.text = "存到相册" if WebShell.can_save_album else "下载图片"
		copy_button.text = "复制链接"
	else:
		save_button.text = "保存图片"
		copy_button.text = "复制链接" if EcoShare.SHARE_WEB_URL != "" else "复制分享码"

# ---------- 分享动作 ----------

func _share_url() -> String:
	# 固定落地页优先（见 EcoShare.SHARE_WEB_URL 的说明）；没配才退回当前页面地址
	if EcoShare.SHARE_WEB_URL != "":
		return "%s?%s=%s" % [EcoShare.SHARE_WEB_URL, EcoShare.PARAM, code]
	if OS.has_feature("web"):
		return WebShell.page_link(code)
	return ""

func _share_text() -> String:
	var head := "来逛逛我的生态缸「%s」（%d 星 · %s）" % [String(snap.get("name", DEFAULT_NAME)), int(snap.get("stars", 0)), EcoShare.summary(snap)]
	var url := _share_url()
	if url != "":
		return head + "\n" + url
	return head + "\n打开「工位池塘」→ 水族馆 → 分享 → 去朋友家看看，粘贴这段分享码：\n" + code

func _card_png() -> PackedByteArray:
	var img := card_vp.get_texture().get_image()
	return img.save_png_to_buffer() if img != null else PackedByteArray()

func _on_share_pressed() -> void:
	var png := _card_png()
	WebShell.share(EcoShare.share_path(code), _share_url(), "工位池塘 · 我的生态缸", _share_text(), Marshalls.raw_to_base64(png))
	say("正在打开分享……")

func _on_save_pressed() -> void:
	var png := _card_png()
	if png.is_empty():
		say("卡片还没画好，稍等一下再试", UITheme.DANGER)
		return
	if OS.has_feature("web"):
		WebShell.save_image(Marshalls.raw_to_base64(png), "desk-pond-tank.png")
		return
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if dir == "":
		dir = OS.get_user_data_dir()
	dir = dir.path_join("工位池塘")
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("T", "-")
	var path := dir.path_join("生态缸-%s.png" % stamp)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		say("保存失败：%s" % error_string(FileAccess.get_open_error()), UITheme.DANGER)
		return
	f.store_buffer(png)
	f.close()
	say("已保存到 %s" % path)
	OS.shell_show_in_file_manager(path)

func _on_copy_pressed() -> void:
	if OS.has_feature("web"):
		WebShell.copy_text(_share_text())
		return
	DisplayServer.clipboard_set(_share_text())
	say("已复制，粘贴给朋友吧" if EcoShare.SHARE_WEB_URL != "" else "已复制分享码和说明，朋友在工位池塘里粘贴就能来逛")

func _on_share_result(kind: String, ok: bool, detail: String) -> void:
	if not visible:
		return
	match kind:
		"share":
			if ok:
				say("已打开分享面板")
			elif detail == "AbortError":
				say("已取消分享", UITheme.INK_SOFT)
			else:
				# 这个环境拉不起分享面板：退一步，把文案和链接复制下来
				_copy_is_fallback = true
				WebShell.copy_text(_share_text())
		"save":
			if ok:
				say("已存到相册" if detail == "album" else "图片已下载")
			else:
				say("保存没成功，可以长按预览图保存，或改用「复制链接」", UITheme.DANGER)
		"copy":
			var fallback := _copy_is_fallback
			_copy_is_fallback = false
			if ok:
				say("这里拉不起分享面板，已把链接复制好，直接粘贴给朋友吧" if fallback else "链接已复制，粘贴给朋友吧")
			else:
				say("复制没成功，可以长按选中下面的链接手动复制：\n" + _share_url(), UITheme.DANGER)

func _request_qr() -> void:
	if OS.has_feature("web") and WebShell.can_qr and code != "":
		WebShell.request_qr(EcoShare.share_path(code), 240)

func _on_qr(img: Image) -> void:
	card_qr.texture = ImageTexture.create_from_image(img)
	card_qr.visible = true
	card_qr_bg.visible = true
	has_qr = true
	_update_hint()
