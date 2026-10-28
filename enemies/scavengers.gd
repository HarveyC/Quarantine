class_name Scavengers
extends RefCounted
## Harrow's looters: human enemies who want the squad's kit, not their blood.
##   Cutter    claws like a Runner; a hit lifts one of the soldier's items, then it runs for the edge.
##             Kill it to get the item back. If it escapes, the item is gone for the rest of the fight.
##   Torchman  lobs firebombs (EnemyAbilities "firebomb"); its fuel tank bursts into flame when it dies.
##   Fence     keeps clear of the squad with a sack of loot, then slips off the map. Killing it pays Supplies.
## Status keys: soldier "stolen": Array[String] item ids GearFx.mk ignores; Cutter "loot":
## {"unit": soldier id, "item": id}; any Scavenger "fled": true once it has left the map.
## Every action still goes through Rules.validate/apply. OWNER: enemies workstream.


# --- AI -------------------------------------------------------------------------------------

## Rushes like a Runner until it holds loot, then runs for the nearest map edge.
static func cutter(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	if u.status.has("loot"):
		return _run_for_edge(s, u)
	return EnemyBehaviours.rush(s, u, hostiles, "claw")


## Hangs back 5 to 8 tiles from the squad, and leaves the map once the fight has run long enough
## or a soldier gets close.
static func fence(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	var near := INF
	for h in hostiles:
		near = minf(near, EnemyAI._dist(u.pos, h.pos))
	if s.turn >= EnemyRoster.FENCE_LEAVES_TURN or near <= 2.0:
		return _run_for_edge(s, u)
	var reach := Rules.move_range(s, u)
	var best := u.pos
	var best_score := EnemyBehaviours._flee_score(s, u, u.pos, hostiles)
	for c in reach:
		var sc := EnemyBehaviours._flee_score(s, u, c, hostiles) - int(reach[c]) * 0.02
		if sc > best_score:
			best_score = sc
			best = c
	if best != u.pos:
		return EnemyAI._check(s, {"type": Types.MOVE, "unit": u.id, "to": best})
	return {}


static func edge_dist(s: GameState, c: Vector2i) -> int:
	return mini(mini(c.x, c.y), mini(s.grid.width - 1 - c.x, s.grid.height - 1 - c.y))


## Walks toward the nearest edge cell; once on the edge it slips away.
static func _run_for_edge(s: GameState, u: Unit) -> Dictionary:
	if edge_dist(s, u.pos) == 0:
		escape(s, u)
		return {}
	var reach := Rules.move_range(s, u)
	var best := u.pos
	var best_score := -float(edge_dist(s, u.pos))
	for c in reach:
		var sc := -float(edge_dist(s, c)) - int(reach[c]) * 0.01 - Hazards.avoid_cost(s, u, c)
		if sc > best_score:
			best_score = sc
			best = c
	if best != u.pos:
		return EnemyAI._check(s, {"type": Types.MOVE, "unit": u.id, "to": best})
	return {}


## The Scavenger leaves the fight: whatever it carried goes with it.
static func escape(s: GameState, u: Unit) -> void:
	u.status["fled"] = true
	s.emit({"type": "fled", "unit": u.id, "loot": u.status.has("loot") or u.kind == "fence"})
	Encounter.kill(s, u)


# --- rules ----------------------------------------------------------------------------------

## A Cutter's claw landed on `t`: it lifts the soldier's best item that it hasn't already taken.
static func snatch(s: GameState, u: Unit, t: Unit) -> void:
	if u.status.has("loot") or not u.is_alive() or t.team != Types.Team.PLAYER:
		return
	var item := _best_item(t)
	if item == "":
		return
	var stolen: Array = t.status.get("stolen", [])
	stolen.append(item)
	t.status["stolen"] = stolen
	u.status["loot"] = {"unit": t.id, "item": item}
	s.emit({"type": "stolen", "unit": t.id, "thief": u.id, "item": item})


static func _best_item(t: Unit) -> String:
	var g: Dictionary = t.status.get("gear", {})
	var stolen: Array = t.status.get("stolen", [])
	var best := ""
	var best_mk := 0
	var slots := g.keys()
	slots.sort()
	for slot in slots:
		var id: String = g[slot].id
		if stolen.has(id) or GearFx.is_pending(id):
			continue
		if int(g[slot].mk) > best_mk:
			best_mk = int(g[slot].mk)
			best = id
	return best


## Hook from Encounter.on_died.
static func on_died(s: GameState, u: Unit) -> void:
	if u.status.get("fled", false):
		return
	if u.status.has("loot"):
		var thief_loot: Dictionary = u.status.loot
		var t := s.get_unit(int(thief_loot.unit))
		if t != null:
			var stolen: Array = t.status.get("stolen", [])
			stolen.erase(thief_loot.item)
			t.status["stolen"] = stolen
			s.emit({"type": "recovered", "unit": t.id, "item": thief_loot.item})
	if u.kind == "fence":
		s.encounter["loot"] = int(s.encounter.get("loot", 0)) + 1
		s.emit({"type": "loot", "unit": u.id, "supplies": EnemyRoster.FENCE_SUPPLIES})
	if u.kind == "torchman" and s.phase != Types.Phase.ENDED:
		Hazards.add(s, EnemyAbilities.square(s.grid, u.pos, 1), "fire", EnemyRoster.TANK_FIRE_TURNS, u.id, Types.Team.ENEMY)
