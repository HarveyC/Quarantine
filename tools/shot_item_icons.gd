extends SceneTree
## Item icon style sample (dev check): godot -s tools/shot_item_icons.gd -- out.png
## One row per style: A outline glyphs, B solid duotone glyphs, same shapes.

const Styles := preload("res://ui/styles.gd")
const Draw := preload("res://ui/bloom_draw.gd")

# Shapes on a 24 grid: "p" closed polygon, "l" open line, "c" circle [cx, cy, r], "d" dot.
const ITEMS := [
	["Laser sight", Color("d9a441"), [
		["p", [[2, 9], [14, 9], [14, 15], [2, 15]]], ["l", [[14, 12], [22, 12]]], ["d", [6, 12, 1.2]], ["l", [[18, 8], [21, 6]]], ["l", [[18, 16], [21, 18]]]]],
	["Tracer rounds", Color("6bb7d6"), [
		["p", [[5, 20], [5, 10], [8, 5], [11, 10], [11, 20]]], ["l", [[16, 20], [19, 4]]], ["l", [[14, 14], [17, 11]]], ["l", [[19, 14], [22, 11]]]]],
	["Kevlar vest", Color("9aa89b"), [
		["p", [[7, 3], [10, 5], [14, 5], [17, 3], [21, 7], [19, 11], [18, 21], [6, 21], [5, 11], [3, 7]]], ["l", [[12, 5], [12, 21]]], ["l", [[7, 14], [11, 14]]], ["l", [[13, 14], [17, 14]]]]],
	["Thermite charge", Color("e07a3c"), [
		["p", [[6, 9], [18, 9], [18, 21], [6, 21]]], ["l", [[9, 9], [9, 6], [15, 6], [15, 9]]], ["p", [[12, 12], [14, 15], [12, 18], [10, 15]]], ["l", [[12, 3], [12, 6]]]]],
	["Sentry turret", Color("c9a0f0"), [
		["p", [[5, 15], [19, 15], [19, 19], [5, 19]]], ["p", [[8, 9], [16, 9], [16, 15], [8, 15]]], ["l", [[16, 12], [22, 12]]], ["l", [[12, 15], [12, 19]]], ["l", [[7, 21], [4, 22]]], ["l", [[17, 21], [20, 22]]]]],
	["Filter mask", Color("9aa89b"), [
		["p", [[5, 7], [19, 7], [19, 14], [15, 20], [9, 20], [5, 14]]], ["c", [12, 15, 3]], ["l", [[2, 10], [5, 10]]], ["l", [[19, 10], [22, 10]]], ["l", [[9, 11], [15, 11]]]]],
	["Medkit", Color("d9a441"), [
		["p", [[3, 8], [21, 8], [21, 20], [3, 20]]], ["l", [[9, 8], [9, 5], [15, 5], [15, 8]]], ["l", [[12, 11], [12, 17]]], ["l", [[9, 14], [15, 14]]]]],
	["Rifle", Color("6bb7d6"), [
		["p", [[2, 11], [14, 11], [14, 9], [22, 9], [22, 12], [14, 12], [11, 13], [10, 19], [7, 19], [8, 13], [2, 14]]], ["l", [[16, 12], [16, 16], [19, 16]]]]],
	["Requisition", Color("d9a441"), [
		["p", [[4, 7], [20, 7], [20, 20], [4, 20]]], ["l", [[8, 7], [8, 4], [16, 4], [16, 7]]], ["l", [[8, 12], [16, 12]]], ["l", [[8, 16], [13, 16]]], ["p", [[15, 15], [18, 15], [18, 18], [15, 18]]]]],
	["Early graft", Color("4fc4b0"), [
		["p", [[12, 4], [18, 8], [18, 15], [12, 20], [6, 15], [6, 8]]], ["c", [12, 12, 2.5]], ["l", [[12, 4], [12, 9.5]]], ["l", [[12, 14.5], [12, 20]]], ["l", [[6, 8], [9.8, 10.5]]], ["l", [[18, 8], [14.2, 10.5]]]]],
	# Map nodes.
	["Weapons cache", Color("d9a441"), [
		["p", [[3, 14], [21, 14], [21, 21], [3, 21]]], ["l", [[3, 14], [21, 21]]], ["l", [[21, 14], [3, 21]]],
		["p", [[4, 9], [13, 9], [13, 7], [20, 7], [20, 10], [13, 10], [11, 11], [10, 14], [8, 14], [8, 11], [4, 11]]]]],
	["Depot", Color("d9a441"), [
		["p", [[3, 13], [11, 13], [11, 21], [3, 21]]], ["p", [[13, 9], [21, 9], [21, 21], [13, 21]]], ["p", [[6, 5], [10, 5], [10, 13], [6, 13]]], ["l", [[16, 13], [18, 13]]]]],
	["Hospital", Color("d9a441"), [
		["p", [[4, 8], [20, 8], [20, 21], [4, 21]]], ["l", [[12, 11], [12, 18]]], ["l", [[8.5, 14.5], [15.5, 14.5]]], ["l", [[4, 8], [12, 3], [20, 8]]]]],
	["Skirmish", Color("d9a441"), [
		["c", [12, 12, 8]], ["l", [[12, 1.5], [12, 6]]], ["l", [[12, 18], [12, 22.5]]], ["l", [[1.5, 12], [6, 12]]], ["l", [[18, 12], [22.5, 12]]], ["d", [12, 12, 1.2]]]],
	["Nest", Color("4fc4b0"), [
		["c", [12, 7.5, 3.6]], ["c", [6.5, 16, 3.6]], ["c", [17.5, 16, 3.6]], ["d", [12, 13.2, 1.0]]]],
	["Boss", Color("e0605a"), [
		["p", [[5, 11], [5, 8], [8, 5], [16, 5], [19, 8], [19, 11], [16, 15], [16, 20], [8, 20], [8, 15]]], ["l", [[5, 8], [2, 3]]], ["l", [[19, 8], [22, 3]]], ["d", [9.5, 11, 1.2]], ["d", [14.5, 11, 1.2]]]],
	# Action wheel.
	["Reload", Color("d9a441"), [
		["p", [[6, 10], [14, 10], [16, 21], [9, 21]]], ["l", [[7, 14], [15, 14]]], ["p", [[8, 3], [12, 3], [12, 8], [8, 8]]], ["l", [[17, 6], [21, 6], [21, 12]]], ["l", [[21, 6], [16, 11]]]]],
	["Shoot", Color("d9a441"), [
		["c", [12, 12, 8]], ["l", [[12, 1.5], [12, 6]]], ["l", [[12, 18], [12, 22.5]]], ["l", [[1.5, 12], [6, 12]]], ["l", [[18, 12], [22.5, 12]]], ["p", [[12, 8], [14, 12], [12, 16], [10, 12]]]]],
	["Overwatch", Color("d9a441"), [
		["p", [[2, 12], [7, 6.5], [12, 5], [17, 6.5], [22, 12], [17, 17.5], [12, 19], [7, 17.5]]], ["c", [12, 12, 3]], ["l", [[12, 21], [12, 23]]]]],
	["Hunker", Color("d9a441"), [
		["p", [[4, 20], [4, 13], [8, 9], [16, 9], [20, 13], [20, 20]]], ["l", [[2, 20], [22, 20]]], ["l", [[9, 14], [15, 14]]]]],
	["Move", Color("d9a441"), [
		["p", [[4, 20], [4, 15], [8, 15], [8, 18], [14, 18], [14, 20]]], ["l", [[11, 4], [16, 9], [11, 14]]], ["l", [[16, 9], [4, 9]]]]],
	["Stim", Color("d9a441"), [
		["p", [[9, 7], [15, 7], [15, 18], [9, 18]]], ["l", [[12, 18], [12, 22]]], ["l", [[7, 7], [17, 7]]], ["l", [[12, 2], [12, 7]]], ["l", [[9, 12], [15, 12]]]]],
]


class Glyph extends Control:
	var shapes: Array
	var col: Color
	var solid := false

	func _draw() -> void:
		var R := minf(size.x, size.y) * 0.5
		var c := size * 0.5
		Draw.glow(self, c, R * 1.2, col, 0.5)
		draw_circle(c, R - 1.0, Color("1d1f1c"))
		draw_circle(c, R - 3.0, Color(col, 0.12))
		draw_arc(c, R - 2.0, 0, TAU, 64, Color(col, 0.75), 2.0, true)
		var s := R * 1.05 / 12.0
		var o := c - Vector2(12, 12) * s
		var w := maxf(2.0, R * 0.065)
		for sh in shapes:
			match sh[0]:
				"p":
					var pts := PackedVector2Array()
					for p in sh[1]:
						pts.append(o + Vector2(p[0], p[1]) * s)
					if solid:
						draw_colored_polygon(pts, Color(col, 0.38))
					pts.append(pts[0])
					draw_polyline(pts, col, w, true)
				"l":
					var pts := PackedVector2Array()
					for p in sh[1]:
						pts.append(o + Vector2(p[0], p[1]) * s)
					draw_polyline(pts, col, w, true)
				"c":
					var a: Array = sh[1]
					if solid:
						draw_circle(o + Vector2(a[0], a[1]) * s, a[2] * s, Color(col, 0.38))
					draw_arc(o + Vector2(a[0], a[1]) * s, a[2] * s, 0, TAU, 32, col, w, true)
				"d":
					var a: Array = sh[1]
					draw_circle(o + Vector2(a[0], a[1]) * s, a[2] * s * 1.6, col)


const GROUPS := [["Items", 0, 10], ["Map nodes", 10, 6], ["Action wheel", 16, 6]]


func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://icons.png"
	var style := int(OS.get_cmdline_user_args()[1]) if OS.get_cmdline_user_args().size() > 1 else 0
	root.size = Vector2i(1280, 640)
	var bg := ColorRect.new()
	bg.color = Color("14161a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var theme := Styles.make_theme()
	var rows := [["A  Outline", false], ["B  Solid", true]]
	for r in [style]:
		var y0 := 0
		var tag := Label.new()
		tag.text = rows[r][0]
		tag.theme = theme
		tag.position = Vector2(24, y0 + 10)
		tag.add_theme_font_size_override("font_size", 22)
		root.add_child(tag)
		for gi in GROUPS.size():
			var gy := y0 + 50 + gi * 198
			var cap := Label.new()
			cap.text = GROUPS[gi][0]
			cap.theme = theme
			cap.position = Vector2(24, gy)
			cap.modulate = Color(1, 1, 1, 0.5)
			root.add_child(cap)
			for k in GROUPS[gi][2]:
				var i: int = GROUPS[gi][1] + k
				var g := Glyph.new()
				g.shapes = ITEMS[i][2]
				g.col = ITEMS[i][1]
				g.solid = rows[r][1]
				g.position = Vector2(30 + k * 124, gy + 28)
				g.size = Vector2(104, 104)
				root.add_child(g)
				var l := Label.new()
				l.text = ITEMS[i][0]
				l.theme = theme
				l.position = Vector2(14 + k * 124, gy + 140)
				l.size = Vector2(124, 24)
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				l.add_theme_font_size_override("font_size", 14)
				root.add_child(l)
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png(out)
	quit()
