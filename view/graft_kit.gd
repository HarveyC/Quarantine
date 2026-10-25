extends RefCounted
## Graft meshes on a soldier body (Grafts): one prop per grafted slot, built from primitives and
## hung on the skeleton like MeleeKit's props, so ModelKit's materials, grime and hit flash
## apply. Machine parts are pale bare steel with lamps in the player's colour ("visor"); Bloom
## parts are raw tissue, bark and teal growths. Turned soldiers and Echoes reuse the body, so
## they wear them too.
##
## Machine parts use their own "graft_steel" role: ModelKit shares one material per role name,
## so "metal" would take the body's dark gunmetal.
##
## Bone frames (rest pose): Head and spine_03 +Y up, +Z out of the face / chest; lowerarm_r +Y
## runs to the wrist, -X is the back of the arm; thighs and calves +Y runs down the leg, -Z is
## the front of the leg.

const GunModels := preload("res://view/gun_models.gd")

const STEEL := Color("c8d0d5")
const FLESH := Color("6a3c3a")
const BARK := Color("3d3329")
const CLAW := Color("2b2622")
const HOSE := Color("23211e")
const COLORS := {"graft_steel": STEEL, "flesh_raw": FLESH, "growth": FLESH, "bark": BARK, "claw": CLAW, "hose": HOSE}


## Hangs a prop for every graft in `grafts` ({slot: id}) on `model`. Call before
## ModelKit.apply_materials.
static func dress(model: Node3D, grafts: Dictionary) -> void:
	if grafts.is_empty():
		return
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var sk := skels[0] as Skeleton3D
	for slot in grafts:
		match str(grafts[slot]):
			"targeting_optic": _attach(sk, "Head", "graft_head", _optic())
			"lattice_sight": _attach(sk, "Head", "graft_head", _lattice())
			"servo_arm":
				_attach(sk, "lowerarm_r", "graft_arm", _servo())
				_attach(sk, "upperarm_r", "graft_upperarm", _servo_upper())
			"bloom_limb":
				_attach(sk, "lowerarm_r", "graft_arm", _limb())
				_attach(sk, "upperarm_r", "graft_upperarm", _limb_upper())
				_attach(sk, "hand_r", "graft_claw", _claw())
			"plated_ribs": _attach(sk, "spine_03", "graft_chest", _ribs())
			"heart_knot": _attach(sk, "spine_03", "graft_chest", _knot())
			"hydraulic_legs":
				for side in ["l", "r"]:
					_attach(sk, "thigh_" + side, "graft_thigh_" + side, _brace(side == "l", 0.43))
					_attach(sk, "calf_" + side, "graft_calf_" + side, _brace(side == "l", 0.45))
			"runner_legs":
				for side in ["l", "r"]:
					_attach(sk, "thigh_" + side, "graft_thigh_" + side, _bark(side == "l", 0.43))
					_attach(sk, "calf_" + side, "graft_calf_" + side, _bark(side == "l", 0.45))


## Names of the graft props on a model (tests, renders).
static func props(model: Node) -> Array[String]:
	var out: Array[String] = []
	for n in model.find_children("graft_*", "MeshInstance3D", true, false):
		out.append(String(n.name))
	return out


static func _attach(sk: Skeleton3D, bone: String, nm: String, mesh: Mesh) -> void:
	if sk.find_bone(bone) < 0:
		return
	var att := BoneAttachment3D.new()
	att.name = nm + "_att"
	sk.add_child(att)
	att.bone_name = bone
	att.transform = sk.get_bone_global_rest(sk.find_bone(bone))
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	att.add_child(mi)


static func _mesh(parts: Array) -> Mesh:
	return GunModels.build_mesh(parts, {}, COLORS)


# --- Machine ---------------------------------------------------------------

## A big targeting lens with a range-finder over the right optic.
static func _optic() -> Mesh:
	return _mesh([
		["graft_steel", "tube", Vector3(-0.055, 0.1, 0.09), Vector3(-0.055, 0.1, 0.17), 0.045],
		["visor", "tube", Vector3(-0.055, 0.1, 0.17), Vector3(-0.055, 0.1, 0.18), 0.036],
		["graft_steel", "box", Vector3(-0.115, 0.12, 0.06), Vector3(0.03, 0.09, 0.11)],
		["graft_steel", "tube", Vector3(-0.12, 0.16, 0.04), Vector3(-0.12, 0.29, 0.04), 0.007],
		["visor", "ball", Vector3(-0.12, 0.295, 0.04), 0.014],
	])


## A bare servo forearm: a steel sleeve, pistons and a lamp along the back.
static func _servo() -> Mesh:
	return _mesh([
		["graft_steel", "box", Vector3(0, 0.05, 0), Vector3(0.11, 0.09, 0.11)],
		["graft_steel", "tube", Vector3(0.0, 0.05, 0.0), Vector3(0.0, 0.25, 0.0), 0.042],
		["graft_steel", "tube", Vector3(0.05, 0.06, 0.04), Vector3(0.045, 0.25, 0.035), 0.014],
		["graft_steel", "tube", Vector3(-0.05, 0.06, -0.04), Vector3(-0.045, 0.25, -0.035), 0.014],
		["visor", "box", Vector3(-0.057, 0.05, 0), Vector3(0.006, 0.03, 0.06)],
		["graft_steel", "box", Vector3(0, 0.26, 0), Vector3(0.085, 0.035, 0.085)],
	])


static func _servo_upper() -> Mesh:
	return _mesh([
		["graft_steel", "ball", Vector3(0, 0.02, 0), 0.07],
		["graft_steel", "tube", Vector3(0, 0.04, 0), Vector3(0, 0.2, 0), 0.05],
	])


## An armoured ribcage plate over the carrier, a second regulator and hoses on the back.
static func _ribs() -> Mesh:
	var p := [
		["graft_steel", "box", Vector3(0, 0.02, 0.17), Vector3(0.3, 0.26, 0.03)],
		["graft_steel", "tube", Vector3(0.12, -0.06, -0.17), Vector3(0.12, 0.14, -0.17), 0.045],
		["visor", "tube", Vector3(0.12, 0.14, -0.17), Vector3(0.12, 0.16, -0.17), 0.032],
		["hose", "tube", Vector3(0.12, 0.0, -0.13), Vector3(0.2, 0.02, 0.0), 0.014],
		["hose", "tube", Vector3(0.2, 0.02, 0.0), Vector3(0.13, 0.06, 0.17), 0.014],
	]
	for i in 4:
		p.append(["graft_steel", "box", Vector3(0, -0.08 + i * 0.065, 0.19), Vector3(0.26 - i * 0.02, 0.016, 0.014)])
	p.append(["visor", "box", Vector3(0, 0.12, 0.19), Vector3(0.05, 0.015, 0.01)])
	return _mesh(p)


## A hydraulic brace down the outside of a thigh or calf (`length` of the bone).
static func _brace(left: bool, length: float) -> Mesh:
	var x := 0.09 if left else -0.09
	return _mesh([
		["graft_steel", "tube", Vector3(x, 0.02, 0.0), Vector3(x, length, 0.0), 0.017],
		["graft_steel", "tube", Vector3(x, 0.06, 0.0), Vector3(x, length * 0.7, 0.0), 0.03],
		["graft_steel", "ball", Vector3(x, length, 0.0), 0.038],
		["graft_steel", "box", Vector3(x * 0.6, 0.06, 0.0), Vector3(0.05, 0.05, 0.15)],
		["visor", "box", Vector3(x * 1.32, length * 0.4, 0.0), Vector3(0.006, 0.05, 0.02)],
	])


# --- Bloom -----------------------------------------------------------------

## Teal crystals growing through a cracked visor.
static func _lattice() -> Mesh:
	var p := []
	var spikes := [[Vector3(-0.05, 0.12, 0.13), Vector3(0.4, 0.2, 0.3), 0.12],
		[Vector3(0.0, 0.16, 0.13), Vector3(0.2, -0.3, -0.2), 0.15], [Vector3(0.06, 0.1, 0.13), Vector3(-0.3, 0.4, -0.5), 0.1],
		[Vector3(-0.08, 0.19, 0.1), Vector3(0.6, 0.0, 0.6), 0.1], [Vector3(0.05, 0.22, 0.09), Vector3(-0.5, 0.2, 0.2), 0.11],
		[Vector3(0.0, 0.26, 0.0), Vector3(0.1, 0.0, 0.3), 0.12]]
	for s in spikes:
		p.append(["glow", "box", s[0], Vector3(0.026, s[2], 0.026), s[1]])
	p.append(["growth", "ball", Vector3(0.0, 0.12, 0.125), 0.045])
	return _mesh(p)


## A swollen fungal forearm with glowing veins.
static func _limb() -> Mesh:
	return _mesh([
		["flesh_raw", "ball", Vector3(0.0, 0.06, 0.0), 0.08],
		["flesh_raw", "ball", Vector3(0.01, 0.15, 0.01), 0.075],
		["flesh_raw", "ball", Vector3(-0.01, 0.23, 0.0), 0.06],
		["glow", "tube", Vector3(0.07, 0.03, 0.03), Vector3(0.055, 0.24, 0.04), 0.009],
		["glow", "tube", Vector3(-0.07, 0.05, -0.03), Vector3(-0.05, 0.23, -0.04), 0.008],
		["growth", "ball", Vector3(0.05, 0.12, 0.06), 0.03],
		["growth", "ball", Vector3(-0.04, 0.19, 0.06), 0.024],
	])


static func _limb_upper() -> Mesh:
	return _mesh([
		["flesh_raw", "ball", Vector3(0.0, 0.12, 0.0), 0.075],
		["glow", "tube", Vector3(0.06, 0.04, 0.03), Vector3(0.05, 0.22, 0.03), 0.008],
	])


## Long claws past the fingers.
static func _claw() -> Mesh:
	var p := []
	for i in 3:
		var z := -0.035 + i * 0.035
		p.append(["claw", "box", Vector3(-0.02, 0.2, z), Vector3(0.016, 0.24, 0.016), Vector3(0.0, 0.0, 0.3)])
	p.append(["glow", "ball", Vector3(-0.02, 0.09, 0.0), 0.02])
	return _mesh(p)


## A pulsing knot bursting through the plate carrier.
static func _knot() -> Mesh:
	return _mesh([
		["flesh_raw", "ball", Vector3(0.02, 0.03, 0.17), 0.1],
		["flesh_raw", "ball", Vector3(-0.08, 0.1, 0.15), 0.055],
		["flesh_raw", "ball", Vector3(0.09, -0.05, 0.15), 0.045],
		["growth", "ball", Vector3(0.03, 0.05, 0.26), 0.045],
		["glow", "tube", Vector3(0.02, 0.03, 0.24), Vector3(0.15, 0.17, 0.17), 0.01],
		["glow", "tube", Vector3(0.02, 0.03, 0.24), Vector3(-0.13, -0.1, 0.18), 0.01],
		["glow", "tube", Vector3(0.0, 0.05, 0.24), Vector3(-0.06, 0.22, 0.17), 0.009],
	])


## Bark plates and backward spines down a thigh or calf.
static func _bark(left: bool, length: float) -> Mesh:
	var x := 0.02 if left else -0.02
	var p := [
		["bark", "box", Vector3(x, length * 0.3, -0.07), Vector3(0.14, length * 0.4, 0.04), Vector3(0.15, 0, 0)],
		["bark", "box", Vector3(x, length * 0.72, -0.06), Vector3(0.12, length * 0.36, 0.04), Vector3(-0.1, 0, 0)],
		["glow", "ball", Vector3(x, length * 0.5, -0.095), 0.02],
	]
	for i in 3:
		p.append(["claw", "box", Vector3(x, 0.06 + i * length * 0.3, 0.09), Vector3(0.016, 0.11, 0.016), Vector3(-0.9, 0, 0)])
	return _mesh(p)
