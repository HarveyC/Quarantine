extends TestCase
## Halden-Voss Recovery: the Director's roof posts and phase gates, the retrieval mark and cage, and
## the Collectors that pin, drag and take a soldier (enemies/director_boss.gd, enemies/retrieval.gd).


func _open(w: int, h: int) -> PackedStringArray:
	var rows := PackedStringArray()
	for y in h:
		rows.append(".".repeat(w))
	return rows


func _soldier(s: GameState, kind: String, at: Vector2i) -> Unit:
	var u := UnitData.make(kind, Types.Team.PLAYER)
	u.owner_player = 0
	return s.add_unit(u, at)


func _fight(kinds: Array) -> GameState:
	var s := make_blank(_open(20, 20))
	var x := 3
	for k in kinds:
		_soldier(s, k, Vector2i(x, 17))
		x += 3
	s.grid.enemy_spawns.assign([Vector2i(10, 2)])
	Encounter.setup(s, {"boss": "director", "node": "boss", "act": 2, "squad": kinds.size()})
	return s


func _of(s: GameState, kind: String) -> Array:
	return s.living(Types.Team.ENEMY).filter(func(u): return u.kind == kind)


func test_the_director_stands_behind_roof_posts_that_scale_with_the_squad() -> void:
	for n in [1, 2, 4]:
		var kinds := ["trooper", "marksman", "medic", "breacher"].slice(0, n)
		var s := _fight(kinds)
		assert_eq(_of(s, "director").size(), 1, "one Director")
		assert_eq(_of(s, "sharpshooter").size(), DirectorBoss.POSTS[n], "posts for a squad of %d" % n)
		assert_eq(_of(s, "director")[0].status.get("tether", ""), "sharpshooter" if DirectorBoss.POSTS[n] > 0 else "", "tethered to the posts")


func test_she_takes_no_damage_while_a_post_lives_and_opens_when_the_last_falls() -> void:
	var s := _fight(["trooper", "marksman"])
	var d: Unit = _of(s, "director")[0]
	var shooter: Unit = s.living(Types.Team.PLAYER)[0]
	var hp := d.hp
	Rules.deal_damage(s, d, 20, shooter)
	assert_eq(d.hp, hp, "immune while tethered")
	for p in _of(s, "sharpshooter"):
		Rules.deal_damage(s, p, 999, shooter)
	assert_true(not d.status.has("tether"), "untethered with the last post down")
	Rules.deal_damage(s, d, 3, shooter)
	assert_true(d.hp < hp, "open to fire")


func test_each_phase_gate_stops_a_single_hit() -> void:
	var s := _fight(["trooper", "marksman"])
	var d: Unit = _of(s, "director")[0]
	var shooter: Unit = s.living(Types.Team.PLAYER)[0]
	d.status.erase("tether")
	Rules.deal_damage(s, d, 999, shooter)
	assert_true(d.is_alive(), "survives the first big hit")
	assert_eq(int(d.status.boss_phase), 2, "phase 2")
	assert_eq(d.hp, DirectorBoss.gates(d)[0], "stopped on the gate")
	assert_eq(d.status.get("tether"), "sharpshooter", "a second team covers her again")
	d.status.erase("tether")
	Rules.deal_damage(s, d, 999, shooter)
	assert_eq(int(d.status.boss_phase), 3, "phase 3")
	assert_true(not d.status.has("tether"), "no cover in phase 3")
	Rules.deal_damage(s, d, 999, shooter)
	assert_true(not d.is_alive(), "and she can die")


func test_the_mark_goes_to_the_most_infected_and_hurts() -> void:
	var s := _fight(["trooper", "marksman", "medic"])
	var d: Unit = _of(s, "director")[0]
	var soldiers := s.living(Types.Team.PLAYER)
	soldiers[1].infection = 6
	Retrieval.apply(s, d, {"ability": "flag"})
	assert_true(Retrieval.is_marked(soldiers[1]), "the most Infected is marked")
	assert_true(not Retrieval.is_marked(soldiers[0]), "only one at a time")
	var post: Unit = _of(s, "sharpshooter")[0]
	var before := Encounter.modify_damage(s, soldiers[0], 3, post)
	var after := Encounter.modify_damage(s, soldiers[1], 3, post)
	assert_eq(after, before + Retrieval.MARK_DAMAGE, "enemy hits on the marked soldier deal extra")


func test_a_collector_drags_its_captive_to_the_lane_and_takes_them() -> void:
	var s := make_blank(_open(14, 14))
	var victim := _soldier(s, "trooper", Vector2i(7, 9))
	_soldier(s, "marksman", Vector2i(2, 12))
	s.grid.enemy_spawns.assign([Vector2i(7, 2)])
	s.encounter["squad"] = 4
	var c := s.add_unit(EnemyRoster.make("collector"), Vector2i(7, 8))
	c.status["alerted"] = true
	c.status["pinning"] = victim.id
	victim.status["pinned_by"] = c.id
	Retrieval.apply(s, c, {"ability": "drag"})
	assert_eq(c.pos, Vector2i(7, 8) + Vector2i(0, -Retrieval.DRAG_STEPS[4]), "the Collector hauls toward the lane")
	assert_true(victim.pos.distance_to(c.pos) <= 1.5, "the captive comes along")
	assert_true(victim.is_alive(), "not yet taken")
	c.pos = Vector2i(7, 3)
	victim.pos = Vector2i(7, 4)
	c.status["pinning"] = victim.id
	Retrieval.apply(s, c, {"ability": "drag"})
	assert_true(not victim.is_alive(), "taken at the lane")
	assert_true(not c.is_alive(), "and the Collector slips away")
	assert_eq(s.log.filter(func(e): return e.type == "taken").size(), 1, "a taken event")


func test_the_cage_takes_a_pinned_soldier_and_only_hurts_a_free_one() -> void:
	var s := _fight(["trooper", "marksman"])
	var d: Unit = _of(s, "director")[0]
	var pinned: Unit = s.living(Types.Team.PLAYER)[0]
	var free: Unit = s.living(Types.Team.PLAYER)[1]
	var c := s.add_unit(EnemyRoster.make("collector"), Encounter.free_cell(s, pinned.pos + Vector2i(0, -1)))
	c.status["pinning"] = pinned.id
	pinned.status["pinned_by"] = c.id
	s.turn = 1
	Retrieval.apply(s, d, {"ability": "retrieve", "cell": Retrieval.cage_cell(s, pinned)})
	Retrieval.apply(s, d, {"ability": "retrieve", "cell": free.pos})
	s.turn = 2
	Encounter.on_enemy_phase_start(s)
	assert_true(not pinned.is_alive(), "the pinned soldier is taken")
	assert_true(free.is_alive() and free.hp < free.max_hp, "a free soldier is only hurt")


func test_the_director_fight_builds_on_its_arena_and_a_lone_soldier_can_play_it() -> void:
	var spec := {"act": 2, "node": "boss", "objective": "boss", "outbreak": 6, "seed": 5, "squad": 1, "players": 1, "boss": "director"}
	var fight := FightBuilder.build(spec)
	assert_eq(fight.encounter.boss, "director")
	var config := MatchConfig.make(1, 99)
	config["enemies"] = fight.enemies
	config["encounter"] = fight.encounter
	var s := MatchConfig.build(config)
	assert_eq(_of(s, "director").size(), 1, "she is on the map")
	assert_eq(_of(s, "sharpshooter").size(), DirectorBoss.POSTS[1], "and her posts for one soldier")
