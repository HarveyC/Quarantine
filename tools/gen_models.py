"""Generates the soldier and enemy models as .glb files in assets/models/.

Every model is built from code in Blender (no third-party meshes), so the whole
cast shares one look and the infection growths can be authored per rig.

Run with Blender 4.2+ (or the `bpy` pip module, Python 3.11/3.13):
    blender --background --python tools/gen_models.py
    python3 tools/gen_models.py            # with `pip install bpy`
Optional: pass model names after `--` to rebuild only some, e.g. `-- runner spitter`.

How a model is laid out (the game relies on these names, see view/model_kit.gd):
  * Empties are joints: hips, leg_l/leg_r, knee_l/knee_r, torso, head, arm_l/arm_r,
    elbow_l/elbow_r, plus gun, gun/support, gun/muzzle on soldiers and sac,
    head/muzzle on enemies. The game rotates these procedurally; there is no
    skinning or baked animation.
  * Each joint owns one mesh named "<joint>_mesh" with one material per surface.
    Material names are roles the game swaps for its character shader
    (cloth_team, armor_team, mark_team, strap, metal, skin, visor, glow, ...).
  * Infection growths are separate meshes named "grow<N>_<joint>" (N = 1 Exposed,
    2 Mutating, 3 Critical) that the game shows as a soldier's infection rises.
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


# --- soldier rig -------------------------------------------------------------------
# Chunky stylised proportions: big helmet, hands and boots, broad shoulders.
HIP_Z = 0.80
TORSO_Z = 0.88
SHOULDER_Z = 1.40
HEAD_Z = 1.52
ARM_X = 0.27
UPPER = 0.27
FORE = 0.25


def soldier_joints(m, heavy=False):
    ax = ARM_X + (0.04 if heavy else 0.0)
    m.joint("hips", (0, 0, HIP_Z))
    m.joint("torso", (0, 0, TORSO_Z), "hips")
    m.joint("head", (0, 0, HEAD_Z), "torso")
    for s, side in ((-1, "r"), (1, "l")):
        m.joint("leg_" + side, (0.115 * s, 0, HIP_Z), "hips")
        m.joint("knee_" + side, (0.115 * s, 0, 0.43), "leg_" + side)
        m.joint("arm_" + side, (ax * s, 0, SHOULDER_Z), "torso")
        m.joint("elbow_" + side, (ax * s, 0, SHOULDER_Z - UPPER), "arm_" + side)
    return ax


def soldier_body(m, kind):
    heavy = kind == "breacher"
    ax = soldier_joints(m, heavy)
    # pelvis and belt
    m.add("hips", box((0.31, 0.22, 0.17), (0, 0, 0.80), 0.05), "cloth_team")
    m.add("hips", box((0.35, 0.25, 0.06), (0, 0, 0.875), 0.02), "strap")
    m.add("hips", box((0.07, 0.03, 0.05), (0, -0.13, 0.875), 0.01), "metal")
    for s in (-1, 1):
        m.add("hips", box((0.07, 0.10, 0.09), (0.17 * s, 0.02, 0.85), 0.015), "strap")
    m.add("hips", box((0.16, 0.07, 0.08), (0, 0.14, 0.85), 0.015), "strap")
    # legs
    for s, side in ((-1, "r"), (1, "l")):
        x = 0.115 * s
        leg, knee = "leg_" + side, "knee_" + side
        m.add(leg, cyl(0.078, 0.092, 0.40, (x, 0, 0.62), segs=12), "cloth_team")
        m.add(leg, box((0.05, 0.12, 0.13), (x + 0.085 * s, -0.01, 0.6), 0.02), "cloth_team")   # cargo pocket
        m.add(leg, box((0.055, 0.125, 0.03), (x + 0.088 * s, -0.01, 0.67), 0.01), "strap")     # flap
        m.add(leg, cyl(0.094, 0.094, 0.035, (x, 0, 0.72), segs=12), "strap")                    # thigh strap
        if heavy:
            m.add(leg, box((0.17, 0.06, 0.2), (x + 0.02 * s, -0.08, 0.63), 0.025, rot=(0.12, 0, 0)), "armor_team")
        m.add(knee, cyl(0.06, 0.072, 0.32, (x, 0, 0.29), segs=12), "cloth_team")
        m.add(knee, box((0.13, 0.08, 0.12), (x, -0.07, 0.43), 0.035, rot=(0.15, 0, 0)), "armor_team")   # knee pad
        m.add(knee, box((0.14, 0.25, 0.13), (x, -0.035, 0.08), 0.04), "leather")                        # boot
        m.add(knee, box((0.15, 0.27, 0.04), (x, -0.04, 0.02), 0.012), "strap")                          # sole
        m.add(knee, cyl(0.075, 0.075, 0.05, (x, 0, 0.16), segs=12), "strap")                            # boot cuff
    # torso
    m.add("torso", cyl(0.15, 0.17, 0.26, (0, 0, 1.0), segs=14), "cloth_team")
    chest = (0.52, 0.34, 0.40) if heavy else (0.46, 0.30, 0.36)
    m.add("torso", box(chest, (0, -0.01, 1.24), 0.06), "armor_team")
    m.add("torso", box((chest[0] * 0.72, 0.05, 0.22), (0, -0.01 - chest[1] / 2, 1.27), 0.02), "plate")
    for i in range(3):
        m.add("torso", box((0.085, 0.06, 0.1), ((i - 1) * 0.1, -0.19 - (0.02 if heavy else 0), 1.11), 0.015), "strap")
    m.add("torso", cyl(0.13, 0.12, 0.07, (0, 0, 1.44), segs=14), "strap")                     # collar
    # shoulder pads sit on the torso so they stay put while the arms aim
    for s in (-1, 1):
        if heavy:
            m.add("torso", pauldron(0.17, (0.29 * s, 0, 1.42), s), "armor_team")
            m.add("torso", box((0.17, 0.24, 0.05), (0.33 * s, 0, 1.34), 0.02, rot=(0, -0.5 * s, 0)), "plate")
            m.add("torso", box((0.04, 0.16, 0.05), (0.43 * s, 0, 1.41), 0.01, rot=(0, -0.5 * s, 0)), "mark_team")
        else:
            m.add("torso", pauldron(0.135, (0.27 * s, 0, 1.425), s), "armor_team")
            m.add("torso", box((0.03, 0.12, 0.04), (0.375 * s, 0, 1.40), 0.01, rot=(0, -0.6 * s, 0)), "mark_team")
    # arms: upper arm, elbow pad, forearm, big glove
    for s, side in ((-1, "r"), (1, "l")):
        x = ax * s
        arm, elbow = "arm_" + side, "elbow_" + side
        m.add(arm, cyl(0.06, 0.068, UPPER, (x, 0, SHOULDER_Z - UPPER / 2), segs=10), "cloth_team")
        m.add(elbow, sphere(0.068, (x, 0, SHOULDER_Z - UPPER), (1, 1, 0.9)), "strap")
        fz = SHOULDER_Z - UPPER - FORE / 2
        m.add(elbow, cyl(0.056, 0.064, FORE, (x, 0, fz), segs=10), "armor_team" if heavy else "cloth_team")
        m.add(elbow, cyl(0.068, 0.068, 0.07, (x, 0, fz - 0.05), segs=10), "strap")                 # glove cuff
        m.add(elbow, box((0.085, 0.1, 0.11), (x, -0.01, SHOULDER_Z - UPPER - FORE - 0.04), 0.03), "strap")
    # head: neck, face; helmets per class below
    m.add("head", cyl(0.065, 0.06, 0.1, (0, 0, 1.5), segs=10), "skin")
    m.add("head", sphere(0.13, (0, -0.005, 1.61), (0.95, 1.0, 1.08)), "skin")
    m.add("head", box((0.04, 0.05, 0.05), (0, -0.13, 1.6), 0.015), "skin")                       # nose


def pauldron(r, at, side):
    """Domed shoulder plate tilted down over the arm."""
    bm = sphere(r, (0, 0, 0), (1.0, 1.15, 0.62), segs=16, rings=10)
    cut(bm, (0, 0, -r * 0.18), (0, 0, 1))
    return _place(bm, at, rot=(0, -0.35 * side, 0))


def helmet(m, z=1.66, r=0.178, brim=True, flat=0.82):
    bm = sphere(r, (0, 0.005, z), (1.0, 1.06, flat), segs=18, rings=10)
    cut(bm, (0, 0, z - 0.035), (0, 0, 1))
    m.add("head", bm, "armor_team")
    if brim:
        m.add("head", cyl(r + 0.012, r + 0.004, 0.03, (0, 0.005, z - 0.03), segs=18), "plate")


def goggles(m, z=1.625, w=0.25):
    m.add("head", box((w, 0.06, 0.065), (0, -0.115, z), 0.025), "visor")
    m.add("head", box((w + 0.03, 0.04, 0.025), (0, -0.1, z + 0.045), 0.008), "strap")


# --- weapons (authored around the grip, barrel along -Y) ------------------------------
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

def build_trooper():
    m = Model("trooper")
    soldier_body(m, "trooper")
    helmet(m)
    goggles(m)
    m.add("head", box((0.05, 0.05, 0.06), (-0.17, -0.02, 1.66), 0.012), "metal")              # helmet torch / radio
    m.add("head", box((0.10, 0.05, 0.035), (0, -0.14, 1.71), 0.01), "plate")                  # NVG mount
    # radio pack with tall antenna: the trooper's silhouette marker
    m.add("torso", box((0.32, 0.16, 0.34), (0, 0.24, 1.22), 0.04), "strap")
    m.add("torso", box((0.22, 0.06, 0.24), (0, 0.33, 1.23), 0.02), "metal")
    m.add("torso", box((0.06, 0.02, 0.03), (-0.05, 0.36, 1.3), 0.005), "lens")
    m.add("torso", tube((0.11, 0.30, 1.36), (0.15, 0.36, 1.95), 0.008, 0.004, segs=6), "metal")
    m.add("torso", sphere(0.014, (0.15, 0.36, 1.95)), "metal")
    m.add("torso", capsule(0.05, 0.22, (0, 0.2, 1.43), rot=(0, math.pi / 2, 0)), "cloth_team")  # bedroll
    weapon(m, "trooper")
    growths(m)
    return m


def build_marksman():
    m = Model("marksman")
    soldier_body(m, "marksman")
    # hood over a soft cap, open at the face, with a stiff peak; monocular instead of goggles
    m.add("head", sphere(0.14, (0, 0.01, 1.67), (1.0, 1.05, 0.6)), "cloth_team")
    hood = sphere(0.178, (0, 0.025, 1.625), (1.0, 1.08, 1.08), segs=18, rings=10)
    cut(hood, (0, -0.06, 0), (0, 1, -0.25))      # open at the face
    cut(hood, (0, 0, 1.47), (0, 0, 1))
    m.add("head", hood, "cloak_team")
    m.add("head", box((0.24, 0.1, 0.025), (0, -0.12, 1.74), 0.01, rot=(-0.25, 0, 0)), "cloak_team")
    m.add("head", tube((-0.055, -0.12, 1.62), (-0.055, -0.2, 1.62), 0.028, segs=12), "metal")
    m.add("head", tube((-0.055, -0.199, 1.62), (-0.055, -0.205, 1.62), 0.022, segs=12), "lens")
    m.add("head", box((0.2, 0.05, 0.08), (0, -0.115, 1.52), 0.025), "cloak_team")                 # face scarf
    # cape over the shoulders and back, ragged ghillie strips
    cape = cyl(0.33, 0.22, 0.62, (0, 0.05, 1.12), segs=16)
    cut(cape, (0, -0.02, 0), (0, 1, 0))
    bend_noise(cape, 0.03, seed=3)
    m.add("torso", cape, "cloak_team")
    rnd = random.Random(7)
    for i in range(14):
        a = rnd.uniform(-1.4, 1.4)
        z = rnd.uniform(0.82, 1.4)
        r = 0.22 + (z - 0.82) / 0.62 * -0.09 + 0.12
        p = (math.sin(a) * r, 0.05 + math.cos(a) * r * 0.9, z)
        m.add("torso", box((0.05, 0.012, rnd.uniform(0.12, 0.22)), p, 0.004, rot=(rnd.uniform(-0.3, 0.3), 0, a)),
              "cloak_team" if i % 3 else "leather")
    m.add("torso", box((0.1, 0.05, 0.5), (0.0, 0.2, 1.1), 0.02, rot=(0, 0.6, 0)), "leather")        # rifle case strap
    weapon(m, "marksman")
    growths(m, hood=True)
    return m


def build_medic():
    m = Model("medic")
    soldier_body(m, "medic")
    helmet(m, r=0.172, flat=0.86)
    goggles(m)
    m.add("head", box((0.07, 0.04, 0.05), (0, -0.165, 1.70), 0.015), "metal")                       # headlamp
    m.add("head", box((0.05, 0.01, 0.035), (0, -0.188, 1.70), 0.008), "lamp")
    for s in (-1, 1):                                                                                 # helmet crosses
        m.add("head", box((0.01, 0.08, 0.025), (0.175 * s, 0.0, 1.67), 0.004), "red")
        m.add("head", box((0.01, 0.025, 0.08), (0.175 * s, 0.0, 1.67), 0.004), "red")
    # big white trauma pack: the medic's silhouette marker
    m.add("torso", box((0.40, 0.22, 0.46), (0, 0.27, 1.22), 0.05), "white")
    m.add("torso", box((0.34, 0.06, 0.12), (0, 0.39, 1.05), 0.03), "white")
    m.add("torso", box((0.16, 0.012, 0.05), (0, 0.385, 1.3), 0.005), "red")
    m.add("torso", box((0.05, 0.012, 0.16), (0, 0.385, 1.3), 0.005), "red")
    for s in (-1, 1):
        m.add("torso", tube((0.21 * s, 0.25, 1.0), (0.21 * s, 0.25, 1.44), 0.04, segs=10), "white")  # side canisters
        m.add("torso", box((0.03, 0.10, 0.10), (0.375 * s, 0, 1.42), 0.01, rot=(0, -0.6 * s, 0)), "white")
    for s in (-1, 1):                                                                                  # arm bands
        m.add("arm_" + ("r" if s < 0 else "l"), cyl(0.072, 0.072, 0.06, (ARM_X * s, 0, 1.26), segs=10), "white")
    m.add("arm_l", box((0.02, 0.05, 0.015), (ARM_X + 0.072, 0, 1.26), 0.003), "red")
    m.add("arm_l", box((0.02, 0.015, 0.05), (ARM_X + 0.072, 0, 1.26), 0.003), "red")
    m.add("hips", box((0.12, 0.08, 0.10), (0.1, -0.13, 0.84), 0.02), "white")                          # belt kit
    weapon(m, "medic")
    growths(m)
    return m


def build_breacher():
    m = Model("breacher")
    soldier_body(m, "breacher")
    # full-face helmet with a slit visor and chin guard
    m.add("head", sphere(0.19, (0, 0.0, 1.645), (1.0, 1.06, 0.95), segs=18, rings=10), "armor_team")
    m.add("head", box((0.28, 0.08, 0.20), (0, -0.14, 1.59), 0.05), "plate")
    m.add("head", box((0.22, 0.03, 0.035), (0, -0.183, 1.63), 0.01), "visor")
    m.add("head", box((0.2, 0.06, 0.07), (0, -0.15, 1.5), 0.025), "strap")
    m.add("head", box((0.05, 0.25, 0.04), (0, 0.0, 1.83), 0.015), "plate")                           # crest ridge
    for s in (-1, 1):
        m.add("head", box((0.03, 0.08, 0.08), (0.18 * s, -0.02, 1.62), 0.01), "metal")
    # breaching charges on the chest, tank-like back plate
    for s in (-1, 1):
        m.add("torso", box((0.08, 0.06, 0.12), (0.13 * s, -0.215, 1.3), 0.012), "amber")
    m.add("torso", box((0.40, 0.14, 0.38), (0, 0.24, 1.22), 0.04), "plate")
    m.add("torso", tube((0, 0.31, 1.05), (0, 0.31, 1.42), 0.07, segs=12), "metal")
    # forearm shield on the left arm, strapped along the outside of the forearm
    x = (ARM_X + 0.04) + 0.09
    fz = SHOULDER_Z - UPPER - FORE / 2 - 0.02
    m.add("elbow_l", box((0.05, 0.42, 0.62), (x, -0.06, fz), 0.03), "plate")
    m.add("elbow_l", box((0.055, 0.40, 0.05), (x + 0.004, -0.06, fz + 0.2), 0.01), "amber")
    m.add("elbow_l", box((0.055, 0.12, 0.035), (x + 0.004, -0.12, fz + 0.12), 0.008), "visor")     # view port
    for dz in (-0.2, 0.0):
        m.add("elbow_l", box((0.06, 0.02, 0.06), (x - 0.03, 0.08, fz + dz), 0.005), "metal")
    weapon(m, "breacher")
    growths(m, heavy=True)
    return m


def growths(m, hood=False, heavy=False):
    """Infection stages. grow1 Exposed blisters, grow2 Mutating crystal outbreak on the
    shoulder, grow3 Critical spines through the back, head and arm."""
    ax = ARM_X + (0.04 if heavy else 0.0)
    rnd = random.Random(hash(m.name) & 0xffff)
    fz = SHOULDER_Z - UPPER - FORE * 0.5
    # 1: blisters on the left forearm and neck
    m.add("elbow_l", sphere(0.07, (ax, -0.01, fz), (1.05, 1.1, 1.3)), "flesh_raw", "grow1")
    for i in range(6):
        a = rnd.uniform(-2.0, 1.5)
        m.add("elbow_l", sphere(rnd.uniform(0.016, 0.026), (ax + math.cos(a) * 0.072, math.sin(a) * 0.072, fz + rnd.uniform(-0.08, 0.08))), "glow", "grow1")
    for i in range(3):
        m.add("head", sphere(0.018, (0.06 + i * 0.012, 0.03 - i * 0.02, 1.49 + i * 0.01)), "glow", "grow1")
    # 2: crystals burst through the left shoulder pad
    sx = 0.29 if not heavy else 0.31
    m.add("torso", sphere(0.10, (sx, 0.02, 1.47), (1.1, 1.0, 0.7)), "flesh_raw", "grow2")
    for i in range(6):
        d = Vector((rnd.uniform(0.2, 1.0), rnd.uniform(-0.6, 0.6), rnd.uniform(0.5, 1.3)))
        m.add("torso", shard((sx + rnd.uniform(-0.03, 0.04), rnd.uniform(-0.04, 0.05), 1.48), d, rnd.uniform(0.1, 0.2), 0.03), "glow", "grow2")
    for i in range(4):
        m.add("leg_r", sphere(rnd.uniform(0.018, 0.028), (-0.115 - 0.085, rnd.uniform(-0.06, 0.04), rnd.uniform(0.52, 0.7))), "glow", "grow2")
    # 3: spines through the back, growth on the head, swollen arm
    for i in range(5):
        base = (rnd.uniform(-0.12, 0.12), 0.30, rnd.uniform(1.15, 1.45))
        d = Vector((base[0] * 2.0, 1.0, rnd.uniform(0.4, 1.2)))
        m.add("torso", shard(base, d, rnd.uniform(0.18, 0.3), rnd.uniform(0.035, 0.05)), "glow", "grow3")
        m.add("torso", sphere(0.05, base), "flesh_raw", "grow3")
    hz = 1.7 if not hood else 1.72
    m.add("head", sphere(0.07, (0.13, 0.03, hz - 0.04), (1, 1, 0.8)), "flesh_raw", "grow3")
    for i in range(3):
        d = Vector((1.0, rnd.uniform(-0.5, 0.5), rnd.uniform(0.6, 1.4)))
        m.add("head", shard((0.15, rnd.uniform(-0.02, 0.06), hz), d, rnd.uniform(0.1, 0.16), 0.025), "glow", "grow3")
    m.add("elbow_l", sphere(0.1, (ax + 0.02, 0.0, fz + 0.03), (1.0, 1.1, 1.4)), "flesh_raw", "grow3")
    for i in range(3):
        d = Vector((1.0, rnd.uniform(-0.6, 0.6), rnd.uniform(-0.6, 0.8)))
        m.add("elbow_l", shard((ax + 0.08, rnd.uniform(-0.05, 0.05), fz + rnd.uniform(-0.05, 0.1)), d, 0.12, 0.022), "glow", "grow3")


# --- infected humanoid rig (Runner, Spitter; Shrieker / Bloater later) ---------------------
E_HIP = 0.64
E_KNEE = 0.33
E_TORSO = 0.68


def infected_joints(m, shoulder_x, shoulder_z, upper, head_at):
    m.joint("hips", (0, 0, E_HIP))
    m.joint("torso", (0, 0, E_TORSO), "hips")
    m.joint("head", head_at, "torso")
    for s, side in ((-1, "r"), (1, "l")):
        m.joint("leg_" + side, (0.11 * s, 0, E_HIP), "hips")
        m.joint("knee_" + side, (0.11 * s, -0.02, E_KNEE), "leg_" + side)
        m.joint("arm_" + side, (shoulder_x * s, -0.06, shoulder_z), "torso")
        m.joint("elbow_" + side, (shoulder_x * s, -0.06, shoulder_z - upper), "arm_" + side)


def infected_legs(m, thick, seed):
    for s, side in ((-1, "r"), (1, "l")):
        x = 0.11 * s
        leg, knee = "leg_" + side, "knee_" + side
        m.add(leg, skin([(x, 0, E_HIP + 0.02), (x, -0.025, 0.54), (x, -0.02, 0.43), (x, -0.02, E_KNEE)], [(0, 1), (1, 2), (2, 3)],
                        [0.075 * thick, 0.085 * thick, 0.065 * thick, 0.048 * thick], wobble=0.014, seed=seed + s), "flesh")
        m.add(knee, skin([(x, -0.02, E_KNEE), (x, 0.03, 0.24), (x, 0.03, 0.13), (x, 0.04, 0.05), (x, -0.06, 0.02)],
                         [(0, 1), (1, 2), (2, 3), (3, 4)], [0.048 * thick, 0.055 * thick, 0.038 * thick, 0.032, 0.04],
                         wobble=0.01, seed=seed + 2 * s), "flesh")
        for k in range(3):   # clawed toes
            m.add(knee, shard((x + (k - 1) * 0.025, -0.08, 0.02), (0.0, -1.0, -0.25), 0.07, 0.012, 4), "bone")
        m.add(knee, cyl(0.058 * thick, 0.05 * thick, 0.05, (x, -0.02, E_KNEE + 0.02), segs=9), "rags")
        m.add(knee, sphere(0.056 * thick, (x, -0.025, E_KNEE), (1, 1.1, 1)), "flesh")              # knee joint
        m.add(leg, sphere(0.08 * thick, (x, 0, E_HIP + 0.01)), "flesh")                            # hip joint


def rags(m, r, z, seed):
    """Torn remains of quarantine coveralls: a waistband and hanging strips."""
    m.add("hips", cyl(r * 1.05, r * 1.1, 0.06, (0, 0, z - 0.14), segs=12), "rags")
    rnd = random.Random(seed + 99)
    for i in range(9):
        a = i / 9.0 * math.tau + rnd.uniform(-0.2, 0.2)
        ln = rnd.uniform(0.1, 0.24)
        p = (math.sin(a) * r * 1.1, math.cos(a) * r * 1.0, z - 0.14 - ln * 0.5)
        m.add("hips", box((0.06, 0.012, ln), p, 0.004, rot=(rnd.uniform(-0.25, 0.25), rnd.uniform(-0.2, 0.2), -a)), "rags")
    for i in range(4):   # shreds stuck to the chest
        a = rnd.uniform(-1.2, 1.2) + (math.pi if i % 2 else 0)
        m.add("torso", box((0.08, 0.012, 0.1), (math.sin(a) * r * 1.15, math.cos(a) * r * 0.95, z + rnd.uniform(0.05, 0.18)),
                           0.004, rot=(rnd.uniform(-0.3, 0.3), 0, -a)), "rags")


def build_runner():
    m = Model("runner")
    seed = 11
    infected_joints(m, 0.2, 1.17, 0.31, (0, -0.1, 1.27))
    infected_legs(m, 1.0, seed)
    # pelvis in torn coveralls
    m.add("hips", skin([(0, 0, 0.6), (0, 0, 0.72)], [(0, 1)], [(0.14, 0.1), (0.13, 0.09)], wobble=0.008), "flesh")
    # gaunt, hunched torso: spine curves forward, ribcage shows through tears
    spine = [(0, 0.0, 0.70), (0, 0.02, 0.86), (0, 0.0, 1.02), (0, -0.05, 1.15), (0, -0.08, 1.22)]
    m.add("torso", skin(spine, [(i, i + 1) for i in range(4)], [(0.11, 0.08), (0.12, 0.09), (0.16, 0.11), (0.15, 0.1), (0.07, 0.06)],
                        wobble=0.012, seed=seed), "flesh")
    rags(m, 0.13, 0.84, seed)
    for s in (-1, 1):
        for i in range(4):   # ribs
            z = 0.96 + i * 0.05
            m.add("torso", tube((0.05 * s, -0.115, z), (0.14 * s, -0.02, z + 0.02), 0.011, segs=6), "bone")
    rnd = random.Random(seed)
    # crystals erupting along the spine: silhouette marker for Infected
    for i in range(7):
        z = 0.9 + i * 0.055
        base = (rnd.uniform(-0.05, 0.05), 0.09 + 0.03 * math.sin(i), z)
        m.add("torso", shard(base, (rnd.uniform(-0.6, 0.6), 1.0, rnd.uniform(0.3, 1.0)), rnd.uniform(0.1, 0.22), 0.03), "glow")
    for i in range(6):
        a = rnd.uniform(-3.0, 3.0)
        m.add("torso", sphere(rnd.uniform(0.02, 0.035), (math.sin(a) * 0.15, math.cos(a) * 0.1, rnd.uniform(0.85, 1.12))), "glow")
    # head: elongated skull, split jaw, glowing eyes
    hx, hy, hz = 0, -0.1, 1.27
    m.add("head", skin([(0, -0.06, 1.17), (0, -0.1, 1.27), (0, -0.16, 1.31), (0, -0.22, 1.30)], [(0, 1), (1, 2), (2, 3)],
                       [0.05, 0.09, 0.1, 0.06], wobble=0.008, seed=seed + 5), "flesh")
    m.add("head", skin([(0, -0.13, 1.24), (0, -0.25, 1.19)], [(0, 1)], [(0.06, 0.03), (0.04, 0.02)]), "flesh_raw")   # lower jaw
    for s in (-1, 1):
        m.add("head", sphere(0.018, (0.045 * s, -0.27, 1.31), (1.2, 0.8, 0.8)), "glow")
        for k in range(3):
            m.add("head", shard((0.03 * s * (k - 1) * 0.6, -0.23, 1.255), (0, -0.2, -1), 0.03, 0.006, 4), "bone")
    m.add("head", sphere(0.03, (0, -0.21, 1.25)), "glow")                                                        # throat glow
    for i in range(3):
        m.add("head", shard((rnd.uniform(-0.04, 0.04), -0.08, 1.35), (rnd.uniform(-0.5, 0.5), 0.6, 1.0), 0.09, 0.018), "glow")
    m.joint("muzzle", (0, -0.27, 1.24), "head")
    # long arms ending in bone blades
    for s, side in ((-1, "r"), (1, "l")):
        x = 0.2 * s
        arm, elbow = "arm_" + side, "elbow_" + side
        m.add(arm, skin([(x, -0.06, 1.18), (x, -0.05, 1.03), (x, -0.06, 0.86)], [(0, 1), (1, 2)], [0.06, 0.058, 0.042],
                        wobble=0.012, seed=seed + 7 * s), "flesh")
        m.add(elbow, skin([(x, -0.06, 0.86), (x, -0.055, 0.76), (x, -0.06, 0.6), (x, -0.07, 0.55)], [(0, 1), (1, 2), (2, 3)],
                          [0.042, 0.048, 0.032, 0.042], wobble=0.012, seed=seed + 9 * s), "flesh")
        for k in range(3):
            m.add(elbow, shard((x + (k - 1) * 0.022, -0.07, 0.54), ((k - 1) * 0.15, -0.35, -1.0), 0.22, 0.014, 4), "bone")
        m.add(elbow, sphere(0.022, (x + 0.03 * s, -0.04, 0.72)), "glow")
        m.add(arm, cyl(0.07, 0.065, 0.08, (x, -0.06, 1.06), segs=9), "rags")
        m.add(elbow, sphere(0.05, (x, -0.06, 0.86)), "flesh")
        m.add(arm, sphere(0.065, (x, -0.06, 1.18)), "flesh")
    return m


def build_spitter():
    m = Model("spitter")
    seed = 23
    infected_joints(m, 0.24, 1.14, 0.26, (0, -0.16, 1.24))
    infected_legs(m, 1.3, seed)
    m.add("hips", skin([(0, 0, 0.6), (0, 0, 0.74)], [(0, 1)], [(0.17, 0.13), (0.18, 0.13)], wobble=0.01), "flesh")
    # swollen torso, translucent glowing sac on the back
    spine = [(0, 0.0, 0.70), (0, 0.03, 0.85), (0, 0.02, 1.0), (0, -0.06, 1.14), (0, -0.12, 1.2)]
    m.add("torso", skin(spine, [(i, i + 1) for i in range(4)], [(0.15, 0.13), (0.2, 0.17), (0.22, 0.18), (0.17, 0.14), (0.09, 0.08)],
                        wobble=0.02, seed=seed), "flesh")
    m.joint("sac", (0, 0.2, 1.08), "torso")
    sac = sphere(0.24, (0, 0.2, 1.08), (1.0, 0.85, 1.1), segs=18, rings=12)
    bend_noise(sac, 0.04, scale=9.0, seed=5)
    m.add("sac", sac, "sac")
    rnd = random.Random(seed)
    for i in range(7):   # veins over the sac
        a = rnd.uniform(-1.2, 1.2)
        b = rnd.uniform(-0.8, 0.9)
        p = Vector((math.sin(a) * 0.24 * math.cos(b), 0.2 + math.cos(a) * 0.2 * math.cos(b), 1.08 + math.sin(b) * 0.26))
        m.add("sac", tube(p, p + Vector((0, 0, 0.12)).normalized() * 0.1 + (p - Vector((0, 0.2, 1.08))) * 0.08, 0.012, 0.006, segs=5), "flesh_raw")
    for i in range(10):
        a = rnd.uniform(-2.6, 2.6)
        m.add("torso", sphere(rnd.uniform(0.025, 0.05), (math.sin(a) * 0.21, math.cos(a) * 0.16 - 0.02, rnd.uniform(0.78, 1.1))), "glow")
    rags(m, 0.19, 0.82, seed)
    # head sunk into the shoulders, huge distended jaw and throat sac
    m.add("head", skin([(0, -0.08, 1.16), (0, -0.16, 1.24), (0, -0.23, 1.27)], [(0, 1), (1, 2)],
                       [0.08, 0.1, 0.07], wobble=0.01, seed=seed + 3), "flesh")
    m.add("head", skin([(0, -0.14, 1.17), (0, -0.29, 1.12)], [(0, 1)], [(0.08, 0.05), (0.07, 0.04)], wobble=0.006), "flesh_raw")
    m.add("head", sphere(0.075, (0, -0.17, 1.1), (1.1, 1.0, 0.9)), "sac")                                        # throat sac
    m.add("head", sphere(0.04, (0, -0.25, 1.2)), "glow")
    for s in (-1, 1):
        m.add("head", sphere(0.016, (0.05 * s, -0.29, 1.29), (1.2, 0.8, 0.8)), "glow")
        m.add("head", sphere(0.013, (0.025 * s, -0.27, 1.32), (1.2, 0.8, 0.8)), "glow")
    m.joint("muzzle", (0, -0.31, 1.2), "head")
    for s, side in ((-1, "r"), (1, "l")):
        x = 0.24 * s
        arm, elbow = "arm_" + side, "elbow_" + side
        m.add(arm, skin([(x, -0.06, 1.15), (x, -0.06, 0.88)], [(0, 1)], [0.07, 0.055], wobble=0.01, seed=seed + 7 * s), "flesh")
        m.add(elbow, skin([(x, -0.06, 0.88), (x, -0.07, 0.68), (x, -0.08, 0.64)], [(0, 1), (1, 2)], [0.055, 0.045, 0.055],
                          wobble=0.01, seed=seed + 9 * s), "flesh")
        for k in range(3):
            m.add(elbow, shard((x + (k - 1) * 0.025, -0.08, 0.63), ((k - 1) * 0.2, -0.3, -1.0), 0.11, 0.013, 4), "bone")
        m.add(arm, sphere(0.03, (x + 0.05 * s, -0.04, 1.04)), "glow")
        m.add(elbow, sphere(0.06, (x, -0.06, 0.88)), "flesh")
        m.add(arm, sphere(0.08, (x, -0.06, 1.15)), "flesh")
    return m


MODELS = {
    "trooper": build_trooper, "marksman": build_marksman, "medic": build_medic,
    "breacher": build_breacher, "runner": build_runner, "spitter": build_spitter,
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
