extends Node3D
## Training and hint markers on the board: an amber bracket on each goal tile, a soft
## pulsing fill, and a chevron bobbing over the first one. Lives under the Board so it sits
## on roofs like units do. View only.

const Palette := preload("res://view/palette.gd")
const Board := preload("res://view/board.gd")
const Styles := preload("res://ui/styles.gd")

var cells: Array[Vector2i] = []
var _fill: StandardMaterial3D
var _line: StandardMaterial3D
var _chevron: Node3D
var _t := 0.0


func _init() -> void:
	name = "TutorialMarkers"
	_fill = Palette.overlay(Color(Styles.AMBER, 0.18))
	_line = Palette.overlay(Color(Styles.AMBER, 0.95))


func set_cells(list: Array) -> void:
	var next: Array[Vector2i] = []
	next.assign(list)
	if next == cells:
		return
	cells = next
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_chevron = null
	for c in cells:
		var q := Palette.box(Vector3(0.9, 0.01, 0.9), _fill)
		q.position = Board.cell_to_world(c, 0.035)
		add_child(q)
		_bracket(Board.cell_to_world(c, 0.05))
	if not cells.is_empty():
		_chevron = _make_chevron()
		_chevron.position = Board.cell_to_world(cells[0], 1.6)
		add_child(_chevron)


## Screen point to aim an arrow at: the middle of the marked tiles.
func world_center() -> Vector3:
	var sum := Vector3.ZERO
	for c in cells:
		sum += Board.cell_to_world(c, 0.3)
	return sum / maxf(1.0, cells.size())


func _bracket(at: Vector3) -> void:
	var k := 0.22
	var h := 0.44
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var a := Palette.box(Vector3(k, 0.02, 0.05), _line)
		a.position = at + Vector3(corner.x * (h - k * 0.5), 0, corner.y * h)
		add_child(a)
		var b := Palette.box(Vector3(0.05, 0.02, k), _line)
		b.position = at + Vector3(corner.x * h, 0, corner.y * (h - k * 0.5))
		add_child(b)


func _make_chevron() -> Node3D:
	var root := Node3D.new()
	var m := Palette.overlay(Styles.AMBER, true)
	for side in [-1.0, 1.0]:
		var bar := Palette.box(Vector3(0.36, 0.07, 0.07), m)
		bar.position = Vector3(side * 0.12, 0.12, 0)
		bar.rotation.z = side * 0.75
		root.add_child(bar)
	return root


func _process(delta: float) -> void:
	_t += delta
	_fill.albedo_color.a = 0.12 + 0.12 * (0.5 + 0.5 * sin(_t * 4.0))
	if _chevron != null and not cells.is_empty():
		_chevron.position = Board.cell_to_world(cells[0], 1.5 + 0.15 * sin(_t * 3.0))
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam != null:
			var to := cam.global_position - _chevron.global_position
			_chevron.rotation.y = atan2(to.x, to.z)
