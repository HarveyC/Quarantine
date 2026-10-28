extends TestCase
## The Lantern Echoes boss (Act 3 pool): one Echo per soldier wearing that class and signature, the
## Last Echo untouchable while one stands, Taken husks that pulse Infection, and the mirrored finish.
## The view side is in test_enemy_view.gd.


func _fight(squad: int, classes: Array = ["trooper", "medic", "breacher", "marksman"], seed := 4) -> GameState:
	var fight := FightBuilder.build({"act": 3, "node": "boss", "objective": "boss", "outbreak": 0, "seed": seed,
		"squad": squad, "players": 1, "boss": "lantern_echoes"})
	var picked: Array = []
	for i in squad:
		picked.append({"kind": classes[i % classes.size()], "player": 0})
	var config := {"map": MatchConfig.MAP, "squad": picked, "enemies": [], "encounter": fight.encounter, "seed": seed,
		"map_spec": {"biome": "bore", "objective": "boss", "seed": seed, "act": 3, "boss": "lantern_echoes"}}
	var s := MatchConfig.build(config)
	Rules.start_mission(s)
	return s


func _boss(s: GameState) -> Unit:
	return LanternEchoes.boss_of(s)


func _hit(s: GameState, u: Unit, amount: int) -> void:
	Rules.deal_damage(s, u, amount, s.living(Types.Team.PLAYER)[0])


func test_it_is_in_act_3s_pool_with_its_tables() -> void:
	assert_true(EnemyRoster.BOSS_POOL[3].has("lantern_echoes"), "rolled in act 3")
	assert_true(EnemyRoster.BOSSES.has("lantern_echoes"), "a boss kind")
	assert_true(FightBuilder.BOSS_HEALTH.has("lantern_echoes"), "health by squad size")
	assert_true(StoryData.BOSS_SCENES.has("lantern_echoes") and StoryData.ACT_SCENES_BY_BOSS.has("lantern_echoes"), "its scenes")
	var seen := {}
	for sd in 40:
		seen[EnemyRoster.boss_for(3, sd)] = true
	assert_true(seen.has("lantern_echoes") and seen.has("the_source"), "the seed rolls both Act 3 bosses")


func test_one_echo_per_soldier_wears_that_class_and_signature() -> void:
	for squad in [1, 2, 3, 4]:
		var s := _fight(squad)
		var echoes := LanternEchoes.echoes(s)
		assert_eq(echoes.size(), squad, "squad %d raises %d Echoes" % [squad, squad])
		var classes := s.living(Types.Team.PLAYER).map(func(u: Unit) -> String: return u.kind)
		for i in echoes.size():
			var e: Unit = echoes[i]
			assert_eq(e.kind, classes[i], "the Echo wears its soldier's class")
			assert_true(e.display_name.begins_with("Echo "), "named for the fallen")
			assert_true(e.abilities.has(Signatures.for_class(e.kind)), "and has the class signature")
			assert_true(e.status.get("turned", false) and e.team == Types.Team.ENEMY, "an enemy that reads as Turned")
			assert_true(not EnemyRoster.infects(e), "its hits carry no Infection")
		assert_eq(_boss(s).kind, "lantern_echoes", "the Last Echo waits behind them")


func test_the_last_echo_is_untouchable_while_an_echo_stands() -> void:
	var s := _fight(2)
	var boss := _boss(s)
	var hp := boss.hp
	_hit(s, boss, 20)
	assert_eq(boss.hp, hp, "no damage reaches it")
	assert_true(s.log.any(func(e): return e.type == "immune" and e.unit == boss.id and e.reason == "echoes"), "and the view is told why")


func test_the_first_fallen_echo_opens_phase_two_and_the_source_takes_its_body() -> void:
	var s := _fight(3)
	var boss := _boss(s)
	var first: Unit = LanternEchoes.echoes(s)[0]
	var cell := first.pos
	_hit(s, first, 999)
	assert_eq(int(boss.status.boss_phase), 2, "phase 2")
	assert_true(s.log.any(func(e): return e.type == "echo_fell" and e.unit == first.id), "it collapses")
	assert_true(Encounter.is_spore(s, cell), "into spores where it stood")
	assert_eq(LanternEchoes.taken(s).size(), 0, "the husk rises at the next enemy phase, not at once")
	Encounter.on_enemy_phase_start(s)
	var husks := LanternEchoes.taken(s)
	assert_eq(husks.size(), 1, "the Source takes the body")
	assert_true(husks[0].display_name.begins_with("Taken "), "a Taken husk")
	assert_true(s.log.any(func(e): return e.type == "echo_taken"), "with its own beat")


func test_each_husk_pulses_infection_through_the_squad() -> void:
	var s := _fight(3)
	_hit(s, LanternEchoes.echoes(s)[0], 999)
	Encounter.on_enemy_phase_start(s)
	var soldier: Unit = s.living(Types.Team.PLAYER)[0]
	var before := soldier.infection
	Encounter.on_enemy_phase_start(s)   # the next round: one husk is up
	assert_eq(soldier.infection, before + int(LanternEchoes.TAKEN_PULSE[3]), "one husk, one pulse")
	_hit(s, LanternEchoes.echoes(s)[0], 999)
	Encounter.on_enemy_phase_start(s)   # a second body rises and both pulse
	var mid := soldier.infection
	Encounter.on_enemy_phase_start(s)
	assert_eq(soldier.infection - mid, int(LanternEchoes.TAKEN_PULSE[3]) * 2, "two husks, twice the pulse")


func test_the_last_echo_falls_open_and_wears_the_weakest_soldier() -> void:
	var s := _fight(2, ["trooper", "medic"])
	var boss := _boss(s)
	var medic: Unit = s.living(Types.Team.PLAYER).filter(func(u): return u.kind == "medic")[0]
	medic.hp = 2   # the lowest HP soldier
	_hit(s, LanternEchoes.echoes(s)[0], 999)
	Encounter.on_enemy_phase_start(s)
	assert_eq(LanternEchoes.taken(s).size(), 1, "a husk is up")
	_hit(s, LanternEchoes.echoes(s)[0], 999)
	assert_eq(int(boss.status.boss_phase), 3, "phase 3 once the last Echo is down")
	assert_eq(str(boss.status.mirror), "medic", "it mirrors the weakest soldier")
	assert_true(boss.abilities.has("stim") and boss.abilities.has("quarantine_field"), "with that class and signature")
	assert_eq(LanternEchoes.taken(s).size(), 0, "the husks collapse into spores")
	assert_true(boss.mobility >= LanternEchoes.LAST_MOBILITY, "and it moves")
	var hp := boss.hp
	_hit(s, boss, 3)
	assert_eq(boss.hp, hp - 3, "now it can be hurt")
	assert_true(not LanternEchoes.scripted(boss), "and it plays like an Echo")


func test_killing_the_last_echo_ends_the_fight() -> void:
	var s := _fight(1)
	var boss := _boss(s)
	_hit(s, LanternEchoes.echoes(s)[0], 999)
	assert_eq(int(boss.status.boss_phase), 3, "a lone Echo goes straight to the finish")
	_hit(s, boss, 999)
	Rules.check_end(s)
	assert_eq(s.result, Types.Result.VICTORY, "the boss falls and the fight is won")


func test_echoes_use_their_class_signature_on_their_turn() -> void:
	var s := _fight(4, ["trooper", "marksman", "medic", "breacher"])
	var echoes := LanternEchoes.echoes(s)
	var foe: Unit = s.living(Types.Team.PLAYER)[0]
	var used := {}
	for e in echoes:
		e.pos = foe.pos + Vector2i(0, -3) + Vector2i(echoes.find(e) % 2, echoes.find(e) / 2)
		e.actions_left = 2
		var hostiles: Array[Unit] = [foe]
		var action := LanternEchoes.choose(s, e, hostiles)
		used[e.kind] = str(action.get("ability", action.get("type", "")))
	assert_eq(used.trooper, "lockdown", "the Trooper Echo locks the nave down")
	assert_eq(used.marksman, "deadeye", "the Marksman Echo takes its Deadeye")
	assert_eq(used.breacher, "bring_down", "the Breacher Echo brings the cover down")


func test_an_echoes_hits_are_scaled_for_the_squad_and_do_not_infect() -> void:
	var s := _fight(2)
	var echo: Unit = LanternEchoes.echoes(s)[0]
	var soldier: Unit = s.living(Types.Team.PLAYER)[0]
	soldier.max_hp = 99
	soldier.hp = 99
	var inf := soldier.infection
	Rules.deal_damage(s, soldier, 10, echo)
	assert_eq(soldier.hp, 99 - roundi(10 * float(LanternEchoes.ECHO_DAMAGE[2])), "a squad of two takes the scaled hit")
	assert_eq(soldier.infection, inf, "no Infection from the hit")


func test_the_bore_arena_for_this_boss_is_its_own() -> void:
	for sd in [1, 2, 3, 4, 5]:
		var g := MapGen.generate({"biome": "bore", "objective": "boss", "seed": sd, "boss": "lantern_echoes"})
		assert_eq(MapGen.last_plot, "arena", "an authored arena")
		assert_true(g.player_spawns.size() >= 4 and g.enemy_spawns.size() >= MapGen.MIN_ENEMY_SPAWNS, "spawns for the squad and the pods")
		var boss: Vector2i = g.marker("boss")[0]
		assert_true(g.level(boss) >= 2, "the Last Echo sits on the dais seat (level %d)" % g.level(boss))
		assert_true(g.in_bounds(boss), "on the map")
	var data := MapGen._load_biome("bore")
	assert_eq(MapGen._arenas_for(data.arenas, "lantern_echoes").map(func(a): return a.name), ["lantern_wake"], "tagged for it")
	assert_true(not MapGen._arenas_for(data.arenas, "the_source").map(func(a): return a.name).has("lantern_wake"), "and kept off the Source's ground")
