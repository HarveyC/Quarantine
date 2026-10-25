extends TestCase
## Units on stairs and rubble ramps: every foot sits on (not inside) the steps, for every body
## kind and facing, standing still and on the way up; flat floors and roofs are left alone.

const Board := preload("res://view/board.gd")
const UnitView := preload("res://view/unit_view.gd")

# Stairs s at (2, 2) climb east to a roof (x 3..5); a second flight S at (4, 3) climbs north
# to the upper roof at (4, 2).
const ROWS := [
	"........",
	"...^^^..",
	"..s^2^..",
	"...^S^..",
	"...^^^..",
	"........",
]
# A wide roof far from its stairs, for the flat checks.
const FLAT := [
	"..........",
	".s^^^^^^..",
	"..^^^^^^..",
	"..^^^^^^..",
	"..........",
	"..........",
]
const KINDS := ["lurker", "burrower", "runner", "trooper", "brute", "brood_mother", "broodling", "leaper"]


func _board(rows: Array = ROWS) -> Node3D:
	var b := Board.new()
	b.build(Grid.from_rows(PackedStringArray(rows)))
	return b


func _view(kind: String, elite := false) -> Node3D:
	var u := Unit.new()
	u.id = 1
	u.kind = kind
	u.team = Types.Team.PLAYER if kind == "trooper" else Types.Team.ENEMY
	u.owner_player = 0 if kind == "trooper" else -1
	u.max_hp = 5
	u.hp = 5
	var uv := UnitView.new()
	uv.build(u)
	if elite:
		uv.scale = Vector3.ONE * 1.2
	return uv


## World positions of the unit's feet as drawn right now.
func _feet(uv: Node3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for f in uv._feet:
		out.append(uv.transform * (uv._body.transform * f))
	return out


## Lowest gap between a foot and the surface under it (negative = inside the steps; well above
## zero = floating), over the feet on walkable cells.
## Feet reaching over a block two levels above the stairs are left out: no leg can stand there.
func _gap(uv: Node3D, g: Grid, stairs: Vector2i) -> float:
	var sink := INF
	for w in _feet(uv):
		var c := Vector2i(roundi(w.x), roundi(w.z))
		if not g.in_bounds(c) or not g.is_walkable(c) or g.level(c) > g.level(stairs) + 1:
			continue
		sink = minf(sink, w.y - Board.surface(Vector2(w.x, w.z)))
	return sink


func _place(uv: Node3D, p: Vector3, yaw: float) -> void:
	uv.position = p
	uv.set_yaw(yaw)
	uv._fit_snap = true
	uv.tick(0.0)


func test_stair_surface_follows_the_steps() -> void:
	var b := _board()
	var s := Vector2i(2, 2)
	assert_true(is_equal_approx(Board.lift(s), 0.0), "stairs rise from the ground")
	assert_eq(Board.stair_dir(s), Vector2i(1, 0), "climbs towards the roof")
	assert_true(is_equal_approx(Board.surface(Vector2(1.55, 2)), Board.RAISE / 4.0), "bottom step")
	assert_true(is_equal_approx(Board.surface(Vector2(2.45, 2)), Board.RAISE), "top step meets the roof")
	assert_true(Board.stand(s) > Board.RAISE * 0.5, "units stand on the middle steps, not under them")
	assert_true(is_equal_approx(Board.cell_to_world(s).y, Board.stand(s)), "markers sit on the steps too")
	var upper := Vector2i(4, 3)
	assert_eq(Board.stair_dir(upper), Vector2i(0, -1), "roof stairs climb north")
	assert_true(Board.stand(upper) > Board.RAISE * 1.5, "roof stairs stand above the roof")
	assert_true(is_equal_approx(Board.stand(Vector2i(4, 4)), Board.RAISE), "plain roof")
	assert_eq(Board.stair_dir(Vector2i(4, 4)), Vector2i.ZERO, "roofs are flat")
	b.free()


func test_every_body_stands_on_the_steps() -> void:
	var b := _board()
	var g: Grid = b.grid
	for kind in KINDS:
		for elite in [false, true]:
			var uv := _view(kind, elite)
			for stairs in [Vector2i(2, 2), Vector2i(4, 3)]:
				for q in 8:
					_place(uv, Board.cell_to_world(stairs), q * PI / 4.0)
					var gap := _gap(uv, g, stairs)
					var tag := "%s%s on %s facing %d" % ["elite " if elite else "", kind, stairs, q * 45]
					assert_true(gap > -0.03, "%s: no foot inside the steps (%.2f)" % [tag, gap])
					assert_true(gap < 0.45, "%s: still standing on them (%.2f)" % [tag, gap])
			uv.free()
	b.free()


func test_climbing_the_stairs_keeps_feet_out_of_them() -> void:
	var b := _board()
	var g: Grid = b.grid
	for kind in ["lurker", "trooper", "brute"]:
		var uv := _view(kind, kind == "lurker")
		var path := [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)]
		for back in [false, true]:
			var cells: Array = path.duplicate()
			if back:
				cells.reverse()
			for i in 2:
				var a := Board.cell_to_world(cells[i])
				var z := Board.cell_to_world(cells[i + 1])
				for k in 11:
					var p := Board.walk_point(cells[i], cells[i + 1], k / 10.0)
					_place(uv, p, atan2(z.x - a.x, z.z - a.z))
					var gap := _gap(uv, g, Vector2i(2, 2))
					assert_true(gap > -0.03, "%s %s at %s: feet clear the steps (%.2f)" % [kind, "down" if back else "up", p, gap])
		uv.free()
	b.free()


func test_lurkers_lean_into_the_climb() -> void:
	var b := _board()
	var uv := _view("lurker", true)
	uv.tick(0.0)
	assert_true(uv._crawler, "the spider rig counts as many-legged")
	assert_true(uv._feet.size() >= 6, "one point per leg tip")
	_place(uv, Board.cell_to_world(Vector2i(2, 2)), PI * 0.5)   # facing east, up the stairs
	assert_true(uv._body.rotation.x < -0.1, "nose up the slope")
	_place(uv, Board.cell_to_world(Vector2i(2, 2)), -PI * 0.5)
	assert_true(uv._body.rotation.x > 0.1, "nose down the slope")
	uv.free()
	b.free()


func test_flat_ground_and_roofs_are_untouched() -> void:
	var b := _board(FLAT)
	for kind in ["lurker", "trooper"]:
		var uv := _view(kind, true)
		uv.tick(0.0)
		for c in [Vector2i(8, 5), Vector2i(5, 2), Vector2i(6, 2), Vector2i(4, 5)]:
			_place(uv, Board.cell_to_world(c), 0.7)
			assert_true(is_zero_approx(uv._fit_off), "%s at %s: no lift" % [kind, c])
			assert_true(is_zero_approx(uv._body.rotation.x) and is_zero_approx(uv._body.rotation.z), "%s at %s: upright" % [kind, c])
		uv.free()
	b.free()


func test_rubble_ramps_carry_units_like_stairs() -> void:
	var g := Grid.from_rows(PackedStringArray(ROWS))
	g.rubble[Vector2i(2, 2)] = "roof"
	var b := Board.new()
	b.build(g)
	var c := Vector2i(2, 2)
	assert_true(Board.surface(Vector2(2.45, 2)) > Board.surface(Vector2(1.55, 2)), "the ramp rises to the roof")
	for kind in ["lurker", "runner"]:
		var uv := _view(kind, true)
		for q in 4:
			_place(uv, Board.cell_to_world(c), q * PI * 0.5)
			assert_true(_gap(uv, g, c) > -0.03, "%s on the rubble ramp, facing %d" % [kind, q * 90])
		uv.free()
	b.free()
