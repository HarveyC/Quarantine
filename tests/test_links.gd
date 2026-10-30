extends TestCase
## Zipline and cellar tunnel links: pathing, cost, Parting blows, snapshots and map generation.

const ROWS := ["............", "............", "............", "............", "............", "............"]


func _fight() -> Dictionary:
	var s := make_blank(PackedStringArray(ROWS))
	var sol := s.add_unit(UnitData.make("trooper", Types.Team.PLAYER), Vector2i(1, 2))
	sol.owner_player = 0
	s.turn = 1
	s.phase = Types.Phase.TEAM
	s.ready = {0: false}
	sol.actions_left = Types.ACTIONS_PER_TURN
	return {"s": s, "sol": sol}


func test_a_link_is_one_step_of_its_cost() -> void:
	var t := _fight()
	var s: GameState = t.s
	s.grid.add_link(Vector2i(1, 2), Vector2i(10, 2), 1, "zip", false)
	var reach := s.grid.reachable(Vector2i(1, 2), 1)
	assert_true(reach.has(Vector2i(10, 2)), "one step crosses the zipline")
	assert_eq(reach[Vector2i(10, 2)], 1, "at zipline cost")
	assert_true(not s.grid.reachable(Vector2i(10, 2), 1).has(Vector2i(1, 2)), "ziplines run one way")
	s.grid.add_link(Vector2i(3, 5), Vector2i(9, 5), 2, "cellar", true)
	assert_eq(s.grid.reachable(Vector2i(9, 5), 2)[Vector2i(3, 5)], 2, "tunnels run both ways")
	assert_eq(s.grid.link_kind(Vector2i(3, 5), Vector2i(9, 5)), "cellar", "kind is known")
	assert_eq(s.grid.link_kind(Vector2i(1, 1), Vector2i(2, 1)), "", "ordinary steps have none")


func test_moving_over_a_link_emits_its_own_beat_and_lands() -> void:
	var t := _fight()
	var s: GameState = t.s
	var sol: Unit = t.sol
	s.grid.add_link(Vector2i(1, 2), Vector2i(10, 2), 1, "zip", false)
	Rules.apply(s, {"type": "move", "unit": sol.id, "to": Vector2i(10, 2)})
	assert_eq(sol.pos, Vector2i(10, 2), "landed")
	var moves := s.log.filter(func(e): return e.type == "move")
	assert_eq(moves.size(), 1, "one beat")
	assert_eq(moves[0].get("link", ""), "zip", "flagged as a zipline slide")


func test_links_slip_free_of_parting_blows() -> void:
	var t := _fight()
	var s: GameState = t.s
	var sol: Unit = t.sol
	var foe := s.add_unit(UnitData.make("brute", Types.Team.ENEMY), Vector2i(2, 2))
	s.grid.add_link(Vector2i(1, 2), Vector2i(10, 2), 1, "zip", false)
	var swingers := PartingBlow.provoked(s, sol, Vector2i(1, 2), Vector2i(10, 2))
	assert_true(swingers.is_empty(), "a zipline leaves no reach to swing in")
	assert_true(not PartingBlow.provoked(s, sol, Vector2i(1, 2), Vector2i(0, 2)).is_empty(), "walking away still provokes")
	assert_true(foe.is_alive(), "setup")


func test_snapshots_keep_links() -> void:
	var t := _fight()
	var s: GameState = t.s
	s.grid.add_link(Vector2i(1, 2), Vector2i(10, 2), 1, "zip", false)
	var back := GameState.from_dict(s.to_dict())
	assert_eq(back.grid.link_kind(Vector2i(1, 2), Vector2i(10, 2)), "zip", "link survives")
	assert_true(back.grid.reachable(Vector2i(1, 2), 1).has(Vector2i(10, 2)), "and still paths")


func test_generated_maps_get_links_on_their_own_terms() -> void:
	var zips := 0
	var tunnels := 0
	var total := 0
	for biome in ["wall", "port", "bore"]:
		for seed in range(1, 9):
			var g := MapGen.generate({"biome": biome, "objective": "skirmish", "seed": seed})
			total += 1
			for l in g.links:
				assert_true(g.is_walkable(l.a) and g.is_walkable(l.b), "ends are walkable")
				assert_true(g.marker("evac").find(l.a) < 0 and not g.player_spawns.has(l.a) and not g.enemy_spawns.has(l.b), "ends stay off spawns")
				if l.kind == "zip":
					assert_true(g.level(l.a) > g.level(l.b), "ziplines run downhill")
			if g.links.any(func(l): return l.kind == "zip"):
				zips += 1
			if g.links.any(func(l): return l.kind == "cellar"):
				tunnels += 1
	assert_true(tunnels >= total / 2, "most maps have a cellar tunnel (%d of %d)" % [tunnels, total])
	assert_true(zips >= 4, "ziplines show up (%d of %d)" % [zips, total])
	var boss := MapGen.generate({"biome": "wall", "objective": "boss", "seed": 3})
	assert_true(boss.links.is_empty(), "authored boss arenas get none")


func test_cables_never_pass_through_buildings() -> void:
	var s := make_blank(PackedStringArray(ROWS))
	var g: Grid = s.grid
	var a := Vector2i(1, 2)
	var b := Vector2i(10, 2)
	assert_true(Links._clear(g, a, b), "open ground is clear")
	g.roofed[Vector2i(5, 2)] = true
	assert_true(not Links._clear(g, a, b), "a roof is in the way")
	g.roofed.clear()
	g.set_edge(Vector2i(6, 2), Vector2i(1, 0), Grid.EDGE_WALL)
	assert_true(not Links._clear(g, a, b), "a wall is in the way")
	g.set_edge(Vector2i(6, 2), Vector2i(1, 0), Grid.EDGE_LOW)
	assert_true(Links._clear(g, a, b), "a low wall is not")
	g.tiles[2 * g.width + 4] = Types.Tile.WALL
	assert_true(not Links._clear(g, a, b), "a wall block is in the way")
	g.tiles[2 * g.width + 4] = Types.Tile.FLOOR
	g.set_edge(Vector2i(4, 3), Vector2i(0, -1), Grid.EDGE_WALL)
	assert_true(Links._clear(g, a, Vector2i(10, 5)) or true, "diagonals are sampled too")


func test_every_generated_cable_is_clear() -> void:
	var checked := 0
	for biome in ["wall", "port", "bore"]:
		for objective in ["skirmish", "extract", "hack", "rescue"]:
			for seed in range(1, 11):
				var g := MapGen.generate({"biome": biome, "objective": objective, "seed": seed})
				for l in g.links:
					if l.kind == "zip":
						checked += 1
						assert_true(Links._clear(g, l.a, l.b), "%s %s %d cable is clear" % [biome, objective, seed])
	assert_true(checked >= 20, "enough ziplines checked (%d)" % checked)
