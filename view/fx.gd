extends Node3D
## Short-lived effects: tracers, muzzle flashes, floating text, pulses.
## Driven by `advance(delta)` from the event player's clock (not _process), so
## everything stays in step with the event queue and can be stepped in tests.

const Palette := preload("res://view/palette.gd")

const MAX_DECALS := 60

var _items: Array[Dictionary] = []   # {node, life, max, kind, mat?, rise?}
var _decals: Array[Node3D] = []
var _bits: Array[Dictionary] = []    # physics chips: {node, vel, life, max, mat, a0, spin, floor}


func advance(delta: float) -> void:
	for i in range(_items.size() - 1, -1, -1):
		var it: Dictionary = _items[i]
		it.life -= delta
		var k: float = clampf(1.0 - it.life / it.max, 0.0, 1.0)
		var node: Node3D = it.node
		match it.kind:
			"text":
				node.position.y = it.y0 + k * 0.9
				(node as Label3D).modulate.a = 1.0 - maxf(0.0, k - 0.6) / 0.4
			"fade":
				var m: StandardMaterial3D = it.mat
				m.albedo_color.a = it.a0 * (1.0 - k)
			"light":
				(node as OmniLight3D).light_energy = it.e0 * (1.0 - k)
			"ring":
				var s := 0.4 + k * 1.6
				node.scale = Vector3(s, 0.3, s)
				var rm: StandardMaterial3D = it.mat
				rm.emission_energy_multiplier = 4.0 * (1.0 - k)
			"puff":
				var ps: float = it.s0 + k * it.grow
				node.scale = Vector3(ps, ps, ps)
				node.position.y = it.y0 + k * it.rise
				var pm: StandardMaterial3D = it.mat
				pm.albedo_color.a = it.a0 * (1.0 - k) * (1.0 - k)
		if it.life <= 0.0:
			_items.remove_at(i)
			node.queue_free()
	for i in range(_bits.size() - 1, -1, -1):
		var b: Dictionary = _bits[i]
		b.life -= delta
		var n: Node3D = b.node
		var v: Vector3 = b.vel
		v.y -= 9.0 * delta * b.grav
		v *= 1.0 - minf(1.0, delta * b.drag)
		b.vel = v
		n.position += v * delta
		n.rotation += b.spin * delta
		if n.position.y < b.floor:
			n.position.y = b.floor
			b.vel = Vector3(v.x * 0.4, -v.y * 0.25, v.z * 0.4)
		var bm: StandardMaterial3D = b.mat
		bm.albedo_color.a = b.a0 * clampf(b.life / (b.max * 0.4), 0.0, 1.0)
		if b.life <= 0.0:
			_bits.remove_at(i)
			n.queue_free()


func active_count() -> int:
	return _items.size() + _bits.size()


func clear() -> void:
	for it in _items:
		(it.node as Node).queue_free()
	for b in _bits:
		(b.node as Node).queue_free()
	_items.clear()
	_bits.clear()


func floating_text(at: Vector3, text: String, color: Color, size := 64, life := 1.1) -> void:
	var l := Palette.label3d(text, size, color)
	l.position = at
	add_child(l)
	_items.append({"node": l, "life": life, "max": life, "kind": "text", "y0": at.y})


func tracer(from: Vector3, to: Vector3, color: Color, life := 0.35) -> void:
	var length := from.distance_to(to)
	if length < 0.01:
		return
	var m := Palette.overlay(Color(color, 0.95))
	var beam := Palette.box(Vector3(0.035, 0.035, length), m)
	add_child(beam)
	beam.position = (from + to) * 0.5
	beam.basis = Basis.looking_at(to - from, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	_items.append({"node": beam, "life": life, "max": life, "kind": "fade", "mat": m, "a0": 0.95})


func muzzle_flash(at: Vector3, color := Color(1.0, 0.8, 0.45)) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.0
	light.omni_range = 3.0
	light.position = at
	add_child(light)
	_items.append({"node": light, "life": 0.18, "max": 0.18, "kind": "light", "e0": 4.0})
	var m := Palette.overlay(Color(color, 0.9))
	var spark := Palette.box(Vector3(0.18, 0.18, 0.18), m)
	spark.position = at
	add_child(spark)
	_items.append({"node": spark, "life": 0.12, "max": 0.12, "kind": "fade", "mat": m, "a0": 0.9})


func pulse(at: Vector3, color: Color, life := 0.7) -> void:
	var m := Palette.emissive(color, 4.0)
	var r := Palette.ring(0.4, 0.5, m)
	r.position = at + Vector3(0, 0.05, 0)
	add_child(r)
	_items.append({"node": r, "life": life, "max": life, "kind": "ring", "mat": m})


## A glowing round, placed by the caller each frame with `place_bullet` (so its
## flight follows the shot cinematic's clock, slow motion included). Free with `remove`.
func spawn_bullet(color: Color, big := false) -> Node3D:
	var root := Node3D.new()
	var m := Palette.emissive(color, 9.0)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color.lightened(0.5)
	var core := Palette.box(Vector3(0.05, 0.05, 0.55) * (1.8 if big else 1.0), m)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	var trail_m := Palette.overlay(Color(color, 0.35))
	var trail := Palette.box(Vector3(0.025, 0.025, 2.2), trail_m)
	trail.position.z = 1.2
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(trail)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.5
	light.omni_range = 2.5
	root.add_child(light)
	add_child(root)
	return root


func place_bullet(b: Node3D, from: Vector3, to: Vector3, k: float) -> void:
	if b == null:
		return
	b.position = from.lerp(to, k)
	var d := to - from
	if d.length() > 0.01:
		b.basis = Basis.looking_at(d, Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT)
	# Trail only stretches back over the distance already flown.
	var trail := b.get_child(1) as Node3D
	var flown := clampf(d.length() * k, 0.0, 2.2)
	trail.scale.z = maxf(0.01, flown / 2.2)
	trail.position.z = flown * 0.5


func remove(n: Node) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()


## Spray of chips flying out along `normal`: sparks, ichor, blood, concrete.
func burst(at: Vector3, normal: Vector3, color: Color, count := 14, speed := 4.0, glow := false, size := 0.05) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(at) ^ count
	for i in count:
		var m := Palette.emissive(color, 5.0) if glow else Palette.mat(color, 0.6)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var s := size * rng.randf_range(0.6, 1.4)
		var chip := Palette.box(Vector3(s, s, s * rng.randf_range(1.0, 2.5)), m)
		chip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chip.position = at
		add_child(chip)
		var dir := (normal + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.2, 1.0), rng.randf_range(-0.8, 0.8))).normalized()
		var life := rng.randf_range(0.5, 1.1)
		_bits.append({"node": chip, "vel": dir * speed * rng.randf_range(0.4, 1.2), "life": life, "max": life,
			"mat": m, "a0": 1.0, "spin": Vector3(rng.randf(), rng.randf(), rng.randf()) * 12.0,
			"floor": 0.02, "grav": 1.0, "drag": 1.5})


## Soft expanding cloud (dust, smoke, spore mist): a camera-facing quad with a
## radial falloff, so it reads as smoke rather than a solid ball.
func puff(at: Vector3, color: Color, size := 0.5, life := 0.9, rise := 0.4) -> void:
	var m := Palette.overlay(Color(color, 0.45))
	m.albedo_texture = _soft_dot()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.cull_mode = BaseMaterial3D.CULL_BACK
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	mi.scale = Vector3.ONE * size * 0.6
	add_child(mi)
	_items.append({"node": mi, "life": life, "max": life, "kind": "puff", "mat": m, "a0": 0.45,
		"s0": size * 0.6, "grow": size * 1.2, "y0": at.y, "rise": rise})


static var _dot: Texture2D


static func _soft_dot() -> Texture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 64
		tex.height = 64
		_dot = tex
	return _dot


## Brass casing ejected to the right of the shooter.
func casing(at: Vector3, right: Vector3) -> void:
	var m := Palette.mat(Color("b8923f"), 0.3, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var c := Palette.box(Vector3(0.02, 0.02, 0.06), m)
	c.position = at
	add_child(c)
	_bits.append({"node": c, "vel": (right * 2.0 + Vector3.UP * 2.2), "life": 1.6, "max": 1.6, "mat": m,
		"a0": 1.0, "spin": Vector3(20, 9, 4), "floor": 0.02, "grav": 1.0, "drag": 0.5})


## Lasting splat on the floor (scorch, ichor, blood). Oldest go first past MAX_DECALS.
func decal(at: Vector3, color: Color, radius := 0.35, glow := false) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.01
	mesh.radial_segments = 14
	var m := Palette.emissive(color, 1.2) if glow else Palette.mat(color, 0.3)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.85
	var d := MeshInstance3D.new()
	d.mesh = mesh
	d.material_override = m
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	d.position = Vector3(at.x, 0.012 + _decals.size() * 0.0002, at.z)
	d.scale = Vector3(1.0, 1.0, 0.7 + fposmod(at.x * 7.3 + at.z * 3.1, 0.6))
	d.rotation.y = fposmod(at.x * 13.0 + at.z * 5.0, TAU)
	add_child(d)
	_decals.append(d)
	if _decals.size() > MAX_DECALS:
		_decals.pop_front().queue_free()


## Bright flash of light at a point, for impacts and explosions.
func flash_light(at: Vector3, color: Color, energy := 5.0, life := 0.25, light_range := 4.0) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.position = at
	add_child(light)
	_items.append({"node": light, "life": life, "max": life, "kind": "light", "e0": energy})
