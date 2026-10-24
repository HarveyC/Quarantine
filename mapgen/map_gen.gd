class_name MapGen
extends RefCounted
## Builds a tactical map from a spec by stitching hand-made 4x4 parcels onto a plot
## (XCOM 2-style plots and parcels). Pure rules code, no nodes.
##
## spec = {"biome": "wall"|"port"|"bore", "objective": "skirmish"|"extract"|"hold"|"rescue"|"purge"|"elite"|"boss",
##         "seed": int}. Other keys are ignored. The result depends on the spec alone (its own RNG,
## never state.rng), so every peer generates the identical map from the MatchConfig the host broadcasts.
##
## Output: a Grid with tiles, player_spawns (deploy zone, row-major), enemy_spawns (pod cells,
## round-robin across pods), biome, and markers (see MARKER_KEYS). Biome parcels live in
## res://maps/biome_<biome>.txt; biomes without a file use "wall".

const PARCEL := 4
const MAX_TRIES := 30
const FALLBACK_MAP := "res://maps/mission_01.txt"
const MIN_ENEMY_SPAWNS := 8
const MARKER_KEYS: Array[String] = ["evac", "beacon", "civilian", "exit", "nest", "hive", "boss", "reinforce"]

## Parcel role an "O" plot slot takes for each objective.
const OBJECTIVE_ROLE := {"extract": "evac", "hold": "beacon", "rescue": "rescue", "purge": "nest", "elite": "hive"}
## Marker an "O" cell becomes, by parcel role.
const ROLE_MARKER := {"evac": "evac", "beacon": "beacon", "rescue": "civilian", "nest": "nest", "hive": "hive"}

# Validation bands (see the design doc, Tactical maps).
const POD_STEPS := Vector2i(6, 20)        # walking distance from the drop zone: every pod cell >= x, each pod's nearest cell <= y
const EVAC_MIN_STEPS := 12
const OBJECTIVE_MIN_STEPS := 5            # civilians, nests, hive
const FULL_COVER := Vector2(0.04, 0.24)   # share of all tiles
const HALF_COVER := Vector2(0.05, 0.22)
const DEAD_GROUND := 3                    # every floor tile within this many tiles of cover
const MAX_SIGHTLINE := 12                 # longest straight open run in a row or column
const REINFORCE_MIN_STEPS := 6
const LANE_COVER_CHANCE := 0.08
const RAISED := Vector2(0.06, 0.35)       # share of all tiles on a roof (level 1 or 2)
const MIN_WAYS_UP := 2                    # stairs or ladders on the map

# The 8 symmetries of a square parcel, as (x, y) -> cell inside a PARCEL x PARCEL block.
# Breach and deploy parcels only use 0 and 4 (identity, mirror) so walls stay on their row
# and cover keeps facing the enemy side.
const ALL_TRANSFORMS: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
const UPRIGHT_TRANSFORMS: Array[int] = [0, 4]

static var _biomes := {}
## Why the last rejected layout failed validation (dev aid for tuning parcels).
static var last_reject := ""


## The map for `spec`. Rerolls up to MAX_TRIES layouts that fail validation, then falls back
## to the handmade test map (which tests assert never happens for the shipped biomes).
static func generate(spec: Dictionary) -> Grid:
	var biome := _biome_name(str(spec.get("biome", "wall")))
	var objective := str(spec.get("objective", "skirmish"))
	var data := _load_biome(biome)
	var plots: Array = data.plots.filter(func(p: Dictionary) -> bool: return p.objectives.has(objective))
	if plots.is_empty():
		objective = "skirmish"
		plots = data.plots.filter(func(p: Dictionary) -> bool: return p.objectives.has("skirmish"))
	for attempt in MAX_TRIES:
		var rng := RandomNumberGenerator.new()
		rng.seed = ("%d:%s:%s:%d" % [int(spec.get("seed", 0)), biome, objective, attempt]).hash()
		var g := _build(data, plots[rng.randi() % plots.size()], objective, rng)
		if g != null:
			g.biome = biome
			g.objective = objective
			return g
	push_warning("MapGen: no valid layout for %s, using the fallback map" % [spec])
	var fb := Grid.load_file(FALLBACK_MAP)
	fb.biome = biome
	fb.objective = "skirmish"
	return fb


static func _biome_name(b: String) -> String:
	return b if FileAccess.file_exists("res://maps/biome_%s.txt" % b) else "wall"


# ---------------------------------------------------------------- loading

static func _load_biome(biome: String) -> Dictionary:
	if _biomes.has(biome):
		return _biomes[biome]
	var data := parse(FileAccess.get_file_as_string("res://maps/biome_%s.txt" % biome))
	_biomes[biome] = data
	return data


## Parses a biome file into {"parcels": {role: [{name, rows}]}, "plots": [{name, objectives, lanes, rows}]}.
static func parse(text: String) -> Dictionary:
	var parcels := {}
	var plots: Array = []
	var current: Dictionary = {}
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with(";"):
			continue
		if line.begins_with("@"):
			var parts := line.substr(1).split(" ", false)
			if parts[0] == "plot":
				var lanes := 0
				for p in parts:
					if p.begins_with("lanes="):
						lanes = int(p.trim_prefix("lanes="))
				current = {"name": parts[2], "objectives": Array(parts[1].split(",")), "lanes": lanes, "rows": PackedStringArray()}
				plots.append(current)
			else:
				current = {"name": parts[1], "rows": PackedStringArray()}
				if not parcels.has(parts[0]):
					parcels[parts[0]] = []
				parcels[parts[0]].append(current)
			continue
		current.rows.append(line)
	return {"parcels": parcels, "plots": plots}


static func _transform(rows: PackedStringArray, t: int) -> PackedStringArray:
	var size := rows.size()
	var n := size - 1
	var out := PackedStringArray()
	for y in size:
		var row := ""
		for x in size:
			var src: Vector2i
			match t:
				0: src = Vector2i(x, y)
				1: src = Vector2i(y, n - x)
				2: src = Vector2i(n - x, n - y)
				3: src = Vector2i(n - y, x)
				4: src = Vector2i(n - x, y)
				5: src = Vector2i(y, x)
				6: src = Vector2i(x, n - y)
				_: src = Vector2i(n - y, n - x)
			row += rows[src.y][src.x]
		out.append(row)
	return out


# ---------------------------------------------------------------- building

## Draws parcels for one role without repeats until the pool runs out.
class _Pool:
	var items: Array = []
	var bag: Array = []
	var rng: RandomNumberGenerator

	func _init(source: Array, r: RandomNumberGenerator) -> void:
		items = source
		rng = r

	func draw() -> Dictionary:
		if bag.is_empty():
			bag = items.duplicate()
			# Fisher-Yates with our RNG (Array.shuffle uses the global one).
			for i in range(bag.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var tmp = bag[i]
				bag[i] = bag[j]
				bag[j] = tmp
		return bag.pop_back()


static func _build(data: Dictionary, plot: Dictionary, objective: String, rng: RandomNumberGenerator) -> Grid:
	var lanes: int = plot.lanes
	var cols: int = plot.rows[0].length()
	var prow: int = plot.rows.size()
	var step := PARCEL + lanes
	var g := Grid.new()
	g.width = cols * PARCEL + (cols - 1) * lanes
	g.height = prow * PARCEL + (prow - 1) * lanes
	g.tiles.resize(g.width * g.height)
	g.tiles.fill(Types.Tile.FLOOR)

	var pools := {}
	var slot_role := {"D": "deploy", "B": "breach", "E": "pod", "F": "filler", "T": "tower",
		"L": "landmark", "O": OBJECTIVE_ROLE.get(objective, "filler")}
	var deploy: Array[Vector2i] = []
	var pods: Array = []                  # one Array[Vector2i] per pod parcel
	var markers := {}
	for k in MARKER_KEYS:
		markers[k] = []
	var reserved := {}                    # cells the fix-up passes must leave as floor
	var spine_rows: Array[int] = []
	var landmarked := {}                  # plot slots already covered by an 8x8 landmark
	for py in prow:
		for px in cols:
			if landmarked.has(Vector2i(px, py)):
				continue
			var role: String = slot_role[plot.rows[py][px]]
			if role == "breach" and not spine_rows.has(py * step + 1):
				spine_rows.append(py * step + 1)
			var size := PARCEL
			if role == "landmark":
				if not data.parcels.has("landmark"):
					role = "tower"
				else:
					size = PARCEL * 2
					for k in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
						landmarked[Vector2i(px, py) + k] = true
			if not pools.has(role):
				pools[role] = _Pool.new(data.parcels.get(role, data.parcels.filler), rng)
			var parcel: Dictionary = pools[role].draw()
			var options: Array[int] = UPRIGHT_TRANSFORMS if role in ["breach", "deploy"] else ALL_TRANSFORMS
			var rows := _transform(parcel.rows, options[rng.randi() % options.size()])
			var pod: Array[Vector2i] = []
			for y in size:
				for x in size:
					var c := Vector2i(px * step + x, py * step + y)
					var ch := rows[y][x]
					var t := g.read_glyph(c, ch)
					match ch:
						"?": t = Types.Tile.LOW if rng.randf() < 0.5 else Types.Tile.FLOOR
						"/", "s", "|", "S":
							reserved[c] = true
						"P":
							deploy.append(c)
							reserved[c] = true
						"E", "e":
							if ch == "e":
								g.set_level(c, 1)
							pod.append(c)
							reserved[c] = true
						"O":
							markers[ROLE_MARKER.get(role, "hive")].append(c)
							reserved[c] = true
					g.tiles[c.y * g.width + c.x] = t
			if not pod.is_empty():
				pods.append(pod)

	# Lanes between parcels: open ground with a little scattered cover; the cordon wall runs through them.
	if lanes > 0:
		for y in g.height:
			for x in g.width:
				if x % step < PARCEL and y % step < PARCEL:
					continue
				if spine_rows.has(y) and y % step < PARCEL:
					g.tiles[y * g.width + x] = Types.Tile.WALL
				elif rng.randf() < LANE_COVER_CHANCE:
					g.tiles[y * g.width + x] = Types.Tile.LOW

	if objective == "boss":
		var centre := Vector2i(g.width / 2, g.height / 2)
		for y in range(centre.y - 2, centre.y + 3):
			for x in range(centre.x - 2, centre.x + 3):
				if g.in_bounds(Vector2i(x, y)):
					g.tiles[y * g.width + x] = Types.Tile.FLOOR
					g.set_level(Vector2i(x, y), 0)
					g.ladders.erase(Vector2i(x, y))
					g.stairs.erase(Vector2i(x, y))
					g.fragile.erase(Vector2i(x, y))
					reserved[Vector2i(x, y)] = true
		markers.boss.append(centre)

	# Roofs are laid out by hand and every ladder and stair needs both ends clear: the fix-up passes leave them be.
	for l in g.ladders.keys() + g.stairs.keys():
		for d in Grid.DIRS4:
			reserved[l + d] = true
	for y in g.height:
		for x in g.width:
			if g.level(Vector2i(x, y)) > 0:
				reserved[Vector2i(x, y)] = true
	deploy.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	if deploy.size() < 4 or pods.is_empty():
		last_reject = "plot has no deploy or pods"
		return null
	_fix_dead_ground(g, reserved, rng)
	_fix_sightlines(g, reserved, rng)

	# Connectivity: everything that matters must be reachable from the drop zone and able to walk
	# back to it (drop-downs are one way); seal the rest. `back` keeps only round-trip cells.
	var dist := _distance_map(g, deploy)
	var there := g.reachable(deploy[0], g.width * g.height)
	var back := _can_return(g, [deploy[0]])
	for c in back.keys():
		if not there.has(c):
			back.erase(c)
	for k in markers:
		for c in markers[k]:
			if not dist.has(c) or not back.has(c):
				last_reject = "unreachable " + k
				return null
	for pod in pods:
		for c in pod:
			if not dist.has(c) or not back.has(c):
				last_reject = "unreachable pod"
				return null
	for c in deploy:
		if not back.has(c):
			last_reject = "drop zone pit"
			return null
	for y in g.height:
		for x in g.width:
			var c := Vector2i(x, y)
			if g.is_walkable(c) and not (dist.has(c) and back.has(c)):
				g.tiles[y * g.width + x] = Types.Tile.WALL
				dist.erase(c)
	for c in g.ladders.keys() + g.stairs.keys():
		if not g.is_walkable(c):
			g.ladders.erase(c)
			g.stairs.erase(c)

	if not _validate(g, objective, dist, deploy, pods, markers, spine_rows):
		return null

	g.player_spawns.assign(deploy)
	g.enemy_spawns.assign(_interleave_pods(g, pods, dist, reserved))
	if objective == "rescue":
		markers.exit.assign(deploy)
	if markers.hive.is_empty():
		markers.hive.append(_farthest_open(g, dist, reserved))
	markers.reinforce.assign(_reinforce_cells(g, objective, dist, markers))
	g.markers = markers
	return g


## Walking distance from the nearest deploy cell, using the game's own 8-way movement rules.
static func _distance_map(g: Grid, sources: Array[Vector2i]) -> Dictionary:
	var best := {}
	for s in sources:
		var d := g.reachable(s, g.width * g.height)
		for c in d:
			if not best.has(c) or d[c] < best[c]:
				best[c] = d[c]
	return best


## Cells from which some cell of `targets` can be walked to (Grid.step_cost run backwards).
static func _can_return(g: Grid, targets: Array[Vector2i]) -> Dictionary:
	var seen := {}
	var frontier: Array[Vector2i] = []
	for t in targets:
		seen[t] = true
		frontier.append(t)
	while not frontier.is_empty():
		var next: Array[Vector2i] = []
		for t in frontier:
			for d in Grid.DIRS8:
				var c: Vector2i = t - d
				if not seen.has(c) and g.is_walkable(c) and g.step_cost(c, d) > 0:
					seen[c] = true
					next.append(c)
		frontier = next
	return seen


static func _is_cover(g: Grid, c: Vector2i) -> bool:
	return g.in_bounds(c) and (g.tile(c) != Types.Tile.FLOOR or g.level(c) > 0)


## Adds half cover near any floor tile that has none within DEAD_GROUND tiles.
static func _fix_dead_ground(g: Grid, reserved: Dictionary, rng: RandomNumberGenerator) -> void:
	for y in g.height:
		for x in g.width:
			var c := Vector2i(x, y)
			if g.tile(c) != Types.Tile.FLOOR or _has_cover_near(g, c, DEAD_GROUND):
				continue
			var spots: Array[Vector2i] = []
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var n := c + Vector2i(dx, dy)
					if g.in_bounds(n) and g.tile(n) == Types.Tile.FLOOR and not reserved.has(n) and _isolated(g, n):
						spots.append(n)
			if not spots.is_empty():
				var s := spots[rng.randi() % spots.size()]
				g.tiles[s.y * g.width + s.x] = Types.Tile.LOW


## True when no tile around `c` blocks movement, so a block placed there can never seal a path.
static func _isolated(g: Grid, c: Vector2i) -> bool:
	for d in Grid.DIRS8:
		if g.in_bounds(c + d) and not g.is_walkable(c + d):
			return false
	return true


static func _has_cover_near(g: Grid, c: Vector2i, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if _is_cover(g, c + Vector2i(dx, dy)):
				return true
	return false


## Breaks straight open runs longer than MAX_SIGHTLINE with a block of full cover.
static func _fix_sightlines(g: Grid, reserved: Dictionary, rng: RandomNumberGenerator) -> void:
	for horizontal in [true, false]:
		var lines: int = g.height if horizontal else g.width
		var length: int = g.width if horizontal else g.height
		for i in lines:
			var run: Array[Vector2i] = []
			for j in length + 1:
				var c: Vector2i = Vector2i(j, i) if horizontal else Vector2i(i, j)
				if j < length and not g.blocks_los(c):
					run.append(c)
					continue
				if run.size() > MAX_SIGHTLINE:
					_block_sightline(g, run, horizontal, reserved, rng)
				run.clear()


## Turns one tile in the middle third of `run` into full cover. Raising half cover to full
## costs no walking room, so that is tried first; a floor tile is used only if it does not
## touch another wall across the run, so repeated fixes never stack into a sealed line.
static func _block_sightline(g: Grid, run: Array[Vector2i], horizontal: bool, reserved: Dictionary, rng: RandomNumberGenerator) -> void:
	var middle := run.slice(run.size() / 3, run.size() * 2 / 3 + 1)
	var across: Vector2i = Vector2i(0, 1) if horizontal else Vector2i(1, 0)
	var lows := middle.filter(func(c: Vector2i) -> bool: return g.tile(c) == Types.Tile.LOW and not reserved.has(c))
	var floors := middle.filter(func(c: Vector2i) -> bool:
		return g.tile(c) == Types.Tile.FLOOR and not reserved.has(c) \
			and g.tile(c + across) != Types.Tile.WALL and g.tile(c - across) != Types.Tile.WALL)
	var pick: Array = lows if not lows.is_empty() else floors
	if pick.is_empty():
		return
	var s: Vector2i = pick[rng.randi() % pick.size()]
	g.tiles[s.y * g.width + s.x] = Types.Tile.WALL


static func _validate(g: Grid, objective: String, dist: Dictionary, deploy: Array[Vector2i], pods: Array,
		markers: Dictionary, spine_rows: Array[int]) -> bool:
	for pod in pods:
		var nearest := 1 << 30
		for c in pod:
			nearest = mini(nearest, dist[c])
		if nearest < POD_STEPS.x or nearest > POD_STEPS.y:
			last_reject = "pod distance %d" % nearest
			return false
	for c in markers.evac:
		if dist[c] < EVAC_MIN_STEPS:
			last_reject = "evac too close"
			return false
	for k in ["civilian", "nest", "hive"]:
		for c in markers[k]:
			if dist[c] < OBJECTIVE_MIN_STEPS:
				last_reject = k + " too close"
				return false
	var nests: Array = markers.nest
	for i in nests.size():
		for j in range(i + 1, nests.size()):
			var d: Vector2i = (nests[i] - nests[j]).abs()
			if maxi(d.x, d.y) < 5:
				last_reject = "nests bunched"
				return false
	# The cordon wall keeps at least 2 separate gaps.
	for y in spine_rows:
		var gaps := 0
		var open := false
		for x in g.width:
			var walk := g.is_walkable(Vector2i(x, y))
			if walk and not open:
				gaps += 1
			open = walk
		if gaps < 2:
			last_reject = "wall has %d gaps" % gaps
			return false
	var full := 0
	var half := 0
	for t in g.tiles:
		if t == Types.Tile.WALL:
			full += 1
		elif t == Types.Tile.LOW:
			half += 1
	var total := float(g.tiles.size())
	var raised := g.levels.size() - g.levels.count(0) if not g.levels.is_empty() else 0
	if raised / total < RAISED.x or raised / total > RAISED.y:
		last_reject = "raised %.2f" % (raised / total)
		return false
	var ways_up := 0
	for c in g.ladders.keys() + g.stairs.keys():
		if g.is_walkable(c):
			ways_up += 1
	if ways_up < MIN_WAYS_UP:
		last_reject = "only %d ways up" % ways_up
		return false
	if full / total < FULL_COVER.x or full / total > FULL_COVER.y:
		last_reject = "full cover %.2f" % (full / total)
		return false
	if half / total < HALF_COVER.x or half / total > HALF_COVER.y:
		last_reject = "half cover %.2f" % (half / total)
		return false
	return true


## Pod cells round-robin across pods so taking the first N spreads enemies out, topped up
## with free cells next to the pods until there are MIN_ENEMY_SPAWNS.
static func _interleave_pods(g: Grid, pods: Array, dist: Dictionary, reserved: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var groups: Array = []
	var longest := 0
	for pod in pods:
		groups.append(pod.duplicate())
		longest = maxi(longest, pod.size())
	for k in longest:
		for pod in pods:
			if k < pod.size():
				out.append(pod[k])
	# Top up one pod at a time, growing each by a free neighbour of its own cells.
	var stuck := 0
	var i := 0
	while out.size() < MIN_ENEMY_SPAWNS and stuck < groups.size():
		var group: Array = groups[i % groups.size()]
		var grown := false
		for c in group:
			for d in Grid.DIRS8:
				var n: Vector2i = c + d
				if dist.has(n) and not out.has(n) and not reserved.has(n) and dist[n] >= POD_STEPS.x:
					group.append(n)
					out.append(n)
					grown = true
					break
			if grown:
				break
		stuck = 0 if grown else stuck + 1
		i += 1
	return out


## The open floor cell farthest from the drop zone (a default Hive node spot for nest fights).
static func _farthest_open(g: Grid, dist: Dictionary, reserved: Dictionary) -> Vector2i:
	var best := Vector2i(-1, -1)
	for c in dist:
		if reserved.has(c):
			continue
		if best.x < 0 or dist[c] > dist[best] or (dist[c] == dist[best] and (c.y < best.y or c.y == best.y and c.x < best.x)):
			best = c
	return best


## Edge cells where reinforcement waves enter, chosen by objective, never near the drop zone.
static func _reinforce_cells(g: Grid, objective: String, dist: Dictionary, markers: Dictionary) -> Array[Vector2i]:
	var edge: Array[Vector2i] = []
	for y in g.height:
		for x in g.width:
			var c := Vector2i(x, y)
			var on_edge := x == 0 or y == 0 or x == g.width - 1 or y == g.height - 1
			if on_edge and dist.has(c) and dist[c] >= REINFORCE_MIN_STEPS:
				edge.append(c)
	# Lower score = preferred. Ties break on position so every peer picks the same cells.
	var score := func(c: Vector2i) -> float:
		match objective:
			"extract":   # behind and beside the squad's start
				return float(-c.y)
			"hold":      # the two side edges
				return 0.0 if c.x == 0 or c.x == g.width - 1 else 100.0
			"rescue":    # near the civilians
				var best := 1e9
				for v in markers.civilian:
					best = minf(best, Vector2(c - v).length())
				return best
		return float(c.y)  # far edge first
	edge.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var sa: float = score.call(a)
		var sb: float = score.call(b)
		if sa != sb:
			return sa < sb
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	var out: Array[Vector2i] = []
	for c in edge:
		if out.size() >= 6:
			break
		if out.all(func(o: Vector2i) -> bool: return maxi(absi(o.x - c.x), absi(o.y - c.y)) >= 2):
			out.append(c)
	return out
