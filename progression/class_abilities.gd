class_name ClassAbilities
extends RefCounted
## Abilities added by the progression workstream: Hazmat Incinerate, Vector Siphon, perk abilities
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
		var has_targets: bool = def.targeting == "cell" or not targets.is_empty()
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
	if not _owns(u, id) or not Kit.is_soldier(u):
		return "Unknown ability"
	var def: Dictionary = ABILITIES[id]
	if int(u.cooldowns.get(id, 0)) > 0:
		return "On cooldown"
	if u.actions_left < maxi(1, def.cost):
		return "Not enough actions"
	var extra := _extra_error(u, id)
	if extra != "":
		return extra
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
			if not s.grid.in_bounds(c) or s.grid.blocks_los(c):
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
