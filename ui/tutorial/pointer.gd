extends Control
## Draws what a coach card points at: pulsing amber brackets around a screen rect and an
## arrow from the card to it. Full screen, never takes the mouse.

const Styles := preload("res://ui/styles.gd")

## Where the arrow starts (usually the card's edge) and what it points at, in screen space.
var from := Vector2.ZERO
var target := Rect2()
var has_target := false
## Draw brackets round the target (off for a single board point).
var brackets := true
var _t := 0.0


func _init() -> void:
	name = "Pointer"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func point_at(card: Rect2, rect: Rect2, with_brackets := true) -> void:
	has_target = true
	target = rect
	brackets = with_brackets
	var c := rect.get_center()
	# Leave from the card edge that faces the target.
	var cc := card.get_center()
	if c.y > card.end.y:
		from = Vector2(clampf(c.x, card.position.x + 24, card.end.x - 24), card.end.y)
	elif c.y < card.position.y:
		from = Vector2(clampf(c.x, card.position.x + 24, card.end.x - 24), card.position.y)
	else:
		from = Vector2(card.end.x if c.x > cc.x else card.position.x, clampf(c.y, card.position.y + 16, card.end.y - 16))
	queue_redraw()


func clear() -> void:
	if has_target:
		has_target = false
		queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if has_target:
		queue_redraw()


func _draw() -> void:
	if not has_target:
		return
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	var col := Color(Styles.AMBER, 0.75 + 0.25 * pulse)
	var r := target.grow(5.0 + 3.0 * pulse)
	if brackets:
		var k := minf(16.0, minf(r.size.x, r.size.y) * 0.4)
		for corner in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
			var dx := k if corner.x == r.position.x else -k
			var dy := k if corner.y == r.position.y else -k
			draw_polyline(PackedVector2Array([corner + Vector2(0, dy), corner, corner + Vector2(dx, 0)]), col, 3.0)
	# Arrow: stop short of the target edge.
	var tip := _edge_point(r, from)
	var dir := (tip - from)
	if dir.length() < 24.0:
		return
	var n := dir.normalized()
	tip -= n * (4.0 + 6.0 * pulse)
	var shadow := Color(0, 0, 0, 0.55)
	draw_line(from + Vector2(1, 2), tip + Vector2(1, 2), shadow, 4.0)
	draw_dashed_line(from, tip - n * 10.0, col, 3.0, 10.0)
	var side := Vector2(-n.y, n.x)
	var head := PackedVector2Array([tip, tip - n * 16.0 + side * 9.0, tip - n * 16.0 - side * 9.0])
	draw_colored_polygon(head, col)


## Where the line from `p` toward the rect's centre crosses its border.
static func _edge_point(r: Rect2, p: Vector2) -> Vector2:
	var c := r.get_center()
	var d := c - p
	if r.has_point(p) or d.length() < 0.01:
		return c
	var hx := r.size.x * 0.5
	var hy := r.size.y * 0.5
	var t := 1.0
	if absf(d.x) > 0.0:
		t = minf(t, absf(hx / d.x))
	if absf(d.y) > 0.0:
		t = minf(t, absf(hy / d.y))
	return c - d * t
