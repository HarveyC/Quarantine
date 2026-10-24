extends TestCase
## Co-op pings and map drawing: checks and limits (coop/marks.gd), the host relay, the ping wheel,
## and the mark layer on the tactical and route maps.

const MAIN := preload("res://scenes/main.tscn")
const MarkLayer := preload("res://ui/marks/mark_layer.gd")
const PingWheel := preload("res://ui/marks/ping_wheel.gd")
const RouteSurface := preload("res://ui/marks/route_surface.gd")
const CameraRig := preload("res://view/camera_rig.gd")


func _host() -> NetSession:
	var n := NetSession.new()
	n.is_host = true
	n.my_player = 0
	n.in_match = true
	n.lobby = {1: {"name": "Host", "player": 0, "cid": "host"}, 2: {"name": "Ana", "player": 1, "cid": "a"}}
	return n


func test_sanitize_keeps_good_marks_and_drops_junk() -> void:
	var p := Marks.sanitize({"type": "ping", "player": 1, "where": "fight", "kind": "attack", "cell": Vector2i(3, 4), "unit": 7, "evil": "x"})
	assert_eq(p, {"type": "ping", "player": 1, "where": "fight", "kind": "attack", "cell": Vector2i(3, 4), "unit": 7}, "clean ping")
	assert_eq(Marks.sanitize({"type": "ping", "player": 0, "where": "fight", "kind": "nuke", "cell": Vector2i.ZERO}), {}, "unknown kind")
	assert_eq(Marks.sanitize({"type": "ping", "player": 0, "where": "moon", "kind": "look", "cell": Vector2i.ZERO}), {}, "unknown screen")
	assert_eq(Marks.sanitize({"type": "ping", "player": 0, "where": "route", "kind": "look"}), {}, "a ping needs somewhere to be")
	assert_eq(Marks.sanitize("not a dict"), {}, "not a dictionary")
	var at := Marks.sanitize({"type": "ping", "player": 0, "where": "route", "kind": "move", "at": Vector2(3, -1)})
	assert_eq(at.at, Vector2(1, 0), "route points are clamped to the board")
	var big := PackedVector3Array()
	for i in 100:
		big.append(Vector3(i, 0, 0))
	var s := Marks.sanitize({"type": "stroke", "player": 2, "where": "fight", "id": 5, "points": big, "end": true})
	assert_eq(s.points.size(), Marks.MAX_CHUNK, "chunks are capped")
	assert_true(s.end, "end flag kept")
	assert_eq(Marks.sanitize({"type": "stroke", "player": 2, "where": "route", "id": 5, "points": big}), {}, "route strokes are 2D")


func test_limiter_allows_a_burst_then_refills() -> void:
	var lim := Marks.Limiter.new()
	var burst := int(Marks.LIMITS.ping[0])
	for i in burst:
		assert_true(lim.allow(0, "ping", 10.0), "burst ping %d" % i)
	assert_true(not lim.allow(0, "ping", 10.0), "over the burst is dropped")
	assert_true(lim.allow(1, "ping", 10.0), "other players have their own bucket")
	assert_true(lim.allow(0, "ping", 10.0 + 1.0 / Marks.LIMITS.ping[1] + 0.01), "refills over time")


func test_quick_ping_reads_what_is_under_it() -> void:
	var s := make_state(["runner"])
	Vision.disable(s)
	var enemy: Unit = s.living(Types.Team.ENEMY)[0]
	var soldier: Unit = s.living(Types.Team.PLAYER)[0]
	assert_eq(Marks.fight_context(s, enemy.pos), "enemy", "enemy")
	assert_eq(Marks.quick_kind(Marks.fight_context(s, enemy.pos)), "attack", "quick ping on an enemy says attack")
	assert_eq(Marks.fight_context(s, soldier.pos), "ally", "soldier")
	assert_eq(Marks.quick_kind("hazard"), "danger", "hazard says danger")
	assert_eq(Marks.quick_kind(""), "look", "empty ground says look")
	var fog := make_state(["runner"])
	var hidden: Unit = fog.living(Types.Team.ENEMY)[0]
	hidden.status["hidden"] = true
	assert_eq(Marks.fight_context(fog, hidden.pos), "", "a hidden enemy isn't given away")


func test_host_relays_marks_as_the_sender_and_rate_limits() -> void:
	var n := _host()
	var got: Array = []
	n.marked.connect(func(m: Dictionary) -> void: got.append(m))
	var out := n.relay_mark(2, {"type": "ping", "player": 3, "where": "fight", "kind": "danger", "cell": Vector2i(1, 1)})
	assert_eq(out.player, 1, "stamped with the sender's own player, not the claimed one")
	assert_eq(got.size(), 1, "host shows a client's ping")
	assert_eq(n.relay_mark(9, {"type": "ping", "where": "fight", "kind": "look", "cell": Vector2i(1, 1)}), {}, "strangers are ignored")
	for i in 10:
		n.relay_mark(2, {"type": "ping", "where": "fight", "kind": "look", "cell": Vector2i(i, 1)})
	assert_eq(got.size(), int(Marks.LIMITS.ping[0]), "a flood is cut to the burst")
	# The host's own pings show at once and go through the same checks.
	assert_true(n.mark({"type": "ping", "where": "route", "kind": "move", "node": 4}), "host ping")
	assert_eq(got.back().player, 0, "the host's own player")
	n.in_match = false
	assert_true(not n.mark({"type": "ping", "where": "route", "kind": "move", "node": 4}), "nothing to ping outside a match")
	n.free()


func test_local_session_marks_go_straight_to_the_view() -> void:
	var s := LocalSession.new()
	var got: Array = []
	s.marked.connect(func(m: Dictionary) -> void: got.append(m))
	assert_true(s.mark({"type": "ping", "player": 1, "where": "fight", "kind": "loot", "cell": Vector2i(2, 2)}), "sent")
	assert_eq(got.size(), 1, "shown")
	assert_eq(got[0].player, 1, "hot-seat keeps the player who pinged")
	assert_true(not s.mark({"type": "ping", "player": 1, "where": "fight", "kind": "bogus", "cell": Vector2i(2, 2)}), "junk refused")
	s.free()


func test_wheel_slices_go_clockwise_from_the_top() -> void:
	assert_eq(PingWheel.slice_for(Vector2(0, -80)), 0, "up is the first slice (move)")
	assert_eq(PingWheel.slice_for(Vector2(80, -20)), 1, "right is attack")
	assert_eq(PingWheel.slice_for(Vector2(-80, -20)), 4, "left is loot")
	assert_eq(PingWheel.slice_for(Vector2(5, 5)), -1, "the hub cancels")
	assert_eq(Marks.WHEEL[1], "attack", "wheel order")


func test_fight_pings_and_strokes_show_and_fade() -> void:
	var tree: SceneTree = Engine.get_meta("test_tree")
	var v: MissionView = MAIN.instantiate()
	v.auto_start = false
	tree.root.add_child(v)
	v.start(MissionView.default_mission(1234))
	v.player.flush()
	var layer: MarkLayer = v.marks
	assert_true(layer != null and layer.surface != null, "the fight has a mark layer")
	var enemy: Unit = v.state.living(Types.Team.ENEMY)[0]
	var t := {"cell": enemy.pos, "unit": enemy.id, "context": "enemy"}
	assert_true(layer.ping(t), "quick ping sent")
	assert_eq(layer.pings.size(), 1, "and shown")
	assert_eq(layer.pings[0].m.kind, "attack", "quick ping on an enemy is an attack ping")
	assert_true(layer.pings[0].node is Node3D, "with a beacon in the world")
	for i in 3:
		v.session._mark_limit = Marks.Limiter.new()
		layer.ping({"cell": Vector2i(i, 0), "context": ""}, "move")
	assert_eq(layer.pings.size(), Marks.MAX_PINGS, "a player's oldest ping makes way")
	# A stroke in two chunks joins up into one line.
	layer._on_marked({"type": "stroke", "player": 1, "where": "fight", "id": 3, "points": PackedVector3Array([Vector3(1, 0, 1), Vector3(2, 0, 1)])})
	layer._on_marked({"type": "stroke", "player": 1, "where": "fight", "id": 3, "points": PackedVector3Array([Vector3(2, 0, 1), Vector3(3, 0, 2)]), "end": true})
	assert_eq(layer.strokes.size(), 1, "one stroke")
	assert_eq(layer.strokes["1:3"].chunks.size(), 2, "two chunks")
	layer._on_marked({"type": "ping", "player": 0, "where": "route", "kind": "look", "node": 1})
	assert_eq(layer.pings.size(), Marks.MAX_PINGS, "route marks don't show on the tactical map")
	# Everything fades out on its own.
	for p in layer.pings:
		p.t -= Marks.PING_LIFE + 1.0
	for s in layer.strokes.values():
		for ch in s.chunks:
			ch[1] -= Marks.STROKE_LIFE + 1.0
	layer._expire()
	assert_eq(layer.pings.size(), 0, "pings expire")
	assert_eq(layer.strokes.size(), 0, "strokes fade")
	v.queue_free()


func test_route_map_pings_snap_to_nodes() -> void:
	var tree: SceneTree = Engine.get_meta("test_tree")
	var run := RunRules.new_run(2, 5)
	RunRules.start_run(run)
	var s := LocalSession.new()
	s.save_enabled = false
	s.run = run
	var view := RunView.new()
	tree.root.add_child(view)
	view.setup(s)
	view.size = Vector2(1600, 900)
	view._map.size = Vector2(1200, 700)
	view._map._layout()
	var surf: RouteSurface = view.marks.surface
	var n: Dictionary = run.map[3]
	var at: Vector2 = view._map.get_global_rect().position + view._map.node_pos(n) + Vector2(4, 3)
	var t := surf.target(at)
	assert_eq(t.get("node"), n.id, "a ping near a node lands on it")
	assert_true(str(t.subject) != "", "and names it")
	assert_true(view.marks.ping(t), "sent")
	assert_eq(view.marks.pings[0].m.kind, "move", "a quick ping on a node says go here")
	var free_at: Vector2 = view._map.get_global_rect().position + Vector2(20, 20)
	assert_true(surf.target(free_at).has("at"), "open board pings a point")
	var p: Variant = surf.point(free_at)
	assert_true(p is Vector2 and p.x >= 0.0 and p.x <= 1.0, "stroke points are fractions of the board")
	assert_true((surf.point_screen(p) as Vector2).distance_to(free_at) < 0.5, "and map back to the same spot")
	view.queue_free()
	s.free()


func test_ping_and_draw_are_rebindable_with_pad_buttons() -> void:
	var names := GameSettings.ACTIONS.map(func(a: Array) -> String: return a[0])
	assert_true(names.has("ping") and names.has("draw"), "both listed in Settings > Controls")
	assert_eq(GameSettings.keys_for("ping"), [KEY_G], "G pings")
	assert_eq(GameSettings.keys_for("draw"), [KEY_V], "V draws")
	assert_eq(GameSettings.pad_label("ping"), "L3", "L3 pings")
	assert_eq(GameSettings.pad_label("draw"), "R3", "R3 draws")


func test_pad_zoom_steps_through_three_distances() -> void:
	var rig := CameraRig.new()
	rig._target_dist = 13.0
	rig.zoom_cycle()
	assert_eq(rig._target_dist, 8.0, "in")
	rig.zoom_cycle()
	assert_eq(rig._target_dist, 20.0, "from the closest back out")
	rig.zoom_cycle()
	assert_eq(rig._target_dist, 13.0, "then in again")
	rig.free()
