extends TestCase
## Fog of war (vision/). Maps are small open rooms so distances are easy to read.

const MAIN := preload("res://scenes/main.tscn")


## A grid with a raised strip (column 1), like the map workstream's Grid.level.
class RaisedGrid extends Grid:
	func level(c: Vector2i) -> int:
		return 1 if c.x == 1 else 0


func _room(w := 20, h := 5, wall_x := -1) -> PackedStringArray:
	var rows := PackedStringArray()
	for y in h:
		var r := ""
		for x in w:
			r += "#" if x == wall_x and y > 0 else "."
		rows.append(r)
	return rows


func _soldier(s: GameState, kind: String, at: Vector2i) -> Unit:
	var u := UnitData.make(kind, Types.Team.PLAYER)
	u.owner_player = 0
	s.add_unit(u, at)
	u.actions_left = 2
	return u


func _enemy(s: GameState, kind: String, at: Vector2i) -> Unit:
	return s.add_unit(EnemyRoster.make(kind), at)


func test_sight_radius_and_walls() -> void:
	var s := make_blank(_room(20, 5, 5))
	var t := _soldier(s, "trooper", Vector2i(0, 0))
	assert_eq(Vision.sight(s, t), Vision.SOLDIER_SIGHT, "trooper sight")
	assert_true(Vision.cell_visible(s, Types.Team.PLAYER, Vector2i(8, 0)), "8 tiles along the open top row")
	assert_true(not Vision.cell_visible(s, Types.Team.PLAYER, Vector2i(9, 0)), "9 tiles is past sight")
	assert_true(not Vision.cell_visible(s, Types.Team.PLAYER, Vector2i(7, 3)), "behind the wall")
	var m := _soldier(s, "marksman", Vector2i(0, 1))
	assert_eq(Vision.sight(s, m), 10, "marksman sees further")


func test_explored_remembers_cells_out_of_sight() -> void:
	var s := make_blank(_room(30, 3))
	var t := _soldier(s, "trooper", Vector2i(0, 1))
	_enemy(s, "runner", Vector2i(29, 1))
	Rules.start_mission(s)
	assert_true(Vision.is_explored(s, Vector2i(5, 1)), "seen at start")
	assert_true(not Vision.is_explored(s, Vector2i(20, 1)), "far end unexplored")
	assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": t.id, "to": Vector2i(5, 1)}), "move")
	assert_true(Vision.is_explored(s, Vector2i(13, 1)), "explored while walking")
	assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": t.id, "to": Vector2i(0, 1)}), "move back")
	assert_true(Vision.is_explored(s, Vector2i(13, 1)) and not Vision.cell_visible(s, Types.Team.PLAYER, Vector2i(13, 1)), "explored, not visible")
	var fog := Vision.fog_grid(s)
	assert_eq(fog[1 * 30 + 2], Vision.VISIBLE, "fog grid visible")
	assert_eq(fog[1 * 30 + 13], Vision.EXPLORED, "fog grid explored")
	assert_eq(fog[1 * 30 + 25], Vision.UNEXPLORED, "fog grid unexplored")


func test_squad_shares_vision_and_cant_shoot_into_fog() -> void:
	var s := make_blank(_room(20, 3))
	var t := _soldier(s, "trooper", Vector2i(0, 1))
	var e := _enemy(s, "runner", Vector2i(12, 1))
	Vision.refresh(s)
	assert_true(Combat.can_see(s, t.pos, e.pos), "line of sight within weapon range")
	assert_true(not Vision.sees_unit(s, Types.Team.PLAYER, e), "but out of sight radius")
	assert_true(not Combat.visible_targets(s, t).has(e), "not a target in fog")
	assert_true(Rules.validate(s, {"type": Types.SHOOT, "unit": t.id, "target": e.id}) != "", "shot rejected")
	_soldier(s, "medic", Vector2i(6, 1))
	assert_true(Vision.sees_unit(s, Types.Team.PLAYER, e), "a squadmate spots it")
	assert_true(Combat.visible_targets(s, t).has(e), "shared vision: the trooper can shoot it")


func test_attackers_give_their_position_away() -> void:
	var s := make_blank(_room(20, 3))
	var t := _soldier(s, "trooper", Vector2i(0, 1))
	var e := _enemy(s, "fallen", Vector2i(12, 1))
	Rules.start_mission(s)
	assert_true(not Vision.sees_unit(s, Types.Team.PLAYER, e), "unseen")
	s.phase = Types.Phase.ENEMY
	e.actions_left = 2
	assert_true(Rules.apply(s, {"type": Types.SHOOT, "unit": e.id, "target": t.id}), "enemy shoots from the dark")
	assert_true(Vision.sees_unit(s, Types.Team.PLAYER, e), "exposed by firing")
	s.turn += 1
	s.phase = Types.Phase.TEAM
	assert_true(Vision.sees_unit(s, Types.Team.PLAYER, e), "still exposed in the squad phase")
	assert_true(Combat.visible_targets(s, t).has(e), "and can be shot back")
	s.phase = Types.Phase.ENEMY
	assert_true(not Vision.sees_unit(s, Types.Team.PLAYER, e), "gone again after the squad phase")
	assert_eq(Vision.last_seen(s).get(e.id), Vector2i(12, 1), "last known position kept")


func test_overwatch_only_covers_own_sight() -> void:
	var s := make_blank(_room(20, 3))
	var w := _soldier(s, "trooper", Vector2i(0, 1))
	w.overwatch = true
	var far := _enemy(s, "runner", Vector2i(14, 1))
	assert_true(Combat.reactions_to_move(s, far, Vector2i(11, 1)).is_empty(), "11 tiles: outside sight, no reaction")
	assert_true(Combat.reactions_to_move(s, far, Vector2i(7, 1)).has(w), "7 tiles: reacts")
	w.status["gear"] = {"weapon": {"id": "rangefinder", "mk": 1}}
	assert_true(Combat.reactions_to_move(s, far, Vector2i(10, 1)).has(w), "Rangefinder +2 overwatch range")
	far.status["hidden"] = true
	assert_true(Combat.reactions_to_move(s, far, Vector2i(5, 1)).is_empty(), "hidden movers don't trigger it")


func test_hidden_enemies_still_act() -> void:
	var s := make_blank(_room(30, 3))
	_soldier(s, "trooper", Vector2i(0, 1))
	var e := _enemy(s, "runner", Vector2i(26, 1))
	e.status["alerted"] = true
	Rules.start_mission(s)
	var before := e.pos
	Rules.set_ready(s, 0, true)
	assert_true(e.pos != before, "the unseen runner moved in the enemy phase")


func test_intents_only_for_seen_enemies() -> void:
	var s := make_blank(_room(30, 3))
	_soldier(s, "trooper", Vector2i(0, 1))
	var near := _enemy(s, "runner", Vector2i(5, 1))
	var far := _enemy(s, "runner", Vector2i(25, 1))
	near.status["alerted"] = true
	far.status["alerted"] = true
	Rules.start_mission(s)
	var ids := EnemyIntent.intents(s).map(func(it): return it.unit)
	assert_true(ids.has(near.id), "seen enemy shows intent")
	assert_true(not ids.has(far.id), "unseen enemy hides intent")


func test_high_ground_adds_sight() -> void:
	var s := GameState.new()
	s.grid = RaisedGrid.new()
	var g := Grid.from_rows(_room(20, 3))
	s.grid.width = g.width
	s.grid.height = g.height
	s.grid.tiles = g.tiles
	s.players.assign([0])
	var low := _soldier(s, "trooper", Vector2i(0, 1))
	var high := _soldier(s, "trooper", Vector2i(1, 1))
	assert_eq(Vision.sight(s, low), Vision.SOLDIER_SIGHT, "ground level")
	assert_eq(Vision.sight(s, high), Vision.SOLDIER_SIGHT + Vision.HIGH_GROUND_BONUS, "raised tile")


func test_smart_link_shoots_marked_enemy_an_ally_sees() -> void:
	var rows := PackedStringArray([
		"..........",
		".....#....",
		".....#....",
		"..........",
	])
	var s := make_blank(rows)
	var a := _soldier(s, "trooper", Vector2i(3, 2))
	_soldier(s, "medic", Vector2i(7, 0))
	var e := _enemy(s, "runner", Vector2i(7, 2))
	Vision.refresh(s)
	assert_true(not Combat.can_see(s, a.pos, e.pos), "wall between")
	assert_true(Vision.sees_unit(s, Types.Team.PLAYER, e), "the medic sees it")
	a.status["gear"] = {"weapon": {"id": "smart_link", "mk": 2}}
	assert_true(not Combat.shot_targets(s, a).has(e), "not Marked yet")
	e.status["tagged"] = Combat.phase_index(s) + 2
	assert_true(Combat.shot_targets(s, a).has(e), "Marked: Smart-link shot")
	var odds := Combat.hit_chance(s, a, e)
	assert_true(odds.los and odds.hit > 0, "it has odds")
	assert_true(odds.breakdown.any(func(t): return t[0] == "Smart-link"), "Mk II +10 aim")
	assert_true(Rules.validate(s, {"type": Types.SHOOT, "unit": a.id, "target": e.id}) == "", "shot allowed")
	assert_true(not GearFx.is_pending("smart_link"), "in reward draws now")


func test_motion_tracker_blips_enemies_moving_nearby() -> void:
	var s := make_blank(_room(30, 3, 4))
	var t := _soldier(s, "trooper", Vector2i(0, 0))
	t.status["gear"] = {"utility": {"id": "motion_tracker", "mk": 1}}
	var e := _enemy(s, "runner", Vector2i(7, 2))
	Rules.start_mission(s)
	assert_true(not Vision.sees_unit(s, Types.Team.PLAYER, e), "behind the wall")
	s.phase = Types.Phase.ENEMY
	e.actions_left = 2
	assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": e.id, "to": Vector2i(6, 2)}), "enemy moves")
	assert_eq(Vision.blips(s).get(e.id), Vector2i(6, 2), "blip at its new cell")
	s.turn += 1
	s.phase = Types.Phase.TEAM
	assert_true(Vision.blips(s).has(e.id), "still shown in the squad phase")
	s.phase = Types.Phase.ENEMY
	Vision.refresh(s)
	assert_true(not Vision.blips(s).has(e.id), "fades after it")


func test_recon_drone_reveals_an_area() -> void:
	var s := make_blank(_room(30, 3, 4))
	var t := _soldier(s, "trooper", Vector2i(0, 0))
	t.status["pockets"] = [{"id": "recon_drone", "charges": 1}]
	t.status["gear"] = {}
	var e := _enemy(s, "runner", Vector2i(9, 2))
	Rules.start_mission(s)
	assert_true(not Vision.sees_unit(s, Types.Team.PLAYER, e), "unseen")
	var act := {"type": Types.ABILITY, "unit": t.id, "ability": "item:recon_drone", "cell": Vector2i(8, 2)}
	assert_eq(Rules.validate(s, act), "", "drone launch is legal without line of sight")
	assert_true(Rules.apply(s, act), "launched")
	assert_true(Vision.sees_unit(s, Types.Team.PLAYER, e), "revealed from above")
	assert_true(Vision.cell_visible(s, Types.Team.PLAYER, Vector2i(13, 2)), "6-tile radius")
	assert_true(not Vision.cell_visible(s, Types.Team.PLAYER, Vector2i(16, 2)), "not past it")


func test_spore_sense_senses_infected_through_walls() -> void:
	var s := make_blank(_room(20, 5, 4))
	var t := _soldier(s, "trooper", Vector2i(2, 3))
	var e := _enemy(s, "runner", Vector2i(6, 3))
	var f := _enemy(s, "fallen", Vector2i(6, 4))
	Vision.refresh(s)
	assert_true(not Vision.sees_unit(s, Types.Team.PLAYER, e), "behind the wall")
	assert_true(Vision.sensed(s).is_empty(), "no sense without the mutation")
	t.status["sense_radius"] = Vision.SENSE_RADIUS
	assert_true(Vision.sensed(s).has(e.id), "infected runner sensed")
	assert_true(not Vision.sensed(s).has(f.id), "the Fallen aren't infected")
	assert_true(not Combat.visible_targets(s, t).has(e), "sensed is not a target")
	e.status["alerted"] = true
	assert_true(EnemyIntent.intents(s).any(func(it): return it.unit == e.id), "its intent shows")


func test_lurker_ripple_only_in_sight() -> void:
	var s := make_blank(_room(30, 3))
	_soldier(s, "trooper", Vector2i(0, 1))
	var near := _enemy(s, "lurker", Vector2i(6, 1))
	var far := _enemy(s, "lurker", Vector2i(25, 1))
	assert_true(near.status.get("hidden", false), "lurkers start hidden")
	Vision.refresh(s)
	var r := EnemyIntent.ripples(s)
	assert_true(r.has(near.pos), "ripple in sight")
	assert_true(not r.has(far.pos), "nothing out in the dark")
	assert_true(not Vision.sees_unit(s, Types.Team.PLAYER, near), "the Lurker itself stays unseen")


func test_vision_is_saved_and_checksummed() -> void:
	var s := make_state(["runner", "spitter"])
	Rules.start_mission(s)
	var u := s.controllable_units(0)[0]
	Rules.apply(s, {"type": Types.MOVE, "unit": u.id, "to": Rules.move_range(s, u).keys().back()})
	var copy := GameState.from_dict(str_to_var(var_to_str(s.to_dict())))
	assert_eq(copy.checksum(), s.checksum(), "same checksum after a round trip")
	assert_eq(Vision.fog_grid(copy), Vision.fog_grid(s), "same fog")
	var before := s.checksum()
	s.vision["explored"][0] = 1 - s.vision["explored"][0]
	assert_true(s.checksum() != before, "explored cells are in the checksum")


func test_view_hides_unseen_enemies_and_draws_fog() -> void:
	var s := make_state(["runner", "runner", "spitter"])
	var v: MissionView = MAIN.instantiate()
	v.start(s)
	v.player.flush()
	for e in s.living(Types.Team.ENEMY):
		var seen := Vision.sees_unit(s, Types.Team.PLAYER, e)
		assert_eq(v.view_for(e.id).visible, seen, "enemy %d drawn only when seen" % e.id)
	assert_eq(v.fog.shown(), Vision.fog_grid(s), "fog texture matches the rules")
	var hidden := s.living(Types.Team.ENEMY).filter(func(e): return not Vision.sees_unit(s, Types.Team.PLAYER, e))
	if not hidden.is_empty():
		assert_true(v.unit_view_at(hidden[0].pos) == null, "can't hover a hidden enemy")
		var ev := MissionView.FogOverlay.annotate(s, {"type": "overwatch", "unit": hidden[0].id})
		assert_true(ev.get("_hidden", false), "its events play silently")
	v.free()


func test_raised_tiles_block_ground_sight() -> void:
	var s := make_blank(_room(12, 3))
	for y in 3:
		s.grid.set_level(Vector2i(5, y), 1)
	assert_true(not Combat.can_see(s, Vector2i(2, 1), Vector2i(8, 1)), "a raised block hides ground from ground")
	assert_true(Combat.can_see(s, Vector2i(5, 1), Vector2i(9, 1)), "from the roof you see down")
	assert_true(Combat.can_see(s, Vector2i(2, 1), Vector2i(5, 1)), "a unit on the roof edge is seen")
	var flyer := _enemy(s, "runner", Vector2i(8, 1))
	flyer.status["flying"] = true
	assert_true(Combat.can_see(s, Vector2i(2, 1), Vector2i(8, 1)), "a flyer is seen over the roofs")


func test_spore_sense_mutation_is_live() -> void:
	var s := make_blank(_room(20, 5, 4))
	var t := _soldier(s, "trooper", Vector2i(2, 3))
	var e := _enemy(s, "runner", Vector2i(6, 3))
	t.status["mutations"] = {"exposed": "spore_sense"}
	t.infection = 30
	assert_eq(Vision.sense_radius(t), Vision.SENSE_RADIUS, "awake at Exposed")
	assert_true(Vision.sensed(s).has(e.id), "senses through the wall")
	t.infection = 10
	assert_eq(Vision.sense_radius(t), 0, "dormant below its tier")
