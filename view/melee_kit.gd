extends RefCounted
## Melee classes (Reaper, Warden) wear another class's character and carry props built
## from primitives at runtime: the Reaper a bonesaw machete in the weapon hand, the Bloom
## breaking out along that arm, and rags; the Warden a riot shield on the off forearm, a
## shock maul and amber hazard striping. Both carry a sidearm: holstered on the hip, it is
## swapped into the weapon hand (and the melee weapon put away) while aiming.
##
## Prop meshes go on BoneAttachment3D nodes under the skeleton, so ModelKit's role
## materials, grime and hit flash apply to them like to the baked gear. Their roles reuse
## the body's own materials where it has them ("metal", "plate", "amber", ...).
## Bone frames (rest pose): hand_r/hand_l +Y runs along the fingers, +Z out of the thumb
## side; the forearms +Y runs to the wrist, -X (left) is the back of the arm.

const GunModels := preload("res://view/gun_models.gd")

## kind -> the class whose character it borrows.
const BODY := {"reaper": "marksman", "warden": "trooper"}
## Body size (the Warden reads heavier).
const SIZE := {"reaper": 0.98, "warden": 1.06}
## Where the drawn sidearm's muzzle is, in the weapon hand's (hand_r) space.
const MUZZLE := {"reaper": Vector3(-0.035, 0.225, 0.095), "warden": Vector3(-0.035, 0.335, 0.1)}

const SHOCK := Color(0.45, 0.75, 1.0)
const G := Vector3(-0.035, 0.085, 0.0)   # centre of the right fist, in hand_r space


static func is_melee(kind: String) -> bool:
	return BODY.has(kind)


static func body_of(kind: String) -> String:
	return BODY.get(kind, "trooper")


static func size_of(kind: String) -> float:
	return SIZE.get(kind, 1.0)


## Puts `kind`'s props on `model` (the borrowed character) and hides its baked gun.
static func dress(model: Node3D, kind: String) -> void:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var sk := skels[0] as Skeleton3D
	model.set_meta("melee", kind)
	var gun := model.find_child("gun", true, false)
	if gun != null:
		for c in gun.get_children():
			if c is Node3D:
				(c as Node3D).visible = false
	_attach(sk, "hand_r", "melee_weapon", _blade() if kind == "reaper" else _maul())
	_attach(sk, "hand_r", "sidearm_drawn", _sidearm(kind)).visible = false
	_attach(sk, "thigh_r", "sidearm_holster", _holster(kind))
	if kind == "reaper":
		_attach(sk, "lowerarm_r", "bloom_arm", _bloom_arm())
		_attach(sk, "spine_02", "rags", _rags())
	else:
		var sh := _attach(sk, "lowerarm_l", "shield", _shield())
		# shield width along the forearm, height across it, its face out of the back of the arm
		sh.transform = Transform3D(Basis(Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)), Vector3(-0.085, 0.12, -0.12))
		_attach(sk, "upperarm_l", "pauldron_l", _pauldron(-1.0))
		_attach(sk, "upperarm_r", "pauldron_r", _pauldron(1.0))


## Class palette over the player tint (`mats`: role -> ShaderMaterial from ModelKit):
## the Reaper dark and ragged, the Warden in heavier, darker steel.
static func tint(kind: String, mats: Dictionary) -> void:
	var dark: Dictionary = {"reaper": {"cloth_team": 0.62, "cloak_team": 0.6, "armor_team": 0.55, "rags": 0.2},
		"warden": {"armor_team": 0.25, "plate": 0.1}}.get(kind, {})
	for role in dark:
		if mats.has(role):
			var m: ShaderMaterial = mats[role]
			var c: Color = m.get_shader_parameter("albedo")
			if kind == "warden" and role == "armor_team":
				c = c.lerp(Color("3c3e3a"), 0.5)
			m.set_shader_parameter("albedo", c.darkened(dark[role]))
	if kind == "reaper" and mats.has("cloth_team"):
		mats.cloth_team.set_shader_parameter("camo", 0.15)


## Shows the drawn sidearm (and hides the holstered one and the melee weapon), or puts it away.
static func set_drawn(model: Node, on: bool) -> void:
	for nm in ["melee_weapon", "sidearm_drawn", "sidearm_holster"]:
		var n := model.find_child(nm, true, false) as Node3D
		if n != null:
			n.visible = on == (nm == "sidearm_drawn")


static func _attach(sk: Skeleton3D, bone: String, nm: String, mesh: Mesh) -> MeshInstance3D:
	var att := BoneAttachment3D.new()
	att.name = nm + "_att"
	sk.add_child(att)
	att.bone_name = bone
	var b := sk.find_bone(bone)
	if b >= 0:
		att.transform = sk.get_bone_global_rest(b)   # until the skeleton first updates it
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	att.add_child(mi)
	return mi


# --- props -------------------------------------------------------------------

## Reaper: a long machete with a bonesaw spine and a cleaver tip, Bloom growing up the hilt.
static func _blade() -> Mesh:
	var p := [
		["leather", "tube", G + Vector3(0, 0, -0.06), G + Vector3(0, 0, 0.07), 0.017],
		["metal", "box", G + Vector3(0, 0, 0.075), Vector3(0.03, 0.07, 0.012)],
		["metal", "box", G + Vector3(0, 0.012, 0.34), Vector3(0.007, 0.066, 0.52)],
		["metal", "box", G + Vector3(0, 0.022, 0.585), Vector3(0.007, 0.086, 0.08)],
		["glow", "box", G + Vector3(0.0045, 0.0, 0.33), Vector3(0.002, 0.007, 0.4)],
		["glow", "box", G + Vector3(-0.0045, 0.004, 0.27), Vector3(0.002, 0.006, 0.28)],
		["flesh_raw", "ball", G + Vector3(0, -0.012, 0.1), 0.028],
		["glow", "ball", G + Vector3(0.012, -0.02, 0.12), 0.012],
	]
	for i in 7:   # the saw teeth along the spine
		p.append(["metal", "box", G + Vector3(0, -0.024, 0.15 + i * 0.055), Vector3(0.006, 0.016, 0.016), Vector3(PI * 0.25, 0, 0)])
	return GunModels.build_mesh(p, {}, {"flesh_raw": Color("5a3a36"), "leather": Color("2a2420")})


## Reaper: Bloom tissue and glowing veins breaking out of the weapon forearm.
static func _bloom_arm() -> Mesh:
	return GunModels.build_mesh([
		["flesh_raw", "ball", Vector3(0.0, 0.07, 0.05), 0.04],
		["flesh_raw", "ball", Vector3(0.03, 0.15, 0.045), 0.03],
		["flesh_raw", "ball", Vector3(-0.02, 0.2, 0.05), 0.022],
		["glow", "ball", Vector3(0.012, 0.08, 0.075), 0.016],
		["glow", "ball", Vector3(0.035, 0.16, 0.066), 0.012],
		["glow", "tube", Vector3(0.0, 0.02, 0.05), Vector3(0.02, 0.24, 0.045), 0.007],
		["glow", "tube", Vector3(0.04, 0.03, 0.02), Vector3(0.03, 0.2, 0.045), 0.005],
	], {}, {"flesh_raw": Color("5a3a36")})


## Reaper: tattered strips hanging down the back.
static func _rags() -> Mesh:
	var p := []
	for i in 5:
		var x := -0.12 + i * 0.06
		var h := 0.32 + 0.09 * float((i * 7) % 3)
		p.append(["rags", "box", Vector3(x, -0.1 - h * 0.5, -0.15), Vector3(0.055, h, 0.008), Vector3(0.12, 0, (i - 2) * 0.08)])
	return GunModels.build_mesh(p, {}, {"rags": Color("2b2a24")})


## Warden: a short stun maul, shock coils glowing round the head.
static func _maul() -> Mesh:
	return GunModels.build_mesh([
		["leather", "tube", G + Vector3(0, 0, -0.07), G + Vector3(0, 0, 0.08), 0.02],
		["metal", "tube", G + Vector3(0, 0, 0.08), G + Vector3(0, 0, 0.38), 0.021],
		["amber", "tube", G + Vector3(0, 0, 0.12), G + Vector3(0, 0, 0.16), 0.024],
		["metal", "box", G + Vector3(0, 0, 0.45), Vector3(0.078, 0.078, 0.14)],
		["lamp", "tube", G + Vector3(0, 0, 0.395), G + Vector3(0, 0, 0.41), 0.05],
		["lamp", "tube", G + Vector3(0, 0, 0.49), G + Vector3(0, 0, 0.505), 0.05],
		["lamp", "ball", G + Vector3(0, 0, 0.53), 0.024],
	], {}, {"lamp": [SHOCK.darkened(0.3), SHOCK], "leather": Color("2a2420")})


## Warden: a tall riot shield, a viewport slit near the top and hazard stripes along the
## bottom. Own frame: X width, Y height, +Z the face.
static func _shield() -> Mesh:
	var w := 0.56
	var h := 0.98
	var t := 0.026
	var r := 0.07
	var f := t * 0.5
	var p := [
		["plate", "box", Vector3.ZERO, Vector3(w, h - 2.0 * r, t)],
		["plate", "box", Vector3.ZERO, Vector3(w - 2.0 * r, h, t)],
		["metal", "box", Vector3(0, h * 0.3, f + 0.002), Vector3(w * 0.68, 0.085, 0.004)],
		["visor", "box", Vector3(0, h * 0.3, f + 0.005), Vector3(w * 0.6, 0.045, 0.004)],
		["slab", "box", Vector3(0, -h * 0.5 + 0.1, f + 0.002), Vector3(w - 0.05, 0.11, 0.004)],
		["amber", "box", Vector3(0, h * 0.5 - 0.045, f + 0.002), Vector3(w - 2.0 * r, 0.022, 0.004)],
		["strap", "box", Vector3(0, 0, -f - 0.014), Vector3(0.06, 0.32, 0.028)],
	]
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var c := Vector3(sx * (w * 0.5 - r), sy * (h * 0.5 - r), 0)
			p.append(["plate", "tube", c - Vector3(0, 0, f), c + Vector3(0, 0, f), r])
	for i in 6:
		p.append(["amber", "box", Vector3(-0.19 + i * 0.076, -h * 0.5 + 0.1, f + 0.005), Vector3(0.03, 0.105, 0.004), Vector3(0, 0, 0.6)])
	return GunModels.build_mesh(p, {}, {"plate": Color("4a4c46"), "slab": Color("1c1d1b")})


## Warden: a heavy shoulder plate with an amber stripe (`side` -1 left, 1 right).
static func _pauldron(side: float) -> Mesh:
	var top := -side   # the top of the upper arm is -X on the left, +X on the right
	return GunModels.build_mesh([
		["armor_team", "box", Vector3(top * 0.075, 0.05, 0), Vector3(0.05, 0.17, 0.17)],
		["amber", "box", Vector3(top * 0.102, 0.05, 0), Vector3(0.006, 0.035, 0.172)],
	], {}, {"armor_team": Color("3a3c36")})


## The drawn sidearm: the Reaper's pistol or the Warden's heavy revolver, barrel along
## the fingers.
static func _sidearm(kind: String) -> Mesh:
	if kind == "warden":
		return GunModels.build_mesh([
			["leather", "box", G + Vector3(0, -0.01, 0.02), Vector3(0.028, 0.036, 0.11)],
			["metal", "box", G + Vector3(0, 0.035, 0.085), Vector3(0.03, 0.08, 0.05)],
			["metal", "tube", G + Vector3(0, 0.035, 0.09), G + Vector3(0, 0.085, 0.09), 0.025],
			["metal", "tube", G + Vector3(0, 0.08, 0.1), G + Vector3(0, 0.25, 0.1), 0.012],
			["amber", "box", G + Vector3(0, 0.24, 0.115), Vector3(0.006, 0.01, 0.01)],
		], {}, {"leather": Color("3a2a1e")})
	return GunModels.build_mesh([
		["strap", "box", G + Vector3(0, -0.005, 0.02), Vector3(0.028, 0.034, 0.11)],
		["metal", "box", G + Vector3(0, 0.06, 0.095), Vector3(0.03, 0.17, 0.034)],
		["metal", "box", G + Vector3(0, 0.03, 0.055), Vector3(0.008, 0.03, 0.008)],
	])


## The sidearm in its hip holster (thigh_r space: +Y down the thigh, -X the outside).
static func _holster(kind: String) -> Mesh:
	return GunModels.build_mesh([
		["leather", "box", Vector3(-0.1, 0.16, 0.0), Vector3(0.045, 0.17, 0.08)],
		["leather" if kind == "warden" else "strap", "box", Vector3(-0.1, 0.05, 0.02), Vector3(0.03, 0.07, 0.035)],
		["metal", "box", Vector3(-0.1, 0.03, 0.035), Vector3(0.032, 0.025, 0.04)],
	], {}, {"leather": Color("2e261e")})
