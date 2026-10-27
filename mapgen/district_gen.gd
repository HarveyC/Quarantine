class_name DistrictGen
extends RefCounted
## Builds a fight map from places instead of stamped parcels: a few streets, then a building, yard,
## camp, container stack or rock cut in every lot. Walls only exist as part of a place (a building's
## ring and partitions, a yard fence, a tent), so nothing stands alone. MapGen finishes the result
## with the same validation as every other layout. Pure rules code; its own RNG, never state.rng.
##
## build() returns {} when the layout could not be made, else
## {"grid", "deploy", "pods", "markers", "reserved"} for MapGen._finish.

## The grid of the last build, kept for dev scripts that draw layouts that failed validation.
static var last_grid: Grid

const SIZE := 28
const COLUMNS := 3
const MIN_BLOCK_W := 6
const MIN_BLOCK_H := 5
const CROSS_STREET := 2
const DEPLOY_TOP := 21                    # the landing yard fills rows 21 to 27 of the middle column
const POD_DIST := Vector2i(8, 24)         # walking distance from the drop zone for pod cells
const MAX_PODS := 5

const WALL := Grid.EDGE_WALL
const WINDOW := Grid.EDGE_WINDOW
const LOW_EDGE := Grid.EDGE_LOW
const DOOR := Grid.EDGE_DOOR
const SHUT := Grid.EDGE_CLOSED

const LOTS := {
	"wall": ["rowhouses", "rowhouses", "rowhouses", "barracks", "barracks", "ruin", "yard", "tents", "rooftop", "plaza"],
	"port": ["warehouse", "warehouse", "warehouse", "containers", "containers", "rowhouses", "rowhouses", "rooftop", "plaza", "yard"],
	"bore": ["rowhouses", "rowhouses", "rockmass", "rockmass", "yard", "rooftop", "ruin", "plaza"],
}
## Each biome has one signature lot that always shows up at least twice.
const SIGNATURE := {"wall": "tents", "port": "containers", "bore": "rockmass"}
const SHUT_DOOR_CHANCE := 0.5
const WINDOW_CHANCE := 0.3


class Ctx:
	var g: Grid
	var rng: RandomNumberGenerator
	var biome: String
	var claimed := {}                     # cells inside any lot, set of Vector2i
	var indoor := {}                      # cells inside a building's rooms
	var places: Array = []                # {"kind": String, "cells": Array[Vector2i]} places an enemy pod or objective may use
	var reserved := {}
	var pod_cells: Array[Vector2i] = []
	var deploy: Array[Vector2i] = []
	var landing := Rect2i()


static func build(biome: String, objective: String, rng: RandomNumberGenerator) -> Dictionary:
	var c := Ctx.new()
	c.biome = biome
	c.rng = rng
	c.g = Grid.new()
	c.g.width = SIZE
	c.g.height = SIZE
	c.g.tiles.resize(SIZE * SIZE)
	c.g.tiles.fill(Types.Tile.FLOOR)

	var street_w: Array[int] = [rng.randi_range(2, 3), rng.randi_range(2, 3)]
	var left := _split(SIZE - street_w[0] - street_w[1], COLUMNS, MIN_BLOCK_W, rng)
	var blocks: Array[Rect2i] = []
	var x := 0
	for i in COLUMNS:
		var x1 := x + left[i] - 1
		if i == 1:
			c.landing = Rect2i(x, DEPLOY_TOP, left[i], SIZE - DEPLOY_TOP)
			blocks.append_array(_column(x, x1, 0, DEPLOY_TOP - CROSS_STREET - 1, [1, 1, 2][rng.randi() % 3], rng))
		else:
			blocks.append_array(_column(x, x1, 0, SIZE - 1, [2, 2, 3][rng.randi() % 3], rng))
		x = x1 + 1 + (street_w[i] if i < COLUMNS - 1 else 0)

	_landing_yard(c)
	var kinds: Array = LOTS[biome].duplicate()
	var types: Array[String] = []
	for b in blocks:
		types.append(kinds[rng.randi() % kinds.size()])
	for want in ["rooftop", "rooftop", SIGNATURE[biome], SIGNATURE[biome]]:
		if types.count(want) < 2:
			var idx: Array[int] = []
			for i in types.size():
				if types[i] != "rooftop" and types[i] != SIGNATURE[biome]:
					idx.append(i)
			if idx.is_empty():
				break
			types[idx[rng.randi() % idx.size()]] = want
	for i in blocks.size():
			_fill_block(c, blocks[i], types[i])
	_street_props(c)
	last_grid = c.g
	var markers := {}
	for k in MapGen.MARKER_KEYS:
		markers[k] = []
	var pods := _place_pods(c)
	if pods.is_empty():
		return {}
	if not _place_objective(c, objective, pods, markers):
		return {}
	return {"grid": c.g, "deploy": c.deploy, "pods": pods, "markers": markers, "reserved": c.reserved}


# ---------------------------------------------------------------- layout

static func _split(total: int, n: int, minimum: int, rng: RandomNumberGenerator) -> Array[int]:
	var out: Array[int] = []
	for i in n:
		out.append(minimum)
	for i in total - minimum * n:
		out[rng.randi() % n] += 1
	return out


## One column of blocks from y0 to y1, `streets` two-tile cross streets between them.
static func _column(x0: int, x1: int, y0: int, y1: int, streets: int, rng: RandomNumberGenerator) -> Array[Rect2i]:
	var heights := _split((y1 - y0 + 1) - CROSS_STREET * streets, streets + 1, MIN_BLOCK_H, rng)
	var out: Array[Rect2i] = []
	var y := y0
	for h in heights:
		out.append(Rect2i(x0, y, x1 - x0 + 1, h))
		y += h + CROSS_STREET
	return out


static func _x1(r: Rect2i) -> int:
	return r.position.x + r.size.x - 1


static func _y1(r: Rect2i) -> int:
	return r.position.y + r.size.y - 1


static func _cells(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(r.position.y, _y1(r) + 1):
		for x in range(r.position.x, _x1(r) + 1):
			out.append(Vector2i(x, y))
	return out


static func _claim(c: Ctx, r: Rect2i) -> void:
	for cell in _cells(r):
		c.claimed[cell] = true


## Edge on a side of a rectangle: side "N" "S" "W" "E", i cells along it.
static func _side_key(r: Rect2i, side: String, i: int) -> Array:
	var x0 := r.position.x
	var y0 := r.position.y
	match side:
		"N": return [x0 + i, y0 - 1, 1]
		"S": return [x0 + i, _y1(r), 1]
		"W": return [x0 - 1, y0 + i, 0]
	return [_x1(r), y0 + i, 0]


static func _side_len(r: Rect2i, side: String) -> int:
	return r.size.x if side == "N" or side == "S" else r.size.y


## The cell just outside a side, at i cells along it.
static func _outside(r: Rect2i, side: String, i: int) -> Vector2i:
	var x0 := r.position.x
	var y0 := r.position.y
	match side:
		"N": return Vector2i(x0 + i, y0 - 1)
		"S": return Vector2i(x0 + i, _y1(r) + 1)
		"W": return Vector2i(x0 - 1, y0 + i)
	return Vector2i(_x1(r) + 1, y0 + i)


static func _set_edge(c: Ctx, k: Array, kind: int) -> void:
	c.g.set_edge(Vector2i(k[0], k[1]), Vector2i(1, 0) if k[2] == 0 else Vector2i(0, 1), kind)


static func _get_edge(c: Ctx, k: Array) -> int:
	return c.g.edge(Vector2i(k[0], k[1]), Vector2i(1, 0) if k[2] == 0 else Vector2i(0, 1))


static func _ring(c: Ctx, r: Rect2i, kind: int, skip := "") -> void:
	for side in ["N", "S", "W", "E"]:
		if skip.contains(side):
			continue
		for i in _side_len(r, side):
			_set_edge(c, _side_key(r, side, i), kind)


static func _is_free(c: Ctx, cell: Vector2i) -> bool:
	return c.g.in_bounds(cell) and c.g.tile(cell) == Types.Tile.FLOOR and c.g.level(cell) == 0 \
		and not c.g.stairs.has(cell) and not c.g.ladders.has(cell)


static func _put(c: Ctx, cell: Vector2i, tile: int) -> void:
	if c.g.in_bounds(cell):
		c.g.tiles[cell.y * c.g.width + cell.x] = tile


## Sides of `r` that face open ground (inside the map and not beyond another building of this lot).
static func _open_sides(c: Ctx, lot: Rect2i, r: Rect2i) -> String:
	var out := ""
	for side in ["N", "S", "W", "E"]:
		var on_lot_side := false
		match side:
			"N": on_lot_side = r.position.y == lot.position.y
			"S": on_lot_side = _y1(r) == _y1(lot)
			"W": on_lot_side = r.position.x == lot.position.x
			"E": on_lot_side = _x1(r) == _x1(lot)
		if on_lot_side and c.g.in_bounds(_outside(r, side, _side_len(r, side) / 2)):
			out += side
	return out


static func _landing_yard(c: Ctx) -> void:
	var r := c.landing
	_ring(c, r, WALL, "S")
	# A three-wide gate to the north street and a doorway in each side wall.
	var gate := c.rng.randi_range(1, maxi(1, r.size.x - 4))
	for i in range(gate, gate + 3):
		_set_edge(c, _side_key(r, "N", i), Grid.EDGE_NONE)
	for side in ["W", "E"]:
		_set_edge(c, _side_key(r, side, c.rng.randi_range(1, r.size.y - 2)), DOOR)
	var cx := r.position.x + r.size.x / 2
	var bottom := _y1(r)
	for dx in [-1, 0]:
		for dy in [-1, 0]:
			c.deploy.append(Vector2i(cx + dx, bottom + dy))
	for dx in [-2, -1, 1, 2]:
		_put(c, Vector2i(cx + dx, r.position.y + 1), Types.Tile.LOW)
	_claim(c, r)
	for cell in c.deploy:
		c.reserved[cell] = true
	c.deploy.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))


static func _fill_block(c: Ctx, b: Rect2i, kind: String) -> void:
	var w := b.size.x
	var h := b.size.y
	if kind != "plaza" and w >= 11 and h >= 7 and c.rng.randf() < 0.6:
		var a := c.rng.randi_range(b.position.x + 5, _x1(b) - 5)
		var gap := c.rng.randi_range(1, 2)
		_fill_lot(c, Rect2i(b.position.x, b.position.y, a - b.position.x, h), kind)
		var other: Array = LOTS[c.biome]
		_fill_lot(c, Rect2i(a + gap, b.position.y, _x1(b) - a - gap + 1, h), other[c.rng.randi() % other.size()])
		return
	if kind != "plaza" and h >= 11 and w >= 7 and c.rng.randf() < 0.5:
		var a2 := c.rng.randi_range(b.position.y + 4, _y1(b) - 4)
		var gap2 := c.rng.randi_range(1, 2)
		_fill_lot(c, Rect2i(b.position.x, b.position.y, w, a2 - b.position.y), kind)
		var other2: Array = LOTS[c.biome]
		_fill_lot(c, Rect2i(b.position.x, a2 + gap2, w, _y1(b) - a2 - gap2 + 1), other2[c.rng.randi() % other2.size()])
		return
	_fill_lot(c, b, kind)


static func _fill_lot(c: Ctx, lot: Rect2i, kind: String) -> void:
	if kind == "yard" or kind == "plaza":
		var inner := Rect2i(lot.position + Vector2i(1, 1), lot.size - Vector2i(2, 2))
		if inner.size.x >= 4 and inner.size.y >= 4:
			lot = inner
	var w := lot.size.x
	var h := lot.size.y
	if w < 4 or h < 4:
		return
	if kind == "plaza" and (w > 7 or h > 7):
		kind = "yard"
		_fill_lot(c, lot, kind)
		return
	match kind:
		"rowhouses": _rowhouses(c, lot)
		"barracks":
			if w >= 9:
				var half := w / 2
				_building(c, Rect2i(lot.position, Vector2i(half - 1, h)), lot, {"depth": 1})
				_building(c, Rect2i(lot.position + Vector2i(half + 1, 0), Vector2i(w - half - 1, h)), lot, {"depth": 1})
			else:
				_building(c, lot, lot, {"depth": 2 if w * h >= 45 else 1})
		"ruin": _building(c, lot, lot, {"depth": 1, "ruin": true})
		"warehouse": _warehouse(c, lot)
		"yard": _yard(c, lot)
		"tents": _tents(c, lot)
		"containers": _containers(c, lot)
		"rockmass":
			if w >= 6 and h >= 5:
				_rockmass(c, lot)
			else:
				_building(c, lot, lot, {"depth": 1})
		"rooftop": _rooftop(c, lot)
		"plaza": _plaza(c, lot)
	_claim(c, lot)


# ---------------------------------------------------------------- places

static func _rowhouses(c: Ctx, lot: Rect2i) -> void:
	var along_x := lot.size.x >= lot.size.y
	var length := lot.size.x if along_x else lot.size.y
	var n := maxi(2, length / 5)
	var cuts := _split(length, n, 4, c.rng)
	var pos := 0
	for cut in cuts:
		var r := Rect2i(lot.position + Vector2i(pos, 0), Vector2i(cut, lot.size.y)) if along_x \
			else Rect2i(lot.position + Vector2i(0, pos), Vector2i(lot.size.x, cut))
		_building(c, r, lot, {"depth": 1 if r.size.x * r.size.y >= 40 else 0})
		pos += cut


## A walled building: ring, rooms split by partitions with doorways, doors to the street, windows.
static func _building(c: Ctx, r: Rect2i, lot: Rect2i, opts: Dictionary) -> Array[Rect2i]:
	var rng := c.rng
	_ring(c, r, WALL)
	var rooms := _bsp(c, r, int(opts.get("depth", 1)))
	var open := _open_sides(c, lot, r)
	var sides: Array[String] = []
	for s in open:
		sides.append(s)
	if sides.is_empty():
		for s in ["N", "S", "W", "E"]:
			if c.g.in_bounds(_outside(r, s, 0)):
				sides.append(s)
	_shuffle(sides, rng)
	var doors := 2 if (sides.size() > 1 and r.size.x * r.size.y >= 24) else 1
	for k in mini(doors, sides.size()):
		var side := sides[k]
		var n := _side_len(r, side)
		var i := rng.randi_range(1, maxi(1, n - 2))
		var width := 2 if bool(opts.get("wide", false)) and n >= 6 else 1
		for d in width:
			var key := _side_key(r, side, mini(i + d, n - 1))
			_set_edge(c, key, SHUT if rng.randf() < SHUT_DOOR_CHANCE else DOOR)
	for side in ["N", "S", "W", "E"]:
		for i in _side_len(r, side):
			var key := _side_key(r, side, i)
			if _get_edge(c, key) == WALL and rng.randf() < float(opts.get("windows", WINDOW_CHANCE)):
				var out := _outside(r, side, i)
				if c.g.in_bounds(out) and c.g.tile(out) != Types.Tile.WALL:
					_set_edge(c, key, WINDOW)
	if bool(opts.get("ruin", false)):
		_breach(c, r, sides)
	for room in rooms:
		for cell in _cells(room):
			c.indoor[cell] = true
		_furnish(c, room)
		c.places.append({"kind": "building", "cells": _open_cells(c, room)})
	_claim(c, r)
	return rooms


static func _open_cells(c: Ctx, r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in _cells(r):
		if _is_free(c, cell):
			out.append(cell)
	return out


static func _bsp(c: Ctx, r: Rect2i, depth: int) -> Array[Rect2i]:
	var rng := c.rng
	var w := r.size.x
	var h := r.size.y
	var x0 := r.position.x
	var y0 := r.position.y
	var out: Array[Rect2i] = []
	if depth == 0 or w * h < 28 or (w < 6 and h < 6):
		out.append(r)
		return out
	if (w >= h and w >= 6) or h < 6:
		var sx := rng.randi_range(x0 + 2, _x1(r) - 3)
		for y in range(y0, _y1(r) + 1):
			c.g.set_edge(Vector2i(sx, y), Vector2i(1, 0), WALL)
		var doors := 2 if h >= 7 and rng.randf() < 0.4 else 1
		var ys: Array[int] = []
		for y in range(y0, _y1(r) + 1):
			ys.append(y)
		_shuffle(ys, rng)
		for k in doors:
			c.g.set_edge(Vector2i(sx, ys[k]), Vector2i(1, 0), DOOR)
		out.append_array(_bsp(c, Rect2i(x0, y0, sx - x0 + 1, h), depth - 1))
		out.append_array(_bsp(c, Rect2i(sx + 1, y0, _x1(r) - sx, h), depth - 1))
		return out
	var sy := rng.randi_range(y0 + 2, _y1(r) - 3)
	for x in range(x0, _x1(r) + 1):
		c.g.set_edge(Vector2i(x, sy), Vector2i(0, 1), WALL)
	var doors2 := 2 if w >= 7 and rng.randf() < 0.4 else 1
	var xs: Array[int] = []
	for x in range(x0, _x1(r) + 1):
		xs.append(x)
	_shuffle(xs, rng)
	for k in doors2:
		c.g.set_edge(Vector2i(xs[k], sy), Vector2i(0, 1), DOOR)
	out.append_array(_bsp(c, Rect2i(x0, y0, w, sy - y0 + 1), depth - 1))
	out.append_array(_bsp(c, Rect2i(x0, sy + 1, w, _y1(r) - sy), depth - 1))
	return out


## Breaks two spans of a building's outer wall and spills rubble (half cover) on both sides.
static func _breach(c: Ctx, r: Rect2i, sides: Array[String]) -> void:
	for pass_i in 2:
		var side: String = sides[c.rng.randi() % sides.size()] if not sides.is_empty() else "N"
		var n := _side_len(r, side)
		if n < 4:
			continue
		var i := c.rng.randi_range(1, n - 3)
		for d in 2:
			var key := _side_key(r, side, i + d)
			var e := _get_edge(c, key)
			if e != WALL and e != WINDOW:
				continue
			_set_edge(c, key, Grid.EDGE_NONE)
			var out := _outside(r, side, i + d)
			if _is_free(c, out) and not c.claimed.has(out):
				_put(c, out, Types.Tile.LOW)
			if d == 0:
				var inside := out + _inward(side)
				if _is_free(c, inside):
					_put(c, inside, Types.Tile.LOW)


static func _inward(side: String) -> Vector2i:
	match side:
		"N": return Vector2i(0, 1)
		"S": return Vector2i(0, -1)
		"W": return Vector2i(1, 0)
	return Vector2i(-1, 0)


## One or two pieces of furniture (half cover) in a corner of a room, never beside a doorway.
static func _furnish(c: Ctx, room: Rect2i) -> void:
	if room.size.x * room.size.y < 9:
		return
	var corners: Array[Vector2i] = [room.position, Vector2i(_x1(room), room.position.y),
		Vector2i(room.position.x, _y1(room)), Vector2i(_x1(room), _y1(room))]
	_shuffle(corners, c.rng)
	var placed := 0
	for cell in corners:
		if placed >= (2 if room.size.x * room.size.y >= 20 else 1):
			break
		if not _is_free(c, cell):
			continue
		var near_door := false
		for d in Grid.DIRS8:
			for e in Grid.DIRS4:
				var k := c.g.edge(cell + d, e)
				if k == DOOR or k == SHUT:
					near_door = true
		if near_door:
			continue
		_put(c, cell, Types.Tile.LOW)
		placed += 1


static func _warehouse(c: Ctx, lot: Rect2i) -> void:
	_building(c, lot, lot, {"depth": 0, "wide": true, "windows": 0.2})
	var inner := Rect2i(lot.position + Vector2i(1, 1), lot.size - Vector2i(2, 2))
	var y := inner.position.y + 1
	while y < _y1(inner):
		var x := inner.position.x + 1
		while x < _x1(inner) - 1:
			if c.rng.randf() < 0.8:
				for d in 2:
					var cell := Vector2i(x + d, y)
					if _is_free(c, cell) and not _near_door(c, cell):
						_put(c, cell, Types.Tile.WALL)
			x += 4
		y += 3


static func _near_door(c: Ctx, cell: Vector2i) -> bool:
	for d in Grid.DIRS8:
		for e in Grid.DIRS4:
			var k := c.g.edge(cell + d, e)
			if k == DOOR or k == SHUT:
				return true
	return false


## A fenced yard: a gate or two, crate stacks against the fence, a small shed.
static func _yard(c: Ctx, lot: Rect2i) -> void:
	var rng := c.rng
	_ring(c, lot, LOW_EDGE)
	var sides: Array[String] = ["N", "S", "W", "E"]
	_shuffle(sides, rng)
	for k in 2:
		var n := _side_len(lot, sides[k])
		var i := rng.randi_range(1, maxi(1, n - 3))
		for d in 2:
			_set_edge(c, _side_key(lot, sides[k], mini(i + d, n - 1)), Grid.EDGE_NONE)
	var inner := Rect2i(lot.position + Vector2i(1, 1), lot.size - Vector2i(2, 2))
	var shed := Rect2i()
	if inner.size.x >= 5 and inner.size.y >= 4:
		var sw := rng.randi_range(3, mini(4, inner.size.x))
		var sh := rng.randi_range(3, mini(4, inner.size.y))
		var sx := inner.position.x if rng.randf() < 0.5 else _x1(inner) - sw + 1
		var sy := inner.position.y if rng.randf() < 0.5 else _y1(inner) - sh + 1
		shed = Rect2i(sx, sy, sw, sh)
		_building(c, shed, shed, {"depth": 0, "windows": 0.15})
	var placed := 0
	for tries in 12:
		if placed >= 3:
			break
		var p := Vector2i(rng.randi_range(inner.position.x, _x1(inner) - 1), rng.randi_range(inner.position.y, _y1(inner)))
		var pair: Array[Vector2i] = [p, p + (Vector2i(1, 0) if rng.randf() < 0.5 else Vector2i(0, 1))]
		var ok := true
		for cell in pair:
			if not inner.has_point(cell) or not _is_free(c, cell) or (shed.size != Vector2i.ZERO and shed.grow(1).has_point(cell)):
				ok = false
		if not ok:
			continue
		var on_edge := pair.any(func(cell: Vector2i) -> bool: return cell.x in [inner.position.x, _x1(inner)] or cell.y in [inner.position.y, _y1(inner)])
		if on_edge or rng.randf() < 0.3:
			for cell in pair:
				_put(c, cell, Types.Tile.WALL)
			placed += 1
	var cells: Array[Vector2i] = []
	for cell in _open_cells(c, lot):
		if not _near_door(c, cell):
			cells.append(cell)
	c.places.append({"kind": "yard", "cells": cells})


## A camp: canvas rooms (low walls all round, one opening, a cot inside) in rows with one-tile aisles.
static func _tents(c: Ctx, lot: Rect2i) -> void:
	var cols := maxi(1, (lot.size.x + 1) / 4)
	var rows := maxi(1, (lot.size.y + 1) / 4)
	var origin := lot.position + Vector2i((lot.size.x - (cols * 4 - 1)) / 2, (lot.size.y - (rows * 4 - 1)) / 2)
	for ty in rows:
		for tx in cols:
			var r := Rect2i(origin + Vector2i(tx * 4, ty * 4), Vector2i(3, 3))
			if not lot.encloses(r):
				continue
			_ring(c, r, LOW_EDGE)
			var side := "S" if c.rng.randf() < 0.5 else "E"
			_set_edge(c, _side_key(r, side, 1), Grid.EDGE_NONE)
			_put(c, r.position, Types.Tile.LOW)
			var cells: Array[Vector2i] = []
			for cell in _cells(r):
				if _is_free(c, cell):
					cells.append(cell)
			c.places.append({"kind": "tent", "cells": cells})
	var open: Array[Vector2i] = []
	for cell in _cells(lot):
		if _is_free(c, cell):
			open.append(cell)
	c.places.append({"kind": "camp", "cells": open})


## Shipping containers in rows with two-tile aisles.
static func _containers(c: Ctx, lot: Rect2i) -> void:
	var rng := c.rng
	var along_x := rng.randf() < 0.5
	var a0 := lot.position.x if along_x else lot.position.y
	var a1 := _x1(lot) if along_x else _y1(lot)
	var b0 := lot.position.y if along_x else lot.position.x
	var b1 := _y1(lot) if along_x else _x1(lot)
	var row := b0 + rng.randi_range(0, 1)
	while row + 1 <= b1:
		var pos := a0 + rng.randi_range(0, 1)
		while pos + 2 <= a1:
			var length := mini([4, 5, 6][rng.randi() % 3] if a1 - a0 >= 7 else [3, 4][rng.randi() % 2], a1 - pos + 1)
			if length >= 3 and rng.randf() < 0.85:
				for t in 2:
					for u in length:
						var cell := Vector2i(pos + u, row + t) if along_x else Vector2i(row + t, pos + u)
						if _is_free(c, cell):
							_put(c, cell, Types.Tile.WALL)
			pos += length + [1, 2, 2][rng.randi() % 3]
		row += 4
	var open: Array[Vector2i] = []
	for cell in _cells(lot):
		if _is_free(c, cell):
			open.append(cell)
	c.places.append({"kind": "stacks", "cells": open})


## A rock cut: solid rock with eroded corners and a two-wide tunnel through it, with a chamber.
static func _rockmass(c: Ctx, lot: Rect2i) -> void:
	var rng := c.rng
	for cell in _cells(lot):
		_put(c, cell, Types.Tile.WALL)
	var x0 := lot.position.x
	var y0 := lot.position.y
	var x1 := _x1(lot)
	var y1 := _y1(lot)
	for corner in [[x0, y0, 1, 1], [x1, y0, -1, 1], [x0, y1, 1, -1], [x1, y1, -1, -1]]:
		var n := rng.randi_range(1, 2)
		for i in n:
			for j in n - i:
				_put(c, Vector2i(corner[0] + corner[2] * i, corner[1] + corner[3] * j), Types.Tile.FLOOR)
	if lot.size.x >= lot.size.y:
		var ty := rng.randi_range(y0 + 1, maxi(y0 + 1, y1 - 2))
		for x in range(x0, x1 + 1):
			for t in 2:
				_put(c, Vector2i(x, mini(ty + t, y1)), Types.Tile.FLOOR)
		if lot.size.x >= 8:
			var cx := rng.randi_range(x0 + 2, x1 - 4)
			for x in range(cx, cx + 3):
				for y in range(ty - 1, ty + 3):
					if y >= y0 and y <= y1:
						_put(c, Vector2i(x, y), Types.Tile.FLOOR)
	else:
		var tx := rng.randi_range(x0 + 1, maxi(x0 + 1, x1 - 2))
		for y in range(y0, y1 + 1):
			for t in 2:
				_put(c, Vector2i(mini(tx + t, x1), y), Types.Tile.FLOOR)
		if lot.size.y >= 8:
			var cy := rng.randi_range(y0 + 2, y1 - 4)
			for y in range(cy, cy + 3):
				for x in range(tx - 1, tx + 3):
					if x >= x0 and x <= x1:
						_put(c, Vector2i(x, y), Types.Tile.FLOOR)
	c.places.append({"kind": "cut", "cells": _open_cells(c, lot)})


## A flat-roofed block you climb: stairs up one face, sometimes a ladder, cover on top, and a
## penthouse (upper roof) on the bigger ones.
static func _rooftop(c: Ctx, lot: Rect2i) -> void:
	var rng := c.rng
	var w := lot.size.x
	var h := lot.size.y
	if w < 5 or h < 4:
		_building(c, lot, lot, {"depth": 1})
		return
	var rw := mini(w, 6)
	var rh := mini(h - 1, 4)
	var rx := lot.position.x + rng.randi_range(0, w - rw)
	var roof := Rect2i(rx, lot.position.y, rw, rh)
	for cell in _cells(roof):
		c.g.set_level(cell, 1)
	var stairs := Vector2i(roof.position.x + rng.randi_range(0, rw - 1), _y1(roof) + 1)
	c.g.stairs[stairs] = true
	c.reserved[stairs] = true
	if rng.randf() < 0.5:
		var ladder := Vector2i(roof.position.x - 1, roof.position.y + rng.randi_range(0, rh - 1))
		if c.g.in_bounds(ladder) and _is_free(c, ladder) and not c.claimed.has(ladder):
			c.g.ladders[ladder] = true
			c.reserved[ladder] = true
	var covers := 0
	for tries in 8:
		if covers >= 2:
			break
		var cell := Vector2i(rng.randi_range(roof.position.x + 1, _x1(roof) - 1), rng.randi_range(roof.position.y + 1, _y1(roof)))
		if c.g.level(cell) == 1 and c.g.tile(cell) == Types.Tile.FLOOR and not c.g.stairs.has(cell):
			_put(c, cell, Types.Tile.LOW)
			covers += 1
	if rw >= 5 and rng.randf() < 0.5:
		var top := roof.position
		c.g.set_level(top, 2)
		c.g.set_level(top + Vector2i(1, 0), 2)
		_put(c, top, Types.Tile.FLOOR)
		_put(c, top + Vector2i(1, 0), Types.Tile.FLOOR)
		var up := top + Vector2i(0, 1)
		_put(c, up, Types.Tile.FLOOR)
		c.g.set_level(up, 1)
		c.g.stairs[up] = true
		c.reserved[up] = true
	for cell in _cells(roof):
		c.reserved[cell] = true
	_claim(c, lot)
	var open: Array[Vector2i] = []
	for cell in _cells(lot):
		if _is_free(c, cell) and not roof.has_point(cell):
			open.append(cell)
	c.places.append({"kind": "apron", "cells": open})


## An open square with something in the middle: sandbags, a crane base, a rail cart.
static func _plaza(c: Ctx, lot: Rect2i) -> void:
	var cx := lot.position.x + lot.size.x / 2
	var cy := lot.position.y + lot.size.y / 2
	match c.biome:
		"port":
			for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				_put(c, Vector2i(cx, cy) + d, Types.Tile.WALL)
			for d in [Vector2i(-2, 1), Vector2i(3, 0)]:
				if _is_free(c, Vector2i(cx, cy) + d):
					_put(c, Vector2i(cx, cy) + d, Types.Tile.LOW)
		"bore":
			for d in [Vector2i(0, 0), Vector2i(1, 0)]:
				_put(c, Vector2i(cx, cy) + d, Types.Tile.WALL)
			for d in [Vector2i(-1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, -1)]:
				if _is_free(c, Vector2i(cx, cy) + d):
					_put(c, Vector2i(cx, cy) + d, Types.Tile.LOW)
		_:
			for dx in range(-2, 3):
				if dx != 0:
					_put(c, Vector2i(cx + dx, cy - 1), Types.Tile.LOW)
			for dy in [0, 1]:
				for dx in [-2, 2]:
					_put(c, Vector2i(cx + dx, cy + dy), Types.Tile.LOW)
	c.places.append({"kind": "square", "cells": _open_cells(c, lot)})


# ---------------------------------------------------------------- streets

## Parked or wrecked vehicles along the curb: two cells of half cover against a wall.
static func _street_props(c: Ctx) -> void:
	var placed := 0
	var tries := 0
	while placed < 6 and tries < 200:
		tries += 1
		var p := Vector2i(c.rng.randi_range(1, SIZE - 4), c.rng.randi_range(1, SIZE - 4))
		var pair: Array[Vector2i] = [p, p + (Vector2i(1, 0) if c.rng.randf() < 0.5 else Vector2i(0, 1))]
		var ok := true
		for cell in pair:
			if c.claimed.has(cell) or not _is_free(c, cell) or c.reserved.has(cell):
				ok = false
		if not ok:
			continue
		var curb := false
		for cell in pair:
			for d in Grid.DIRS4:
				if c.claimed.has(cell + d) and not pair.has(cell + d):
					curb = true
		if not curb:
			continue
		for cell in pair:
			_put(c, cell, Types.Tile.LOW)
		placed += 1


# ---------------------------------------------------------------- pods and objectives

static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func _centre(cells: Array) -> Vector2:
	var sum := Vector2.ZERO
	for cell in cells:
		sum += Vector2(cell)
	return sum / maxi(cells.size(), 1)


## Enemy pods start inside places far enough from the drop zone: rooms, yards, camps, rock cuts.
static func _place_pods(c: Ctx) -> Array:
	var dist := c.g.reachable(c.deploy[0], SIZE * SIZE)
	var cands: Array = []
	for place in c.places:
		var cells: Array[Vector2i] = []
		for cell in place.cells:
			if dist.has(cell) and dist[cell] >= POD_DIST.x and dist[cell] <= POD_DIST.y and not c.reserved.has(cell) \
					and c.g.tile(cell) == Types.Tile.FLOOR and not _near_door(c, cell):
				cells.append(cell)
		if cells.size() >= 3 and place.kind != "apron":
			cands.append({"cells": cells, "centre": _centre(cells)})
	_shuffle(cands, c.rng)
	var pods: Array = []
	var centres: Array[Vector2] = []
	for cand in cands:
		if pods.size() >= MAX_PODS:
			break
		if not centres.all(func(o: Vector2) -> bool: return absf(o.x - cand.centre.x) + absf(o.y - cand.centre.y) >= 8.0):
			continue
		centres.append(cand.centre)
		var cells: Array = cand.cells.duplicate()
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return (Vector2(a) - cand.centre).length() < (Vector2(b) - cand.centre).length())
		var pod: Array[Vector2i] = []
		for k in mini(c.rng.randi_range(2, 3), cells.size()):
			pod.append(cells[k])
			c.pod_cells.append(cells[k])
			c.reserved[cells[k]] = true
		pods.append(pod)
	var total := 0
	var nearest := 1 << 30
	for pod in pods:
		total += pod.size()
		for cell in pod:
			nearest = mini(nearest, dist[cell])
	if pods.size() < 3 or total < MapGen.MIN_ENEMY_SPAWNS or nearest > 20:
		MapGen.last_reject = "pods %d cells %d nearest %d" % [pods.size(), total, nearest]
		return []
	return pods


## Marks the objective's cells. False (with last_reject set) when the map has no room for them.
static func _place_objective(c: Ctx, objective: String, pods: Array, markers: Dictionary) -> bool:
	var dist := c.g.reachable(c.deploy[0], SIZE * SIZE)
	match objective:
		"extract", "escort":
			var spot := _free_block(c, dist, 2, 14, 27, 40)
			if spot.x < 0:
				MapGen.last_reject = "no room for the evac zone"
				return false
			for cell in _block_cells(spot, 2):
				markers.evac.append(cell)
		"hold":
			var spot2 := _free_block(c, dist, 3, 8, 18, 40)
			if spot2.x < 0:
				MapGen.last_reject = "no room for the beacon"
				return false
			for cell in _block_cells(spot2, 3):
				markers.beacon.append(cell)
		"rescue":
			var room := _far_place(c, dist, 10, 24, markers, 5, [], 7)
			if room.is_empty():
				MapGen.last_reject = "no room for civilians"
				return false
			for k in mini(2, room.cells.size()):
				markers.civilian.append(room.cells[k])
		"purge":
			var used: Array[Vector2i] = []
			for k in 3:
				var place := _far_place(c, dist, 8, 27, markers, 5, used)
				if place.is_empty():
					MapGen.last_reject = "no room for nests"
					return false
				markers.nest.append(place.cells[0])
				used.append(place.cells[0])
		"elite":
			var place2 := _far_place(c, dist, 10, 27, markers, 5)
			if place2.is_empty():
				MapGen.last_reject = "no room for the hive"
				return false
			markers.hive.append(place2.cells[0])
		"demolish", "hack", "samples":
			var key: String = MapGen.SITE_MARKER[objective]
			var used2: Array[Vector2i] = []
			for k in 3:
				var place3 := _far_place(c, dist, 8, 27, markers, 6, used2)
				if place3.is_empty():
					MapGen.last_reject = "no room for sites"
					return false
				markers[key].append(place3.cells[0])
				used2.append(place3.cells[0])
	for k in markers:
		for cell in markers[k]:
			c.reserved[cell] = true
	return true


## The best place for a single objective cell: far enough, in a place no pod or marker already uses,
## and at least `apart` from the cells in `used`. Returns {"cells": [...]} (best cell first) or {}.
static func _far_place(c: Ctx, dist: Dictionary, lo: int, hi: int, markers: Dictionary, apart: int, used: Array[Vector2i] = [], pod_gap := 4) -> Dictionary:
	var options: Array = []
	for place in c.places:
		if place.kind == "apron":
			continue
		var cells: Array[Vector2i] = []
		for cell in place.cells:
			if not dist.has(cell) or dist[cell] < lo or dist[cell] > hi or c.reserved.has(cell) or _near_door(c, cell) or _near_pod(c, cell, pod_gap):
				continue
			if used.any(func(u: Vector2i) -> bool: return maxi(absi(u.x - cell.x), absi(u.y - cell.y)) < apart):
				continue
			if c.g.tile(cell) == Types.Tile.FLOOR:
				cells.append(cell)
		if cells.size() >= 2:
			options.append(cells)
	if options.is_empty():
		return {}
	var pick: Array = options[c.rng.randi() % options.size()]
	var anchor: Vector2i = pick[c.rng.randi() % pick.size()]
	var ordered: Array = pick.duplicate()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return maxi(absi(a.x - anchor.x), absi(a.y - anchor.y)) < maxi(absi(b.x - anchor.x), absi(b.y - anchor.y)))
	return {"cells": ordered}


static func _near_pod(c: Ctx, cell: Vector2i, gap: int) -> bool:
	return c.pod_cells.any(func(p: Vector2i) -> bool: return maxi(absi(p.x - cell.x), absi(p.y - cell.y)) < gap)


static func _block_cells(origin: Vector2i, n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in n:
		for dx in n:
			out.append(origin + Vector2i(dx, dy))
	return out


## Top-left of a free n by n block of open ground (no walls or edges through it) between `lo` and
## `hi` steps from the drop zone, picked at random from the candidates; (-1, -1) when there is none.
static func _free_block(c: Ctx, dist: Dictionary, n: int, lo: int, hi: int, _tries: int) -> Vector2i:
	var spots: Array[Vector2i] = []
	for y in SIZE - n + 1:
		for x in SIZE - n + 1:
			var origin := Vector2i(x, y)
			var ok := true
			for cell in _block_cells(origin, n):
				if not _is_free(c, cell) or c.reserved.has(cell) or not dist.has(cell) or dist[cell] < lo or dist[cell] > hi or _near_pod(c, cell, 5):
					ok = false
					break
				for d in [Vector2i(1, 0), Vector2i(0, 1)]:
					if (cell - origin).x + d.x < n and (cell - origin).y + d.y < n and c.g.edge(cell, d) != Grid.EDGE_NONE:
						ok = false
				if not ok:
					break
			if ok:
				spots.append(origin)
	if spots.is_empty():
		return Vector2i(-1, -1)
	return spots[c.rng.randi() % spots.size()]
