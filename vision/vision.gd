class_name Vision
extends RefCounted
## Fog of war: what the squad can see. Pure rules, like Combat; the view only reads it.
## OWNER: fog of war workstream. See "Fog of war" in docs/ARCHITECTURE.md.
##
## The squad shares one vision. A cell is visible when any living squad unit (soldiers,
## deployables; not Lapsed soldiers) is within its sight radius of it and has line of sight
## (Combat.can_see, so walls block and soldiers lean out of cover). Enemies outside that
## vision are hidden from the players but keep acting normally. Enemy rules are unchanged:
## the AI keeps its own activation and targeting.
##
## State lives in `GameState.vision` (saved, synced and checksummed like the rest):
##   "explored": PackedByteArray, 1 per cell the squad has ever seen (row-major)
##   "exposed":  {unit id: phase index}  attackers stay visible until then (firing gives you away)
##   "last_seen": {unit id: Vector2i}    where an enemy was when the squad last saw it
##   "blips":    {unit id: {"cell", "until"}}  Motion tracker contacts (position only)
##   "reveals":  [{"cell", "radius", "until"}]  areas seen from above (Recon drone), until -1 = fight
##   "off":      true turns fog off for this fight (dev aid, old tests)
## Everything here only reads `state.rng`-free data, so every peer computes the same vision.

const SOLDIER_SIGHT := 8
const ENEMY_SIGHT := 8
## Per-kind sight radius overrides.
const KIND_SIGHT := {"marksman": 10, "turret": 6, "decoy": 0}
const HIGH_GROUND_BONUS := 2
## An attacker is visible for this many half-turns (an enemy that shoots in the enemy phase
## stays visible through the next squad phase).
const EXPOSE_PHASES := 2
const DRONE_RADIUS := 6
const DRONE_RANGE := 10.0
## Motion tracker range per Mk.
const TRACKER_RANGE := [8.0, 12.0]
## Spore Sense: infected enemies within this many tiles are sensed through walls.
const SENSE_RADIUS := 6

const UNEXPLORED := 0
const EXPLORED := 1
const VISIBLE := 2


static func enabled(s: GameState) -> bool:
	return not s.vision.get("off", false)


## Turns fog off for this fight (tests of other modules, dev aid). Everything is visible.
static func disable(s: GameState) -> void:
	s.vision["off"] = true


# --- Sight ---------------------------------------------------------------------------------

## Height of the ground under `u`: 0 on flat maps (Grid.level from the map workstream, or the
## Elevation module's height, which counts flying units as 1).
static func height(s: GameState, u: Unit) -> int:
	var h: Variant = RunHooks.call_static("Elevation", "height", [s, u], null)
	if h != null:
		return int(h)
	return EnemyTerrain.level(s, u.pos)


## Sight radius in tiles: kind base, +2 on high ground, plus `status["sight_bonus"]` (perks, gear).
static func sight(s: GameState, u: Unit) -> int:
	var r: int = KIND_SIGHT.get(u.kind, SOLDIER_SIGHT if u.team == Types.Team.PLAYER else ENEMY_SIGHT)
	if u.status.has("deployable"):
		r = KIND_SIGHT.get(str(u.status.deployable), r)
	if r <= 0:
		return 0
	if height(s, u) > 0:
		r += HIGH_GROUND_BONUS
	return r + int(u.status.get("sight_bonus", 0))


## True if `u` adds to its team's vision.
static func is_source(u: Unit, team: int) -> bool:
	return u.is_alive() and u.team == team and not u.status.get("lapsed", false)


## True if `u` itself sees cell `c` (sight radius and line of sight).
static func unit_sees_cell(s: GameState, u: Unit, c: Vector2i, radius: int = -1) -> bool:
	var r := sight(s, u) if radius < 0 else radius
	return u.pos.distance_to(c) <= r and Combat.can_see(s, u.pos, c)


static func _revealed(s: GameState, c: Vector2i) -> bool:
	var now := Combat.phase_index(s)
	for rv in s.vision.get("reveals", []):
		if (int(rv.until) < 0 or now < int(rv.until)) and Vector2i(rv.cell).distance_to(c) <= float(rv.radius):
			return true
	return false


## True if team `team` sees cell `c` right now. Cheap: one line-of-sight check per squad unit.
static func cell_visible(s: GameState, team: int, c: Vector2i) -> bool:
	if not enabled(s):
		return true
	if team == Types.Team.PLAYER and _revealed(s, c):
		return true
	for u in s.units:
		if is_source(u, team) and unit_sees_cell(s, u, c):
			return true
	return false


## True if team `team` can see unit `t`: their own units, exposed attackers, and anything on a
## visible cell. Hidden units (a Lurker lying in wait, a Burrower underground) are never seen.
static func sees_unit(s: GameState, team: int, t: Unit) -> bool:
	if t == null or not t.is_alive():
		return false
	if t.team == team:
		return true
	if t.status.get("hidden", false):
		return false
	if not enabled(s):
		return true
	if is_exposed(s, t):
		return true
	return cell_visible(s, team, t.pos)


static func is_exposed(s: GameState, t: Unit) -> bool:
	var until: Variant = s.vision.get("exposed", {}).get(t.id)
	return until != null and Combat.phase_index(s) < int(until)


## Every cell team `team` sees, as a set {Vector2i: true}.
static func visible_cells(s: GameState, team: int = Types.Team.PLAYER) -> Dictionary:
	var out := {}
	var g := s.grid
	if not enabled(s):
		for y in g.height:
			for x in g.width:
				out[Vector2i(x, y)] = true
		return out
	for u in s.units:
		if not is_source(u, team):
			continue
		var r := sight(s, u)
		for y in range(maxi(0, u.pos.y - r), mini(g.height, u.pos.y + r + 1)):
			for x in range(maxi(0, u.pos.x - r), mini(g.width, u.pos.x + r + 1)):
				var c := Vector2i(x, y)
				if not out.has(c) and unit_sees_cell(s, u, c, r):
					out[c] = true
	if team == Types.Team.PLAYER:
		var now := Combat.phase_index(s)
		for rv in s.vision.get("reveals", []):
			if int(rv.until) >= 0 and now >= int(rv.until):
				continue
			var rc: Vector2i = rv.cell
			var rr := int(rv.radius)
			for y in range(maxi(0, rc.y - rr), mini(g.height, rc.y + rr + 1)):
				for x in range(maxi(0, rc.x - rr), mini(g.width, rc.x + rr + 1)):
					if rc.distance_to(Vector2i(x, y)) <= rr:
						out[Vector2i(x, y)] = true
	return out


## Per-cell fog for the view: UNEXPLORED / EXPLORED / VISIBLE, row-major.
static func fog_grid(s: GameState) -> PackedByteArray:
	var g := s.grid
	var out := PackedByteArray()
	out.resize(g.width * g.height)
	if not enabled(s):
		out.fill(VISIBLE)
		return out
	var ex := explored(s)
	for i in out.size():
		out[i] = EXPLORED if i < ex.size() and ex[i] != 0 else UNEXPLORED
	for c in visible_cells(s):
		out[c.y * g.width + c.x] = VISIBLE
	return out


static func explored(s: GameState) -> PackedByteArray:
	return s.vision.get("explored", PackedByteArray())


static func is_explored(s: GameState, c: Vector2i) -> bool:
	if not enabled(s):
		return true
	var ex := explored(s)
	var i := c.y * s.grid.width + c.x
	return s.grid.in_bounds(c) and i < ex.size() and ex[i] != 0


## Enemies the squad sees, by id.
static func visible_enemies(s: GameState, team: int = Types.Team.PLAYER) -> Array[int]:
	var out: Array[int] = []
	for u in s.living():
		if u.team != team and sees_unit(s, team, u):
			out.append(u.id)
	return out


# --- Senses (Spore Sense, Motion tracker, last known positions) -----------------------------

## Spore Sense radius of `u`: `status["sense_radius"]` (set by Progression while the mutation
## is awake), 0 if it has none.
static func sense_radius(u: Unit) -> int:
	return int(u.status.get("sense_radius", 0))


static func _infected(u: Unit) -> bool:
	return u.status.get("turned", false) or EnemyRoster.infects(u)


## Infected enemies some squad member senses through walls but the squad can't see: shown as
## ghost outlines (their intents too). Not targetable: shots still need sight.
static func sensed(s: GameState, team: int = Types.Team.PLAYER) -> Array[int]:
	var out: Array[int] = []
	if not enabled(s):
		return out
	for t in s.living():
		if t.team == team or not _infected(t) or t.status.get("hidden", false) or sees_unit(s, team, t):
			continue
		for u in s.units:
			if is_source(u, team) and sense_radius(u) > 0 and u.pos.distance_to(t.pos) <= sense_radius(u):
				out.append(t.id)
				break
	return out


static func is_sensed(s: GameState, t: Unit, team: int = Types.Team.PLAYER) -> bool:
	return sensed(s, team).has(t.id)


## Motion tracker contacts the squad isn't looking at: {unit id: Vector2i}.
static func blips(s: GameState) -> Dictionary:
	var out := {}
	var now := Combat.phase_index(s)
	for id in s.vision.get("blips", {}):
		var b: Dictionary = s.vision.blips[id]
		var u := s.get_unit(int(id))
		if u != null and u.is_alive() and now < int(b.until) and not sees_unit(s, Types.Team.PLAYER, u):
			out[int(id)] = b.cell
	return out


## Last known positions of enemies out of sight: {unit id: Vector2i}.
static func last_seen(s: GameState) -> Dictionary:
	var out := {}
	for id in s.vision.get("last_seen", {}):
		var u := s.get_unit(int(id))
		if u != null and u.is_alive() and not sees_unit(s, Types.Team.PLAYER, u):
			out[int(id)] = s.vision.last_seen[id]
	return out


# --- Overwatch -----------------------------------------------------------------------------

## True if overwatcher `w` reacts to `mover` stepping onto `cell`: the cell must be inside the
## watcher's own sight radius (+ Rangefinder) and line of sight. Hidden movers never trigger it.
static func overwatch_sees(s: GameState, w: Unit, mover: Unit, cell: Vector2i) -> bool:
	if mover.status.get("hidden", false):
		return false
	var r := sight(s, w) + GearFx.overwatch_range_bonus(w)
	if not enabled(s):
		r = maxi(r, int(Combat.SIGHT_RANGE))
	return unit_sees_cell(s, w, cell, r)


# --- Rules hooks (state changes; called from Rules / Combat / GearFx) ------------------------

## Brings the stored vision up to date: explores what the squad sees now, records enemy
## positions, drops expired exposure and blips. Called by Rules after every action and phase.
static func refresh(s: GameState) -> void:
	if not enabled(s) or s.grid == null:
		return
	var g := s.grid
	var ex := explored(s)
	if ex.size() != g.width * g.height:
		ex = PackedByteArray()
		ex.resize(g.width * g.height)
	var vis := visible_cells(s)
	for c in vis:
		ex[c.y * g.width + c.x] = 1
	s.vision["explored"] = ex
	var now := Combat.phase_index(s)
	var exposed: Dictionary = s.vision.get("exposed", {})
	for id in exposed.keys():
		if now >= int(exposed[id]):
			exposed.erase(id)
	var blip: Dictionary = s.vision.get("blips", {})
	for id in blip.keys():
		if now >= int(blip[id].until):
			blip.erase(id)
	var reveals: Array = s.vision.get("reveals", [])
	s.vision["reveals"] = reveals.filter(func(rv): return int(rv.until) < 0 or now < int(rv.until))
	var seen: Dictionary = s.vision.get("last_seen", {})
	for id in seen.keys():
		var u := s.get_unit(int(id))
		if u == null or not u.is_alive() or (vis.has(seen[id]) and not sees_unit(s, Types.Team.PLAYER, u)):
			seen.erase(id)   # dead, or the squad looked there and it's gone
	for u in s.living():
		if u.team != Types.Team.PLAYER and sees_unit(s, Types.Team.PLAYER, u):
			seen[u.id] = u.pos
	s.vision["last_seen"] = seen


## One step of a move (Rules._do_move): a soldier explores as it walks; an enemy moving in the
## enemy phase pings Motion trackers in range and updates its last known position if seen.
static func on_step(s: GameState, u: Unit) -> void:
	if not enabled(s):
		return
	if is_source(u, Types.Team.PLAYER):
		var g := s.grid
		var ex := explored(s)
		if ex.size() != g.width * g.height:
			ex = PackedByteArray()
			ex.resize(g.width * g.height)
		var r := sight(s, u)
		for y in range(maxi(0, u.pos.y - r), mini(g.height, u.pos.y + r + 1)):
			for x in range(maxi(0, u.pos.x - r), mini(g.width, u.pos.x + r + 1)):
				var i := y * g.width + x
				if ex[i] == 0 and unit_sees_cell(s, u, Vector2i(x, y), r):
					ex[i] = 1
		s.vision["explored"] = ex
		return
	if u.team == Types.Team.PLAYER:
		return
	if sees_unit(s, Types.Team.PLAYER, u):
		var seen: Dictionary = s.vision.get("last_seen", {})
		seen[u.id] = u.pos
		s.vision["last_seen"] = seen
	if s.phase != Types.Phase.ENEMY:
		return
	for w in s.living(Types.Team.PLAYER):
		var m := GearFx.mk(w, "motion_tracker")
		if m > 0 and w.pos.distance_to(u.pos) <= TRACKER_RANGE[clampi(m, 1, 2) - 1]:
			var blip: Dictionary = s.vision.get("blips", {})
			blip[u.id] = {"cell": u.pos, "until": Combat.phase_index(s) + 2}
			s.vision["blips"] = blip
			return


## `u` attacked: it gives its position away until the end of the other side's next phase.
static func expose(s: GameState, u: Unit) -> void:
	if u == null or not u.is_alive() or u.team == Types.Team.PLAYER and not u.status.get("lapsed", false):
		return
	if u.status.get("hidden", false):
		return
	var exposed: Dictionary = s.vision.get("exposed", {})
	exposed[u.id] = maxi(int(exposed.get(u.id, 0)), Combat.phase_index(s) + EXPOSE_PHASES)
	s.vision["exposed"] = exposed
	var seen: Dictionary = s.vision.get("last_seen", {})
	seen[u.id] = u.pos
	s.vision["last_seen"] = seen


## An area seen from above (Recon drone): every cell within `radius` of `cell`, walls or not,
## for `phases` half-turns (-1 = the rest of the fight).
static func add_reveal(s: GameState, cell: Vector2i, radius: int, phases: int = -1) -> void:
	var list: Array = s.vision.get("reveals", [])
	list.append({"cell": cell, "radius": radius, "until": -1 if phases < 0 else Combat.phase_index(s) + phases})
	s.vision["reveals"] = list
	s.emit({"type": "revealed_area", "cell": cell, "radius": radius})
	refresh(s)
