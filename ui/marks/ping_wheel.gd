extends Control
## The ping wheel: hold the ping button and point (mouse, or the left stick) at a slice, let go to
## send it. Five slices clockwise from the top (Marks.WHEEL); letting go in the middle cancels.
## Drawn in the Bloom look: dark glass ring, amber for the slice you're on, your colour round the rim.

const Styles := preload("res://ui/styles.gd")
const Icons := preload("res://ui/icons.gd")
const W := preload("res://ui/widgets.gd")

const R_IN := 44.0
const R_OUT := 118.0
## Pointer travel (px) before a slice is picked; less than this is the cancel hub.
const DEAD := 30.0
const GAP := 0.05   # radians between slices

## Wheel centre, in this control's coordinates.
var center := Vector2.ZERO
var color := Styles.PLAYERS[0]
## Slice under the pointer, or -1 for the hub.
var sel := -1
## What the ping lands on ("Runner", "Fuel barrel"), shown under the hub.
var subject := ""
var _t := 0.0


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func open_at(at: Vector2, player_color: Color, what := "") -> void:
	# Keep the whole wheel on screen.
	var m := R_OUT + 24.0
	center = Vector2(clampf(at.x, m, maxf(m, size.x - m)), clampf(at.y, m, maxf(m, size.y - m)))
	color = player_color
	subject = what
	sel = -1
	_t = 0.0
	visible = true
	queue_redraw()


## Picks the slice from where the pointer is relative to the centre.
func point_at(offset: Vector2) -> void:
	var s := slice_for(offset)
	if s != sel:
		sel = s
		var feel := get_node_or_null("/root/Soundscape")
		if feel != null and s >= 0:
			feel.ui("tick")
	queue_redraw()


static func slice_for(offset: Vector2) -> int:
	if offset.length() < DEAD:
		return -1
	var n := Marks.WHEEL.size()
	var a := fposmod(offset.angle() + PI * 0.5, TAU)   # 0 = straight up, clockwise
	return int(round(a / (TAU / n))) % n


func picked() -> String:
	return Marks.WHEEL[sel] if sel >= 0 else ""


func _process(delta: float) -> void:
	if visible and _t < 1.0:
		_t = minf(1.0, _t + delta * 7.0)
		queue_redraw()


func _draw() -> void:
	var n := Marks.WHEEL.size()
	var grow := 1.0 - pow(1.0 - _t, 3.0)
	var r_in := R_IN * (0.7 + 0.3 * grow)
	var r_out := R_OUT * (0.7 + 0.3 * grow)
	modulate.a = grow
	W.Draw.glow(self, center, r_out * 1.25, Color(0, 0, 0), 1.6)
	# Glass ring.
	var step := TAU / n
	for i in n:
		var mid := -PI * 0.5 + i * step
		var a0 := mid - step * 0.5 + GAP
		var a1 := mid + step * 0.5 - GAP
		var on := i == sel
		var fill := Color(Styles.AMBER.darkened(0.72), 0.95) if on else Color(Styles.BG_SOFT, 0.94)
		var pts := _sector(r_in, r_out + (6.0 if on else 0.0), a0, a1)
		draw_colored_polygon(pts, fill)
		var edge := pts.duplicate()
		edge.append(pts[0])
		draw_polyline(edge, Styles.AMBER if on else Styles.BORDER_STRONG, 2.0 if on else 1.2, true)
		var kind: String = Marks.WHEEL[i]
		var info := Marks.kind_info(kind)
		var c := center + Vector2.from_angle(mid) * (r_in + r_out) * 0.5
		var isz := 34.0 if on else 30.0
		if kind == "danger" and not on:
			W.Draw.glow(self, c, 24.0, Styles.DANGER, 0.35)
		Icons.draw(self, info.icon, Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz)),
			Styles.AMBER_LIGHT if on else (Styles.DANGER_TEXT if kind == "danger" else Styles.TEXT), 2.2)
	# The player's colour round the rim.
	draw_arc(center, r_out + 12.0, 0, TAU, 96, Color(color, 0.85), 3.0, true)
	# Hub: what you'd send, or cancel.
	draw_circle(center, r_in - 6.0, Color(Styles.GROUND, 0.96))
	draw_arc(center, r_in - 6.0, 0, TAU, 48, Styles.BORDER, 1.5, true)
	var label := str(Marks.kind_info(picked()).label) if sel >= 0 else "Cancel"
	var col := Styles.AMBER if sel >= 0 else Styles.MUTED
	_text_c(Styles.FONT_COND_BOLD, label.to_upper(), center + Vector2(0, 5), 13, col)
	if subject != "":
		var font := Styles.FONT_BODY_BOLD
		var fs := Styles.fs(14)
		var w := font.get_string_size(subject, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 28.0
		var r := Rect2(center + Vector2(-w * 0.5, r_out + 22.0), Vector2(w, 28.0))
		W.Draw.capsule(self, r, Color(Styles.BG_SOFT, 0.95))
		draw_rect(Rect2(r.position + Vector2(10, 7), Vector2(3, 14)), color)
		_text_c(font, subject, r.get_center() + Vector2(3, 5), 14, Styles.TEXT)


func _sector(r0: float, r1: float, a0: float, a1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 18
	for k in steps + 1:
		pts.append(center + Vector2.from_angle(lerpf(a0, a1, float(k) / steps)) * r1)
	for k in steps + 1:
		pts.append(center + Vector2.from_angle(lerpf(a1, a0, float(k) / steps)) * r0)
	return pts


func _text_c(font: Font, text: String, at: Vector2, size_px: int, col: Color) -> void:
	var fs := Styles.fs(size_px)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, at - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
