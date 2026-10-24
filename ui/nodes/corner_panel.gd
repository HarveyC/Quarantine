extends PanelContainer
## A node-screen panel in the Bloom look: the rounded glass box comes from its stylebox
## (NodeUi.box); `stripe` draws a short owner pill centred on its top edge.

var stripe := Color(0, 0, 0, 0)
var marks := true   # kept for callers; Bloom panels have no corner marks


func _draw() -> void:
	if stripe.a <= 0:
		return
	var w := minf(size.x * 0.4, 90.0)
	var x := (size.x - w) * 0.5
	draw_rect(Rect2(x + 2, -1, w - 4, 4), stripe)
	draw_circle(Vector2(x + 2, 1), 2, stripe)
	draw_circle(Vector2(x + w - 2, 1), 2, stripe)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
