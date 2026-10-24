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
		var pillars := 0
		for seed in range(1, count + 1):
			var g := MapGen.generate({"biome": biome, "objective": o, "seed": seed})
			if g.markers.is_empty():
				fallbacks += 1
			pillars += lone_pillars(g)
			if seed <= 2:
				print("%s seed %d (%dx%d)" % [o, seed, g.width, g.height])
				print(render(g))
		print("%s: %d/%d fell back (last reject: %s), lone pillars per map %.1f\n" % [o, fallbacks, count, MapGen.last_reject, pillars / float(count)])
	quit()


## Ground wall tiles with no wall tile beside them: the "random pillar" look.
static func lone_pillars(g: Grid) -> int:
	var n := 0
	for y in g.height:
		for x in g.width:
			var c := Vector2i(x, y)
			if g.tile(c) != Types.Tile.WALL or g.level(c) > 0:
				continue
			if not Grid.DIRS4.any(func(d: Vector2i) -> bool: return g.in_bounds(c + d) and g.tile(c + d) == Types.Tile.WALL):
				n += 1
	return n


static func render(g: Grid) -> String:
	var marks := {}
	for k in g.markers:
		for c in g.markers[k]:
			marks[c] = {"evac": "X", "beacon": "B", "civilian": "C", "exit": "", "nest": "N", "hive": "H", "boss": "S", "reinforce": "r"}[k]
	var cell := {}
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
			cell[c] = ch
	if g.edges.is_empty():
		var out := ""
		for y in g.height:
			for x in g.width:
				out += cell[Vector2i(x, y)]
			out += "\n"
		return out
	# Edge walls: double resolution, borders between cells (| - wall, o window, : low wall, d door).
	var glyph := {Grid.EDGE_WALL: ["|", "-"], Grid.EDGE_WINDOW: ["o", "o"], Grid.EDGE_LOW: [":", ":"], Grid.EDGE_DOOR: ["d", "d"]}
	var lines := ""
	for y in g.height:
		var row := ""
		var under := ""
		for x in g.width:
			var c := Vector2i(x, y)
			row += cell[c]
			var e := g.edge(c, Vector2i(1, 0))
			row += glyph[e][0] if e != Grid.EDGE_NONE else " "
			var sth := g.edge(c, Vector2i(0, 1))
			under += (glyph[sth][1] if sth != Grid.EDGE_NONE else " ") + " "
		lines += row + "\n" + under + "\n"
	return lines
