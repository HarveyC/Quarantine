extends SceneTree
## Dev check: renders animation filmstrips of glbs built on their own skeletons (tools-style prototype).
## godot -s tools/shot_newrig.gd -- GLB_DIR OUT_DIR
const ModelKit := preload("res://view/model_kit.gd")

var _jobs := []   # [file, clip, times, soldier]
var _dir := ""
var _out := ""
var _frames := 0
var _cam: Camera3D
var _cur := -1
var _nodes := []


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	_dir = a[0]
	_out = a[1]
	root.size = Vector2i(1800, 560)
	_jobs = [
		["carrier", "walk", [0.0, 0.17, 0.33, 0.5, 0.67, 0.83], true],
		["carrier", "aim", [0.0, 0.04, 0.12, 0.3, 0.6, 0.9], true],
		["carrier", "death", [0.0, 0.2, 0.4, 0.6, 0.8, 1.0], true],
		["crawler", "walk", [0.0, 0.17, 0.33, 0.5, 0.67, 0.83], false],
		["crawler", "strike", [0.0, 0.15, 0.3, 0.45, 0.6, 0.8], false],
		["crawler", "death", [0.0, 0.2, 0.4, 0.6, 0.8, 1.0], false],
	]
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0b0e0f")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("2c3a40")
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
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
	pm.size = Vector2(40, 40)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("2a2c28")
	fm.roughness = 0.95
	fl.material_override = fm
	root.add_child(fl)
	_cam = Camera3D.new()
	_cam.fov = 34.0
	root.add_child(_cam)
	_cam.current = true


func _load(job: Array) -> void:
	for n in _nodes:
		n.queue_free()
	_nodes.clear()
	var scene: PackedScene = load("%s/%s.glb" % [_dir, job[0]])
	var times: Array = job[2]
	for i in times.size():
		var n: Node3D = scene.instantiate()
		ModelKit.apply_materials(n, 0, job[3])
		root.add_child(n)
		n.position = Vector3((i - (times.size() - 1) * 0.5) * 1.95, 0, 0)
		n.rotation_degrees.y = float(OS.get_environment("NR_YAW") if OS.get_environment("NR_YAW") != "" else "25")
		var ap: AnimationPlayer = n.find_child("AnimationPlayer", true, false)
		if ap and ap.has_animation(job[1]):
			ap.play(job[1])
			ap.seek(float(times[i]) * ap.get_animation(job[1]).length, true)
			ap.pause()
		_nodes.append(n)
	_cam.position = Vector3(0, 1.5, 9.8)
	_cam.look_at(Vector3(0, 0.75, 0))


func _process(_d: float) -> bool:
	_frames += 1
	var phase := _frames % 12
	if phase == 1:
		_cur += 1
		if _cur >= _jobs.size():
			quit(0)
			return false
		_load(_jobs[_cur])
	elif phase == 10:
		var p := "%s/%s-%s.png" % [_out, _jobs[_cur][0], _jobs[_cur][1]]
		root.get_texture().get_image().save_png(p)
		print("[newrig] saved ", p)
	return false
