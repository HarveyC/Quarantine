extends TestCase

const Director := preload("res://ui/story/story_director.gd")
## The Source's aspects (Hunger, Remembers, Regrown): chosen from the run, and each changes the fight.


func _fight(aspect: String, squad := 2, names: Array = []) -> GameState:
	var s := make_blank(_open(14, 14))
	for i in squad:
		var u := UnitData.make(["trooper", "marksman", "medic", "breacher"][i], Types.Team.PLAYER)
		u.owner_player = 0
		s.add_unit(u, Vector2i(2 + i * 3, 12))
	s.grid.enemy_spawns.assign([Vector2i(7, 2)])
	Encounter.setup(s, {"boss": "the_source", "node": "boss", "act": 3, "squad": squad, "aspect": aspect, "echo_names": names})
	return s


func _open(w: int, h: int) -> PackedStringArray:
	var rows := PackedStringArray()
	for y in h:
		rows.append(".".repeat(w))
	return rows


func _src(s: GameState) -> Unit:
	return s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "the_source")[0]


func _roots(s: GameState) -> Array:
	return s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "source_root")


func _enemy_turn(s: GameState, u: Unit) -> void:
	s.phase = Types.Phase.ENEMY
	u.actions_left = Types.ACTIONS_PER_TURN
	for k in u.cooldowns.keys():
		u.cooldowns[k] = max(0, u.cooldowns[k] - 1)
	EnemyAI.take_turn(s, u)
	u.actions_left = 0


func _run(infection: int, laid := false, lost := false, last_ending := "") -> RunState:
	var run := RunState.new()
	run.act = 3
	run.story = {"echoes": [{"key": "a", "name": "Osei", "laid": laid}], "last_ending": last_ending}
	run.soldiers = [{"id": 1, "sid": 1, "kind": "trooper", "name": "Reyes", "owner": 0, "status": RunSoldier.ACTIVE, "infection": infection}]
	if lost:
		run.echoes = [{"name": "Reyes"}]
	return run


func test_the_run_picks_the_aspect() -> void:
	assert_eq(SourceBoss.aspect_for(_run(60)), "hunger", "an Infected squad")
	assert_eq(SourceBoss.aspect_for(_run(80)), "hunger", "one soldier near Turning")
	assert_eq(SourceBoss.aspect_for(_run(10, true)), "remembers", "an Echo laid to rest")
	assert_eq(SourceBoss.aspect_for(_run(10, false, true)), "remembers", "a soldier lost this run")
	assert_eq(SourceBoss.aspect_for(_run(10, false, false, "burn")), "regrown", "the last wave burned it")
	assert_eq(SourceBoss.aspect_for(_run(10)), "", "nothing to remember: the plain Source")
	assert_eq(SourceBoss.aspect_for(_run(60, true, true, "burn")), "hunger", "this run's Infection comes first")
	var run := _run(60)
	assert_eq(SourceBoss.aspect_for(run), "hunger")
	run.soldiers[0].infection = 0
	assert_eq(SourceBoss.aspect_for(run), "hunger", "chosen once as Act 3 opens")


func test_the_fight_spec_carries_the_aspect() -> void:
	var spec := {"act": 3, "node": "boss", "objective": "boss", "seed": 5, "squad": 2, "boss": "the_source",
		"aspect": "remembers", "echo_names": ["Osei"]}
	var built := FightBuilder.build(spec)
	assert_eq(built.encounter.aspect, "remembers")
	spec.erase("aspect")
	assert_true(not FightBuilder.build(spec).encounter.has("aspect"), "no aspect, plain Source")


func test_hunger_pulls_from_phase_1_and_starts_the_ring_closer() -> void:
	var s := _fight("hunger")
	var src := _src(s)
	var t: Unit = s.living(Types.Team.PLAYER)[0]
	t.infection = 40
	var before := Vector2(t.pos).distance_to(Vector2(src.pos))
	s.turn = 1
	_enemy_turn(s, src)
	assert_true(Vector2(t.pos).distance_to(Vector2(src.pos)) < before, "the most Infected soldier is pulled in while the roots live")
	assert_eq(EnemyIntent._intent(s, src).icon, "pull", "the intent names the pull")
	var plain := _fight("")
	_enemy_turn(plain, _src(plain))
	assert_eq(EnemyIntent._intent(plain, _src(plain)).icon, "pulse")
	var edge := Vector2i(1, 5)
	Encounter.on_enemy_phase_end(s)
	Encounter.on_enemy_phase_end(plain)
	assert_true(Encounter.is_spore(s, edge) or Encounter.is_spore(s, Vector2i(2, 5)), "the ring has already closed in")
	assert_true(not Encounter.is_spore(plain, Vector2i(2, 5)), "the plain Source starts at the edge")


func test_remembers_raises_named_echoes_early_with_fewer_roots() -> void:
	var s := _fight("remembers", 4, ["Osei", "Reyes"])
	assert_eq(_roots(s).size(), Encounter.SOURCE_ROOTS[4] - 1, "fewer roots")
	var src := _src(s)
	s.turn = 1
	_enemy_turn(s, src)
	var echoes := s.living(Types.Team.ENEMY).filter(func(u): return u.display_name.begins_with("Echo of"))
	assert_eq(echoes.size(), 1, "an Echo from the first round")
	assert_eq(echoes[0].display_name, "Echo of Osei")
	assert_true(int(src.status.boss_phase) == 1, "with the roots still up")
	var plain := _fight("", 4)
	_enemy_turn(plain, _src(plain))
	assert_true(not plain.living(Types.Team.ENEMY).any(func(u): return u.display_name.contains("Echo")), "the plain Source waits for the open core")


func test_regrown_grows_a_root_back_while_the_core_is_open() -> void:
	var s := _fight("regrown", 2)
	var src := _src(s)
	var t: Unit = s.living(Types.Team.PLAYER)[0]
	for r in _roots(s):
		Rules.deal_damage(s, r, 99, t)
	assert_eq(int(src.status.boss_phase), 2, "core open")
	assert_true(not src.status.has("tether"))
	s.turn = int(src.status.open_turn) + SourceBoss.REGROWN_WINDOW[2] - 1
	_enemy_turn(s, src)
	assert_eq(_roots(s).size(), 0, "not yet")
	s.turn += 1
	_enemy_turn(s, src)
	assert_eq(_roots(s).size(), 1, "a root grows back")
	assert_eq(str(src.status.get("tether", "")), "source_root", "and shields it")
	assert_eq(int(src.status.boss_phase), 1, "the Source is closed again")
	Rules.deal_damage(s, src, 5, t)
	assert_eq(src.hp, src.max_hp, "immune")
	Rules.deal_damage(s, _roots(s)[0], 99, t)
	assert_eq(int(src.status.boss_phase), 2, "the core opens a second time")
	for i in 12:
		s.turn += 1
		_enemy_turn(s, src)
		for r in _roots(s):
			Rules.deal_damage(s, r, 99, t)
	assert_eq(int(src.status.regrown_cycles), SourceBoss.REGROWN_CYCLES[2], "only so many times")
	var plain := _fight("", 2)
	for r in _roots(plain):
		Rules.deal_damage(plain, r, 99, plain.living(Types.Team.PLAYER)[0])
	plain.turn = 20
	_enemy_turn(plain, _src(plain))
	assert_eq(_roots(plain).size(), 0, "the plain Source never regrows in the open window")


func test_the_source_stays_immune_to_knockback_in_every_aspect() -> void:
	for a in SourceBoss.ASPECTS:
		var s := _fight(a)
		var src := _src(s)
		var before := src.pos
		EnemyAbilities.knockback(s, src, Vector2i(0, 1), 2)
		assert_eq(src.pos, before, "%s stays put" % a)


func test_every_aspect_has_its_lines_and_rules() -> void:
	for a in SourceBoss.ASPECTS:
		assert_true(SourceBoss.ASPECT_NAMES.has(a) and SourceBoss.ASPECT_RULES.has(a))
		var lines: Dictionary = StoryData.SOURCE_ASPECT_LINES[a]
		for k in ["intro", "open", "collapse"]:
			assert_true(lines.has(k), "%s has an %s line" % [a, k])
	var run := _run(60)
	run.map = RunMap.generate(run.rng, 3)
	var scene: Dictionary = Director.boss_spec(run, "the_source")
	assert_true(str(scene.sub).contains("Hunger"), "the intro names the aspect")
	assert_eq(scene.lines[1].text if scene.lines[1] is Dictionary else scene.lines[1][1], StoryData.SOURCE_ASPECT_LINES.hunger.intro[1])
