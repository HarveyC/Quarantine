class_name Breaker
extends RefCounted
## The Act 1 boss "the Breaker": the wall engineers' demolition rig, running with nobody driving it.
## Three phases, each gated so no single hit skips one:
##   1 Plated (100-67%): a front plate takes 3 off every hit from level ground in its arc (flank it or
##     shoot from height). Winds up a marked charge lane every turn that ploughs through the cover along
##     it (and beside it), with a hound-and-relay escort.
##   2 Cracked (67-33%): the plate splits off. Still charges, and now rips rubble down (marked) on
##     whoever stands on high ground, or the best-covered soldier, which smashes the cover and brings
##     raised ground down.
##   3 Stripped (33-0%): fast, hits harder, and winds up two charge lanes at once, the second starting
##     where the first ends. Its runs shake every roof along them down.
## Encounter, EnemyBehaviours and FightBuilder call in here. OWNER: enemies workstream.

## Boss HP as a share of its 40, by squad size (FightBuilder, instead of SQUAD_BOSS_HEALTH).
const HEALTH := {1: 0.65, 2: 0.71, 3: 0.85, 4: 0.95}
const MOBILITY := {1: 4, 2: 5, 3: 6}
const DAMAGE := {1: Vector2i(4, 6), 2: Vector2i(4, 6), 3: Vector2i(6, 8)}
const PLATE_CRACKED_ARMOUR := 1
const DEBRIS_RANGE := 12
const DEBRIS_TARGETS := {1: 1, 2: 1, 3: 2, 4: 2}
const WAVE_FIRST := 3
const WAVE_EVERY := 4
## The rig's own machines: a Relay mast and the odd Hound or Loader frame. Hounds pour in later.
const ADDS := {1: [], 2: ["relay"], 3: ["relay", "hound"], 4: ["relay", "hound", "loader"]}
const WAVE_KINDS := {1: [], 2: ["hound"], 3: ["hound"], 4: ["hound", "hound"]}
## Score of a lane: each smashed cover tile, a soldier at its end, an ally at its end.
const COVER_SCORE := 1.0
const HIT_SCORE := 6.0
const ALLY_PENALTY := -20.0


static func setup(s: GameState, b: Unit, squad: int) -> void:
	b.status["alerted"] = true
	b.cooldowns["debris"] = 1
	if not WAVE_KINDS[squad].is_empty():
		if not s.encounter.has("waves"):
			s.encounter["waves"] = []
		s.encounter.waves.append({"turn": WAVE_FIRST, "every": WAVE_EVERY, "kinds": WAVE_KINDS[squad].duplicate()})


# --- phases --------------------------------------------------------------------------------

## HP at which phase 2 and phase 3 start.
static func gates(u: Unit) -> Array[int]:
	return [ceili(u.max_hp * 2 / 3.0), ceili(u.max_hp / 3.0)]


## Caps a hit so it stops at the next phase gate.
static func clamp_damage(u: Unit, amount: int) -> int:
	var phase := int(u.status.get("boss_phase", 1))
	var g := gates(u)
	if phase <= g.size() and u.hp > g[phase - 1]:
		return mini(amount, u.hp - g[phase - 1])
	return amount


static func on_damaged(s: GameState, u: Unit) -> void:
	var phase := int(u.status.get("boss_phase", 1))
	var g := gates(u)
	if phase > g.size() or u.hp > g[phase - 1]:
		return
	u.status.boss_phase = phase + 1
	u.mobility = MOBILITY[phase + 1]
	u.damage = DAMAGE[phase + 1]
	u.cooldowns.clear()
	if phase == 1:
		u.status.erase("plate")
		u.status["armour"] = PLATE_CRACKED_ARMOUR
		u.display_name = "The Breaker, Cracked"
		s.emit({"type": "boss_phase", "unit": u.id, "phase": 2, "boss": u.kind,
			"hp": u.hp, "max_hp": u.max_hp, "text": "The Breaker's plate splits!"})
		return
	u.status.erase("armour")
	u.display_name = "The Breaker, Stripped"
	s.emit({"type": "boss_phase", "unit": u.id, "phase": 3, "boss": u.kind,
		"hp": u.hp, "max_hp": u.max_hp, "text": "Stripped to the frame!"})


# --- its turn --------------------------------------------------------------------------------

static func take_turn(s: GameState, u: Unit) -> void:
	var phase := int(u.status.get("boss_phase", 1))
	if u.status.has("charge_dir"):
		_run_charges(s, u, phase)
		if not u.is_alive() or s.phase == Types.Phase.ENDED:
			return
		u.actions_left = 1   # the run itself ends the generic turn; the rig still has an arm free
	for step in 3:
		if u.actions_left <= 0 or not u.is_alive() or s.phase == Types.Phase.ENDED:
			return
		var hostiles := EnemyAI._hostiles(s, u)
		if hostiles.is_empty():
			return
		var went := false
		if phase == 2 and int(u.cooldowns.get("debris", 0)) <= 0:
			went = _debris(s, u, hostiles)
		if not went:
			went = _act(s, EnemyBehaviours.rush(s, u, hostiles, "slam"))
		if not went:
			return


## Runs the lane(s) it wound up last turn. In phase 3 the second lane follows the first.
static func _run_charges(s: GameState, u: Unit, phase: int) -> void:
	var second: Variant = u.status.get("charge_dir2")
	u.status.erase("charge_dir2")
	_try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "charge"})
	if second is Vector2i and phase >= 3 and u.is_alive() and s.phase != Types.Phase.ENDED:
		u.status["charge_dir"] = second
		u.actions_left = 1
		_try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "charge"})


## After its turn: marks the lane(s) it will run next turn.
static func end_turn(s: GameState, u: Unit) -> void:
	if not u.is_alive() or s.phase == Types.Phase.ENDED or u.status.has("charge_dir"):
		return
	var phase := int(u.status.get("boss_phase", 1))
	var first := best_lane(s, u, u.pos, Vector2i.ZERO)
	if first.is_empty():
		return
	u.status["charge_dir"] = first.dir
	var cells: Array[Vector2i] = []
	cells.assign(first.cells)
	if phase >= 3:
		var second := best_lane(s, u, lane_end(u, first), -first.dir)
		if not second.is_empty():
			u.status["charge_dir2"] = second.dir
			cells.append_array(second.cells)
	s.emit({"type": "telegraph", "unit": u.id, "kind": "charge", "cells": cells, "turn": s.turn + 1})


## The lanes it has wound up now: [{dir, cells, hit}], the second starting where the first ends.
static func lanes(s: GameState, u: Unit) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not u.status.has("charge_dir"):
		return out
	var first := EnemyAbilities.charge_lane(s, u, u.pos, u.status.charge_dir)
	first["dir"] = u.status.charge_dir
	out.append(first)
	if u.status.has("charge_dir2"):
		var second := EnemyAbilities.charge_lane(s, u, lane_end(u, first), u.status.charge_dir2)
		second["dir"] = u.status.charge_dir2
		out.append(second)
	return out


## The cell a run along `lane` leaves it on: the last free cell (just short of whoever it hits).
static func lane_end(u: Unit, lane: Dictionary) -> Vector2i:
	var cells: Array = lane.cells
	if lane.get("hit") != null:
		cells = cells.slice(0, cells.size() - 1)
	return cells[-1] if not cells.is_empty() else u.pos


## The best lane to wind up from `from`: through the most cover, or onto a soldier. {} when none is
## worth a run. `skip` is a direction to leave out (the second lane never doubles back).
static func best_lane(s: GameState, u: Unit, from: Vector2i, skip: Vector2i) -> Dictionary:
	var best := {}
	var best_score := 0.0
	for d in Grid.DIRS8:
		if skip != Vector2i.ZERO and d == skip:
			continue
		var lane := EnemyAbilities.charge_lane(s, u, from, d)
		var cells: Array = lane.cells
		if cells.size() < 2:
			continue
		var hit: Unit = lane.hit
		var path: Array[Vector2i] = []
		path.assign(cells.slice(0, cells.size() - 1) if hit != null else cells)
		var smash := 0
		for c in path:
			if s.grid.tile(c) == Types.Tile.LOW:
				smash += 1
		for c in swath(s.grid, path):
			if s.grid.tile(c) == Types.Tile.LOW and not path.has(c):
				smash += 1
		var score := smash * COVER_SCORE + cells.size() * 0.1
		if hit != null:
			score += HIT_SCORE if u.is_enemy_of(hit) else ALLY_PENALTY
		if score > best_score:
			best_score = score
			best = {"dir": d, "cells": cells, "hit": hit}
	return best


## Cells beside a run along `path` that it flattens as well.
static func swath(g: Grid, path: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in path:
		for d in Grid.DIRS8:
			var n: Vector2i = c + d
			if g.in_bounds(n) and not out.has(n):
				out.append(n)
	return out


# --- phase 2: debris -------------------------------------------------------------------------

## Rubble on whoever stands highest, else on the soldier with the most cover to lose: the 3x3
## around each (up to DEBRIS_TARGETS of them), minus tiles an ally stands on.
static func debris_cells(s: GameState, u: Unit, hostiles: Array[Unit]) -> Array[Vector2i]:
	var targets: Array[Unit] = []
	for h in hostiles:
		if s.grid.level(h.pos) > 0 and u.pos.distance_to(h.pos) <= DEBRIS_RANGE:
			targets.append(h)
	targets.sort_custom(func(a: Unit, b: Unit) -> bool: return s.grid.level(a.pos) > s.grid.level(b.pos))
	if targets.is_empty():
		for h in hostiles:
			if u.pos.distance_to(h.pos) <= DEBRIS_RANGE and Combat.cover_against(s.grid, h.pos, u.pos) != Types.Cover.NONE:
				targets.append(h)
				break
	var out: Array[Vector2i] = []
	var allies := {}
	for o in s.living(u.team):
		allies[o.pos] = true
	for t in targets.slice(0, DEBRIS_TARGETS[_squad(s)]):
		for c in EnemyAbilities.square(s.grid, t.pos, 1):
			if not out.has(c) and not allies.has(c):
				out.append(c)
	return out


static func _debris(s: GameState, u: Unit, hostiles: Array[Unit]) -> bool:
	var cells := debris_cells(s, u, hostiles)
	if cells.is_empty():
		return false
	return _try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "debris", "cells": cells})


static func _squad(s: GameState) -> int:
	return clampi(int(s.encounter.get("squad", 4)), 1, 4)


static func _act(s: GameState, a: Dictionary) -> bool:
	return not a.is_empty() and _try(s, a)


static func _try(s: GameState, a: Dictionary) -> bool:
	return EnemyBehaviours._try(s, a)
