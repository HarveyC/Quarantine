extends RefCounted
## Drawing helpers shared by the Bloom widgets: capsules (rounded bar segments) and soft glows.

## A rounded bar segment (capsule) from `r`.
static func capsule(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var rad := minf(r.size.x, r.size.y) * 0.5
	if r.size.x >= r.size.y:
		ci.draw_rect(Rect2(r.position.x + rad, r.position.y, r.size.x - rad * 2, r.size.y), col)
		ci.draw_circle(Vector2(r.position.x + rad, r.position.y + rad), rad, col)
		ci.draw_circle(Vector2(r.end.x - rad, r.position.y + rad), rad, col)
	else:
		ci.draw_rect(Rect2(r.position.x, r.position.y + rad, r.size.x, r.size.y - rad * 2), col)
		ci.draw_circle(Vector2(r.position.x + rad, r.position.y + rad), rad, col)
		ci.draw_circle(Vector2(r.position.x + rad, r.end.y - rad), rad, col)


## A soft round glow (stacked translucent discs) at `c`.
static func glow(ci: CanvasItem, c: Vector2, radius: float, col: Color, strength := 0.5) -> void:
	var steps := 6
	for i in steps:
		var k := 1.0 - float(i) / steps
		ci.draw_circle(c, radius * k, Color(col, strength * 0.16 * (1.0 - k * 0.6)))
