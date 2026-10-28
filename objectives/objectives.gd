class_name Objectives
extends RefCounted
## Fight objectives and their win/lose rules (design doc: Mission objectives). Pure rules code.
##
## The objective comes from the map (`grid.objective`, set by MapGen) and its cells from
## `grid.markers`. Progress lives in `GameState.objective` (serialized). A fight ends the moment its
## objective is met. Rules calls setup / on_team_phase_end / on_enemy_phase_end / check, and the
## run framework calls bonus_met. See docs/ARCHITECTURE.md, "Objectives".
##
##   skirmish, elite, boss: kill every enemy.
##   extract: every living soldier on the evac zone at the end of a squad turn. After turn
##            EXTRACT_TURNS the dropship leaves: soldiers off the pad are lost.
##   hold:    survive HOLD_TURNS rounds; lost once enemies have stood in the beacon zone with no
##            soldier on it at the end of HOLD_OVERRUN_ROUNDS rounds in a row. The first such round
##            only warns (a `beacon_overrun` event) and doesn't count as held, so the squad always
##            gets a turn to retake it.
##   rescue:  civilians are moved by the players (move only, any player); win when every living civilian has reached the
##            exit (the drop zone). If every civilian dies, killing every enemy wins instead.
##   purge:   destroy every spore nest (units of kind NEST_KIND), or kill every enemy.
##   escort:  a courier starts with the squad; any player can move it (move only) to the evac zone. Lost if it dies.
##   demolish: stand on a charge site at the end of a squad turn to arm it. An armed charge blows
##            CHARGE_FUSE rounds later (a demo blast, soldiers in it are hurt too); an enemy standing on
##            it defuses it. Won when every charge has blown, lost after DEMOLISH_TURNS rounds.
##   hack:    a soldier on a relay for HACK_TURNS squad turns in a row hacks it. An enemy ending a round
##            on an unhacked relay with no soldier there destroys it. Won at HACK_NEED hacked, lost when
##            too few relays are left to reach that.
##   samples: step on a sample at the end of a squad turn to pick it up (the carrier loses SAMPLE_SLOW
##            move), end a squad turn on the drop zone to hand it in. A carrier's death drops it; an
##            enemy ending a round on a loose sample destroys it. Won at SAMPLES_NEED delivered, lost
##            when too few are left.

const EXTRACT_TURNS := 8           # one more than the old 7: the evac zone sits farther out on the bigger maps
const HOLD_TURNS := 4
const HOLD_OVERRUN_ROUNDS := 2  # rounds in a row the enemy can own the beacon before it falls
const BONUS_BY_TURN := 5        # skirmish / elite / purge bonus: done by the end of this turn
const NEST_KIND := "spore_nest"
const ESCORT_HP := 8
const ESCORT_MOVE := 3          # tiles the courier can walk per move
const CHARGE_FUSE := 2          # rounds from arming to the blast
const CHARGE_BLAST := {"radius": 1, "centre": 3, "ring": 1, "damage": 3}
const DEMOLISH_TURNS := 10      # all charges must have blown by the end of this round
const HACK_TURNS := 2           # squad turns in a row on a relay
const HACK_NEED := 2            # relays that must be hacked (there are 3)
const SAMPLES_NEED := 2         # samples that must be handed in (there are 3)
const SAMPLE_SLOW := 1          # moves the carrier loses
const NEW_KINDS := ["escort", "demolish", "hack", "samples"]
const CIVILIAN := {"name": "Civilian", "max_hp": 3, "mobility": 4}

const TEXT := {
	"skirmish": "Clear the area",
	"elite": "Destroy the nest",
	"boss": "Kill the boss",
	"extract": "Reach the evac zone",
	"hold": "Hold the beacon",
	"rescue": "Escort the civilians to the drop zone",
	"purge": "Destroy the spore nests",
	"escort": "Walk the courier to the evac zone",
	"demolish": "Blow the charges",
	"hack": "Hack the relays",
	"samples": "Bring the samples to the drop zone",
}

## Why a fight was lost (Objectives.loss_cause): headline, icon, one line of detail.
const LOSS := {
	"beacon": {"title": "Beacon overrun", "icon": "flag",
		"line": "Enemies held the beacon with no soldier on it for %d rounds running." % HOLD_OVERRUN_ROUNDS},
	"left_behind": {"title": "Left behind", "icon": "clock",
		"line": "The dropship left before anyone reached the evac zone."},
	"courier_down": {"title": "Courier lost", "icon": "skull",
		"line": "The courier fell before it reached the evac zone."},
	"charges_late": {"title": "Out of time", "icon": "clock",
		"line": "The charges were not all set off in %d rounds." % DEMOLISH_TURNS},
	"relays_lost": {"title": "Relays lost", "icon": "flag",
		"line": "Too few relays were left to finish the hack."},
	"samples_lost": {"title": "Samples lost", "icon": "alert",
		"line": "Too few samples were left to bring back."},
	"turned": {"title": "The squad Turned", "icon": "turned",
		"line": "The Bloom took every soldier."},
	"squad_down": {"title": "All soldiers down", "icon": "skull",
		"line": "No soldier is left standing."},
}


static func kind(s: GameState) -> String:
	var k: String = s.grid.objective
	return k if TEXT.has(k) else "skirmish"


static func is_civilian(u: Unit) -> bool:
	return u.status.has("civilian")


## Called once when the mission is built (Rules.new_mission_on_grid): sets up progress and spawns
## the civilians of a rescue fight.
static func setup(s: GameState) -> void:
	s.objective = {"kind": kind(s), "result": Types.Result.NONE}
	match kind(s):
		"hold":
			s.objective.held = 0
			s.objective.overrun = 0
			s.objective.contested = false
		"extract":
			s.objective.left_behind = 0
		"escort":
			var courier := _spawn_courier(s)
			s.objective.courier = courier.id if courier != null else -1
			s.objective.start_dist = _courier_dist(s, courier.pos) if courier != null else 0
		"demolish":
			s.objective.charges = _fill(s.grid.marker("charge").size(), "idle")
			s.objective.fuse = _fill(s.grid.marker("charge").size(), 0)
		"hack":
			s.objective.relays = _fill(s.grid.marker("relay").size(), "idle")
			s.objective.hacking = _fill(s.grid.marker("relay").size(), 0)
		"samples":
			s.objective.samples = _fill(s.grid.marker("sample").size(), "ground")
			s.objective.carriers = _fill(s.grid.marker("sample").size(), -1)
			s.objective.where = s.grid.marker("sample").duplicate()
		"rescue":
			var ids: Array = []
			for c in s.grid.marker("civilian"):
				if s.unit_at(c) == null:
					ids.append(_spawn_civilian(s, c).id)
			s.objective.civilians = ids
			s.objective.rescued = []


static func _fill(n: int, v: Variant) -> Array:
	var a: Array = []
	a.resize(n)
	a.fill(v)
	return a


## The courier stands on the free cell nearest the drop zone's first cell.
static func _spawn_courier(s: GameState) -> Unit:
	var origin: Vector2i = s.grid.player_spawns[0] if not s.grid.player_spawns.is_empty() else Vector2i.ZERO
	var best := Vector2i(-1, -1)
	for r in range(1, 5):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := origin + Vector2i(dx, dy)
				if best.x < 0 and s.grid.in_bounds(c) and s.grid.is_walkable(c) and s.unit_at(c) == null \
						and not s.grid.player_spawns.has(c):
					best = c
		if best.x >= 0:
			break
	if best.x < 0:
		return null
	var u := _spawn_civilian(s, best)
	u.display_name = "Courier"
	u.max_hp = ESCORT_HP
	u.hp = ESCORT_HP
	u.mobility = ESCORT_MOVE
	u.status["courier"] = true
	return u


static func _spawn_civilian(s: GameState, c: Vector2i) -> Unit:
	var u := Unit.new()
	u.kind = "civilian"
	u.team = Types.Team.PLAYER
	u.display_name = CIVILIAN.name
	u.owner_player = -1          # no owner: any player can move them (Rules.validate allows MOVE only)
	u.max_hp = CIVILIAN.max_hp
	u.hp = CIVILIAN.max_hp
	u.aim = 0
	u.mobility = CIVILIAN.mobility
	u.damage = Vector2i.ZERO
	u.status["civilian"] = true
	return s.add_unit(u, c)


## Living squad soldiers: no deployables, no civilians.
static func soldiers(s: GameState) -> Array[Unit]:
	return Deployables.soldiers(s).filter(func(u: Unit) -> bool: return not is_civilian(u))


static func _civilians(s: GameState, living_only := true) -> Array[Unit]:
	var out: Array[Unit] = []
	for id in s.objective.get("civilians", []):
		var u := s.get_unit(id)
		if u != null and (u.is_alive() or not living_only):
			out.append(u)
	return out


# ---------------------------------------------------------------- hooks called by Rules

## End of the squad's turn (after hazards): extraction and rescue are checked.
static func on_team_phase_end(s: GameState) -> void:
	if s.objective.is_empty() or s.phase == Types.Phase.ENDED:
		return
	match kind(s):
		"extract": _check_extract(s)
		"rescue": _rescue_turn(s)
		"escort": _escort_turn(s)
		"demolish": _demolish_arm(s)
		"hack": _hack_turn(s)
		"samples": _samples_turn(s)


## End of a full round (after the enemy phase and hazards): the beacon is checked.
static func on_enemy_phase_end(s: GameState) -> void:
	if s.objective.is_empty() or s.phase == Types.Phase.ENDED:
		return
	match kind(s):
		"hold": _check_hold(s)
		"demolish": _demolish_round(s)
		"hack": _hack_round(s)
		"samples": _samples_round(s)


static func _check_extract(s: GameState) -> void:
	var evac := s.grid.marker("evac")
	var squad := soldiers(s)
	var on_pad := squad.filter(func(u: Unit) -> bool: return evac.has(u.pos))
	_progress(s, on_pad.size(), squad.size())
	if on_pad.size() == squad.size():
		s.objective.result = Types.Result.VICTORY
	elif s.turn >= EXTRACT_TURNS:
		# The dropship leaves: anyone not aboard is lost.
		for u in squad:
			if not on_pad.has(u):
				u.hp = 0
				u.status["left_behind"] = true
				s.objective.left_behind += 1
				s.emit({"type": "left_behind", "unit": u.id})
				s.emit({"type": "died", "unit": u.id})
		s.objective.result = Types.Result.VICTORY if not on_pad.is_empty() else Types.Result.DEFEAT


# ---------------------------------------------------------------- escort

static func courier(s: GameState) -> Unit:
	return s.get_unit(int(s.objective.get("courier", -1)))


## Steps from `from` to the nearest evac cell, walking the way a unit can (Grid.step_cost), or -1.
static func _courier_dist(s: GameState, from: Vector2i) -> int:
	var dist := _dist_to_evac(s)
	return int(dist.get(from, -1))


static func _dist_to_evac(s: GameState) -> Dictionary:
	var seen := {}
	var frontier: Array[Vector2i] = []
	for t in s.grid.marker("evac"):
		seen[t] = 0
		frontier.append(t)
	while not frontier.is_empty():
		var next: Array[Vector2i] = []
		for t in frontier:
			for d in Grid.DIRS8:
				var c: Vector2i = t - d
				if not seen.has(c) and s.grid.is_walkable(c) and s.grid.step_cost(c, d) > 0:
					seen[c] = seen[t] + 1
					next.append(c)
		frontier = next
	return seen


static func nearest_soldier_dist(s: GameState, cell: Vector2i) -> int:
	var best := 1 << 20
	for u in soldiers(s):
		best = mini(best, _cheb(u.pos, cell))
	return best


static func _escort_turn(s: GameState) -> void:
	var c := courier(s)
	if c == null or not c.is_alive():
		return
	var dist := _dist_to_evac(s)
	if not c.is_alive():
		return
	var left: int = dist.get(c.pos, 0)
	_progress(s, maxi(int(s.objective.start_dist) - left, 0), int(s.objective.start_dist))
	if s.grid.marker("evac").has(c.pos):
		s.objective.result = Types.Result.VICTORY


# ---------------------------------------------------------------- demolish

static func _soldier_on(s: GameState, cell: Vector2i) -> bool:
	var u := s.unit_at(cell)
	return u != null and u.is_alive() and u.team == Types.Team.PLAYER and not is_civilian(u) and not u.status.has("deployable")


static func _enemy_on(s: GameState, cell: Vector2i) -> bool:
	var u := s.unit_at(cell)
	return u != null and u.is_alive() and u.team == Types.Team.ENEMY


static func _demolish_arm(s: GameState) -> void:
	var cells := s.grid.marker("charge")
	for i in cells.size():
		if s.objective.charges[i] == "idle" and _soldier_on(s, cells[i]):
			s.objective.charges[i] = "armed"
			s.objective.fuse[i] = CHARGE_FUSE
			s.emit({"type": "charge_armed", "cell": cells[i], "fuse": CHARGE_FUSE})
	_demolish_progress(s)


static func _demolish_round(s: GameState) -> void:
	var cells := s.grid.marker("charge")
	for i in cells.size():
		if s.objective.charges[i] != "armed":
			continue
		if _enemy_on(s, cells[i]):
			s.objective.charges[i] = "idle"
			s.emit({"type": "charge_defused", "cell": cells[i]})
			continue
		s.objective.fuse[i] -= 1
		if s.objective.fuse[i] <= 0:
			s.objective.charges[i] = "blown"
			s.emit({"type": "charge_blown", "cell": cells[i]})
			Destruction.explode(s, cells[i], CHARGE_BLAST, null, "demo")
			if s.phase == Types.Phase.ENDED:
				return
	_demolish_progress(s)
	if s.objective.charges.all(func(v: String) -> bool: return v == "blown"):
		s.objective.result = Types.Result.VICTORY
	elif s.turn >= DEMOLISH_TURNS:
		s.objective.fail = "charges_late"
		s.objective.result = Types.Result.DEFEAT


static func _demolish_progress(s: GameState) -> void:
	_progress(s, s.objective.charges.count("blown"), s.objective.charges.size())


# ---------------------------------------------------------------- hack

static func _hack_turn(s: GameState) -> void:
	var cells := s.grid.marker("relay")
	for i in cells.size():
		if s.objective.relays[i] != "idle":
			continue
		if _soldier_on(s, cells[i]):
			s.objective.hacking[i] += 1
			if s.objective.hacking[i] >= HACK_TURNS:
				s.objective.relays[i] = "hacked"
				s.emit({"type": "relay_hacked", "cell": cells[i]})
			else:
				s.emit({"type": "relay_hacking", "cell": cells[i], "left": HACK_TURNS - s.objective.hacking[i]})
		else:
			s.objective.hacking[i] = 0
	_hack_check(s)


static func _hack_round(s: GameState) -> void:
	var cells := s.grid.marker("relay")
	for i in cells.size():
		if s.objective.relays[i] == "idle" and _enemy_on(s, cells[i]) and not _soldier_on(s, cells[i]):
			s.objective.relays[i] = "lost"
			s.emit({"type": "relay_lost", "cell": cells[i]})
	_hack_check(s)


static func _hack_check(s: GameState) -> void:
	var hacked: int = s.objective.relays.count("hacked")
	var open: int = s.objective.relays.count("idle")
	_progress(s, hacked, HACK_NEED)
	if hacked >= HACK_NEED:
		s.objective.result = Types.Result.VICTORY
	elif hacked + open < HACK_NEED:
		s.objective.fail = "relays_lost"
		s.objective.result = Types.Result.DEFEAT


# ---------------------------------------------------------------- samples

static func _samples_turn(s: GameState) -> void:
	var drop := s.grid.marker("exit")
	var n: int = s.objective.samples.size()
	for i in n:
		var st: String = s.objective.samples[i]
		var cell: Vector2i = s.objective.where[i]
		if st == "carried":
			var u := s.get_unit(int(s.objective.carriers[i]))
			if u == null or not u.is_alive():
				_drop_sample(s, i)
			elif drop.has(u.pos):
				s.objective.samples[i] = "delivered"
				u.mobility += SAMPLE_SLOW
				u.status.erase("carrying")
				s.emit({"type": "sample_delivered", "unit": u.id, "cell": u.pos})
			else:
				s.objective.where[i] = u.pos
		elif st == "ground":
			var u := s.unit_at(cell)
			if u != null and _soldier_on(s, cell) and not u.status.has("carrying"):
				s.objective.samples[i] = "carried"
				s.objective.carriers[i] = u.id
				u.mobility = maxi(1, u.mobility - SAMPLE_SLOW)
				u.status["carrying"] = i
				s.emit({"type": "sample_taken", "unit": u.id, "cell": cell})
	_samples_check(s)


static func _drop_sample(s: GameState, i: int) -> void:
	var u := s.get_unit(int(s.objective.carriers[i]))
	s.objective.samples[i] = "ground"
	s.objective.carriers[i] = -1
	if u != null:
		s.objective.where[i] = u.pos
		u.status.erase("carrying")
	s.emit({"type": "sample_dropped", "cell": s.objective.where[i]})


static func _samples_round(s: GameState) -> void:
	for i in s.objective.samples.size():
		if s.objective.samples[i] == "carried":
			var u := s.get_unit(int(s.objective.carriers[i]))
			if u == null or not u.is_alive():
				_drop_sample(s, i)
		if s.objective.samples[i] == "ground" and _enemy_on(s, s.objective.where[i]):
			s.objective.samples[i] = "lost"
			s.emit({"type": "sample_lost", "cell": s.objective.where[i]})
	_samples_check(s)


static func _samples_check(s: GameState) -> void:
	var done: int = s.objective.samples.count("delivered")
	var live: int = s.objective.samples.count("ground") + s.objective.samples.count("carried")
	_progress(s, done, SAMPLES_NEED)
	if done >= SAMPLES_NEED:
		s.objective.result = Types.Result.VICTORY
	elif done + live < SAMPLES_NEED:
		s.objective.fail = "samples_lost"
		s.objective.result = Types.Result.DEFEAT


static func _check_hold(s: GameState) -> void:
	var zone := s.grid.marker("beacon")
	var ours := soldiers(s).any(func(u: Unit) -> bool: return zone.has(u.pos))
	var theirs := s.living(Types.Team.ENEMY).any(func(u: Unit) -> bool: return zone.has(u.pos))
	if theirs:
		s.objective.contested = true
	if theirs and not ours:
		s.objective.overrun = int(s.objective.get("overrun", 0)) + 1
		if s.objective.overrun >= HOLD_OVERRUN_ROUNDS:
			s.objective.result = Types.Result.DEFEAT
		else:
			s.emit({"type": "beacon_overrun", "rounds_left": HOLD_OVERRUN_ROUNDS - s.objective.overrun})
		return   # an overrun round isn't a held one
	s.objective.overrun = 0
	s.objective.held += 1
	_progress(s, s.objective.held, HOLD_TURNS)
	if s.objective.held >= HOLD_TURNS:
		s.objective.result = Types.Result.VICTORY


static func _rescue_turn(s: GameState) -> void:
	var exit := s.grid.marker("exit")
	for c in _civilians(s):
		if s.objective.rescued.has(c.id):
			continue
		if c.is_alive() and exit.has(c.pos):
			s.objective.rescued.append(c.id)
			s.emit({"type": "rescued", "unit": c.id})
	var waiting := _civilians(s).filter(func(c: Unit) -> bool: return not s.objective.rescued.has(c.id))
	_progress(s, s.objective.rescued.size(), s.objective.civilians.size())
	if waiting.is_empty() and not s.objective.rescued.is_empty():
		s.objective.result = Types.Result.VICTORY


static func _progress(s: GameState, done: int, goal: int) -> void:
	if s.objective.get("progress", -1) == done and s.objective.get("goal", -1) == goal:
		return
	s.objective.progress = done
	s.objective.goal = goal
	s.emit({"type": "objective", "kind": kind(s), "progress": done, "goal": goal})


## The fight's result from its objective, or Types.Result.NONE while it is still on.
## Rules.check_end calls this after the squad-wiped check.
static func check(s: GameState) -> int:
	if s.objective.is_empty():
		return Types.Result.VICTORY if s.living(Types.Team.ENEMY).is_empty() else Types.Result.NONE
	if s.objective.result != Types.Result.NONE:
		return s.objective.result
	var enemies_dead := s.living(Types.Team.ENEMY).is_empty()
	match kind(s):
		"extract", "hold", "demolish", "hack", "samples":
			return Types.Result.NONE
		"escort":
			var c := courier(s)
			if c == null or not c.is_alive():
				s.objective.fail = "courier_down"
				s.objective.result = Types.Result.DEFEAT
				return Types.Result.DEFEAT
			return Types.Result.NONE
		"rescue":
			# Killing everything only wins once no civilian is left to save.
			return Types.Result.VICTORY if enemies_dead and _civilians(s).is_empty() else Types.Result.NONE
		"purge":
			# Dead units stay in s.units, so this needs no stored state.
			var nests := s.units.filter(func(u: Unit) -> bool: return u.kind == NEST_KIND)
			if not nests.is_empty() and not nests.any(func(u: Unit) -> bool: return u.is_alive()):
				return Types.Result.VICTORY
	return Types.Result.VICTORY if enemies_dead else Types.Result.NONE


## Why the fight was lost: a LOSS key, or "" when it wasn't.
static func loss_cause(s: GameState) -> String:
	if s.result != Types.Result.DEFEAT:
		return ""
	if not s.objective.is_empty() and kind(s) == "hold" and s.objective.result == Types.Result.DEFEAT:
		return "beacon"
	if not s.objective.is_empty() and s.objective.result == Types.Result.DEFEAT and s.objective.has("fail"):
		return str(s.objective.fail)
	var squad := _squad_units(s)
	if squad.any(func(u: Unit) -> bool: return u.status.get("left_behind", false)):
		return "left_behind"
	if not squad.is_empty() and squad.all(func(u: Unit) -> bool: return u.status.get("turned", false)):
		return "turned"
	return "squad_down"


## The cells the camera should look at for a loss: the beacon zone, else where the squad fell.
static func loss_cells(s: GameState) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	match loss_cause(s):
		"beacon":
			out.assign(s.grid.marker("beacon"))
			return out
		"courier_down":
			var c := courier(s)
			if c != null:
				out.append(c.pos)
				return out
		"charges_late": 
			out.assign(s.grid.marker("charge"))
			return out
		"relays_lost":
			out.assign(s.grid.marker("relay"))
			return out
		"samples_lost":
			out.assign(s.objective.get("where", []))
			return out
	for u in _squad_units(s):
		out.append(u.pos)
	return out


## Every squad soldier, living, dead or Turned (no civilians or deployables).
static func _squad_units(s: GameState) -> Array[Unit]:
	return s.units.filter(func(u: Unit) -> bool:
		return u.status.get("turned", false) or (Kit.is_soldier(u) and not is_civilian(u) and not u.status.has("deployable")))


## Whether the fight's bonus objective was met (+10 Supplies, +1 Intel in a run). Only after a win.
static func bonus_met(s: GameState) -> bool:
	if s.result != Types.Result.VICTORY or s.objective.is_empty():
		return false
	match kind(s):
		"extract": return s.objective.left_behind == 0
		"hold": return not s.objective.contested
		"rescue":
			return not s.objective.civilians.is_empty() and s.objective.rescued.size() == s.objective.civilians.size()
		"boss": return false
		"escort":
			var c := courier(s)
			return c != null and c.is_alive() and c.hp >= c.max_hp
		"demolish": return s.turn <= DEMOLISH_TURNS - 3
		"hack": return s.objective.relays.count("lost") == 0
		"samples": return s.objective.samples.count("lost") == 0
	return s.turn <= BONUS_BY_TURN


## One line for the HUD: the goal and how far along it is.
static func describe(s: GameState) -> String:
	var k := kind(s)
	var text: String = TEXT[k]
	match k:
		"extract":
			return "%s  ·  dropship leaves after turn %d" % [text, EXTRACT_TURNS]
		"hold":
			var line := "%s  ·  %d/%d turns" % [text, s.objective.get("held", 0), HOLD_TURNS]
			return line + "  ·  OVERRUN, RETAKE IT" if int(s.objective.get("overrun", 0)) > 0 else line
		"rescue":
			return "%s  ·  %d/%d safe" % [text, s.objective.get("rescued", []).size(), s.objective.get("civilians", []).size()]
		"purge":
			var nests := s.living(Types.Team.ENEMY).filter(func(u: Unit) -> bool: return u.kind == NEST_KIND).size()
			return "%s  ·  %d left" % [text, nests] if nests > 0 else text
		"escort":
			var c := courier(s)
			if c == null or not c.is_alive():
				return text
			var left := _courier_dist(s, c.pos)
			return "%s  ·  %d tiles to go" % [text, maxi(left, 0)]
		"demolish":
			return "%s  ·  %d/%d blown  ·  round %d/%d" % [text, s.objective.charges.count("blown"), s.objective.charges.size(), s.turn, DEMOLISH_TURNS]
		"hack":
			return "%s  ·  %d/%d hacked" % [text, s.objective.relays.count("hacked"), HACK_NEED]
		"samples":
			return "%s  ·  %d/%d delivered" % [text, s.objective.samples.count("delivered"), SAMPLES_NEED]
	return text


static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
