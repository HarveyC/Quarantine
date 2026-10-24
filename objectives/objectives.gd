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
##   hold:    survive HOLD_TURNS rounds; lost if, at the end of a round, enemies stand in the
##            beacon zone and no soldier does.
##   rescue:  civilians follow the nearest soldier; win when every living civilian has reached the
##            exit (the drop zone). If every civilian dies, killing every enemy wins instead.
##   purge:   destroy every spore nest (units of kind NEST_KIND), or kill every enemy.

const EXTRACT_TURNS := 7
const HOLD_TURNS := 4
const BONUS_BY_TURN := 5        # skirmish / elite / purge bonus: done by the end of this turn
const NEST_KIND := "spore_nest"
const CIVILIAN := {"name": "Civilian", "max_hp": 3, "mobility": 4}

const TEXT := {
	"skirmish": "Clear the area",
	"elite": "Destroy the nest",
	"boss": "Kill the boss",
	"extract": "Reach the evac zone",
	"hold": "Hold the beacon",
	"rescue": "Escort the civilians to the drop zone",
	"purge": "Destroy the spore nests",
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
			s.objective.contested = false
		"extract":
			s.objective.left_behind = 0
		"rescue":
			var ids: Array = []
			for c in s.grid.marker("civilian"):
				if s.unit_at(c) == null:
					ids.append(_spawn_civilian(s, c).id)
			s.objective.civilians = ids
			s.objective.rescued = []
		"purge":
			s.objective.had_nests = false


static func _spawn_civilian(s: GameState, c: Vector2i) -> Unit:
	var u := Unit.new()
	u.kind = "civilian"
	u.team = Types.Team.PLAYER
	u.display_name = CIVILIAN.name
	u.owner_player = -1          # nobody commands them
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

## End of the squad's turn (after hazards): civilians follow, extraction and rescue are checked.
static func on_team_phase_end(s: GameState) -> void:
	if s.objective.is_empty() or s.phase == Types.Phase.ENDED:
		return
	match kind(s):
		"extract": _check_extract(s)
		"rescue": _rescue_turn(s)


## End of a full round (after the enemy phase and hazards): the beacon is checked.
static func on_enemy_phase_end(s: GameState) -> void:
	if s.objective.is_empty() or s.phase == Types.Phase.ENDED:
		return
	if kind(s) == "hold":
		_check_hold(s)


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


static func _check_hold(s: GameState) -> void:
	var zone := s.grid.marker("beacon")
	var ours := soldiers(s).any(func(u: Unit) -> bool: return zone.has(u.pos))
	var theirs := s.living(Types.Team.ENEMY).any(func(u: Unit) -> bool: return zone.has(u.pos))
	if theirs:
		s.objective.contested = true
	if theirs and not ours:
		s.objective.result = Types.Result.DEFEAT
		return
	s.objective.held += 1
	_progress(s, s.objective.held, HOLD_TURNS)
	if s.objective.held >= HOLD_TURNS:
		s.objective.result = Types.Result.VICTORY


static func _rescue_turn(s: GameState) -> void:
	var exit := s.grid.marker("exit")
	for c in _civilians(s):
		if s.objective.rescued.has(c.id):
			continue
		if not exit.has(c.pos):
			_follow(s, c)
		if c.is_alive() and exit.has(c.pos):
			s.objective.rescued.append(c.id)
			s.emit({"type": "rescued", "unit": c.id})
	var waiting := _civilians(s).filter(func(c: Unit) -> bool: return not s.objective.rescued.has(c.id))
	_progress(s, s.objective.rescued.size(), s.objective.civilians.size())
	if waiting.is_empty() and not s.objective.rescued.is_empty():
		s.objective.result = Types.Result.VICTORY


## A civilian walks one move toward the nearest soldier (or onto a free exit cell when one is in
## reach and a soldier is close), as a normal MOVE so overwatch and hazards apply.
static func _follow(s: GameState, c: Unit) -> void:
	var squad := soldiers(s)
	if squad.is_empty():
		return
	var reach := Rules.move_range(s, c)
	var nearest: Unit = squad[0]
	for u in squad:
		if _cheb(u.pos, c.pos) < _cheb(nearest.pos, c.pos):
			nearest = u
	var best := c.pos
	var best_score := _follow_score(s, c, c.pos, nearest.pos)
	for cell in reach:
		var sc := _follow_score(s, c, cell, nearest.pos)
		if sc < best_score or (sc == best_score and (cell.y < best.y or cell.y == best.y and cell.x < best.x)):
			best = cell
			best_score = sc
	if best == c.pos:
		return
	c.actions_left = 1
	Rules.apply(s, {"type": Types.MOVE, "unit": c.id, "to": best})
	c.actions_left = 0


static func _follow_score(s: GameState, c: Unit, cell: Vector2i, leader: Vector2i) -> float:
	var d := _cheb(cell, leader)
	var score := float(maxi(d - 1, 0)) * 10.0   # keep within one tile of the leader
	if s.grid.marker("exit").has(cell) and d <= 3:
		score -= 25.0                            # step onto the exit when the escort is close
	return score + Hazards.avoid_cost(s, c, cell) * 5.0


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
		"extract", "hold":
			return Types.Result.NONE
		"rescue":
			# Killing everything only wins once no civilian is left to save.
			return Types.Result.VICTORY if enemies_dead and _civilians(s).is_empty() else Types.Result.NONE
		"purge":
			var nests := s.living(Types.Team.ENEMY).filter(func(u: Unit) -> bool: return u.kind == NEST_KIND)
			if not nests.is_empty():
				s.objective.had_nests = true
			elif s.objective.had_nests or s.units.any(func(u: Unit) -> bool: return u.kind == NEST_KIND):
				return Types.Result.VICTORY
	return Types.Result.VICTORY if enemies_dead else Types.Result.NONE


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
	return s.turn <= BONUS_BY_TURN


## One line for the HUD: the goal and how far along it is.
static func describe(s: GameState) -> String:
	var k := kind(s)
	var text: String = TEXT[k]
	match k:
		"extract":
			return "%s  ·  dropship leaves after turn %d" % [text, EXTRACT_TURNS]
		"hold":
			return "%s  ·  %d/%d turns" % [text, s.objective.get("held", 0), HOLD_TURNS]
		"rescue":
			return "%s  ·  %d/%d safe" % [text, s.objective.get("rescued", []).size(), s.objective.get("civilians", []).size()]
		"purge":
			var nests := s.living(Types.Team.ENEMY).filter(func(u: Unit) -> bool: return u.kind == NEST_KIND).size()
			return "%s  ·  %d left" % [text, nests] if nests > 0 else text
	return text


static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
