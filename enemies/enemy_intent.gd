class_name EnemyIntent
extends RefCounted
## What each enemy is about to do, for the intent icons and red danger tiles the view shows
## during the team phase. Pure reads of GameState. OWNER: enemies workstream.
##
## intents(s) -> Array of {unit, icon, label, target (unit id or -1), affixes: Array[String]}
##   icon: "claw" | "shoot" | "spit" | "burst" | "charge" | "scream" | "spawn" | "strike" | "leap" | "snipe" | "drop" |
##         "pull" | "pulse" | "hide" | "seek" | "dormant" | "pinning"
## dangers(s) -> Array of {kind, cells: Array[Vector2i], unit, turn}: tiles that get hit next (kind "trail" is the
##   line a burrowed enemy digs along, drawn as dirt rather than red)
##   enemy phase (bursts, charges, airstrikes, core slams). Paint them red.
## Spore zones are Hazards tiles, drawn by the Board. incoming(s) -> vent cells glowing for a wave.
## tethers(s) -> Array of [shield id, shielded id] pairs to draw as threads.
## ripples(s) -> Array[Vector2i] cells of hidden Lurkers inside the squad's vision (a faint ripple).
## Fog of war: only enemies the squad sees (or senses, Spore Sense) show an intent, and only their
## dangers show; telegraphed strikes (airstrikes, core slams) always show.


static func intents(s: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var sensed := Vision.sensed(s)
	for u in s.living(Types.Team.ENEMY):
		if u.status.get("hidden", false) or not (Vision.sees_unit(s, Types.Team.PLAYER, u) or sensed.has(u.id)):
			continue
		var it := _intent(s, u)
		it["unit"] = u.id
		var affixes: Array[String] = []
		for a in u.status.get("affixes", []):
			affixes.append(EnemyRoster.AFFIX_INFO[a].name)
		it["affixes"] = affixes
		out.append(it)
	return out


static func _intent(s: GameState, u: Unit) -> Dictionary:
	var sp: Dictionary = u.status.get("spawner", {})
	if not sp.is_empty():
		var n := maxi(0, int(sp.next) - s.turn)
		return {"icon": "spawn", "label": "SPAWNS NOW" if n == 0 else "SPAWNS IN %d" % n, "target": -1}
	if EnemyRoster.is_static(u):
		return {"icon": "dormant", "label": "", "target": -1}
	var phase := int(u.status.get("boss_phase", 1))
	if u.kind == "the_source":
		if u.status.has("tether"):
			return {"icon": "pulse", "label": "LASH + INFECTION +%d" % Encounter.SOURCE_PULSE_SQUAD[clampi(int(s.encounter.get("squad", 4)), 1, 4)], "target": -1}
		var pt := EnemyAbilities.pull_target(s, u)
		return {"icon": "pull", "label": "PULL + SLAM" if phase == 2 else "LASH + SLAM", "target": pt.id if pt else -1}
	if not EnemyAI.is_alerted(u) and not u.status.get("turned", false) and UnitData.ENEMIES.has(u.kind):
		return {"icon": "dormant", "label": "UNAWARE", "target": -1}
	if u.kind == "collector" and not Recovery.collector_intent(s, u).is_empty():
		return Recovery.collector_intent(s, u)
	if u.status.has("pinning"):
		return {"icon": "pinning", "label": "HOLDING" if u.kind == "netter" else "MAULING", "target": int(u.status.pinning)}
	if u.status.has("swelling"):
		return {"icon": "bloom" if u.kind == "acolyte" else "burst", "label": "BLOOMING" if u.kind == "acolyte" else "BURSTING", "target": -1}
	if u.status.has("hushing"):
		return {"icon": "hush", "label": "SILENCING", "target": int(u.status.hushing)}
	if u.status.has("leap_cell"):
		return {"icon": "leap", "label": "LEAPING", "target": -1}
	if u.status.has("hooked"):
		return {"icon": "hook", "label": "HOOKING", "target": int(u.status.hooked)}
	if u.status.has("sighted"):
		return {"icon": "snipe", "label": "AIMING", "target": int(u.status.sighted)}
	if u.status.has("charge_dir"):
		var lane := EnemyAbilities.charge_lane(s, u, u.pos, u.status.charge_dir)
		var hit: Unit = lane.hit
		return {"icon": "charge", "label": "CHARGING", "target": hit.id if hit and u.is_enemy_of(hit) else -1}
	var hostiles := EnemyAI._hostiles(s, u)
	var plan := EnemyAI.preview(s, u)   # what the AI would do right now: targets come from it
	match u.kind:
		"bloater", "broodling":
			return {"icon": "seek", "label": "SEEKING", "target": _nearest(u, hostiles)}
		"netter":
			return {"icon": "net", "label": "NETTING", "target": _planned(s, u, plan, _most_exposed(s, u, hostiles))}
		"handler":
			var mark := Recovery.designate_target(s, u) if Recovery.designation_of(s, u) == null else null
			if mark != null:
				return {"icon": "designate", "label": "DESIGNATING", "target": mark.id}
			return {"icon": "hide", "label": "HANDLING", "target": -1}
		"sterilizer":
			if int(u.cooldowns.get("sterilize", 0)) <= 1:
				return {"icon": "flame", "label": "STERILIZE", "target": _nearest(u, hostiles)}
			return {"icon": "hide", "label": "RETREATING", "target": -1}
		"acolyte":
			return {"icon": "bloom", "label": "RUSHING", "target": _planned(s, u, plan, _most_exposed(s, u, hostiles))}
		"cantor":
			return {"icon": "chant", "label": "CHANTING", "target": -1}
		"hush":
			var quiet := Choir.hush_target(s, u) if int(u.cooldowns.get("hush", 0)) <= 1 else null
			if quiet != null:
				return {"icon": "hush", "label": "HUSHING", "target": quiet.id}
			return {"icon": "hide", "label": "HIDING", "target": -1}
		"shrieker":
			if int(u.cooldowns.get("scream", 0)) <= 1:
				return {"icon": "scream", "label": "SCREAM", "target": -1}
			return {"icon": "hide", "label": "HIDING", "target": -1}
		"spitter":
			return {"icon": "spit", "label": "SPIT", "target": _best_visible(s, u)}
		"drifter":
			return {"icon": "drop", "label": "DROP", "target": _planned(s, u, plan, _most_exposed(s, u, hostiles))}
		"burrower":
			return {"icon": "claw", "label": "BURROW", "target": -1}
		"hooker":
			return {"icon": "hook", "label": "HOOK", "target": _planned(s, u, plan, _best_visible(s, u))}
		"relay":
			return {"icon": "hide", "label": "RELAYING", "target": -1}
		"hound":
			return {"icon": "claw", "label": "HUNTING", "target": _planned(s, u, plan, _most_exposed(s, u, hostiles))}
		"emplacement":
			return {"icon": "strike", "label": "CROSSFIRE", "target": -1}
		"overwatcher":
			if EnemyAI._best_shot(s, u).is_empty():
				return {"icon": "hide", "label": "WATCHING", "target": -1}
		"torchman":
			if int(u.cooldowns.get("firebomb", 0)) <= 1:
				return {"icon": "satchel", "label": "FIREBOMB", "target": _nearest(u, hostiles)}
			return {"icon": "hide", "label": "RETREATING", "target": -1}
		"cutter":
			if u.status.has("loot"):
				return {"icon": "hide", "label": "FLEEING", "target": -1}
			return {"icon": "claw", "label": "SNATCH", "target": _planned(s, u, plan, _most_exposed(s, u, hostiles))}
		"fence":
			return {"icon": "hide", "label": "LEAVING" if s.turn >= EnemyRoster.FENCE_LEAVES_TURN else "HOLDING LOOT", "target": -1}
		"sapper":
			if int(u.cooldowns.get("satchel", 0)) <= 1:
				return {"icon": "satchel", "label": "SATCHEL", "target": _nearest(u, hostiles)}
			return {"icon": "hide", "label": "RETREATING", "target": -1}
		"stalker":
			if EnemyBehaviours.is_watched(s, u):
				return {"icon": "hide", "label": "FROZEN", "target": -1}
			return {"icon": "claw", "label": "STALKING", "target": _planned(s, u, plan, _most_exposed(s, u, hostiles))}
		"weaver":
			var mt := EnemyAbilities.mend_target(s, u)
			if mt != null:
				return {"icon": "mend", "label": "MENDING", "target": mt.id}
			return {"icon": "hide", "label": "HIDING", "target": -1}
		"brood_mother":
			if BroodMother.will_burrow(s, u, true):
				return {"icon": "claw", "label": "BURROWING", "target": -1}
			if phase >= 3:
				return {"icon": "claw", "label": "BERSERK", "target": _planned(s, u, plan, _most_exposed(s, u, hostiles))}
			if int(u.cooldowns.get("acid_rain", 0)) <= 1:
				return {"icon": "strike", "label": "ACID RAIN", "target": -1}
		"colonel_hale":
			var near := ColonelHale._nearest_dist(u.pos, hostiles)
			if phase == 1:
				if int(u.cooldowns.get("airstrike", 0)) <= 1:
					return {"icon": "strike", "label": "AIRSTRIKE", "target": -1}
				if near <= ColonelHale.FALL_BACK:
					return {"icon": "hide", "label": "FALLING BACK", "target": -1}
			elif phase == 3 and near <= 2 and int(u.cooldowns.get("danger_close", 0)) <= 1:
				return {"icon": "strike", "label": "DANGER CLOSE", "target": -1}
			elif phase == 3 and near > 2 and int(u.cooldowns.get("hurl", 0)) <= 1:
				return {"icon": "strike", "label": "HURL", "target": -1}
			elif phase >= 2 and int(u.cooldowns.get("stomp", 0)) <= 1 and \
					hostiles.filter(func(h: Unit) -> bool: return s.grid.melee_reach(u.pos, h.pos)).size() >= 2:
				return {"icon": "strike", "label": "STOMP", "target": -1}
	var melee: bool = UnitData.is_melee_only(u.kind) or (u.kind == "colonel_hale" and phase >= 2)
	var icon := "claw" if melee else "shoot"
	if EnemyAI.has_scripted_turn(u):   # bosses run their own turn, so there is no generic plan to read
		return {"icon": icon, "label": "", "target": _most_exposed(s, u, hostiles) if melee else _best_visible(s, u)}
	if plan.is_empty():
		return {"icon": "hide", "label": "HOLDING", "target": -1}
	return {"icon": icon, "label": "", "target": _planned(s, u, plan, -1)}


## The unit the AI's own next action (EnemyAI.preview) is aimed at: its shoot / ability target, or for a
## move the hostile nearest the cell it is walking to. `fallback` when the plan names nobody.
static func _planned(s: GameState, u: Unit, plan: Dictionary, fallback: int) -> int:
	if plan.is_empty():
		return fallback
	if plan.has("target"):
		return int(plan.target)
	var at: Vector2i = plan.get("to", plan.get("cell", u.pos))
	var best: Unit = null
	for h in EnemyAI._hostiles(s, u):
		if best == null or EnemyAI._dist(at, h.pos) < EnemyAI._dist(at, best.pos):
			best = h
	return best.id if best else fallback

static func dangers(s: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in s.encounter.get("telegraphs", []):
		out.append({"kind": t.kind, "cells": t.cells, "unit": int(t.get("unit", -1)), "turn": int(t.turn)})
	for u in s.living(Types.Team.ENEMY):
		if not Vision.sees_unit(s, Types.Team.PLAYER, u) and not u.status.has("emerge_cell"):
			continue
		if u.status.has("swelling"):
			out.append({"kind": "bloom" if u.kind == "acolyte" else "burst", "cells": Choir.bloom_cells(s, u) if u.kind == "acolyte" else EnemyAbilities.square(s.grid, u.pos, 1),
				"unit": u.id, "turn": s.turn})
		if u.status.has("hushing"):
			var hu := s.get_unit(int(u.status.hushing))
			if hu != null and hu.is_alive():
				out.append({"kind": "hush", "cells": EnemyAbilities.line_cells(u.pos, hu.pos), "unit": u.id, "turn": s.turn})
		if u.kind == "collector" and Recovery.held(s, u) != null:
			out.append({"kind": "drag", "cells": Recovery.drag_path(s, u), "unit": u.id, "turn": s.turn})
		if u.status.has("leap_cell"):
			out.append({"kind": "leap", "cells": EnemyAbilities.square(s.grid, u.status.leap_cell, 1), "unit": u.id, "turn": s.turn})
		if u.status.has("emerge_cell"):
			out.append({"kind": "erupt", "cells": EnemyAbilities.square(s.grid, u.status.emerge_cell, 1), "unit": u.id, "turn": s.turn})
			out.append({"kind": "trail", "cells": u.status.get("trail", []), "unit": u.id, "turn": s.turn})
		if u.status.has("sighted"):
			var t := s.get_unit(int(u.status.sighted))
			if t != null and t.is_alive():
				out.append({"kind": "snipe", "cells": [t.pos], "unit": u.id, "turn": s.turn})
		if u.status.has("charge_dir"):
			var lane := EnemyAbilities.charge_lane(s, u, u.pos, u.status.charge_dir)
			out.append({"kind": "charge", "cells": lane.cells, "unit": u.id, "turn": s.turn})
		if u.status.has("hooked"):
			var h := s.get_unit(int(u.status.hooked))
			if h != null and h.is_alive():
				out.append({"kind": "hook", "cells": EnemyAbilities.line_cells(u.pos, h.pos), "unit": u.id, "turn": s.turn})
	return out


## [shield id, shielded id] for every living shield (egg sac, root, hive node) and the enemy whose
## tether it holds, both seen by the squad.
static func tethers(s: GameState) -> Array:
	var out: Array = []
	for u in s.living(Types.Team.ENEMY):
		var kind := str(u.status.get("tether", ""))
		if kind == "" or not Vision.sees_unit(s, Types.Team.PLAYER, u):
			continue
		for o in s.living(Types.Team.ENEMY):
			if o.kind == kind and Vision.sees_unit(s, Types.Team.PLAYER, o):
				out.append([o.id, u.id])
	return out


## [{unit, cells}] the armoured side of every Carapace the squad sees.
static func plates(s: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u in s.living(Types.Team.ENEMY):
		if u.status.get("plate", false) and Vision.sees_unit(s, Types.Team.PLAYER, u):
			out.append({"unit": u.id, "cells": EnemyBehaviours.plate_cells(s, u)})
	return out


## [weaver id, mended id] for each Weaver's thread, seen by the squad.
static func links(s: GameState) -> Array:
	var out: Array = []
	for u in s.living(Types.Team.ENEMY):
		if u.kind != "weaver" or not Vision.sees_unit(s, Types.Team.PLAYER, u):
			continue
		var t := EnemyAbilities.mend_target(s, u)
		if t != null and Vision.sees_unit(s, Types.Team.PLAYER, t):
			out.append([u.id, t.id])
	out.append_array(Choir.links(s))
	return out


## [handler id, soldier id] for each live designation the squad can see: the line Recovery aims along.
static func designations(s: GameState) -> Array:
	var out: Array = []
	for u in s.living(Types.Team.ENEMY):
		var t := Recovery.designation_of(s, u) if u.kind == "handler" else null
		if t != null and Vision.sees_unit(s, Types.Team.PLAYER, u):
			out.append([u.id, t.id])
	return out


## [{unit, cell}] each Cantor the squad sees: enemies in its ring, in its sight, hit harder.
static func chants(s: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u in s.living(Types.Team.ENEMY):
		if u.kind == "cantor" and Vision.sees_unit(s, Types.Team.PLAYER, u):
			out.append({"unit": u.id, "cell": u.pos})
	return out


## [{unit, cell}] each Rallying enemy the squad sees: Infected within RALLY_RADIUS of it hit harder.
static func rallies(s: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u in s.living(Types.Team.ENEMY):
		if EnemyRoster.has_affix(u, "rallying") and Vision.sees_unit(s, Types.Team.PLAYER, u):
			out.append({"unit": u.id, "cell": u.pos})
	return out


static func incoming(s: GameState) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for w in s.encounter.get("incoming", []):
		for c in w.cells:
			out.append(c)
	return out


static func ripples(s: GameState) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for u in s.living(Types.Team.ENEMY):
		if u.status.get("hidden", false) and not u.status.has("burrowed") and Vision.cell_visible(s, Types.Team.PLAYER, u.pos):
			out.append(u.pos)
	return out


static func _nearest(u: Unit, hostiles: Array[Unit]) -> int:
	var best: Unit = null
	for h in hostiles:
		if best == null or EnemyAI._dist(u.pos, h.pos) < EnemyAI._dist(u.pos, best.pos):
			best = h
	return best.id if best else -1


static func _most_exposed(s: GameState, u: Unit, hostiles: Array[Unit]) -> int:
	var best: Unit = null
	var best_score := -INF
	for h in hostiles:
		var score := EnemyAI._target_score(s, u, h, u.pos)
		if score > best_score:
			best_score = score
			best = h
	return best.id if best else -1


static func _best_visible(s: GameState, u: Unit) -> int:
	var best: Unit = null
	var best_hit := -1
	for t in Combat.visible_targets(s, u):
		var hit: int = Combat.hit_chance(s, u, t).hit
		if hit > best_hit:
			best_hit = hit
			best = t
	return best.id if best else -1
