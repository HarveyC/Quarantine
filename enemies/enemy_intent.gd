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
			return {"icon": "pulse", "label": "LASH + INFECTION +%d" % Encounter.SOURCE_PULSE, "target": -1}
		var pt := EnemyAbilities.pull_target(s, u)
		return {"icon": "pull", "label": "PULL + SLAM" if phase == 2 else "LASH + SLAM", "target": pt.id if pt else -1}
	if not EnemyAI.is_alerted(u) and not u.status.get("turned", false) and UnitData.ENEMIES.has(u.kind):
		return {"icon": "dormant", "label": "UNAWARE", "target": -1}
	if u.status.has("pinning"):
		return {"icon": "pinning", "label": "MAULING", "target": int(u.status.pinning)}
	if u.status.has("swelling"):
		return {"icon": "burst", "label": "BURSTING", "target": -1}
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
	match u.kind:
		"bloater", "broodling":
			return {"icon": "seek", "label": "SEEKING", "target": _nearest(u, hostiles)}
		"shrieker":
			if int(u.cooldowns.get("scream", 0)) <= 1:
				return {"icon": "scream", "label": "SCREAM", "target": -1}
			return {"icon": "hide", "label": "HIDING", "target": -1}
		"spitter":
			return {"icon": "spit", "label": "SPIT", "target": _best_visible(s, u)}
		"drifter":
			return {"icon": "drop", "label": "DROP", "target": _most_exposed(s, u, hostiles)}
		"burrower":
			return {"icon": "claw", "label": "BURROW", "target": -1}
		"hooker":
			return {"icon": "hook", "label": "HOOK", "target": _best_visible(s, u)}
		"sapper":
			if int(u.cooldowns.get("satchel", 0)) <= 1:
				return {"icon": "satchel", "label": "SATCHEL", "target": _nearest(u, hostiles)}
			return {"icon": "hide", "label": "RETREATING", "target": -1}
		"stalker":
			if EnemyBehaviours.is_watched(s, u):
				return {"icon": "hide", "label": "FROZEN", "target": -1}
			return {"icon": "claw", "label": "STALKING", "target": _most_exposed(s, u, hostiles)}
		"weaver":
			var mt := EnemyAbilities.mend_target(s, u)
			if mt != null:
				return {"icon": "mend", "label": "MENDING", "target": mt.id}
			return {"icon": "hide", "label": "HIDING", "target": -1}
		"brood_mother":
			if BroodMother.will_burrow(s, u, true):
				return {"icon": "claw", "label": "BURROWING", "target": -1}
			if phase >= 3:
				return {"icon": "claw", "label": "BERSERK", "target": _most_exposed(s, u, hostiles)}
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
	if UnitData.is_melee_only(u.kind) or (u.kind == "colonel_hale" and phase >= 2):
		return {"icon": "claw", "label": "", "target": _most_exposed(s, u, hostiles)}
	return {"icon": "shoot", "label": "", "target": _best_visible(s, u)}


static func dangers(s: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in s.encounter.get("telegraphs", []):
		out.append({"kind": t.kind, "cells": t.cells, "unit": int(t.get("unit", -1)), "turn": int(t.turn)})
	for u in s.living(Types.Team.ENEMY):
		if not Vision.sees_unit(s, Types.Team.PLAYER, u) and not u.status.has("emerge_cell"):
			continue
		if u.status.has("swelling"):
			out.append({"kind": "burst", "cells": EnemyAbilities.square(s.grid, u.pos, 1), "unit": u.id, "turn": s.turn})
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
