class_name FightBuilder
extends RefCounted
## Builds a fight's enemy list and encounter from a threat budget (design doc, Enemies:
## Outbreak scaling). Pure and deterministic from `spec.seed`. OWNER: enemies workstream.
##
## spec = {act (1-3), row, node ("skirmish" | "ambush" | "nest" | "boss"),
##         objective ("extract" | "hold" | "rescue" | "purge" | "boss"), outbreak, seed, players,
##         squad (soldiers deploying, 1-4; default 4),
##         modifiers: {extra_enemies, enemies_dead_at_start, ambush, detected, boss_health_mult}}
## Fights scale with `squad` (co-op squads are one soldier per player), not with `players`.

const SKIRMISH_BUDGET := {1: 6, 2: 7, 3: 9}
const NEST_BUDGET := {1: 3, 2: 4, 3: 5}     # on top of the elite and the Hive node
const BOSS_BUDGET := {1: 0, 2: 0, 3: 0}     # bosses bring their own adds
const BUDGET_PER_ENEMY := 2                  # each "+1 enemy" from events or Severity
## Regular fights gain 2 budget for every 3 Outbreak points, so every point counts: 3 gives +2
## (one enemy, as Spreading always did), 6 gives +4 (Rampant's two), capped at 9+.
const OUTBREAK_BUDGET_CAP := 6
const ENEMY_CAP := 5
const MIN_START := 3
## Threat budget share, fewest starting enemies and boss health by squad size (4 is the baseline
## the budgets are tuned for). Tuned with the balance sim (tools/balance): a squad of each size
## loses roughly the same share of its HP per fight.
const SQUAD_BUDGET := {1: 0.35, 2: 0.5, 3: 0.75, 4: 1.0}
const SQUAD_MIN_START := {1: 1, 2: 2, 3: 3, 4: 3}
const SQUAD_BOSS_HEALTH := {1: 0.35, 2: 0.4, 3: 0.6, 4: 1.0}
## Colonel Hale's escort by squad size.
## Spore nests a Purge objective places, by squad size.
const PURGE_NESTS := {1: 2, 2: 2, 3: 2, 4: 3}
const PURGE_BUDGET_CUT := 2
const HALE_ADDS := {1: [], 2: [], 3: ["fallen"], 4: ["fallen", "fallen", "sharpshooter"]}
## A lone soldier can't break a Lurker's pin (a teammate has to hit it), so it never meets one.
const SOLO_BANNED: Array[String] = ["lurker"]
const STAGE_NAMES: Array[String] = ["Contained", "Spreading", "Rampant", "Critical", "Collapse"]


## Outbreak stage: 0 Contained (0-2), 1 Spreading (3-5), 2 Rampant (6-8), 3 Critical (9-12), 4 Collapse (13+).
static func stage(outbreak: int) -> int:
	if outbreak >= 13:
		return 4
	if outbreak >= 9:
		return 3
	if outbreak >= 6:
		return 2
	if outbreak >= 3:
		return 1
	return 0


## Threat budget Outbreak adds to a regular fight (not a boss).
static func outbreak_budget(outbreak: int) -> int:
	return mini(OUTBREAK_BUDGET_CAP, maxi(0, outbreak) * 2 / 3)


static func build(spec: Dictionary) -> Dictionary:
	var act := clampi(int(spec.get("act", 1)), 1, 3)
	var node := str(spec.get("node", "skirmish"))
	var objective := str(spec.get("objective", ""))
	var mods: Dictionary = spec.get("modifiers", {})
	var st := stage(int(spec.get("outbreak", 0)))
	var squad := clampi(int(spec.get("squad", 4)), 1, 4)
	var cap := mini(ENEMY_CAP, squad + 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 1)) * 7919 + 17
	# The elite is rolled first so preview() can show it without knowing Outbreak.
	var elite_kind := _pick(rng, EnemyRoster.elite_pool(act))
	var extra := int(mods.get("extra_enemies", 0))
	if node == "boss":
		extra += 1 if st >= 2 else 0   # bosses bring their own adds
	var budget := 0
	match node:
		"nest": budget = NEST_BUDGET[act]
		"boss": budget = BOSS_BUDGET[act]
		_: budget = SKIRMISH_BUDGET[act]
	budget += BUDGET_PER_ENEMY * extra
	if node != "boss":
		budget += outbreak_budget(int(spec.get("outbreak", 0)))
	if objective == "purge":
		budget -= PURGE_BUDGET_CUT   # the spore nests keep adding Runners
	budget = ceili(budget * float(SQUAD_BUDGET[squad]))
	var enemies: Array[String] = []
	var enc := {"act": act, "node": node, "objective": objective, "outbreak": int(spec.get("outbreak", 0)),
		"stage": st, "waves": [], "squad": squad}
	if node == "nest":
		enemies.append(EnemyRoster.spec(elite_kind, true, _affixes(rng, 2 if st >= 3 and squad >= 3 else 1, true)))
		enc["hive"] = true
	elif node != "boss" and st >= 3 and rng.randf() < 0.5:
		var cost: int = EnemyRoster.COST[elite_kind] * 2
		if budget >= cost + 1:
			enemies.append(EnemyRoster.spec(elite_kind, true, _affixes(rng, 1, false)))
			budget -= cost
	if node == "boss":
		enc["boss"] = EnemyRoster.BOSS_OF_ACT[act]
		if act == 2:
			enemies.append_array(HALE_ADDS[squad])
		var share: Dictionary = BroodMother.HEALTH if act == 1 else SQUAD_BOSS_HEALTH
		var mult := float(mods.get("boss_health_mult", 1.0)) * float(share[squad])
		if mult != 1.0:
			enc["boss_health_mult"] = mult
	var pool := EnemyRoster.pool(act)
	if squad == 1:
		pool = pool.filter(func(k: String) -> bool: return not SOLO_BANNED.has(k))
	budget = _buy(rng, pool, budget, enemies, 0 if node == "boss" else mini(SQUAD_MIN_START[squad], cap), act, cap)
	# Spare budget past the cap: an affix on a regular, or an earlier reinforcement wave.
	if st >= 2 and node != "boss":
		enc.waves.append({"turn": 3 if st >= 4 else 4, "every": 3 if st >= 4 else 0, "kinds": _wave(rng, pool, 1 if squad <= 2 else 2, act)})
	var flip := false
	while budget >= BUDGET_PER_ENEMY:
		budget -= BUDGET_PER_ENEMY
		flip = not flip
		if flip or not _hasten_wave(enc.waves):
			_affix_regular(rng, enemies)
	_objective_pressure(rng, objective, pool, enc, squad, act)
	if objective == "purge":
		enc["purge_nests"] = PURGE_NESTS[squad] - (1 if enc.get("hive", false) else 0)   # the Hive node spawns too
	if st >= 1:
		enc["spore_patches"] = 2 if st >= 3 else 1
	if st >= 2:
		enc["infect_bonus"] = 5
	if st >= 4:
		enc["start_infection"] = 10
	if node == "ambush" or mods.get("ambush", false):
		enc["ambush"] = true
	enc["concealed"] = starts_concealed(node, objective, mods)
	var dead := int(mods.get("enemies_dead_at_start", 0))
	while dead > 0 and enemies.size() > 1 and not EnemyRoster.parse(enemies[-1]).elite:
		enemies.pop_back()
		dead -= 1
	return {"enemies": enemies, "encounter": enc}


## Concealment is a per-mission option: most fights start with the squad unseen, but an Ambush
## (the enemy strikes first), Hold the beacon (they know where you're digging in) and boss
## fights start detected. An event can also force it with modifiers.detected.
static func starts_concealed(node: String, objective: String, mods: Dictionary = {}) -> bool:
	if node in ["ambush", "boss"] or objective in ["hold", "boss"]:
		return false
	return not mods.get("ambush", false) and not mods.get("detected", false)


## What the map screen shows for a fight node. Does not depend on Outbreak.
static func preview(spec: Dictionary) -> Dictionary:
	var act := clampi(int(spec.get("act", 1)), 1, 3)
	var node := str(spec.get("node", "skirmish"))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 1)) * 7919 + 17
	var elite_kind := _pick(rng, EnemyRoster.elite_pool(act))
	match node:
		"nest":
			var name: String = UnitData.ENEMIES[elite_kind].name
			return {"title": "Infested nest: Elite " + name, "elite": elite_kind}
		"boss":
			var boss: String = EnemyRoster.BOSS_OF_ACT[act]
			return {"title": UnitData.ENEMIES[boss].name, "elite": ""}
		"ambush":
			return {"title": "Ambush", "elite": ""}
	return {"title": "Skirmish", "elite": ""}


## Most ranged enemies a fight with `cap` slots gets: 1 in 2-4 slots, 2 in 5. The rest are melee.
static func ranged_limit(cap: int) -> int:
	return maxi(1, (cap + 1) / 3)


## Buys regulars until the budget or the cap runs out. Returns the budget left. Mostly melee: ranged
## kinds stop once ranged_limit is reached, and Runners (the staple) fit any budget.
static func _buy(rng: RandomNumberGenerator, pool: Array[String], budget: int, enemies: Array[String], min_start: int, act: int = 1, cap: int = ENEMY_CAP) -> int:
	var ranged := 0
	for e in enemies:
		if EnemyRoster.is_ranged(EnemyRoster.parse(e).kind):
			ranged += 1
	while budget > 0 and enemies.size() < cap:
		var slots := cap - enemies.size()
		var still_needed := maxi(0, min_start - enemies.size() - 1)
		var max_cost := budget - still_needed
		var target := ceili(float(budget) / slots)
		var affordable: Array[String] = []
		var top := 0
		for k in pool:
			var c: int = EnemyRoster.COST[k]
			if c <= max_cost and (ranged < ranged_limit(cap) or not EnemyRoster.is_ranged(k)):
				affordable.append(k)
				top = maxi(top, c)
		if affordable.is_empty():
			break
		var preferred: Array[String] = []
		for k in affordable:
			if EnemyRoster.COST[k] >= mini(target, top) or k == "runner":
				preferred.append(k)
		var kind := _pick_weighted(rng, preferred, act)
		if EnemyRoster.is_ranged(kind):
			ranged += 1
		enemies.append(kind)
		budget -= EnemyRoster.COST[kind]
	return budget


## Reinforcements are melee infected pouring in (mostly Runners), never shooters.
static func _wave(rng: RandomNumberGenerator, pool: Array[String], n: int, act: int = 1) -> Array[String]:
	var cheap: Array[String] = []
	for k in pool:
		if EnemyRoster.COST[k] <= 2 and k != "lurker" and not EnemyRoster.is_ranged(k):
			cheap.append(k)
	var out: Array[String] = []
	for i in n:
		out.append(_pick_weighted(rng, cheap, act))
	return out


## Waves for objective pressure (Hold: every turn from 2 sides; Extract: behind the squad every 2 turns).
static func _objective_pressure(rng: RandomNumberGenerator, objective: String, pool: Array[String], enc: Dictionary, squad: int = 4, act: int = 1) -> void:
	match objective:
		"hold":
			enc.waves.append({"turn": 2, "every": 1, "kinds": _wave(rng, pool, 1, act)})
			if squad >= 3:
				enc.waves.append({"turn": 3, "every": 2, "kinds": _wave(rng, pool, 1, act)})
		"extract":
			enc.waves.append({"turn": 2, "every": 2, "kinds": _wave(rng, pool, 1 if squad <= 2 else 2, act)})


static func _hasten_wave(waves: Array) -> bool:
	for w in waves:
		if int(w.turn) > 2:
			w.turn = int(w.turn) - 1
			return true
	return false


static func _affix_regular(rng: RandomNumberGenerator, enemies: Array[String]) -> void:
	for i in enemies.size():
		var p := EnemyRoster.parse(enemies[i])
		if p.elite or not p.affixes.is_empty():
			continue
		enemies[i] = EnemyRoster.spec(p.kind, false, _affixes(rng, 1, false))
		return


static func _affixes(rng: RandomNumberGenerator, n: int, allow_tether: bool) -> Array[String]:
	var options: Array[String] = []
	for a in EnemyRoster.AFFIXES:
		if a != "tethered" or allow_tether:
			options.append(a)
	var out: Array[String] = []
	for i in n:
		var a := _pick(rng, options)
		options.erase(a)
		out.append(a)
	return out


## Like _pick, with each kind counted EnemyRoster.weight times and the act's signature enemies
## counted twice as often.
static func _pick_weighted(rng: RandomNumberGenerator, from: Array[String], act: int) -> String:
	var bag: Array[String] = []
	for k in from:
		var n: int = EnemyRoster.weight(k, act) * (2 if EnemyRoster.SIGNATURE.get(act, []).has(k) else 1)
		for i in n:
			bag.append(k)
	return _pick(rng, bag)


static func _pick(rng: RandomNumberGenerator, from: Array[String]) -> String:
	return from[rng.randi_range(0, from.size() - 1)]
