extends SceneTree
## Face-cover study renders (exploration only): the model lineup with one option's props on every
## NPC head. Needs a real renderer.
##   godot --rendering-driver opengl3 -s tools/shot_faces.gd -- OUT_DIR OPTION [close_kinds]
## OPTION: base, growth, mask, cowl, wrap. Writes OPTION-lineup.jpg, OPTION-tactical.jpg and
## OPTION-close-KIND.jpg for each close kind.

const Lineup := preload("res://view/lineup.gd")
const Face := preload("res://tools/face_proto.gd")
const ModelKit := preload("res://view/model_kit.gd")

const KINDS := ["runner", "spitter", "leaper", "shrieker", "broodling", "brute", "bloater", "brood_mother", "fallen",
	"colonel_hale", "civilian"]

var _out := ""
var _opt := ""
var _lineup: Node3D
var _cam: Camera3D
var _heads := {}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	_opt = args[1]
	var closes: PackedStringArray = (args[2] if args.size() > 2 else "runner,shrieker,brute,spitter,civilian,brood_mother").split(",")
	_run.call_deferred(closes)


func _run(closes: PackedStringArray) -> void:
	root.msaa_3d = Viewport.MSAA_DISABLED
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	if _opt.begins_with("shade"):
		_patch_shader()
	_lineup = Lineup.new()
	root.add_child(_lineup)
	_lineup.set_process(false)
	await process_frame
	await process_frame
	_cam = _lineup._cam
	for uv in _lineup.views:
		if not (_opt == "base" or _opt.begins_with("shade")):
			var att := Face.dress(uv._model, uv.kind, _opt)
			if att != null:
				ModelKit.apply_materials(att, uv.owner_player, uv.soldier_body)
				_heads[uv.kind] = att
			else:
				_heads[uv.kind] = _head_marker(uv)
		else:
			_heads[uv.kind] = _head_marker(uv)
	for i in 6:
		_tick()
		await process_frame
	var n: int = _lineup.views.size()
	# lineup
	_cam.fov = 38.0
	_cam.position = Vector3(0, 1.45, 10.5)
	_cam.look_at(Vector3(0, 0.95, 0))
	await _shot("lineup")
	# tactical: the game camera (13 m, 55 degrees, fov 50)
	_cam.fov = 50.0
	var pitch := deg_to_rad(55.0)
	var target := Vector3(0, 0.8, 0)
	_cam.position = target + Vector3(0, sin(pitch), cos(pitch)) * 13.0
	_cam.look_at(target)
	await _shot("tactical")
	for k in closes:
		var uv: Node3D = null
		for v in _lineup.views:
			if v.kind == k:
				uv = v
		if uv == null:
			continue
		var head: Node3D = _heads.get(k)
		var hp: Vector3 = head.global_position
		var sz := ModelKit.size_of(k)
		_cam.fov = 24.0
		var fwd: Vector3 = head.global_transform.basis.z.normalized()
		var dir := (fwd * 1.0 + Vector3(0.35, 0.25, 0.3)).normalized()
		_cam.position = hp + dir * 0.9 * sz
		_cam.look_at(hp + Vector3(0, 0.02, 0))
		await _shot("close-" + k)
	quit(0)


func _tick() -> void:
	for uv in _lineup.views:
		uv.tick(0.016)


func _shot(name: String) -> void:
	for i in 3:
		_tick()
		await process_frame
	var img := root.get_texture().get_image()
	img.save_jpg("%s/%s-%s.jpg" % [_out, _opt, name], 0.9)
	print("[faces] ", _opt, " ", name)


func _head_marker(uv: Node3D) -> Node3D:
	var sk := uv._model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var att := BoneAttachment3D.new()
	sk.add_child(att)
	att.bone_name = "Head"
	return att


## Face-darkening: bare skin on the head (rest-space height above the neck, front half) goes
## near black; the glowing eyes are separate meshes and stay lit.
func _patch_shader() -> void:
	var sh := load("res://view/character.gdshader") as Shader
	var amt := "1.0" if _opt == "shade" else "0.78"
	var code := sh.code
	code = code.replace("uniform bool textured = false;", "uniform bool textured = false;\nuniform float face_dark = 1.0;")
	code = code.replace("		NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), texture(normal_tex, UV).rgb, bare);", """		float fdp = face_dark * smoothstep(1.50, 1.57, obj_pos.z) * smoothstep(0.03, -0.04, obj_pos.y);
		NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), texture(normal_tex, UV).rgb, bare * (1.0 - fdp));""")
	code = code.replace("	ALBEDO = col;", """	float fd_head = smoothstep(1.50, 1.57, p.z);
	float fd_front = smoothstep(0.03, -0.04, p.y);
	float fd = face_dark * fd_head * fd_front * max(skin, skin_all);
	col *= 1.0 - fd * %s;
	ALBEDO = col;""" % amt)
	code = code.replace("	EMISSION = emit;", "	EMISSION = emit * (1.0 - fd);\n	SPECULAR = 1.0 - fd;")
	sh.code = code
