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

var grid: Grid
var _tiles: Node3D
var _range_layer: Node3D
var _path_layer: Node3D
var _cover_layer: Node3D
var _mark_layer: Node3D
var _hazard_layer: Node3D
var _hazard_nodes := {}   # cell -> Node3D
var _hover: MeshInstance3D

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


static func cell_to_world(c: Vector2i, y := 0.0) -> Vector3:
	return Vector3(c.x, y + lift(c), c.y)


## World height of a cell's floor.
static func lift(c: Vector2i) -> float:
	return RAISE * _shown.level(c) if _shown != null else 0.0


static func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x), roundi(p.z))


func center() -> Vector3:
	return Vector3((grid.width - 1) * 0.5, 0, (grid.height - 1) * 0.5)


func build(g: Grid) -> void:
	grid = g
	_shown = g
	_tiles = _layer("Tiles")
	_range_layer = _layer("Range")
	_path_layer = _layer("Path")
	_cover_layer = _layer("Cover")
	_mark_layer = _layer("Marks")
	_hazard_layer = _layer("Hazards")
	_m_range = Palette.overlay(Color(0.55, 0.75, 0.95, 0.09))
	_m_path = Palette.overlay(Color(Palette.AMBER, 0.9))
	_m_dest = Palette.overlay(Color(Palette.AMBER, 0.45))
	_m_half = Palette.overlay(Color(0.95, 0.8, 0.3, 0.85), true)
	_m_full = Palette.overlay(Color(0.35, 0.7, 1.0, 0.9), true)
	_build_ground()
	_build_tiles()
	_build_zones()
	_build_perimeter()
	_build_lights()
	_hover = Palette.box(Vector3(0.96, 0.03, 0.96), Palette.overlay(Color(1, 1, 1, 0.22)))
	_hover.visible = false
	add_child(_hover)


## Rebuilds the tile props after the grid changed (cover smashed by a Brute or an airstrike).
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
	var ground := Palette.box(Vector3(grid.width + 40, 0.1, grid.height + 40), grimy(Palette.GROUND, 1.0, 0.08))
	ground.position = center() + Vector3(0, -0.26, 0)
	_tiles.add_child(ground)


func _hash(c: Vector2i) -> int:
	return absi((c.x * 73856093) ^ (c.y * 19349663))


func _build_tiles() -> void:
	var floor_mats: Array[StandardMaterial3D] = []
	for col in Palette.FLOOR_SHADES:
		floor_mats.append(grimy(col, 0.95, 0.18))
	var wall_mat := grimy(Palette.WALL.lightened(0.15), 0.9, 0.35)
	var trim_mat := Palette.mat(Palette.WALL_TRIM, 0.6, 0.4)
	var rib_mat := grimy(Palette.WALL.lightened(0.08), 0.8, 0.35, 0.2)
	var hazard := Palette.mat(Palette.AMBER.darkened(0.15), 0.7)
	var crate_mat := grimy(Palette.CRATE, 0.9, 0.5)
	var band_mat := Palette.mat(Palette.CRATE_BAND, 0.7, 0.3)
	var bag_mat := grimy(Color("5b5640"), 1.0, 0.6)
	var concrete := grimy(Color("6a6862"), 0.95, 0.4)
	var barrel_mats: Array[StandardMaterial3D] = [grimy(Color("5a2a22"), 0.7, 0.5, 0.3), grimy(Color("3c4a3a"), 0.7, 0.5, 0.3)]
	var rubble := grimy(Color("3d3c38"), 1.0, 0.6)
	var goo_mat := Palette.emissive(Palette.TEAL, 1.6)
	var goo_lights := 0
	var roof_mat := grimy(Palette.WALL.darkened(0.25), 0.9, 0.3)
	var deck_mat := grimy(Color("8a8f86"), 0.6, 0.35, 0.4)   # steel decking: roofs read lighter than the ground
	var lip_mat := Palette.emissive(Palette.AMBER, 0.6)
	var ladder_mat := Palette.mat(Palette.AMBER.darkened(0.3), 0.6, 0.5)
	var deck2_mat := grimy(Color("a3a89c"), 0.55, 0.35, 0.45)  # upper roofs read lighter still
	var plank_mat := grimy(Color("7a5a36"), 0.95, 0.5)        # scaffold planks: wood says "breaks"
	var pole_mat := Palette.mat(Color("8c8a80"), 0.5, 0.7)
	var tarp_mat := grimy(Color("4f5a44"), 1.0, 0.4)
	var stair_mat := grimy(Color("77786f"), 0.85, 0.4, 0.2)
	for y in grid.height:
		for x in grid.width:
			var c := Vector2i(x, y)
			var h := _hash(c)
			var shade := (h % 3) + (1 if (x + y) % 2 == 0 else 0)
			var top_mat: Material = floor_mats[shade % floor_mats.size()]
			if grid.is_fragile(c):
				top_mat = plank_mat
			elif grid.level(c) > 1:
				top_mat = deck2_mat
			elif grid.level(c) > 0:
				top_mat = deck_mat
			var tile := Palette.box(Vector3(0.97, 0.2, 0.97), top_mat)
			tile.position = cell_to_world(c, -0.1)
			_tiles.add_child(tile)
			if grid.is_fragile(c):
				_add_scaffold(c, h, pole_mat, tarp_mat, lip_mat)
			elif grid.level(c) > 0:
				_add_platform(c, h, roof_mat, lip_mat)
			if grid.is_ladder(c):
				_add_ladder(c, ladder_mat)
			if grid.is_stairs(c):
				_add_stairs(c, stair_mat, lip_mat)
			match grid.tile(c):
				Types.Tile.WALL: _add_wall(c, h, wall_mat, trim_mat, rib_mat, hazard)
				Types.Tile.LOW:
					match (h >> 3) % 4:
						0: _add_crate(c, h, crate_mat, band_mat)
						1: _add_sandbags(c, h, bag_mat)
						2: _add_barrier(c, h, concrete, hazard)
						_: _add_barrels(c, h, barrel_mats)
				_:
					if h % 23 == 0:
						_add_goo(c, h, goo_mat, goo_lights < GameSettings.puddle_lights())
						goo_lights += 1
					elif h % 5 == 0:
						_add_rubble(c, h, rubble)
	# Painted road markings across the deployment zone.
	var paint := Palette.mat(Color(Palette.AMBER, 1.0).darkened(0.35), 0.9)
	for x in grid.width:
		if x % 2 == 0:
			var dash := Palette.box(Vector3(0.55, 0.005, 0.08), paint)
			dash.position = Vector3(x, 0.003, grid.height - 3.5)
			_tiles.add_child(dash)


const HAZARD_COLORS := {"fire": Color("ff7a2a"), "spore": Color("2ef2c8"), "acid": Color("b8e03a")}


## Draws (or redraws) hazard `kind` on `cells`. Fire also gets a few flickering embers and a light.
func set_hazard(cells: Array, kind: String) -> void:
	var color: Color = HAZARD_COLORS.get(kind, Color.WHITE)
	var plate_mat := Palette.overlay(Color(color, 0.32 if kind == "fire" else 0.22))
	var glow := Palette.emissive(color, 2.2 if kind == "fire" else 1.0)
	var lights := 0
	for c in cells:
		clear_hazard([c])
		var n := Node3D.new()
		n.position = cell_to_world(c, 0.0)
		_hazard_layer.add_child(n)
		_hazard_nodes[c] = n
		var plate := Palette.box(Vector3(0.94, 0.015, 0.94), plate_mat)
		plate.position.y = 0.012
		n.add_child(plate)
		var h := _hash(c)
		for i in (3 if kind == "fire" else 2):
			var bit := Palette.box(Vector3.ONE * (0.12 if kind == "fire" else 0.2), glow)
			bit.position = Vector3(float((h >> (i * 3)) % 7) / 7.0 - 0.43, 0.08, float((h >> (i * 3 + 9)) % 7) / 7.0 - 0.43)
			if kind != "fire":
				bit.scale.y = 0.15
			n.add_child(bit)
		if kind == "fire" and lights < 3:
			lights += 1
			var l := OmniLight3D.new()
			l.light_color = color
			l.light_energy = 1.6
			l.omni_range = 2.4
			l.position.y = 0.5
			n.add_child(l)


func clear_hazard(cells: Array) -> void:
	for c in cells:
		if _hazard_nodes.has(c):
			_hazard_nodes[c].queue_free()
			_hazard_nodes.erase(c)


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
		for child in n.get_children():
			if child is MeshInstance3D and child.position.y > 0.05:
				child.position.y = 0.08 + 0.06 * sin(t * 7.0 + float(_hash(c) % 17))


## Objective zones from MapGen markers, painted on the floor: evac pad (green) and beacon (amber).
func _build_zones() -> void:
	var zones := {"evac": Color(0.35, 0.95, 0.45), "beacon": Palette.AMBER}
	for key in zones:
		var cells: Array = grid.marker(key)
		if cells.is_empty():
			continue
		var fill := Palette.overlay(Color(zones[key], 0.16))
		var edge := Palette.emissive(zones[key], 1.2)
		var inside := {}
		for c in cells:
			inside[c] = true
		for c in cells:
			var plate := Palette.box(Vector3(0.98, 0.01, 0.98), fill)
			plate.position = cell_to_world(c, 0.006)
			_tiles.add_child(plate)
			# A glowing line along the zone's outer edges.
			for d in Grid.DIRS4:
				if inside.has(c + d):
					continue
				var line := Palette.box(Vector3(0.98, 0.012, 0.05) if d.y != 0 else Vector3(0.05, 0.012, 0.98), edge)
				line.position = cell_to_world(c, 0.01) + Vector3(d.x, 0, d.y) * 0.47
				_tiles.add_child(line)


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
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + d
		if not grid.in_bounds(n) or grid.level(n) != grid.level(c) + 1 or not grid.is_walkable(n):
			continue
		var base := lift(c)
		var out := Vector3(d.x, 0, d.y)
		var along := Vector3(absf(d.y), 0, absf(d.x))
		const STEPS := 4
		for i in STEPS:
			var hgt := RAISE * float(i + 1) / STEPS
			var depth := 1.0 / STEPS
			var step := Palette.box(along * 0.8 + out.abs() * depth + Vector3(0, hgt, 0), m)
			step.position = Vector3(c.x, base + hgt * 0.5, c.y) + out * (-0.5 + depth * (i + 0.5))
			_tiles.add_child(step)
			var nose := Palette.box(along * 0.8 + Vector3(0.02, 0.02, 0.02), trim)
			nose.position = Vector3(c.x, base + hgt + 0.01, c.y) + out * (-0.5 + depth * i)
			_tiles.add_child(nose)
		return


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


func _add_wall(c: Vector2i, h: int, body: Material, trim: Material, rib: Material, hazard: Material) -> void:
	var w := Palette.box(Vector3(1.0, 2.2, 1.0), body)
	w.position = cell_to_world(c, 1.1)
	_tiles.add_child(w)
	var cap := Palette.box(Vector3(1.04, 0.1, 1.04), trim)
	cap.position = cell_to_world(c, 2.22)
	_tiles.add_child(cap)
	# Ribs and a hazard band on the faces that are not against another wall.
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + d
		if grid.in_bounds(n) and grid.tile(n) == Types.Tile.WALL:
			continue
		var out := Vector3(d.x, 0, d.y)
		var along := Vector3(absf(d.y), 0, absf(d.x))
		for k in [-0.3, 0.3]:
			var r := Palette.box(Vector3(0.08, 2.1, 0.08), rib)
			r.position = cell_to_world(c, 1.05) + out * 0.52 + along * k
			_tiles.add_child(r)
		if h % 2 == 0:
			var band := Palette.box(Vector3(1.0, 0.12, 0.02) if along.x > 0 else Vector3(0.02, 0.12, 1.0), hazard)
			band.position = cell_to_world(c, 0.35) + out * 0.505
			_tiles.add_child(band)


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
		light.light_energy = 0.8
		light.omni_range = 1.8
		light.position = goo.position + Vector3(0, 0.3, 0)
		_tiles.add_child(light)


## Chain-link fence around the board with posts, plus a few container stacks outside.
func _build_perimeter() -> void:
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
		_tiles.add_child(fence)
		var posts := int(length / 2.5)
		for i in posts + 1:
			var p := a.lerp(b, float(i) / posts)
			var post := Palette.box(Vector3(0.08, 2.6, 0.08), post_mat)
			post.position = Vector3(p.x, 1.3, p.y)
			_tiles.add_child(post)
	var cont := [grimy(Color("4a5a4a"), 0.8, 0.3, 0.4), grimy(Color("6b3a2c"), 0.8, 0.3, 0.4), grimy(Color("3e4a5a"), 0.8, 0.3, 0.4)]
	var spots := [Vector3(-5, 0, 3), Vector3(-4.5, 0, 10), Vector3(grid.width + 3.5, 0, 5), Vector3(5, 0, -4.5), Vector3(11, 0, grid.height + 3.5)]
	for i in spots.size():
		var along_x: bool = spots[i].z < 0 or spots[i].z > grid.height
		var size := Vector3(6.0, 2.6, 2.4) if along_x else Vector3(2.4, 2.6, 6.0)
		var box := Palette.box(size, cont[i % cont.size()])
		box.position = spots[i] + Vector3(0, 1.3, 0)
		_tiles.add_child(box)
		if i % 2 == 0:
			var top := Palette.box(size, cont[(i + 1) % cont.size()])
			top.position = spots[i] + Vector3(0, 3.9, 0)
			top.rotation.y = 0.05
			_tiles.add_child(top)


## Sodium floodlights on poles outside the fence, aimed into the board.
func _build_lights() -> void:
	var pole_mat := Palette.mat(Color("2d3033"), 0.5, 0.7)
	var lamp_mat := Palette.emissive(Color("ffcf8a"), 3.0)
	var spots := [Vector3(-2.5, 0, -2.5), Vector3(grid.width + 1.5, 0, 4.0), Vector3(3.0, 0, grid.height + 1.5),
		Vector3(grid.width + 1.5, 0, grid.height + 1.5), Vector3(-2.5, 0, 9.0)]
	var aims := [Vector3(4, 0, 4), Vector3(10, 0, 6), Vector3(5, 0, 11), Vector3(11, 0, 12), Vector3(3, 0, 8)]
	for i in spots.size():
		var base: Vector3 = spots[i]
		var pole := Palette.box(Vector3(0.14, 7.0, 0.14), pole_mat)
		pole.position = base + Vector3(0, 3.5, 0)
		_tiles.add_child(pole)
		var head := Palette.box(Vector3(0.6, 0.18, 0.35), lamp_mat)
		head.position = base + Vector3(0, 7.0, 0)
		head.basis = Basis.looking_at(aims[i] - head.position, Vector3.UP)
		_tiles.add_child(head)
		var spot := SpotLight3D.new()
		spot.light_color = Color("ffb767")
		spot.light_energy = 5.0
		spot.spot_range = 18.0
		spot.spot_angle = 34.0
		spot.spot_attenuation = 0.6
		spot.spot_angle_attenuation = 0.7
		spot.shadow_enabled = i < 3
		spot.transform = Transform3D(Basis.looking_at(aims[i] - (base + Vector3(0, 6.9, 0)), Vector3.UP), base + Vector3(0, 6.9, 0))
		_tiles.add_child(spot)
	# Red warning beacons on two corners of the fence.
	for p in [Vector3(-1.5, 2.7, -1.5), Vector3(grid.width + 0.5, 2.7, grid.height + 0.5)]:
		var bulb := Palette.box(Vector3(0.14, 0.14, 0.14), Palette.emissive(Palette.DANGER, 6.0))
		bulb.position = p
		_tiles.add_child(bulb)
		var l := OmniLight3D.new()
		l.light_color = Palette.DANGER
		l.light_energy = 1.2
		l.omni_range = 3.0
		l.position = p
		_tiles.add_child(l)


# --- overlays ---------------------------------------------------------------

func _clear(layer: Node3D) -> void:
	for ch in layer.get_children():
		ch.queue_free()
		layer.remove_child(ch)


func clear_overlays() -> void:
	for l in [_range_layer, _path_layer, _cover_layer, _mark_layer]:
		_clear(l)
	_hover.visible = false


func show_range(cells: Dictionary) -> void:
	_clear(_range_layer)
	for c in cells:
		var q := Palette.box(Vector3(0.92, 0.01, 0.92), _m_range)
		q.position = cell_to_world(c, 0.015)
		_range_layer.add_child(q)


func show_path(path: Array[Vector2i]) -> void:
	_clear(_path_layer)
	for i in path.size():
		var last := i == path.size() - 1
		var dot := Palette.box(Vector3(0.6, 0.02, 0.6) if last else Vector3(0.14, 0.03, 0.14), _m_dest if last else _m_path)
		dot.position = cell_to_world(path[i], 0.03)
		_path_layer.add_child(dot)


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


## Coloured squares on arbitrary cells (targeting candidates, ability areas).
func mark_cells(cells: Array, color: Color) -> void:
	_clear(_mark_layer)
	var m := Palette.overlay(color)
	for c in cells:
		var q := Palette.box(Vector3(0.9, 0.02, 0.9), m)
		q.position = cell_to_world(c, 0.025)
		_mark_layer.add_child(q)


func set_hover(c: Vector2i, on: bool) -> void:
	_hover.visible = on and grid.in_bounds(c)
	_hover.position = cell_to_world(c, 0.02)
