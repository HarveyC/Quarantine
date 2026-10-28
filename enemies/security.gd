class_name Security
extends RefCounted
## Colony Security: Hale's cordon holdouts who never turned. People, so their hits deal damage only.
##   Shieldman    a riot shield: hits from the front arc deal no damage (Encounter.modify_damage). Flanks,
##                height and blasts get round it. Slams like a Carapace.
##   Overwatcher  holds its post. It shoots what it sees, else keeps Overwatch up, and its reaction
##                shots carry no aim penalty (Combat.hit_chance).
##   Emplacement  a sandbag gun that never moves. Every enemy phase it marks a cone of floor that
##                goes off next phase for CROSSFIRE_DAMAGE on everyone standing in it, Infected too.
## Every action still goes through Rules.validate/apply. OWNER: enemies workstream.


## Takes the shot it has, else keeps Overwatch up. Never advances.
static func overwatcher(s: GameState, u: Unit) -> Dictionary:
	var shot := EnemyAI._best_shot(s, u)
	if not shot.is_empty():
		return shot.action
	return EnemyAI._check(s, {"type": Types.OVERWATCH, "unit": u.id})


## Aims at the nearest soldier on its first turn, then keeps that facing and lays the cone.
static func emplacement_turn(s: GameState, u: Unit) -> void:
	if not u.status.has("facing"):
		var near: Unit = null
		for h in EnemyAI._hostiles(s, u):
			if near == null or EnemyAI._dist(u.pos, h.pos) < EnemyAI._dist(u.pos, near.pos):
				near = h
		if near == null:
			return
		var f := Vector2i(signi(near.pos.x - u.pos.x), signi(near.pos.y - u.pos.y))
		u.status["facing"] = f if f != Vector2i.ZERO else Vector2i(0, 1)
	var cells := cone(s, u)
	if cells.is_empty():
		return
	Encounter.add_telegraph(s, {"kind": "crossfire", "cells": cells, "turn": s.turn + 1,
		"damage": EnemyRoster.CROSSFIRE_DAMAGE, "source": u.id, "smash": false, "unit": u.id})


## Floor the gun covers: within range, inside the cone around its facing, in its line of sight.
static func cone(s: GameState, u: Unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var f := Vector2(u.status.get("facing", Vector2i(0, 1))).normalized()
	var r := EnemyRoster.CROSSFIRE_RANGE
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var d := Vector2i(dx, dy)
			if d == Vector2i.ZERO:
				continue
			var c := u.pos + d
			if not s.grid.in_bounds(c) or not s.grid.is_walkable(c):
				continue
			if Vector2(d).normalized().dot(f) < EnemyRoster.CROSSFIRE_CONE or not Combat.can_see(s, u.pos, c):
				continue
			out.append(c)
	return out
