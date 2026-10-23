extends RefCounted
## Colours and material factories for the placeholder "grimy stylized 3D" look.
## Shared by the 3D view and the HUD so both use the same player/tier colours.

const TEAL := Color("2ef2c8")
const TEAL_DIM := Color("1b8f78")
const DANGER := Color("e2533a")
const AMBER := Color("e8b04a")

const FLOOR_SHADES: Array[Color] = [Color("3b3d39"), Color("363834"), Color("41423d"), Color("33352f")]
const WALL := Color("24272a")
const WALL_TRIM := Color("3a3f44")
const CRATE := Color("4d4a35")
const CRATE_BAND := Color("2f2d22")
const GROUND := Color("1d1f1c")

const ENEMY_BODY := Color("1a1d1b")

## Body tint per player (index = player id), and a brighter variant for UI text.
const PLAYER_BODY: Array[Color] = [Color("56633a"), Color("a38d62"), Color("4f5d66"), Color("6b4f45")]
const PLAYER_UI: Array[Color] = [Color("a9c46e"), Color("e6c98f"), Color("8fb3c9"), Color("d39a86")]

## Infection tier colours, indexed by Infection.Tier (CLEAN..TURNED).
const TIER_COLORS: Array[Color] = [Color("6d7370"), Color("2ea88f"), Color("2ef2c8"), Color("b4f22e"), Color("e2533a")]

const CLASS_LETTER := {"trooper": "T", "marksman": "M", "medic": "+", "breacher": "B"}


static func player_body(p: int) -> Color:
	return PLAYER_BODY[posmod(p, PLAYER_BODY.size())]


static func player_ui(p: int) -> Color:
	return PLAYER_UI[posmod(p, PLAYER_UI.size())]


static func tier_color(t: int) -> Color:
	return TIER_COLORS[clampi(t, 0, TIER_COLORS.size() - 1)]


static func class_letter(kind: String) -> String:
	return CLASS_LETTER.get(kind, kind.left(1).to_upper())


static func mat(color: Color, roughness := 0.85, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


static func emissive(color: Color, energy := 2.0) -> StandardMaterial3D:
	var m := mat(color.darkened(0.4), 0.5)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


## Unshaded, alpha-blended, optionally drawn on top of everything. For overlays and FX.
static func overlay(color: Color, on_top := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = on_top
	return m


static func box(size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	return mi


static func ring(inner: float, outer: float, material: Material) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 24
	mesh.ring_segments = 6
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func label3d(text: String, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.005
	l.modulate = color
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	return l
