class_name Retrieval
extends RefCounted
## The Director's part of Halden-Voss Recovery: the retrieval mark and the retrieval cage. The Director
## fight (enemies/director_boss.gd) is built on it, with Recovery's Netters and Collectors (enemies/recovery.gd).
##   Mark      the most Infected soldier is marked: every enemy hit on them deals +1 and the Director's
##             shots ignore their cover.
##   Retrieval a telegraphed 3x3 cage. It hurts every soldier inside, and takes one a Netter or Collector holds.
## Status keys: soldier "retrieval": true (marked); Director "mark": soldier id. Every action still goes
## through Rules.validate/apply. OWNER: enemies workstream.

const MARK_DAMAGE := 1           # extra damage from every enemy hit on the marked soldier
const CAGE_DAMAGE := 5
const CAGE_RANGE := 30.0   # called down from the roofs, so the whole arena
const IDS: Array[String] = ["flag", "retrieve"]


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


## Where a cage lands to catch `t`: on a pinned soldier (who cannot step out), else on `t`.
static func cage_cell(s: GameState, t: Unit) -> Vector2i:
	for p in s.living(Types.Team.PLAYER):
		if p.status.has("pinned_by") and p.pos.distance_to(t.pos) <= 2.0:
			return p.pos
	return t.pos


# --- the cage ---------------------------------------------------------------------------------

## A soldier caught in a capture telegraph while a Netter or Collector holds them is taken.
static func after_cage(s: GameState, victims: Array[Unit]) -> void:
	for v in victims:
		if v.is_alive() and v.team == Types.Team.PLAYER and Recovery.netted(s, v):
			var holder := s.get_unit(int(v.status.pinned_by))
			if holder != null:
				Recovery._capture(s, holder, v)
