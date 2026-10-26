extends RefCounted
## Mutations a soldier carries as visible Bloom growths: one cluster of teal-veined tissue per
## grafted mutation, hung on the skeleton. Each mutation has its own shape (a throat sac for Acid
## Spit, a second heart for Second Heart, scythes for Rampage), and the slot sets the scale:
## Exposed growths are small, Mutating ones swell, Critical ones dominate the silhouette. A
## mutation only works while Infection is at its tier, so a dormant one is drawn as dull, unlit
## tissue (UnitView swaps a dead material in); it glows again when Infection climbs back.
##
## Read from the unit's replicated state (status "mutations"), so every peer draws the same body.
## Bone frames as in GraftKit: spine_03 and Head +Y up, +Z out of the chest and face; upper/lower
## arms +Y runs to the elbow/wrist and -X is the back of the arm; thighs and calves +Y runs down.

const GunModels := preload("res://view/gun_models.gd")

const FLESH := Color("6a3c3a")
const BARK := Color("3d3329")
const CLAW := Color("2b2622")
const BONE := Color("c9bda1")
const CHITIN := Color("4a3a2a")
const BLOOD := Color("5a1f1c")
const COLORS := {"flesh_raw": FLESH, "bark": BARK, "claw": CLAW, "m_bone": BONE, "m_chitin": CHITIN, "m_blood": BLOOD}


## Hangs growths for every mutation in `mutations` ({slot: id}). Call before ModelKit.apply_materials.
static func dress(model: Node3D, mutations: Dictionary) -> void:
	if mutations.is_empty():
		return
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var sk := skels[0] as Skeleton3D
	for slot in mutations:
		var id := str(mutations[slot])
		for part in _parts(id):
			_attach(sk, part[0], "mut_%s_%s" % [id, part[1]], _mesh(part[2]))


## Every mutation growth on `model` as {mutation id: [MeshInstance3D]}.
static func nodes(model: Node) -> Dictionary:
	var out := {}
	for n in model.find_children("mut_*", "MeshInstance3D", true, false):
		var nm := String(n.name)
		var id := ""
		for known in MutationData.MUTATIONS:
			if nm.begins_with("mut_%s_" % known) and known.length() > id.length():
				id = known
		if id != "":
			if not out.has(id):
				out[id] = []
			out[id].append(n)
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


## Parts of one mutation as [[bone, name, parts], ...]. Frames: spine_03 and Head have +X to the
## soldier's left, +Y up, +Z forward; arms run +Y down the limb, +Z forward, and the outer side is
## -X on the left arm and +X on the right (`lat`); legs run +Y down with -Z forward.
static func _parts(id: String) -> Array:
	match id:
		# --- Exposed: small ---------------------------------------------------
		"spore_sense":   # eye stalks sprouting from the helmet, tipped with glowing spores
			return [["Head", "stalks", [
				["flesh_raw", "tube", Vector3(-0.09, 0.14, 0.0), Vector3(-0.15, 0.34, 0.02), 0.014, 0.006],
				["flesh_raw", "tube", Vector3(0.09, 0.14, 0.0), Vector3(0.15, 0.34, 0.02), 0.014, 0.006],
				["glow", "ball", Vector3(-0.15, 0.35, 0.02), 0.03],
				["glow", "ball", Vector3(0.15, 0.35, 0.02), 0.03]]]]
		"adrenal_surge":   # pulsing glands either side of the neck, veins running down the chest
			var p := []
			for sx in [-1.0, 1.0]:
				p.append(["flesh_raw", "ball", Vector3(sx * 0.1, 0.27, 0.03), 0.05])
				p.append(["glow", "ball", Vector3(sx * 0.1, 0.28, 0.08), 0.02])
				p.append(["glow", "tube", Vector3(sx * 0.1, 0.25, 0.09), Vector3(sx * 0.15, 0.08, 0.215), 0.007])
				p.append(["glow", "tube", Vector3(sx * 0.15, 0.08, 0.215), Vector3(sx * 0.12, -0.1, 0.215), 0.006])
			return [["spine_03", "gland", p]]
		"barbed_hide":   # bark barbs fanned over both shoulders
			var p := []
			for sx in [-1.0, 1.0]:
				for i in 3:
					p.append(["claw", "tube", Vector3(sx * 0.2, 0.2, -0.04 + i * 0.07), Vector3(sx * (0.27 + i * 0.01), 0.36 - abs(i - 1) * 0.04, -0.06 + i * 0.07), 0.026, 0.004])
			return [["spine_03", "barbs", p]]
		"bone_magazine":   # a column of bone rounds growing down the plate carrier, tips glowing
			var p := []
			for i in 4:
				var y := 0.14 - i * 0.075
				p.append(["m_bone", "tube", Vector3(-0.2, y, 0.17), Vector3(-0.2, y + 0.055, 0.21), 0.024, 0.014])
				p.append(["glow", "ball", Vector3(-0.2, y + 0.06, 0.215), 0.012])
			return [["spine_03", "rounds", p]]
		"hollow_bones":   # pale bone spurs out of the elbows and knees
			var out := []
			for lat in [-1.0, 1.0]:
				var nm := "l" if lat < 0.0 else "r"
				out.append(["lowerarm_" + nm, "spur_" + nm, [["m_bone", "tube", Vector3(lat * 0.04, 0.0, 0.0), Vector3(lat * 0.24, -0.04, -0.03), 0.035, 0.006], ["m_bone", "ball", Vector3(lat * 0.04, 0.0, 0.0), 0.045]]])
				out.append(["calf_" + nm, "knee_" + nm, [["m_bone", "tube", Vector3(0.0, 0.0, -0.06), Vector3(-lat * 0.03, 0.02, -0.28), 0.035, 0.006], ["m_bone", "ball", Vector3(0.0, 0.0, -0.06), 0.045]]])
			return out
		"lure_scent":   # a frill of pollen fronds round the helmet crown
			var p := []
			for i in 8:
				var a := i * TAU / 8.0
				var base := Vector3(cos(a) * 0.1, 0.19, sin(a) * 0.1)
				var tip := Vector3(cos(a) * 0.17, 0.33, sin(a) * 0.17)
				p.append(["flesh_raw", "tube", base, tip, 0.018, 0.006])
				p.append(["glow", "ball", tip, 0.018])
			return [["Head", "frill", p]]
		"clotting_blood":   # dark scab clumps along the plate carrier edges, wet with spores
			return [["spine_03", "scabs", [
				["m_blood", "ball", Vector3(-0.17, -0.02, 0.2), 0.055], ["m_blood", "ball", Vector3(-0.2, -0.12, 0.17), 0.04],
				["m_blood", "ball", Vector3(0.17, 0.08, 0.2), 0.05], ["m_blood", "ball", Vector3(0.2, -0.02, 0.17), 0.04],
				["glow", "ball", Vector3(-0.17, -0.02, 0.25), 0.017], ["glow", "ball", Vector3(0.17, 0.08, 0.245), 0.016]]]]
		# --- Mutating: swelling ------------------------------------------------
		"chitin_plates":   # glossy shell plates over the shoulders and forearms, glowing at the seams
			var out := []
			for lat in [-1.0, 1.0]:
				var nm := "l" if lat < 0.0 else "r"
				out.append(["upperarm_" + nm, "shell_" + nm, [["m_chitin", "ball", Vector3(lat * 0.05, 0.04, 0.0), 0.125],
					["m_chitin", "box", Vector3(lat * 0.13, 0.12, 0.0), Vector3(0.06, 0.26, 0.22)],
					["glow", "box", Vector3(lat * 0.162, 0.12, 0.0), Vector3(0.008, 0.2, 0.014)],
					["glow", "box", Vector3(lat * 0.162, 0.12, 0.07), Vector3(0.008, 0.2, 0.014)]]])
				out.append(["lowerarm_" + nm, "bracer_" + nm, [["m_chitin", "box", Vector3(lat * 0.08, 0.15, 0.0), Vector3(0.05, 0.26, 0.15)],
					["glow", "box", Vector3(lat * 0.107, 0.15, 0.0), Vector3(0.008, 0.2, 0.014)]]])
			return out
		"leech_bite":   # a toothed sucker mouth swelling out of the off upper arm
			var p := [["flesh_raw", "ball", Vector3(-0.07, 0.1, 0.0), 0.11], ["m_blood", "tube", Vector3(-0.15, 0.1, 0.0), Vector3(-0.17, 0.1, 0.0), 0.075]]
			for i in 8:
				var a := i * TAU / 8.0
				p.append(["m_bone", "tube", Vector3(-0.16, 0.1 + cos(a) * 0.065, sin(a) * 0.065), Vector3(-0.21, 0.1 + cos(a) * 0.04, sin(a) * 0.04), 0.014, 0.002])
			p.append(["glow", "ball", Vector3(-0.15, 0.1, 0.0), 0.025])
			return [["upperarm_l", "mouth", p]]
		"acid_spit":   # a swollen acid sac under the chin, glowing at the lip
			return [["Head", "sac", [
				["flesh_raw", "ball", Vector3(0.0, -0.17, 0.06), 0.1],
				["glow", "ball", Vector3(0.0, -0.17, 0.15), 0.04],
				["glow", "tube", Vector3(-0.07, -0.09, 0.1), Vector3(-0.1, -0.2, 0.12), 0.008],
				["glow", "tube", Vector3(0.07, -0.09, 0.1), Vector3(0.1, -0.2, 0.12), 0.008],
				["m_blood", "ball", Vector3(0.0, -0.25, 0.1), 0.03]]]]
		"second_heart":   # a second heart bulging out of the ribs, veined to the first
			return [["spine_03", "heart", [
				["m_blood", "ball", Vector3(-0.1, -0.02, 0.2), 0.07],
				["flesh_raw", "ball", Vector3(-0.1, 0.05, 0.22), 0.04],
				["glow", "ball", Vector3(-0.1, -0.02, 0.265), 0.022],
				["glow", "tube", Vector3(-0.1, 0.06, 0.22), Vector3(0.0, 0.18, 0.16), 0.01],
				["glow", "tube", Vector3(-0.07, -0.06, 0.22), Vector3(0.0, -0.18, 0.16), 0.008]]]]
		"rally_musk":   # musk pods hung from the belt
			return [["pelvis", "pods", [
				["flesh_raw", "ball", Vector3(0.0, 0.03, 0.19), 0.045], ["glow", "ball", Vector3(0.0, 0.03, 0.23), 0.015],
				["flesh_raw", "ball", Vector3(-0.08, 0.02, 0.17), 0.035], ["flesh_raw", "ball", Vector3(0.08, 0.02, 0.17), 0.035],
				["glow", "ball", Vector3(-0.08, 0.02, 0.2), 0.012], ["glow", "ball", Vector3(0.08, 0.02, 0.2), 0.012]]]]
		"kindled_spores":   # smouldering spore pods crowding the shoulder, glowing like embers
			return [["upperarm_r", "embers", [
				["flesh_raw", "ball", Vector3(0.1, 0.08, 0.02), 0.08], ["flesh_raw", "ball", Vector3(0.13, 0.17, -0.03), 0.055],
				["flesh_raw", "ball", Vector3(0.08, 0.2, 0.05), 0.045],
				["glow", "ball", Vector3(0.15, 0.08, 0.06), 0.025], ["glow", "ball", Vector3(0.16, 0.18, 0.0), 0.02],
				["glow", "ball", Vector3(0.1, 0.22, 0.09), 0.016]]]]
		"hive_hush":   # fungal gills fanned over both ears, muffling the helmet
			var p := []
			for sx in [-1.0, 1.0]:
				for i in 4:
					p.append(["flesh_raw", "box", Vector3(sx * 0.125, 0.03 + i * 0.035, 0.0), Vector3(0.03, 0.014, 0.17 - i * 0.025)])
				p.append(["glow", "box", Vector3(sx * 0.143, 0.09, 0.0), Vector3(0.006, 0.12, 0.012)])
			return [["Head", "gills", p]]
		"shared_blood":   # a vein cord from the heart down to a dark vial at the hip
			return [["spine_03", "cord", [
				["glow", "tube", Vector3(0.12, 0.1, 0.2), Vector3(0.17, -0.2, 0.18), 0.01],
				["m_blood", "ball", Vector3(0.17, -0.22, 0.17), 0.045], ["glow", "ball", Vector3(0.17, -0.22, 0.21), 0.016]]]]
		"twin_sight":   # a second eye opened in the helmet's brow
			return [["Head", "eye", [
				["flesh_raw", "ball", Vector3(0.0, 0.19, 0.1), 0.05],
				["glow", "ball", Vector3(0.0, 0.19, 0.145), 0.025],
				["claw", "box", Vector3(0.0, 0.19, 0.16), Vector3(0.008, 0.035, 0.006)]]]]
		"mirror_graft":   # the off arm swollen into a copy of the weapon arm
			return [["lowerarm_l", "mirror", [
				["flesh_raw", "ball", Vector3(-0.03, 0.08, 0.0), 0.09], ["flesh_raw", "ball", Vector3(-0.03, 0.18, 0.01), 0.075],
				["glow", "tube", Vector3(-0.1, 0.04, 0.03), Vector3(-0.09, 0.24, 0.04), 0.009],
				["glow", "ball", Vector3(-0.09, 0.14, 0.05), 0.024]]]]
		# --- Critical: dominant -----------------------------------------------
		"rampage":   # bone scythes past both wrists, barbs down the upper arms
			var out := []
			for lat in [-1.0, 1.0]:
				var nm := "l" if lat < 0.0 else "r"
				out.append(["lowerarm_" + nm, "scythe_" + nm, _scythe(lat)])
				out.append(["upperarm_" + nm, "spikes_" + nm, _spikes(lat)])
			return out
		"regenerator":   # new tissue spreading from a swollen belly node, a second node on the nape
			var p := [["flesh_raw", "ball", Vector3(0.0, -0.2, 0.2), 0.085], ["glow", "ball", Vector3(0.0, -0.2, 0.275), 0.03]]
			for i in 6:
				var a := -0.9 + i * 0.36
				p.append(["flesh_raw", "ball", Vector3(sin(a) * 0.2, -0.2 + cos(a) * 0.2 - 0.1, 0.19), 0.035])
				p.append(["glow", "tube", Vector3(0.0, -0.2, 0.24), Vector3(sin(a) * 0.2, -0.2 + cos(a) * 0.2 - 0.1, 0.225), 0.006])
			p.append(["flesh_raw", "ball", Vector3(0.0, 0.3, -0.34), 0.12])
			p.append(["glow", "ball", Vector3(0.0, 0.3, -0.45), 0.03])
			return [["spine_03", "cords", p]]
		"hollow_voice":   # a bell throat sac and a bone horn at the jaw
			return [["Head", "horn", [
				["flesh_raw", "ball", Vector3(0.0, -0.1, 0.06), 0.085],
				["glow", "ball", Vector3(0.0, -0.1, 0.12), 0.022],
				["m_bone", "tube", Vector3(0.0, -0.02, 0.1), Vector3(0.0, 0.0, 0.3), 0.03, 0.055],
				["glow", "tube", Vector3(0.0, 0.0, 0.3), Vector3(0.0, 0.0, 0.305), 0.045]]]]
		"bloom":   # spore bulbs swelling over both shoulders and the pack
			var p := []
			for sx in [-1.0, 1.0]:
				p.append(["flesh_raw", "ball", Vector3(sx * 0.2, 0.28, 0.0), 0.085])
				p.append(["flesh_raw", "ball", Vector3(sx * 0.27, 0.22, 0.05), 0.055])
				p.append(["flesh_raw", "ball", Vector3(sx * 0.22, 0.2, -0.07), 0.05])
				p.append(["glow", "ball", Vector3(sx * 0.2, 0.35, 0.02), 0.04])
				p.append(["glow", "ball", Vector3(sx * 0.3, 0.25, 0.08), 0.022])
				p.append(["glow", "ball", Vector3(sx * 0.25, 0.23, -0.1), 0.02])
			p.append(["flesh_raw", "ball", Vector3(0.0, 0.34, -0.3), 0.09])
			p.append(["glow", "ball", Vector3(0.0, 0.4, -0.32), 0.04])
			return [["spine_03", "crown", p]]
		"overgrowth":   # roots crawling up both legs, anchored at the feet
			var p := [["bark", "box", Vector3(0.0, 0.25, -0.07), Vector3(0.12, 0.38, 0.03)]]
			for i in 4:
				p.append(["flesh_raw", "tube", Vector3(0.0, 0.05 + i * 0.1, -0.07), Vector3(0.09 * (1 if i % 2 == 0 else -1), 0.1 + i * 0.1, -0.08), 0.014])
				p.append(["glow", "ball", Vector3(0.09 * (1 if i % 2 == 0 else -1), 0.1 + i * 0.1, -0.09), 0.015])
			return [["thigh_l", "roots_tl", p], ["thigh_r", "roots_tr", p], ["calf_l", "roots_cl", p], ["calf_r", "roots_cr", p]]
		"martyr_strain":   # bursting bulbs strapped across the chest like charges
			return [["spine_03", "bulbs", [
				["m_blood", "ball", Vector3(-0.1, 0.1, 0.2), 0.065], ["m_blood", "ball", Vector3(0.1, 0.1, 0.2), 0.065],
				["m_blood", "ball", Vector3(0.0, -0.05, 0.21), 0.075],
				["glow", "ball", Vector3(-0.1, 0.1, 0.255), 0.022], ["glow", "ball", Vector3(0.1, 0.1, 0.255), 0.022],
				["glow", "ball", Vector3(0.0, -0.05, 0.275), 0.026],
				["glow", "tube", Vector3(-0.1, 0.1, 0.22), Vector3(0.1, 0.1, 0.22), 0.008],
				["glow", "tube", Vector3(0.0, 0.1, 0.22), Vector3(0.0, -0.05, 0.24), 0.008]]]]
		# --- Strain (Vector) --------------------------------------------------
		"host_body":   # a swollen host sac heaped over the pack
			return [["spine_03", "host", [
				["flesh_raw", "ball", Vector3(0.0, 0.34, -0.3), 0.14], ["flesh_raw", "ball", Vector3(-0.14, 0.28, -0.26), 0.09],
				["flesh_raw", "ball", Vector3(0.14, 0.28, -0.26), 0.09], ["glow", "ball", Vector3(0.0, 0.4, -0.4), 0.05],
				["glow", "ball", Vector3(-0.14, 0.32, -0.34), 0.026], ["glow", "ball", Vector3(0.14, 0.32, -0.34), 0.026],
				["glow", "tube", Vector3(0.0, 0.3, -0.2), Vector3(0.0, 0.18, 0.0), 0.012]]]]
		"spore_burst":   # a puffball of spores on the shoulder
			return [["spine_03", "puff", [
				["flesh_raw", "ball", Vector3(0.2, 0.32, 0.0), 0.11], ["glow", "ball", Vector3(0.2, 0.4, 0.0), 0.045],
				["glow", "ball", Vector3(0.28, 0.34, 0.07), 0.025], ["glow", "ball", Vector3(0.14, 0.34, -0.08), 0.025],
				["glow", "ball", Vector3(0.26, 0.28, -0.07), 0.02]]]]
		"hive_link":   # antenna tendrils off the helmet back
			var p := []
			for i in 4:
				var sx := -1.0 if i % 2 == 0 else 1.0
				var h := 0.2 + (i / 2) * 0.12
				var tip := Vector3(sx * (0.12 + i * 0.03), 0.14 + h, -0.14)
				p.append(["flesh_raw", "tube", Vector3(sx * 0.06, 0.14, -0.1), tip, 0.014, 0.005])
				p.append(["glow", "ball", tip, 0.022])
			return [["Head", "tendrils", p]]
		"flies":   # a halo of flies round the head and shoulders
			var p := []
			for i in 9:
				var a := i * TAU / 9.0
				p.append(["claw", "ball", Vector3(cos(a) * 0.24, 0.2 + (i % 3) * 0.07, sin(a) * 0.22), 0.02])
				if i % 3 == 0:
					p.append(["glow", "ball", Vector3(cos(a) * 0.24, 0.22 + (i % 3) * 0.07, sin(a) * 0.22), 0.009])
			return [["Head", "swarm", p]]
		"ride_the_wave":   # a glowing fin crest running over the helmet and down the nape
			var p := []
			for i in 6:
				var z := 0.08 - i * 0.055
				var y := 0.22 + 0.1 * sin(float(i) / 5.0 * PI) - i * 0.015
				p.append(["flesh_raw", "box", Vector3(0.0, y, z), Vector3(0.022, 0.1 + 0.03 * (i % 2), 0.06), Vector3(-0.35, 0, 0)])
				p.append(["glow", "box", Vector3(0.0, y + 0.06, z - 0.01), Vector3(0.024, 0.014, 0.04)])
			return [["Head", "crest", p]]
		"patient_zero":   # a crown of bone spikes and a split chest, the source of it all
			var p := []
			for i in 7:
				var a := i * TAU / 7.0
				p.append(["m_bone", "tube", Vector3(cos(a) * 0.1, 0.2, sin(a) * 0.1), Vector3(cos(a) * 0.15, 0.4 + (i % 2) * 0.06, sin(a) * 0.15), 0.022, 0.004])
			return [["Head", "crown", p], ["spine_03", "split", [
				["flesh_raw", "ball", Vector3(0.0, 0.03, 0.2), 0.1], ["glow", "ball", Vector3(0.0, 0.03, 0.27), 0.04],
				["glow", "tube", Vector3(0.0, 0.03, 0.26), Vector3(0.0, 0.2, 0.2), 0.012], ["glow", "tube", Vector3(0.0, 0.03, 0.26), Vector3(0.0, -0.17, 0.2), 0.012]]]]
	return []


## Bone barbs along an upper arm's outer side (`lat`: -1 left arm, +1 right).
static func _spikes(lat: float) -> Array:
	var p := []
	for i in 3:
		p.append(["m_bone", "tube", Vector3(lat * 0.08, 0.04 + i * 0.1, 0.0), Vector3(lat * 0.2, 0.0 + i * 0.1, -0.02), 0.03, 0.006])
	return p


## A curved bone scythe past the wrist, bending out and away, veined at the root.
static func _scythe(lat: float) -> Array:
	return [["flesh_raw", "ball", Vector3(0.0, 0.16, 0.0), 0.07], ["glow", "ball", Vector3(lat * 0.01, 0.16, 0.065), 0.02],
		["m_bone", "tube", Vector3(lat * 0.02, 0.26, 0.0), Vector3(lat * 0.1, 0.5, 0.0), 0.04, 0.026],
		["m_bone", "tube", Vector3(lat * 0.1, 0.5, 0.0), Vector3(lat * 0.26, 0.68, 0.0), 0.026, 0.004],
		["glow", "tube", Vector3(lat * 0.06, 0.4, 0.035), Vector3(lat * 0.15, 0.56, 0.03), 0.006]]
