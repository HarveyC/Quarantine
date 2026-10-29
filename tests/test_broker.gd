extends TestCase
## The Act 1 boss "the Broker": the haul, the shaken-loose items and the burn, and its place in the boss pool.


func _open(w: int, h: int) -> PackedStringArray:
	var rows := PackedStringArray()
	for y in h:
		rows.append(".".repeat(w))
	return rows


func _fight(squad: int) -> Array:
	var s := make_blank(_open(20, 20))
	var soldiers: Array = []
	for i in squad:
		var u := UnitData.make("trooper", Types.Team.PLAYER)
		u.owner_player = 0
		u.status["gear"] = {"a": {"id": "tracer_rounds", "mk": 1}, "b": {"id": "filter_mask", "mk": 2}}
		soldiers.append(s.add_unit(u, Vector2i(3 + i, 17)))
	var b := s.add_unit(EnemyRoster.make("broker"), Vector2i(10, 4))
	s.encounter = {"squad": squad, "boss": "broker"}
	Broker.setup(s, b, squad)
	return [s, b, soldiers]


func test_the_broker_is_in_act_1s_pool_with_everything_a_boss_needs() -> void:
	assert_true(EnemyRoster.BOSS_POOL[1].has("broker") and EnemyRoster.BOSSES.has("broker"), "pooled")
	assert_true(FightBuilder.BOSS_HEALTH.has("broker") and StoryData.BOSS_SCENES.has("broker"), "health and intro scene")
	for p in [2, 3]:
		assert_true(StoryData.CAPTION_BARKS.has("broker_%d" % p), "a radio line for phase %d" % p)
	assert_true(Glossary.has("enemy_broker") and Glossary.has("haul"), "hover cards")
	var built := FightBuilder.build({"act": 1, "node": "boss", "objective": "boss", "seed": 3, "squad": 2, "boss": "broker"})
	assert_eq(built.encounter.boss, "broker")
	assert_true(built.enemies.has("cutter"), "his Cutters come with him")


func test_the_arena_for_the_broker_has_an_exit_gate() -> void:
	var seen_gate := false
	for seed in [1, 2, 3, 4]:
		var g := MapGen.generate({"biome": "wall", "objective": "boss", "seed": seed, "boss": "broker"})
		assert_true(MapGen.last_plot == "arena", "an arena, not the fallback")
		var gate: Array = g.markers.exit
		assert_eq(gate.size(), 1, "one exit gate")
		var c: Vector2i = gate[0]
		assert_true(g.is_walkable(c) and (c.x == 0 or c.y == 0 or c.x == g.width - 1 or c.y == g.height - 1), "a walkable cell on the edge")
		seen_gate = true
	assert_true(seen_gate)
	var brood := MapGen.generate({"biome": "wall", "objective": "boss", "seed": 1, "boss": "brood_mother"})
	assert_true(brood.markers.exit.is_empty(), "the Brood Mother's arena has no gate")


func test_phase_two_takes_one_item_per_soldier_and_marks_the_exit() -> void:
	var f := _fight(2)
	var s: GameState = f[0]
	var b: Unit = f[1]
	Rules.deal_damage(s, b, 999, f[2][0])
	assert_eq(int(b.status.boss_phase), 2, "stopped at the gate")
	assert_eq(b.status.hoard.size(), 2, "one item each")
	for sol in f[2]:
		assert_eq(GearFx.mk(sol, "filter_mask"), 0, "the best item is disabled")
		assert_eq(GearFx.mk(sol, "tracer_rounds"), 1, "the other still works")
	assert_true(s.log.any(func(e): return e.type == "exit_marked"), "the gate is called out")


func test_a_hit_shakes_one_item_loose_and_the_gate_burns_the_rest() -> void:
	var f := _fight(2)
	var s: GameState = f[0]
	var b: Unit = f[1]
	Rules.deal_damage(s, b, 999, f[2][0])
	Rules.deal_damage(s, b, 1, f[2][0])
	assert_eq(b.status.hoard.size(), 1, "a hit knocks one loose")
	assert_eq(GearFx.mk(f[2][0], "filter_mask"), 2, "back with its owner")
	b.pos = b.status.exit
	b.actions_left = 2
	Broker.take_turn(s, b)
	assert_eq(int(b.status.boss_phase), 3, "at the gate he burns the rest")
	assert_true(b.status.hoard.is_empty())
	assert_eq(GearFx.mk(f[2][1], "filter_mask"), 0, "the second owner stays without it")
	assert_eq(f[2][1].status.burned, ["filter_mask"], "recorded as burned")
	assert_true(s.log.any(func(e): return e.type == "burned"), "and shown")


func test_the_haul_still_runs_for_a_lone_soldier_and_burns_at_a_third() -> void:
	var f := _fight(1)
	var s: GameState = f[0]
	var b: Unit = f[1]
	Rules.deal_damage(s, b, 999, f[2][0])
	assert_eq(b.status.hoard.size(), 1)
	var gates := Broker.gates(b)
	b.hp = gates[1] + 1
	Rules.deal_damage(s, b, 5, f[2][0])
	assert_eq(int(b.status.boss_phase), 3, "cornered at a third health")
	assert_eq(b.hp, gates[1], "no hit skips the gate")
	assert_eq(GearFx.mk(f[2][0], "filter_mask"), 0, "the lone soldier plays on without it")


func test_in_phase_two_he_runs_for_the_gate() -> void:
	var f := _fight(2)
	var s: GameState = f[0]
	var b: Unit = f[1]
	Rules.deal_damage(s, b, 999, f[2][0])
	var before := Vector2(b.pos).distance_to(Vector2(b.status.exit))
	s.phase = Types.Phase.ENEMY
	b.actions_left = 2
	Broker.take_turn(s, b)
	assert_true(Vector2(b.pos).distance_to(Vector2(b.status.exit)) < before, "closer to the gate")
