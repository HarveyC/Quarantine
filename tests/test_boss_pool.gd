extends TestCase
## Boss pools per act: the boss node's seed rolls the boss, and everything downstream follows it.


func test_every_pool_entry_is_a_boss_with_a_health_table_and_a_scene() -> void:
	for act in [1, 2, 3]:
		assert_true(not EnemyRoster.BOSS_POOL[act].is_empty(), "act %d has a pool" % act)
		for kind in EnemyRoster.BOSS_POOL[act]:
			assert_true(EnemyRoster.BOSSES.has(kind), "%s is a boss kind" % kind)
			assert_true(FightBuilder.BOSS_HEALTH.has(kind), "%s has a health table" % kind)
			assert_true(StoryData.BOSS_SCENES.has(kind), "%s has an intro scene" % kind)


func test_the_seed_rolls_a_boss_from_the_pool_and_repeats() -> void:
	for act in [1, 2, 3]:
		for seed in [1, 2, 99, 123456]:
			var boss := EnemyRoster.boss_for(act, seed)
			assert_true(EnemyRoster.BOSS_POOL[act].has(boss), "rolled from the pool")
			assert_eq(EnemyRoster.boss_for(act, seed), boss, "same seed, same boss")


func test_the_run_knows_its_act_boss_and_the_fight_uses_it() -> void:
	var run := RunState.new()
	run.act = 2
	run.map = RunMap.generate(run.rng, 2)
	var boss := run.act_boss()
	assert_true(EnemyRoster.BOSS_POOL[2].has(boss))
	var built := FightBuilder.build({"act": 2, "node": "boss", "objective": "boss", "seed": 5, "squad": 2, "boss": boss})
	assert_eq(built.encounter.boss, boss)
	var pv := FightBuilder.preview({"act": 2, "node": "boss", "seed": 1, "boss": boss})
	assert_eq(pv.boss, boss)
	assert_eq(pv.title, UnitData.ENEMIES[boss].name)


func test_an_unknown_boss_in_the_spec_falls_back_to_the_roll() -> void:
	var built := FightBuilder.build({"act": 1, "node": "boss", "objective": "boss", "seed": 7, "squad": 2, "boss": "nonsense"})
	assert_eq(built.encounter.boss, EnemyRoster.boss_for(1, 7))
