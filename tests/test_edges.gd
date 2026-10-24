extends TestCase
## Edge walls: thin walls, windows, low walls and doorways on the borders between cells. Movement,
## sight, cover, melee, destruction, snapshots and the maps that use them.

# A 3x3 room at (1..3, 1..3): walls all round, a doorway under (2, 3), a window east of (3, 1).
# A low wall east of (4, 0).
const ROWS := [
	"+ + + + + + +",
	" . . . . .:. ",
	"+ +-+-+-+ + +",
	" .|. . .o. . ",
	"+ + + + + + +",
	" .|. . .|. . ",
	"+ + + + + + +",
	" .|. . .|. . ",
	"+ +-+d+-+ + +",
	" . . . . . . ",
	"+ + + + + + +",
]


func _grid() -> Grid:
	return Grid.from_edge_rows(PackedStringArray(ROWS))


func _state() -> GameState:
	var s := GameState.new()
	s.rng.seed = 7
	s.grid = _grid()
	s.players.assign([0])
	s.turn = 1
	Vision.disable(s)
	return s


func test_rows_parse_into_cells_and_edges() -> void:
	var g := _grid()
	assert_eq(Vector2i(g.width, g.height), Vector2i(6, 5), "6x5 cells")
	assert_eq(g.edge(Vector2i(0, 2), Vector2i(1, 0)), Grid.EDGE_WALL, "west wall")
	assert_eq(g.edge(Vector2i(1, 2), Vector2i(-1, 0)), Grid.EDGE_WALL, "same border from the other side")
	assert_eq(g.edge(Vector2i(2, 3), Vector2i(0, 1)), Grid.EDGE_DOOR, "doorway")
	assert_eq(g.edge(Vector2i(3, 1), Vector2i(1, 0)), Grid.EDGE_WINDOW, "window")
	assert_eq(g.edge(Vector2i(4, 0), Vector2i(1, 0)), Grid.EDGE_LOW, "low wall")
	assert_eq(g.edge(Vector2i(2, 2), Vector2i(1, 0)), Grid.EDGE_NONE, "open inside the room")
	assert_eq(g.edges.size(), 13, "12 room borders and a low wall")


func test_movement_respects_edges() -> void:
	var g := _grid()
	assert_eq(g.step_cost(Vector2i(0, 2), Vector2i(1, 0)), -1, "walls block")
	assert_eq(g.step_cost(Vector2i(2, 3), Vector2i(0, 1)), 1, "doorways are free")
	assert_eq(g.step_cost(Vector2i(3, 1), Vector2i(1, 0)), 1 + Grid.VAULT_COST, "climbing through a window")
	assert_eq(g.step_cost(Vector2i(4, 0), Vector2i(1, 0)), 1 + Grid.VAULT_COST, "vaulting a low wall")
	assert_eq(g.step_cost(Vector2i(1, 3), Vector2i(1, 1)), -1, "no diagonal past a wall end")
	assert_eq(g.step_cost(Vector2i(2, 4), Vector2i(1, -1)), -1, "no diagonal through a doorway")
	var path := g.find_path(Vector2i(0, 2), Vector2i(2, 2))
	assert_true(path.size() > 2 and path.has(Vector2i(2, 3)) and path.has(Vector2i(2, 4)), "goes round through the door: %s" % [path])


func test_sight_and_cover() -> void:
	var g := _grid()
	assert_true(not Combat.line_clear(g, Vector2i(0, 2), Vector2i(2, 2)), "walls block sight")
	assert_true(Combat.line_clear(g, Vector2i(5, 1), Vector2i(2, 1)), "windows are see-through")
	assert_true(Combat.line_clear(g, Vector2i(2, 4), Vector2i(2, 2)), "so are doorways")
	assert_true(Combat.line_clear(g, Vector2i(0, 2), Vector2i(2, 2), 1), "a roof looks over a ground-floor wall")
	assert_eq(g.cover_toward(Vector2i(0, 2), Vector2i(1, 0)), Types.Cover.FULL, "wall: full cover")
	assert_eq(g.cover_toward(Vector2i(4, 1), Vector2i(-1, 0)), Types.Cover.HALF, "window: half cover")
	assert_eq(g.cover_toward(Vector2i(5, 0), Vector2i(-1, 0)), Types.Cover.HALF, "low wall: half cover")
	assert_eq(g.cover_toward(Vector2i(2, 4), Vector2i(0, -1)), Types.Cover.NONE, "doorway: none")
	assert_eq(Combat.cover_against(g, Vector2i(0, 2), Vector2i(5, 2)), Types.Cover.FULL, "behind the wall vs a shooter east")
	assert_eq(g.cover_sides(Vector2i(1, 1))[Vector2i(-1, 0)], Types.Cover.FULL, "cover icons see edges")
	assert_true(Combat.peek_cells(g, Vector2i(1, 2)).has(Vector2i(1, 1)), "lean out along an edge wall")


func test_melee_needs_an_open_border() -> void:
	var g := _grid()
	assert_true(not g.touching(Vector2i(0, 2), Vector2i(1, 2)), "no claws through a wall")
	assert_true(g.touching(Vector2i(2, 3), Vector2i(2, 4)), "through a doorway")
	assert_true(g.touching(Vector2i(4, 1), Vector2i(3, 1)), "over a window sill")
	var s := _state()
	var runner := s.add_unit(UnitData.make("runner", Types.Team.ENEMY), Vector2i(0, 2))
	var t := s.add_unit(UnitData.make("trooper", Types.Team.PLAYER), Vector2i(1, 2))
	runner.actions_left = 2
	assert_eq(Rules.validate(s, {"type": Types.ABILITY, "unit": runner.id, "ability": "claw", "target": t.id}), "Not adjacent",
		"claw is refused across the wall")


func test_explosions_breach_edge_walls() -> void:
	var s := _state()
	var k := Grid.edge_key(Vector2i(0, 2), Vector2i(1, 0))
	var before := s.grid.fingerprint()
	Destruction.hit(s, {Vector2i(0, 2): 1})
	assert_eq(s.grid.edges.get(k), Grid.EDGE_WALL, "one hit cracks it")
	assert_eq(s.grid.edge_wear.get(k), 1, "cracked")
	assert_true(s.grid.fingerprint() != before, "the checksum sees the crack")
	Destruction.hit(s, {Vector2i(1, 2): 1})
	assert_true(not s.grid.edges.has(k), "the second hit (from the inside) breaks through")
	assert_eq(s.grid.step_cost(Vector2i(0, 2), Vector2i(1, 0)), 1, "walk through the breach")
	var ev: Dictionary = s.log.filter(func(e): return e.type == "cover_destroyed")[-1]
	assert_true(ev.changes.any(func(ch): return ch.get("edge") == k and ch.kind == "break"), "the view hears about it")
	Destruction.hit(s, {Vector2i(5, 0): 1})
	assert_eq(s.grid.edge(Vector2i(4, 0), Vector2i(1, 0)), Grid.EDGE_NONE, "a low wall goes in one hit")
	Destruction.hit(s, {Vector2i(2, 4): 5})
	assert_eq(s.grid.edge(Vector2i(2, 3), Vector2i(0, 1)), Grid.EDGE_DOOR, "doorways stay")


func test_edges_survive_snapshots() -> void:
	var s := _state()
	Destruction.hit(s, {Vector2i(0, 1): 1})
	var back := GameState.from_dict(s.to_dict())
	assert_eq(back.grid.edges, s.grid.edges, "edges")
	assert_eq(back.grid.edge_wear, s.grid.edge_wear, "wear")
	assert_eq(back.checksum(), s.checksum(), "same checksum")
	assert_eq(Grid.from_dict({"width": 1, "height": 1, "tiles": PackedByteArray([0]), "player_spawns": [], "enemy_spawns": []}).edges,
		{}, "old snapshots load")


func test_generated_maps_have_buildings() -> void:
	for biome in ["wall", "port", "bore"]:
		var with_rooms := 0
		var doors := 0
		for seed in range(1, 21):
			var g := MapGen.generate({"biome": biome, "objective": "skirmish", "seed": seed})
			if g.edges.size() >= 12:
				with_rooms += 1
			doors += g.edges.values().count(Grid.EDGE_DOOR)
			for k in g.edges:
				for c in Grid.edge_cells(k):
					assert_true(g.in_bounds(c), "%s seed %d: edge %s inside the map" % [biome, seed, k])
		assert_true(with_rooms >= 15, "%s: most maps have buildings (%d/20)" % [biome, with_rooms])
		assert_true(doors >= 20, "%s: buildings have doors (%d)" % [biome, doors])


func test_parcel_transforms_carry_edges() -> void:
	var rows := MapGen._double(PackedStringArray(["....", "....", "....", "...."]))
	assert_eq(rows.size(), 9, "plain parcels go double resolution")
	var drawn := PackedStringArray(["+-+ + + +", " . . . . ", "+ + + + +", " . . . . ", "+ + + + +", " . . . . ", "+ + + + +", " . . . . ", "+ + + + +"])
	for t in MapGen.ALL_TRANSFORMS:
		var split := Grid.split_edge_rows(MapGen._transform(drawn, t))
		assert_eq(split.edges.size(), 1, "transform %d keeps the edge" % t)
		var e: Array = split.edges[0]
		var cell: Vector2i = e[0] + (e[1] if e[0].x < 0 or e[0].y < 0 else Vector2i.ZERO)
		assert_true(cell.x in [0, 3] and cell.y in [0, 3], "transform %d: still on a corner cell (%s)" % [t, cell])


func test_lone_pillars_are_gone() -> void:
	# The old maps had ~17 lone wall blocks each; now buildings, edge walls and T-walls do that job.
	for biome in ["wall", "port"]:
		var lone := 0
		for seed in range(1, 21):
			var g := MapGen.generate({"biome": biome, "objective": "hold", "seed": seed})
			for y in g.height:
				for x in g.width:
					var c := Vector2i(x, y)
					if g.tile(c) == Types.Tile.WALL and g.level(c) == 0 \
							and not Grid.DIRS4.any(func(d: Vector2i) -> bool: return g.tile(c + d) == Types.Tile.WALL):
						lone += 1
		assert_true(lone <= 30, "%s: %d lone pillars in 20 maps" % [biome, lone])
