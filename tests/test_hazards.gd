extends TestCase
## Tile hazards: placement rules, hits on moving and standing, ageing, sparing, snapshots.

const ROWS := ["..........", "..........", "..........", "......#..."]


func _setup() -> Dictionary:
	var s := make_blank(PackedStringArray(ROWS))
	var sol := s.add_unit(UnitData.make("trooper", Types.Team.PLAYER), Vector2i(1, 1))
	sol.owner_player = 0
	var foe := s.add_unit(UnitData.make("runner", Types.Team.ENEMY), Vector2i(9, 0))
	s.turn = 1
	s.phase = Types.Phase.TEAM
	s.ready = {0: false}
	sol.actions_left = Types.ACTIONS_PER_TURN
	return {"s": s, "sol": sol, "foe": foe}


func _events(s: GameState, type: String) -> Array:
	return s.log.filter(func(e): return e.type == type)


func test_add_skips_walls_and_emits_event() -> void:
	var t := _setup()
	var s: GameState = t.s
	var changed := Hazards.add(s, [Vector2i(5, 3), Vector2i(6, 3)], "fire", 2)
	assert_eq(changed, [Vector2i(5, 3)] as Array[Vector2i], "wall cell skipped")
	assert_eq(Hazards.at(s, Vector2i(5, 3)).kind, "fire", "fire placed")
	assert_eq(_events(s, "hazard").size(), 1, "one hazard event")


func test_fire_burns_away_spores_but_spores_do_not_smother_fire() -> void:
	var t := _setup()
	var s: GameState = t.s
	Hazards.add(s, [Vector2i(3, 3)], "spore", Hazards.PERMANENT)
	Hazards.add(s, [Vector2i(3, 3)], "fire", 1)
	assert_eq(Hazards.at(s, Vector2i(3, 3)).kind, "fire", "fire replaces spores")
	Hazards.add(s, [Vector2i(3, 3)], "spore", 3)
	assert_eq(Hazards.at(s, Vector2i(3, 3)).kind, "fire", "spores can't replace fire")


func test_moving_through_fire_hits_once() -> void:
	var t := _setup()
	var s: GameState = t.s
	var sol: Unit = t.sol
	Hazards.add(s, [Vector2i(2, 1), Vector2i(3, 1)], "fire", 2)
	var hp := sol.hp
	assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": sol.id, "to": Vector2i(4, 1)}), "move")
	assert_eq(sol.hp, hp - Hazards.KINDS.fire.damage, "one hit for crossing two fire cells")
	assert_eq(_events(s, "hazard_tick").size(), 1, "one tick event")


func test_standing_in_spores_infects_soldiers_at_end_of_turn_not_enemies() -> void:
	var t := _setup()
	var s: GameState = t.s
	var sol: Unit = t.sol
	var foe: Unit = t.foe
	Hazards.add(s, [sol.pos, foe.pos], "spore", Hazards.PERMANENT)
	Hazards.on_team_phase_end(s)
	assert_eq(sol.infection, Hazards.KINDS.spore.infection, "soldier infected")
	var fhp := foe.hp
	Hazards.on_enemy_phase_end(s)
	assert_eq(foe.hp, fhp, "infected ignore spores")
	assert_eq(Hazards.avoid_cost(s, foe, foe.pos), 0.0, "enemies don't avoid spores")
	assert_true(Hazards.avoid_cost(s, sol, sol.pos) > 0.0, "soldiers do")


func test_soldier_laid_spores_cut_enemies() -> void:
	var t := _setup()
	var s: GameState = t.s
	var sol: Unit = t.sol
	var foe: Unit = t.foe
	Hazards.add(s, [foe.pos], "spore", 3, sol.id)
	var fhp := foe.hp
	Hazards.on_enemy_phase_end(s)
	assert_eq(foe.hp, fhp - Hazards.SOLDIER_SPORE_DAMAGE, "soldier spores cut the Infected")
	assert_true(Hazards.avoid_cost(s, foe, foe.pos) > 0.0, "and the Infected avoid them")


func test_spare_team_fire_spares_the_squad() -> void:
	var t := _setup()
	var s: GameState = t.s
	var sol: Unit = t.sol
	var foe: Unit = t.foe
	Hazards.add(s, [sol.pos, foe.pos], "fire", 2, sol.id, Types.Team.PLAYER)
	var hp := sol.hp
	var fhp := foe.hp
	Hazards.on_team_phase_end(s)
	Hazards.on_enemy_phase_end(s)
	assert_eq(sol.hp, hp, "caster's team unharmed")
	assert_eq(foe.hp, fhp - Hazards.KINDS.fire.damage, "enemy burned")


func test_hazards_age_and_expire() -> void:
	var t := _setup()
	var s: GameState = t.s
	Hazards.add(s, [Vector2i(4, 0)], "acid", 2)
	Hazards.on_enemy_phase_end(s)
	assert_eq(Hazards.at(s, Vector2i(4, 0)).turns, 1, "one round left")
	Hazards.on_enemy_phase_end(s)
	assert_true(Hazards.at(s, Vector2i(4, 0)).is_empty(), "expired")
	assert_eq(_events(s, "hazard_end").size(), 1, "end event")


func test_full_round_through_rules() -> void:
	var t := _setup()
	var s: GameState = t.s
	var sol: Unit = t.sol
	Hazards.add(s, [sol.pos], "fire", 1)
	Rules.set_ready(s, 0, true)
	var ticks := _events(s, "hazard_tick").filter(func(e): return e.unit == sol.id)
	assert_eq(ticks.size(), 1, "burned once, at the end of the squad's turn")
	assert_true(s.log.find(ticks[0]) < s.log.find(_events(s, "enemy_phase")[0]), "before the enemies act")
	assert_eq(s.turn, 2, "next turn started")
	assert_true(Hazards.at(s, sol.pos).is_empty() or sol.pos != Vector2i(1, 1), "1-round fire is out")


func test_hazards_survive_snapshot_and_checksum() -> void:
	var t := _setup()
	var s: GameState = t.s
	Hazards.add(s, [Vector2i(2, 2)], "spore", 3)
	var back := GameState.from_dict(s.to_dict())
	assert_eq(back.hazards, s.hazards, "hazards restored")
	assert_eq(back.checksum(), s.checksum(), "same checksum")
	var before := s.checksum()
	Hazards.add(s, [Vector2i(3, 2)], "fire", 1)
	assert_true(s.checksum() != before, "hazards are part of the checksum")
