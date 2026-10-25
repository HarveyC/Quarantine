class_name Mutations
extends RefCounted
## Active mutations: listing for the HUD, validation and effects. Infection.available_mutations /
## validate_mutation / apply_mutation delegate here. OWNER: progression workstream.
##
## A soldier can use an active mutation that is (a) grafted in one of their slots and awake,
## (b) a Vector's awake Exposed mutation lent to them by Hive Link, or (c) mirrored this turn by a
## Mirror Graft partner (no action, cost already paid).

const LEECH_INFECTED_EXTRA := 5
const ACID_RANGE := 5.0
const ACID_DAMAGE := 3
const ACID_SPLASH := 5
const RALLY_RADIUS := 3.0
const RALLY_GAIN := 3
const CAST_RANGE := 6.0


## Infection per use for `u`, after Sealed Suit (+5), Willing Host (-5), Apex (-5), Patient Zero (0).
static func use_cost(u: Unit, id: String) -> int:
	var base := MutationData.base_use_cost(id)
	if base <= 0:
		return 0
	if Kit.awake(u, "patient_zero"):
		return 0
	var cost := base
	if Kit.has_passive(u, "sealed_suit"):
		cost += 5
	if Kit.has_passive(u, "willing_host"):
		cost = maxi(5, cost - 5)
	if Kit.has_perk(u, "apex"):
		cost = maxi(5, cost - 5)
	if GearFx.has_set(u, "Strain"):
		cost = maxi(5, cost - 5)
	return cost


## How `u` gets to use `id` right now: "own", "dormant" (grafted but asleep), "borrowed" (Hive Link),
## "mirror" (Mirror Graft this turn) or "" (can't).
static func source(s: GameState, u: Unit, id: String) -> String:
	if not MutationData.get_def(id).get("active", false):
		return ""
	var mirror: Dictionary = u.status.get("k_mirror", {})
	if mirror.get("id", "") == id and int(mirror.get("turn", -1)) == s.turn:
		return "mirror"
	if Kit.has_mutation(u, id):
		return "own" if Kit.awake(u, id) else "dormant"
	var v := s.get_unit(int(u.status.get("k_hive_link_from", -1)))
	if v != null and v.is_alive() and Kit.awake(v, "hive_link") and v.status.get("mutations", {}).get("exposed", "") == id and Kit.awake(v, id):
		return "borrowed"
	return ""


## HUD list: {id, name, desc, cost, actions, targeting, ready, reason, cooldown, source, tier}.
static func available(s: GameState, u: Unit) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not Kit.is_soldier(u):
		return out
	var ids: Array[String] = []
	for slot in MutationData.SLOTS:
		var id: String = u.status.get("mutations", {}).get(slot, "")
		if id != "" and not ids.has(id):
			ids.append(id)
	var mirror: String = u.status.get("k_mirror", {}).get("id", "")
	var lender := s.get_unit(int(u.status.get("k_hive_link_from", -1)))
	for extra in [mirror, lender.status.get("mutations", {}).get("exposed", "") if lender else ""]:
		if extra != "" and not ids.has(extra):
			ids.append(extra)
	for id in ids:
		var src := source(s, u, id)
		if src == "":
			continue
		var m := MutationData.get_def(id)
		var reason := reason_for(s, u, id)
		out.append({
			"id": id, "name": m.name, "desc": "%s Drawback: %s" % [m.desc, m.drawback],
			"cost": 0 if src == "mirror" else use_cost(u, id), "actions": 0 if src == "mirror" else int(m.get("actions", 1)),
			"targeting": m.get("targeting", "none"), "ready": reason == "", "reason": reason,
			"cooldown": int(u.cooldowns.get(id, 0)), "source": src, "tier": MutationData.awake_at(id),
		})
	return out


static func reason_for(s: GameState, u: Unit, id: String) -> String:
	if not MutationData.has(id):
		return "Unknown mutation"
	if not u.is_alive():
		return "No such unit"
	if not Kit.is_soldier(u):
		return "Only soldiers can mutate"
	var src := source(s, u, id)
	if src == "":
		return "Unknown mutation" if not Kit.has_mutation(u, id) else "Passive"
	if src == "dormant":
		return "Dormant until %s" % Infection.tier_name(MutationData.awake_at(id))
	var actions: int = 0 if src == "mirror" else int(MutationData.get_def(id).get("actions", 1))
	if u.actions_left < maxi(1, actions):
		return "No actions left"
	if int(u.cooldowns.get(id, 0)) > 0:
		return "Cooling down (%d)" % int(u.cooldowns[id])
	match id:
		"adrenal_surge":
			if u.status.get("k_surge_turn") == s.turn:
				return "Already used this turn"
		"lure_scent", "rally_musk":
			if u.status.get("k_%s_turn" % id) == s.turn:
				return "Already used this turn"
		"hive_link":
			if u.status.get("k_hive_linked", false):
				return "Already linked this fight"
	if MutationData.get_def(id).get("targeting", "none") == "unit" and targets_for(s, u, id).is_empty():
		return "No targets"
	return ""


static func targets_for(s: GameState, u: Unit, id: String) -> Array[int]:
	var out: Array[int] = []
	for t in s.units:
		if target_error(s, u, id, t) == "":
			out.append(t.id)
	return out


static func target_error(s: GameState, u: Unit, id: String, t: Unit) -> String:
	if t == null or not t.is_alive() or t == u:
		return "No such target"
	match id:
		"leech_bite":
			if not u.is_enemy_of(t) or not s.grid.melee_reach(u.pos, t.pos):
				return "Not an adjacent enemy"
		"acid_spit":
			if not u.is_enemy_of(t) or u.pos.distance_to(t.pos) > ACID_RANGE or not Combat.can_see(s, u.pos, t.pos):
				return "No enemy in range"
		"hollow_voice":
			if t.team != Types.Team.ENEMY or not UnitData.ENEMIES.has(t.kind) or UnitData.ENEMIES[t.kind].get("boss", false):
				return "Only non-boss Infected"
			if not Combat.can_see(s, u.pos, t.pos):
				return "No line of sight"
		"flies":
			if not u.is_enemy_of(t) or not Combat.can_see(s, u.pos, t.pos):
				return "No line of sight"
			if t.status.get("k_flies", false):
				return "Already swarmed"
		"hive_link":
			if not Kit.is_soldier(t):
				return "Not an ally"
		_:
			return "No target needed"
	return ""


static func _cell_error(s: GameState, u: Unit, id: String, cell: Variant) -> String:
	if not cell is Vector2i or not s.grid.in_bounds(cell):
		return "No target cell"
	match id:
		"rampage":
			if cell == u.pos or not Rules.move_range(s, u).has(cell):
				return "Out of range"
		_:
			if u.pos.distance_to(cell) > CAST_RANGE or not Combat.can_see(s, u.pos, cell):
				return "Out of range"
	return ""


static func validate(s: GameState, u: Unit, action: Dictionary) -> String:
	var id := str(action.get("mutation", ""))
	var err := reason_for(s, u, id)
	if err != "":
		return err
	match MutationData.get_def(id).get("targeting", "none"):
		"unit":
			return target_error(s, u, id, s.get_unit(int(action.get("target", -1))))
		"cell":
			return _cell_error(s, u, id, action.get("cell"))
	return ""


## Applies a validated mutation: actions, effect (emits {"type": "mutation", ...}), then Infection cost.
static func apply(s: GameState, u: Unit, action: Dictionary) -> void:
	var id: String = action.mutation
	var m := MutationData.get_def(id)
	var src := source(s, u, id)
	var cost := 0 if src == "mirror" else use_cost(u, id)
	if src == "mirror":
		u.status.erase("k_mirror")
	else:
		u.actions_left -= int(m.get("actions", 1))
	var t := s.get_unit(int(action.get("target", -1)))
	var ev := {"type": "mutation", "unit": u.id, "mutation": id}
	if t != null:
		ev["target"] = t.id
	if action.has("cell"):
		ev["cell"] = action.cell
	match id:
		"adrenal_surge":
			u.actions_left += 1
			u.status["k_surge_turn"] = s.turn
			u.status["k_surge_penalty"] = s.turn + 1
			s.emit(ev.merged({"actions": u.actions_left}))
		"lure_scent":
			u.status["k_lure_scent_turn"] = s.turn
			u.status["k_lure_turn"] = s.turn
			u.status["k_lure_until"] = Combat.phase_index(s) + (2 if s.phase == Types.Phase.TEAM else 1)
			s.emit(ev)
		"leech_bite":
			_leech(s, u, t, ev)
		"acid_spit":
			s.emit(ev.merged({"damage": ACID_DAMAGE}))
			Rules.deal_damage(s, t, ACID_DAMAGE, u)
			if t.is_alive():
				t.status["suppressed"] = Combat.phase_index(s) + 2
				t.overwatch = false
			for a in s.living(Types.Team.PLAYER):
				if Kit.is_soldier(a) and Kit.cheb(a.pos, t.pos) == 1:
					Infection.add(s, a, ACID_SPLASH)
		"rally_musk":
			u.status["k_rally_musk_turn"] = s.turn
			var allies: Array[Unit] = []
			for a in s.living(Types.Team.PLAYER):
				if a != u and Kit.is_soldier(a) and a.pos.distance_to(u.pos) <= RALLY_RADIUS:
					allies.append(a)
			s.emit(ev.merged({"units": allies.map(func(x: Unit) -> int: return x.id)}))
			for a in allies:
				a.status["k_rally_turn"] = s.turn
				Kit.refresh_stats(s, a)
				Infection.add(s, a, RALLY_GAIN)
		"rampage":
			_rampage(s, u, action.cell, ev)
		"hollow_voice":
			u.status["k_hollow_voice"] = true
			s.emit(ev)
			_seize(s, t)
		"overgrowth":
			_overgrowth(s, u, action.cell)
			s.emit(ev)
		"spore_burst":
			var cells: Array[Vector2i] = []
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var c: Vector2i = action.cell + Vector2i(dx, dy)
					if s.grid.is_walkable(c):
						cells.append(c)
			s.emit(ev)
			var z := Zones.add(s, "spore_burst", cells, Combat.phase_index(s) + 3, u)
			for c in cells:
				var o := s.unit_at(c)
				if o != null:
					Zones.burst_tick(s, z, o)
		"hive_link":
			u.status["k_hive_linked"] = true
			u.status["k_hive_link_to"] = t.id
			t.status["k_hive_link_from"] = u.id
			s.emit(ev)
		"flies":
			t.status["k_flies"] = true
			s.emit(ev)
	if src == "own" or src == "borrowed":
		_mirror(s, u, id, cost)
	if cost > 0 and u.is_alive():
		cost = GearFx.mutation_cost(s, u, cost)   # Symbiotic suit pays it in HP
	if cost > 0 and u.is_alive():
		Infection.add(s, u, cost)


## Mirror Graft: the partner pays the same cost now and may use the mutation free this turn.
static func _mirror(s: GameState, u: Unit, id: String, cost: int) -> void:
	var p := Kit.bond_partner(s, u, "mirror_graft")
	if p == null or not Kit.awake(u, "mirror_graft"):
		return
	p.status["k_mirror"] = {"id": id, "turn": s.turn}
	if cost > 0:
		Infection.add(s, p, cost)


static func _melee(s: GameState, u: Unit, t: Unit) -> int:
	var odds := Combat.melee_chance(s, u, t)
	var r := Combat.resolve_roll(s.rng.randi_range(1, 100), odds)
	if not (r.hit or r.graze):
		return 0
	return Combat.final_damage(s.rng.randi_range(u.damage.x, u.damage.y), r.graze, false)


static func _leech(s: GameState, u: Unit, t: Unit, ev: Dictionary) -> void:
	var dmg := _melee(s, u, t)
	var healed := mini(dmg, u.max_hp - u.hp)
	s.emit(ev.merged({"hit": dmg > 0, "damage": dmg, "healed": healed}))
	if dmg > 0:
		Rules.deal_damage(s, t, dmg, u)
		u.hp += healed
	if t.team == Types.Team.ENEMY:
		Infection.add(s, u, LEECH_INFECTED_EXTRA)


static func _rampage(s: GameState, u: Unit, cell: Vector2i, ev: Dictionary) -> void:
	var path := s.grid.find_path(u.pos, cell, s.occupied(u.id))
	var from := u.pos
	var victims: Array[Unit] = []
	for c in path:
		for o in s.living():
			if o != u and u.is_enemy_of(o) and Kit.cheb(o.pos, c) == 1 and not victims.has(o):
				victims.append(o)
	u.pos = cell
	s.emit({"type": "move", "unit": u.id, "from": from, "path": path})
	s.emit(ev.merged({"units": victims.map(func(x: Unit) -> int: return x.id)}))
	for o in victims:
		if not u.is_alive():
			break
		var dmg := _melee(s, u, o)
		s.emit({"type": "ability", "unit": u.id, "ability": "claw", "target": o.id, "hit": dmg > 0,
			"graze": false, "damage": dmg, "chance": Combat.melee_chance(s, u, o).hit})
		if dmg > 0:
			Rules.deal_damage(s, o, dmg, u)
	if u.is_alive():
		Infection.roll_lapse(s, u)


## Hollow Voice: the Infected attacks its nearest ally right now and loses its next turn.
static func _seize(s: GameState, t: Unit) -> void:
	t.status["k_skip_turn"] = true
	var best: Unit = null
	for o in s.living(Types.Team.ENEMY):
		if o != t and (best == null or o.pos.distance_to(t.pos) < best.pos.distance_to(t.pos)):
			best = o
	if best == null:
		return
	if s.grid.melee_reach(t.pos, best.pos) or UnitData.is_melee_only(t.kind):
		if not s.grid.melee_reach(t.pos, best.pos):
			return
		var dmg := _melee(s, t, best)
		s.emit({"type": "ability", "unit": t.id, "ability": "claw", "target": best.id, "hit": dmg > 0,
			"graze": false, "damage": dmg, "chance": Combat.melee_chance(s, t, best).hit})
		if dmg > 0:
			Rules.deal_damage(s, best, dmg, t)
	elif Combat.can_see(s, t.pos, best.pos):
		Combat.fire(s, t, best, false)


static func _overgrowth(s: GameState, u: Unit, cell: Vector2i) -> void:
	var walls: Array[Vector2i] = []
	var spores: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := cell + Vector2i(dx, dy)
			if not s.grid.is_walkable(c):
				continue
			if s.unit_at(c) == null:
				walls.append(c)
				Zones.set_tile(s.grid, c, Types.Tile.WALL)
			else:
				spores.append(c)
	var until := Combat.phase_index(s) + 4
	Zones.add(s, "growth", walls, until, u)
	Hazards.add(s, spores, "spore", 2, u.id)
