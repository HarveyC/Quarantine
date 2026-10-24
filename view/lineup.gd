extends Node3D
## Dev aid: a model lineup for checking soldier / enemy art up close.
## `godot -- --lineup=out.png [--lineup-mode=classes|infection|action]` renders one
## frame and quits; without a path it stays open as a turntable viewer.
##   classes:   the four classes (P1, P1, P2, P2) plus every enemy model
##   infection: one soldier per infection tier, Clean to Turned
##   action:    the classes and enemies aiming / lunging mid-animation
##   hit:       everyone flinching from a non-lethal hit
## `--lineup-kinds=runner,spitter` shows just those models, closer up.

const UnitView := preload("res://view/unit_view.gd")
const PostFx := preload("res://view/post_fx.gd")
const ModelKit := preload("res://view/model_kit.gd")

const ENEMIES: Array[String] = ["runner", "spitter", "leaper", "shrieker", "broodling", "brute", "bloater",
	"brood_mother", "fallen", "sharpshooter", "colonel_hale", "lurker", "burrower"]

var mode := "classes"
var shot_path := ""
var views: Array = []
var _frames := 0
var _cam: Camera3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lineup="):
			shot_path = a.trim_prefix("--lineup=")
		elif a.begins_with("--lineup-mode="):
			mode = a.trim_prefix("--lineup-mode=")
	_build_stage()
	var kinds_arg := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lineup-kinds="):
			kinds_arg = a.trim_prefix("--lineup-kinds=")
	if kinds_arg != "":
		var ks := kinds_arg.split(",")
		for i in ks.size():
			var soldier := not (ks[i] in ENEMIES)
			var uv := _spawn(ks[i], i % 2 if soldier else -1, 0)
			uv.position = Vector3((i - (ks.size() - 1) * 0.5) * 1.1, 0, 0)
		_cam.position = Vector3(0, 1.4, 1.6 + ks.size() * 1.1)
		_cam.look_at(Vector3(0, 0.9, 0))
		return
	match mode:
		"infection":
			var values := [0, 30, 60, 85, 100]
			for i in values.size():
				var uv := _spawn("trooper", 0, values[i])
				uv.position = Vector3((i - 2) * 1.25, 0, 0)
				if values[i] >= 100:
					uv.set_turned()
		_:
			# squad (and a civilian) in front, the infected behind them
			var kinds := ["trooper", "marksman", "medic", "breacher", "civilian"]
			for i in kinds.size():
				var uv := _spawn(kinds[i], [0, 0, 1, 1, -1][i], 0)
				uv.position = Vector3((i - 2) * 1.3, 0, 1.2)
			var x := -6.2
			for k in ENEMIES:
				var w := 0.9 * ModelKit.size_of(k)
				x += w * 0.5
				var uv := _spawn(k, -1, 0)
				uv.position = Vector3(x, 0, -1.6)
				x += w * 0.5 + 0.25
	var cam_z := 6.2 if mode == "infection" else 9.5
	_cam.position = Vector3(0, 2.2 if mode != "infection" else 1.75, cam_z)
	_cam.look_at(Vector3(0, 1.0, 0))


func _spawn(kind: String, player: int, infection: int) -> Node3D:
	var u := Unit.new()
	u.id = views.size() + 1
	u.kind = kind
	u.display_name = kind.capitalize()
	u.owner_player = player
	u.team = Types.Team.ENEMY if kind in ENEMIES else Types.Team.PLAYER
	u.max_hp = 6
	u.hp = 6
	u.infection = infection
	var uv := UnitView.new()
	uv.build(u)
	uv.set_overlays_visible(false)
	add_child(uv)
	uv.face_towards(uv.position + Vector3(0.75, 0, 1), true)
	views.append(uv)
	return uv


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0b0e0f")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("2c3a40")
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	GameSettings.apply_environment(env)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color("ffd9a6")
	key.light_energy = 1.3
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-40, 35, 0)
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("5fc9d6")
	rim.light_energy = 0.7
	rim.rotation_degrees = Vector3(-20, 200, 0)
	add_child(rim)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(30, 30)
	var fl := MeshInstance3D.new()
	fl.mesh = floor_mesh
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("2a2c28")
	fm.roughness = 0.95
	fl.material_override = fm
	add_child(fl)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	add_child(_cam)
	_cam.current = true
	var post := CanvasLayer.new()
	add_child(post)
	post.add_child(PostFx.make())


func _process(delta: float) -> void:
	_frames += 1
	for i in views.size():
		var uv: Node3D = views[i]
		if mode == "action" and _frames == 5:
			if uv.is_soldier:
				uv.aim_now(1.0)
			else:
				uv.set_lunge(0.6)
		if mode == "hit" and _frames == 5:
			uv.hit_react(uv.position + Vector3(0, 0, 3), 1.0)
		uv.tick(delta)
		if shot_path == "":
			uv.rotate_y(delta * 0.4)
	if shot_path != "" and _frames == (5 + _hit_frames() if mode == "hit" else 40):
		get_viewport().get_texture().get_image().save_png(shot_path)
		print("[lineup] saved ", shot_path)
		get_tree().quit(0)


## `--lineup-hit-frame=N`: how many frames after the hit to capture (default 20).
func _hit_frames() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lineup-hit-frame="):
			return int(a.trim_prefix("--lineup-hit-frame="))
	return 20
