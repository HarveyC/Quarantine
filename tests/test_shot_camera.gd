extends TestCase
## Shot camera placement: the over-the-shoulder and push-in spots must keep the lens out
## of walls, cover and raised ground, and see the shooter and target where possible.

const MAIN := preload("res://scenes/main.tscn")
const ShotCamera := preload("res://view/shot_camera.gd")
const Board := preload("res://view/board.gd")
const Weapons := preload("res://combat/weapons.gd")


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
	var eye: Vector3 = v.player._ots_eye(from, at, at + Vector3(0, 1.3, 0), Vector3(0, 0, 0.5))
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
					var eye: Vector3 = v.player._ots_eye(from, at, at + Vector3(0, 1.3, 0), dir * 0.5)
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


func test_shot_moments_rules() -> void:
	var M := preload("res://view/shot_moments.gd")
	var base := {"squad": true, "hit": true, "dist": 4.0, "chance": 70}
	var with := func(extra: Dictionary) -> String:
		var f := base.duplicate()
		f.merge(extra, true)
		return M.moment(f)
	assert_eq(M.moment(base), "", "routine hit")
	assert_eq(with.call({"hit": false, "kill": true, "crit": true}), "", "misses never cut")
	assert_eq(with.call({"kill": true}), "kill", "kill")
	assert_eq(with.call({"kill": true, "last_enemy": true}), "last_enemy", "last enemy")
	assert_eq(with.call({"crit": true}), "crit", "crit")
	assert_eq(with.call({"boss_target": true}), "boss", "boss hit")
	assert_eq(with.call({"dist": 12.0}), "long_shot", "long shot")
	assert_eq(with.call({"high_ground": true, "dist": 7.0}), "high_ground", "high ground")
	assert_eq(with.call({"high_ground": true, "dist": 3.0}), "", "point blank off a roof is routine")
	assert_eq(with.call({"chance": 25}), "long_odds", "long odds landed")
	# Enemies and Turned soldiers.
	var foe := {"squad": false, "hit": true, "soldier_target": true, "dist": 12.0, "chance": 20}
	assert_eq(M.moment(foe), "", "enemy hit on a soldier")
	foe.kill = true
	assert_eq(M.moment(foe), "soldier_down", "a soldier goes down")
	foe.kill = false
	foe.crit = true
	assert_eq(M.moment(foe), "crit", "crit on a soldier")
	assert_eq(M.moment({"squad": false, "hit": true, "boss_shooter": true}), "boss", "the boss lands a blow")


## Points in front of a camera at `eye` looking at `look` sit inside a `fov` frame (16:9).
func _in_frame(eye: Vector3, look: Vector3, fov: float, p: Vector3) -> bool:
	var basis := Transform3D().looking_at(look - eye, Vector3.UP).basis
	var local := basis.inverse() * (p - eye)
	if local.z >= -0.1:
		return false
	var tv := tan(deg_to_rad(fov * 0.5))
	return absf(local.y / -local.z) <= tv and absf(local.x / -local.z) <= tv * 16.0 / 9.0


func test_enemy_two_shot_frames_both_in_tight_spots() -> void:
	# A walled alley, a room corner under a roof, and a shot down off a roof past a wall: the
	# spots where the old over-the-shoulder camera ended up in a wall or on a chest.
	var spots := [
		[["..............", "..^^^^^.......", "..^^^^^.......", ".###########..", "..a....b......", ".###########..", ".............."], 0],
		[["##########", "#^^^.....#", "#^^^.....#", "#ba......#", "#........#", "#####.####", ".........."], 0],
		[["............", "..^^^^^^....", "..^^a^^^....", "..^^^^^^....", "....#####...", "............", "......b.....", "............"], 0],
	]
	for spot in spots:
		var rows: Array = spot[0]
		var clean := PackedStringArray()
		var at := {}
		for y in rows.size():
			var r: String = rows[y]
			for ch in ["a", "b"]:
				var x := r.find(ch)
				if x >= 0:
					at[ch] = Vector2i(x, y)
			clean.append(r.replace("a", ".").replace("b", "."))
		var g := Grid.from_rows(clean)
		var a := _pos(g, at.a)
		var b := _pos(g, at.b)
		var w := ShotCamera.two_shot(g, a, b)
		var eye: Vector3 = w.eye
		var label := "%s>%s" % [at.a, at.b]
		assert_true(ShotCamera.eye_clear(g, eye), label + ": lens out of the scenery")
		assert_true(ShotCamera.sees(g, eye, [a + Vector3(0, 1.1, 0), b + Vector3(0, 1.0, 0)]), label + ": both in view")
		for p in [a, b, a + Vector3(0, 1.7, 0), b + Vector3(0, 1.7, 0)]:
			assert_true(_in_frame(eye, w.look, w.fov, p), label + ": %s in frame" % p)
		assert_true(eye.distance_to(a) > 3.5 and eye.distance_to(b) > 3.5, label + ": pulled back, not on a chest (%s)" % eye)


func test_enemy_two_shot_on_generated_maps() -> void:
	var shots := 0
	var full := 0
	for seed in [1, 2, 3]:
		var g := MapGen.generate({"biome": "wall", "objective": "skirmish", "seed": seed})
		var floors: Array[Vector2i] = []
		for y in g.height:
			for x in g.width:
				if g.is_walkable(Vector2i(x, y)) and (x * 7 + y * 3) % 7 == 0:
					floors.append(Vector2i(x, y))
		for i in range(0, floors.size(), 4):
			for j in range(1, floors.size(), 9):
				var d := floors[i].distance_to(floors[j])
				if d < 1.0 or d > 12.0:
					continue
				var a := _pos(g, floors[i])
				var b := _pos(g, floors[j])
				if not ShotCamera.line_clear(g, a + Vector3(0, 1.4, 0), b + Vector3(0, 1.4, 0)):
					continue
				var w := ShotCamera.two_shot(g, a, b)
				shots += 1
				assert_true(ShotCamera.eye_clear(g, w.eye), "seed %d %s>%s: lens clear" % [seed, floors[i], floors[j]])
				assert_true(_in_frame(w.eye, w.look, w.fov, a + Vector3(0, 1.0, 0)) and _in_frame(w.eye, w.look, w.fov, b + Vector3(0, 1.0, 0)),
					"seed %d %s>%s: both in frame" % [seed, floors[i], floors[j]])
				if ShotCamera.sees(g, w.eye, [a + Vector3(0, 1.1, 0), b + Vector3(0, 1.0, 0)]):
					full += 1
	assert_true(shots > 60, "sampled enough attacks (%d)" % shots)
	assert_true(full * 20 >= shots * 19, "attacker and target both in clear view (%d/%d)" % [full, shots])


func test_close_push_keeps_a_wide_lens() -> void:
	assert_true(ShotCamera.fit_fov(2.6) >= 49.0, "close in a tight spot: wide")
	assert_eq(ShotCamera.fit_fov(8.0), 30.0, "far off: the long lens")


func test_enemy_attack_callout_follows_the_attack() -> void:
	var v: MissionView = MAIN.instantiate()
	v.start(MissionView.default_mission(1234), false)
	v.player.flush()
	var soldier := v.state.controllable_units(0)[0]
	var enemy := v.state.living(Types.Team.ENEMY)[0]
	var c = v.hud.callout
	v.player.enemy_phase = true
	var hp := v.view_for(soldier.id).hp
	v.player.enqueue({"type": "shot", "unit": enemy.id, "target": soldier.id, "hit": true, "graze": false,
		"crit": true, "damage": 3, "chance": 55, "reaction": false})
	v.player.enqueue({"type": "damage", "unit": soldier.id, "amount": 3, "hp": hp - 3})
	v.player.enqueue({"type": "infection", "unit": soldier.id, "value": 10, "tier": 0})
	v.player.enqueue({"type": "pinned", "unit": enemy.id, "target": soldier.id})
	v.player.advance(0.05)
	assert_true(c.active, "an enemy shot puts the callout up")
	var sum: Dictionary = c.summary()
	assert_eq(sum.attacker, enemy.id, "attacker")
	assert_eq(sum.target, soldier.id, "target")
	assert_eq(sum.icon, "shoot", "attack icon")
	assert_eq(sum.chance, "55%", "odds")
	var steps := 0
	while v.player.pending() > 1 and steps < 2000:
		v.player.advance(1.0 / 30.0)
		steps += 1
	sum = c.summary()
	assert_eq(sum.word, "CRIT", "the result in one word")
	assert_eq(sum.damage, 3, "damage marked")
	assert_true(sum.statuses.has("infection"), "Infection gained shown")
	v.player.flush()
	sum = c.summary()
	assert_true(sum.statuses.has("suppress"), "pinning fire shown")
	assert_true(not c.active, "released once the action is over")
	# A soldier's own shot in the squad phase, with no cut, keeps the action bar.
	v.player.enemy_phase = false
	v.player.cinematics = false
	v.player.enqueue({"type": "shot", "unit": soldier.id, "target": enemy.id, "hit": false, "graze": false,
		"crit": false, "damage": 0, "chance": 60, "reaction": false})
	v.player.flush()
	assert_eq(c.summary().word, "CRIT", "no callout for a routine squad shot")
	v.player.cinematics = true
	# A soldier's shot in the enemy phase (overwatch) names the gun; an enemy's shot does not.
	v.player.enemy_phase = true
	v.player.enqueue({"type": "shot", "unit": soldier.id, "target": enemy.id, "hit": true, "graze": false,
		"crit": false, "damage": 2, "chance": 60, "reaction": true})
	v.player.advance(0.05)
	assert_eq(c.summary().gun, Weapons.gun_name(Weapons.id_of(soldier)).to_upper(), "the gun fired is named")
	v.player.flush()
	v.player.enqueue({"type": "shot", "unit": enemy.id, "target": soldier.id, "hit": true, "graze": false,
		"crit": false, "damage": 2, "chance": 60, "reaction": false})
	v.player.advance(0.05)
	assert_eq(c.summary().gun, "", "an enemy's attack names no gun")
	v.player.flush()
	v.free()


func test_enemy_strike_callout_shows_the_soldier_going_down() -> void:
	var v: MissionView = MAIN.instantiate()
	v.start(MissionView.default_mission(1234), false)
	v.player.flush()
	var soldier := v.state.controllable_units(0)[0]
	var enemy := v.state.living(Types.Team.ENEMY)[0]
	v.player.enemy_phase = true
	var hp := v.view_for(soldier.id).hp
	v.player.enqueue({"type": "ability", "ability": "claw", "unit": enemy.id, "target": soldier.id, "hit": true, "chance": 80})
	v.player.enqueue({"type": "damage", "unit": soldier.id, "amount": hp, "hp": 0})
	v.player.enqueue({"type": "died", "unit": soldier.id})
	v.player.advance(0.05)
	assert_true(v.player.in_cinematic, "a soldier going down cuts in")
	assert_eq(v.hud.callout.summary().icon, "bloom_claw", "claw icon")
	v.player.flush()
	var sum: Dictionary = v.hud.callout.summary()
	assert_eq(sum.word, "HIT", "hit")
	assert_true(sum.statuses.has("down"), "the soldier shown going down")
	v.free()
