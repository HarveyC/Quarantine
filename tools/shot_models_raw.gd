extends SceneTree
## Dev check: lays out every glb in a folder (scaled to 1.8 m, first idle-like clip posed) in the lineup lighting.
## godot -s tools/shot_models_raw.gd -- res://folder OUT.png [per_row]
var _out := ""
var _frames := 0
var _files := []
var _dir := ""
var _cam: Camera3D
var _cur: Node3D


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var dir := a[0]
	_out = a[1]
	var per_row := int(a[2]) if a.size() > 2 else 6
	root.size = Vector2i(1800, 450 * int(ceil(DirAccess.get_files_at(dir).size() / 2.0 / per_row)))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0b0e0f")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("2c3a40")
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color("ffd9a6")
	key.light_energy = 1.3
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-40, 35, 0)
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("5fc9d6")
	rim.light_energy = 0.7
	rim.rotation_degrees = Vector3(-20, 200, 0)
	root.add_child(rim)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("2a2c28")
	fm.roughness = 0.95
	fl.material_override = fm
	root.add_child(fl)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".glb"):
			_files.append(f)
	_files.sort()
	_dir = dir
	root.size = Vector2i(640, 760)
	_cam = Camera3D.new()
	_cam.fov = 34
	root.add_child(_cam)
	_cam.current = true
	_cam.position = Vector3(0, 1.1, 5.2)
	_cam.look_at(Vector3(0, 0.9, 0))


func _process(_d: float) -> bool:
	_frames += 1
	var phase := _frames % 16
	var idx := _frames / 16
	if phase == 1:
		if _cur != null:
			_cur.queue_free()
		if idx >= _files.size():
			quit(0)
			return false
		_cur = (load(_dir + "/" + _files[idx]) as PackedScene).instantiate()
		root.add_child(_cur)
		var ap: AnimationPlayer = _cur.find_child("AnimationPlayer", true, false)
		var clip := ""
		if ap:
			var list := ap.get_animation_list()
			for an in list:
				if String(an).to_lower().contains("idle"):
					clip = an
					break
			if clip == "" and list.size() > 0:
				clip = list[0]
			if clip != "":
				ap.play(clip)
				ap.seek(0.4, true)
				ap.pause()
		print("[raw] ", _files[idx], " clips ", ap.get_animation_list().size() if ap else 0, " using ", clip)
	elif phase == 6 and _cur != null:
		var b := _bone_bounds(_cur)
		var sc := 1.8 / maxf(b.size.y, 0.001)
		var c := b.get_center()
		_cur.scale = Vector3.ONE * sc
		_cur.position = Vector3(-c.x * sc, -b.position.y * sc, -c.z * sc)
		_cur.rotation_degrees.y = 20
	elif phase == 14 and _cur != null:
		var p := "%s/%s.png" % [_out, _files[idx].get_basename()]
		root.get_texture().get_image().save_png(p)
	return false


func _bounds(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var t := Transform3D.IDENTITY
		var at: Node = mi
		while at != null and at != n:
			t = (at as Node3D).transform * t
			at = at.get_parent()
		var b: AABB = t * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func _bone_bounds(n: Node3D) -> AABB:
	var sk: Skeleton3D = n.find_child("*", true, false) as Skeleton3D
	for c in n.find_children("*", "Skeleton3D", true, false):
		sk = c as Skeleton3D
	if sk == null or sk.get_bone_count() == 0:
		return _bounds(n)
	var out := AABB()
	for i in sk.get_bone_count():
		var p: Vector3 = (n.global_transform.affine_inverse() * sk.global_transform) * sk.get_bone_global_pose(i).origin
		if i == 0:
			out = AABB(p, Vector3.ZERO)
		else:
			out = out.expand(p)
	out = out.grow(maxf(out.size.y * 0.04, 0.0001))
	return out
