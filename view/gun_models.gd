extends RefCounted
## Procedural guns, keyed by look (a signature weapon id, see Weapons.look_of): for classes that
## borrow another class's character model (Hazmat and Vector wear the Trooper's body), and for
## soldiers carrying an alternate gun whose look isn't their class's baked one. Builds the weapon
## in the "gun" bone's space (+Z out of the barrel, +Y up, origin at the grip) and swaps it in
## for the baked gun, moving the "muzzle" and "support" sockets to match. Surfaces reuse the
## baked gun's role materials so ModelKit tints them.

const Palette := preload("res://view/palette.gd")

## Classes whose body is borrowed, and the look of their own gun.
const KIND_LOOK := {"hazmat": "lmg", "vector": "carbine"}

## look -> {parts: [[role, "box"|"tube", a, b, size_or_radius]], muzzle, support}.
## "box": centre `a`, size `b`. "tube": from `a` to `b` along Z with radius `r`.
const GUNS := {
	"rifle": {   # assault rifle: receiver, handguard, curved-ish box magazine, fixed stock
		"parts": [
			["metal", "box", Vector3(0, 0.05, 0.05), Vector3(0.07, 0.1, 0.34)],
			["strap", "box", Vector3(0, 0.05, 0.3), Vector3(0.065, 0.08, 0.18)],
			["metal", "tube", Vector3(0, 0.06, 0.38), Vector3(0, 0.06, 0.6), 0.013],
			["strap", "box", Vector3(0, -0.05, 0.1), Vector3(0.04, 0.13, 0.06)],
			["strap", "box", Vector3(0, 0.03, -0.22), Vector3(0.05, 0.1, 0.2)],
			["strap", "box", Vector3(0, -0.05, -0.02), Vector3(0.04, 0.1, 0.05)],
			["metal", "box", Vector3(0, 0.12, 0.05), Vector3(0.03, 0.03, 0.1)],
			["amber", "box", Vector3(0.036, 0.05, 0.15), Vector3(0.004, 0.02, 0.06)],
		],
		"muzzle": Vector3(0, 0.06, 0.61), "support": Vector3(0, 0.0, 0.28),
	},
	"dmr": {   # long rifle: long barrel, big scope, heavy stock
		"parts": [
			["metal", "box", Vector3(0, 0.05, 0.05), Vector3(0.07, 0.1, 0.38)],
			["metal", "tube", Vector3(0, 0.06, 0.25), Vector3(0, 0.06, 0.8), 0.014],
			["metal", "tube", Vector3(0, 0.15, -0.05), Vector3(0, 0.15, 0.22), 0.028],
			["lens", "box", Vector3(0, 0.15, 0.225), Vector3(0.03, 0.03, 0.004)],
			["strap", "box", Vector3(0, 0.03, -0.26), Vector3(0.05, 0.11, 0.24)],
			["strap", "box", Vector3(0, -0.04, 0.08), Vector3(0.04, 0.09, 0.06)],
			["strap", "box", Vector3(0, -0.05, -0.03), Vector3(0.04, 0.1, 0.05)],
		],
		"muzzle": Vector3(0, 0.06, 0.81), "support": Vector3(0, 0.0, 0.32),
	},
	"pdw": {   # compact: short barrel, long stick magazine, stub stock
		"parts": [
			["metal", "box", Vector3(0, 0.05, 0.04), Vector3(0.065, 0.1, 0.26)],
			["metal", "tube", Vector3(0, 0.06, 0.17), Vector3(0, 0.06, 0.32), 0.012],
			["strap", "box", Vector3(0, -0.07, 0.06), Vector3(0.035, 0.16, 0.045)],
			["strap", "box", Vector3(0, 0.04, -0.15), Vector3(0.04, 0.06, 0.12)],
			["strap", "box", Vector3(0, -0.05, -0.03), Vector3(0.04, 0.1, 0.05)],
			["metal", "box", Vector3(0, 0.115, 0.04), Vector3(0.03, 0.025, 0.07)],
		],
		"muzzle": Vector3(0, 0.06, 0.33), "support": Vector3(0, 0.0, 0.16),
	},
	"shotgun": {   # pump gun: fat barrel over a tube magazine, slide grip
		"parts": [
			["metal", "box", Vector3(0, 0.05, 0.03), Vector3(0.07, 0.1, 0.28)],
			["metal", "tube", Vector3(0, 0.07, 0.15), Vector3(0, 0.07, 0.62), 0.02],
			["metal", "tube", Vector3(0, 0.025, 0.18), Vector3(0, 0.025, 0.55), 0.016],
			["strap", "box", Vector3(0, 0.03, 0.36), Vector3(0.06, 0.06, 0.14)],
			["strap", "box", Vector3(0, 0.03, -0.22), Vector3(0.05, 0.11, 0.22)],
			["strap", "box", Vector3(0, -0.05, -0.03), Vector3(0.04, 0.1, 0.05)],
		],
		"muzzle": Vector3(0, 0.07, 0.63), "support": Vector3(0, 0.03, 0.36),
	},
	"lmg": {   # light machine gun: long shrouded barrel, box magazine, bipod
		"parts": [
			["metal", "box", Vector3(0, 0.045, 0.04), Vector3(0.085, 0.12, 0.36)],
			["strap", "tube", Vector3(0, 0.06, 0.2), Vector3(0, 0.06, 0.52), 0.034],
			["metal", "tube", Vector3(0, 0.06, 0.5), Vector3(0, 0.06, 0.74), 0.015],
			["metal", "tube", Vector3(0, 0.06, 0.7), Vector3(0, 0.06, 0.76), 0.024],
			["strap", "box", Vector3(0.055, -0.04, 0.07), Vector3(0.09, 0.14, 0.13)],
			["amber", "box", Vector3(0.101, -0.04, 0.07), Vector3(0.004, 0.03, 0.1)],
			["metal", "box", Vector3(0, 0.135, 0.06), Vector3(0.025, 0.03, 0.16)],
			["strap", "box", Vector3(0, 0.02, -0.24), Vector3(0.06, 0.11, 0.22)],
			["strap", "box", Vector3(0, -0.05, -0.01), Vector3(0.04, 0.1, 0.06)],
			["metal", "box", Vector3(0.02, 0.01, 0.55), Vector3(0.012, 0.012, 0.2)],
			["metal", "box", Vector3(-0.02, 0.01, 0.55), Vector3(0.012, 0.012, 0.2)],
		],
		"muzzle": Vector3(0, 0.06, 0.77), "support": Vector3(0, 0.0, 0.3),
	},
	"sidearm": {   # service pistol: slide over a short grip, no stock
		"parts": [
			["metal", "box", Vector3(0, 0.07, 0.07), Vector3(0.05, 0.07, 0.22)],
			["metal", "tube", Vector3(0, 0.065, 0.17), Vector3(0, 0.065, 0.22), 0.012],
			["strap", "box", Vector3(0, -0.01, 0.0), Vector3(0.04, 0.12, 0.06)],
			["amber", "box", Vector3(0.026, 0.07, 0.08), Vector3(0.004, 0.015, 0.08)],
		],
		"muzzle": Vector3(0, 0.065, 0.23), "support": Vector3(0, 0.0, 0.05),
	},
	"carbine": {   # bio-carbine: compact, a glowing culture vial along the receiver
		"parts": [
			["metal", "box", Vector3(0, 0.05, 0.02), Vector3(0.065, 0.1, 0.3)],
			["strap", "box", Vector3(0, 0.05, 0.24), Vector3(0.06, 0.075, 0.16)],
			["metal", "tube", Vector3(0, 0.06, 0.3), Vector3(0, 0.06, 0.44), 0.014],
			["glow", "tube", Vector3(0.045, 0.06, -0.06), Vector3(0.045, 0.06, 0.12), 0.018],
			["metal", "box", Vector3(0.045, 0.06, 0.03), Vector3(0.042, 0.042, 0.03)],
			["strap", "box", Vector3(0, -0.04, 0.08), Vector3(0.04, 0.13, 0.05)],
			["strap", "box", Vector3(0, 0.03, -0.2), Vector3(0.05, 0.1, 0.18)],
			["strap", "box", Vector3(0, -0.04, -0.03), Vector3(0.04, 0.09, 0.05)],
			["metal", "box", Vector3(0, 0.12, 0.02), Vector3(0.04, 0.04, 0.08)],
			["lens", "box", Vector3(0, 0.12, 0.061), Vector3(0.025, 0.025, 0.004)],
		],
		"muzzle": Vector3(0, 0.06, 0.45), "support": Vector3(0, -0.02, 0.22),
	},
}


static func has_gun(kind: String) -> bool:
	return KIND_LOOK.has(kind)


## Replaces the baked gun under `model` with `kind`'s own. No-op if either is missing.
static func swap(model: Node, kind: String) -> void:
	swap_look(model, KIND_LOOK.get(kind, ""))


## The look a soldier of `kind` shows with no alternate gun.
static func kind_look(kind: String) -> String:
	return KIND_LOOK.get(kind, Weapons.look_of(Weapons.id_for(kind)))


## Replaces the baked gun under `model` with the procedural gun for `look`. No-op if either is missing.
static func swap_look(model: Node, look: String) -> void:
	var att := model.find_child("gun", true, false)
	if not GUNS.has(look) or att == null or att.get_child_count() == 0 or not att.get_child(0) is MeshInstance3D:
		return
	var old := att.get_child(0) as MeshInstance3D
	var by_role := {}
	for i in old.mesh.get_surface_count():
		var m := old.mesh.surface_get_material(i)
		if m != null:
			by_role[m.resource_name] = m
	var def: Dictionary = GUNS[look]
	old.mesh = build_mesh(def.parts, by_role)
	var skel := model.find_children("*", "Skeleton3D", true, false)
	if skel.is_empty():
		return
	var sk := skel[0] as Skeleton3D
	for sock in ["muzzle", "support"]:
		var i := sk.find_bone(sock)
		if i >= 0:
			var rest := sk.get_bone_rest(i)
			rest.origin = def[sock]
			sk.set_bone_rest(i, rest)
			sk.set_bone_pose_position(i, rest.origin)


## One mesh from primitive parts, one surface per role. Parts: [role, "box", centre, size
## (, euler)], [role, "tube", from, to, radius] (along any direction) or [role, "ball",
## centre, radius]. `by_role` supplies materials to reuse; other roles get a plain one
## (coloured from `colors`: an albedo Color, or [albedo, emission]) that ModelKit tints.
static func build_mesh(parts: Array, by_role := {}, colors := {}) -> ArrayMesh:
	var tools := {}
	for p in parts:
		var role: String = p[0]
		if not tools.has(role):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[role] = st
		var prim: PrimitiveMesh
		var xf := Transform3D.IDENTITY
		match p[1]:
			"box":
				var b := BoxMesh.new()
				b.size = p[3]
				prim = b
				xf.origin = p[2]
				if p.size() > 4:
					xf.basis = Basis.from_euler(p[4])
			"ball":
				var sp := SphereMesh.new()
				sp.radius = p[3]
				sp.height = p[3] * 2.0
				sp.radial_segments = 10
				sp.rings = 5
				prim = sp
				xf.origin = p[2]
			_:
				var a: Vector3 = p[2]
				var e: Vector3 = p[3]
				var c := CylinderMesh.new()
				c.top_radius = p[5] if p.size() > 5 else p[4]   # a sixth element tapers the tube to a cone
				c.bottom_radius = p[4]
				c.height = a.distance_to(e)
				c.radial_segments = 10
				c.rings = 1
				prim = c
				xf = Transform3D(_y_to((e - a).normalized()), (a + e) * 0.5)
		(tools[role] as SurfaceTool).append_from(prim, 0, xf)
	var mesh := ArrayMesh.new()
	for role in tools:
		var st: SurfaceTool = tools[role]
		st.generate_normals()
		st.commit(mesh)
		var m: Material = by_role.get(role, null)
		if m == null:
			m = _role_material(role, colors.get(role, null))
		mesh.surface_set_material(mesh.get_surface_count() - 1, m)
	return mesh


## Rotation taking +Y onto `d` (a cylinder's axis onto the tube's direction).
static func _y_to(d: Vector3) -> Basis:
	var axis := Vector3.UP.cross(d)
	if axis.length() < 1e-5:
		return Basis.IDENTITY if d.y > 0.0 else Basis(Vector3.RIGHT, PI)
	return Basis(axis.normalized(), acos(clampf(Vector3.UP.dot(d), -1.0, 1.0)))


static func _role_material(role: String, color: Variant = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = role
	m.albedo_color = {"amber": Palette.AMBER, "glow": Palette.TEAL}.get(role, Color(0.3, 0.3, 0.3))
	if color is Color:
		m.albedo_color = color
	elif color is Array:
		m.albedo_color = color[0]
		m.emission = color[1]
	if role == "metal":
		m.metallic = 0.6
		m.roughness = 0.45
	return m
