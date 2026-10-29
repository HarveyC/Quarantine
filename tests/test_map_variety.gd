extends TestCase
## Map variety: footprints per objective, biome landmarks and skybridge towers.

const BIOMES: Array[String] = ["wall", "port", "bore"]


func test_district_maps_use_every_footprint() -> void:
	var sizes := {}
	for objective in ["skirmish", "extract", "rescue", "hack"]:
		for seed in range(1, 11):
			var g := MapGen.generate({"biome": "wall", "objective": objective, "seed": seed})
			assert_eq(MapGen.last_plot, "district", "%s %d built as a district" % [objective, seed])
			sizes["%dx%d" % [g.width, g.height]] = true
	for k in ["28x28", "38x22", "46x18", "20x38"]:
		assert_true(sizes.has(k), "a %s map appears" % k)


func test_extract_sends_the_squad_across_long_maps() -> void:
	for seed in range(1, 9):
		var g := MapGen.generate({"biome": "port", "objective": "extract", "seed": seed})
		var dist := g.reachable(g.player_spawns[0], g.width * g.height)
		for c in g.markers.evac:
			assert_true(dist[c] >= MapGen.EVAC_MIN_STEPS, "evac is far from the drop on seed %d" % seed)
		if g.width >= 38:
			assert_true(dist[g.markers.evac[0]] >= 20, "long maps make you cross them (seed %d)" % seed)


func test_hack_relays_prefer_rooftops() -> void:
	var on_roofs := 0
	for seed in range(1, 11):
		var g := MapGen.generate({"biome": "port", "objective": "hack", "seed": seed})
		if g.markers.relay.size() == 3 and g.markers.relay.all(func(c: Vector2i) -> bool: return g.level(c) >= 1):
			on_roofs += 1
	assert_true(on_roofs >= 3, "relays sit on rooftops in many hack maps (%d)" % on_roofs)


func test_port_maps_carry_a_gantry() -> void:
	var with := 0
	for seed in range(1, 11):
		var g := MapGen.generate({"biome": "port", "objective": "skirmish", "seed": seed})
		if g.fragile.size() >= 8:
			with += 1
	assert_true(with >= 5, "gantry catwalks show up in most Port Ardent maps (%d of 10)" % with)


func test_towers_bring_level_two_into_most_maps() -> void:
	var with := 0
	for biome in BIOMES:
		for seed in range(1, 7):
			var g := MapGen.generate({"biome": biome, "objective": "skirmish", "seed": seed})
			if g.levels.has(2):
				with += 1
	assert_true(with >= 12, "upper roofs in most maps (%d of 18)" % with)
