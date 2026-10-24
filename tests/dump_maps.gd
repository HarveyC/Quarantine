extends SceneTree
## Dev aid: prints generated maps and how often each objective needs rerolls or falls back.
## godot --headless -s tests/dump_maps.gd -- [objective|all] [count] [biome]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var objectives: Array = ["skirmish", "extract", "hold", "rescue", "purge", "elite", "boss"]
	if args.size() > 0 and args[0] != "all":
		objectives = [args[0]]
	var count := int(args[1]) if args.size() > 1 else 3
	var biome: String = args[2] if args.size() > 2 else "wall"
	for o in objectives:
		var fallbacks := 0
		for seed in range(1, count + 1):
			var g := MapGen.generate({"biome": biome, "objective": o, "seed": seed})
			if g.markers.is_empty():
				fallbacks += 1
			if seed <= 2:
				print("%s seed %d (%dx%d)" % [o, seed, g.width, g.height])
				print(render(g))
		print("%s: %d/%d fell back (last reject: %s)\n" % [o, fallbacks, count, MapGen.last_reject])
	quit()


static func render(g: Grid) -> String:
	var marks := {}
	for k in g.markers:
		for c in g.markers[k]:
			marks[c] = {"evac": "X", "beacon": "B", "civilian": "C", "exit": "", "nest": "N", "hive": "H", "boss": "S", "reinforce": "r"}[k]
	var out := ""
	for y in g.height:
		for x in g.width:
			var c := Vector2i(x, y)
			var ch: String = [".", "#", "="][g.tile(c)]
			if g.level(c) == 1 and g.tile(c) != Types.Tile.WALL:
				ch = ("~" if g.is_fragile(c) else "^") if ch == "." else "%"
			elif g.level(c) == 2 and g.tile(c) != Types.Tile.WALL:
				ch = "2" if ch == "." else "$"
			if g.is_ladder(c): ch = "/" if g.level(c) == 0 else "|"
			if g.is_stairs(c): ch = "s" if g.level(c) == 0 else "S"
			if g.player_spawns.has(c): ch = "P"
			elif g.enemy_spawns.has(c): ch = "E"
			elif marks.has(c) and marks[c] != "": ch = marks[c]
			out += ch
		out += "\n"
	return out
