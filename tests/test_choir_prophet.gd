extends TestCase
## The Act 2 boss the Choir Prophet (enemies/choir_prophet.gd): the guard, the chant ring, verses,
## the fix and compel, Hush, the Crescendo and his arena. The view beats are in test_enemy_view.gd.


func _open(w: int, h: int) -> PackedStringArray:
	var rows := PackedStringArray()
	for y in h:
		rows.append(".".repeat(w))
	return rows


func _soldier(s: GameState, kind: String, at: Vector2i) -> Unit:
	var u := UnitData.make(kind, Types.Team.PLAYER)
	u.owner_player = 0
	return s.add_unit(u, at)


func _events(s: GameState, type: String) -> Array:
	return s.log.filter(func(e): return e.type == type)


## One enemy turn for `u`, the way Rules.run_enemy_phase runs it.
func _enemy_turn(s: GameState, u: Unit) -> void:
	s.phase = Types.Phase.ENEMY
	u.actions_left = Types.ACTIONS_PER_TURN
	for k in u.cooldowns.keys():
		u.cooldowns[k] = max(0, u.cooldowns[k] - 1)
	Encounter.on_unit_turn_start(s, u)
	EnemyAI.take_turn(s, u)
	u.actions_left = 0
	Encounter.on_unit_turn_end(s, u)


## A 20x20 open arena with the Prophet on the dais at (10, 4) and the squad well outside his ring.
func _fight(squad := 4, rows := PackedStringArray()) -> GameState:
	var s := make_blank(rows if not rows.is_empty() else _open(20, 20))
	_soldier(s, "trooper", Vector2i(3, 16))
	_soldier(s, "marksman", Vector2i(8, 16))
	_soldier(s, "medic", Vector2i(12, 16))
	_soldier(s, "breacher", Vector2i(17, 16))
	s.grid.enemy_spawns.assign([Vector2i(10, 4), Vector2i(2, 2), Vector2i(17, 2)])
	s.grid.markers["boss"] = [Vector2i(10, 4)]
	Encounter.setup(s, {"boss": "choir_prophet", "node": "boss", "act": 2, "squad": squad})
	s.turn = 2
	return s


func _prophet(s: GameState) -> Unit:
	return s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "choir_prophet")[0]


func _cantors(s: GameState) -> Array:
	var kind := ChoirProphet.choir_kind("cantor")
	return s.living(Types.Team.ENEMY).filter(func(u): return u.kind == kind)


## Advances a phase by hitting the Prophet through his gates, with the guard down.
func _to_phase(s: GameState, h: Unit, phase: int) -> void:
	for c in _cantors(s):
		Encounter.kill(s, c)
	while int(h.status.boss_phase) < phase:
		Rules.deal_damage(s, h, 999, s.living(Types.Team.PLAYER)[0])
	h.cooldowns.clear()


func test_he_starts_on_the_dais_ringed_by_cantors_with_the_choir_on_its_way() -> void:
	for squad in [1, 2, 4]:
		var s := _fight(squad)
		var h := _prophet(s)
		assert_eq(h.pos, Vector2i(10, 4), "on the dais")
		assert_eq(_cantors(s).size(), ChoirProphet.CANTORS[squad], "a ring of Cantors for %d" % squad)
		for c in _cantors(s):
			assert_eq(EnemyAbilities._cheb(c.pos, h.pos), 2, "kneeling round him")
		if squad == 1:
			assert_true(s.encounter.get("waves", []).is_empty(), "a lone soldier faces no waves")
			continue
		assert_true(s.encounter.waves.size() == 1, "the Choir comes in waves")
		assert_true(int(s.encounter.waves[0].turn) == ChoirProphet.WAVE_FIRST, "from turn 2")
		for k in s.encounter.waves[0].kinds:
			assert_true(UnitData.ENEMIES.has(k), "%s exists" % k)


func test_the_cantors_guard_him_and_each_phase_gate_stops_a_hit() -> void:
	var s := _fight()
	var h := _prophet(s)
	var t := s.living(Types.Team.PLAYER)[0]
	Rules.deal_damage(s, h, 5, t)
	assert_eq(h.max_hp - h.hp, 5 - ChoirProphet.GUARD, "the singing Cantors soak part of every hit")
	Rules.deal_damage(s, h, 1, t)
	assert_eq(h.max_hp - h.hp, 5 - ChoirProphet.GUARD + 1, "a hit of 1 still lands")
	for c in _cantors(s):
		Encounter.kill(s, c)
	h.hp = h.max_hp
	Rules.deal_damage(s, h, 5, t)
	assert_eq(h.max_hp - h.hp, 5, "with the circle broken he takes it all")
	Rules.deal_damage(s, h, 999, t)
	assert_eq(int(h.status.boss_phase), 2, "one hit cannot skip the Answer")
	assert_eq(h.hp, ChoirProphet.gates(h)[0], "stopped at the first gate")
	Rules.deal_damage(s, h, 999, t)
	assert_eq(int(h.status.boss_phase), 3, "nor the Crescendo")
	assert_eq(h.hp, ChoirProphet.gates(h)[1], "stopped at the second gate")
	assert_eq(_events(s, "boss_phase").size(), 2, "both banners")
	Rules.deal_damage(s, h, 999, t)
	assert_true(not h.is_alive(), "and then he falls")


func test_health_scales_with_squad() -> void:
	for squad in [1, 2, 3, 4]:
		var enc: Dictionary = FightBuilder.build({"act": 2, "node": "boss", "objective": "boss", "seed": 2,
			"players": squad, "squad": squad, "boss": "choir_prophet"}).encounter
		assert_eq(enc.boss, "choir_prophet")
		assert_true(absf(float(enc.get("boss_health_mult", 1.0)) - float(ChoirProphet.HEALTH[squad])) < 0.001, "his share for %d" % squad)


func test_the_chant_ring_presses_infection_into_soldiers_inside_and_empowers_the_choir() -> void:
	var s := _fight()
	var h := _prophet(s)
	var inside := s.living(Types.Team.PLAYER)[0]
	inside.pos = Vector2i(10, 8)
	var outside := s.living(Types.Team.PLAYER)[1]
	s.phase = Types.Phase.ENEMY
	Encounter.on_enemy_phase_start(s)
	assert_eq(inside.infection, ChoirProphet.RING_INFECTION[1], "inside the ring")
	assert_eq(outside.infection, 0, "outside it")
	assert_eq(_events(s, "chant").size(), 1, "the ring pulses")
	assert_eq(_events(s, "chant")[0].units, [inside.id], "on the soldier inside")
	var cantor: Unit = _cantors(s)[0]
	assert_eq(Encounter.modify_damage(s, inside, 3, cantor), 3 + ChoirProphet.RING_DAMAGE[1], "the Choir hits harder inside it")
	cantor.pos = Vector2i(10, 15)
	assert_eq(Encounter.modify_damage(s, inside, 3, cantor), 3, "and no harder outside it")
	h.status["suppressed"] = Combat.phase_index(s) + 2
	inside.infection = 0
	Encounter.on_enemy_phase_start(s)
	assert_eq(inside.infection, 0, "a suppressed Prophet cannot sing the ring")
	cantor.pos = Vector2i(10, 5)
	assert_eq(Encounter.modify_damage(s, inside, 3, cantor), 3, "nor empower the Choir")


func test_the_ring_closes_in_each_phase() -> void:
	var s := _fight()
	var h := _prophet(s)
	var r1 := ChoirProphet.ring_radius(h)
	_to_phase(s, h, 2)
	var r2 := ChoirProphet.ring_radius(h)
	_to_phase(s, h, 3)
	var r3 := ChoirProphet.ring_radius(h)
	assert_true(r1 > r2 and r2 > r3, "5, 4, then 3 tiles")
	assert_true(ChoirProphet.RING_DAMAGE[3] > ChoirProphet.RING_DAMAGE[1], "and it bites harder")


func test_a_verse_is_marked_a_turn_before_it_lands_with_infection() -> void:
	var s := _fight()
	var h := _prophet(s)
	for c in _cantors(s):
		Encounter.kill(s, c)
	var t := s.living(Types.Team.PLAYER)[0]
	t.pos = Vector2i(10, 13)
	_enemy_turn(s, h)
	var tel: Array = s.encounter.telegraphs.filter(func(x): return x.kind == "verse")
	assert_true(not tel.is_empty(), "a verse is marked")
	assert_true(tel[0].cells.has(t.pos), "on the soldier")
	var hp := t.hp
	s.turn += 1
	Encounter.on_enemy_phase_start(s)
	assert_true(t.hp < hp, "it lands next phase")
	assert_true(t.infection > 0, "and carries Infection")


func test_fix_then_compel_takes_a_soldier_for_two_rounds() -> void:
	var s := _fight()
	var h := _prophet(s)
	_to_phase(s, h, 2)
	var victim := s.living(Types.Team.PLAYER)[1]
	victim.infection = 60
	_enemy_turn(s, h)
	assert_eq(int(h.status.get("fixed", -1)), victim.id, "the hymn fixes on the most Infected soldier")
	assert_true(not victim.status.get("lapsed", false), "not yet taken")
	s.turn += 1
	_enemy_turn(s, h)
	assert_true(victim.status.get("lapsed", false), "taken next round")
	assert_true(victim.ai_controlled, "AI controlled")
	assert_true(not h.status.has("fixed"), "the link is spent")
	assert_eq(_events(s, "lapse").filter(func(e): return e.get("compelled", false)).size(), 1, "announced as a compel")
	Infection.on_team_phase_start(s)
	assert_true(victim.status.get("lapsed", false), "still his after one round")
	Infection.on_team_phase_start(s)
	assert_true(victim.status.get("lapsed", false), "and after the second")
	Infection.on_team_phase_start(s)
	assert_true(not victim.status.get("lapsed", false), "free on the third")
	assert_true(not victim.status.has("compelled"), "the hold is gone")


func test_a_cure_breaks_the_hold_at_once() -> void:
	var s := _fight()
	var h := _prophet(s)
	_to_phase(s, h, 2)
	var victim := s.living(Types.Team.PLAYER)[1]
	ChoirProphet.compel(s, victim)
	assert_true(victim.status.get("lapsed", false))
	Infection.end_lapse(s, victim)
	assert_true(not victim.status.has("compelled") and not victim.ai_controlled, "cleansed, back in control")


func test_breaking_sight_or_suppressing_him_cuts_the_link() -> void:
	var rows := _open(20, 20)
	var s := _fight(4, rows)
	var h := _prophet(s)
	_to_phase(s, h, 2)
	var victim := s.living(Types.Team.PLAYER)[1]
	victim.infection = 60
	_enemy_turn(s, h)
	assert_true(h.status.has("fixed"))
	# A wall between them: the link fails.
	EnemyAbilities.set_tile(s.grid, Vector2i(victim.pos.x, 9), Types.Tile.WALL)
	for dx in range(-3, 4):
		EnemyAbilities.set_tile(s.grid, Vector2i(victim.pos.x + dx, 9), Types.Tile.WALL)
	s.turn += 1
	_enemy_turn(s, h)
	assert_true(not victim.status.get("lapsed", false), "out of sight, not compelled")
	assert_eq(_events(s, "lock_lost").size(), 1, "the link is lost")
	# Suppression: no fix at all.
	var s2 := _fight()
	var h2 := _prophet(s2)
	_to_phase(s2, h2, 2)
	h2.status["suppressed"] = Combat.phase_index(s2) + 2
	_enemy_turn(s2, h2)
	assert_true(not h2.status.has("fixed") and s2.encounter.telegraphs.is_empty(), "a suppressed Prophet sings nothing")


func test_a_compelled_soldier_shoots_the_squad_and_alone_stands_transfixed_alone() -> void:
	var s := _fight()
	var h := _prophet(s)
	var victim := s.living(Types.Team.PLAYER)[1]
	var mate := s.living(Types.Team.PLAYER)[0]
	mate.pos = victim.pos + Vector2i(2, 0)
	var before := mate.hp
	ChoirProphet.compel(s, victim)
	victim.actions_left = 2
	EnemyAI.take_turn(s, victim)
	assert_true(_events(s, "shot").size() >= 1 or mate.hp < before, "turns on a squadmate")
	# Alone: nobody else to shoot, so the song draws them in.
	var solo := make_blank(_open(20, 20))
	var lone := _soldier(solo, "trooper", Vector2i(10, 16))
	solo.grid.enemy_spawns.assign([Vector2i(10, 4)])
	solo.grid.markers["boss"] = [Vector2i(10, 4)]
	Encounter.setup(solo, {"boss": "choir_prophet", "node": "boss", "act": 2, "squad": 1})
	var at := lone.pos
	ChoirProphet.compel(solo, lone)
	lone.actions_left = 2
	EnemyAI.take_turn(solo, lone)
	assert_eq(lone.pos, at, "a lone soldier stands transfixed")
	assert_true(lone.status.get("lapsed", false) and lone.actions_left == 2, "and loses the rounds")
	assert_eq(ChoirProphet.compelled_damage(lone, 4), 2, "their own hits are halved")
	assert_eq(ChoirProphet.compelled_damage(mate, 4), 4, "other soldiers' are not")


func test_hush_silences_a_signature_until_it_wears_off() -> void:
	var s := _fight()
	var h := _prophet(s)
	_to_phase(s, h, 3)
	var t := s.living(Types.Team.PLAYER)[0]
	t.abilities.append("lockdown")
	_enemy_turn(s, h)
	assert_true(t.status.has("hushed"), "his Hush lands on the soldier with a signature")
	var err := Encounter.validate(s, t, {"type": Types.ABILITY, "unit": t.id, "ability": "lockdown"})
	assert_true(err.begins_with("Hushed"), "the signature is silent: %s" % err)
	assert_eq(Encounter.validate(s, t, {"type": Types.OVERWATCH, "unit": t.id}), "", "everything else still works")
	for i in ChoirProphet.HUSH_ROUNDS:
		ChoirProphet.on_team_phase_start(s)
		assert_true(t.status.has("hushed"), "round %d" % (i + 1))
	ChoirProphet.on_team_phase_start(s)
	assert_true(not t.status.has("hushed"), "wears off after two rounds")
	assert_eq(_events(s, "unhushed").size(), 1)


func test_nobody_with_a_signature_means_no_hush() -> void:
	var s := _fight()
	var h := _prophet(s)
	_to_phase(s, h, 3)
	for u in s.living(Types.Team.PLAYER):
		u.abilities.assign(u.abilities.filter(func(a): return not Signatures.is_signature(a)))
	_enemy_turn(s, h)
	assert_true(s.living(Types.Team.PLAYER).all(func(u): return not u.status.has("hushed")))


func test_the_hymn_builds_to_a_crescendo_that_cannot_see_behind_walls() -> void:
	var rows := _open(20, 20)
	var s := _fight(4, rows)
	var h := _prophet(s)
	_to_phase(s, h, 3)
	# A wall across the arena: the soldier tucked behind it is hidden from him.
	for dx in range(-8, 9):
		EnemyAbilities.set_tile(s.grid, Vector2i(10 + dx, 9), Types.Tile.WALL)
	var exposed := s.living(Types.Team.PLAYER)[0]
	exposed.pos = Vector2i(10, 7)
	var hidden := s.living(Types.Team.PLAYER)[1]
	hidden.pos = Vector2i(10, 12)
	for turn in ChoirProphet.HYMN_MAX - 1:
		s.turn += 1
		_enemy_turn(s, h)
		assert_true(s.encounter.telegraphs.all(func(t): return t.kind != "crescendo"), "still building (%d)" % turn)
	assert_eq(_events(s, "hymn").size(), ChoirProphet.HYMN_MAX - 1, "the hymn pulses each round")
	s.turn += 1
	_enemy_turn(s, h)
	var tel: Array = s.encounter.telegraphs.filter(func(x): return x.kind == "crescendo")
	assert_eq(tel.size(), 1, "then the Crescendo is marked")
	assert_true(tel[0].cells.has(exposed.pos), "everything he can see")
	assert_true(not tel[0].cells.has(hidden.pos), "but not what stands behind the wall")
	assert_eq(int(h.status.hymn), 0, "and the hymn starts over")
	var hp := exposed.hp
	var inf := exposed.infection
	s.turn += 1
	Encounter.on_enemy_phase_start(s)
	assert_true(exposed.hp < hp and exposed.infection >= inf + ChoirProphet.CRESCENDO_INFECTION, "it lands with Infection")
	assert_eq(hidden.hp, hidden.max_hp, "the hidden soldier is untouched")


func test_every_ability_has_a_definition_and_a_phase() -> void:
	for id in ChoirProphet.OWNS:
		assert_true(EnemyAbilities.DEFS.has(id), "%s is defined" % id)
		assert_true(UnitData.ENEMIES.choir_prophet.abilities.has(id), "%s is his" % id)
	var s := _fight()
	var h := _prophet(s)
	var names := EnemyAbilities.describe(s, h).map(func(d): return d.id)
	assert_eq(names, ["verse"], "phase 1 shows only the verse")
	_to_phase(s, h, 3)
	names = EnemyAbilities.describe(s, h).map(func(d): return d.id)
	assert_true(names.has("hush") and names.has("crescendo") and names.has("fix"), "phase 3 adds Hush and the Crescendo")


func test_the_act_pool_rolls_him_and_the_arena_is_his() -> void:
	assert_true(EnemyRoster.BOSS_POOL[2].has("choir_prophet"), "in the Act 2 pool")
	assert_true(StoryData.BOSS_SCENES.has("choir_prophet") and StoryData.ACT_SCENES_BY_BOSS.has("choir_prophet"), "his scenes")
	assert_true(StoryData.SILENT_BARKS.has("choir_prophet_2") and StoryData.SILENT_BARKS.has("choir_prophet_3"), "his phase barks")
	for seed in [1, 2, 3, 4, 5, 6]:
		var g := MapGen.generate({"biome": "port", "objective": "boss", "seed": seed, "boss": "choir_prophet"})
		assert_eq(MapGen.last_plot, "arena")
		var boss: Array = g.markers.boss
		assert_eq(boss[0].y, 6, "the dais sits mid-arena")
		var other := MapGen.generate({"biome": "port", "objective": "boss", "seed": seed, "boss": "colonel_hale"})
		assert_true(other.markers.boss[0] != boss[0], "Hale keeps his command post")


func test_a_real_fight_builds_with_the_prophet_and_his_circle() -> void:
	var fight := FightBuilder.build({"act": 2, "node": "boss", "objective": "boss", "seed": 5, "squad": 2, "players": 2, "boss": "choir_prophet"})
	var config := MatchConfig.make(2, 5)
	config["enemies"] = fight.enemies
	config["encounter"] = fight.encounter
	config["map_spec"] = {"biome": "port", "objective": "boss", "seed": 5, "boss": "choir_prophet"}
	var s := MatchConfig.build(config)
	var h := _prophet(s)
	assert_true(h.is_alive())
	assert_eq(_cantors(s).size(), ChoirProphet.CANTORS[2])
	assert_true(h.pos.y == 6, "on the dais")
