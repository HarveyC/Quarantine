class_name BoreEngine
extends RefCounted
## The Act 3 boss fight, "the Cold Start". The drill that cut the Bore is running again. It cannot
## be shot to death: three coolant valves keep its core sealed, and the core only opens when the
## last valve is cut. Three states:
##   1 Sealed (no valve cut): immune while any valve lives. Pistons sweep marked rows and columns,
##     and every valve spawns Hounds, so the squad has to cross the deck to reach them.
##   2 Overload (one or two valves cut, or the core sealed again): each cut valve drops the platform
##     it stood on a turn later, adds a piston lane, and the Engine bites down on anything beside it.
##   3 Core open (all valves cut): the shield is gone for a few rounds. Hits land, but the first
##     window cannot take it below half. When the window ends it seals, regrows some valves and
##     starts again, so the squad needs the burst to be done inside the window.
## Encounter, EnemyBehaviours and FightBuilder call in here. OWNER: enemies workstream.

## Boss HP as a share of its 30, by squad size (FightBuilder, instead of SQUAD_BOSS_HEALTH).
const HEALTH := {1: 0.45, 2: 0.7, 3: 2.8, 4: 4.0}
const PISTONS := {1: 1, 2: 2, 3: 2, 4: 3}            # marked lanes per turn while sealed
const WINDOW := {1: 6, 2: 6, 3: 4, 4: 3}             # squad turns the core stays open
const REGROW := {1: 1, 2: 2, 3: 2, 4: 2}             # valves the Engine regrows when it seals again
const FIRST_FLOOR := 0.5                             # share of its HP the first window cannot cut through
const VALVE_OFFSETS: Array[Vector2i] = [Vector2i(0, -6), Vector2i(-6, 3), Vector2i(6, 3)]
const PAD_RADIUS := 2                                # platform that falls with a valve
const BITE_REACH := 3                                # a soldier this close (Chebyshev) is bitten
const HEAL := 0.1                                    # share of max HP it regains when it seals again
const HOUND_EVERY := {1: 16, 2: 10, 3: 7, 4: 5}        # turns between a valve's Hounds


static func setup(s: GameState, e: Unit, squad: int) -> void:
	var homes: Array[Vector2i] = []
	for i in VALVE_OFFSETS.size():
		var valve := Encounter._place(s, "coolant_valve", e.pos + VALVE_OFFSETS[i])
		_arm(valve, squad, i)
		homes.append(valve.pos)
	e.status["valve_homes"] = homes
	e.status["cut"] = 0
	e.status["windows"] = 0
	e.status["alerted"] = true


static func _arm(valve: Unit, squad: int, i: int) -> void:
	valve.status["alerted"] = true
	valve.status["spawner"] = {"kinds": ["hound"], "every": int(HOUND_EVERY[squad]), "next": 3 + i, "i": i}


static func valves_alive(s: GameState) -> int:
	var n := 0
	for o in s.living(Types.Team.ENEMY):
		if o.kind == "coolant_valve":
			n += 1
	return n


static func is_open(u: Unit) -> bool:
	return int(u.status.get("window", 0)) > 0


# --- phases --------------------------------------------------------------------------------

## While the core is open for the first time a hit stops at the floor, so no single hit ends it.
static func clamp_damage(u: Unit, amount: int) -> int:
	if is_open(u) and int(u.status.get("windows", 0)) == 0:
		var floor_hp := ceili(u.max_hp * FIRST_FLOOR)
		if u.hp > floor_hp:
			return mini(amount, u.hp - floor_hp)
		return 0
	return amount


## A valve is cut: the platform it stood on gives way next turn and the Engine bites down harder.
static func on_valve_cut(s: GameState, valve: Unit) -> void:
	var e := _engine(s)
	if e == null:
		return
	e.status["cut"] = int(e.status.get("cut", 0)) + 1
	var raised: Array[Vector2i] = []
	for dy in range(-PAD_RADIUS, PAD_RADIUS + 1):
		for dx in range(-PAD_RADIUS, PAD_RADIUS + 1):
			var c := valve.pos + Vector2i(dx, dy)
			if s.grid.in_bounds(c) and s.grid.level(c) > 0:
				raised.append(c)
	if not raised.is_empty():
		Encounter.add_telegraph(s, {"kind": "collapse", "cells": raised, "turn": s.turn + 1, "damage": 0,
			"source": e.id, "collapse": true, "smash": false, "unit": e.id})
	var left := valves_alive(s)
	s.emit({"type": "valve_cut", "unit": valve.id, "engine": e.id, "left": left})
	if int(e.status.get("boss_phase", 1)) == 1 and left > 0:
		e.status.boss_phase = 2
		s.emit({"type": "boss_phase", "unit": e.id, "phase": 2, "boss": e.kind, "text": "The valves overload!"})


## Called after the last valve died and the tether was lifted: the core opens.
static func on_valves_dead(s: GameState, e: Unit) -> void:
	var squad := clampi(int(s.encounter.get("squad", 4)), 1, 4)
	e.status["window"] = int(WINDOW[squad])
	s.encounter["lapse_double"] = true
	if int(e.status.get("boss_phase", 1)) < 3:
		e.status.boss_phase = 3
		s.emit({"type": "boss_phase", "unit": e.id, "phase": 3, "boss": e.kind, "text": "The core is open!"})
	s.emit({"type": "core_open", "unit": e.id, "left": int(e.status.window)})


## The window ran out: the core seals, some valves grow back and the Engine mends a little.
static func reseal(s: GameState, e: Unit, squad: int) -> void:
	e.status.erase("window")
	e.status["windows"] = int(e.status.get("windows", 0)) + 1
	e.status["tether"] = "coolant_valve"
	e.status["boss_phase"] = 2
	var homes: Array = e.status.get("valve_homes", [])
	for i in mini(int(REGROW[squad]), homes.size()):
		var valve := Encounter._place(s, "coolant_valve", homes[i])
		_arm(valve, squad, i)
		valve.status["spawner"].next = s.turn + 3 + i
		s.emit({"type": "spawned", "unit": valve.id, "kind": valve.kind, "cell": valve.pos, "from": e.id})
	e.hp = mini(e.max_hp, e.hp + roundi(e.max_hp * HEAL))
	s.emit({"type": "core_sealed", "unit": e.id, "hp": e.hp, "max_hp": e.max_hp, "valves": valves_alive(s)})


# --- its turn --------------------------------------------------------------------------------

static func take_turn(s: GameState, e: Unit) -> void:
	var squad := clampi(int(s.encounter.get("squad", 4)), 1, 4)
	if is_open(e):
		e.status.window = int(e.status.window) - 1
		if int(e.status.window) <= 0:
			reseal(s, e, squad)
		else:
			s.emit({"type": "core_open", "unit": e.id, "left": int(e.status.window)})
	var hostiles := EnemyAI._hostiles(s, e)
	if hostiles.is_empty():
		return
	e.actions_left = 6   # every piston is its own marked lane; the bite ends the turn
	var lanes := int(PISTONS[squad]) + (1 if int(e.status.get("cut", 0)) >= 2 else 0)
	if is_open(e):
		lanes = maxi(1, lanes - 1)   # the pistons slow while the core is bare
	_pistons(s, e, hostiles, lanes)
	if not e.is_alive() or s.phase == Types.Phase.ENDED:
		return
	if int(e.status.get("boss_phase", 1)) >= 2 or is_open(e):
		_bite(s, e, hostiles)


## Marks `n` lanes (a whole row or column each), one through each of the soldiers it can catch,
## preferring the lane that crosses the most of them and not repeating a line.
static func _pistons(s: GameState, e: Unit, hostiles: Array[Unit], n: int) -> void:
	var used := {}
	for i in n:
		var best := {}
		var best_score := 0.0
		for h in hostiles:
			for axis in ["row", "col"]:
				var key := "%s%d" % [axis, h.pos.y if axis == "row" else h.pos.x]
				if used.has(key):
					continue
				var cells := EnemyAbilities.slam_line(s, e, h.pos, axis)
				var score := 0.0
				for o in hostiles:
					if cells.has(o.pos):
						score += 1.0 + 0.5 * s.grid.level(o.pos)
				if score > best_score:
					best_score = score
					best = {"cell": h.pos, "axis": axis, "key": key}
		if best.is_empty():
			return
		used[best.key] = true
		EnemyBehaviours._try(s, {"type": Types.ABILITY, "unit": e.id, "ability": "piston", "cell": best.cell, "axis": best.axis})


static func _bite(s: GameState, e: Unit, hostiles: Array[Unit]) -> void:
	for h in hostiles:
		if EnemyAI._cheb(e.pos, h.pos) <= BITE_REACH:
			EnemyBehaviours._try(s, {"type": Types.ABILITY, "unit": e.id, "ability": "bite"})
			return


static func _engine(s: GameState) -> Unit:
	for o in s.living(Types.Team.ENEMY):
		if o.kind == "bore_engine":
			return o
	return null
