"""Renders an exercise's key poses or its whole loop from its recipe: the
correct form as `<id>_…`, each mistake as `<id>-m<line>_…`, from the recipe's
view and from the side.

Run inside Blender:
  Blender -b --python render.py -- <rig.npz> <exercise id> <out dir> [keys|loop]
"""

import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import recipe  # noqa: E402
from pose import SIDES, Rig, keyed, pose_at  # noqa: E402

rig_path, name, out_dir, mode = (sys.argv[sys.argv.index("--") + 1 :] + ["keys"])[:4]
FPS = 15
SIZE = (720, 720)
# The app's light theme: the body is muscle-base, gear takes line, line-strong
# and ink-muted as the debug page does.
COLORS = {
    "body": "E2E4E8",
    "main": "3F7D62",
    "secondary": "8FB3A0",
    "gear": "DCE0E7",
    "steel": "8B94A3",
    "plate": "586273",
    "pad": "8B94A3",
    "wrong": "A6473C",
}


def linear(code):
    srgb = [int(code[i : i + 2], 16) / 255 for i in (0, 2, 4)]
    return [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]


rig = Rig(rig_path)
spec, entry = recipe.load(name), recipe.catalogue()[name]
gear_at = recipe.gear_of(spec["gear"])
views = [tuple(spec["view"]), (90, 4)]
if mode == "hands":
    # The left hand from close by: along the bar, from the front, from above.
    views = [(90, 0), (0, 5), (0, 80)]
focus = None

# (label, keys, joints to ring) for the correct form and every shown mistake.
clips = [(name, recipe.clip(spec), [])]
for i, mistake in enumerate(spec["mistakes"]):
    if mistake.get("shown", True):
        clips.append((f"{name}-m{mistake['line']}", recipe.clip(spec, i), mistake["ring"]))
clips = [(label, keyed(rig, keys), ring) for label, keys, ring in clips]

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
shading.show_object_outline = False
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
_, welded_first, welded = np.unique(np.round(rig.verts / 1e-4).astype(np.int64), axis=0, return_index=True, return_inverse=True)
faces = welded.ravel()[rig.tris]
body_mesh = bpy.data.meshes.new("body")
body_mesh.from_pydata(rig.verts[welded_first].tolist(), [], faces.tolist())
slots = ["body", "main", "secondary"]
codes = [n.removesuffix("_left").removesuffix("_right") for n in rig.part_names]
part_slot = np.array([1 if c in entry["mainMuscles"] else 2 if c in entry["secondaryMuscles"] else 0 for c in codes])
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
camera = bpy.data.objects.new("camera", camera_data)
scene.collection.objects.link(camera)
scene.camera = camera

bpy.ops.mesh.primitive_torus_add(major_radius=0.09, minor_radius=0.007)
ring_mesh = bpy.context.object.data
bpy.data.objects.remove(bpy.context.object)
rings = []


def placed(solved, first):
    """The body's vertices and the gear's pieces for one frame."""
    return rig.skin(*solved), gear_at(rig, solved, first)


def extent(frames):
    """Corners of the box around everything the frames show."""
    low, high = np.full(3, np.inf), np.full(3, -np.inf)
    for body, pieces in frames:
        clouds = [body] + [
            np.array([m[:3, :3] @ (x, y, z) + m[:3, 3] for x in (-r, r) for y in (-r, r) for z in (-0.5, 0.5)])
            for kind, m, _ in pieces
            for r in [1 if kind == "cyl" else 0.5]
        ]
        low = np.minimum(low, np.min([c.min(axis=0) for c in clouds], axis=0))
        high = np.maximum(high, np.max([c.max(axis=0) for c in clouds], axis=0))
    return np.array([[x, y, z] for x in (low[0], high[0]) for y in (low[1], high[1]) for z in (low[2], high[2])])


# One framing for the whole exercise, from the key poses of every clip.
corners = extent(
    [placed(rig.solve(pose), rig.solve(keys[0][1])) for _, keys, _ in clips for pose in {id(p): p for _, p in keys}.values()]
)
centre = (corners.min(axis=0) + corners.max(axis=0)) / 2


def aim(azimuth, elevation):
    az, el = math.radians(azimuth), math.radians(elevation)
    direction = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    turn = (-direction).to_track_quat("-Z", "Y")
    right, up = np.array(turn @ Vector((1, 0, 0))), np.array(turn @ Vector((0, 1, 0)))
    wide, tall = (np.ptp((corners - centre) @ axis) for axis in (right, up))
    camera_data.ortho_scale = 0.42 if mode == "hands" else max(tall, wide * SIZE[1] / SIZE[0]) * 1.06
    camera.location = Vector(focus if mode == "hands" else centre) + direction * 20
    camera.rotation_euler = turn.to_euler()
    return direction, turn


def floor(view, body):
    """The floor disc and the body's shadow on it as ellipses in the picture:
    [x, y, half width, half height] each. sheet.py paints them under the render."""
    az, el = math.radians(view[0]), math.radians(view[1])
    direction = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    turn = (-direction).to_track_quat("-Z", "Y")
    right, up = np.array(turn @ Vector((1, 0, 0))), np.array(turn @ Vector((0, 1, 0)))
    per_unit = SIZE[0] / camera_data.ortho_scale

    def ellipse(at, radius):
        offset = np.array([at[0], at[1], 0]) - centre
        x, y = SIZE[0] / 2 + offset @ right * per_unit, SIZE[1] / 2 - offset @ up * per_unit
        return [x, y, radius * per_unit, radius * per_unit * abs(math.sin(el))]

    span = np.ptp(corners[:, :2], axis=0)
    under = (body[:, :2].min(axis=0) + body[:, :2].max(axis=0)) / 2
    reach = np.ptp(body[:, :2], axis=0).max() / 2
    return {"disc": ellipse(centre, span.max() * 0.48), "shadow": ellipse(under, reach * 0.8)}


gear = []


def show(solved, first, ring, label):
    global focus
    body, pieces = placed(solved, first)
    focus = rig.grip(*solved, "L")
    body_mesh.vertices.foreach_set("co", body[welded_first].ravel())
    body_mesh.update()
    for i, (kind, matrix, color) in enumerate(pieces):
        if i == len(gear):
            gear.append(add_object(f"gear{i}", unit_mesh(kind), [color]))
        gear[i].matrix_world = Matrix(matrix.tolist())
        gear[i].hide_render = mode == "hands" and color == "plate"
    while len(rings) < len(ring):
        rings.append(add_object(f"ring{len(rings)}", ring_mesh.copy(), ["wrong"]))
    for v, view in enumerate(views):
        direction, turn = aim(*view)
        for i, mark in enumerate(rings):
            mark.hide_render = i >= len(ring)
            if i < len(ring):
                # In front of the body, facing the camera.
                mark.location = Vector(solved[1][ring[i]]) + direction * 0.3
                mark.rotation_euler = turn.to_euler()
        scene.render.filepath = os.path.join(out_dir, f"{label}_v{v}.png")
        bpy.ops.render.render(write_still=True)
        with open(os.path.join(out_dir, f"{label}_v{v}.json"), "w") as f:
            off = [-9999, -9999, 1, 1]
            json.dump({"disc": off, "shadow": off} if mode == "hands" else floor(view, body), f)


def report(solved):
    """How far each limb is stretched and how far a hand or foot missed."""
    R, p = solved
    parts = []
    for side, _ in SIDES:
        arm = np.linalg.norm(p[f"hand_{side}"] - p[f"upper_arm_{side}"]) / sum(rig.rest[side]["arm"])
        leg = np.linalg.norm(p[f"foot_{side}"] - p[f"thigh_{side}"]) / sum(rig.rest[side]["leg"])
        parts.append(f"{side}: arm {arm:.2f} leg {leg:.2f}")
    return "  ".join(parts) + f"  missed {max(rig.missed.values()) * 100:.1f} cm"


for label, keys, ring in clips:
    first = rig.solve(keys[0][1])
    if mode != "loop":
        for i, pose in enumerate({id(p): p for _, p in keys}.values()):
            solved = rig.solve(pose)
            print(f"KEY {label} {i}: {report(solved)}")
            show(solved, first, ring, f"{label}_k{i}")
    else:
        for f in range(round(keys[-1][0] * FPS)):
            show(rig.solve(pose_at(keys, f / FPS)), first, ring, f"{label}_f{f:03d}")
