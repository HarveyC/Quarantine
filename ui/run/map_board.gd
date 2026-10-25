extends Control
## The act's node map, drawn left to right: the drop point, rows 1-5, the boss. Shows where the
## squad is, the path it took, the routes open now (amber), everyone's route-vote chips and a hover
## card for any node. Purely a view of RunState: clicks are reported with node_pressed.

signal node_pressed(id: int)
signal node_hovered(id: int)   # -1 when the mouse leaves a node

const Styles := preload("res://ui/styles.gd")
const Icons := preload("res://ui/icons.gd")
const W := preload("res://ui/widgets.gd")
const NodeInfo := preload("res://ui/run/node_info.gd")

const ROW_HINTS: Array[String] = ["", "Skirmish", "Rolled", "Rolled", "Field hospital", "Boss"]
const LINE := Color(0.66, 0.78, 0.8, 0.32)
const TRAVELLED := Color("c98a3a")
const NIGHT := Color("111a28")
const PAD := Vector2(100, 0)
const HEAD_H := 64.0
const LEGEND_H := 40.0

enum Look { FUTURE, OPTION, CURRENT, VISITED, PASSED }

var run: RunState
## node id -> NodeDot
var dots := {}
var reveal_mode := false
## player -> display name, for vote chips.
var names := {}
var hover := -1
var _legend_rects: Array = []   # [Rect2, node type] per legend item, for hover cards

var _card: Control
var _t := 0.0
var _veins: W.Veins


## One node on the board: a ring with its type icon. Draws itself from its fields.
class NodeDot extends Control:
	var id := -1
	var type := ""
	var look: int = 0
	var revealable := false
	var hovered := false
	var pulse := 0.0
	## Smaller rings on a short board (a small window at a big Interface scale).
	var k := 1.0

	func radius() -> float:
		if type == RunMap.BOSS:
			return 50.0 * k
		match look:
			1: return 37.0 * k   # OPTION
			2: return 40.0 * k   # CURRENT
		return 30.0 * k

	func _draw() -> void:
		var c := size * 0.5
		var r := radius()
		var col := NodeInfo.color(type)
		var border := LINE
		var fill := NIGHT
		var icon_col := Styles.DIM
		var width := 2.0
		var alpha := 1.0
		var infested := type == RunMap.NEST or type == RunMap.BOSS or type == RunMap.AMBUSH
		match look:
			Look.OPTION:
				border = col if type != RunMap.SKIRMISH and type != RunMap.UNKNOWN else Styles.AMBER
				icon_col = border.lightened(0.2)
				fill = Color(border.darkened(0.78), 0.97)
				width = 2.5
				W.Draw.glow(self, c, r * 1.55, Styles.AMBER if not infested else border, 0.55 + 0.35 * pulse)
				draw_arc(c, r + 5 + pulse * 2.0, 0, TAU, 64, Color(Styles.AMBER, 0.25 + 0.2 * pulse), 2.0, true)
			Look.CURRENT:
				# The squad's lantern: a glowing amber orb.
				W.Draw.glow(self, c, r * 1.8, Styles.AMBER, 1.0)
				_blob(c, r, Styles.AMBER_DEEP, 0)
				_blob(c - Vector2(r, r) * 0.08, r * 0.82, Styles.AMBER, 0)
				_blob(c - Vector2(r, r) * 0.22, r * 0.4, Styles.AMBER_LIGHT, 0)
				var lr := r * 1.0
				Icons.draw(self, "lantern", Rect2(c - Vector2(lr, lr) * 0.5, Vector2(lr, lr)), Styles.AMBER_DARK, 2.4)
				return
			Look.VISITED:
				border = Color(TRAVELLED, 0.7)
				icon_col = TRAVELLED
				fill = Color("1a1712")
			Look.PASSED:
				# Behind the squad the Bloom has taken the node.
				alpha = 0.75
				border = Color(Styles.TEAL, 0.45)
				icon_col = Color(Styles.TEAL, 0.6)
				fill = Color(Styles.TEAL_DEEP, 0.35)
			Look.FUTURE:
				if type == RunMap.UNKNOWN:
					border = Color(Styles.DIM, 0.4)
					icon_col = Color(Styles.DIM, 0.6)
				if infested or type == RunMap.HOSPITAL or type == RunMap.DEPOT:
					border = Color(col, 0.55)
					icon_col = col.darkened(0.05)
		if type == RunMap.BOSS and look != Look.PASSED:
			W.Draw.glow(self, c, r * 1.7, Styles.DANGER, 0.6)
			fill = Color("2a0d1e")
			border = Styles.DANGER
			width = maxf(width, 3.0)
		if revealable:
			border = Styles.AMBER
			icon_col = Styles.AMBER
			width = 3.0
		if hovered:
			fill = fill.lightened(0.08)
			border = border.lightened(0.25)
		modulate.a = alpha
		if infested and look != Look.PASSED:
			_blob(c, r, fill, 1 + id % 5)
			_blob_line(c, r, border, width, 1 + id % 5)
		else:
			draw_circle(c, r, fill)
			if type == RunMap.UNKNOWN and not revealable:
				for k in 16:
					var a0 := k * TAU / 16.0
					draw_arc(c, r, a0, a0 + TAU / 32.0, 6, border, width, true)
			else:
				draw_arc(c, r, 0, TAU, 64, border, width, true)
		var ir := r * (0.95 if type == RunMap.BOSS else 0.9)
		Icons.draw(self, NodeInfo.icon(type), Rect2(c - Vector2(ir, ir) * 0.5, Vector2(ir, ir)), icon_col, 2.2 if r > 34 else 1.9)

	## An organic, slightly lumpy disc (infested nodes). `lumps` 0 is a plain circle.
	func _blob_pts(c: Vector2, r: float, lumps: int) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for k in 48:
			var a := TAU * k / 48.0
			var wob := 1.0 + (0.06 * sin(a * 3.0 + lumps) + 0.04 * sin(a * 5.0 + lumps * 2.0) if lumps > 0 else 0.0)
			pts.append(c + Vector2(cos(a), sin(a)) * r * wob)
		return pts

	func _blob(c: Vector2, r: float, col: Color, lumps: int) -> void:
		draw_colored_polygon(_blob_pts(c, r, lumps), col)

	func _blob_line(c: Vector2, r: float, col: Color, w: float, lumps: int) -> void:
		var pts := _blob_pts(c, r, lumps)
		pts.append(pts[0])
		draw_polyline(pts, col, w, true)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = false
	resized.connect(_layout)
	_veins = W.Veins.new("left", 1.0, 6, 23)
	_veins.alpha = 0.6
	_veins.branching = 0.16
	add_child(_veins)


func _process(delta: float) -> void:
	_t += delta
	# Keep the Bloom's reach in step with the board (the parent can size us after a refresh).
	if run != null and absf(_veins.size.x - (bloom_edge() + position.x + 30.0)) > 2.0:
		_layout()
	var p := 0.5 + 0.5 * sin(_t * 3.0)
	for id in dots:
		var d: NodeDot = dots[id]
		if d.look == Look.OPTION:
			d.pulse = p
			d.queue_redraw()


# --- geometry -----------------------------------------------------------------------

func _area() -> Rect2:
	return Rect2(PAD.x, HEAD_H + 30, size.x - PAD.x * 2, size.y - HEAD_H - 30 - LEGEND_H - 40)


## Centre x of a column: 0 is the drop point, 1-5 the rows.
func col_x(row: int) -> float:
	var a := _area()
	return a.position.x + a.size.x * row / float(RunState.ROWS)


func node_pos(n: Dictionary) -> Vector2:
	var a := _area()
	return Vector2(col_x(n.row), a.position.y + n.x * a.size.y)


func drop_pos() -> Vector2:
	var a := _area()
	return Vector2(col_x(0), a.get_center().y)


# --- state ------------------------------------------------------------------------------

func set_run(r: RunState) -> void:
	run = r
	refresh()


func refresh() -> void:
	if run == null:
		return
	var ids := {}
	for n in run.map:
		ids[n.id] = true
	for id in dots.keys():
		if not ids.has(id):
			dots[id].queue_free()
			dots.erase(id)
	var reach := run.reachable_nodes() if run.phase == RunState.Phase.MAP else ([] as Array[int])
	var row_now := run.row
	for n in run.map:
		var d: NodeDot = dots.get(n.id)
		if d == null:
			d = NodeDot.new()
			d.id = n.id
			d.mouse_filter = Control.MOUSE_FILTER_STOP
			var id: int = n.id
			d.gui_input.connect(func(e: InputEvent) -> void:
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					node_pressed.emit(id))
			d.mouse_entered.connect(func() -> void: set_hover(id))
			d.mouse_exited.connect(func() -> void:
				if hover == id:
					set_hover(-1))
			add_child(d)
			dots[n.id] = d
		d.type = RunMap.shown_type(n)
		if n.id == run.node:
			d.look = Look.CURRENT
		elif reach.has(n.id):
			d.look = Look.OPTION
		elif n.visited:
			d.look = Look.VISITED
		elif n.row <= row_now:
			d.look = Look.PASSED
		else:
			d.look = Look.FUTURE
		d.revealable = reveal_mode and n.hidden and run.phase == RunState.Phase.MAP and run.intel > 0
		var clickable: bool = d.look == Look.OPTION or d.revealable
		d.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if clickable else Control.CURSOR_ARROW
		d.queue_redraw()
	_layout()
	if hover >= 0 and not dots.has(hover):
		set_hover(-1)
	else:
		_rebuild_card()


func _layout() -> void:
	if run == null:
		return
	# The tendrils grow from the screen's left edge up to the Bloom's edge.
	var left := position.x + 30.0
	_veins.position = Vector2(-left, 0)
	_veins.size = Vector2(maxf(bloom_edge() + left, 10.0), size.y)
	_veins._build()
	var k := clampf(_area().size.y / 420.0, 0.7, 1.0)
	for n in run.map:
		var d: NodeDot = dots.get(n.id)
		if d != null:
			d.k = k
			var r := 54.0 * k
			d.size = Vector2(r, r) * 2
			d.position = node_pos(n) - d.size * 0.5
	_place_card()
	queue_redraw()


func set_hover(id: int) -> void:
	if hover == id:
		return
	if dots.has(hover):
		dots[hover].hovered = false
		dots[hover].queue_redraw()
	hover = id
	if dots.has(id):
		dots[id].hovered = true
		dots[id].queue_redraw()
	_rebuild_card()
	node_hovered.emit(id)


# --- hover card ------------------------------------------------------------------------

func _rebuild_card() -> void:
	if _card != null:
		_card.queue_free()
		_card = null
	if hover < 0 or run == null:
		return
	var n := run.get_node(hover)
	if n.is_empty():
		return
	var info := NodeInfo.card(run, n)
	var f := W.Frame.new(Vector4(16, 14, 16, 14))
	var accent: Color = info.tag_color if info.tag_color != Styles.DIM else Styles.BORDER_STRONG
	f.set_look(Color(0.047, 0.067, 0.106, 0.97), accent, Styles.AMBER)
	f.custom_minimum_size.x = 310
	f.z_index = 10
	var box := Styles.vbox(8)
	f.add_child(box)
	var head := Styles.hbox(8)
	head.add_child(Styles.caps(info.title, 21))
	head.add_child(Styles.spacer())
	if info.tag != "":
		head.add_child(Styles.caps(info.tag, 13, info.tag_color))
	box.add_child(head)
	if info.body != "":
		var body := Styles.label(info.body, 14, Color("cfccbd"))
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size.x = 278
		box.add_child(body)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for row in info.rows:
		grid.add_child(Styles.label(row[0], 13, Styles.MUTED))
		var v := Styles.label(row[1], 13, row[2])
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.custom_minimum_size.x = 200
		grid.add_child(v)
	box.add_child(grid)
	var hint := _card_hint(n)
	if hint != "":
		box.add_child(Styles.caps(hint, 12, Styles.AMBER))
	add_child(f)
	_card = f
	f.reset_size()
	_place_card.call_deferred()


func _card_hint(n: Dictionary) -> String:
	if run.phase != RunState.Phase.MAP:
		return ""
	var d: NodeDot = dots.get(n.id)
	if d == null:
		return ""
	if d.revealable:
		return "Click to reveal · 1 Intel"
	if d.look == Look.OPTION:
		return "Click to choose" if run.is_solo() else "Click to vote"
	return ""


func _place_card() -> void:
	if _card == null or run == null or not dots.has(hover):
		return
	var n := run.get_node(hover)
	var at := node_pos(n)
	var r: float = dots[hover].radius()
	_card.reset_size()
	var s := _card.size
	var p := at + Vector2(r + 22, -s.y * 0.5)
	if p.x + s.x > size.x - 8:
		p.x = at.x - r - 22 - s.x
	p.y = clampf(p.y, 8, size.y - s.y - 8)
	_card.position = p


# --- drawing -----------------------------------------------------------------------------

func _draw() -> void:
	if run == null:
		return
	var font: Font = Styles.FONT_COND_BOLD
	var body: Font = Styles.FONT_BODY
	var a := _area()
	# Faint survey grid over the whole screen, and the Infection creeping in behind the squad.
	var full := Rect2(-position, (get_parent() as Control).size if get_parent() is Control else size)
	# Soft survey contours.
	for i in 7:
		var pts := PackedVector2Array()
		var y0 := full.position.y + full.size.y * (0.1 + i * 0.13)
		for xi in 41:
			var x := full.position.x + full.size.x * xi / 40.0
			pts.append(Vector2(x, y0 + sin(xi * 0.38 + i * 1.3) * 12.0))
		draw_polyline(pts, Color(Styles.DIM, 0.045), 1.0, true)
	# The Bloom creeping in from the left behind the squad: a teal haze that reaches past the
	# rows already left behind, deeper as the Outbreak grows. Tendrils (bloom_veins) grow with it.
	var haze_r := bloom_edge()
	var teal_a := Color(Styles.TEAL, 0.16)
	var teal_0 := Color(Styles.TEAL, 0.0)
	draw_polygon(PackedVector2Array([full.position, Vector2(haze_r, full.position.y), Vector2(haze_r, full.end.y), Vector2(full.position.x, full.end.y)]),
		PackedColorArray([teal_a, teal_0, teal_0, teal_a]))
	var hc := Vector2(full.position.x + (haze_r - full.position.x) * 0.25, a.get_center().y)
	W.Draw.glow(self, hc, (haze_r - full.position.x) * 0.9, Styles.TEAL, 0.9)

	# Column headers.
	for c in RunState.ROWS + 1:
		var cx := col_x(c)
		var here := c == run.row or (c == 0 and run.node < 0)
		var next := c == run.row + 1 and run.phase == RunState.Phase.MAP
		var head_col := Styles.AMBER if next else (TRAVELLED if here else Styles.MUTED)
		var label := "Drop" if c == 0 else "Row %d" % c
		_text_c(font, label.to_upper(), Vector2(cx, 26), 15, head_col, 1.5)
		if ROW_HINTS[c] != "":
			_text_c(body, ROW_HINTS[c], Vector2(cx, 46), 13, Styles.MUTED)
		draw_line(Vector2(cx, 58), Vector2(cx, 64), Color(head_col, 0.6), 1.0)

	# Links.
	var reach := run.reachable_nodes() if run.phase == RunState.Phase.MAP else ([] as Array[int])
	for n in run.map:
		if n.row == 1:
			var from := drop_pos()
			if run.node < 0 and reach.has(n.id):
				_link(from, node_pos(n), 18.0, _r(n.id), Styles.AMBER, 3.0, true)
			elif n.visited:
				_link(from, node_pos(n), 18.0, _r(n.id), TRAVELLED, 3.0, false)
			else:
				_link(from, node_pos(n), 18.0, _r(n.id), Color(LINE, 0.5 if run.node >= 0 else 1.0), 2.0, true)
		for id in n.links:
			var m := run.get_node(id)
			if m.is_empty():
				continue
			if n.visited and (m.visited or m.id == run.node) and n.id != run.node:
				_link(node_pos(n), node_pos(m), _r(n.id), _r(m.id), TRAVELLED, 3.0, false)
			elif n.id == run.node and reach.has(id):
				var voted := run.votes.values().has(id)
				_link(node_pos(n), node_pos(m), _r(n.id), _r(m.id), Styles.AMBER if voted else Color(Styles.AMBER, 0.75), 3.0, true)
			else:
				var faded: bool = n.row <= run.row and n.id != run.node
				_link(node_pos(n), node_pos(m), _r(n.id), _r(m.id), Color(LINE, 0.35 if faded else 1.0), 2.0, true)

	# Drop point.
	var dp := drop_pos()
	var dcol := Styles.AMBER if run.node < 0 else TRAVELLED
	if run.node < 0:
		W.Draw.glow(self, dp, 40, Styles.AMBER, 0.8)
	draw_circle(dp, 15, NIGHT)
	draw_arc(dp, 15, 0, TAU, 40, dcol, 2.0, true)
	Icons.draw(self, "arrow_right", Rect2(dp - Vector2(9, 9), Vector2(18, 18)), dcol, 2.0)
	if run.node < 0:
		_text_c(font, "SQUAD", dp + Vector2(0, 40), 14, Styles.AMBER, 1.5)

	# Labels under nodes: where the squad is, the open routes' names, the boss's name.
	for n in run.map:
		var p := node_pos(n)
		var type := RunMap.shown_type(n)
		var below := p + Vector2(0, _r(n.id) + 20)
		if n.id == run.node:
			_text_c(font, "SQUAD · HERE" if run.phase == RunState.Phase.MAP else "SQUAD", below, 14, Styles.AMBER, 1.5)
		elif type == RunMap.BOSS:
			_text_c(font, NodeInfo.boss_name(run).to_upper(), below, 15, NodeInfo.NEST_RED, 1.5)
		elif reach.has(n.id):
			var lc := NodeInfo.color(type) if type != RunMap.SKIRMISH and type != RunMap.UNKNOWN else Styles.AMBER
			var t := NodeInfo.short_name(type)
			if n.objective != "" and type != RunMap.UNKNOWN:
				t += " · " + NodeInfo.OBJECTIVE_NAMES.get(n.objective, n.objective)
			_text_c(font, t.to_upper(), below, 14, lc, 1.5)
			if type == RunMap.UNKNOWN:
				_text_c(body, "1 Intel to reveal", below + Vector2(0, 17), 12, Styles.MUTED)

	# Key numbers on the open routes, matching the vote panel (keys 1-4).
	for i in mini(reach.size(), 4):
		var n := run.get_node(reach[i])
		var kp := node_pos(n) + Vector2(-_r(n.id) - 8, -_r(n.id) + 2)
		draw_circle(kp, 12, Color("141c2a"))
		draw_arc(kp, 12, 0, TAU, 32, Color(Styles.AMBER, 0.7), 1.5, true)
		_text_c(Styles.FONT_MONO, str(i + 1), kp + Vector2(0, 5), 12, Styles.AMBER_LIGHT)

	# Votes: each voter's name in their colour over the node they picked (no pills; the side
	# panel says who hosts).
	var per_node := {}
	for pl in run.votes:
		var id: int = run.votes[pl]
		per_node[id] = per_node.get(id, []) + [pl]
	for id in per_node:
		var n := run.get_node(id)
		if n.is_empty():
			continue
		var voters: Array = per_node[id]
		voters.sort()
		var chips: Array = []
		var total := 0.0
		for pl in voters:
			var t := _voter_name(pl).to_upper()
			var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			chips.append([pl, t, w])
			total += w + 12
		var cx := node_pos(n).x - (total - 12) * 0.5
		var cy := node_pos(n).y - _r(id) - 14
		for ch in chips:
			draw_string_outline(font, Vector2(cx, cy), ch[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 5, Color(Styles.GROUND, 0.9))
			draw_string(font, Vector2(cx, cy), ch[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Styles.player_color(ch[0]))
			cx += ch[2] + 12

	# Legend.
	var lx := 0.0
	var ly := size.y - 18
	var items: Array = []
	var lw := 0.0
	for type in NodeInfo.LEGEND:
		var t := NodeInfo.short_name(type)
		var w := 18 + 6 + body.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		items.append([type, t, w])
		lw += w + 22
	lx = (size.x - (lw - 22)) * 0.5
	_legend_rects.clear()
	for it in items:
		_legend_rects.append([Rect2(lx - 4, ly - 18, it[2] + 8, 26), it[0]])
		var col := NodeInfo.color(it[0])
		Icons.draw(self, NodeInfo.icon(it[0]), Rect2(lx, ly - 13, 18, 18), col if col != Styles.TEXT else Styles.DIM, 1.6)
		draw_string(body, Vector2(lx + 24, ly), it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Styles.DIM)
		lx += it[2] + 22


## Hover card terms for the legend under the map (TermTips asks).
func tip_at(p: Vector2) -> Dictionary:
	for r in _legend_rects:
		if (r[0] as Rect2).has_point(p):
			return {"terms": ["node_" + str(r[1])]}
	return {}


## Where the Bloom's haze reaches on the board (x): past the squad's column, further with the
## Outbreak.
func bloom_edge() -> float:
	var row := maxi(run.row, 0)
	var x := col_x(row) - 20.0 + float(run.outbreak) * 22.0
	return clampf(x, PAD.x * 0.6, size.x * 0.85)


func _r(id: int) -> float:
	var d: NodeDot = dots.get(id)
	return d.radius() if d != null else 30.0


func _voter_name(p: int) -> String:
	var n: String = names.get(p, "")
	return n if n != "" else "P%d" % (p + 1)


## A link between two node centres, trimmed to the rings. Dotted for routes not taken.
func _link(a: Vector2, b: Vector2, ra: float, rb: float, col: Color, width: float, dotted: bool) -> void:
	var dir := (b - a).normalized()
	var from := a + dir * (ra + 6)
	var to := b - dir * (rb + 6)
	if (to - from).dot(dir) <= 0:
		return
	if dotted:
		var step := 10.0
		var dist := from.distance_to(to)
		var t := 0.0
		while t < dist:
			draw_circle(from + dir * t, width * 0.6, col)
			t += step
	else:
		draw_line(from, to, col, width, true)


func _text_c(font: Font, text: String, at: Vector2, size_px: int, col: Color, spacing := 0.0) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x + spacing * text.length()
	var x := at.x - w * 0.5
	if spacing <= 0.0:
		draw_string(font, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)
		return
	for ch in text:
		draw_string(font, Vector2(x, at.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x + spacing
