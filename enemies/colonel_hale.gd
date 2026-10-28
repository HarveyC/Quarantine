class_name ColonelHale
extends RefCounted
## The Act 2 boss fight, "the Last Order". Three phases, each gated so no single hit skips one:
##   1 Command (100-67%): holds the highest ground near his start, calls airstrikes on the squad's
##     clusters and the soldiers on rooftops, flashbangs overwatch, pops smoke and falls back when
##     a soldier closes in. A recovery team drops in from turn 3.
##   2 Mutation (67-33%): the Bloom takes him. Heals a little, grows plating, roars (his adds
##     frenzy), then stomps (marked 3x3), charges lanes (marked) through cover and roofs, and keeps
##     calling the fire mission on the squad's clusters.
##   3 Wreck (33-0%): sheds the plating. Hurls wreckage onto cover (marked 3x3), keeps the fire
##     mission coming and calls danger close on his own position (marked 5x5) when the squad crowds him.
## Encounter, EnemyBehaviours and FightBuilder call in here. OWNER: enemies workstream.

## Boss HP as a share of his 36, by squad size (FightBuilder, instead of SQUAD_BOSS_HEALTH).
const HEALTH := {1: 0.6, 2: 0.7, 3: 1.05, 4: 1.35}
const MOBILITY := {2: 6, 3: 7}
const HEAL := 0.15              # share of max HP he regains when the Bloom takes him
const POST_RADIUS := 6          # how far from his start he looks for the highest ground
const FALL_BACK := 3            # a soldier this close (Chebyshev) sends him looking for a new post
const WAVE_FIRST := 3
const WAVE_EVERY := 4
## Colony Security reinforcements: the recovery team is Hale's cordon, not the Infected.
const WAVE_KINDS := {1: [], 2: ["overwatcher"], 3: ["shieldman", "overwatcher"], 4: ["shieldman", "overwatcher", "fallen"]}


static func setup(s: GameState, h: Unit, squad: int) -> void:
	h.cooldowns["airstrike"] = 1
	h.status["post"] = h.pos
	h.status["alerted"] = true
	if not WAVE_KINDS[squad].is_empty():
		if not s.encounter.has("waves"):
			s.encounter["waves"] = []
		s.encounter.waves.append({"turn": WAVE_FIRST, "every": WAVE_EVERY, "kinds": WAVE_KINDS[squad].duplicate()})


## The best command post within POST_RADIUS of `c`: highest ground, then the most cover around.
static func post_near(g: Grid, c: Vector2i) -> Vector2i:
	var best := c
	var best_score := -INF
	for dy in range(-POST_RADIUS, POST_RADIUS + 1):
		for dx in range(-POST_RADIUS, POST_RADIUS + 1):
			var p := c + Vector2i(dx, dy)
			if not g.in_bounds(p) or not g.is_walkable(p):
				continue
			var cover := 0
			for d in Grid.DIRS8:
				if g.in_bounds(p + d) and g.tile(p + d) != Types.Tile.FLOOR:
					cover += 1
			var score := g.level(p) * 10.0 + cover - Vector2(p).distance_to(Vector2(c)) * 0.3
			if score > best_score:
				best_score = score
				best = p
	return best


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
		u.hp = mini(u.max_hp, u.hp + roundi(u.max_hp * HEAL))
		u.status["armour"] = 1
		u.display_name = "Hale, Mutated"
		for o in s.living(Types.Team.ENEMY):
			if o != u and not EnemyRoster.is_static(o):
				Encounter.frenzy(s, o)
		s.emit({"type": "boss_phase", "unit": u.id, "phase": 2, "boss": u.kind,
			"hp": u.hp, "max_hp": u.max_hp, "text": "Colonel Hale mutates!"})
		return
	u.status.erase("armour")
	u.display_name = "Hale, Unbound"
	u.cooldowns["danger_close"] = 1
	s.emit({"type": "boss_phase", "unit": u.id, "phase": 3, "boss": u.kind,
		"hp": u.hp, "max_hp": u.max_hp, "text": "The plating tears away!"})


# --- his turn --------------------------------------------------------------------------------

static func take_turn(s: GameState, u: Unit) -> void:
	if u.status.has("charge_dir"):
		_try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "charge"})
		return
	var phase := int(u.status.get("boss_phase", 1))
	for step in 4:
		if u.actions_left <= 0 or not u.is_alive() or s.phase == Types.Phase.ENDED:
			return
		var hostiles := EnemyAI._hostiles(s, u)
		if hostiles.is_empty():
			return
		var went := false
		match phase:
			1: went = _command(s, u, hostiles)
			2: went = _brute(s, u, hostiles)
			_: went = _wreck(s, u, hostiles)
		if not went:
			return


## Phase 1: air support from the high ground.
static func _command(s: GameState, u: Unit, hostiles: Array[Unit]) -> bool:
	if int(u.cooldowns.get("airstrike", 0)) <= 0:
		var strike := strike_cell(s, u, hostiles)
		if strike.hits >= 1 and _act(s, EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "airstrike", "cell": strike.cell})):
			return true
	if int(u.cooldowns.get("flashbang", 0)) <= 0:
		for h in hostiles:
			if Combat.is_overwatching(s, h) or Combat.is_hunkered(s, h):
				if _act(s, EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "flashbang", "cell": h.pos})):
					return true
	var near := _nearest_dist(u.pos, hostiles)
	if near <= FALL_BACK:
		if int(u.cooldowns.get("smoke_screen", 0)) <= 0 and Hazards.at(s, u.pos).get("kind", "") != "smoke" \
				and _act(s, EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "smoke_screen", "cell": u.pos})):
			return true
		if _fall_back(s, u, hostiles):
			return true
	if u.actions_left >= 2 and _climb(s, u, hostiles):
		return true
	return _act(s, EnemyBehaviours.cover_shooter(s, u, hostiles))


## The fire mission never stops: from phase 2 he still calls strikes on the best cluster whenever it is
## ready and costs him no one he cares about, so standing still is never safe.
static func _fire_mission(s: GameState, u: Unit, hostiles: Array[Unit]) -> bool:
	if int(u.cooldowns.get("airstrike", 0)) > 0:
		return false
	var strike := strike_cell(s, u, hostiles)
	return strike.hits >= 1 and _act(s, EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "airstrike", "cell": strike.cell}))


## The 3x3 that catches the most soldiers, with extra weight on anyone on high ground (a strike
## brings the roof down on them). {cell, hits}.
static func strike_cell(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	var best := {"cell": u.pos, "hits": 0}
	var best_score := 0.0
	for h in hostiles:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c: Vector2i = h.pos + Vector2i(dx, dy)
				if not s.grid.in_bounds(c) or EnemyAI._cheb(c, u.pos) <= 1:
					continue
				var hits := 0
				var score := 0.0
				for o in s.living():
					if EnemyAI._cheb(o.pos, c) <= 1:
						var foe := u.is_enemy_of(o)
						hits += 1 if foe else -1
						score += (1.0 + 0.75 * s.grid.level(o.pos)) if foe else -1.5
				if score > best_score:
					best_score = score
					best = {"cell": c, "hits": hits}
	return best


## How good a command post `c` is: high ground and cover, with the squad in sight but not on top
## of him.
static func post_score(s: GameState, u: Unit, c: Vector2i, hostiles: Array[Unit]) -> float:
	var near := _nearest_dist(c, hostiles)
	var score := EnemyBehaviours._cover_cell_score(s, u, c, hostiles) + s.grid.level(c) * 2.0
	if near < FALL_BACK + 2:
		score -= (FALL_BACK + 2 - near) * 2.0
	return score


static func _fall_back(s: GameState, u: Unit, hostiles: Array[Unit]) -> bool:
	return _relocate(s, u, hostiles, 0.5)


static func _climb(s: GameState, u: Unit, hostiles: Array[Unit]) -> bool:
	return _relocate(s, u, hostiles, 2.5)


static func _relocate(s: GameState, u: Unit, hostiles: Array[Unit], margin: float) -> bool:
	var reach := Rules.move_range(s, u)
	var here := post_score(s, u, u.pos, hostiles)
	var best_cell := u.pos
	var best_score := here + margin
	for c in reach:
		var score := post_score(s, u, c, hostiles) - int(reach[c]) * 0.05
		if score > best_score:
			best_score = score
			best_cell = c
	if best_cell == u.pos:
		return false
	u.status["post"] = best_cell
	return _act(s, EnemyAI._check(s, {"type": Types.MOVE, "unit": u.id, "to": best_cell}))


## Phase 2: the Brute. Stomps when two or more are in reach, else claws; the charge itself is
## wound up at the end of his turn (EnemyBehaviours.end_turn) and shown as a marked lane.
static func _brute(s: GameState, u: Unit, hostiles: Array[Unit]) -> bool:
	if _fire_mission(s, u, hostiles):
		return true
	var adjacent := hostiles.filter(func(h: Unit) -> bool: return s.grid.melee_reach(u.pos, h.pos))
	if adjacent.size() >= 2 and _act(s, EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "stomp"})):
		return true
	return _act(s, EnemyBehaviours.rush(s, u, _melee_pool(s, u, hostiles), "slam"))


## Phase 3: hurls wreckage at soldiers dug in behind cover or up high, calls danger close when
## crowded, and otherwise tears into whoever is nearest.
static func _wreck(s: GameState, u: Unit, hostiles: Array[Unit]) -> bool:
	var crowd := hostiles.filter(func(h: Unit) -> bool: return EnemyAI._cheb(u.pos, h.pos) <= 2)
	if not crowd.is_empty() and int(u.cooldowns.get("danger_close", 0)) <= 0 \
			and _act(s, EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "danger_close"})):
		return true
	var adjacent := hostiles.filter(func(h: Unit) -> bool: return s.grid.melee_reach(u.pos, h.pos))
	if adjacent.size() >= 2 and _act(s, EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "stomp"})):
		return true
	if adjacent.is_empty() and int(u.cooldowns.get("hurl", 0)) <= 0:
		var target := hurl_cell(s, u, hostiles)
		if target.hits >= 1 and _act(s, EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "hurl", "cell": target.cell})):
			return true
	if _fire_mission(s, u, hostiles):
		return true
	return _act(s, EnemyBehaviours.rush(s, u, _melee_pool(s, u, hostiles), "slam"))


## Where wreckage lands: the 3x3 with the most soldiers, favouring those on high ground or in
## cover (the hurl breaks both). {cell, hits}.
static func hurl_cell(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	var best := {"cell": u.pos, "hits": 0}
	var best_score := 0.0
	for h in hostiles:
		if u.pos.distance_to(h.pos) > EnemyAbilities.HURL_RANGE or EnemyAI._cheb(u.pos, h.pos) <= 2:
			continue
		var hits := 0
		var score := 0.0
		for o in s.living():
			if EnemyAI._cheb(o.pos, h.pos) <= 1:
				if u.is_enemy_of(o):
					hits += 1
					score += 1.0 + 0.75 * s.grid.level(o.pos) + (0.5 if Combat.cover_against(s.grid, o.pos, u.pos) != Types.Cover.NONE else 0.0)
				else:
					score -= 1.5
		if score > best_score:
			best_score = score
			best = {"cell": h.pos, "hits": hits}
	return best


## Who he rushes: whoever is already in reach, else the prey.
static func _melee_pool(s: GameState, u: Unit, hostiles: Array[Unit]) -> Array[Unit]:
	for h in hostiles:
		if s.grid.melee_reach(u.pos, h.pos):
			return hostiles
	return _prey(s, u, hostiles)


## Soldiers on the highest ground first: the Brute goes after whoever thinks they are safe up there.
static func _prey(s: GameState, u: Unit, hostiles: Array[Unit]) -> Array[Unit]:
	var top := -1
	for h in hostiles:
		top = maxi(top, s.grid.level(h.pos))
	var high := hostiles.filter(func(h: Unit) -> bool: return s.grid.level(h.pos) == top and top > 0 \
		and u.pos.distance_to(h.pos) <= u.mobility + 2)
	var out: Array[Unit] = []
	out.assign(high if not high.is_empty() else hostiles)
	return out


static func _nearest_dist(c: Vector2i, hostiles: Array[Unit]) -> int:
	var best := 99
	for h in hostiles:
		best = mini(best, EnemyAI._cheb(c, h.pos))
	return best


static func _act(s: GameState, a: Dictionary) -> bool:
	return not a.is_empty() and _try(s, a)


static func _try(s: GameState, a: Dictionary) -> bool:
	return EnemyBehaviours._try(s, a)
