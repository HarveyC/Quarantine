extends RefCounted
## Small custom-drawn HUD pieces: bracketed panels, HP pips, action diamonds,
## the Infection bar with tier marks, icons and keycaps.

const Styles := preload("res://ui/styles.gd")
const Icons := preload("res://ui/icons.gd")


const Frame := preload("res://ui/frame.gd")


## Segmented bar: `filled` of `count` segments, optionally a hatched range that a
## preview says will be lost (last `lose` filled segments).
class Pips extends Control:
	var count := 5
	var filled := 5
	var lose := 0
	var color := Styles.HP
	var off := Styles.HP_OFF
	var seg := Vector2(12, 5)
	var gap := 3.0

	func _init(seg_size := Vector2(12, 5)) -> void:
		seg = seg_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_values(c: int, f: int, l := 0, col := Styles.HP) -> void:
		count = maxi(c, 0)
		filled = clampi(f, 0, count)
		lose = clampi(l, 0, filled)
		color = col
		custom_minimum_size = Vector2(count * seg.x + maxf(0, count - 1) * gap, seg.y)
		queue_redraw()

	func _draw() -> void:
		var y := (size.y - seg.y) * 0.5
		for i in count:
			var r := Rect2(i * (seg.x + gap), y, seg.x, seg.y)
			if i >= filled:
				draw_rect(r, off)
			elif i >= filled - lose:
				draw_rect(r, Color("5a2318"))
				var stripes := 3
				for k in stripes:
					var x := r.position.x + (k + 0.5) * r.size.x / stripes
					draw_line(Vector2(x - 2, r.end.y), Vector2(x + 2, r.position.y), Styles.DANGER, 2.0)
			else:
				draw_rect(r, color)


## Action points as small diamonds.
class Diamonds extends Control:
	var total := 2
	var filled := 2
	var color := Styles.AMBER
	var d := 9.0

	func _init(size_px := 9.0) -> void:
		d = size_px
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_values(t: int, f: int, col := Styles.AMBER) -> void:
		total = maxi(t, 0)
		filled = clampi(f, 0, total)
		color = col
		var step := d * 1.45 + 3.0
		custom_minimum_size = Vector2(total * step, d * 1.45)
		queue_redraw()

	func _draw() -> void:
		var h := d * 0.72
		var step := d * 1.45 + 3.0
		for i in total:
			var c := Vector2(h + i * step, size.y * 0.5)
			var pts := PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0)])
			if i < filled:
				draw_colored_polygon(pts, color)
			else:
				pts.append(pts[0])
				draw_polyline(pts, Color("5b6150"), 1.0, true)


## Infection 0-100 with tier marks at 25/50/75, a glow on the fill, and an optional
## preview value drawn as a hatched ghost.
class InfBar extends Control:
	var value := 0
	var preview := -1

	func _init(h := 5.0) -> void:
		custom_minimum_size = Vector2(60, h)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_value(v: int) -> void:
		value = clampi(v, 0, 100)
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color("1d2723"))
		var w := size.x * value / 100.0
		if value > 0:
			draw_rect(Rect2(0, -1, w, size.y + 2), Color(Styles.TEAL, 0.18))
			draw_rect(Rect2(0, 0, w, size.y), Styles.TEAL if value >= 25 else Styles.TEAL.darkened(0.25))
		for t in [25, 50, 75]:
			var x: float = size.x * t / 100.0
			draw_rect(Rect2(x - 0.5, -2, 1.5, size.y + 4), Styles.GROUND)


## A line icon from Icons, sized by custom_minimum_size.
class Icon extends Control:
	var id := ""
	var color := Styles.TEXT
	var width := 2.0

	func _init(icon_id := "", col := Styles.TEXT, px := 24.0, w := 2.0) -> void:
		id = icon_id
		color = col
		width = w
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_icon(icon_id: String, col: Color) -> void:
		id = icon_id
		color = col
		queue_redraw()

	func _draw() -> void:
		Icons.draw(self, id, Rect2(Vector2.ZERO, size), color, width)


## Square class-icon tile used on soldier cards.
static func glyph(kind: String, col: Color, px := 46.0, border := Color("3a443a")) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Styles.BG_RAISED
	sb.border_color = border
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(px, px)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := Icon.new(Icons.for_class(kind), col, px * 0.55, 1.8)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(ic)
	return p


## Keyboard key cap, e.g. [Tab].
static func keycap(text: String, size := 11, fg := Color("d6d2c2"), bg := Color("151a16"), border := Color("4d574b")) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.border_width_bottom = 2
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Styles.mono(text, size, fg)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(10, 0)
	p.add_child(l)
	return p


## Flat chip: a filled caps tag ("SQUAD PHASE") or an outlined one.
static func chip(text: String, col: Color, filled := true, size := 13) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col if filled else Color.TRANSPARENT
	sb.border_color = col if filled else Color("3a433a")
	sb.set_border_width_all(1)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(Styles.caps(text, size, Styles.GROUND if filled else Styles.DIM))
	return p
