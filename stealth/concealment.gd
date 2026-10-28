class_name Concealment
extends RefCounted
## XCOM-style squad concealment. Most fights start with the squad Concealed: the Infected are
## dormant or on patrol and nobody has seen you yet. Pure rules code. State lives in
## `s.encounter["concealment"]` = {"on": bool, "lost_turn": int, "cause": String}, so it is in
## every snapshot and lockstep peers always agree. See docs/ARCHITECTURE.md, "Concealment".
##
## Concealment is a per-mission option: FightBuilder sets encounter "concealed" (off for Ambush
## nodes, Hold the beacon and boss fights, and Story.setup_echo turns it off for Echo fights).
## Fights without an encounter (dev missions, most tests) never start concealed.
##
## It breaks, for the whole squad, the moment any of these happens (`cause`):
##   spotted    one of ours is within detect_radius of a dormant Infected that can see them;
##              checked on every step either side takes and at the start of each enemy's turn
##   fired      a soldier attacks or damages an enemy (missed shots count)
##   attacked   an enemy damages one of ours (a Lurker's pounce, an Echo)
##   explosion  a barrel, charge or grenade goes off (Destruction.noise)
##   signal     the evac flare goes up (Objectives, extract)
##   alerted    an Infected wakes for any other reason (a hidden Lurker found, a scream)
## It emits {"type": "concealment_lost", "cause", "unit" (spotter or target, -1), "by" (ours, -1)}
## and wakes that enemy and its pod.
##
## While concealed, dormant Infected patrol near where they started and new spawns arrive
## dormant. Shots on an unaware enemy get the AMBUSH_AIM bonus, and so do reaction shots in the
## enemy phase of the turn concealment broke: "everyone on overwatch, then open fire" pays off.

const DETECT_RADIUS := 4.0
const HUSH_RADIUS := 2.0      # Hive Hush: the Infected take you for one of their own
const AMBUSH_AIM := 15
const PATROL_CHANCE := 0.6
const PATROL_STEP := 3        # tiles per patrol move
const PATROL_RADIUS := 5.0    # how far a patrol strays from where the enemy started
const CAUSES := ["spotted", "fired", "attacked", "explosion", "alerted", "signal"]


## Called by Encounter.setup. `enc.concealed` turns concealment on for this fight.
static func setup(s: GameState, enc: Dictionary) -> void:
	if not enc.get("concealed", false):
		return
	s.encounter["concealment"] = {"on": true, "lost_turn": -1, "cause": ""}
	for u in s.living(Types.Team.ENEMY):
		if not EnemyRoster.is_static(u):
			u.status["patrol_home"] = u.pos


static func active(s: GameState) -> bool:
	return s.encounter.get("concealment", {}).get("on", false)


## True if this fight started concealed (whether or not it still is).
static func used(s: GameState) -> bool:
	return s.encounter.has("concealment")


## The turn concealment broke (-1 if it hasn't, or the fight never had it).
static func lost_turn(s: GameState) -> int:
	return int(s.encounter.get("concealment", {}).get("lost_turn", -1))


## Turns concealment off before the fight starts, without an event (Echo fights).
static func disable(s: GameState) -> void:
	s.encounter.erase("concealment")


## Breaks concealment. `enemy` (if any) and its pod wake up.
static func lose(s: GameState, cause: String, enemy: Unit = null, ours: Unit = null) -> void:
	if not active(s):
		return
	var c: Dictionary = s.encounter.concealment
	c["on"] = false
	c["lost_turn"] = s.turn
	c["cause"] = cause
	s.emit({"type": "concealment_lost", "cause": cause, "unit": enemy.id if enemy != null else -1,
		"by": ours.id if ours != null else -1})
	if enemy != null and enemy.team == Types.Team.ENEMY:
		EnemyAI.alert(s, enemy)


# --- detection -------------------------------------------------------------------------------

## Can dormant `watcher` spot `h` right now? Only Infected that patrol can (not spawners, nests
## or Lurkers lying in wait).
static func detects(s: GameState, watcher: Unit, h: Unit) -> bool:
	if not watcher.is_alive() or not h.is_alive() or not watcher.is_enemy_of(h):
		return false
	if EnemyAI.is_alerted(watcher) or EnemyRoster.is_static(watcher) or watcher.status.get("hidden", false):
		return false
	if not UnitData.ENEMIES.has(watcher.kind):
		return false
	if GearFx.in_smoke(s, h):
		return false
	var r := HUSH_RADIUS if Kit.awake(h, "hive_hush") else DETECT_RADIUS
	return watcher.pos.distance_to(h.pos) <= r and Combat.can_see(s, watcher.pos, h.pos)


## Cells where one of ours would be spotted by a dormant enemy in `watchers` (the view passes
## only the enemies the squad can see, so this never leaks what is under the fog).
static func danger_cells(s: GameState, watchers: Array) -> Dictionary:
	var out := {}
	var fields := sight_fields(s, watchers)
	for id in fields:
		out.merge(fields[id].cells)
	return out


## Each dormant watcher's own detection area: {enemy id: {"cells": {cell: true}, "at": pos}}.
## Walkable cells within DETECT_RADIUS it has line of sight to (walls, map edges and high ground
## carve it), minus smoke. Awake, static and hidden enemies have none.
static func sight_fields(s: GameState, watchers: Array) -> Dictionary:
	var out := {}
	var r := int(DETECT_RADIUS)
	for w: Unit in watchers:
		if not w.is_alive() or EnemyAI.is_alerted(w) or EnemyRoster.is_static(w) or w.status.get("hidden", false):
			continue
		if not UnitData.ENEMIES.has(w.kind):
			continue
		var cells := {}
		for y in range(w.pos.y - r, w.pos.y + r + 1):
			for x in range(w.pos.x - r, w.pos.x + r + 1):
				var c := Vector2i(x, y)
				if s.grid.in_bounds(c) and w.pos.distance_to(c) <= DETECT_RADIUS and c != w.pos \
						and s.grid.is_walkable(c) and Combat.can_see(s, w.pos, c) \
						and Hazards.at(s, c).get("kind", "") != "smoke":
					cells[c] = true
		if not cells.is_empty():
			out[w.id] = {"cells": cells, "at": w.pos}
	return out


## Checked on every step a unit takes (Rules.move_along, which flushes the walk so far and
## then calls lose): ours walking into sight, or a patrol walking into view of ours.
## Returns [spotter, spotted], or [] when nobody is seen.
static func spotter(s: GameState, u: Unit) -> Array:
	if not active(s):
		return []
	if u.team == Types.Team.PLAYER:
		for e in s.living(Types.Team.ENEMY):
			if detects(s, e, u):
				return [e, u]
	else:
		for h in s.living(Types.Team.PLAYER):
			if detects(s, u, h):
				return [u, h]
	return []


## Start of a dormant enemy's turn (EnemyAI): has it spotted anyone?
static func scan(s: GameState, u: Unit) -> bool:
	for h in s.living(Types.Team.PLAYER):
		if detects(s, u, h):
			lose(s, "spotted", u, h)
			return true
	return false


# --- hooks -------------------------------------------------------------------------------------

## After a squad action (Rules.apply): any attack on an enemy gives the squad away.
static func after_action(s: GameState, u: Unit, action: Dictionary) -> void:
	if not active(s) or u.team != Types.Team.PLAYER:
		return
	if action.type != Types.SHOOT and action.type != Types.ABILITY:
		return
	var t := s.get_unit(action.get("target", -1))
	if t != null and u.is_enemy_of(t):
		lose(s, "fired", t, u)
	elif Rules.EXPOSING_CELL_ABILITIES.has(str(action.get("ability", ""))):
		lose(s, "fired", null, u)


## Rules.deal_damage: any hit between the squad and the Infected.
static func on_damage(s: GameState, target: Unit, source: Unit) -> void:
	if not active(s) or source == null or not source.is_enemy_of(target):
		return
	if source.team == Types.Team.PLAYER:
		lose(s, "fired", target, source)
	else:
		lose(s, "attacked", source, target)


## EnemyAI.alert: an Infected woke for some other reason.
static func on_alert(s: GameState, u: Unit) -> void:
	if active(s):
		lose(s, "alerted", u)


## Destruction.noise: explosions carry.
static func on_noise(s: GameState) -> void:
	if active(s):
		lose(s, "explosion")


## Hit-chance term (Combat.hit_chance): the target hasn't seen it coming.
static func odds_terms(s: GameState, attacker: Unit, target: Unit, reaction: bool, breakdown: Array) -> void:
	if attacker.team != Types.Team.PLAYER or target.team != Types.Team.ENEMY:
		return
	if active(s) and not EnemyAI.is_alerted(target):
		breakdown.append(["Unaware", AMBUSH_AIM])
	elif reaction and s.phase == Types.Phase.ENEMY and lost_turn(s) == s.turn:
		breakdown.append(["Ambush shot", AMBUSH_AIM])


# --- patrols ---------------------------------------------------------------------------------

## A dormant enemy's turn while the squad is concealed: wander near home, a few tiles at a time.
## Each step can spot the squad (on_step). Uses s.rng, so every peer moves it the same way.
static func patrol(s: GameState, u: Unit) -> void:
	if EnemyRoster.is_static(u) or s.rng.randf() >= PATROL_CHANCE:
		return
	var home: Vector2i = u.status.get("patrol_home", u.pos)
	var cells: Array = []
	for c in s.grid.reachable(u.pos, mini(u.mobility, PATROL_STEP), s.occupied(u.id)).keys():
		if c != u.pos and Vector2(c).distance_to(Vector2(home)) <= PATROL_RADIUS:
			cells.append(c)
	if cells.is_empty():
		return
	var action := {"type": Types.MOVE, "unit": u.id, "to": cells[s.rng.randi_range(0, cells.size() - 1)]}
	if Rules.validate(s, action) == "":
		Rules.apply(s, action)


# --- text --------------------------------------------------------------------------------------

## Why concealment broke, for banners and the field log.
static func cause_text(cause: String, enemy_name := "") -> String:
	match cause:
		"spotted": return "Spotted by %s" % enemy_name if enemy_name != "" else "Spotted"
		"fired": return "The squad opened fire"
		"attacked": return "Under attack"
		"explosion": return "The blast was heard"
		"signal": return "The flare lit up the area"
	return "The Infected are awake"
