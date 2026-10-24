class_name RunMap
extends RefCounted
## Node map generation for one act (design doc, "Run map and events"): 5 rows, row 1 Skirmish,
## rows 2-3 rolled, row 4 Field hospital, row 5 the boss. Links never cross. Pure function of the
## run rng, so every peer that generates from the same seed gets the same map.
##
## A node is a Dictionary:
##   id: int, row: 1-5, col: index within its row, x: 0-1 horizontal layout position,
##   type: one of the node types below, links: Array[int] of node ids in the next row,
##   objective: "extract"|"hold"|"rescue"|"purge"|"boss"|"" (fights only),
##   seed: int (the fight / event seed of this node), visited: bool,
##   hidden: bool (an unrevealed "?" node), resolved: the type a "?" node turned into, "" until then.

const SKIRMISH := "skirmish"
const NEST := "nest"
const EVENT := "event"
const DEPOT := "depot"
const HOSPITAL := "hospital"
const SURVIVORS := "survivors"
const BOSS := "boss"
const UNKNOWN := "unknown"   # a hidden "?" node
const AMBUSH := "ambush"     # what a "?" node can resolve to: a Skirmish with enemies alerted

const FIGHTS: Array[String] = [SKIRMISH, NEST, BOSS, AMBUSH]
const BIOMES: Array[String] = ["wall", "port", "bore"]

## Weights for rows 2-3 per act (percent).
const WEIGHTS := {
	1: {SKIRMISH: 40, UNKNOWN: 25, NEST: 8, DEPOT: 12, SURVIVORS: 10, HOSPITAL: 5},
	2: {SKIRMISH: 35, UNKNOWN: 25, NEST: 13, DEPOT: 12, SURVIVORS: 10, HOSPITAL: 5},
	3: {SKIRMISH: 30, UNKNOWN: 25, NEST: 18, DEPOT: 12, SURVIVORS: 8, HOSPITAL: 7},
}
## What a "?" node resolves to (percent), before the fight-chance streak bonus.
const UNKNOWN_WEIGHTS := {EVENT: 60, AMBUSH: 20, DEPOT: 10, SURVIVORS: 10}
const SKIRMISH_OBJECTIVES := {"extract": 35, "hold": 35, "rescue": 15, "purge": 15}
const NEST_OBJECTIVES := {"purge": 50, "hold": 50}

const NAMES := {
	SKIRMISH: "Skirmish", NEST: "Infested nest", EVENT: "Event", DEPOT: "Supply depot",
	HOSPITAL: "Field hospital", SURVIVORS: "Survivors", BOSS: "Boss", UNKNOWN: "Unknown", AMBUSH: "Ambush",
}


static func is_fight(type: String) -> bool:
	return type in FIGHTS


static func biome(act: int) -> String:
	return BIOMES[clampi(act - 1, 0, BIOMES.size() - 1)]


## The node's type as the squad sees it: "unknown" until a "?" node is revealed or entered.
static func shown_type(n: Dictionary) -> String:
	return UNKNOWN if n.hidden else (n.resolved if n.resolved != "" else n.type)


static func pick_weighted(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0
	for k in weights:
		total += weights[k]
	var roll := rng.randi_range(1, total)
	for k in weights:
		roll -= weights[k]
		if roll <= 0:
			return k
	return weights.keys()[0]


static func generate(rng: RandomNumberGenerator, act: int) -> Array:
	var sizes: Array[int] = [rng.randi_range(2, 3), rng.randi_range(3, 4), rng.randi_range(3, 4), rng.randi_range(2, 3), 1]
	var nodes: Array = []
	var by_row: Array = []
	var next_id := 1
	for r in RunState.ROWS:
		var row_nodes: Array = []
		for c in sizes[r]:
			var n := {"id": next_id, "row": r + 1, "col": c, "x": (c + 0.5) / sizes[r], "type": "", "links": [],
				"objective": "", "seed": rng.randi() % 1000000 + 1, "visited": false, "hidden": false, "resolved": ""}
			next_id += 1
			row_nodes.append(n)
			nodes.append(n)
		by_row.append(row_nodes)
	for r in RunState.ROWS - 1:
		_link_rows(rng, by_row[r], by_row[r + 1])
	_assign_types(rng, act, by_row)
	for n in nodes:
		n.hidden = n.type == UNKNOWN
		match n.type:
			SKIRMISH: n.objective = pick_weighted(rng, SKIRMISH_OBJECTIVES)
			NEST: n.objective = pick_weighted(rng, NEST_OBJECTIVES)
			BOSS: n.objective = "boss"
	return nodes


## Non-crossing links between two rows: a random monotone staircase walk from the left ends to the
## right ends, so every node gets a link and nothing crosses. Walks giving a node more than 2
## links out are re-rolled.
static func _link_rows(rng: RandomNumberGenerator, a: Array, b: Array) -> void:
	var steps: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	for attempt in 100:
		var cells: Array[Vector2i] = [Vector2i.ZERO]
		var c := Vector2i.ZERO
		while c != Vector2i(a.size() - 1, b.size() - 1):
			var options := steps.filter(func(d: Vector2i) -> bool: return c.x + d.x < a.size() and c.y + d.y < b.size())
			c += options[rng.randi() % options.size()]
			cells.append(c)
		var out := {}
		for cell in cells:
			out[cell.x] = out.get(cell.x, 0) + 1
		if out.values().all(func(k: int) -> bool: return k <= 2):
			for cell in cells:
				a[cell.x].links.append(b[cell.y].id)
			return
	# Even split (always valid for the 1-4 node rows used here).
	for j in b.size():
		a[j * a.size() / b.size()].links.append(b[j].id)
	for i in a.size():
		if a[i].links.is_empty():
			a[i].links.append(b[i * b.size() / a.size()].id)


static func _assign_types(rng: RandomNumberGenerator, act: int, by_row: Array) -> void:
	for n in by_row[0]:
		n.type = SKIRMISH
	for n in by_row[3]:
		n.type = HOSPITAL
	by_row[4][0].type = BOSS
	var weights: Dictionary = WEIGHTS[clampi(act, 1, 3)]
	for attempt in 40:
		for r in [1, 2]:
			for n in by_row[r]:
				n.type = pick_weighted(rng, weights)
		_place_missing(rng, act, by_row)
		if _valid(act, by_row):
			return
	_repair(rng, by_row)


## "At least one nest" and "at least one depot" are placed over rolled nodes rather than
## re-rolled: a Skirmish becomes the nest and a non-combat node the depot, so the per-path rules
## that held before still hold.
static func _place_missing(rng: RandomNumberGenerator, act: int, by_row: Array) -> void:
	var middle: Array = by_row[1] + by_row[2]
	if not middle.any(func(n: Dictionary) -> bool: return n.type == NEST):
		var c := middle.filter(func(n: Dictionary) -> bool: return n.type == SKIRMISH and (act > 1 or n.row == 3))
		if not c.is_empty():
			c[rng.randi() % c.size()].type = NEST
	if not middle.any(func(n: Dictionary) -> bool: return n.type == DEPOT):
		var c := middle.filter(func(n: Dictionary) -> bool: return n.type in [EVENT, UNKNOWN, SURVIVORS])
		if not c.is_empty():
			c[rng.randi() % c.size()].type = DEPOT


static func _non_combat(type: String) -> bool:
	return type != SKIRMISH and type != NEST


static func _valid(act: int, by_row: Array) -> bool:
	var row2: Array = by_row[1]
	var row3: Array = by_row[2]
	if act == 1 and row2.any(func(n: Dictionary) -> bool: return n.type == NEST):
		return false
	# A hospital in row 3 always leads into row 4's hospitals.
	if row3.any(func(n: Dictionary) -> bool: return n.type == HOSPITAL):
		return false
	if not (row2 + row3).any(func(n: Dictionary) -> bool: return n.type == NEST):
		return false
	if not (row2 + row3).any(func(n: Dictionary) -> bool: return n.type == DEPOT):
		return false
	for a in row2:
		for id in a.links:
			var b: Dictionary = _find(row3, id)
			if a.type == b.type and (a.type == DEPOT or a.type == HOSPITAL):
				return false
			if not _non_combat(a.type) and not _non_combat(b.type):
				return false
	return true


## Fallback when every roll broke a rule: row 2 is all non-combat (a depot first), row 3 all
## fights with one nest. Always valid.
static func _repair(rng: RandomNumberGenerator, by_row: Array) -> void:
	for n in by_row[1]:
		n.type = DEPOT if n.col == 0 else [UNKNOWN, SURVIVORS, UNKNOWN][n.col % 3]
	for n in by_row[2]:
		n.type = SKIRMISH
	by_row[2][rng.randi() % by_row[2].size()].type = NEST


static func _find(nodes: Array, id: int) -> Dictionary:
	for n in nodes:
		if n.id == id:
			return n
	return {}


## Resolves a "?" node (when it is revealed with Intel or entered). The streak of non-fights
## raises the fight chance by 10% each, reset when a fight comes up.
static func resolve_unknown(run: RunState, n: Dictionary) -> String:
	if n.resolved != "":
		return n.resolved
	var w := UNKNOWN_WEIGHTS.duplicate()
	w[AMBUSH] += 10 * run.unknown_streak
	w[EVENT] = maxi(0, w[EVENT] - 10 * run.unknown_streak)
	n.resolved = pick_weighted(run.rng, w)
	if n.resolved == AMBUSH:
		run.unknown_streak = 0
		n.objective = pick_weighted(run.rng, SKIRMISH_OBJECTIVES)
	else:
		run.unknown_streak += 1
	return n.resolved
