extends RefCounted
class_name TankArt

# 生态缸的全部像素画：物件 / 小生物 / 鱼 / 访客都用矩形拼出来，
# 缸体、商店图标、库存条共用这一套。尺寸以「1 倍像素」为单位，s 为缩放；
# 物件以「底边中点」为锚（浮萍以水面为锚），鱼和访客以中心为锚。

# 物件的 1 倍包围盒（宽, 高），用于点选与图标取景
const ITEM_SIZES := {
	"grass": Vector2(16, 22),
	"hornwort": Vector2(12, 46),
	"sword": Vector2(26, 30),
	"moss_ball": Vector2(12, 11),
	"duckweed": Vector2(30, 9),
	"rock": Vector2(24, 12),
	"stone_stack": Vector2(18, 24),
	"driftwood": Vector2(42, 26),
	"seashell": Vector2(13, 10),
	"coral": Vector2(22, 24),
	"anemone": Vector2(18, 16),
	"diver": Vector2(16, 28),
	"castle": Vector2(34, 38),
	"chest": Vector2(18, 16),
	"shipwreck": Vector2(46, 32),
	"airstone": Vector2(12, 6),
	"filter": Vector2(14, 26),
	"snail": Vector2(11, 9),
	"shrimp": Vector2(12, 6),
}

const VISITOR_SIZES := {
	"hermit_crab": Vector2(14, 11),
	"seahorse": Vector2(10, 18),
	"goby": Vector2(13, 6),
	"clownfish": Vector2(13, 8),
	"octopus": Vector2(16, 16),
	"axolotl": Vector2(20, 9),
	"jellyfish": Vector2(14, 24),
	"turtle": Vector2(26, 12),
}

# 每种鱼的体色：[主色, 鳍/尾色]
const FISH_COLORS := {
	"slacking_crucian": [Color(0.55, 0.62, 0.42), Color(0.42, 0.50, 0.32)],
	"salted_fish": [Color(0.78, 0.74, 0.70), Color(0.62, 0.58, 0.55)],
	"meeting_carp": [Color(0.85, 0.55, 0.30), Color(0.70, 0.42, 0.22)],
	"commute_sardine": [Color(0.62, 0.70, 0.78), Color(0.48, 0.56, 0.66)],
	"keyboard_loach": [Color(0.50, 0.42, 0.30), Color(0.38, 0.32, 0.22)],
	"deadline_goldfish": [Color(0.97, 0.66, 0.22), Color(0.88, 0.46, 0.16)],
	"weekly_pufferfish": [Color(0.86, 0.78, 0.45), Color(0.70, 0.62, 0.34)],
	"overtime_eel": [Color(0.34, 0.30, 0.42), Color(0.24, 0.22, 0.30)],
	"annual_koi": [Color(0.97, 0.55, 0.30), Color(0.95, 0.95, 0.95)],
	"slacking_legend": [Color(0.95, 0.80, 0.30), Color(0.80, 0.62, 0.18)],
}

const PLANT := Color(0.24, 0.55, 0.33)
const PLANT_SOFT := Color(0.33, 0.66, 0.40)
const PLANT_DARK := Color(0.17, 0.42, 0.27)
const PLANT_LIGHT := Color(0.52, 0.78, 0.45)
const STONE := Color(0.56, 0.58, 0.58)
const STONE_LIGHT := Color(0.70, 0.72, 0.70)
const STONE_DARK := Color(0.40, 0.42, 0.43)
const WOOD := Color(0.47, 0.33, 0.22)
const WOOD_DARK := Color(0.34, 0.23, 0.15)
const EYE := Color(0.08, 0.10, 0.12)

# ---- 绘制上下文（一次只画一个物件，用静态变量省去层层传参）----
static var _ci: CanvasItem
static var _base := Vector2.ZERO
static var _s := 1.0
static var _flip := false
static var _tint := Color(0, 0, 0, 0)   # rgb = 目标色，a = 混合量（景深 / 剪影）
static var _alpha := 1.0

static func _begin(ci: CanvasItem, base: Vector2, s: float, flip: bool, tint: Color, alpha: float) -> void:
	_ci = ci
	_base = base
	_s = s
	_flip = flip
	_tint = tint
	_alpha = alpha

static func _col(c: Color) -> Color:
	var out := c
	if _tint.a > 0.0:
		out = Color(c.r, c.g, c.b).lerp(Color(_tint.r, _tint.g, _tint.b), _tint.a)
	out.a = c.a * _alpha
	return out

# 以锚点为原点、1 倍像素为单位画矩形；翻转时以锚点竖线为轴镜像。
static func _r(x: float, y: float, w: float, h: float, c: Color) -> void:
	var lx := -x - w if _flip else x
	var pos := Vector2(_base.x + lx * _s, _base.y + y * _s).round()
	var sz := Vector2(maxf(w * _s, 1.0), maxf(h * _s, 1.0)).round()
	_ci.draw_rect(Rect2(pos, sz), _col(c))

# 不受翻转影响的绝对坐标矩形（气泡等）
static func px(ci: CanvasItem, x: float, y: float, w: float, h: float, c: Color) -> void:
	ci.draw_rect(Rect2(Vector2(x, y).round(), Vector2(maxf(w, 1.0), maxf(h, 1.0)).round()), c)

static func hash01(n: int) -> float:
	var v := sin(float(n) * 12.9898 + 78.233) * 43758.5453
	return v - floor(v)

# ================= 物件 =================

static func item_size(id: String) -> Vector2:
	return ITEM_SIZES.get(id, Vector2(16, 16))

static func is_surface(id: String) -> bool:
	return id == "duckweed"

# 小生物在「家」附近来回溜达的偏移（1 倍像素）；编辑时 t 传 0 让它们停住。
static func critter_offset(id: String, uid: int, t: float) -> Vector2:
	match id:
		"snail":
			return Vector2(sin(t * 0.07 + uid * 1.7) * 26.0, 0.0)
		"shrimp":
			var hop := maxf(sin(t * 2.3 + uid), 0.0)
			return Vector2(sin(t * 0.25 + uid * 2.1) * 18.0, -hop * hop * 3.0)
		"moss_ball":
			return Vector2(sin(t * 0.05 + uid) * 3.0, 0.0)
	return Vector2.ZERO

static func critter_facing_left(id: String, uid: int, t: float) -> bool:
	match id:
		"snail":
			return cos(t * 0.07 + uid * 1.7) < 0.0
		"shrimp":
			return cos(t * 0.25 + uid * 2.1) < 0.0
	return false

# base：底边中点（浮萍为水面中点）。surface_y：水面的绝对 y，气泡石用来画气泡柱。
static func draw_item(ci: CanvasItem, id: String, base: Vector2, s: float, t: float, flip := false,
		tint := Color(0, 0, 0, 0), alpha := 1.0, surface_y := -1.0) -> void:
	_begin(ci, base, s, flip, tint, alpha)
	match id:
		"grass": _grass(t)
		"hornwort": _hornwort(t)
		"sword": _sword(t)
		"moss_ball": _moss_ball()
		"duckweed": _duckweed(t)
		"rock": _rock()
		"stone_stack": _stone_stack()
		"driftwood": _driftwood()
		"seashell": _seashell()
		"coral": _coral()
		"anemone": _anemone(t)
		"diver": _diver(t)
		"castle": _castle(t)
		"chest": _chest(t)
		"shipwreck": _shipwreck()
		"airstone": _airstone(t, surface_y)
		"filter": _filter(t)
		"snail": _snail()
		"shrimp": _shrimp(t)
		_: _r(-6, -8, 12, 8, Color(0.8, 0.3, 0.8))

static func _grass(t: float) -> void:
	var xs := [-6.0, -3.0, 0.0, 3.0, 6.0]
	var hs := [14, 20, 22, 17, 12]
	for k in range(xs.size()):
		var segs := int(hs[k]) / 3
		var col: Color = PLANT if k % 2 == 0 else PLANT_SOFT
		for j in range(segs):
			var sway := sin(t * 1.8 + k * 0.9 + j * 0.35) * j * 0.35
			_r(float(xs[k]) + sway - 1.0, -(j + 1) * 3.0, 2.0, 3.5, col)

static func _hornwort(t: float) -> void:
	for j in range(15):
		var sw := sin(t * 1.3 + j * 0.22) * j * 0.22
		var y := -(j + 1) * 3.0
		_r(sw - 1.0, y, 2.0, 3.5, PLANT_DARK)
		if j % 2 == 1:
			_r(sw - 4.0, y + 1.0, 8.0, 1.5, PLANT_SOFT)
			_r(sw - 5.0, y - 0.5, 1.5, 1.5, PLANT_LIGHT)
			_r(sw + 3.5, y - 0.5, 1.5, 1.5, PLANT_LIGHT)
	_r(sin(t * 1.3 + 3.3) * 3.3 - 2.0, -48.0, 4.0, 3.0, PLANT_LIGHT)

static func _sword(t: float) -> void:
	# [倾斜, 高度]：由外到内画，中间的叶子盖在上面
	var leaves := [[-0.85, 15], [0.85, 16], [-0.4, 23], [0.4, 22], [-0.1, 26], [0.12, 29]]
	for k in range(leaves.size()):
		var lean := float(leaves[k][0])
		var h := int(leaves[k][1])
		var col: Color = PLANT if k % 2 == 0 else PLANT_SOFT
		var steps := h / 3
		for j in range(steps):
			var sway := sin(t * 1.2 + k * 1.1) * j * 0.12
			var w := maxf(5.0 - j * 0.3, 2.0)
			var x := lean * j * 3.0 + sway - w * 0.5
			_r(x, -(j + 1) * 3.0, w, 3.5, col)
			if j > 0 and j < steps - 1:
				_r(x + w * 0.5 - 0.5, -(j + 1) * 3.0, 1.0, 3.0, PLANT_DARK)

static func _moss_ball() -> void:
	var rows := [6, 10, 12, 12, 12, 10, 6]
	for i in range(rows.size()):
		var w := float(rows[i])
		_r(-w * 0.5, -11.0 + i * 1.6, w, 1.8, PLANT_DARK if i >= 5 else PLANT)
	_r(-3.0, -9.5, 2.0, 2.0, PLANT_LIGHT)
	_r(1.0, -7.0, 2.0, 1.5, PLANT_SOFT)
	_r(-4.0, -5.5, 2.0, 1.5, PLANT_SOFT)
	_r(2.5, -3.5, 1.5, 1.5, PLANT_LIGHT)

static func _duckweed(t: float) -> void:
	var drift := sin(t * 0.3) * 2.0
	var xs := [-13.0, -8.0, -3.0, 2.0, 7.0, 11.0]
	for k in range(xs.size()):
		var x := float(xs[k]) + drift
		var root_len := 3.0 + (k % 3) * 1.5
		_r(x + 1.5 + sin(t * 1.5 + k) * 0.6, 2.0, 0.8, root_len, Color(0.75, 0.82, 0.70, 0.7))
		_r(x, 0.0, 4.0, 2.0, PLANT_SOFT if k % 2 == 0 else PLANT_LIGHT)
		_r(x + 0.5, -0.5, 3.0, 0.8, PLANT_LIGHT)

static func _stone(x: float, w: float, h: float, col: Color, hi: Color, lo: Color) -> void:
	_r(x + 1.0, -h, w - 2.0, 1.0, col)
	_r(x, -h + 1.0, w, h - 1.0, col)
	_r(x + 1.5, -h + 1.0, 2.5, 1.0, hi)
	_r(x, -1.5, w, 1.5, lo)

static func _rock() -> void:
	_stone(-12.0, 13.0, 10.0, STONE, STONE_LIGHT, STONE_DARK)
	_stone(0.0, 10.0, 7.0, Color(0.62, 0.60, 0.55), Color(0.76, 0.74, 0.68), Color(0.46, 0.44, 0.40))
	_stone(8.0, 5.0, 4.0, STONE_DARK, STONE, Color(0.32, 0.34, 0.35))

static func _stone_stack() -> void:
	var ws := [18.0, 14.0, 11.0, 8.0]
	var hs := [6.0, 6.0, 5.0, 5.0]
	var ox := [0.0, 1.0, -1.0, 1.0]
	var y := 0.0
	for i in range(ws.size()):
		var col: Color = STONE if i % 2 == 0 else Color(0.62, 0.60, 0.55)
		var w := float(ws[i])
		_r(float(ox[i]) - w * 0.5 + 1.0, y - float(hs[i]), w - 2.0, 1.0, col)
		_r(float(ox[i]) - w * 0.5, y - float(hs[i]) + 1.0, w, float(hs[i]) - 1.0, col)
		_r(float(ox[i]) - w * 0.5 + 1.5, y - float(hs[i]) + 1.0, 3.0, 1.0, STONE_LIGHT)
		_r(float(ox[i]) - w * 0.5, y - 1.0, w, 1.0, STONE_DARK)
		y -= float(hs[i])

static func _driftwood() -> void:
	# 主干：斜向上的阶梯
	for i in range(11):
		_r(-19.0 + i * 3.0, -3.0 - i * 1.9, 5.0, 4.0, WOOD if i % 3 else WOOD_DARK)
	# 左上分枝
	for i in range(6):
		_r(-5.0 - i * 1.4, -12.0 - i * 2.4, 3.0, 3.0, WOOD)
	# 右侧分枝
	for i in range(5):
		_r(9.0 + i * 2.4, -19.0 + i * 0.4, 3.0, 2.5, WOOD_DARK)
	_r(-21.0, -2.0, 9.0, 2.0, WOOD_DARK)
	_r(-2.0, -14.5, 5.0, 1.5, PLANT_SOFT)
	_r(8.0, -23.0, 4.0, 1.5, PLANT)

static func _seashell() -> void:
	var body := Color(0.93, 0.80, 0.68)
	var line := Color(0.78, 0.58, 0.48)
	_r(-6.0, -5.0, 10.0, 5.0, body)
	_r(-4.0, -8.0, 7.0, 3.0, body)
	_r(-2.0, -10.0, 3.0, 2.0, line)
	_r(3.0, -5.0, 3.5, 4.0, Color(0.96, 0.66, 0.66))
	_r(-4.0, -6.0, 1.0, 6.0, line)
	_r(-1.0, -8.0, 1.0, 8.0, line)
	_r(2.0, -6.0, 1.0, 5.0, line)
	_r(-6.0, -1.0, 10.0, 1.0, line)

static func _coral() -> void:
	var c1 := Color(0.86, 0.42, 0.46)
	var c2 := Color(0.93, 0.60, 0.50)
	_r(-3.0, -18.0, 6.0, 18.0, c1)
	_r(-8.0, -9.0, 5.0, 3.0, c1)
	_r(3.0, -11.0, 4.0, 3.0, c1)
	_r(-10.0, -15.0, 5.0, 9.0, c2)
	_r(6.0, -17.0, 5.0, 9.0, c2)
	_r(-11.0, -21.0, 5.0, 7.0, c1)
	_r(7.0, -24.0, 5.0, 8.0, c1)
	_r(-2.0, -21.0, 4.0, 4.0, c2)
	_r(-10.0, -20.0, 1.5, 1.5, Color(1.0, 0.85, 0.80))
	_r(9.0, -22.0, 1.5, 1.5, Color(1.0, 0.85, 0.80))

static func _anemone(t: float) -> void:
	var base := Color(0.62, 0.36, 0.52)
	var arm := Color(0.93, 0.52, 0.72)
	var tip := Color(1.0, 0.80, 0.88)
	_r(-5.0, -5.0, 10.0, 5.0, base)
	_r(-6.0, -6.0, 12.0, 2.0, base)
	for k in range(7):
		var x := -7.0 + k * 2.3
		for j in range(3):
			var sway := sin(t * 2.0 + k * 0.9) * (j + 1) * 0.7
			_r(x + sway, -9.0 - j * 3.0, 1.8, 3.2, tip if j == 2 else arm)

static func _diver(t: float) -> void:
	var suit := Color(0.33, 0.44, 0.52)
	var dark := Color(0.18, 0.20, 0.22)
	var brass := Color(0.82, 0.64, 0.30)
	var glass := Color(0.60, 0.80, 0.86)
	_r(-5.0, -3.0, 4.0, 3.0, dark)
	_r(1.0, -3.0, 4.0, 3.0, dark)
	_r(-4.0, -10.0, 3.0, 7.0, suit)
	_r(1.0, -10.0, 3.0, 7.0, suit)
	_r(-5.0, -18.0, 10.0, 9.0, suit)
	_r(-5.0, -12.0, 10.0, 2.0, dark)
	_r(-7.0, -17.0, 2.0, 6.0, suit)
	_r(5.0, -17.0, 2.0, 6.0, suit)
	_r(-4.0, -27.0, 8.0, 1.0, brass)
	_r(-5.0, -26.0, 10.0, 8.0, brass)
	_r(-3.0, -24.0, 6.0, 4.5, glass)
	_r(-2.0, -23.5, 1.5, 1.5, Color(0.92, 0.97, 0.98))
	_r(5.0, -23.0, 3.0, 1.5, dark)
	for k in range(3):
		var prog := fmod(t * 0.35 + k / 3.0, 1.0)
		var bs := 1.5 + k * 0.5
		_r(-1.0 + sin(prog * 9.0 + k) * 1.2, -29.0 - prog * 30.0, bs, bs, Color(0.85, 0.94, 0.96, 0.7 * (1.0 - prog)))

static func _castle(t: float) -> void:
	var sl := Color(0.66, 0.64, 0.60)
	var sd := Color(0.50, 0.49, 0.47)
	var dark := Color(0.16, 0.20, 0.24)
	# 城墙 + 两座塔
	_r(-9.0, -22.0, 18.0, 22.0, sl)
	_r(-17.0, -30.0, 10.0, 30.0, sd)
	_r(7.0, -34.0, 10.0, 34.0, sd)
	for i in range(3):
		_r(-17.0 + i * 4.0, -32.0, 2.0, 2.0, sd)
		_r(7.0 + i * 4.0, -36.0, 2.0, 2.0, sd)
		_r(-8.0 + i * 6.5, -24.0, 3.0, 2.0, sl)
	# 城门 + 窗
	_r(-4.0, -10.0, 8.0, 10.0, dark)
	_r(-3.0, -11.0, 6.0, 1.0, dark)
	_r(-13.0, -22.0, 2.0, 4.0, dark)
	_r(11.0, -26.0, 2.0, 4.0, dark)
	_r(-1.0, -18.0, 2.0, 3.0, dark)
	# 旗子：两格交替飘动
	var wave := 1.0 if sin(t * 3.0) > 0.0 else 0.0
	_r(-12.5, -38.0, 1.0, 6.0, dark)
	_r(-11.5, -38.0 + wave * 0.5, 5.0, 3.0, Color(0.85, 0.35, 0.30))
	_r(11.5, -42.0, 1.0, 6.0, dark)
	_r(12.5, -42.0 + (1.0 - wave) * 0.5, 5.0, 3.0, Color(0.95, 0.75, 0.30))

static func _chest(t: float) -> void:
	var wood := Color(0.55, 0.38, 0.22)
	var lid := Color(0.46, 0.31, 0.18)
	var gold := Color(0.95, 0.80, 0.30)
	_r(-9.0, -11.0, 18.0, 11.0, wood)
	_r(-9.0, -16.0, 18.0, 5.0, lid)
	_r(-2.0, -13.0, 4.0, 5.0, gold)
	_r(-9.0, -8.0, 18.0, 2.0, lid)
	var glint := fmod(t * 0.5, 3.0)
	if glint < 0.4:
		_r(4.0 + glint * 8.0, -15.0, 1.5, 1.5, Color(1.0, 1.0, 0.85))

static func _shipwreck() -> void:
	var hull := Color(0.42, 0.30, 0.22)
	var hull_dark := Color(0.32, 0.22, 0.16)
	var mast := Color(0.50, 0.38, 0.26)
	_r(-22.0, -12.0, 40.0, 12.0, hull)
	_r(14.0, -17.0, 9.0, 13.0, hull)
	_r(-22.0, -4.0, 42.0, 4.0, hull_dark)
	_r(-22.0, -9.0, 36.0, 1.0, hull_dark)
	_r(-14.0, -11.0, 6.0, 5.0, Color(0.14, 0.12, 0.10))
	_r(2.0, -8.0, 3.0, 3.0, Color(0.14, 0.12, 0.10))
	# 断桅：向后斜
	for i in range(8):
		_r(-5.0 - i * 0.8, -14.0 - i * 2.4, 3.0, 3.0, mast)
	_r(-12.0, -28.0, 7.0, 6.0, Color(0.80, 0.76, 0.66, 0.85))
	_r(-11.0, -22.0, 3.0, 3.0, Color(0.80, 0.76, 0.66, 0.85))

static func _airstone(t: float, surface_y: float) -> void:
	_r(-5.0, -4.0, 10.0, 4.0, Color(0.38, 0.36, 0.42))
	_r(-4.0, -5.0, 8.0, 1.0, Color(0.46, 0.44, 0.50))
	_r(-3.0, -3.0, 1.0, 1.0, Color(0.25, 0.24, 0.28))
	_r(1.0, -2.0, 1.0, 1.0, Color(0.25, 0.24, 0.28))
	var top := surface_y if surface_y >= 0.0 else _base.y - 40.0 * _s
	var start := _base.y - 6.0 * _s
	var span := maxf(start - top, 10.0)
	for k in range(7):
		var prog := fmod(t * 0.55 + k / 7.0, 1.0)
		var bs := (1.5 + (k % 3) * 0.7) * _s
		var bx := _base.x + sin(prog * 12.0 + k) * 2.0 * _s - bs * 0.5
		px(_ci, bx, start - prog * span, bs, bs, _col(Color(0.88, 0.96, 0.98, 0.75)))

static func _filter(t: float) -> void:
	var body := Color(0.22, 0.25, 0.28)
	var panel := Color(0.32, 0.36, 0.40)
	_r(-5.0, -20.0, 10.0, 20.0, body)
	_r(-4.0, -18.0, 8.0, 7.0, panel)
	_r(-4.0, -9.0, 8.0, 1.0, panel)
	_r(-4.0, -6.0, 8.0, 1.0, panel)
	_r(-6.0, -22.0, 12.0, 2.0, Color(0.30, 0.34, 0.38))
	_r(-1.0, -26.0, 2.0, 4.0, body)
	_r(-1.0, -26.0, 6.0, 2.0, body)
	for k in range(4):
		var prog := fmod(t * 0.9 + k / 4.0, 1.0)
		_r(5.0 + prog * 9.0, -25.5 + sin(prog * 6.0) * 0.8, 1.2, 1.2, Color(0.85, 0.94, 0.96, 0.8 * (1.0 - prog)))

static func _snail() -> void:
	var foot := Color(0.86, 0.80, 0.62)
	var shell := Color(0.80, 0.56, 0.24)
	var spiral := Color(0.55, 0.34, 0.14)
	_r(-5.0, -2.0, 10.0, 2.0, foot)
	_r(4.0, -4.0, 2.0, 3.0, foot)
	_r(5.0, -6.0, 1.0, 2.0, foot)
	_r(3.5, -6.0, 1.0, 2.0, foot)
	_r(-4.0, -8.0, 7.0, 6.0, shell)
	_r(-3.0, -9.0, 5.0, 1.0, shell)
	_r(-2.0, -6.0, 3.0, 1.0, spiral)
	_r(0.0, -7.0, 1.0, 3.0, spiral)
	_r(-2.0, -5.0, 1.0, 1.0, spiral)

static func _shrimp(t: float) -> void:
	var body := Color(0.22, 0.24, 0.27, 0.92)
	var stripe := Color(0.55, 0.60, 0.62, 0.9)
	_r(-4.0, -4.0, 7.0, 3.0, body)
	_r(-6.0, -5.0, 2.0, 3.0, body)
	_r(-7.0, -6.0, 1.5, 2.0, body)
	_r(3.0, -5.0, 2.5, 3.0, body)
	_r(-2.0, -4.0, 1.0, 3.0, stripe)
	_r(1.0, -4.0, 1.0, 3.0, stripe)
	var leg := 0.5 if sin(t * 9.0) > 0.0 else 0.0
	for i in range(3):
		_r(-2.0 + i * 2.0 + leg, -1.0, 0.8, 1.0, body)
	_r(5.0, -6.0, 6.0, 0.6, stripe)
	_r(4.5, -4.5, 1.0, 1.0, EYE)

# ================= 鱼 =================

# c：中心。level 越高鱼越大；Lv.5 身上会有一道流光。
static func draw_fish(ci: CanvasItem, fish_id: String, c: Vector2, s: float, facing_left: bool, t: float,
		alpha := 1.0, level := 1, tint := Color(0, 0, 0, 0)) -> void:
	s *= 1.0 + maxf(level - 1, 0) * 0.07
	_begin(ci, c, s, facing_left, tint, alpha)
	match fish_id:
		"drift_bottle": _fish_bottle()
		"overtime_eel": _fish_eel(t)
		"weekly_pufferfish": _fish_puffer(t)
		_: _fish_generic(fish_id, t)
	if level >= 5:
		var sweep := fmod(t * 0.6, 2.5)
		if sweep < 1.0:
			_r(-6.0 + sweep * 12.0, -2.5, 1.5, 1.5, Color(1.0, 1.0, 0.9, 0.95))

static func _fish_generic(fish_id: String, t: float) -> void:
	var cols: Array = FISH_COLORS.get(fish_id, [Color(0.6, 0.6, 0.6), Color(0.45, 0.45, 0.45)])
	var body: Color = cols[0]
	var fin: Color = cols[1]
	var wag := 0.6 if sin(t * 7.0) > 0.0 else -0.6
	_r(-7.0, -3.5, 14.0, 7.0, body)
	_r(-5.0, -4.5, 10.0, 1.0, body)
	_r(-5.0, 3.5, 10.0, 1.0, body)
	_r(-4.5, -5.5, 7.0, 1.5, fin)
	_r(-10.0, -3.5 + wag, 3.0, 7.0, fin)
	if fish_id == "annual_koi" or fish_id == "slacking_legend":
		_r(-2.0, -3.5, 3.0, 3.0, fin)
		_r(2.0, 0.5, 2.5, 2.5, fin)
	if fish_id == "salted_fish":
		_r(3.0, -2.0, 2.5, 1.0, EYE)
		_r(3.75, -2.75, 1.0, 2.5, EYE)
	else:
		_r(3.5, -1.5, 1.5, 1.5, EYE)

static func _fish_puffer(t: float) -> void:
	var cols: Array = FISH_COLORS["weekly_pufferfish"]
	var body: Color = cols[0]
	var fin: Color = cols[1]
	var puff := 1.0 if fmod(t, 6.0) < 1.2 else 0.0
	var d := 12.0 + puff * 3.0
	_r(-d * 0.5, -d * 0.5, d, d, body)
	_r(-d * 0.5 - 2.0, -1.0, 2.0, 2.0, fin)
	_r(d * 0.5, -1.0, 2.0, 2.0, fin)
	_r(-1.0, -d * 0.5 - 2.0, 2.0, 2.0, fin)
	_r(-1.0, d * 0.5, 2.0, 2.0, fin)
	_r(-d * 0.5 - 3.0, -2.0, 3.0, 4.0, fin)
	_r(d * 0.22, -2.0, 1.5, 1.5, EYE)

static func _fish_eel(t: float) -> void:
	var dark: Color = FISH_COLORS["overtime_eel"][0]
	for i in range(7):
		var x := (i - 3.0) * 5.0
		var y := sin(t * 3.0 + i * 0.7) * 3.0
		var hh := 4.0 if i > 1 else 2.5
		_r(x - 2.5, y - hh * 0.5, 6.0, hh, dark)
	_r(15.0, sin(t * 3.0 + 4.2) * 3.0 - 1.0, 1.5, 1.5, Color(0.85, 0.85, 0.90))

static func _fish_bottle() -> void:
	var glass := Color(0.55, 0.78, 0.70, 0.85)
	_r(-4.0, -7.0, 8.0, 14.0, glass)
	_r(-2.0, -11.0, 4.0, 4.0, glass)
	_r(-1.5, -13.0, 3.0, 2.0, Color(0.70, 0.52, 0.32))
	_r(-3.0, -1.0, 6.0, 3.0, Color(0.93, 0.90, 0.80))

# ================= 访客 =================

static func visitor_size(id: String) -> Vector2:
	return VISITOR_SIZES.get(id, Vector2(12, 10))

static func draw_visitor(ci: CanvasItem, id: String, c: Vector2, s: float, facing_left: bool, t: float,
		alpha := 1.0, tint := Color(0, 0, 0, 0)) -> void:
	_begin(ci, c, s, facing_left, tint, alpha)
	match id:
		"hermit_crab": _v_crab(t)
		"seahorse": _v_seahorse(t)
		"goby": _v_goby(t)
		"clownfish": _v_clownfish(t)
		"octopus": _v_octopus(t)
		"axolotl": _v_axolotl(t)
		"jellyfish": _v_jellyfish(t)
		"turtle": _v_turtle(t)

static func _v_crab(t: float) -> void:
	var red := Color(0.86, 0.36, 0.26)
	var shell := Color(0.93, 0.80, 0.68)
	var line := Color(0.78, 0.58, 0.48)
	var step := 0.8 if sin(t * 8.0) > 0.0 else 0.0
	for i in range(3):
		_r(-1.0 + i * 2.5, 3.5 + (step if i % 2 else 0.8 - step), 1.0, 2.0, red)
	_r(-1.0, -1.0, 7.0, 4.0, red)
	_r(5.0, -1.0, 3.0, 3.0, red)
	_r(6.0, -2.0, 2.0, 1.5, red)
	_r(3.0, -4.5, 0.8, 3.5, red)
	_r(4.5, -5.0, 0.8, 4.0, red)
	_r(2.8, -5.5, 1.2, 1.2, EYE)
	_r(4.3, -6.0, 1.2, 1.2, EYE)
	_r(-7.0, -2.0, 8.0, 6.0, shell)
	_r(-5.0, -5.0, 5.0, 3.0, shell)
	_r(-4.0, -3.0, 1.0, 6.0, line)
	_r(-1.5, -4.0, 1.0, 5.0, line)
	_r(-3.5, -6.0, 2.0, 1.5, line)

static func _v_seahorse(t: float) -> void:
	var body := Color(0.95, 0.70, 0.30)
	var dark := Color(0.80, 0.52, 0.20)
	var bob := sin(t * 1.5) * 0.8
	_r(-2.0, -9.0 + bob, 5.0, 4.0, body)
	_r(3.0, -8.0 + bob, 3.0, 1.5, body)
	_r(-1.0, -10.0 + bob, 2.0, 1.0, dark)
	_r(-2.0, -5.0 + bob, 3.0, 3.0, body)
	_r(-3.0, -2.0 + bob, 5.0, 6.0, body)
	_r(1.0, -1.0 + bob, 1.0, 4.0, dark)
	_r(-2.0, 4.0 + bob, 2.5, 3.0, body)
	_r(-1.0, 7.0 + bob, 2.0, 1.5, body)
	_r(0.5, 6.0 + bob, 1.5, 1.5, dark)
	var flap := 1.0 if sin(t * 12.0) > 0.0 else 0.0
	_r(-4.0 - flap * 0.5, -1.0 + bob, 1.0 + flap * 0.5, 3.0, dark)
	_r(1.0, -8.0 + bob, 1.0, 1.0, EYE)

static func _v_goby(t: float) -> void:
	var body := Color(0.82, 0.76, 0.58)
	var spot := Color(0.55, 0.46, 0.30)
	var fin := 0.5 if sin(t * 6.0) > 0.0 else 0.0
	_r(-6.0, -2.0, 11.0, 4.0, body)
	_r(-8.0, -1.5 + fin, 2.0, 3.0, body)
	_r(3.0, -3.0, 3.0, 5.0, body)
	_r(-4.0, -1.0, 1.0, 1.0, spot)
	_r(-1.0, 0.0, 1.0, 1.0, spot)
	_r(1.5, -1.5, 1.0, 1.0, spot)
	_r(0.0, 1.5, 3.0, 1.0 + fin, spot)
	_r(4.0, -3.0, 1.2, 1.2, EYE)

static func _v_clownfish(t: float) -> void:
	var orange := Color(0.98, 0.52, 0.16)
	var white := Color(0.98, 0.96, 0.92)
	var wag := 0.6 if sin(t * 8.0) > 0.0 else -0.6
	_r(-6.0, -3.0, 12.0, 6.0, orange)
	_r(-4.0, -4.0, 8.0, 1.0, orange)
	_r(-9.0, -3.0 + wag, 3.0, 6.0, orange)
	_r(-9.0, -3.0 + wag, 1.0, 6.0, EYE)
	_r(-3.0, -4.0, 2.0, 8.0, white)
	_r(2.0, -3.0, 2.0, 6.0, white)
	_r(-3.5, -4.0, 0.6, 8.0, EYE)
	_r(4.0, -3.0, 0.6, 6.0, EYE)
	_r(4.5, -1.5, 1.2, 1.2, EYE)

static func _v_octopus(t: float) -> void:
	var skin := Color(0.80, 0.36, 0.40)
	var dark := Color(0.62, 0.24, 0.30)
	for k in range(6):
		var x := -6.0 + k * 2.4
		for j in range(3):
			var sw := sin(t * 2.2 + k * 1.3 + j * 0.8) * (j + 1) * 0.6
			_r(x + sw, -1.0 + j * 2.6, 1.8, 2.8, skin if j < 2 else dark)
	_r(-6.0, -9.0, 12.0, 8.0, skin)
	_r(-5.0, -11.0, 10.0, 2.0, skin)
	_r(-3.0, -12.0, 6.0, 1.0, skin)
	_r(-4.0, -6.0, 2.0, 2.0, Color(0.98, 0.96, 0.92))
	_r(1.5, -6.0, 2.0, 2.0, Color(0.98, 0.96, 0.92))
	_r(-3.5, -5.5, 1.0, 1.0, EYE)
	_r(2.5, -5.5, 1.0, 1.0, EYE)
	_r(-4.0, -10.0, 1.5, 1.5, Color(0.92, 0.56, 0.58))

static func _v_axolotl(t: float) -> void:
	var pink := Color(0.98, 0.72, 0.76)
	var gill := Color(0.88, 0.38, 0.52)
	var sway := sin(t * 2.0)
	_r(-9.0, -1.0, 11.0, 4.0, pink)
	_r(-13.0, -1.0 + sway * 0.6, 4.0, 3.0, Color(0.98, 0.80, 0.84, 0.85))
	_r(2.0, -3.0, 6.0, 6.0, pink)
	for i in range(3):
		_r(3.0 + i * 1.5, -5.0 - i * 0.6 + sway * 0.3, 1.0, 2.0, gill)
		_r(3.0 + i * 1.5, 3.0 + i * 0.6 - sway * 0.3, 1.0, 2.0, gill)
	_r(-6.0, 3.0, 1.5, 2.0, pink)
	_r(0.0, 3.0, 1.5, 2.0, pink)
	_r(6.0, -1.5, 1.2, 1.2, EYE)
	_r(6.0, 1.0, 1.5, 0.8, Color(0.60, 0.30, 0.34))

static func _v_jellyfish(t: float) -> void:
	var pulse := sin(t * 2.2) * 0.12
	var glow := Color(0.70, 0.95, 0.95, 0.14)
	var bell := Color(0.78, 0.90, 0.98, 0.80)
	var inner := Color(0.98, 0.72, 0.90, 0.85)
	_r(-10.0, -14.0, 20.0, 22.0, glow)
	var rows := [6.0, 10.0, 13.0, 14.0]
	for i in range(rows.size()):
		var w := float(rows[i]) * (1.0 + pulse)
		_r(-w * 0.5, -12.0 + i * 2.0, w, 2.2, bell)
	_r(-3.0, -9.0, 6.0, 3.0, inner)
	for k in range(5):
		var x := -5.0 + k * 2.5
		for j in range(4):
			var sw := sin(t * 1.8 + k + j * 0.9) * (j + 1) * 0.5
			_r(x + sw, -3.0 + j * 3.0, 0.8, 3.0, Color(0.85, 0.92, 0.98, 0.6))

static func _v_turtle(t: float) -> void:
	var shell := Color(0.36, 0.52, 0.30)
	var shell_d := Color(0.26, 0.40, 0.22)
	var skin := Color(0.62, 0.70, 0.46)
	var paddle := sin(t * 2.5) * 1.5
	_r(6.0, -5.0 + paddle, 5.0, 3.0, skin)
	_r(-9.0, -4.0 - paddle, 4.0, 2.0, skin)
	_r(6.0, 3.0 - paddle, 5.0, 2.5, skin)
	_r(-9.0, 2.5 + paddle, 4.0, 2.0, skin)
	_r(-10.0, -3.0, 20.0, 6.0, shell)
	_r(-8.0, -5.0, 16.0, 2.0, shell)
	_r(-5.0, -6.0, 10.0, 1.0, shell)
	_r(-6.0, -3.0, 3.0, 2.0, shell_d)
	_r(-1.0, -4.0, 3.0, 2.0, shell_d)
	_r(4.0, -3.0, 3.0, 2.0, shell_d)
	_r(-3.0, 0.0, 3.0, 2.0, shell_d)
	_r(2.0, 0.0, 3.0, 2.0, shell_d)
	_r(10.0, -2.0, 4.0, 3.5, skin)
	_r(12.0, -1.5, 1.0, 1.0, EYE)
	_r(-12.0, -0.5, 2.0, 1.5, skin)

# ================= 小部件 =================

static func draw_pearl(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	_begin(ci, c, s, false, Color(0, 0, 0, 0), 1.0)
	var ring := Color(0.86, 0.95, 0.98, 0.55)
	_r(-5.0, -7.0, 10.0, 1.0, ring)
	_r(-5.0, 6.0, 10.0, 1.0, ring)
	_r(-7.0, -5.0, 1.0, 10.0, ring)
	_r(6.0, -5.0, 1.0, 10.0, ring)
	_r(-6.0, -6.0, 1.0, 1.0, ring)
	_r(5.0, -6.0, 1.0, 1.0, ring)
	_r(-6.0, 5.0, 1.0, 1.0, ring)
	_r(5.0, 5.0, 1.0, 1.0, ring)
	_r(-5.0, -5.0, 10.0, 10.0, Color(0.80, 0.92, 0.96, 0.18))
	_r(-3.0, -3.0, 6.0, 6.0, Color(0.98, 0.96, 0.92))
	_r(-2.0, -4.0, 4.0, 1.0, Color(0.98, 0.96, 0.92))
	_r(-2.0, 3.0, 4.0, 1.0, Color(0.90, 0.86, 0.82))
	_r(-2.0, -2.0, 1.5, 1.5, Color(1.0, 1.0, 1.0))
	if fmod(t * 0.8, 2.0) < 0.25:
		_r(3.0, -5.0, 1.5, 1.5, Color(1.0, 1.0, 1.0))

static func draw_food(ci: CanvasItem, c: Vector2, s: float) -> void:
	px(ci, c.x - s, c.y - s, 2.0 * s, 2.0 * s, Color(0.66, 0.44, 0.24))

static func draw_heart(ci: CanvasItem, c: Vector2, s: float, alpha: float) -> void:
	_begin(ci, c, s, false, Color(0, 0, 0, 0), alpha)
	var pink := Color(0.95, 0.45, 0.55)
	_r(-3.0, -3.0, 2.0, 2.0, pink)
	_r(1.0, -3.0, 2.0, 2.0, pink)
	_r(-3.0, -1.0, 6.0, 2.0, pink)
	_r(-2.0, 1.0, 4.0, 1.0, pink)
	_r(-1.0, 2.0, 2.0, 1.0, pink)

# 贝壳货币图标（扇贝），c 为中心
static func draw_shell_icon(ci: CanvasItem, c: Vector2, s: float) -> void:
	_begin(ci, c, s, false, Color(0, 0, 0, 0), 1.0)
	var body := Color(0.96, 0.78, 0.60)
	var rib := Color(0.84, 0.58, 0.42)
	_r(-2.0, -5.0, 4.0, 1.0, body)
	_r(-4.0, -4.0, 8.0, 2.0, body)
	_r(-5.0, -2.0, 10.0, 4.0, body)
	_r(-2.0, 2.0, 4.0, 2.0, body)
	_r(-3.0, 2.0, 6.0, 1.0, rib)
	_r(-2.5, -3.0, 1.0, 5.0, rib)
	_r(-0.5, -4.0, 1.0, 6.0, rib)
	_r(1.5, -3.0, 1.0, 5.0, rib)
