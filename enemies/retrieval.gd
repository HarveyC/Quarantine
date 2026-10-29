class_name Retrieval
extends RefCounted
## Halden-Voss Recovery's way of taking a soldier alive: the Director's mark, the Collectors that pin
## and drag, and the retrieval cage. The Director fight (enemies/director_boss.gd) is built on it.
##   Mark      the most Infected soldier is marked: every enemy hit on them deals +1, the Director's
##             shots ignore their cover, and the Collectors go for them first.
##   Collector pounces on a soldier and pins them (the Lurker's hold: Struggle, or hit the Collector),
##             then every round drags them toward the nearest exit lane. At the lane the soldier is taken.
##   Retrieval a telegraphed 3x3 cage. It hurts every soldier inside, and takes a soldier a Collector has pinned.
## Status keys: soldier "retrieval": true (marked); Director "mark": soldier id. Every action still goes
## through Rules.validate/apply. OWNER: enemies workstream.

const MARK_DAMAGE := 1           # extra damage from every enemy hit on the marked soldier
const CAGE_DAMAGE := 5
const CAGE_RANGE := 16.0
## Tiles a Collector hauls its captive per round, by squad size (a lone soldier gets a longer fight to break free).
const DRAG_STEPS := {1: 1, 2: 2, 3: 2, 4: 2}
const IDS: Array[String] = ["flag", "retrieve", "drag"]


static func handles(id: String) -> bool:
	return IDS.has(id)


# --- the mark -------------------------------------------------------------------------------

## The soldier to mark: the most Infected, then the most hurt, then the nearest to `u`.
static func mark_target(s: GameState, u: Unit) -> Unit:
	var best: Unit = null
	for t in s.living(Types.Team.PLAYER):
		if t.status.get("turned", false) or t.status.get("lapsed", false):
			continue
		if best == null or _mark_score(u, t) > _mark_score(u, best):
			best = t
	return best


static func _mark_score(u: Unit, t: Unit) -> float:
	return t.infection * 1.0 + (t.max_hp - t.hp) * 0.5 - EnemyAI._dist(u.pos, t.pos) * 0.01


static func marked(s: GameState) -> Unit:
	for t in s.living(Types.Team.PLAYER):
		if t.status.get("retrieval", false):
			return t
	return null


static func clear_mark(s: GameState) -> void:
	for t in s.units:
		t.status.erase("retrieval")


static func is_marked(u: Unit) -> bool:
	return u.status.get("retrieval", false)


# --- abilities ------------------------------------------------------------------------------

static func validate(s: GameState, u: Unit, action: Dictionary) -> String:
	match str(action.get("ability", "")):
		"flag":
			var t := mark_target(s, u)
			if t == null:
				return "Nobody to mark"
			if is_marked(t):
				return "Already marked"
		"retrieve":
			var cell: Variant = action.get("cell")
			if not cell is Vector2i or not s.grid.in_bounds(cell):
				return "Invalid cell"
			if u.pos.distance_to(cell) > CAGE_RANGE:
				return "Out of range"
		"drag":
			var c := s.get_unit(int(u.status.get("pinning", -1)))
			if c == null or not c.is_alive():
				return "Nobody pinned"
			if lane_path(s, u).is_empty():
				return "No way out"
	return ""


static func apply(s: GameState, u: Unit, action: Dictionary) -> void:
	match str(action.ability):
		"flag":
			var t := mark_target(s, u)
			clear_mark(s)
			t.status["retrieval"] = true
			u.status["mark"] = t.id
			s.emit({"type": "ability", "unit": u.id, "ability": "flag", "target": t.id})
		"retrieve":
			var cells := EnemyAbilities.square(s.grid, action.cell, 1)
			s.emit({"type": "ability", "unit": u.id, "ability": "retrieve", "cell": action.cell, "cells": cells})
			Encounter.add_telegraph(s, {"kind": "retrieval", "cells": cells, "turn": s.turn + 1,
				"damage": CAGE_DAMAGE, "source": u.id, "smash": false, "unit": u.id, "capture": true})
		"drag":
			_drag(s, u)


## Where a cage lands to catch `t`: on a pinned soldier (who cannot step out), else on `t`.
static func cage_cell(s: GameState, t: Unit) -> Vector2i:
	for p in s.living(Types.Team.PLAYER):
		if p.status.has("pinned_by") and p.pos.distance_to(t.pos) <= 2.0:
			return p.pos
	return t.pos


# --- Collectors -----------------------------------------------------------------------------

## The map edge cells the Collectors come in by and haul captives out through.
static func exits(s: GameState) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var markers: Variant = s.grid.get("markers")
	if markers is Dictionary:
		out.assign(markers.get("reinforce", []))
	if out.is_empty():
		out.assign(s.grid.enemy_spawns)
	return out


## The cells a Collector would walk next, toward the nearest exit it can reach ([] if none).
static func lane_path(s: GameState, u: Unit) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	var occ := s.occupied(u.id)
	for e in exits(s):
		if e == u.pos:
			return [e] as Array[Vector2i]
		var path := s.grid.find_path(u.pos, e, occ)
		if path.is_empty():
			continue
		if best.is_empty() or path.size() < best.size():
			best = path
	return best


static func steps_per_round(s: GameState) -> int:
	var n: int = DRAG_STEPS[clampi(int(s.encounter.get("squad", 4)), 1, 4)]
	var d := _boss(s)
	if d != null and int(d.status.get("boss_phase", 1)) >= 3:
		n += 1
	return n


static func _boss(s: GameState) -> Unit:
	for o in s.living(Types.Team.ENEMY):
		if o.kind == "director":
			return o
	return null


## A Collector's choice: pounce on the best soldier it can reach, else close in on the prey.
static func collector(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	var prey: Array[Unit] = []
	for h in hostiles:
		if not h.status.has("pinned_by"):
			prey.append(h)
	if prey.is_empty():
		return {}
	prey.sort_custom(func(a: Unit, b: Unit) -> bool: return _prey_score(u, a) > _prey_score(u, b))
	for t in prey:
		var a := EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "pounce", "target": t.id})
		if not a.is_empty():
			return a
	return EnemyAI._advance(s, u, [prey[0]] as Array[Unit])


static func _prey_score(u: Unit, t: Unit) -> float:
	return (20.0 if is_marked(t) else 0.0) - t.hp * 0.5 - EnemyAI._dist(u.pos, t.pos) * 0.3


static func _drag(s: GameState, u: Unit) -> void:
	var captive := s.get_unit(int(u.status.pinning))
	var path := lane_path(s, u)
	var steps := mini(steps_per_round(s), path.size())
	var walked: Array[Vector2i] = []
	for i in steps:
		walked.append(path[i])
	var from := u.pos
	var trail: Array[Vector2i] = [from]
	for i in range(0, walked.size() - 1):
		trail.append(walked[i])
	var cfrom := captive.pos
	Rules.open_doors_along(s, from, walked, u)
	u.pos = walked[-1] if not walked.is_empty() else from
	captive.pos = trail[-1]
	captive.overwatch = false
	captive.hunkered = false
	s.emit({"type": "ability", "unit": u.id, "ability": "drag", "target": captive.id})
	if not walked.is_empty():
		s.emit({"type": "move", "unit": u.id, "from": from, "path": walked})
		s.emit({"type": "move", "unit": captive.id, "from": cfrom, "path": trail, "dragged": true})
	u.actions_left = 0
	if exits(s).has(u.pos):
		take(s, captive, u)


## The Collector reaches the lane: the soldier is gone for good and the Collector slips away.
static func take(s: GameState, t: Unit, by: Unit) -> void:
	if not t.is_alive():
		return
	by.status.erase("pinning")
	t.status.erase("pinned_by")
	t.status.erase("pinned_at")
	s.emit({"type": "taken", "unit": t.id, "by": by.id})
	t.hp = 0
	t.overwatch = false
	if t.status.get("retrieval", false):
		t.status.erase("retrieval")
	s.emit({"type": "died", "unit": t.id, "taken": true})
	Encounter.on_died(s, t)
	Kit.on_death(s, t, by)
	by.status["fled"] = true
	s.emit({"type": "fled", "unit": by.id, "loot": false})
	Encounter.kill(s, by)
	Rules.check_end(s)


## A soldier caught in a capture telegraph while a Collector holds them is taken.
static func after_cage(s: GameState, victims: Array[Unit]) -> void:
	for v in victims:
		if v.is_alive() and v.team == Types.Team.PLAYER and v.status.has("pinned_by"):
			var holder := s.get_unit(int(v.status.pinned_by))
			if holder != null and holder.kind == "collector":
				take(s, v, holder)
