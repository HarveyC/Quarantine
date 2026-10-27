class_name RunMap
extends RefCounted
## Node map generation for one act (design doc, "Run map and events"): 6 rows in Act 1 and 7 in Acts 2-3
## (RunState.rows_for). Row 1 Skirmish, the rows up to the last two rolled, then the Field hospital and the boss. Links never cross. Pure function of the
## run rng, so every peer that generates from the same seed gets the same map.
##
## A node is a Dictionary:
##   id: int, row: 1-5, col: index within its row, x: 0-1 horizontal layout position,
##   type: one of the node types below, links: Array[int] of node ids in the next row,
##   objective: "skirmish"|"extract"|"hold"|"rescue"|"purge"|"boss"|"" (fights only),
##   seed: int (the fight / event seed of this node), visited: bool,
##   hidden: bool (an unrevealed "?" node), resolved: the type a "?" node turned into, "" until then.

const SKIRMISH := "skirmish"
const NEST := "nest"
const EVENT := "event"
const DEPOT := "depot"
const HOSPITAL := "hospital"
const SURVIVORS := "survivors"
const ARMORY := "armory"     # a weapons cache: every soldier takes a gun (the class gun first)
const BOSS := "boss"
const UNKNOWN := "unknown"   # a hidden "?" node
const AMBUSH := "ambush"     # what a "?" node can resolve to: a Skirmish with enemies alerted

const FIGHTS: Array[String] = [SKIRMISH, NEST, BOSS, AMBUSH]
const BIOMES: Array[String] = ["wall", "port", "bore"]

## Weights for rows 2-3 per act (percent).
const WEIGHTS := {
	1: {SKIRMISH: 40, UNKNOWN: 25, NEST: 8, DEPOT: 12, SURVIVORS: 10, HOSPITAL: 5},
	2: {SKIRMISH: 35, UNKNOWN: 25, NEST: 13, DEPOT: 12, SURVIVORS: 10, HOSPITAL: 5, ARMORY: 4},
	3: {SKIRMISH: 30, UNKNOWN: 25, NEST: 18, DEPOT: 12, SURVIVORS: 8, HOSPITAL: 7, ARMORY: 4},
}
## What a "?" node resolves to (percent), before the fight-chance streak bonus.
const UNKNOWN_WEIGHTS := {EVENT: 60, AMBUSH: 20, DEPOT: 10, SURVIVORS: 10}
## Objectives a Skirmish or Ambush rolls, per act (percent). "skirmish" is a plain clear-the-area
## fight. Each roll already on the act's map divides that objective's weight (see roll_objective).
const SKIRMISH_OBJECTIVES := {
	1: {"skirmish": 24, "extract": 16, "hold": 16, "rescue": 12, "purge": 12, "escort": 10, "demolish": 10},
	2: {"skirmish": 15, "extract": 14, "hold": 14, "rescue": 14, "purge": 14, "escort": 8, "demolish": 8, "hack": 7, "samples": 6},
	3: {"skirmish": 16, "extract": 12, "hold": 16, "rescue": 13, "purge": 16, "demolish": 7, "hack": 9, "samples": 11},
}
const NEST_OBJECTIVES := {"purge": 50, "hold": 50}

const NAMES := {
	SKIRMISH: "Skirmish", NEST: "Infested nest", EVENT: "Event", DEPOT: "Supply depot",
	HOSPITAL: "Field hospital", SURVIVORS: "Survivors", ARMORY: "Weapons cache", BOSS: "Boss", UNKNOWN: "Unknown", AMBUSH: "Ambush",
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
	var rows := RunState.rows_for(act)
	var sizes: Array[int] = [rng.randi_range(2, 3)]
	for r in rows - 3:
		sizes.append(rng.randi_range(3, 4))
	sizes.append(rng.randi_range(2, 3))
	sizes.append(1)
	var nodes: Array = []
	var by_row: Array = []
	var next_id := 1
	for r in rows:
		var row_nodes: Array = []
		for c in sizes[r]:
			var n := {"id": next_id, "row": r + 1, "col": c, "x": (c + 0.5) / sizes[r], "type": "", "links": [],
				"objective": "", "seed": rng.randi() % 1000000 + 1, "visited": false, "hidden": false, "resolved": ""}
			next_id += 1
			row_nodes.append(n)
			nodes.append(n)
		by_row.append(row_nodes)
	for r in rows - 1:
		_link_rows(rng, by_row[r], by_row[r + 1])
	_assign_types(rng, act, by_row)
	for n in nodes:
		n.hidden = n.type == UNKNOWN
		match n.type:
			SKIRMISH: n.objective = roll_objective(rng, act, nodes)
			NEST: n.objective = pick_weighted(rng, NEST_OBJECTIVES)
			BOSS: n.objective = "boss"
	return nodes


## A Skirmish / Ambush objective for `act`. Every Skirmish or Ambush on `map` that already has
## this objective divides its weight by one more, so an act's fights spread across the mix
## instead of repeating one objective.
static func roll_objective(rng: RandomNumberGenerator, act: int, map: Array) -> String:
	var base: Dictionary = SKIRMISH_OBJECTIVES[clampi(act, 1, SKIRMISH_OBJECTIVES.size())]
	var seen := {}
	for m in map:
		if (m.type == SKIRMISH or m.resolved == AMBUSH) and base.has(m.objective):
			seen[m.objective] = seen.get(m.objective, 0) + 1
	var w := {}
	for k in base:
		w[k] = maxi(1, roundi(float(base[k]) * 4.0 / (4.0 + 4.0 * seen.get(k, 0))))
	return pick_weighted(rng, w)


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
	var rows := by_row.size()
	for n in by_row[0]:
		n.type = SKIRMISH
	for n in by_row[rows - 2]:
		n.type = HOSPITAL
	by_row[rows - 1][0].type = BOSS
	var weights: Dictionary = WEIGHTS[clampi(act, 1, 3)]
	for attempt in 40:
		for r in range(1, rows - 2):
			for n in by_row[r]:
				n.type = pick_weighted(rng, weights)
		_place_missing(rng, act, by_row)
		if _valid(act, rolled_rows(by_row)):
			return
	_repair(rng, by_row)


## The rolled rows between the opening Skirmish and the Field hospital.
static func rolled_rows(by_row: Array) -> Array:
	return by_row.slice(1, by_row.size() - 2)


## "At least one nest" and "at least one depot" are placed over rolled nodes rather than
## re-rolled: a Skirmish becomes the nest and a non-combat node the depot, so the per-path rules
## that held before still hold.
static func _place_missing(rng: RandomNumberGenerator, act: int, by_row: Array) -> void:
	var middle: Array = []
	for r in rolled_rows(by_row):
		middle.append_array(r)
	var last_rolled := by_row.size() - 2
	if not middle.any(func(n: Dictionary) -> bool: return n.type == NEST):
		var c := middle.filter(func(n: Dictionary) -> bool: return n.type == SKIRMISH and (act > 1 or n.row == last_rolled))
		if not c.is_empty():
			c[rng.randi() % c.size()].type = NEST
	if act == 1 and not middle.any(func(n: Dictionary) -> bool: return n.type == ARMORY):
		# Act 1 always has a weapons cache on the first rolled row, where a path can reach it early.
		var first: Array = rolled_rows(by_row)[0].filter(func(n: Dictionary) -> bool: return n.type != DEPOT and n.type != HOSPITAL)
		if not first.is_empty():
			first[rng.randi() % first.size()].type = ARMORY
	if not middle.any(func(n: Dictionary) -> bool: return n.type == DEPOT):
		var c := middle.filter(func(n: Dictionary) -> bool: return n.type in [EVENT, UNKNOWN, SURVIVORS])
		if not c.is_empty():
			c[rng.randi() % c.size()].type = DEPOT


static func _non_combat(type: String) -> bool:
	return type != SKIRMISH and type != NEST


## `rolled` is the rolled rows in order (see rolled_rows).
static func _valid(act: int, rolled: Array) -> bool:
	var all: Array = []
	for r in rolled:
		all.append_array(r)
	if act == 1 and rolled[0].any(func(n: Dictionary) -> bool: return n.type == NEST):
		return false
	# A hospital in the last rolled row always leads into the Field hospital row.
	if rolled.back().any(func(n: Dictionary) -> bool: return n.type == HOSPITAL):
		return false
	if not all.any(func(n: Dictionary) -> bool: return n.type == NEST):
		return false
	if not all.any(func(n: Dictionary) -> bool: return n.type == DEPOT):
		return false
	if act == 1 and not rolled[0].any(func(n: Dictionary) -> bool: return n.type == ARMORY):
		return false
	for i in rolled.size() - 1:
		for a in rolled[i]:
			for id in a.links:
				var b: Dictionary = _find(rolled[i + 1], id)
				if a.type == b.type and (a.type == DEPOT or a.type == HOSPITAL or a.type == ARMORY):
					return false
				if not _non_combat(a.type) and not _non_combat(b.type):
					return false
	return true


## Fallback when every roll broke a rule: the rolled rows alternate, the first all non-combat (a
## depot first) and the next all fights, with one nest among the fights. Always valid.
static func _repair(rng: RandomNumberGenerator, by_row: Array) -> void:
	var rolled := rolled_rows(by_row)
	var fights: Array = []
	for i in rolled.size():
		for n in rolled[i]:
			if i % 2 == 0:
				n.type = DEPOT if (n.col == 0 and i == 0) else [UNKNOWN, SURVIVORS, UNKNOWN][n.col % 3]
				if n.col == 1 and i == 0 and rolled[0].size() > 1:
					n.type = ARMORY
			else:
				n.type = SKIRMISH
				fights.append(n)
	fights[rng.randi() % fights.size()].type = NEST


static func _find(nodes: Array, id: int) -> Dictionary:
	for n in nodes:
		if n.id == id:
			return n
	return {}


## The Bridge event: the rest of the act loses a column. Drops the rightmost node of every row
## after `row` that has more than one node, relinks whatever pointed at it to the new rightmost
## node (so nothing crosses), and gives any node left without a way in a link from the rightmost
## node of the row before.
static func remove_column(map: Array, row: int) -> void:
	var last := _last_row(map)
	for r in range(row + 1, last):
		var nodes := _row(map, r)
		if nodes.size() < 2:
			continue
		var gone: Dictionary = nodes.back()
		var keep: Dictionary = nodes[nodes.size() - 2]
		map.erase(gone)
		for n in _row(map, r - 1):
			if n.links.has(gone.id):
				n.links.erase(gone.id)
				if not n.links.has(keep.id):
					n.links.append(keep.id)
	for r in range(row + 2, last + 1):
		var prev := _row(map, r - 1)
		for n in _row(map, r):
			if not prev.any(func(p: Dictionary) -> bool: return p.links.has(n.id)):
				prev.back().links.append(n.id)


static func _last_row(map: Array) -> int:
	var last := 1
	for n in map:
		last = maxi(last, n.row)
	return last


static func _row(map: Array, r: int) -> Array:
	var out := map.filter(func(n: Dictionary) -> bool: return n.row == r)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.col < b.col)
	return out


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
		n.objective = roll_objective(run.rng, run.act, run.map)
	else:
		run.unknown_streak += 1
	return n.resolved
