extends TestCase
## Tactical map generator: determinism, validity of every layout, and mission setup on it.

const OBJECTIVES: Array[String] = ["skirmish", "extract", "hold", "rescue", "purge", "elite", "boss", "escort", "demolish", "hack", "samples"]


## One biome per act: The Wall, Port Ardent, The Bore.
const BIOMES: Array[String] = ["wall", "port", "bore"]


func _spec(objective: String, seed: int, biome := "wall") -> Dictionary:
	return {"biome": biome, "objective": objective, "seed": seed}


## The stamped-parcel layout, kept for the plots and the parcel files.
func _plots(objective: String, seed: int, biome := "wall") -> Dictionary:
	return {"biome": biome, "objective": objective, "seed": seed, "layout": "plots"}


func test_same_spec_same_map() -> void:
	for o in OBJECTIVES:
		var a := MapGen.generate(_spec(o, 42))
		var b := MapGen.generate(_spec(o, 42))
		assert_eq(a.to_dict(), b.to_dict(), "%s map is deterministic" % o)


func test_different_seeds_give_different_layouts() -> void:
	var seen := {}
	for seed in range(1, 21):
		seen[MapGen.generate(_spec("skirmish", seed)).tiles] = true
	assert_true(seen.size() >= 18, "20 seeds give at least 18 distinct layouts (got %d)" % seen.size())


## One biome per test method so CI can run the three in parallel shards.
func _every_objective_generates_valid_maps(biome: String) -> void:
	for o in OBJECTIVES:
		for seed in range(1, 41):
			var g := MapGen.generate(_spec(o, seed, biome))
			var tag := "%s %s seed %d" % [biome, o, seed]
			assert_true(not g.markers.is_empty(), tag + " did not fall back to the handmade map")
			if o == "boss":
				assert_true(g.width >= 20 and g.width <= 28 and g.height >= 20 and g.height <= 28, tag + " size")
			else:   # district footprints: square, corner, wide, long and tall
				assert_true(g.width >= 18 and g.width <= 46 and g.height >= 18 and g.height <= 38 and g.width * g.height >= 700, tag + " size")
			assert_eq(g.biome, biome, tag + " biome")
			assert_true(g.player_spawns.size() >= 4, tag + " deploy cells")
			assert_true(g.enemy_spawns.size() >= MapGen.MIN_ENEMY_SPAWNS, tag + " enemy spawns")
			var reach := g.reachable(g.player_spawns[0], 999)
			for c in g.player_spawns + g.enemy_spawns:
				assert_true(reach.has(c), "%s spawn %s reachable" % [tag, c])
			for k in g.markers:
				for c in g.markers[k]:
					assert_true(reach.has(c), "%s marker %s %s reachable" % [tag, k, c])
			for y in g.height:
				for x in g.width:
					if g.is_walkable(Vector2i(x, y)):
						assert_true(reach.has(Vector2i(x, y)), "%s no sealed-off floor" % tag)
			assert_true(g.marker("reinforce").size() >= 4, tag + " reinforcement cells")


func test_every_objective_generates_valid_maps_wall() -> void:
	_every_objective_generates_valid_maps("wall")


func test_every_objective_generates_valid_maps_port() -> void:
	_every_objective_generates_valid_maps("port")


func test_every_objective_generates_valid_maps_bore() -> void:
	_every_objective_generates_valid_maps("bore")


func test_objective_markers() -> void:
	var g := MapGen.generate(_spec("extract", 3))
	assert_eq(g.marker("evac").size(), 4, "2x2 evac zone")
	assert_eq(MapGen.generate(_spec("hold", 3)).marker("beacon").size(), 9, "3x3 beacon")
	var r := MapGen.generate(_spec("rescue", 3))
	assert_true(r.marker("civilian").size() >= 1 and r.marker("civilian").size() <= 2, "1 or 2 civilians")
	assert_eq(r.marker("exit"), r.player_spawns, "rescue exit is the drop zone")
	assert_eq(MapGen.generate(_spec("purge", 3)).marker("nest").size(), 3, "3 nests")
	assert_eq(MapGen.generate(_spec("elite", 3)).marker("hive").size(), 1, "hive node")
	var b := MapGen.generate(_spec("boss", 3))
	assert_eq(b.marker("boss").size(), 1, "one boss anchor")
	var anchor: Vector2i = b.marker("boss")[0]
	assert_true(b.is_walkable(anchor), "boss anchor stands on open ground")
	for biome in BIOMES:
		var arena := MapGen.generate(_spec("boss", 3, biome))
		assert_eq(arena.width, 20, biome + " boss arena is 20x20")
		var a: Vector2i = arena.marker("boss")[0]
		var open := 0
		for d in Grid.DIRS8:
			if arena.is_walkable(a + d):
				open += 1
		assert_true(open >= 5, biome + " arena leaves room around the boss")


func test_boss_arenas_are_authored_per_biome() -> void:
	for biome in BIOMES:
		for seed in range(1, 9):
			var g := MapGen.generate(_spec("boss", seed, biome))
			assert_eq(MapGen.last_plot, "arena", "%s boss seed %d uses its arena" % [biome, seed])
			assert_true(g.player_spawns.size() >= 4 and g.enemy_spawns.size() >= MapGen.MIN_ENEMY_SPAWNS, biome + " arena spawns")
			var a: Vector2i = g.marker("boss")[0]
			assert_true(g.reachable(g.player_spawns[0], 999).has(a), biome + " boss reachable from the drop zone")
	# Hale holds the highest ground: his anchor is the upper roof of the command post.
	assert_eq(MapGen.generate(_spec("boss", 1, "port")).level(MapGen.generate(_spec("boss", 1, "port")).marker("boss")[0]), 2, "Hale starts on the upper roof")


func test_drop_zone_sight_stays_under_the_cap() -> void:
	for biome in BIOMES:
		for o in ["skirmish", "extract", "hold", "hack"]:
			for seed in range(1, 9):
				var g := MapGen.generate(_spec(o, seed, biome))
				assert_true(MapGen.drop_sight(g, g.player_spawns[0]) <= MapGen.DROP_SIGHT_CAP + 0.001, "%s %s seed %d drop zone sight" % [biome, o, seed])


func test_lane_plots_give_three_routes_and_height() -> void:
	var lanes := 0
	var raised := 0.0
	for seed in range(1, 41):
		var g := MapGen.generate(_plots("skirmish", seed, "wall"))
		if MapGen.last_plot.begins_with(MapGen.LANE_PLOT_PREFIX):
			lanes += 1
			raised += (g.levels.size() - g.levels.count(0)) / float(g.levels.size())
	assert_true(lanes >= 15, "lane plots are the usual skirmish map (got %d of 40)" % lanes)
	assert_true(raised / maxi(lanes, 1) >= 0.10, "lane maps carry real height")


func test_pods_sit_inside_two_moves() -> void:
	for seed in range(1, 21):
		var g := MapGen.generate(_spec("skirmish", seed))
		var dist := MapGen._distance_map(g, g.player_spawns)
		var nearest := 1 << 30
		for c in g.enemy_spawns:
			assert_true(dist[c] >= MapGen.POD_STEPS.x, "no enemy spawns next to the squad")
			nearest = mini(nearest, dist[c])
		assert_true(nearest <= MapGen.POD_STEPS.y, "contact within two moves")


func test_streets_between_parcels_stay_open() -> void:
	# Streets are the MIN_LANES-wide strips between parcels: open ground apart from the cordon wall
	# and the odd sandbag line.
	var step := MapGen.PARCEL + MapGen.MIN_LANES
	for biome in BIOMES:
		var street := 0
		var open := 0
		for seed in range(1, 11):
			var g := MapGen.generate(_plots("skirmish", seed, biome))
			for y in g.height:
				for x in g.width:
					if x % step < MapGen.PARCEL and y % step < MapGen.PARCEL:
						continue
					street += 1
					if g.tile(Vector2i(x, y)) == Types.Tile.FLOOR:
						open += 1
		assert_true(open >= street * 0.75, "%s: streets mostly open (%d/%d)" % [biome, open, street])


func test_fights_are_built_from_places() -> void:
	for biome in BIOMES:
		for o in OBJECTIVES:
			if o == "boss":
				continue
			for seed in range(1, 7):
				MapGen.generate(_spec(o, seed, biome))
				assert_eq(MapGen.last_plot, "district", "%s %s seed %d is a district layout" % [biome, o, seed])


## Every wall stands in a building, yard or camp: edges joined at their ends (walls, windows, doorways,
## fences) form pieces of at least four edges, so nothing stands alone.
func test_no_free_standing_wall_pieces() -> void:
	for biome in BIOMES:
		for seed in range(1, 9):
			var g := MapGen.generate(_spec("skirmish", seed, biome))
			var tag := "%s seed %d" % [biome, seed]
			var walls: Array[Vector3i] = []
			for k in g.edges:
				walls.append(k)
			var at_point := {}
			for i in walls.size():
				for p in _edge_ends(walls[i]):
					if not at_point.has(p):
						at_point[p] = []
					at_point[p].append(i)
			var seen := {}
			var doors := 0
			var strays := 0
			for k in g.edges:
				if g.edges[k] == Grid.EDGE_DOOR or g.edges[k] == Grid.EDGE_CLOSED:
					doors += 1
			assert_true(doors >= 4, tag + " has doors (%d)" % doors)
			for i in walls.size():
				if seen.has(i):
					continue
				var size := 0
				var touches_rim := false
				var frontier := [i]
				seen[i] = true
				while not frontier.is_empty():
					var j: int = frontier.pop_back()
					size += 1
					for p in _edge_ends(walls[j]):
						if p.x <= 0 or p.y <= 0 or p.x >= g.width or p.y >= g.height:
							touches_rim = true
						for n in at_point[p]:
							if not seen.has(n):
								seen[n] = true
								frontier.append(n)
				if size < 4 and not touches_rim:
					strays += 1
			# Pieces against the map rim are building walls clipped by the border; the blast walls the
			# drop zone sight cap adds are the only interior strays, and there are few of them.
			assert_true(strays <= 4, "%s: %d short pieces of wall stand alone" % [tag, strays])


## The two lattice points an edge key runs between.
func _edge_ends(k: Vector3i) -> Array[Vector2i]:
	if k.z == 0:
		return [Vector2i(k.x + 1, k.y), Vector2i(k.x + 1, k.y + 1)]
	return [Vector2i(k.x, k.y + 1), Vector2i(k.x + 1, k.y + 1)]


func test_unknown_biome_and_objective_fall_back_to_act_1_skirmish() -> void:
	var g := MapGen.generate({"biome": "moon", "objective": "nonsense", "seed": 5})
	assert_eq(g.biome, "wall", "a biome without a parcel file uses the wall parcels")
	assert_true(g.width >= 16, "skirmish size")


func test_grid_markers_survive_snapshot() -> void:
	var g := MapGen.generate(_spec("hold", 9))
	var back := Grid.from_dict(g.to_dict())
	assert_eq(back.markers, g.markers, "markers")
	assert_eq(back.biome, "wall", "biome")
	var old := g.to_dict()
	old.erase("markers")
	old.erase("biome")
	assert_eq(Grid.from_dict(old).markers, {}, "old snapshots load")


func test_parcel_transforms_keep_tiles() -> void:
	var rows := PackedStringArray(["#...", "....", "....", "...="])
	for t in MapGen.ALL_TRANSFORMS:
		var out := MapGen._transform(rows, t)
		assert_eq("".join(out).count("#"), 1, "transform %d keeps the wall" % t)
		assert_eq("".join(out).count("="), 1, "transform %d keeps the cover" % t)
	assert_eq(MapGen._transform(rows, 4)[0], "...#", "mirror")


func test_mission_starts_on_generated_map() -> void:
	var config := MatchConfig.make(2, 77)
	assert_true(config.has("map_spec"), "matches roll a layout")
	var s := MatchConfig.build(config)
	assert_eq(s.grid.to_dict(), MatchConfig.build(config).grid.to_dict(), "every peer builds the same map")
	assert_eq(s.living(Types.Team.PLAYER).size(), 2, "one soldier per player deployed")
	assert_eq(s.living(Types.Team.ENEMY).size(), config.enemies.size(), "enemies placed")
	for u in s.units:
		assert_true(s.grid.is_walkable(u.pos), "%s on floor" % u.kind)
	Rules.start_mission(s)
	assert_eq(s.phase, Types.Phase.TEAM, "mission runs")


func test_every_map_has_climbable_high_ground() -> void:
	for biome in BIOMES:
		for o in OBJECTIVES:
			for seed in range(1, 11):
				var g := MapGen.generate(_spec(o, seed, biome))
				var tag := "%s %s seed %d" % [biome, o, seed]
				var dist := g.reachable(g.player_spawns[0], 9999)
				var roofs := 0
				for y in g.height:
					for x in g.width:
						if g.level(Vector2i(x, y)) > 0 and dist.has(Vector2i(x, y)):
							roofs += 1
				assert_true(roofs >= 4, tag + " has reachable high ground (got %d)" % roofs)
				for l in g.ladders.keys() + g.stairs.keys():
					assert_true(g.is_walkable(l), tag + " ladder or stairs on open ground")


func test_landmark_plots_place_a_big_building() -> void:
	for biome in ["port", "bore"]:
		var d := MapGen.parse(FileAccess.get_file_as_string("res://maps/biome_%s.txt" % biome))
		assert_true(d.parcels.get("landmark", []).size() >= 3, biome + " has landmark buildings")
		var tall := 0
		for seed in range(1, 31):
			if MapGen.generate(_spec("skirmish", seed, biome)).levels.has(2):
				tall += 1
		assert_true(tall >= 5, "%s upper roofs show up (%d/30)" % [biome, tall])
	var data := MapGen.parse(FileAccess.get_file_as_string("res://maps/biome_wall.txt"))
	assert_true(data.parcels.get("landmark", []).size() >= 3, "act 1 has landmark buildings")
	for lm in data.parcels.landmark:
		# Parcels are kept at double resolution (cells plus the borders between them).
		assert_eq(lm.rows.size(), 17, lm.name + " is 8 rows")
		for r in lm.rows:
			assert_eq(r.length(), 17, lm.name + " is 8 wide")
	var with_l := 0
	for p in data.plots:
		if Array(p.rows).any(func(r: String) -> bool: return r.contains("L")):
			with_l += 1
			assert_eq(p.lanes, 0, p.name + " landmark plots have no lanes")
	assert_true(with_l >= 6, "most objectives have a landmark plot")
	# Some generated maps reach the upper roof level.
	var tall := 0
	for seed in range(1, 31):
		var g := MapGen.generate(_spec("skirmish", seed))
		if g.levels.has(2):
			tall += 1
	assert_true(tall >= 5, "upper roofs show up (%d/30)" % tall)


## One biome per test method so CI can run the three in parallel shards.
func _every_cell_can_walk_back_to_the_drop_zone(biome: String) -> void:
	for o in OBJECTIVES:
		for seed in range(1, 16):
			var g := MapGen.generate(_spec(o, seed, biome))
			var start := g.player_spawns[0]
			var back := MapGen._can_return(g, [start])
			for c in g.reachable(start, 9999):
				assert_true(back.has(c), "%s %s seed %d: %s can get back" % [biome, o, seed, c])


func test_every_cell_can_walk_back_to_the_drop_zone_wall() -> void:
	_every_cell_can_walk_back_to_the_drop_zone("wall")


func test_every_cell_can_walk_back_to_the_drop_zone_port() -> void:
	_every_cell_can_walk_back_to_the_drop_zone("port")


func test_every_cell_can_walk_back_to_the_drop_zone_bore() -> void:
	_every_cell_can_walk_back_to_the_drop_zone("bore")


func test_each_act_has_its_own_parcels() -> void:
	var wall := MapGen.generate(_spec("skirmish", 7, "wall"))
	for biome in ["port", "bore"]:
		var data := MapGen.parse(FileAccess.get_file_as_string("res://maps/biome_%s.txt" % biome))
		var count := 0
		for role in data.parcels:
			count += data.parcels[role].size()
		assert_true(count >= 30, "%s has at least 30 parcels (got %d)" % [biome, count])
		assert_true(data.plots.size() >= 8, "%s has at least 8 plots" % biome)
		for o in OBJECTIVES:
			assert_true(data.plots.any(func(p: Dictionary) -> bool: return p.objectives.has(o)), "%s has a %s plot" % [biome, o])
		assert_true(MapGen.generate(_spec("skirmish", 7, biome)).tiles != wall.tiles, biome + " lays out its own map")
	for act in [1, 2, 3]:
		assert_eq(RunMap.biome(act), BIOMES[act - 1], "act %d biome" % act)
