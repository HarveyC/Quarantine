class_name Hazards
extends RefCounted
## Tile hazards: fire, spore and acid on map cells. Pure rules code; state lives in `s.hazards`
## (cell -> {"kind", "turns", "source"}), serialized with GameState so it survives resyncs.
##
## Effects hit a unit once per move that crosses or ends on a hazard (once per kind), and at the
## end of its own side's turn while standing in one. Damage goes through Rules.deal_damage,
## Infection through Infection.add. Nothing here rolls dice, so no RNG is used.
##
## Callers: Hazards.add(s, cells, kind, turns, source_id, spare_team) from gear, abilities, enemies and maps;
## Hazards.at(s, cell) and Hazards.avoid_cost(s, u, cell) for queries and AI path scoring.
## Rules calls the on_* hooks. See docs/ARCHITECTURE.md, "Tile hazards".

## Per kind: damage and infection per hit, which teams it ignores, which kinds it replaces on its
## cell, and how strongly the AI should avoid it (added to a cell's score, higher = worse).
const KINDS := {
	"fire": {"name": "Fire", "damage": 2, "infection": 0, "ignores": [], "replaces": ["spore", "acid"], "avoid": 6.0},
	"spore": {"name": "Spores", "damage": 0, "infection": 10, "ignores": [Types.Team.ENEMY], "replaces": [], "avoid": 4.0},
	"acid": {"name": "Acid", "damage": 1, "infection": 0, "ignores": [], "replaces": ["spore"], "avoid": 3.0},
}
const PERMANENT := -1


## Puts `kind` on every walkable cell in `cells` for `turns` rounds (PERMANENT = until removed).
## `spare_team` (a Types.Team, or -1) makes it harmless to that team, e.g. a Clean Burn fire.
## A cell already holding the same kind keeps the longer duration; a different kind is replaced
## only if this kind lists it in "replaces" (fire burns spores away; nothing puts fire out but time).
## Emits one `hazard` event with the cells actually changed. Returns those cells.
static func add(s: GameState, cells: Array, kind: String, turns: int, source_id: int = -1, spare_team: int = -1) -> Array[Vector2i]:
	assert(KINDS.has(kind), "unknown hazard kind " + kind)
	var changed: Array[Vector2i] = []
	for c in cells:
		if not s.grid.is_walkable(c):
			continue
		var cur: Dictionary = s.hazards.get(c, {})
		if not cur.is_empty():
			if cur.kind == kind:
				if cur.turns == PERMANENT or (turns != PERMANENT and cur.turns >= turns):
					continue
			elif not KINDS[kind].replaces.has(cur.kind):
				continue
		s.hazards[c] = {"kind": kind, "turns": turns, "source": source_id, "spare": spare_team}
		changed.append(c)
	if not changed.is_empty():
		s.emit({"type": "hazard", "kind": kind, "cells": changed, "turns": turns, "source": source_id, "spare": spare_team})
	return changed


## Clears hazards from `cells` (all kinds, or only `kind`). Emits `hazard_end` per kind removed.
static func remove(s: GameState, cells: Array, kind: String = "") -> void:
	var gone := {}
	for c in cells:
		var cur: Dictionary = s.hazards.get(c, {})
		if cur.is_empty() or (kind != "" and cur.kind != kind):
			continue
		s.hazards.erase(c)
		if not gone.has(cur.kind):
			gone[cur.kind] = [] as Array[Vector2i]
		gone[cur.kind].append(c)
	for k in gone:
		s.emit({"type": "hazard_end", "kind": k, "cells": gone[k]})


## The hazard on `cell` ({"kind", "turns", "source", "spare"}), or {} if none.
static func at(s: GameState, cell: Vector2i) -> Dictionary:
	return s.hazards.get(cell, {})


## Cells holding `kind`, in a stable order.
static func cells_of(s: GameState, kind: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in s.hazards:
		if s.hazards[c].kind == kind:
			out.append(c)
	return out


## How much `u` should want to avoid standing on or crossing `cell`: 0 when there is no hazard
## or it can't hurt `u`, else the kind's "avoid" weight. For AI cell scoring.
static func avoid_cost(s: GameState, u: Unit, cell: Vector2i) -> float:
	var h := at(s, cell)
	if h.is_empty() or not _affects_here(u, h):
		return 0.0
	return KINDS[h.kind].avoid


## Whether hazard `kind` can hurt `u` at all. Deployables (status "deployable") take no Infection.
static func affects(u: Unit, kind: String) -> bool:
	var k: Dictionary = KINDS[kind]
	if k.ignores.has(u.team):
		return false
	if k.damage <= 0 and not _takes_infection(u):
		return false
	return true


static func _affects_here(u: Unit, h: Dictionary) -> bool:
	return h.get("spare", -1) != u.team and affects(u, h.kind)


static func _takes_infection(u: Unit) -> bool:
	return u.team == Types.Team.PLAYER and not u.status.has("deployable") and not u.status.has("civilian") \
		and not u.status.get("turned", false)


# ---------------------------------------------------------------- hooks called by Rules

## End of the team phase (Rules.set_ready, before enemies act): player-team units standing in a
## hazard are hit.
static func on_team_phase_end(s: GameState) -> void:
	_hit_standing(s, Types.Team.PLAYER)


## End of the enemy phase: enemies standing in a hazard are hit, then every hazard ages by one
## round and expired ones end.
static func on_enemy_phase_end(s: GameState) -> void:
	_hit_standing(s, Types.Team.ENEMY)
	var expired := {}
	for c in s.hazards.keys():
		var h: Dictionary = s.hazards[c]
		if h.turns == PERMANENT:
			continue
		h.turns -= 1
		if h.turns <= 0:
			if not expired.has(h.kind):
				expired[h.kind] = [] as Array[Vector2i]
			expired[h.kind].append(c)
	for k in expired:
		remove(s, expired[k], k)


## `u` moved along `path` (cells entered, in order): each hazard kind crossed hits it once.
static func on_move(s: GameState, u: Unit, path: Array[Vector2i]) -> void:
	var done := {}
	for c in path:
		var h := at(s, c)
		if not h.is_empty() and not done.has(h.kind):
			done[h.kind] = true
			_hit(s, u, c)


static func _hit_standing(s: GameState, team: int) -> void:
	for u in s.living(team):
		if s.phase == Types.Phase.ENDED:
			return
		_hit(s, u, u.pos)


## Applies the hazard on `cell` to `u`.
static func _hit(s: GameState, u: Unit, cell: Vector2i) -> void:
	var h := at(s, cell)
	if h.is_empty() or not u.is_alive() or not _affects_here(u, h):
		return
	var k: Dictionary = KINDS[h.kind]
	var infection: int = k.infection if _takes_infection(u) else 0
	var hit := GearFx.hazard_hit(s, u, h, k.damage, infection)  # coats, masks, Scorched earth
	if hit == Vector2i.ZERO:
		return
	infection = hit.y
	s.emit({"type": "hazard_tick", "unit": u.id, "kind": h.kind, "cell": cell, "damage": hit.x, "infection": infection})
	if hit.x > 0:
		Rules.deal_damage(s, u, hit.x, null)
	if infection > 0 and u.is_alive():
		Infection.add(s, u, infection)
