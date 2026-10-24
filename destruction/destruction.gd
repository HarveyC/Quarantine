class_name Destruction
extends RefCounted
## Destructible terrain: cover that breaks in steps, walls and roofs that come down, fuel barrels
## and the explosions that do it. Pure rules code; the damage state lives on the Grid (wear,
## volatile, hard, rubble) so it is saved, synced and checksummed with the map.
## See docs/ARCHITECTURE.md, "Destruction", and the study page linked there.
##
## Terrain takes "hits" (never bullets: only explosives, airstrikes and smashing enemies):
##   wall           WALL_HITS hits -> rubble heap (half cover, see-through) -> 1 more -> floor
##   half cover     1 hit -> floor (debris)
##   fuel barrel    1 hit -> explodes (BARREL_*), then floor
##   roof cell      ROOF_HITS per level -> drops one level and becomes a rubble ramp (stairs)
##   scaffold       1 hit -> drops to the ground (Elevation's old blast rule)
##   hard / edge    never (the map's own rim)
##   edge wall      WALL_HITS hits -> gone (a breach; windows the same), low wall 1 hit, doorways never.
##                  A border takes the larger of the hits on the two cells beside it.
## Hits beyond what breaks a layer carry into the next one (a demo charge goes straight through a
## wall). Units on a cell that drops fall: Elevation.FALL_DAMAGE_PER_LEVEL a level.
##
## Determinism: no dice. Cells resolve in row-major order, barrels set off in a chain resolve
## breadth-first in the order they were hit, so every peer gets the same board.

const WALL_HITS := 2
const ROOF_HITS := 2
const NOISE_RADIUS := 6.0

## Explosion profiles: radius, hits on the centre cell, hits on the ring, damage to units.
const FRAG := {"radius": 1, "centre": 1, "ring": 1, "damage": 3}
const DEMO := {"radius": 1, "centre": 3, "ring": 1, "damage": 3}
const BARREL := {"radius": 1, "centre": 2, "ring": 1, "damage": 3}
const BARREL_FIRE_TURNS := 2
## Demo charge reach (Chebyshev): placed on an adjacent tile or wall.
const DEMO_RANGE := 1
const SHOOT_BARREL := {"name": "Shoot barrel", "targeting": "cell", "cost": -1, "cooldown": 0,
	"desc": "Shoot a fuel barrel you can see. It always hits: 3 damage and fire around it, and it sets off barrels next to it. Ends turn."}

## Set while a barrel's own fire is placed, so that fire does not set off barrels a second ring out
## (a barrel's chain reaches as far as its blast, no further).
static var _barrel_fire := false


# --- Queries ---------------------------------------------------------------------------------

## Whether explosives can damage the tile at `c` at all.
static func breakable(g: Grid, c: Vector2i) -> bool:
	if not g.in_bounds(c) or g.is_hard(c):
		return false
	if g.tile(c) == Types.Tile.WALL and (c.x == 0 or c.y == 0 or c.x == g.width - 1 or c.y == g.height - 1):
		return false   # the map's own edge
	return g.tile(c) != Types.Tile.FLOOR or g.level(c) > 0


## Hits per cell for an explosion profile at `center` (Chebyshev radius).
static func pattern(g: Grid, center: Vector2i, p: Dictionary) -> Dictionary:
	var out := {}
	var r: int = p.radius
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := center + Vector2i(dx, dy)
			if g.in_bounds(c):
				out[c] = int(p.centre) if c == center else int(p.ring)
	return out


## What `hits` would do, without changing anything: {cell: "crack" | "break" | "clear" |
## "drop" | "barrel"} for every cell that would change (a chain's extra barrels included).
## Used by the aim preview, the balance bot and tests. Same rules as apply via a scratch grid.
static func preview(s: GameState, hits: Dictionary) -> Dictionary:
	var g := Grid.from_dict(s.grid.to_dict())
	var out := {}
	var queue: Array[Vector2i] = []
	_preview_hits(g, hits, out, queue)
	var i := 0
	while i < queue.size():
		var b := queue[i]
		i += 1
		_preview_hits(g, pattern(g, b, BARREL), out, queue)
	return out


static func _preview_hits(g: Grid, hits: Dictionary, out: Dictionary, queue: Array[Vector2i]) -> void:
	for c in _sorted(hits.keys()):
		var r := _hit_cell(g, c, int(hits[c]))
		if r.barrel:
			queue.append(c)
			out[c] = "barrel"
		elif r.dropped > 0:
			out[c] = "drop"
		elif r.changed and not out.has(c):
			out[c] = r.kind


## Units an explosion of profile `p` at `center` would hurt, in id order.
static func units_in(s: GameState, center: Vector2i, p: Dictionary, spare: Unit = null) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in s.living():
		if u != spare and _cheb(u.pos, center) <= int(p.radius):
			out.append(u)
	return out


# --- Explosions --------------------------------------------------------------------------------

## A blast of profile `p` (FRAG, DEMO, BARREL) at `center`: emits "explosion", hurts units in the
## area (not `spare`), wakes dormant Infected nearby, then breaks terrain. `by` is credited with
## kills and set-off barrels. `kind` is for the view ("frag", "demo", "barrel", ...).
static func explode(s: GameState, center: Vector2i, p: Dictionary, by: Unit, kind: String, spare: Unit = null) -> void:
	var hurt := units_in(s, center, p, spare)
	s.emit({"type": "explosion", "kind": kind, "cell": center, "radius": int(p.radius),
		"unit": by.id if by != null else -1, "units": hurt.map(func(u: Unit) -> int: return u.id),
		"damage": int(p.damage), "level": s.grid.level(center)})
	for u in hurt:
		Rules.deal_damage(s, u, int(p.damage), by)
	noise(s, center)
	hit(s, pattern(s.grid, center, p), by)


## Dormant Infected within NOISE_RADIUS of `at` wake up (and alert their pods).
static func noise(s: GameState, at: Vector2i) -> void:
	for u in s.living(Types.Team.ENEMY):
		if not EnemyAI.is_alerted(u) and u.pos.distance_to(at) <= NOISE_RADIUS:
			EnemyAI.alert(s, u)


## Applies terrain hits ({cell: hits}). Emits one "cover_destroyed" for the tile changes, then
## "level_changed" / "fell" / "damage" for collapsing floors, then sets off hit barrels in order.
## Returns every cell that changed.
static func hit(s: GameState, hits: Dictionary, by: Unit = null) -> Array[Vector2i]:
	var g := s.grid
	var changes: Array = []
	var drops: Array = []
	var barrels: Array[Vector2i] = []
	var cells: Array[Vector2i] = []
	for c in _sorted(hits.keys()):
		var was_level := g.level(c)
		var r := _hit_cell(g, c, int(hits[c]), true)
		if r.barrel:
			barrels.append(c)
		if r.changed:
			changes.append({"cell": c, "kind": r.kind, "tile": g.tile(c)})
			cells.append(c)
		if r.dropped > 0:
			drops.append([c, was_level, r.dropped])
	for ch in _hit_edges(g, hits):
		changes.append(ch)
		if not cells.has(ch.cell):
			cells.append(ch.cell)
	if not changes.is_empty():
		s.emit({"type": "cover_destroyed", "cells": cells, "changes": changes, "unit": by.id if by != null else -1})
	for d in drops:
		_drop(s, d[0], d[1], d[2], by)
	for b in barrels:
		if s.phase == Types.Phase.ENDED:
			break
		detonate(s, b, by)
	return cells


## Edge walls on the borders of the hit cells take the larger of the two cells' hits. Returns
## "cover_destroyed" change entries ({cell, kind, tile, edge}; `cell` is the edge's west/north cell).
static func _hit_edges(g: Grid, hits: Dictionary) -> Array:
	var out: Array = []
	if g.edges.is_empty():
		return out
	var on := {}
	for c in hits:
		for d in Grid.DIRS4:
			var k := Grid.edge_key(c, d)
			if g.edges.has(k):
				on[k] = maxi(int(on.get(k, 0)), maxi(int(hits.get(c, 0)), int(hits.get(c + d, 0))))
	var keys: Array = on.keys()
	keys.sort()
	for k in keys:
		var n: int = on[k]
		if n <= 0:
			continue
		var kind: int = g.edges[k]
		var cell: Vector2i = Grid.edge_cells(k)[0]
		var change := ""
		match kind:
			Grid.EDGE_WALL, Grid.EDGE_WINDOW:
				var worn := int(g.edge_wear.get(k, 0)) + n
				if worn < WALL_HITS:
					g.edge_wear[k] = worn
					change = "crack"
				else:
					g.edges.erase(k)
					g.edge_wear.erase(k)
					change = "break"
			Grid.EDGE_LOW:
				g.edges.erase(k)
				change = "clear"
		if change != "":
			out.append({"cell": cell, "kind": change, "tile": g.tile(cell), "edge": k})
	return out


## A fuel barrel at `c` goes off (its tile is already floor when called from `hit`).
static func detonate(s: GameState, c: Vector2i, by: Unit = null) -> void:
	var g := s.grid
	if g.is_volatile(c):
		g.volatile.erase(c)
		g.set_tile(c, Types.Tile.FLOOR)
		g.rubble[c] = "barrel"
		g.wear.erase(c)
		s.emit({"type": "cover_destroyed", "cells": [c], "changes": [{"cell": c, "kind": "barrel", "tile": Types.Tile.FLOOR}],
			"unit": by.id if by != null else -1})
	explode(s, c, BARREL, by, "barrel")
	if s.phase == Types.Phase.ENDED:
		return
	var fire: Array[Vector2i] = []
	for cell in _sorted(pattern(g, c, BARREL).keys()):
		if g.is_walkable(cell):
			fire.append(cell)
	_barrel_fire = true
	Hazards.add(s, fire, "fire", BARREL_FIRE_TURNS, by.id if by != null else -1)
	_barrel_fire = false


## Hazards hook: fire placed on `cells` sets off any barrel next to them (not a barrel's own fire).
static func on_fire(s: GameState, cells: Array, source_id: int) -> void:
	if _barrel_fire:
		return
	var lit: Array[Vector2i] = []
	for c in cells:
		for d in Grid.DIRS8:
			var b: Vector2i = c + d
			if s.grid.is_volatile(b) and not lit.has(b):
				lit.append(b)
	if lit.is_empty():
		return
	var hits := {}
	for b in lit:
		hits[b] = 1
	hit(s, hits, s.get_unit(source_id) if source_id >= 0 else null)


## The cells holding cover between `target` and an attack from `from` (what Breach knocks down).
static func cover_cells(g: Grid, target: Vector2i, from: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for side in [Vector2i(signi(from.x - target.x), 0), Vector2i(0, signi(from.y - target.y))]:
		if side != Vector2i.ZERO and g.cover_toward(target, side) != Types.Cover.NONE:
			out.append(target + side)
	return out


# --- Shoot barrel (any soldier with a gun) -----------------------------------------------------

static func handles(id: String) -> bool:
	return id == "shoot_barrel"


## Ability entries for the action bar: Shoot barrel shows only while a barrel is in sight.
static func available(s: GameState, u: Unit) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _can_shoot(u):
		return out
	var cells := barrel_targets(s, u)
	if cells.is_empty():
		return out
	out.append({"id": "shoot_barrel", "name": SHOOT_BARREL.name, "targeting": "cell", "cost": -1,
		"cooldown": 0, "desc": SHOOT_BARREL.desc, "targets": [], "cells": cells,
		"ready": u.actions_left > 0 and u.is_alive()})
	return out


## Barrels `u` can shoot right now.
static func barrel_targets(s: GameState, u: Unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in _sorted(s.grid.volatile.keys()):
		if _barrel_error(s, u, c) == "":
			out.append(c)
	return out


static func validate(s: GameState, u: Unit, action: Dictionary) -> String:
	if not _can_shoot(u):
		return "No gun"
	var c: Variant = action.get("cell")
	if not c is Vector2i:
		return "No target cell"
	return _barrel_error(s, u, c)


static func apply(s: GameState, u: Unit, action: Dictionary) -> void:
	var c: Vector2i = action.cell
	u.actions_left = 0
	s.emit({"type": "ability", "unit": u.id, "ability": "shoot_barrel", "cell": c})
	hit(s, {c: 1}, u)


static func _can_shoot(u: Unit) -> bool:
	return u.team == Types.Team.PLAYER and not u.ai_controlled and not UnitData.is_melee_only(u.kind)


static func _barrel_error(s: GameState, u: Unit, c: Vector2i) -> String:
	if not s.grid.is_volatile(c):
		return "No barrel there"
	if u.pos.distance_to(c) > Combat.SIGHT_RANGE:
		return "Too far"
	if not Combat.can_see(s, u.pos, c) or not Vision.cell_visible(s, u.team, c):
		return "No line of sight"
	return ""


# --- Terrain ----------------------------------------------------------------------------------

## One cell takes `n` hits, layer by layer. Returns {changed, kind, barrel, dropped (levels)}.
## `live` false is the preview: same rules, no fall damage or events (the caller handles both).
static func _hit_cell(g: Grid, c: Vector2i, n: int, _live := false) -> Dictionary:
	var r := {"changed": false, "kind": "", "barrel": false, "dropped": 0}
	if n <= 0 or not breakable(g, c):
		return r
	var left := n
	if g.tile(c) == Types.Tile.WALL:
		var worn := int(g.wear.get(c, 0)) + left
		if worn < WALL_HITS:
			g.wear[c] = worn
			r.changed = true
			r.kind = "crack"
			return r
		left = worn - WALL_HITS
		g.wear.erase(c)
		g.set_tile(c, Types.Tile.LOW)
		g.rubble[c] = "heap"
		r.changed = true
		r.kind = "break"
	if left > 0 and g.tile(c) == Types.Tile.LOW:
		left -= 1
		r.changed = true
		if g.is_volatile(c):
			g.volatile.erase(c)
			g.set_tile(c, Types.Tile.FLOOR)
			g.rubble[c] = "barrel"
			r.barrel = true
			r.kind = "barrel"
			return r   # the blast does the rest
		g.set_tile(c, Types.Tile.FLOOR)
		g.rubble[c] = "debris"
		r.kind = "clear" if r.kind == "" else r.kind
	if left > 0 and g.is_walkable(c) and g.level(c) > 0:
		if g.is_fragile(c):
			r.dropped = g.level(c)
			r.changed = true
			r.kind = "drop"
			return r
		var worn := int(g.wear.get(c, 0)) + left
		var drop := mini(worn / ROOF_HITS, g.level(c))
		worn -= drop * ROOF_HITS
		if worn > 0 and drop < g.level(c):
			g.wear[c] = worn
		else:
			g.wear.erase(c)
		r.changed = true
		if drop > 0:
			r.dropped = drop
			r.kind = "drop"
		elif r.kind == "":
			r.kind = "crack"
	if r.dropped > 0 and not _live:
		_settle(g, c, g.level(c) - r.dropped, g.is_fragile(c))
	return r


## A cell's floor drops `levels` (live): Elevation.set_level emits level_changed and fixes
## ladders; a solid roof leaves a rubble ramp, a scaffold just falls; whoever stood there falls.
static func _drop(s: GameState, c: Vector2i, was: int, levels: int, by: Unit) -> void:
	var g := s.grid
	var scaffold := g.is_fragile(c)
	var to := 0 if scaffold else was - levels
	Elevation.set_level(s, c, to)
	_settle(g, c, to, scaffold)
	var u := s.unit_at(c)
	if u != null and u.is_alive() and not u.status.get("flying", false):
		var dmg := (was - to) * Elevation.FALL_DAMAGE_PER_LEVEL
		s.emit({"type": "fell", "unit": u.id, "damage": dmg})
		Rules.deal_damage(s, u, dmg, by)


## Leaves a collapsed cell at level `to`: rubble that works as stairs wherever it now sits next to
## higher ground (so a crater always has a way out and a breached roof a new way up).
static func _settle(g: Grid, c: Vector2i, to: int, scaffold: bool) -> void:
	g.set_level(c, to)
	g.fragile.erase(c)
	g.rubble[c] = "scaffold" if scaffold else "roof"
	if scaffold:
		return
	for d in Grid.DIRS4:
		var n := c + d
		if g.is_walkable(n) and g.level(n) == to + 1:
			g.stairs[c] = true
			return


static func _sorted(cells: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(cells)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
