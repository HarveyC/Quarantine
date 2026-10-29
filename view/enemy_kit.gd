extends RefCounted
## Scripted variants of the existing infected rigs for the 2026-10-25 enemy sprint: each new
## kind wears another kind's character with its own props (built from primitives, like
## MeleeKit's) and tint, so it reads apart from its body at tactical zoom.
##   Hooker    a Spitter with a barbed hook arm and a coil of line on the hip
##   Sapper    a lean Runner with satchels strapped to the back and a blinking charge
##   Carapace  a Brute with a bone plate over its front
##   Stalker   a tall, pale Runner with long back spines
##   Weaver    a Shrieker with glowing strands trailing from both hands
##   Director  Hale's frame in a long white coat with a headset and a data slate (Halden-Voss Recovery)
##   Collector a Sharpshooter's body with a net launcher across the chest and a winch drum on the back
## Bone frames (rest pose): spine bones +Y up the spine, +Z the chest, -Z the back;
## hand/forearm bones +Y toward the fingers.

const GunModels := preload("res://view/gun_models.gd")

const BODY := {"hooker": "spitter", "sapper": "runner", "carapace": "brute", "stalker": "runner", "weaver": "shrieker",
	"cutter": "runner", "torchman": "fallen", "fence": "fallen",
	"shieldman": "fallen", "overwatcher": "fallen", "emplacement": "fallen",
	"hound": "runner", "loader": "brute", "relay": "shrieker",
	"netter": "fallen", "handler": "fallen", "sterilizer": "fallen", "collector": "fallen",
	"acolyte": "runner", "cantor": "shrieker", "hush": "shrieker",
	"director": "colonel_hale"}
const SIZE := {"hooker": 1.0, "sapper": 0.88, "carapace": 1.1, "stalker": 1.12, "weaver": 0.95, "cutter": 0.95, "torchman": 1.05, "fence": 0.95,
	"shieldman": 1.1, "overwatcher": 1.0, "emplacement": 1.0,
	"hound": 0.8, "loader": 1.2, "relay": 0.7,
	"netter": 1.05, "handler": 0.95, "sterilizer": 1.1, "collector": 1.15,
	"acolyte": 0.85, "cantor": 1.0, "hush": 0.95}
## Role tints: kind -> {role: lighten (+) or darken (-) amount}.
const TINT := {
	"hooker": {"body": -0.25, "flesh": -0.15},
	"sapper": {"body": -0.1, "rags": -0.2},
	"carapace": {"body": -0.15},
	"stalker": {"body": 0.35, "skin": 0.35, "flesh": 0.3, "chitin": 0.3},
	"weaver": {"body": 0.3, "skin": 0.3, "flesh": 0.25},
	"cutter": {"body": 0.15, "rags": 0.1},
	"torchman": {"body": -0.1},
	"fence": {"body": 0.1, "rags": 0.2},
	"shieldman": {"body": 0.2},
	"overwatcher": {"body": -0.2},
	"emplacement": {"body": 0.1},
	"hound": {"body": -0.3, "skin": -0.3, "flesh": -0.3},
	"loader": {"body": -0.25, "skin": -0.25},
	"relay": {"body": -0.3, "skin": -0.3, "flesh": -0.3},
	"netter": {"body": 0.3}, "handler": {"body": 0.1, "rags": -0.15}, "sterilizer": {"body": 0.4},
	"collector": {"body": -0.1, "rags": 0.1},
	"acolyte": {"body": 0.35, "skin": 0.3, "rags": 0.3}, "cantor": {"body": 0.45, "skin": 0.4, "flesh": 0.2},
	"hush": {"body": -0.3, "skin": 0.3, "flesh": -0.1},
	"director": {"body": 0.3, "cloth_team": 0.45, "armor_team": 0.35, "cloak_team": 0.5},
}


static func has(kind: String) -> bool:
	return BODY.has(kind)


static func body_of(kind: String) -> String:
	return BODY.get(kind, "runner")


static func size_of(kind: String) -> float:
	return SIZE.get(kind, 1.0)


static func dress(model: Node3D, kind: String) -> void:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var sk := skels[0] as Skeleton3D
	model.set_meta("variant", kind)
	match kind:
		"hooker":
			_attach(sk, "lowerarm_r", "hook_arm", _hook_arm())
			_attach(sk, "pelvis", "line_coil", _coil())
		"sapper":
			_attach(sk, "spine_03", "satchels", _satchels())
		"carapace":
			_attach(sk, "spine_03", "plate_front", _plate())
		"stalker":
			_attach(sk, "spine_03", "back_spines", _spines())
		"torchman":
			_attach(sk, "spine_03", "fuel_tank", _tank())
		"shieldman":
			_attach(sk, "spine_03", "riot_shield", _shield())
		"emplacement":
			_attach(sk, "pelvis", "sandbags", _sandbags())
		"director":
			_attach(sk, "spine_03", "long_coat", _coat())
			_attach(sk, "Head", "headset", _headset())
			_attach(sk, "lowerarm_l", "data_slate", _slate())
		"collector":
			_attach(sk, "spine_03", "net_launcher", _net_launcher())
			_attach(sk, "spine_03", "winch_drum", _winch())
		"weaver":
			_attach(sk, "lowerarm_l", "strands_l", _strands())
			_attach(sk, "lowerarm_r", "strands_r", _strands())


static func tint(kind: String, mats: Dictionary) -> void:
	var t: Dictionary = TINT.get(kind, {})
	for role in t:
		if mats.has(role):
			var m: ShaderMaterial = mats[role]
			var c: Color = m.get_shader_parameter("albedo")
			m.set_shader_parameter("albedo", c.lightened(t[role]) if t[role] > 0.0 else c.darkened(-t[role]))


static func _attach(sk: Skeleton3D, bone: String, nm: String, mesh: Mesh) -> MeshInstance3D:
	var att := BoneAttachment3D.new()
	att.name = nm + "_att"
	sk.add_child(att)
	att.bone_name = bone
	var b := sk.find_bone(bone)
	if b >= 0:
		att.transform = sk.get_bone_global_rest(b)
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	att.add_child(mi)
	return mi


static func _hook_arm() -> Mesh:
	var p := [
		["metal", "tube", Vector3(0.0, 0.05, 0.04), Vector3(0.0, 0.36, 0.08), 0.04],
		["metal", "tube", Vector3(0.0, 0.36, 0.08), Vector3(0.0, 0.56, 0.0), 0.022],
		["metal", "tube", Vector3(0.0, 0.56, 0.0), Vector3(0.0, 0.66, -0.12), 0.016],
		["metal", "tube", Vector3(0.0, 0.66, -0.12), Vector3(0.0, 0.58, -0.2), 0.012],
		["glow", "ball", Vector3(0.0, 0.2, 0.07), 0.02],
	]
	for i in 3:
		p.append(["metal", "box", Vector3(0.0, 0.12 + i * 0.08, 0.075), Vector3(0.012, 0.03, 0.05), Vector3(0.5, 0, 0)])
	return GunModels.build_mesh(p, {}, {"metal": Color("8a8a7c")})


static func _coil() -> Mesh:
	var p := []
	for i in 4:
		p.append(["leather", "tube", Vector3(0.17, -0.02 + i * 0.03, -0.06), Vector3(0.17, -0.02 + i * 0.03, 0.06), 0.045 - i * 0.003])
	p.append(["glow", "ball", Vector3(0.17, 0.1, 0.0), 0.02])
	return GunModels.build_mesh(p, {}, {"leather": Color("2a2420")})


static func _satchels() -> Mesh:
	var p := [
		["leather", "box", Vector3(0.0, 0.0, -0.17), Vector3(0.34, 0.26, 0.12)],
		["leather", "box", Vector3(0.0, 0.0, -0.17), Vector3(0.38, 0.03, 0.14)],
		["metal", "box", Vector3(0.17, -0.2, -0.15), Vector3(0.1, 0.16, 0.1)],
		["metal", "box", Vector3(-0.17, -0.2, -0.15), Vector3(0.1, 0.16, 0.1)],
		["amber", "box", Vector3(0.0, 0.03, -0.24), Vector3(0.26, 0.03, 0.01)],
		["lamp", "ball", Vector3(0.0, 0.0, -0.25), 0.028],
		["leather", "box", Vector3(0.0, 0.08, 0.2), Vector3(0.42, 0.06, 0.05), Vector3(0.0, 0.0, 0.5)],
		["metal", "box", Vector3(-0.08, 0.08, 0.235), Vector3(0.1, 0.1, 0.05), Vector3(0.0, 0.0, 0.5)],
		["lamp", "ball", Vector3(-0.08, 0.08, 0.265), 0.025],
	]
	return GunModels.build_mesh(p, {}, {"leather": Color("3a3228"), "lamp": [Color(0.55, 0.2, 0.08), Color(1.0, 0.55, 0.15)]})


static func _tank() -> Mesh:
	var p := [
		["metal", "tube", Vector3(0.0, -0.18, -0.19), Vector3(0.0, 0.2, -0.19), 0.1],
		["amber", "box", Vector3(0.0, 0.0, -0.29), Vector3(0.16, 0.03, 0.01)],
		["lamp", "ball", Vector3(0.0, 0.26, -0.19), 0.035],
	]
	return GunModels.build_mesh(p, {}, {"metal": Color("a0412c"), "lamp": [Color(0.55, 0.2, 0.08), Color(1.0, 0.55, 0.15)]})


static func _shield() -> Mesh:
	var p := [
		["glass", "box", Vector3(0.0, 0.05, 0.28), Vector3(0.5, 0.7, 0.04)],
		["frame", "box", Vector3(0.0, 0.42, 0.28), Vector3(0.56, 0.05, 0.06)],
		["frame", "box", Vector3(0.0, -0.3, 0.28), Vector3(0.56, 0.05, 0.06)],
		["amber", "box", Vector3(0.0, 0.05, 0.31), Vector3(0.4, 0.03, 0.01)],
	]
	return GunModels.build_mesh(p, {}, {"glass": Color("4a5a66"), "frame": Color("2a2a28")})


static func _sandbags() -> Mesh:
	var p := []
	for i in 5:
		p.append(["bag", "box", Vector3(-0.4 + i * 0.2, -0.1, 0.4), Vector3(0.22, 0.16, 0.16)])
	for i in 4:
		p.append(["bag", "box", Vector3(-0.3 + i * 0.2, 0.05, 0.4), Vector3(0.22, 0.16, 0.16)])
	p.append(["metal", "tube", Vector3(0.0, 0.2, 0.2), Vector3(0.0, 0.2, 0.7), 0.04])
	return GunModels.build_mesh(p, {}, {"bag": Color("8a7e5c"), "metal": Color("3a3a38")})


static func _plate() -> Mesh:
	var p := [
		["plate", "box", Vector3(0.0, 0.06, 0.2), Vector3(0.5, 0.62, 0.06)],
		["plate", "box", Vector3(0.0, 0.4, 0.17), Vector3(0.58, 0.14, 0.08)],
		["amber", "box", Vector3(0.0, 0.06, 0.235), Vector3(0.44, 0.03, 0.01)],
		["amber", "box", Vector3(0.0, -0.12, 0.235), Vector3(0.44, 0.03, 0.01)],
	]
	for x in [-0.2, 0.0, 0.2]:
		p.append(["plate", "box", Vector3(x, 0.06, 0.24), Vector3(0.05, 0.5, 0.03)])
	return GunModels.build_mesh(p, {}, {"plate": Color("d0c6a8")})


static func _spines() -> Mesh:
	var p := []
	for i in 5:
		var x := -0.16 + i * 0.08
		var h := 0.3 + 0.07 * float((i * 5) % 3)
		p.append(["bone", "tube", Vector3(x, 0.0, -0.12), Vector3(x * 1.4, 0.12 + h * 0.5, -0.12 - h * 0.6), 0.012])
	p.append(["glow", "ball", Vector3(0.0, 0.1, -0.15), 0.025])
	return GunModels.build_mesh(p, {}, {"bone": Color("cfc9b4")})


static func _strands() -> Mesh:
	var p := []
	for i in 4:
		var s := -0.04 + i * 0.027
		p.append(["glow", "tube", Vector3(s, 0.1, 0.0), Vector3(s * 3.0, 0.4 + i * 0.05, 0.04 - i * 0.03), 0.006])
	p.append(["glow", "ball", Vector3(0.0, 0.1, 0.0), 0.022])
	return GunModels.build_mesh(p, {}, {})


static func _coat() -> Mesh:
	var p := [
		["coat", "box", Vector3(0.07, -0.34, -0.13), Vector3(0.12, 0.9, 0.025), Vector3(0.0, 0.0, -0.05)],
		["coat", "box", Vector3(-0.07, -0.34, -0.13), Vector3(0.12, 0.9, 0.025), Vector3(0.0, 0.0, 0.05)],
		["coat", "box", Vector3(0.0, 0.16, -0.1), Vector3(0.26, 0.07, 0.07)],
		["trim", "box", Vector3(0.0, -0.78, -0.13), Vector3(0.3, 0.02, 0.03)],
	]
	return GunModels.build_mesh(p, {}, {"coat": Color("d6d9d3"), "trim": Color("2a2d30")})


static func _headset() -> Mesh:
	var p := [
		["metal", "ball", Vector3(0.1, 0.02, 0.0), 0.04],
		["metal", "tube", Vector3(0.1, 0.02, 0.02), Vector3(0.05, -0.06, 0.15), 0.008],
		["lens", "ball", Vector3(0.05, -0.06, 0.16), 0.018],
		["metal", "tube", Vector3(0.1, 0.05, -0.02), Vector3(0.12, 0.3, -0.04), 0.006],
	]
	return GunModels.build_mesh(p, {}, {"metal": Color("3a3d40"), "lens": [Color(0.5, 0.3, 0.1), Color(1.0, 0.6, 0.2)]})


static func _slate() -> Mesh:
	var p := [
		["frame", "box", Vector3(0.0, 0.2, 0.08), Vector3(0.16, 0.22, 0.02)],
		["lens", "box", Vector3(0.0, 0.2, 0.095), Vector3(0.13, 0.18, 0.004)],
	]
	return GunModels.build_mesh(p, {}, {"frame": Color("2a2d30"), "lens": [Color(0.1, 0.3, 0.4), Color(0.4, 0.8, 1.0)]})


static func _net_launcher() -> Mesh:
	var p := [
		["metal", "tube", Vector3(-0.2, -0.05, 0.22), Vector3(0.2, 0.2, 0.22), 0.045, 0.06],
		["strap", "box", Vector3(0.0, 0.08, 0.2), Vector3(0.5, 0.05, 0.03), Vector3(0.0, 0.0, 0.5)],
		["lamp", "ball", Vector3(0.2, 0.2, 0.22), 0.03],
	]
	return GunModels.build_mesh(p, {}, {"metal": Color("4a4d50"), "strap": Color("d36a1c"), "lamp": [Color(0.55, 0.2, 0.08), Color(1.0, 0.55, 0.15)]})


static func _winch() -> Mesh:
	var p := [
		["metal", "tube", Vector3(-0.14, 0.0, -0.2), Vector3(0.14, 0.0, -0.2), 0.11],
		["strap", "tube", Vector3(-0.1, 0.0, -0.2), Vector3(0.1, 0.0, -0.2), 0.125],
		["metal", "box", Vector3(0.0, 0.16, -0.2), Vector3(0.1, 0.06, 0.1)],
		["lamp", "ball", Vector3(0.0, 0.2, -0.16), 0.02],
	]
	return GunModels.build_mesh(p, {}, {"metal": Color("4a4d50"), "strap": Color("d36a1c"), "lamp": [Color(0.55, 0.2, 0.08), Color(1.0, 0.55, 0.15)]})
