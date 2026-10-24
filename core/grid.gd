class_name Grid
extends RefCounted
## Tile map, cover lookup and pathfinding. Pure data, no nodes.

const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIRS8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var width := 0
var height := 0
var tiles := PackedByteArray()
var player_spawns: Array[Vector2i] = []
var enemy_spawns: Array[Vector2i] = []
## Set by MapGen: the act's look ("wall", "port", "bore"); "" for handmade maps.
var biome := ""
## Set by MapGen: named cells for objectives and spawns, String -> Array of Vector2i
## (see MapGen.MARKER_KEYS). Empty for handmade maps.
var markers := {}
## Set by MapGen: the fight's objective ("skirmish", "extract", ...); "" for handmade maps.
var objective := ""
## High ground: level per cell (0 ground, 1 roof, 2 upper roof), row-major like `tiles`.
## Empty = all ground. Change it in a fight only through Elevation.set_level so the view hears about it.
var levels := PackedByteArray()
## Ladder cells (set of Vector2i): climb one level to an orthogonal neighbour. Climbing costs
## LADDER_COST steps.
var ladders := {}
## Stair cells (set of Vector2i): like ladders, but a normal step (the fast, wide way up).
var stairs := {}
## Fragile raised cells (set of Vector2i): scaffolds and catwalks that explosives collapse.
var fragile := {}

const MAX_LEVEL := 2
## Steps a ladder climb costs (going up or down a ladder).
const LADDER_COST := 2


static func from_rows(rows: PackedStringArray) -> Grid:
	var g := Grid.new()
	g.height = rows.size()
	g.width = rows[0].length()
	g.tiles.resize(g.width * g.height)
	for y in g.height:
		assert(rows[y].length() == g.width, "map row %d has wrong width" % y)
		for x in g.width:
			var c := Vector2i(x, y)
			match rows[y][x]:
				"P": g.player_spawns.append(c)
				"E": g.enemy_spawns.append(c)
			g.tiles[y * g.width + x] = g.read_glyph(c, rows[y][x])
	return g


## Loads a map text file. Lines starting with ';' and blank lines are ignored.
## Applies a map glyph's height layer to `c` (level, ladder, stairs, fragile) and returns its tile.
## Glyphs: # wall, = low cover; ^ roof (L1), % low cover on a roof, ~ fragile roof (scaffold),
## 2 upper roof (L2), $ low cover on L2; / ladder and s stairs on the ground (up to L1),
## | ladder and S stairs on a roof (up to L2). Anything else is ground floor.
func read_glyph(c: Vector2i, ch: String) -> int:
	match ch:
		"#": return Types.Tile.WALL
		"=": return Types.Tile.LOW
		"^": set_level(c, 1)
		"~":
			set_level(c, 1)
			fragile[c] = true
		"%":
			set_level(c, 1)
			return Types.Tile.LOW
		"2": set_level(c, 2)
		"$":
			set_level(c, 2)
			return Types.Tile.LOW
		"/": ladders[c] = true
		"s": stairs[c] = true
		"|":
			set_level(c, 1)
			ladders[c] = true
		"S":
			set_level(c, 1)
			stairs[c] = true
	return Types.Tile.FLOOR


static func load_file(path: String) -> Grid:
	var rows := PackedStringArray()
	for line in FileAccess.get_file_as_string(path).split("\n"):
		line = line.strip_edges()
		if line.is_empty() or line.begins_with(";"):
			continue
		rows.append(line)
	return from_rows(rows)


func to_dict() -> Dictionary:
	return {"width": width, "height": height, "tiles": tiles,
		"player_spawns": player_spawns.duplicate(), "enemy_spawns": enemy_spawns.duplicate(),
		"biome": biome, "markers": markers.duplicate(true), "objective": objective,
		"levels": levels, "ladders": ladders.keys(), "stairs": stairs.keys(), "fragile": fragile.keys()}


static func from_dict(d: Dictionary) -> Grid:
	var g := Grid.new()
	g.width = d.width
	g.height = d.height
	g.tiles = d.tiles
	g.player_spawns.assign(d.player_spawns)
	g.enemy_spawns.assign(d.enemy_spawns)
	g.biome = d.get("biome", "")
	g.markers = d.get("markers", {}).duplicate(true)
	g.objective = d.get("objective", "")
	g.levels = d.get("levels", PackedByteArray())
	for c in d.get("ladders", []):
		g.ladders[c] = true
	for c in d.get("stairs", []):
		g.stairs[c] = true
	for c in d.get("fragile", []):
		g.fragile[c] = true
	return g


## Cells under a marker name, empty if the map has none.
func marker(key: String) -> Array:
	return markers.get(key, [])


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func tile(c: Vector2i) -> int:
	return tiles[c.y * width + c.x] if in_bounds(c) else Types.Tile.WALL


func is_walkable(c: Vector2i) -> bool:
	return tile(c) == Types.Tile.FLOOR


## 0 for ground, 1 for a roof, 2 for an upper roof (out of bounds counts as ground).
func level(c: Vector2i) -> int:
	return levels[c.y * width + c.x] if not levels.is_empty() and in_bounds(c) else 0


## Raw level write for map building. In a fight use Elevation.set_level (emits an event).
func set_level(c: Vector2i, n: int) -> void:
	if not in_bounds(c):
		return
	if levels.is_empty():
		if n == 0:
			return
		levels.resize(width * height)
		levels.fill(0)
	levels[c.y * width + c.x] = n


func is_ladder(c: Vector2i) -> bool:
	return ladders.has(c)


func is_stairs(c: Vector2i) -> bool:
	return stairs.has(c)


func is_fragile(c: Vector2i) -> bool:
	return fragile.has(c)


## Whether the map has any high ground at all.
func has_levels() -> bool:
	return not levels.is_empty() and levels.count(0) < levels.size()


func blocks_los(c: Vector2i) -> bool:
	return tile(c) == Types.Tile.WALL


## Cover provided by the tile at `c` to a unit standing next to it.
func cover_value(c: Vector2i) -> int:
	match tile(c):
		Types.Tile.WALL: return Types.Cover.FULL
		Types.Tile.LOW: return Types.Cover.HALF
	return Types.Cover.NONE


## Cover on each of the 4 sides of `c`, keyed by direction. Used by the view for cover icons.
func cover_sides(c: Vector2i) -> Dictionary:
	var out := {}
	for d in DIRS4:
		if in_bounds(c + d):
			out[d] = cover_value(c + d)
	return out


## Cost of one step from `from` in direction `d`, or -1 if it can't be taken.
## Flat steps cost 1. Changing level must be straight (not diagonal): up one level only from or
## onto stairs (cost 1) or a ladder (LADDER_COST); down the same way, or by dropping off any
## ledge (one way, 1 per level dropped, no damage). `ignore_levels` (leapers, flyers) changes level
## anywhere for 1. Diagonals never cut a wall corner nor a ledge corner.
func step_cost(from: Vector2i, d: Vector2i, blocked: Dictionary = {}, ignore_levels := false) -> int:
	var to := from + d
	if not is_walkable(to) or blocked.has(to):
		return -1
	var diagonal := d.x != 0 and d.y != 0
	if diagonal:
		var a := from + Vector2i(d.x, 0)
		var b := from + Vector2i(0, d.y)
		if not is_walkable(a) or not is_walkable(b):
			return -1
		if not ignore_levels and (level(a) != level(from) or level(b) != level(from) or level(to) != level(from)):
			return -1
		return 1
	var rise := level(to) - level(from)
	if rise == 0 or ignore_levels:
		return 1
	if absi(rise) == 1 and (is_stairs(from) or is_stairs(to)):
		return 1
	if absi(rise) == 1 and (is_ladder(from) or is_ladder(to)):
		return LADDER_COST
	return -rise if rise < 0 else -1


## Compatibility wrapper: whether the step can be taken at all.
func _can_step(from: Vector2i, d: Vector2i, blocked: Dictionary, ignore_levels := false) -> bool:
	return step_cost(from, d, blocked, ignore_levels) > 0


## Cells reachable from `from` within `max_steps` movement (8-way; see step_cost).
## `blocked` is a set (Dictionary keys) of occupied cells. Returns {cell: cost}, including `from`.
## `ignore_levels` lets the walker change level anywhere (see step_cost).
func reachable(from: Vector2i, max_steps: int, blocked: Dictionary = {}, ignore_levels := false) -> Dictionary:
	return _search(from, max_steps, blocked, ignore_levels, Vector2i(-1, -1)).dist


## Cheapest path from `from` to `to`, excluding `from`. Empty if unreachable.
func find_path(from: Vector2i, to: Vector2i, blocked: Dictionary = {}, ignore_levels := false) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if to == from:
		return path
	var r := _search(from, 1 << 20, blocked, ignore_levels, to)
	if not r.parent.has(to):
		return path
	var c := to
	while c != from:
		path.push_front(c)
		c = r.parent[c]
	return path


## Movement cost of walking `path` from `from` (sum of step_cost); -1 if a step is illegal.
func path_cost(from: Vector2i, path: Array[Vector2i], blocked: Dictionary = {}, ignore_levels := false) -> int:
	var total := 0
	var c := from
	for n in path:
		var k := step_cost(c, n - c, blocked, ignore_levels) if maxi(absi(n.x - c.x), absi(n.y - c.y)) == 1 else -1
		if k < 0:
			return -1
		total += k
		c = n
	return total


## Dijkstra with small integer costs (bucket queue). Neighbours are tried in DIRS8 order and
## buckets are FIFO, so results are deterministic on every peer. Stops early once `goal` settles.
func _search(from: Vector2i, max_cost: int, blocked: Dictionary, ignore_levels: bool, goal: Vector2i) -> Dictionary:
	var dist := {from: 0}
	var parent := {from: from}
	var buckets := [[from]]
	var k := 0
	while k < buckets.size():
		var bucket: Array = buckets[k]
		var i := 0
		while i < bucket.size():
			var c: Vector2i = bucket[i]
			i += 1
			if dist[c] != k:
				continue
			if c == goal:
				return {"dist": dist, "parent": parent}
			for d in DIRS8:
				var cost := step_cost(c, d, blocked, ignore_levels)
				if cost < 0:
					continue
				var n := c + d
				var nd := k + cost
				if nd > max_cost or (dist.has(n) and dist[n] <= nd):
					continue
				dist[n] = nd
				parent[n] = c
				while buckets.size() <= nd:
					buckets.append([])
				buckets[nd].append(n)
		k += 1
	return {"dist": dist, "parent": parent}
