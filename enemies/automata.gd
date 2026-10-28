class_name Automata
extends RefCounted
## The colony's machines, still following their last orders around the drill shaft.
##   Hound drone   fast and fragile; hunts the weakest soldier and ignores the rest.
##   Loader frame  armoured; charges through cover like a Brute.
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
