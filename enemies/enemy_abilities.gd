class_name EnemyAbilities
extends RefCounted
## Abilities used only by the enemy roster and bosses. Rules routes ABILITY actions whose id is
## in DEFS here instead of to Combat, so they go through Rules.validate / Rules.apply like any
## other action and stay deterministic for online play. OWNER: enemies workstream.
##
## Action fields: "target" (unit id) for unit abilities, "cell" (Vector2i) for cell abilities,
## core_slam also takes "axis": "row" | "col".

## "cost": actions spent, -1 = ends the turn. "phase": only usable in that boss phase.
const DEFS := {
	"slam": {"name": "Slam", "targeting": "unit", "cost": -1, "cooldown": 0,
		"desc": "Melee hit on an adjacent soldier that knocks them back 1 tile."},
	"charge": {"name": "Charge", "targeting": "none", "cost": -1, "cooldown": 0,
		"desc": "Charges along the lane it wound up for, smashing half cover, then slams the first unit in the way."},
	"burst": {"name": "Burst", "targeting": "none", "cost": -1, "cooldown": 0,
		"desc": "Bursts: 3 damage and +20 Infection in a 3x3, leaving a spore zone."},
	"pounce": {"name": "Pounce", "targeting": "unit", "cost": -1, "cooldown": 0,
		"desc": "Leaps next to a soldier and pins them until a teammate hits the Lurker."},
	"maul": {"name": "Maul", "targeting": "none", "cost": -1, "cooldown": 0,
		"desc": "Mauls the pinned soldier for 2 damage."},
	"scream": {"name": "Scream", "targeting": "none", "cost": -1, "cooldown": 2,
		"desc": "Infected within 6 tiles get +2 move and +10 aim next turn, and every dormant pod wakes."},
	"acid_rain": {"name": "Acid rain", "targeting": "cell", "cost": 1, "cooldown": 2,
		"desc": "Lobs acid onto a 3x3 that lands next enemy phase: 3 damage and a spore patch for 2 turns."},
	"rockfall": {"name": "Rockfall", "targeting": "none", "cost": -1, "cooldown": 0,
		"desc": "Throws up a spray of rocks onto marked tiles that land next enemy phase: 2 damage each, smashes cover. Move off a marked tile to dodge."},
	"airstrike": {"name": "Airstrike", "targeting": "cell", "cost": 1, "cooldown": 2, "phase": 1,
		"desc": "Calls a 3x3 airstrike that lands next enemy phase: 4 damage and destroys half cover."},
	"flashbang": {"name": "Flashbang", "targeting": "cell", "cost": 1, "cooldown": 2, "phase": 1,
		"desc": "Removes overwatch and hunker from soldiers in a 3x3."},
	"leap": {"name": "Leap", "targeting": "none", "cost": -1, "cooldown": 0,
		"desc": "Lands on the marked spot, ignoring terrain, height and overwatch: 3 damage in a 3x3 and knocks soldiers away (off ledges too)."},
	"drift": {"name": "Drift", "targeting": "cell", "cost": 1, "cooldown": 0,
		"desc": "Floats to a cell in range over walls, cover and height."},
	"spore_drop": {"name": "Spore drop", "targeting": "unit", "cost": -1, "cooldown": 0,
		"desc": "Drops on a soldier within 2 tiles from above: 2 damage that ignores cover, and a spore puddle."},
	"sight": {"name": "Laser sight", "targeting": "unit", "cost": -1, "cooldown": 0,
		"desc": "Locks onto a soldier it can see. Next turn it fires unless the soldier breaks line of sight or it is suppressed."},
	"snipe": {"name": "Snipe", "targeting": "none", "cost": -1, "cooldown": 0,
		"desc": "Fires at the locked soldier: never misses, ignores half cover, full cover halves the damage."},
	"burrow": {"name": "Burrow", "targeting": "unit", "cost": -1, "cooldown": 0,
		"desc": "Tunnels toward a soldier and marks where it will erupt next turn."},
	"erupt": {"name": "Erupt", "targeting": "none", "cost": -1, "cooldown": 0,
		"desc": "Bursts out: 3 damage in a 3x3, destroys half cover and collapses high ground there."},
	"hook": {"name": "Hook", "targeting": "unit", "cost": -1, "cooldown": 0,
		"desc": "Locks a barbed line onto a soldier it can see. Next turn it reels them up to 3 tiles toward it for 2 damage, unless line of sight breaks or it is suppressed. The first soldier on the line is the one pulled."},
	"reel": {"name": "Reel", "targeting": "none", "cost": -1, "cooldown": 0,
		"desc": "Yanks the soldier on the hooked line toward the Hooker. A pull off high ground takes fall damage."},
	"satchel": {"name": "Satchel", "targeting": "cell", "cost": 1, "cooldown": 2,
		"desc": "Throws a satchel onto a 3x3 that goes off next enemy phase: 3 damage to everyone in it and it cracks cover. Killing the Sapper does not stop it."},
	"firebomb": {"name": "Firebomb", "targeting": "cell", "cost": 1, "cooldown": 2,
		"desc": "Lobs a firebomb onto a 3x3 that goes off next enemy phase: 2 damage to everyone in it, then the ground burns for 2 rounds. The Infected walk through the fire unharmed."},
	"mend": {"name": "Mend", "targeting": "unit", "cost": 1, "cooldown": 1,
		"desc": "Threads to a wounded Infected within 6 tiles in line of sight and heals it 3. Cut the thread by killing the Weaver or breaking line of sight."},
	"pull": {"name": "Pull", "targeting": "none", "cost": 1, "cooldown": 0, "phases": [2, 3],
		"desc": "Drags the soldier with the most Infection 2 tiles toward the Source."},
	"core_slam": {"name": "Core slam", "targeting": "cell", "cost": -1, "cooldown": 0, "phases": [2, 3],
		"desc": "Marks a whole row or column; it slams for 4 damage next enemy phase."},
	"smoke_screen": {"name": "Smoke screen", "targeting": "cell", "cost": 1, "cooldown": 4,
		"desc": "Pops a 3x3 smoke cloud to cover a fall back: +defense inside it."},
	"stomp": {"name": "Stomp", "targeting": "none", "cost": -1, "cooldown": 3,
		"desc": "Stamps the ground around him: 3 damage in a 3x3 next enemy phase, smashes cover."},
	"hurl": {"name": "Hurl", "targeting": "cell", "cost": 1, "cooldown": 2,
		"desc": "Hurls wreckage onto a 3x3 that lands next enemy phase: 4 damage, smashes cover and roofs."},
	"danger_close": {"name": "Danger close", "targeting": "none", "cost": 1, "cooldown": 3,
		"desc": "Calls an airstrike on his own position: 4 damage in a 5x5 next enemy phase, hits his own adds too."},
	"flag": {"name": "Retrieval mark", "targeting": "none", "cost": 1, "cooldown": 2, "phases": [2, 3],
		"desc": "Marks the most Infected soldier for retrieval: every enemy hit on them deals +1 damage, her shots ignore their cover and the Collectors go for them first."},
	"retrieve": {"name": "Retrieval", "targeting": "cell", "cost": 1, "cooldown": 2, "phases": [3],
		"desc": "Drops a retrieval cage on a 3x3 that lands next enemy phase: 5 damage, and a soldier a Collector has pinned is taken."},
	"drag": {"name": "Drag", "targeting": "none", "cost": -1, "cooldown": 0,
		"desc": "Hauls the pinned soldier toward the nearest exit lane. At the lane they are taken. Hit the Collector to free them."},
	"lash": {"name": "Lash", "targeting": "cell", "cost": 1, "cooldown": 0, "phases": [1, 3],
		"desc": "Roots lash a 3x3 next enemy phase: 3 damage and spores. Aims at the highest ground."},
}
## Hale's abilities by phase (ColonelHale): radio and air support, then the Brute, then the wreck.
const HALE_PHASES := {
	1: ["airstrike", "flashbang", "smoke_screen"],
	2: ["slam", "charge", "stomp", "airstrike"],
	3: ["slam", "charge", "stomp", "hurl", "danger_close", "airstrike"],
}

const CHARGE_RANGE := 6
const BURST_DAMAGE := 3
const BURST_INFECTION := 8        # on top of the normal hit gain, about +20 in total
const BROODLING_BURST_DAMAGE := 2
const SPORE_TURNS := 2
const MAUL_DAMAGE := 2
const SCREAM_RADIUS := 6.0
const FLASH_RANGE := 7.0
const STRIKE_DAMAGE := 4
const ACID_RAIN_DAMAGE := 3
const ACID_RAIN_RANGE := 10.0
const ROCK_DAMAGE := 2
const PULL_STEPS := 2
const LEAP_RANGE := 5
const LEAP_DAMAGE := 4
const DROP_RANGE := 2
const BURROW_RANGE := 8
const ERUPT_DAMAGE := 3
const STOMP_DAMAGE := 3
const SMOKE_RANGE := 6.0
const SMOKE_TURNS := 3
const HURL_RANGE := 9.0
const LASH_RANGE := 24.0


static func handles(id: String) -> bool:
	return DEFS.has(id)


## For a HUD inspecting an enemy: [{id, name, desc, cooldown, ready}].
static func describe(s: GameState, u: Unit) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in u.abilities:
		if DEFS.has(id) and _phase_ok(u, id):
			var cd: int = u.cooldowns.get(id, 0)
			out.append({"id": id, "name": DEFS[id].name, "desc": DEFS[id].desc, "cooldown": cd, "ready": cd <= 0})
	return out


static func _phase_ok(u: Unit, id: String) -> bool:
	var phase: int = u.status.get("boss_phase", 1)
	if u.kind == "colonel_hale":
		return HALE_PHASES[clampi(phase, 1, 3)].has(id)
	var need: int = DEFS[id].get("phase", 0)
	if DEFS[id].has("phases"):
		return DEFS[id].phases.has(phase)
	return need == 0 or need == phase


static func validate(s: GameState, u: Unit, action: Dictionary) -> String:
	var id: String = action.get("ability", "")
	if not DEFS.has(id) or not u.abilities.has(id):
		return "Unknown ability"
	if not _phase_ok(u, id):
		return "Not in this phase"
	if int(u.cooldowns.get(id, 0)) > 0:
		return "On cooldown"
	var def: Dictionary = DEFS[id]
	if Retrieval.handles(id):
		return Retrieval.validate(s, u, action)
	if def.targeting == "unit":
		var t := s.get_unit(action.get("target", -1))
		if t == null or not t.is_alive():
			return "No such target"
		if id == "mend":
			if t.team != u.team or t == u or EnemyRoster.is_static(t) or EnemyRoster.is_boss(t) or t.hp >= t.max_hp:
				return "Nothing to mend"
			if _cheb(u.pos, t.pos) > EnemyRoster.MEND_RANGE or not Combat.can_see(s, u.pos, t.pos):
				return "Thread cut"
			return ""
		if not u.is_enemy_of(t):
			return "Not an enemy"
		match id:
			"slam":
				if not s.grid.melee_reach(u.pos, t.pos):
					return "Not adjacent"
			"spore_drop":
				if _cheb(u.pos, t.pos) > DROP_RANGE:
					return "Out of range"
			"sight":
				if t.status.get("hidden", false) or not Combat.can_see(s, u.pos, t.pos):
					return "No line of sight"
			"hook":
				if u.status.has("hooked"):
					return "Already hooked"
				if t.status.get("hidden", false) or not Combat.can_see(s, u.pos, t.pos):
					return "No line of sight"
				var hd := _cheb(u.pos, t.pos)
				if hd < EnemyRoster.HOOK_MIN or hd > EnemyRoster.HOOK_RANGE:
					return "Out of range"
				if hook_victim(s, u, t) == null:
					return "Snagged"
			"burrow":
				if u.status.has("burrowed"):
					return "Already burrowed"
				if u.pos.distance_to(t.pos) > BURROW_RANGE:
					return "Out of range"
			"pounce":
				if u.status.has("pinning"):
					return "Already pinning"
				if t.status.has("pinned_by"):
					return "Already pinned"
				if pounce_cell(s, u, t) == Vector2i(-1, -1) and not s.grid.melee_reach(u.pos, t.pos):
					return "Out of reach"
		return ""
	if def.targeting == "cell":
		var cell: Variant = action.get("cell")
		if not cell is Vector2i or not s.grid.in_bounds(cell):
			return "Invalid cell"
		match id:
			"acid_rain":
				if u.pos.distance_to(cell) > ACID_RAIN_RANGE:
					return "Out of range"
			"flashbang":
				if u.pos.distance_to(cell) > FLASH_RANGE or not Combat.can_see(s, u.pos, cell):
					return "Out of range"
			"core_slam":
				if not action.get("axis", "") in ["row", "col"]:
					return "No axis"
			"smoke_screen":
				if u.pos.distance_to(cell) > SMOKE_RANGE:
					return "Out of range"
			"hurl":
				if u.pos.distance_to(cell) > HURL_RANGE or _cheb(u.pos, cell) <= 1:
					return "Out of range"
			"satchel", "firebomb":
				if _cheb(u.pos, cell) > EnemyRoster.SATCHEL_RANGE or not Combat.can_see(s, u.pos, cell):
					return "Out of range"
			"drift":
				var c: Vector2i = cell
				if s.grid.tile(c) == Types.Tile.WALL or s.unit_at(c) != null or c == u.pos:
					return "Blocked"
				if _cheb(u.pos, c) > u.mobility:
					return "Out of range"
		return ""
	match id:
		"charge":
			if not u.status.has("charge_dir"):
				return "Not wound up"
		"burst":
			if not u.status.has("swelling"):
				return "Not swelling"
		"leap":
			if not u.status.has("leap_cell"):
				return "No landing marked"
		"reel":
			var h := s.get_unit(int(u.status.get("hooked", -1)))
			if h == null or not h.is_alive() or not Combat.can_see(s, u.pos, h.pos):
				return "Lost the target"
			if Combat.has_status(s, u, "suppressed"):
				return "Suppressed"
			if hook_victim(s, u, h) == null:
				return "Snagged"
		"snipe":
			var t := s.get_unit(int(u.status.get("sighted", -1)))
			if t == null or not t.is_alive() or not Combat.can_see(s, u.pos, t.pos):
				return "Lost the target"
			if Combat.has_status(s, u, "suppressed"):
				return "Suppressed"
		"erupt":
			if not u.status.has("emerge_cell"):
				return "Not burrowed"
		"maul":
			var p := s.get_unit(u.status.get("pinning", -1))
			if p == null or not p.is_alive():
				return "Nobody pinned"
		"pull":
			if u.status.get("pull_turn", -1) == s.turn:
				return "Already pulled"
			if pull_target(s, u) == null:
				return "No target"
	return ""


## Actions an ability spends. The Director lays a lock and fires on it as two separate actions.
static func _cost(u: Unit, id: String, def: Dictionary) -> int:
	if u.kind == "director" and id in ["sight", "snipe"]:
		return 1
	return int(def.cost)


static func apply(s: GameState, u: Unit, action: Dictionary) -> void:
	var id: String = action.ability
	var def: Dictionary = DEFS[id]
	var cost: int = _cost(u, id, def)
	u.actions_left = 0 if cost < 0 else maxi(0, u.actions_left - cost)
	if int(def.cooldown) > 0:
		u.cooldowns[id] = def.cooldown
	if Retrieval.handles(id):
		Retrieval.apply(s, u, action)
		return
	match id:
		"slam": _slam(s, u, s.get_unit(action.target))
		"leap": _leap(s, u)
		"drift":
			var from := u.pos
			u.pos = action.cell
			s.emit({"type": "move", "unit": u.id, "from": from, "path": [action.cell] as Array[Vector2i], "flying": true})
		"spore_drop": _spore_drop(s, u, s.get_unit(action.target))
		"sight":
			var t := s.get_unit(action.target)
			u.status["sighted"] = t.id
			s.emit({"type": "ability", "unit": u.id, "ability": "sight", "target": t.id})
			s.emit({"type": "telegraph", "unit": u.id, "kind": "snipe", "cells": [t.pos] as Array[Vector2i], "turn": s.turn + 1, "target": t.id})
		"snipe": _snipe(s, u)
		"hook": _hook(s, u, s.get_unit(action.target))
		"reel": _reel(s, u)
		"mend": _mend(s, u, s.get_unit(action.target))
		"satchel":
			var cells := square(s.grid, action.cell, 1)
			s.emit({"type": "ability", "unit": u.id, "ability": id, "cell": action.cell, "cells": cells})
			Encounter.add_telegraph(s, {"kind": "satchel", "cells": cells, "turn": s.turn + 1,
				"damage": EnemyRoster.SATCHEL_DAMAGE, "source": u.id, "smash": true, "unit": u.id})
		"firebomb":
			var fcells := square(s.grid, action.cell, 1)
			s.emit({"type": "ability", "unit": u.id, "ability": id, "cell": action.cell, "cells": fcells})
			Encounter.add_telegraph(s, {"kind": "firebomb", "cells": fcells, "turn": s.turn + 1,
				"damage": EnemyRoster.FIREBOMB_DAMAGE, "source": u.id, "smash": false, "unit": u.id,
				"fire": EnemyRoster.FIREBOMB_FIRE_TURNS})
		"burrow": _burrow(s, u, s.get_unit(action.target))
		"erupt": _erupt(s, u)
		"charge": _charge(s, u)
		"burst": burst(s, u)
		"pounce": _pounce(s, u, s.get_unit(action.target))
		"maul": _maul(s, u)
		"scream": _scream(s, u)
		"airstrike":
			var cells := square(s.grid, action.cell, 1)
			s.emit({"type": "ability", "unit": u.id, "ability": id, "cell": action.cell, "cells": cells})
			Encounter.add_telegraph(s, {"kind": "airstrike", "cells": cells, "turn": s.turn + 1,
				"damage": STRIKE_DAMAGE, "source": -1, "smash": true, "unit": u.id})
		"acid_rain":
			var cells := square(s.grid, action.cell, 1)
			s.emit({"type": "ability", "unit": u.id, "ability": id, "cell": action.cell, "cells": cells})
			Encounter.add_telegraph(s, {"kind": "acid_rain", "cells": cells, "turn": s.turn + 1,
				"damage": ACID_RAIN_DAMAGE, "source": u.id, "smash": false, "unit": u.id, "spores": SPORE_TURNS})
		"flashbang": _flashbang(s, u, action.cell)
		"smoke_screen":
			var cells := square(s.grid, action.cell, 1)
			s.emit({"type": "ability", "unit": u.id, "ability": id, "cell": action.cell, "cells": cells})
			Hazards.add(s, cells, "smoke", SMOKE_TURNS, u.id)
		"stomp", "danger_close":
			var cells := square(s.grid, u.pos, 1 if id == "stomp" else 2)
			s.emit({"type": "ability", "unit": u.id, "ability": id, "cell": u.pos, "cells": cells})
			Encounter.add_telegraph(s, {"kind": id, "cells": cells, "turn": s.turn + 1,
				"damage": STOMP_DAMAGE if id == "stomp" else STRIKE_DAMAGE, "source": u.id, "smash": true, "unit": u.id})
		"rockfall":
			var rocks: Array = action.get("cells", [])
			s.emit({"type": "ability", "unit": u.id, "ability": id, "cells": rocks})
			Encounter.add_telegraph(s, {"kind": "rockfall", "cells": rocks, "turn": s.turn + 1,
				"damage": ROCK_DAMAGE, "source": u.id, "smash": true, "unit": u.id})
		"hurl":
			var cells := square(s.grid, action.cell, 1)
			s.emit({"type": "ability", "unit": u.id, "ability": id, "cell": action.cell, "cells": cells})
			Encounter.add_telegraph(s, {"kind": "hurl", "cells": cells, "turn": s.turn + 1,
				"damage": STRIKE_DAMAGE, "source": u.id, "smash": true, "unit": u.id})
		"lash":
			var cells := square(s.grid, action.cell, 1)
			s.emit({"type": "ability", "unit": u.id, "ability": id, "cell": action.cell, "cells": cells})
			Encounter.add_telegraph(s, {"kind": "lash", "cells": cells, "turn": s.turn + 1,
				"damage": SourceBoss.LASH_DAMAGE, "source": u.id, "smash": false, "unit": u.id, "spores": SPORE_TURNS})
		"pull": _pull(s, u)
		"core_slam":
			var cells := slam_line(s, u, action.cell, action.axis)
			s.emit({"type": "ability", "unit": u.id, "ability": id, "cell": action.cell, "cells": cells})
			Encounter.add_telegraph(s, {"kind": "core_slam", "cells": cells, "turn": s.turn + 1,
				"damage": STRIKE_DAMAGE, "source": u.id, "smash": false, "unit": u.id})


# --- individual abilities ----------------------------------------------------------------

static func _slam(s: GameState, u: Unit, t: Unit) -> void:
	var odds := Combat.melee_chance(s, u, t)
	var r := Combat.resolve_roll(s.rng.randi_range(1, 100), odds)
	var dmg := 0
	if r.hit or r.graze:
		dmg = Combat.final_damage(s.rng.randi_range(u.damage.x, u.damage.y), r.graze, false)
	s.emit({"type": "ability", "unit": u.id, "ability": "slam", "target": t.id,
		"hit": r.hit or r.graze, "graze": r.graze, "damage": dmg, "chance": odds.hit})
	if dmg > 0:
		Rules.deal_damage(s, t, dmg, u)
		if r.hit and t.is_alive():
			knockback(s, t, _step_dir(u.pos, t.pos), 1)


## Cells the charge would cross from `from` along `dir`, and the unit it would hit (or null).
static func charge_lane(s: GameState, u: Unit, from: Vector2i, dir: Vector2i) -> Dictionary:
	var cells: Array[Vector2i] = []
	var c := from
	var hit: Unit = null
	for i in CHARGE_RANGE:
		var n := c + dir
		if not s.grid.in_bounds(n) or s.grid.tile(n) == Types.Tile.WALL:
			break
		if not s.grid.melee_reach(c, n):
			break   # walls and ledges stop a charge; stairs don't
		var o := s.unit_at(n)
		if o != null and o != u:
			hit = o
			cells.append(n)
			break
		cells.append(n)
		c = n
	return {"cells": cells, "hit": hit}


static func _charge(s: GameState, u: Unit) -> void:
	var dir: Vector2i = u.status.charge_dir
	u.status.erase("charge_dir")
	var lane := charge_lane(s, u, u.pos, dir)
	var hit: Unit = lane.hit
	var path: Array[Vector2i] = []
	var smashed: Array[Vector2i] = []
	for c in lane.cells:
		if hit != null and c == hit.pos:
			break
		if s.grid.tile(c) == Types.Tile.LOW:
			smashed.append(c)
		path.append(c)
	var from := u.pos
	if not smashed.is_empty():
		# Ploughs through the cover in its lane first (a fuel barrel in the way goes off).
		var hits := {}
		for c in smashed:
			hits[c] = 1
		Destruction.hit(s, hits, u)
		if not u.is_alive() or s.phase == Types.Phase.ENDED:
			return
	if not path.is_empty():
		Rules.open_doors_along(s, from, path, u)
		u.pos = path[-1]
		s.emit({"type": "move", "unit": u.id, "from": from, "path": path})
		if u.kind == "colonel_hale":   # the Brute's run shakes every roof along its lane down
			var shaken := {}
			for c in path:
				for n in square(s.grid, c, 1):
					shaken[n] = true
			EnemyTerrain.collapse(s, shaken.keys(), u)
	var dmg := 0
	if hit != null and u.is_enemy_of(hit):
		dmg = s.rng.randi_range(u.damage.x, u.damage.y)
	s.emit({"type": "ability", "unit": u.id, "ability": "charge", "target": hit.id if hit else -1,
		"hit": dmg > 0, "damage": dmg, "path": path})
	if dmg > 0:
		Rules.deal_damage(s, hit, dmg, u)
		if hit.is_alive():
			knockback(s, hit, dir, 1)


## Leaper: lands on the cell it marked last turn. Ignores terrain, height and overwatch. The impact
## hits every level around the landing (that is how Leapers get at raised soldiers); the claws that
## follow it need Grid.melee_reach like any other.
static func _leap(s: GameState, u: Unit) -> void:
	var cell: Vector2i = u.status.leap_cell
	u.status.erase("leap_cell")
	if s.unit_at(cell) != null or not s.grid.is_walkable(cell):
		cell = Encounter.free_cell(s, cell)
	var cells := square(s.grid, cell, 1)
	var from := u.pos
	u.pos = cell
	s.emit({"type": "move", "unit": u.id, "from": from, "path": [cell] as Array[Vector2i], "leap": true})
	var victims: Array[Unit] = []
	for t in s.living():
		if t != u and cells.has(t.pos) and u.is_enemy_of(t):
			victims.append(t)
	s.emit({"type": "ability", "unit": u.id, "ability": "leap", "cell": cell, "cells": cells,
		"units": victims.map(func(x: Unit) -> int: return x.id), "damage": LEAP_DAMAGE})
	for t in victims:
		Rules.deal_damage(s, t, LEAP_DAMAGE, u)
		if t.is_alive():
			knockback(s, t, _step_dir(cell, t.pos), 1)


## Cells a Leaper could land on next turn: free, walkable, within range, next to a hostile.
static func landing_cells(s: GameState, u: Unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var occ := s.occupied(u.id)
	for t in s.living():
		if not u.is_enemy_of(t) or t.status.get("hidden", false):
			continue
		for d in Grid.DIRS8:
			var c: Vector2i = t.pos + d
			if not out.has(c) and s.grid.is_walkable(c) and not occ.has(c) and _cheb(u.pos, c) <= LEAP_RANGE:
				out.append(c)
	return out


static func _spore_drop(s: GameState, u: Unit, t: Unit) -> void:
	var dmg := s.rng.randi_range(u.damage.x, u.damage.y)
	s.emit({"type": "ability", "unit": u.id, "ability": "spore_drop", "target": t.id, "hit": true, "damage": dmg})
	Rules.deal_damage(s, t, dmg, u)
	Encounter.add_spores(s, [t.pos], SPORE_TURNS, u)


static func _snipe(s: GameState, u: Unit) -> void:
	var t := s.get_unit(int(u.status.sighted))
	u.status.erase("sighted")
	var dmg := s.rng.randi_range(u.damage.x, u.damage.y)
	var cover := Elevation.adjust_cover(s, u, t, u.pos, Combat.cover_against(s.grid, t.pos, u.pos))
	if Retrieval.is_marked(t):
		cover = Types.Cover.NONE   # a marked soldier has nowhere to hide
	if cover == Types.Cover.FULL:
		dmg = maxi(1, dmg / 2)
	s.emit({"type": "shot", "unit": u.id, "target": t.id, "hit": true, "graze": cover == Types.Cover.FULL,
		"crit": false, "damage": dmg, "chance": 100, "reaction": false, "snipe": true})
	Rules.deal_damage(s, t, dmg, u)


# --- Hooker, Weaver --------------------------------------------------------------------------

## Cells a straight line from `a` to `b` crosses, `a` excluded and `b` included.
static func line_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in range(1, n + 1):
		var f := float(i) / n
		out.append(Vector2i(roundi(lerpf(a.x, b.x, f)), roundi(lerpf(a.y, b.y, f))))
	return out


## The soldier a hook from `u` toward `t` catches: the first unit on the line, if it is a hostile.
static func hook_victim(s: GameState, u: Unit, t: Unit) -> Unit:
	for c in line_cells(u.pos, t.pos):
		var o := s.unit_at(c)
		if o != null and o != u:
			return o if u.is_enemy_of(o) else null
	return null


static func _hook(s: GameState, u: Unit, t: Unit) -> void:
	u.status["hooked"] = t.id
	s.emit({"type": "ability", "unit": u.id, "ability": "hook", "target": t.id})
	s.emit({"type": "telegraph", "unit": u.id, "kind": "hook", "cells": line_cells(u.pos, t.pos), "turn": s.turn + 1, "target": t.id})


static func _reel(s: GameState, u: Unit) -> void:
	var locked := s.get_unit(int(u.status.hooked))
	u.status.erase("hooked")
	var t := hook_victim(s, u, locked)
	var path := pull_toward(s, t, u.pos, EnemyRoster.HOOK_PULL)
	var from := t.pos
	var dmg := EnemyRoster.HOOK_DAMAGE
	if not path.is_empty():
		t.pos = path[-1]
		t.hunkered = false
		t.overwatch = false
		t.status.erase("ow_until")
		t.status.erase("hunker_until")
	s.emit({"type": "ability", "unit": u.id, "ability": "reel", "target": t.id, "hit": true, "damage": dmg, "path": path})
	if not path.is_empty():
		s.emit({"type": "move", "unit": t.id, "from": from, "path": path, "knockback": true, "hooked": true})
		Encounter.check_pins(s)
		var fall := EnemyTerrain.fall_damage(s, from, t.pos)
		if fall > 0:
			s.emit({"type": "fell", "unit": t.id, "damage": fall})
			Rules.deal_damage(s, t, fall, null)
	if t.is_alive():
		Rules.deal_damage(s, t, dmg, u)


## Steps `t` toward `goal` along open floor, up to `steps`, stopping once beside it, against a
## wall or unit, or at a step up. Returns the cells walked (empty when it cannot move).
static func pull_toward(s: GameState, t: Unit, goal: Vector2i, steps: int) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var c := t.pos
	var occ := s.occupied(t.id)
	for i in steps:
		if _cheb(c, goal) <= 1:
			break
		var best := c
		for d in Grid.DIRS8:
			var n: Vector2i = c + d
			if not s.grid.is_walkable(n) or occ.has(n) or n == goal or not s.grid.touching(c, n):
				continue
			if EnemyTerrain.level(s, n) > EnemyTerrain.level(s, c):
				continue
			if d.x != 0 and d.y != 0 and not (s.grid.is_walkable(c + Vector2i(d.x, 0)) and s.grid.is_walkable(c + Vector2i(0, d.y))):
				continue
			if n.distance_squared_to(goal) < best.distance_squared_to(goal):
				best = n
		if best == c:
			break
		c = best
		path.append(c)
	return path


## Cell a hooked soldier would land on (for the AI's combo scoring), or `t.pos` if it would not move.
static func reel_landing(s: GameState, u: Unit, t: Unit) -> Vector2i:
	var path := pull_toward(s, t, u.pos, EnemyRoster.HOOK_PULL)
	return path[-1] if not path.is_empty() else t.pos


static func _mend(s: GameState, u: Unit, t: Unit) -> void:
	var healed := mini(EnemyRoster.MEND_HEAL, t.max_hp - t.hp)
	t.hp += healed
	s.emit({"type": "ability", "unit": u.id, "ability": "mend", "target": t.id, "heal": healed, "hp": t.hp})
	s.emit({"type": "regenerate", "unit": t.id, "healed": healed, "hp": t.hp})


## The wounded Infected a Weaver would mend now (most hurt first), or null.
static func mend_target(s: GameState, u: Unit) -> Unit:
	var best: Unit = null
	var best_lost := 0
	for o in s.living(u.team):
		if validate(s, u, {"ability": "mend", "target": o.id}) != "":
			continue
		var lost := o.max_hp - o.hp
		if lost > best_lost:
			best_lost = lost
			best = o
	return best


static func _burrow(s: GameState, u: Unit, t: Unit) -> void:
	var best := Encounter.free_cell(s, t.pos)
	for d in Grid.DIRS8:
		var c: Vector2i = t.pos + d
		if s.grid.is_walkable(c) and s.unit_at(c) == null:
			best = c
			break
	u.status["burrowed"] = true
	u.status["hidden"] = true
	u.status["emerge_cell"] = best
	var trail := trail_cells(u.pos, best)
	u.status["trail"] = trail
	u.overwatch = false
	s.emit({"type": "ability", "unit": u.id, "ability": "burrow", "target": t.id, "cell": best, "trail": trail})
	s.emit({"type": "burrowed", "unit": u.id})
	s.emit({"type": "telegraph", "unit": u.id, "kind": "erupt", "cells": square(s.grid, best, 1), "turn": s.turn + 1,
		"trail": trail})


## The straight line of cells a tunnelling enemy digs along from `from` to `to`, ending on `to`.
static func trail_cells(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var steps := maxi(absi(to.x - from.x), absi(to.y - from.y))
	for i in range(1, steps + 1):
		var c := Vector2i(roundi(lerpf(from.x, to.x, float(i) / steps)), roundi(lerpf(from.y, to.y, float(i) / steps)))
		if out.is_empty() or out[-1] != c:
			out.append(c)
	if out.is_empty():
		out.append(to)
	return out


static func _erupt(s: GameState, u: Unit) -> void:
	var cell: Vector2i = u.status.emerge_cell
	u.status.erase("emerge_cell")
	u.status.erase("burrowed")
	if s.unit_at(cell) != null and s.unit_at(cell) != u or not s.grid.is_walkable(cell):
		cell = Encounter.free_cell(s, cell)
	var from := u.pos
	var trail := trail_cells(from, cell)
	u.status.erase("trail")
	u.pos = cell
	s.emit({"type": "move", "unit": u.id, "from": from, "path": trail, "tunnel": true})
	Encounter.reveal(s, u)
	var cells := square(s.grid, cell, 1)
	var victims: Array[Unit] = []
	for t in s.living():
		if t != u and cells.has(t.pos):
			victims.append(t)
	s.emit({"type": "ability", "unit": u.id, "ability": "erupt", "cell": cell, "cells": cells,
		"units": victims.map(func(x: Unit) -> int: return x.id), "damage": ERUPT_DAMAGE})
	var smashed := {}
	for c in cells:
		if s.grid.tile(c) == Types.Tile.LOW:
			smashed[c] = 1
	Destruction.hit(s, smashed, u)
	for t in victims:
		Rules.deal_damage(s, t, ERUPT_DAMAGE, u)
	EnemyTerrain.collapse(s, cells, u)


## Bloater / Broodling burst. Kills the burster. Also used for the death burst.
static func burst(s: GameState, u: Unit) -> void:
	u.status["burst"] = true
	u.status.erase("swelling")
	var small := u.kind == "broodling"
	var dmg := BROODLING_BURST_DAMAGE if small else BURST_DAMAGE
	var cells := square(s.grid, u.pos, 1)
	var victims: Array[Unit] = []
	for t in s.living():
		if t != u and cells.has(t.pos):
			victims.append(t)
	s.emit({"type": "ability", "unit": u.id, "ability": "burst", "cell": u.pos, "cells": cells,
		"units": victims.map(func(x: Unit) -> int: return x.id), "damage": dmg})
	if u.is_alive():
		u.hp = 0
		s.emit({"type": "died", "unit": u.id})
		Encounter.on_died(s, u)
	for t in victims:
		Rules.deal_damage(s, t, dmg, u)
		if not small and t.is_alive() and t.team == Types.Team.PLAYER:
			Infection.add(s, t, BURST_INFECTION)
	if not small:
		Encounter.add_spores(s, cells, SPORE_TURNS, u)


## Free cell next to `t` (in melee reach: same level or a stair step) the Lurker can reach this
## move, closest first; (-1, -1) if none.
static func pounce_cell(s: GameState, u: Unit, t: Unit) -> Vector2i:
	var reach := Rules.move_range(s, u)
	var best := Vector2i(-1, -1)
	var best_steps := 1 << 20
	for d in Grid.DIRS8:
		var c: Vector2i = t.pos + d
		if reach.has(c) and int(reach[c]) < best_steps and s.grid.melee_reach(c, t.pos):
			best = c
			best_steps = reach[c]
	return best


static func _pounce(s: GameState, u: Unit, t: Unit) -> void:
	if not s.grid.melee_reach(u.pos, t.pos):
		var cell := pounce_cell(s, u, t)
		var path := s.grid.find_path(u.pos, cell, s.occupied(u.id))
		var from := u.pos
		Rules.open_doors_along(s, from, path, u)
		u.pos = cell
		s.emit({"type": "move", "unit": u.id, "from": from, "path": path})
	Encounter.reveal(s, u)
	var dmg := s.rng.randi_range(u.damage.x, u.damage.y)
	s.emit({"type": "ability", "unit": u.id, "ability": "pounce", "target": t.id, "hit": true, "damage": dmg})
	Rules.deal_damage(s, t, dmg, u)
	if t.is_alive() and u.is_alive() and t.team == Types.Team.PLAYER:
		t.status["pinned_by"] = u.id
		t.status["pinned_at"] = s.turn
		u.status["pinning"] = t.id
		t.overwatch = false
		t.hunkered = false
		t.actions_left = 0
		s.emit({"type": "pinned", "unit": t.id, "by": u.id})


static func _maul(s: GameState, u: Unit) -> void:
	var t := s.get_unit(u.status.pinning)
	s.emit({"type": "ability", "unit": u.id, "ability": "maul", "target": t.id, "hit": true, "damage": MAUL_DAMAGE})
	Rules.deal_damage(s, t, MAUL_DAMAGE, u)


static func _scream(s: GameState, u: Unit) -> void:
	var buffed: Array[int] = []
	for o in s.living(u.team):
		if o != u and not EnemyRoster.is_static(o) and u.pos.distance_to(o.pos) <= SCREAM_RADIUS:
			Encounter.frenzy(s, o)
			buffed.append(o.id)
	s.emit({"type": "ability", "unit": u.id, "ability": "scream", "units": buffed})
	Grafts.jam(s, u, SCREAM_RADIUS)   # the scream jams soldiers' Machine parts
	for o in s.living(u.team):
		EnemyAI.alert(s, o)


static func _flashbang(s: GameState, u: Unit, cell: Vector2i) -> void:
	var cells := square(s.grid, cell, 1)
	var hit: Array[int] = []
	for t in s.living():
		if cells.has(t.pos) and u.is_enemy_of(t):
			t.overwatch = false
			t.status.erase("ow_until")
			t.hunkered = false
			t.status.erase("hunker_until")
			hit.append(t.id)
	s.emit({"type": "ability", "unit": u.id, "ability": "flashbang", "cell": cell, "cells": cells, "units": hit})


## Living soldier with the most Infection (nearest breaks ties), or null.
static func pull_target(s: GameState, u: Unit) -> Unit:
	var best: Unit = null
	for t in s.living():
		if not u.is_enemy_of(t) or t.status.get("turned", false):
			continue
		if best == null or t.infection > best.infection \
				or (t.infection == best.infection and _cheb(t.pos, u.pos) < _cheb(best.pos, u.pos)):
			best = t
	return best


static func _pull(s: GameState, u: Unit) -> void:
	u.status["pull_turn"] = s.turn
	var t := pull_target(s, u)
	s.emit({"type": "ability", "unit": u.id, "ability": "pull", "target": t.id})
	var path: Array[Vector2i] = []
	var c := t.pos
	var occ := s.occupied(t.id)
	for i in PULL_STEPS:
		var best := c
		for d in Grid.DIRS8:
			var n: Vector2i = c + d
			if not s.grid.is_walkable(n) or occ.has(n):
				continue
			if d.x != 0 and d.y != 0 and not (s.grid.is_walkable(c + Vector2i(d.x, 0)) and s.grid.is_walkable(c + Vector2i(0, d.y))):
				continue
			if not s.grid.touching(c, n):
				continue
			if n.distance_squared_to(u.pos) < best.distance_squared_to(u.pos):
				best = n
		if best == c:
			break
		c = best
		path.append(c)
	if not path.is_empty():
		var from := t.pos
		t.pos = c
		t.hunkered = false
		s.emit({"type": "move", "unit": t.id, "from": from, "path": path})


## A whole row or column through `cell`, without the cells right around the Source.
static func slam_line(s: GameState, u: Unit, cell: Vector2i, axis: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n := s.grid.width if axis == "row" else s.grid.height
	for i in n:
		var c := Vector2i(i, cell.y) if axis == "row" else Vector2i(cell.x, i)
		if s.grid.tile(c) != Types.Tile.WALL and _cheb(c, u.pos) > 1:
			out.append(c)
	return out


# --- helpers -------------------------------------------------------------------------------

## Bosses and fixed enemies (nests, sacs, emplacements) can't be shoved off their spot.
static func immovable(t: Unit) -> bool:
	return EnemyRoster.is_boss(t) or UnitData.ENEMIES.get(t.kind, {}).get("static", false)


## Pushes `t` up to `steps` tiles along `dir` while the way is open floor. Emits a move event.
static func knockback(s: GameState, t: Unit, dir: Vector2i, steps: int) -> void:
	if immovable(t):
		return
	var path: Array[Vector2i] = []
	var c := t.pos
	var occ := s.occupied(t.id)
	for i in steps:
		var n := c + dir
		if not s.grid.is_walkable(n) or occ.has(n) or EnemyTerrain.level(s, n) > EnemyTerrain.level(s, c):
			break   # a knock stops against a wall, a unit, or a step up
		if dir.x != 0 and dir.y != 0 and not (s.grid.is_walkable(c + Vector2i(dir.x, 0)) and s.grid.is_walkable(c + Vector2i(0, dir.y))):
			break
		if not s.grid.touching(c, n):
			break
		c = n
		path.append(c)
	if path.is_empty():
		return
	var from := t.pos
	t.pos = c
	t.hunkered = false
	s.emit({"type": "move", "unit": t.id, "from": from, "path": path, "knockback": true})
	Encounter.check_pins(s)
	var fall := EnemyTerrain.fall_damage(s, from, c)
	if fall > 0:
		s.emit({"type": "fell", "unit": t.id, "damage": fall})
		Rules.deal_damage(s, t, fall, null)


## In-bounds, non-wall cells within `r` (Chebyshev) of `c`.
static func square(g: Grid, c: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var n := c + Vector2i(dx, dy)
			if g.in_bounds(n) and g.tile(n) != Types.Tile.WALL:
				out.append(n)
	return out


static func set_tile(g: Grid, c: Vector2i, tile: int) -> void:
	g.tiles[c.y * g.width + c.x] = tile


static func _step_dir(from: Vector2i, to: Vector2i) -> Vector2i:
	return Vector2i(signi(to.x - from.x), signi(to.y - from.y))


static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
