extends RefCounted
## A simple squad player for the balance sim: plays each soldier the way a sensible player would.
## Moves to cover with a shot, shoots the best target, uses the class ability when it clearly
## helps, overwatches when there is nothing to shoot. Every action goes through Rules.apply, so
## the sim plays by the real rules. Not used by the game itself.

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
	var a := _support(s, u)
	if not a.is_empty():
		return a
	a = _class_attack(s, u)
	if not a.is_empty():
		return a
	var shot := _best_shot(s, u, u.pos)
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


static func _class_attack(s: GameState, u: Unit) -> Dictionary:
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
	if _is_tether(s, t):
		v = v * 2.0 + 1.0
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
static func _best_move(s: GameState, u: Unit, hostiles: Array[Unit], shot_here: Dictionary) -> Dictionary:
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
	if best_cell == u.pos or best < here + 0.4:
		return {}
	return {"type": Types.MOVE, "unit": u.id, "to": best_cell}


static func _cell_score(s: GameState, u: Unit, c: Vector2i, hostiles: Array[Unit], awake: Array[Unit],
		field: Dictionary, here: bool) -> float:
	var score := 0.0
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
			if _immune(s, t):
				v = 0.01
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
