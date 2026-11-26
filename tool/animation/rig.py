"""Fits a skeleton to a body model and skins its muscle parts.

Run inside Blender:
  Blender -b --python rig.py -- <body.glb> <rig.npz>

The result holds the parts' geometry in metres (z up, the body faces -y, its
left is +x), the joints, and up to four bone weights per vertex.
"""

import json
import struct
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, kdtree

src, out = sys.argv[sys.argv.index("--") + 1 :][:2]
HEIGHT = 1.78

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
# The file may already carry a skin from an earlier export: keep only its
# mesh nodes, as they were before skinning.
with open(src, "rb") as f:
    f.seek(12)
    gltf = json.loads(f.read(struct.unpack("<I4x", f.read(8))[0]))
names = sorted(n["name"] for n in gltf["nodes"] if "mesh" in n)
parts = [bpy.data.objects[n] for n in names]
for o in list(bpy.context.scene.objects):
    if o not in parts:
        bpy.data.objects.remove(o)
for o in parts:
    o.parent = None
    o.modifiers.clear()
    o.vertex_groups.clear()
    o.data.transform(o.matrix_world)
    o.matrix_world = Matrix.Identity(4)
top = max(v.co.z for o in parts for v in o.data.vertices)
for o in parts:
    o.data.transform(Matrix.Scale(HEIGHT / top, 4))

verts, tris, vert_part, tri_part = [], [], [], []
offset = 0
for i, o in enumerate(parts):
    mesh = o.data
    mesh.calc_loop_triangles()
    co = np.empty(len(mesh.vertices) * 3, np.float32)
    mesh.vertices.foreach_get("co", co)
    tri = np.empty(len(mesh.loop_triangles) * 3, np.int32)
    mesh.loop_triangles.foreach_get("vertices", tri)
    verts.append(co.reshape(-1, 3))
    tris.append(tri.reshape(-1, 3) + offset)
    vert_part.append(np.full(len(mesh.vertices), i, np.int32))
    tri_part.append(np.full(len(mesh.loop_triangles), i, np.int32))
    offset += len(mesh.vertices)
V = np.concatenate(verts)
label = np.array(names)[np.concatenate(vert_part)]

# Landmarks are read off the mesh in the model's own proportions: `u` turns a
# fraction of the body height into metres.
u = HEIGHT / 0.98
x, y, z = V[:, 0], V[:, 1], V[:, 2]


def centre(mask):
    return V[mask].mean(axis=0)


def band(lo, hi):
    return (z > lo * u) & (z < hi * u)


def is_part(*codes):
    return np.isin(label, [f"{c}_left" for c in codes])


arm = is_part("biceps", "triceps", "forearm") | ((label == "none") & (x > 0.125 * u))
leg = (x > 0.005 * u) & (z < 0.5 * u)
torso = np.abs(x) < 0.1 * u

delt = centre(is_part("front_delt", "mid_delt", "rear_delt"))
shoulder = np.array([0.112 * u, delt[1], 0.775 * u])
elbow = centre(arm & band(0.615, 0.64))
wrist = centre(arm & band(0.49, 0.51) & (x > 0.15 * u))
in_hand = (label == "none") & (x > 0.18 * u) & band(0.3, 0.49)
fingertips = centre(in_hand & (z < np.quantile(z[in_hand], 0.06)))
knuckles = wrist + (fingertips - wrist) * 0.5
fingers = wrist + (fingertips - wrist) * 0.75
mid_forearm = (elbow + wrist) / 2

thigh_top = centre(leg & band(0.46, 0.48))
hip = np.array([0.065 * u, thigh_top[1], 0.525 * u])
knee = centre(leg & band(0.285, 0.305))
ankle = centre(leg & band(0.05, 0.07))
toe = centre(leg & (z < 0.03 * u) & (y < ankle[1] - 0.06 * u))


def spine(height, back=0.0):
    c = centre(torso & band(height - 0.01, height + 0.01))
    return np.array([0.0, c[1] + back * u, height * u])


pelvis = np.array([0.0, hip[1], 0.54 * u])
lumbar = spine(0.60, 0.01)
chest = spine(0.70, 0.01)
neck = spine(0.84, 0.01)
skull = centre((np.abs(x) < 0.05 * u) & band(0.885, 0.905))
skull[0] = 0.0
crown = np.array([0.0, skull[1], HEIGHT])
clavicle = np.array([0.02 * u, chest[1] * 0.3 + shoulder[1] * 0.7, 0.80 * u])


def mirror(p):
    return p * np.array([-1.0, 1.0, 1.0])


# name: (head, tail, parent)
bones = {
    "pelvis": (pelvis, lumbar, None),
    "lumbar": (lumbar, chest, "pelvis"),
    "chest": (chest, neck, "lumbar"),
    "neck": (neck, skull, "chest"),
    "head": (skull, crown, "neck"),
}
for side, flip in (("L", lambda p: p), ("R", mirror)):
    bones |= {
        f"clavicle_{side}": (flip(clavicle), flip(shoulder), "chest"),
        f"upper_arm_{side}": (flip(shoulder), flip(elbow), f"clavicle_{side}"),
        f"forearm_{side}": (flip(elbow), flip(mid_forearm), f"upper_arm_{side}"),
        f"wrist_{side}": (flip(mid_forearm), flip(wrist), f"forearm_{side}"),
        f"hand_{side}": (flip(wrist), flip(knuckles), f"wrist_{side}"),
        f"fingers_{side}": (flip(knuckles), flip(fingers), f"hand_{side}"),
        f"fingertips_{side}": (flip(fingers), flip(fingertips), f"fingers_{side}"),
        f"thigh_{side}": (flip(hip), flip(knee), "pelvis"),
        f"shin_{side}": (flip(knee), flip(ankle), f"thigh_{side}"),
        f"foot_{side}": (flip(ankle), flip(toe), f"shin_{side}"),
    }
bone_names = list(bones)
for name, (head, tail, _) in bones.items():
    if name.endswith("_R"):
        continue
    print(f"{name:12s} head {np.round(head, 3)} tail {np.round(tail, 3)}")

# Bone heat needs one closed surface: weld a joined copy of the parts, weight
# it, then hand each part vertex the weights of the welded vertex under it.
copies = []
for o in parts:
    c = o.copy()
    c.data = o.data.copy()
    bpy.context.collection.objects.link(c)
    copies.append(c)
bpy.ops.object.select_all(action="DESELECT")
for c in copies:
    c.select_set(True)
bpy.context.view_layer.objects.active = copies[0]
bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
bm = bmesh.new()
bm.from_mesh(body.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
bm.to_mesh(body.data)
bm.free()

rig_data = bpy.data.armatures.new("rig")
rig = bpy.data.objects.new("rig", rig_data)
bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
for name, (head, tail, parent) in bones.items():
    bone = rig_data.edit_bones.new(name)
    bone.head, bone.tail = head.tolist(), tail.tolist()
    if parent:
        bone.parent = rig_data.edit_bones[parent]
bpy.ops.object.mode_set(mode="OBJECT")

bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type="ARMATURE_AUTO")

group_bone = [bone_names.index(g.name) for g in body.vertex_groups]
welded = np.zeros((len(body.data.vertices), len(bone_names)), np.float32)
for v in body.data.vertices:
    for g in v.groups:
        welded[v.index, group_bone[g.group]] = g.weight
unweighted = int((welded.sum(axis=1) < 1e-6).sum())
print(f"welded {len(welded)} of {len(V)} vertices, {unweighted} without weights")

tree = kdtree.KDTree(len(welded))
for v in body.data.vertices:
    if welded[v.index].sum() > 1e-6:
        tree.insert(v.co, v.index)
tree.balance()
full = np.stack([welded[tree.find(p.tolist())[1]] for p in V])

# Bone heat follows one finger at most: the fingers close together, so their
# weights are set by how far along the hand a vertex is. The thumb stays with
# the hand.
def step(lo, hi, value):
    t = np.clip((value - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


palms, extra = {}, {}
for side in "LR":
    hand_bones = [bone_names.index(f"{b}_{side}") for b in ("hand", "fingers", "fingertips")]
    wrist_at, tip_at = bones[f"hand_{side}"][0], bones[f"fingertips_{side}"][1]
    length = np.linalg.norm(tip_at - wrist_at)
    along = (tip_at - wrist_at) / length
    total = full[:, hand_bones].sum(axis=1)
    in_hand = total > 0
    local = V[in_hand] - wrist_at
    flat = np.linalg.svd(local[local @ along > 0.2 * length] - local.mean(axis=0))[2][2]
    across = np.cross(flat - (flat @ along) * along, along)
    across /= np.linalg.norm(across)
    s, t = local @ along / length, local @ across
    if t[(np.abs(t) > 0.05) & (s < 0.5)].mean() < 0:
        across, t = -across, -t
    palm = np.cross(along, across) * (1 if side == "L" else -1)
    palms[side] = palm
    thumb = (t > 0.05) & (s < 0.5)
    knuckle, middle = np.where(thumb, 0, step(0.45, 0.55, s)), np.where(thumb, 0, step(0.68, 0.78, s))
    opposing = np.where(s < 0.5, step(0.045, 0.065, t), 0)
    share = np.stack([1 - knuckle, knuckle - middle, middle], axis=1) * (1 - opposing)[:, None]
    full[np.ix_(in_hand, hand_bones)] = total[in_hand, None] * share
    extra[f"thumb_{side}"] = (wrist_at + local[thumb & (t < 0.058)].mean(axis=0), f"hand_{side}")
    column = np.zeros(len(V), np.float32)
    column[in_hand] = total[in_hand] * opposing
    full = np.hstack([full, column[:, None]])

# Linear blending thins a joint that bends far. A helper bone at the joint,
# turned half as far as the bone below it, carries the vertices around it.
helpers = {
    "hip": ("thigh", ("pelvis", "thigh"), 0.20),
    "knee": ("shin", ("thigh", "shin"), 0.15),
    "shoulder": ("upper_arm", ("clavicle", "upper_arm"), 0.15),
    "elbow": ("forearm", ("upper_arm", "forearm"), 0.11),
}
for side, sign in (("L", 1), ("R", -1)):
    for helper, (below, around, radius) in helpers.items():
        at = bones[f"{below}_{side}"][0]
        columns = [bone_names.index(b if b == "pelvis" else f"{b}_{side}") for b in around]
        near = np.clip(1 - (np.linalg.norm(V - at, axis=1) / radius) ** 2, 0, 1) ** 2
        near *= step(0, 0.05, sign * V[:, 0])
        taken = full[:, columns] * near[:, None]
        full[:, columns] -= taken
        full = np.hstack([full, taken.sum(axis=1, keepdims=True)])
        extra[f"{helper}_{side}"] = (at, f"{below}_{side}")
for name, (head, parent) in extra.items():
    bones[name] = (head, head, parent)
bone_names = list(bones)

order = np.argsort(-full, axis=1)[:, :4]
weight = np.take_along_axis(full, order, axis=1)
weight /= weight.sum(axis=1, keepdims=True)

np.savez_compressed(
    out,
    verts=V,
    tris=np.concatenate(tris),
    vert_part=np.concatenate(vert_part),
    tri_part=np.concatenate(tri_part),
    part_names=np.array(names),
    bone_names=np.array(bone_names),
    bone_heads=np.array([bones[b][0] for b in bone_names], np.float32),
    bone_tails=np.array([bones[b][1] for b in bone_names], np.float32),
    bone_parents=np.array(
        [bone_names.index(bones[b][2]) if bones[b][2] else -1 for b in bone_names]
    ),
    palms=np.array([palms["L"], palms["R"]], np.float32),
    skin_bones=order.astype(np.int32),
    skin_weights=weight.astype(np.float32),
)
print("saved", out)
