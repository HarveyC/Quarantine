class_name Kit
extends RefCounted
## In-mission effects of class passives, perks and mutation passives. OWNER: progression workstream.
## Rules, Combat, Infection and EnemyAI call these hooks at one line each; everything that
## changes state still happens inside Rules.apply / the phase functions, so it replicates.
##
## Unit status keys (stamped by Progression.apply_record, see docs/ARCHITECTURE.md):
##   "perks": Array[String]        perk ids the soldier owns
##   "mutations": {slot: id}       grafted mutations ("exposed", "mutating", "critical", "strain")
##   "rank": int, "uid": String    run rank and the run's soldier id
##   "bond": {"id", "partner"}     Bonded mutation and partner unit id (resolved at mission start)
##   "inoculated": bool            half Infection gain this fight (after a Serum cure)
##   "kit_mods": {stat: n}         stat deltas currently applied by refresh_stats
## Per-fight / per-turn bookkeeping keys are prefixed "k_" and are owned by this file.

const SHOULDER_DEFENSE := 10
const STEADFAST_DEFENSE := 20
const HOLD_LINE_HUNKER := 10
const TRIAGE_DEFENSE := 20
const JUGGERNAUT_DEFENSE := 10
const STEADY_AIM := 10
const LURE_AIM := 15
const LURE_RADIUS := 6.0
const DEADEYE_CRIT := 20
const CHITIN_ARMOR := 2
const WILLING_HOST_FLOOR := 25
const LOW_PROFILE := 15
const SHIELD_UP := 20


# ---------------------------------------------------------------- queries

static func is_soldier(u: Unit) -> bool:
	return u != null and u.team == Types.Team.PLAYER and not u.status.get("turned", false)


static func has_perk(u: Unit, id: String) -> bool:
	return is_soldier(u) and (u.status.get("perks", []) as Array).has(id)


static func has_passive(u: Unit, id: String) -> bool:
	return is_soldier(u) and PerkData.passive(u.kind).get("id", "") == id


## Grafted (awake or dormant).
static func has_mutation(u: Unit, id: String) -> bool:
	return u != null and (u.status.get("mutations", {}) as Dictionary).values().has(id)


## Grafted and the soldier's Infection is at the mutation's tier or higher.
static func awake(u: Unit, id: String) -> bool:
	return is_soldier(u) and has_mutation(u, id) and Infection.tier(u.infection) >= MutationData.awake_at(id)


static func awake_mutations(u: Unit) -> Array[String]:
	var out: Array[String] = []
	if not is_soldier(u):
		return out
	for id in (u.status.get("mutations", {}) as Dictionary).values():
		if awake(u, id):
			out.append(id)
	return out


static func bond_partner(s: GameState, u: Unit, id: String) -> Unit:
	var b: Dictionary = u.status.get("bond", {})
	if b.get("id", "") != id or not has_mutation(u, id):
		return null
	var p := s.get_unit(int(b.get("partner", -1)))
	return p if p != null and p.is_alive() and is_soldier(p) else null


static func cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Once-per-fight / once-per-key latch: returns true the first time for a given `key` value.
static func _once(u: Unit, key: String, value: Variant = true) -> bool:
	if u.status.get(key) == value:
		return false
	u.status[key] = value
	return true


# ---------------------------------------------------------------- stats

## Re-applies stat deltas that depend on awake mutations and short buffs. Called when a soldier
## spawns, whenever Infection changes tier, at every phase start and after buffs are applied.
static func refresh_stats(s: GameState, u: Unit) -> void:
	var want := {"mobility": 0, "aim": 0}
	if is_soldier(u):
		if awake(u, "hollow_bones"):
			want.mobility += 2
		if awake(u, "chitin_plates"):
			want.mobility -= 1
		if has_perk(u, "symbiote") and Infection.tier(u.infection) >= Infection.Tier.MUTATING:
			want.mobility += 1
			want.aim += 10
		if s != null and u.status.get("k_rally_turn", -1) == s.turn:
			want.mobility += 1
			want.aim += 10
	if s != null and u.status.has("k_pinned") and Combat.has_status(s, u, "k_pinned"):
		want.mobility -= 2
	var old: Dictionary = u.status.get("kit_mods", {})
	for stat in want:
		var delta: int = want[stat] - int(old.get(stat, 0))
		u.set(stat, int(u.get(stat)) + delta)
	if want.values().all(func(v): return v == 0):
		u.status.erase("kit_mods")
	else:
		u.status["kit_mods"] = want


# ---------------------------------------------------------------- phases

static func on_team_phase_start(s: GameState) -> void:
	Zones.on_phase_start(s, Types.Team.ENEMY)
	_bleed_tick(s, Types.Team.PLAYER)
	for u in s.living(Types.Team.PLAYER):
		if not is_soldier(u):
			continue
		if s.turn == 1 and has_passive(u, "willing_host") and u.infection < WILLING_HOST_FLOOR:
			u.infection = WILLING_HOST_FLOOR
			Infection.sync_passives(u)
			s.emit({"type": "infection", "unit": u.id, "value": u.infection, "tier": Infection.tier(u.infection)})
		if u.status.get("k_lose_action") == s.turn:
			u.actions_left = maxi(0, u.actions_left - 1)
		if u.status.get("k_surge_penalty") == s.turn:
			u.actions_left = mini(u.actions_left, 1)
		if has_passive(u, "containment") and not u.ai_controlled:
			for a in s.living(Types.Team.PLAYER):
				if a != u and is_soldier(a) and cheb(a.pos, u.pos) == 1 and a.infection > 0:
					Infection.add(s, a, -medic_cure(a, 5))
		if awake(u, "clotting_blood"):
			_heal(s, u, 1, "clotting_blood")
		if awake(u, "regenerator"):
			_heal(s, u, 3, "regenerator")
			Infection.add(s, u, 2)
		_ride_the_wave_tick(s, u)
	for u in s.units:
		refresh_stats(s, u)


## Start of the enemy phase = the end of the squad's turn.
static func on_enemy_phase_start(s: GameState) -> void:
	Zones.on_phase_start(s, Types.Team.PLAYER)
	_bleed_tick(s, Types.Team.ENEMY)
	for u in s.living(Types.Team.PLAYER):
		if not is_soldier(u):
			continue
		if awake(u, "barbed_hide"):
			for a in s.living(Types.Team.PLAYER):
				if a != u and is_soldier(a) and cheb(a.pos, u.pos) == 1:
					Infection.add(s, a, 2)
		var twin := bond_partner(s, u, "twin_sight")
		if twin != null and u.id < twin.id and u.pos.distance_to(twin.pos) > 6.0:
			u.status["k_lose_action"] = s.turn + 1
			twin.status["k_lose_action"] = s.turn + 1
		if awake(u, "patient_zero") and not u.ai_controlled and s.phase != Types.Phase.ENDED:
			if Infection.roll_lapse(s, u):
				u.actions_left = Types.ACTIONS_PER_TURN
				EnemyAI.take_turn(s, u)
				u.actions_left = 0
	for u in s.units:
		refresh_stats(s, u)


static func _heal(s: GameState, u: Unit, amount: int, why: String) -> void:
	var healed := mini(amount, u.max_hp - u.hp)
	if healed <= 0:
		return
	u.hp += healed
	s.emit({"type": "heal", "unit": u.id, "amount": healed, "hp": u.hp, "source": why})


static func _ride_the_wave_tick(s: GameState, u: Unit) -> void:
	if not u.status.has("k_riding"):
		return
	if u.infection < Infection.MAX:
		u.status.erase("k_riding")
		return
	var left: int = int(u.status.k_riding) - 1
	if left > 0:
		u.status["k_riding"] = left
	else:
		u.status.erase("k_riding")
		Infection.force_turn(s, u)


# ---------------------------------------------------------------- actions

## Extra restrictions on top of each module's own validation. "" = allowed.
static func validate(s: GameState, u: Unit, action: Dictionary) -> String:
	var type: String = action.get("type", "")
	if u.status.get("k_move_only") == s.turn and type != Types.MOVE:
		return "Kick In: only a move is left"
	if u.status.get("k_shoot_only") == s.turn and type != Types.SHOOT:
		return "Run and Gun: only a shot is left"
	if type == Types.HUNKER:
		if awake(u, "chitin_plates"):
			return "Chitin Plates: can't hunker down"
		if u.status.get("k_lure_turn") == s.turn:
			return "Lure Scent: can't hunker down this turn"
	return ""


static func before_action(s: GameState, u: Unit, action: Dictionary) -> void:
	u.status["k_first_action"] = s.phase == Types.Phase.TEAM and u.actions_left >= Types.ACTIONS_PER_TURN
	if is_soldier(u) and (action.get("type") in [Types.SHOOT, Types.ABILITY] or action.has("target") or action.has("cell")):
		u.status["k_attacked"] = true


static func after_action(s: GameState, u: Unit, action: Dictionary) -> void:
	u.status.erase("k_first_action")
	if action.get("type") == Types.MOVE and u.is_alive() and is_soldier(u):
		var moves: int = int(u.status.get("k_moves", 0)) if u.status.get("k_moves_turn") == s.turn else 0
		u.status["k_moves"] = moves + 1
		u.status["k_moves_turn"] = s.turn
		if u.actions_left == 0 and moves + 1 >= 2 and has_perk(u, "run_and_gun") \
				and not Combat.visible_targets(s, u).is_empty() and _once(u, "k_run_and_gun"):
			u.actions_left = 1
			u.status["k_shoot_only"] = s.turn
	if action.get("type") == Types.SHOOT:
		u.status.erase("k_shoot_only")


## Tiles moved this turn (for Steady Aim / Relocate).
static func tiles_moved(s: GameState, u: Unit) -> int:
	return int(u.status.get("k_moved_tiles", 0)) if u.status.get("k_moved_turn") == s.turn else 0


## Called by Rules._do_move for each cell entered (counts tiles for Steady Aim / Relocate).
static func on_step(s: GameState, u: Unit, _c: Vector2i) -> void:
	if is_soldier(u):
		if u.status.get("k_moved_turn") != s.turn:
			u.status["k_moved_turn"] = s.turn
			u.status["k_moved_tiles"] = 0
		u.status["k_moved_tiles"] = int(u.status.k_moved_tiles) + 1


# ---------------------------------------------------------------- odds and damage

## Cover after perks: a Warden's Bulwark covers the ally right behind it (Tower Shield: full
## cover); Expose lowers a Tagged enemy's cover by one step for the squad.
static func cover_against(s: GameState, attacker: Unit, target: Unit, cover: int, from: Vector2i = attacker.pos) -> int:
	cover = maxi(cover, bulwark_cover(s, target, from))
	if cover == Types.Cover.NONE or attacker.team != Types.Team.PLAYER or not Combat.has_status(s, target, "tagged"):
		return cover
	for u in s.living(Types.Team.PLAYER):
		if has_perk(u, "expose"):
			return cover - 1
	return cover


## Cover a soldier at `target` gets from an adjacent Warden standing between it and `from`
## (one step toward the attacker on x or y, like a cover tile).
static func bulwark_cover(s: GameState, target: Unit, from: Vector2i) -> int:
	if not is_soldier(target):
		return Types.Cover.NONE
	var best: int = Types.Cover.NONE
	for d in [Vector2i(signi(from.x - target.pos.x), 0), Vector2i(0, signi(from.y - target.pos.y))]:
		if d == Vector2i.ZERO:
			continue
		var w := s.unit_at(target.pos + d)
		if w != null and w != target and w.is_alive() and has_passive(w, "bulwark") and not w.ai_controlled:
			best = maxi(best, Types.Cover.FULL if has_perk(w, "tower_shield") else Types.Cover.HALF)
	return best


## Adds perk/passive/mutation terms to a hit-chance breakdown. Returns extra crit chance.
static func modify_odds(s: GameState, attacker: Unit, target: Unit, from: Vector2i, reaction: bool, breakdown: Array) -> int:
	var crit := 0
	# Defender side.
	if is_soldier(target):
		var shoulder := 0
		for a in s.living(Types.Team.PLAYER):
			if a != target and has_passive(a, "shoulder_to_shoulder") and cheb(a.pos, target.pos) == 1:
				shoulder = maxi(shoulder, STEADFAST_DEFENSE if has_perk(a, "steadfast") else SHOULDER_DEFENSE)
		if shoulder > 0:
			breakdown.append(["Shoulder to Shoulder", -shoulder])
		if has_perk(target, "hold_the_line") and Combat.is_hunkered(s, target):
			breakdown.append(["Hold the Line", -HOLD_LINE_HUNKER])
		if target.status.has("k_triage") and Combat.has_status(s, target, "k_triage"):
			breakdown.append(["Triage Cover", -TRIAGE_DEFENSE])
		if has_perk(target, "juggernaut") and target.status.get("k_flanked_turn") == s.turn:
			breakdown.append(["Juggernaut", -JUGGERNAUT_DEFENSE])
		if reaction and has_passive(target, "bloodlust"):
			breakdown.append(["Low profile", -LOW_PROFILE])
		if reaction and has_passive(target, "bulwark"):
			breakdown.append(["Shield up", -SHIELD_UP])
	# Attacker side.
	if is_soldier(attacker):
		if has_passive(attacker, "steady_aim"):
			var moved := tiles_moved(s, attacker) if from == attacker.pos else 99
			if moved == 0 or (has_perk(attacker, "relocate") and moved <= 2):
				breakdown.append(["Steady Aim", STEADY_AIM])
		if reaction and has_perk(attacker, "long_watch"):
			breakdown.append(["Long Watch", Combat.REACTION_PENALTY])
		if reaction:
			for a in s.living(Types.Team.PLAYER):
				if a != attacker and a.status.get("k_lure_until", -1) > Combat.phase_index(s) and a.pos.distance_to(target.pos) <= LURE_RADIUS:
					breakdown.append(["Lure Scent", LURE_AIM])
					break
		if has_perk(attacker, "deadeye") and Combat.has_status(s, target, "tagged"):
			crit += DEADEYE_CRIT
	return crit


## Damage of a shot that connected, before Rules.deal_damage.
static func shot_damage(_s: GameState, u: Unit, t: Unit, dmg: int) -> int:
	if dmg > 0 and has_passive(u, "point_blank") and u.pos.distance_to(t.pos) <= Combat.CLOSE_RANGE:
		dmg += 1
	return dmg


## Called by Combat.fire after the shot resolved.
static func after_shot(s: GameState, u: Unit, t: Unit, odds: Dictionary, hit: bool) -> void:
	if is_soldier(u) and odds.get("flanked", false) and u.is_enemy_of(t):
		u.status["k_flanked_turn"] = s.turn
	if hit and t.is_alive() and has_perk(t, "return_fire") and s.phase == Types.Phase.ENEMY and u.is_alive() \
			and t.is_enemy_of(u) and not t.ai_controlled and Combat.can_see(s, t.pos, u.pos) \
			and _once(t, "k_return_fire", Combat.phase_index(s)):
		Combat.fire(s, t, u, false)


## Every damage instance passes through here first (Rules.deal_damage). Returns the final amount.
static func modify_incoming(s: GameState, target: Unit, amount: int, source: Unit) -> int:
	if amount <= 0:
		return amount
	if source != null and target.status.get("k_flies", false):
		amount += 1
	if awake(target, "hollow_bones"):
		amount += 1
	if awake(target, "chitin_plates"):
		amount = maxi(1, amount - CHITIN_ARMOR)
	if source != null and has_perk(target, "unbreakable") and cheb(source.pos, target.pos) == 1:
		amount = maxi(1, amount - 1)
	var partner := bond_partner(s, target, "shared_blood")
	if partner != null and amount >= 2 and not target.status.get("k_splitting", false):
		var half := amount / 2
		amount -= half
		partner.status["k_splitting"] = true
		Rules.deal_damage(s, partner, half, null)
		partner.status.erase("k_splitting")
	if amount >= target.hp and is_soldier(target):
		if has_perk(target, "last_stand") and _once(target, "k_last_stand"):
			s.emit({"type": "perk", "unit": target.id, "perk": "last_stand"})
			return target.hp - 1
		if has_perk(target, "last_wall") and _once(target, "k_last_wall"):
			s.emit({"type": "perk", "unit": target.id, "perk": "last_wall"})
			return target.hp - 1
		if awake(target, "second_heart") and _once(target, "k_second_heart"):
			target.status["k_second_heart_pending"] = true
			s.emit({"type": "mutation", "unit": target.id, "mutation": "second_heart"})
			return target.hp - 1
	return amount


static func after_damage(s: GameState, target: Unit, amount: int, source: Unit) -> void:
	if amount > 0 and source != null and is_soldier(target) and source.is_enemy_of(target):
		target.status["hits_taken"] = int(target.status.get("hits_taken", 0)) + 1   # Warden unlock
	if target.status.get("k_second_heart_pending", false):
		target.status.erase("k_second_heart_pending")
		Infection.add(s, target, 15)
	if amount > 0 and source != null and target.is_alive() and awake(target, "bloom") and source.is_enemy_of(target):
		var near: Array[Unit] = []
		for o in s.living():
			if o != target and cheb(o.pos, target.pos) == 1:
				near.append(o)
		s.emit({"type": "mutation", "unit": target.id, "mutation": "bloom", "units": near.map(func(x: Unit) -> int: return x.id)})
		for o in near:
			if o.is_enemy_of(target):
				Rules.deal_damage(s, o, 2, target)
			elif is_soldier(o):
				Infection.add(s, o, 5)


## Combat's claw resolved against `target` (hit or not). Riposte: a Reaper strikes back once
## per enemy phase.
static func after_claw(s: GameState, attacker: Unit, target: Unit) -> void:
	if has_perk(target, "riposte") and target.is_alive() and attacker.is_alive() and not target.ai_controlled \
			and target.is_enemy_of(attacker) and cheb(attacker.pos, target.pos) == 1 \
			and s.phase == Types.Phase.ENEMY and _once(target, "k_riposte", Combat.phase_index(s)):
		ClassAbilities.strike(s, target, attacker, "riposte")


## Bleed Out: a bleeding unit of `team` takes 1 damage at the start of its side's phase.
static func _bleed_tick(s: GameState, team: int) -> void:
	for u in s.living(team):
		var left := int(u.status.get("k_bleed", 0))
		if left <= 0:
			continue
		if left > 1:
			u.status["k_bleed"] = left - 1
		else:
			u.status.erase("k_bleed")
		s.emit({"type": "bleed", "unit": u.id, "damage": 1})
		Rules.deal_damage(s, u, 1, s.get_unit(int(u.status.get("k_bleed_by", -1))))
		if s.phase == Types.Phase.ENDED:
			return


## A melee hit landed on `target` (claw). Brawler and Barbed Hide bite back.
static func after_melee(s: GameState, attacker: Unit, target: Unit, dmg: int) -> void:
	if dmg <= 0 or not attacker.is_alive():
		return
	var back := 0
	if has_perk(target, "brawler"):
		back += 2
	if awake(target, "barbed_hide"):
		back += 2
	if back > 0:
		Rules.deal_damage(s, attacker, back, target)


static func on_death(s: GameState, dead: Unit, source: Unit) -> void:
	if dead.status.get("k_flies", false):
		var best: Unit = null
		for u in s.living(Types.Team.PLAYER):
			if is_soldier(u) and (best == null or u.pos.distance_to(dead.pos) < best.pos.distance_to(dead.pos)):
				best = u
		if best != null:
			Infection.add(s, best, 5)
	if awake(dead, "martyr_strain"):
		martyr(s, dead)
	if source == null or not source.is_alive() or not dead.is_enemy_of(source):
		return
	if is_soldier(source) and cheb(source.pos, dead.pos) == 1:
		source.status["close_kills"] = int(source.status.get("close_kills", 0)) + 1   # Reaper unlock
	if has_perk(source, "feed"):
		_heal(s, source, 2, "feed")
	if has_perk(source, "double_tap") and source.status.get("k_first_action", false) and _once(source, "k_double_tap", s.turn):
		source.actions_left += 1
		source.status.erase("k_shoot_only")
		s.emit({"type": "perk", "unit": source.id, "perk": "double_tap"})


## Infection._turn calls this after a soldier Turns.
static func on_turned(s: GameState, u: Unit) -> void:
	if has_mutation(u, "martyr_strain") and Infection.tier(u.infection) >= MutationData.awake_at("martyr_strain"):
		martyr(s, u)


static func martyr(s: GameState, u: Unit) -> void:
	if not _once(u, "k_martyred"):
		return
	s.emit({"type": "mutation", "unit": u.id, "mutation": "martyr_strain"})
	for a in s.living(Types.Team.PLAYER):
		if a != u and is_soldier(a):
			Infection.add(s, a, -20)


# ---------------------------------------------------------------- abilities

static func ability_range(u: Unit, id: String, base: int) -> int:
	match id:
		"stim":
			return 3 if has_perk(u, "long_reach") else base
		"breach":
			return 3 if has_perk(u, "long_fuse") else base
	return base


## Action cost (-1 = ends turn) after perks.
static func ability_cost(u: Unit, id: String, cost: int) -> int:
	if id == "suppress" and has_perk(u, "lockdown"):
		return 1
	return cost


static func ability_cooldown(u: Unit, id: String, cd: int) -> int:
	match id:
		"stim":
			return 1 if has_perk(u, "field_kit") else cd
		"tag":
			return 1 if has_perk(u, "hunters_mark") else cd
		"incinerate":
			return 1 if has_perk(u, "backdraft") else cd
	return cd


## HP a Medic heal restores on `t` (Clotting Blood halves, Regenerator blocks).
static func medic_heal(t: Unit, amount: int) -> int:
	if awake(t, "regenerator"):
		return 0
	if awake(t, "clotting_blood"):
		return amount / 2
	return amount


## Infection a Medic purge removes from `t` (Hive Hush halves).
static func medic_cure(t: Unit, amount: int) -> int:
	return amount / 2 if awake(t, "hive_hush") else amount


static func after_stim(s: GameState, u: Unit, t: Unit, removed: int) -> void:
	if has_perk(u, "transfusion") and removed >= 5:
		_heal(s, t, removed / 5, "transfusion")
	if has_perk(u, "triage_cover"):
		t.status["k_triage"] = Combat.phase_index(s) + (2 if s.phase == Types.Phase.TEAM else 1)
	if has_perk(u, "overdrive"):
		t.actions_left += 1
		Infection.add(s, t, 10)


## Called at the end of Combat._apply_ability for the built abilities.
static func after_ability(s: GameState, u: Unit, id: String, t: Unit) -> void:
	match id:
		"suppress":
			if has_perk(u, "pinned_down") and t != null:
				t.status["k_pinned"] = t.status.get("suppressed", 0)
				refresh_stats(s, t)
		"tag":
			if has_perk(u, "hunters_mark") and t != null and t.status.has("tagged"):
				t.status["tagged"] = int(t.status.tagged) + 2
		"breach":
			if t != null and has_perk(u, "frag_charge"):
				for o in s.living():
					if o != t and o != u and cheb(o.pos, t.pos) == 1:
						Rules.deal_damage(s, o, 2, u)
			if t != null and t.is_alive() and has_perk(u, "shrapnel"):
				t.status["suppressed"] = Combat.phase_index(s) + 2
				t.overwatch = false
			if has_perk(u, "kick_in") and u.is_alive():
				u.actions_left = 1
				u.status["k_move_only"] = s.turn


# ---------------------------------------------------------------- overwatch

## Whether watcher `w` may react to `mover` (Kill Zone never shoots the same mover twice).
static func can_react(w: Unit, mover: Unit) -> bool:
	return w.status.get("k_kz_last", -1) != mover.id


## Twin Sight: `w`'s overwatch also triggers on cells its partner can see.
static func shared_sight(s: GameState, w: Unit, cell: Vector2i) -> bool:
	var p := bond_partner(s, w, "twin_sight")
	return p != null and Vision.unit_sees_cell(s, p, cell)


## Called before a reaction shot clears overwatch. True keeps it up (Kill Zone's second shot).
static func keep_overwatch(s: GameState, w: Unit, mover: Unit) -> bool:
	if not has_perk(w, "kill_zone"):
		return false
	w.status["k_kz_last"] = mover.id
	return _once(w, "k_kill_zone", int(w.status.get("ow_until", Combat.phase_index(s))))


# ---------------------------------------------------------------- infection

## Adjusts an Infection change before it lands (Infection.add). May redirect it (Host Body).
static func infection_change(s: GameState, u: Unit, amount: int) -> int:
	if amount <= 0 or not is_soldier(u) or s.turn == 0:
		return amount   # before turn 1 the run is just restoring carried Infection
	if u.status.has("k_decon") and Combat.has_status(s, u, "k_decon"):
		return 0
	for v in s.living(Types.Team.PLAYER):
		if v != u and awake(v, "host_body") and not v.ai_controlled and cheb(v.pos, u.pos) <= 2 \
				and _once(v, "k_host_body", s.turn):
			s.emit({"type": "mutation", "unit": v.id, "mutation": "host_body", "target": u.id})
			Infection.add(s, v, amount)
			return 0
	if has_passive(u, "sealed_suit"):
		amount = maxi(1, amount / 2)
	if u.status.get("inoculated", false):
		amount = maxi(1, amount / 2)
	return amount


## Called when a soldier would Turn. Returns true if something stopped it.
static func prevent_turn(s: GameState, u: Unit) -> bool:
	if u.status.has("k_riding"):
		return true
	if has_perk(u, "brink") and _once(u, "k_brink"):
		u.infection = Infection.CRITICAL_AT - 1
		s.emit({"type": "perk", "unit": u.id, "perk": "brink"})
		s.emit({"type": "infection", "unit": u.id, "value": u.infection, "tier": Infection.tier(u.infection)})
		Rules.deal_damage(s, u, 3, null)
		return true
	if awake(u, "ride_the_wave") and _once(u, "k_rode"):
		u.status["k_riding"] = 2
		s.emit({"type": "mutation", "unit": u.id, "mutation": "ride_the_wave"})
		return true
	return false


static func lapse_chance(u: Unit, chance: float) -> float:
	if has_perk(u, "iron_will"):
		chance *= 0.5
	if u.status.get("k_hollow_voice", false):
		chance *= 2.0
	return minf(chance, 1.0)


static func on_lapse(s: GameState, u: Unit) -> void:
	var p := bond_partner(s, u, "shared_blood")
	if p != null and not Infection.is_lapsed(p) and not u.status.get("k_chain_lapse", false):
		p.status["k_chain_lapse"] = true
		Infection.roll_lapse(s, p)
		p.status.erase("k_chain_lapse")
	var linked := s.get_unit(int(u.status.get("k_hive_link_to", -1)))
	if linked != null and linked.is_alive():
		linked.actions_left = maxi(0, linked.actions_left - 1)


## Can `lapsed` be talked down at all (Martyr Strain says no).
static func can_talk_down(lapsed: Unit) -> bool:
	return not awake(lapsed, "martyr_strain")


# ---------------------------------------------------------------- enemy AI

## Hollow Voice: a seized Infected sits out its next turn (consumes the flag).
static func skips_turn(u: Unit) -> bool:
	if not u.status.get("k_skip_turn", false):
		return false
	u.status.erase("k_skip_turn")
	return true


## False if `watcher` (a dormant Infected) cannot spot `h` at this distance (Hive Hush).
static func can_be_spotted(_s: GameState, watcher: Unit, h: Unit) -> bool:
	return not (awake(h, "hive_hush") and watcher.pos.distance_to(h.pos) > 4.0 and not h.status.get("k_attacked", false))


## Extra AI target score: Lure Scent makes the lured soldier the Infected's favourite.
static func target_bias(s: GameState, _u: Unit, t: Unit) -> float:
	return 20.0 if t.status.get("k_lure_until", -1) > Combat.phase_index(s) else 0.0
