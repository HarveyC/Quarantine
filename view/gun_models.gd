extends RefCounted
## Guns for classes that borrow another class's character model (Hazmat and Vector wear the
## Trooper's body): builds the weapon in the "gun" bone's space (+Z out of the barrel, +Y up,
## origin at the grip) and swaps it in for the baked rifle, moving the "muzzle" and "support"
## sockets to match. Surfaces reuse the baked gun's role materials so ModelKit tints them.

const Palette := preload("res://view/palette.gd")

## kind -> {parts: [[role, "box"|"tube", a, b, size_or_radius]], muzzle, support}.
## "box": centre `a`, size `b`. "tube": from `a` to `b` along Z with radius `r`.
const GUNS := {
	"hazmat": {   # light machine gun: long shrouded barrel, box magazine, bipod
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
	"vector": {   # bio-carbine: compact, a glowing culture vial along the receiver
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
	return GUNS.has(kind)


## Replaces the baked gun under `model` with `kind`'s. No-op if either is missing.
static func swap(model: Node, kind: String) -> void:
	var att := model.find_child("gun", true, false)
	if not GUNS.has(kind) or att == null or att.get_child_count() == 0 or not att.get_child(0) is MeshInstance3D:
		return
	var old := att.get_child(0) as MeshInstance3D
	var by_role := {}
	for i in old.mesh.get_surface_count():
		var m := old.mesh.surface_get_material(i)
		if m != null:
			by_role[m.resource_name] = m
	var def: Dictionary = GUNS[kind]
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
				c.top_radius = p[4]
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
