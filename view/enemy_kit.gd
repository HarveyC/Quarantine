extends RefCounted
## Scripted variants of the existing infected rigs for the 2026-10-25 enemy sprint: each new
## kind wears another kind's character with its own props (built from primitives, like
## MeleeKit's) and tint, so it reads apart from its body at tactical zoom.
##   Hooker    a Spitter with a barbed hook arm and a coil of line on the hip
##   Sapper    a lean Runner with satchels strapped to the back and a blinking charge
##   Carapace  a Brute with a bone plate over its front
##   Stalker   a tall, pale Runner with long back spines
##   Weaver    a Shrieker with glowing strands trailing from both hands
## Bone frames (rest pose): spine bones +Y up the spine, +Z the chest, -Z the back;
## hand/forearm bones +Y toward the fingers.

const GunModels := preload("res://view/gun_models.gd")

const BODY := {"hooker": "spitter", "sapper": "runner", "carapace": "brute", "stalker": "runner", "weaver": "shrieker",
	"cutter": "runner", "torchman": "fallen", "fence": "fallen",
	"shieldman": "fallen", "overwatcher": "fallen", "emplacement": "fallen",
	"hound": "runner", "loader": "brute", "relay": "shrieker",
	"packrat": "brute", "rigger": "runner", "lookout": "fallen", "sergeant": "fallen", "grenadier": "fallen", "field_medic": "fallen",
	"tender": "shrieker", "carrier": "brute", "arc_welder": "runner"}
const SIZE := {"hooker": 1.0, "sapper": 0.88, "carapace": 1.1, "stalker": 1.12, "weaver": 0.95, "cutter": 0.95, "torchman": 1.05, "fence": 0.95,
	"shieldman": 1.1, "overwatcher": 1.0, "emplacement": 1.0,
	"hound": 0.8, "loader": 1.2, "relay": 0.7,
	"packrat": 0.95, "rigger": 0.9, "lookout": 0.95, "sergeant": 1.05, "grenadier": 1.0, "field_medic": 1.0,
	"tender": 0.9, "carrier": 1.0, "arc_welder": 0.9}
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
	"packrat": {"body": 0.1, "rags": 0.25},
	"rigger": {"body": 0.05, "rags": 0.15},
	"lookout": {"body": 0.1, "rags": 0.1},
	"sergeant": {"body": 0.25},
	"grenadier": {"body": -0.05},
	"field_medic": {"body": 0.3},
	"tender": {"body": -0.3, "skin": -0.3, "flesh": -0.3},
	"carrier": {"body": -0.35, "skin": -0.35, "flesh": -0.35},
	"arc_welder": {"body": -0.3, "skin": -0.3, "flesh": -0.3},
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
		"packrat":
			_attach(sk, "spine_03", "scrap_plates", _scrap())
		"rigger":
			_attach(sk, "spine_03", "wire_spool", _spool())
		"lookout":
			_attach(sk, "spine_03", "signal_lamp", _lamp())
		"sergeant":
			_attach(sk, "spine_03", "radio_mast", _mast())
		"grenadier":
			_attach(sk, "spine_03", "bandolier", _bandolier())
		"field_medic":
			_attach(sk, "spine_03", "med_pack", _medpack())
		"tender":
			_attach(sk, "spine_03", "tool_arms", _tool_arms())
		"carrier":
			_attach(sk, "spine_03", "drone_bay", _bay())
		"arc_welder":
			_attach(sk, "spine_03", "welding_rig", _welder())
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


# --- 2026-10-28 faction packs: Scavengers, Security, Automata -------------------------------------

## Packrat: salvage hung off the body as plates: a hubcap on the chest, a door panel on the back, pans on the shoulders.
static func _scrap() -> Mesh:
	var p := [
		["scrap", "box", Vector3(0.0, 0.1, 0.22), Vector3(0.46, 0.5, 0.04), Vector3(0.0, 0.0, 0.08)],
		["rust", "box", Vector3(0.0, 0.05, -0.2), Vector3(0.56, 0.62, 0.05), Vector3(0.0, 0.0, -0.06)],
		["scrap", "box", Vector3(0.3, 0.38, 0.0), Vector3(0.24, 0.05, 0.3), Vector3(0.0, 0.0, 0.3)],
		["scrap", "box", Vector3(-0.3, 0.38, 0.0), Vector3(0.24, 0.05, 0.3), Vector3(0.0, 0.0, -0.3)],
		["rust", "box", Vector3(0.0, -0.22, 0.22), Vector3(0.4, 0.18, 0.04)],
		["amber", "box", Vector3(0.0, 0.1, 0.25), Vector3(0.3, 0.03, 0.01)],
	]
	for i in 3:
		p.append(["scrap", "tube", Vector3(-0.18 + i * 0.18, -0.35, -0.22), Vector3(-0.18 + i * 0.18, -0.55, -0.22), 0.025])
	return GunModels.build_mesh(p, {}, {"scrap": Color("8c8e86"), "rust": Color("6a4a32")})


## Rigger: a drum of wire on the back and hooks on the belt.
static func _spool() -> Mesh:
	var p := [
		["drum", "tube", Vector3(-0.14, 0.05, -0.2), Vector3(0.14, 0.05, -0.2), 0.17],
		["wire", "tube", Vector3(-0.1, 0.05, -0.2), Vector3(0.1, 0.05, -0.2), 0.2],
		["drum", "box", Vector3(0.0, -0.17, -0.2), Vector3(0.32, 0.04, 0.12)],
		["amber", "ball", Vector3(0.0, 0.05, -0.38), 0.025],
	]
	for i in 3:
		p.append(["drum", "tube", Vector3(0.16, -0.18, -0.05 + i * 0.05), Vector3(0.16, -0.3, -0.05 + i * 0.05), 0.012])
	return GunModels.build_mesh(p, {}, {"drum": Color("4a4a44"), "wire": Color("a49a7a")})


## Lookout: a signal lamp on a shoulder mast and a flare pistol holster.
static func _lamp() -> Mesh:
	var p := [
		["steel", "tube", Vector3(0.18, 0.2, -0.05), Vector3(0.18, 0.62, -0.05), 0.02],
		["steel", "box", Vector3(0.18, 0.66, -0.05), Vector3(0.16, 0.12, 0.12)],
		["lamp", "ball", Vector3(0.18, 0.66, 0.03), 0.055],
		["steel", "box", Vector3(-0.2, -0.2, 0.12), Vector3(0.08, 0.2, 0.1)],
		["amber", "box", Vector3(-0.2, -0.1, 0.18), Vector3(0.05, 0.05, 0.02)],
	]
	return GunModels.build_mesh(p, {}, {"steel": Color("3a3a38"), "lamp": [Color(0.55, 0.2, 0.08), Color(1.0, 0.45, 0.15)]})


## Sergeant: a tall radio mast on the back and a rank band across the chest.
static func _mast() -> Mesh:
	var p := [
		["steel", "box", Vector3(0.0, 0.05, -0.2), Vector3(0.3, 0.34, 0.12)],
		["steel", "tube", Vector3(0.1, 0.2, -0.22), Vector3(0.1, 0.95, -0.25), 0.012],
		["amber", "ball", Vector3(0.1, 0.96, -0.25), 0.03],
		["band", "box", Vector3(0.0, 0.3, 0.2), Vector3(0.52, 0.07, 0.04)],
		["band", "box", Vector3(0.0, 0.22, 0.21), Vector3(0.52, 0.04, 0.04)],
		["amber", "box", Vector3(0.0, 0.3, 0.225), Vector3(0.2, 0.025, 0.01)],
	]
	return GunModels.build_mesh(p, {}, {"steel": Color("3a3d3c"), "band": Color("7a6a3a")})


## Grenadier: a bandolier of grenades slung across the chest and a satchel on the hip.
static func _bandolier() -> Mesh:
	var p := [
		["strap", "tube", Vector3(-0.24, 0.35, 0.18), Vector3(0.24, -0.15, 0.2), 0.03],
		["bag", "box", Vector3(0.2, -0.2, -0.05), Vector3(0.16, 0.2, 0.22)],
	]
	for i in 4:
		var t := 0.12 + i * 0.22
		var c := Vector3(-0.24, 0.35, 0.2).lerp(Vector3(0.24, -0.15, 0.22), t)
		p.append(["nade", "ball", c + Vector3(0, 0, 0.05), 0.045])
		p.append(["amber", "ball", c + Vector3(0, 0.05, 0.05), 0.014])
	return GunModels.build_mesh(p, {}, {"strap": Color("2e2a22"), "nade": Color("4a5a3a"), "bag": Color("4a4a38")})


## Field medic: a pack on the back with a cross, and a chest light.
static func _medpack() -> Mesh:
	var p := [
		["pack", "box", Vector3(0.0, 0.05, -0.2), Vector3(0.42, 0.5, 0.16)],
		["cross", "box", Vector3(0.0, 0.05, -0.285), Vector3(0.22, 0.06, 0.01)],
		["cross", "box", Vector3(0.0, 0.05, -0.285), Vector3(0.06, 0.22, 0.01)],
		["pack", "box", Vector3(0.0, 0.3, 0.2), Vector3(0.14, 0.14, 0.03)],
		["cross", "box", Vector3(0.0, 0.3, 0.22), Vector3(0.1, 0.03, 0.01)],
		["cross", "box", Vector3(0.0, 0.3, 0.22), Vector3(0.03, 0.1, 0.01)],
	]
	return GunModels.build_mesh(p, {}, {"pack": Color("5a5e58"), "cross": [Color(0.6, 0.15, 0.1), Color(0.9, 0.25, 0.15)]})


## Tender: a pair of servo arms folded over the shoulders, tipped with work lamps.
static func _tool_arms() -> Mesh:
	var p := []
	for sx in [-1.0, 1.0]:
		p.append(["servo", "tube", Vector3(sx * 0.2, 0.2, -0.1), Vector3(sx * 0.34, 0.5, -0.1), 0.03])
		p.append(["servo", "tube", Vector3(sx * 0.34, 0.5, -0.1), Vector3(sx * 0.2, 0.7, 0.1), 0.024])
		p.append(["lamp", "ball", Vector3(sx * 0.2, 0.72, 0.12), 0.04])
	p.append(["servo", "box", Vector3(0.0, 0.1, -0.2), Vector3(0.4, 0.4, 0.14)])
	p.append(["amber", "box", Vector3(0.0, 0.1, -0.275), Vector3(0.28, 0.03, 0.01)])
	return GunModels.build_mesh(p, {}, {"servo": Color("55575a"), "lamp": [Color(0.5, 0.35, 0.1), Color(1.0, 0.7, 0.2)]})


## Carrier: a drone bay strapped on a hauler: a box with a hatch, drones in racks, and a beacon.
static func _bay() -> Mesh:
	var p := [
		["hull", "box", Vector3(0.0, 0.3, -0.05), Vector3(0.9, 0.6, 0.7)],
		["hatch", "box", Vector3(0.0, 0.3, 0.31), Vector3(0.6, 0.4, 0.03)],
		["amber", "box", Vector3(0.0, 0.3, 0.33), Vector3(0.5, 0.03, 0.01)],
		["amber", "box", Vector3(0.0, 0.5, 0.33), Vector3(0.5, 0.03, 0.01)],
		["hull", "tube", Vector3(0.3, 0.6, -0.05), Vector3(0.3, 1.0, -0.05), 0.02],
		["lamp", "ball", Vector3(0.3, 1.02, -0.05), 0.05],
	]
	for sx in [-0.28, 0.0, 0.28]:
		p.append(["hatch", "box", Vector3(sx, 0.62, -0.05), Vector3(0.2, 0.06, 0.3)])
	return GunModels.build_mesh(p, {}, {"hull": Color("4a4d4a"), "hatch": Color("2c2e2d"), "lamp": [Color(0.5, 0.35, 0.1), Color(1.0, 0.7, 0.2)]})


## Arc-welder: a gas bottle on the back and two arc rods held out front, tipped with blue-white light.
static func _welder() -> Mesh:
	var p := [
		["bottle", "tube", Vector3(0.0, -0.15, -0.22), Vector3(0.0, 0.35, -0.22), 0.09],
		["steel", "box", Vector3(0.0, 0.38, -0.22), Vector3(0.1, 0.08, 0.1)],
		["steel", "tube", Vector3(0.0, 0.38, -0.2), Vector3(0.3, 0.2, 0.1), 0.012],
	]
	for sx in [-1.0, 1.0]:
		p.append(["steel", "tube", Vector3(sx * 0.12, 0.05, 0.1), Vector3(sx * 0.14, 0.05, 0.5), 0.016])
		p.append(["arc", "ball", Vector3(sx * 0.14, 0.05, 0.53), 0.04])
	return GunModels.build_mesh(p, {}, {"bottle": Color("5a6a7a"), "steel": Color("303234"), "arc": [Color(0.5, 0.6, 0.8), Color(0.7, 0.88, 1.0)]})
