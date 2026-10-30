extends TestCase
## The Bore Engine (Act 3 boss, enemies/bore_engine.gd): sealed behind three coolant valves, each cut
## valve drops its platform, the last one opens the core for a few rounds, then it seals again.


func _open(w: int, h: int) -> PackedStringArray:
	var rows := PackedStringArray()
	for y in h:
		rows.append(".".repeat(w))
	return rows


func _soldier(s: GameState, kind: String, at: Vector2i) -> Unit:
	var u := UnitData.make(kind, Types.Team.PLAYER)
	u.owner_player = 0
	return s.add_unit(u, at)


func _state(squad := 4) -> GameState:
	var s := make_blank(_open(20, 20))
	_soldier(s, "trooper", Vector2i(2, 18))
	_soldier(s, "marksman", Vector2i(5, 18))
	_soldier(s, "medic", Vector2i(14, 18))
	_soldier(s, "breacher", Vector2i(17, 18))
	s.grid.enemy_spawns.assign([Vector2i(10, 2)])
	s.grid.markers = {"boss": [Vector2i(10, 9)]}
	Encounter.setup(s, {"boss": "bore_engine", "node": "boss", "act": 3, "squad": squad})
	return s


func _engine(s: GameState) -> Unit:
	return s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "bore_engine")[0]


func _valves(s: GameState) -> Array:
	return s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "coolant_valve")


func _cut(s: GameState, valve: Unit) -> void:
	Rules.deal_damage(s, valve, 99, s.living(Types.Team.PLAYER)[0])


func test_sealed_behind_three_valves_and_immune() -> void:
	var s := _state()
	var e := _engine(s)
	assert_eq(_valves(s).size(), 3, "three coolant valves")
	assert_eq(e.status.get("tether", ""), "coolant_valve", "tethered to the valves")
	Rules.deal_damage(s, e, 10, s.living(Types.Team.PLAYER)[0])
	assert_eq(e.hp, e.max_hp, "immune while a valve lives")
	for v in _valves(s):
		assert_true(EnemyRoster.is_static(v), "valves are fixed targets")
		assert_true(v.status.has("spawner"), "each valve sends Hounds")


func test_boss_pool_and_health_include_the_engine() -> void:
	assert_true(EnemyRoster.BOSS_POOL[3].has("bore_engine"), "in the Act 3 pool")
	assert_true(EnemyRoster.BOSSES.has("bore_engine"), "a boss kind")
	for squad in [1, 2, 3, 4]:
		var built := FightBuilder.build({"act": 3, "node": "boss", "objective": "boss", "seed": 3, "squad": squad, "boss": "bore_engine"})
		assert_eq(built.encounter.boss, "bore_engine")


func test_a_cut_valve_overloads_marks_its_platform_and_the_last_opens_the_core() -> void:
	var s := _state(2)
	var e := _engine(s)
	var vs := _valves(s)
	for c in EnemyAbilities.square(s.grid, vs[0].pos, 2):
		s.grid.set_level(c, 1)
	_cut(s, vs[0])
	assert_eq(int(e.status.boss_phase), 2, "the first cut overloads it")
	assert_eq(int(e.status.cut), 1)
	var falls: Array = s.encounter.telegraphs.filter(func(t): return t.get("collapse", false))
	assert_eq(falls.size(), 1, "the platform under the valve is marked to fall")
	s.turn += 1
	Encounter.on_enemy_phase_start(s)
	assert_eq(s.grid.level(vs[0].pos), 0, "and it falls a turn later")
	_cut(s, vs[1])
	assert_true(not BoreEngine.is_open(e), "two cut: still sealed")
	_cut(s, vs[2])
	assert_true(BoreEngine.is_open(e), "the last valve opens the core")
	assert_eq(int(e.status.boss_phase), 3)
	assert_eq(e.status.get("tether", "x") != "", true)
	var t := s.living(Types.Team.PLAYER)[0]
	Rules.deal_damage(s, e, 4, t)
	assert_eq(e.hp, e.max_hp - 4, "hits land through the open core")


func test_the_first_window_cannot_be_the_last() -> void:
	var s := _state(4)
	var e := _engine(s)
	for v in _valves(s):
		_cut(s, v)
	var t := s.living(Types.Team.PLAYER)[0]
	Rules.deal_damage(s, e, 999, t)
	assert_eq(e.hp, ceili(e.max_hp * BoreEngine.FIRST_FLOOR), "the first window stops at half")
	assert_true(e.is_alive())
	Rules.deal_damage(s, e, 5, t)
	assert_eq(e.hp, ceili(e.max_hp * BoreEngine.FIRST_FLOOR), "and takes nothing more in that window")


func test_the_core_seals_again_and_the_second_window_kills() -> void:
	var s := _state(4)
	var e := _engine(s)
	for v in _valves(s):
		_cut(s, v)
	var t := s.living(Types.Team.PLAYER)[0]
	Rules.deal_damage(s, e, 999, t)
	var hp := e.hp
	var turns := 0
	while BoreEngine.is_open(e) and turns < 10:
		s.turn += 1
		BoreEngine.take_turn(s, e)
		turns += 1
	assert_eq(turns, BoreEngine.WINDOW[4], "the window lasts its turns")
	assert_true(not BoreEngine.is_open(e), "closed")
	assert_eq(_valves(s).size(), BoreEngine.REGROW[4], "valves grow back")
	assert_eq(e.status.get("tether", ""), "coolant_valve", "tethered again")
	assert_true(e.hp > hp, "it mends a little")
	var sealed: Array = s.log.filter(func(ev): return ev.type == "core_sealed")
	assert_eq(sealed.size(), 1, "the sealing is an event")
	for v in _valves(s):
		_cut(s, v)
	assert_true(BoreEngine.is_open(e), "open again")
	Rules.deal_damage(s, e, 999, t)
	assert_true(not e.is_alive(), "the second window can finish it")
	assert_true(s.encounter.get("over", false), "the fight is over")


func test_pistons_mark_lanes_through_the_squad() -> void:
	var s := _state(4)
	var e := _engine(s)
	s.turn = 1
	e.actions_left = 2
	EnemyBehaviours.custom_turn(s, e)
	var lanes: Array = s.encounter.telegraphs.filter(func(t): return t.kind == "piston")
	assert_eq(lanes.size(), BoreEngine.PISTONS[4], "one lane per piston")
	var catches := 0
	for t in lanes:
		for u in s.living(Types.Team.PLAYER):
			if t.cells.has(u.pos):
				catches += 1
	assert_true(catches >= 1, "the lanes run through soldiers")
	assert_eq(s.encounter.telegraphs.filter(func(t): return t.kind == "bite").size(), 0, "no bite before a valve is cut")
	# Resolve: soldiers on a lane take the piston's damage.
	var before := 0
	for u in s.living(Types.Team.PLAYER):
		before += u.hp
	s.turn = 2
	Encounter.on_enemy_phase_start(s)
	var after := 0
	for u in s.living(Types.Team.PLAYER):
		after += u.hp
	assert_true(after < before, "a piston lands")


func test_it_bites_what_stands_beside_it_once_overloaded() -> void:
	var s := _state(4)
	var e := _engine(s)
	var near := s.living(Types.Team.PLAYER)[0]
	s.grid.set_level(near.pos, 0)
	near.pos = e.pos + Vector2i(1, 1)
	_cut(s, _valves(s)[0])
	s.turn = 3
	e.actions_left = 2
	EnemyBehaviours.custom_turn(s, e)
	var bites: Array = s.encounter.telegraphs.filter(func(t): return t.kind == "bite")
	assert_eq(bites.size(), 1, "the jaws are marked")
	assert_true(bites[0].cells.has(near.pos), "round the soldier beside it")
	assert_true(not bites[0].cells.has(Vector2i(0, 0)), "and no wider than 5x5")


func test_the_arena_is_drawn_for_the_engine_and_valves_sit_on_its_platforms() -> void:
	var arenas: Array = MapGen.parse(FileAccess.get_file_as_string("res://maps/biome_bore.txt")).arenas
	var own: Array = MapGen._arenas_for({"arenas": arenas}, "bore_engine")
	assert_eq(own.size(), 1, "one arena is tagged for the Engine")
	assert_eq(MapGen._arenas_for({"arenas": arenas}, "the_source").size(), arenas.filter(func(a): return a.get("boss", "") == "").size(), "the Source keeps the other arenas")
	for seed in [1, 2, 3, 4, 5, 6]:
		var g := MapGen.generate({"biome": "bore", "objective": "boss", "seed": seed, "boss": "bore_engine"})
		assert_eq(MapGen.last_plot, "arena")
		var b: Vector2i = g.marker("boss")[0]
		var s := make_blank(_open(g.width, g.height))
		s.grid = g
		_soldier(s, "trooper", g.player_spawns[0])
		s.grid.enemy_spawns.assign(g.enemy_spawns)
		Encounter.setup(s, {"boss": "bore_engine", "node": "boss", "act": 3, "squad": 1})
		var e := _engine(s)
		assert_eq(e.pos, b, "the Engine stands on the shaft")
		for v in _valves(s):
			assert_true(g.level(v.pos) > 0, "seed %d: a valve stands on a platform" % seed)
			assert_true(g.is_walkable(v.pos), "and the valve cell is open")
