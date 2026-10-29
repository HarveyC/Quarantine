class_name EnemyBehaviours
extends RefCounted
## The shared AI behaviours for the enemy roster, used by EnemyAI. Rush (Runner, Brute),
## Kite (Spitter) and pod activation live in EnemyAI; this adds Cover shooter (Fallen, Turned
## soldiers, Colonel Hale), Seek cluster (Bloater), Ambush (Lurker), Support (Shrieker), the
## Brute's charge and the bosses. Every action still goes through Rules.validate/apply.
## OWNER: enemies workstream.

const SUPPORT_MIN := 6.0
const SUPPORT_MAX := 10.0
const SCREAM_ALLIES := 2
const KINDS: Array[String] = ["fallen", "bloater", "broodling", "brute", "lurker", "shrieker",
	"leaper", "drifter", "sharpshooter", "burrower", "hooker", "sapper", "carapace", "stalker", "weaver", "cutter", "torchman", "fence", "shieldman", "overwatcher", "hound", "loader",
	"brood_mother", "breaker", "colonel_hale", "the_source"]


static func handles(s: GameState, u: Unit) -> bool:
	return KINDS.has(u.kind) or u.status.get("turned", false)


## Turns that skip the normal alert/choose loop. Returns true if the turn was handled.
static func custom_turn(s: GameState, u: Unit) -> bool:
	if u.kind == "emplacement":
		Security.emplacement_turn(s, u)
		return true
	if EnemyRoster.is_static(u):
		return true
	if u.kind == "brood_mother":
		BroodMother.take_turn(s, u)
		return true
	if u.kind == "breaker":
		Breaker.take_turn(s, u)
		return true
	if u.kind == "colonel_hale":
		ColonelHale.take_turn(s, u)
		return true
	if u.kind == "the_source":
		SourceBoss.take_turn(s, u)
		return true
	if u.status.has("swelling"):
		_try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "burst"})
		return true
	if u.status.has("charge_dir"):
		_try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "charge"})
		return true
	if u.status.has("pinning"):
		_try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "maul"})
		return true
	if u.status.has("leap_cell"):
		_try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "leap"})
		# It lands ready to fight: claws anyone in melee reach that the impact didn't throw clear.
		if u.is_alive() and s.phase != Types.Phase.ENDED:
			u.actions_left = 1
			for h in s.living():
				if u.is_enemy_of(h) and s.grid.melee_reach(u.pos, h.pos) \
						and _try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "claw", "target": h.id}):
					break
			u.actions_left = 0
		return true
	if u.status.has("emerge_cell"):
		_try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "erupt"})
		return true
	if u.status.has("hooked"):
		if _try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "reel"}):
			return true
		u.status.erase("hooked")
		s.emit({"type": "lock_lost", "unit": u.id})
	if u.status.has("sighted"):
		if _try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "snipe"}):
			return true
		u.status.erase("sighted")
		s.emit({"type": "lock_lost", "unit": u.id})
	if u.kind == "lurker" and u.status.get("hidden", false):
		_ambush(s, u)
		return true
	return false


static func choose(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	if u.status.get("turned", false):
		return cover_shooter(s, u, hostiles)
	match u.kind:
		"fallen": return cover_shooter(s, u, hostiles)
		"bloater", "broodling": return seek_cluster(s, u, hostiles)
		"brute": return rush(s, u, hostiles, "slam")
		"lurker": return _lurker(s, u, hostiles)
		"shrieker": return support(s, u, hostiles)
		"leaper": return _leaper(s, u, hostiles)
		"drifter": return _drifter(s, u, hostiles)
		"sharpshooter": return _sharpshooter(s, u, hostiles)
		"burrower": return _burrower(s, u, hostiles)
		"hooker": return _hooker(s, u, hostiles)
		"sapper": return _sapper(s, u, hostiles)
		"carapace": return rush(s, u, hostiles, "slam")
		"stalker": return _stalker(s, u, hostiles)
		"weaver": return _weaver(s, u, hostiles)
		"cutter": return Scavengers.cutter(s, u, hostiles)
		"torchman": return _sapper(s, u, hostiles, "firebomb")
		"fence": return Scavengers.fence(s, u, hostiles)
		"shieldman": return rush(s, u, hostiles, "slam")
		"overwatcher": return Security.overwatcher(s, u)
		"hound": return rush(s, u, Automata.hound_targets(hostiles), "claw")
		"loader": return rush(s, u, hostiles, "slam")
	return {}


## After the unit's turn: Bloaters swell next to clusters, Brutes wind up a charge.
static func end_turn(s: GameState, u: Unit) -> void:
	var hostiles := EnemyAI._hostiles(s, u)
	if u.status.get("plate", false):
		_face(s, u, hostiles)
	if u.kind == "breaker":
		Breaker.end_turn(s, u)
	if u.kind in ["bloater", "broodling"] and not u.status.has("swelling") and EnemyAI.is_alerted(u):
		var need := 1 if u.kind == "broodling" else 2
		if _adjacent(s, u.pos, hostiles) >= need:
			u.status["swelling"] = s.turn
			s.emit({"type": "telegraph", "unit": u.id, "kind": "burst",
				"cells": EnemyAbilities.square(s.grid, u.pos, 1), "turn": s.turn + 1})
	if u.kind == "leaper" and not u.status.has("leap_cell") and EnemyAI.is_alerted(u) and _adjacent(s, u.pos, hostiles) == 0:
		var cell := _best_landing(s, u, hostiles)
		if cell != Vector2i(-1, -1):
			u.status["leap_cell"] = cell
			s.emit({"type": "telegraph", "unit": u.id, "kind": "leap",
				"cells": EnemyAbilities.square(s.grid, cell, 1), "turn": s.turn + 1})
	if can_charge(u) and not u.status.has("charge_dir") and EnemyAI.is_alerted(u) and _adjacent(s, u.pos, hostiles) == 0:
		var best := {}
		var best_score := -INF
		for d in Grid.DIRS8:
			var lane := EnemyAbilities.charge_lane(s, u, u.pos, d)
			var hit: Unit = lane.hit
			if hit == null or not u.is_enemy_of(hit) or lane.cells.size() < 2:
				continue
			var score := EnemyAI._target_score(s, u, hit, u.pos)
			if score > best_score:
				best_score = score
				best = {"dir": d, "cells": lane.cells}
		if not best.is_empty():
			u.status["charge_dir"] = best.dir
			s.emit({"type": "telegraph", "unit": u.id, "kind": "charge", "cells": best.cells, "turn": s.turn + 1})


static func can_charge(u: Unit) -> bool:
	if u.kind == "brute" or u.kind == "loader":
		return true
	return u.kind == "colonel_hale" and int(u.status.get("boss_phase", 1)) >= 2


# --- behaviours ----------------------------------------------------------------------------

## Rush: melee an adjacent hostile with `ability`, else get next to the most exposed one.
static func rush(s: GameState, u: Unit, hostiles: Array[Unit], ability: String) -> Dictionary:
	var adjacent: Array[Unit] = []
	for h in hostiles:
		if s.grid.melee_reach(u.pos, h.pos):
			adjacent.append(h)
	adjacent.sort_custom(func(a: Unit, b: Unit) -> bool:
		return EnemyAI._target_score(s, u, a, u.pos) > EnemyAI._target_score(s, u, b, u.pos))
	for t in adjacent:
		var hit := EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": ability, "target": t.id})
		if not hit.is_empty():
			return hit
	if not adjacent.is_empty():
		return {}
	var reach := Rules.move_range(s, u)
	var best_cell := u.pos
	var best_score := -INF
	for h in hostiles:
		for d in Grid.DIRS8:
			var c: Vector2i = h.pos + d
			if c == u.pos or not reach.has(c) or not s.grid.melee_reach(c, h.pos):
				continue
			if EnemyAI.telegraph_cost(s, c) > 0.0:
				continue
			var score := EnemyAI._target_score(s, u, h, c) - int(reach[c]) * 0.1 \
					- maxi(0, EnemyAI.crowding(s, u, h) - 1) * 0.8
			if score > best_score:
				best_score = score
				best_cell = c
	if best_cell != u.pos:
		var move := EnemyAI._check(s, {"type": Types.MOVE, "unit": u.id, "to": best_cell})
		if not move.is_empty():
			return move
	return EnemyAI._advance(s, u, hostiles)


## Cover shooter: take the cover with the best shot, shoot, overwatch if nothing is in sight.
static func cover_shooter(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	var here := _cover_cell_score(s, u, u.pos, hostiles)
	var shot := EnemyAI._best_shot(s, u)
	if u.actions_left >= 2 or shot.is_empty():
		var reach := Rules.move_range(s, u)
		var best_cell := u.pos
		var best_score := here
		for c in reach:
			var score := _cover_cell_score(s, u, c, hostiles) - int(reach[c]) * 0.05
			if score > best_score:
				best_score = score
				best_cell = c
		if best_cell != u.pos and best_score > here + 0.5:
			var move := EnemyAI._check(s, {"type": Types.MOVE, "unit": u.id, "to": best_cell})
			if not move.is_empty():
				return move
	if not shot.is_empty():
		return shot.action
	if u.actions_left >= 2:
		var adv := EnemyAI._advance(s, u, hostiles)
		if not adv.is_empty():
			return adv
	return EnemyAI._check(s, {"type": Types.OVERWATCH, "unit": u.id})


static func _cover_cell_score(s: GameState, u: Unit, c: Vector2i, hostiles: Array[Unit]) -> float:
	var best_hit := 0
	var cover := 0.0
	var watchers := 0
	var nearest := INF
	for h in hostiles:
		nearest = minf(nearest, EnemyAI._dist(c, h.pos))
		if not Combat.can_see(s, c, h.pos):
			continue
		watchers += 1
		match Combat.cover_against(s.grid, c, h.pos):
			Types.Cover.FULL: cover += 2.0
			Types.Cover.HALF: cover += 1.0
			_: cover -= 1.5
		best_hit = maxi(best_hit, int(Combat.hit_chance(s, u, h, c).hit))
	var score := best_hit / 20.0 - Hazards.avoid_cost(s, u, c) - EnemyAI.telegraph_cost(s, c)
	if watchers > 0:
		score += cover / watchers
	if u.hp * 3 <= u.max_hp:
		score -= watchers * 1.5   # badly hurt: slip out of sight instead of trading
	if nearest > 10.0:
		score -= (nearest - 10.0) * 0.5
	return score


## Seek cluster: walk to the tile next to the most soldiers.
static func seek_cluster(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	var sources: Array[Vector2i] = []
	for h in hostiles:
		sources.append(h.pos)
	var field := EnemyAI._distance_field(s.grid, sources)
	var reach := Rules.move_range(s, u)
	var score_of := func(c: Vector2i) -> float:
		return _adjacent(s, c, hostiles) * 10.0 - float(field.get(c, 99)) - Hazards.avoid_cost(s, u, c)
	var here: float = score_of.call(u.pos)
	var best_cell := u.pos
	var best_score := here
	for c in reach:
		var score: float = score_of.call(c) - int(reach[c]) * 0.01
		if score > best_score:
			best_score = score
			best_cell = c
	if best_cell == u.pos:
		return {}
	return EnemyAI._check(s, {"type": Types.MOVE, "unit": u.id, "to": best_cell})


## Ambush: a hidden Lurker stays still until a soldier is in reach, then pounces on the one
## furthest from teammates.
static func _ambush(s: GameState, u: Unit) -> void:
	var t := _pounce_target(s, u)
	if t != null:
		EnemyAI.alert(s, u)
		_try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "pounce", "target": t.id})


static func _pounce_target(s: GameState, u: Unit) -> Unit:
	var best: Unit = null
	var best_iso := -1.0
	for t in s.living(Types.Team.PLAYER):
		if not u.is_enemy_of(t) or t.status.has("pinned_by"):
			continue
		if EnemyAbilities.validate(s, u, {"ability": "pounce", "target": t.id}) != "":
			continue
		var iso := INF
		for o in s.living(t.team):
			if o != t:
				iso = minf(iso, EnemyAI._dist(t.pos, o.pos))
		if iso > best_iso:
			best_iso = iso
			best = t
	return best


static func _lurker(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	var t := _pounce_target(s, u)
	if t != null:
		var p := EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "pounce", "target": t.id})
		if not p.is_empty():
			return p
	return rush(s, u, hostiles, "claw")


## Support: stay behind allies and out of sight; scream when 2+ allies are close.
static func support(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	var near_allies := 0
	for o in s.living(u.team):
		if o != u and not EnemyRoster.is_static(o) and u.pos.distance_to(o.pos) <= EnemyAbilities.SCREAM_RADIUS:
			near_allies += 1
	var scream := EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "scream"})
	var seen := _seen_by(s, u.pos, hostiles)
	if not scream.is_empty() and near_allies >= SCREAM_ALLIES and (not seen or u.actions_left < 2):
		return scream
	var reach := Rules.move_range(s, u)
	var here := _support_score(s, u, u.pos, hostiles)
	var best_cell := u.pos
	var best_score := here
	for c in reach:
		var score := _support_score(s, u, c, hostiles) - int(reach[c]) * 0.02
		if score > best_score:
			best_score = score
			best_cell = c
	if best_cell != u.pos and best_score > here + 0.25:
		var move := EnemyAI._check(s, {"type": Types.MOVE, "unit": u.id, "to": best_cell})
		if not move.is_empty():
			return move
	if not scream.is_empty() and near_allies >= SCREAM_ALLIES:
		return scream
	return {}


static func _support_score(s: GameState, u: Unit, c: Vector2i, hostiles: Array[Unit]) -> float:
	var nearest := INF
	for h in hostiles:
		nearest = minf(nearest, EnemyAI._dist(c, h.pos))
	var score := -Hazards.avoid_cost(s, u, c)
	if _seen_by(s, c, hostiles):
		score -= 3.0
	if nearest < SUPPORT_MIN:
		score -= (SUPPORT_MIN - nearest) * 1.5
	elif nearest > SUPPORT_MAX:
		score -= (nearest - SUPPORT_MAX) * 0.5
	for o in s.living(u.team):
		if o != u and not EnemyRoster.is_static(o) and Vector2(c).distance_to(Vector2(o.pos)) <= EnemyAbilities.SCREAM_RADIUS:
			score += 0.75
	return score


# --- vertical enemies ----------------------------------------------------------------------

## Leaper: claws if adjacent, and runs in to claw when a soldier is within one move; otherwise
## gets within leaping range and ends its turn so it can mark a landing spot (end_turn).
## Prefers spots next to soldiers on high ground or in clusters.
static func _leaper(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	for h in hostiles:
		if s.grid.melee_reach(u.pos, h.pos):
			var claw := EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "claw", "target": h.id})
			if not claw.is_empty():
				return claw
	if u.actions_left >= 2:
		var reach := Rules.move_range(s, u)
		for h in hostiles:
			for d in Grid.DIRS8:
				if reach.has(h.pos + d) and h.pos + d != u.pos:
					return EnemyAI._choose_runner(s, u, hostiles)
	if _best_landing(s, u, hostiles) != Vector2i(-1, -1):
		return {}
	return EnemyAI._advance(s, u, hostiles)


static func _best_landing(s: GameState, u: Unit, hostiles: Array[Unit]) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_score := -INF
	for c in EnemyAbilities.landing_cells(s, u):
		var score := 0.0
		for h in hostiles:
			if s.grid.touching(c, h.pos):
				score += 3.0 + EnemyTerrain.level(s, h.pos) * 2.0   # knock them off their perch
		score -= EnemyAI._dist(u.pos, c) * 0.1
		if score > best_score:
			best_score = score
			best = c
	return best


## Drifter: floats over everything to hang above the most exposed soldier, then drops on them.
static func _drifter(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	var target := _most_exposed(s, u, hostiles)
	if target == null:
		return {}
	if EnemyAI._cheb(u.pos, target.pos) <= EnemyAbilities.DROP_RANGE:
		var drop := EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "spore_drop", "target": target.id})
		if not drop.is_empty():
			return drop
	var best := u.pos
	var best_score := -INF
	for dy in range(-u.mobility, u.mobility + 1):
		for dx in range(-u.mobility, u.mobility + 1):
			var c := u.pos + Vector2i(dx, dy)
			if not s.grid.in_bounds(c) or s.grid.tile(c) == Types.Tile.WALL or (c != u.pos and s.unit_at(c) != null):
				continue
			var d := EnemyAI._cheb(c, target.pos)
			var score := -float(d)
			if d <= EnemyAbilities.DROP_RANGE:
				score += 10.0
				if Combat.cover_against(s.grid, target.pos, c) == Types.Cover.NONE:
					score += 2.0   # come at them from the open side
			if score > best_score:
				best_score = score
				best = c
	if best == u.pos:
		return {}
	return EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "drift", "cell": best})


## Sharpshooter: climbs to the best perch (high ground first), then locks on with its laser.
static func _sharpshooter(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	if u.actions_left >= 2:
		var here := _perch_score(s, u, u.pos, hostiles)
		var reach := Rules.move_range(s, u)
		var best := u.pos
		var best_score := here
		for c in reach:
			var score := _perch_score(s, u, c, hostiles) - int(reach[c]) * 0.05
			if score > best_score:
				best_score = score
				best = c
		if best != u.pos and best_score > here + 0.5:
			var move := EnemyAI._check(s, {"type": Types.MOVE, "unit": u.id, "to": best})
			if not move.is_empty():
				return move
	var target: Unit = null
	var best_hit := -1
	for t in Combat.visible_targets(s, u):
		var hit: int = Combat.hit_chance(s, u, t).hit
		if hit > best_hit:
			best_hit = hit
			target = t
	if target != null:
		var sight := EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "sight", "target": target.id})
		if not sight.is_empty():
			return sight
	if u.actions_left >= 2:
		var adv := EnemyAI._advance(s, u, hostiles)
		if not adv.is_empty():
			return adv
	return EnemyAI._check(s, {"type": Types.OVERWATCH, "unit": u.id})


static func _perch_score(s: GameState, u: Unit, c: Vector2i, hostiles: Array[Unit]) -> float:
	return _cover_cell_score(s, u, c, hostiles) + EnemyTerrain.level(s, c) * 3.0


## Burrower: claws if adjacent, otherwise tunnels toward the soldier on the highest ground.
static func _burrower(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	for h in hostiles:
		if s.grid.melee_reach(u.pos, h.pos):
			var claw := EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "claw", "target": h.id})
			if not claw.is_empty():
				return claw
	var target: Unit = null
	var best := -INF
	for h in hostiles:
		var score := EnemyTerrain.level(s, h.pos) * 5.0 + EnemyAI._target_score(s, u, h, u.pos)
		if score > best and u.pos.distance_to(h.pos) <= EnemyAbilities.BURROW_RANGE:
			best = score
			target = h
	if target != null:
		var b := EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "burrow", "target": target.id})
		if not b.is_empty():
			return b
	return EnemyAI._advance(s, u, hostiles)


static func _most_exposed(s: GameState, u: Unit, hostiles: Array[Unit]) -> Unit:
	var best: Unit = null
	var best_score := -INF
	for h in hostiles:
		var score := EnemyAI._target_score(s, u, h, u.pos)
		if score > best_score:
			best_score = score
			best = h
	return best


# --- 2026-10-25 sprint: Hooker, Sapper, Carapace, Stalker, Weaver ---------------------------

## Hooker: finds a perch with a clear line to a soldier 3-7 tiles away, locks on, and reels the
## pull that costs the squad most (off a roof, out of cover, onto a waiting Brute or Bloater).
static func _hooker(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	var best := {}
	var best_score := -INF
	for t in hostiles:
		var a := EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "hook", "target": t.id})
		if a.is_empty():
			continue
		var score := _hook_score(s, u, t)
		if score > best_score:
			best_score = score
			best = a
	if not best.is_empty():
		return best
	if u.actions_left >= 2:
		var reach := Rules.move_range(s, u)
		var here := _hook_perch(s, u, u.pos, hostiles)
		var best_cell := u.pos
		var cell_score := here
		for c in reach:
			var sc := _hook_perch(s, u, c, hostiles) - int(reach[c]) * 0.05
			if sc > cell_score:
				cell_score = sc
				best_cell = c
		if best_cell != u.pos and cell_score > here + 0.5:
			var move := EnemyAI._check(s, {"type": Types.MOVE, "unit": u.id, "to": best_cell})
			if not move.is_empty():
				return move
		var adv := EnemyAI._advance(s, u, hostiles)
		if not adv.is_empty():
			return adv
	return EnemyAI._check(s, {"type": Types.OVERWATCH, "unit": u.id})


## How good the pull is for the Infected: wounded and exposed targets, a landing beside friends,
## a drop off high ground, a soldier torn out of cover or out of overwatch.
static func _hook_score(s: GameState, u: Unit, t: Unit) -> float:
	var land := EnemyAbilities.reel_landing(s, u, t)
	var score := 4.0 + EnemyAI._target_score(s, u, t, u.pos) * 0.5
	for o in s.living(u.team):
		if o != u and not EnemyRoster.is_static(o) and EnemyAI._cheb(o.pos, land) <= 1:
			score += 3.0 if o.kind in ["brute", "carapace", "bloater", "runner", "leaper"] else 1.0
	score += EnemyTerrain.fall_damage(s, t.pos, land) * 1.5
	if Combat.cover_against(s.grid, t.pos, u.pos) != Types.Cover.NONE and Combat.cover_against(s.grid, land, u.pos) == Types.Cover.NONE:
		score += 2.0
	if Combat.is_overwatching(s, t) or Combat.is_hunkered(s, t):
		score += 2.0
	for o in s.living(t.team):
		if o != t and EnemyAI._cheb(o.pos, land) <= 1:
			score -= 2.0   # a squad-mate beside the landing makes the Hooker the target
	return score


static func _hook_perch(s: GameState, u: Unit, c: Vector2i, hostiles: Array[Unit]) -> float:
	var score := _cover_cell_score(s, u, c, hostiles) + EnemyTerrain.level(s, c) * 1.5
	var can := false
	for h in hostiles:
		var d := EnemyAI._cheb(c, h.pos)
		if d >= EnemyRoster.HOOK_MIN and d <= EnemyRoster.HOOK_RANGE and Combat.can_see(s, c, h.pos):
			can = true
			break
	return score + (5.0 if can else 0.0)


## Sapper: throws a satchel on the squad's cover, then runs. Walks to a cell with a clear throw when
## it has none, and keeps out of reach while the satchel is on cooldown.
static func _sapper(s: GameState, u: Unit, hostiles: Array[Unit], ability := "satchel") -> Dictionary:
	if int(u.cooldowns.get(ability, 0)) <= 0:
		var throw := _best_satchel(s, u, u.pos, hostiles)
		if not throw.is_empty():
			return EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": ability, "cell": throw.cell})
		if u.actions_left >= 2:
			var reach := Rules.move_range(s, u)
			var best_cell := u.pos
			var best_score := -INF
			for c in reach:
				var th := _best_satchel(s, u, c, hostiles)
				if th.is_empty():
					continue
				var sc := float(th.score) - int(reach[c]) * 0.1 - Hazards.avoid_cost(s, u, c)
				if sc > best_score:
					best_score = sc
					best_cell = c
			if best_cell != u.pos:
				var move := EnemyAI._check(s, {"type": Types.MOVE, "unit": u.id, "to": best_cell})
				if not move.is_empty():
					return move
			var adv := EnemyAI._advance(s, u, hostiles)
			if not adv.is_empty():
				return adv
		return {}
	# On cooldown: back off to 5-8 tiles from the squad, out of sight.
	var reach := Rules.move_range(s, u)
	var here := _flee_score(s, u, u.pos, hostiles)
	var best := u.pos
	var best_score := here
	for c in reach:
		var sc := _flee_score(s, u, c, hostiles) - int(reach[c]) * 0.02
		if sc > best_score:
			best_score = sc
			best = c
	if best != u.pos and best_score > here + 0.25:
		return EnemyAI._check(s, {"type": Types.MOVE, "unit": u.id, "to": best})
	return {}


static func _flee_score(s: GameState, u: Unit, c: Vector2i, hostiles: Array[Unit]) -> float:
	var nearest := INF
	for h in hostiles:
		nearest = minf(nearest, EnemyAI._dist(c, h.pos))
	var score := -Hazards.avoid_cost(s, u, c)
	if _seen_by(s, c, hostiles):
		score -= 2.0
	if EnemyAI.telegraph_cost(s, c) > 0.0:
		score -= 4.0
	if nearest < 5.0:
		score -= (5.0 - nearest) * 1.5
	elif nearest > 8.0:
		score -= (nearest - 8.0) * 0.5
	return score


## Best satchel from `from`: {cell, score}, or {} when no throw hits a soldier. Aims at the cover
## a soldier stands behind: more cracked cover, more squad-mates and fewer friends in the blast.
static func _best_satchel(s: GameState, u: Unit, from: Vector2i, hostiles: Array[Unit]) -> Dictionary:
	var best := {}
	var best_score := 0.0
	var seen := {}
	for h in hostiles:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c: Vector2i = h.pos + Vector2i(dx, dy)
				if seen.has(c) or not s.grid.in_bounds(c) or s.grid.tile(c) == Types.Tile.WALL:
					continue
				seen[c] = true
				if EnemyAI._cheb(from, c) > EnemyRoster.SATCHEL_RANGE or EnemyAI._cheb(from, c) <= 1 \
						or not Combat.can_see(s, from, c):
					continue
				var hits := 0
				var cover := 0.0
				var friends := 0
				for o in s.living():
					if o == u or EnemyAI._cheb(o.pos, c) > 1:
						continue
					if u.is_enemy_of(o):
						hits += 1
						for d in Grid.DIRS4:
							if s.grid.cover_toward(o.pos, d) > 0:
								cover += 0.4
					else:
						friends += 1
				if hits == 0:
					continue
				var score := hits * 3.0 + cover - friends * 4.0 - EnemyAI.telegraph_cost(s, c)
				if score > best_score:
					best_score = score
					best = {"cell": c, "score": score}
	return best


## Turns a Carapace's plate toward the nearest soldier and tells the view.
static func _face(s: GameState, u: Unit, hostiles: Array[Unit]) -> void:
	var near := _nearest(u, hostiles)
	if near == null:
		return
	var f := Vector2i(signi(near.pos.x - u.pos.x), signi(near.pos.y - u.pos.y))
	if f != Vector2i.ZERO and f != u.status.get("facing", Vector2i.ZERO):
		u.status["facing"] = f
		s.emit({"type": "braced", "unit": u.id, "facing": f})


## True when `src` hits a plated unit on its armoured side: the arc within about 50 degrees of where
## it faces, from level ground or below.
static func plate_covers(s: GameState, target: Unit, src: Unit) -> bool:
	if not target.status.get("plate", false) or src == null:
		return false
	if Elevation.height(s, src) > Elevation.height(s, target):
		return false
	var d := Vector2(src.pos - target.pos)
	var f := Vector2(target.status.get("facing", Vector2i(0, 1)))
	if d == Vector2.ZERO or f == Vector2.ZERO:
		return false
	return d.normalized().dot(f.normalized()) >= 0.6


## The three cells a Carapace's plate guards (for the overlay).
static func plate_cells(s: GameState, u: Unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var f: Vector2i = u.status.get("facing", Vector2i(0, 1))
	for d in Grid.DIRS8:
		if Vector2(d).normalized().dot(Vector2(f).normalized()) >= 0.6:
			var c: Vector2i = u.pos + d
			if s.grid.in_bounds(c) and s.grid.tile(c) != Types.Tile.WALL:
				out.append(c)
	return out


## Stalker: frozen while a soldier can see it, so it only claws what is already beside it. Unseen it
## closes on the soldier furthest from the rest (the extra reach comes from Encounter).
static func _stalker(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	if is_watched(s, u):
		for h in hostiles:
			if s.grid.melee_reach(u.pos, h.pos):
				var claw := EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "claw", "target": h.id})
				if not claw.is_empty():
					return claw
		return {}
	return rush(s, u, hostiles, "claw")


static func is_watched(s: GameState, u: Unit) -> bool:
	return Vision.sees_unit(s, Types.Team.PLAYER, u)


## Weaver: mends the most wounded Infected it can thread to, then keeps behind its friends.
static func _weaver(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	var t := EnemyAbilities.mend_target(s, u)
	if t != null:
		return EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "mend", "target": t.id})
	return support(s, u, hostiles)


# --- bosses --------------------------------------------------------------------------------

## 3x3 centre covering the most hostiles: {cell, hits}.
static func best_square(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	var best := {"cell": u.pos, "hits": 0}
	for h in hostiles:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c: Vector2i = h.pos + Vector2i(dx, dy)
				if not s.grid.in_bounds(c) or EnemyAI._cheb(c, u.pos) <= 1:
					continue
				var hits := 0
				for o in s.living():
					if EnemyAI._cheb(o.pos, c) <= 1:
						hits += 1 if u.is_enemy_of(o) else -1
				if hits > best.hits:
					best = {"cell": c, "hits": hits}
	return best


# --- helpers -------------------------------------------------------------------------------

static func _try(s: GameState, action: Dictionary) -> bool:
	return Rules.validate(s, action) == "" and Rules.apply(s, action)


## Hostiles `c` can reach in melee (Grid.melee_reach: same level or across a stair step).
static func _adjacent(s: GameState, c: Vector2i, hostiles: Array[Unit]) -> int:
	var n := 0
	for h in hostiles:
		if s.grid.melee_reach(c, h.pos):
			n += 1
	return n


static func _seen_by(s: GameState, c: Vector2i, hostiles: Array[Unit]) -> bool:
	for h in hostiles:
		if Combat.can_see(s, h.pos, c):
			return true
	return false


static func _nearest(u: Unit, hostiles: Array[Unit]) -> Unit:
	var best: Unit = null
	for h in hostiles:
		if best == null or EnemyAI._dist(u.pos, h.pos) < EnemyAI._dist(u.pos, best.pos):
			best = h
	return best
