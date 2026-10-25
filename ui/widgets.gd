extends RefCounted
## Small custom-drawn HUD pieces in the Bloom look: rounded HP pips, glowing lantern action
## orbs, the Infection bar with tier marks, ring gauges and portrait rings, creeping Bloom
## tendrils, icons, key caps and chips.

const Styles := preload("res://ui/styles.gd")
const Icons := preload("res://ui/icons.gd")


const Frame := preload("res://ui/frame.gd")
const Draw := preload("res://ui/bloom_draw.gd")


## Segmented bar: `filled` of `count` segments, optionally a hatched range that a
## preview says will be lost (last `lose` filled segments) or a ghost range it would refill
## (the `gain` empty segments after the fill).
class Pips extends Control:
	var count := 5
	var filled := 5
	var lose := 0
	var gain := 0
	var color := Styles.HP
	var off := Styles.HP_OFF
	var seg := Vector2(12, 5)
	var gap := 3.0

	func _init(seg_size := Vector2(12, 5)) -> void:
		seg = seg_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_values(c: int, f: int, l := 0, col := Styles.HP, g := 0) -> void:
		count = maxi(c, 0)
		filled = clampi(f, 0, count)
		lose = clampi(l, 0, filled)
		gain = clampi(g, 0, count - filled)
		color = col
		custom_minimum_size = Vector2(count * seg.x + maxf(0, count - 1) * gap, seg.y)
		queue_redraw()

	func _draw() -> void:
		var y := (size.y - seg.y) * 0.5
		for i in count:
			var r := Rect2(i * (seg.x + gap), y, seg.x, seg.y)
			if i >= filled + gain:
				Draw.capsule(self, r, off)
			elif i >= filled:
				Draw.capsule(self, r, Color(color, 0.28))
				Draw.capsule(self, r.grow(-1.2), Color(color, 0.5))
			elif i >= filled - lose:
				Draw.capsule(self, r, Color(Styles.DANGER, 0.3))
				Draw.capsule(self, r.grow(-1.2), Color(Styles.DANGER, 0.55))
			else:
				Draw.capsule(self, r, color)


## HP pips in the XCOM 2 style: one pip per HP, wrapping into rows of PER_ROW with a wider gap
## after every GROUP, so a 22 HP soldier is two short rows and a 40 HP boss four, never a ruler.
## Same values and preview ranges as Pips.
class HpPips extends Pips:
	const PER_ROW := 10
	const GROUP := 5
	var row_gap := 2.0

	func _init(seg_size := Vector2(7, 4), pip_gap := 2.0) -> void:
		super(seg_size)
		gap = pip_gap
		row_gap = maxf(2.0, seg_size.y * 0.5)

	static func rows_for(max_hp: int) -> int:
		return maxi(1, ceili(max_hp / float(PER_ROW)))

	func _group_gap() -> float:
		return gap + maxf(2.0, seg.x * 0.4)

	func _pip_x(i: int) -> float:
		var k := i % PER_ROW
		return k * (seg.x + gap) + (_group_gap() - gap if k >= GROUP else 0.0)

	func set_values(c: int, f: int, l := 0, col := Styles.HP, g := 0) -> void:
		super(c, f, l, col, g)
		var cols := mini(count, PER_ROW)
		var rows := rows_for(count)
		custom_minimum_size = Vector2(_pip_x(cols - 1) + seg.x if cols > 0 else 0.0, rows * seg.y + (rows - 1) * row_gap)

	func _draw() -> void:
		var y0 := (size.y - custom_minimum_size.y) * 0.5
		for i in count:
			var r := Rect2(_pip_x(i), y0 + int(i / PER_ROW) * (seg.y + row_gap), seg.x, seg.y)
			if i >= filled + gain:
				Draw.capsule(self, r, off)
			elif i >= filled:
				Draw.capsule(self, r, Color(color, 0.28))
				Draw.capsule(self, r.grow(-1.2), Color(color, 0.5))
			elif i >= filled - lose:
				Draw.capsule(self, r, Color(Styles.DANGER, 0.3))
				Draw.capsule(self, r.grow(-1.2), Color(Styles.DANGER, 0.55))
			else:
				Draw.capsule(self, r, color)


## Action points as small glowing lantern orbs (the class keeps its old name).
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
		var rad := d * 0.6
		var step := d * 1.45 + 3.0
		for i in total:
			var c := Vector2(d * 0.72 + i * step, size.y * 0.5)
			if i < filled:
				Draw.glow(self, c, rad * 2.0, color, 0.9)
				draw_circle(c, rad, color)
				draw_circle(c + Vector2(-rad, -rad) * 0.3, rad * 0.35, Color(1, 1, 1, 0.45))
			else:
				draw_arc(c, rad - 0.5, 0, TAU, 20, Color(Styles.DIM, 0.45), 1.2, true)


## Infection 0-100 as a rounded teal bar with tier marks at 25/50/75, a glow on the fill, and
## an optional preview value drawn as a ghost.
class InfBar extends Control:
	var value := 0
	var preview := -1

	func _init(h := 5.0) -> void:
		custom_minimum_size = Vector2(60, h)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_value(v: int, to := -1) -> void:
		value = clampi(v, 0, 100)
		preview = clampi(to, -1, 100)
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		Draw.capsule(self, r, Color(Styles.TEAL, 0.1))
		var shown := mini(value, preview) if preview >= 0 else value
		var w := size.x * shown / 100.0
		if preview > value:
			# The rise as a brighter ghost past the current fill.
			var gr := Rect2(0, 0, maxf(size.x * preview / 100.0, size.y), size.y)
			Draw.capsule(self, gr.grow(2.0), Color(Styles.TEAL, 0.22))
			Draw.capsule(self, gr, Color(Styles.TEAL.lightened(0.25), 0.5))
		elif preview >= 0 and preview < value:
			# The drop as a hollow stretch where the fill used to be.
			var dr := Rect2(0, 0, maxf(size.x * value / 100.0, size.y), size.y)
			Draw.capsule(self, dr, Color(Styles.TEAL, 0.18))
		if shown > 0:
			var fr := Rect2(0, 0, maxf(w, size.y), size.y)
			Draw.capsule(self, fr.grow(1.5), Color(Styles.TEAL, 0.2))
			Draw.capsule(self, fr, Styles.TEAL if shown >= 25 else Styles.TEAL.darkened(0.25))
		for t in [25, 50, 75]:
			var x: float = size.x * t / 100.0
			draw_rect(Rect2(x - 0.75, -1, 1.5, size.y + 2), Styles.GROUND)


## A ring gauge: a track circle and an arc filled clockwise from the top to `value` (0..1). An
## optional second arc (`extra`, after the fill) shows a preview. The fill glows.
class Ring extends Control:
	var value := 0.0
	var extra := 0.0
	var color := Styles.TEAL
	var extra_color := Styles.DANGER
	var track := Color(1, 1, 1, 0.1)
	var thickness := 5.0
	var glow := true

	func _init(px := 64.0, thick := 5.0, col := Styles.TEAL) -> void:
		custom_minimum_size = Vector2(px, px)
		thickness = thick
		color = col
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_value(v: float, col := color, more := 0.0) -> void:
		value = clampf(v, 0.0, 1.0)
		color = col
		extra = clampf(more, 0.0, 1.0 - value)
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - thickness * 0.5 - 1.0
		draw_arc(c, r, 0, TAU, 64, track, thickness, true)
		var a0 := -PI * 0.5
		if value > 0.0:
			var a1 := a0 + TAU * value
			if glow:
				draw_arc(c, r, a0, a1, 64, Color(color, 0.18), thickness + 7.0, true)
				draw_arc(c, r, a0, a1, 64, Color(color, 0.3), thickness + 3.0, true)
			draw_arc(c, r, a0, a1, 64, color, thickness, true)
		if extra > 0.0:
			draw_arc(c, r, a0 + TAU * value, a0 + TAU * (value + extra), 32, Color(extra_color, 0.7), thickness, true)


## A round soldier portrait: the class icon in a dark disc, a thin owner-colour inner ring, and
## an outer ring gauge for Infection (teal). `lit` adds the lantern glow of the active soldier.
class Portrait extends Control:
	var kind := ""
	var owner_color := Styles.TEXT
	var infection := 0
	var lit := false
	var dim := false
	var preview := -1   # Infection a hover preview would leave, drawn as a ghost arc

	func _init(px := 64.0) -> void:
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func setup(k: String, col: Color, inf: int, is_lit := false, is_dim := false) -> void:
		kind = k
		owner_color = col
		infection = inf
		lit = is_lit
		dim = is_dim
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var R := minf(size.x, size.y) * 0.5
		var ring := maxf(3.0, R * 0.09)
		if lit:
			Draw.glow(self, c, R * 1.45, Styles.AMBER, 1.0)
		elif infection >= 50:
			Draw.glow(self, c, R * 1.35, Styles.TEAL, 0.8)
		var r := R - ring * 0.5 - 1.0
		draw_arc(c, r, 0, TAU, 64, Color(1, 1, 1, 0.1), ring, true)
		var shown := mini(infection, preview) if preview >= 0 else infection
		if preview > infection:
			var g1 := -PI * 0.5 + TAU * preview / 100.0
			draw_arc(c, r, -PI * 0.5, g1, 64, Color(Styles.TEAL, 0.45), ring, true)
		elif preview >= 0 and preview < infection:
			var g1 := -PI * 0.5 + TAU * infection / 100.0
			draw_arc(c, r, -PI * 0.5, g1, 64, Color(Styles.TEAL, 0.18), ring, true)
		if shown > 0:
			var a1 := -PI * 0.5 + TAU * shown / 100.0
			draw_arc(c, r, -PI * 0.5, a1, 64, Color(Styles.TEAL, 0.3), ring + 4.0, true)
			draw_arc(c, r, -PI * 0.5, a1, 64, Styles.TEAL, ring, true)
		var inner := r - ring * 0.5 - 2.0
		draw_circle(c, inner, Styles.GROUND)
		draw_circle(c, inner - 1.0, Color("1a2433") if not dim else Color("121822"))
		draw_arc(c, inner - 1.0, 0, TAU, 48, Styles.AMBER if lit else Color(owner_color, 0.85), 2.0, true)
		var icol := (Styles.AMBER_LIGHT if lit else Styles.TEXT) if not dim else Styles.MUTED
		var ip := inner * 1.05
		Icons.draw(self, Icons.for_class(kind), Rect2(c - Vector2(ip, ip) * 0.5, Vector2(ip, ip)), icol, maxf(1.6, R * 0.05))


## Creeping Bloom tendrils: a few branching, slowly swaying veins with glowing nodules, grown
## from one edge of the control toward `reach` (0..1) of the way across. Purely decorative;
## screens put it behind their content. `edge`: "left", "right", "top", "bottom" or "center"
## (radiating from `origin`, in 0..1 of the size).
class Veins extends Control:
	var edge := "left"
	var origin := Vector2(0.5, 0.5)
	var reach := 0.3
	var color := Styles.TEAL
	var strands := 5
	var seed_value := 7
	var alpha := 0.75
	var animate := true
	var branching := 0.22
	var start_radius := 0.0   # "center": strands start this far (px) from the origin
	var _t := 0.0
	var _paths: Array = []

	func _init(from_edge := "left", how_far := 0.3, count := 5, s := 7) -> void:
		edge = from_edge
		reach = how_far
		strands = count
		seed_value = s
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		resized.connect(_build)
		_build()
		set_process(animate)

	func set_reach(v: float) -> void:
		reach = clampf(v, 0.0, 1.0)
		_build()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _build() -> void:
		_paths.clear()
		if size.x < 2 or size.y < 2:
			return
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		for i in strands:
			var start: Vector2
			var dir: Vector2
			var span: float
			var f := (i + 0.5 + rng.randf_range(-0.35, 0.35)) / strands
			match edge:
				"right":
					start = Vector2(size.x + 4, size.y * f)
					dir = Vector2.LEFT
					span = size.x
				"top":
					start = Vector2(size.x * f, -4)
					dir = Vector2.DOWN
					span = size.y
				"bottom":
					start = Vector2(size.x * f, size.y + 4)
					dir = Vector2.UP
					span = size.y
				"center":
					var a := TAU * (i + rng.randf_range(-0.3, 0.3)) / strands
					dir = Vector2(cos(a), sin(a))
					start = size * origin + dir * start_radius
					span = size.length() * 0.5
				_:
					start = Vector2(-4, size.y * f)
					dir = Vector2.RIGHT
					span = size.x
			var length := span * reach * rng.randf_range(0.55, 1.0)
			_grow(rng, start, dir, length, 3.2 - (0.0 if i % 2 == 0 else 0.8), 0)

	func _grow(rng: RandomNumberGenerator, start: Vector2, dir: Vector2, length: float, width: float, depth: int) -> void:
		if length < 12.0:
			return
		var pts := PackedVector2Array([start])
		var p := start
		var d := dir.normalized()
		var steps := maxi(4, int(length / 18.0))
		var step := length / steps
		for k in steps:
			d = d.rotated(rng.randf_range(-0.45, 0.45)).normalized()
			d = (d + dir.normalized() * 0.35).normalized()
			p += d * step
			pts.append(p)
			if depth < 2 and k > 1 and rng.randf() < branching:
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				_grow(rng, p, d.rotated(side * rng.randf_range(0.6, 1.1)), length * rng.randf_range(0.25, 0.45), width * 0.55, depth + 1)
		_paths.append({"pts": pts, "w": width, "phase": rng.randf() * TAU, "depth": depth})

	func _draw() -> void:
		for path in _paths:
			var pts: PackedVector2Array = path.pts
			var sway := PackedVector2Array()
			for k in pts.size():
				var wob := sin(_t * 0.6 + path.phase + k * 0.7) * 1.6 * (float(k) / pts.size())
				sway.append(pts[k] + Vector2(wob, -wob))
			var w: float = path.w
			draw_polyline(sway, Color(color, alpha * 0.18), w + 6.0, true)
			draw_polyline(sway, Color(color, alpha), w, true)
			var tip := sway[sway.size() - 1]
			var pulse := 0.75 + 0.25 * sin(_t * 1.4 + path.phase)
			Draw.glow(self, tip, (w + 3.0) * 3.0, color, alpha * pulse)
			draw_circle(tip, w + 1.2, Color(color, alpha))


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


## Holds a screen's layout at full size and shrinks it evenly when it needs more room than it
## has (Largest text on a small window), so nothing runs off the edge. Reports no minimum size
## of its own: put it at the root of a full-screen layout.
class FitBox extends Container:
	var _fitting := false
	var _scale := 1.0
	var _for_size := Vector2.ZERO

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _get_minimum_size() -> Vector2:
		return Vector2.ZERO

	func _notification(what: int) -> void:
		if what != NOTIFICATION_SORT_CHILDREN or size.x <= 0 or size.y <= 0 or _fitting:
			return
		_fitting = true
		if size != _for_size:
			_for_size = size
			_scale = 1.0
		for c in get_children():
			if c is Control and (c as Control).visible:
				_fit(c)
		_fitting = false

	## Starts over at full size, for when the content swaps (a panel opens or closes).
	func refit() -> void:
		_for_size = Vector2.ZERO
		queue_sort()

	## Wrapped and flowing content needs less height when it gets more width, so the scale only
	## ever steps down for a given box size: it settles instead of flickering between two fits.
	func _fit(c: Control) -> void:
		for i in 6:
			fit_child_in_rect(c, Rect2(Vector2.ZERO, size / _scale))
			c.scale = Vector2(_scale, _scale)
			var need := c.get_combined_minimum_size()
			var next := minf(1.0, minf(size.x / maxf(need.x, 1.0), size.y / maxf(need.y, 1.0)))
			if next >= _scale - 0.002:
				break
			_scale = next


## Round class-icon tile used on soldier cards: a dark disc with a coloured ring.
static func glyph(kind: String, col: Color, px := 46.0, border := Styles.BORDER_STRONG) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := Styles.panel_box(Color("162030"), border, Styles.PILL)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.set_content_margin_all(0)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(px, px)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := Icon.new(Icons.for_class(kind), col, px * 0.52, 1.8)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(ic)
	return p


## Keyboard key cap, e.g. [Tab].
static func keycap(text: String, size := 11, fg := Styles.TEXT, bg := Color("141c2a"), border := Styles.BORDER_STRONG) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := Styles.panel_box(bg, border, 6)
	sb.border_width_bottom = 2
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Styles.mono(text, size, fg)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(10, 0)
	p.add_child(l)
	return p


## A caps tag ("OVERWATCH", "HIT 72%") set straight on its panel: no pill, no box. `filled`
## tags are the loud ones (full colour, bold); the others are tinted towards the dim text.
static func chip(text: String, col: Color, filled := true, size := 13) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(Styles.caps(text, size, col if filled else col.lerp(Styles.DIM, 0.3)))
	return p
