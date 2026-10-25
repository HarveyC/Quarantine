class_name BroodMother
extends RefCounted
## The Act 1 boss fight, "the Nest Cycle". Three phases, each gated so no single hit skips one:
##   1 Rooted (100-67%): immune while her egg sacs live; marks acid rain on the squad. When every
##     sac is dead she re-lays one after RELAY turns.
##   2 Burrowing (67-33%): dives and erupts next to the soldier on the highest ground (3x3, smashes
##     cover, collapses roofs), surfaces with a fresh sac that shields her, stays up two turns.
##   3 Berserk (33-0%): her sacs burst into Broodlings, the shield is gone, she rushes and claws.
## Encounter, EnemyBehaviours and FightBuilder call in here. OWNER: enemies workstream.

## Boss HP as a share of her 40, by squad size (FightBuilder, instead of SQUAD_BOSS_HEALTH).
const HEALTH := {1: 0.3, 2: 0.75, 3: 1.6, 4: 2.8}
const SACS := {1: 1, 2: 2, 3: 3, 4: 4}              # sacs she starts with
const SURFACE_SACS := {1: 0, 2: 1, 3: 1, 4: 2}      # sacs she keeps alive while burrowing
const RELAY := 3               # turns before she re-lays a sac once every sac is dead (phase 1)
const SAC_RUNNER_EVERY := {1: 8, 2: 6, 3: 5, 4: 4}   # turns between a sac's Runners
const SURFACED_TURNS := 3      # her turns above ground (the eruption turn included) before she dives again
const BURROW_COOLDOWN := 2
const MOBILITY := {2: 4, 3: 5}
const OFFSETS: Array[Vector2i] = [Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, -2), Vector2i(0, 2)]


static func setup(s: GameState, b: Unit, squad: int) -> void:
	for i in SACS[squad]:
		lay_sac(s, b, b.pos + OFFSETS[i], 2 + i % 2)
	b.cooldowns["lay"] = RELAY


## Lays a sac near `cell` that spawns Runners from turn `first` and shields her while it lives.
static func lay_sac(s: GameState, b: Unit, cell: Vector2i, first: int) -> Unit:
	var sac := Encounter._place(s, "egg_sac", cell)
	sac.status["alerted"] = true
	sac.status["spawner"] = {"kinds": ["runner"], "every": SAC_RUNNER_EVERY[_squad(s)],
		"next": first, "i": 0}
	if int(b.status.get("boss_phase", 1)) < 3:
		b.status["tether"] = "egg_sac"
	return sac


static func _squad(s: GameState) -> int:
	return clampi(int(s.encounter.get("squad", 4)), 1, 4)


static func _sacs(s: GameState) -> int:
	return s.living(Types.Team.ENEMY).filter(func(o: Unit) -> bool: return o.kind == "egg_sac").size()


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
	if phase == 1:
		s.emit({"type": "boss_phase", "unit": u.id, "phase": 2, "boss": u.kind,
			"text": "The Brood Mother tears free and burrows!"})
		return
	u.status.erase("tether")
	for o in s.living(Types.Team.ENEMY):
		if o.kind == "egg_sac":
			var at := o.pos
			Encounter.kill(s, o)
			Encounter.spawn(s, "broodling", at, u)
	s.emit({"type": "boss_phase", "unit": u.id, "phase": 3, "boss": u.kind,
		"text": "The Brood Mother goes berserk!"})


# --- her turn --------------------------------------------------------------------------------

static func take_turn(s: GameState, u: Unit) -> void:
	var phase := int(u.status.get("boss_phase", 1))
	if u.status.has("emerge_cell"):
		_try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "erupt"})
		if not u.is_alive() or s.phase == Types.Phase.ENDED:
			return
		u.status["surfaced"] = s.turn
		if phase == 2 and _sacs(s) < SURFACE_SACS[_squad(s)]:
			var sac := lay_sac(s, u, u.pos + Vector2i(0, 1), s.turn + 2)
			s.emit({"type": "spawned", "unit": sac.id, "kind": sac.kind, "cell": sac.pos, "from": u.id})
		return
	var moved := false
	for step in 4:
		if u.actions_left <= 0 or not u.is_alive() or s.phase == Types.Phase.ENDED:
			return
		var hostiles := EnemyAI._hostiles(s, u)
		if hostiles.is_empty():
			return
		match phase:
			1:
				if _sacs(s) == 0 and int(u.cooldowns.get("lay", 0)) <= 0:
					var sac := lay_sac(s, u, u.pos + OFFSETS[s.turn % 2], s.turn + 2)
					s.emit({"type": "spawned", "unit": sac.id, "kind": sac.kind, "cell": sac.pos, "from": u.id})
					u.cooldowns["lay"] = RELAY
					u.actions_left -= 1
					continue
				if _acid_rain(s, u, hostiles):
					continue
				if _claw_adjacent(s, u, hostiles):
					return
				_act(s, EnemyAI._best_spit(s, u, hostiles).get("action", {}))
				return
			2:
				if will_burrow(s, u):
					var t := burrow_target(s, u, hostiles)
					if t != null and _act(s, EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "burrow", "target": t.id})):
						u.cooldowns["burrow_cd"] = BURROW_COOLDOWN
						return
				# Surfaced: close in, then claw. Acid rain only when she has no one to claw.
				if _claw_adjacent(s, u, hostiles):
					return
				if not moved and u.actions_left >= 2:
					moved = true
					if _act(s, EnemyBehaviours.rush(s, u, hostiles, "claw")):
						continue
				if _acid_rain(s, u, hostiles):
					continue
				return
			_:
				if _claw_adjacent(s, u, hostiles):
					return
				if u.actions_left >= 2 and _act(s, EnemyBehaviours.rush(s, u, hostiles, "claw")):
					continue
				if _acid_rain(s, u, hostiles):
					continue
				if _act(s, EnemyBehaviours.rush(s, u, hostiles, "claw")):
					continue
				return


## Phase 2: whether she dives this turn (she has been up long enough). `preview` asks during the
## team phase, before her cooldowns tick down at the start of her turn.
static func will_burrow(s: GameState, u: Unit, preview := false) -> bool:
	return int(u.status.get("boss_phase", 1)) == 2 and not u.status.has("burrowed") \
		and int(u.status.get("surfaced", -99)) + SURFACED_TURNS <= s.turn \
		and int(u.cooldowns.get("burrow_cd", 0)) <= (1 if preview else 0)


## The soldier she erupts next to: highest ground first, then the usual exposure score.
static func burrow_target(s: GameState, u: Unit, hostiles: Array[Unit]) -> Unit:
	var target: Unit = null
	var best := -INF
	for h in hostiles:
		if u.pos.distance_to(h.pos) > EnemyAbilities.BURROW_RANGE:
			continue
		var score := EnemyTerrain.level(s, h.pos) * 5.0 + EnemyAI._target_score(s, u, h, u.pos)
		if score > best:
			best = score
			target = h
	return target


static func _acid_rain(s: GameState, u: Unit, hostiles: Array[Unit]) -> bool:
	if int(u.cooldowns.get("acid_rain", 0)) > 0:
		return false
	var in_range := hostiles.filter(func(h: Unit) -> bool: return u.pos.distance_to(h.pos) <= EnemyAbilities.ACID_RAIN_RANGE - 1.5)
	var best := EnemyBehaviours.best_square(s, u, in_range)
	if best.hits < 1:
		return false
	return _try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "acid_rain", "cell": best.cell})


static func _claw_adjacent(s: GameState, u: Unit, hostiles: Array[Unit]) -> bool:
	var near := hostiles.filter(func(h: Unit) -> bool: return s.grid.melee_reach(u.pos, h.pos))
	near.sort_custom(func(a: Unit, b: Unit) -> bool: return a.hp < b.hp)
	for h in near:
		if _try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "claw", "target": h.id}):
			return true
	return false


static func _act(s: GameState, a: Dictionary) -> bool:
	return not a.is_empty() and _try(s, a)


static func _try(s: GameState, a: Dictionary) -> bool:
	return EnemyBehaviours._try(s, a)
