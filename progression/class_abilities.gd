class_name ClassAbilities
extends RefCounted
## Abilities added by the progression workstream: Hazmat Incinerate, Vector Siphon, the melee
## classes' strikes (Reaper Lunge, Warden Shield Bash and Guard), perk abilities
## (Purge, Decon Shower, Squad Leader's order), and two any-soldier actions: talking down a Lapsed
## ally and a mid-fight Serum cure. Combat delegates ids it doesn't know to this class, so these
## go through Types.ABILITY actions and Rules.apply like the built abilities. OWNER: progression.

## Same shape as Combat.ABILITIES. "cost": actions, -1 = ends turn. "any": usable by every soldier.
const ABILITIES := {
	"incinerate": {"name": "Incinerate", "targeting": "cell", "cost": -1, "cooldown": 2,
		"desc": "3-tile cone: 3 damage to every unit in it (allies too), ignoring cover. Leaves fire for 1 turn. Ends turn."},
	"siphon": {"name": "Siphon", "targeting": "unit", "cost": 1, "cooldown": 1,
		"desc": "Move up to 15 Infection from an adjacent ally onto yourself and heal 1 HP per 5 moved. 1 action."},
	"purge": {"name": "Purge", "targeting": "unit", "cost": -1, "cooldown": 3,
		"desc": "Remove 30 Infection from an adjacent ally. Ends turn."},
	"decon": {"name": "Decon Shower", "targeting": "unit", "cost": 1, "cooldown": 2,
		"desc": "An adjacent ally loses 10 Infection and gains none until the next team phase. 1 action."},
	"squad_order": {"name": "Squad Leader", "targeting": "unit", "cost": 1, "cooldown": 0,
		"desc": "Once per fight: an adjacent ally gains +1 action this turn. 1 action."},
	"lunge": {"name": "Lunge", "targeting": "unit", "cost": -1, "cooldown": 0,
		"desc": "Dash up to 4 tiles to a visible enemy and cut it for 4-6, +1 per Infection tier. Only half cover counts. Kills on Infected add 5 Infection. Ends turn."},
	"bash": {"name": "Shield Bash", "targeting": "unit", "cost": 1, "cooldown": 1,
		"desc": "Hit an adjacent enemy for 3-5, knock it back a tile and stun it (it loses its next turn). +2 damage on Turned soldiers. 1 action."},
	"guard": {"name": "Guard", "targeting": "none", "cost": -1, "cooldown": 0,
		"desc": "Until your next turn, Bash the first enemy that steps next to you, which stops it in its tracks. Ends turn."},
	"shield_charge": {"name": "Shield Charge", "targeting": "unit", "cost": -1, "cooldown": 3,
		"desc": "Move up to 3 tiles to a visible enemy and Bash it. Ends turn."},
	"talk_down": {"name": "Talk Down", "targeting": "unit", "cost": 1, "cooldown": 0, "any": true,
		"desc": "Talk an adjacent Lapsed ally back to their senses. 1 action."},
	"serum": {"name": "Serum", "targeting": "unit", "cost": 2, "cooldown": 0, "any": true,
		"desc": "Full cure for an adjacent ally: Infection to 0, every mutation wiped, ends a Lapse. 2 actions, uses a Serum."},
}

const INCINERATE_DAMAGE := 3
const SIPHON_AMOUNT := 15
const DEEP_SIPHON_AMOUNT := 25
const PURGE_AMOUNT := 30
const DECON_AMOUNT := 10
const CALM_VOICE_CURE := 10
## Melee: strikes roll the soldier's aim plus MELEE_AIM; only half cover counts (Combat.melee_chance).
const MELEE_AIM := 15
const LUNGE_REACH := 4
const LONG_STRIDE_REACH := 6
const CHARGE_REACH := 3
const BLADE_DAMAGE := Vector2i(4, 6)
const MAUL_DAMAGE := Vector2i(3, 5)
const QUARANTINE_DAMAGE := 2
const FEED_INFECTION := 5
const HARVEST_HEAL := 2
const BLEED_TURNS := 2
const STERILIZE_CURE := 5
const NO_CELL := Vector2i(-1, -1)


static func handles(id: String) -> bool:
	return ABILITIES.has(id)


static func _owns(u: Unit, id: String) -> bool:
	return ABILITIES[id].get("any", false) or u.abilities.has(id)


## Same shape as Combat.available_abilities entries. Any-soldier actions only show when usable.
static func available(s: GameState, u: Unit) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not Kit.is_soldier(u):
		return out
	for id in ABILITIES:
		if not _owns(u, id):
			continue
		var def: Dictionary = ABILITIES[id]
		var targets := targets_for(s, u, id)
		if def.get("any", false) and (targets.is_empty() or (id == "serum" and int(u.status.get("serum", 0)) <= 0)):
			continue
		var cd: int = int(u.cooldowns.get(id, 0))
		var has_targets: bool = def.targeting != "unit" or not targets.is_empty()
		out.append({"id": id, "name": def.name, "targeting": def.targeting, "cost": def.cost,
			"cooldown": cd, "desc": def.desc, "targets": targets,
			"ready": cd <= 0 and u.actions_left >= maxi(1, def.cost) and u.is_alive() and has_targets and _extra_error(u, id) == ""})
	return out


static func targets_for(s: GameState, u: Unit, id: String) -> Array[int]:
	var out: Array[int] = []
	if ABILITIES[id].targeting != "unit":
		return out
	for t in s.units:
		if target_error(s, u, id, t) == "":
			out.append(t.id)
	return out


static func _extra_error(u: Unit, id: String) -> String:
	if id == "squad_order" and u.status.get("k_squad_order", false):
		return "Already used this fight"
	if id == "serum" and int(u.status.get("serum", 0)) <= 0:
		return "No Serum"
	return ""


static func target_error(s: GameState, u: Unit, id: String, t: Unit) -> String:
	if t == null or not t.is_alive():
		return "No such target"
	if id in ["lunge", "bash", "shield_charge"]:
		return _strike_target_error(s, u, id, t)
	if t == u or not Kit.is_soldier(t):
		return "Not an ally"
	var dist := Kit.cheb(u.pos, t.pos)
	match id:
		"siphon":
			if dist > (3 if Kit.has_perk(u, "deep_siphon") else 1):
				return "Too far"
			if t.infection <= 0:
				return "No Infection to siphon"
		"purge", "decon":
			if dist > 1:
				return "Too far"
			if id == "purge" and t.infection <= 0:
				return "No Infection to purge"
		"squad_order":
			if dist > 1:
				return "Too far"
		"talk_down":
			if not Infection.is_lapsed(t):
				return "Not Lapsed"
			if dist > (3 if Kit.has_perk(u, "calm_voice") else 1):
				return "Too far"
			if not Kit.can_talk_down(t):
				return "Martyr Strain: can't be talked down"
		"serum":
			if dist > 1:
				return "Too far"
	return ""


static func validate(s: GameState, u: Unit, action: Dictionary) -> String:
	var id: String = action.get("ability", "")
	# A Turned Reaper or Warden keeps its melee strikes (EnemyAI uses them); nothing else.
	var turned_strike: bool = u.status.get("turned", false) and id in ["lunge", "bash", "shield_charge"]
	if not _owns(u, id) or not (Kit.is_soldier(u) or turned_strike):
		return "Unknown ability"
	var def: Dictionary = ABILITIES[id]
	if int(u.cooldowns.get(id, 0)) > 0:
		return "On cooldown"
	if u.actions_left < maxi(1, def.cost):
		return "Not enough actions"
	var extra := _extra_error(u, id)
	if extra != "":
		return extra
	if def.targeting == "none":
		return ""
	if def.targeting == "cell":
		var cell: Variant = action.get("cell")
		if not cell is Vector2i or not s.grid.in_bounds(cell) or cell == u.pos:
			return "No target cell"
		if incinerate_cells(s, u, cell).is_empty():
			return "Nothing to burn there"
		return ""
	if not action.has("target"):
		return "No target"
	return target_error(s, u, id, s.get_unit(action.target))


## Cells Incinerate hits when aimed at `cell`: a cone (3 tiles, Wide Nozzle 4) within 45 degrees
## of the aim line, or a 4-tile line with Firewall. Walls and cells out of sight are skipped.
static func incinerate_cells(s: GameState, u: Unit, cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var aim := Vector2(cell - u.pos)
	if aim.length() == 0.0:
		return out
	aim = aim.normalized()
	if Kit.has_perk(u, "firewall"):
		for i in range(1, 5):
			var c := u.pos + Vector2i(roundi(aim.x * i), roundi(aim.y * i))
			if not s.grid.in_bounds(c) or s.grid.blocks_los(c) or not Combat.line_clear(s.grid, u.pos, c):
				break
			if not out.has(c):
				out.append(c)
		return out
	var reach := 4 if Kit.has_perk(u, "wide_nozzle") else 3
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var v := Vector2(dx, dy)
			var dist := v.length()
			if dist == 0.0 or dist > reach + 0.5 or v.dot(aim) / dist < 0.7:
				continue
			var c := u.pos + Vector2i(dx, dy)
			if s.grid.in_bounds(c) and not s.grid.blocks_los(c) and Combat.line_clear(s.grid, u.pos, c):
				out.append(c)
	return out


static func apply(s: GameState, u: Unit, action: Dictionary) -> void:
	var id: String = action.ability
	var def: Dictionary = ABILITIES[id]
	var cost: int = def.cost
	u.actions_left = 0 if cost < 0 else maxi(0, u.actions_left - cost)
	var cd := Kit.ability_cooldown(u, id, int(def.cooldown))
	if cd > 0:
		u.cooldowns[id] = cd
	if id == "incinerate":
		_incinerate(s, u, action.cell)
		return
	if id == "guard":
		u.status["k_guard_until"] = Combat.phase_index(s) + 2
		u.status["k_guard_left"] = 2 if Kit.has_perk(u, "vigilant") else 1
		s.emit({"type": "guard", "unit": u.id})
		return
	if id in ["lunge", "bash", "shield_charge"]:
		_melee_ability(s, u, id, s.get_unit(action.target))
		return
	var t := s.get_unit(action.target)
	var ev := {"type": "ability", "unit": u.id, "ability": id, "target": t.id}
	match id:
		"siphon":
			var moved := mini(DEEP_SIPHON_AMOUNT if Kit.has_perk(u, "deep_siphon") else SIPHON_AMOUNT, t.infection)
			var healed := mini(moved / 5, u.max_hp - u.hp)
			u.hp += healed
			ev.merge({"moved": moved, "heal": healed, "hp": u.hp})
			s.emit(ev)
			Infection.add(s, t, -moved)
			Infection.add(s, u, moved)
		"purge":
			var amount := Kit.medic_cure(t, PURGE_AMOUNT)
			ev["amount"] = amount
			s.emit(ev)
			Infection.add(s, t, -amount)
		"decon":
			t.status["k_decon"] = Combat.phase_index(s) + (2 if s.phase == Types.Phase.TEAM else 1)
			s.emit(ev)
			Infection.add(s, t, -DECON_AMOUNT)
		"squad_order":
			u.status["k_squad_order"] = true
			t.actions_left += 1
			s.emit(ev)
		"talk_down":
			s.emit(ev)
			Infection.end_lapse(s, t)
			if Kit.has_perk(u, "calm_voice"):
				Infection.add(s, t, -CALM_VOICE_CURE)
		"serum":
			u.status["serum"] = int(u.status.get("serum", 0)) - 1
			s.emit(ev)
			cure(s, t)


## Serum: Infection to 0, every mutation wiped, Lapse ended, Inoculated for the rest of the fight.
## Progression.after_fight sees status "cured" and keeps the soldier Inoculated for 2 fights.
static func cure(s: GameState, t: Unit) -> void:
	if Infection.is_lapsed(t):
		Infection.end_lapse(s, t)
	t.status["mutations"] = {}
	t.status.erase("bond")
	t.status.erase("k_riding")
	t.status["cured"] = true
	t.status["inoculated"] = true
	Infection.add(s, t, -t.infection)
	Kit.refresh_stats(s, t)


static func _incinerate(s: GameState, u: Unit, cell: Vector2i) -> void:
	var cells := incinerate_cells(s, u, cell)
	var clean := Kit.has_perk(u, "clean_burn")
	var hit: Array[Unit] = []
	for c in cells:
		var t := s.unit_at(c)
		if t != null and t != u and (not clean or u.is_enemy_of(t)):
			hit.append(t)
	s.emit({"type": "ability", "unit": u.id, "ability": "incinerate", "cell": cell, "cells": cells.duplicate(),
		"units": hit.map(func(x: Unit) -> int: return x.id), "damage": INCINERATE_DAMAGE})
	for t in hit:
		Rules.deal_damage(s, t, INCINERATE_DAMAGE, u)
	# Fire burns spores away (Hazards' "replaces" rule).
	Hazards.add(s, cells, "fire", 2 if Kit.has_perk(u, "napalm") else 1, u.id, u.team if clean else -1)


# ---------------------------------------------------------------- melee classes

static func _strike_target_error(s: GameState, u: Unit, id: String, t: Unit) -> String:
	if not u.is_enemy_of(t):
		return "Not an enemy"
	if id == "bash":
		return "" if s.grid.melee_reach(u.pos, t.pos) else "Not adjacent"
	if not Combat.visible_targets(s, u).has(t):
		return "No line of sight"
	if lunge_landing(s, u, t, strike_reach(u, id)) == NO_CELL:
		return "Can't reach"
	return ""


## Path tiles a Lunge / Shield Charge may cover.
static func strike_reach(u: Unit, id: String) -> int:
	if id == "shield_charge":
		return CHARGE_REACH
	return LONG_STRIDE_REACH if Kit.has_perk(u, "long_stride") else LUNGE_REACH


## Where `u` ends up to strike `t` with a dash of up to `reach` tiles: its own cell when already
## adjacent, else the closest free cell next to `t` (ties: the one where `t` has no cover).
## NO_CELL if there is none. Pure (the view previews it).
static func lunge_landing(s: GameState, u: Unit, t: Unit, reach: int) -> Vector2i:
	if s.grid.melee_reach(u.pos, t.pos):
		return u.pos
	var dist := s.grid.reachable(u.pos, reach, s.occupied(u.id))
	var best := NO_CELL
	var best_score := INF
	for d in Grid.DIRS8:
		var c: Vector2i = t.pos + d
		if c == u.pos or not dist.has(c) or s.unit_at(c) != null or not s.grid.melee_reach(c, t.pos):
			continue
		var score := float(dist[c])
		if Combat.cover_against(s.grid, t.pos, c) != Types.Cover.NONE:
			score += 0.5
		if score < best_score:
			best_score = score
			best = c
	return best


## Melee odds for a strike from `from`: Combat.melee_chance plus the class's MELEE_AIM. Red Mist
## makes a Critical Reaper's strikes certain.
static func strike_odds(s: GameState, u: Unit, t: Unit, from: Vector2i = u.pos) -> Dictionary:
	var odds := Combat.melee_chance(s, u, t, from)
	odds.breakdown.append(["Melee weapon", MELEE_AIM])
	odds.hit = clampi(odds.hit + MELEE_AIM, Combat.MIN_CHANCE, 100)
	if Kit.has_perk(u, "red_mist") and Infection.tier(u.infection) >= Infection.Tier.CRITICAL:
		odds.breakdown.append(["Red Mist", 100 - odds.hit])
		odds.hit = 100
	odds.graze = mini(Combat.GRAZE_BAND, 100 - odds.hit)
	return odds


static func _melee_ability(s: GameState, u: Unit, id: String, t: Unit) -> void:
	if id != "bash":
		var landing := lunge_landing(s, u, t, strike_reach(u, id))
		if landing != u.pos:
			Rules.move_along(s, u, landing)
		if not u.is_alive() or not t.is_alive() or not s.grid.melee_reach(u.pos, t.pos) or s.phase == Types.Phase.ENDED:
			return   # overwatch (or a Guard) stopped the dash
	if id == "lunge":
		var others: Array[Unit] = []
		if Kit.has_perk(u, "cleave"):
			for o in s.living():
				if o != t and u.is_enemy_of(o) and s.grid.melee_reach(u.pos, o.pos):
					others.append(o)
		strike(s, u, t, "lunge")
		for o in others:
			if u.is_alive() and o.is_alive():
				strike(s, u, o, "lunge", {"cleave": true})
	else:
		strike(s, u, t, "bash", {"charge": true} if id == "shield_charge" else {})


## One melee strike from a Reaper ("lunge", "riposte") or Warden ("bash"): rolls, emits the
## ability event, deals damage and runs the on-hit / on-kill effects. Spends no actions.
## Returns the damage dealt.
static func strike(s: GameState, u: Unit, t: Unit, kind: String, extra: Dictionary = {}) -> int:
	var odds := strike_odds(s, u, t)
	var r := Combat.resolve_roll(s.rng.randi_range(1, 100), odds)
	u.status.erase("suppressed")
	var bash := kind == "bash"
	var dmg := 0
	if r.hit or r.graze:
		var roll_range := MAUL_DAMAGE if bash else BLADE_DAMAGE
		var base := s.rng.randi_range(roll_range.x, roll_range.y)
		if bash and t.status.get("turned", false):
			base += QUARANTINE_DAMAGE
		elif not bash:
			base += Infection.tier(u.infection) if Infection.tier(u.infection) < Infection.Tier.TURNED else 0
		dmg = Combat.final_damage(base, r.graze, false)
	var ev := {"type": "ability", "unit": u.id, "ability": kind, "target": t.id,
		"hit": r.hit or r.graze, "graze": r.graze, "damage": dmg, "chance": odds.hit}
	ev.merge(extra)
	s.emit(ev)
	if dmg <= 0:
		return 0
	Rules.deal_damage(s, t, dmg, u)
	Kit.after_melee(s, u, t, dmg)
	if bash:
		_after_bash(s, u, t)
	elif t.is_alive():
		if Kit.has_perk(u, "bleed_out"):
			t.status["k_bleed"] = BLEED_TURNS
			t.status["k_bleed_by"] = u.id
			s.emit({"type": "bleeding", "unit": t.id, "turns": BLEED_TURNS})
		if Kit.has_perk(u, "hamstring"):
			t.status["k_pinned"] = Combat.phase_index(s) + (2 if s.phase == Types.Phase.TEAM else 3)
			Kit.refresh_stats(s, t)
	else:
		_after_melee_kill(s, u, t)
	return dmg


## Reaper kills: Bloodlust (an action back, team phase, once per turn), Feeds on It, Harvest.
static func _after_melee_kill(s: GameState, u: Unit, t: Unit) -> void:
	if not u.is_alive():
		return
	if Kit.has_passive(u, "bloodlust") and s.phase == Types.Phase.TEAM and Kit._once(u, "k_bloodlust", s.turn):
		u.actions_left += 1
		s.emit({"type": "perk", "unit": u.id, "perk": "bloodlust"})
	if u.kind == "reaper" and EnemyRoster.infects(t):
		Infection.add(s, u, FEED_INFECTION)
	if Kit.has_perk(u, "harvest"):
		Kit._heal(s, u, HARVEST_HEAL, "harvest")


## A Bash landed: knock back and stun (bosses and rooted things stand firm), then perks.
static func _after_bash(s: GameState, u: Unit, t: Unit) -> void:
	if Kit.has_perk(u, "sterilize") and u.infection > 0:
		Infection.add(s, u, -STERILIZE_CURE)
	if not t.is_alive():
		return
	if Kit.has_perk(u, "intimidate"):
		for o in s.living():
			if o != t and u.is_enemy_of(o) and Kit.cheb(o.pos, t.pos) == 1:
				o.status["suppressed"] = Combat.phase_index(s) + 2
				o.overwatch = false
				s.emit({"type": "ability", "unit": u.id, "ability": "suppress", "target": o.id, "source": "intimidate"})
	if EnemyRoster.is_boss(t) or UnitData.ENEMIES.get(t.kind, {}).get("static", false):
		return
	EnemyAbilities.knockback(s, t, Vector2i(signi(t.pos.x - u.pos.x), signi(t.pos.y - u.pos.y)), 1)
	if t.is_alive():
		# In the enemy phase (a Guard bash) the stun ends the turn it interrupted.
		if s.phase == Types.Phase.TEAM:
			t.status["k_skip_turn"] = true
		t.actions_left = 0
		s.emit({"type": "stunned", "unit": t.id, "by": u.id})


static func is_guarding(s: GameState, w: Unit) -> bool:
	return w.is_alive() and int(w.status.get("k_guard_left", 0)) > 0 \
		and Combat.phase_index(s) < int(w.status.get("k_guard_until", -1))


## Guarding Wardens hostile to `mover` that it just stepped next to at `cell`. Pure.
static func guards_against(s: GameState, mover: Unit, cell: Vector2i) -> Array[Unit]:
	var out: Array[Unit] = []
	for w in s.units:
		if w != mover and w.is_enemy_of(mover) and is_guarding(s, w) and s.grid.melee_reach(w.pos, cell):
			out.append(w)
	return out


## Rules.move_along calls this after overwatch at each step. A Guard bash that lands ends the
## mover's movement and turn. Returns true if the mover must stop.
static func resolve_guards(s: GameState, mover: Unit, guards: Array[Unit]) -> bool:
	for w in guards:
		if not mover.is_alive() or s.phase == Types.Phase.ENDED:
			return true
		w.status["k_guard_left"] = int(w.status.k_guard_left) - 1
		if strike(s, w, mover, "bash", {"reaction": true}) > 0:
			mover.actions_left = 0
			return true
	return not mover.is_alive()
