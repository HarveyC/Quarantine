class_name SourceBoss
extends RefCounted
## The Act 3 boss fight, "the Bloom Cycle". Three phases:
##   1 Rooted: immune while its roots live. The roots lash (marked 3x3 on the highest ground
##     first), spawn Runners and Spitters, and the Source pulses Infection through the squad
##     while the spore ring closes in from the map edge.
##   2 Core open (all roots dead until 33% HP): it pulls the most infected soldier toward it,
##     slams whole rows and columns (marked), and raises Echoes (turned fallen) from the shaft.
##   3 Collapse (below 33%): the shaft gives way. Every raised tile near it falls a turn after
##     it is marked, the spore ring runs two rings a turn, and it regrows roots that shield it
##     again while it lashes and slams.
## Encounter, EnemyBehaviours and FightBuilder call in here. OWNER: enemies workstream.

## Boss HP as a share of its 30, by squad size (FightBuilder, instead of SQUAD_BOSS_HEALTH).
const HEALTH := {1: 0.22, 2: 0.55, 3: 0.9, 4: 1.0}
const LASH := {1: 1, 2: 1, 3: 2, 4: 2}               # lashes per turn while the roots are up
const LASH_DAMAGE := 3
const REGROW := {1: 1, 2: 1, 3: 2, 4: 2}             # roots it regrows in the collapse
const REGROW_OFFSETS: Array[Vector2i] = [Vector2i(-5, 1), Vector2i(5, 1)]
const ECHO_EVERY := {1: 5, 2: 4, 3: 3, 4: 3}         # turns between Echoes (phases 2 and 3)
const COLLAPSE_RADIUS := 12


# --- phases --------------------------------------------------------------------------------

## HP at which the collapse starts.
static func gate(u: Unit) -> int:
	return ceili(u.max_hp / 3.0)


## While the core is open a hit stops at the collapse gate, so no single hit skips it.
static func clamp_damage(u: Unit, amount: int) -> int:
	if int(u.status.get("boss_phase", 1)) == 2 and u.hp > gate(u):
		return mini(amount, u.hp - gate(u))
	return amount


static func on_roots_dead(s: GameState, u: Unit) -> void:
	if int(u.status.get("boss_phase", 1)) == 1:
		u.status.boss_phase = 2
		s.encounter["lapse_double"] = true
		s.emit({"type": "boss_phase", "unit": u.id, "phase": 2, "boss": u.kind, "text": "The core opens!"})


static func on_damaged(s: GameState, u: Unit) -> void:
	if int(u.status.get("boss_phase", 1)) != 2 or u.hp > gate(u):
		return
	u.status.boss_phase = 3
	u.status["phase3_turn"] = s.turn
	var raised: Array[Vector2i] = []
	for y in s.grid.height:
		for x in s.grid.width:
			var c := Vector2i(x, y)
			if s.grid.level(c) > 0 and EnemyAbilities._cheb(c, u.pos) <= COLLAPSE_RADIUS:
				raised.append(c)
	if not raised.is_empty():
		Encounter.add_telegraph(s, {"kind": "collapse", "cells": raised, "turn": s.turn + 1, "damage": 0,
			"source": u.id, "collapse": true, "smash": false, "unit": u.id})
	var squad := clampi(int(s.encounter.get("squad", 4)), 1, 4)
	for i in REGROW[squad]:
		var root := Encounter._place(s, "source_root", u.pos + REGROW_OFFSETS[i])
		root.status["spawner"] = {"kinds": ["runner", "spitter"], "every": 3 + int(Encounter.BOSS_SPAWN_EVERY_EXTRA[squad]),
			"next": s.turn + 2, "i": i}
		root.status["alerted"] = true
		s.emit({"type": "spawned", "unit": root.id, "kind": root.kind, "cell": root.pos, "from": u.id})
	u.status["tether"] = "source_root"
	s.emit({"type": "boss_phase", "unit": u.id, "phase": 3, "boss": u.kind, "text": "The shaft gives way!"})


# --- its turn --------------------------------------------------------------------------------

static func take_turn(s: GameState, u: Unit) -> void:
	var phase := int(u.status.get("boss_phase", 1))
	var squad := clampi(int(s.encounter.get("squad", 4)), 1, 4)
	var hostiles := EnemyAI._hostiles(s, u)
	if hostiles.is_empty():
		return
	if phase >= 2:
		_echo(s, u, squad)
	if phase != 2 and u.status.has("tether"):
		_lash(s, u, hostiles, LASH[squad])
	elif phase == 3:
		_lash(s, u, hostiles, 1)
	if phase < 2 or u.actions_left <= 0 or not u.is_alive() or s.phase == Types.Phase.ENDED:
		return
	if not u.status.has("tether"):
		EnemyBehaviours._try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "pull"})
		_slam(s, u, hostiles)


## Lashes `n` marked 3x3s: one per soldier, highest ground first, then the most infected.
static func _lash(s: GameState, u: Unit, hostiles: Array[Unit], n: int) -> void:
	var left := hostiles.duplicate()
	for i in n:
		if u.actions_left <= 0 or left.is_empty():
			return
		left.sort_custom(func(a: Unit, b: Unit) -> bool:
			var ka := s.grid.level(a.pos) * 100 + a.infection
			var kb := s.grid.level(b.pos) * 100 + b.infection
			return ka > kb)
		var t: Unit = left.pop_front()
		if not EnemyBehaviours._try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "lash", "cell": t.pos}):
			continue
		left = left.filter(func(o: Unit) -> bool: return EnemyAI._cheb(o.pos, t.pos) > 1)


static func _slam(s: GameState, u: Unit, hostiles: Array[Unit]) -> void:
	var best := {}
	var best_hits := 0
	for h in hostiles:
		for axis in ["row", "col"]:
			var cells := EnemyAbilities.slam_line(s, u, h.pos, axis)
			var hits := 0
			for o in hostiles:
				if cells.has(o.pos):
					hits += 1
			if hits > best_hits:
				best_hits = hits
				best = {"cell": h.pos, "axis": axis}
	if not best.is_empty():
		EnemyBehaviours._try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "core_slam", "cell": best.cell, "axis": best.axis})


## Raises an Echo (a turned fallen) from the shaft every few turns once the core is open.
static func _echo(s: GameState, u: Unit, squad: int) -> void:
	if (s.turn - 1) % int(ECHO_EVERY[squad]) != 0 or Encounter._mobile_enemies(s) >= Encounter._spawn_cap(s):
		return
	var echo := Encounter.spawn(s, "fallen", u.pos + Vector2i(0, 3), u)
	echo.display_name = "Echo"
	Encounter.frenzy(s, echo)
