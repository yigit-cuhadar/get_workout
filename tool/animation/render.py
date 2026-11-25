"""Renders an exercise's key poses or its whole loop.

Run inside Blender:
  Blender -b --python render.py -- <rig.npz> <exercise> <out dir> [keys|loop]
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import exercises  # noqa: E402
from pose import SIDES, Rig, normalized, pose_at  # noqa: E402

rig_path, name, out_dir, mode = (sys.argv[sys.argv.index("--") + 1 :] + ["keys"])[:4]
FPS = 15
SIZE = (540, 720)
COLORS = {
    "body": "D3D6DA",
    "main": "3F7D62",
    "secondary": "8FB3A0",
    "gear": "A4A9B0",
    "steel": "7C828A",
    "plate": "5B6068",
    "pad": "8B9097",
}


def linear(code):
    srgb = [int(code[i : i + 2], 16) / 255 for i in (0, 2, 4)]
    return [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]


rig = Rig(rig_path)
exercise = exercises.EXERCISES[name](rig)
poses = {id(p): normalized(p) for _, p in exercise["keys"]}
keys = [(t, poses[id(p)]) for t, p in exercise["keys"]]

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.render.resolution_x, scene.render.resolution_y = SIZE
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.film_transparent = True
scene.view_settings.view_transform = "Standard"
shading = scene.display.shading
shading.light = "STUDIO"
shading.color_type = "MATERIAL"
shading.show_specular_highlight = False
shading.show_object_outline = True
shading.object_outline_color = linear("6A7078")
shading.show_cavity = True
shading.cavity_type = "WORLD"
scene.display.render_aa = "8"

materials = {}
for key, code in COLORS.items():
    materials[key] = bpy.data.materials.new(key)
    materials[key].diffuse_color = (*linear(code), 1)


def add_object(label, mesh, slots):
    obj = bpy.data.objects.new(label, mesh)
    for slot in slots:
        mesh.materials.append(materials[slot])
    scene.collection.objects.link(obj)
    return obj


# The parts are drawn as one welded surface so shading runs across muscles.
_, first, welded = np.unique(np.round(rig.verts / 1e-4).astype(np.int64), axis=0, return_index=True, return_inverse=True)
faces = welded.ravel()[rig.tris]
body_mesh = bpy.data.meshes.new("body")
body_mesh.from_pydata(rig.verts[first].tolist(), [], faces.tolist())
slots = ["body", "main", "secondary"]
codes = [n.removesuffix("_left").removesuffix("_right") for n in rig.part_names]
part_slot = np.array([1 if c in exercise["main"] else 2 if c in exercise["secondary"] else 0 for c in codes])
body_mesh.polygons.foreach_set("material_index", part_slot[rig.tri_part])
body_mesh.polygons.foreach_set("use_smooth", [True] * len(faces))
add_object("body", body_mesh, slots)


def unit_mesh(kind):
    mesh = bpy.data.meshes.new(kind)
    bm = bmesh.new()
    if kind == "cyl":
        bmesh.ops.create_cone(bm, cap_ends=True, segments=32, radius1=1, radius2=1, depth=1)
    else:
        bmesh.ops.create_cube(bm, size=1)
    bm.to_mesh(mesh)
    bm.free()
    return mesh


camera_data = bpy.data.cameras.new("camera")
camera_data.type = "ORTHO"
camera_data.ortho_scale = exercise["height"]
camera = bpy.data.objects.new("camera", camera_data)
scene.collection.objects.link(camera)
scene.camera = camera


def aim(azimuth, elevation):
    az, el = math.radians(azimuth), math.radians(elevation)
    direction = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    camera.location = Vector(exercise["centre"]) + direction * 20
    camera.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()


gear = []


def show(pose, label):
    R, p = rig.solve(pose)
    body_mesh.vertices.foreach_set("co", rig.skin(R, p)[first].ravel())
    body_mesh.update()
    for i, (kind, matrix, color) in enumerate(exercise["gear"](rig, R, p)):
        if i == len(gear):
            gear.append(add_object(f"gear{i}", unit_mesh(kind), [color]))
        gear[i].matrix_world = Matrix(matrix.tolist())
    for v, (azimuth, elevation) in enumerate(exercise["views"]):
        aim(azimuth, elevation)
        scene.render.filepath = os.path.join(out_dir, f"{name}_{label}_v{v}.png")
        bpy.ops.render.render(write_still=True)
    return R, p


def report(pose, R, p):
    """How far each limb is stretched and how far each hand is from its grip."""
    parts = []
    for side, _ in SIDES:
        arm = np.linalg.norm(p[f"hand_{side}"] - p[f"upper_arm_{side}"]) / sum(rig.rest[side]["arm"])
        leg = np.linalg.norm(p[f"foot_{side}"] - p[f"thigh_{side}"]) / sum(rig.rest[side]["leg"])
        parts.append(f"{side}: arm {arm:.2f} leg {leg:.2f}")
    return "  ".join(parts)


if mode == "keys":
    for i, pose in enumerate(poses.values()):
        R, p = show(pose, f"k{i}")
        print(f"KEY {i}: {report(pose, R, p)}")
else:
    for f in range(round(keys[-1][0] * FPS)):
        show(pose_at(keys, f / FPS), f"f{f:03d}")
