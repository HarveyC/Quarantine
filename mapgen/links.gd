class_name Links
extends RefCounted
## Zipline and cellar tunnel links on a finished map (see Grid.links). A zipline runs one way from a roof
## to the ground or a lower roof; a cellar tunnel joins two ground hatches both ways. Each costs a unit
## one move step however far it goes, and slips free of Parting blows. Pure rules code, its own rng.

const ZIP_SPAN := Vector2i(5, 12)       # Chebyshev distance between the two ends
const TUNNEL_SPAN := Vector2i(9, 24)
const MAX_ZIPS := 2
const ZIP_COST := 1
const TUNNEL_COST := 2
const NAMES := {"zip": "Zipline", "cellar": "Cellar tunnel"}


static func place(g: Grid, rng: RandomNumberGenerator) -> void:
	if g.biome == "" or g.markers.is_empty():
		return
	var busy := {}
	for k in g.markers:
		for c in g.markers[k]:
			busy[c] = true
	for c in g.player_spawns + g.enemy_spawns:
		busy[c] = true
	for c in g.volatile:
		busy[c] = true
	for c in g.water:
		busy[c] = true
	for c in g.rails:
		busy[c] = true
	var ground := _cells(g, busy, false)
	var roofs := _cells(g, busy, true)
	var zips := 0
	for attempt in 30:
		if zips >= MAX_ZIPS or roofs.is_empty():
			break
		var a: Vector2i = roofs[rng.randi() % roofs.size()]
		var options: Array = []
		for b in ground + roofs:
			var span := _span(a, b)
			if span >= ZIP_SPAN.x and span <= ZIP_SPAN.y and g.level(b) < g.level(a) and _clear(g, a, b):
				options.append(b)
		if options.is_empty():
			continue
		var b: Vector2i = options[rng.randi() % options.size()]
		g.add_link(a, b, ZIP_COST, "zip", false)
		for c in [a, b]:
			busy[c] = true
		roofs.erase(a)
		ground.erase(b)
		roofs.erase(b)
		zips += 1
	# One tunnel on most maps, two on the big ones.
	var tunnels := 2 if g.width * g.height >= 800 else 1
	for t in tunnels:
		for attempt in 30:
			if ground.size() < 2:
				break
			var a: Vector2i = ground[rng.randi() % ground.size()]
			var options: Array = []
			for b in ground:
				var span := _span(a, b)
				if span >= TUNNEL_SPAN.x and span <= TUNNEL_SPAN.y:
					options.append(b)
			if options.is_empty():
				continue
			var b: Vector2i = options[rng.randi() % options.size()]
			g.add_link(a, b, TUNNEL_COST, "cellar", true)
			ground.erase(a)
			ground.erase(b)
			break


static func _span(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Open floor cells an end may sit on: no cover, stairs, ladders, markers or spawns, and a free neighbour
## on every side so a hatch or an anchor is never walled in. `raised` picks roof cells, else ground.
static func _cells(g: Grid, busy: Dictionary, raised: bool) -> Array:
	var out: Array = []
	for y in g.height:
		for x in g.width:
			var c := Vector2i(x, y)
			if busy.has(c) or g.tile(c) != Types.Tile.FLOOR or g.stairs.has(c) or g.ladders.has(c) or g.fragile.has(c):
				continue
			if (g.level(c) > 0) != raised:
				continue
			if g.player_spawns.any(func(p: Vector2i) -> bool: return _span(p, c) < 6):
				continue
			if Grid.DIRS4.any(func(d: Vector2i) -> bool: return not g.is_walkable(c + d) or g.stairs.has(c + d) or g.ladders.has(c + d)):
				continue
			out.append(c)
	return out


## The cable may not run through a wall block or anything taller than its upper end.
static func _clear(g: Grid, a: Vector2i, b: Vector2i) -> bool:
	var steps := _span(a, b)
	for i in range(1, steps):
		var p := Vector2(a).lerp(Vector2(b), float(i) / steps)
		var c := Vector2i(roundi(p.x), roundi(p.y))
		if g.tile(c) == Types.Tile.WALL or g.level(c) > g.level(a):
			return false
	return true
