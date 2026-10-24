class_name Elevation
extends RefCounted
## High ground (ground, roofs at level 1, upper roofs at level 2). Pure rules code. The level
## data lives on the Grid (Grid.level, ladders, stairs, fragile scaffolds; set by MapGen from the
## parcels); movement costs live in Grid.step_cost (stairs, ladders, drop-downs). This module holds
## the combat bonus, the in-fight way to change a tile's level and explosive collapses.
## See docs/ARCHITECTURE.md, "High ground".
##
## Shooting down from high ground: +AIM_BONUS aim and the target's cover counts one step lower
## (full -> half, half -> none). Shooting up at high ground: the target has at least half cover.
## Neither changes "flanked" (the crit bonus still needs a real flank). The bonus is the same for
## one or two levels up: height is about reaching a perch, not stacking numbers.

const AIM_BONUS := 10
const FALL_DAMAGE_PER_LEVEL := 2


## How high `u` stands: its cell's level (0-2), or at least 1 when flying (status "flying").
static func height(s: GameState, u: Unit, at: Vector2i = u.pos) -> int:
	if u.status.get("flying", false):
		return maxi(1, s.grid.level(at))
	return s.grid.level(at)


## +1 when `attacker` (standing at `from`) is higher than `target`, -1 when lower, else 0.
static func advantage(s: GameState, attacker: Unit, target: Unit, from: Vector2i = attacker.pos) -> int:
	return signi(height(s, attacker, from) - height(s, target))


## Cover the target really gets once height is counted (`cover` is the flat Combat.cover_against).
static func adjust_cover(s: GameState, attacker: Unit, target: Unit, from: Vector2i, cover: int) -> int:
	match advantage(s, attacker, target, from):
		1: return maxi(cover - 1, Types.Cover.NONE)
		-1: return maxi(cover, Types.Cover.HALF)
	return cover


## Aim bonus from height for a shot from `from`.
static func aim_mod(s: GameState, attacker: Unit, target: Unit, from: Vector2i = attacker.pos) -> int:
	return AIM_BONUS if advantage(s, attacker, target, from) > 0 else 0


## A raised cell with a walkable ground cell beside it (where a unit can be knocked off).
static func is_ledge(g: Grid, c: Vector2i) -> bool:
	if g.level(c) == 0:
		return false
	for d in Grid.DIRS8:
		if g.is_walkable(c + d) and g.level(c + d) < g.level(c):
			return true
	return false


## Changes a tile's level in a fight (e.g. a Burrower collapsing a roof). Units on the cell stay
## put and simply stand at the new level. Ladders left joining nothing are removed.
## Emits {"type": "level_changed", "cell", "level"}.
static func set_level(s: GameState, c: Vector2i, n: int) -> void:
	if not s.grid.in_bounds(c) or s.grid.level(c) == n:
		return
	s.grid.set_level(c, n)
	if n == 0:
		s.grid.fragile.erase(c)
	for l in [c] + _neighbours(c):
		if s.grid.is_ladder(l) and not _joins_levels(s.grid, l):
			s.grid.ladders.erase(l)
		if s.grid.is_stairs(l) and not _joins_levels(s.grid, l):
			s.grid.stairs.erase(l)
	s.emit({"type": "level_changed", "cell": c, "level": n})


## An explosion around `center` (Chebyshev `radius`) brings down fragile scaffolds and catwalks:
## those cells drop to the ground and anyone standing on them falls (FALL_DAMAGE_PER_LEVEL a
## level, emits "fell"). Units in the air (status "flying") stay up. Returns the collapsed cells.
static func blast(s: GameState, center: Vector2i, radius: int, by: Unit = null) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var c := center + Vector2i(dx, dy)
			if s.grid.is_fragile(c) and s.grid.level(c) > 0:
				cells.append(c)
	for c in cells:
		var was := s.grid.level(c)
		set_level(s, c, 0)
		var u := s.unit_at(c)
		if u != null and u.is_alive() and not u.status.get("flying", false):
			var dmg := was * FALL_DAMAGE_PER_LEVEL
			s.emit({"type": "fell", "unit": u.id, "damage": dmg})
			Rules.deal_damage(s, u, dmg, by)
	return cells


static func _joins_levels(g: Grid, c: Vector2i) -> bool:
	for d in Grid.DIRS4:
		if g.is_walkable(c + d) and absi(g.level(c + d) - g.level(c)) == 1:
			return true
	return false


static func _neighbours(c: Vector2i) -> Array:
	var out := []
	for d in Grid.DIRS4:
		out.append(c + d)
	return out
