class_name TutorialScript
extends RefCounted
## The training mission: a fixed map and a list of short lessons, each with a goal the squad
## has to reach before the next one starts. Pure rules like Rules: it builds the GameState,
## watches its events, and its lesson set-ups (spawns, a dose of Infection) go through the
## same modules a real fight uses, so the view plays them like any other event.
##
## TutorialSession calls `observe(ev)` for every event and `update(s)` after each change;
## the overlay (ui/tutorial/tutorial_overlay.gd) reads `current()` and calls `proceed(s)`
## for the info lessons that only need a Continue click.

const MAP := "res://maps/tutorial.txt"
const SEED := 4242

## Where the lessons point. Cells match maps/tutorial.txt.
const MOVE_CELLS: Array[Vector2i] = [Vector2i(7, 18), Vector2i(8, 18)]
const COVER_CELLS: Array[Vector2i] = [Vector2i(1, 17), Vector2i(2, 17)]
const SCOUT_CELLS: Array[Vector2i] = [Vector2i(4, 15), Vector2i(5, 15), Vector2i(11, 15), Vector2i(12, 15)]
const ROOF_CELLS: Array[Vector2i] = [Vector2i(10, 12), Vector2i(10, 11), Vector2i(11, 11), Vector2i(12, 11),
	Vector2i(10, 10), Vector2i(12, 10), Vector2i(10, 9), Vector2i(11, 9), Vector2i(12, 9)]
const NEST_CELL := Vector2i(7, 4)
## The Runner for the fog lesson appears at the first of these the squad can't see.
const SCOUT_SPAWNS: Array[Vector2i] = [Vector2i(5, 8), Vector2i(4, 7), Vector2i(10, 7), Vector2i(12, 6), Vector2i(7, 2)]
const WAVE_CELLS: Array[Vector2i] = [Vector2i(5, 1), Vector2i(10, 1)]
## A hidden spore nest walled into the corner: a fight with no enemies left is won, so this
## keeps the training open between lessons. It dies when the last lesson is done.
const ANCHOR_CELL := Vector2i(15, 0)
## Infection the infection lesson tops a soldier up to (Exposed: Adrenal Surge wakes).
const LESSON_INFECTION := 30
## The overwatch lesson moves on after this many enemy phases even if no reaction shot fired.
const OVERWATCH_PHASES := 2

## Each lesson: `id`, `title`, `text` (one or two short lines), and what the overlay points at:
## `cells` (marked on the floor), `hud` (a HUD piece: ready / aim / overwatch / mutation /
## roster), `keys` (keycaps to show). `info` lessons wait for Continue; `visual` adds a small
## diagram to the card.
const STEPS: Array[Dictionary] = [
	{"id": "welcome", "title": "Basic training", "info": true, "keys": ["W A S D", "Q E", "Wheel"],
		"text": "Lantern Company drill. Pan the camera with WASD, turn it with Q and E, zoom with the wheel."},
	{"id": "move", "title": "Move", "cells": MOVE_CELLS, "keys": ["LMB"],
		"text": "Click a soldier, then a marked tile. A move costs 1 of your 2 actions."},
	{"id": "cover", "title": "Take cover", "cells": COVER_CELLS, "visual": "cover",
		"text": "Shields on a tile edge show cover. Half cover stops some shots, full cover stops more. Get your other soldier behind the wall."},
	{"id": "ready", "title": "Team phase", "hud": "ready", "keys": ["Space"],
		"text": "Everyone moves in any order, then presses Ready. Enemies act once every player is ready."},
	{"id": "fog", "title": "Fog of war", "cells": SCOUT_CELLS,
		"text": "Dark ground is unknown. The squad shares what each soldier sees. Scout ahead to a marked tile."},
	{"id": "shoot", "title": "Hit chance", "hud": "aim", "keys": ["1"],
		"text": "Contact. Press Shoot to aim: the panel shows your odds and why. Drop the Runner."},
	{"id": "high_ground", "title": "High ground", "cells": ROOF_CELLS, "visual": "height",
		"text": "Climb the ladder. From a roof you get +10 aim and +2 sight, and targets lose a step of cover."},
	{"id": "overwatch", "title": "Overwatch", "hud": "overwatch", "keys": ["2", "Space"],
		"text": "Runners incoming. Overwatch fires at the first enemy that moves in sight. Set it, then Ready."},
	{"id": "clear", "title": "Finish them", "text": "Clear the Runners."},
	{"id": "infection", "title": "Infection", "hud": "mutation",
		"text": "Bites raise Infection. At 25 a mutation wakes. Use Adrenal Surge, the teal button, for a third action."},
	{"id": "turning", "title": "Turning", "info": true, "visual": "tiers",
		"text": "From 50 a soldier can Lapse and act on their own. At 100 they Turn for good. Medic Stim, hospitals and Serum cure it."},
	{"id": "nest", "title": "Purge the nest", "cells": [NEST_CELL],
		"text": "Destroy the spore nest to finish training."},
]

## Index into STEPS; STEPS.size() once training is complete.
var step := 0
var _entered_turn := 0
var _enemy_phases := 0
var _reaction := false
var _mutation := false
var _continued := false
var _anchor := -1
var _nest := -1
## The soldier the infection lesson dosed (unit id), so the overlay can select them.
var dosed := -1


static func squad() -> Array:
	var out: Array = []
	for k in ["trooper", "marksman"]:
		out.append({"kind": k, "player": 0, "prog": Progression.quick_play_record(k)})
	return out


func build_state() -> GameState:
	var empty: Array[String] = []
	var s := Rules.new_mission_on_grid(Grid.load_file(MAP), squad(), empty, SEED)
	var anchor := EnemyRoster.make("spore_nest")
	anchor.status["hidden"] = true
	anchor.status["tutorial_anchor"] = true
	_anchor = s.add_unit(anchor, ANCHOR_CELL).id
	_nest = s.add_unit(EnemyRoster.make("spore_nest"), NEST_CELL).id
	step = 0
	return s


func current() -> Dictionary:
	return STEPS[step] if step < STEPS.size() else {}


func is_complete() -> bool:
	return step >= STEPS.size()


func observe(s: GameState, ev: Dictionary) -> void:
	match str(ev.get("type", "")):
		"shot":
			var u := s.get_unit(int(ev.get("unit", -1)))
			if u != null and u.team == Types.Team.PLAYER and ev.get("reaction", false):
				_reaction = true
		"mutation":
			var u := s.get_unit(int(ev.get("unit", -1)))
			if u != null and u.team == Types.Team.PLAYER:
				_mutation = true
		"enemy_phase":
			_enemy_phases += 1


## Continue on an info lesson.
func proceed(s: GameState) -> void:
	if current().get("info", false):
		_continued = true
		update(s)


## Dev aid (screenshots): starts lesson `n` with its set-up, skipping the goals before it.
func jump_to(s: GameState, n: int) -> void:
	step = clampi(n, 0, STEPS.size())
	_enter(s)


## Moves through every lesson whose goal is met. Returns true if the lesson changed.
func update(s: GameState) -> bool:
	var moved := false
	while not is_complete() and s.phase != Types.Phase.ENDED and _done(s):
		step += 1
		moved = true
		_enter(s)
	if not is_complete() and s.phase == Types.Phase.ENDED and s.result == Types.Result.VICTORY:
		step = STEPS.size()   # the nest fell early: training is still complete
		moved = true
	return moved


func _done(s: GameState) -> bool:
	match str(current().get("id", "")):
		"welcome", "turning":
			return _continued
		"move":
			return _squad_on(s, MOVE_CELLS)
		"cover":
			return _squad_on(s, COVER_CELLS)
		"ready":
			return s.turn > _entered_turn
		"fog":
			return _mobile_enemies(s).any(func(u: Unit) -> bool: return Vision.sees_unit(s, Types.Team.PLAYER, u)) \
				or _mobile_enemies(s).is_empty()
		"shoot", "clear":
			return _mobile_enemies(s).is_empty()
		"high_ground":
			return _squad(s).any(func(u: Unit) -> bool: return s.grid.level(u.pos) > 0)
		"overwatch":
			return _reaction or _enemy_phases >= OVERWATCH_PHASES or _mobile_enemies(s).is_empty()
		"infection":
			return _mutation
		"nest":
			var nest := s.get_unit(_nest)
			if nest == null or not nest.is_alive():
				_finish(s)
				return true
	return false


## Set-up for the lesson just entered.
func _enter(s: GameState) -> void:
	_entered_turn = s.turn
	_enemy_phases = 0
	_continued = false
	match str(current().get("id", "")):
		"fog":
			var cell := SCOUT_SPAWNS[0]
			for c in SCOUT_SPAWNS:
				if s.unit_at(c) == null and not Vision.cell_visible(s, Types.Team.PLAYER, c):
					cell = c
					break
			var r := EnemyRoster.make("runner")
			s.add_unit(r, Encounter.free_cell(s, cell))
			Vision.refresh(s)
			s.emit({"type": "spawned", "unit": r.id, "kind": r.kind, "cell": r.pos, "from": -1})
		"overwatch":
			_patch_up(s)
			_reaction = false
			for c in WAVE_CELLS:
				Encounter.spawn(s, "runner", c)
			Vision.refresh(s)
		"infection":
			_patch_up(s)
			_mutation = false
			var u := lesson_soldier(s)
			if u != null:
				dosed = u.id
				if u.infection < LESSON_INFECTION:
					Infection.add(s, u, LESSON_INFECTION - u.infection)


## The soldier the infection lesson doses: one with actions left if there is one.
func lesson_soldier(s: GameState) -> Unit:
	var best: Unit = null
	for u in _squad(s):
		if best == null or (u.actions_left > 0 and best.actions_left <= 0):
			best = u
	return best


func _finish(s: GameState) -> void:
	var anchor := s.get_unit(_anchor)
	if anchor != null and anchor.is_alive():
		Encounter.kill(s, anchor)
	Rules.check_end(s)


## Tops the squad back up between lessons so a bad roll doesn't end training.
func _patch_up(s: GameState) -> void:
	for u in _squad(s):
		if u.hp < u.max_hp:
			var healed := u.max_hp - u.hp
			u.hp = u.max_hp
			s.emit({"type": "regenerate", "unit": u.id, "healed": healed, "hp": u.hp})


func _squad(s: GameState) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in s.living(Types.Team.PLAYER):
		if not u.status.has("deployable"):
			out.append(u)
	return out


func _squad_on(s: GameState, cells: Array[Vector2i]) -> bool:
	return _squad(s).any(func(u: Unit) -> bool: return cells.has(u.pos))


func _mobile_enemies(s: GameState) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in s.living(Types.Team.ENEMY):
		if not UnitData.ENEMIES.get(u.kind, {}).get("static", false):
			out.append(u)
	return out
