class_name Choir
extends RefCounted
## The Choir: Harrow's survivors who followed the song. Their hits carry Infection like the Infected's.
## The group rule is Chant.
##   Acolyte  runs in at speed 6 and, once beside a soldier, swells; next turn it blooms in a 5x5 for
##            Infection and no damage. Killed while swelling it blooms anyway; killed before, it is just dead.
##   Cantor   sings a chant ring: every enemy within CHANT_RADIUS that the Cantor can see hits for
##            +CHANT_DAMAGE. Break its line of sight or kill it to end the bonus.
##   Hush     locks onto a soldier in sight, then silences their class abilities for two rounds. Break
##            line of sight or Suppress it between the lock and the silence.
## Status keys: soldier "hushed": phase index the silence lasts to (Combat.has_status); Hush "hushing":
## soldier id; Acolyte "swelling": turn, like the Bloater.
## Every action still goes through Rules.validate/apply. OWNER: enemies workstream.

const IDS: Array[String] = ["bloom", "hush", "silence"]


static func handles(id: String) -> bool:
	return IDS.has(id)


static func is_choir(u: Unit) -> bool:
	return EnemyRoster.FACTIONS.choir.has(u.kind)


# --- validation ---------------------------------------------------------------------------

static func validate(s: GameState, u: Unit, action: Dictionary) -> String:
	match str(action.ability):
		"bloom":
			if not u.status.has("swelling"):
				return "Not swelling"
		"hush":
			var t := s.get_unit(action.get("target", -1))
			if t == null or not t.is_alive() or not u.is_enemy_of(t) or t.status.get("hidden", false):
				return "Not an enemy"
			if u.status.has("hushing"):
				return "Already locked"
			if Combat.has_status(s, t, "hushed"):
				return "Already silenced"
			if Kit.cheb(u.pos, t.pos) > EnemyRoster.HUSH_RANGE or not Combat.can_see(s, u.pos, t.pos):
				return "No line of sight"
		"silence":
			var h := s.get_unit(int(u.status.get("hushing", -1)))
			if h == null or not h.is_alive() or not Combat.can_see(s, u.pos, h.pos):
				return "Lost the target"
			if Combat.has_status(s, u, "suppressed"):
				return "Suppressed"
	return ""


# --- rules --------------------------------------------------------------------------------

static func apply(s: GameState, u: Unit, action: Dictionary) -> void:
	match str(action.ability):
		"bloom": bloom(s, u)
		"hush": _hush(s, u, s.get_unit(action.target))
		"silence": _silence(s, u)


static func bloom_cells(s: GameState, u: Unit) -> Array[Vector2i]:
	return EnemyAbilities.square(s.grid, u.pos, EnemyRoster.BLOOM_RADIUS)


## The Acolyte goes off: Infection for every soldier in the 5x5 and spores on the ground. It dies.
static func bloom(s: GameState, u: Unit) -> void:
	u.status["burst"] = true
	u.status.erase("swelling")
	var extra := EnemyRoster.CHANT_INFECTION if chant_bonus(s, u) > 0 else 0
	var cells := bloom_cells(s, u)
	var victims: Array[Unit] = []
	for t in s.living(Types.Team.PLAYER):
		if cells.has(t.pos):
			victims.append(t)
	s.emit({"type": "ability", "unit": u.id, "ability": "bloom", "cell": u.pos, "cells": cells,
		"units": victims.map(func(x: Unit) -> int: return x.id), "infection": EnemyRoster.BLOOM_INFECTION + extra})
	if u.is_alive():
		u.hp = 0
		s.emit({"type": "died", "unit": u.id})
		Encounter.on_died(s, u)
	for t in victims:
		Infection.add(s, t, EnemyRoster.BLOOM_INFECTION + extra)
	Encounter.add_spores(s, cells, EnemyAbilities.SPORE_TURNS, u)


static func _hush(s: GameState, u: Unit, t: Unit) -> void:
	u.status["hushing"] = t.id
	s.emit({"type": "ability", "unit": u.id, "ability": "hush", "target": t.id})
	s.emit({"type": "telegraph", "unit": u.id, "kind": "hush", "cells": EnemyAbilities.line_cells(u.pos, t.pos),
		"turn": s.turn + 1, "target": t.id})


static func _silence(s: GameState, u: Unit) -> void:
	var t := s.get_unit(int(u.status.hushing))
	u.status.erase("hushing")
	t.status["hushed"] = Combat.phase_index(s) + EnemyRoster.HUSH_PHASES
	s.emit({"type": "ability", "unit": u.id, "ability": "silence", "target": t.id})
	s.emit({"type": "hushed", "unit": t.id, "by": u.id})


## +CHANT_DAMAGE for an enemy standing inside a Cantor's ring in its line of sight.
static func chant_bonus(s: GameState, source: Unit) -> int:
	if source.team != Types.Team.ENEMY or EnemyRoster.is_static(source):
		return 0
	for c in s.living(source.team):
		if c.kind == "cantor" and chanting(s, c, source):
			return EnemyRoster.CHANT_DAMAGE
	return 0


static func chanting(s: GameState, cantor: Unit, o: Unit) -> bool:
	return o != cantor and not EnemyRoster.is_static(o) and cantor.pos.distance_to(o.pos) <= EnemyRoster.CHANT_RADIUS \
		and Combat.can_see(s, cantor.pos, o.pos)


## Hook from Encounter.on_enemy_phase_start: each Cantor with a flock sings, so the view shows the ring.
static func on_enemy_phase_start(s: GameState) -> void:
	for c in s.living(Types.Team.ENEMY):
		if c.kind != "cantor":
			continue
		var flock: Array[int] = []
		for o in s.living(Types.Team.ENEMY):
			if chanting(s, c, o):
				flock.append(o.id)
		if not flock.is_empty():
			s.emit({"type": "chant", "unit": c.id, "units": flock})


## Hook from EnemyBehaviours.end_turn: an Acolyte beside a soldier swells.
static func end_turn(s: GameState, u: Unit, hostiles: Array[Unit]) -> void:
	if u.kind != "acolyte" or u.status.has("swelling") or not EnemyAI.is_alerted(u):
		return
	if EnemyBehaviours._adjacent(s, u.pos, hostiles) == 0:
		return
	u.status["swelling"] = s.turn
	s.emit({"type": "telegraph", "unit": u.id, "kind": "bloom", "cells": bloom_cells(s, u), "turn": s.turn + 1})


# --- AI -----------------------------------------------------------------------------------

## Hush: the soldier whose class abilities are most ready, else the most Infected one.
static func hush_target(s: GameState, u: Unit) -> Unit:
	var best: Unit = null
	var best_score := -INF
	for t in s.living(Types.Team.PLAYER):
		if validate(s, u, {"ability": "hush", "target": t.id}) != "":
			continue
		var ready := 0
		for a in Combat.available_abilities(s, t):
			if int(a.cooldown) <= 0:
				ready += 1
		var score := ready * 10.0 + t.infection / 25.0 - Kit.cheb(t.pos, u.pos) * 0.1
		if score > best_score:
			best_score = score
			best = t
	return best


static func hush(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	if int(u.cooldowns.get("hush", 0)) <= 0:
		var t := hush_target(s, u)
		if t != null:
			return EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "hush", "target": t.id})
		if u.actions_left >= 2:
			var adv := EnemyAI._advance(s, u, hostiles)
			if not adv.is_empty():
				return adv
	return EnemyBehaviours.support(s, u, hostiles)


## Cantor: stays behind its flock, close enough to see them.
static func cantor(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	return EnemyBehaviours.support(s, u, hostiles)


# --- view reads ---------------------------------------------------------------------------

## [cantor id, ally id] for every chant link the squad can see.
static func links(s: GameState) -> Array:
	var out: Array = []
	for c in s.living(Types.Team.ENEMY):
		if c.kind != "cantor" or not Vision.sees_unit(s, Types.Team.PLAYER, c):
			continue
		for o in s.living(Types.Team.ENEMY):
			if chanting(s, c, o) and Vision.sees_unit(s, Types.Team.PLAYER, o):
				out.append([c.id, o.id])
	return out
