extends TestCase
## Tactical map generator: determinism, validity of every layout, and mission setup on it.

const OBJECTIVES: Array[String] = ["skirmish", "extract", "hold", "rescue", "purge", "elite", "boss"]


func _spec(objective: String, seed: int) -> Dictionary:
	return {"biome": "wall", "objective": objective, "seed": seed}


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


func test_every_objective_generates_valid_maps() -> void:
	for o in OBJECTIVES:
		for seed in range(1, 41):
			var g := MapGen.generate(_spec(o, seed))
			var tag := "%s seed %d" % [o, seed]
			assert_true(not g.markers.is_empty(), tag + " did not fall back to the handmade map")
			assert_true(g.width >= 16 and g.width <= 20 and g.height >= 16 and g.height <= 20, tag + " size")
			assert_eq(g.biome, "wall", tag + " biome")
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
	assert_eq(b.marker("boss"), [Vector2i(b.width / 2, b.height / 2)], "boss anchor at the centre")
	assert_true(b.is_walkable(Vector2i(b.width / 2 + 2, b.height / 2 - 2)), "open ground around the boss")


func test_pods_sit_inside_two_moves() -> void:
	for seed in range(1, 21):
		var g := MapGen.generate(_spec("skirmish", seed))
		var dist := MapGen._distance_map(g, g.player_spawns)
		var nearest := 1 << 30
		for c in g.enemy_spawns:
			assert_true(dist[c] >= MapGen.POD_STEPS.x, "no enemy spawns next to the squad")
			nearest = mini(nearest, dist[c])
		assert_true(nearest <= MapGen.POD_STEPS.y, "contact within two moves")


func test_unknown_biome_and_objective_fall_back_to_act_1_skirmish() -> void:
	var g := MapGen.generate({"biome": "port", "objective": "nonsense", "seed": 5})
	assert_eq(g.biome, "wall", "port uses the wall parcels until it has its own")
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
	assert_eq(s.living(Types.Team.PLAYER).size(), 4, "squad deployed")
	assert_eq(s.living(Types.Team.ENEMY).size(), config.enemies.size(), "enemies placed")
	for u in s.units:
		assert_true(s.grid.is_walkable(u.pos), "%s on floor" % u.kind)
	Rules.start_mission(s)
	assert_eq(s.phase, Types.Phase.TEAM, "mission runs")


func test_every_map_has_climbable_high_ground() -> void:
	for o in ["skirmish", "extract", "hold", "rescue", "purge", "elite", "boss"]:
		for seed in range(1, 11):
			var g := MapGen.generate(_spec(o, seed))
			var tag := "%s seed %d" % [o, seed]
			var dist := g.reachable(g.player_spawns[0], 9999)
			var roofs := 0
			for y in g.height:
				for x in g.width:
					if g.level(Vector2i(x, y)) > 0 and dist.has(Vector2i(x, y)):
						roofs += 1
			assert_true(roofs >= 4, tag + " has reachable high ground (got %d)" % roofs)
			for l in g.ladders:
				assert_true(g.level(l) == 0 and g.is_walkable(l), tag + " ladder on open ground")
