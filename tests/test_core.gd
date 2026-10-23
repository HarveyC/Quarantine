extends TestCase


func test_map_loads() -> void:
	var g := Grid.load_file("res://maps/mission_01.txt")
	assert_eq(g.width, 16, "width")
	assert_eq(g.height, 16, "height")
	assert_eq(g.player_spawns.size(), 4, "player spawns")
	assert_true(g.enemy_spawns.size() >= 4, "enemy spawns")


func test_pathfinding_avoids_walls_and_corners() -> void:
	var g := Grid.from_rows(PackedStringArray([
		"....",
		".#..",
		"....",
	]))
	assert_true(not g.reachable(Vector2i(0, 0), 5).has(Vector2i(1, 1)), "wall unreachable")
	# The wall blocks both diagonals around it, so the detour takes 4 steps.
	assert_eq(g.find_path(Vector2i(0, 0), Vector2i(2, 2)).size(), 4, "path length around wall")
	assert_true(g.find_path(Vector2i(0, 0), Vector2i(1, 1)).is_empty(), "no path into wall")


func test_move_spends_action_and_emits_event() -> void:
	var s := make_state()
	Rules.start_mission(s)
	var u := s.controllable_units(0)[0]
	var events: Array = []
	s.event.connect(func(ev): events.append(ev))
	var to := u.pos + Vector2i(0, -2)
	assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": u.id, "to": to}), "move accepted")
	assert_eq(u.pos, to, "position")
	assert_eq(u.actions_left, 1, "actions left")
	assert_eq(events.filter(func(e): return e.type == "move").size(), 1, "one move event")


func test_illegal_move_rejected() -> void:
	var s := make_state()
	Rules.start_mission(s)
	var u := s.controllable_units(0)[0]
	assert_true(not Rules.apply(s, {"type": Types.MOVE, "unit": u.id, "to": Vector2i(0, 0)}), "too far")
	assert_eq(u.actions_left, 2, "no action spent")


func test_all_ready_runs_enemy_phase_and_next_turn() -> void:
	var s := make_state()
	Rules.start_mission(s)
	Rules.set_ready(s, 0, true)
	assert_eq(s.turn, 1, "still turn 1 until everyone is ready")
	Rules.set_ready(s, 1, true)
	assert_true(s.turn == 2 or s.phase == Types.Phase.ENDED, "advanced to turn 2")


func test_unit_round_trips_through_dict() -> void:
	var u := UnitData.make("medic", Types.Team.PLAYER)
	u.pos = Vector2i(3, 4)
	u.status["lapsed"] = true
	var v := Unit.from_dict(u.to_dict())
	assert_eq(v.to_dict(), u.to_dict(), "round trip")


## Soak test: everyone just readies up for 30 turns. Must not hang or crash.
func test_soak_ready_only() -> void:
	var s := make_state(["runner", "runner", "spitter", "spitter"])
	Rules.start_mission(s)
	for i in 30:
		if s.phase == Types.Phase.ENDED:
			break
		for p in s.players:
			Rules.set_ready(s, p, true)
	assert_true(s.turn > 1, "turns advanced")
