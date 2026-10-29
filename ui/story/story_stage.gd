extends Node3D
## The staged 3D shot behind a story scene: a small set built from primitives plus the game's own
## character models, lit for mood, with a slow camera move. One per scene, inside the scene's own
## SubViewport world. Sets: "wall" (the cordon breach), "port" (a Port Ardent street), "bore"
## (the rim of the shaft), "boss" (a boss up close), "burn" / "sample" / "carry" (the endings).
##
## `cast` is the squad: [{kind, owner, infection}] (the run's soldiers; any length, 1-4 shown).

const UnitView := preload("res://view/unit_view.gd")
const PostFx := preload("res://view/post_fx.gd")
const ModelKit := preload("res://view/model_kit.gd")

const CONCRETE := Color("283345")
const GROUND := Color("171f30")
const TEAL := Color("3fe0c5")
const SODIUM := Color("ffc27a")
const FIRE := Color("ff7a2e")

var set_kind := "wall"
var cast: Array = []
var boss := ""
var carrier_index := 0
## Seconds the camera takes over its move (the scene sets it to its own length).
var duration := 14.0

var cam: Camera3D
var _env: Environment
var _views: Array = []
var _walkers: Array = []   # [{view, from, to}] moved along with the camera
var _from: Transform3D
var _to: Transform3D
var _t := 0.0
var _pulse: Array = []     # lights that breathe: [{light, base}]
var _shaft: MeshInstance3D


func configure(kind: String, squad: Array, boss_kind := "", carrier := 0, secs := 14.0) -> void:
	set_kind = kind
	cast = squad
	boss = boss_kind
	carrier_index = carrier
	duration = secs


func _ready() -> void:
	_build_env()
	cam = Camera3D.new()
	cam.fov = 42.0
	cam.near = 0.1
	cam.far = 300.0
	add_child(cam)
	cam.current = true
	match set_kind:
		"port": _set_port()
		"bore": _set_bore("bore")
		"boss": _set_boss()
		"burn", "sample", "carry": _set_bore(set_kind)
		_: _set_wall()
	cam.transform = _from
	var post := CanvasLayer.new()
	add_child(post)
	post.add_child(PostFx.make())


func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / maxf(duration, 0.1), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	cam.transform = _from.interpolate_with(_to, k)
	for w in _walkers:
		var uv: Node3D = w.view
		uv.position = (w.from as Vector3).lerp(w.to, clampf(_t / w.secs, 0.0, 1.0))
		if _t >= w.secs:
			uv.set_moving(false)
	for uv in _views:
		uv.tick(delta)
	for p in _pulse:
		(p.light as Light3D).light_energy = p.base * (0.8 + 0.2 * sin(_t * p.get("speed", 1.6) + p.get("phase", 0.0)))
	if _shaft != null and set_kind == "carry":
		var m: StandardMaterial3D = _shaft.material_override
		m.albedo_color.a = lerpf(0.05, 0.3, k)


# --- shared pieces --------------------------------------------------------------------

func _build_env() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color("07090a")
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color("223035")
	_env.ambient_light_energy = 0.45
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.05
	_env.tonemap_white = 6.0
	_env.glow_enabled = true
	_env.glow_intensity = 0.9
	_env.glow_bloom = 0.08
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	_env.fog_enabled = true
	_env.fog_light_color = Color("101618")
	_env.fog_density = 0.035
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)


func _look(from: Vector3, at: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(at - from, Vector3.UP), from)


func _mat(col: Color, emit := 0.0, rough := 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emit
	return m


func _box(size: Vector3, pos: Vector3, col: Color, rot := 0.0, emit := 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(col, emit)
	mi.position = pos
	mi.rotation.y = rot
	add_child(mi)
	return mi


func _ground(col := GROUND, size := 120.0) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(col)
	add_child(mi)


## A cluster of glowing Bloom growths around `at`.
func _growth(at: Vector3, n := 5, scale := 1.0, col := TEAL) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(at)
	for i in n * 2:
		var mesh := SphereMesh.new()
		var r := rng.randf_range(0.1, 0.32) * scale
		mesh.radius = r
		mesh.height = r * rng.randf_range(1.2, 2.2)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _mat(col.darkened(rng.randf_range(0.2, 0.6)), rng.randf_range(0.6, 2.0), 0.5)
		mi.position = at + Vector3(rng.randf_range(-0.9, 0.9), r * 0.5, rng.randf_range(-0.6, 0.6)) * scale
		add_child(mi)


func _omni(pos: Vector3, col: Color, energy: float, rng_m: float, pulse := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_m
	add_child(l)
	if pulse:
		_pulse.append({"light": l, "base": energy, "phase": pos.x})
	return l


func _spot(pos: Vector3, at: Vector3, col: Color, energy: float, rng_m: float, angle := 30.0) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.spot_range = rng_m
	l.spot_angle = angle
	l.shadow_enabled = true
	add_child(l)
	l.transform = _look(pos, at)
	return l


## Drifting spores: small glowing motes in a box around `center`.
func _spores(center: Vector3, extent: Vector3, col := TEAL, amount := 80) -> void:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extent
	p.direction = Vector3(0, 1, 0)
	p.spread = 60.0
	p.gravity = Vector3(0, 0.02, 0)
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.25
	var mesh := SphereMesh.new()
	mesh.radius = 0.014
	mesh.height = 0.028
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = _mat(col, 6.0, 1.0)
	p.mesh = mesh
	p.position = center
	add_child(p)


func _unit(kind: String, owner: int, infection: int, pos: Vector3, face: Vector3, turned := false) -> Node3D:
	var u := Unit.new()
	u.id = _views.size() + 1
	u.kind = kind
	u.display_name = kind
	u.owner_player = owner
	u.team = Types.Team.PLAYER if UnitData.SOLDIERS.has(kind) else Types.Team.ENEMY
	u.max_hp = 6
	u.hp = 6
	u.infection = infection
	u.pos = Vector2i.ZERO
	var uv := UnitView.new()
	uv.build(u)
	uv.set_overlays_visible(false)
	add_child(uv)
	uv.position = pos
	uv.face_towards(face, true)
	if turned:
		uv.set_turned()
	uv.get("_infection_ring").visible = false   # a gameplay readout, not part of the shot
	_views.append(uv)
	return uv


## The squad in a loose line at `center`, facing `face`, `gap` apart along `side`.
func _squad(center: Vector3, face: Vector3, gap := 1.3, side := Vector3.RIGHT) -> Array:
	var out: Array = []
	var shown := cast.slice(0, 4)
	if shown.is_empty():
		shown = [{"kind": "trooper", "owner": 0, "infection": 20}]
	for i in shown.size():
		var c: Dictionary = shown[i]
		var off := (i - (shown.size() - 1) * 0.5) * gap
		var stagger := Vector3(0, 0, 0.35 if i % 2 == 1 else 0.0)
		var pos := center + side * off + stagger
		out.append(_unit(c.get("kind", "trooper"), c.get("owner", 0), c.get("infection", 0), pos,
			pos + (face - center)))
	return out


# --- sets ---------------------------------------------------------------------------------

## The cordon wall at night, the breach lit teal from the far side, the squad in front of it.
func _set_wall() -> void:
	_ground()
	for side in [-1.0, 1.0]:
		_box(Vector3(26, 9, 1.6), Vector3(side * 16.0, 4.5, -14), CONCRETE)
		for i in 5:   # panel seams and a walkway lip
			_box(Vector3(0.25, 9.0, 1.7), Vector3(side * (5.5 + i * 5.0), 4.5, -14), CONCRETE.darkened(0.35))
		_box(Vector3(26, 0.5, 2.4), Vector3(side * 16.0, 9.2, -14), CONCRETE.darkened(0.2))
		_box(Vector3(1.2, 10, 2.0), Vector3(side * 3.1, 5, -14), CONCRETE.darkened(0.2))
		# floodlight towers on the wall top, washing down over the camp
		_box(Vector3(0.3, 3.0, 0.3), Vector3(side * 9.0, 10.9, -14), Color("1c2231"))
		_box(Vector3(0.9, 0.5, 0.4), Vector3(side * 9.0, 12.4, -13.6), SODIUM, 0.0, 4.0)
		_spot(Vector3(side * 9.0, 12.2, -13.0), Vector3(side * 2.5, 0, -5), SODIUM, 9.0, 34.0, 32.0)
		_omni(Vector3(side * 6.0, 4.0, -12.0), SODIUM.darkened(0.2), 1.6, 9.0)
	# a lintel over the breach, rubble at its foot
	_box(Vector3(6.2, 1.4, 1.6), Vector3(0, 8.3, -14), CONCRETE.darkened(0.1))
	_box(Vector3(1.6, 0.8, 1.2), Vector3(-1.2, 0.4, -13.2), CONCRETE, 0.4)
	_box(Vector3(1.0, 0.6, 0.9), Vector3(1.5, 0.3, -12.6), CONCRETE, -0.7)
	# the Bloom beyond the wall, spilling through
	_omni(Vector3(0, 2.5, -17), TEAL, 10.0, 16.0, true)
	_omni(Vector3(0, 1.0, -12.5), TEAL, 2.5, 6.0, true)
	_growth(Vector3(-2.2, 0, -14.4), 6, 1.3)
	_growth(Vector3(2.0, 0, -13.6), 4, 0.9)
	_growth(Vector3(0.6, 0, -18), 8, 2.2)
	# the camp on this side: tents, a barrier and a warning light
	for i in 6:
		var x := -12.0 + i * 4.6
		if absf(x) > 3.0:
			_box(Vector3(2.4, 1.3, 2.4), Vector3(x, 0.65, -7.0 - (i % 2) * 1.6), Color("232e40"), 0.785)
	_box(Vector3(5.0, 0.9, 0.3), Vector3(-5.5, 0.45, -2.5), Color("4a3f2a"), 0.2)
	_omni(Vector3(-6, 1.2, -3), Color("ff4a33"), 1.6, 6.0, true)
	_spores(Vector3(0, 3, -10), Vector3(10, 3, 6))
	_squad(Vector3(0, 0, -4.5), Vector3(0, 0, -14))
	_from = _look(Vector3(3.5, 2.6, 7.5), Vector3(0, 3.2, -14))
	_to = _look(Vector3(1.2, 1.8, 2.2), Vector3(0, 2.8, -14))


## A Port Ardent street: tall blocks, growths pouring from the doors, the squad walking in.
func _set_port() -> void:
	_ground(Color("151c2b"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for side in [-1.0, 1.0]:
		var z := 4.0
		while z > -60.0:
			var w := rng.randf_range(5.0, 8.0)
			var h := rng.randf_range(9.0, 22.0)
			_box(Vector3(6, h, w - 0.4), Vector3(side * 8.5, h * 0.5, z - w * 0.5), Color("1e2737").lerp(Color("242e40"), rng.randf()))
			# a few lit windows
			for i in 3:
				if rng.randf() < 0.5:
					_box(Vector3(0.1, 0.7, 0.9), Vector3(side * 5.45, rng.randf_range(3, h - 1), z - rng.randf_range(1, w - 1)),
						SODIUM.darkened(0.3) if rng.randf() < 0.6 else TEAL, 0.0, 2.0)
			if rng.randf() < 0.55:
				_growth(Vector3(side * 5.6, 0, z - w * 0.5), 6, 1.3)
			z -= w
	_box(Vector3(2.0, 1.4, 4.4), Vector3(-2.0, 0.7, -14), Color("3a2f24"), 0.5)   # an overturned truck
	_omni(Vector3(0, 6, -30), TEAL, 7.0, 30.0, true)
	_omni(Vector3(-3, 3, -14), SODIUM, 2.0, 9.0)
	_spores(Vector3(0, 3, -16), Vector3(5, 3, 16))
	var squad := _squad(Vector3(0, 0, -2), Vector3(0, 0, -30), 1.2)
	for uv in squad:
		uv.set_moving(true)
		_walkers.append({"view": uv, "from": uv.position, "to": uv.position + Vector3(0, 0, -6.5), "secs": duration * 0.8})
	_from = _look(Vector3(3.2, 0.8, 2.5), Vector3(0, 1.6, -8))
	_to = _look(Vector3(2.0, 1.2, -4.5), Vector3(-0.5, 2.5, -24))


## The rim of the Bore: a shaft of teal light rising out of the dark, scaffolding, the squad at
## the edge. The endings reuse it with their own light and staging.
func _set_bore(kind: String) -> void:
	_ground(Color("141a28"))
	var pit := CylinderMesh.new()
	pit.top_radius = 7.5
	pit.bottom_radius = 7.5
	pit.height = 0.06
	var glow := TEAL
	if kind == "burn":
		glow = FIRE
	var disc := MeshInstance3D.new()
	disc.mesh = pit
	disc.material_override = _mat(glow.darkened(0.9), 0.6 if kind != "carry" else 1.2, 1.0)
	disc.position = Vector3(0, 0.02, 0)
	add_child(disc)
	# the lip of the shaft glows where the light spills over it
	var lip := TorusMesh.new()
	lip.inner_radius = 7.3
	lip.outer_radius = 7.7
	var lip_mi := MeshInstance3D.new()
	lip_mi.mesh = lip
	lip_mi.material_override = _mat(glow, 2.5, 1.0)
	add_child(lip_mi)
	# the light coming up the shaft
	var shaft := CylinderMesh.new()
	shaft.top_radius = 8.0
	shaft.bottom_radius = 7.2
	shaft.height = 26.0
	_shaft = MeshInstance3D.new()
	_shaft.mesh = shaft
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.albedo_color = Color(glow, 0.1)
	_shaft.material_override = sm
	_shaft.position = Vector3(0, 13, 0)
	add_child(_shaft)
	_omni(Vector3(0, 1.5, 0), glow, 10.0, 22.0, true)
	_omni(Vector3(0, 8, 0), glow, 4.0, 26.0, true)
	# the rim: broken slabs and drill scaffolding
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 22:
		var a := TAU * i / 22.0
		var r := 8.2 + rng.randf_range(0, 1.2)
		_box(Vector3(rng.randf_range(1.5, 2.6), rng.randf_range(0.3, 1.1), rng.randf_range(0.8, 1.6)),
			Vector3(cos(a) * r, 0.3, sin(a) * r), CONCRETE.darkened(rng.randf_range(0, 0.35)), -a + rng.randf_range(-0.3, 0.3))
	for i in 4:
		var a := TAU * (i + 0.5) / 4.0
		var base := Vector3(cos(a) * 9.5, 0, sin(a) * 9.5)
		_box(Vector3(0.35, 16, 0.35), base + Vector3(0, 8, 0), Color("2a2620"))
	_box(Vector3(0.4, 0.4, 19.5), Vector3(0, 15.5, 0), Color("2a2620"), PI * 0.25)
	_box(Vector3(0.4, 0.4, 19.5), Vector3(0, 15.5, 0), Color("2a2620"), -PI * 0.25)
	for i in 6:
		var a := TAU * i / 6.0 + 0.3
		_growth(Vector3(cos(a) * 7.8, 0, sin(a) * 7.8), 5, 1.1, glow if kind == "burn" else TEAL)
	_spores(Vector3(0, 4, 0), Vector3(7, 5, 7), glow, 120)
	var at := Vector3(0, 0, 9.6)
	match kind:
		"burn":
			_squad(at, Vector3(0, 0, 0), 1.3)
			_fire()
			_from = _look(Vector3(-2.0, 2.4, 17.0), Vector3(0, 2.0, 0))
			_to = _look(Vector3(-0.6, 1.8, 13.5), Vector3(0, 3.5, 0))
		"sample":
			_squad(at + Vector3(-1.5, 0, 0), Vector3(0, 0, 0), 1.2)
			for i in 2:
				var hv := _unit(["marksman", "trooper"][i], -1, 0, at + Vector3(2.8 + i * 1.1, 0, -0.4 + i * 0.6), at + Vector3(-1, 0, -1.5))
				_white(hv)
			_box(Vector3(0.7, 0.5, 0.45), at + Vector3(1.2, 0.25, -1.4), Color("d8dad2"))   # the sample case
			_box(Vector3(0.3, 0.12, 0.2), at + Vector3(1.2, 0.56, -1.4), TEAL, 0.0, 6.0)
			_omni(at + Vector3(1.2, 1.0, -1.4), TEAL, 1.5, 4.0, true)
			_spot(at + Vector3(3.0, 6.0, 2.0), at + Vector3(1.6, 0, -1), Color("e8f0ff"), 5.0, 14.0, 24.0)
			_from = _look(Vector3(6.5, 2.2, 17.0), at + Vector3(0.6, 1.2, -1.0))
			_to = _look(Vector3(4.2, 1.7, 14.8), at + Vector3(1.0, 0.9, -1.4))
		"carry":
			var shown := cast.slice(0, 4)
			var others: Array = []
			var carrier: Dictionary = {"kind": "trooper", "owner": 0, "infection": 90}
			for i in shown.size():
				if i == carrier_index:
					carrier = shown[i]
				else:
					others.append(shown[i])
			var keep := cast
			cast = others
			_squad(at + Vector3(0, 0, 1.0), Vector3(0, 0, 0), 1.4)
			cast = keep
			var cv := _unit(carrier.get("kind", "trooper"), carrier.get("owner", 0), 100, at + Vector3(0, 0, -0.8), Vector3.ZERO, true)
			cv.set_moving(true)
			_walkers.append({"view": cv, "from": cv.position, "to": Vector3(0, 0, 3.0), "secs": duration * 0.75})
			_from = _look(Vector3(1.4, 1.5, 14.5), Vector3(0, 1.6, 4.0))
			_to = _look(Vector3(0.4, 2.6, 13.0), Vector3(0, 3.0, 0))
		_:
			_squad(at, Vector3(0, 0, 0), 1.3)
			_from = _look(Vector3(1.5, 3.2, 15.5), Vector3(0, 2.5, 0))
			_to = _look(Vector3(0.3, 2.4, 12.6), Vector3(0, 0.5, 0))


func _fire() -> void:
	var p := CPUParticles3D.new()
	p.amount = 260
	p.lifetime = 1.6
	p.preprocess = 2.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 6.8
	p.emission_ring_inner_radius = 0.5
	p.emission_ring_height = 0.2
	p.direction = Vector3(0, 1, 0)
	p.spread = 12.0
	p.gravity = Vector3(0, 3.0, 0)
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = _mat(FIRE, 3.0, 1.0)
	p.mesh = mesh
	p.position = Vector3(0, 0.2, 0)
	add_child(p)
	_omni(Vector3(3, 2, 2), FIRE, 6.0, 14.0, true)
	_omni(Vector3(-3, 2, -2), Color("ffb347"), 5.0, 14.0, true)


## Halden-Voss white: recolours a model's armour and cloth.
func _white(uv: Node3D) -> void:
	var mats: Dictionary = uv.get("_mats")
	for role in ["body", "cloth_team", "cloak_team", "armor_team"]:
		if mats.has(role):
			mats[role].set_shader_parameter("albedo", Color("c9ccc4") if role != "body" else Color("8a8d86"))


## A boss alone in the dark, lit from below and behind, the camera pushing in.
func _set_boss() -> void:
	_ground(Color("15171a"))
	var kind := boss if boss != "" else "brood_mother"
	var size := ModelKit.size_of(kind)
	var col := TEAL
	match kind:
		"colonel_hale":
			col = Color("e8f0ff")
			for x in [-6.0, 6.0]:
				_box(Vector3(2.5, 1.2, 1.0), Vector3(x, 0.6, -2.0), CONCRETE, 0.3 * signf(x))
			_spot(Vector3(0, 9, 4), Vector3(0, 0, 0), col, 7.0, 16.0, 22.0)
			_omni(Vector3(-4, 1, -4), Color("ff4a33"), 2.0, 8.0, true)
		"director":   # three posts on the roofs behind her, red laser lines laid across the shot
			col = Color("e8f0ff")
			for x in [-6.5, 6.5]:
				_box(Vector3(3.0, 3.0, 2.2), Vector3(x, 1.5, -4.5), CONCRETE, 0.0)
				var post := _unit("sharpshooter", -1, 0, Vector3(x, 3.0, -4.5), Vector3(0, 0, 10))
				_white(post)
				var beam := _box(Vector3(0.03, 0.03, 12.0), Vector3(x * 0.35, 2.6, 1.0), Color("ff3a2a"), 0.0, 4.0)
				beam.rotation.y = -0.35 * signf(x)
			_box(Vector3(4.0, 4.4, 2.6), Vector3(0, 2.2, -5.5), CONCRETE, 0.0)
			_spot(Vector3(0, 9, 4), Vector3(0, 0, 0), col, 7.0, 16.0, 22.0)
			_omni(Vector3(-3, 1, -3), Color("ff4a33"), 1.5, 8.0, true)
		"the_source":
			for i in 6:
				var a := TAU * i / 6.0
				_unit("source_root", -1, 0, Vector3(cos(a) * 4.5, 0, sin(a) * 4.5 - 1.0), Vector3(0, 0, -1))
			_omni(Vector3(0, 3, 0), TEAL, 9.0, 18.0, true)
			_spores(Vector3(0, 3, 0), Vector3(8, 4, 8), TEAL, 140)
		_:
			for i in 4:
				var a := PI * 0.15 + PI * 0.7 * i / 3.0
				_unit("egg_sac", -1, 0, Vector3(cos(a) * 4.0, 0, -sin(a) * 2.5 - 2.0), Vector3(0, 0, 0))
			_growth(Vector3(-3, 0, -3), 7, 1.6)
			_growth(Vector3(3.5, 0, -2.5), 6, 1.4)
			_spores(Vector3(0, 2, -1), Vector3(6, 3, 5))
	_unit(kind, -1, 0, Vector3.ZERO, Vector3(0, 0, 10))
	_omni(Vector3(0, 0.4, 2.5), col, 3.0, 8.0, true)
	_omni(Vector3(0, 4.0, -4.0), col, 4.0, 12.0)
	var h := 1.7 * size
	_from = _look(Vector3(1.4, h * 0.45, 3.0 + size * 2.6), Vector3(0, h * 0.6, 0))
	_to = _look(Vector3(0.3, h * 0.4, 1.4 + size * 1.6), Vector3(0, h * 0.7, 0))
