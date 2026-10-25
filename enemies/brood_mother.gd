class_name BroodMother
extends RefCounted
## PROTOTYPE: three candidate Brood Mother fights, picked by encounter "brood_variant"
## ("nest" | "stalker" | "tide"). With no variant the old fight runs unchanged.
## OWNER: enemies workstream.

## Boss HP as a share of 40, by squad size.
const HP := {
	"nest": {1: 0.3, 2: 0.75, 3: 1.5, 4: 2.5},
	"stalker": {1: 0.25, 2: 0.45, 3: 1.0, 4: 1.6},
	"tide": {1: 0.4, 2: 1.3, 3: 2.0, 4: 2.8},
}
const NEST_SACS := {1: 1, 2: 2, 3: 3, 4: 4}
const NEST_P2_SACS := {1: 0, 2: 1, 3: 1, 4: 2}   # sacs she keeps laying as she surfaces
const NEST_RELAY := 3            # turns before she lays a fresh sac once every sac is dead
const STALK_SACS := {1: 1, 2: 1, 3: 2, 4: 3}
const STALK_POUNCE_EVERY := {1: 4, 2: 3, 3: 2, 4: 2}
const STALK_FEED := {1: 0, 2: 1, 3: 1, 4: 1}   # HP each living sac feeds her every turn
const TIDE_CLUTCH_EVERY := {1: 3, 2: 2, 3: 1, 4: 1}
const TIDE_HATCH := 2            # turns a clutch takes to hatch
const SAC_RUNNER_EVERY := 4


static func variant(s: GameState) -> String:
	return str(s.encounter.get("brood_variant", ""))


static func setup(s: GameState, b: Unit, squad: int) -> void:
	var v := variant(s)
	b.status["brood_variant"] = v
	b.max_hp = maxi(1, roundi(40 * float(HP[v][squad])))
	b.hp = b.max_hp
	var slower: int = Encounter.BOSS_SPAWN_EVERY_EXTRA[squad]
	match v:
		"nest":
			for a in ["burrow", "erupt", "acid_rain"]:
				b.abilities.append(a)
			var offsets: Array[Vector2i] = [Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, -2), Vector2i(0, 2)]
			for i in NEST_SACS[squad]:
				_sac(s, b, b.pos + offsets[i], 2 + i % 2, SAC_RUNNER_EVERY + slower)
		"stalker":
			b.status.erase("tether")
			b.status["hidden"] = true
			b.mobility = 5
			for a in ["pounce", "maul"]:
				b.abilities.append(a)
			var spots := s.grid.enemy_spawns.duplicate()
			spots.sort_custom(func(x: Vector2i, y: Vector2i) -> bool:
				return Encounter._dist_to_squad(s, x) > Encounter._dist_to_squad(s, y))
			var placed: Array[Vector2i] = []
			for c in spots:
				if placed.size() >= STALK_SACS[squad]:
					break
				if placed.any(func(p: Vector2i) -> bool: return p.distance_to(c) < 6.0):
					continue
				placed.append(c)
			while placed.size() < STALK_SACS[squad]:
				placed.append(b.pos + Vector2i(placed.size() * 2 - 3, 2))
			for i in placed.size():
				_sac(s, b, placed[i], 3 + i, SAC_RUNNER_EVERY + slower + 1)
		"tide":
			b.status.erase("tether")
			b.mobility = 2
			b.abilities.append("acid_rain")
			b.cooldowns["lay"] = 1


static func _sac(s: GameState, b: Unit, cell: Vector2i, next: int, every: int) -> Unit:
	var sac := Encounter._place(s, "egg_sac", cell)
	sac.status["alerted"] = true
	sac.status["spawner"] = {"kinds": ["runner"], "every": every, "next": next, "i": 0}
	if variant(s) == "nest":
		b.status["tether"] = "egg_sac"
	return sac


# --- damage and phases ---------------------------------------------------------------------

## Phase gates: a single hit can't skip a phase.
static func thresholds(u: Unit) -> Array[int]:
	match str(u.status.get("brood_variant", "")):
		"nest": return [ceili(u.max_hp * 2 / 3.0), ceili(u.max_hp / 3.0)]
	return [ceili(u.max_hp / 2.0)]


static func clamp_damage(u: Unit, amount: int) -> int:
	var phase := int(u.status.get("boss_phase", 1))
	var gates := thresholds(u)
	if phase - 1 < gates.size():
		var floor_hp: int = gates[phase - 1]
		if u.hp > floor_hp:
			return mini(amount, u.hp - floor_hp)
	return amount


static func on_damaged(s: GameState, u: Unit) -> void:
	var gates := thresholds(u)
	var phase := int(u.status.get("boss_phase", 1))
	if phase - 1 >= gates.size() or u.hp > gates[phase - 1]:
		return
	u.status.boss_phase = phase + 1
	var squad := clampi(int(s.encounter.get("squad", 4)), 1, 4)
	match variant(s):
		"nest":
			if phase == 1:
				u.mobility = 4
				s.emit({"type": "boss_phase", "unit": u.id, "phase": 2, "boss": u.kind,
					"text": "The Brood Mother tears free and dives!"})
			else:
				u.mobility = 5
				u.status.erase("tether")
				for o in s.living(Types.Team.ENEMY):
					if o.kind == "egg_sac":
						Encounter.kill(s, o)
						Encounter.spawn(s, "broodling", o.pos, u)
				s.emit({"type": "boss_phase", "unit": u.id, "phase": 3, "boss": u.kind,
					"text": "The Brood Mother goes berserk!"})
		"stalker":
			u.mobility = 7
			for o in s.living(Types.Team.ENEMY):
				if o.kind == "egg_sac":
					Encounter.spawn(s, "runner", o.pos, o)
			s.emit({"type": "boss_phase", "unit": u.id, "phase": 2, "boss": u.kind,
				"text": "The Brood Mother shrieks for her brood!"})
		"tide":
			s.emit({"type": "boss_phase", "unit": u.id, "phase": 2, "boss": u.kind,
				"text": "The Brood Mother climbs to her perch!"})
			_climb(s, u)


static func enemy_phase_start(s: GameState) -> void:
	var b := Encounter._boss(s, "brood_mother")
	if b == null:
		return
	match variant(s):
		"stalker":
			var heal := mini(_sacs(s) * int(STALK_FEED[clampi(int(s.encounter.get("squad", 4)), 1, 4)]), b.max_hp - b.hp)
			if heal > 0:
				b.hp += heal
				s.emit({"type": "regenerate", "unit": b.id, "healed": heal, "hp": b.hp})
		"tide":
			for o in s.living(Types.Team.ENEMY):
				if o.kind != "egg_sac" or not o.status.has("hatch") or int(o.status.hatch) > s.turn:
					continue
				var kinds: Array = o.status.hatch_kinds
				var at := o.pos
				Encounter.kill(s, o)
				for k in kinds:
					if Encounter._mobile_enemies(s) < Encounter._spawn_cap(s) + 2:
						Encounter.spawn(s, k, at, b)


# --- turns -----------------------------------------------------------------------------------

static func take_turn(s: GameState, u: Unit) -> void:
	match variant(s):
		"nest": _nest_turn(s, u)
		"stalker": _stalker_turn(s, u)
		"tide": _tide_turn(s, u)


static func _hostiles(s: GameState, u: Unit) -> Array[Unit]:
	return EnemyAI._hostiles(s, u)


static func _sacs(s: GameState) -> int:
	return s.living(Types.Team.ENEMY).filter(func(o: Unit) -> bool: return o.kind == "egg_sac").size()


static func _claw_adjacent(s: GameState, u: Unit) -> bool:
	var hostiles := _hostiles(s, u)
	hostiles.sort_custom(func(a: Unit, b: Unit) -> bool: return a.hp < b.hp)
	for h in hostiles:
		if s.grid.melee_reach(u.pos, h.pos):
			if EnemyBehaviours._try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "claw", "target": h.id}):
				return true
	return false


static func _acid_rain(s: GameState, u: Unit) -> bool:
	if not u.abilities.has("acid_rain") or int(u.cooldowns.get("acid_rain", 0)) > 0:
		return false
	var best := EnemyBehaviours.best_square(s, u, _hostiles(s, u))
	if best.hits < 1:
		return false
	return EnemyBehaviours._try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "acid_rain", "cell": best.cell})


static func _act(s: GameState, u: Unit, a: Dictionary) -> bool:
	return not a.is_empty() and EnemyBehaviours._try(s, a)


## Nest: rooted behind her sacs, then burrows around the arena laying new ones, then berserk.
static func _nest_turn(s: GameState, u: Unit) -> void:
	var phase := int(u.status.get("boss_phase", 1))
	var squad := clampi(int(s.encounter.get("squad", 4)), 1, 4)
	if u.status.has("emerge_cell"):
		EnemyBehaviours._try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "erupt"})
		if not u.is_alive() or s.phase == Types.Phase.ENDED:
			return
		u.status["surfaced"] = s.turn
		if phase == 2 and _sacs(s) < NEST_P2_SACS[squad]:
			_sac(s, u, u.pos + Vector2i(0, 1), s.turn + 2, SAC_RUNNER_EVERY + Encounter.BOSS_SPAWN_EVERY_EXTRA[squad])
		return
	for step in 4:
		if u.actions_left <= 0 or not u.is_alive() or s.phase == Types.Phase.ENDED:
			return
		var hostiles := _hostiles(s, u)
		match phase:
			1:
				if _sacs(s) == 0 and int(u.cooldowns.get("lay", 0)) <= 0:
					var off: Array[Vector2i] = [Vector2i(-2, 0), Vector2i(2, 0)]
					_sac(s, u, u.pos + off[s.turn % 2], s.turn + 2, SAC_RUNNER_EVERY + Encounter.BOSS_SPAWN_EVERY_EXTRA[squad])
					u.cooldowns["lay"] = NEST_RELAY
					u.actions_left -= 1
					continue
				if _acid_rain(s, u):
					continue
				if _claw_adjacent(s, u):
					return
				if _act(s, u, EnemyAI._best_spit(s, u, hostiles).get("action", {})):
					return
				return
			2:
				if _claw_adjacent(s, u):
					return
				if int(u.status.get("surfaced", -9)) + 2 <= s.turn and int(u.cooldowns.get("burrow_cd", 0)) <= 0:
					var t := _burrow_target(s, u, hostiles)
					if t != null and _act(s, u, EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "burrow", "target": t.id})):
						u.cooldowns["burrow_cd"] = 2
						return
				if _acid_rain(s, u):
					continue
				if _act(s, u, EnemyAI._best_spit(s, u, hostiles).get("action", {})):
					return
				if _act(s, u, EnemyBehaviours.rush(s, u, hostiles, "claw")):
					continue
				return
			_:
				if _claw_adjacent(s, u):
					return
				if u.actions_left >= 2 and _act(s, u, EnemyBehaviours.rush(s, u, hostiles, "claw")):
					continue
				if _acid_rain(s, u):
					continue
				if _act(s, u, EnemyBehaviours.rush(s, u, hostiles, "claw")):
					continue
				return


static func _burrow_target(s: GameState, u: Unit, hostiles: Array[Unit]) -> Unit:
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


## Stalker: hunts from the fog, pounces on whoever strays, retreats to heal off her sacs.
static func _stalker_turn(s: GameState, u: Unit) -> void:
	if u.status.has("pinning"):
		EnemyBehaviours._try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "maul"})
		return
	var hostiles := _hostiles(s, u)
	var t := EnemyBehaviours._pounce_target(s, u)
	var squad := clampi(int(s.encounter.get("squad", 4)), 1, 4)
	var fresh: bool = int(u.status.get("struck", -9)) <= s.turn - int(STALK_POUNCE_EVERY[squad])
	if t != null and fresh:
		if EnemyBehaviours._try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "pounce", "target": t.id}):
			u.status["struck"] = s.turn
			if u.status.has("pinning"):
				Encounter.release_pin(s, u, "hit_and_run")
			return
	# Retreat or stalk: a cell out of every soldier's sight, near (but not next to) her prey.
	var prey := EnemyBehaviours._pounce_target(s, u)
	if prey == null:
		prey = EnemyBehaviours._nearest(u, hostiles)
	var reach := Rules.move_range(s, u)
	var best_cell := u.pos
	var best := -INF
	for c in reach:
		var seen := false
		for h in hostiles:
			if h.pos.distance_to(c) <= Vision.SOLDIER_SIGHT and Combat.can_see(s, h.pos, c):
				seen = true
				break
		var score := -10.0 if seen else 0.0
		if prey != null:
			var d: float = Vector2(c).distance_to(Vector2(prey.pos))
			score -= absf(d - 5.0)
		score += EnemyTerrain.level(s, c) * 0.5 - Hazards.avoid_cost(s, u, c)
		if score > best:
			best = score
			best_cell = c
	if best_cell != u.pos:
		EnemyBehaviours._try(s, {"type": Types.MOVE, "unit": u.id, "to": best_cell})
	if u.is_alive() and u.actions_left > 0:
		_claw_adjacent(s, u)
	if u.is_alive():
		var seen := false
		for h in _hostiles(s, u):
			if h.pos.distance_to(u.pos) <= Vision.SOLDIER_SIGHT and Combat.can_see(s, h.pos, u.pos):
				seen = true
		if not seen and not u.status.has("pinning"):
			u.status["hidden"] = true


## Tide: lays clutches that hatch unless broken; at half HP climbs to high ground and shells.
static func _tide_turn(s: GameState, u: Unit) -> void:
	var phase := int(u.status.get("boss_phase", 1))
	var squad := clampi(int(s.encounter.get("squad", 4)), 1, 4)
	for step in 4:
		if u.actions_left <= 0 or not u.is_alive() or s.phase == Types.Phase.ENDED:
			return
		var hostiles := _hostiles(s, u)
		if int(u.cooldowns.get("lay", 0)) <= 0 and not hostiles.is_empty():
			var near := EnemyBehaviours._nearest(u, hostiles)
			var dir := Vector2(near.pos - u.pos).normalized()
			var cell := Encounter.free_cell(s, u.pos + Vector2i((dir * 3.0).round()))
			var c := Encounter._place(s, "egg_sac", cell)
			c.status["alerted"] = true
			c.status["hatch"] = s.turn + TIDE_HATCH
			c.status["hatch_kinds"] = ["leaper"] if phase >= 2 else (["runner", "broodling"] if squad >= 3 else ["broodling", "broodling"])
			s.emit({"type": "spawned", "unit": c.id, "kind": c.kind, "cell": c.pos, "from": u.id})
			u.cooldowns["lay"] = TIDE_CLUTCH_EVERY[squad] + 1
			u.actions_left -= 1
			continue
		if _claw_adjacent(s, u):
			return
		if phase >= 2:
			if _acid_rain(s, u):
				continue
			if _act(s, u, EnemyAI._best_spit(s, u, hostiles).get("action", {})):
				return
			return
		if _act(s, u, EnemyAI._best_spit(s, u, hostiles).get("action", {})):
			return
		if _act(s, u, EnemyBehaviours.rush(s, u, hostiles, "claw")):
			continue
		return


static func _climb(s: GameState, u: Unit) -> void:
	var best := u.pos
	var best_score := -INF
	var occ := s.occupied(u.id)
	for y in s.grid.height:
		for x in s.grid.width:
			var c := Vector2i(x, y)
			if not s.grid.is_walkable(c) or occ.has(c) or c.distance_to(u.pos) > 10.0:
				continue
			var lvl := EnemyTerrain.level(s, c)
			if lvl <= 0:
				continue
			var score := lvl * 3.0 - c.distance_to(u.pos) * 0.2
			if score > best_score:
				best_score = score
				best = c
	if best != u.pos:
		var from := u.pos
		u.pos = best
		s.emit({"type": "move", "unit": u.id, "from": from, "path": [best] as Array[Vector2i], "leap": true})
