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
		"player_spawns": player_spawns.duplicate(), "enemy_spawns": enemy_spawns.duplicate()}


static func from_dict(d: Dictionary) -> Grid:
	var g := Grid.new()
	g.width = d.width
	g.height = d.height
	g.tiles = d.tiles
	g.player_spawns.assign(d.player_spawns)
	g.enemy_spawns.assign(d.enemy_spawns)
	return g


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func tile(c: Vector2i) -> int:
	return tiles[c.y * width + c.x] if in_bounds(c) else Types.Tile.WALL


func is_walkable(c: Vector2i) -> bool:
	return tile(c) == Types.Tile.FLOOR


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


func _can_step(from: Vector2i, d: Vector2i, blocked: Dictionary) -> bool:
	var to := from + d
	if not is_walkable(to) or blocked.has(to):
		return false
	# No corner cutting on diagonals.
	if d.x != 0 and d.y != 0:
		return is_walkable(from + Vector2i(d.x, 0)) and is_walkable(from + Vector2i(0, d.y))
	return true


## Cells reachable from `from` within `max_steps` (8-way, each step costs 1).
## `blocked` is a set (Dictionary keys) of occupied cells. Returns {cell: steps}, including `from`.
func reachable(from: Vector2i, max_steps: int, blocked: Dictionary = {}) -> Dictionary:
	var dist := {from: 0}
	var frontier: Array[Vector2i] = [from]
	while not frontier.is_empty():
		var next: Array[Vector2i] = []
		for c in frontier:
			if dist[c] >= max_steps:
				continue
			for d in DIRS8:
				var n := c + d
				if not dist.has(n) and _can_step(c, d, blocked):
					dist[n] = dist[c] + 1
					next.append(n)
		frontier = next
	return dist


## Shortest path from `from` to `to`, excluding `from`. Empty if unreachable.
func find_path(from: Vector2i, to: Vector2i, blocked: Dictionary = {}) -> Array[Vector2i]:
	var parent := {from: from}
	var frontier: Array[Vector2i] = [from]
	while not frontier.is_empty() and not parent.has(to):
		var next: Array[Vector2i] = []
		for c in frontier:
			for d in DIRS8:
				var n := c + d
				if not parent.has(n) and _can_step(c, d, blocked):
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
