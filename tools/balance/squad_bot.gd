extends RefCounted
## A simple squad player for the balance sim: plays each soldier the way a sensible player would.
## Moves to cover with a shot, shoots the best target, uses the class ability when it clearly
## helps, overwatches when there is nothing to shoot. Every action goes through Rules.apply, so
## the sim plays by the real rules. Not used by the game itself.

## nosig=1 in balance_sim: the bot ignores Rank 2 signatures, for before/after comparisons.
static var skip_signatures := false
## nogear=1 in balance_sim: the bot leaves gadgets and pocket items alone, for before/after comparisons.
static var skip_gear := false
## nopurge=1 in balance_sim: the bot does not Flush, Decon or Serum infected allies.
static var skip_purge := false
const COVER_WEIGHT := 1.5      # how much the bot values standing in cover vs. a better shot
const FLANKED_PENALTY := 2.5   # standing in the open in sight of an alerted enemy


## Plays every controllable soldier of `player` for this team phase, then readies the player.
static func play_player(s: GameState, player: int) -> void:
	# Soldiers boxed in by their squadmates go last, once the others have moved out of the way.
	var boxed: Array[Unit] = []
	for u in s.controllable_units(player):
		if Rules.move_range(s, u).size() <= 1:
			boxed.append(u)
			continue
		play_soldier(s, u)
		if s.phase != Types.Phase.TEAM:
			return
	for u in boxed:
		play_soldier(s, u)
		if s.phase != Types.Phase.TEAM:
			return
	if s.phase == Types.Phase.TEAM:
		Rules.set_ready(s, player, true)


static func play_soldier(s: GameState, u: Unit) -> void:
	var struggle := {"type": Types.STRUGGLE, "unit": u.id}
	if Rules.validate(s, struggle) == "":
		Rules.apply(s, struggle)   # a pinned soldier always tries to throw the Lurker off
	for step in 6:
		if not u.is_alive() or u.actions_left <= 0 or s.phase != Types.Phase.TEAM:
			return
		var a := choose(s, u)
		if a.is_empty() or not Rules.apply(s, a):
			return


static func choose(s: GameState, u: Unit) -> Dictionary:
	var hostiles := _hostiles(s, u)
	if hostiles.is_empty():
		return {}
	var reload := {"type": Types.RELOAD, "unit": u.id}
	if Ammo.tracked(u) and Ammo.rounds(u) == 0 and _ok(s, reload):
		return reload   # a dry gun reloads before anything else
	var a := _support(s, u)
	if not a.is_empty():
		return a
	a = _gear_use(s, u)
	if not a.is_empty():
		return a
	a = _class_attack(s, u)
	if not a.is_empty():
		return a
	a = _barrel(s, u)
	if not a.is_empty():
		return a
	var danger := danger_cells(s)
	if danger.has(u.pos):
		var dodge := _best_move(s, u, hostiles, {}, true)
		if not dodge.is_empty():
			return dodge
	var shot := _best_shot(s, u, u.pos)
	if Ammo.tracked(u) and Ammo.rounds(u) <= 1 and u.actions_left >= 2 and (shot.is_empty() or shot.hit < 60) and _ok(s, reload):
		return reload   # last round and no sure shot: reload now, shoot with the second action
	if u.actions_left >= 2:
		var move := _best_move(s, u, hostiles, shot)
		if not move.is_empty():
			return move
	if not shot.is_empty():
		if u.actions_left >= 2 and u.abilities.has("tag") and _ok(s, _tag(u, shot.target)):
			return _tag(u, shot.target)
		if u.abilities.has("suppress") and shot.hit < 40 and EnemyAI.is_alerted(shot.target) \
				and _ok(s, _suppress(u, shot.target)):
			return _suppress(u, shot.target)
		if shot.hit >= 30:
			return shot.action
	var guard := {"type": Types.ABILITY, "unit": u.id, "ability": "guard"}
	if u.abilities.has("guard") and _ok(s, guard) and _melee_threat_near(s, u, 8):
		return guard
	if Ammo.tracked(u) and Ammo.rounds(u) * 2 <= Ammo.mag_size(u) and _ok(s, reload):
		return reload   # nothing to do this turn but top up
	var ow := {"type": Types.OVERWATCH, "unit": u.id}
	return ow if _ok(s, ow) else {}


# --- class abilities ---------------------------------------------------------------------------

## Healing, Infection control and talking down Lapsed allies.
static func _support(s: GameState, u: Unit) -> Dictionary:
	for t in s.living(Types.Team.PLAYER):
		if Infection.is_lapsed(t):
			var a := {"type": Types.ABILITY, "unit": u.id, "ability": "talk_down", "target": t.id}
			if _ok(s, a):
				return a
	if not skip_purge:
		var worst: Unit = null
		var worst_id := ""
		for id in ["purge", "decon", "serum"]:
			if not u.abilities.has(id):
				continue
			var floor_inf := 70 if id == "serum" else 25
			for t in s.living(Types.Team.PLAYER):
				var a := {"type": Types.ABILITY, "unit": u.id, "ability": id, "target": t.id}
				if t.infection >= floor_inf and _ok(s, a) and (worst == null or t.infection > worst.infection):
					worst = t
					worst_id = id
		if worst != null:
			return {"type": Types.ABILITY, "unit": u.id, "ability": worst_id, "target": worst.id}
	if u.abilities.has("stim"):
		var best: Unit = null
		for t in s.living(Types.Team.PLAYER):
			var a := {"type": Types.ABILITY, "unit": u.id, "ability": "stim", "target": t.id}
			if (t.max_hp - t.hp >= 3 or t.infection >= 40) and _ok(s, a):
				if best == null or t.hp < best.hp:
					best = t
		if best != null:
			return {"type": Types.ABILITY, "unit": u.id, "ability": "stim", "target": best.id}
	if u.abilities.has("siphon"):
		for t in s.living(Types.Team.PLAYER):
			var a := {"type": Types.ABILITY, "unit": u.id, "ability": "siphon", "target": t.id}
			if t.infection >= 30 and u.infection < 60 and _ok(s, a):
				return a
	return {}


## Gadgets and pocket items a player would use: flares, concussion, thermite and grenades on a
## cluster of alerted enemies, medkits and injectors on a hurt ally, Adrenal pump when busy.
static func _gear_use(s: GameState, u: Unit) -> Dictionary:
	if skip_gear:
		return {}
	var foes := _hostiles(s, u).filter(func(t: Unit) -> bool: return EnemyAI.is_alerted(t))
	for ab in GearFx.available_abilities(s, u):
		if not ab.ready:
			continue
		var id: String = ab.id
		var base := {"type": Types.ABILITY, "unit": u.id, "ability": id}
		match id:
			"gear:flare_launcher", "gear:concussion_launcher", "gear:thermite_charge", "item:frag_grenade", "item:flashbang":
				var need := 1 if id == "gear:flare_launcher" or id == "gear:thermite_charge" else 2
				var best_cell := Vector2i(-1, -1)
				var best_n := need - 1
				for t in foes:
					var n := 0
					for o in foes:
						if Kit.cheb(o.pos, t.pos) <= 1:
							n += 1
					for ally in s.living(Types.Team.PLAYER):
						if Kit.cheb(ally.pos, t.pos) <= 1:
							n -= 2
					var a := base.duplicate()
					a["cell"] = t.pos
					if n > best_n and _ok(s, a):
						best_n = n
						best_cell = t.pos
				if best_cell.x >= 0:
					base["cell"] = best_cell
					return base
			"gear:med_injector", "item:medkit":
				var worst: Unit = null
				for t in s.living(Types.Team.PLAYER):
					var a := base.duplicate()
					a["target"] = t.id
					if (t.max_hp - t.hp >= 4 or t.infection >= 50) and _ok(s, a) and (worst == null or t.hp < worst.hp):
						worst = t
				if worst != null:
					base["target"] = worst.id
					return base
			"gear:adrenal_pump", "gear:containment_emitter":
				if not foes.is_empty() and _ok(s, base):
					return base
	return {}


## Rank 2 signatures (Signatures): fired as soon as they are ready and clearly useful.
static func _signature(s: GameState, u: Unit) -> Dictionary:
	var id := Signatures.for_class(u.kind)
	if skip_signatures or id == "" or not u.abilities.has(id) or int(u.cooldowns.get(id, 0)) > 0:
		return {}
	var hostiles := _hostiles(s, u)
	var base := {"type": Types.ABILITY, "unit": u.id, "ability": id}
	match id:
		"deadeye", "bring_down":
			var best: Unit = null
			for t in hostiles:
				var a := base.duplicate()
				a["target"] = t.id
				if _ok(s, a) and (best == null or t.hp > best.hp):
					best = t
			if best != null:
				base["target"] = best.id
				return base
			return {}
		"lockdown":
			for t in hostiles:
				if EnemyAI.is_alerted(t) and Kit.cheb(u.pos, t.pos) >= 4 and Kit.cheb(u.pos, t.pos) <= 12 and _ok(s, base):
					return base
		"quarantine_field":
			for a in s.living(Types.Team.PLAYER):
				if Kit.cheb(a.pos, u.pos) <= Signatures.FIELD_RADIUS and (a.infection >= 25 or a.hp * 2 <= a.max_hp) and _ok(s, base):
					return base
		"vent":
			if u.infection >= 35:
				for t in hostiles:
					if Kit.cheb(u.pos, t.pos) <= Signatures.VENT_RADIUS and _ok(s, base):
						return base
		"provoke":
			if u.hp * 2 > u.max_hp:
				for t in hostiles:
					if EnemyAI.is_alerted(t) and Kit.cheb(u.pos, t.pos) <= 8 and _ok(s, base):
						return base
		_:
			if _ok(s, base):   # flashover, death_sweep: validation needs a burning or adjacent enemy
				return base
	return {}


static func _class_attack(s: GameState, u: Unit) -> Dictionary:
	var sig := _signature(s, u)
	if not sig.is_empty():
		return sig
	var melee := _melee_attack(s, u)
	if not melee.is_empty():
		return melee
	if u.abilities.has("breach"):
		var best: Dictionary = {}
		for t in _hostiles(s, u):
			var a := {"type": Types.ABILITY, "unit": u.id, "ability": "breach", "target": t.id}
			if _ok(s, a) and (best.is_empty() or t.hp > s.get_unit(best.target).hp):
				best = a
		if not best.is_empty():
			return best
	if u.abilities.has("incinerate") and int(u.cooldowns.get("incinerate", 0)) <= 0:
		var best_cell := Vector2i(-1, -1)
		var best_score := 1
		for t in _hostiles(s, u):
			if Kit.cheb(u.pos, t.pos) > 3:
				continue
			var score := 0
			for c in ClassAbilities.incinerate_cells(s, u, t.pos):
				var o := s.unit_at(c)
				if o != null and o != u:
					score += 2 if u.is_enemy_of(o) else -3
			if score >= best_score:
				best_score = score
				best_cell = t.pos
		var a := {"type": Types.ABILITY, "unit": u.id, "ability": "incinerate", "cell": best_cell}
		if best_cell.x >= 0 and _ok(s, a):
			return a
	return {}


## Shoot a fuel barrel when the blast (and any chain, Destruction.barrel_blasts) catches more
## enemies than allies: enemies count 2, likely kills 3 more, allies -4, all weighed by the odds
## of hitting the drum (Combat.barrel_chance). A sure shot needs a score of 3.
static func _barrel(s: GameState, u: Unit) -> Dictionary:
	var best: Dictionary = {}
	var best_score := 3.0
	for c in Combat.shot_barrels(s, u):
		var blasts := Destruction.barrel_blasts(s, c)
		var score := 0
		for o in s.living():
			var hits := blasts.filter(func(b: Vector2i) -> bool: return Kit.cheb(b, o.pos) <= 1).size()
			if hits == 0:
				continue
			if u.is_enemy_of(o):
				score += 2 + (3 if o.hp <= hits * Destruction.BARREL.damage else 0)
			else:
				score -= 4
		var weighed := score * float(Combat.barrel_chance(s, u, c).hit) / 100.0
		if weighed >= best_score:
			best_score = weighed
			best = {"type": Types.SHOOT, "unit": u.id, "cell": c}
	return best


static func _tag(u: Unit, t: Unit) -> Dictionary:
	return {"type": Types.ABILITY, "unit": u.id, "ability": "tag", "target": t.id}


static func _suppress(u: Unit, t: Unit) -> Dictionary:
	return {"type": Types.ABILITY, "unit": u.id, "ability": "suppress", "target": t.id}


# --- shooting and moving -----------------------------------------------------------------------

## Best shot from where `u` stands: {action, hit, target, ev}, or {}.
static func _best_shot(s: GameState, u: Unit, from: Vector2i) -> Dictionary:
	if UnitData.is_melee_only(u.kind):
		return {}
	var best := {}
	for t in Combat.shot_targets(s, u):
		var ev := _shot_value(s, u, t, from)
		var a := {"type": Types.SHOOT, "unit": u.id, "target": t.id}
		if (best.is_empty() or ev > best.ev) and _ok(s, a):
			best = {"action": a, "hit": int(Combat.hit_chance(s, u, t, from).hit), "target": t, "ev": ev}
	return best


## Expected value of shooting `t` from `from`: expected damage, with a bonus for likely kills.
static func _shot_value(s: GameState, u: Unit, t: Unit, from: Vector2i) -> float:
	var odds := Combat.hit_chance(s, u, t, from)
	var p := float(odds.hit) / 100.0
	var avg := (u.damage.x + u.damage.y) / 2.0
	var v := p * minf(avg, t.hp)
	if u.damage.x >= t.hp:
		v += p * 3.0
	elif u.damage.y >= t.hp:
		v += p * 1.5
	if _immune(s, t):
		return 0.01
	if t.status.has("pinning"):
		v = v * 2.0 + 2.0   # any hit frees the pinned squadmate
	elif _is_tether(s, t):
		v = v * 2.0 + 1.0
	elif t.status.has("spawner"):
		v = v * 1.5 + 0.5   # nests, hive nodes and sacs keep spawning: worth clearing
	elif EnemyRoster.is_static(t):
		v *= 0.6
	return v


## Bosses and Tethered enemies take no damage while their tether kind lives.
static func _immune(s: GameState, t: Unit) -> bool:
	var kind := str(t.status.get("tether", ""))
	if kind == "":
		return false
	for o in s.living():
		if o.kind == kind:
			return true
	return false


static func _is_tether(s: GameState, t: Unit) -> bool:
	for o in s.living():
		if str(o.status.get("tether", "")) == t.kind:
			return true
	return false


## Move to the cell that best trades a good shot against safety; advance when nothing is in reach.
static func _best_move(s: GameState, u: Unit, hostiles: Array[Unit], shot_here: Dictionary, must := false) -> Dictionary:
	var awake: Array[Unit] = []
	for h in hostiles:
		if EnemyAI.is_alerted(h) and not EnemyRoster.is_static(h):
			awake.append(h)
	var reach := Rules.move_range(s, u)
	var field := _distance_field(s, hostiles)
	var here := _cell_score(s, u, u.pos, hostiles, awake, field, true)
	var best_cell := u.pos
	var best := here
	for c in reach:
		var score: float = _cell_score(s, u, c, hostiles, awake, field, false) - int(reach[c]) * 0.02
		if score > best:
			best = score
			best_cell = c
	if best_cell == u.pos or (best < here + 0.4 and not must):
		return {}
	var a := {"type": Types.MOVE, "unit": u.id, "to": best_cell}
	if _in_melee_reach(s, u) and Kit.cheb(u.pos, best_cell) <= PartingBlow.CAREFUL_RANGE:
		a["careful"] = true
	return a


static func _in_melee_reach(s: GameState, u: Unit) -> bool:
	for h in _hostiles(s, u):
		if PartingBlow.can_swing(s, h) and s.grid.melee_reach(h.pos, u.pos):
			return true
	return false


## Cells something lands on next enemy phase, with the damage: strike telegraphs (airstrikes,
## acid rain, core slams), burrowers' eruptions, Leapers' landings and swelling Bloaters.
static func danger_cells(s: GameState) -> Dictionary:
	var out := {}
	for t in s.encounter.get("telegraphs", []):
		for c in t.cells:
			out[c] = int(out.get(c, 0)) + int(t.damage)
	for e in s.living(Types.Team.ENEMY):
		var at := Vector2i(-1, -1)
		var dmg := 3
		if e.status.has("emerge_cell"):
			at = e.status.emerge_cell
		elif e.status.has("leap_cell"):
			at = e.status.leap_cell
			dmg = EnemyAbilities.LEAP_DAMAGE
		elif e.status.has("swelling"):
			at = e.pos
		if at.x < 0:
			continue
		for c in EnemyAbilities.square(s.grid, at, 1):
			out[c] = int(out.get(c, 0)) + dmg
	return out


static func _cell_score(s: GameState, u: Unit, c: Vector2i, hostiles: Array[Unit], awake: Array[Unit],
		field: Dictionary, here: bool) -> float:
	var score := -float(_danger_cache(s).get(c, 0)) * 2.0
	# Offence: the best expected shot from this cell (the soldier has one action left after moving).
	var best_ev := 0.0
	if not UnitData.is_melee_only(u.kind):
		for t in hostiles:
			# Only targets the squad already sees, or that this soldier would see from there.
			var seen: bool = Vision.sees_unit(s, u.team, t) or (not t.status.get("hidden", false) \
				and c.distance_to(t.pos) <= Vision.KIND_SIGHT.get(u.kind, Vision.SOLDIER_SIGHT))
			if seen and c.distance_to(t.pos) <= Combat.SIGHT_RANGE and Combat.can_see(s, c, t.pos):
				best_ev = maxf(best_ev, _shot_value(s, u, t, c))
	score += best_ev * 2.0
	if u.abilities.has("breach") and int(u.cooldowns.get("breach", 0)) <= 0:
		for t in hostiles:
			if Kit.cheb(c, t.pos) <= Combat.BREACH_RANGE and Combat.can_see(s, c, t.pos):
				score += 3.0
				break
	# Defence: cover against every alerted enemy that could see this cell.
	for h in awake:
		if c.distance_to(h.pos) > Combat.SIGHT_RANGE + 2 or not Combat.can_see(s, h.pos, c):
			continue
		match Combat.cover_against(s.grid, c, h.pos):
			Types.Cover.FULL: score += COVER_WEIGHT
			Types.Cover.HALF: score += COVER_WEIGHT * 0.5
			_: score -= FLANKED_PENALTY
		if UnitData.is_melee_only(h.kind) and Kit.cheb(c, h.pos) <= 1:
			score -= 1.5
	# Approach: when nothing is awake or in reach, walk toward the enemy, keeping near the squad.
	score -= float(field.get(c, 99)) * (0.25 if best_ev <= 0.0 else 0.08)
	var allies := 0
	for o in s.living(Types.Team.PLAYER):
		if o != u and Kit.cheb(o.pos, c) <= 6:
			allies += 1
	score += minf(allies, 2) * 0.3
	return score


static var _danger_turn := -1
static var _danger_size := -1
static var _danger := {}


static func _danger_cache(s: GameState) -> Dictionary:
	var key: int = s.log.size()
	if key != _danger_size:
		_danger_size = key
		_danger = danger_cells(s)
	return _danger


static func _distance_field(s: GameState, hostiles: Array[Unit]) -> Dictionary:
	var src: Array[Vector2i] = []
	for h in hostiles:
		src.append(h.pos)
	return EnemyAI._distance_field(s.grid, src)


static func _hostiles(s: GameState, u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for t in s.living():
		if u.is_enemy_of(t) and not Objectives.is_civilian(t):
			out.append(t)
	return out


static func _ok(s: GameState, a: Dictionary) -> bool:
	return Rules.validate(s, a) == ""


# --- melee classes ----------------------------------------------------------------------------

## Reaper / Warden: Bash an adjacent enemy, else Lunge / Shield Charge the best target in reach,
## else (with 2 actions) close in to striking distance.
static func _melee_attack(s: GameState, u: Unit) -> Dictionary:
	if not (u.abilities.has("lunge") or u.abilities.has("bash")):
		return {}
	var best := {}
	var best_v := 0.0
	for id in ["bash", "shield_charge", "lunge"]:
		if not u.abilities.has(id):
			continue
		for t in _hostiles(s, u):
			var a := {"type": Types.ABILITY, "unit": u.id, "ability": id, "target": t.id}
			if not _ok(s, a):
				continue
			var land := ClassAbilities.lunge_landing(s, u, t, ClassAbilities.strike_reach(u, id)) if id != "bash" else u.pos
			var p := float(ClassAbilities.strike_odds(s, u, t, land).hit) / 100.0
			var dmg := ClassAbilities.BLADE_DAMAGE if id == "lunge" else ClassAbilities.MAUL_DAMAGE
			var v := p * minf((dmg.x + dmg.y) / 2.0, t.hp) + (p * 3.0 if dmg.x >= t.hp else 0.0)
			if _immune(s, t) or (t.abilities.has("burst") and id != "bash"):
				v = 0.01   # a Bloater bursts on whoever killed it up close: shoot it instead
			elif EnemyRoster.is_static(t):
				v *= 0.6
			if id == "bash":
				v += 1.0   # 1 action, and the stun
			if v > best_v:
				best_v = v
				best = a
	if not best.is_empty():
		return best
	if u.actions_left < 2 or not u.abilities.has("lunge"):
		return {}
	# Close in: the reachable cell nearest an awake enemy, preferring cover.
	var reach := Rules.move_range(s, u)
	var best_cell := u.pos
	var best_score := INF
	for h in _hostiles(s, u):
		if not EnemyAI.is_alerted(h) or EnemyRoster.is_static(h):
			continue
		for c in reach:
			var d := Kit.cheb(c, h.pos)
			if d > ClassAbilities.strike_reach(u, "lunge"):
				continue
			var score := float(d) - (0.8 if Combat.cover_against(s.grid, c, h.pos) != Types.Cover.NONE else 0.0)
			if score < best_score:
				best_score = score
				best_cell = c
	if best_cell == u.pos:
		return {}
	return {"type": Types.MOVE, "unit": u.id, "to": best_cell}


static func _melee_threat_near(s: GameState, u: Unit, dist: int) -> bool:
	for h in _hostiles(s, u):
		if EnemyAI.is_alerted(h) and UnitData.is_melee_only(h.kind) and Kit.cheb(u.pos, h.pos) <= dist:
			return true
	return false
