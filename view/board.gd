extends Node3D
## 3D tiles for a Grid plus the tactical overlays drawn on top of it
## (reachable cells, path preview, cover shields, hover cursor, cell markers).
## One grid cell = one world unit; cell (x, y) sits at world (x, 0, y), or (x, RAISE, y) on high
## ground, so everything placed with cell_to_world (units, props, overlays) sits on the roof.
##
## Set dressing (all cosmetic, derived from the grid and a position hash so every
## peer builds the same scene): grimy concrete, varied cover props, rubble, glowing
## infection puddles, a chain-link perimeter and sodium floodlights.

const Palette := preload("res://view/palette.gd")
const Styles := preload("res://ui/styles.gd")

var grid: Grid
var _tiles: Node3D
## Ground, objective zones, perimeter and lights: built once, untouched by rebuild_tiles.
var _fixed: Node3D
var _range_layer: Node3D
var _path_layer: Node3D
var _cover_layer: Node3D
var _mark_layer: Node3D
var _blast_layer: Node3D
var _hazard_layer: Node3D
var _sight_layer: Node3D   # enemy sight while Concealed; kept until show_sight / clear_sight
var _sight_key := ""
var _hazard_nodes := {}   # cell -> Node3D
var _hazard_kinds := {}   # cell -> hazard kind, for the region outlines and the legend
var _hazard_edges: Node3D
var _charge_labels: Array[Label3D] = []   # one per charge site, in marker order
var _zone_keys: Array[String] = []   # objective zones on this map (TileOverlays.ZONES)
var _sight_cells := {}
var _blast_cells := {}
var _mark_kind := ""
var _hover: Node3D

var _m_range: StandardMaterial3D
var _m_path: StandardMaterial3D
var _m_dest: StandardMaterial3D
var _m_half: StandardMaterial3D
var _m_full: StandardMaterial3D

static var _grime_tex: Texture2D
static var _fence_tex: Texture2D
## The grid being shown, for cell heights in the static helpers (one board at a time).
static var _shown: Grid

## World height of one level of high ground.
const RAISE := 1.2


## Steps drawn on a stair cell; each one is RAISE / STAIR_STEPS tall and 1 / STAIR_STEPS deep.
const STAIR_STEPS := 4


static func cell_to_world(c: Vector2i, y := 0.0) -> Vector3:
	return Vector3(c.x, y + stand(c), c.y)


## World height of a cell's floor (on stairs and ramps, the bottom they rise from).
static func lift(c: Vector2i) -> float:
	return RAISE * _shown.level(c) if _shown != null else 0.0


## World height a unit stands at in the middle of a cell: the floor, or the step under the
## centre of stairs and rubble ramps.
static func stand(c: Vector2i) -> float:
	return surface(Vector2(c.x, c.y))


## A point `t` (0..1) of the way along a one-cell move from `a` to `b`. Moves on and off stairs
## and ramps follow the steps; every other move (a ladder climb, a drop) slides straight.
static func walk_point(a: Vector2i, b: Vector2i, t: float) -> Vector3:
	var p := cell_to_world(a).lerp(cell_to_world(b), t)
	if _shown != null and (_shown.is_stairs(a) or _shown.is_stairs(b)) and absi(_shown.level(a) - _shown.level(b)) <= 1:
		p.y = surface(Vector2(p.x, p.z))
	return p


## Which way a stair or ramp cell climbs: towards its first walkable neighbour one level up
## (the same one _add_stairs and _add_ramp build towards). ZERO for every other cell.
static func stair_dir(c: Vector2i) -> Vector2i:
	if _shown == null or not _shown.is_stairs(c):
		return Vector2i.ZERO
	for d in Grid.DIRS4:
		var n: Vector2i = c + d
		if _shown.in_bounds(n) and _shown.level(n) == _shown.level(c) + 1 and _shown.is_walkable(n):
			return d
	return Vector2i.ZERO


## World height of the walkable surface at a ground-plane point (x, z): the top of the step
## under it on stairs, the slab on a rubble ramp, the floor anywhere else.
static func surface(p: Vector2) -> float:
	var c := Vector2i(roundi(p.x), roundi(p.y))
	var base := lift(c)
	var d := stair_dir(c)
	if d == Vector2i.ZERO:
		return base
	# 0 at the low edge of the cell, 1 at the edge against the level above
	var u := clampf((p - Vector2(c)).dot(Vector2(d)) + 0.5, 0.0, 1.0)
	if _shown.rubble.get(c, "") == "roof":
		return base + 0.08 + (RAISE - 0.08) * u
	var step := clampi(floori(u * STAIR_STEPS) + 1, 1, STAIR_STEPS)
	return base + RAISE * float(step) / STAIR_STEPS


## The grid on show, or null before a board is built (the lineup).
static func shown() -> Grid:
	return _shown


static func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x), roundi(p.z))


func center() -> Vector3:
	return Vector3((grid.width - 1) * 0.5, 0, (grid.height - 1) * 0.5)


func build(g: Grid) -> void:
	grid = g
	_shown = g
	_fixed = _layer("Fixed")
	_tiles = _layer("Tiles")
	_range_layer = _layer("Range")
	_path_layer = _layer("Path")
	_cover_layer = _layer("Cover")
	_mark_layer = _layer("Marks")
	_blast_layer = _layer("Blast")
	_hazard_layer = _layer("Hazards")
	_sight_layer = _layer("Sight")
	_hazard_edges = _layer("HazardEdges")
	_m_range = Palette.overlay(Color(TileOverlays.MOVE, 0.07))
	_m_path = Palette.overlay(Color(Palette.AMBER, 0.9))
	_m_dest = Palette.overlay(Color(Palette.AMBER, 0.45))
	_m_half = Palette.overlay(Color(0.95, 0.8, 0.3, 0.85), true)
	_m_full = Palette.overlay(Color(0.35, 0.7, 1.0, 0.9), true)
	_build_ground()
	_build_tiles()
	_build_roofs()
	_build_zones()
	_build_water()
	_build_links()
	_build_perimeter()
	_build_lights()
	_hover = _brackets(Palette.overlay(Color(1, 1, 1, 0.9)), 0.46, 0.2)
	_hover.visible = false
	add_child(_hover)


## Flooded cells (Grid.water): a shallow translucent pool over the floor with a paler sheen on top.
func _build_water() -> void:
	if grid.water.is_empty():
		return
	var layer := _layer("Water")
	var pool := Palette.overlay(Color(0.2, 0.42, 0.62, 0.62))
	var sheen := Palette.overlay(Color(0.55, 0.78, 0.95, 0.18))
	var cells: Array = grid.water.keys()
	cells.sort()
	for c in cells:
		var plate := Palette.box(Vector3(1.0, 0.04, 1.0), pool)
		plate.position = cell_to_world(c, 0.0) + Vector3(0, 0.03, 0)
		layer.add_child(plate)
		var h := _hash(c)
		var glint := Palette.box(Vector3(0.5, 0.01, 0.12), sheen)
		glint.position = cell_to_world(c, 0.0) + Vector3(float(h % 5) / 10.0 - 0.2, 0.06, float((h >> 3) % 5) / 10.0 - 0.2)
		layer.add_child(glint)


## Each link has its own colour; both ends and the cable share it,.
const LINK_COLORS: Array[Color] = [Color("ffb938"), Color("b48cff"), Color("8be28b"), Color("ff8fa3")]
var _link_ends := {}        # cell -> index into grid.links
var _link_layer: Node3D     # hover hint: the line to the other end


static func link_color(i: int) -> Color:
	return LINK_COLORS[i % LINK_COLORS.size()]


## A flat or sloped strip between two world points.
func _strip(a: Vector3, b: Vector3, width: float, material: Material) -> MeshInstance3D:
	var span := b - a
	var strip := Palette.box(Vector3(width, 0.03, span.length()), material)
	strip.transform = Transform3D(Basis.looking_at(span.normalized(), Vector3.UP), (a + b) * 0.5)
	return strip


## Zipline cables with chevrons pointing downhill, and cellar hatches. Linked ends share a colour; the
## tunnel's two hatches share a colour; the hover card names them.
func _build_links() -> void:
	_link_ends.clear()
	if grid.links.is_empty():
		return
	var layer := _layer("Links")
	var steel := Palette.mat(Color("8c97a0"), 0.5)
	var dark := Palette.overlay(Color(0.02, 0.02, 0.03, 0.92))
	for i in grid.links.size():
		var l: Dictionary = grid.links[i]
		var col := link_color(i)
		var glow := Palette.emissive(col, 1.0)
		var mark := Palette.overlay(Color(col, 0.5))
		var ends: Array = [l.a, l.b]
		for c in ends:
			_link_ends[c] = i
		if l.kind == "zip":
			var top: Array[Vector3] = []
			for c in ends:
				var base := cell_to_world(c)
				var post := Palette.box(Vector3(0.08, 1.3, 0.08), steel)
				post.position = base + Vector3(0, 0.65, 0)
				layer.add_child(post)
				var plate := Palette.box(Vector3(0.9, 0.02, 0.9), mark)
				plate.position = base + Vector3(0, 0.03, 0)
				layer.add_child(plate)
				top.append(base + Vector3(0, 1.25, 0))
			layer.add_child(_strip(top[0], top[1], 0.035, glow))
			# Chevrons along the cable point the way down.
			var dir := (top[1] - top[0]).normalized()
			for t in [0.3, 0.5, 0.7]:
				var tip := MeshInstance3D.new()
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 0.13
				cone.height = 0.3
				cone.radial_segments = 4
				tip.mesh = cone
				tip.material_override = glow
				tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				tip.transform = Transform3D(Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.RIGHT, -PI / 2), top[0].lerp(top[1], t))
				layer.add_child(tip)
		else:
			for c in ends:
				var base := cell_to_world(c)
				var hatch := Palette.box(Vector3(0.82, 0.03, 0.82), dark)
				hatch.position = base + Vector3(0, 0.035, 0)
				layer.add_child(hatch)
				for side in [Vector3(0.43, 0, 0), Vector3(-0.43, 0, 0), Vector3(0, 0, 0.43), Vector3(0, 0, -0.43)]:
					var bar := Palette.box(Vector3(0.06 if side.x != 0 else 0.92, 0.05, 0.06 if side.z != 0 else 0.92), glow)
					bar.position = base + side + Vector3(0, 0.05, 0)
					layer.add_child(bar)
	_link_layer = _layer("LinkHint")


## The link whose end is `c`, as an index into Grid.links (-1 for none).
func link_at(c: Vector2i) -> int:
	return int(_link_ends.get(c, -1))


## Hovering a link end draws a line to where it comes out and rings the exit; the hover card
## names it and its cost.
func show_link_hint(c: Vector2i) -> void:
	if _link_layer == null:
		return
	_clear(_link_layer)
	var i := link_at(c)
	if i < 0:
		return
	var l: Dictionary = grid.links[i]
	var other: Vector2i = l.b if c == l.a else l.a
	var col := link_color(i)
	var from := cell_to_world(c, 0.0) + Vector3(0, 0.08, 0)
	var to := cell_to_world(other, 0.0) + Vector3(0, 0.08, 0)
	var dash := Palette.overlay(Color(col, 0.9), true)
	var span := to - from
	var n := int(span.length() / 0.5)
	for k in range(0, n, 2):
		_link_layer.add_child(_strip(from + span * (float(k) / n), from + span * (float(k + 1) / n), 0.12, dash))
	var ring := Palette.ring(0.34, 0.44, Palette.overlay(Color(col, 0.95), true))
	ring.position = to
	ring.scale.y = 0.2
	_link_layer.add_child(ring)


## Link exits a soldier can reach this turn, ringed in the link's colour with the way in: called with the move range.
func _mark_link_exits(cells: Dictionary) -> void:
	for i in grid.links.size():
		var l: Dictionary = grid.links[i]
		for end in [l.b, l.a]:
			if end == l.a and not l.both:
				continue
			if not cells.has(end):
				continue
			var ring := Palette.ring(0.3, 0.4, Palette.overlay(Color(link_color(i), 0.95), true))
			ring.position = cell_to_world(end, 0.04)
			ring.scale.y = 0.2
			_range_layer.add_child(ring)


## Four L-shaped corner marks round a cell (the hover cursor, aimed cells). `half` is the
## distance from the centre to a corner, `arm` the length of each leg.
static func _brackets(m: Material, half: float, arm: float, thick := 0.045) -> Node3D:
	var n := Node3D.new()
	for k in 4:
		var sx := 1.0 if k % 2 == 0 else -1.0
		var sz := 1.0 if k < 2 else -1.0
		for bar in [Vector3(arm, 0.012, thick), Vector3(thick, 0.012, arm)]:
			var b := Palette.box(bar, m)
			b.position = Vector3(sx * (half - bar.x * 0.5), 0, sz * (half - bar.z * 0.5))
			n.add_child(b)
	return n


## Rebuilds the tile props after the grid changed (cover smashed by a Brute or an airstrike).
## Only the prop layer is rebuilt: the ground, objective zones, perimeter and lights stay.
func rebuild_tiles() -> void:
	_clear(_tiles)
	_build_tiles()


func _layer(n: String) -> Node3D:
	var l := Node3D.new()
	l.name = n
	add_child(l)
	return l


## Tileable grime: layered noise baked once into a texture shared by every surface.
static func grime_texture() -> Texture2D:
	if _grime_tex == null:
		var n := FastNoiseLite.new()
		n.seed = 11
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.035
		n.fractal_octaves = 5
		var img := n.get_seamless_image(256, 256)
		img.convert(Image.FORMAT_RGB8)
		# Push contrast so stains read, keep it bright enough to multiply with tints.
		for y in 256:
			for x in 256:
				var v := img.get_pixel(x, y).r
				v = clampf(0.78 + (v - 0.5) * 0.7, 0.45, 1.0)
				img.set_pixel(x, y, Color(v, v * 0.98, v * 0.94))
		img.generate_mipmaps()
		_grime_tex = ImageTexture.create_from_image(img)
	return _grime_tex


static func grimy(color: Color, roughness := 0.9, scale := 0.25, metallic := 0.0) -> StandardMaterial3D:
	var m := Palette.mat(color, roughness, metallic)
	m.albedo_texture = grime_texture()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	return m


static func fence_texture() -> Texture2D:
	if _fence_tex == null:
		var img := Image.create(64, 64, true, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var wire := Color(0.55, 0.57, 0.55, 1)
		for i in 64:
			for w in 2:
				img.set_pixel((i + w) % 64, i, wire)
				img.set_pixel((63 - i + w) % 64, i, wire)
		img.generate_mipmaps()
		_fence_tex = ImageTexture.create_from_image(img)
	return _fence_tex


func _build_ground() -> void:
	var ground := Palette.box(Vector3(grid.width + 40, 0.1, grid.height + 40), grimy(BiomeLook.of(grid.biome).ground, 1.0, 0.08))
	ground.position = center() + Vector3(0, -0.26, 0)
	_fixed.add_child(ground)


func _hash(c: Vector2i) -> int:
	return absi((c.x * 73856093) ^ (c.y * 19349663))


func _build_tiles() -> void:
	var look := BiomeLook.of(grid.biome)
	var floor_mats: Array[StandardMaterial3D] = []
	for col in look.floor:
		floor_mats.append(grimy(col, 0.95, 0.18))
	var wall_mat := grimy(look.wall.darkened(0.35), 0.45, 0.75)   # reinforced steel plate
	var trim_mat := Palette.mat(look.trim, 0.6, 0.4)
	var rib_mat := grimy(look.wall.lightened(0.12), 0.5, 0.7, 0.2)
	var hazard := Palette.mat(Palette.AMBER.darkened(0.15), 0.7)
	var crate_mat := grimy(look.crate, 0.9, 0.5)
	var band_mat := Palette.mat(Palette.CRATE_BAND, 0.7, 0.3)
	var bag_mat := grimy(Color("5b5640"), 1.0, 0.6)
	var concrete := grimy(Color("6a6862"), 0.95, 0.4)
	# Plain drums are grey and olive: red with an amber band is kept for fuel barrels that explode.
	var barrel_mats: Array[StandardMaterial3D] = [grimy(Color("4a4d48"), 0.7, 0.5, 0.3), grimy(Color("3c4a3a"), 0.7, 0.5, 0.3)]
	var fuel_mat := grimy(Color("a3301f"), 0.55, 0.6, 0.35)
	var lamp_mat := Palette.emissive(Palette.AMBER, 2.4)
	var crack_mat := Palette.mat(Color("0d0e0f"), 1.0)
	var rebar_mat := Palette.mat(Color("6b4a32"), 0.6, 0.6)
	var scorch_mat := Palette.mat(Color("121110"), 1.0)
	var rubble := grimy(Color("3d3c38"), 1.0, 0.6)
	# Kept dim: these are stains for mood, not a marking (spores are the bright teal ones).
	var goo_mat := Palette.emissive(Palette.TEAL_DIM, 0.6)
	var goo_lights := 0
	var roof_mat := grimy(look.wall.darkened(0.25), 0.9, 0.3)
	var deck_mat := grimy(look.deck, 0.6, 0.35, 0.4)   # steel decking: roofs read lighter than the ground
	var lip_mat := Palette.emissive(Palette.AMBER, 0.6)
	var ladder_mat := Palette.mat(Palette.AMBER.darkened(0.3), 0.6, 0.5)
	var deck2_mat := grimy(Color("a3a89c"), 0.55, 0.35, 0.45)  # upper roofs read lighter still
	var plank_mat := grimy(Color("7a5a36"), 0.95, 0.5)        # scaffold planks: wood says "breaks"
	var pole_mat := Palette.mat(Color("8c8a80"), 0.5, 0.7)
	var tarp_mat := grimy(Color("4f5a44"), 1.0, 0.4)
	var stair_mat := grimy(Color("77786f"), 0.85, 0.4, 0.2)
	var indoor := _indoor_cells()
	var indoor_mats: Array[StandardMaterial3D] = [grimy(look.indoor, 0.8, 0.5), grimy(look.indoor.darkened(0.12), 0.8, 0.5)]
	for y in grid.height:
		for x in grid.width:
			var c := Vector2i(x, y)
			var h := _hash(c)
			var shade := (h % 3) + (1 if (x + y) % 2 == 0 else 0)
			var top_mat: Material = floor_mats[shade % floor_mats.size()]
			if indoor.has(c) and grid.level(c) == 0:
				top_mat = indoor_mats[(x + y) % 2]
			if grid.is_fragile(c):
				top_mat = plank_mat
			elif grid.level(c) > 1:
				top_mat = deck2_mat
			elif grid.level(c) > 0:
				top_mat = deck_mat
			var tile := Palette.box(Vector3(0.97, 0.2, 0.97), top_mat)
			tile.position = Vector3(c.x, lift(c) - 0.1, c.y)
			_tiles.add_child(tile)
			if grid.is_fragile(c):
				_add_scaffold(c, h, pole_mat, tarp_mat, lip_mat)
			elif grid.level(c) > 0:
				_add_platform(c, h, roof_mat, lip_mat)
			if grid.is_ladder(c):
				_add_ladder(c, ladder_mat)
			var broke: String = grid.rubble.get(c, "")
			if grid.is_stairs(c) and broke == "roof":
				_add_ramp(c, h, rubble)
			elif grid.is_stairs(c):
				_add_stairs(c, stair_mat, lip_mat)
			if grid.tile(c) != Types.Tile.WALL and grid.level(c) > 0 and grid.wear.has(c):
				_add_cracks(c, h, grid.level(c) * RAISE, crack_mat, true)
			match grid.tile(c):
				Types.Tile.WALL:
					_add_wall(c, h, wall_mat, trim_mat, rib_mat, hazard)
					if grid.wear.has(c):
						_add_cracks(c, h, 2.2, crack_mat, false)
						_add_rubble(c, h ^ 0x55, rubble)
				Types.Tile.LOW:
					if grid.is_volatile(c):
						_add_fuel_drums(c, h, fuel_mat, hazard, lamp_mat)
					elif broke == "heap":
						_add_heap(c, h, concrete, rebar_mat)
					else:
						match (h >> 3) % 4:
							0: _add_crate(c, h, crate_mat, band_mat)
							1: _add_sandbags(c, h, bag_mat)
							2: _add_barrier(c, h, concrete, hazard)
							_: _add_barrels(c, h, barrel_mats)
				_:
					if broke != "" and broke != "roof":
						_add_debris(c, h, broke, rubble, plank_mat, scorch_mat)
					elif grid.is_stairs(c):
						pass   # nothing loose on the steps: it would float over the lower ones
					elif h % look.goo_every == 0:
						_add_goo(c, h, goo_mat, goo_lights < GameSettings.puddle_lights())
						goo_lights += 1
					elif h % 5 == 0:
						_add_rubble(c, h, rubble)
	_build_edges(look, trim_mat, hazard, crack_mat)
	# Painted road markings across the deployment zone.
	var paint := Palette.mat(Color(Palette.AMBER, 1.0).darkened(0.35), 0.9)
	for x in grid.width:
		if x % 2 == 0:
			var dash := Palette.box(Vector3(0.55, 0.005, 0.08), paint)
			dash.position = Vector3(x, 0.003, grid.height - 3.5)
			_tiles.add_child(dash)


## Ground cells inside a building: shut off from the map's rim by edge walls, windows, doorways and
## wall tiles. They get an indoor floor so rooms read from the camera.
func _indoor_cells() -> Dictionary:
	var out := {}
	if grid.edges.is_empty():
		return out
	var outside := {}
	var frontier: Array[Vector2i] = []
	for y in grid.height:
		for x in grid.width:
			var c := Vector2i(x, y)
			if (x == 0 or y == 0 or x == grid.width - 1 or y == grid.height - 1) and grid.tile(c) != Types.Tile.WALL:
				outside[c] = true
				frontier.append(c)
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_back()
		for d in Grid.DIRS4:
			var n := c + d
			if grid.in_bounds(n) and not outside.has(n) and grid.tile(n) != Types.Tile.WALL and grid.edge(c, d) == Grid.EDGE_NONE:
				outside[n] = true
				frontier.append(n)
	for y in grid.height:
		for x in grid.width:
			var c := Vector2i(x, y)
			if not outside.has(c) and grid.tile(c) != Types.Tile.WALL:
				out[c] = true
	return out


## Roofs: drawn only as a thin outline round each connected group of roofed cells, so the interior is
## always visible from the camera while the outline shows a roof is there (it still blocks sight for
## the rules).
const ROOF_THICK := 0.06
const ROOF_LINE := 0.07


func _build_roofs() -> void:
	if grid.roofed.is_empty():
		return
	var look := BiomeLook.of(grid.biome)
	var line := Palette.emissive(look.trim.lightened(0.35), 0.8)
	var layer := _layer("Roofs")
	var y := EDGE_HEIGHT + ROOF_THICK * 0.5
	for c in grid.roofed:
		for d in Grid.DIRS4:
			if grid.roofed.has(c + d):
				continue
			var bar := Palette.box(Vector3(1.0 if d.x == 0 else ROOF_LINE, ROOF_THICK, 1.0 if d.y == 0 else ROOF_LINE), line)
			bar.position = Vector3(c.x + d.x * 0.5, y, c.y + d.y * 0.5)
			layer.add_child(bar)


## Edge walls: thin walls, windows, low walls and door frames on the borders between cells, with
## a post wherever walls meet so corners read solid.
const EDGE_HEIGHT := 1.9
const EDGE_THICK := 0.16


func _build_edges(look: Dictionary, trim: Material, hazard: Material, crack_mat: Material) -> void:
	if grid.edges.is_empty():
		return
	var wall := grimy(look.partition.lightened(0.42), 0.95, 0.0)   # plain and pale: it breaks
	var dark := grimy(look.partition.darkened(0.35), 0.9, 0.35)
	var frame := Palette.mat(look.trim.lightened(0.1), 0.5, 0.5)
	var glass := Palette.mat(Color(0.35, 0.5, 0.55, 1.0), 0.15, 0.6)
	var low := grimy(Color("6a6862"), 0.95, 0.4)
	var posts := {}
	var keys: Array = grid.edges.keys()
	keys.sort()
	for k in keys:
		var kind: int = grid.edges[k]
		var cells := Grid.edge_cells(k)
		var base := RAISE * mini(grid.level(cells[0]), grid.level(cells[1]))
		var top := RAISE * maxi(grid.level(cells[0]), grid.level(cells[1]))
		var mid := Vector3(cells[0].x, 0, cells[0].y) + (Vector3(0.5, 0, 0) if k.z == 0 else Vector3(0, 0, 0.5))
		var size := func(along: float, tall: float, thick: float) -> Vector3:
			return Vector3(thick, tall, along) if k.z == 0 else Vector3(along, tall, thick)
		var put := func(m: Material, along: float, y0: float, y1: float, thick := EDGE_THICK, shift := 0.0) -> MeshInstance3D:
			var b := Palette.box(size.call(along, y1 - y0, thick), m)
			b.position = mid + Vector3(0, (y0 + y1) * 0.5, 0) + (Vector3(0, 0, shift) if k.z == 0 else Vector3(shift, 0, 0))
			_tiles.add_child(b)
			return b
		var h := top - base + EDGE_HEIGHT
		match kind:
			Grid.EDGE_WALL:
				put.call(wall, 1.0, base, base + h)
				put.call(dark, 1.0, base, base + 0.25, EDGE_THICK + 0.04)
				put.call(trim, 1.04, base + h, base + h + 0.06, EDGE_THICK + 0.06)
				if grid.edge_wear.has(k):
					put.call(crack_mat, 0.5, base + 0.4, base + 1.3, EDGE_THICK + 0.02, 0.1)
			Grid.EDGE_WINDOW:
				put.call(wall, 1.0, base, base + 0.85)
				put.call(trim, 1.04, base + 0.85, base + 0.91, EDGE_THICK + 0.08)
				put.call(wall, 1.0, base + h - 0.4, base + h)
				put.call(trim, 1.04, base + h, base + h + 0.06, EDGE_THICK + 0.06)
				for side in [-0.44, 0.44]:
					put.call(frame, 0.12, base + 0.85, base + h - 0.4, EDGE_THICK + 0.02, side)
				put.call(frame, 0.06, base + 0.91, base + h - 0.4, 0.05)   # mullion
				put.call(glass, 0.8, base + 1.3, base + h - 0.4, 0.02).transparency = 0.6
				if grid.edge_wear.has(k):
					put.call(crack_mat, 0.4, base + 0.2, base + 0.7, EDGE_THICK + 0.02, -0.15)
			Grid.EDGE_LOW:
				put.call(low, 0.98, base, base + 0.8, 0.26)
				put.call(hazard if (k.x + k.y) % 3 == 0 else trim, 1.0, base + 0.8, base + 0.86, 0.3)
			Grid.EDGE_CLOSED:
				put.call(wall, 1.0, base, base + h - 0.3)
				put.call(frame, 0.82, base + 0.05, base + h - 0.4, EDGE_THICK + 0.05)
				put.call(Palette.emissive(Palette.AMBER, 0.8), 0.18, base + 1.0, base + 1.14, EDGE_THICK + 0.1, 0.3)   # handle
				put.call(wall, 1.0, base + h - 0.3, base + h)
				put.call(Palette.emissive(Palette.AMBER, 0.8), 0.6, base + h - 0.36, base + h - 0.3, EDGE_THICK + 0.04)
			Grid.EDGE_DOOR:
				for side in [-0.42, 0.42]:
					put.call(wall, 0.16, base, base + h, EDGE_THICK + 0.02, side)
				put.call(wall, 1.0, base + h - 0.3, base + h)
				put.call(Palette.emissive(Palette.AMBER, 0.8), 0.6, base + h - 0.36, base + h - 0.3, EDGE_THICK + 0.04)
		if kind != Grid.EDGE_LOW:
			for end in [-0.5, 0.5]:
				var p := mid + (Vector3(0, 0, end) if k.z == 0 else Vector3(end, 0, 0))
				var pk := Vector2i(roundi(p.x * 2.0), roundi(p.z * 2.0))
				posts[pk] = maxf(float(posts.get(pk, 0.0)), base + h)
	for pk in posts:
		var post := Palette.box(Vector3(EDGE_THICK + 0.06, posts[pk] + 0.06, EDGE_THICK + 0.06), dark)
		post.position = Vector3(pk.x * 0.5, (posts[pk] + 0.06) * 0.5, pk.y * 0.5)
		_tiles.add_child(post)


const HAZARD_COLORS := {"fire": TileOverlays.FIRE, "spore": Palette.TEAL, "acid": TileOverlays.ACID, "smoke": TileOverlays.SMOKE, "live": Color("7fd0ff")}


## Draws (or redraws) hazard `kind` on `cells`. Each kind has its own floor pattern and props
## (TileOverlays): fire = warning stripes, embers and a light; spores = a field of dots and
## floating pods; acid = blotches. Every hazard area also gets an outline in its colour.
func set_hazard(cells: Array, kind: String) -> void:
	var color: Color = HAZARD_COLORS.get(kind, Color.WHITE)
	var pat := TileOverlays.pattern(kind)
	var plate_mat := TileOverlays.floor_material(Color(color, 0.55 if kind == "fire" else 0.5), pat, {"hatch": 2.0, "puddle": 0.5}.get(pat, 1.0))
	var glow := Palette.emissive(color, 2.2 if kind == "fire" else 1.2)
	var lights := 0
	for c in cells:
		_drop_hazard(c)
		var n := Node3D.new()
		n.position = cell_to_world(c, 0.0)
		_hazard_layer.add_child(n)
		_hazard_nodes[c] = n
		_hazard_kinds[c] = kind
		if kind == "smoke":
			_add_smoke(n, c, color)
			continue
		var plate := Palette.box(Vector3(1.0, 0.015, 1.0), plate_mat)
		plate.position.y = 0.012
		n.add_child(plate)
		var h := _hash(c)
		match kind:
			"fire":   # flickering embers
				for i in 3:
					var bit := Palette.box(Vector3.ONE * 0.12, glow)
					bit.position = Vector3(float((h >> (i * 3)) % 7) / 7.0 - 0.43, 0.08, float((h >> (i * 3 + 9)) % 7) / 7.0 - 0.43)
					bit.set_meta("bob", Vector3(0.08, 0.06, 7.0))
					n.add_child(bit)
			"spore":  # round pods drifting at knee height
				for i in 2:
					var pod := MeshInstance3D.new()
					var sm := SphereMesh.new()
					sm.radius = 0.055
					sm.height = 0.11
					sm.radial_segments = 8
					sm.rings = 4
					pod.mesh = sm
					pod.material_override = glow
					pod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					pod.position = Vector3(float((h >> (i * 3)) % 7) / 7.0 - 0.38, 0.3 + 0.12 * i, float((h >> (i * 3 + 9)) % 7) / 7.0 - 0.38)
					pod.set_meta("bob", Vector3(pod.position.y, 0.07, 1.6))
					n.add_child(pod)
		if kind == "fire" and lights < 3:
			lights += 1
			var l := OmniLight3D.new()
			l.light_color = color
			l.light_energy = 1.6
			l.omni_range = 2.4
			l.position.y = 0.5
			n.add_child(l)
	_outline_hazards()


## A smoke grenade's cloud on one tile: a pale ground haze and a few soft billboard puffs
## stacked to head height, so a soldier inside reads as hidden in it.
func _add_smoke(n: Node3D, c: Vector2i, color: Color) -> void:
	n.set_meta("smoke", true)
	var plate := Palette.box(Vector3(1.0, 0.015, 1.0), Palette.overlay(Color(color, 0.2)))
	plate.position.y = 0.012
	n.add_child(plate)
	var h := _hash(c)
	for i in 4:
		var m := Palette.overlay(Color(color, 0.34 - i * 0.04))
		m.albedo_texture = _soft_puff()
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		var q := QuadMesh.new()
		q.size = Vector2.ONE * (1.7 - i * 0.15)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(float((h >> (i * 3)) % 5) / 10.0 - 0.2, 0.35 + i * 0.42, float((h >> (i * 3 + 7)) % 5) / 10.0 - 0.2)
		mi.set_meta("base", mi.position)
		n.add_child(mi)


static var _puff_tex: Texture2D


static func _soft_puff() -> Texture2D:
	if _puff_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 64
		tex.height = 64
		_puff_tex = tex
	return _puff_tex


func clear_hazard(cells: Array) -> void:
	for c in cells:
		_drop_hazard(c)
	_outline_hazards()


func _drop_hazard(c: Vector2i) -> void:
	if _hazard_nodes.has(c):
		_hazard_nodes[c].queue_free()
		_hazard_nodes.erase(c)
	_hazard_kinds.erase(c)


## Redraws the outline round every hazard area, one colour per kind (smoke has none: the cloud
## is its own edge).
func _outline_hazards() -> void:
	_clear(_hazard_edges)
	var by_kind := {}
	for c in _hazard_kinds:
		var k: String = _hazard_kinds[c]
		if k == "smoke":
			continue
		if not by_kind.has(k):
			by_kind[k] = {}
		by_kind[k][c] = true
	for k in by_kind:
		_outline(by_kind[k], Palette.overlay(Color(HAZARD_COLORS.get(k, Color.WHITE), 0.85)), 0.05, _hazard_edges)


## The hazard kind on `c` as drawn ("" for none).
func hazard_at(c: Vector2i) -> String:
	return str(_hazard_kinds.get(c, ""))


## Rebuilds every hazard from state (mission start, snapshot resync).
func sync_hazards(hazards: Dictionary) -> void:
	clear_hazard(_hazard_nodes.keys())
	var by_kind := {}
	for c in hazards:
		var k: String = hazards[c].kind
		if not by_kind.has(k):
			by_kind[k] = []
		by_kind[k].append(c)
	for k in by_kind:
		set_hazard(by_kind[k], k)


## Fire flickers. Called every frame by the mission view.
func tick_hazards(t: float) -> void:
	for c in _hazard_nodes:
		var n: Node3D = _hazard_nodes[c]
		if n.has_meta("smoke"):   # the cloud drifts slowly instead of flickering
			for child in n.get_children():
				if child.has_meta("base"):
					var b: Vector3 = child.get_meta("base")
					var ph := float(_hash(c) % 13) + b.y * 3.0
					child.position = b + Vector3(sin(t * 0.5 + ph) * 0.12, sin(t * 0.7 + ph) * 0.05, cos(t * 0.4 + ph) * 0.12)
			continue
		for child in n.get_children():
			if child.has_meta("bob"):   # (base height, amplitude, speed)
				var b: Vector3 = child.get_meta("bob")
				child.position.y = b.x + b.y * sin(t * b.z + float(_hash(c) % 17))


## Objective zones from MapGen markers, painted on the floor with a glowing edge and named by a
## floating label: evac pad and drop zone (green), beacon (amber). See TileOverlays.ZONES.
func _build_zones() -> void:
	_zone_keys.clear()
	_charge_labels.clear()
	for key in TileOverlays.ZONES:
		var cells: Array = grid.marker(key)
		if cells.is_empty():
			continue
		_zone_keys.append(key)
		var col := TileOverlays.color(key)
		var fill := Palette.overlay(Color(col, 0.16))
		var edge := Palette.emissive(col, 1.2)
		var inside := {}
		var mid := Vector3.ZERO
		for c in cells:
			inside[c] = true
			mid += cell_to_world(c)
		for c in cells:
			var plate := Palette.box(Vector3(0.98, 0.01, 0.98), fill)
			plate.position = cell_to_world(c, 0.006)
			_fixed.add_child(plate)
			# A glowing line along the zone's outer edges.
			for d in Grid.DIRS4:
				if inside.has(c + d):
					continue
				var line := Palette.box(Vector3(0.98, 0.012, 0.05) if d.y != 0 else Vector3(0.05, 0.012, 0.98), edge)
				line.position = cell_to_world(c, 0.01) + Vector3(d.x, 0, d.y) * 0.47
				_fixed.add_child(line)
		if key == "charge":   # sites are scattered: each carries its own label, sitting on its tile
			for c in cells:
				var site := zone_label(str(TileOverlays.KINDS[key].label), col)
				site.position = cell_to_world(c) + Vector3(0, 1.1, 0)
				_fixed.add_child(site)
				_charge_labels.append(site)
			continue
		var label := zone_label(str(TileOverlays.KINDS[key].label), col)
		label.position = mid / cells.size() + Vector3(0, 1.5, 0)
		_fixed.add_child(label)


## Charge site labels follow the charge: CHARGE (idle), ARMED with the fuse, then BLOWN. A soldier
## standing on an idle site reads "END TURN TO ARM".
func refresh_charges(s: GameState) -> void:
	if _charge_labels.is_empty() or s.objective.get("kind", "") != "demolish":
		return
	var cells: Array = grid.marker("charge")
	for i in mini(cells.size(), _charge_labels.size()):
		var l := _charge_labels[i]
		var col := TileOverlays.color("charge")
		var text := "CHARGE"
		match str(s.objective.charges[i]):
			"armed":
				text = "ARMED  %d" % int(s.objective.fuse[i])
				col = Palette.DANGER
			"blown":
				text = "BLOWN"
				col = col.darkened(0.4)
			_:
				if Objectives._soldier_on(s, cells[i]):
					text = "END TURN TO ARM"
					col = Palette.AMBER
		l.text = text
		l.modulate = col.lightened(0.15)


## A floating caps label for an objective zone ("EVAC"), always facing the camera.
static func zone_label(text: String, col: Color) -> Label3D:
	var l := Label3D.new()
	l.name = "ZoneLabel"
	l.text = text
	l.font = Styles.FONT_COND_BOLD
	l.font_size = 44
	l.outline_size = 14
	l.outline_modulate = Color(0.02, 0.03, 0.03, 0.85)
	l.modulate = col.lightened(0.15)
	l.pixel_size = 0.0075
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 5
	l.outline_render_priority = 4
	return l


## Objective zones on this map, as TileOverlays keys.
func zones() -> Array[String]:
	return _zone_keys


## The objective zone `c` is in ("" for none).
func zone_at(c: Vector2i) -> String:
	for key in _zone_keys:
		if grid.marker(key).has(c):
			return key
	return ""


## The block under a raised cell, with a trim lip on its open (ledge) edges.
func _add_platform(c: Vector2i, h: int, body: Material, trim: Material) -> void:
	var top := lift(c)
	var block := Palette.box(Vector3(1.0, top, 1.0), body)
	block.position = Vector3(c.x, top * 0.5 - 0.2, c.y)
	_tiles.add_child(block)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + d
		if grid.in_bounds(n) and grid.level(n) >= grid.level(c):
			continue
		var along := Vector3(absf(d.y), 0, absf(d.x))
		var lip := Palette.box(Vector3(0.02, 0.06, 0.02) + along * 1.0, trim)
		lip.position = Vector3(c.x, top + 0.02, c.y) + Vector3(d.x, 0, d.y) * 0.49
		_tiles.add_child(lip)
		if (h + d.x * 3 + d.y * 7) % 3 == 0:
			var rib := Palette.box(Vector3(0.08, top, 0.08), trim)
			rib.position = Vector3(c.x, top * 0.5 - 0.2, c.y) + Vector3(d.x, 0, d.y) * 0.5
			_tiles.add_child(rib)


## A fragile scaffold: poles, cross braces and a tarp skirt instead of a solid block, under a
## plank deck, so it reads as something explosives can bring down.
func _add_scaffold(c: Vector2i, h: int, pole: Material, tarp: Material, trim: Material) -> void:
	var top := lift(c)
	for k in [Vector2(-0.44, -0.44), Vector2(0.44, -0.44), Vector2(-0.44, 0.44), Vector2(0.44, 0.44)]:
		var p := Palette.box(Vector3(0.07, top + 0.2, 0.07), pole)
		p.position = Vector3(c.x + k.x, top * 0.5 - 0.2, c.y + k.y)
		_tiles.add_child(p)
	var skirt := Palette.box(Vector3(0.9, top * 0.75, 0.9), tarp)
	skirt.position = Vector3(c.x, top * 0.45 - 0.2, c.y)
	_tiles.add_child(skirt)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + d
		if grid.in_bounds(n) and grid.level(n) >= grid.level(c):
			continue
		var along := Vector3(absf(d.y), 0, absf(d.x))
		var brace := Palette.box(Vector3(0.04, 0.04, 0.04) + along * 1.2, pole)
		brace.position = Vector3(c.x, top * 0.5 - 0.1, c.y) + Vector3(d.x, 0, d.y) * 0.47
		brace.rotate(Vector3(d.x, 0, d.y).abs(), deg_to_rad(35.0 if (h + d.x + d.y) % 2 == 0 else -35.0))
		_tiles.add_child(brace)
		var lip := Palette.box(Vector3(0.02, 0.05, 0.02) + along * 1.0, trim)
		lip.position = Vector3(c.x, top + 0.02, c.y) + Vector3(d.x, 0, d.y) * 0.49
		_tiles.add_child(lip)


## Stairs on a cell, rising towards the higher neighbour(s) they lead to.
func _add_stairs(c: Vector2i, m: Material, trim: Material) -> void:
	var d := stair_dir(c)
	if d == Vector2i.ZERO:
		return
	var base := lift(c)
	var out := Vector3(d.x, 0, d.y)
	var along := Vector3(absf(d.y), 0, absf(d.x))
	for i in STAIR_STEPS:
		var hgt := RAISE * float(i + 1) / STAIR_STEPS
		var depth := 1.0 / STAIR_STEPS
		var step := Palette.box(along * 0.8 + out.abs() * depth + Vector3(0, hgt, 0), m)
		step.position = Vector3(c.x, base + hgt * 0.5, c.y) + out * (-0.5 + depth * (i + 0.5))
		_tiles.add_child(step)
		var nose := Palette.box(along * 0.8 + Vector3(0.02, 0.02, 0.02), trim)
		nose.position = Vector3(c.x, base + hgt + 0.01, c.y) + out * (-0.5 + depth * i)
		_tiles.add_child(nose)


## A ladder on a ground cell, against the raised neighbour(s) it climbs to.
func _add_ladder(c: Vector2i, m: Material) -> void:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + d
		if not grid.in_bounds(n) or grid.level(n) != grid.level(c) + 1:
			continue
		var lo := minf(lift(c), lift(n))
		var hi := maxf(lift(c), lift(n))
		var face := Vector3(c.x, 0, c.y) + Vector3(d.x, 0, d.y) * (0.42 if grid.level(n) > grid.level(c) else -0.58)
		var along := Vector3(absf(d.y), 0, absf(d.x))
		for k in [-0.22, 0.22]:
			var rail := Palette.box(Vector3(0.05, hi - lo + 0.5, 0.05), m)
			rail.position = face + along * k + Vector3(0, (hi + lo) * 0.5 + 0.2, 0)
			_tiles.add_child(rail)
		var rung_y := lo + 0.2
		while rung_y < hi + 0.4:
			var rung := Palette.box(Vector3(0.03, 0.03, 0.03) + along * 0.44, m)
			rung.position = face + Vector3(0, rung_y, 0)
			_tiles.add_child(rung)
			rung_y += 0.28


## A reinforced block: dark steel plate with a hazard band at the base, a plate seam and corner
## posts, so it never reads as the pale thin walls that break.
func _add_wall(c: Vector2i, h: int, body: Material, trim: Material, rib: Material, hazard: Material) -> void:
	var w := Palette.box(Vector3(1.0, 2.2, 1.0), body)
	w.position = cell_to_world(c, 1.1)
	_tiles.add_child(w)
	var cap := Palette.box(Vector3(1.04, 0.1, 1.04), rib)
	cap.position = cell_to_world(c, 2.22)
	_tiles.add_child(cap)
	# Posts on the corners of the block, then plates and a hazard band on the faces that are not
	# against another wall.
	for sx in [-0.5, 0.5]:
		for sz in [-0.5, 0.5]:
			var post := Palette.box(Vector3(0.12, 2.24, 0.12), rib)
			post.position = cell_to_world(c, 1.12) + Vector3(sx, 0, sz)
			_tiles.add_child(post)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + d
		if grid.in_bounds(n) and grid.tile(n) == Types.Tile.WALL:
			continue
		var out := Vector3(d.x, 0, d.y)
		var along := Vector3(absf(d.y), 0, absf(d.x))
		for yy in [0.35, 1.9]:
			var band := Palette.box(Vector3(1.0, 0.14, 0.03) if along.x > 0 else Vector3(0.03, 0.14, 1.0), hazard if yy < 1.0 else rib)
			band.position = cell_to_world(c, yy) + out * 0.505
			_tiles.add_child(band)
		var seam := Palette.box(Vector3(1.0, 0.05, 0.03) if along.x > 0 else Vector3(0.03, 0.05, 1.0), rib)
		seam.position = cell_to_world(c, 1.15) + out * 0.505
		_tiles.add_child(seam)


func _add_crate(c: Vector2i, h: int, body: Material, band: Material) -> void:
	var crate := Palette.box(Vector3(0.9, 0.8, 0.9), body)
	crate.position = cell_to_world(c, 0.4)
	crate.rotation.y = deg_to_rad(float(h % 9) - 4.0)
	_tiles.add_child(crate)
	for yy in [0.18, -0.2]:
		var strap := Palette.box(Vector3(0.94, 0.08, 0.94), band)
		strap.position = Vector3(0, yy, 0)
		crate.add_child(strap)
	if h % 3 == 0:
		var top := Palette.box(Vector3(0.5, 0.35, 0.5), body)
		top.position = Vector3(0.1, 0.57, -0.1)
		top.rotation.y = 0.4
		crate.add_child(top)


func _add_sandbags(c: Vector2i, h: int, m: Material) -> void:
	var root := Node3D.new()
	root.position = cell_to_world(c)
	root.rotation.y = PI * 0.5 if h % 2 == 0 else 0.0
	_tiles.add_child(root)
	for row in 3:
		for i in 3:
			var mesh := CapsuleMesh.new()
			mesh.radius = 0.15
			mesh.height = 0.46
			mesh.radial_segments = 8
			mesh.rings = 2
			var bag := MeshInstance3D.new()
			bag.mesh = mesh
			bag.material_override = m
			bag.rotation = Vector3(0, 0, PI * 0.5)
			bag.scale = Vector3(1.0, 1.0, 0.75)
			bag.position = Vector3((i - 1) * 0.3 + (0.15 if row % 2 == 1 else 0.0) - 0.05, 0.12 + row * 0.2, (row - 1) * 0.05)
			root.add_child(bag)


func _add_barrier(c: Vector2i, h: int, m: Material, stripe: Material) -> void:
	var root := Node3D.new()
	root.position = cell_to_world(c)
	root.rotation.y = PI * 0.5 if h % 2 == 0 else 0.0
	_tiles.add_child(root)
	var base := Palette.box(Vector3(0.98, 0.3, 0.55), m)
	base.position.y = 0.15
	root.add_child(base)
	var top := Palette.box(Vector3(0.98, 0.5, 0.22), m)
	top.position.y = 0.55
	root.add_child(top)
	var band := Palette.box(Vector3(0.3, 0.12, 0.23), stripe)
	band.position = Vector3(-0.25, 0.6, 0)
	root.add_child(band)


func _add_barrels(c: Vector2i, h: int, mats: Array[StandardMaterial3D]) -> void:
	for i in 3:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.2
		mesh.bottom_radius = 0.2
		mesh.height = 0.62
		mesh.radial_segments = 12
		var b := MeshInstance3D.new()
		b.mesh = mesh
		b.material_override = mats[(h + i) % mats.size()]
		var ang := float(i) * TAU / 3.0 + float(h % 7)
		b.position = cell_to_world(c, 0.31) + Vector3(cos(ang), 0, sin(ang)) * 0.22
		_tiles.add_child(b)


## Height above the floor that shots at a fuel barrel aim for: the middle of its 0.74 m drums.
const FUEL_DRUM_AIM := 0.4


## Fuel barrel (Destruction): a pair of red drums with an amber hazard band and a small warning
## lamp on top, so it reads as "explodes" from any camera angle.
func _add_fuel_drums(c: Vector2i, h: int, body: Material, band: Material, lamp: Material) -> void:
	for i in 2:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.24
		mesh.bottom_radius = 0.24
		mesh.height = 0.74
		mesh.radial_segments = 16
		var drum := MeshInstance3D.new()
		drum.mesh = mesh
		drum.material_override = body
		var off := Vector3(-0.17 if i == 0 else 0.19, 0, 0.12 if i == 0 else -0.14).rotated(Vector3.UP, float(h % 6))
		drum.position = cell_to_world(c, 0.37) + off
		_tiles.add_child(drum)
		var ring := CylinderMesh.new()
		ring.top_radius = 0.245
		ring.bottom_radius = 0.245
		ring.height = 0.1
		ring.radial_segments = 16
		var stripe := MeshInstance3D.new()
		stripe.mesh = ring
		stripe.material_override = band
		stripe.position = Vector3(0, 0.12, 0)
		drum.add_child(stripe)
		if i == 0:
			var cap := Palette.box(Vector3(0.09, 0.07, 0.09), lamp)
			cap.position = Vector3(0, 0.4, 0)
			drum.add_child(cap)


## A broken wall's rubble heap (half cover you can see over): slabs, chunks and bent rebar.
func _add_heap(c: Vector2i, h: int, m: Material, rebar: Material) -> void:
	var root := Node3D.new()
	root.position = cell_to_world(c)
	root.rotation.y = float(h % 4) * PI * 0.5
	_tiles.add_child(root)
	var base := Palette.box(Vector3(0.9, 0.34, 0.8), m)
	base.position = Vector3(0, 0.12, 0)
	base.rotation = Vector3(0.12, 0.2, -0.08)
	root.add_child(base)
	for i in 5:
		var k := float((h >> (i * 2)) % 10) / 10.0
		var slab := Palette.box(Vector3(0.36 + k * 0.2, 0.12 + k * 0.08, 0.3), m)
		slab.position = Vector3(-0.3 + i * 0.15, 0.32 + k * 0.18, (k - 0.5) * 0.5)
		slab.rotation = Vector3(k * 0.9 - 0.4, k * 3.0, 0.5 - k)
		root.add_child(slab)
	for i in 3:
		var bar := Palette.box(Vector3(0.025, 0.55, 0.025), rebar)
		bar.position = Vector3(-0.2 + i * 0.2, 0.5, -0.1 + i * 0.08)
		bar.rotation = Vector3(0.5 - i * 0.35, 0.0, -0.4 + i * 0.4)
		root.add_child(bar)


## What's left on a cleared cell: chunks and splinters ("debris"), a burnt-out drum and a scorch
## mark ("barrel"), or fallen planks and poles ("scaffold").
func _add_debris(c: Vector2i, h: int, kind: String, chunk: Material, plank: Material, scorch: Material) -> void:
	var floor_y := lift(c)
	var mark := Palette.box(Vector3(0.9, 0.012, 0.8), scorch) if kind == "barrel" else null
	if mark != null:
		mark.position = Vector3(c.x, floor_y + 0.006, c.y)
		mark.rotation.y = float(h % 7)
		_tiles.add_child(mark)
		var shell := CylinderMesh.new()
		shell.top_radius = 0.2
		shell.bottom_radius = 0.26
		shell.height = 0.22
		shell.radial_segments = 10
		var drum := MeshInstance3D.new()
		drum.mesh = shell
		drum.material_override = scorch
		drum.position = Vector3(c.x + 0.15, floor_y + 0.1, c.y - 0.1)
		drum.rotation = Vector3(1.2, float(h % 5), 0.3)
		_tiles.add_child(drum)
	var mat := plank if kind == "scaffold" else chunk
	for i in 4 + h % 3:
		var k := float((h >> (i * 3)) % 100) / 100.0
		var sz := Vector3(0.5, 0.05, 0.1) if kind == "scaffold" else Vector3(0.12, 0.08, 0.1) * (0.8 + k)
		var bit := Palette.box(sz, mat)
		var k2 := float((h >> (i * 5)) % 100) / 100.0
		bit.position = Vector3(c.x + (k - 0.5) * 0.8, floor_y + sz.y * 0.5, c.y + (k2 - 0.5) * 0.8)
		bit.rotation = Vector3(0, k * 6.0, k * 0.6)
		_tiles.add_child(bit)


## Cracks on a damaged wall's faces (`top` = false) or across a cracked roof (`top` = true).
func _add_cracks(c: Vector2i, h: int, height: float, m: Material, top: bool) -> void:
	var base := lift(c) if not top else 0.0
	if top:
		for i in 3:
			var k := float((h >> (i * 4)) % 16) / 16.0
			var line := Palette.box(Vector3(0.5 - k * 0.2, 0.012, 0.035), m)
			line.position = Vector3(c.x + (k - 0.5) * 0.5, height + 0.004, c.y + (i - 1) * 0.22)
			line.rotation.y = k * 2.5 - 1.2
			_tiles.add_child(line)
		return
	for d in Grid.DIRS4:
		var n: Vector2i = c + d
		if grid.in_bounds(n) and grid.tile(n) == Types.Tile.WALL:
			continue
		var out := Vector3(d.x, 0, d.y)
		var along := Vector3(absf(d.y), 0, absf(d.x))
		for i in 3:
			var k := float((h >> (i * 4 + d.x + 2)) % 16) / 16.0
			var seg := Palette.box(Vector3(0.03, 0.55 + k * 0.4, 0.03), m)
			seg.position = Vector3(c.x, base, c.y) + out * 0.515 + along * (k - 0.5) * 0.7 + Vector3(0, 0.6 + i * 0.5, 0)
			seg.rotate(out.abs(), (k - 0.5) * 1.4)
			_tiles.add_child(seg)
		var chip := Palette.box(Vector3(0.3, 0.22, 0.12), m)   # a bite out of the top edge
		chip.position = Vector3(c.x, base + height - 0.08, c.y) + out * 0.47 + along * 0.2
		_tiles.add_child(chip)


## A collapsed roof cell: a slope of broken slabs from its new floor up to the level above,
## walkable like stairs (Destruction makes it a ramp).
func _add_ramp(c: Vector2i, h: int, m: Material) -> void:
	var d := stair_dir(c)
	if d == Vector2i.ZERO:
		return
	var base := lift(c)
	var out := Vector3(d.x, 0, d.y)
	var along := Vector3(absf(d.y), 0, absf(d.x))
	var slab := Palette.box(along * 0.95 + out.abs() * 1.25 + Vector3(0, 0.16, 0), m)
	slab.position = Vector3(c.x, base + RAISE * 0.45, c.y) + out * 0.02
	slab.rotate(along, atan2(RAISE, 1.0) * (d.x - d.y))   # high end towards the roof
	_tiles.add_child(slab)
	for i in 4:
		var k := float((h >> (i * 3)) % 8) / 8.0
		var chunk := Palette.box(Vector3(0.22, 0.16, 0.2) * (0.8 + k), m)
		chunk.position = Vector3(c.x, base + 0.1 + k * 0.4, c.y) + along * (k - 0.5) * 0.7 + out * (-0.35 + i * 0.2)
		chunk.rotation = Vector3(k, k * 4.0, 0.3)
		_tiles.add_child(chunk)


func _add_rubble(c: Vector2i, h: int, m: Material) -> void:
	for i in 1 + h % 3:
		var k := float((h >> (i * 3)) % 100) / 100.0
		var s := 0.06 + k * 0.1
		var r := Palette.box(Vector3(s * 1.4, s, s), m)
		r.position = cell_to_world(c, s * 0.4) + Vector3(k - 0.5, 0, float((h >> (i * 5)) % 100) / 100.0 - 0.5) * 0.8
		r.rotation = Vector3(k * 2.0, k * 6.0, k)
		_tiles.add_child(r)


## Small glowing infection puddles scattered on the floor for mood.
func _add_goo(c: Vector2i, h: int, material: Material, with_light: bool) -> void:
	var mesh := CylinderMesh.new()
	var r := 0.18 + float(h % 5) * 0.04
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = 0.02
	var goo := MeshInstance3D.new()
	goo.mesh = mesh
	goo.material_override = material
	goo.position = cell_to_world(c, 0.01) + Vector3(float(h % 7) * 0.05 - 0.15, 0, float(h % 5) * 0.05 - 0.1)
	goo.scale = Vector3(1.0, 1.0, 0.6 + float(h % 4) * 0.15)
	_tiles.add_child(goo)
	if with_light:
		var light := OmniLight3D.new()
		light.light_color = Palette.TEAL
		light.light_energy = 0.4
		light.omni_range = 1.8
		light.position = goo.position + Vector3(0, 0.3, 0)
		_tiles.add_child(light)


## Chain-link fence around the board with posts, plus a few container stacks outside.
func _build_perimeter() -> void:
	if grid.biome == "port":
		BiomeLook.build_port_perimeter(_fixed, grid)
		return
	if grid.biome == "bore":
		BiomeLook.build_bore_perimeter(_fixed, grid)
		return
	var post_mat := Palette.mat(Color("3a3d3f"), 0.5, 0.6)
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_texture = fence_texture()
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mesh_mat.alpha_scissor_threshold = 0.5
	mesh_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_mat.uv1_scale = Vector3(1, 1, 1)
	mesh_mat.metallic = 0.6
	mesh_mat.roughness = 0.5
	var lo := Vector2(-1.5, -1.5)
	var hi := Vector2(grid.width + 0.5, grid.height + 0.5)
	var sides := [[Vector2(lo.x, lo.y), Vector2(hi.x, lo.y)], [Vector2(hi.x, lo.y), Vector2(hi.x, hi.y)],
		[Vector2(hi.x, hi.y), Vector2(lo.x, hi.y)], [Vector2(lo.x, hi.y), Vector2(lo.x, lo.y)]]
	for side in sides:
		var a: Vector2 = side[0]
		var b: Vector2 = side[1]
		var length := a.distance_to(b)
		var quad := QuadMesh.new()
		quad.size = Vector2(length, 2.4)
		var fence := MeshInstance3D.new()
		fence.mesh = quad
		var m := mesh_mat.duplicate() as StandardMaterial3D
		m.uv1_scale = Vector3(length * 2.5, 2.4 * 2.5, 1)
		fence.material_override = m
		fence.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var mid := (a + b) * 0.5
		fence.position = Vector3(mid.x, 1.2, mid.y)
		fence.rotation.y = -atan2(b.y - a.y, b.x - a.x)
		_fixed.add_child(fence)
		var posts := int(length / 2.5)
		for i in posts + 1:
			var p := a.lerp(b, float(i) / posts)
			var post := Palette.box(Vector3(0.08, 2.6, 0.08), post_mat)
			post.position = Vector3(p.x, 1.3, p.y)
			_fixed.add_child(post)
	var cont := [grimy(Color("4a5a4a"), 0.8, 0.3, 0.4), grimy(Color("6b3a2c"), 0.8, 0.3, 0.4), grimy(Color("3e4a5a"), 0.8, 0.3, 0.4)]
	var spots := [Vector3(-5, 0, 3), Vector3(-4.5, 0, 10), Vector3(grid.width + 3.5, 0, 5), Vector3(5, 0, -4.5), Vector3(11, 0, grid.height + 3.5)]
	for i in spots.size():
		var along_x: bool = spots[i].z < 0 or spots[i].z > grid.height
		var size := Vector3(6.0, 2.6, 2.4) if along_x else Vector3(2.4, 2.6, 6.0)
		var box := Palette.box(size, cont[i % cont.size()])
		box.position = spots[i] + Vector3(0, 1.3, 0)
		_fixed.add_child(box)
		if i % 2 == 0:
			var top := Palette.box(size, cont[(i + 1) % cont.size()])
			top.position = spots[i] + Vector3(0, 3.9, 0)
			top.rotation.y = 0.05
			_fixed.add_child(top)


## Sodium floodlights on poles outside the fence, aimed into the board.
func _build_lights() -> void:
	if grid.biome == "port":
		BiomeLook.build_port_lights(_fixed, grid)
		return
	if grid.biome == "bore":
		BiomeLook.build_bore_lights(_fixed, grid)
		return
	var pole_mat := Palette.mat(Color("2d3033"), 0.5, 0.7)
	var lamp_mat := Palette.emissive(Color("ffcf8a"), 3.0)
	# Placed and aimed as a share of the board, so bigger maps stay lit edge to edge.
	var w := float(grid.width)
	var h := float(grid.height)
	var spots := [Vector3(-2.5, 0, -2.5), Vector3(w + 1.5, 0, h * 0.25), Vector3(w * 0.19, 0, h + 1.5),
		Vector3(w + 1.5, 0, h + 1.5), Vector3(-2.5, 0, h * 0.56)]
	var aims := [Vector3(w * 0.25, 0, h * 0.25), Vector3(w * 0.62, 0, h * 0.38), Vector3(w * 0.31, 0, h * 0.69),
		Vector3(w * 0.69, 0, h * 0.75), Vector3(w * 0.19, 0, h * 0.5)]
	var reach := 18.0 + maxf(w, h) - 16.0
	for i in spots.size():
		var base: Vector3 = spots[i]
		var pole := Palette.box(Vector3(0.14, 7.0, 0.14), pole_mat)
		pole.position = base + Vector3(0, 3.5, 0)
		_fixed.add_child(pole)
		var head := Palette.box(Vector3(0.6, 0.18, 0.35), lamp_mat)
		head.position = base + Vector3(0, 7.0, 0)
		head.basis = Basis.looking_at(aims[i] - head.position, Vector3.UP)
		_fixed.add_child(head)
		var spot := SpotLight3D.new()
		spot.light_color = Color("ffb767")
		spot.light_energy = 5.0
		spot.spot_range = reach
		spot.spot_angle = 34.0
		spot.spot_attenuation = 0.6
		spot.spot_angle_attenuation = 0.7
		spot.shadow_enabled = i < 3
		spot.transform = Transform3D(Basis.looking_at(aims[i] - (base + Vector3(0, 6.9, 0)), Vector3.UP), base + Vector3(0, 6.9, 0))
		_fixed.add_child(spot)
	# Red warning beacons on two corners of the fence.
	for p in [Vector3(-1.5, 2.7, -1.5), Vector3(grid.width + 0.5, 2.7, grid.height + 0.5)]:
		var bulb := Palette.box(Vector3(0.14, 0.14, 0.14), Palette.emissive(Palette.DANGER, 6.0))
		bulb.position = p
		_fixed.add_child(bulb)
		var l := OmniLight3D.new()
		l.light_color = Palette.DANGER
		l.light_energy = 1.2
		l.omni_range = 3.0
		l.position = p
		_fixed.add_child(l)


# --- overlays ---------------------------------------------------------------

func _clear(layer: Node3D) -> void:
	for ch in layer.get_children():
		ch.queue_free()
		layer.remove_child(ch)


func clear_overlays() -> void:
	for l in [_range_layer, _path_layer, _cover_layer, _mark_layer, _blast_layer]:
		_clear(l)
	_blast_cells = {}
	_mark_kind = ""
	_hover.visible = false


## The floor markings on screen right now, as TileOverlays keys in legend order (OverlayLegend).
func active_overlays() -> Array[String]:
	var on := {}
	if _range_layer.get_child_count() > 0:
		on["move"] = true
	if not _sight_cells.is_empty():
		on["sight"] = true
	if _mark_kind == "aim":
		on["aim"] = true
	if not _blast_cells.is_empty():
		on["blast"] = true
	for c in _hazard_kinds:
		on[_hazard_kinds[c]] = true
	for z in _zone_keys:
		on[z] = true
	var out: Array[String] = []
	for k in TileOverlays.KINDS:
		if on.has(k):
			out.append(k)
	return out


## True when `c` is inside the enemy sight wash (Concealed only).
func in_sight(c: Vector2i) -> bool:
	return _sight_cells.has(c)


## True when `c` is inside the explosive aim preview.
func in_blast(c: Vector2i) -> bool:
	return _blast_cells.has(c)


## Move range: a pale fill with an outline round the whole area. While the squad is Concealed,
## `spotted` cells (Concealment.danger_cells) are drawn red with a corner bracket: stepping on
## one gives the squad away.
func show_range(cells: Dictionary, spotted: Dictionary = {}) -> void:
	_clear(_range_layer)
	var red: StandardMaterial3D = null
	var edge: StandardMaterial3D = null
	if not spotted.is_empty():
		red = Palette.overlay(Color(Palette.DANGER, 0.12))   # the sight wash (show_sight) is under it too
		edge = Palette.overlay(Color(Palette.DANGER, 0.85), true)
	for c in cells:
		var alarm := spotted.has(c)
		var q := Palette.box(Vector3(0.92, 0.01, 0.92), red if alarm else _m_range)
		q.position = cell_to_world(c, 0.015)
		_range_layer.add_child(q)
		if alarm:
			for k in 4:
				var sx := 1.0 if k % 2 == 0 else -1.0
				var sz := 1.0 if k < 2 else -1.0
				for bar in [Vector3(0.22, 0.012, 0.04), Vector3(0.04, 0.012, 0.22)]:
					var b := Palette.box(bar, edge)
					b.position = cell_to_world(c, 0.02) + Vector3(sx * (0.44 - bar.x * 0.5), 0, sz * (0.44 - bar.z * 0.5))
					_range_layer.add_child(b)
	if not cells.is_empty():
		_outline(cells, Palette.overlay(Color(TileOverlays.MOVE, 0.55)), 0.04, _range_layer)
		_mark_link_exits(cells)


## Move path preview. `spotted_at` (index into `path`, -1 for none) is the first step a dormant
## enemy would see: from there the dots turn red and an open eye hangs over that tile.
func show_path(path: Array[Vector2i], spotted_at := -1, origin := Vector2i(-1, -1)) -> void:
	_clear(_path_layer)
	var red_dot: StandardMaterial3D = null
	var red_dest: StandardMaterial3D = null
	if spotted_at >= 0:
		red_dot = Palette.overlay(Color(Palette.DANGER, 0.95))
		red_dest = Palette.overlay(Color(Palette.DANGER, 0.5))
	var prev := origin
	for i in path.size():
		var last := i == path.size() - 1
		var seen := spotted_at >= 0 and i >= spotted_at
		var m := (red_dest if seen else _m_dest) if last else (red_dot if seen else _m_path)
		var dot := Palette.box(Vector3(0.6, 0.02, 0.6) if last else Vector3(0.14, 0.03, 0.14), m)
		dot.position = cell_to_world(path[i], 0.03)
		_path_layer.add_child(dot)
		if prev.x >= 0 and maxi(absi(path[i].x - prev.x), absi(path[i].y - prev.y)) > 1:
			# A link jump: a dashed line from where the unit rides in to where it comes out.
			var li := link_at(prev)
			var col := link_color(li) if li >= 0 else Palette.AMBER
			var a := cell_to_world(prev, 0.0) + Vector3(0, 0.1, 0)
			var span := cell_to_world(path[i], 0.0) + Vector3(0, 0.1, 0) - a
			var n := maxi(2, int(span.length() / 0.5))
			for k in range(0, n, 2):
				_path_layer.add_child(_strip(a + span * (float(k) / n), a + span * (float(k + 1) / n), 0.14, Palette.overlay(Color(col, 0.95), true)))
		prev = path[i]
	if spotted_at >= 0 and spotted_at < path.size():
		var at := cell_to_world(path[spotted_at])
		var ring := Palette.ring(0.36, 0.44, Palette.overlay(Color(Palette.DANGER, 0.95), true))
		ring.position = at + Vector3(0, 0.05, 0)
		ring.scale.y = 0.2
		_path_layer.add_child(ring)
		var eye := eye_marker()
		eye.position = at + Vector3(0, 1.25, 0)
		_path_layer.add_child(eye)


## A billboarded open eye in the danger red: "you are seen here".
static func eye_marker(px := 0.011) -> Sprite3D:
	var sp := Sprite3D.new()
	sp.texture = _eye_texture()
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.no_depth_test = true
	sp.pixel_size = px
	sp.modulate = Palette.DANGER.lightened(0.15)
	sp.render_priority = 10
	return sp


static var _eye_tex: Texture2D


## The "detected" eye from the HUD icon set, rasterised once: almond outline, iris ring, pupil,
## on a dark halo so it reads over any floor.
static func _eye_texture() -> Texture2D:
	if _eye_tex != null:
		return _eye_tex
	var w := 72
	var h := 44
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx := (w - 1) * 0.5
	var cy := (h - 1) * 0.5
	var half := 32.0
	for y in h:
		for x in w:
			var dx := (x - cx) / half
			var dy := y - cy
			var lid := 15.0 * maxf(0.0, 1.0 - dx * dx)   # lid height at this x
			var r := Vector2(x - cx, y - cy).length()
			var ink := (absf(dx) <= 1.0 and absf(absf(dy) - lid) < 2.2) or (r > 6.0 and r < 9.5 and absf(dy) < lid) or r < 3.6
			var halo := absf(dx) <= 1.12 and absf(dy) < lid + 5.0
			if ink:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
			elif halo:
				img.set_pixel(x, y, Color(0, 0, 0, 0.55))
	_eye_tex = ImageTexture.create_from_image(img)
	return _eye_tex


## Where the dormant enemies the squad can see would spot a soldier (Concealed only).
## `fields` = {enemy id: {"cells": {cell: true}, "at": Vector2i}}. The union is a faint red wash
## with a crisp red outline, walls, edges and high ground carving it the way line of sight does;
## `focus` (an enemy id, -1 for none) lifts that enemy's own area and dims the rest.
func show_sight(fields: Dictionary, focus := -1) -> void:
	var key := str(focus) + ":" + str(fields.hash())
	if key == _sight_key:
		return
	_sight_key = key
	_clear(_sight_layer)
	_sight_cells = {}
	if fields.is_empty():
		return
	var all := {}
	for id in fields:
		for c in fields[id].cells:
			all[c] = true
	_sight_cells = all
	var mine: Dictionary = fields[focus].cells if fields.has(focus) else {}
	var dim := not mine.is_empty()
	var wash := Palette.overlay(Color(Palette.DANGER, 0.025 if dim else 0.05))
	var hot := Palette.overlay(Color(Palette.DANGER, 0.14))
	for c in all:
		var q := Palette.box(Vector3(0.98, 0.01, 0.98), hot if mine.has(c) else wash)
		q.position = cell_to_world(c, 0.012)
		_sight_layer.add_child(q)
	_outline(all, Palette.overlay(Color(Palette.DANGER, 0.35 if dim else 0.75)), 0.05)
	if dim:
		_outline(mine, Palette.overlay(Color(Palette.DANGER.lightened(0.2), 1.0)), 0.08)


func clear_sight() -> void:
	_sight_key = ""
	_sight_cells = {}
	_clear(_sight_layer)


## Bars along every edge of `cells` that borders a cell outside it, added to `layer` (the sight
## layer by default).
func _outline(cells: Dictionary, m: StandardMaterial3D, width: float, layer: Node3D = null) -> void:
	if layer == null:
		layer = _sight_layer
	for c in cells:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if cells.has(c + d):
				continue
			var bar := Palette.box(Vector3(width, 0.02, 1.0) if d.x != 0 else Vector3(1.0, 0.02, width), m)
			bar.position = cell_to_world(c, 0.03) + Vector3(d.x * (0.5 - width * 0.5), 0, d.y * (0.5 - width * 0.5))
			layer.add_child(bar)


## Shield plates on each side of `c` that offers cover. `sides` is Grid.cover_sides(c).
func show_cover(c: Vector2i, sides: Dictionary) -> void:
	_clear(_cover_layer)
	for d in sides:
		var cover: int = sides[d]
		if cover == Types.Cover.NONE:
			continue
		var full := cover == Types.Cover.FULL
		var plate := Palette.box(Vector3(0.42, 0.55 if full else 0.3, 0.05), _m_full if full else _m_half)
		var dir := Vector2(d)
		plate.position = cell_to_world(c, 0.45 if full else 0.3) + Vector3(dir.x, 0, dir.y) * 0.4
		plate.rotation.y = atan2(dir.x, dir.y)
		_cover_layer.add_child(plate)
		var boss := Palette.box(Vector3(0.14, 0.14, 0.07), Palette.overlay(Color(1, 1, 1, 0.9), true))
		boss.position = Vector3(0, 0.05, 0)
		plate.add_child(boss)


func clear_path() -> void:
	_clear(_path_layer)
	_clear(_cover_layer)
	clear_blast()


## Aim preview for an explosive (Destruction.preview): the blast area in a red crosshatch with
## an outline, then a glass block over everything that will change, red for what breaks, drops
## or goes off, amber for what only cracks. `changes` is {cell: kind}.
func show_blast(area: Array, changes: Dictionary) -> void:
	clear_blast()
	var a := TileOverlays.floor_material(Color(Palette.DANGER, 0.5), "cross", 2.0)
	for c in area:
		var q := Palette.box(Vector3(1.0, 0.02, 1.0), a)
		q.position = cell_to_world(c, 0.03)
		_blast_layer.add_child(q)
		_blast_cells[c] = true
	_outline(_blast_cells, Palette.overlay(Color(Palette.DANGER, 0.9)), 0.05, _blast_layer)
	var red := Palette.overlay(Color(Palette.DANGER, 0.32))
	var amber := Palette.overlay(Color(Palette.AMBER, 0.26))
	for c in changes:
		var kind: String = changes[c]
		var tall := 2.3 if grid.tile(c) == Types.Tile.WALL else (0.95 if grid.tile(c) == Types.Tile.LOW else 0.12)
		var y0 := -RAISE * grid.level(c) + 0.02 if kind == "drop" else 0.0
		var block := Palette.box(Vector3(1.0, tall - y0, 1.0), amber if kind == "crack" else red)
		block.position = cell_to_world(c, (tall + y0) * 0.5)
		_blast_layer.add_child(block)


func clear_blast() -> void:
	_clear(_blast_layer)
	_blast_cells = {}


## Coloured squares on arbitrary cells (targeting candidates). `kind` "aim" is the area an item
## or ability will land on: amber squares with corner brackets, listed in the legend.
func mark_cells(cells: Array, color: Color, kind := "") -> void:
	_clear(_mark_layer)
	_mark_kind = kind if not cells.is_empty() else ""
	var m := Palette.overlay(color)
	var edge := Palette.overlay(Color(color, 0.95)) if kind == "aim" else null
	for c in cells:
		var q := Palette.box(Vector3(0.9, 0.02, 0.9), m)
		q.position = cell_to_world(c, 0.025)
		_mark_layer.add_child(q)
		if edge != null:
			var b := _brackets(edge, 0.44, 0.2, 0.04)
			b.position = cell_to_world(c, 0.035)
			_mark_layer.add_child(b)


func set_hover(c: Vector2i, on: bool) -> void:
	_hover.visible = on and grid.in_bounds(c)
	_hover.position = cell_to_world(c, 0.02)
