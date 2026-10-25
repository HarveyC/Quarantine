extends RefCounted
## Face-cover study (exploration only, not wired into the game): props that hide the faces of
## NPC models, built as noise-displaced ellipsoid patches plus a few primitives and hung on the
## Head bone like GraftKit's props. Head bone frame: +Y up, +Z out of the face; the eye line is
## near y = 0.10, the chin near y = -0.02, the face front near z = 0.105.
##
## Four options (see OPTIONS): growth, mask, cowl, wrap. `dress(model, kind, option)` hangs the
## right props for one kind; "shade" is a shader-only variant for bare faces.

const GunModels := preload("res://view/gun_models.gd")

const OPTIONS := ["growth", "mask", "cowl", "wrap"]

const HC := Vector3(0.0, 0.1, 0.01)           # head centre
const HR := Vector3(0.092, 0.118, 0.108)     # head radii

const LEAN := ["runner", "spitter", "leaper", "broodling", "shrieker", "bloater", "brood_mother"]
const SOLDIERLY := ["fallen", "colonel_hale", "sharpshooter"]

# role: [albedo, metallic, roughness, emission or null]
const LOOK := {
	"flesh_raw": [Color("6a3c3a"), 0.0, 0.7, null],
	"glow": [Color("2ef2c8"), 0.0, 0.5, null],
	"chitin": [Color("4a4338"), 0.0, 0.55, null],
	"rubber": [Color("1b1d1c"), 0.0, 0.8, null],
	"filter": [Color("3b3f3c"), 0.5, 0.45, null],
	"strap": [Color("2a2723"), 0.0, 0.9, null],
	"wrap": [Color("a89c82"), 0.0, 0.95, null],
	"stain": [Color("5e4630"), 0.0, 1.0, null],
	"cowl": [Color("2b2f27"), 0.0, 0.95, null],
	"void": [Color("040505"), 0.0, 1.0, null],
	"glass": [Color("0e1717"), 0.55, 0.22, null],
	"scarf": [Color("5b4a3a"), 0.0, 1.0, null],
	"lens": [Color("0d2a29"), 0.0, 0.3, Color("0d4d44")],
}


# --- builder ----------------------------------------------------------------------------

class B:
	var st := {}
	var seed_n := 1

	func tool(role: String) -> SurfaceTool:
		if not st.has(role):
			var s := SurfaceTool.new()
			s.begin(Mesh.PRIMITIVE_TRIANGLES)
			st[role] = s
		return st[role]

	func mesh() -> ArrayMesh:
		var m := ArrayMesh.new()
		for role in st:
			var s: SurfaceTool = st[role]
			s.generate_normals()
			s.commit(m)
			var mat := StandardMaterial3D.new()
			mat.resource_name = role
			var look: Array = LOOK.get(role, [Color(0.3, 0.3, 0.3), 0.0, 0.8, null])
			mat.albedo_color = look[0]
			mat.metallic = look[1]
			mat.roughness = look[2]
			if look[3] != null:
				mat.emission_enabled = true
				mat.emission = look[3]
			m.surface_set_material(m.get_surface_count() - 1, mat)
		return m


## A patch of an ellipsoid: lon runs round the head (0 = the face, +PI/-PI = the back), lat from
## the underside (-PI/2) over the top (PI/2). `amp` lumps the surface with noise.
static func patch(b: B, role: String, c: Vector3, r: Vector3, lon := Vector2(-PI, PI), lat := Vector2(-PI / 2, PI / 2),
		amp := 0.0, freq := 10.0, basis := Basis.IDENTITY, nx := 44, ny := 26) -> void:
	var nz := FastNoiseLite.new()
	b.seed_n += 1
	nz.seed = b.seed_n * 7919
	nz.frequency = 1.0
	var full := lon.y - lon.x >= TAU - 0.01
	var cols := nx if full else nx + 1
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in ny + 1:
		var phi := lerpf(lat.x, lat.y, float(j) / ny)
		for i in cols:
			var th := lerpf(lon.x, lon.y, float(i) / nx)
			var d := Vector3(cos(phi) * sin(th), sin(phi), cos(phi) * cos(th))
			var k := 1.0 + amp * nz.get_noise_3d(d.x * freq * 0.3, d.y * freq * 0.3, d.z * freq * 0.3)
			s.add_vertex(c + basis * (d * r * k))
	for j in ny:
		for i in nx:
			var i2 := (i + 1) % cols if full else i + 1
			var a := j * cols + i
			var bb := j * cols + i2
			var cc := (j + 1) * cols + i
			var dd := (j + 1) * cols + i2
			for idx in [a, cc, bb, bb, cc, dd]:
				s.add_index(idx)
	s.generate_normals()
	b.tool(role).append_from(s.commit(), 0, Transform3D.IDENTITY)


static func ball(b: B, role: String, c: Vector3, rad: float, squash := Vector3.ONE, amp := 0.0) -> void:
	patch(b, role, c, squash * rad, Vector2(-PI, PI), Vector2(-PI / 2, PI / 2), amp, 12.0, Basis.IDENTITY, 14, 8)


static func tube(b: B, role: String, a: Vector3, e: Vector3, rad: float, rad2 := -1.0) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = rad if rad2 < 0.0 else rad2
	cyl.bottom_radius = rad
	cyl.height = a.distance_to(e)
	cyl.radial_segments = 8
	cyl.rings = 1
	var xf := Transform3D(GunModels._y_to((e - a).normalized()), (a + e) * 0.5)
	b.tool(role).append_from(cyl, 0, xf)


static func shard(b: B, role: String, base: Vector3, dir: Vector3, length: float, width: float) -> void:
	tube(b, role, base, base + dir.normalized() * length, width, 0.0)


static func box(b: B, role: String, c: Vector3, size: Vector3, euler := Vector3.ZERO) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	b.tool(role).append_from(bm, 0, Transform3D(Basis.from_euler(euler), c))


# --- pieces ------------------------------------------------------------------------------

## Bloom swallowing the face: a lumpy mass, seeds of glow, crystals at the brow.
static func fungal_face(b: B, rnd: RandomNumberGenerator, big := 1.0, eyes := true, half := 0) -> void:
	var lon := Vector2(-1.35, 1.35)
	if half != 0:
		lon = Vector2(-0.15, 1.5) if half > 0 else Vector2(-1.5, 0.15)
	patch(b, "flesh_raw", HC + Vector3(0, -0.012, 0.012), HR * Vector3(1.14, 1.1, 1.13) * big, lon, Vector2(-1.05, 0.8), 0.2, 11.0)
	for i in 6:
		var a := rnd.randf_range(-1.0, 1.0) + (0.0 if half == 0 else float(half) * 0.7)
		var y := rnd.randf_range(0.01, 0.17)
		var p := Vector3(sin(a) * 0.095, y, cos(a) * 0.115) * big
		ball(b, "flesh_raw", p, rnd.randf_range(0.022, 0.04), Vector3(1, 0.9, 1), 0.2)
	for i in 3:
		var a := rnd.randf_range(-0.9, 0.9) + (0.0 if half == 0 else float(half) * 0.6)
		var p := Vector3(sin(a) * 0.1, rnd.randf_range(0.02, 0.15), cos(a) * 0.12) * big
		tube(b, "glow", p, p + Vector3(rnd.randf_range(-0.05, 0.05), rnd.randf_range(-0.07, 0.03), 0.03), 0.006)
	if eyes:
		for s in [-1, 1]:
			box(b, "glow", Vector3(0.04 * s, 0.108, 0.122 * big), Vector3(0.034, 0.011, 0.01), Vector3(0, 0, -0.25 * s))
	for i in 4:
		var x := rnd.randf_range(-0.07, 0.07)
		shard(b, "glow", Vector3(x, 0.19 * big, 0.06), Vector3(x * 5.0, 1.0, 0.5 + rnd.randf_range(-0.2, 0.4)), rnd.randf_range(0.07, 0.13), 0.014)


## A Harrow dust respirator: rubber shell, two round lenses, a snout and filter canisters, a strap.
## `ruin` 0..1 tears it open and lets the Bloom through.
static func respirator(b: B, rnd: RandomNumberGenerator, ruin := 0.0, lens_role := "lens", big := 1.0) -> void:
	var lon := Vector2(-1.4, 1.4) if ruin < 0.5 else Vector2(-1.4, 0.55)
	patch(b, "rubber", HC + Vector3(0, -0.015, 0.012), HR * Vector3(1.12, 1.07, 1.1) * big, lon, Vector2(-1.15, 0.5), 0.015, 8.0)
	for s in [-1, 1]:
		if ruin >= 0.5 and s > 0:
			continue
		tube(b, "filter", Vector3(0.042 * s, 0.1, 0.1) * big, Vector3(0.042 * s, 0.1, 0.122) * big, 0.03)
		tube(b, lens_role, Vector3(0.042 * s, 0.1, 0.12) * big, Vector3(0.042 * s, 0.1, 0.128) * big, 0.023)
	ball(b, "rubber", Vector3(0, 0.035, 0.1) * big, 0.05, Vector3(1.2, 0.85, 0.9))
	tube(b, "filter", Vector3(0, 0.03, 0.115) * big, Vector3(0, 0.03, 0.155) * big, 0.027)
	for s in [-1, 1]:
		tube(b, "filter", Vector3(0.07 * s, 0.01, 0.09) * big, Vector3(0.08 * s, 0.0, 0.125) * big, 0.027)
	patch(b, "strap", HC + Vector3(0, 0.015, 0), HR * Vector3(1.14, 0.2, 1.13) * big, Vector2(-PI, PI), Vector2(-PI / 2, PI / 2), 0.0, 1.0, Basis.IDENTITY, 24, 4)
	if ruin > 0.0:
		patch(b, "flesh_raw", HC + Vector3(0.05, -0.01, 0.04), HR * Vector3(0.9, 1.0, 0.9), Vector2(0.4, 1.7), Vector2(-0.9, 0.9), 0.3, 11.0)
		for i in 3:
			ball(b, "flesh_raw", Vector3(0.06 + rnd.randf_range(0, 0.04), 0.03 + i * 0.05, 0.1), 0.026, Vector3.ONE, 0.2)
		box(b, "glow", Vector3(0.06, 0.1, 0.12), Vector3(0.03, 0.01, 0.01), Vector3(0, 0, 0.2))
		tube(b, "glow", Vector3(0.0, 0.0, 0.14), Vector3(0.05, 0.06, 0.13), 0.006)


## A cloth cowl pulled forward; the face behind it is a pool of shadow with eyes in it.
static func cowl(b: B, rnd: RandomNumberGenerator, depth := 1.0, size := 1.0, eye_glow := true, torn := false) -> void:
	var open := 0.78 + (1.0 - depth) * 0.3
	patch(b, "cowl", HC + Vector3(0, 0.0, -0.02), HR * Vector3(1.4, 1.26, 1.32) * size, Vector2(open, TAU - open), Vector2(-0.75, 1.5), 0.06, 7.0)
	patch(b, "cowl", HC + Vector3(0, -0.075, 0.0), Vector3(0.13, 0.05, 0.12) * size, Vector2(-PI, PI), Vector2(-0.2, 1.5), 0.05, 6.0)   # drape over the shoulders
	# shadow inside
	patch(b, "void", HC + Vector3(0, -0.005, 0.0), HR * Vector3(1.04, 1.02, 1.03), Vector2(-1.05, 1.05), Vector2(-1.1, 1.0), 0.0, 1.0)
	if eye_glow:
		for s in [-1, 1]:
			box(b, "glow", Vector3(0.036 * s, 0.108, 0.112), Vector3(0.026, 0.008, 0.008), Vector3(0, 0, -0.2 * s))
	if torn:
		for i in 4:
			var x := -0.09 + i * 0.06
			box(b, "cowl", Vector3(x, 0.22 - i * 0.01, -0.12), Vector3(0.025, 0.1, 0.012), Vector3(0.1, 0, rnd.randf_range(-0.2, 0.2)))


## Bandage layers wound round the head; a slit at the eyes shows a glimmer.
static func bandage(b: B, rnd: RandomNumberGenerator, mouth_open := false, trail := 1.0, eyes := true) -> void:
	var n := 7
	for i in n:
		var l0 := lerpf(-0.95, 1.0, float(i) / n)
		var l1 := l0 + 0.5
		var tilt := Basis.from_euler(Vector3(rnd.randf_range(-0.14, 0.14), 0, rnd.randf_range(-0.16, 0.16)))
		var rr := 1.1 + 0.035 * (i % 2)
		var role := "wrap" if i % 3 != 2 else "stain"
		var eye_band := l0 > -0.05 and l0 < 0.35
		var lon := Vector2(-PI, PI)
		if eye_band:
			lon = Vector2(0.3, TAU - 0.3)
		elif mouth_open and l0 < -0.2:
			lon = Vector2(0.55, TAU - 0.55)
		patch(b, role, HC + Vector3(0, 0, 0.005), HR * rr, lon, Vector2(l0, minf(l1, 1.55)), 0.02, 12.0, tilt, 30, 5)
	patch(b, "wrap", HC + Vector3(0, 0.0, 0.005), HR * 1.12, Vector2(-PI, PI), Vector2(1.0, PI / 2), 0.02, 12.0, Basis.from_euler(Vector3(0.1, 0, 0.08)), 30, 6)
	patch(b, "void", HC + Vector3(0, 0, 0.0), HR * Vector3(1.04, 1.02, 1.03), Vector2(-0.55, 0.55), Vector2(-0.1, 0.4), 0.0, 1.0)
	if eyes:
		for s in [-1, 1]:
			box(b, "glow", Vector3(0.037 * s, 0.108, 0.113), Vector3(0.028, 0.008, 0.008), Vector3(0, 0, -0.18 * s))
	if mouth_open:
		patch(b, "void", HC + Vector3(0, -0.07, 0.01), Vector3(0.05, 0.05, 0.08), Vector2(-0.6, 0.6), Vector2(-0.6, 0.6), 0.0, 1.0)
		patch(b, "glow", HC + Vector3(0, -0.075, 0.005), Vector3(0.03, 0.03, 0.08), Vector2(-0.5, 0.5), Vector2(-0.5, 0.5), 0.0, 1.0)
	for i in int(5 * trail):
		var a := rnd.randf_range(1.6, 4.6)
		var p := Vector3(sin(a) * 0.12, 0.08 + rnd.randf_range(0, 0.1), cos(a) * 0.12)
		box(b, "wrap" if i % 2 == 0 else "stain", p + Vector3(0, -0.07 * trail, 0), Vector3(0.028, 0.14 * trail + rnd.randf_range(0, 0.06), 0.008), Vector3(rnd.randf_range(-0.3, 0.3), a, rnd.randf_range(-0.25, 0.25)))


## A cracked glass faceplate under the helmet, with a hole where the Bloom comes through.
static func cracked_visor(b: B, rnd: RandomNumberGenerator, big := 1.0, hole := true) -> void:
	patch(b, "glass", HC + Vector3(0, -0.01, 0.012), HR * Vector3(1.13, 1.1, 1.13) * big, Vector2(-1.25, 1.25), Vector2(-1.0, 0.7), 0.0, 1.0)
	patch(b, "filter", HC + Vector3(0, -0.01, 0.012), HR * Vector3(1.16, 1.13, 1.15) * big, Vector2(-1.32, 1.32), Vector2(-1.1, -0.95), 0.0, 1.0, Basis.IDENTITY, 24, 2)   # rim
	var pt := Vector3(0.025, 0.12, 0.13) * big
	for i in 7:
		var a := float(i) / 7.0 * TAU + rnd.randf_range(-0.2, 0.2)
		var p := pt
		for k in 3:
			var dir := Vector3(cos(a + rnd.randf_range(-0.5, 0.5)), sin(a + rnd.randf_range(-0.5, 0.5)) * 0.9, -0.05)
			var e := p + dir.normalized() * rnd.randf_range(0.02, 0.04)
			e.z = 0.13 - absf(e.x) * 0.12 - absf(e.y - 0.1) * 0.1
			tube(b, "glow", p, e, 0.0032)
			p = e
	if hole:
		ball(b, "flesh_raw", pt + Vector3(0.0, -0.01, -0.01), 0.032, Vector3(1.1, 0.9, 0.8), 0.25)
		for i in 3:
			shard(b, "glow", pt + Vector3(0, -0.005, 0.0), Vector3(rnd.randf_range(-0.7, 0.7), 0.2, 1.0), 0.055 + i * 0.012, 0.011)


## A grown bone helm over the brow and cheeks with one slit to see through.
static func chitin_helm(b: B, rnd: RandomNumberGenerator, big := 1.0) -> void:
	patch(b, "chitin", HC + Vector3(0, 0.0, 0.01), HR * Vector3(1.2, 1.16, 1.18) * big, Vector2(-1.9, 1.9), Vector2(-0.55, 1.35), 0.08, 8.0)
	patch(b, "void", HC + Vector3(0, 0.0, 0.0), HR * Vector3(1.08, 1.05, 1.08) * big, Vector2(-0.9, 0.9), Vector2(-0.2, 0.3), 0.0, 1.0)
	box(b, "glow", Vector3(0, 0.1, 0.133) * big, Vector3(0.1, 0.012, 0.01) * big)
	for i in 3:
		var x := -0.06 + i * 0.06
		shard(b, "chitin", Vector3(x, 0.2, 0.0) * big, Vector3(0.0, 1.0, -0.4 - i % 2 * 0.3), 0.13 + (i % 2) * 0.06, 0.03)
	for s in [-1, 1]:
		shard(b, "chitin", Vector3(0.11 * s, 0.07, 0.07) * big, Vector3(s * 1.0, 0.2, 0.8), 0.1, 0.026)


## Bloom crusting round a mask or helmet that already hides the face.
static func crust(b: B, rnd: RandomNumberGenerator, mask_front := true) -> void:
	for i in 6:
		var a := rnd.randf_range(-1.1, 1.1)
		var p := Vector3(sin(a) * 0.1, rnd.randf_range(0.0, 0.17), cos(a) * 0.125)
		ball(b, "flesh_raw", p, rnd.randf_range(0.015, 0.03), Vector3.ONE, 0.2)
		if i % 2 == 0:
			shard(b, "glow", p, Vector3(sin(a), 0.6, 1.0), 0.06, 0.01)


## Survivors: a scarf over the nose and chin and a pair of goggles (the colony's issue).
static func scarf_goggles(b: B, rnd: RandomNumberGenerator, full := false) -> void:
	patch(b, "scarf", HC + Vector3(0, -0.02, 0.012), HR * Vector3(1.1, 1.04, 1.09), Vector2(-PI, PI) if full else Vector2(-1.5, 1.5), Vector2(-1.25, 0.0 if not full else 1.2), 0.04, 9.0, Basis.IDENTITY, 28, 10)
	for s in [-1, 1]:
		tube(b, "filter", Vector3(0.042 * s, 0.108, 0.098), Vector3(0.042 * s, 0.108, 0.118), 0.031)
		tube(b, "lens", Vector3(0.042 * s, 0.108, 0.118), Vector3(0.042 * s, 0.108, 0.125), 0.024)
	patch(b, "strap", HC + Vector3(0, 0.02, 0), HR * Vector3(1.12, 0.14, 1.11), Vector2(-PI, PI), Vector2(-PI / 2, PI / 2), 0.0, 1.0, Basis.IDENTITY, 24, 4)


# --- dressing ------------------------------------------------------------------------------

static func archetype(kind: String) -> String:
	if kind == "brute":
		return "brute"
	if kind in SOLDIERLY:
		return "soldierly"
	if kind == "civilian":
		return "civilian"
	return "lean"


## Props for `kind` under `option` as a mesh (null: leave the face as the model has it).
static func mesh_for(kind: String, option: String) -> Mesh:
	var b := B.new()
	var rnd := RandomNumberGenerator.new()
	rnd.seed = hash(kind) + hash(option)
	var arch := archetype(kind)
	var sz: float = {"broodling": 0.95, "bloater": 1.0, "brood_mother": 1.0}.get(kind, 1.0)
	if arch == "soldierly":
		return null   # already behind a sealed mask or cracked helmet
	match option:
		"growth":
			match arch:
				"lean":
					var half: int = {"leaper": 1, "spitter": 0}.get(kind, 0)
					fungal_face(b, rnd, 1.0 + (0.12 if kind in ["bloater", "broodling"] else 0.0), kind != "shrieker", half)
					if kind == "shrieker":
						ball(b, "void", Vector3(0, -0.04, 0.09), 0.04, Vector3(1.1, 1.2, 0.8))
				"brute":
					fungal_face(b, rnd, 1.1)
					chitin_helm(b, rnd, 1.02)
				"soldierly":
					if kind == "fallen":
						fungal_face(b, rnd, 1.02)
					else:
						crust(b, rnd)
				"civilian":
					scarf_goggles(b, rnd)
		"mask":
			match arch:
				"lean":
					respirator(b, rnd, 0.6 if kind in ["runner", "leaper", "spitter"] else 0.0)
					if kind == "shrieker":
						respirator(b, rnd, 1.0)
				"brute":
					respirator(b, rnd, 1.0, "lens", 1.12)
				"soldierly":
					if kind == "fallen":
						respirator(b, rnd, 1.0)
					else:
						crust(b, rnd)
				"civilian":
					respirator(b, rnd, 0.0)
					cowl(b, rnd, 0.4, 1.0, false)
		"cowl":
			match arch:
				"lean":
					cowl(b, rnd, 1.0, sz, true, kind in ["runner", "leaper"])
				"brute":
					cowl(b, rnd, 1.0, 1.16, true)
				"soldierly":
					if kind == "fallen":
						cowl(b, rnd, 1.0, 1.08, true, true)
					else:
						return null
				"civilian":
					cowl(b, rnd, 0.9, 1.0, true)
		"wrap":
			match arch:
				"lean":
					bandage(b, rnd, kind == "shrieker", 1.0, kind != "bloater")
				"brute":
					chitin_helm(b, rnd, 1.02)
				"soldierly":
					cracked_visor(b, rnd, 1.0, kind == "fallen")
				"civilian":
					scarf_goggles(b, rnd, true)
	return b.mesh()


static func dress(model: Node3D, kind: String, option: String) -> Node3D:
	var m := mesh_for(kind, option)
	if m == null:
		return null
	var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var bone := sk.find_bone("Head")
	var att := BoneAttachment3D.new()
	att.name = "face_att"
	sk.add_child(att)
	att.bone_name = "Head"
	att.transform = sk.get_bone_global_rest(bone)
	var mi := MeshInstance3D.new()
	mi.name = "face_cover"
	mi.mesh = m
	att.add_child(mi)
	return att
