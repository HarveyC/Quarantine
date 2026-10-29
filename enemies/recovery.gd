class_name Recovery
extends RefCounted
## Halden-Voss Recovery: the company's contractors, sent to bring a soldier back alive. People, so
## their hits deal damage only. The group rule is Capture.
##   Netter      a containment net: a hit pins the soldier (no actions) until a teammate hits the Netter
##               or they Struggle free. The Netter then just holds on.
##   Handler     Designates the most Infected soldier in sight; every Recovery enemy gets DESIGNATE_AIM
##               more aim against them until the Handler dies.
##   Sterilizer  lays a flame cone that goes off next enemy phase: damage to all in it, spores burned
##               off, and soldiers in it lose STERILIZE_CLEANSE Infection.
##   Collector   takes over a netted soldier and drags them DRAG_STEPS tiles a turn toward the nearest
##               edge. A soldier dragged onto the edge is captured and lost; kill the Collector first.
## Status keys: soldier "designated": Handler id; Handler "designating": soldier id; netted soldiers
## use the Lurker's "pinned_by"/"pinning" pair (Encounter.release_pin, struggle, check_pins).
## Every action still goes through Rules.validate/apply. OWNER: enemies workstream.

const IDS: Array[String] = ["net", "designate", "sterilize", "drag"]


static func handles(id: String) -> bool:
	return IDS.has(id)


static func is_recovery(u: Unit) -> bool:
	return EnemyRoster.FACTIONS.recovery.has(u.kind)


# --- validation ---------------------------------------------------------------------------

static func validate(s: GameState, u: Unit, action: Dictionary) -> String:
	var id: String = action.ability
	if id == "sterilize":
		return _sterilize_error(s, u, action.get("cell"))
	var t := s.get_unit(action.get("target", -1))
	if t == null or not t.is_alive():
		return "No such target"
	if not u.is_enemy_of(t) or t.status.get("hidden", false):
		return "Not an enemy"
	match id:
		"net":
			if not s.grid.melee_reach(u.pos, t.pos):
				return "Not adjacent"
			if u.status.has("pinning"):
				return "Already holding"
			if t.status.has("pinned_by"):
				return "Already pinned"
		"designate":
			if designation_of(s, u) != null:
				return "Already designating"
			if t.status.has("designated"):
				return "Already designated"
			if Kit.cheb(u.pos, t.pos) > EnemyRoster.DESIGNATE_RANGE or not Combat.can_see(s, u.pos, t.pos):
				return "No line of sight"
		"drag":
			if not netted(s, t):
				return "Not netted"
			if not s.grid.melee_reach(u.pos, t.pos):
				return "Not adjacent"
			if drag_path(s, u).is_empty() and Scavengers.edge_dist(s, u.pos) > 0:
				return "Blocked"
	return ""


static func _sterilize_error(s: GameState, u: Unit, cell: Variant) -> String:
	if not cell is Vector2i or not s.grid.in_bounds(cell):
		return "Invalid cell"
	var d := Kit.cheb(u.pos, cell)
	if d < 1 or d > EnemyRoster.STERILIZE_RANGE:
		return "Out of range"
	if not Combat.can_see(s, u.pos, cell):
		return "No line of sight"
	return ""


# --- rules --------------------------------------------------------------------------------

static func apply(s: GameState, u: Unit, action: Dictionary) -> void:
	match str(action.ability):
		"net": _net(s, u, s.get_unit(action.target))
		"designate": _designate(s, u, s.get_unit(action.target))
		"sterilize": _sterilize(s, u, action.cell)
		"drag": _drag(s, u, s.get_unit(action.target))


## The soldier held by a Netter or Collector, not by a Lurker.
static func netted(s: GameState, t: Unit) -> bool:
	var l := s.get_unit(int(t.status.get("pinned_by", -1)))
	return l != null and l.kind in ["netter", "collector"]


static func _net(s: GameState, u: Unit, t: Unit) -> void:
	var odds := Combat.melee_chance(s, u, t)
	var r := Combat.resolve_roll(s.rng.randi_range(1, 100), odds)
	var hit: bool = r.hit or r.graze
	var dmg := 0
	if hit:
		dmg = Combat.final_damage(s.rng.randi_range(u.damage.x, u.damage.y), r.graze, false)
	s.emit({"type": "ability", "unit": u.id, "ability": "net", "target": t.id, "hit": hit, "damage": dmg, "chance": odds.hit})
	if not hit:
		return
	if dmg > 0:
		Rules.deal_damage(s, t, dmg, u)
	if t.is_alive() and u.is_alive() and t.team == Types.Team.PLAYER and not t.status.has("pinned_by"):
		hold(s, u, t)
		s.emit({"type": "pinned", "unit": t.id, "by": u.id, "net": true})


## `u` takes hold of `t`: no actions for the soldier until the hold breaks.
static func hold(s: GameState, u: Unit, t: Unit) -> void:
	t.status["pinned_by"] = u.id
	t.status["pinned_at"] = s.turn
	u.status["pinning"] = t.id
	t.overwatch = false
	t.hunkered = false
	t.actions_left = 0


# --- Handler ------------------------------------------------------------------------------

## The soldier `u` has designated, if it still stands and the mark holds.
static func designation_of(s: GameState, u: Unit) -> Unit:
	var t := s.get_unit(int(u.status.get("designating", -1)))
	if t != null and t.is_alive() and int(t.status.get("designated", -1)) == u.id:
		return t
	return null


static func _designate(s: GameState, u: Unit, t: Unit) -> void:
	t.status["designated"] = u.id
	u.status["designating"] = t.id
	s.emit({"type": "ability", "unit": u.id, "ability": "designate", "target": t.id})


## The soldier a Handler would designate: most Infection, then nearest.
static func designate_target(s: GameState, u: Unit) -> Unit:
	var best: Unit = null
	for t in s.living(Types.Team.PLAYER):
		if validate(s, u, {"ability": "designate", "target": t.id}) != "":
			continue
		if best == null or t.infection > best.infection \
				or (t.infection == best.infection and Kit.cheb(t.pos, u.pos) < Kit.cheb(best.pos, u.pos)):
			best = t
	return best


## Breakdown term for Combat.hit_chance / melee_chance: Recovery hits the designated soldier easier.
static func odds_terms(s: GameState, attacker: Unit, target: Unit, breakdown: Array) -> void:
	if attacker.team != Types.Team.ENEMY or not is_recovery(attacker) or not target.status.has("designated"):
		return
	var h := s.get_unit(int(target.status.designated))
	if h != null and h.is_alive():
		breakdown.append(["Designated", EnemyRoster.DESIGNATE_AIM])


## Hook from Encounter.on_died: a dead Handler's mark lapses.
static func on_died(s: GameState, u: Unit) -> void:
	if u.kind == "handler":
		for t in s.units:
			if int(t.status.get("designated", -1)) == u.id:
				t.status.erase("designated")
				s.emit({"type": "mark_lapsed", "unit": t.id, "by": u.id})


# --- Sterilizer ---------------------------------------------------------------------------

## Floor a flame cone from `origin` aimed at `cell` covers: within STERILIZE_LENGTH, inside about
## 30 degrees either side of the aim, in line of sight.
static func cone(s: GameState, origin: Vector2i, cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var aim := Vector2(cell - origin).normalized()
	var r := EnemyRoster.STERILIZE_LENGTH
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var d := Vector2i(dx, dy)
			var c := origin + d
			if d == Vector2i.ZERO or not s.grid.in_bounds(c) or not s.grid.is_walkable(c):
				continue
			if Vector2(d).normalized().dot(aim) < 0.86 or Vector2(d).length() > r + 0.5 or not Combat.can_see(s, origin, c):
				continue
			out.append(c)
	return out


static func _sterilize(s: GameState, u: Unit, cell: Vector2i) -> void:
	var cells := cone(s, u.pos, cell)
	u.status["facing"] = Vector2i(signi(cell.x - u.pos.x), signi(cell.y - u.pos.y))
	s.emit({"type": "ability", "unit": u.id, "ability": "sterilize", "cell": cell, "cells": cells})
	Encounter.add_telegraph(s, {"kind": "sterilize", "cells": cells, "turn": s.turn + 1,
		"damage": EnemyRoster.STERILIZE_DAMAGE, "source": u.id, "smash": false, "unit": u.id,
		"cleanse": EnemyRoster.STERILIZE_CLEANSE, "burn": true})


## Hook from Encounter._resolve_telegraphs for a Sterilizer's cone once it has gone off.
static func after_strike(s: GameState, t: Dictionary, victims: Array[Unit]) -> void:
	if not t.get("burn", false):
		return
	Hazards.remove(s, t.cells, "spore")
	for v in victims:
		if v.is_alive() and v.team == Types.Team.PLAYER and int(t.get("cleanse", 0)) > 0 and v.infection > 0:
			var before := v.infection
			Infection.add(s, v, -int(t.cleanse))
			if v.infection < before:
				s.emit({"type": "cleansed", "unit": v.id, "amount": before - v.infection})


# --- Collector ----------------------------------------------------------------------------

## The soldier `u` is holding, or null.
static func held(s: GameState, u: Unit) -> Unit:
	var t := s.get_unit(int(u.status.get("pinning", -1)))
	if t != null and t.is_alive() and int(t.status.get("pinned_by", -1)) == u.id:
		return t
	return null


## The cells `u` would walk dragging its soldier: up to DRAG_STEPS, each closer to the nearest edge,
## over open floor and never up a step. Empty when it is walled in.
static func drag_path(s: GameState, u: Unit) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var c := u.pos
	var occ := s.occupied(u.id)
	for i in EnemyRoster.DRAG_STEPS:
		var best := c
		var best_edge := Scavengers.edge_dist(s, c)
		for d in Grid.DIRS8:
			var n: Vector2i = c + d
			if not s.grid.is_walkable(n) or occ.has(n) or not s.grid.touching(c, n):
				continue
			if EnemyTerrain.level(s, n) > EnemyTerrain.level(s, c):
				continue
			if d.x != 0 and d.y != 0 and not (s.grid.is_walkable(c + Vector2i(d.x, 0)) and s.grid.is_walkable(c + Vector2i(0, d.y))):
				continue
			var e := Scavengers.edge_dist(s, n)
			if e < best_edge:
				best_edge = e
				best = n
		if best == c:
			break
		c = best
		path.append(c)
		if best_edge == 0:
			break
	return path


static func _drag(s: GameState, u: Unit, t: Unit) -> void:
	var old := s.get_unit(int(t.status.get("pinned_by", -1)))
	if old != null and old != u:
		old.status.erase("pinning")
	t.status["pinned_by"] = u.id
	u.status["pinning"] = t.id
	var path := drag_path(s, u)
	if path.is_empty():   # already on the edge: nothing left to drag along
		s.emit({"type": "ability", "unit": u.id, "ability": "drag", "target": t.id, "path": path})
		_capture(s, u, t)
		return
	var from := u.pos
	var t_from := t.pos
	var behind: Array[Vector2i] = [from]
	for i in range(path.size() - 1):
		behind.append(path[i])
	u.pos = path[-1]
	t.pos = behind[-1]
	s.emit({"type": "ability", "unit": u.id, "ability": "drag", "target": t.id, "path": path})
	s.emit({"type": "move", "unit": u.id, "from": from, "path": path})
	s.emit({"type": "move", "unit": t.id, "from": t_from, "path": behind, "knockback": true, "dragged": true})
	if Scavengers.edge_dist(s, u.pos) == 0:
		_capture(s, u, t)


## The Collector reaches the edge with its soldier: they are gone, and so is the Collector.
static func _capture(s: GameState, u: Unit, t: Unit) -> void:
	u.status.erase("pinning")
	t.status.erase("pinned_by")
	t.status.erase("pinned_at")
	s.emit({"type": "captured", "unit": t.id, "by": u.id})
	Rules.deal_damage(s, t, t.hp + 999, null)
	if u.is_alive():
		Scavengers.escape(s, u)


# --- AI -----------------------------------------------------------------------------------

## Rushes and nets the soldier it can reach that is not already held.
static func netter(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	if u.status.has("pinning"):
		return {}
	var free: Array[Unit] = []
	for h in hostiles:
		if not h.status.has("pinned_by"):
			free.append(h)
	return EnemyBehaviours.rush(s, u, free if not free.is_empty() else hostiles, "net")


## Designates a soldier when it has none marked, otherwise keeps behind its friends.
static func handler(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	if designation_of(s, u) == null:
		var t := designate_target(s, u)
		if t != null:
			return EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "designate", "target": t.id})
	return EnemyBehaviours.support(s, u, hostiles)


## Best cone `u` could lay from `from`: {cell, score}. Soldiers in the flame count for it and its own
## side counts against it.
static func best_cone(s: GameState, u: Unit, from: Vector2i, hostiles: Array[Unit]) -> Dictionary:
	var best := {}
	var best_score := 0.0
	for h in hostiles:
		var d := Kit.cheb(from, h.pos)
		if d < 1 or d > EnemyRoster.STERILIZE_RANGE or not Combat.can_see(s, from, h.pos):
			continue
		var score := 0.0
		for c in cone(s, from, h.pos):
			var o := s.unit_at(c)
			if o == null or o == u:
				continue
			if u.is_enemy_of(o):
				score += 3.0 + (1.5 if o.infection >= 25 else 0.0)   # the flame scrubs the Infection that gives them power
			else:
				score -= 3.0
		if score > best_score:
			best_score = score
			best = {"cell": h.pos, "score": score}
	return best


## Lays a cone when one catches the squad, else steps to a cell that can, else keeps its distance.
static func sterilizer(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	if int(u.cooldowns.get("sterilize", 0)) <= 0:
		var here := best_cone(s, u, u.pos, hostiles)
		if not here.is_empty():
			return EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "sterilize", "cell": here.cell})
		if u.actions_left >= 2:
			var reach := Rules.move_range(s, u)
			var best_cell := u.pos
			var best_score := 0.0
			for c in reach:
				var th := best_cone(s, u, c, hostiles)
				var sc := float(th.get("score", 0.0)) - int(reach[c]) * 0.1 - Hazards.avoid_cost(s, u, c) - EnemyAI.telegraph_cost(s, c)
				if not th.is_empty() and sc > best_score:
					best_score = sc
					best_cell = c
			if best_cell != u.pos:
				return EnemyAI._check(s, {"type": Types.MOVE, "unit": u.id, "to": best_cell})
			return EnemyAI._advance(s, u, hostiles)
		return {}
	return EnemyBehaviours.support(s, u, hostiles)


## The soldier a Collector wants: one a Netter holds, nearest first.
static func netted_prize(s: GameState, u: Unit) -> Unit:
	var best: Unit = null
	for t in s.living(Types.Team.PLAYER):
		if not netted(s, t) or not u.is_enemy_of(t):
			continue
		if best == null or Kit.cheb(t.pos, u.pos) < Kit.cheb(best.pos, u.pos):
			best = t
	return best


## A Collector's own turn: keep dragging what it holds, or go and take over a netted soldier. False when
## there is nobody to collect, so it fights like any melee enemy.
static func collector_turn(s: GameState, u: Unit) -> bool:
	var t := held(s, u)
	if t == null:
		t = netted_prize(s, u)
		if t == null:
			return false
		if not s.grid.melee_reach(u.pos, t.pos):
			var one: Array[Unit] = [t]
			var step := EnemyBehaviours.rush(s, u, one, "drag")
			if not step.is_empty():
				Rules.apply(s, step)
			if not u.is_alive() or u.actions_left <= 0 or not s.grid.melee_reach(u.pos, t.pos):
				return true
	EnemyBehaviours._try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "drag", "target": t.id})
	return true


## Intent for a Collector, or {} to fall through to the generic rows.
static func collector_intent(s: GameState, u: Unit) -> Dictionary:
	var t := held(s, u)
	if t != null:
		return {"icon": "drag", "label": "DRAGGING", "target": t.id}
	var prize := netted_prize(s, u)
	if prize != null:
		return {"icon": "drag", "label": "COLLECTING", "target": prize.id}
	return {}
