extends SceneTree
## Dev aid: prints generated maps and how often each objective needs rerolls or falls back.
## godot --headless -s tests/dump_maps.gd -- [objective] [count]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var objectives: Array = ["skirmish", "extract", "hold", "rescue", "purge", "elite", "boss"]
	if args.size() > 0 and args[0] != "all":
		objectives = [args[0]]
	var count := int(args[1]) if args.size() > 1 else 3
	for o in objectives:
		var fallbacks := 0
		for seed in range(1, count + 1):
			var g := MapGen.generate({"biome": "wall", "objective": o, "seed": seed})
			if g.markers.is_empty():
				fallbacks += 1
			if seed <= 2:
				print("%s seed %d (%dx%d)" % [o, seed, g.width, g.height])
				print(render(g))
		print("%s: %d/%d fell back\n" % [o, fallbacks, count])
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
			if g.player_spawns.has(c): ch = "P"
			elif g.enemy_spawns.has(c): ch = "E"
			elif marks.has(c) and marks[c] != "": ch = marks[c]
			out += ch
		out += "\n"
	return out
