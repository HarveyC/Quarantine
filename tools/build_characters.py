"""Builds the character models from CC0 Quaternius assets plus our own gear and
infection growths. Output goes to assets/characters/.

Source art (CC0, see assets/characters/CREDITS.md) comes from the GitHub prerelease
`cc0-assets-1`. Download and unzip it first:
    mkdir -p ~/cc0 && cd ~/cc0 && (download the release zips) && unzip each into ~/cc0/x/<zip name>/
then run with Blender 4.2+ or the bpy module:
    python3 tools/build_characters.py [--src ~/cc0/x] [names...]

What it makes:
  * anims_ual1.glb / anims_ual2.glb: the clips the game uses from the Universal
    Animation Library 1 and 2 (in place, UE-style humanoid skeleton).
  * One .glb per unit kind: a Universal Base Characters body on that same skeleton,
    with gear (helmets, vests, weapons, class kit) or infection growths parented to
    bones. Gear and growths are built with the primitives from gen_models.py.
Every character keeps its armature named "Armature" so the shared clips' track paths
(Armature/Skeleton3D:<bone>) bind to any of them. Material names are the character
shader roles (see view/model_kit.gd); the textured body material becomes "body".
Meshes named "grow1_*", "grow2_*", "grow3_*" are infection stages; "gun" holds the
weapon with "muzzle" and "support" empties; enemies may have "muzzle" on the head.
Coordinates: Blender Z up, characters face -Y, right hand at -X (T-pose rest).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_models as G  # noqa: E402  (imports bpy first)
import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

ROOT = G.ROOT
OUT = os.path.join(ROOT, "assets", "characters")
SRC = os.path.expanduser("~/cc0/x")
UBC = "Quaternius_UniversalBaseCharacters_Standard/Universal Base Characters[Standard]/Base Characters/Godot - UE/"
UAL1 = "Quaternius_UniversalAnimationLibrary_Standard/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb"
UAL2 = "Quaternius_UniversalAnimationLibrary2_Standard/Universal Animation Library 2[Standard]/Unreal-Godot/UAL2_Standard.glb"

# Clips the game plays (see view/skinned_body.gd); everything else is dropped.
CLIPS_UAL1 = [
    "Idle_Loop", "Walk_Loop", "Jog_Fwd_Loop", "Sprint_Loop", "Crouch_Idle_Loop", "Crouch_Fwd_Loop",
    "Pistol_Aim_Neutral", "Pistol_Idle_Loop", "Pistol_Shoot", "Hit_Chest", "Hit_Head", "Death01",
    "Punch_Cross", "Jump_Start", "Jump_Loop", "Jump_Land", "Spell_Simple_Shoot", "Roll", "Interact",
]
CLIPS_UAL2 = [
    "Zombie_Idle_Loop", "Zombie_Walk_Fwd_Loop", "Zombie_Scratch", "OverhandThrow", "Idle_Rail_Call",
    "Hit_Knockback", "Idle_Shield_Loop", "Shield_OneShot", "Consume", "Idle_FoldArms_Loop",
]

# UBC male rest pose landmarks (metres), used to fit gear.
HEAD_C = Vector((0, -0.005, 1.715))
CHEST_Z = 1.33
SHOULDER = Vector((0.212, 0.065, 1.456))
ELBOW_X = 0.463
WRIST_X = 0.706
KNEE_Z = 0.542
HAND_R = Vector((-0.74, 0.065, 1.456))


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def export(name, animations=False):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".glb")
    # Textures are shared (assets/characters/textures, loaded by the shader), not embedded.
    kw = dict(filepath=path, export_format="GLB", export_yup=True, export_apply=False,
              export_cameras=False, export_lights=False, export_extras=False,
              export_animations=animations, export_image_format="NONE",
              export_vertex_color="ACTIVE")
    if animations:
        kw.update(export_animation_mode="ACTIONS", export_force_sampling=True, export_optimize_animation_size=True)
    bpy.ops.export_scene.gltf(**kw)
    print("wrote %s (%.1f MB)" % (path, os.path.getsize(path) / 1e6))


# --- animation libraries ------------------------------------------------------------

def build_anims(src_rel, keep, name):
    G.fresh_scene()
    objs = import_glb(os.path.join(SRC, src_rel))
    arm = next(o for o in objs if o.type == "ARMATURE")
    arm.name = "Armature"
    for o in objs:
        if o.type == "MESH":
            bpy.data.objects.remove(o)
    ad = arm.animation_data
    for tr in list(ad.nla_tracks):
        if tr.name not in keep:
            ad.nla_tracks.remove(tr)
    for a in list(bpy.data.actions):
        if a.name not in keep:
            bpy.data.actions.remove(a)
    ad.action = None
    missing = [k for k in keep if k not in bpy.data.actions]
    if missing:
        print("missing clips:", missing)
    export(name, animations=True)


# --- bodies and gear --------------------------------------------------------------------

class Rig:
    """A UBC body plus parts parented to its bones."""

    def __init__(self, name, body="male"):
        G.fresh_scene()
        self.name = name
        f = "Superhero_Male_FullBody.gltf" if body == "male" else "Superhero_Female_FullBody.gltf"
        objs = import_glb(os.path.join(SRC, UBC, f))
        self.arm = next(o for o in objs if o.type == "ARMATURE")
        self.arm.name = "Armature"
        for o in objs:
            if o.type == "MESH":
                if o.parent is None:
                    bpy.data.objects.remove(o)       # stray icosphere
                else:
                    for slot in o.material_slots:
                        if slot.material and slot.material.name.startswith("MI_Superhero"):
                            slot.material.name = "body"
                        elif slot.material and slot.material.name.startswith("MI_Hair"):
                            slot.material.name = "hair"
                        elif slot.material and slot.material.name.startswith("MI_Eyes"):
                            slot.material.name = "eyes"
        self.parts = {}      # (bone, object name) -> [(bm, role)]
        self.origins = {}    # object name -> world pivot (default: the world origin)
        self.empties = []    # (name, bone or parent object, world pos)

    def add(self, bone, bm, role, name=None):
        key = (bone, name or (bone + "_gear"))
        self.parts.setdefault(key, []).append((bm, role))

    def empty(self, name, bone, pos):
        self.empties.append((name, bone, Vector(pos)))

    def body(self):
        return next(o for o in bpy.data.objects if o.type == "MESH" and any(m and m.name == "body" for m in o.data.materials))

    def clothe(self, name, keep, inflate, role, wrinkle=0.006, seed=1):
        """A skinned garment: the body faces where `keep(world pos)` holds, pushed out
        along their normals. Being a copy of the body it keeps its bone weights."""
        src = self.body()
        ob = src.copy()
        ob.data = src.data.copy()
        ob.name = name
        bpy.context.scene.collection.objects.link(ob)
        mw = ob.matrix_world
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        dead = [f for f in bm.faces if not all(keep(mw @ v.co) for v in f.verts)]
        bmesh.ops.delete(bm, geom=dead, context="FACES")
        bm.normal_update()
        rnd = random.Random(seed)
        noise = {}
        for v in bm.verts:
            w = mw @ v.co
            k = (round(w.x * 14), round(w.y * 14), round(w.z * 9))
            n = noise.setdefault(k, rnd.uniform(-1, 1))
            v.co += v.normal * ((inflate(w) if callable(inflate) else inflate) + n * wrinkle)
        bm.to_mesh(ob.data)
        bm.free()
        ob.data.materials.clear()
        ob.data.materials.append(G.material(role))
        for poly in ob.data.polygons:
            poly.material_index = 0
            poly.use_smooth = True
        return ob

    def drop_meshes(self, *names):
        for o in list(bpy.data.objects):
            if o.type == "MESH" and any(o.name.startswith(n) for n in names):
                bpy.data.objects.remove(o)

    def build(self):
        bpy.context.view_layer.update()
        for (bone, oname), items in self.parts.items():
            me = bpy.data.meshes.new(oname)
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
            bmesh.ops.recalc_face_normals(bm_all, faces=bm_all.faces)
            pivot = self.origins.get(oname)
            if pivot is not None:
                bmesh.ops.translate(bm_all, verts=bm_all.verts, vec=-pivot)
            bm_all.to_mesh(me)
            bm_all.free()
            for r in roles:
                me.materials.append(G.material(r))
            for p in me.polygons:
                p.use_smooth = True
            if hasattr(me, "set_sharp_from_angle"):
                me.set_sharp_from_angle(angle=math.radians(38))
            ob = bpy.data.objects.new(oname, me)
            bpy.context.scene.collection.objects.link(ob)
            self._bone_parent(ob, bone, pivot)
        for name, bone, pos in self.empties:
            e = bpy.data.objects.new(name, None)
            e.empty_display_size = 0.03
            bpy.context.scene.collection.objects.link(e)
            if bone in bpy.data.objects:          # parented to another part (e.g. the gun)
                e.parent = bpy.data.objects[bone]
                bpy.context.view_layer.update()
                e.matrix_world = Matrix.Translation(pos)
            else:
                self._bone_parent(e, bone, pos)
        bpy.context.view_layer.update()

    def bake_rest_colors(self):
        """Vertex colour = rest position (rgb, so surface noise doesn't swim when skinned)
        plus a skin mask in alpha (head and hands of the body)."""
        for ob in bpy.data.objects:
            if ob.type != "MESH":
                continue
            me = ob.data
            mw = ob.matrix_world
            for c in list(me.color_attributes):
                me.color_attributes.remove(c)
            while len(me.uv_layers) > 1:
                me.uv_layers.remove(me.uv_layers[-1])
            attr = me.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="POINT")
            body = any(m and m.name == "body" for m in me.materials)
            skin = []
            for v in me.vertices:
                w = mw @ v.co
                skin.append(1.0 if body and (w.z > 1.53 or abs(w.x) > 0.7) else 0.0)
                attr.data[v.index].color = (w.x * 0.5 + 0.5, w.y * 0.5 + 0.5, w.z / 2.5, 1.0)
            me.color_attributes.active_color = attr
            me.color_attributes.render_color_index = me.color_attributes.active_color_index
            if body:      # the glTF exporter drops vertex alpha, so the mask rides in UV2
                uv = me.uv_layers.new(name="SkinMask")
                for loop in me.loops:
                    uv.data[loop.index].uv = (skin[loop.vertex_index], 0.0)

    def _bone_parent(self, ob, bone, pos=None):
        ob.parent = self.arm
        ob.parent_type = "BONE"
        ob.parent_bone = bone
        bpy.context.view_layer.update()
        ob.matrix_world = Matrix.Translation(pos) if pos is not None else Matrix.Identity(4)

    def export(self):
        self.build()
        self.bake_rest_colors()
        export(self.name)


def mirror(fn):
    for s, side in ((-1, "r"), (1, "l")):
        fn(s, side)


# --- soldier kit ------------------------------------------------------------------------

def fatigues(r, sleeve=0.56, boot=0.16):
    """Combat shirt and trousers over the base body (sleeves to `sleeve` metres out)."""
    # baggy through the thighs, bloused into the boots, snug at the shoulders
    def puff(p):
        return 0.014 + 0.02 * max(0.0, 1.0 - abs(p.z - 0.72) / 0.32) + (0.01 if p.z < 0.3 else 0.0)
    r.clothe("uniform", lambda p: boot < p.z < 1.5 and abs(p.x) < sleeve and not (p.z > 1.44 and abs(p.x) < 0.09 and p.y < 0),
             puff, "cloth_team", wrinkle=0.008)
    for s in (-1, 1):   # cuffs
        side = "r" if s < 0 else "l"
        r.add("lowerarm_" + side, G.tube(((sleeve - 0.03) * s, 0.065, 1.456), ((sleeve + 0.005) * s, 0.065, 1.456), 0.047), "strap")


def soldier_kit(r, kind):
    heavy = kind == "breacher"
    w = 1.12 if heavy else 1.0
    fatigues(r)
    # belt with pouches
    r.add("pelvis", G.cyl(0.165 * w, 0.17 * w, 0.06, (0, 0.01, 0.99), segs=16), "strap")
    for s in (-1, 1):
        r.add("pelvis", G.box((0.07, 0.10, 0.09), (0.17 * s * w, 0.0, 0.97), 0.015), "strap")
    r.add("pelvis", G.box((0.16, 0.07, 0.08), (0, 0.15, 0.97), 0.015), "strap")
    r.add("pelvis", G.box((0.06, 0.03, 0.05), (0, -0.155, 0.99), 0.01), "metal")
    # plate carrier
    vest = (0.42 * w, 0.30 * w, 0.36 * w)
    r.add("spine_03", G.box(vest, (0, 0.0, 1.31), 0.06), "armor_team")
    r.add("spine_03", G.box((vest[0] * 0.72, 0.05, 0.22), (0, -vest[1] / 2 - 0.005, 1.33), 0.02), "plate")
    for i in range(3):
        r.add("spine_02", G.box((0.085, 0.06, 0.1), ((i - 1) * 0.1, -0.175 * w, 1.17), 0.015), "strap")
    r.add("spine_03", G.cyl(0.105, 0.095, 0.06, (0, 0.03, 1.5), segs=14), "strap")          # collar
    # shoulder pads ride the upper arm so they follow it
    def pads(s, side):
        rr = 0.13 if heavy else 0.1
        bm = G.sphere(rr, (0, 0, 0), (1.1, 1.0, 0.5), segs=16, rings=10)
        G.cut(bm, (0, 0, -rr * 0.18), (0, 0, 1))
        r.add("upperarm_" + side, G._place(bm, (0.25 * s, 0.065, 1.49), rot=(0, 0.3 * s, 0)), "armor_team")
        r.add("upperarm_" + side, G.box((0.08, 0.025, 0.03), (0.27 * s, -0.03, 1.5), 0.006, rot=(0, 0.3 * s, 0)), "mark_team")
        if heavy:
            r.add("upperarm_" + side, G.box((0.2, 0.2, 0.05), (0.3 * s, 0.065, 1.46), 0.02, rot=(0, 0.6 * s, 0)), "plate")
        # elbow pad, forearm guard, glove
        r.add("lowerarm_" + side, G.sphere(0.055, (ELBOW_X * s, 0.07, 1.456), (1, 1, 0.9)), "strap")
        r.add("lowerarm_" + side, G.tube((0.52 * s, 0.065, 1.456), (0.68 * s, 0.065, 1.456), 0.05, 0.045),
              "armor_team" if heavy else "strap")
        r.add("hand_" + side, G.box((0.1, 0.095, 0.05), (0.77 * s, 0.06, 1.45), 0.02), "strap")
        # knee pad, boot shell
        x = 0.114 * s
        r.add("calf_" + side, G.box((0.12, 0.08, 0.12), (x, -0.03, KNEE_Z), 0.035), "armor_team")
        r.add("foot_" + side, G.box((0.13, 0.27, 0.12), (x, -0.025, 0.06), 0.04), "leather")
        r.add("foot_" + side, G.box((0.14, 0.29, 0.035), (x, -0.03, 0.018), 0.012), "strap")
        r.add("calf_" + side, G.cyl(0.065, 0.068, 0.07, (x, 0.07, 0.16), segs=12), "strap")
        r.add("thigh_" + side, G.box((0.05, 0.12, 0.13), (x + 0.085 * s, 0.03, 0.72), 0.02), "cloth_team")
        if heavy:
            r.add("thigh_" + side, G.box((0.16, 0.06, 0.2), (x, -0.07, 0.75), 0.025), "armor_team")
    mirror(pads)


def helmet(r, crest=False):
    bm = G.sphere(0.138, (0, 0.0, HEAD_C.z + 0.02), (1.0, 1.1, 0.86), segs=18, rings=10)
    G.cut(bm, (0, 0, HEAD_C.z - 0.0), (0, 0, 1))
    r.add("Head", bm, "armor_team")
    r.add("Head", G.cyl(0.148, 0.142, 0.025, (0, 0.0, HEAD_C.z + 0.005), segs=18), "plate")


def goggles(r):
    r.add("Head", G.box((0.2, 0.05, 0.055), (0, -0.11, 1.715), 0.02), "visor")
    r.add("Head", G.box((0.25, 0.03, 0.02), (0, -0.095, 1.755), 0.006), "strap")


# Where the weapon's grip sits when shouldered and aimed (the game poses it from there).
GUN_AIM = Vector((-0.12, -0.3, 1.38))


def weapon(r, kind):
    """Rifle on its own pivot at the grip, riding the chest bone; the game poses it
    (low ready / aimed / recoil) and puts both hands on it by IK."""
    m = G.Model("tmp")
    G.GUN_AT = GUN_AIM.copy()
    G.weapon(m, kind)
    for bm, role in m.parts["gun_mesh"]:
        r.add("spine_03", bm, role, "gun")
    r.origins["gun"] = GUN_AIM.copy()
    for nm in ("muzzle", "support"):
        r.empty(nm, "gun", m.joints[nm][0])


def growths(r, heavy=False):
    rnd = random.Random(hash(r.name) & 0xffff)
    # 1: blisters along the left forearm and neck
    r.add("lowerarm_l", G.sphere(0.06, (0.58, 0.06, 1.47), (1.4, 1.0, 1.05)), "flesh_raw", "grow1_arm")
    for i in range(6):
        r.add("lowerarm_l", G.sphere(rnd.uniform(0.016, 0.026), (rnd.uniform(0.5, 0.66), 0.06 + rnd.uniform(-0.05, 0.05), 1.5 + rnd.uniform(-0.02, 0.03))), "glow", "grow1_arm")
    for i in range(3):
        r.add("neck_01", G.sphere(0.017, (0.05 + i * 0.012, 0.06 - i * 0.02, 1.55 + i * 0.01)), "glow", "grow1_neck")
    # 2: crystals burst through the left shoulder
    base = Vector((0.2, 0.05, 1.55))
    r.add("spine_03", G.sphere(0.09, tuple(base), (1.1, 1.0, 0.7)), "flesh_raw", "grow2_shoulder")
    for i in range(6):
        d = Vector((rnd.uniform(0.2, 1.0), rnd.uniform(-0.6, 0.6), rnd.uniform(0.5, 1.3)))
        r.add("spine_03", G.shard(tuple(base + Vector((rnd.uniform(-0.03, 0.04), rnd.uniform(-0.04, 0.05), 0))), d, rnd.uniform(0.1, 0.2), 0.03), "glow", "grow2_shoulder")
    for i in range(4):
        r.add("thigh_r", G.sphere(rnd.uniform(0.018, 0.028), (-0.2, rnd.uniform(-0.04, 0.06), rnd.uniform(0.62, 0.8))), "glow", "grow2_thigh")
    # 3: spines through the back, a growth on the head, a swollen arm
    for i in range(5):
        b = (rnd.uniform(-0.1, 0.1), 0.2, rnd.uniform(1.2, 1.45))
        r.add("spine_03", G.shard(b, (b[0] * 2.0, 1.0, rnd.uniform(0.4, 1.2)), rnd.uniform(0.18, 0.3), rnd.uniform(0.035, 0.05)), "glow", "grow3_back")
        r.add("spine_03", G.sphere(0.045, b), "flesh_raw", "grow3_back")
    r.add("Head", G.sphere(0.06, (0.1, 0.02, 1.78), (1, 1, 0.8)), "flesh_raw", "grow3_head")
    for i in range(3):
        r.add("Head", G.shard((0.12, rnd.uniform(-0.02, 0.05), 1.8), (1.0, rnd.uniform(-0.5, 0.5), rnd.uniform(0.6, 1.4)), rnd.uniform(0.1, 0.16), 0.024), "glow", "grow3_head")
    r.add("lowerarm_l", G.sphere(0.085, (0.6, 0.06, 1.47), (1.6, 1.1, 1.1)), "flesh_raw", "grow3_arm")
    for i in range(3):
        r.add("lowerarm_l", G.shard((rnd.uniform(0.55, 0.65), 0.06, 1.53), (rnd.uniform(-0.5, 0.5), rnd.uniform(-0.6, 0.6), 1.0), 0.12, 0.022), "glow", "grow3_arm")


def build_soldier(kind):
    r = Rig(kind)
    r.drop_meshes("Eyebrows")
    soldier_kit(r, kind)
    if kind == "trooper":
        helmet(r)
        goggles(r)
        r.add("spine_03", G.box((0.30, 0.15, 0.32), (0, 0.22, 1.3), 0.04), "strap")
        r.add("spine_03", G.box((0.2, 0.05, 0.22), (0, 0.31, 1.3), 0.02), "metal")
        r.add("spine_03", G.tube((0.1, 0.28, 1.42), (0.14, 0.34, 1.98), 0.008, 0.004, segs=6), "metal")
        r.add("spine_03", G.capsule(0.05, 0.22, (0, 0.18, 1.5), rot=(0, math.pi / 2, 0)), "cloth_team")
    elif kind == "marksman":
        r.add("Head", G.sphere(0.13, (0, 0.01, 1.76), (1.0, 1.05, 0.6)), "cloth_team")
        hood = G.sphere(0.165, (0, 0.02, 1.71), (1.0, 1.1, 1.1), segs=18, rings=10)
        G.cut(hood, (0, -0.05, 0), (0, 1, -0.25))
        G.cut(hood, (0, 0, 1.56), (0, 0, 1))
        r.add("Head", hood, "cloak_team")
        r.add("Head", G.box((0.22, 0.09, 0.022), (0, -0.115, 1.81), 0.008, rot=(-0.25, 0, 0)), "cloak_team")
        r.add("Head", G.tube((-0.05, -0.1, 1.715), (-0.05, -0.17, 1.715), 0.026, segs=12), "metal")
        r.add("Head", G.tube((-0.05, -0.169, 1.715), (-0.05, -0.175, 1.715), 0.02, segs=12), "lens")
        cape = G.cyl(0.3, 0.2, 0.6, (0, 0.06, 1.2), segs=16)
        G.cut(cape, (0, 0.0, 0), (0, 1, 0))
        G.bend_noise(cape, 0.03, seed=3)
        r.add("spine_03", cape, "cloak_team")
    elif kind == "medic":
        helmet(r)
        goggles(r)
        r.add("Head", G.box((0.06, 0.035, 0.045), (0, -0.14, 1.79), 0.012), "metal")
        r.add("Head", G.box((0.045, 0.01, 0.03), (0, -0.16, 1.79), 0.006), "lamp")
        for s in (-1, 1):
            r.add("Head", G.box((0.01, 0.07, 0.022), (0.14 * s, 0.0, 1.75), 0.004), "red")
            r.add("Head", G.box((0.01, 0.022, 0.07), (0.14 * s, 0.0, 1.75), 0.004), "red")
        r.add("spine_03", G.box((0.38, 0.2, 0.44), (0, 0.25, 1.3), 0.05), "white")
        r.add("spine_03", G.box((0.16, 0.012, 0.05), (0, 0.355, 1.36), 0.005), "red")
        r.add("spine_03", G.box((0.05, 0.012, 0.16), (0, 0.355, 1.36), 0.005), "red")
        for s in (-1, 1):
            r.add("upperarm_" + ("r" if s < 0 else "l"), G.tube((0.32 * s, 0.065, 1.456), (0.38 * s, 0.065, 1.456), 0.06), "white")
        r.add("upperarm_l", G.box((0.05, 0.015, 0.02), (0.35, 0.0, 1.456), 0.003), "red")
        r.add("upperarm_l", G.box((0.02, 0.015, 0.05), (0.35, 0.0, 1.456), 0.003), "red")
    elif kind == "breacher":
        r.drop_meshes("Eyes")
        r.add("Head", G.sphere(0.15, (0, 0.0, 1.725), (1.0, 1.08, 1.0), segs=18, rings=10), "armor_team")
        r.add("Head", G.box((0.24, 0.07, 0.18), (0, -0.115, 1.69), 0.045), "plate")
        r.add("Head", G.box((0.19, 0.03, 0.03), (0, -0.152, 1.72), 0.008), "visor")
        r.add("Head", G.box((0.045, 0.22, 0.035), (0, 0.0, 1.88), 0.012), "plate")
        for s in (-1, 1):
            r.add("spine_03", G.box((0.08, 0.06, 0.12), (0.12 * s, -0.2, 1.36), 0.012), "amber")
        r.add("spine_03", G.box((0.38, 0.13, 0.36), (0, 0.24, 1.3), 0.04), "plate")
        # forearm shield along the outside of the left forearm
        r.add("lowerarm_l", G.box((0.6, 0.4, 0.05), (0.6, 0.0, 1.53), 0.03), "plate")
        r.add("lowerarm_l", G.box((0.58, 0.05, 0.055), (0.6, -0.17, 1.535), 0.01), "amber")
        r.add("lowerarm_l", G.box((0.12, 0.11, 0.055), (0.66, -0.06, 1.536), 0.008), "visor")
    weapon(r, kind)
    growths(r, heavy=kind == "breacher")
    r.export()


# --- the infected ----------------------------------------------------------------------

def _h(p, n=4):
    """Stable pseudo-random 0..n-1 from a position (for ragged holes)."""
    return int(abs(math.sin(p.x * 91.7 + p.y * 47.3 + p.z * 13.1) * 43758.5)) % n


def infected(r, rags=True, claws=True, k=1.0):
    """Shared look of a turned civilian: glowing eyes, torn rags, claws. `k` scales the
    landmarks for the smaller female body."""
    r.drop_meshes("Eyebrows", "Hair")
    for o in bpy.data.objects:
        if o.type == "MESH" and o.name.startswith("Eyes"):
            o.data.materials.clear()
            o.data.materials.append(G.material("glow"))
    if rags:
        r.clothe("rags", lambda p: 0.55 * k < p.z < 1.45 * k and abs(p.x) < 0.3 and _h(p) != 0
                 and not (p.z < 0.98 * k and abs(p.x) < 0.04), 0.012, "rags", wrinkle=0.012)
    if claws:
        for s, side in ((-1, "r"), (1, "l")):
            for i in range(3):
                r.add("hand_" + side, G.shard((0.79 * s * k, 0.03 + i * 0.03, 1.44 * k), (s, -0.2 + i * 0.2, -0.25), 0.13, 0.012, sides=4), "bone", "claws")


def crystals(r, bone, base, n, length, rnd, role="glow", name=None, spread=0.6, up=(0, 0.6, 1)):
    base = Vector(base)
    for i in range(n):
        d = Vector(up) + Vector((rnd.uniform(-spread, spread), rnd.uniform(-spread, spread), rnd.uniform(-spread, spread) * 0.5))
        r.add(bone, G.shard(tuple(base + Vector((rnd.uniform(-0.04, 0.04), rnd.uniform(-0.03, 0.03), rnd.uniform(-0.04, 0.04)))),
                            tuple(d), rnd.uniform(length * 0.6, length), length * 0.16), role, name)
    r.add(bone, G.sphere(length * 0.45, tuple(base), (1.2, 1.0, 0.8)), "flesh_raw", name)


def blisters(r, bone, centre, n, size, rnd, spread=0.06, name=None):
    for i in range(n):
        c = Vector(centre) + Vector((rnd.uniform(-spread, spread), rnd.uniform(-spread, spread), rnd.uniform(-spread, spread)))
        r.add(bone, G.sphere(rnd.uniform(size * 0.6, size), tuple(c)), "glow", name)


def build_infected(kind):
    female = kind in ("shrieker", "brood_mother")
    k = 0.976 if female else 1.0
    r = Rig(kind, "female" if female else "male")
    rnd = random.Random(sum(map(ord, kind)))
    if kind == "runner":
        infected(r)
        crystals(r, "spine_03", (0.08, 0.16, 1.4), 7, 0.24, rnd, up=(0.3, 1, 0.8))
        crystals(r, "Head", (-0.07, 0.04, 1.8), 3, 0.12, rnd, up=(-0.5, 0.3, 1))
        blisters(r, "lowerarm_r", (-0.55, 0.06, 1.47), 5, 0.025, rnd)
        blisters(r, "thigh_l", (0.13, -0.05, 0.75), 4, 0.025, rnd)
    elif kind == "spitter":
        infected(r)
        r.add("spine_03", G.sphere(0.24, (0, 0.25, 1.36), (1.0, 0.9, 1.1)), "sac", "sac")
        r.origins["sac"] = Vector((0, 0.18, 1.36))
        r.add("spine_03", G.sphere(0.1, (0, 0.1, 1.33), (1.6, 1.0, 1.6)), "flesh_raw")
        for i in range(5):
            a = i * 1.2566
            r.add("spine_03", G.tube((math.cos(a) * 0.1, 0.08, 1.36 + math.sin(a) * 0.12),
                                     (math.cos(a) * 0.2, 0.26, 1.36 + math.sin(a) * 0.22), 0.018, 0.01, segs=6), "flesh_raw")
        r.add("neck_01", G.sphere(0.07, (0, -0.06, 1.55), (1.2, 1.0, 1.0)), "glow")
        r.empty("muzzle", "Head", (0, -0.12, 1.66))
    elif kind == "leaper":
        infected(r, rags=False)
        r.clothe("rags", lambda p: 0.6 < p.z < 1.05 and _h(p, 3) != 0, 0.012, "rags", wrinkle=0.01)
        for s, side in ((-1, "r"), (1, "l")):
            crystals(r, "calf_" + side, (0.11 * s, 0.08, 0.35), 3, 0.18, rnd, up=(0, 1, 0.6), spread=0.3)
        crystals(r, "spine_02", (0, 0.13, 1.18), 5, 0.2, rnd, up=(0, 1, 0.5), spread=0.3)
    elif kind == "shrieker":
        infected(r, k=k)
        r.add("Head", G.sphere(0.07, (0, -0.1, 1.6), (1.2, 0.8, 1.3)), "glow")             # split jaw
        for i in range(7):
            a = (i - 3) * 0.35
            r.add("Head", G.shard((math.sin(a) * 0.08, 0.04, 1.73), (math.sin(a) * 1.2, 0.5, 1.0), 0.22 + (3 - abs(i - 3)) * 0.04, 0.02), "glow", "crest")
        crystals(r, "spine_03", (0, 0.12, 1.33), 5, 0.18, rnd, up=(0, 1, 0.6))
    elif kind == "broodling":
        infected(r, rags=False, claws=True)
        for bone, c in (("spine_03", (0, 0.14, 1.32)), ("spine_02", (0.1, -0.12, 1.15)), ("Head", (0.05, 0.02, 1.76)),
                        ("upperarm_l", (0.32, 0.06, 1.47)), ("thigh_r", (-0.13, 0.0, 0.7))):
            blisters(r, bone, c, 6, 0.05, rnd, spread=0.08)
        crystals(r, "spine_03", (0, 0.15, 1.36), 6, 0.2, rnd, up=(0, 1, 0.9))
    elif kind == "brute":
        infected(r, rags=False)
        r.clothe("rags", lambda p: 0.55 < p.z < 1.05 and _h(p, 5) != 0, 0.015, "rags", wrinkle=0.012)
        # bone armour grown over the shoulders, back and forearms
        for s, side in ((-1, "r"), (1, "l")):
            bm = G.sphere(0.17, (0.25 * s, 0.06, 1.5), (1.2, 1.1, 0.8), segs=14, rings=8)
            G.bend_noise(bm, 0.03, seed=2)
            r.add("upperarm_" + side, bm, "chitin")
            r.add("lowerarm_" + side, G.capsule(0.09, 0.2, (0.6 * s, 0.06, 1.46), rot=(0, math.pi / 2, 0), scale=(1.2, 1.2, 1.0)), "flesh")
            crystals(r, "upperarm_" + side, (0.28 * s, 0.1, 1.6), 3, 0.18, rnd, role="chitin", up=(s * 0.4, 0.4, 1))
            r.add("hand_" + side, G.sphere(0.09, (0.78 * s, 0.06, 1.45), (1.2, 1.0, 1.0)), "chitin")
        bm = G.sphere(0.24, (0, 0.17, 1.38), (1.2, 0.7, 1.0), segs=16, rings=10)
        G.bend_noise(bm, 0.04, seed=5)
        r.add("spine_03", bm, "chitin")
        crystals(r, "spine_03", (0, 0.3, 1.42), 6, 0.28, rnd, up=(0, 1, 0.7))
    elif kind == "bloater":
        infected(r, rags=False, claws=False)
        bm = G.sphere(0.3, (0, -0.12, 1.12), (1.0, 1.0, 1.05), segs=18, rings=12)
        G.bend_noise(bm, 0.025, seed=4)
        r.add("spine_01", bm, "flesh")
        blisters(r, "spine_01", (0, -0.36, 1.12), 9, 0.07, rnd, spread=0.17)
        r.add("spine_01", G.sphere(0.14, (0, -0.33, 1.1), (1.2, 0.6, 1.2)), "sac", "sac")
        r.origins["sac"] = Vector((0, -0.3, 1.1))
        blisters(r, "spine_03", (0, 0.14, 1.38), 6, 0.06, rnd, spread=0.12)
    elif kind == "brood_mother":
        infected(r, rags=False, k=k)
        r.clothe("rags", lambda p: 0.4 < p.z < 1.4 and _h(p, 4) != 0, 0.02, "flesh", wrinkle=0.02)
        for i in range(5):
            c = (rnd.uniform(-0.15, 0.15), 0.2 + rnd.uniform(0, 0.08), 1.0 + i * 0.09)
            r.add("spine_02" if i < 3 else "spine_03", G.sphere(0.09, c, (1.0, 1.1, 0.9)), "sac", "eggs")
        for i in range(9):
            a = (i - 4) * 0.32
            r.add("Head", G.shard((math.sin(a) * 0.09, 0.02, 1.7), (math.sin(a) * 0.9, 0.3, 1.0), 0.28 - abs(i - 4) * 0.03, 0.022), "glow", "crown")
        crystals(r, "spine_03", (0.15, 0.12, 1.4), 5, 0.25, rnd, up=(0.6, 0.8, 0.8))
        crystals(r, "spine_03", (-0.15, 0.12, 1.4), 5, 0.25, rnd, up=(-0.6, 0.8, 0.8))
    r.export()


def build_turned(kind):
    """Turned soldiers on the enemy side: the soldier kit, lapsed into the Bloom."""
    r = Rig(kind)
    rnd = random.Random(sum(map(ord, kind)))
    r.drop_meshes("Eyebrows", "Hair")
    soldier_kit(r, "trooper")
    if kind == "colonel_hale":
        # officer: peaked cap, greatcoat, rank tabs, sidearm-length carbine
        r.add("Head", G.cyl(0.125, 0.135, 0.07, (0, 0.0, 1.78), segs=18), "cloth_team")
        r.add("Head", G.cyl(0.15, 0.15, 0.02, (0, 0.0, 1.81), segs=18), "cloth_team")
        r.add("Head", G.box((0.2, 0.09, 0.012), (0, -0.12, 1.765), 0.005, rot=(-0.3, 0, 0)), "leather")
        r.add("Head", G.box((0.05, 0.01, 0.03), (0, -0.135, 1.8), 0.004), "amber")
        r.clothe("coat", lambda p: 0.45 < p.z < 1.5 and abs(p.x) < 0.5, lambda p: 0.04 + max(0.0, 1.0 - p.z) * 0.12, "cloak_team", wrinkle=0.01)
        for s in (-1, 1):
            r.add("spine_03", G.box((0.06, 0.02, 0.025), (0.12 * s, -0.16, 1.47), 0.004), "amber")
        weapon(r, "medic")
    elif kind == "sharpshooter":
        r.add("Head", G.sphere(0.13, (0, 0.01, 1.76), (1.0, 1.05, 0.6)), "cloth_team")
        r.add("Head", G.tube((-0.05, -0.1, 1.715), (-0.05, -0.17, 1.715), 0.026, segs=12), "metal")
        r.add("Head", G.tube((-0.05, -0.169, 1.715), (-0.05, -0.175, 1.715), 0.02, segs=12), "lens")
        weapon(r, "marksman")
    else:   # fallen: helmet cracked open by growths, no weapon
        helmet(r)
        crystals(r, "Head", (0.06, 0.02, 1.83), 4, 0.16, rnd, up=(0.4, 0.2, 1))
    crystals(r, "spine_03", (0.1, 0.2, 1.4), 5, 0.22, rnd, up=(0.3, 1, 0.8))
    blisters(r, "lowerarm_l", (0.58, 0.06, 1.47), 5, 0.025, rnd)
    for o in bpy.data.objects:
        if o.type == "MESH" and o.name.startswith("Eyes"):
            o.data.materials.clear()
            o.data.materials.append(G.material("glow"))
    r.export()


def build_civilian():
    r = Rig("civilian", "female")
    r.drop_meshes("Eyebrows")
    k = 0.976
    r.clothe("shirt", lambda p: 0.9 * k < p.z < 1.5 * k and abs(p.x) < 0.45, 0.014, "shirt", wrinkle=0.008)
    r.clothe("trousers", lambda p: 0.1 < p.z < 1.0 * k, lambda p: 0.012 + max(0.0, 0.6 - p.z) * 0.02, "denim", wrinkle=0.008)
    # hair: a cap over the skull and a tied-back tail
    hair = G.sphere(0.112, (0, 0.012, 1.672), (1.0, 1.08, 1.0), segs=18, rings=10)
    G.cut(hair, (0, -0.05, 1.63), (0, 0.55, 1))
    r.add("Head", hair, "hair")
    r.add("Head", G.capsule(0.035, 0.14, (0, 0.11, 1.6), rot=(0.5, 0, 0)), "hair")
    for s, side in ((-1, "r"), (1, "l")):
        r.add("foot_" + side, G.box((0.11, 0.24, 0.09), (0.1 * s, -0.03, 0.05), 0.03), "leather")
    r.add("spine_03", G.box((0.26, 0.12, 0.3), (0, 0.17, 1.27), 0.05), "strap")      # backpack of belongings
    r.add("spine_03", G.box((0.18, 0.13, 0.12), (0, 0.17, 1.46), 0.04), "cloak_team")  # bedroll
    r.export()


# --- creatures on their own rigs -----------------------------------------------------------

SPIDER = "Quaternius_AnimatedEnemies_polypizza_glb/Spider.glb"


class Creature(Rig):
    """A Quaternius animated creature (own skeleton and clips, kept in the export),
    scaled to `width` metres across and dressed with growths."""

    def __init__(self, name, src_rel, width):
        G.fresh_scene()
        self.name = name
        objs = import_glb(os.path.join(SRC, src_rel))
        for o in objs:
            if o.type == "EMPTY" and o.name.endswith("_end") or (o.type == "MESH" and o.parent is None):
                bpy.data.objects.remove(o)
        self.arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
        self.arm.name = "Armature"
        root = self.arm.parent or self.arm
        bpy.context.view_layer.update()
        mesh = next(o for o in bpy.data.objects if o.type == "MESH")
        pts = [mesh.matrix_world @ Vector(c) for c in mesh.bound_box]
        extent = max(max(p.x for p in pts) - min(p.x for p in pts), max(p.y for p in pts) - min(p.y for p in pts))
        k = width / extent
        root.scale = root.scale * k
        bpy.context.view_layer.update()
        for slot in mesh.material_slots:
            col = slot.material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value if slot.material.use_nodes else (0, 0, 0, 1)
            slot.material.name = "glow" if col[0] > 0.3 and col[1] < 0.2 else "chitin"
        self.parts, self.origins, self.empties = {}, {}, []
        self.scale = k

    def at(self, bone):
        """World head position of a bone."""
        return self.arm.matrix_world @ self.arm.data.bones[bone].head_local

    def export(self):
        self.build()
        self.bake_rest_colors()
        export(self.name, animations=True)


def build_creature(kind):
    rnd = random.Random(sum(map(ord, kind)))
    if kind == "lurker":
        r = Creature(kind, SPIDER, 1.7)
        ab, th, hd = r.at("Abdomen"), r.at("Thorax"), r.at("Head")
        crystals(r, "Abdomen", ab + Vector((0, 0.18, 0.2)), 7, 0.26, rnd, up=(0, 0.6, 1))
        blisters(r, "Abdomen", ab + Vector((0, 0.25, 0.05)), 8, 0.05, rnd, spread=0.14)
        blisters(r, "Head", hd + Vector((0, -0.05, 0.05)), 4, 0.03, rnd, spread=0.05)
        crystals(r, "Thorax", th + Vector((0, 0, 0.12)), 3, 0.14, rnd, up=(0, 0.2, 1))
    else:   # burrower: bigger, armoured, ridged for digging
        r = Creature(kind, SPIDER, 2.2)
        ab, th, hd = r.at("Abdomen"), r.at("Thorax"), r.at("Head")
        bm = G.sphere(0.42, tuple(ab + Vector((0, 0.15, 0.12))), (1.0, 1.25, 0.6), segs=16, rings=10)
        G.bend_noise(bm, 0.04, seed=8)
        r.add("Abdomen", bm, "chitin")
        for i in range(6):
            p = ab + Vector((0, -0.2 + i * 0.13, 0.32 - abs(i - 2.5) * 0.04))
            r.add("Abdomen", G.shard(tuple(p), (0, 0.4, 1), 0.24 - abs(i - 2.5) * 0.03, 0.04), "glow")
        for s in (-1, 1):
            r.add("Head", G.shard(tuple(hd + Vector((0.08 * s, -0.12, -0.05))), (0.4 * s, -1, -0.3), 0.3, 0.04), "chitin", "mandibles")
        blisters(r, "Thorax", th + Vector((0, 0, 0.15)), 6, 0.05, rnd, spread=0.12)
    r.export()


NAMES = {
    "anims": lambda: (build_anims(UAL1, CLIPS_UAL1, "anims_ual1"), build_anims(UAL2, CLIPS_UAL2, "anims_ual2")),
    "trooper": lambda: build_soldier("trooper"),
    "marksman": lambda: build_soldier("marksman"),
    "medic": lambda: build_soldier("medic"),
    "breacher": lambda: build_soldier("breacher"),
    "civilian": build_civilian,
}
for _k in ("runner", "spitter", "leaper", "shrieker", "broodling", "brute", "bloater", "brood_mother"):
    NAMES[_k] = (lambda k: lambda: build_infected(k))(_k)
for _k in ("lurker", "burrower"):
    NAMES[_k] = (lambda k: lambda: build_creature(k))(_k)
for _k in ("fallen", "sharpshooter", "colonel_hale"):
    NAMES[_k] = (lambda k: lambda: build_turned(k))(_k)


def main():
    global SRC
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    if "--src" in argv:
        i = argv.index("--src")
        SRC = os.path.expanduser(argv[i + 1])
        del argv[i:i + 2]
    names = [a for a in argv if a in NAMES] or list(NAMES)
    for n in names:
        NAMES[n]()


if __name__ == "__main__":
    main()
