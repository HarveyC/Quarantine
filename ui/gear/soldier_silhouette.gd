extends Control
## The soldier as a plain silhouette between the slot columns of the loadout screen: head,
## torso, arms and legs drawn as one figure. A part is lit amber when the slot that sits on it
## holds something, and stays a faint outline when it is open.

const Styles := preload("res://ui/styles.gd")

const FILL := Color(0.66, 0.78, 0.8, 0.07)
const EDGE := Color(0.66, 0.78, 0.8, 0.30)

var filled := {}   # part ("head", "body", "arms", "legs") -> true when something is equipped there


func _init() -> void:
	custom_minimum_size = Vector2(220, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(parts: Dictionary) -> void:
	filled = parts.duplicate()
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var cx := w * 0.5
	var u := minf(w / 150.0, h / 330.0)
	var top := (h - 330.0 * u) * 0.5
	_part("head", PackedVector2Array(_circle(Vector2(cx, top + 34 * u), 26 * u)))
	_part("body", _pts(cx, top, u, [[-38, 70], [38, 70], [44, 100], [42, 190], [30, 200], [-30, 200], [-42, 190], [-44, 100]]))
	_part("arms", _pts(cx, top, u, [[-44, 76], [-70, 90], [-76, 200], [-60, 204], [-50, 120]]))
	_part("arms", _pts(cx, top, u, [[44, 76], [70, 90], [76, 200], [60, 204], [50, 120]]))
	_part("legs", _pts(cx, top, u, [[-30, 200], [-4, 200], [-8, 320], [-34, 320]]))
	_part("legs", _pts(cx, top, u, [[30, 200], [4, 200], [8, 320], [34, 320]]))


func _part(part: String, pts: PackedVector2Array) -> void:
	var lit: bool = filled.get(part, false)
	draw_colored_polygon(pts, Color(Styles.AMBER, 0.16) if lit else FILL)
	var ring := pts.duplicate()
	ring.append(pts[0])
	draw_polyline(ring, Color(Styles.AMBER, 0.85) if lit else EDGE, 2.0 if lit else 1.5, true)


static func _pts(cx: float, top: float, u: float, raw: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in raw:
		out.append(Vector2(cx + p[0] * u, top + p[1] * u))
	return out


static func _circle(c: Vector2, r: float) -> Array:
	var out := []
	for i in 28:
		var a := TAU * i / 28.0
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out
