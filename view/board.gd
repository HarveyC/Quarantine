extends Node3D
## 3D tiles for a Grid plus the tactical overlays drawn on top of it
## (reachable cells, path preview, cover shields, hover cursor, cell markers).
## One grid cell = one world unit; cell (x, y) sits at world (x, 0, y).
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
var _hover: MeshInstance3D

var _m_range: StandardMaterial3D
var _m_path: StandardMaterial3D
var _m_dest: StandardMaterial3D
var _m_half: StandardMaterial3D
var _m_full: StandardMaterial3D

static var _grime_tex: Texture2D
static var _fence_tex: Texture2D


static func cell_to_world(c: Vector2i, y := 0.0) -> Vector3:
	return Vector3(c.x, y, c.y)


static func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x), roundi(p.z))


func center() -> Vector3:
	return Vector3((grid.width - 1) * 0.5, 0, (grid.height - 1) * 0.5)


func build(g: Grid) -> void:
	grid = g
	_tiles = _layer("Tiles")
	_range_layer = _layer("Range")
	_path_layer = _layer("Path")
	_cover_layer = _layer("Cover")
	_mark_layer = _layer("Marks")
	_m_range = Palette.overlay(Color(0.55, 0.75, 0.95, 0.09))
	_m_path = Palette.overlay(Color(Palette.AMBER, 0.9))
	_m_dest = Palette.overlay(Color(Palette.AMBER, 0.45))
	_m_half = Palette.overlay(Color(0.95, 0.8, 0.3, 0.85), true)
	_m_full = Palette.overlay(Color(0.35, 0.7, 1.0, 0.9), true)
	_build_ground()
	_build_tiles()
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
	for y in grid.height:
		for x in grid.width:
			var c := Vector2i(x, y)
			var h := _hash(c)
			var shade := (h % 3) + (1 if (x + y) % 2 == 0 else 0)
			var tile := Palette.box(Vector3(0.97, 0.2, 0.97), floor_mats[shade % floor_mats.size()])
			tile.position = cell_to_world(c, -0.1)
			_tiles.add_child(tile)
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
						_add_goo(c, h, goo_mat, goo_lights < 8)
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
