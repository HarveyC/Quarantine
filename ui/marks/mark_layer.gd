extends Control
## Co-op pings and map drawing on one screen (the tactical map or the route map). Reads ping and
## draw input, sends marks through the session, and draws every mark the session hands back:
## a pin with the player's colour, the ping's icon and a label, an arrow on the screen edge for
## pings out of view, and fading strokes.
##
## The screen-specific parts live in a "surface" (ui/marks/fight_surface.gd, route_surface.gd):
## what's under the pointer, where a mark sits on screen, who is pinging. Positions from the
## surface are in viewport coordinates (what get_mouse_position and unproject_position use).
##
## Input (Settings > Controls): Ping (G, middle mouse, L3) taps a quick ping that reads what's
## under the pointer, or held opens the ping wheel. Draw (V, R3) held sketches with the pointer.

signal draw_tapped   # the pad draw button was tapped without drawing (the fight uses it to zoom)

const Styles := preload("res://ui/styles.gd")
const Icons := preload("res://ui/icons.gd")
const W := preload("res://ui/widgets.gd")
const PingWheel := preload("res://ui/marks/ping_wheel.gd")

## Seconds the ping button is held before the wheel opens.
const HOLD := 0.22
## Screen pixels the pointer moves between stroke points.
const STEP_PX := 6.0
## Inset of the screen edge where off-screen arrows sit.
const EDGE := 34.0
const BADGE_R := 17.0
const SOUND_DB := {"ping": -7.0, "ping_attack": -6.0, "ping_danger": -5.0}

var surface: RefCounted
var session: Node
## Live pings: {m, t, label, node (Node3D or null)}
var pings: Array = []
## Live strokes: "player:id" -> {player, chunks: [[points, t]], done}
var strokes := {}
var wheel: PingWheel

var _press := {}          # the ping button while it's down: {src, t, at, target}
var _drawing := false
var _draw_pad := false
var _draw_id := 0
var _draw_pts: Array = []
var _draw_last := Vector2.INF
var _draw_flush := 0.0
var _drew := false
var _audio: AudioStreamPlayer
var _streams := {}


func _init() -> void:
	name = "Marks"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 5   # over the route map's node rings and vote chips, which are added later
	wheel = PingWheel.new()
	wheel.visible = false
	add_child(wheel)
	_audio = AudioStreamPlayer.new()
	_audio.bus = "UI" if AudioServer.get_bus_index("UI") >= 0 else "Master"
	add_child(_audio)
	for s in SOUND_DB:
		var path := "res://audio/%s.wav" % s
		if ResourceLoader.exists(path):
			_streams[s] = load(path)


## Hooks the layer to a surface and the session (anything with mark() and a marked signal).
func setup(surf: RefCounted, s: Node) -> void:
	surface = surf
	if session != null and session.has_signal("marked") and session.marked.is_connected(_on_marked):
		session.marked.disconnect(_on_marked)
	session = s
	if session != null and session.has_signal("marked"):
		session.marked.connect(_on_marked)
	clear()


func _exit_tree() -> void:
	clear()


func clear() -> void:
	for p in pings:
		_free_node(p)
	pings.clear()
	strokes.clear()
	_cancel_ping()
	_drawing = false
	queue_redraw()


# --- sending -----------------------------------------------------------------------------------

## Sends a ping of `kind` at `target` (a surface.target() result). An empty kind means the quick
## ping, which reads its kind from what's there.
func ping(target: Dictionary, kind := "") -> bool:
	if target.is_empty() or session == null or not session.has_method("mark"):
		return false
	var m := target.duplicate()
	var ctx := str(m.get("context", ""))
	m.erase("context")
	m.erase("subject")
	m.type = Marks.PING
	m.kind = kind if kind != "" else Marks.quick_kind(ctx)
	m.where = surface.where()
	m.player = surface.player()
	return session.mark(m)


func _send_stroke(end: bool) -> void:
	if _draw_pts.is_empty() and not end:
		return
	var pts: Variant
	if surface.where() == Marks.FIGHT:
		pts = PackedVector3Array(_draw_pts)
	else:
		pts = PackedVector2Array(_draw_pts)
	var m := {"type": Marks.STROKE, "where": surface.where(), "player": surface.player(), "id": _draw_id, "points": pts}
	if end:
		m.end = true
	if session != null and session.has_method("mark") and session.mark(m):
		# Start the next chunk where this one ended, so the line has no gaps.
		_draw_pts = [_draw_pts.back()] if not _draw_pts.is_empty() else []
	_draw_flush = 0.0


# --- receiving ---------------------------------------------------------------------------------

func _on_marked(m: Dictionary) -> void:
	if surface == null or m.get("where") != surface.where():
		return
	match m.type:
		Marks.PING:
			_add_ping(m)
		Marks.STROKE:
			_add_stroke(m)


func _add_ping(m: Dictionary) -> void:
	var mine := pings.filter(func(p: Dictionary) -> bool: return p.m.player == m.player)
	while mine.size() >= Marks.MAX_PINGS:
		_free_node(mine[0])
		pings.erase(mine[0])
		mine.remove_at(0)
	var p := {"m": m, "t": Marks.now(), "label": surface.describe(m), "node": surface.spawn(m)}
	pings.append(p)
	_play(str(Marks.kind_info(m.kind).sound))
	queue_redraw()


func _add_stroke(m: Dictionary) -> void:
	var key := "%d:%d" % [m.player, m.id]
	if not strokes.has(key):
		var own := strokes.keys().filter(func(k: String) -> bool: return strokes[k].player == m.player)
		while own.size() >= Marks.MAX_STROKES:
			strokes.erase(own.pop_front())
		strokes[key] = {"player": m.player, "chunks": [], "n": 0}
	var s: Dictionary = strokes[key]
	if s.n + m.points.size() > Marks.MAX_POINTS:
		return
	s.n += m.points.size()
	s.chunks.append([m.points, Marks.now()])
	queue_redraw()


func _free_node(p: Dictionary) -> void:
	var n: Variant = p.get("node")
	if n is Node and is_instance_valid(n):
		(n as Node).queue_free()


func _play(sound: String) -> void:
	if not _streams.has(sound) or preload("res://view/sfx.gd").muted or not _audio.is_inside_tree():
		return
	_audio.stream = _streams[sound]
	_audio.volume_db = SOUND_DB.get(sound, -6.0)
	_audio.pitch_scale = randf_range(0.97, 1.03)
	_audio.play()


# --- input -------------------------------------------------------------------------------------

func _active() -> bool:
	if surface == null or not is_visible_in_tree() or not surface.active():
		return false
	if GameSettings.is_menu_open():
		return false
	var vp := get_viewport()
	if vp != null and vp.gui_get_focus_owner() is LineEdit:
		return false
	for n in get_tree().get_nodes_in_group("pad_focus"):
		if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
			return false
	return true


func _input(e: InputEvent) -> void:
	if not _active():
		if not _press.is_empty() or _drawing:
			_cancel_ping()
			_end_draw()
		return
	GameSettings.ensure_input_map()
	var mb := e as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_begin_ping("mouse")
			elif _press.get("src") == "mouse":
				_end_ping()
			get_viewport().set_input_as_handled()
		elif wheel.visible and mb.pressed:
			# A click while the wheel is up picks the slice (right click cancels).
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_end_ping()
			else:
				_cancel_ping()
			get_viewport().set_input_as_handled()
		return
	if not (e is InputEventKey or e is InputEventJoypadButton) or e.is_echo():
		return
	if e.is_action("ping"):
		if e.is_pressed():
			_begin_ping("action")
		elif _press.get("src") == "action":
			_end_ping()
		get_viewport().set_input_as_handled()
	elif e.is_action("draw"):
		if e.is_pressed() and not _drawing:
			_begin_draw(e is InputEventJoypadButton)
		elif not e.is_pressed():
			_end_draw()
		get_viewport().set_input_as_handled()
	elif wheel.visible and e.is_pressed() and e.is_action("cancel"):
		_cancel_ping()
		get_viewport().set_input_as_handled()


func _pointer() -> Vector2:
	return get_viewport().get_mouse_position()


func _begin_ping(src: String) -> void:
	var at := _pointer()
	_press = {"src": src, "t": Marks.now(), "at": at, "target": surface.target(at)}


func _end_ping() -> void:
	if _press.is_empty():
		return
	var target: Dictionary = _press.target
	var kind := ""
	if wheel.visible:
		kind = wheel.picked()
		wheel.visible = false
		_press = {}
		if kind == "":
			return   # let go on the hub: cancelled
	_press = {}
	if target.is_empty() or not ping(target, kind):
		_play_ui("deny")


func _cancel_ping() -> void:
	_press = {}
	if wheel != null:
		wheel.visible = false


func _begin_draw(pad: bool) -> void:
	_drawing = true
	_draw_pad = pad
	_drew = false
	_draw_id = (_draw_id + 1) % 100000
	_draw_pts = []
	_draw_last = Vector2.INF
	_draw_flush = 0.0
	_sample_draw()


func _end_draw() -> void:
	if not _drawing:
		return
	_drawing = false
	if _drew:
		_send_stroke(true)
	elif _draw_pad:
		draw_tapped.emit()
	_draw_pts = []


func _sample_draw() -> void:
	var at := _pointer()
	if _draw_last != Vector2.INF and at.distance_to(_draw_last) < STEP_PX:
		return
	var pt: Variant = surface.point(at)
	if pt == null:
		return
	_draw_last = at
	_draw_pts.append(pt)
	if _draw_pts.size() >= 2:
		_drew = true
	if _draw_pts.size() >= Marks.MAX_CHUNK:
		_send_stroke(false)


func _play_ui(kind: String) -> void:
	var ss := get_node_or_null("/root/Soundscape")
	if ss != null:
		ss.ui(kind)


func _process(delta: float) -> void:
	if not _press.is_empty():
		if not wheel.visible and Marks.now() - float(_press.t) >= HOLD:
			wheel.size = size
			wheel.open_at(_to_local(_press.at), Marks.color(surface.player()), str(_press.target.get("subject", "")))
			_play_ui("open")
		if wheel.visible:
			var off := _to_local(_pointer()) - wheel.center
			if InputMap.has_action("pad_left"):
				var v := Input.get_vector("pad_left", "pad_right", "pad_up", "pad_down")
				if v.length() > 0.5:
					off = v * 100.0
			wheel.point_at(off)
	if _drawing:
		_sample_draw()
		_draw_flush += delta
		if _draw_flush >= Marks.CHUNK_SECONDS and _draw_pts.size() >= 2:
			_send_stroke(false)
	_expire()
	if not pings.is_empty() or not strokes.is_empty():
		queue_redraw()


func _expire() -> void:
	var now := Marks.now()
	for p in pings.duplicate():
		if now - float(p.t) > Marks.PING_LIFE:
			_free_node(p)
			pings.erase(p)
			queue_redraw()
	for k in strokes.keys():
		var last: Array = strokes[k].chunks.back() if not strokes[k].chunks.is_empty() else [[], -INF]
		if now - float(last[1]) > Marks.STROKE_LIFE:
			strokes.erase(k)
			queue_redraw()


# --- drawing -----------------------------------------------------------------------------------

## Viewport coordinates -> this control's.
func _to_local(v: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * v if is_inside_tree() else v


func _draw() -> void:
	if surface == null or not surface.active():
		return
	var now := Marks.now()
	for s in strokes.values():
		_draw_stroke(s, now)
	for p in pings:
		_draw_ping(p, now)


func _draw_stroke(s: Dictionary, now: float) -> void:
	var col := Marks.color(s.player)
	var prev: Variant = null
	for ch in s.chunks:
		var age := now - float(ch[1])
		var a := clampf((Marks.STROKE_LIFE - age) / 1.4, 0.0, 1.0)
		var line := PackedVector2Array()
		for pt in ch[0]:
			var sp: Variant = surface.point_screen(pt)
			if sp == null:
				_stroke_seg(line, col, a)
				line = PackedVector2Array()
				continue
			line.append(_to_local(sp))
		if line.size() > 0 and prev != null and line[0].distance_to(prev) < 80.0:
			line.insert(0, prev)
		_stroke_seg(line, col, a)
		prev = line[line.size() - 1] if line.size() > 0 else null


func _stroke_seg(line: PackedVector2Array, col: Color, a: float) -> void:
	if line.size() < 2 or a <= 0.0:
		return
	draw_polyline(line, Color(0, 0, 0, 0.35 * a), 8.0, true)
	draw_polyline(line, Color(col, 0.28 * a), 11.0, true)
	draw_polyline(line, Color(col.lightened(0.25), 0.95 * a), 3.5, true)


func _draw_ping(p: Dictionary, now: float) -> void:
	var m: Dictionary = p.m
	var age := now - float(p.t)
	var a := clampf((Marks.PING_LIFE - age) / 1.0, 0.0, 1.0)
	var col := Marks.color(m.player)
	var info := Marks.kind_info(m.kind)
	var danger: bool = m.kind == "danger"
	var sp: Variant = surface.ping_screen(m)
	var rect := Rect2(Vector2(EDGE, EDGE), size - Vector2(EDGE, EDGE) * 2)
	var local: Variant = _to_local(sp) if sp != null else null
	if local == null or not rect.has_point(local):
		_draw_edge_arrow(m, local, col, info, a, age)
		return
	var at: Vector2 = local
	var pop := clampf(age / 0.18, 0.0, 1.0)
	pop = 1.0 + 0.25 * sin(pop * PI) if pop < 1.0 else 1.0
	# A ping on something round (a route node) rings it and hangs its badge off to the side.
	var ring := float(surface.ping_ring(m))
	var r0 := ring if ring > 0.0 else 8.0
	# Ripples on arrival, then a slow breathing ring.
	for k in 2:
		var r_age := age - k * 0.25
		if r_age > 0.0 and r_age < 0.9:
			var t := r_age / 0.9
			draw_arc(at, r0 + 52.0 * t, 0, TAU, 48, Color(Styles.DANGER if danger else col, (1.0 - t) * 0.8 * a), 2.5, true)
	var breathe := 0.5 + 0.5 * sin(age * 4.0)
	var badge: Vector2
	var stem_from: Vector2
	if ring > 0.0:
		draw_arc(at, ring + 4.0 + 3.0 * breathe, 0, TAU, 64, Color(col, 0.9 * a), 3.0, true)
		var d := Vector2(0.7, -0.7)
		stem_from = at + d * (ring + 6.0)
		badge = at + d * (ring + 34.0 * pop)
	else:
		draw_arc(at, 10.0 + 3.0 * breathe, 0, TAU, 32, Color(col, 0.55 * a), 2.0, true)
		draw_circle(at, 4.0, Color(col, a))
		stem_from = at - Vector2(0, 6)
		badge = at - Vector2(0, 52) * pop
		badge.y = maxf(badge.y, BADGE_R + 8.0)   # near the top edge the stem shortens instead
	draw_line(stem_from, badge + (stem_from - badge).limit_length(BADGE_R), Color(col, 0.7 * a), 2.0, true)
	_badge(badge, col, info, danger, a, pop)
	# Label: who and what.
	var text := str(info.label).to_upper()
	var who := _player_name(m.player)
	var subject := str(p.label)
	_label(badge + Vector2(BADGE_R * pop + 8, 0), who, text, subject, col, a)


func _badge(c: Vector2, col: Color, info: Dictionary, danger: bool, a: float, scale := 1.0) -> void:
	var r := BADGE_R * scale
	W.Draw.glow(self, c, r * 2.1, Styles.DANGER if danger else col, 0.55 * a)
	draw_circle(c, r, Color(Styles.GROUND, 0.94 * a))
	draw_arc(c, r, 0, TAU, 40, Color(col, a), 2.5, true)
	var isz := r * 1.15
	Icons.draw(self, info.icon, Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz)),
		Color(Styles.DANGER_TEXT if danger else Styles.TEXT, a), 2.0)


func _label(left_mid: Vector2, who: String, what: String, subject: String, col: Color, a: float) -> void:
	var f_what := Styles.FONT_COND_BOLD
	var f_sub := Styles.FONT_BODY
	var fs := Styles.fs(12)
	var head := (who + "  " if who != "" else "") + what
	var w := f_what.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if subject != "":
		w = maxf(w, f_sub.get_string_size(subject, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var h := 22.0 if subject == "" else 38.0
	var r := Rect2(left_mid + Vector2(0, -h * 0.5), Vector2(w + 22.0, h))
	# Keep it on screen: flip to the left of the badge near the right edge.
	if r.end.x > size.x - 6:
		r.position.x = left_mid.x - r.size.x - BADGE_R * 2 - 16
	draw_rect(r, Color(Styles.BG_SOFT, 0.9 * a))
	draw_rect(Rect2(r.position, Vector2(3, r.size.y)), Color(col, a))
	var y := r.position.y + 15.0
	var x := r.position.x + 12.0
	if who != "":
		draw_string(f_what, Vector2(x, y), who, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.lightened(0.2), a))
		x += f_what.get_string_size(who + "  ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f_what, Vector2(x, y), what, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Styles.TEXT, a))
	if subject != "":
		draw_string(f_sub, Vector2(r.position.x + 12.0, y + 16.0), subject, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Styles.DIM, a))


## A ping out of view: a badge on the screen edge with a pointer towards it.
func _draw_edge_arrow(m: Dictionary, local: Variant, col: Color, info: Dictionary, a: float, age: float) -> void:
	var mid := size * 0.5
	var dir: Vector2
	if local == null:
		# Behind the camera: point the way the surface says, or straight down.
		var hint: Variant = surface.behind_dir(m)
		dir = hint if hint is Vector2 else Vector2.DOWN
	else:
		dir = (local as Vector2) - mid
	if dir.length() < 0.01:
		dir = Vector2.DOWN
	dir = dir.normalized()
	var half := mid - Vector2(EDGE, EDGE) - Vector2(BADGE_R, BADGE_R)
	var t := minf(half.x / maxf(absf(dir.x), 0.0001), half.y / maxf(absf(dir.y), 0.0001))
	var c := mid + dir * t
	var pulse := 0.5 + 0.5 * sin(age * 5.0)
	var tip := c + dir * (BADGE_R + 13.0 + 3.0 * pulse)
	var side := dir.orthogonal() * 8.0
	var base := c + dir * (BADGE_R + 3.0)
	draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), Color(col, a))
	_badge(c, col, info, m.kind == "danger", a)


func _player_name(p: int) -> String:
	if session == null:
		return ""
	var names: Dictionary = session.get("player_names") if session.get("player_names") is Dictionary else {}
	var local: Array = session.local_players() if session.has_method("local_players") else []
	# Only name the pinger when there's more than one player to tell apart.
	if names.size() <= 1 and local.size() <= 1:
		return ""
	return str(names.get(p, "P%d" % (p + 1)))
