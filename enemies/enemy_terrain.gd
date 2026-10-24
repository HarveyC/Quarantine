class_name EnemyTerrain
extends RefCounted
## Elevation reads and writes for the enemy roster. The heights layer (Grid.level, and the
## Elevation module that changes it) belongs to the map workstream; until it lands every cell
## is level 0, so everything here degrades to flat ground.
## OWNER: enemies workstream.

const FALL_DAMAGE_PER_LEVEL := 2


static func level(s: GameState, c: Vector2i) -> int:
	if s.grid.has_method("level"):
		return int(s.grid.call("level", c))
	return 0


static func can_lower(s: GameState) -> bool:
	return s.grid.has_method("set_level")


## Collapses raised cells back to ground (Burrower). Units standing on them take fall damage.
## Returns the collapsed cells. Elevation.set_level emits the level_changed events.
static func collapse(s: GameState, cells: Array, by: Unit) -> Array[Vector2i]:
	var done: Array[Vector2i] = []
	if not can_lower(s):
		return done
	for c in cells:
		var was := level(s, c)
		if was <= 0:
			continue
		RunHooks.call_static("Elevation", "set_level", [s, c, 0])
		if level(s, c) > 0:   # Elevation module not landed yet
			s.grid.call("set_level", c, 0)
		done.append(c)
		var u := s.unit_at(c)
		if u != null and not EnemyRoster.is_flying(u):
			s.emit({"type": "fell", "unit": u.id, "damage": was * FALL_DAMAGE_PER_LEVEL})
			Rules.deal_damage(s, u, was * FALL_DAMAGE_PER_LEVEL, null)
	return done


## Damage for dropping from `from` to `to` (knocked off a ledge). 0 on flat ground.
static func fall_damage(s: GameState, from: Vector2i, to: Vector2i) -> int:
	return maxi(0, level(s, from) - level(s, to)) * FALL_DAMAGE_PER_LEVEL


## The highest level among `cells` (0 when flat).
static func top(s: GameState, cells: Array) -> int:
	var best := 0
	for c in cells:
		best = maxi(best, level(s, c))
	return best
