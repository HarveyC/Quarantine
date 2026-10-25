extends TestCase
## Shots aim at each target's real body (UnitView.aim_point), never at a fixed chest height:
## egg sacs and spore nests are shot down at on the floor, the Drifter up at, crawlers low,
## and the rifle itself pitches to meet them (UnitView.aim_at). tools/shot_aim.gd renders it.

const MAIN := preload("res://scenes/main.tscn")
const UnitView := preload("res://view/unit_view.gd")
const ModelKit := preload("res://view/model_kit.gd")


func _view(kind: String, enemy := true) -> UnitView:
	var u := Unit.new()
	u.id = 1
	u.kind = kind
	u.team = Types.Team.ENEMY if enemy else Types.Team.PLAYER
	u.owner_player = -1 if enemy else 0
	u.max_hp = 5
	u.hp = 5
	var uv: UnitView = UnitView.new()
	uv.build(u)
	uv.tick(0.05)
	return uv


## [bottom, top] of the body above the unit's feet: the static model's own mesh bounds, or
## the skeleton's lowest and highest bones (skinned meshes only report their bind pose).
func _span(uv: UnitView) -> Vector2:
	if uv._skin == null:
		var b := ModelKit.bounds(uv._model, uv)
		return Vector2(b.position.y, b.end.y)
	var lo := INF
	var hi := -INF
	var skel: Skeleton3D = uv._skin.skel
	for i in skel.get_bone_count():
		var y: float = uv._to_world(skel, uv._skin.bone_pose(skel.get_bone_name(i)).origin).y - uv.position.y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	return Vector2(maxf(lo, 0.0), hi)


func test_every_kind_is_aimed_inside_its_own_body() -> void:
	var heights := {}
	for kind in UnitData.SOLDIERS.keys() + UnitData.ENEMIES.keys():
		var uv := _view(kind, UnitData.ENEMIES.has(kind))
		var span := _span(uv)
		var h := span.y - span.x
		var aim := uv.aim_point().y - uv.position.y
		# (a skeleton's top bone is the base of the head, so it gets no margin)
		assert_true(aim > span.x + h * 0.2 and aim < span.y - (h * 0.1 if uv._skin == null else 0.0),
			"%s is aimed inside its body: %.2f within %.2f..%.2f" % [kind, aim, span.x, span.y])
		heights[kind] = aim
		# On a roof or down in a pit the aim point moves with the body.
		uv.position = Vector3(3, 2.4, -2)
		assert_true(absf(uv.aim_point().y - 2.4 - aim) < 0.02, "%s's aim point rides with it onto a roof" % kind)
		uv.free()
	# A single chest height for everyone would fail these.
	for low in ["egg_sac", "spore_nest", "lurker", "burrower"]:
		assert_true(heights[low] < 0.6, "%s sits low and is shot low (%.2f)" % [low, heights[low]])
	assert_true(heights.drifter > 0.95, "the floating Drifter is shot up at (%.2f)" % heights.drifter)
	assert_true(heights.brood_mother > heights.trooper + 0.4, "the Brood Mother is shot higher than a soldier")


## Pitch of the rifle's barrel (+ = down) and of the line from its muzzle to `at`.
func _barrel_vs_line(uv: UnitView, at: Vector3) -> Vector2:
	var m: Transform3D = uv._skin.bone_pose("muzzle")
	var from := uv._to_world(uv._skin.skel, m.origin)
	var fwd := uv._to_world(uv._skin.skel, m.origin + m.basis.z.normalized()) - from
	var to := at - from
	return Vector2(atan2(-fwd.y, Vector2(fwd.x, fwd.z).length()), atan2(-to.y, Vector2(to.x, to.z).length()))


func test_the_rifle_pitches_down_and_up_to_the_target() -> void:
	for case in [["egg_sac", 0.0], ["spore_nest", 0.0], ["runner", 2.4], ["runner", -1.2]]:
		var shooter := _view("trooper", false)
		var target := _view(case[0])
		target.position = Vector3(0, case[1], 5)
		shooter.face_towards(target.position, true)
		shooter.set_aim(1.0)
		shooter.aim_at(target.aim_point())
		for i in 12:
			shooter.tick(0.05)
		var p := _barrel_vs_line(shooter, target.aim_point())
		assert_true(absf(p.x - p.y) < 0.12, "rifle points at the %s %+.1f m (barrel %.2f rad, line %.2f rad)" % [case[0], case[1], p.x, p.y])
		# Lowered again, the barrel levels out.
		shooter.set_aim(0.0)
		for i in 20:
			shooter.tick(0.05)
		assert_true(absf(shooter._pitch) < 0.01, "pitch eases back once the rifle is lowered")
		shooter.free()
		target.free()


func test_rounds_land_on_an_egg_sac_not_above_it() -> void:
	var s := MissionView.default_mission(1234)
	var a: Unit = s.living(Types.Team.PLAYER)[0]
	var t: Unit = s.living(Types.Team.ENEMY)[0]
	t.kind = "egg_sac"
	var v: MissionView = MAIN.instantiate()
	v.start(s, false)
	var sv := v.view_for(a.id)
	var tv := v.view_for(t.id)
	var box := ModelKit.bounds(tv._model, tv)
	for gun in ["rifle", "shotgun"]:
		var feel: Dictionary = v.player._feel(sv)
		if gun == "shotgun":
			feel = feel.merged({"pellets": 6}, true)
		for imp in v.player._round_impacts(sv, tv, feel, true, false, 11):
			var y: float = (imp.pos as Vector3).y - tv.position.y
			assert_true(y > box.position.y and y < box.end.y, "%s round lands on the sac (%.2f within %.2f..%.2f)" % [gun, y, box.position.y, box.end.y])
	v.free()
