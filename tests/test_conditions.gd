extends TestCase
## Fight conditions: which fights get one, the terrain they lay, sight changes and telegraphed events.

const ROWS := ["............", "............", "............", "............", "............", "............"]


func _fight(cond: String) -> GameState:
	var s := make_blank(PackedStringArray(ROWS))
	s.grid.condition = cond
	var sol := s.add_unit(UnitData.make("trooper", Types.Team.PLAYER), Vector2i(2, 2))
	sol.owner_player = 0
	s.turn = 1
	s.phase = Types.Phase.TEAM
	s.ready = {0: false}
	return s


func test_for_fight_is_a_pure_function_of_the_seed() -> void:
	for seed in 40:
		assert_eq(Conditions.for_fight(seed, 2, "extract", "skirmish"), Conditions.for_fight(seed, 2, "extract", "skirmish"), "same seed, same condition")
		assert_eq(Conditions.for_fight(seed, 3, "boss", "boss"), "", "bosses never get one")
	var kinds := {}
	for seed in 200:
		kinds[Conditions.for_fight(seed, 3, "extract", "skirmish")] = true
	assert_eq(kinds.size(), Conditions.KINDS.size() + 1, "act 3 uses every condition and sometimes none")
	for seed in 200:
		assert_true(Conditions.for_fight(seed, 1, "extract", "skirmish") in ["", "fog", "flooded", "shelling"], "act 1 keeps to the gentle ones")


func test_flooded_and_rails_lay_terrain_on_open_ground() -> void:
	for biome in ["wall", "port", "bore"]:
		var wet := MapGen.generate({"biome": biome, "objective": "extract", "seed": 5, "condition": "flooded", "act": 1})
		assert_true(wet.water.size() >= 12, "%s has pools" % biome)
		for c in wet.water:
			assert_true(wet.is_walkable(c) and wet.level(c) == 0, "water only on ground")
			for k in wet.markers:
				assert_true(not wet.markers[k].has(c), "water leaves %s alone" % k)
		var live := MapGen.generate({"biome": biome, "objective": "extract", "seed": 5, "condition": "live_rails", "act": 2})
		assert_true(live.rails.size() >= 6, "%s has rails" % biome)
	var dry := MapGen.generate({"biome": "wall", "objective": "extract", "seed": 5})
	assert_eq(dry.condition, "", "no condition unless asked")
	assert_true(dry.water.is_empty() and dry.rails.is_empty(), "dry map")


func test_wading_costs_an_extra_step_and_fire_cannot_burn_on_water() -> void:
	var s := _fight("flooded")
	s.grid.water[Vector2i(3, 2)] = true
	assert_eq(s.grid.step_cost(Vector2i(2, 2), Vector2i(1, 0)), 2, "stepping into water costs 2")
	assert_eq(s.grid.step_cost(Vector2i(2, 2), Vector2i(0, 1)), 1, "dry step costs 1")
	Hazards.add(s, [Vector2i(3, 2), Vector2i(4, 2)], "fire", 2)
	assert_eq(Hazards.at(s, Vector2i(3, 2)), {}, "no fire on water")
	assert_eq(Hazards.at(s, Vector2i(4, 2)).kind, "fire", "fire on dry ground")


func test_fog_and_blackout_cut_sight() -> void:
	var s := _fight("fog")
	var sol := s.living(Types.Team.PLAYER)[0]
	assert_eq(Vision.sight(s, sol), Vision.SOLDIER_SIGHT - 3, "fog cuts the squad's sight")
	var foe := s.add_unit(UnitData.make("runner", Types.Team.ENEMY), Vector2i(9, 4))
	assert_eq(Vision.sight(s, foe), Vision.ENEMY_SIGHT - 3, "and the Infected's")
	s.grid.condition = "blackout"
	assert_eq(Vision.sight(s, sol), Vision.SOLDIER_SIGHT - 3, "blackout blinds the squad")
	assert_eq(Vision.sight(s, foe), Vision.ENEMY_SIGHT - 1, "the Infected know the ground")
	s.grid.condition = ""
	assert_eq(Vision.sight(s, sol), Vision.SOLDIER_SIGHT, "no condition, no change")


func test_live_rails_become_hazards_that_hurt() -> void:
	var s := _fight("live_rails")
	for x in range(4, 10):
		s.grid.rails[Vector2i(x, 2)] = true
	Conditions.setup(s, 2)
	assert_eq(Hazards.at(s, Vector2i(5, 2)).kind, "live", "rail cells are hazards")
	var sol := s.living(Types.Team.PLAYER)[0]
	var hp := sol.hp
	Hazards.on_move(s, sol, [Vector2i(4, 2), Vector2i(5, 2)] as Array[Vector2i])
	assert_eq(hp - sol.hp, Hazards.KINDS.live.damage, "one hit for crossing")


func test_shelling_is_called_a_round_ahead_then_lands() -> void:
	var s := _fight("shelling")
	Conditions.setup(s, 1)
	s.turn = 2
	Conditions.on_enemy_phase_start(s)
	var tels: Array = s.encounter.telegraphs
	assert_eq(tels.size(), 1, "announced on round 2 for round 3")
	assert_eq(int(tels[0].turn), 3, "lands on round 3")
	assert_true((tels[0].cells as Array).has(Vector2i(2, 2)), "on the lone soldier")
	var sol := s.living(Types.Team.PLAYER)[0]
	var hp := sol.hp
	s.turn = 3
	Encounter.on_enemy_phase_start(s)
	assert_eq(hp - sol.hp, Conditions.SHELL_DAMAGE, "a soldier who stayed takes the hit")


func test_convoy_arrives_from_the_reinforcement_cells() -> void:
	var s := _fight("convoy")
	s.grid.markers["reinforce"] = [Vector2i(11, 0)]
	Conditions.setup(s, 2)
	s.turn = 3
	Conditions.on_enemy_phase_start(s)
	assert_eq(s.encounter.incoming.size(), 1, "convoy announced on round 3")
	assert_true(s.log.any(func(e): return e.type == "reinforcements_incoming"), "the view hears about it")
	var before := s.living(Types.Team.ENEMY).size()
	s.turn = 4
	Encounter.on_enemy_phase_start(s)
	assert_eq(s.living(Types.Team.ENEMY).size(), before + Conditions.CONVOY[2].size(), "they step off")


func test_snapshots_keep_the_condition() -> void:
	var cfg := MatchConfig.make(2, 9)
	cfg.map_spec = {"biome": "wall", "objective": "skirmish", "seed": 9, "condition": "live_rails", "act": 2}
	var s := MatchConfig.build(cfg)
	var back := GameState.from_dict(s.to_dict())
	assert_eq(back.grid.condition, "live_rails", "condition survives")
	assert_eq(back.grid.rails.size(), s.grid.rails.size(), "rails survive")
	assert_eq(back.checksum(), s.checksum(), "peers agree")
