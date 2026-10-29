"""Generates the Drifter and the Bloom's static props (hive node, egg sac, spore nest,
Source root, the Source) as .glb files in assets/models/, and holds the mesh
primitives, material roles and weapon builder that tools/build_characters.py uses
to dress the CC0 character bodies.

Run with Blender 4.2+ (or the `bpy` pip module, Python 3.11/3.13):
    blender --background --python tools/gen_models.py
    python3 tools/gen_models.py            # with `pip install bpy`
Optional: pass model names after `--` to rebuild only some, e.g. `-- drifter egg_sac`.

How a model is laid out (the game relies on these names, see view/model_kit.gd):
  * Empties are joints: "body" (the game makes it breathe) and optionally "muzzle".
  * Each joint owns one mesh named "<joint>_mesh" with one material per surface.
    Material names are roles the game swaps for its character shader
    (cloth_team, armor_team, mark_team, strap, metal, skin, visor, glow, ...).
Coordinates: Blender Z up, the character faces -Y and its right hand is at -X,
which the glTF exporter turns into Godot's Y up / +Z forward.
"""
import math
import os
import random
import sys

import bpy  # first: it makes bmesh / mathutils importable
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "models")

# --- materials ----------------------------------------------------------------
# role -> (base colour, roughness, metallic, emission strength). Team-tinted roles
# are recoloured per player in game; the colours here are only the defaults.
MATS = {
    "cloth_team": ((0.20, 0.24, 0.13), 0.95, 0.0, 0.0),
    "armor_team": ((0.16, 0.18, 0.13), 0.65, 0.15, 0.0),
    "mark_team": ((0.66, 0.77, 0.43), 0.6, 0.0, 0.6),
    "cloak_team": ((0.14, 0.16, 0.10), 1.0, 0.0, 0.0),
    "plate": ((0.13, 0.14, 0.13), 0.55, 0.35, 0.0),
    "strap": ((0.07, 0.075, 0.06), 0.95, 0.0, 0.0),
    "leather": ((0.10, 0.075, 0.05), 0.8, 0.0, 0.0),
    "metal": ((0.05, 0.055, 0.06), 0.4, 0.8, 0.0),
    "skin": ((0.43, 0.31, 0.24), 0.75, 0.0, 0.0),
    "visor": ((0.66, 0.77, 0.43), 0.3, 0.0, 2.2),
    "lens": ((1.0, 0.33, 0.2), 0.2, 0.0, 2.5),
    "lamp": ((1.0, 0.85, 0.6), 0.3, 0.0, 3.0),
    "white": ((0.62, 0.61, 0.56), 0.85, 0.0, 0.0),
    "red": ((0.55, 0.11, 0.09), 0.8, 0.0, 0.0),
    "amber": ((0.82, 0.55, 0.15), 0.6, 0.0, 0.0),
    "glow": ((0.18, 0.95, 0.78), 0.4, 0.0, 3.5),
    "growth": ((0.07, 0.30, 0.26), 0.35, 0.0, 1.6),
    "flesh": ((0.03, 0.04, 0.04), 0.45, 0.0, 0.0),
    "flesh_raw": ((0.26, 0.09, 0.08), 0.45, 0.0, 0.0),
    "bone": ((0.50, 0.47, 0.38), 0.5, 0.0, 0.0),
    "rags": ((0.20, 0.17, 0.12), 1.0, 0.0, 0.0),
    "sac": ((0.08, 0.45, 0.38), 0.25, 0.0, 2.2),
    "chitin": ((0.07, 0.08, 0.075), 0.4, 0.1, 0.0),
    "denim": ((0.08, 0.10, 0.13), 0.95, 0.0, 0.0),
    "shirt": ((0.30, 0.12, 0.09), 0.95, 0.0, 0.0),
    "hair": ((0.05, 0.04, 0.035), 0.8, 0.0, 0.0),
}


def material(role):
    m = bpy.data.materials.get(role)
    if m:
        return m
    col, rough, metal, emit = MATS[role]
    m = bpy.data.materials.new(role)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*col, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit > 0:
        bsdf.inputs["Emission Color"].default_value = (*col, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit
    return m


# --- primitives (bmesh, built at the origin then placed) ---------------------------

def _place(bm, at=(0, 0, 0), rot=None, scale=None):
    if scale is not None:
        bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
    if rot is not None:
        m = rot if isinstance(rot, Matrix) else euler(*rot)
        bmesh.ops.transform(bm, matrix=m.to_4x4(), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(at), verts=bm.verts)
    return bm


def euler(x=0.0, y=0.0, z=0.0):
    from mathutils import Euler
    return Euler((x, y, z), "XYZ").to_matrix()


def aim_z(direction):
    """Rotation turning +Z towards `direction`."""
    return Vector((0, 0, 1)).rotation_difference(Vector(direction).normalized()).to_matrix()


def box(size, at=(0, 0, 0), bevel=0.015, segs=2, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if bevel > 0:
        bevel = min(bevel, min(size) * 0.45)
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segs, profile=0.5,
                        affect="EDGES", clamp_overlap=True)
    return _place(bm, at, rot)


def cyl(r_bottom, r_top, depth, at=(0, 0, 0), rot=None, segs=12, bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs,
                          radius1=r_bottom, radius2=r_top, depth=depth)
    if bevel > 0:
        rim = [e for e in bm.edges if not e.is_manifold or len(e.link_faces) == 2 and
               abs(e.link_faces[0].normal.z) > 0.9 or len(e.link_faces) == 2 and abs(e.link_faces[1].normal.z) > 0.9]
        bmesh.ops.bevel(bm, geom=rim, offset=bevel, segments=2, profile=0.5, affect="EDGES", clamp_overlap=True)
    return _place(bm, at, rot)


def tube(a, b, r_a, r_b=None, segs=10, bevel=0.0):
    """Cylinder from point a to point b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    return cyl(r_a, r_b if r_b is not None else r_a, d.length, at=(a + b) * 0.5, rot=aim_z(d), segs=segs, bevel=bevel)


def sphere(r, at=(0, 0, 0), scale=(1, 1, 1), segs=14, rings=8, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
    bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
    return _place(bm, at, rot)


def capsule(r, length, at=(0, 0, 0), rot=None, scale=(1, 1, 1), segs=12):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=8, radius=r)
    for v in bm.verts:
        v.co.z += length * 0.5 if v.co.z > 1e-5 else (-length * 0.5 if v.co.z < -1e-5 else 0.0)
    bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
    return _place(bm, at, rot)


def shard(base, direction, length, r, sides=5):
    """Crystal spike growing from `base` along `direction`."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=r, radius2=0.0, depth=length)
    bmesh.ops.translate(bm, vec=Vector((0, 0, length * 0.5)), verts=bm.verts)
    return _place(bm, base, aim_z(direction))


def cut(bm, point, normal, keep_above=True):
    """Slices the mesh with a plane and drops one side (fills the hole)."""
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector(point), plane_no=Vector(normal),
                                 clear_inner=keep_above, clear_outer=not keep_above)
    edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    if edges:
        bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    return bm


def bend_noise(bm, amount, scale=6.0, seed=0):
    """Organic wobble: displaces vertices with smooth pseudo-noise."""
    rnd = random.Random(seed)
    ph = [rnd.uniform(0, 6.28) for _ in range(6)]
    for v in bm.verts:
        p = v.co * scale
        n = (math.sin(p.x + ph[0]) * math.sin(p.y * 1.3 + ph[1]) + math.sin(p.z * 0.9 + ph[2])
             * math.sin(p.x * 1.7 + ph[3]) + 0.5 * math.sin(p.y * 2.3 + p.z * 1.9 + ph[4]))
        nrm = v.normal if v.normal.length > 0 else Vector((0, 0, 1))
        v.co += nrm * n * amount * 0.4
    return bm


def skin(points, edges, radii, subsurf=2, wobble=0.0, seed=0):
    """Organic mesh from a vertex skeleton via Blender's Skin modifier."""
    me = bpy.data.meshes.new("skin_tmp")
    me.from_pydata([Vector(p) for p in points], edges, [])
    ob = bpy.data.objects.new("skin_tmp", me)
    bpy.context.scene.collection.objects.link(ob)
    mod = ob.modifiers.new("skin", "SKIN")
    mod.use_smooth_shade = True
    sv = me.skin_vertices[0].data
    for i, r in enumerate(radii):
        sv[i].radius = (r, r) if not isinstance(r, tuple) else r
    sv[0].use_root = True
    if subsurf:
        ss = ob.modifiers.new("ss", "SUBSURF")
        ss.levels = subsurf
        ss.render_levels = subsurf
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    ev = ob.evaluated_get(dg)
    bm = bmesh.new()
    bm.from_mesh(ev.to_mesh())
    ev.to_mesh_clear()
    bpy.data.objects.remove(ob)
    bpy.data.meshes.remove(me)
    bm.normal_update()
    if wobble > 0:
        bend_noise(bm, wobble * 2.5, scale=9.0, seed=seed)
    return bm


# --- model assembly ------------------------------------------------------------------

class Model:
    """Collects parts per joint and writes one mesh per joint (and per growth group)."""

    def __init__(self, name):
        self.name = name
        self.joints = {}      # name -> (world pos, parent)
        self.parts = {}       # mesh key -> list of (bm, role)
        self.key_joint = {}   # mesh key -> joint

    def joint(self, name, pos, parent=None):
        self.joints[name] = (Vector(pos), parent)

    def add(self, joint, bm, role, group=""):
        key = (group + "_" + joint) if group else (joint + "_mesh")
        self.parts.setdefault(key, []).append((bm, role))
        self.key_joint[key] = joint

    def build(self):
        empties = {}
        root = bpy.data.objects.new(self.name, None)
        bpy.context.scene.collection.objects.link(root)
        # parents first
        order = []
        def visit(n):
            if n in order:
                return
            p = self.joints[n][1]
            if p:
                visit(p)
            order.append(n)
        for n in self.joints:
            visit(n)
        for n in order:
            pos, parent = self.joints[n]
            e = bpy.data.objects.new(n, None)
            e.empty_display_size = 0.05
            bpy.context.scene.collection.objects.link(e)
            e.location = pos
            par = empties[parent] if parent else root
            e.parent = par
            e.matrix_parent_inverse = par.matrix_world.inverted() if parent else Matrix.Identity(4)
            bpy.context.view_layer.update()
            empties[n] = e
        for key, items in self.parts.items():
            joint = self.key_joint[key]
            me = bpy.data.meshes.new(key)
            bm_all = bmesh.new()
            roles = []
            for bm, role in items:
                if role not in roles:
                    roles.append(role)
                tmp = bpy.data.meshes.new("tmp")
                bm.to_mesh(tmp)
                bm.free()
                n0 = len(bm_all.faces)
                bm_all.from_mesh(tmp)
                bm_all.faces.ensure_lookup_table()
                for f in bm_all.faces[n0:]:
                    f.material_index = roles.index(role)
                bpy.data.meshes.remove(tmp)
            # the mesh is authored in world (rest) space; store it relative to its joint
            jpos = self.joints[joint][0]
            bmesh.ops.translate(bm_all, vec=-jpos, verts=bm_all.verts)
            bmesh.ops.recalc_face_normals(bm_all, faces=bm_all.faces)
            bm_all.to_mesh(me)
            bm_all.free()
            for r in roles:
                me.materials.append(material(r))
            for p in me.polygons:
                p.use_smooth = True
            if hasattr(me, "set_sharp_from_angle"):
                me.set_sharp_from_angle(angle=math.radians(38))
            ob = bpy.data.objects.new(key, me)
            bpy.context.scene.collection.objects.link(ob)
            ob.parent = empties[joint]
            ob.location = (0, 0, 0)
        bpy.context.view_layer.update()

    def export(self):
        os.makedirs(OUT, exist_ok=True)
        path = os.path.join(OUT, self.name + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True,
                                  export_apply=True, export_animations=False, export_cameras=False,
                                  export_lights=False, export_extras=False)
        tris = sum(len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH")
        print("wrote %s (%d faces)" % (path, tris))


def fresh_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# --- weapons (used by tools/build_characters.py) ------------------------------------
GUN_AT = Vector((-0.13, -0.17, 1.24))


def weapon(m, kind):
    m.joint("gun", tuple(GUN_AT), "torso")
    g = lambda p: tuple(GUN_AT + Vector(p))
    if kind == "marksman":
        m.add("gun", box((0.055, 0.40, 0.085), g((0, -0.10, 0.05)), 0.012), "metal")
        m.add("gun", tube(g((0, -0.30, 0.06)), g((0, -0.66, 0.06)), 0.014), "metal")
        m.add("gun", tube(g((0, -0.62, 0.06)), g((0, -0.80, 0.06)), 0.024, segs=12, bevel=0.005), "strap")  # suppressor
        m.add("gun", box((0.05, 0.22, 0.05), g((0, -0.38, 0.045)), 0.012), "leather")                       # wood foregrip
        m.add("gun", tube(g((0, 0.10, 0.145)), g((0, -0.18, 0.145)), 0.032, segs=14, bevel=0.006), "metal")    # scope
        m.add("gun", tube(g((0, -0.18, 0.145)), g((0, -0.21, 0.145)), 0.04, 0.036, segs=14), "metal")
        m.add("gun", tube(g((0, -0.205, 0.145)), g((0, -0.212, 0.145)), 0.03, segs=14), "lens")
        m.add("gun", box((0.03, 0.03, 0.05), g((0, -0.04, 0.11)), 0.006), "metal")
        m.add("gun", box((0.05, 0.24, 0.09), g((0, 0.22, 0.02)), 0.02, rot=(0.08, 0, 0)), "leather")       # stock
        m.add("gun", box((0.04, 0.06, 0.10), g((0, 0.02, -0.03)), 0.012, rot=(-0.3, 0, 0)), "strap")        # grip
        m.add("gun", box((0.04, 0.07, 0.08), g((0, -0.12, -0.02)), 0.01), "metal")                          # mag
        for s in (-1, 1):                                                                                  # bipod
            m.add("gun", tube(g((0.012 * s, -0.55, 0.035)), g((0.03 * s, -0.36, -0.005)), 0.008, segs=6), "metal")
        support, muzzle = (0, -0.38, 0.0), (0, -0.82, 0.06)
    elif kind == "medic":
        m.add("gun", box((0.06, 0.24, 0.10), g((0, -0.06, 0.05)), 0.015), "metal")
        m.add("gun", tube(g((0, -0.18, 0.06)), g((0, -0.30, 0.06)), 0.018), "metal")
        m.add("gun", box((0.04, 0.05, 0.11), g((0, -0.16, -0.04)), 0.012), "strap")                          # foregrip
        m.add("gun", box((0.035, 0.05, 0.14), g((0, -0.06, -0.06)), 0.01), "metal")                          # mag
        m.add("gun", box((0.04, 0.06, 0.10), g((0, 0.03, -0.03)), 0.012, rot=(-0.3, 0, 0)), "strap")
        m.add("gun", box((0.03, 0.16, 0.04), g((0, 0.14, 0.04)), 0.01), "metal")                            # wire stock
        m.add("gun", box((0.035, 0.06, 0.04), g((0, -0.03, 0.12)), 0.008), "metal")
        m.add("gun", box((0.02, 0.02, 0.02), g((0, -0.06, 0.12)), 0.004), "lens")
        support, muzzle = (0, -0.16, -0.08), (0, -0.31, 0.06)
    elif kind == "breacher":
        m.add("gun", box((0.075, 0.30, 0.11), g((0, -0.06, 0.05)), 0.018), "metal")
        m.add("gun", tube(g((0, -0.20, 0.075)), g((0, -0.56, 0.075)), 0.024, segs=12), "metal")
        m.add("gun", tube(g((0, -0.20, 0.03)), g((0, -0.50, 0.03)), 0.02, segs=10), "metal")                 # tube mag
        m.add("gun", box((0.07, 0.15, 0.07), g((0, -0.32, 0.035)), 0.02), "strap")                           # pump
        m.add("gun", box((0.075, 0.03, 0.075), g((0, -0.28, 0.035)), 0.008), "amber")
        m.add("gun", box((0.055, 0.22, 0.10), g((0, 0.18, 0.02)), 0.02, rot=(0.1, 0, 0)), "strap")
        m.add("gun", box((0.045, 0.06, 0.10), g((0, 0.03, -0.03)), 0.012, rot=(-0.3, 0, 0)), "strap")
        for i in range(4):
            m.add("gun", cyl(0.012, 0.012, 0.05, g((0.045, 0.02 - i * 0.03, 0.05)), rot=(0, 0, 0), segs=6), "red")  # shells
        support, muzzle = (0, -0.32, -0.01), (0, -0.58, 0.075)
    else:   # trooper assault rifle
        m.add("gun", box((0.06, 0.30, 0.095), g((0, -0.07, 0.05)), 0.014), "metal")
        m.add("gun", box((0.058, 0.20, 0.07), g((0, -0.30, 0.055)), 0.016), "strap")                         # handguard
        m.add("gun", tube(g((0, -0.38, 0.06)), g((0, -0.52, 0.06)), 0.014), "metal")
        m.add("gun", tube(g((0, -0.50, 0.06)), g((0, -0.55, 0.06)), 0.02, segs=8), "metal")                  # brake
        m.add("gun", box((0.04, 0.07, 0.15), g((0, -0.13, -0.05)), 0.012, rot=(0.25, 0, 0)), "metal")        # mag
        m.add("gun", box((0.045, 0.20, 0.085), g((0, 0.17, 0.035)), 0.02, rot=(0.06, 0, 0)), "strap")
        m.add("gun", box((0.04, 0.06, 0.10), g((0, 0.02, -0.03)), 0.012, rot=(-0.3, 0, 0)), "strap")
        m.add("gun", box((0.045, 0.08, 0.05), g((0, -0.06, 0.125)), 0.01), "metal")                          # optic
        m.add("gun", box((0.03, 0.006, 0.03), g((0, -0.101, 0.128)), 0.003), "lens")
        m.add("gun", tube(g((0, -0.30, 0.0)), g((0, -0.42, 0.0)), 0.022, segs=10), "metal")                  # launcher
        support, muzzle = (0, -0.30, 0.0), (0, -0.56, 0.06)
    m.joint("support", g(support), "gun")
    m.joint("muzzle", g(muzzle), "gun")


# --- classes ----------------------------------------------------------------------------


# --- props and the Drifter: static bodies with one "body" joint (it breathes) ----------

def tendril(m, joint, start, direction, length, r, segs, rnd, role="flesh", curl=0.25):
    p = Vector(start)
    d = Vector(direction).normalized()
    for i in range(segs):
        d = (d + Vector((rnd.uniform(-curl, curl), rnd.uniform(-curl, curl), rnd.uniform(-curl, curl) * 0.5))).normalized()
        q = p + d * (length / segs)
        rr = r * (1.0 - i / segs) + 0.004
        m.add(joint, tube(tuple(p), tuple(q), rr, rr * 0.85, segs=8), role)
        m.add(joint, sphere(rr, tuple(q), segs=8, rings=5), role)
        p = q
    return p


def glow_cluster(m, joint, base, n, length, rnd, up=(0, 0, 1), spread=0.5, r=0.16):
    base = Vector(base)
    for i in range(n):
        d = Vector(up) + Vector((rnd.uniform(-spread, spread), rnd.uniform(-spread, spread), rnd.uniform(-spread, spread) * 0.4))
        m.add(joint, shard(tuple(base + Vector((rnd.uniform(-0.05, 0.05), rnd.uniform(-0.05, 0.05), 0))), tuple(d),
                           rnd.uniform(length * 0.55, length), length * r), "glow")


def blob(r, at, scale, seed, wobble=0.04):
    bm = sphere(r, at, scale, segs=16, rings=10)
    bend_noise(bm, wobble, seed=seed)
    return bm


def build_drifter():
    m = Model("drifter")
    rnd = random.Random(31)
    m.joint("body", (0, 0, 1.1))
    m.add("body", blob(0.34, (0, 0, 1.15), (1.0, 1.0, 0.9), 3), "sac")
    for i in range(7):
        a = i * 0.8976
        m.add("body", sphere(0.12, (math.cos(a) * 0.3, math.sin(a) * 0.3, 1.06), (1, 1, 0.7)), "flesh")
        tendril(m, "body", (math.cos(a) * 0.22, math.sin(a) * 0.22, 0.92), (math.cos(a) * 0.3, math.sin(a) * 0.3, -1), 0.55, 0.025, 6, rnd)
    m.add("body", blob(0.2, (0, 0, 0.9), (1.2, 1.2, 0.6), 5), "flesh_raw")
    glow_cluster(m, "body", (0, 0, 1.4), 5, 0.2, rnd, spread=0.6)
    m.joint("muzzle", (0, 0, 0.8), "body")
    return m


def build_hive_node():
    m = Model("hive_node")
    rnd = random.Random(7)
    m.joint("body", (0, 0, 0.4))
    m.add("body", blob(0.5, (0, 0, 0.25), (1.0, 1.0, 0.7), 1, 0.07), "flesh")
    for i in range(6):
        a = i * 1.047 + 0.3
        m.add("body", blob(0.2, (math.cos(a) * 0.42, math.sin(a) * 0.42, 0.1), (1.2, 1.0, 0.7), 10 + i), "flesh_raw")
        tendril(m, "body", (math.cos(a) * 0.45, math.sin(a) * 0.45, 0.05), (math.cos(a), math.sin(a), -0.15), 0.6, 0.05, 5, rnd)
    m.add("body", sphere(0.2, (0, -0.1, 0.55), (1, 1, 1.2)), "sac")
    glow_cluster(m, "body", (0, 0, 0.5), 9, 0.65, rnd, spread=0.55)
    return m


def build_egg_sac():
    m = Model("egg_sac")
    rnd = random.Random(11)
    m.joint("body", (0, 0, 0.25))
    m.add("body", blob(0.35, (0, 0, 0.05), (1.2, 1.1, 0.35), 2, 0.05), "flesh")
    for i, (x, y, r) in enumerate(((0, 0, 0.22), (0.2, 0.12, 0.16), (-0.18, 0.14, 0.15), (0.05, -0.2, 0.14))):
        m.add("body", sphere(r, (x, y, 0.12 + r), (1, 1, 1.25)), "sac")
        m.add("body", tube((x, y, 0.08), (x, y, 0.12 + r * 0.6), r * 0.45, r * 0.2, segs=8), "flesh_raw")
    return m


def build_spore_nest():
    m = Model("spore_nest")
    rnd = random.Random(13)
    m.joint("body", (0, 0, 0.3))
    m.add("body", blob(0.45, (0, 0, 0.1), (1.0, 1.0, 0.45), 4, 0.05), "flesh")
    for i in range(5):
        a = i * 1.2566
        base = (math.cos(a) * 0.25, math.sin(a) * 0.25, 0.18)
        m.add("body", cyl(0.09, 0.06, 0.3, (base[0], base[1], 0.32), segs=10), "flesh_raw")
        m.add("body", cyl(0.055, 0.055, 0.02, (base[0], base[1], 0.48), segs=10), "glow")
    m.add("body", sphere(0.14, (0, 0, 0.32)), "sac")
    m.joint("muzzle", (0, 0, 0.55), "body")
    return m


def build_source_root():
    m = Model("source_root")
    rnd = random.Random(17)
    m.joint("body", (0, 0, 0.5))
    m.add("body", blob(0.45, (0, 0, 0.0), (1.3, 1.3, 0.4), 6, 0.06), "flesh")
    for i in range(5):
        a = i * 1.2566 + 0.4
        tendril(m, "body", (math.cos(a) * 0.15, math.sin(a) * 0.15, 0.05), (math.cos(a) * 0.35, math.sin(a) * 0.35, 1), 1.1 + rnd.uniform(0, 0.4), 0.09, 7, rnd, curl=0.3)
    glow_cluster(m, "body", (0, 0, 0.1), 6, 0.45, rnd, spread=0.8)
    m.add("body", sphere(0.12, (0, 0, 0.35)), "glow")
    return m


def build_the_source():
    m = Model("the_source")
    rnd = random.Random(23)
    m.joint("body", (0, 0, 1.4))
    m.add("body", blob(1.0, (0, 0, 0.1), (1.4, 1.4, 0.35), 8, 0.1), "flesh")
    for i in range(9):
        a = i * 0.698
        tendril(m, "body", (math.cos(a) * 0.5, math.sin(a) * 0.5, 0.15), (math.cos(a), math.sin(a), 0.25), 1.5, 0.16, 6, rnd, curl=0.2)
    m.add("body", blob(0.55, (0, 0, 1.4), (1.0, 1.0, 1.25), 9, 0.06), "sac")
    m.add("body", sphere(0.3, (0, -0.1, 1.45)), "glow")
    for i in range(4):
        a = i * 1.5708 + 0.5
        tendril(m, "body", (math.cos(a) * 0.4, math.sin(a) * 0.4, 0.3), (math.cos(a) * 0.4, math.sin(a) * 0.4, 1), 1.6, 0.14, 6, rnd, curl=0.15)
    glow_cluster(m, "body", (0, 0, 1.9), 12, 1.1, rnd, spread=0.7, r=0.12)
    glow_cluster(m, "body", (0, 0, 0.3), 10, 0.8, rnd, spread=1.0, r=0.12)
    m.joint("muzzle", (0, -0.4, 1.5), "body")
    return m


def build_bore_engine():
    m = Model("bore_engine")
    rnd = random.Random(41)
    m.joint("body", (0, 0, 1.6))
    m.add("body", cyl(2.0, 1.7, 0.7, (0, 0, 0.35), segs=20, bevel=0.05), "plate")          # the collar bolted to the rim
    m.add("body", cyl(1.55, 1.35, 1.0, (0, 0, 1.1), segs=18, bevel=0.04), "metal")         # engine block
    for i in range(6):                                                                      # cooling jacket ribs
        z = 0.75 + i * 0.16
        m.add("body", cyl(1.62, 1.62, 0.06, (0, 0, z), segs=18), "amber")
    m.add("body", cyl(0.95, 0.0, 2.1, (0, 0, 2.9), segs=14), "metal")                      # the drill head
    for i in range(3):                                                                      # cutting flights
        a = i * 2.0944
        for k in range(5):
            z = 1.9 + k * 0.38
            r = 0.92 - k * 0.17
            m.add("body", box((0.5, 0.12, 0.1), (math.cos(a + k * 0.5) * r, math.sin(a + k * 0.5) * r, z), rot=(0, 0, a + k * 0.5)), "plate")
    m.add("body", sphere(0.55, (0, 0, 1.5), (1.0, 1.0, 0.8)), "glow")                      # the core behind the armour
    for i in range(4):                                                                      # piston arms
        a = i * 1.5708 + 0.785
        dx, dy = math.cos(a), math.sin(a)
        m.add("body", tube((dx * 1.4, dy * 1.4, 1.2), (dx * 2.7, dy * 2.7, 0.45), 0.2, 0.14), "metal")
        m.add("body", tube((dx * 2.1, dy * 2.1, 0.9), (dx * 3.0, dy * 3.0, 0.45), 0.3, 0.3), "plate")
        m.add("body", box((0.6, 0.6, 0.5), (dx * 3.0, dy * 3.0, 0.3), rot=(0, 0, a)), "amber")
    for i in range(3):                                                                      # coolant lines into the three valves
        a = i * 2.0944 + 1.5708
        m.add("body", tube((math.cos(a) * 1.5, math.sin(a) * 1.5, 1.9), (math.cos(a) * 2.2, math.sin(a) * 2.2, 0.8), 0.13), "red")
    glow_cluster(m, "body", (0, 0, 1.2), 8, 0.5, rnd, spread=1.4, r=0.1)
    m.joint("muzzle", (0, -1.2, 1.6), "body")
    return m


def build_coolant_valve():
    m = Model("coolant_valve")
    m.joint("body", (0, 0, 0.5))
    m.add("body", cyl(0.5, 0.45, 0.35, (0, 0, 0.17), segs=14, bevel=0.03), "plate")
    m.add("body", cyl(0.2, 0.2, 0.9, (0, 0, 0.7), segs=10), "red")                          # the standpipe
    m.add("body", tube((-0.55, 0, 0.55), (0.55, 0, 0.55), 0.14), "metal")                  # the cross line
    m.add("body", cyl(0.5, 0.5, 0.06, (0, 0, 1.2), segs=16), "amber")                       # handwheel
    for i in range(4):
        a = i * 0.785
        m.add("body", box((1.0, 0.07, 0.06), (0, 0, 1.2), rot=(0, 0, a)), "amber")
    m.add("body", sphere(0.14, (0, 0, 1.28)), "glow")                                       # the gauge lamp
    return m


MODELS = {
    "drifter": build_drifter, "hive_node": build_hive_node, "egg_sac": build_egg_sac,
    "spore_nest": build_spore_nest, "source_root": build_source_root, "the_source": build_the_source,
    "bore_engine": build_bore_engine, "coolant_valve": build_coolant_valve,
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = [a for a in argv if a in MODELS] or list(MODELS)
    for n in names:
        fresh_scene()
        m = MODELS[n]()
        m.build()
        m.export()


if __name__ == "__main__":
    main()
