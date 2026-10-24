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
## High ground: level per cell (0 ground, 1 raised), row-major like `tiles`. Empty = all ground.
## Change it in a fight only through Elevation.set_level so the view hears about it.
var levels := PackedByteArray()
## Ladder cells (set of Vector2i): the only cells a unit can step between levels from or onto.
var ladders := {}


static func from_rows(rows: PackedStringArray) -> Grid:
	var g := Grid.new()
	g.height = rows.size()
	g.width = rows[0].length()
	g.tiles.resize(g.width * g.height)
	for y in g.height:
		assert(rows[y].length() == g.width, "map row %d has wrong width" % y)
		for x in g.width:
			var t := Types.Tile.FLOOR
			match rows[y][x]:
				"#": t = Types.Tile.WALL
				"=": t = Types.Tile.LOW
				"P": g.player_spawns.append(Vector2i(x, y))
				"E": g.enemy_spawns.append(Vector2i(x, y))
				"^": g.set_level(Vector2i(x, y), 1)
				"%":
					t = Types.Tile.LOW
					g.set_level(Vector2i(x, y), 1)
				"/": g.ladders[Vector2i(x, y)] = true
			g.tiles[y * g.width + x] = t
	return g


## Loads a map text file. Lines starting with ';' and blank lines are ignored.
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
		"levels": levels, "ladders": ladders.keys()}


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


## 0 for ground, 1 for high ground (out of bounds counts as ground).
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


## One step from `from` in direction `d`. Changing level needs a ladder at either end and a
## straight (not diagonal) step, unless `ignore_levels` (leapers, flyers).
func _can_step(from: Vector2i, d: Vector2i, blocked: Dictionary, ignore_levels := false) -> bool:
	var to := from + d
	if not is_walkable(to) or blocked.has(to):
		return false
	var diagonal := d.x != 0 and d.y != 0
	if not ignore_levels and level(from) != level(to):
		if diagonal or not (is_ladder(from) or is_ladder(to)):
			return false
	# No corner cutting on diagonals (nor across a ledge).
	if diagonal:
		var a := from + Vector2i(d.x, 0)
		var b := from + Vector2i(0, d.y)
		if not is_walkable(a) or not is_walkable(b):
			return false
		if not ignore_levels and (level(a) != level(from) or level(b) != level(from)):
			return false
	return true


## Cells reachable from `from` within `max_steps` (8-way, each step costs 1).
## `blocked` is a set (Dictionary keys) of occupied cells. Returns {cell: steps}, including `from`.
## `ignore_levels` lets the walker change level anywhere (see _can_step).
func reachable(from: Vector2i, max_steps: int, blocked: Dictionary = {}, ignore_levels := false) -> Dictionary:
	var dist := {from: 0}
	var frontier: Array[Vector2i] = [from]
	while not frontier.is_empty():
		var next: Array[Vector2i] = []
		for c in frontier:
			if dist[c] >= max_steps:
				continue
			for d in DIRS8:
				var n := c + d
				if not dist.has(n) and _can_step(c, d, blocked, ignore_levels):
					dist[n] = dist[c] + 1
					next.append(n)
		frontier = next
	return dist


## Shortest path from `from` to `to`, excluding `from`. Empty if unreachable.
func find_path(from: Vector2i, to: Vector2i, blocked: Dictionary = {}, ignore_levels := false) -> Array[Vector2i]:
	var parent := {from: from}
	var frontier: Array[Vector2i] = [from]
	while not frontier.is_empty() and not parent.has(to):
		var next: Array[Vector2i] = []
		for c in frontier:
			for d in DIRS8:
				var n := c + d
				if not parent.has(n) and _can_step(c, d, blocked, ignore_levels):
					parent[n] = c
					next.append(n)
		frontier = next
	var path: Array[Vector2i] = []
	if not parent.has(to) or to == from:
		return path
	var c := to
	while c != from:
		path.push_front(c)
		c = parent[c]
	return path
