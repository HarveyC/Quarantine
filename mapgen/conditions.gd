class_name Conditions
extends RefCounted
## Fight conditions: one per run fight (about half of them), chosen from the node's seed so the run
## map can show it before the fight. A condition either changes sight (fog, blackout), lays terrain
## on the map (flooded pools, live rails) or schedules telegraphed events (shelling, a convoy, roofs
## giving way). Pure rules code: terrain comes from the map's own rng, events from state.rng.
##
## Entry points: for_fight (which condition), shape (MapGen, lays terrain), setup (MatchConfig, rails
## and events), sight_mod (Vision), on_enemy_phase_start (Rules, announces events a round ahead).
## State lives in `s.condition` ({"events": [...]}) and Grid.condition / Grid.water / Grid.rails.

const CHANCE := 0.55
const BY_ACT := {
	1: ["fog", "flooded", "shelling"],
	2: ["fog", "flooded", "shelling", "blackout", "live_rails", "convoy"],
	3: ["fog", "flooded", "shelling", "blackout", "live_rails", "convoy", "roofs"],
}
## Sight radius change per team for the sight conditions.
const SIGHT := {"fog": {"player": -3, "enemy": -3}, "blackout": {"player": -3, "enemy": -1}}
const POOLS := 3
const POOL_SIZE := Vector2i(12, 20)
const RAILS := 2
const RAIL_LEN := Vector2i(6, 9)
const SHELL_DAMAGE := 3
const SHELL_FIRE := 2
const COLLAPSE_RANGE := 7
const CONVOY := {1: ["runner", "runner"], 2: ["runner", "runner", "spitter"], 3: ["runner", "runner", "spitter", "runner"]}

const KINDS := {
	"fog": {"name": "Fog bank", "line": "Everyone sees 3 tiles less this fight."},
	"blackout": {"name": "Blackout", "line": "The lights are out. Your squad sees 3 tiles less, the Infected 1 less."},
	"flooded": {"name": "Flooded", "line": "Pools of water slow every step and put fire out."},
	"live_rails": {"name": "Live rails", "line": "Rails with current in them hurt whoever crosses them."},
	"shelling": {"name": "Shelling", "line": "Artillery lands on a soldier's tile every few rounds, called a round ahead."},
	"convoy": {"name": "Convoy", "line": "A convoy of Infected arrives from the edge on round 4."},
	"roofs": {"name": "Roof collapse", "line": "Rooftops give way every few rounds, called a round ahead."},
}


## The condition for a run fight, "" for none. Bosses and the tutorial never get one.
static func for_fight(seed: int, act: int, objective: String, node: String) -> String:
	if objective == "boss" or objective == "" or node == "boss":
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:condition" % seed).hash()
	if rng.randf() > CHANCE:
		return ""
	var pool: Array = BY_ACT[clampi(act, 1, 3)]
	return pool[rng.randi() % pool.size()]


static func display_name(kind: String) -> String:
	return str(KINDS.get(kind, {}).get("name", ""))


## Sight radius change for `u` under the grid's condition (0 or negative).
static func sight_mod(s: GameState, u: Unit) -> int:
	var table: Dictionary = SIGHT.get(s.grid.condition, {})
	if table.is_empty():
		return 0
	return int(table["player" if u.team == Types.Team.PLAYER else "enemy"])


# ---------------------------------------------------------------- terrain (MapGen)

## Lays the condition's terrain on a finished map. `rng` is the map's own.
static func shape(g: Grid, condition: String, rng: RandomNumberGenerator) -> void:
	g.condition = condition
	var open := _open_cells(g)
	match condition:
		"flooded":
			for i in POOLS:
				_pool(g, open, rng)
		"live_rails":
			for i in RAILS:
				_rail(g, open, rng)


## Ground cells a condition may cover: plain floor, no objective, spawn, barrel, stair or edge feature,
## away from the drop zone and the enemy pods.
static func _open_cells(g: Grid) -> Dictionary:
	var out := {}
	var keep := {}
	for k in g.markers:
		for c in g.markers[k]:
			keep[c] = true
	for y in g.height:
		for x in g.width:
			var c := Vector2i(x, y)
			if not g.is_walkable(c) or g.level(c) != 0 or keep.has(c) or g.volatile.has(c) or g.stairs.has(c) or g.ladders.has(c):
				continue
			if g.player_spawns.any(func(p: Vector2i) -> bool: return maxi(absi(p.x - x), absi(p.y - y)) < 6):
				continue
			if g.enemy_spawns.any(func(p: Vector2i) -> bool: return maxi(absi(p.x - x), absi(p.y - y)) < 3):
				continue
			if Grid.DIRS4.any(func(d: Vector2i) -> bool: return g.is_ladder(c + d) or g.is_stairs(c + d)):
				continue
			out[c] = true
	return out


static func _sorted(cells: Dictionary) -> Array:
	var keys: Array = cells.keys()
	keys.sort()
	return keys


## A blob of 12 to 20 connected cells grown from a random open cell.
static func _pool(g: Grid, open: Dictionary, rng: RandomNumberGenerator) -> void:
	var keys := _sorted(open)
	if keys.is_empty():
		return
	var start: Vector2i = keys[rng.randi() % keys.size()]
	var want := rng.randi_range(POOL_SIZE.x, POOL_SIZE.y)
	var blob: Array[Vector2i] = [start]
	var edge: Array[Vector2i] = [start]
	var seen := {start: true}
	while blob.size() < want and not edge.is_empty():
		var i := rng.randi() % edge.size()
		var c: Vector2i = edge[i]
		var grew := false
		var dirs := Grid.DIRS4.duplicate()
		for j in range(dirs.size() - 1, 0, -1):
			var k := rng.randi_range(0, j)
			var tmp = dirs[j]
			dirs[j] = dirs[k]
			dirs[k] = tmp
		for d in dirs:
			var n: Vector2i = c + d
			if open.has(n) and not seen.has(n) and not g.water.has(n):
				seen[n] = true
				blob.append(n)
				edge.append(n)
				grew = true
				break
		if not grew:
			edge.remove_at(i)
	for c in blob:
		g.water[c] = true
		open.erase(c)


## A straight run of 6 to 9 open cells in a row or a column.
static func _rail(g: Grid, open: Dictionary, rng: RandomNumberGenerator) -> void:
	var keys := _sorted(open)
	for attempt in 40:
		if keys.is_empty():
			return
		var start: Vector2i = keys[rng.randi() % keys.size()]
		var d := Vector2i(1, 0) if rng.randf() < 0.5 else Vector2i(0, 1)
		var run: Array[Vector2i] = []
		var c := start
		while open.has(c) and run.size() < RAIL_LEN.y:
			run.append(c)
			c += d
		if run.size() < RAIL_LEN.x:
			continue
		for cell in run:
			g.rails[cell] = true
			open.erase(cell)
		return


# ---------------------------------------------------------------- state (MatchConfig, Rules)

## Called once the fight is built: live rails go in as permanent hazards, events get their rounds.
static func setup(s: GameState, act := 1) -> void:
	var cond := s.grid.condition
	if cond == "":
		return
	s.condition = {"kind": cond, "act": act, "events": []}
	match cond:
		"live_rails":
			var cells: Array[Vector2i] = []
			cells.assign(s.grid.rails.keys())
			cells.sort()
			Hazards.add(s, cells, "live", Hazards.PERMANENT)
		"shelling":
			s.condition.events = [{"turn": 3, "kind": "shell"}, {"turn": 6, "kind": "shell"}]
		"roofs":
			s.condition.events = [{"turn": 3, "kind": "roof"}, {"turn": 6, "kind": "roof"}]
		"convoy":
			s.condition.events = [{"turn": 4, "kind": "convoy"}]
	if not s.condition.events.is_empty() and s.encounter.is_empty():
		s.encounter = {"telegraphs": [], "incoming": []}   # telegraphs resolve through Encounter


## Rules.run_enemy_phase: events due next round are announced now (a telegraph or incoming cells),
## so the squad has a full turn to react.
static func on_enemy_phase_start(s: GameState) -> void:
	if s.condition.is_empty():
		return
	for ev in s.condition.events:
		if int(ev.turn) - 1 != s.turn:
			continue
		match ev.kind:
			"shell":
				_announce_shell(s, int(ev.turn))
			"roof":
				if not _announce_roof(s, int(ev.turn)):
					_announce_shell(s, int(ev.turn))
			"convoy":
				_announce_convoy(s, int(ev.turn))


static func _soldiers(s: GameState) -> Array[Unit]:
	return s.living(Types.Team.PLAYER).filter(func(u: Unit) -> bool: return not u.status.has("civilian"))


static func _announce_shell(s: GameState, turn: int) -> void:
	var soldiers := _soldiers(s)
	if soldiers.is_empty():
		return
	var target: Unit = soldiers[s.rng.randi() % soldiers.size()]
	var cells: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := target.pos + Vector2i(dx, dy)
			if s.grid.is_walkable(c):
				cells.append(c)
	Encounter.add_telegraph(s, {"kind": "airstrike", "cells": cells, "turn": turn, "damage": SHELL_DAMAGE,
		"source": -1, "smash": true, "fire": SHELL_FIRE, "unit": -1})


## Raised ground near the squad comes down. False when no roof is close enough.
static func _announce_roof(s: GameState, turn: int) -> bool:
	var cells: Array[Vector2i] = []
	for y in s.grid.height:
		for x in s.grid.width:
			var c := Vector2i(x, y)
			if s.grid.level(c) > 0 and s.grid.is_walkable(c) and _soldiers(s).any(func(u: Unit) -> bool: return maxi(absi(u.pos.x - x), absi(u.pos.y - y)) <= COLLAPSE_RANGE):
				cells.append(c)
	if cells.size() < 4:
		return false
	var anchor: Vector2i = cells[s.rng.randi() % cells.size()]
	var hit: Array[Vector2i] = []
	for c in cells:
		if maxi(absi(c.x - anchor.x), absi(c.y - anchor.y)) <= 1:
			hit.append(c)
	Encounter.add_telegraph(s, {"kind": "collapse", "cells": hit, "turn": turn, "damage": 0, "source": -1,
		"collapse": true, "unit": -1})
	return true


static func _announce_convoy(s: GameState, turn: int) -> void:
	var kinds: Array = CONVOY[clampi(int(s.condition.get("act", 1)), 1, 3)]
	var cells: Array = s.grid.markers.get("reinforce", [])
	if cells.is_empty():
		cells = s.grid.enemy_spawns.slice(0, 3)
	if cells.is_empty():
		return
	s.encounter.incoming.append({"turn": turn, "cells": cells.duplicate(), "kinds": kinds.duplicate()})
	s.emit({"type": "reinforcements_incoming", "cells": cells, "turn": turn, "count": kinds.size()})
