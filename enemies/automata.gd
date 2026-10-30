class_name Automata
extends RefCounted
## The colony's machines, still following their last orders around the drill shaft.
##   Hound drone   fast and fragile; hunts the weakest soldier and ignores the rest.
##   Loader frame  armoured; charges through cover like a Brute.
##   Tender        a repair frame: mends every wounded machine in sight within REPAIR_RANGE for REPAIR_HEAL.
##   Carrier       a static drone bay (Encounter spawner): drops CARRIER_DROP Hounds every CARRIER_EVERY rounds
##                 until it is shot down.
##   Arc-welder    a short arc that never misses, then jumps through soldiers beside the one it hit.
##   Relay         a mast. Machines within RELAY_RANGE of a living one get a third action each turn;
##                 with none alive they get a single action.
## Every action still goes through Rules.validate/apply. OWNER: enemies workstream.


static func is_machine(u: Unit) -> bool:
	return UnitData.ENEMIES.get(u.kind, {}).get("machine", false)


## The soldier with the least HP (nearest on ties): a Hound goes only for them.
static func hound_targets(hostiles: Array[Unit]) -> Array[Unit]:
	var best: Unit = null
	for h in hostiles:
		if best == null or h.hp < best.hp:
			best = h
	var out: Array[Unit] = []
	if best != null:
		out.append(best)
	return out


static func relay_near(s: GameState, u: Unit) -> bool:
	for o in s.living(u.team):
		if o.kind == "relay" and Kit.cheb(o.pos, u.pos) <= EnemyRoster.RELAY_RANGE:
			return true
	return false


static func relay_alive(s: GameState, u: Unit) -> bool:
	for o in s.living(u.team):
		if o.kind == "relay":
			return true
	return false


## Hook from Encounter.on_unit_turn_start.
static func on_turn_start(s: GameState, u: Unit) -> void:
	if not is_machine(u) or not u.is_alive():
		return
	if relay_near(s, u):
		u.actions_left = maxi(u.actions_left, Types.ACTIONS_PER_TURN + 1)
	elif not relay_alive(s, u):
		u.actions_left = 1
		if not u.status.get("stalled", false):
			u.status["stalled"] = true
			s.emit({"type": "stalled", "unit": u.id})


# --- Tender ------------------------------------------------------------------------------------

static func is_repairable(o: Unit) -> bool:
	return is_machine(o) or o.kind == "relay"


static func repair_targets(s: GameState, u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for o in s.living(u.team):
		if o != u and is_repairable(o) and o.hp < o.max_hp and EnemyAbilities._cheb(u.pos, o.pos) <= EnemyRoster.REPAIR_RANGE \
				and Combat.can_see(s, u.pos, o.pos):
			out.append(o)
	return out


static func tender(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	if int(u.cooldowns.get("repair", 0)) <= 0 and not repair_targets(s, u).is_empty():
		return EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "repair"})
	return EnemyBehaviours.support(s, u, hostiles)


static func repair(s: GameState, u: Unit) -> void:
	var ids: Array[int] = []
	var healed := {}
	for o in repair_targets(s, u):
		healed[o.id] = mini(EnemyRoster.REPAIR_HEAL, o.max_hp - o.hp)
		o.hp += int(healed[o.id])
		ids.append(o.id)
	s.emit({"type": "ability", "unit": u.id, "ability": "repair", "units": ids})
	for id in ids:
		s.emit({"type": "regenerate", "unit": id, "healed": int(healed[id]), "hp": s.get_unit(id).hp})


# --- Arc-welder --------------------------------------------------------------------------------

## Soldiers the arc jumps to after `t`: beside it, then beside those, up to ARC_CHAIN_LINKS links.
static func arc_chain(s: GameState, u: Unit, t: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	var frontier: Array[Unit] = [t]
	for link in EnemyRoster.ARC_CHAIN_LINKS:
		var next: Array[Unit] = []
		for f in frontier:
			for o in s.living(t.team):
				if o != t and not out.has(o) and EnemyAbilities._cheb(f.pos, o.pos) <= 1:
					out.append(o)
					next.append(o)
		frontier = next
	return out


static func arc(s: GameState, u: Unit, t: Unit) -> void:
	var dmg := s.rng.randi_range(u.damage.x, u.damage.y)
	var cover := Elevation.adjust_cover(s, u, t, u.pos, Combat.cover_against(s.grid, t.pos, u.pos))
	if cover == Types.Cover.FULL:
		dmg = maxi(1, dmg / 2)
	var chain := arc_chain(s, u, t)
	s.emit({"type": "ability", "unit": u.id, "ability": "arc", "target": t.id, "hit": true, "damage": dmg,
		"units": chain.map(func(x: Unit) -> int: return x.id), "damage_chain": EnemyRoster.ARC_CHAIN_DAMAGE})
	Rules.deal_damage(s, t, dmg, u)
	for o in chain:
		if o.is_alive() and s.phase != Types.Phase.ENDED:
			Rules.deal_damage(s, o, EnemyRoster.ARC_CHAIN_DAMAGE, u)


## Arcs the target that jumps furthest, else walks to a cell within ARC_RANGE of one.
static func welder(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	var best := {}
	var best_score := -INF
	for t in hostiles:
		var a := EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "arc", "target": t.id})
		if a.is_empty():
			continue
		var score := 3.0 + arc_chain(s, u, t).size() * 2.0 + EnemyAI._target_score(s, u, t, u.pos) * 0.1
		if score > best_score:
			best_score = score
			best = a
	if not best.is_empty():
		return best
	var reach := Rules.move_range(s, u)
	var best_cell := u.pos
	var cell_score := -INF
	for c in reach:
		if EnemyAI.telegraph_cost(s, c) > 0.0:
			continue
		for t in hostiles:
			if EnemyAbilities._cheb(c, t.pos) <= EnemyRoster.ARC_RANGE and Combat.can_see(s, c, t.pos):
				var sc := 3.0 + arc_chain(s, u, t).size() * 2.0 - int(reach[c]) * 0.1 - Hazards.avoid_cost(s, u, c)
				if sc > cell_score:
					cell_score = sc
					best_cell = c
	if best_cell != u.pos:
		return EnemyAI._check(s, {"type": Types.MOVE, "unit": u.id, "to": best_cell})
	return EnemyAI._advance(s, u, hostiles)
