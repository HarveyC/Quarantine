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
const MARKER_KEYS: Array[String] = ["evac", "beacon", "civilian", "exit", "nest", "hive", "boss", "reinforce", "charge", "relay", "sample"]

## Parcel role an "O" plot slot takes for each objective.
const OBJECTIVE_ROLE := {"extract": "evac", "hold": "beacon", "rescue": "rescue", "purge": "nest", "elite": "hive",
	"escort": "evac", "demolish": "site", "hack": "site", "samples": "site"}
## Marker an "O" cell becomes, by parcel role.
const ROLE_MARKER := {"evac": "evac", "beacon": "beacon", "rescue": "civilian", "nest": "nest", "hive": "hive"}
## "site" parcels serve three objectives; the objective decides what their O cell becomes.
const SITE_MARKER := {"demolish": "charge", "hack": "relay", "samples": "sample"}

# Validation bands (see the design doc, Tactical maps).
const POD_STEPS := Vector2i(6, 20)        # walking distance from the drop zone: every pod cell >= x, each pod's nearest cell <= y
const GRAND_WIDTH := 26                   # maps this wide or wider (5x5 plots are 28x28) get GRAND_POD_MAX
const GRAND_POD_MAX := 27
const EVAC_MIN_STEPS := 12
const OBJECTIVE_MIN_STEPS := 5            # civilians, nests, hive
const FULL_COVER := Vector2(0.03, 0.24)   # share of all tiles
const HALF_COVER := Vector2(0.04, 0.22)
const DEAD_GROUND := 4                    # every floor tile within this many tiles of cover
const MAX_SIGHTLINE := 24                 # longest straight open run in a row or column
## Lane plots (three routes between the drop court and the objective, see maps/biome_*.txt) are
## picked this often when the objective has any; the older free-form plots share the rest.
const LANE_PLOT_PREFIX := "lanes_"
const LANE_PLOT_SHARE := 0.65
const DROP_SIGHT_CAP := 0.35              # share of walkable ground the drop zone can see on turn one
const DROP_SIGHT_SLABS := 10              # blast walls the sight pass may add to get under the cap
const BOSS_DEAD_GROUND := 3               # boss arenas keep the tighter fix-ups they were tuned on
const BOSS_MAX_SIGHTLINE := 12
const REINFORCE_MIN_STEPS := 6
const RAISED := Vector2(0.04, 0.35)       # share of all tiles on a roof (level 1 or 2)
const MIN_WAYS_UP := 2                    # stairs or ladders on the map

# Open ground: every plot gets streets at least MIN_LANES wide between its parcels. Streets carry
# the odd short sandbag line instead of scattered crates, and loose single crates in parcels are
# thinned out (structured cover such as lines, buildings and roofs stays).
const MIN_LANES := 2
const LANE_BARRICADE_CHANCE := 0.3        # per street segment beside a parcel
const DECLUTTER_CHANCE := 0.5             # a lone half-cover tile is cleared
const QUERY_LOW_CHANCE := 0.35            # a "?" in a parcel becomes half cover

# The 8 symmetries of a square parcel, as (x, y) -> cell inside a PARCEL x PARCEL block.
# Breach and deploy parcels only use 0 and 4 (identity, mirror) so walls stay on their row
# and cover keeps facing the enemy side.
const ALL_TRANSFORMS: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
const UPRIGHT_TRANSFORMS: Array[int] = [0, 4]

static var _biomes := {}
## Generated fuel barrels per map (when its parcels place none), and where they may go.
const BARRELS := 2
const BARREL_DROP_GAP := 7
const BARREL_POD_REACH := 3
## Why the last rejected layout failed validation (dev aid for tuning parcels).
static var last_reject := ""
## Name of the plot the last generated map was built from (dev aid for stats scripts).
static var last_plot := ""


## The map for `spec`. Rerolls up to MAX_TRIES layouts that fail validation, then falls back
## to the handmade test map (which tests assert never happens for the shipped biomes).
static func generate(spec: Dictionary) -> Grid:
	var biome := _biome_name(str(spec.get("biome", "wall")))
	var objective := str(spec.get("objective", "skirmish"))
	var data := _load_biome(biome)
	if objective == "boss" and not data.arenas.is_empty():
		var arng := RandomNumberGenerator.new()
		arng.seed = ("%d:%s:arena" % [int(spec.get("seed", 0)), biome]).hash()
		var arena := _build_arena(data.arenas[arng.randi() % data.arenas.size()], arng)
		if arena != null:
			arena.biome = biome
			arena.objective = objective
			last_plot = "arena"
			return arena
		push_warning("MapGen: arena for %s is invalid: %s" % [biome, last_reject])
	var plots: Array = data.plots.filter(func(p: Dictionary) -> bool: return p.objectives.has(objective))
	if plots.is_empty():
		objective = "skirmish"
		plots = data.plots.filter(func(p: Dictionary) -> bool: return p.objectives.has("skirmish"))
	# Fights are built from places (DistrictGen); spec "layout": "plots" asks for the stamped-parcel plots instead.
	if str(spec.get("layout", "district")) == "district" and objective != "boss":
		for attempt in MAX_TRIES:
			var drng := RandomNumberGenerator.new()
			drng.seed = ("%d:%s:%s:%d:district" % [int(spec.get("seed", 0)), biome, objective, attempt]).hash()
			var dg := _build_district(biome, objective, drng)
			if dg != null:
				dg.biome = biome
				dg.objective = objective
				last_plot = "district"
				return dg
		push_warning("MapGen: no valid district for %s (%s), trying the plots" % [spec, last_reject])
	for attempt in MAX_TRIES:
		var rng := RandomNumberGenerator.new()
		rng.seed = ("%d:%s:%s:%d" % [int(spec.get("seed", 0)), biome, objective, attempt]).hash()
		var pool: Array = plots
		var lane_plots: Array = plots.filter(func(p: Dictionary) -> bool: return str(p.name).begins_with(LANE_PLOT_PREFIX))
		if not lane_plots.is_empty() and rng.randf() < LANE_PLOT_SHARE:
			pool = lane_plots
		var plot_of: Dictionary = pool[rng.randi() % pool.size()]
		var g := _build(data, plot_of, objective, rng)
		if g != null:
			g.biome = biome
			g.objective = objective
			last_plot = str(plot_of.get("name", ""))
			return g
	push_warning("MapGen: no valid layout for %s, using the fallback map" % [spec])
	var fb := Grid.load_file(FALLBACK_MAP)
	fb.biome = biome
	fb.objective = "skirmish"
	return fb


## A boss arena drawn whole in the biome file (20x20, plain glyphs; P deploy, E pod cells, B boss
## anchor). Mirrored left-right half the time. Null (with last_reject set) when it is not playable.
static func _build_arena(arena: Dictionary, rng: RandomNumberGenerator) -> Grid:
	var rows := PackedStringArray()
	var flip := rng.randf() < 0.5
	for r in arena.rows:
		# B and b mark the boss anchor on the ground and on an upper roof; both are floor in the grid.
		var row: String = r.replace("B", ".").replace("b", "2")
		rows.append(row.reverse() if flip else row)
	var g := Grid.from_rows(rows)
	var deploy: Array[Vector2i] = []
	var pods: Array[Vector2i] = []
	var boss := Vector2i(-1, -1)
	for y in g.height:
		for x in g.width:
			match arena.rows[y][(g.width - 1 - x) if flip else x]:
				"P": deploy.append(Vector2i(x, y))
				"E": pods.append(Vector2i(x, y))
				"B", "b": boss = Vector2i(x, y)
	if deploy.size() < 4 or pods.size() < MIN_ENEMY_SPAWNS or boss.x < 0:
		last_reject = "arena needs 4 deploy cells, %d pod cells and a boss anchor" % MIN_ENEMY_SPAWNS
		return null
	deploy.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var dist := _distance_map(g, deploy)
	var back := _can_return(g, [deploy[0]])
	for c in pods + [boss]:
		if not dist.has(c) or not back.has(c):
			last_reject = "arena cell %s unreachable" % c
			return null
	for y in g.height:
		for x in g.width:
			var c := Vector2i(x, y)
			if g.is_walkable(c) and not (dist.has(c) and back.has(c)):
				g.tiles[y * g.width + x] = Types.Tile.WALL
	var markers := {}
	for k in MARKER_KEYS:
		markers[k] = []
	markers.boss.append(boss)
	g.player_spawns.assign(deploy)
	g.enemy_spawns.assign(pods)
	markers.reinforce.assign(_reinforce_cells(g, "boss", dist, markers))
	g.markers = markers
	_place_barrels(g, deploy, rng)
	return g


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
	var arenas: Array = []
	var current: Dictionary = {}
	for raw in text.split("\n"):
		# Only the right side is trimmed: a double-resolution row can start with an open border (a space).
		var line := raw.strip_edges(false, true)
		if line.strip_edges().is_empty() or line.begins_with(";"):
			continue
		if line.begins_with("@"):
			var parts := line.substr(1).split(" ", false)
			if parts[0] == "arena":
				current = {"name": parts[1], "rows": PackedStringArray()}
				arenas.append(current)
			elif parts[0] == "plot":
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
	for role in parcels:
		for parcel in parcels[role]:
			parcel.rows = _double(parcel.rows)
	return {"parcels": parcels, "plots": plots, "arenas": arenas}


## A parcel's rows at double resolution (cells at odd positions, borders between; see
## Grid.from_edge_rows). Plain parcels (4 or 8 rows of cells) get open borders; parcels drawn with
## edge walls (9 or 17 rows) are padded back to full width.
static func _double(rows: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	if rows.size() % 2 == 1:
		var w := rows.size()
		for r in rows:
			out.append(r.rpad(w))
		return out
	var n := rows.size()
	var rim := "+ ".repeat(n) + "+"
	out.append(rim)
	for r in rows:
		var row := " "
		for x in n:
			row += r[x] + " "
		out.append(row)
		out.append(rim)
	return out


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


static func _build_district(biome: String, objective: String, rng: RandomNumberGenerator) -> Grid:
	var d := DistrictGen.build(biome, objective, rng)
	if d.is_empty():
		return null
	var spine: Array[int] = []
	return _finish(d.grid, objective, d.deploy, d.pods, d.markers, d.reserved, spine, rng, true)


static func _build(data: Dictionary, plot: Dictionary, objective: String, rng: RandomNumberGenerator) -> Grid:
	# Boss arenas stay exactly as they were (20x20, cover as drawn): the fight is about the boss,
	# not the approach, and their balance is tuned on that layout.
	var open_ground := objective != "boss"
	var lanes: int = maxi(plot.lanes, MIN_LANES) if open_ground else plot.lanes
	var query_low := QUERY_LOW_CHANCE if open_ground else 0.5
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
		"L": "landmark", "C": "compound", "R": "roofline", "S": "street", "O": OBJECTIVE_ROLE.get(objective, "filler")}
	var deploy: Array[Vector2i] = []
	var pods: Array = []                  # one Array[Vector2i] per pod parcel
	var markers := {}
	for k in MARKER_KEYS:
		markers[k] = []
	var reserved := {}                    # cells the fix-up passes must leave as floor
	var spine_rows: Array[int] = []
	var landmarked := {}                  # plot slots already covered by an 8x8 landmark
	var stamped := {}                     # cells laid out by a parcel (a landmark's whole span), not street
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
			var split := Grid.split_edge_rows(_transform(parcel.rows, options[rng.randi() % options.size()]))
			var rows: PackedStringArray = split.cells
			var origin := Vector2i(px * step, py * step)
			if size > PARCEL:
				# A landmark spans two slots and the street between them: centre it in that span.
				var span := PARCEL * 2 + lanes
				for y in span:
					for x in span:
						stamped[origin + Vector2i(x, y)] = true
				origin += Vector2i(lanes / 2, lanes / 2)
			var pod: Array[Vector2i] = []
			for y in size:
				for x in size:
					var c := origin + Vector2i(x, y)
					stamped[c] = true
					var ch := rows[y][x]
					var t := g.read_glyph(c, ch)
					match ch:
						"?": t = Types.Tile.LOW if rng.randf() < query_low else Types.Tile.FLOOR
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
							markers[SITE_MARKER[objective] if role == "site" else ROLE_MARKER.get(role, "hive")].append(c)
							reserved[c] = true
					g.tiles[c.y * g.width + c.x] = t
			for e in split.edges:
				g.set_edge(origin + e[0], e[1], e[2])
			if not pod.is_empty():
				pods.append(pod)

	# Streets between parcels: open ground; the cordon wall runs through them.
	for y in g.height:
		for x in g.width:
			if not stamped.has(Vector2i(x, y)) and spine_rows.has(y) and y % step < PARCEL:
				g.tiles[y * g.width + x] = Types.Tile.WALL
	_street_barricades(g, cols, prow, step, lanes, stamped, rng)
	if open_ground:
		_declutter(g, reserved, rng)

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
					for d in Grid.DIRS4:
						g.set_edge(Vector2i(x, y), d, Grid.EDGE_NONE)
					reserved[Vector2i(x, y)] = true
		markers.boss.append(centre)

	return _finish(g, objective, deploy, pods, markers, reserved, spine_rows, rng, false)


## Fix-ups, connectivity and validation shared by plot layouts and district layouts. `district`
## layouts keep sight in check with the places themselves, so the T-wall passes are skipped and the
## drop-zone cap below only rejects.
static func _finish(g: Grid, objective: String, deploy: Array[Vector2i], pods: Array, markers: Dictionary,
		reserved: Dictionary, spine_rows: Array[int], rng: RandomNumberGenerator, district: bool) -> Grid:
	var open_ground := objective != "boss"
	# Roofs are laid out by hand and every ladder and stair needs both ends clear: the fix-up passes leave them be.
	for l in g.ladders.keys() + g.stairs.keys():
		for d in Grid.DIRS4:
			reserved[l + d] = true
	for y in g.height:
		for x in g.width:
			if g.level(Vector2i(x, y)) > 0:
				reserved[Vector2i(x, y)] = true
	# The fix-ups also leave every cell beside an edge wall alone (doorways, rooms, railings).
	var fixed := reserved.duplicate()
	for k in g.edges:
		for c in Grid.edge_cells(k):
			fixed[c] = true
	deploy.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	if deploy.size() < 4 or pods.is_empty():
		last_reject = "plot has no deploy or pods"
		return null
	_fix_dead_ground(g, fixed, rng, DEAD_GROUND if open_ground else BOSS_DEAD_GROUND)
	if not district:
		_fix_sightlines(g, fixed, rng, MAX_SIGHTLINE if open_ground else BOSS_MAX_SIGHTLINE)
		if open_ground:
			_cap_drop_sight(g, deploy, fixed, rng)

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
	if open_ground and drop_sight(g, deploy[0]) > DROP_SIGHT_CAP:
		last_reject = "drop zone sees %.2f" % drop_sight(g, deploy[0])
		return null

	g.player_spawns.assign(deploy)
	g.enemy_spawns.assign(_interleave_pods(g, pods, dist, reserved))
	_place_barrels(g, deploy, rng)
	if objective in ["rescue", "samples"]:
		markers.exit.assign(deploy)
	if markers.hive.is_empty():
		markers.hive.append(_farthest_open(g, dist, reserved))
	markers.reinforce.assign(_reinforce_cells(g, objective, dist, markers))
	g.markers = markers
	return g


## Share of the walkable ground-level tiles a soldier at `from` can see (map geometry only: walls,
## edge walls and raised cells block as in Combat.line_clear). `step` 2 samples every other tile.
static func drop_sight(g: Grid, from: Vector2i, step := 1) -> float:
	var seen := 0
	var total := 0
	for y in range(0, g.height, step):
		for x in range(0, g.width, step):
			var c := Vector2i(x, y)
			if not g.is_walkable(c) or g.level(c) > 0:
				continue
			total += 1
			if Combat.line_clear(g, from, c, g.level(from)):
				seen += 1
	return seen / float(maxi(total, 1))


## Breaks up the drop zone's view: blast walls across the open ground 4 to 10 tiles out, each the
## one of a few random candidates that hides the most, until the drop zone sees DROP_SIGHT_CAP or less.
static func _cap_drop_sight(g: Grid, deploy: Array[Vector2i], reserved: Dictionary, rng: RandomNumberGenerator) -> void:
	var from := deploy[0]
	var best_share := drop_sight(g, from, 2)
	for pass_i in DROP_SIGHT_SLABS:
		if best_share <= DROP_SIGHT_CAP - 0.02:
			return
		var pick := []
		for tries in 24:
			var c := Vector2i(rng.randi_range(0, g.width - 1), rng.randi_range(0, g.height - 1))
			var d := maxi(absi(c.x - from.x), absi(c.y - from.y))
			if d < 4 or d > 10:
				continue
			var along: Vector2i = Vector2i(1, 0) if rng.randf() < 0.5 else Vector2i(0, 1)
			var side: Vector2i = Vector2i(0, 1) if along.x == 1 else Vector2i(1, 0)
			if not _slab_room(g, c, along, side, reserved):
				continue
			g.set_edge(c, along, Grid.EDGE_WALL)
			g.set_edge(c + side, along, Grid.EDGE_WALL)
			var share := drop_sight(g, from, 2)
			g.set_edge(c, along, Grid.EDGE_NONE)
			g.set_edge(c + side, along, Grid.EDGE_NONE)
			if share < best_share - 0.005:
				best_share = share
				pick = [c, along, side]
		if pick.is_empty():
			continue
		g.set_edge(pick[0], pick[1], Grid.EDGE_WALL)
		g.set_edge(pick[0] + pick[2], pick[1], Grid.EDGE_WALL)


## Now and then a two-tile sandbag line along a street beside a parcel, so the streets stay open
## but never bare. Never on the cordon wall's row or next to other cover.
static func _street_barricades(g: Grid, cols: int, prow: int, step: int, lanes: int, stamped: Dictionary,
		rng: RandomNumberGenerator) -> void:
	if lanes == 0:
		return
	for horizontal in [true, false]:
		var bands: int = (prow if horizontal else cols) - 1
		var segs: int = cols if horizontal else prow
		var along: Vector2i = Vector2i(1, 0) if horizontal else Vector2i(0, 1)
		for b in bands:
			for s in segs:
				if rng.randf() >= LANE_BARRICADE_CHANCE:
					continue
				var lane := b * step + PARCEL + rng.randi() % lanes
				var start := s * step + rng.randi() % (PARCEL - 1)
				var a: Vector2i = Vector2i(start, lane) if horizontal else Vector2i(lane, start)
				var cells: Array[Vector2i] = [a, a + along]
				if cells.all(func(c: Vector2i) -> bool: return not stamped.has(c) and _isolated(g, c)):
					for c in cells:
						g.tiles[c.y * g.width + c.x] = Types.Tile.LOW


## Clears some of the lone half-cover tiles (a single crate with no cover around it) that parcels
## scatter, so the ground reads open. Lines, buildings, roofs and reserved cells stay.
static func _declutter(g: Grid, reserved: Dictionary, rng: RandomNumberGenerator) -> void:
	for y in g.height:
		for x in g.width:
			var c := Vector2i(x, y)
			if g.tile(c) != Types.Tile.LOW or g.level(c) != 0 or reserved.has(c) or g.is_volatile(c):
				continue
			if Grid.DIRS8.any(func(d: Vector2i) -> bool: return g.in_bounds(c + d) and g.tile(c + d) != Types.Tile.FLOOR):
				continue
			if Grid.DIRS4.any(func(d: Vector2i) -> bool: return g.edge(c, d) != Grid.EDGE_NONE):
				continue
			if rng.randf() < DECLUTTER_CHANCE:
				g.tiles[y * g.width + x] = Types.Tile.FLOOR


## Fuel barrels (see Destruction): parcels can place them with "!"; a map with none gets up to
## BARRELS of its half-cover pieces near enemy pods turned into barrels, well away from the drop
## zone and never two side by side. Runs last, so it never changes the rest of the layout.
static func _place_barrels(g: Grid, deploy: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	if not g.volatile.is_empty():
		return
	var spots: Array[Vector2i] = []
	for y in g.height:
		for x in g.width:
			var c := Vector2i(x, y)
			if g.tile(c) != Types.Tile.LOW or g.level(c) != 0:
				continue
			if deploy.any(func(d: Vector2i) -> bool: return maxi(absi(d.x - c.x), absi(d.y - c.y)) < BARREL_DROP_GAP):
				continue
			if g.enemy_spawns.any(func(e: Vector2i) -> bool: return maxi(absi(e.x - c.x), absi(e.y - c.y)) <= BARREL_POD_REACH):
				spots.append(c)
	for i in BARRELS:
		while not spots.is_empty():
			var c: Vector2i = spots.pop_at(rng.randi() % spots.size())
			if Grid.DIRS8.any(func(d: Vector2i) -> bool: return g.is_volatile(c + d)):
				continue
			g.volatile[c] = true
			break


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
	if not g.in_bounds(c):
		return false
	if g.tile(c) != Types.Tile.FLOOR or g.level(c) > 0:
		return true
	for d in Grid.DIRS4:
		if g.edge_cover(c, d) != Types.Cover.NONE:
			return true
	return false


## Adds half cover near any floor tile that has none within `reach` tiles.
static func _fix_dead_ground(g: Grid, reserved: Dictionary, rng: RandomNumberGenerator, reach: int) -> void:
	for y in g.height:
		for x in g.width:
			var c := Vector2i(x, y)
			if g.tile(c) != Types.Tile.FLOOR or _has_cover_near(g, c, reach):
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


## True when no tile around `c` blocks movement and no edge wall is near, so a block placed there
## can never seal a path.
static func _isolated(g: Grid, c: Vector2i) -> bool:
	for d in Grid.DIRS8:
		if g.in_bounds(c + d) and not g.is_walkable(c + d):
			return false
		for e in Grid.DIRS4:
			if g.edge(c + d, e) != Grid.EDGE_NONE:
				return false
	return true


static func _has_cover_near(g: Grid, c: Vector2i, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if _is_cover(g, c + Vector2i(dx, dy)):
				return true
	return false


## Breaks straight open runs longer than `longest` (an edge wall across the line ends a run too).
static func _fix_sightlines(g: Grid, reserved: Dictionary, rng: RandomNumberGenerator, longest: int) -> void:
	for horizontal in [true, false]:
		var lines: int = g.height if horizontal else g.width
		var length: int = g.width if horizontal else g.height
		var along: Vector2i = Vector2i(1, 0) if horizontal else Vector2i(0, 1)
		for i in lines:
			var run: Array[Vector2i] = []
			for j in length + 1:
				var c: Vector2i = Vector2i(j, i) if horizontal else Vector2i(i, j)
				var cut := not run.is_empty() and g.edge_blocks_los(run[-1], along)
				if j < length and not g.blocks_los(c) and not cut:
					run.append(c)
					continue
				if run.size() > longest:
					_block_sightline(g, run, horizontal, reserved, rng)
				run.clear()
				if j < length and not g.blocks_los(c):
					run.append(c)


## Breaks `run` in its middle third with a two-cell blast wall (T-wall) across it on a cell border,
## only where the ground all around is open so it never seals a path. (No more lone wall blocks:
## a run with no room for a T-wall is left alone.)
static func _block_sightline(g: Grid, run: Array[Vector2i], horizontal: bool, reserved: Dictionary, rng: RandomNumberGenerator) -> void:
	var middle := run.slice(run.size() / 3, run.size() * 2 / 3 + 1)
	var along: Vector2i = Vector2i(1, 0) if horizontal else Vector2i(0, 1)
	var across: Vector2i = Vector2i(0, 1) if horizontal else Vector2i(1, 0)
	var spots: Array = []
	for c in middle:
		for side in [across, -across]:
			if _slab_room(g, c, along, side, reserved):
				spots.append([c, side])
	if not spots.is_empty():
		var pick: Array = spots[rng.randi() % spots.size()]
		g.set_edge(pick[0], along, Grid.EDGE_WALL)
		g.set_edge(pick[0] + pick[1], along, Grid.EDGE_WALL)


## Room for a T-wall on the border after `c` (direction `along`) and the same border one cell to
## `side`: the four cells beside it are open ground floor with nothing on that border, and the
## cells just past both ends are open too, so there is always a way around it.
static func _slab_room(g: Grid, c: Vector2i, along: Vector2i, side: Vector2i, reserved: Dictionary) -> bool:
	for b in [-1, 0, 1, 2]:
		var n: Vector2i = c + side * b
		for a in [0, 1]:
			var m: Vector2i = n + along * a
			if not g.in_bounds(m) or not g.is_walkable(m) or g.level(m) != 0:
				return false
			if (b == 0 or b == 1) and reserved.has(m):
				return false
		if g.edge(n, along) != Grid.EDGE_NONE:
			return false
	return true


static func _validate(g: Grid, objective: String, dist: Dictionary, deploy: Array[Vector2i], pods: Array,
		markers: Dictionary, spine_rows: Array[int]) -> bool:
	for pod in pods:
		var nearest := 1 << 30
		for c in pod:
			nearest = mini(nearest, dist[c])
		if nearest < POD_STEPS.x or nearest > (GRAND_POD_MAX if g.width >= GRAND_WIDTH else POD_STEPS.y):
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
	var edge_full := 0
	var edge_half := 0
	for k in g.edges:
		match g.edges[k]:
			Grid.EDGE_WALL: edge_full += 1
			Grid.EDGE_WINDOW, Grid.EDGE_LOW: edge_half += 1
	var total := float(g.tiles.size())
	full += int(edge_full / 2.0)
	half += int(edge_half / 2.0)
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
