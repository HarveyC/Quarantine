extends TestCase
const Director := preload("res://ui/story/story_director.gd")
## The Act 1 boss "the Breaker": pool and data, the front plate, three phases, marked charge lanes that
## flatten cover, the second lane in phase 3, debris on high ground, its own arena and its briefing.


func _open(w: int, h: int) -> PackedStringArray:
	var rows := PackedStringArray()
	for y in h:
		rows.append(".".repeat(w))
	return rows


func _soldier(s: GameState, kind: String, at: Vector2i) -> Unit:
	var u := UnitData.make(kind, Types.Team.PLAYER)
	u.owner_player = 0
	return s.add_unit(u, at)


## A Breaker at (7, 3) on open ground facing south, with one trooper (8 tiles south unless moved).
func _fight(rows := PackedStringArray()) -> Dictionary:
	var s := make_blank(rows if not rows.is_empty() else _open(15, 15))
	var t := _soldier(s, "trooper", Vector2i(7, 11))
	s.grid.enemy_spawns.assign([Vector2i(7, 2)])
	Encounter.setup(s, {"boss": "breaker", "node": "boss", "act": 1, "squad": 1})
	var b: Unit = s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "breaker")[0]
	return {"s": s, "b": b, "t": t}


func _enemy_turn(s: GameState, u: Unit) -> void:
	s.phase = Types.Phase.ENEMY
	u.actions_left = Types.ACTIONS_PER_TURN
	for k in u.cooldowns.keys():
		u.cooldowns[k] = max(0, u.cooldowns[k] - 1)
	Encounter.on_unit_turn_start(s, u)
	EnemyAI.take_turn(s, u)
	u.actions_left = 0
	Encounter.on_unit_turn_end(s, u)


func test_the_breaker_is_in_act_1s_pool_with_its_data() -> void:
	assert_true(EnemyRoster.BOSSES.has("breaker") and EnemyRoster.BOSS_POOL[1].has("breaker"), "pooled in act 1")
	assert_true(FightBuilder.BOSS_HEALTH.has("breaker") and StoryData.BOSS_SCENES.has("breaker"), "health table and intro scene")
	assert_true(StoryData.BARKS.has("breaker_2") and StoryData.BARKS.has("breaker_3"), "a bark for each phase change")
	var rolled := {}
	for seed in range(1, 12):
		rolled[EnemyRoster.boss_for(1, seed)] = true
	assert_true(rolled.has("breaker") and rolled.has("brood_mother"), "the seed rolls either")
	assert_true(UnitData.ENEMIES.breaker.get("plate", false), "it wears a front plate")
	var built := FightBuilder.build({"act": 1, "node": "boss", "objective": "boss", "seed": 4, "squad": 2, "boss": "breaker"})
	assert_eq(built.encounter.boss, "breaker")
	assert_true(built.enemies.has("relay"), "the rig brings a Relay mast")
	assert_true(EnemyRoster.pack_of("breaker").has("hound"), "the Automata pack fills its act")


func test_its_act_fights_draw_from_the_automata_pack() -> void:
	var seen := {}
	for seed in range(1, 60):
		for k in FightBuilder.build({"act": 1, "node": "skirmish", "objective": "rescue", "outbreak": 4, "seed": seed, "boss": "breaker"}).enemies:
			seen[EnemyRoster.parse(k).kind] = true
	assert_true(seen.has("hound") or seen.has("loader"), "hounds or loader frames show up in act 1")
	var plain := {}
	for seed in range(1, 60):
		for k in FightBuilder.build({"act": 1, "node": "skirmish", "objective": "rescue", "outbreak": 4, "seed": seed, "boss": "brood_mother"}).enemies:
			plain[EnemyRoster.parse(k).kind] = true
	assert_true(not plain.has("hound") and not plain.has("loader"), "not when the Brood Mother waits")


func test_the_front_plate_takes_three_off_but_a_flank_does_not() -> void:
	var f := _fight()
	var s: GameState = f.s
	var b: Unit = f.b
	var t: Unit = f.t
	t.pos = b.pos + Vector2i(0, 4)
	b.status["facing"] = Vector2i(0, 1)
	var before := b.hp
	Rules.deal_damage(s, b, 5, t)
	assert_eq(before - b.hp, 2, "5 into the plate does 2")
	t.pos = b.pos + Vector2i(0, -4)
	before = b.hp
	Rules.deal_damage(s, b, 5, t)
	assert_eq(before - b.hp, 5, "5 from behind does 5")


func test_three_phases_shed_the_plate_and_hit_harder() -> void:
	var f := _fight()
	var s: GameState = f.s
	var b: Unit = f.b
	var t: Unit = f.t
	b.status.erase("plate")
	Rules.deal_damage(s, b, 999, t)
	assert_eq(int(b.status.boss_phase), 2, "stops at the first gate")
	assert_true(not b.status.get("plate", false) and int(b.status.armour) == 1, "plate gone, a little armour left")
	Rules.deal_damage(s, b, 999, t)
	assert_eq(int(b.status.boss_phase), 3, "stops at the second gate")
	assert_true(not b.status.has("armour"), "stripped")
	assert_true(b.damage.y > UnitData.ENEMIES.breaker.damage[1] and b.mobility > 4, "faster and harder")
	assert_eq(s.log.filter(func(e): return e.type == "boss_phase").size(), 2, "a banner for each")


func test_it_marks_a_lane_and_flattens_the_cover_beside_it() -> void:
	var rows := _open(15, 15)
	for y in [5, 6, 7]:   # a row of low cover on each side of the file it will run down
		rows[y] = rows[y].substr(0, 6) + "=" + "." + "=" + rows[y].substr(9)
	var f := _fight(rows)
	var s: GameState = f.s
	var b: Unit = f.b
	var t: Unit = f.t
	t.pos = Vector2i(7, 9)
	EnemyBehaviours.end_turn(s, b)
	assert_true(b.status.has("charge_dir"), "winds up a lane")
	assert_eq(b.status.charge_dir, Vector2i(0, 1), "down the file at the soldier")
	var telegraphs := s.log.filter(func(e): return e.type == "telegraph" and e.kind == "charge")
	assert_eq(telegraphs.size(), 1, "and tells the view")
	_enemy_turn(s, b)
	assert_eq(b.pos.x, 7, "it ran the lane")
	for y in [5, 6, 7]:
		assert_true(s.grid.tile(Vector2i(6, y)) != Types.Tile.LOW and s.grid.tile(Vector2i(8, y)) != Types.Tile.LOW, "cover beside the lane is gone at row %d" % y)
	assert_true(t.hp < t.max_hp, "and the soldier at the end is hit")


func test_phase_three_winds_up_two_lanes_and_runs_both() -> void:
	var f := _fight()
	var s: GameState = f.s
	var b: Unit = f.b
	var t: Unit = f.t
	b.status.erase("plate")
	b.status["boss_phase"] = 3
	b.damage = Breaker.DAMAGE[3]
	t.pos = Vector2i(7, 9)
	_soldier(s, "marksman", Vector2i(12, 7))
	EnemyBehaviours.end_turn(s, b)
	assert_true(b.status.has("charge_dir") and b.status.has("charge_dir2"), "two lanes marked")
	assert_eq(Breaker.lanes(s, b).size(), 2, "the overlay can draw both")
	var dangers := EnemyIntent.dangers(s).filter(func(d): return d.kind == "charge")
	assert_eq(dangers.size(), 2, "as two red lanes")
	assert_eq(str(EnemyIntent._intent(s, b).label), "DOUBLE CHARGE")
	var seen := s.log.size()
	_enemy_turn(s, b)
	var runs := s.log.slice(seen).filter(func(e): return e.type == "ability" and e.ability == "charge")
	assert_eq(runs.size(), 2, "both runs happen the same turn")


func test_phase_two_rips_rubble_down_on_high_ground() -> void:
	var f := _fight()
	var s: GameState = f.s
	var b: Unit = f.b
	var t: Unit = f.t
	b.status.erase("plate")
	b.status["boss_phase"] = 2
	t.pos = Vector2i(7, 8)
	s.grid.set_level(t.pos, 1)
	b.cooldowns.erase("debris")
	_enemy_turn(s, b)
	var tg: Array = s.encounter.get("telegraphs", []).filter(func(x): return x.kind == "debris")
	assert_eq(tg.size(), 1, "rubble is marked a turn ahead")
	assert_true(tg[0].cells.has(t.pos) and tg[0].get("drop", false), "on the soldier's tile, and it drops raised ground")
	var hp := t.hp
	s.turn += 1
	Encounter._resolve_telegraphs(s)
	assert_true(t.hp < hp, "the rubble hurts")
	assert_eq(s.grid.level(t.pos), 0, "and the high ground comes down")


func test_the_breaker_has_its_own_arena() -> void:
	var data := MapGen._load_biome("wall")
	var own := MapGen._arenas_for(data, "breaker")
	assert_eq(own.size(), 1, "one arena for it")
	assert_eq(str(own[0].boss), "breaker")
	for a in MapGen._arenas_for(data, "brood_mother"):
		assert_true(str(a.get("boss", "")) == "", "the Brood Mother keeps the untagged pit")
	for seed in [1, 2, 3, 4, 5, 6]:
		var g := MapGen.generate({"biome": "wall", "objective": "boss", "seed": seed, "boss": "breaker"})
		assert_eq(MapGen.last_plot, "arena", "seed %d is an arena" % seed)
		var cover := 0
		var raised := 0
		for y in g.height:
			for x in g.width:
				cover += 1 if g.tile(Vector2i(x, y)) == Types.Tile.LOW else 0
				raised += 1 if g.level(Vector2i(x, y)) > 0 else 0
		assert_true(cover >= 20, "cover for the rig to flatten")
		assert_true(raised >= 16, "a gantry to climb")


func test_the_briefing_names_the_rig_when_it_waits() -> void:
	var run := RunRules.new_run(1, 51)
	run.act = 1
	run.map = RunMap.generate(run.rng, 1)
	for n in run.map:
		if n.type == RunMap.BOSS:
			var seed := 1
			while EnemyRoster.boss_for(1, seed) != "breaker":
				seed += 1
			n["seed"] = seed
	assert_eq(run.act_boss(), "breaker")
	var intro := Director.intro_spec(run)
	var plain := StoryData.INTRO_OPENERS.first.size() + StoryData.INTRO_ORDERS.size()
	assert_eq(intro.lines.size(), plain + 1, "one extra line")
	assert_eq(intro.lines[-1][1], StoryData.INTRO_ORDERS[-1][1], "and the mission order still closes it")
