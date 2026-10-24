class_name Elevation
extends RefCounted
## High ground (one raised level). Pure rules code. The level data lives on the Grid
## (Grid.level / Grid.is_ladder, set by MapGen from the parcels); pathing rules live in
## Grid._can_step (level changes only by ladder). This module holds the combat bonus and the
## in-fight way to change a tile's level. See docs/ARCHITECTURE.md, "High ground".
##
## Shooting down from high ground: +AIM_BONUS aim and the target's cover counts one step lower
## (full -> half, half -> none). Shooting up at high ground: the target has at least half cover.
## Neither changes "flanked" (the crit bonus still needs a real flank).

const AIM_BONUS := 10


## How high `u` stands: its cell's level, or 1 when flying (status "flying").
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
	for l in [c] + _neighbours(c):
		if s.grid.is_ladder(l) and not _joins_levels(s.grid, l):
			s.grid.ladders.erase(l)
	s.emit({"type": "level_changed", "cell": c, "level": n})


static func _joins_levels(g: Grid, c: Vector2i) -> bool:
	for d in Grid.DIRS4:
		if g.is_walkable(c + d) and g.level(c + d) != g.level(c):
			return true
	return false


static func _neighbours(c: Vector2i) -> Array:
	var out := []
	for d in Grid.DIRS4:
		out.append(c + d)
	return out
