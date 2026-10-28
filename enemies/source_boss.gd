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
##
## The run decides an aspect (see aspect_for): Hunger (the squad is Infected) pulls the squad in
## from phase 1 and starts the spore ring closer; Remembers (Echoes this run) raises Echoes of the
## squad's dead from phase 1 with fewer roots to cut; Regrown (the last wave burned it) regrows a
## root during the open core, shielding it again. The Source stays immune to knockback.
## Encounter, EnemyBehaviours and FightBuilder call in here. OWNER: enemies workstream.

## Boss HP as a share of its 30, by squad size (FightBuilder, instead of SQUAD_BOSS_HEALTH).
const HEALTH := {1: 0.3, 2: 0.8, 3: 1.1, 4: 1.3}
const LASH := {1: 1, 2: 2, 3: 3, 4: 3}               # lashes per turn while the roots are up
const LASH_DAMAGE := 3
const REGROW := {1: 1, 2: 1, 3: 2, 4: 2}             # roots it regrows in the collapse
const REGROW_OFFSETS: Array[Vector2i] = [Vector2i(-5, 1), Vector2i(5, 1)]
const ECHO_EVERY := {1: 5, 2: 3, 3: 2, 4: 2}         # turns between Echoes (phases 2 and 3)
const COLLAPSE_RADIUS := 12

const ASPECTS: Array[String] = ["hunger", "remembers", "regrown"]
const ASPECT_NAMES := {"hunger": "Hunger", "remembers": "Remembers", "regrown": "Regrown"}
const ASPECT_RULES := {
	"hunger": "Pulls the most Infected soldier in every round, and the spore ring starts closer.",
	"remembers": "Raises Echoes of the fallen from the first round, with fewer roots.",
	"regrown": "A root grows back while the core is open, and shields it again.",
}
const HUNGER_INFECTION := 50        # a squad average at this Infection, or any soldier past the Critical tier
const HUNGER_RING_HEAD := 2         # rings the spore ring starts ahead
const HUNGER_PULSE := {1: 0, 2: 2, 3: 2, 4: 2}   # extra Infection its round pulse adds while the roots live
const REMEMBERS_ECHO_EVERY := {1: 4, 2: 3, 3: 2, 4: 1}   # turns between Echoes in phase 1
const REGROWN_WINDOW := {1: 4, 2: 3, 3: 3, 4: 2}         # turns the core stays open before a root regrows
const REGROWN_CYCLES := {1: 1, 2: 3, 3: 3, 4: 3}   # times the open core regrows its shield
const REGROWN_ROOTS := {1: 1, 2: 1, 3: 2, 4: 2}          # roots each regrowth brings


# --- aspect ----------------------------------------------------------------------------------

## The aspect this run gives the Source, chosen once and kept in run.story for the Act 3 scenes and
## the fight: Hunger when the squad is Infected, else Remembers when Echoes were laid or soldiers
## lost this run, else Regrown when the last wave burned it, else "" (the plain Bloom Cycle).
static func aspect_for(run: RunState) -> String:
	if str(run.story.get("aspect", "")) != "":
		return str(run.story.aspect)
	var pick := _pick_aspect(run)
	if run.act >= 3 and not run.story.is_empty():
		run.story["aspect"] = pick if pick != "" else "none"
	return pick


static func _pick_aspect(run: RunState) -> String:
	var squad := run.squad()
	var total := 0
	var worst := 0
	for r in squad:
		total += int(r.infection)
		worst = maxi(worst, int(r.infection))
	if not squad.is_empty() and (total / squad.size() >= HUNGER_INFECTION or worst >= Infection.THRESHOLDS[3]):
		return "hunger"
	var laid: bool = run.story.get("echoes", []).any(func(e: Dictionary) -> bool: return e.get("laid", false))
	if laid or not run.echoes.is_empty():
		return "remembers"
	if run.story.get("last_ending", "") == "burn":
		return "regrown"
	return ""


## Names the Echoes the Source raises wear: the soldiers this run has lost, then those laid to rest.
static func echo_names(run: RunState) -> Array:
	var out: Array = []
	for e in run.echoes:
		out.append(str(e.name))
	for e in run.story.get("echoes", []):
		if e.get("laid", false) and not out.has(str(e.name)):
			out.append(str(e.name))
	return out


static func aspect_of(u: Unit) -> String:
	return str(u.status.get("aspect", ""))


static func roots_for(squad: int, aspect: String, base: int) -> int:
	return maxi(1, base - 1) if aspect == "remembers" else base


## Called as the Source is placed.
static func setup(s: GameState, u: Unit, aspect: String, names: Array) -> void:
	if not ASPECTS.has(aspect):
		return
	u.status["aspect"] = aspect
	if not names.is_empty():
		u.status["echo_names"] = names.duplicate()


## Infection the round pulse adds on top of the squad's own.
static func pulse_bonus(s: GameState, u: Unit) -> int:
	return int(HUNGER_PULSE[clampi(int(s.encounter.get("squad", 4)), 1, 4)]) if aspect_of(u) == "hunger" else 0


## Spore rings the aspect starts ahead.
static func ring_head(u: Unit) -> int:
	return HUNGER_RING_HEAD if aspect_of(u) == "hunger" else 0


## Hunger pulls from phase 1; the other phases already do.
static func pulls_in_phase_1(u: Unit) -> bool:
	return aspect_of(u) == "hunger"


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
		u.status["open_turn"] = s.turn
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
	for i in roots_for(squad, aspect_of(u), REGROW[squad]):
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
	if aspect_of(u) != "" and not u.status.get("aspect_said", false):
		u.status["aspect_said"] = true
		s.emit({"type": "boss_aspect", "unit": u.id, "aspect": aspect_of(u), "text": ASPECT_NAMES[aspect_of(u)]})
	if aspect_of(u) == "regrown" and phase == 2:
		_regrow_open(s, u, squad)
	if phase >= 2 or aspect_of(u) == "remembers":
		_echo(s, u, squad, phase)
	if phase == 1 and pulls_in_phase_1(u) and u.actions_left > 0:
		EnemyBehaviours._try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "pull"})
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


## Raises an Echo (a turned fallen) from the shaft every few turns once the core is open, or from
## the first round when it Remembers. It wears the name of a fallen soldier when the run has one.
static func _echo(s: GameState, u: Unit, squad: int, phase: int) -> void:
	var every: int = int(ECHO_EVERY[squad]) if phase >= 2 else int(REMEMBERS_ECHO_EVERY[squad])
	if (s.turn - 1) % every != 0 or Encounter._mobile_enemies(s) >= Encounter._spawn_cap(s):
		return
	var echo := Encounter.spawn(s, "fallen!" if aspect_of(u) == "remembers" and squad > 1 else "fallen", u.pos + Vector2i(0, 3), u)
	var names: Array = u.status.get("echo_names", [])
	var n := int(u.status.get("echoes_raised", 0))
	u.status["echoes_raised"] = n + 1
	echo.display_name = "Echo of %s" % names[n % names.size()] if not names.is_empty() else "Echo"
	Encounter.frenzy(s, echo)


## Regrown: once the core has been open a few turns a root grows back, and the Source is shielded again.
static func _regrow_open(s: GameState, u: Unit, squad: int) -> void:
	if int(u.status.get("regrown_cycles", 0)) >= int(REGROWN_CYCLES[squad]) \
			or s.turn - int(u.status.get("open_turn", s.turn)) < int(REGROWN_WINDOW[squad]):
		return
	u.status["regrown_cycles"] = int(u.status.get("regrown_cycles", 0)) + 1
	for i in REGROWN_ROOTS[squad]:
		var root := Encounter._place(s, "source_root", u.pos + REGROW_OFFSETS[(int(u.status.regrown_cycles) + i) % REGROW_OFFSETS.size()])
		root.status["spawner"] = {"kinds": ["runner", "spitter"], "every": 3 + int(Encounter.BOSS_SPAWN_EVERY_EXTRA[squad]),
			"next": s.turn + 2, "i": i}
		root.status["alerted"] = true
		s.emit({"type": "spawned", "unit": root.id, "kind": root.kind, "cell": root.pos, "from": u.id})
	u.status["tether"] = "source_root"
	u.status["boss_phase"] = 1
	s.emit({"type": "boss_phase", "unit": u.id, "phase": 1, "boss": u.kind, "text": "The roots grow back!"})
