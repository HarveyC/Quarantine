extends RefCounted
## Loads unit models and swaps their role materials for the character shader, tinted
## per player: skinned characters (assets/characters, tools/build_characters.py) and the
## static props (assets/models, tools/gen_models.py). See those scripts' docstrings for
## the naming contract (material roles, "grow<N>_*" infection growths, "sac", "muzzle").

const Palette := preload("res://view/palette.gd")
const SHADER := preload("res://view/character.gdshader")
const GunModels := preload("res://view/gun_models.gd")
const MeleeKit := preload("res://view/melee_kit.gd")

const MODELS := {
	"drifter": preload("res://assets/models/drifter.glb"),
	"hive_node": preload("res://assets/models/hive_node.glb"),
	"egg_sac": preload("res://assets/models/egg_sac.glb"),
	"spore_nest": preload("res://assets/models/spore_nest.glb"),
	"source_root": preload("res://assets/models/source_root.glb"),
	"the_source": preload("res://assets/models/the_source.glb"),
}
## Skinned characters (assets/characters, built by tools/build_characters.py from CC0
## Quaternius bodies and animations, see view/skinned_body.gd). Kinds listed here use
## them; the rest still use the jointed models above.
const CHARACTERS := {
	"trooper": preload("res://assets/characters/trooper.glb"),
	"marksman": preload("res://assets/characters/marksman.glb"),
	"medic": preload("res://assets/characters/medic.glb"),
	"breacher": preload("res://assets/characters/breacher.glb"),
	"civilian": preload("res://assets/characters/civilian.glb"),
	"runner": preload("res://assets/characters/runner.glb"),
	"spitter": preload("res://assets/characters/spitter.glb"),
	"leaper": preload("res://assets/characters/leaper.glb"),
	"shrieker": preload("res://assets/characters/shrieker.glb"),
	"broodling": preload("res://assets/characters/broodling.glb"),
	"brute": preload("res://assets/characters/brute.glb"),
	"bloater": preload("res://assets/characters/bloater.glb"),
	"brood_mother": preload("res://assets/characters/brood_mother.glb"),
	"fallen": preload("res://assets/characters/fallen.glb"),
	"sharpshooter": preload("res://assets/characters/sharpshooter.glb"),
	"colonel_hale": preload("res://assets/characters/colonel_hale.glb"),
	"lurker": preload("res://assets/characters/lurker.glb"),
	"burrower": preload("res://assets/characters/burrower.glb"),
}
## Body size per kind (the characters share one skeleton; bosses and brutes read bigger).
const SIZE := {
	"broodling": 0.62, "brute": 1.32, "bloater": 1.15, "brood_mother": 1.85, "shrieker": 1.1,
	"colonel_hale": 1.05,
}
const BODY_TEX := {
	"male": [preload("res://assets/characters/textures/male_albedo.jpg"), preload("res://assets/characters/textures/male_normal.png")],
	"female": [preload("res://assets/characters/textures/female_albedo.jpg"), preload("res://assets/characters/textures/female_normal.png")],
}

const ARMOR := Color("2e322c")
## Roles that glow on their own and skip grime / veins / hit flash.
const GLOWING := ["glow", "sac", "visor", "lens", "lamp", "mark_team"]
## Roles that infection veins can spread over.
const VEINABLE := ["body", "chitin", "cloth_team", "armor_team", "cloak_team", "skin", "strap", "leather", "plate", "flesh", "flesh_raw", "rags", "white"]


## Model for `kind`; kinds without one borrow the Trooper's (squad) or the Runner's.
static func instantiate(kind: String, is_soldier: bool) -> Node3D:
	if CHARACTERS.has(kind):
		return CHARACTERS[kind].instantiate()
	if MODELS.has(kind):
		return MODELS[kind].instantiate()
	if MeleeKit.is_melee(kind):   # borrowed body, melee props and a sidearm
		var b: Node3D = CHARACTERS[MeleeKit.body_of(kind)].instantiate()
		MeleeKit.dress(b, kind)
		return b
	var m: Node3D = (CHARACTERS.trooper if is_soldier else CHARACTERS.runner).instantiate()
	if GunModels.has_gun(kind):   # borrowed body, own weapon
		GunModels.swap(m, kind)
	return m


static func size_of(kind: String) -> float:
	if MeleeKit.is_melee(kind):
		return MeleeKit.size_of(kind)
	return SIZE.get(kind, 1.0) if CHARACTERS.has(kind) else 1.0


static func is_skinned(model: Node) -> bool:
	return not model.find_children("*", "Skeleton3D", true, false).is_empty()


## Replaces every surface material under `root` with a per-unit character material.
## Returns role -> ShaderMaterial so the unit view can drive flash / infection / tint.
static func apply_materials(root: Node, player: int, is_soldier: bool) -> Dictionary:
	var mats := {}
	_apply(root, player, is_soldier, mats)
	return mats


static func _apply(n: Node, player: int, is_soldier: bool, mats: Dictionary) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var skinned := mi.skin != null or mi.get_parent() is BoneAttachment3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var role := src.resource_name if src != null else "cloth_team"
			if not mats.has(role):
				mats[role] = _make(role, src as StandardMaterial3D, player, is_soldier)
				if skinned:
					_skinned(mats[role], role, String(mi.name), is_soldier)
			mi.set_surface_override_material(i, mats[role])
	for c in n.get_children():
		_apply(c, player, is_soldier, mats)


static func _make(role: String, src: StandardMaterial3D, player: int, is_soldier: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var col := src.albedo_color if src != null else Color.GRAY
	var rough := src.roughness if src != null else 0.85
	var metal := src.metallic if src != null else 0.0
	var body := Palette.player_body(player) if player >= 0 or not is_soldier else Color("4b4a40")
	var ui := Palette.player_ui(player) if player >= 0 or not is_soldier else Palette.AMBER
	match role:
		"cloth_team", "body":
			col = body if is_soldier else Palette.ENEMY_BODY
		"eyes":
			col = Color("1a1612")
		"hair":
			col = Color("2a2420")
		"armor_team":
			col = ARMOR.lerp(body, 0.22).darkened(0.12)
		"cloak_team":
			col = body.darkened(0.45)
		"mark_team":
			col = ui
			_emit(m, ui, 0.7)
		"visor":
			col = ui.darkened(0.5)
			_emit(m, ui, 2.4)
		"glow":
			col = Palette.TEAL.darkened(0.4)
			_emit(m, Palette.TEAL, 3.2)
			m.set_shader_parameter("pulse", 0.18)
		"sac":
			col = Palette.TEAL_DIM.darkened(0.3)
			_emit(m, Palette.TEAL, 1.8)
			m.set_shader_parameter("pulse", 0.25)
		"growth":
			_emit(m, Palette.TEAL, 1.4)
		"lens", "lamp":
			_emit(m, src.emission if src != null else col, 2.5)
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("metallic", metal)
	var glowing := role in GLOWING
	m.set_shader_parameter("grime", 0.0 if glowing else (0.7 if is_soldier else 0.45))
	m.set_shader_parameter("rim", 0.0 if glowing else (0.38 if is_soldier else 0.18))
	if not is_soldier:
		m.set_shader_parameter("rim_color", Color("3f8a7c"))
		m.set_shader_parameter("vein_energy", 1.1)
	m.set_meta("role", role)
	return m


## Skinned parts: noise from the baked rest positions; the body gets its textures.
static func _skinned(m: ShaderMaterial, role: String, mesh_name: String, is_soldier: bool) -> void:
	m.set_shader_parameter("rest_from_color", true)
	if role == "cloth_team" and is_soldier:
		m.set_shader_parameter("camo", 0.8)
	if role != "body":
		return
	var tex: Array = BODY_TEX.female if mesh_name.contains("Female") else BODY_TEX.male
	m.set_shader_parameter("textured", true)
	m.set_shader_parameter("albedo_tex", tex[0])
	m.set_shader_parameter("normal_tex", tex[1])
	m.set_shader_parameter("skin_tint", Color(0.8, 0.74, 0.68) if is_soldier else Color(0.42, 0.47, 0.44))
	m.set_shader_parameter("skin_all", 0.0 if is_soldier else 1.0)


static func _emit(m: ShaderMaterial, color: Color, energy: float) -> void:
	m.set_shader_parameter("emission_color", color)
	m.set_shader_parameter("emission_energy", energy)


static func find(root: Node, joint: String) -> Node3D:
	return root.find_child(joint, true, false) as Node3D


## Infection growth meshes ("grow1_*", "grow2_*", ...) as [stage, node] pairs.
static func growths(root: Node) -> Array:
	var out := []
	_collect_growths(root, out)
	return out


static func _collect_growths(n: Node, out: Array) -> void:
	var nm := String(n.name)
	if n is MeshInstance3D and nm.begins_with("grow") and nm.length() > 4 and nm[4].is_valid_int():
		out.append([int(nm[4]), n])
	for c in n.get_children():
		_collect_growths(c, out)
