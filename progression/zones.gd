class_name Zones
extends RefCounted
## Progression-only area effects: Spore Burst clouds (they deal damage for their owner) and
## Overgrowth walls. Fire and spore tiles are Hazards (hazards/hazards.gd).
## OWNER: progression workstream. State lives in GameState.zones as JSON-friendly Dictionaries:
##   {"kind": "spore_burst"|"growth", "cells": [[x, y], ...], "until": phase index
##    it expires at (see Combat.phase_index), "owner": unit id}
## Events: {"type": "zone", "kind", "cells", "until"} when one appears, {"type": "zone_end", "kind", "cells"}
## when it expires.

const SPORE_GAIN := 5
const BURST_DAMAGE := 2


static func add(s: GameState, kind: String, cells: Array[Vector2i], until: int, owner: Unit = null) -> Dictionary:
	var z := {"kind": kind, "cells": cells.map(func(c: Vector2i) -> Array: return [c.x, c.y]),
		"until": until, "owner": owner.id if owner else -1}
	s.zones.append(z)
	s.emit({"type": "zone", "kind": kind, "cells": cells.duplicate(), "until": until})
	return z


static func cells_of(z: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in z.cells:
		out.append(Vector2i(int(c[0]), int(c[1])))
	return out


static func zones_at(s: GameState, c: Vector2i, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for z in s.zones:
		if z.kind == kind and z.cells.has([c.x, c.y]):
			out.append(z)
	return out


## Called at the start of each phase (`ending` is the team whose turn just ended). Spore Burst
## clouds tick at the start of each team phase. Then expired zones are removed.
static func on_phase_start(s: GameState, ending: int) -> void:
	for z in s.zones.duplicate():
		for c in cells_of(z):
			var u := s.unit_at(c)
			if u == null:
				continue
			if z.kind == "spore_burst" and ending == Types.Team.ENEMY:
				burst_tick(s, z, u)
	var now := Combat.phase_index(s)
	for z in s.zones.duplicate():
		if int(z.until) <= now:
			_remove(s, z)


static func burst_tick(s: GameState, z: Dictionary, u: Unit) -> void:
	var owner := s.get_unit(int(z.get("owner", -1)))
	if owner != null and owner.is_enemy_of(u):
		Rules.deal_damage(s, u, BURST_DAMAGE, owner)
	elif Kit.is_soldier(u):
		Infection.add(s, u, SPORE_GAIN)


static func _remove(s: GameState, z: Dictionary) -> void:
	s.zones.erase(z)
	if z.kind == "growth":
		for c in cells_of(z):
			if s.grid.tile(c) == Types.Tile.WALL:
				set_tile(s.grid, c, Types.Tile.FLOOR)
	s.emit({"type": "zone_end", "kind": z.kind, "cells": cells_of(z)})


static func set_tile(g: Grid, c: Vector2i, t: int) -> void:
	if g.in_bounds(c):
		g.tiles[c.y * g.width + c.x] = t
