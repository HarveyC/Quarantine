class_name DirectorBoss
extends RefCounted
## The Act 2 boss fight, "the Retrieval". The Halden-Voss Director wants one soldier alive and stays out of
## reach on the roofs while her contractors do the taking. Three phases, each gated so no single hit skips one:
##   1 Posts (100-67%): roof snipers cover her (she takes no damage while one lives) and every round
##     she locks a soldier's lane and fires on the lock she laid last round. Recovery Netters and Collectors arrive from turn 3
##     to hold a soldier and drag them to the map edge. Break sight lines, kill the posts, free the netted.
##   2 Mark (67-33%): a second team lands on the roofs and covers her again. She marks the most Infected
##     soldier (+1 damage from every enemy hit, her shots ignore their cover, the cage follows them).
##   3 Extraction (33-0%): no more cover. She drops retrieval cages on the marked soldier (on a pinned one,
##     who cannot step out, the cage takes them), and she keeps moving and smoking.
## Encounter, EnemyBehaviours and FightBuilder call in here. OWNER: enemies workstream.

## Boss HP as a share of her 34, by squad size (FightBuilder, instead of SQUAD_BOSS_HEALTH).
const HEALTH := {1: 0.4, 2: 0.8, 3: 1.15, 4: 1.45}
const MOBILITY := {1: 5, 2: 6, 3: 7}
## Roof snipers covering her in phase 1 and phase 2, by squad size.
const POSTS := {1: 0, 2: 2, 3: 3, 4: 3}
const POSTS_2 := {1: 1, 2: 1, 3: 2, 4: 2}
const POST_RADIUS := 8          # how far from her start the posts and her fall-back roofs lie
const POST_GAP := 3             # posts keep this far (Chebyshev) from each other and from her
const EXPOSED := 2              # soldiers who can see her before she looks for a roof out of sight
const FALL_BACK := 3
const WAVE_FIRST := {1: 5, 2: 3, 3: 3, 4: 3}   # a lone soldier gets longer before the first Collector
const WAVE_EVERY := 4
## Recovery adds per wave, by squad size: Netters to hold a soldier and Collectors to drag them off.
const WAVE_KINDS := {1: ["netter"], 2: ["netter", "collector"], 3: ["netter", "netter", "collector"], 4: ["netter", "netter", "collector"]}


static func setup(s: GameState, d: Unit, squad: int) -> void:
	d.status["alerted"] = true
	d.mobility = MOBILITY[1]
	_place_posts(s, d, POSTS[squad])
	if not s.encounter.has("waves"):
		s.encounter["waves"] = []
	s.encounter.waves.append({"turn": WAVE_FIRST[squad], "every": WAVE_EVERY, "kinds": WAVE_KINDS[squad].duplicate()})


## `n` roof snipers on the best ground around her, and her tether to them.
static func _place_posts(s: GameState, d: Unit, n: int) -> void:
	var taken: Array[Vector2i] = [d.pos]
	for i in n:
		var best := Vector2i(-1, -1)
		var best_score := -INF
		for dy in range(-POST_RADIUS, POST_RADIUS + 1):
			for dx in range(-POST_RADIUS, POST_RADIUS + 1):
				var c := d.pos + Vector2i(dx, dy)
				if not s.grid.in_bounds(c) or not s.grid.is_walkable(c) or s.unit_at(c) != null:
					continue
				if taken.any(func(o: Vector2i) -> bool: return EnemyAI._cheb(o, c) < POST_GAP):
					continue
				var cover := 0
				for dd in Grid.DIRS8:
					if s.grid.in_bounds(c + dd) and s.grid.tile(c + dd) != Types.Tile.FLOOR:
						cover += 1
				var score := s.grid.level(c) * 10.0 + cover - Vector2(c).distance_to(Vector2(d.pos)) * 0.2 + _squad_side(s, c)
				if score > best_score:
					best_score = score
					best = c
		if best.x < 0:
			break
		var post := Encounter._place(s, "sharpshooter", best)
		post.status["alerted"] = true
		taken.append(post.pos)
	if _any_post(s):
		d.status["tether"] = "sharpshooter"


## Posts that cover the squad's side of her roof score a little higher.
static func _squad_side(s: GameState, c: Vector2i) -> float:
	var near := INF
	for p in s.grid.player_spawns:
		near = minf(near, Vector2(p).distance_to(Vector2(c)))
	return -near * 0.05 if near < INF else 0.0


static func _any_post(s: GameState) -> bool:
	for o in s.living(Types.Team.ENEMY):
		if o.kind == "sharpshooter":
			return true
	return false


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
	u.cooldowns.clear()
	if phase == 1:
		_place_posts(s, u, POSTS_2[clampi(int(s.encounter.get("squad", 4)), 1, 4)])
		s.emit({"type": "boss_phase", "unit": u.id, "phase": 2, "boss": u.kind,
			"hp": u.hp, "max_hp": u.max_hp, "text": "The Director calls in a second team!"})
		return
	u.status.erase("tether")
	s.emit({"type": "boss_phase", "unit": u.id, "phase": 3, "boss": u.kind,
		"hp": u.hp, "max_hp": u.max_hp, "text": "The Director calls the extraction!"})


## The last post fell: she is open.
static func on_posts_dead(s: GameState, d: Unit) -> void:
	d.status.erase("tether")


# --- her turn --------------------------------------------------------------------------------

static func take_turn(s: GameState, u: Unit) -> void:
	for step in 5:
		if u.actions_left <= 0 or not u.is_alive() or s.phase == Types.Phase.ENDED:
			return
		var hostiles := EnemyAI._hostiles(s, u)
		if hostiles.is_empty():
			return
		if not _step(s, u, hostiles):
			return


static func _step(s: GameState, u: Unit, hostiles: Array[Unit]) -> bool:
	var phase := int(u.status.get("boss_phase", 1))
	# Fire on the lane she laid last round.
	if u.status.has("sighted"):
		if _act(s, {"type": Types.ABILITY, "unit": u.id, "ability": "snipe"}):
			return true
		u.status.erase("sighted")
		s.emit({"type": "lock_lost", "unit": u.id})
	if phase >= 3 and int(u.cooldowns.get("retrieve", 0)) <= 0:
		var prey := Retrieval.marked(s)
		if prey != null and _act(s, {"type": Types.ABILITY, "unit": u.id, "ability": "retrieve", "cell": Retrieval.cage_cell(s, prey)}):
			return true
	if phase >= 2 and int(u.cooldowns.get("flag", 0)) <= 0:
		var t := Retrieval.mark_target(s, u)
		if t != null and not Retrieval.is_marked(t) and _act(s, {"type": Types.ABILITY, "unit": u.id, "ability": "flag"}):
			return true
	var seen := _seen_by(s, u.pos, hostiles)
	var near := _nearest_dist(u.pos, hostiles)
	if seen >= EXPOSED or near <= FALL_BACK:
		if int(u.cooldowns.get("smoke_screen", 0)) <= 0 and Hazards.at(s, u.pos).get("kind", "") != "smoke" \
				and _act(s, {"type": Types.ABILITY, "unit": u.id, "ability": "smoke_screen", "cell": u.pos}):
			return true
		if _relocate(s, u, hostiles, 1.0):
			return true
	var lock := lock_target(s, u, hostiles)
	if lock != null and _act(s, {"type": Types.ABILITY, "unit": u.id, "ability": "sight", "target": lock.id}):
		return true
	return _relocate(s, u, hostiles, 3.0)


## Who she lays her sight on: the marked soldier, else the one with the least cover in her line.
static func lock_target(s: GameState, u: Unit, hostiles: Array[Unit]) -> Unit:
	var best: Unit = null
	var best_score := -INF
	for h in hostiles:
		if h.status.get("hidden", false) or not Combat.can_see(s, u.pos, h.pos):
			continue
		var cover := Elevation.adjust_cover(s, u, h, u.pos, Combat.cover_against(s.grid, h.pos, u.pos))
		var score := (8.0 if Retrieval.is_marked(h) else 0.0) - h.hp * 0.3 - (3.0 if cover == Types.Cover.FULL else 0.0) \
				- (1.5 if cover == Types.Cover.HALF else 0.0) + (2.0 if h.status.has("pinned_by") else 0.0)
		if score > best_score:
			best_score = score
			best = h
	return best


## How many soldiers can see cell `c`.
static func _seen_by(s: GameState, c: Vector2i, hostiles: Array[Unit]) -> int:
	var n := 0
	for h in hostiles:
		if Combat.can_see(s, h.pos, c):
			n += 1
	return n


## How good a roof `c` is: high, covered, and out of the squad's sight.
static func perch_score(s: GameState, c: Vector2i, hostiles: Array[Unit]) -> float:
	var cover := 0
	for d in Grid.DIRS8:
		if s.grid.in_bounds(c + d) and s.grid.tile(c + d) != Types.Tile.FLOOR:
			cover += 1
	var near := _nearest_dist(c, hostiles)
	var score := s.grid.level(c) * 4.0 + cover * 0.4 - _seen_by(s, c, hostiles) * 1.6
	if near < FALL_BACK + 2:
		score -= (FALL_BACK + 2 - near) * 1.5
	return score


static func _relocate(s: GameState, u: Unit, hostiles: Array[Unit], margin: float) -> bool:
	var reach := Rules.move_range(s, u)
	var here := perch_score(s, u.pos, hostiles)
	var best_cell := u.pos
	var best_score := here + margin
	for c in reach:
		var score := perch_score(s, c, hostiles) - int(reach[c]) * 0.05 - Hazards.avoid_cost(s, u, c)
		if score > best_score:
			best_score = score
			best_cell = c
	if best_cell == u.pos:
		return false
	return _act(s, {"type": Types.MOVE, "unit": u.id, "to": best_cell})


static func _nearest_dist(c: Vector2i, hostiles: Array[Unit]) -> int:
	var best := 99
	for h in hostiles:
		best = mini(best, EnemyAI._cheb(c, h.pos))
	return best


static func _act(s: GameState, a: Dictionary) -> bool:
	return EnemyBehaviours._try(s, a)
