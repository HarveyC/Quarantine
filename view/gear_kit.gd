extends RefCounted
## Equipment a soldier visibly wears: one prop per armour, gadget and loaded pocket, built from
## primitives and hung on the skeleton like GraftKit's parts, so ModelKit's materials, grime and
## hit flash apply. Everything is read from the unit's replicated state (status "gear" and
## "pockets"), so every peer dresses the same body.
##
## Armour is dark ceramic, canvas and player-tinted trim; gadgets sit on the back and hips, where
## the class silhouette stays clear; pockets show as pouches and grenades on the belt. Bloom
## armour (bio mesh, symbiotic suit, mycelial weave) grows teal veins; teal means Infection, so
## no Machine item uses it. Machine Refits keep their own pale steel (GraftKit) so gear never
## reads as a Graft.
##
## Bone frames (rest pose): spine_03 and pelvis +Y up, +Z out of the chest; Head +Y up, +Z out
## of the face; upperarm/lowerarm +Y runs to the elbow/wrist, -X is the back of the arm;
## thighs and calves +Y runs down the leg, -Z is the front of the leg.

const GunModels := preload("res://view/gun_models.gd")

const CERAMIC := Color("8d8f7e")
const PLATE := Color("3d4039")
const CANVAS := Color("6b6a52")
const EXO := Color("3b3f42")
const CHAR := Color("2a2623")
const EMBER := [Color("c8501e"), Color("ff7a2a")]
const MOSS := Color("4a5236")
const BARK := Color("3d3329")
const FLESH := Color("6a3c3a")
const WHITE := Color("d9d9d2")
const RED := Color("b3322a")
const HAZ := Color("c9871a")
const DARK := Color("1e1f1d")
const OLIVE := Color("4b5233")
const TAN := Color("a08c5a")
const COLORS := {
	"k_ceramic": CERAMIC, "k_plate": PLATE, "k_canvas": CANVAS, "k_exo": EXO, "k_char": CHAR,
	"k_ember": EMBER, "k_moss": MOSS, "bark": BARK, "flesh_raw": FLESH, "k_white": WHITE,
	"k_red": RED, "k_haz": HAZ, "k_dark": DARK, "k_olive": OLIVE, "k_tan": TAN,
}

## Armour id -> the part set that dresses it.
const ARMOR_LOOK := {
	"kevlar_vest": "vest", "ballistic_plate": "ballistic", "plated_rig": "rig", "riot_shield": "shield",
	"light_harness": "harness", "exo_frame": "exo", "bio_mesh": "bio", "symbiotic_suit": "symbiote",
	"mycelial_weave": "weave", "filter_mask": "filter", "hazard_liner": "hazard", "flame_coat": "coat",
	"ember_plating": "ember", "ghillie_cloak": "ghillie", "cauterizer": "cauterizer",
	"hold_position": "guard", "feral_grip": "feral", "overlook": "overlook",
	"targeting_optic": "overlook", "lattice_sight": "overlook", "plated_ribs": "ballistic", "heart_knot": "bio",
	"flash_fry": "ember", "bounty_ledger": "vest", "hair_trigger": "harness", "retaliation_plate": "ballistic",
}
## Pocket items that have their own shape (anything else gets a plain pouch).
const POCKET_LOOKS := ["medkit", "flashbang", "smoke_grenade", "recon_drone", "suppressant_shot", "antiviral_dose", "breather_mask", "stim", "frag_grenade", "demo_charge", "containment_foam"]
const GADGET_LOOK := {
	"thermite_charge": "thermite", "flare_launcher": "flare", "concussion_launcher": "concussion",
	"motion_tracker": "tracker", "sentry_turret": "sentry", "grapple": "grapple",
	"adrenal_pump": "pump", "med_injector": "injector", "containment_emitter": "emitter",
	"deployable_cover": "cover", "spotter_flare": "spotter", "bloodletting": "vials",
	"quarantine_field": "collar",
	"rig_suppress": "sentry", "rig_tag": "tracker", "rig_stim": "injector", "rig_breach": "thermite", "rig_incinerate": "emitter", "rig_siphon": "vials",
	"sig_lockdown": "sentry", "sig_deadeye": "tracker", "sig_quarantine_field": "emitter", "sig_bring_down": "thermite", "sig_flashover": "spotter", "sig_vent": "vials", "sig_death_sweep": "grapple", "sig_provoke": "pump",
}


## Hangs a prop for every worn armour, gadget and loaded pocket on `model`. Call before
## ModelKit.apply_materials. `gear` is unit.status["gear"], `pockets` unit.status["pockets"].
static func dress(model: Node3D, kind: String, gear: Dictionary, pockets: Array) -> void:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var sk := skels[0] as Skeleton3D
	for slot in ["body", "head", "offhand"]:
		var armor := str((gear.get(slot, {}) as Dictionary).get("id", ""))
		if ARMOR_LOOK.has(armor):
			for part in _armor(ARMOR_LOOK[armor], kind):
				_attach(sk, part[0], "gear_" + part[1], part[2])
	for slot in ["utility", "utility2"]:
		var gadget := str((gear.get(slot, {}) as Dictionary).get("id", ""))
		if GADGET_LOOK.has(gadget):
			for part in _gadget(GADGET_LOOK[gadget]):
				_attach(sk, part[0], "gear_" + part[1], part[2])
	for i in pockets.size():
		var p: Variant = pockets[i]
		if p is Dictionary and int(p.get("charges", 0)) > 0:
			for part in _pocket(str(p.get("id", "")), i):
				_attach(sk, part[0], "pocket_%d_%s" % [i, part[1]], part[2])


## Names of the gear props on a model (tests, renders).
static func props(model: Node) -> Array[String]:
	var out: Array[String] = []
	for n in model.find_children("gear_*", "MeshInstance3D", true, false):
		out.append(String(n.name))
	for n in model.find_children("pocket_*", "MeshInstance3D", true, false):
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


# --- Armour ------------------------------------------------------------------
## Each look returns [[bone, name, mesh], ...].

static func _armor(look: String, kind: String) -> Array:
	match look:
		"vest":   # a slim ceramic trauma plate, side cummerbund
			return [["spine_03", "vest", _mesh([
				["k_ceramic", "box", Vector3(0, 0.03, 0.185), Vector3(0.21, 0.24, 0.03)],
				["k_plate", "box", Vector3(0, 0.03, 0.2), Vector3(0.15, 0.17, 0.012)],
				["amber", "box", Vector3(0, 0.15, 0.205), Vector3(0.05, 0.012, 0.01)],
				["k_ceramic", "box", Vector3(0, 0.03, -0.18), Vector3(0.2, 0.22, 0.025)],
			])]]
		"ballistic":   # heavy plates, front and back, with collar and shoulder caps
			return [["spine_03", "plate", _mesh([
				["k_ceramic", "box", Vector3(0, 0.02, 0.19), Vector3(0.28, 0.3, 0.04)],
				["k_plate", "box", Vector3(0, 0.02, 0.215), Vector3(0.2, 0.22, 0.012)],
				["k_plate", "box", Vector3(-0.15, 0.0, 0.0), Vector3(0.035, 0.24, 0.26)],
				["k_plate", "box", Vector3(0.15, 0.0, 0.0), Vector3(0.035, 0.24, 0.26)],
				["k_ceramic", "box", Vector3(0, 0.03, -0.19), Vector3(0.27, 0.28, 0.04)],
				["k_plate", "box", Vector3(0, 0.2, 0.08), Vector3(0.26, 0.05, 0.1)],
				["amber", "box", Vector3(0.0, 0.14, 0.222), Vector3(0.12, 0.014, 0.008)],
			])], ["upperarm_l", "cap_l", _cap()], ["upperarm_r", "cap_r", _cap()]]
		"rig":   # plate rig: chest plate, both pauldrons, thigh guards
			return [["spine_03", "rig", _mesh([
				["k_ceramic", "box", Vector3(0, 0.03, 0.19), Vector3(0.3, 0.3, 0.04)],
				["k_plate", "box", Vector3(0, 0.03, 0.215), Vector3(0.22, 0.22, 0.012)],
				["k_plate", "box", Vector3(0, -0.15, 0.17), Vector3(0.28, 0.06, 0.05)],
				["armor_team", "box", Vector3(0, 0.17, 0.215), Vector3(0.1, 0.02, 0.01)],
			])], ["upperarm_l", "paul_l", _pauldron()], ["upperarm_r", "paul_r", _pauldron()],
				["thigh_l", "guard_l", _thigh_guard(true)], ["thigh_r", "guard_r", _thigh_guard(false)]]
		"shield":   # a riot shield on the off forearm
			if kind == "warden":
				return []   # the Warden already carries one
			return [["lowerarm_l", "shield", _mesh([
				["k_dark", "box", Vector3(0.08, 0.16, 0.0), Vector3(0.045, 0.62, 0.46)],
				["k_plate", "box", Vector3(0.106, 0.16, 0.0), Vector3(0.012, 0.54, 0.38)],
				["amber", "box", Vector3(0.112, 0.44, 0.0), Vector3(0.012, 0.04, 0.38)],
				["amber", "box", Vector3(0.112, -0.12, 0.0), Vector3(0.012, 0.04, 0.38)],
				["k_ceramic", "box", Vector3(0.112, 0.16, 0.0), Vector3(0.014, 0.03, 0.38)],
			])]]
		"harness":   # pale canvas cross straps with fat pouches
			var p := [
				["k_canvas", "box", Vector3(0.08, 0.03, 0.2), Vector3(0.07, 0.4, 0.03), Vector3(0, 0, 0.5)],
				["k_canvas", "box", Vector3(-0.08, 0.03, 0.2), Vector3(0.07, 0.4, 0.03), Vector3(0, 0, -0.5)],
				["k_tan", "box", Vector3(-0.12, -0.12, 0.22), Vector3(0.09, 0.1, 0.06)],
				["k_tan", "box", Vector3(0.12, -0.12, 0.22), Vector3(0.09, 0.1, 0.06)],
				["k_tan", "box", Vector3(0, -0.15, 0.22), Vector3(0.08, 0.09, 0.06)],
				["amber", "box", Vector3(0, 0.03, 0.225), Vector3(0.06, 0.06, 0.01)],
			]
			return [["spine_03", "harness", _mesh(p)]]
		"exo":   # a dark exo frame: back rails, hip joints, thigh struts
			return [["spine_03", "exo", _mesh([
				["k_exo", "tube", Vector3(-0.07, -0.22, -0.2), Vector3(-0.07, 0.24, -0.2), 0.022],
				["k_exo", "tube", Vector3(0.07, -0.22, -0.2), Vector3(0.07, 0.24, -0.2), 0.022],
				["k_exo", "box", Vector3(0, 0.2, -0.2), Vector3(0.24, 0.04, 0.05)],
				["k_exo", "box", Vector3(0, -0.02, -0.2), Vector3(0.2, 0.03, 0.045)],
				["visor", "box", Vector3(0, 0.1, -0.23), Vector3(0.08, 0.02, 0.01)],
				["k_exo", "tube", Vector3(-0.17, 0.19, 0.0), Vector3(-0.17, 0.19, -0.2), 0.02],
				["k_exo", "tube", Vector3(0.17, 0.19, 0.0), Vector3(0.17, 0.19, -0.2), 0.02],
			])], ["thigh_l", "strut_l", _exo_leg(true)], ["thigh_r", "strut_r", _exo_leg(false)]]
		"bio":   # a mesh of teal veins woven over the chest and shoulders
			return [["spine_03", "bio", _mesh([
				["glow", "tube", Vector3(-0.12, 0.2, 0.17), Vector3(0.0, 0.0, 0.205), 0.008],
				["glow", "tube", Vector3(0.12, 0.2, 0.17), Vector3(0.0, 0.0, 0.205), 0.008],
				["glow", "tube", Vector3(0.0, 0.0, 0.205), Vector3(-0.1, -0.2, 0.18), 0.008],
				["glow", "tube", Vector3(0.0, 0.0, 0.205), Vector3(0.1, -0.2, 0.18), 0.008],
				["glow", "tube", Vector3(-0.14, 0.04, 0.16), Vector3(0.14, 0.04, 0.16), 0.006],
				["flesh_raw", "ball", Vector3(0.0, 0.0, 0.2), 0.045],
				["flesh_raw", "ball", Vector3(-0.11, 0.17, 0.16), 0.032],
				["flesh_raw", "ball", Vector3(0.11, 0.17, 0.16), 0.032],
			])], ["upperarm_l", "web_l", _web()], ["upperarm_r", "web_r", _web()]]
		"symbiote":   # a second skin of nodules and ridges
			var p := [["flesh_raw", "box", Vector3(0, 0.03, 0.17), Vector3(0.27, 0.3, 0.04)]]
			for i in 5:
				p.append(["flesh_raw", "ball", Vector3(-0.1 + i * 0.05, 0.12 - (i % 2) * 0.12, 0.2), 0.03])
				p.append(["glow", "ball", Vector3(-0.1 + i * 0.05, 0.12 - (i % 2) * 0.12, 0.226), 0.012])
			p.append(["flesh_raw", "box", Vector3(0, 0.0, -0.17), Vector3(0.26, 0.3, 0.04)])
			return [["spine_03", "symbiote", _mesh(p)], ["upperarm_l", "sym_l", _nodes()], ["upperarm_r", "sym_r", _nodes()]]
		"weave":   # shelf fungus fanned over the shoulders and ribs
			var p := []
			for i in 4:
				var y := 0.2 - i * 0.1
				p.append(["bark", "box", Vector3(0.0, y, 0.2 - i * 0.012), Vector3(0.24 - i * 0.02, 0.05, 0.06), Vector3(0.45, 0, 0)])
				p.append(["glow", "box", Vector3(0.0, y - 0.03, 0.225 - i * 0.012), Vector3(0.18 - i * 0.02, 0.008, 0.02)])
			return [["spine_03", "weave", _mesh(p)], ["upperarm_l", "shelf_l", _shelf()], ["upperarm_r", "shelf_r", _shelf()]]
		"filter":   # twin filter canisters bulging off the mask, ringed in hazard orange
			return [["Head", "filter", _mesh([
				["k_dark", "tube", Vector3(-0.1, -0.03, 0.08), Vector3(-0.1, -0.03, 0.2), 0.055],
				["k_dark", "tube", Vector3(0.1, -0.03, 0.08), Vector3(0.1, -0.03, 0.2), 0.055],
				["k_haz", "tube", Vector3(-0.1, -0.03, 0.17), Vector3(-0.1, -0.03, 0.19), 0.06],
				["k_haz", "tube", Vector3(0.1, -0.03, 0.17), Vector3(0.1, -0.03, 0.19), 0.06],
				["metal", "tube", Vector3(-0.1, -0.03, 0.2), Vector3(-0.1, -0.03, 0.215), 0.04],
				["metal", "tube", Vector3(0.1, -0.03, 0.2), Vector3(0.1, -0.03, 0.215), 0.04],
				["k_dark", "box", Vector3(0.0, -0.05, 0.12), Vector3(0.14, 0.06, 0.06)],
			])]]
		"hazard":   # hazard orange collar, chest panel and shin bands
			return [["spine_03", "hazard", _mesh([
				["k_haz", "box", Vector3(0, 0.25, 0.02), Vector3(0.3, 0.05, 0.22)],
				["k_haz", "box", Vector3(0, 0.0, 0.19), Vector3(0.2, 0.1, 0.03)],
				["k_dark", "box", Vector3(-0.05, 0.0, 0.205), Vector3(0.025, 0.1, 0.012), Vector3(0, 0, 0.5)],
				["k_dark", "box", Vector3(0.03, 0.0, 0.205), Vector3(0.025, 0.1, 0.012), Vector3(0, 0, 0.5)],
			])], ["calf_l", "band_l", _band()], ["calf_r", "band_r", _band()]]
		"coat":   # a scorched coat skirt with embers in the seams
			return [["pelvis", "coat", _mesh([
				["k_char", "box", Vector3(0, -0.2, 0.15), Vector3(0.3, 0.38, 0.03), Vector3(0.12, 0, 0)],
				["k_char", "box", Vector3(0, -0.2, -0.15), Vector3(0.3, 0.38, 0.03), Vector3(-0.12, 0, 0)],
				["k_ember", "box", Vector3(0, -0.2, 0.175), Vector3(0.012, 0.3, 0.008)],
				["k_ember", "box", Vector3(0.07, -0.18, 0.172), Vector3(0.01, 0.2, 0.008)],
				["k_ember", "box", Vector3(0, -0.2, -0.175), Vector3(0.012, 0.3, 0.008)],
			])], ["spine_03", "scorch", _mesh([
				["k_char", "box", Vector3(0, 0.03, 0.185), Vector3(0.27, 0.28, 0.03)],
				["k_ember", "box", Vector3(0.0, 0.0, 0.2), Vector3(0.012, 0.22, 0.008)],
			])]]
		"ember":   # charred plates with a glow in the cracks
			return [["spine_03", "ember", _mesh([
				["k_char", "box", Vector3(0, 0.03, 0.19), Vector3(0.28, 0.28, 0.04)],
				["k_ember", "box", Vector3(-0.03, 0.05, 0.212), Vector3(0.012, 0.2, 0.006), Vector3(0, 0, 0.3)],
				["k_ember", "box", Vector3(0.05, 0.0, 0.212), Vector3(0.012, 0.15, 0.006), Vector3(0, 0, -0.4)],
			])], ["upperarm_l", "emb_l", _cap("k_char", true)], ["upperarm_r", "emb_r", _cap("k_char", true)]]
		"cauterizer":
			return _armor("ember", kind) + [["lowerarm_l", "nozzle", _mesh([
				["k_char", "tube", Vector3(0.0, 0.08, 0.0), Vector3(0.0, 0.3, 0.0), 0.04],
				["k_ember", "tube", Vector3(0.0, 0.3, 0.0), Vector3(0.0, 0.32, 0.0), 0.028],
			])]]
		"ghillie":   # a shaggy cloak of moss strips from hood to hem
			var p := []
			for i in 9:
				var x := -0.17 + i * 0.0425
				var len := 0.42 + (i % 3) * 0.1
				p.append(["k_moss", "box", Vector3(x, 0.05 - len * 0.5 + 0.2, -0.2), Vector3(0.04, len, 0.025), Vector3(0.1, 0, (i % 2) * 0.1 - 0.05)])
			p.append(["k_moss", "box", Vector3(0, 0.22, -0.02), Vector3(0.34, 0.07, 0.3)])
			return [["spine_03", "ghillie", _mesh(p)], ["upperarm_l", "drape_l", _drape(-1.0)], ["upperarm_r", "drape_r", _drape(1.0)], ["Head", "hood", _mesh([
				["k_moss", "box", Vector3(0, 0.2, -0.04), Vector3(0.24, 0.05, 0.22)],
				["k_moss", "box", Vector3(0, 0.06, -0.13), Vector3(0.22, 0.26, 0.04)],
			])]]
		"guard":   # broad shoulder guards striped amber (Guard)
			return [["upperarm_l", "guard_l", _guard()], ["upperarm_r", "guard_r", _guard()],
				["spine_03", "gorget", _mesh([["k_plate", "box", Vector3(0, 0.23, 0.1), Vector3(0.24, 0.06, 0.12)], ["amber", "box", Vector3(0, 0.26, 0.16), Vector3(0.1, 0.012, 0.01)]])]]
		"feral":   # barbed forearm spikes and a bark gauntlet (Close)
			return [["lowerarm_l", "barb_l", _barbs(-1.0)], ["lowerarm_r", "barb_r", _barbs(1.0)]]
		"overlook":   # a spotter's periscope over the right shoulder with an amber lamp
			return [["spine_03", "mast", _mesh([
				["k_dark", "tube", Vector3(0.2, 0.18, 0.0), Vector3(0.2, 0.5, 0.0), 0.026],
				["k_dark", "box", Vector3(0.2, 0.54, 0.05), Vector3(0.1, 0.08, 0.16)],
				["amber", "box", Vector3(0.2, 0.54, 0.135), Vector3(0.06, 0.04, 0.01)],
				["amber", "ball", Vector3(0.2, 0.6, -0.01), 0.02],
				["k_haz", "box", Vector3(0.2, 0.2, 0.0), Vector3(0.1, 0.03, 0.1)],
			])]]
	return []


static func _drape(lat: float) -> Mesh:
	var p := []
	for i in 5:
		p.append(["k_moss", "box", Vector3(lat * 0.07, 0.04 + i * 0.045, -0.1 + i * 0.05), Vector3(0.03, 0.2 - (i % 2) * 0.05, 0.04), Vector3(0, 0, lat * 0.2)])
	p.append(["k_moss", "ball", Vector3(lat * 0.04, 0.03, 0.0), 0.1])
	return _mesh(p)


static func _cap(role := "k_plate", ember := false) -> Mesh:
	var p := [[role, "box", Vector3(-0.0, 0.1, 0.0), Vector3(0.13, 0.12, 0.16), Vector3(0, 0, 0)],
		[role, "ball", Vector3(0.0, 0.06, 0.0), 0.095]]
	if ember:
		p.append(["k_ember", "box", Vector3(0.0, 0.1, 0.085), Vector3(0.012, 0.1, 0.006)])
	else:
		p.append(["armor_team", "box", Vector3(0, 0.15, 0.0), Vector3(0.11, 0.015, 0.17)])
	return _mesh(p)


static func _pauldron() -> Mesh:
	return _mesh([
		["k_ceramic", "ball", Vector3(0.0, 0.07, 0.0), 0.11],
		["k_plate", "box", Vector3(0.0, 0.14, 0.0), Vector3(0.18, 0.04, 0.2)],
		["armor_team", "box", Vector3(0.0, 0.165, 0.0), Vector3(0.12, 0.012, 0.15)],
	])


static func _thigh_guard(left: bool) -> Mesh:
	var x := 0.1 if left else -0.1
	return _mesh([
		["k_plate", "box", Vector3(x, 0.2, 0.0), Vector3(0.05, 0.22, 0.16)],
		["k_ceramic", "box", Vector3(x * 1.2, 0.2, 0.0), Vector3(0.02, 0.17, 0.12)],
	])


static func _exo_leg(left: bool) -> Mesh:
	var x := 0.13 if left else -0.13
	return _mesh([
		["k_exo", "tube", Vector3(x, 0.0, 0.0), Vector3(x, 0.44, 0.0), 0.02],
		["k_exo", "ball", Vector3(x, 0.0, 0.0), 0.04],
		["k_exo", "box", Vector3(x * 0.8, 0.22, 0.0), Vector3(0.04, 0.1, 0.1)],
		["visor", "box", Vector3(x * 1.1, 0.22, 0.0), Vector3(0.012, 0.05, 0.02)],
	])


static func _web() -> Mesh:
	return _mesh([
		["glow", "tube", Vector3(0.0, 0.0, 0.07), Vector3(0.0, 0.2, 0.07), 0.007],
		["glow", "tube", Vector3(0.05, 0.04, 0.0), Vector3(0.05, 0.19, 0.04), 0.006],
		["flesh_raw", "ball", Vector3(0.0, 0.08, 0.07), 0.03],
	])


static func _nodes() -> Mesh:
	return _mesh([
		["flesh_raw", "ball", Vector3(0.0, 0.1, 0.07), 0.05],
		["glow", "ball", Vector3(0.0, 0.1, 0.11), 0.014],
		["flesh_raw", "ball", Vector3(0.05, 0.03, 0.06), 0.032],
	])


static func _shelf() -> Mesh:
	return _mesh([
		["bark", "box", Vector3(0.0, 0.1, 0.0), Vector3(0.18, 0.04, 0.2), Vector3(0, 0, 0.2)],
		["glow", "box", Vector3(0.0, 0.075, 0.0), Vector3(0.14, 0.008, 0.15), Vector3(0, 0, 0.2)],
		["bark", "box", Vector3(0.0, 0.0, 0.0), Vector3(0.15, 0.04, 0.17), Vector3(0, 0, 0.2)],
	])


static func _band() -> Mesh:
	return _mesh([
		["k_haz", "box", Vector3(0.0, 0.22, 0.0), Vector3(0.15, 0.07, 0.15)],
		["k_dark", "box", Vector3(0.0, 0.22, 0.0), Vector3(0.155, 0.02, 0.155)],
	])


static func _guard() -> Mesh:
	return _mesh([
		["k_plate", "ball", Vector3(0.0, 0.07, 0.0), 0.13],
		["k_plate", "box", Vector3(0.0, 0.12, 0.0), Vector3(0.26, 0.06, 0.28)],
		["amber", "box", Vector3(0.0, 0.15, -0.06), Vector3(0.2, 0.012, 0.04), Vector3(0, 0.6, 0)],
		["amber", "box", Vector3(0.0, 0.15, 0.04), Vector3(0.2, 0.012, 0.04), Vector3(0, 0.6, 0)],
	])


static func _barbs(lat: float) -> Mesh:
	var p := [["bark", "box", Vector3(lat * 0.07, 0.17, 0.0), Vector3(0.05, 0.22, 0.14)]]
	for i in 3:
		p.append(["claw", "tube", Vector3(lat * 0.09, 0.08 + i * 0.07, 0.0), Vector3(lat * 0.2, 0.04 + i * 0.07, 0.0), 0.022, 0.004])
	return _mesh(p)


# --- Gadgets -----------------------------------------------------------------

static func _gadget(look: String) -> Array:
	match look:
		"thermite":   # a thermite brick with an igniter, hung off the left hip
			return [["pelvis", "thermite", _mesh([
				["k_red", "box", Vector3(-0.2, 0.02, -0.06), Vector3(0.1, 0.2, 0.2)],
				["k_dark", "box", Vector3(-0.2, 0.02, -0.06), Vector3(0.106, 0.03, 0.206)],
				["k_ember", "ball", Vector3(-0.2, 0.14, -0.06), 0.03],
				["k_dark", "tube", Vector3(-0.2, 0.12, -0.06), Vector3(-0.2, 0.15, -0.06), 0.018],
			])]]
		"flare":   # a flare launcher tube on the left shoulder
			return [["spine_03", "flare", _mesh([
				["k_dark", "tube", Vector3(-0.17, 0.12, -0.04), Vector3(-0.17, 0.46, 0.05), 0.04],
				["k_ember", "tube", Vector3(-0.17, 0.46, 0.05), Vector3(-0.172, 0.475, 0.054), 0.034],
				["k_haz", "box", Vector3(-0.17, 0.2, -0.015), Vector3(0.09, 0.03, 0.09)],
			])]]
		"concussion":   # a fat grenade launcher over the right shoulder
			return [["spine_03", "launcher", _mesh([
				["k_dark", "tube", Vector3(0.17, 0.12, -0.1), Vector3(0.17, 0.4, 0.1), 0.06],
				["metal", "tube", Vector3(0.17, 0.4, 0.1), Vector3(0.17, 0.43, 0.12), 0.065],
				["k_haz", "box", Vector3(0.17, 0.22, -0.01), Vector3(0.13, 0.03, 0.13)],
				["k_dark", "box", Vector3(0.17, 0.1, -0.16), Vector3(0.1, 0.12, 0.08)],
			])]]
		"tracker":   # a wrist tracker with an antenna
			return [["lowerarm_l", "tracker", _mesh([
				["k_dark", "box", Vector3(-0.06, 0.2, 0.0), Vector3(0.05, 0.12, 0.1)],
				["visor", "box", Vector3(-0.088, 0.2, 0.0), Vector3(0.006, 0.08, 0.07)],
				["k_dark", "tube", Vector3(-0.06, 0.26, 0.04), Vector3(-0.06, 0.4, 0.04), 0.006],
				["visor", "ball", Vector3(-0.06, 0.41, 0.04), 0.012],
			])]]
		"sentry":   # a folded sentry turret riding high on the pack
			return [["spine_03", "sentry", _mesh([
				["k_dark", "box", Vector3(0.0, 0.34, -0.3), Vector3(0.2, 0.16, 0.16)],
				["metal", "box", Vector3(0.0, 0.46, -0.3), Vector3(0.16, 0.1, 0.14)],
				["metal", "tube", Vector3(0.0, 0.46, -0.24), Vector3(0.0, 0.46, 0.0), 0.016],
				["k_dark", "tube", Vector3(-0.08, 0.28, -0.34), Vector3(-0.15, 0.0, -0.46), 0.014],
				["k_dark", "tube", Vector3(0.08, 0.28, -0.34), Vector3(0.15, 0.0, -0.46), 0.014],
				["visor", "ball", Vector3(0.0, 0.46, -0.235), 0.02],
				["k_haz", "box", Vector3(0.0, 0.34, -0.38), Vector3(0.2, 0.03, 0.012)],
			])]]
		"grapple":   # a grapple gun on the hip and a coil of line over the shoulder
			return [["pelvis", "grapple", _mesh([
				["metal", "box", Vector3(-0.2, 0.0, 0.0), Vector3(0.08, 0.12, 0.24)],
				["metal", "tube", Vector3(-0.2, 0.02, 0.12), Vector3(-0.2, 0.02, 0.3), 0.024],
				["k_dark", "box", Vector3(-0.2, -0.1, -0.06), Vector3(0.06, 0.12, 0.06)],
				["k_tan", "box", Vector3(-0.2, 0.08, 0.1), Vector3(0.04, 0.04, 0.1)],
			])], ["spine_03", "coil", _mesh([
				["k_tan", "box", Vector3(0.17, 0.2, 0.0), Vector3(0.12, 0.05, 0.32), Vector3(0, 0, 0.4)],
				["k_tan", "box", Vector3(0.15, 0.16, 0.0), Vector3(0.12, 0.05, 0.32), Vector3(0, 0, 0.4)],
				["k_tan", "box", Vector3(0.19, 0.24, 0.0), Vector3(0.12, 0.05, 0.32), Vector3(0, 0, 0.4)],
				["metal", "box", Vector3(0.2, 0.2, 0.0), Vector3(0.03, 0.14, 0.03)],
			])]]
		"pump":   # an adrenal pump on the forearm with a hose to the chest
			return [["lowerarm_l", "pump", _mesh([
				["k_dark", "tube", Vector3(-0.06, 0.06, 0.0), Vector3(-0.06, 0.26, 0.0), 0.05],
				["k_red", "tube", Vector3(-0.06, 0.1, 0.0), Vector3(-0.06, 0.22, 0.0), 0.054],
				["amber", "ball", Vector3(-0.06, 0.27, 0.0), 0.028],
			])]]
		"injector":   # a med injector case strapped to the thigh
			return [["thigh_r", "injector", _mesh([
				["k_white", "box", Vector3(-0.12, 0.17, 0.0), Vector3(0.05, 0.2, 0.1)],
				["k_red", "box", Vector3(-0.148, 0.17, 0.0), Vector3(0.008, 0.07, 0.02)],
				["k_red", "box", Vector3(-0.148, 0.17, 0.0), Vector3(0.008, 0.02, 0.07)],
				["k_dark", "tube", Vector3(-0.12, 0.06, 0.0), Vector3(-0.12, 0.28, 0.0), 0.005],
			])]]
		"emitter":   # a containment emitter dish standing off the pack
			return [["spine_03", "emitter", _mesh([
				["k_dark", "box", Vector3(0.0, 0.2, -0.3), Vector3(0.1, 0.34, 0.08)],
				["metal", "tube", Vector3(0.0, 0.34, -0.34), Vector3(0.0, 0.34, -0.42), 0.17],
				["visor", "tube", Vector3(0.0, 0.34, -0.42), Vector3(0.0, 0.34, -0.425), 0.09],
				["metal", "tube", Vector3(0.0, 0.34, -0.34), Vector3(0.0, 0.58, -0.3), 0.012],
				["visor", "ball", Vector3(0.0, 0.59, -0.3), 0.022],
			])]]
		"cover":   # a folded cover panel strapped over the pack
			return [["spine_03", "cover", _mesh([
				["k_plate", "box", Vector3(0.0, 0.2, -0.36), Vector3(0.34, 0.6, 0.05)],
				["k_haz", "box", Vector3(0.0, 0.46, -0.39), Vector3(0.34, 0.04, 0.014)],
				["k_haz", "box", Vector3(0.0, -0.02, -0.39), Vector3(0.34, 0.04, 0.014)],
				["k_dark", "box", Vector3(0.0, 0.22, -0.4), Vector3(0.07, 0.14, 0.02)],
			])]]
		"spotter":   # a marker flare and lamp on the shoulder
			return [["spine_03", "spotter", _mesh([
				["k_dark", "tube", Vector3(-0.17, 0.12, -0.04), Vector3(-0.17, 0.38, -0.04), 0.03],
				["k_ember", "ball", Vector3(-0.17, 0.39, -0.04), 0.03],
				["amber", "ball", Vector3(-0.17, 0.2, 0.0), 0.02],
				["k_haz", "box", Vector3(-0.17, 0.18, -0.04), Vector3(0.08, 0.025, 0.08)],
			])]]
		"vials":   # a bandolier of blood vials across the belt
			var p := [["k_dark", "box", Vector3(0.0, 0.02, 0.15), Vector3(0.32, 0.05, 0.03)]]
			for i in 5:
				p.append(["k_red", "tube", Vector3(-0.11 + i * 0.055, -0.02, 0.17), Vector3(-0.11 + i * 0.055, 0.1, 0.17), 0.016])
				p.append(["k_dark", "ball", Vector3(-0.11 + i * 0.055, 0.1, 0.17), 0.017])
			return [["pelvis", "vials", _mesh(p)]]
		"collar":   # an emitter ring at the throat with lamps
			return [["spine_03", "collar", _mesh([
				["metal", "box", Vector3(0.0, 0.26, 0.08), Vector3(0.3, 0.035, 0.07), Vector3(0.3, 0, 0)],
				["visor", "ball", Vector3(-0.12, 0.27, 0.1), 0.018],
				["visor", "ball", Vector3(0.12, 0.27, 0.1), 0.018],
				["visor", "ball", Vector3(0.0, 0.265, 0.12), 0.018],
				["k_dark", "box", Vector3(0.0, 0.28, -0.06), Vector3(0.3, 0.04, 0.08)],
			])]]
	return []


# --- Pockets -----------------------------------------------------------------
## Pocket 0 clips to the left shoulder strap, pocket 1 to the right, at the chest where the camera
## sees them. Items are drawn about 1.4x life size so they read at tactical zoom.

static func _pocket(id: String, slot: int) -> Array:
	var x := 0.15 if slot == 0 else -0.15
	var o := Vector3(x, 0.1, 0.225)
	var k := 1.4
	var p: Array
	match id:
		"medkit":
			p = [["k_white", "box", o, Vector3(0.1, 0.12, 0.05) * k], ["k_red", "box", o + Vector3(0, 0, 0.03 * k), Vector3(0.07, 0.022, 0.008) * k],
				["k_red", "box", o + Vector3(0, 0, 0.03 * k), Vector3(0.022, 0.07, 0.008) * k]]
		"flashbang":
			p = [["metal", "tube", o + Vector3(0, -0.055, 0) * k, o + Vector3(0, 0.055, 0) * k, 0.032 * k], ["k_dark", "tube", o + Vector3(0, 0.055, 0) * k, o + Vector3(0, 0.075, 0) * k, 0.034 * k]]
		"smoke_grenade":
			p = [["metal", "tube", o + Vector3(0, -0.055, 0) * k, o + Vector3(0, 0.055, 0) * k, 0.034 * k], ["k_haz", "tube", o + Vector3(0, -0.01, 0) * k, o + Vector3(0, 0.03, 0) * k, 0.036 * k]]
		"recon_drone":
			p = [["k_dark", "box", o, Vector3(0.1, 0.045, 0.1) * k], ["metal", "box", o, Vector3(0.2, 0.014, 0.014) * k],
				["metal", "box", o, Vector3(0.014, 0.014, 0.2) * k], ["visor", "ball", o + Vector3(0, -0.02, 0.055) * k, 0.016 * k]]
		"suppressant_shot", "antiviral_dose", "breather_mask", "stim":
			p = [["k_dark", "box", o, Vector3(0.05, 0.12, 0.05) * k], ["k_haz" if id == "stim" else "k_white", "tube", o + Vector3(0, 0.06, 0) * k, o + Vector3(0, 0.13, 0) * k, 0.012 * k],
				["amber", "ball", o + Vector3(0, -0.065, 0) * k, 0.016 * k]]
		"frag_grenade":
			p = [["k_olive", "ball", o, 0.045 * k], ["metal", "box", o + Vector3(0, 0.05, 0) * k, Vector3(0.03, 0.025, 0.03) * k], ["metal", "tube", o + Vector3(0, 0.065, 0) * k, o + Vector3(0.025, 0.075, 0) * k, 0.006 * k]]
		"demo_charge":
			p = [["k_tan", "box", o, Vector3(0.13, 0.09, 0.06) * k], ["k_red", "box", o + Vector3(0, 0, 0.032 * k), Vector3(0.1, 0.02, 0.008) * k],
				["k_dark", "box", o + Vector3(0.05 * k, 0.06 * k, 0), Vector3(0.03, 0.03, 0.03) * k]]
		"containment_foam":
			p = [["metal", "tube", o + Vector3(0, -0.065, 0) * k, o + Vector3(0, 0.065, 0) * k, 0.04 * k], ["visor", "tube", o + Vector3(0, 0.0, 0) * k, o + Vector3(0, 0.04, 0) * k, 0.042 * k],
				["k_dark", "tube", o + Vector3(0, 0.065, 0) * k, o + Vector3(0, 0.095, 0) * k, 0.02 * k]]
		_:
			p = [["k_dark", "box", o, Vector3(0.07, 0.1, 0.07) * k]]
	return [["spine_03", "item", _mesh(p)]]
