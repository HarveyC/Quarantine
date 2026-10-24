extends RefCounted
## Line icons drawn with CanvasItem primitives on a 24x24 grid, so the HUD needs no
## image assets. draw() scales the grid into `rect`.

const CLASS_ICON := {"trooper": "trooper", "marksman": "marksman", "medic": "medic", "breacher": "breacher"}
const ABILITY_ICON := {"suppress": "suppress", "tag": "tag", "stim": "medic", "breach": "breach"}


static func for_class(kind: String) -> String:
	return CLASS_ICON.get(kind, "enemy")


static func for_action(a: Dictionary) -> String:
	if a.get("mutation", false):
		return "mutation"
	match str(a.get("key", "")):
		"shoot":
			return "shoot"
		"overwatch":
			return "overwatch"
		"hunker":
			return "hunker"
	return ABILITY_ICON.get(str(a.get("id", "")), "ability")


static func draw(ci: CanvasItem, id: String, rect: Rect2, color: Color, width := 2.0) -> void:
	var s := minf(rect.size.x, rect.size.y) / 24.0
	var o := rect.position + (rect.size - Vector2(24, 24) * s) * 0.5
	var w := width
	var P := func(pts: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in pts:
			out.append(o + Vector2(p[0], p[1]) * s)
		return out
	var line := func(pts: Array) -> void:
		ci.draw_polyline(P.call(pts), color, w, true)
	var circle := func(cx: float, cy: float, r: float) -> void:
		ci.draw_arc(o + Vector2(cx, cy) * s, r * s, 0, TAU, 32, color, w, true)
	var dot := func(cx: float, cy: float, r: float) -> void:
		ci.draw_circle(o + Vector2(cx, cy) * s, r * s, color)
	var arc := func(cx: float, cy: float, r: float, a0: float, a1: float) -> void:
		ci.draw_arc(o + Vector2(cx, cy) * s, r * s, a0, a1, 24, color, w, true)
	match id:
		"trooper":
			line.call([[5, 13], [12, 8], [19, 13]])
			line.call([[5, 19], [12, 14], [19, 19]])
		"marksman":
			circle.call(12, 12, 7)
			line.call([[12, 2], [12, 7]])
			line.call([[12, 17], [12, 22]])
			line.call([[2, 12], [7, 12]])
			line.call([[17, 12], [22, 12]])
		"medic":
			line.call([[9, 3], [15, 3], [15, 9], [21, 9], [21, 15], [15, 15], [15, 21], [9, 21], [9, 15], [3, 15], [3, 9], [9, 9], [9, 3]])
		"breacher":
			line.call([[12, 3], [20, 6], [20, 12], [17.5, 17.5], [12, 21], [6.5, 17.5], [4, 12], [4, 6], [12, 3]])
		"enemy":
			line.call([[12, 3], [15.5, 8], [17, 12.5], [16, 16], [12, 18.5], [8, 16], [7, 12.5], [8.5, 8], [12, 3]])
		"shoot":
			line.call([[9, 21], [9, 10], [12, 4], [15, 10], [15, 21], [9, 21]])
			line.call([[9, 16], [15, 16]])
		"overwatch":
			line.call([[2, 12], [5, 8.5], [8.5, 6], [12, 5], [15.5, 6], [19, 8.5], [22, 12], [19, 15.5], [15.5, 18], [12, 19], [8.5, 18], [5, 15.5], [2, 12]])
			circle.call(12, 12, 3)
		"hunker":
			line.call([[3, 20], [21, 20]])
			line.call([[6, 20], [6, 14]])
			line.call([[18, 20], [18, 14]])
			arc.call(12, 14, 6, PI, TAU)
		"tag":
			line.call([[3, 12], [3, 3], [12, 3], [21, 12], [12, 21], [3, 12]])
			circle.call(7.5, 7.5, 1.5)
		"suppress":
			for y in [7, 12, 17]:
				line.call([[3, y], [6, y - 2], [9, y], [12, y + 2], [15, y], [18, y - 2], [21, y]])
		"breach":
			line.call([[4, 21], [4, 3], [14, 3], [14, 21]])
			line.call([[17, 8], [21, 6]])
			line.call([[17, 12], [22, 12]])
			line.call([[17, 16], [21, 18]])
		"mutation":
			circle.call(12, 7, 3.5)
			circle.call(7, 15.5, 3.5)
			circle.call(17, 15.5, 3.5)
		"ability":
			circle.call(12, 14, 6)
			line.call([[10, 8], [10, 5], [14, 5], [14, 8]])
		"flag":
			line.call([[5, 21], [5, 4], [16, 4], [14, 8], [16, 12], [5, 12]])
		"check":
			line.call([[4, 12], [9, 17], [20, 6]])
		"clock":
			circle.call(12, 12, 8)
			line.call([[12, 8], [12, 12], [15, 14]])
		"alert":
			circle.call(12, 12, 9)
			line.call([[12, 7], [12, 13]])
			dot.call(12, 16.5, 1.2)
		"dot":
			dot.call(12, 12, 10)
		"cover_half":
			line.call([[3, 20], [21, 20]])
			line.call([[6, 20], [6, 14], [18, 14], [18, 20]])
		_:
			circle.call(12, 12, 8)
