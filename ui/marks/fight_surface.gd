extends RefCounted
## Pings and drawing on the tactical map (see ui/marks/mark_layer.gd): pings land on cells and
## follow the unit standing there, strokes are world points on the floor so they stay put when
## the camera moves. Each ping also gets a beacon in the world: a ring on the floor and a light
## column in the pinger's colour.

const Board := preload("res://view/board.gd")
const HEAD := Vector3(0, 1.9, 0)
## Stroke points sit just above the floor or roof they were drawn on.
const LIFT := 0.06
const HAZARD_NAMES := {"fire": "Fire", "spores": "Spores", "acid": "Acid", "gas": "Gas", "smoke": "Smoke"}
const MARKER_NAMES := {"beacon": "Beacon", "evac": "Gate", "exit": "Exit", "civilian": "Civilian",
		"charge": "Charge site", "relay": "Relay", "sample": "Sample point"}

var view: MissionView


func _init(v: MissionView) -> void:
	view = v


func where() -> String:
	return Marks.FIGHT


func active() -> bool:
	if view == null or view.state == null or view.camera_rig == null or view.camera_rig.cinematic:
		return false
	var pause: Variant = view.get("_pause_layer")
	return not (pause is Node and is_instance_valid(pause))


func player() -> int:
	var s: Node = view.session
	if s is NetSession:
		return (s as NetSession).my_player
	# Hot-seat: whoever's soldier is selected is at the controls.
	var u: Unit = view.input.selected_unit() if view.input != null else null
	if u != null:
		return u.owner_player
	var local: Array = s.local_players() if s != null else []
	return local[0] if not local.is_empty() else 0


## The ping target under viewport point `at`: {cell, unit?, context, subject}, or {} off the map.
func target(at: Vector2) -> Dictionary:
	var hit: Variant = view.camera_rig.screen_to_world(at)
	if hit == null:
		return {}
	var c := Board.world_to_cell(hit)
	if not view.state.grid.in_bounds(c):
		return {}
	var ctx := Marks.fight_context(view.state, c)
	var out := {"cell": c, "context": ctx}
	var u := view.state.unit_at(c)
	if ctx == "enemy" or ctx == "ally":
		out.unit = u.id
	out.subject = describe(out)
	return out


func point(at: Vector2) -> Variant:
	var hit: Variant = view.camera_rig.screen_to_world(at)
	if hit == null:
		return null
	var p: Vector3 = hit
	return Vector3(p.x, p.y + LIFT, p.z)


## Where a ping's badge sits in the world: over its unit's head while that unit lives, else
## on its cell.
func ping_world(m: Dictionary) -> Vector3:
	if m.has("unit"):
		var uv: Node3D = view.view_for(m.unit)
		if uv != null and uv.is_inside_tree() and not uv.get("dead"):
			return uv.global_position + Vector3(0, 0.15, 0)
	var c: Vector2i = m.get("cell", Vector2i.ZERO)
	return Board.cell_to_world(c, 0.05)


func ping_screen(m: Dictionary) -> Variant:
	return _project(ping_world(m))


func point_screen(p: Variant) -> Variant:
	return _project(p) if p is Vector3 else null


## For a ping behind the camera: which way it is on screen (down is towards the viewer).
func ping_ring(_m: Dictionary) -> float:
	return 0.0


func behind_dir(m: Dictionary) -> Variant:
	var cam := view.camera_rig.camera
	var local := cam.global_transform.affine_inverse() * ping_world(m)
	return Vector2(local.x, 1.0).normalized()


func _project(w: Vector3) -> Variant:
	var cam: Camera3D = view.camera_rig.camera if view.camera_rig != null else null
	if cam == null or not cam.is_inside_tree() or cam.is_position_behind(w):
		return null
	return cam.unproject_position(w)


## A short name for what the ping is on: the unit, the barrel or hazard, the objective marker.
func describe(m: Dictionary) -> String:
	var st := view.state
	if st == null or not m.has("cell"):
		return ""
	var c: Vector2i = m.cell
	if m.has("unit"):
		return view.unit_name(m.unit)
	if st.grid.is_volatile(c):
		return "Fuel barrel"
	if st.hazards.has(c):
		var k := str(st.hazards[c].get("kind", ""))
		return HAZARD_NAMES.get(k, k.capitalize())
	for key in MARKER_NAMES:
		if st.grid.marker(key).has(c):
			return MARKER_NAMES[key]
	return ""


## The world beacon for a ping, owned by the mark layer (freed when the ping expires).
func spawn(m: Dictionary) -> Node3D:
	if view == null:
		return null
	var b := Beacon.new()
	b.setup(Marks.color(m.player), m.kind == "danger")
	b.position = Board.cell_to_world(m.get("cell", Vector2i.ZERO), 0.04)   # the view sits at the origin
	view.add_child(b)
	return b


## A ring on the floor and a soft column of light, pulsing in the player's colour.
class Beacon extends Node3D:
	var _ring: MeshInstance3D
	var _beam: MeshInstance3D
	var _mat: StandardMaterial3D
	var _beam_mat: StandardMaterial3D
	var _t := 0.0

	func setup(col: Color, danger: bool) -> void:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.albedo_color = Color(col, 0.9)
		_mat.emission_enabled = true
		_mat.emission = col
		_mat.emission_energy_multiplier = 2.0
		_mat.no_depth_test = true
		_mat.render_priority = 2
		var torus := TorusMesh.new()
		torus.inner_radius = 0.38
		torus.outer_radius = 0.46
		torus.rings = 48
		_ring = MeshInstance3D.new()
		_ring.mesh = torus
		_ring.material_override = _mat
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ring)
		_beam_mat = _mat.duplicate()
		_beam_mat.no_depth_test = false
		_beam_mat.albedo_color = Color(col if not danger else Color("ff5fa2"), 0.28)
		_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.05
		cyl.bottom_radius = 0.12
		cyl.height = 2.6
		cyl.cap_top = false
		cyl.cap_bottom = false
		_beam = MeshInstance3D.new()
		_beam.mesh = cyl
		_beam.material_override = _beam_mat
		_beam.position.y = 1.3
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_beam)

	func _process(delta: float) -> void:
		_t += delta
		var grow := minf(1.0, _t / 0.2)
		var fade := clampf((Marks.PING_LIFE - _t) / 1.0, 0.0, 1.0)
		var s := (0.6 + 0.4 * grow) * (1.0 + 0.08 * sin(_t * 5.0))
		_ring.scale = Vector3(s, 1.0, s)
		_mat.albedo_color.a = 0.9 * fade
		_beam_mat.albedo_color.a = 0.28 * fade * grow
