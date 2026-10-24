extends RefCounted
## Loads the generated character models (assets/models/*.glb, built by
## tools/gen_models.py) and swaps their role materials for the character shader,
## tinted per player. See the generator's docstring for the node naming contract.

const Palette := preload("res://view/palette.gd")
const SHADER := preload("res://view/character.gdshader")

const MODELS := {
	"trooper": preload("res://assets/models/trooper.glb"),
	"marksman": preload("res://assets/models/marksman.glb"),
	"medic": preload("res://assets/models/medic.glb"),
	"breacher": preload("res://assets/models/breacher.glb"),
	"runner": preload("res://assets/models/runner.glb"),
	"spitter": preload("res://assets/models/spitter.glb"),
}
## Forearm length from elbow to the centre of the glove, for arm IK (matches the generator).
const FOREARM := 0.29

const ARMOR := Color("2e322c")
## Roles that glow on their own and skip grime / veins / hit flash.
const GLOWING := ["glow", "sac", "visor", "lens", "lamp", "mark_team"]
## Roles that infection veins can spread over.
const VEINABLE := ["cloth_team", "armor_team", "cloak_team", "skin", "strap", "leather", "plate", "flesh", "flesh_raw", "rags", "white"]


## Model for `kind`; enemies without their own model yet borrow the Runner's.
static func instantiate(kind: String, is_soldier: bool) -> Node3D:
	var scene: PackedScene = MODELS.get(kind, MODELS.trooper if is_soldier else MODELS.runner)
	return scene.instantiate()


## Replaces every surface material under `root` with a per-unit character material.
## Returns role -> ShaderMaterial so the unit view can drive flash / infection / tint.
static func apply_materials(root: Node, player: int, is_soldier: bool) -> Dictionary:
	var mats := {}
	_apply(root, player, is_soldier, mats)
	return mats


static func _apply(n: Node, player: int, is_soldier: bool, mats: Dictionary) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var role := src.resource_name if src != null else "cloth_team"
			if not mats.has(role):
				mats[role] = _make(role, src as StandardMaterial3D, player, is_soldier)
			mi.set_surface_override_material(i, mats[role])
	for c in n.get_children():
		_apply(c, player, is_soldier, mats)


static func _make(role: String, src: StandardMaterial3D, player: int, is_soldier: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var col := src.albedo_color if src != null else Color.GRAY
	var rough := src.roughness if src != null else 0.85
	var metal := src.metallic if src != null else 0.0
	var body := Palette.player_body(player)
	var ui := Palette.player_ui(player)
	match role:
		"cloth_team":
			col = body
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
	m.set_shader_parameter("rim", 0.0 if glowing else (0.28 if is_soldier else 0.14))
	if not is_soldier:
		m.set_shader_parameter("rim_color", Color("3f8a7c"))
		m.set_shader_parameter("vein_energy", 1.1)
	m.set_meta("role", role)
	return m


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
