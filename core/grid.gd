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
## Set by MapGen for run fights (see Conditions): the fight's map condition ("" for none) and the
## flooded cells it laid down (set). Wading into a flooded cell costs one extra step and fire cannot burn on it.
var condition := ""
var water := {}
## Live rail cells (set) laid by the Live rails condition; Conditions.setup turns them into hazards.
var rails := {}
## Links: jumps that are not a step to a neighbour. A zipline slides one way from a roof anchor to the
## ground or another roof; a cellar tunnel joins two hatches both ways. [{"a", "b", "cost", "kind", "both"}],
## see Links. Pathing treats each as one step of `cost`; a unit that takes one slips free of Parting blows.
var links: Array = []
var _link_from := {}   # cell -> [[to, cost, kind]], built from `links`
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
## Destruction (see Destruction): hits a cell's current layer has taken ({Vector2i: int}; a cracked
## wall or roof), fuel barrels (set; LOW tiles that explode), reinforced walls that never break
## (set), and what broke on a cell ({Vector2i: "heap" | "debris" | "barrel" | "roof" | "scaffold"},
## read by the view for rubble and debris). Change them in a fight only through Destruction.
var wear := {}
var volatile := {}
var hard := {}
var rubble := {}
## Thin walls on the borders between cells (XCOM-style): {Vector3i(x, y, side): EDGE_*}, side 0 is the
## east border of (x, y), side 1 its south border. Read them with edge(c, d); see EDGE_* for the rules.
## `edge_wear` counts hits on a cracked edge wall, keyed the same way (see Destruction).
var edges := {}
var edge_wear := {}
## Ground cells under a building roof (set of Vector2i). The roof is not a level: nobody climbs it.
## It hides the interior from above, so a building's outer walls reach past every viewer (sight_top),
## and the view draws it and cuts it away when a soldier is inside.
var roofed := {}

const MAX_LEVEL := 2
const ROOF_TOP := 9
## Edge kinds. WALL: blocks movement and sight, full cover. WINDOW: a wall with a window, half cover,
## see-through, climbing through costs VAULT_COST extra. LOW: a low wall or railing, same rules as
## WINDOW. DOOR: an open doorway, no cover, nothing blocked (the view draws a frame).
const EDGE_NONE := 0
const EDGE_WALL := 1
const EDGE_WINDOW := 2
const EDGE_LOW := 3
const EDGE_DOOR := 4
## A shut door: blocks sight, movement-free but costs DOOR_COST to open; the first unit through opens it for good (EDGE_DOOR).
const EDGE_CLOSED := 5
const DOOR_COST := 1
## Extra steps to vault a low wall or climb through a window.
const VAULT_COST := 1
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


## A map drawn at double resolution with edge walls (the format MapGen parcels use; see
## maps/biome_wall.txt): rows of 2n+1 characters, cell glyphs at odd (x, y), border glyphs between
## them, corners ignored. Border glyphs: - | # wall, o window, = : low wall, d doorway; anything
## else (space, '.', '+') is open.
static func from_edge_rows(rows: PackedStringArray) -> Grid:
	var split := split_edge_rows(rows)
	var g := from_rows(split.cells)
	for e in split.edges:
		g.set_edge(e[0], e[1], e[2])
	return g


## Splits double-resolution rows into {"cells": PackedStringArray, "edges": [[cell, dir, EDGE_*]]}.
## Each border appears once, as the east or south side of a cell; a parcel's west and north rims
## come out as borders of cells at x = -1 or y = -1 (set_edge drops whatever falls off the map).
static func split_edge_rows(rows: PackedStringArray) -> Dictionary:
	var w := rows[0].length()
	var cells := PackedStringArray()
	var out: Array = []
	for y in range(1, rows.size(), 2):
		var row := ""
		for x in range(1, w, 2):
			row += _at(rows, x, y)
		cells.append(row)
	for y in rows.size():
		for x in w:
			if (x + y) % 2 == 0:
				continue   # a cell or a corner
			var kind := edge_glyph(_at(rows, x, y))
			if kind == EDGE_NONE:
				continue
			if x % 2 == 0:   # a vertical border: east side of cell ((x - 2) / 2, (y - 1) / 2)
				out.append([Vector2i(x / 2 - 1, (y - 1) / 2), Vector2i(1, 0), kind])
			else:            # a horizontal border: south side of cell ((x - 1) / 2, (y - 2) / 2)
				out.append([Vector2i((x - 1) / 2, y / 2 - 1), Vector2i(0, 1), kind])
	return {"cells": cells, "edges": out}


static func _at(rows: PackedStringArray, x: int, y: int) -> String:
	return rows[y][x] if y < rows.size() and x < rows[y].length() else " "


## EDGE_* for a border glyph in a double-resolution map.
static func edge_glyph(ch: String) -> int:
	match ch:
		"-", "|", "#": return EDGE_WALL
		"o": return EDGE_WINDOW
		"=", ":": return EDGE_LOW
		"d": return EDGE_DOOR
		"D": return EDGE_CLOSED
	return EDGE_NONE


## Loads a map text file. Lines starting with ';' and blank lines are ignored.
## Applies a map glyph's height layer to `c` (level, ladder, stairs, fragile) and returns its tile.
## Glyphs: # wall, = low cover; ^ roof (L1), % low cover on a roof, ~ fragile roof (scaffold),
## 2 upper roof (L2), $ low cover on L2; / ladder and s stairs on the ground (up to L1),
## | ladder and S stairs on a roof (up to L2); ! fuel barrel (low cover that explodes), H reinforced
## wall (never breaks). Anything else is ground floor.
func read_glyph(c: Vector2i, ch: String) -> int:
	match ch:
		"#": return Types.Tile.WALL
		"=": return Types.Tile.LOW
		"!":
			volatile[c] = true
			return Types.Tile.LOW
		"H":
			hard[c] = true
			return Types.Tile.WALL
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
	var edges := false
	for line in FileAccess.get_file_as_string(path).split("\n"):
		line = line.trim_suffix("\r")
		if line.strip_edges().is_empty() or line.begins_with(";"):
			continue
		if line == "@edges":   # rows are drawn at double resolution, with thin walls between cells
			edges = true
			continue
		rows.append(line if edges else line.strip_edges())
	return from_edge_rows(rows) if edges else from_rows(rows)


func to_dict() -> Dictionary:
	# Packed arrays are shared by reference: copy them so a snapshot never moves with the live map.
	return {"width": width, "height": height, "tiles": tiles.duplicate(),
		"player_spawns": player_spawns.duplicate(), "enemy_spawns": enemy_spawns.duplicate(),
		"biome": biome, "markers": markers.duplicate(true), "objective": objective,
		"condition": condition, "water": water.keys(), "rails": rails.keys(), "links": links.duplicate(true),
		"levels": levels.duplicate(), "ladders": ladders.keys(), "stairs": stairs.keys(), "fragile": fragile.keys(),
		"wear": wear.duplicate(), "volatile": volatile.keys(), "hard": hard.keys(), "rubble": rubble.duplicate(),
		"edges": edges.duplicate(), "edge_wear": edge_wear.duplicate(), "roofed": roofed.keys()}


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
	g.condition = d.get("condition", "")
	for c in d.get("water", []):
		g.water[c] = true
	for c in d.get("rails", []):
		g.rails[c] = true
	g.links = d.get("links", []).duplicate(true)
	g._index_links()
	g.levels = d.get("levels", PackedByteArray())
	for c in d.get("ladders", []):
		g.ladders[c] = true
	for c in d.get("stairs", []):
		g.stairs[c] = true
	for c in d.get("fragile", []):
		g.fragile[c] = true
	g.wear = d.get("wear", {}).duplicate()
	for c in d.get("volatile", []):
		g.volatile[c] = true
	for c in d.get("hard", []):
		g.hard[c] = true
	g.rubble = d.get("rubble", {}).duplicate()
	g.edges = d.get("edges", {}).duplicate()
	g.edge_wear = d.get("edge_wear", {}).duplicate()
	for c in d.get("roofed", []):
		g.roofed[c] = true
	return g


## Order-independent fingerprint of the terrain (tiles, heights, damage), for online checksums.
func fingerprint() -> int:
	var parts := [tiles.hex_encode(), levels.hex_encode()]
	for group in [ladders, stairs, fragile, volatile, roofed]:
		var keys: Array = group.keys()
		keys.sort()
		parts.append(str(keys))
	var worn: Array = wear.keys()
	worn.sort()
	parts.append(str(worn.map(func(c: Vector2i) -> String: return "%s=%d" % [c, wear[c]])))
	for group in [edges, edge_wear]:
		var keys: Array = group.keys()
		keys.sort()
		parts.append(str(keys.map(func(k: Vector3i) -> String: return "%s=%d" % [k, group[k]])))
	return "|".join(parts).hash()


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


func is_volatile(c: Vector2i) -> bool:
	return volatile.has(c)


## Reinforced: every full wall block. Only the thin edge walls between cells break.
func is_hard(c: Vector2i) -> bool:
	return hard.has(c) or tile(c) == Types.Tile.WALL


## Raw tile write. In a fight, terrain changes go through Destruction (which emits events).
func set_tile(c: Vector2i, t: int) -> void:
	if in_bounds(c):
		tiles[c.y * width + c.x] = t


## Whether the map has any high ground at all.
func has_levels() -> bool:
	return not levels.is_empty() and levels.count(0) < levels.size()


func blocks_los(c: Vector2i) -> bool:
	return tile(c) == Types.Tile.WALL


# ---------------------------------------------------------------- edge walls

## Dictionary key of the border between `c` and its orthogonal neighbour `c + d`.
static func edge_key(c: Vector2i, d: Vector2i) -> Vector3i:
	if d == Vector2i(1, 0):
		return Vector3i(c.x, c.y, 0)
	if d == Vector2i(-1, 0):
		return Vector3i(c.x - 1, c.y, 0)
	if d == Vector2i(0, 1):
		return Vector3i(c.x, c.y, 1)
	if d == Vector2i(0, -1):
		return Vector3i(c.x, c.y - 1, 1)
	return Vector3i(-1, -1, -1)


## The two cells on either side of an edge key.
static func edge_cells(k: Vector3i) -> Array[Vector2i]:
	var a := Vector2i(k.x, k.y)
	return [a, a + (Vector2i(1, 0) if k.z == 0 else Vector2i(0, 1))]


## What stands on the border between `c` and `c + d` (EDGE_*); EDGE_NONE for diagonals.
func edge(c: Vector2i, d: Vector2i) -> int:
	return edges.get(edge_key(c, d), EDGE_NONE) if not edges.is_empty() else EDGE_NONE


## Raw edge write for map building. In a fight, edges change only through Destruction.
func set_edge(c: Vector2i, d: Vector2i, kind: int) -> void:
	var k := edge_key(c, d)
	if k.z < 0 or not in_bounds(c) or not in_bounds(c + d):
		return
	if kind == EDGE_NONE:
		edges.erase(k)
		edge_wear.erase(k)
	else:
		edges[k] = kind


## A solid edge wall stands between `c` and `c + d` (orthogonal).
func edge_blocks_los(c: Vector2i, d: Vector2i) -> bool:
	var e := edge(c, d)
	return e == EDGE_WALL or e == EDGE_CLOSED


## Height an edge wall reaches: one storey above the higher of its two floors.
func edge_top(c: Vector2i, d: Vector2i) -> int:
	return maxi(level(c), level(c + d)) + 1


## Height an edge wall hides things to, for sight: edge_top, but past any viewer where it is the
## outer wall of a roofed building (nobody sees in over a roof).
func sight_top(c: Vector2i, d: Vector2i) -> int:
	if not roofed.is_empty() and roofed.has(c) != roofed.has(c + d):
		return ROOF_TOP
	return edge_top(c, d)


## Cover the border between `c` and `c + d` gives to a unit at `c`.
func edge_cover(c: Vector2i, d: Vector2i) -> int:
	match edge(c, d):
		EDGE_WALL, EDGE_CLOSED: return Types.Cover.FULL
		EDGE_WINDOW, EDGE_LOW: return Types.Cover.HALF
	return Types.Cover.NONE


## Nothing on any of the four borders around the corner a diagonal step from `c` by `d` cuts.
func corner_open(c: Vector2i, d: Vector2i) -> bool:
	if edges.is_empty():
		return true
	var a := Vector2i(d.x, 0)
	var b := Vector2i(0, d.y)
	return edge(c, a) == EDGE_NONE and edge(c, b) == EDGE_NONE \
		and edge(c + d, -a) == EDGE_NONE and edge(c + d, -b) == EDGE_NONE


## Units on `a` and `b` can reach each other in melee: next to each other with no wall between
## (diagonally, at least one way around the corner is free of walls).
func touching(a: Vector2i, b: Vector2i) -> bool:
	var d := b - a
	if maxi(absi(d.x), absi(d.y)) != 1:
		return false
	if d.x == 0 or d.y == 0:
		return not edge_blocks_los(a, d)
	var x := Vector2i(d.x, 0)
	var y := Vector2i(0, d.y)
	var via_x := not blocks_los(a + x) and not edge_blocks_los(a, x) and not edge_blocks_los(a + x, y)
	var via_y := not blocks_los(a + y) and not edge_blocks_los(a, y) and not edge_blocks_los(a + y, x)
	return via_x or via_y


## Units on `a` and `b` can strike each other in melee: `touching`, and on the same level, or one
## level apart across a stair step (straight, like walking it). A diagonal needs both on the same
## level with a corner around it no higher than them. Ladders and ledges don't count: a claw
## can't reach a roof from the ground below it.
func melee_reach(a: Vector2i, b: Vector2i) -> bool:
	if not touching(a, b):
		return false
	var la := level(a)
	var lb := level(b)
	var d := b - a
	if d.x == 0 or d.y == 0:
		return la == lb or (absi(la - lb) == 1 and (is_stairs(a) or is_stairs(b)))
	if la != lb:
		return false
	var x := a + Vector2i(d.x, 0)
	var y := a + Vector2i(0, d.y)
	return (level(x) <= la and not blocks_los(x) and not edge_blocks_los(a, Vector2i(d.x, 0))
			and not edge_blocks_los(x, Vector2i(0, d.y))) \
		or (level(y) <= la and not blocks_los(y) and not edge_blocks_los(a, Vector2i(0, d.y))
			and not edge_blocks_los(y, Vector2i(d.x, 0)))


## Cover a unit at `c` gets on its side `d` (orthogonal): the tile there or the edge between.
func cover_toward(c: Vector2i, d: Vector2i) -> int:
	return maxi(cover_value(c + d), edge_cover(c, d))


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
			out[d] = cover_toward(c, d)
	return out


## Cost of one step from `from` in direction `d`, or -1 if it can't be taken.
## Flat steps cost 1. Changing level must be straight (not diagonal): up one level only from or
## onto stairs (cost 1) or a ladder (LADDER_COST); down the same way, or by dropping off any
## ledge (one way, 1 per level dropped, no damage). `ignore_levels` (leapers, flyers) changes level
## anywhere for 1. Diagonals never cut a wall corner nor a ledge corner, nor pass any edge.
## Edge walls block; vaulting a low wall or a window costs VAULT_COST extra; doorways are free and a
## shut door costs DOOR_COST extra to open.
## `climb` (Hydraulic legs) takes ladders for a normal step.
func step_cost(from: Vector2i, d: Vector2i, blocked: Dictionary = {}, ignore_levels := false, climb := false) -> int:
	var to := from + d
	if not is_walkable(to) or blocked.has(to):
		return -1
	var wade := 1 if water.has(to) else 0
	var diagonal := d.x != 0 and d.y != 0
	if diagonal:
		var a := from + Vector2i(d.x, 0)
		var b := from + Vector2i(0, d.y)
		if not is_walkable(a) or not is_walkable(b) or not corner_open(from, d):
			return -1
		if not ignore_levels and (level(a) != level(from) or level(b) != level(from) or level(to) != level(from)):
			return -1
		return 1 + wade
	var extra := wade
	match edge(from, d):
		EDGE_WALL: return -1
		EDGE_WINDOW, EDGE_LOW: extra = VAULT_COST
		EDGE_CLOSED: extra = DOOR_COST
	var rise := level(to) - level(from)
	if rise == 0 or ignore_levels:
		return 1 + extra
	if absi(rise) == 1 and (is_stairs(from) or is_stairs(to)):
		return 1 + extra
	if absi(rise) == 1 and (is_ladder(from) or is_ladder(to)):
		return (1 if climb else LADDER_COST) + extra
	return -rise + extra if rise < 0 else -1


## Adds a link between two cells (see `links`); `both` makes it usable either way.
func add_link(a: Vector2i, b: Vector2i, cost: int, kind: String, both: bool) -> void:
	links.append({"a": a, "b": b, "cost": cost, "kind": kind, "both": both})
	_index_links()


func _index_links() -> void:
	_link_from.clear()
	for l in links:
		if not _link_from.has(l.a):
			_link_from[l.a] = []
		_link_from[l.a].append([l.b, l.cost, l.kind])
		if l.both:
			if not _link_from.has(l.b):
				_link_from[l.b] = []
			_link_from[l.b].append([l.a, l.cost, l.kind])


## The links leaving `c`: [[to, cost, kind]], empty for most cells.
func links_from(c: Vector2i) -> Array:
	return _link_from.get(c, [])


## The link kind of the jump from `a` to `b` ("" when it is an ordinary step).
func link_kind(a: Vector2i, b: Vector2i) -> String:
	for l in links_from(a):
		if l[0] == b:
			return l[2]
	return ""


## Compatibility wrapper: whether the step can be taken at all.
func _can_step(from: Vector2i, d: Vector2i, blocked: Dictionary, ignore_levels := false) -> bool:
	return step_cost(from, d, blocked, ignore_levels) > 0


## Cells reachable from `from` within `max_steps` movement (8-way; see step_cost).
## `blocked` is a set (Dictionary keys) of occupied cells. Returns {cell: cost}, including `from`.
## `ignore_levels` lets the walker change level anywhere (see step_cost).
func reachable(from: Vector2i, max_steps: int, blocked: Dictionary = {}, ignore_levels := false, climb := false) -> Dictionary:
	return _search(from, max_steps, blocked, ignore_levels, Vector2i(-1, -1), climb).dist


## Cheapest path from `from` to `to`, excluding `from`. Empty if unreachable.
func find_path(from: Vector2i, to: Vector2i, blocked: Dictionary = {}, ignore_levels := false, climb := false) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if to == from:
		return path
	var r := _search(from, 1 << 20, blocked, ignore_levels, to, climb)
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
func _search(from: Vector2i, max_cost: int, blocked: Dictionary, ignore_levels: bool, goal: Vector2i, climb := false) -> Dictionary:
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
				var cost := step_cost(c, d, blocked, ignore_levels, climb)
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
			for l in links_from(c):
				var to: Vector2i = l[0]
				var ld: int = k + int(l[1])
				if ld > max_cost or not is_walkable(to) or blocked.has(to) or (dist.has(to) and dist[to] <= ld):
					continue
				dist[to] = ld
				parent[to] = c
				while buckets.size() <= ld:
					buckets.append([])
				buckets[ld].append(to)
		k += 1
	return {"dist": dist, "parent": parent}
