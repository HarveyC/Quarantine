class_name EnemyAI
extends RefCounted
## Decides actions for AI-controlled units: enemies, Turned soldiers and Lapsed soldiers.
## OWNER: AI workstream. `take_turn` is the contract.
##
## A small utility AI: every step it builds candidate actions, scores them, and applies the
## first one that `Rules.validate` accepts. Abilities are only used when validate accepts them,
## so the AI degrades gracefully to SHOOT / MOVE if Combat rejects an ability.
##
## Activation: enemies start dormant (no `status["alerted"]`). They wake when a hostile is in
## sight at the start of their turn, when they have taken damage, or when an alerted ally is
## within POD_RADIUS (pod alert, which chains). Waking emits {"type": "alerted", "unit": id} once.

const POD_RADIUS := 6.0
const SPIT_RANGE := 7.0
const SPITTER_MIN_DIST := 4.0
const SPITTER_MAX_DIST := 7.0
const DORMANT_SHUFFLE_CHANCE := 0.25
const MAX_STEPS_PER_TURN := 6   # hard cap on decisions per turn, on top of actions_left
const MAX_ABILITY_TRIES := 8    # candidate cells/targets validated per ability per step


## Spend `u.actions_left` by calling Rules.apply(s, action) until done.
## Never applies an action that Rules.validate rejected, and always terminates.
static func take_turn(s: GameState, u: Unit) -> void:
	if not _can_act(s, u):
		return
	if u.status.get("lapsed", false):
		_lapsed_turn(s, u)
		return
	if EnemyBehaviours.custom_turn(s, u):
		return
	if not _update_alert(s, u):
		_dormant_turn(s, u)
		return
	var steps := 0
	while _can_act(s, u) and steps < MAX_STEPS_PER_TURN:
		steps += 1
		var action := _choose(s, u)
		if action.is_empty() or not Rules.apply(s, action):
			return


# --- Public helpers --------------------------------------------------------------------------

static func is_alerted(u: Unit) -> bool:
	return u.status.get("alerted", false)


## Wakes `u` (and, through pod alert, dormant allies near it). Emits "alerted" once per unit.
## Other modules may call this, e.g. when a dormant enemy is shot at.
static func alert(s: GameState, u: Unit) -> void:
	if is_alerted(u) or not u.is_alive():
		return
	var queue: Array[Unit] = [u]
	u.status["alerted"] = true
	s.emit({"type": "alerted", "unit": u.id})
	while not queue.is_empty():
		var a: Unit = queue.pop_front()
		for o in s.living(a.team):
			if is_alerted(o) or o.status.get("lapsed", false):
				continue
			if a.pos.distance_to(o.pos) <= POD_RADIUS:
				o.status["alerted"] = true
				s.emit({"type": "alerted", "unit": o.id})
				queue.append(o)


# --- Activation ------------------------------------------------------------------------------

static func _can_act(s: GameState, u: Unit) -> bool:
	return u.is_alive() and u.actions_left > 0 and s.phase != Types.Phase.ENDED


## Returns true if `u` is (now) alerted.
static func _update_alert(s: GameState, u: Unit) -> bool:
	if is_alerted(u):
		return true
	# Turned soldiers (and any non-Infected kind) are always active.
	if not UnitData.ENEMIES.has(u.kind):
		return true
	var wake := u.hp < u.max_hp
	if not wake:
		for h in _hostiles(s, u):
			if Combat.can_see(s, u.pos, h.pos) and Kit.can_be_spotted(s, u, h):
				wake = true
				break
	if not wake:
		for o in s.living(u.team):
			if o != u and is_alerted(o) and not o.status.get("lapsed", false) \
					and o.pos.distance_to(u.pos) <= POD_RADIUS:
				wake = true
				break
	if wake:
		alert(s, u)
	return wake


## Dormant enemies occasionally shuffle 1-2 tiles and otherwise do nothing.
static func _dormant_turn(s: GameState, u: Unit) -> void:
	if s.rng.randf() >= DORMANT_SHUFFLE_CHANCE:
		return
	var cells: Array = s.grid.reachable(u.pos, 2, s.occupied(u.id)).keys()
	cells.erase(u.pos)
	if cells.is_empty():
		return
	var to: Vector2i = cells[s.rng.randi_range(0, cells.size() - 1)]
	var action := {"type": Types.MOVE, "unit": u.id, "to": to}
	if Rules.validate(s, action) == "":
		Rules.apply(s, action)


# --- Lapsed soldiers -------------------------------------------------------------------------

## Confused: 50% shoot the nearest visible unit of any team, else wander to a random cell.
static func _lapsed_turn(s: GameState, u: Unit) -> void:
	var steps := 0
	while _can_act(s, u) and steps < MAX_STEPS_PER_TURN:
		steps += 1
		var action := {}
		if s.rng.randf() < 0.5:
			var nearest: Unit = null
			for t in Combat.visible_targets(s, u):
				if nearest == null or _dist(u.pos, t.pos) < _dist(u.pos, nearest.pos):
					nearest = t
			if nearest != null:
				action = _check(s, {"type": Types.SHOOT, "unit": u.id, "target": nearest.id})
		if action.is_empty():
			var cells: Array = Rules.move_range(s, u).keys()
			cells.erase(u.pos)
			if not cells.is_empty():
				var to: Vector2i = cells[s.rng.randi_range(0, cells.size() - 1)]
				action = _check(s, {"type": Types.MOVE, "unit": u.id, "to": to})
		if action.is_empty() or not Rules.apply(s, action):
			return


# --- Decision making -------------------------------------------------------------------------

## Returns an action that Rules.validate accepts, or {} to end the turn.
static func _choose(s: GameState, u: Unit) -> Dictionary:
	var hostiles := _hostiles(s, u)
	if hostiles.is_empty():
		return {}
	match u.kind:
		"runner": return _choose_runner(s, u, hostiles)
		"spitter": return _choose_spitter(s, u, hostiles)
	if u.abilities.has("lunge") or u.abilities.has("bash"):
		var strike := _melee_soldier_strike(s, u)
		if not strike.is_empty():
			return strike
	if EnemyBehaviours.handles(s, u):
		return EnemyBehaviours.choose(s, u, hostiles)
	return _choose_generic(s, u, hostiles)


## A Turned Reaper or Warden: Bash an adjacent hostile, else Lunge / Shield Charge the best target
## in reach. {} when neither is possible (it then shoots or advances like anyone else).
static func _melee_soldier_strike(s: GameState, u: Unit) -> Dictionary:
	var best := {}
	var best_score := -INF
	for id in ["bash", "lunge", "shield_charge"]:
		if not u.abilities.has(id):
			continue
		for t in _hostiles(s, u):
			var score := _target_score(s, u, t, u.pos) + (2.0 if id == "bash" else 0.0)
			if score <= best_score:
				continue
			var action := _check(s, {"type": Types.ABILITY, "unit": u.id, "ability": id, "target": t.id})
			if not action.is_empty():
				best_score = score
				best = action
	return best


## Melee rushers keep clear of a guarding Warden's reach: stepping next to one gets them bashed.
static func _guard_penalty(s: GameState, u: Unit, c: Vector2i) -> float:
	return 3.0 if not ClassAbilities.guards_against(s, u, c).is_empty() else 0.0


## Shoot the best visible target, else advance toward the nearest hostile.
static func _choose_generic(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	var shot := _best_shot(s, u)
	if not shot.is_empty():
		return shot.action
	return _advance(s, u, hostiles)


## Melee rusher: claw an adjacent hostile, else run next to the best target, else close in.
static func _choose_runner(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	# 1. Adjacent: claw (or shoot if claw is unavailable).
	var adjacent: Array[Unit] = []
	for h in hostiles:
		if _cheb(u.pos, h.pos) == 1:
			adjacent.append(h)
	if not adjacent.is_empty():
		adjacent.sort_custom(func(a: Unit, b: Unit) -> bool:
			return _target_score(s, u, a, u.pos) > _target_score(s, u, b, u.pos))
		for t in adjacent:
			var claw := _check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "claw", "target": t.id})
			if not claw.is_empty():
				return claw
		for t in adjacent:
			var shoot := _check(s, {"type": Types.SHOOT, "unit": u.id, "target": t.id})
			if not shoot.is_empty():
				return shoot
	# 2. Reach a free cell next to a target this move.
	var reach := Rules.move_range(s, u)
	var best_cell := u.pos
	var best_score := -INF
	for h in hostiles:
		for d in Grid.DIRS8:
			var c: Vector2i = h.pos + d
			if c == u.pos or not reach.has(c):
				continue
			var steps: int = reach[c]
			var score := _target_score(s, u, h, c) - steps * 0.1 - _guard_penalty(s, u, c)
			if d.x == 0 or d.y == 0:
				score += 0.5   # orthogonal adjacency is valid for any melee adjacency rule
			if score > best_score:
				best_score = score
				best_cell = c
	if best_cell != u.pos:
		var move := _check(s, {"type": Types.MOVE, "unit": u.id, "to": best_cell})
		if not move.is_empty():
			return move
	# 3. Out of reach: close the distance through cover; if stuck, shoot whatever is visible.
	var adv := _advance(s, u, hostiles, true)
	if not adv.is_empty():
		return adv
	var shot := _best_shot(s, u)
	return shot.action if not shot.is_empty() else {}


## Ranged: hold a covered position 4-7 tiles from the squad, spit at clusters, otherwise shoot.
static func _choose_spitter(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	var attack := _spitter_attack(s, u, hostiles)
	var here := _spitter_cell_score(s, u, u.pos, hostiles)
	var reach := Rules.move_range(s, u)
	var best_cell := u.pos
	var best_score := here
	for c in reach:
		var steps: int = reach[c]
		var score := _spitter_cell_score(s, u, c, hostiles) - steps * 0.05
		if score > best_score:
			best_score = score
			best_cell = c
	var wants_move := best_cell != u.pos and best_score > here + 0.5
	if wants_move and (u.actions_left >= 2 or attack.is_empty()):
		var move := _check(s, {"type": Types.MOVE, "unit": u.id, "to": best_cell})
		if not move.is_empty():
			return move
	if not attack.is_empty():
		return attack
	if u.actions_left >= 2:
		var adv := _advance(s, u, hostiles)
		if not adv.is_empty():
			return adv
	return _check(s, {"type": Types.OVERWATCH, "unit": u.id})


static func _spitter_attack(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	var spit := _best_spit(s, u, hostiles)
	var shot := _best_shot(s, u)
	if not spit.is_empty() and spit.hits >= 2:
		return spit.action
	if not shot.is_empty() and shot.hit >= 50:
		return shot.action
	if not spit.is_empty():
		return spit.action
	if not shot.is_empty():
		return shot.action
	return {}


## Best valid spit: {action, hits}, or {}. Scores cells by hostiles hit minus allies hit (radius 1).
static func _best_spit(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	if not u.abilities.has("spit") or u.cooldowns.get("spit", 0) > 0:
		return {}
	var scored: Array = []   # [hits: int, cell: Vector2i]
	var seen := {}
	for h in hostiles:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c: Vector2i = h.pos + Vector2i(dx, dy)
				if seen.has(c) or not s.grid.in_bounds(c) or _dist(u.pos, c) > SPIT_RANGE:
					continue
				seen[c] = true
				if _cheb(c, u.pos) <= 1:
					continue
				var hits := 0
				for o in s.living():
					if _cheb(o.pos, c) <= 1:
						hits += 1 if u.is_enemy_of(o) else -1
				if hits > 0:
					scored.append([hits, c])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for i in mini(scored.size(), MAX_ABILITY_TRIES):
		var action := _check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "spit", "cell": scored[i][1]})
		if not action.is_empty():
			return {"action": action, "hits": scored[i][0]}
	return {}


## Best valid shot: {action, hit, target}, or {}.
static func _best_shot(s: GameState, u: Unit) -> Dictionary:
	var best := {}
	var best_score := -INF
	for t in Combat.visible_targets(s, u):
		var odds := Combat.hit_chance(s, u, t)
		var hit: int = odds.get("hit", 0)
		var score := float(hit) + _target_score(s, u, t, u.pos) * 3.0
		if u.damage.y >= t.hp:
			score += 20.0
		if score > best_score:
			var action := _check(s, {"type": Types.SHOOT, "unit": u.id, "target": t.id})
			if not action.is_empty():
				best_score = score
				best = {"action": action, "hit": hit, "target": t}
	return best


## Move to the reachable cell with the shortest walking distance to any hostile, or {}.
## `covered`: a rusher that can't reach anyone this turn gives up to a tile of ground to end it
## in cover from the soldiers that can see it, instead of in the open in front of their guns.
static func _advance(s: GameState, u: Unit, hostiles: Array[Unit], covered := false) -> Dictionary:
	var sources: Array[Vector2i] = []
	for h in hostiles:
		sources.append(h.pos)
	var field := _distance_field(s.grid, sources)
	var reach := Rules.move_range(s, u)
	var best_cell := u.pos
	var here: float = field.get(u.pos, INF)
	var best_score: float = here
	for c in reach:
		if not field.has(c):
			continue
		var steps: int = reach[c]
		var score: float = field[c] + steps * 0.01
		if covered and field[c] < here:
			score -= _approach_cover(s, c, hostiles)
		if score < best_score:
			best_score = score
			best_cell = c
	if best_cell == u.pos:
		return {}
	return _check(s, {"type": Types.MOVE, "unit": u.id, "to": best_cell})


# --- Scoring helpers -------------------------------------------------------------------------

## How attractive `t` is as a target for `u` standing at `from`. Low HP, flanked, close.
static func _target_score(s: GameState, u: Unit, t: Unit, from: Vector2i) -> float:
	var score := 10.0 - t.hp + Kit.target_bias(s, u, t)
	if t.status.get("decoy", false):
		score += 8.0   # Deployables: decoys draw fire
	var odds := Combat.hit_chance(s, u, t, from)
	if odds.get("flanked", false):
		score += 3.0
	if t.hunkered:
		score -= 1.0
	return score - _dist(from, t.pos) * 0.2


## How safe cell `c` is from the hostiles that can see it: 1.1 when it has full cover from every
## one of them (or none can see it), 0.6 for at least half cover, 0 when any has it in the open.
## Height counts: a soldier shooting down from a roof sees past one step of cover.
static func _approach_cover(s: GameState, c: Vector2i, hostiles: Array[Unit]) -> float:
	var worst: int = Types.Cover.FULL
	var seen := false
	for h in hostiles:
		if not Combat.can_see(s, h.pos, c):
			continue
		seen = true
		var cover := _grid_cover(s.grid, c, h.pos)
		if Elevation.height(s, h) > s.grid.level(c):
			cover = maxi(cover - 1, Types.Cover.NONE)   # shooting down: cover counts one step lower
		worst = mini(worst, cover)
	if not seen:
		return 1.1
	match worst:
		Types.Cover.FULL: return 1.1
		Types.Cover.HALF: return 0.6
	return 0.0


static func _spitter_cell_score(s: GameState, u: Unit, c: Vector2i, hostiles: Array[Unit]) -> float:
	var nearest := INF
	var has_target := false
	var cover_sum := 0.0
	var watchers := 0
	for h in hostiles:
		var d := _dist(c, h.pos)
		nearest = minf(nearest, d)
		if Combat.can_see(s, c, h.pos):
			has_target = true
			watchers += 1
			match _grid_cover(s.grid, c, h.pos):
				Types.Cover.FULL: cover_sum += 2.0
				Types.Cover.HALF: cover_sum += 1.0
				_: cover_sum -= 1.0
	var score := 0.0
	if nearest < SPITTER_MIN_DIST:
		score -= (SPITTER_MIN_DIST - nearest) * 3.0
	elif nearest > SPITTER_MAX_DIST:
		score -= (nearest - SPITTER_MAX_DIST) * 1.0
	else:
		score += 2.0
	if has_target:
		score += 3.0
		score += cover_sum / watchers
	return score


## Cover that cell `c` gets against a shooter at `from`, from the grid alone.
static func _grid_cover(g: Grid, c: Vector2i, from: Vector2i) -> int:
	var best: int = Types.Cover.NONE
	var delta := from - c
	for d in Grid.DIRS4:
		if d.x * delta.x + d.y * delta.y > 0:
			best = maxi(best, g.cover_value(c + d))
	return best


## Walking cost (8-way, no corner cutting, ignoring units) from each cell to the nearest source.
## Uses Grid.step_cost, so on high ground the way to a soldier on a roof runs through its stairs or
## ladder instead of stopping at the foot of the wall.
static func _distance_field(g: Grid, sources: Array[Vector2i]) -> Dictionary:
	var dist := {}
	var buckets: Array = [[]]
	for c in sources:
		dist[c] = 0
		buckets[0].append(c)
	var k := 0
	while k < buckets.size():
		var bucket: Array = buckets[k]
		var i := 0
		while i < bucket.size():
			var c: Vector2i = bucket[i]
			i += 1
			if dist[c] != k:
				continue
			for d in Grid.DIRS8:
				var n: Vector2i = c + d
				if not g.is_walkable(n):
					continue
				var cost := g.step_cost(n, -d)   # walking from n onto c
				if cost <= 0:
					continue
				var nd := k + cost
				if dist.has(n) and dist[n] <= nd:
					continue
				dist[n] = nd
				while buckets.size() <= nd:
					buckets.append([])
				buckets[nd].append(n)
		k += 1
	return dist


static func _hostiles(s: GameState, u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for t in s.living():
		if u.is_enemy_of(t):
			out.append(t)
	return out


## `action` if Rules.validate accepts it, else {}.
static func _check(s: GameState, action: Dictionary) -> Dictionary:
	return action if Rules.validate(s, action) == "" else {}


static func _dist(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a).distance_to(Vector2(b))


static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
