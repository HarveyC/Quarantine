extends PanelContainer
## A panel with amber corner marks (top left and bottom right, like the HUD's Frame), and an
## optional coloured stripe along its top edge.

const MARK := 12.0
const WIDTH := 2.0

var stripe := Color(0, 0, 0, 0)
var marks := true


func _draw() -> void:
	if stripe.a > 0:
		draw_rect(Rect2(0, 0, size.x, 3), stripe)
	if not marks:
		return
	var c := NodeUi.AMBER
	for corner in [Vector2(0, 0), size]:
		var dx := MARK if corner.x == 0 else -MARK
		var dy := MARK if corner.y == 0 else -MARK
		draw_line(corner, corner + Vector2(dx, 0), c, WIDTH)
		draw_line(corner, corner + Vector2(0, dy), c, WIDTH)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
