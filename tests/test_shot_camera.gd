extends TestCase
## Shot camera placement: the over-the-shoulder and push-in spots must keep the lens out
## of walls, cover and raised ground, and see the shooter and target where possible.

const MAIN := preload("res://scenes/main.tscn")
const ShotCamera := preload("res://view/shot_camera.gd")
const Board := preload("res://view/board.gd")


func _pos(g: Grid, c: Vector2i) -> Vector3:
	return Vector3(c.x, Board.RAISE * g.level(c), c.y)


func test_height_field_matches_the_board() -> void:
	var g := Grid.from_rows(PackedStringArray(["....", ".#=.", ".^%.", "...."]))
	assert_eq(ShotCamera.solid_top(g, Vector3(0, 0, 0)), 0.0, "floor")
	assert_true(ShotCamera.solid_top(g, Vector3(1, 0, 1)) > 2.2, "wall")
	assert_true(ShotCamera.solid_top(g, Vector3(2, 0, 1)) > 0.8, "low cover")
	assert_eq(ShotCamera.solid_top(g, Vector3(1, 0, 2)), Board.RAISE, "high ground")
	assert_true(ShotCamera.solid_top(g, Vector3(2, 0, 2)) > Board.RAISE + 0.8, "cover on high ground")
	assert_true(ShotCamera.solid_top(g, Vector3(-3, 0, 0)) > 2.4, "fence beyond the edge")
	assert_true(not ShotCamera.line_clear(g, Vector3(0, 1.3, 1), Vector3(3, 1.3, 1)), "wall blocks")
	assert_true(ShotCamera.line_clear(g, Vector3(0, 1.3, 0), Vector3(3, 1.3, 0)), "open row is clear")


func test_camera_backs_off_a_wall_behind_the_shooter() -> void:
	var v: MissionView = MAIN.instantiate()
	v.start(MissionView.default_mission(1234), false)
	# Shooter hugging a wall, firing away from it: the default shoulder spot is inside the wall.
	v.state.grid = Grid.from_rows(PackedStringArray([
		"..........",
		"..........",
		"..######..",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
	]))
	var from := Vector3(4, 0, 3)
	var at := Vector3(4, 0, 9)
	var eye: Vector3 = v.player._ots_eye(from, at, Vector3(0, 0, 0.5))
	assert_true(ShotCamera.eye_clear(v.state.grid, eye), "lens not inside the wall")
	assert_true(ShotCamera.line_clear(v.state.grid, eye, from + Vector3(0, 1.3, 0)), "shooter in view")
	v.free()


func test_shot_cameras_stay_out_of_generated_maps() -> void:
	var v: MissionView = MAIN.instantiate()
	v.start(MissionView.default_mission(1234), false)
	var shots := 0
	var full := 0
	for obj in ["skirmish", "hold", "boss"]:
		for seed in [1, 2, 3]:
			var g := MapGen.generate({"biome": "wall", "objective": obj, "seed": seed})
			v.state.grid = g
			var floors: Array[Vector2i] = []
			for y in g.height:
				for x in g.width:
					if g.is_walkable(Vector2i(x, y)) and (x * 7 + y * 3) % 5 == 0:
						floors.append(Vector2i(x, y))
			for i in range(0, floors.size(), 3):
				for j in range(1, floors.size(), 7):
					var a := floors[i]
					var b := floors[j]
					var d := a.distance_to(b)
					if d < 2.0 or d > 12.0 or not ShotCamera.line_clear(g, _pos(g, a) + Vector3(0, 1.4, 0), _pos(g, b) + Vector3(0, 1.4, 0)):
						continue
					var from := _pos(g, a)
					var at := _pos(g, b)
					var dir := Vector3(at.x - from.x, 0, at.z - from.z).normalized()
					var eye: Vector3 = v.player._ots_eye(from, at, dir * 0.5)
					shots += 1
					assert_true(ShotCamera.eye_clear(g, eye) and ShotCamera.eye_clear(g, eye + dir * 0.5),
						"%s/%d %s>%s: lens clear at %s" % [obj, seed, a, b, eye])
					if ShotCamera.sees(g, eye, [from + Vector3(0, 1.3, 0), at + Vector3(0, 1.3, 0)]):
						full += 1
					var push: Variant = v.player._push_eye(eye + dir * 0.5, from, at, at + Vector3(0, 1.1, 0))
					if push != null:
						assert_true(ShotCamera.eye_clear(g, push) and ShotCamera.line_clear(g, eye + dir * 0.5, push),
							"%s/%d %s>%s: push-in clear" % [obj, seed, a, b])
	assert_true(shots > 100, "sampled enough shots (%d)" % shots)
	assert_true(full * 10 >= shots * 9, "shooter and target both in view for most shots (%d/%d)" % [full, shots])
	print("[shot camera] %d/%d shots frame both shooter and target" % [full, shots])
	v.free()
