extends Control
class_name TankIcon

# 商店 / 库存条 / 图鉴里的小图标：直接复用 TankArt 画同一件东西，
# 按控件大小自动取景。silhouette = 未解锁时的剪影（学 Habitica 马厩：先让你看见轮廓）。

var kind := "item"   # item / fish / visitor
var id := ""
var silhouette := false
var level := 1

const SILHOUETTE := Color(0.22, 0.26, 0.28, 1.0)
const FISH_SIZES := {
	"overtime_eel": Vector2(38, 10),
	"drift_bottle": Vector2(10, 18),
	"weekly_pufferfish": Vector2(20, 18),
}

func setup(icon_kind: String, icon_id: String, as_silhouette := false, fish_level := 1) -> TankIcon:
	kind = icon_kind
	id = icon_id
	silhouette = as_silhouette
	level = fish_level
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()
	return self

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	if id == "":
		return
	var tint := SILHOUETTE if silhouette else Color(0, 0, 0, 0)
	var avail := size - Vector2(6, 6)
	if avail.x <= 1.0 or avail.y <= 1.0:
		return
	match kind:
		"item":
			var sz := TankArt.item_size(id)
			var s := minf(minf(avail.x / sz.x, avail.y / sz.y), 2.0)
			var base := Vector2(size.x * 0.5, size.y * 0.5 + sz.y * s * 0.5)
			if TankArt.is_surface(id):
				base.y = size.y * 0.5 - sz.y * s * 0.3
			TankArt.draw_item(self, id, base, s, 0.0, false, tint, 1.0, base.y - sz.y * s)
		"fish":
			var sz: Vector2 = FISH_SIZES.get(id, Vector2(22, 14))
			var s := minf(minf(avail.x / sz.x, avail.y / sz.y), 2.0)
			TankArt.draw_fish(self, id, size * 0.5, s, false, 0.0, 1.0, level, tint)
		"visitor":
			var sz := TankArt.visitor_size(id)
			var s := minf(minf(avail.x / sz.x, avail.y / sz.y), 2.0)
			TankArt.draw_visitor(self, id, size * 0.5, s, false, 0.0, 1.0, tint)
