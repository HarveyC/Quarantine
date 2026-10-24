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


## Muzzle flash: a light, a hot core and flame petals blown out along `dir` (the barrel).
## `size` scales it per weapon, `style` shapes it (see view/gun_feel.gd "flash_style").
func muzzle_flash(at: Vector3, color := Color(1.0, 0.8, 0.45), dir := Vector3.ZERO, size := 1.0, style := "star") -> void:
	if size <= 0.0:
		return
	if style == "gas":
		# Pneumatic: no fire at all, just a cold puff of gas from the barrel.
		puff(at + dir.normalized() * 0.15, Color(0.85, 0.9, 0.92), 0.35 * size + 0.15, 0.5, 0.1)
		puff(at + dir.normalized() * 0.4, Color(0.85, 0.9, 0.92), 0.25 * size + 0.1, 0.4, 0.05)
		return
	var quiet := style == "quiet"
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.0 * size * (0.4 if quiet else 1.0)
	light.omni_range = 2.5 + 1.5 * size
	light.position = at
	add_child(light)
	_items.append({"node": light, "life": 0.12, "max": 0.12, "kind": "light", "e0": light.light_energy})
	var core := _flash_quad(Color(1.0, 0.95, 0.8) if style != "bio" else color.lightened(0.4),
		Vector2(0.32, 0.32) * size * (0.5 if quiet else 1.0), true)
	core.position = at + dir * 0.05
	add_child(core)
	var core_life := 0.16 if style == "bio" else 0.07
	_items.append({"node": core, "life": core_life, "max": core_life, "kind": "fade", "mat": core.material_override, "a0": 1.0})
	if dir.length() < 0.01 or quiet:
		return
	dir = dir.normalized()
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var side := dir.cross(up).normalized()
	match style:
		"bio":
			# A soft bloom of spores instead of fire.
			burst(at + dir * 0.1, dir, color, 8, 2.2, true, 0.025)
			puff(at + dir * 0.45, color.darkened(0.5), 0.12 * size, 0.4, 0.05)
			return
		"brake":
			# The muzzle brake throws most of the blast out to the sides.
			for sgn in [-1.0, 1.0]:
				var b := _flash_quad(color, Vector2(0.3, 0.8) * size, false)
				var bd: Vector3 = (side * sgn + dir * 0.15).normalized()
				b.basis = Basis.looking_at(bd, up) * Basis(Vector3.RIGHT, -PI * 0.5)
				b.position = at + bd * 0.35 * size
				add_child(b)
				_items.append({"node": b, "life": 0.08, "max": 0.08, "kind": "fade", "mat": b.material_override, "a0": 1.0})
				puff(at + bd * 0.6, Color(0.62, 0.6, 0.55), 0.7, 0.9, 0.2)
	# Crossed petals along the barrel (a wide fan for shotguns), plus a short star of side vents.
	var petals := 4 if style == "cone" else 2
	var petal := Vector2(0.28, 0.5) if style == "cone" else (Vector2(0.14, 0.34) if style == "brake" else Vector2(0.16, 0.62))
	for i in petals:
		var p := _flash_quad(color.lightened(0.2), petal * size, false)
		p.basis = Basis.looking_at(dir, up).rotated(dir, PI / petals * i) * Basis(Vector3.RIGHT, -PI * 0.5)
		p.position = at + dir * 0.3 * size
		add_child(p)
		_items.append({"node": p, "life": 0.06, "max": 0.06, "kind": "fade", "mat": p.material_override, "a0": 0.95})
	for sgn in [-1.0, 1.0]:
		var v := _flash_quad(color, Vector2(0.1, 0.26) * size, false)
		var d: Vector3 = (side * sgn + dir * 0.4).normalized()
		v.basis = Basis.looking_at(d, up) * Basis(Vector3.RIGHT, -PI * 0.5)
		v.position = at + d * 0.12 * size
		add_child(v)
		_items.append({"node": v, "life": 0.05, "max": 0.05, "kind": "fade", "mat": v.material_override, "a0": 0.85})
	if style == "cone":
		# Burning powder sparks thrown out ahead of the pellets.
		burst(at + dir * 0.2, dir * 2.0, Color(1.0, 0.75, 0.35), 10, 5.0, true, 0.018)


func _flash_quad(color: Color, size: Vector2, billboard: bool) -> MeshInstance3D:
	var m := Palette.overlay(Color(color, 1.0))
	m.albedo_texture = _soft_dot()
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var mesh := QuadMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A thin smoke line left hanging along a heavy round's path.
func smoke_trail(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.01:
		return
	var m := Palette.overlay(Color(0.75, 0.75, 0.72, 0.28))
	var beam := Palette.box(Vector3(0.05, 0.05, length), m)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	beam.position = (from + to) * 0.5
	beam.basis = Basis.looking_at(to - from, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	_items.append({"node": beam, "life": 1.4, "max": 1.4, "kind": "fade", "mat": m, "a0": 0.28})


## Scorched bullet hole on a surface facing `normal` (cover, walls). Shares the decal cap.
func bullet_hole(at: Vector3, normal: Vector3, size := 0.07) -> void:
	var m := Palette.overlay(Color(0.06, 0.05, 0.04, 0.9))
	m.albedo_texture = _soft_dot()
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * size * 2.0
	var d := MeshInstance3D.new()
	d.mesh = mesh
	d.material_override = m
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var n := normal.normalized()
	d.basis = Basis.looking_at(-n, Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT)
	d.position = at + n * 0.012
	add_child(d)
	_decals.append(d)
	if _decals.size() > MAX_DECALS:
		_decals.pop_front().queue_free()


func pulse(at: Vector3, color: Color, life := 0.7) -> void:
	var m := Palette.emissive(color, 4.0)
	var r := Palette.ring(0.4, 0.5, m)
	r.position = at + Vector3(0, 0.05, 0)
	add_child(r)
	_items.append({"node": r, "life": life, "max": life, "kind": "ring", "mat": m})


## A glowing round, placed by the caller each frame with `place_bullet` (so its
## flight follows the shot cinematic's clock, slow motion included). Free with `remove`.
## `size` scales the round (1.0 = rifle); `lit` = false skips the light (shotgun pellets).
func spawn_bullet(color: Color, big := false, size := 1.0, lit := true) -> Node3D:
	return spawn_round("tracer", color, 1.8 if big else size, lit)


## A round of a given style (see view/gun_feel.gd "proj"). Child 0 is the round itself,
## child 1 its trail (stretched by place_bullet); metas tune the flight:
## "trail" (length), "arc" (lob height share), "wobble" (pulsing glob), "drip" (puffs left behind).
func spawn_round(style: String, color: Color, size := 1.0, lit := true) -> Node3D:
	var root := Node3D.new()
	var core: MeshInstance3D
	var trail_len := 2.2 * minf(1.0, size)
	var trail_w := 0.018
	var trail_a := 0.3
	var light_e := 2.5
	match style:
		"heavy":
			core = Palette.box(Vector3(0.08, 0.08, 0.8) * size, _hot(color, 12.0))
			trail_len = 3.6 * minf(1.3, size)
			trail_w = 0.04 * size
			trail_a = 0.38
			light_e = 4.0
		"ball":
			# Plain rounds between an LMG's tracers: a faint dash, no light.
			core = Palette.box(Vector3(0.035, 0.035, 0.4) * size, _hot(color.darkened(0.15), 6.0))
			trail_len = 0.9
			trail_w = 0.012
			trail_a = 0.2
			lit = false
		"pellet":
			core = Palette.box(Vector3(0.045, 0.045, 0.06) * size, _hot(color, 10.0))
			trail_len = 0.5
			trail_w = 0.012
			trail_a = 0.35
		"slug":
			core = Palette.box(Vector3(0.11, 0.11, 0.22) * size, _hot(color, 12.0))
			trail_len = 1.1
			trail_w = 0.06
			trail_a = 0.32
			light_e = 4.5
			root.set_meta("drip", Color(0.7, 0.68, 0.62))
		"flechette":
			core = Palette.box(Vector3(0.012, 0.012, 0.55) * size, _hot(color, 14.0))
			trail_len = 1.8
			trail_w = 0.006
			trail_a = 0.5
			lit = false
		"bio", "spore":
			var r := (0.09 if style == "bio" else 0.15) * size
			core = _glob(color, r)
			var halo := _flash_quad(color, Vector2.ONE * r * 5.0, true)
			halo.material_override.albedo_color.a = 0.55
			core.add_child(halo)
			trail_len = 0.01
			light_e = 3.0
			root.set_meta("wobble", true)
			root.set_meta("drip", color)
		"dart":
			core = Palette.box(Vector3(0.022, 0.022, 0.34) * size, Palette.mat(Color(0.25, 0.27, 0.28), 0.4, 0.6))
			var tip := Palette.box(Vector3(0.03, 0.03, 0.07) * size, _hot(color, 10.0))
			tip.position.z = -0.19 * size
			core.add_child(tip)
			for i in 2:
				var fin := Palette.box(Vector3(0.11, 0.004, 0.08) * size, _hot(color.lightened(0.3), 3.0))
				fin.position.z = 0.15 * size
				fin.rotation.z = PI * 0.5 * i
				core.add_child(fin)
			trail_len = 0.8
			trail_w = 0.008
			trail_a = 0.22
			light_e = 1.2
		"bolt":
			# An electric slug: a crackling core that leaves arcs hanging behind it.
			core = _glob(color, 0.06 * size)
			var halo2 := _flash_quad(color, Vector2.ONE * 0.4 * size, true)
			core.add_child(halo2)
			trail_len = 1.4
			trail_w = 0.02
			trail_a = 0.6
			light_e = 3.5
			root.set_meta("wobble", true)
			root.set_meta("arcs", color)
		_:
			core = Palette.box(Vector3(0.05, 0.05, 0.55) * size, _hot(color, 9.0))
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	var trail_m := Palette.overlay(Color(color, trail_a))
	trail_m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD   # a streak of light, not a grey slab
	var trail := Palette.box(Vector3(trail_w, trail_w, trail_len), trail_m)
	trail.position.z = trail_len * 0.55
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(trail)
	root.set_meta("trail", trail_len)
	if lit:
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = light_e
		light.omni_range = 2.5
		root.add_child(light)
	add_child(root)
	return root


func _hot(color: Color, energy: float) -> StandardMaterial3D:
	var m := Palette.emissive(color, energy)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color.lightened(0.5)
	return m


## A glowing glob: a white-hot, camera-facing core (bio rounds, spore, shock bolts).
func _glob(color: Color, r: float) -> MeshInstance3D:
	var mi := _flash_quad(Color.WHITE.lerp(color, 0.35), Vector2.ONE * r * 2.6, true)
	mi.material_override.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	return mi


## Moves a round `k` (0..1) of the way from `from` to `to`, along a lob if it has an "arc".
func place_bullet(b: Node3D, from: Vector3, to: Vector3, k: float) -> void:
	if b == null or not is_instance_valid(b):
		return
	var d := to - from
	var arc: float = b.get_meta("arc", 0.0) * d.length()
	b.position = from.lerp(to, k) + Vector3.UP * arc * 4.0 * k * (1.0 - k)
	var heading := d + Vector3.UP * arc * 4.0 * (1.0 - 2.0 * k)
	if heading.length() > 0.01:
		b.basis = Basis.looking_at(heading, Vector3.UP if absf(heading.normalized().y) < 0.99 else Vector3.RIGHT)
	# Trail only stretches back over the distance already flown.
	var trail := b.get_child(1) as Node3D
	var trail_len: float = b.get_meta("trail", 2.2)
	var flown := clampf(d.length() * k, 0.0, trail_len)
	trail.scale.z = maxf(0.01, flown / trail_len)
	trail.position.z = flown * 0.5
	if b.get_meta("wobble", false):
		var w := 1.0 + 0.22 * sin(k * 46.0)
		(b.get_child(0) as Node3D).scale = Vector3(w, 1.0 / w, w)
	# Leave something hanging along the path every so often: spore puffs, slug smoke, arcs.
	var last: Vector3 = b.get_meta("last_drop", from)
	# (Not right at the muzzle, where it would fog the over-the-shoulder shot camera.)
	if b.position.distance_to(last) > 0.45 and k > 0.0 and b.position.distance_to(from) > 1.2:
		b.set_meta("last_drop", b.position)
		if b.has_meta("drip"):
			# Dropped a little behind the round so the cloud never covers it.
			var c: Color = b.get_meta("drip")
			puff(b.position.lerp(last, 0.6), c.darkened(0.2) if c.v > 0.6 else c, 0.14, 0.6, 0.12)
		if b.has_meta("arcs"):
			spark_arc(last, b.position, b.get_meta("arcs"))


## A jagged electric arc between two points that flickers out.
func spark_arc(from: Vector3, to: Vector3, color: Color, life := 0.18) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(from) ^ hash(to)
	var p := from
	for i in 4:
		var q := from.lerp(to, float(i + 1) / 4.0)
		if i < 3:
			q += Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.08, 0.08), rng.randf_range(-0.08, 0.08))
		tracer(p, q, color.lightened(0.3), life)
		p = q


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


## Spent casing ejected to the right of the shooter: "brass", "big" (heavy calibre brass),
## "shell" (a red shotgun hull), "link" (brass plus a belt link) or "cell" (a glowing bio cell).
func casing(at: Vector3, right: Vector3, kind := "brass") -> void:
	var size := Vector3(0.02, 0.02, 0.06)
	var m := Palette.mat(Color("b8923f"), 0.3, 0.9)
	var vel := right * 2.0 + Vector3.UP * 2.2
	var spin := Vector3(20, 9, 4)
	match kind:
		"big":
			size = Vector3(0.032, 0.032, 0.12)
			vel = right * 1.6 + Vector3.UP * 2.0
			spin = Vector3(12, 6, 3)
		"shell":
			size = Vector3(0.036, 0.036, 0.09)
			m = Palette.mat(Color("8c2a22"), 0.6)
			vel = right * 1.8 + Vector3.UP * 2.6
			spin = Vector3(10, 7, 2)
		"cell":
			size = Vector3(0.03, 0.03, 0.05)
			m = Palette.emissive(Color(0.62, 1.0, 0.45), 3.0)
			vel = right * 1.4 + Vector3.UP * 1.8
		"link":
			_eject(at, Vector3(0.03, 0.006, 0.02), Palette.mat(Color(0.2, 0.2, 0.2), 0.5, 0.8),
				right * 1.2 + Vector3.UP * 1.0, Vector3(6, 14, 3))
	_eject(at, size, m, vel, spin)


func _eject(at: Vector3, size: Vector3, m: StandardMaterial3D, vel: Vector3, spin: Vector3) -> void:
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var c := Palette.box(size, m)
	c.position = at
	c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(c)
	_bits.append({"node": c, "vel": vel, "life": 1.6, "max": 1.6, "mat": m,
		"a0": 1.0, "spin": spin, "floor": 0.02, "grav": 1.0, "drag": 0.5})


## A spent dart left stuck in a surface, pointing back along `dir`. Shares the decal cap.
func stuck_dart(at: Vector3, dir: Vector3, color: Color) -> void:
	var root := Node3D.new()
	var body := Palette.box(Vector3(0.02, 0.02, 0.28), Palette.mat(Color(0.25, 0.27, 0.28), 0.4, 0.6))
	body.position.z = 0.12
	root.add_child(body)
	var fin := Palette.box(Vector3(0.09, 0.004, 0.07), Palette.emissive(color, 1.5))
	fin.position.z = 0.24
	root.add_child(fin)
	add_child(root)
	root.position = at
	var d := dir.normalized()
	if d.length() > 0.01:
		root.basis = Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.99 else Vector3.RIGHT)
	_decals.append(root)
	if _decals.size() > MAX_DECALS:
		_decals.pop_front().queue_free()


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
