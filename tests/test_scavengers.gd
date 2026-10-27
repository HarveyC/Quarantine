extends TestCase
## Harrow's looters: Cutter (snatches an item), Torchman (firebomb, fuel tank), Fence (loot).


func _open(w: int, h: int) -> PackedStringArray:
	var rows := PackedStringArray()
	for y in h:
		rows.append(".".repeat(w))
	return rows


func _soldier(s: GameState, kind: String, at: Vector2i) -> Unit:
	var u := UnitData.make(kind, Types.Team.PLAYER)
	u.owner_player = 0
	return s.add_unit(u, at)


func _enemy(s: GameState, spec: String, at: Vector2i) -> Unit:
	var u := s.add_unit(EnemyRoster.make(spec), at)
	u.status["alerted"] = true
	return u


func _events(s: GameState, type: String) -> Array:
	return s.log.filter(func(e): return e.type == type)


func _enemy_turn(s: GameState, u: Unit) -> void:
	s.phase = Types.Phase.ENEMY
	u.actions_left = Types.ACTIONS_PER_TURN
	for k in u.cooldowns.keys():
		u.cooldowns[k] = max(0, u.cooldowns[k] - 1)
	Encounter.on_unit_turn_start(s, u)
	EnemyAI.take_turn(s, u)
	u.actions_left = 0
	Encounter.on_unit_turn_end(s, u)


func test_scavengers_join_the_pools_and_have_cards() -> void:
	assert_true(EnemyRoster.pool(1).has("cutter") and EnemyRoster.pool(1).has("torchman"), "Cutter and Torchman from act 1")
	assert_true(not EnemyRoster.pool(1).has("fence") and EnemyRoster.pool(2).has("fence"), "Fence from act 2")
	for k in ["cutter", "torchman", "fence"]:
		assert_true(Glossary.has("enemy_" + k), "a hover card for " + k)
		assert_true(not EnemyRoster.infects(EnemyRoster.make(k)), k + " is human")


func test_a_cutter_hit_steals_the_best_item_and_a_kill_returns_it() -> void:
	var s := make_blank(_open(10, 10))
	var sol := _soldier(s, "trooper", Vector2i(2, 2))
	sol.status["gear"] = {"a": {"id": "tracer_rounds", "mk": 1}, "b": {"id": "filter_mask", "mk": 2}}
	var cut := _enemy(s, "cutter", Vector2i(3, 2))
	Scavengers.snatch(s, cut, sol)
	assert_eq(cut.status.loot.item, "filter_mask", "took the highest Mk item")
	assert_eq(GearFx.mk(sol, "filter_mask"), 0, "the soldier no longer has it")
	assert_eq(GearFx.mk(sol, "tracer_rounds"), 1, "the rest is untouched")
	assert_eq(_events(s, "stolen").size(), 1, "a stolen beat")
	Encounter.kill(s, cut)
	assert_eq(GearFx.mk(sol, "filter_mask"), 2, "killing the Cutter returns the item")


func test_an_escaped_cutter_keeps_the_item() -> void:
	var s := make_blank(_open(10, 10))
	var sol := _soldier(s, "trooper", Vector2i(5, 5))
	sol.status["gear"] = {"a": {"id": "filter_mask", "mk": 1}}
	var cut := _enemy(s, "cutter", Vector2i(1, 0))
	Scavengers.snatch(s, cut, sol)
	Scavengers.escape(s, cut)
	assert_true(not cut.is_alive(), "gone")
	assert_eq(GearFx.mk(sol, "filter_mask"), 0, "the item left with it")
	assert_eq(_events(s, "recovered").size(), 0, "nothing recovered")


func test_a_cutter_with_loot_runs_for_the_edge() -> void:
	var s := make_blank(_open(12, 12))
	var sol := _soldier(s, "trooper", Vector2i(6, 6))
	sol.status["gear"] = {"a": {"id": "filter_mask", "mk": 1}}
	var cut := _enemy(s, "cutter", Vector2i(5, 6))
	Scavengers.snatch(s, cut, sol)
	var before := Scavengers.edge_dist(s, cut.pos)
	_enemy_turn(s, cut)
	assert_true(Scavengers.edge_dist(s, cut.pos) < before, "heads for the edge")


func test_torchman_firebomb_burns_the_squad_not_the_infected() -> void:
	var s := make_blank(_open(12, 12))
	var sol := _soldier(s, "trooper", Vector2i(6, 6))
	var torch := _enemy(s, "torchman", Vector2i(3, 6))
	var runner := _enemy(s, "runner", Vector2i(7, 6))
	_enemy_turn(s, torch)
	var tel := (s.encounter.get("telegraphs", []) as Array).filter(func(t): return t.kind == "firebomb")
	assert_eq(tel.size(), 1, "a firebomb is down")
	var rhp := runner.hp
	s.turn += 1
	Encounter._resolve_telegraphs(s)
	assert_eq(sol.hp, sol.max_hp - EnemyRoster.FIREBOMB_DAMAGE, "the blast hurts the soldier")
	var fire := Hazards.cells_of(s, "fire")
	assert_true(fire.size() >= 1, "the ground burns")
	Hazards.on_enemy_phase_end(s)
	assert_eq(runner.hp, rhp, "the Infected walk through scavenger fire")


func test_torchman_tank_bursts_into_fire_on_death() -> void:
	var s := make_blank(_open(10, 10))
	var torch := _enemy(s, "torchman", Vector2i(5, 5))
	_soldier(s, "trooper", Vector2i(1, 1))
	Encounter.kill(s, torch)
	assert_true(Hazards.cells_of(s, "fire").size() >= 9, "a 3x3 of fire")


func test_fence_pays_supplies_when_killed_and_nothing_when_it_leaves() -> void:
	var s := make_blank(_open(10, 10))
	_soldier(s, "trooper", Vector2i(1, 1))
	var f1 := _enemy(s, "fence", Vector2i(8, 8))
	Encounter.kill(s, f1)
	assert_eq(int(s.encounter.get("loot", 0)), 1, "one loot sack")
	assert_eq(RunRules.fight_outcome(s, false).loot, 1, "the outcome carries it")
	var f2 := _enemy(s, "fence", Vector2i(9, 9))
	Scavengers.escape(s, f2)
	assert_eq(int(s.encounter.get("loot", 0)), 1, "an escaped Fence pays nothing")
