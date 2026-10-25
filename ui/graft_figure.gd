extends Control
## A soldier's four graft slots as a body diagram: head, weapon arm, chest and legs drawn as one
## figure, each part lit by what it carries (steel for a Machine Refit, teal for a Bloom part,
## a faint outline when open). `preview` makes a slot pulse with the graft a choice would put
## there; `locked` dims the whole figure (grafts not open yet). Hover lists every slot.

const Styles := preload("res://ui/styles.gd")

## Machine parts read as bare steel; teal stays the Infection colour, so Bloom parts take it.
const STEEL := Color("b9c6cf")
const OPEN := Color(0.66, 0.78, 0.8, 0.34)

var grafts := {}
var preview := ""     # graft id a hovered choice would add
var locked := false
var _t := 0.0


func _init(size_px := Vector2(40, 60)) -> void:
	custom_minimum_size = size_px
	mouse_filter = Control.MOUSE_FILTER_PASS


func setup(g: Dictionary, preview_id := "", is_locked := false) -> void:
	grafts = g.duplicate()
	preview = preview_id
	locked = is_locked
	tooltip_text = describe(grafts, preview, locked)
	set_process(preview != "")
	queue_redraw()


static func path_color(id: String) -> Color:
	return Styles.TEAL if GraftData.is_bloom(id) else STEEL


## One line per slot: "Head: Targeting optic (Machine)", open slots too.
static func describe(g: Dictionary, preview_id := "", is_locked := false) -> String:
	var lines: Array[String] = []
	for slot in GraftData.SLOTS:
		var id: String = g.get(slot, "")
		var what := "open"
		if id != "":
			what = "%s (%s). %s" % [GraftData.name_of(id), "Bloom" if GraftData.is_bloom(id) else "Machine", GraftData.get_def(id).desc]
		if preview_id != "" and GraftData.slot_of(preview_id) == slot:
			what = "%s %s (%s). %s" % ["becomes" if id != "" else "gets", GraftData.name_of(preview_id),
				"Bloom" if GraftData.is_bloom(preview_id) else "Machine", GraftData.get_def(preview_id).desc]
		lines.append("%s: %s" % [GraftData.SLOT_NAMES[slot], what])
	if is_locked:
		lines.append("Grafts open in Act %d, at Rank %d." % [GraftData.FROM_ACT, GraftData.FROM_RANK])
	return "\n".join(lines)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _slot_color(slot: String) -> Color:
	if preview != "" and GraftData.slot_of(preview) == slot:
		return path_color(preview).lerp(Color.WHITE, 0.15 + 0.15 * sin(_t * 5.0))
	var id: String = grafts.get(slot, "")
	return OPEN if id == "" else path_color(id)


func _draw() -> void:
	# Drawn on a 60 x 90 grid, scaled to fit and centred.
	var k := minf(size.x / 60.0, size.y / 90.0)
	var o := (size - Vector2(60, 90) * k) * 0.5
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * k
	var a := 0.45 if locked else 1.0
	var limb := func(from: Vector2, to: Vector2, col: Color, w: float, filled: bool) -> void:
		if filled:
			draw_line(from, to, Color(col, a), w * k, true)
			draw_circle(from, w * k * 0.5, Color(col, a))
			draw_circle(to, w * k * 0.5, Color(col, a))
		else:
			var d := (to - from).normalized().orthogonal() * w * k * 0.5
			draw_polyline(PackedVector2Array([from + d, to + d, to - d, from - d, from + d]), Color(col, a), 1.4, true)
	for slot in GraftData.SLOTS:
		var col := _slot_color(slot)
		var filled: bool = grafts.has(slot) or (preview != "" and GraftData.slot_of(preview) == slot)
		match slot:
			"head":
				if filled:
					draw_circle(P.call(30, 11), 8.5 * k, Color(col, a))
				else:
					draw_arc(P.call(30, 11), 8.5 * k, 0, TAU, 28, Color(col, a), 1.4, true)
			"chest":
				var r := Rect2(P.call(20, 23), Vector2(20, 27) * k)
				if filled:
					draw_rect(r, Color(col, a), true)
				else:
					draw_rect(r, Color(col, a), false, 1.4)
			"arm":
				limb.call(P.call(16, 26), P.call(10, 52), col, 7.0, filled)
			"legs":
				limb.call(P.call(25, 56), P.call(23, 84), col, 8.0, filled)
				limb.call(P.call(35, 56), P.call(37, 84), col, 8.0, filled)
	# The other arm carries nothing: always the open outline.
	limb.call(P.call(44, 26), P.call(50, 52), OPEN, 7.0, false)
