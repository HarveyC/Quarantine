extends Node3D
## 3D tiles for a Grid plus the tactical overlays drawn on top of it
## (reachable cells, path preview, cover shields, hover cursor, cell markers).
## One grid cell = one world unit; cell (x, y) sits at world (x, 0, y).

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
	_m_range = Palette.overlay(Color(0.55, 0.75, 0.95, 0.16))
	_m_path = Palette.overlay(Color(Palette.AMBER, 0.9))
	_m_dest = Palette.overlay(Color(Palette.AMBER, 0.45))
	_m_half = Palette.overlay(Color(0.95, 0.8, 0.3, 0.85), true)
	_m_full = Palette.overlay(Color(0.35, 0.7, 1.0, 0.9), true)
	_build_ground()
	_build_tiles()
	_hover = Palette.box(Vector3(0.96, 0.03, 0.96), Palette.overlay(Color(1, 1, 1, 0.22)))
	_hover.visible = false
	add_child(_hover)


func _layer(n: String) -> Node3D:
	var l := Node3D.new()
	l.name = n
	add_child(l)
	return l


func _build_ground() -> void:
	var ground := Palette.box(Vector3(grid.width + 12, 0.1, grid.height + 12), Palette.mat(Palette.GROUND, 1.0))
	ground.position = center() + Vector3(0, -0.26, 0)
	_tiles.add_child(ground)


func _hash(c: Vector2i) -> int:
	return absi((c.x * 73856093) ^ (c.y * 19349663))


func _build_tiles() -> void:
	var floor_mats: Array[StandardMaterial3D] = []
	for col in Palette.FLOOR_SHADES:
		floor_mats.append(Palette.mat(col, 0.95))
	var wall_mat := Palette.mat(Palette.WALL, 0.9, 0.1)
	var trim_mat := Palette.mat(Palette.WALL_TRIM, 0.6, 0.4)
	var crate_mat := Palette.mat(Palette.CRATE, 0.9)
	var band_mat := Palette.mat(Palette.CRATE_BAND, 0.7, 0.3)
	var goo_mat := Palette.emissive(Palette.TEAL, 0.7)
	for y in grid.height:
		for x in grid.width:
			var c := Vector2i(x, y)
			var h := _hash(c)
			var shade := (h % 3) + (1 if (x + y) % 2 == 0 else 0)
			var tile := Palette.box(Vector3(0.97, 0.2, 0.97), floor_mats[shade % floor_mats.size()])
			tile.position = cell_to_world(c, -0.1)
			_tiles.add_child(tile)
			match grid.tile(c):
				Types.Tile.WALL: _add_wall(c, wall_mat, trim_mat)
				Types.Tile.LOW: _add_crate(c, h, crate_mat, band_mat)
				_:
					if h % 23 == 0:
						_add_goo(c, h, goo_mat)


func _add_wall(c: Vector2i, body: Material, trim: Material) -> void:
	var w := Palette.box(Vector3(1.0, 2.2, 1.0), body)
	w.position = cell_to_world(c, 1.1)
	_tiles.add_child(w)
	var cap := Palette.box(Vector3(1.02, 0.08, 1.02), trim)
	cap.position = cell_to_world(c, 2.2)
	_tiles.add_child(cap)


func _add_crate(c: Vector2i, h: int, body: Material, band: Material) -> void:
	var crate := Palette.box(Vector3(0.9, 0.8, 0.9), body)
	crate.position = cell_to_world(c, 0.4)
	crate.rotation.y = deg_to_rad(float(h % 9) - 4.0)
	_tiles.add_child(crate)
	var strap := Palette.box(Vector3(0.94, 0.1, 0.94), band)
	strap.position = Vector3(0, 0.18, 0)
	crate.add_child(strap)


## Small glowing infection puddles scattered on the floor for mood.
func _add_goo(c: Vector2i, h: int, material: Material) -> void:
	var mesh := CylinderMesh.new()
	var r := 0.18 + float(h % 5) * 0.04
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = 0.02
	var goo := MeshInstance3D.new()
	goo.mesh = mesh
	goo.material_override = material
	goo.position = cell_to_world(c, 0.01) + Vector3(float(h % 7) * 0.05 - 0.15, 0, float(h % 5) * 0.05 - 0.1)
	_tiles.add_child(goo)


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
