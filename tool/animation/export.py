"""Writes what the app plays: the skinned body, and per exercise its gear and clip.

  python3 export.py <body.glb> <rig.npz> <skinned body.glb> <clips dir>

The body keeps its geometry and gains JOINTS_0 / WEIGHTS_0 and a skin; beside
it goes `<body>.rig.json`, the joints a solver needs. Each
recipe's correct form gets `<name>.glb`, the gear with every piece bound to a joint of its
own after the body's, and `<name>.clip`, one 3x4 matrix per joint per frame
(layout in forge_model_viewer's ModelClip). Everything is in the body file's
space: y up, the body faces +z.
"""

import json
import os
import struct
import sys

import numpy as np

import recipe
from pose import Rig, normalized, pose_at

source, rig_path, body_out, clips_dir = sys.argv[1:5]
FPS = 12
CELL = 0.09


def read_glb(path):
    data = open(path, "rb").read()
    length = struct.unpack_from("<I", data, 12)[0]
    return json.loads(data[20 : 20 + length]), data[28 + length :]


def write_glb(path, gltf, binary):
    binary += b"\0" * (-len(binary) % 4)
    gltf["buffers"] = [{"byteLength": len(binary)}]
    text = json.dumps(gltf, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 28 + len(text) + len(binary)))
        f.write(struct.pack("<II", len(text), 0x4E4F534A) + text)
        f.write(struct.pack("<II", len(binary), 0x004E4942) + binary)


def add_accessor(gltf, binary, array, component, kind, **extra):
    binary += b"\0" * (-len(binary) % 4)
    gltf["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": array.nbytes})
    binary += array.tobytes()
    gltf["accessors"].append(
        {"bufferView": len(gltf["bufferViews"]) - 1, "componentType": component, "type": kind, "count": len(array)}
        | extra
    )
    return len(gltf["accessors"]) - 1


def as_bytes(weights):
    """Weights as bytes that still sum to 255."""
    out = np.round(weights * 255).astype(np.int32)
    out[np.arange(len(out)), out.argmax(axis=1)] += 255 - out.sum(axis=1)
    return out.astype(np.uint8)


rig = Rig(rig_path)
gltf, binary = read_glb(source)
# The rig is in metres, z up, facing -y; the file in its own unit, y up, facing +z.
metres = rig.verts[:, 2].max() / max(a["max"][1] for a in gltf["accessors"] if "max" in a)
to_file = np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]], float)


def in_file(linear, offset):
    """A rig-space transform as a 3x4 matrix in the file's space."""
    return np.hstack([to_file @ linear @ to_file.T, (to_file @ offset / metres)[:, None]])


heads = np.stack([rig.heads[b] for b in rig.bones]) @ to_file.T / metres


def stored(index, kind, width):
    accessor = gltf["accessors"][index]
    offset = gltf["bufferViews"][accessor["bufferView"]].get("byteOffset", 0) + accessor.get("byteOffset", 0)
    return np.frombuffer(binary, kind, accessor["count"] * width, offset).reshape(-1, width)


def empty():
    return {"asset": {"version": "2.0"}, "scenes": [{"nodes": []}], "nodes": [], "meshes": [], "accessors": [], "bufferViews": []}


def skin(out, data, joints, inverse_bind=None):
    """Adds the joint nodes and the skin, and puts every node in the scene."""
    first = len(out["nodes"])
    out["nodes"] += joints
    out["skins"] = [{"joints": list(range(first, len(out["nodes"])))}]
    if inverse_bind is not None:
        out["skins"][0]["inverseBindMatrices"] = add_accessor(out, data, inverse_bind, 5126, "MAT4")
    out["scenes"][0]["nodes"] = list(range(len(out["nodes"])))


# The body is written afresh from the source's mesh nodes, so a source that was
# skinned before gives the same file. The rig's vertices are the file's, part by
# part in the same order.
out, data = empty(), bytearray()
part_start = np.concatenate([[0], np.cumsum(np.bincount(np.load(rig_path)["vert_part"]))])
for node in gltf["nodes"]:
    if "mesh" not in node:
        continue
    part = rig.part_names.index(node["name"])
    rows = slice(part_start[part], part_start[part + 1])
    (primitive,) = gltf["meshes"][node["mesh"]]["primitives"]
    positions = stored(primitive["attributes"]["POSITION"], np.float32, 3)
    assert np.abs(positions - rig.verts[rows] @ to_file.T / metres).max() < 1e-5, node["name"]
    attributes = {
        "POSITION": add_accessor(out, data, positions, 5126, "VEC3", min=positions.min(axis=0).tolist(), max=positions.max(axis=0).tolist()),
        "NORMAL": add_accessor(out, data, stored(primitive["attributes"]["NORMAL"], np.float32, 3), 5126, "VEC3"),
        "JOINTS_0": add_accessor(out, data, rig.skin_bones[rows].astype(np.uint8), 5121, "VEC4"),
        "WEIGHTS_0": add_accessor(out, data, as_bytes(rig.skin_weights[rows]), 5121, "VEC4", normalized=True),
    }
    kind = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32}[gltf["accessors"][primitive["indices"]]["componentType"]]
    indices = add_accessor(out, data, stored(primitive["indices"], kind, 1).astype(np.uint16).ravel(), 5123, "SCALAR")
    out["meshes"].append({"primitives": [{"attributes": attributes, "indices": indices}]})
    out["nodes"].append({"name": node["name"], "mesh": len(out["meshes"]) - 1, "skin": 0})
inverse_bind = np.tile(np.eye(4, dtype=np.float32), (len(heads), 1, 1))
inverse_bind[:, 3, :3] = -heads  # column-major: the translation is the last column
skin(out, data, [{"name": b, "translation": h.tolist()} for b, h in zip(rig.bones, heads)], inverse_bind)
write_glb(body_out, out, data)
with open(os.path.splitext(body_out)[0] + ".rig.json", "w") as f:
    json.dump(rig.joints(metres), f, separators=(",", ":"))
print(f"{body_out}: {os.path.getsize(body_out) // 1024} KB, {len(rig.bones)} joints")


def grid(corner, u, v, columns, rows):
    """A flat patch from corner along u and v: positions and triangles."""
    i, j = np.meshgrid(np.arange(columns + 1), np.arange(rows + 1))
    positions = corner + i.reshape(-1, 1) / columns * u + j.reshape(-1, 1) / rows * v
    a = (j[:-1, :-1] * (columns + 1) + i[:-1, :-1]).ravel()
    quads = np.stack([a, a + 1, a + columns + 2, a, a + columns + 2, a + columns + 1], axis=1)
    return positions, quads.reshape(-1, 3)


def shape(kind, matrix):
    """A unit cube or a unit cylinder along z: positions, normals, triangles.

    The viewer sorts whole triangles by depth, so faces are cut into cells no
    larger than CELL once `matrix` has sized them.
    """
    size = np.linalg.norm(matrix[:3, :3], axis=0)
    cells = np.maximum(1, np.ceil(size / CELL)).astype(int)
    positions, normals, triangles, count = [], [], [], 0

    def add(patch, normal):
        nonlocal count
        positions.append(patch[0])
        normals.append(np.broadcast_to(normal, patch[0].shape) if np.ndim(normal) == 1 else normal)
        triangles.append(patch[1] + count)
        count += len(patch[0])

    if kind == "box":
        for axis in range(3):
            for sign in (-1, 1):
                n = np.eye(3)[axis] * sign
                a, b = ((axis + 1) % 3, (axis + 2) % 3) if sign > 0 else ((axis + 2) % 3, (axis + 1) % 3)
                u, v = np.eye(3)[a], np.eye(3)[b]
                add(grid((n - u - v) / 2, u, v, cells[a], cells[b]), n)
    else:
        around = 10 if size[0] < 0.02 else 24
        rings = max(1, int(np.ceil(size[0] / CELL)))
        angle = np.arange(around + 1) * 2 * np.pi / around
        rim = np.stack([np.cos(angle), np.sin(angle), np.zeros(around + 1)], axis=1)
        i, j = np.meshgrid(np.arange(around + 1), np.arange(cells[2] + 1))
        side = rim[i.ravel()] + np.outer(j.ravel() / cells[2] - 0.5, (0, 0, 1))
        a = (j[:-1, :-1] * (around + 2) + i[:-1, :-1]).ravel() - j[:-1, :-1].ravel()
        quads = np.stack([a, a + 1, a + around + 2, a, a + around + 2, a + around + 1], axis=1)
        add((side, quads.reshape(-1, 3)), rim[i.ravel()])
        for end in (-1, 1):
            # Rings of the cap from the centre out; the innermost is a fan.
            i, j = np.meshgrid(np.arange(around + 1), np.arange(rings + 1))
            cap = rim[i.ravel()] * (j.reshape(-1, 1) / rings) + (0, 0, end / 2)
            a = (j[:-1, :-1] * (around + 1) + i[:-1, :-1]).ravel()
            quads = np.stack([a, a + around + 1, a + around + 2, a, a + around + 2, a + 1], axis=1).reshape(-1, 3)
            add((cap, quads if end > 0 else quads[:, ::-1]), np.array([0, 0, float(end)]))
    return np.concatenate(positions), np.concatenate(normals), np.concatenate(triangles)


os.makedirs(clips_dir, exist_ok=True)
for name in sorted(f[:-5] for f in os.listdir(recipe.RECIPES) if not f.startswith("_")):
    spec = recipe.load(name)
    clip_keys = recipe.clip(spec)
    poses = {id(p): normalized(p) for _, p in clip_keys}
    keys = [(t, poses[id(p)]) for t, p in clip_keys]
    frames = round(keys[-1][0] * FPS)
    solved = [rig.solve(pose_at(keys, f / FPS)) for f in range(frames)]
    gear_at = recipe.gear_of(spec["gear"])
    gear = [gear_at(rig, now, solved[0]) for now in solved]

    # Gear is stored where the first frame puts it; its joint carries it from there.
    out, data = empty(), bytearray()
    rest = [(shape(k, m)[0] @ m[:3, :3].T + m[:3, 3]) @ to_file.T / metres for k, m, _ in gear[0]]
    for colour in dict.fromkeys(piece[2] for piece in gear[0]):
        positions, normals, joints, triangles, count = [], [], [], [], 0
        for index, (kind, matrix, piece_colour) in enumerate(gear[0]):
            if piece_colour != colour:
                continue
            p, n, t = shape(kind, matrix)
            positions.append((p @ matrix[:3, :3].T + matrix[:3, 3]) @ to_file.T / metres)
            n = n @ np.linalg.inv(matrix[:3, :3]) @ to_file.T
            normals.append(n / np.linalg.norm(n, axis=1, keepdims=True))
            joints.append(np.tile([len(rig.bones) + index, 0, 0, 0], (len(p), 1)))
            triangles.append(t + count)
            count += len(p)
        positions = np.concatenate(positions).astype(np.float32)
        attributes = {
            "POSITION": add_accessor(out, data, positions, 5126, "VEC3", min=positions.min(axis=0).tolist(), max=positions.max(axis=0).tolist()),
            "NORMAL": add_accessor(out, data, np.concatenate(normals).astype(np.float32), 5126, "VEC3"),
            "JOINTS_0": add_accessor(out, data, np.concatenate(joints).astype(np.uint8), 5121, "VEC4"),
            "WEIGHTS_0": add_accessor(out, data, np.tile(np.uint8([255, 0, 0, 0]), (count, 1)), 5121, "VEC4", normalized=True),
        }
        indices = add_accessor(out, data, np.concatenate(triangles).astype(np.uint16).ravel(), 5123, "SCALAR")
        out["meshes"].append({"primitives": [{"attributes": attributes, "indices": indices}]})
        out["nodes"].append({"name": colour, "mesh": len(out["meshes"]) - 1, "skin": 0})
    joint_count = len(rig.bones) + len(gear[0])
    skin(out, data, [{"name": f"joint{j}"} for j in range(joint_count)])
    write_glb(f"{clips_dir}/{name}.glb", out, data)

    clip = np.zeros((frames, joint_count, 3, 4), np.float32)
    first = [np.linalg.inv(matrix) for _, matrix, _ in gear[0]]
    low, high = np.full(3, np.inf), np.full(3, -np.inf)
    for f, (R, p) in enumerate(solved):
        for j, bone in enumerate(rig.bones):
            clip[f, j] = in_file(R[bone], p[bone] - R[bone] @ rig.heads[bone])
        for j, (_, matrix, _) in enumerate(gear[f]):
            carried = matrix @ first[j]
            clip[f, len(rig.bones) + j] = in_file(carried[:3, :3], carried[:3, 3])
        clouds = [rig.skin(R, p) @ to_file.T / metres] + [
            q @ clip[f, len(rig.bones) + j, :, :3].T + clip[f, len(rig.bones) + j, :, 3] for j, q in enumerate(rest)
        ]
        low = np.minimum(low, np.min([c.min(axis=0) for c in clouds], axis=0))
        high = np.maximum(high, np.max([c.max(axis=0) for c in clouds], axis=0))
    bounds = np.concatenate([low, high]).astype(np.float32)
    with open(f"{clips_dir}/{name}.clip", "wb") as f:
        f.write(struct.pack("<IIIf", 0x43564D46, joint_count, frames, FPS) + bounds.tobytes() + clip.tobytes())
    sizes = [os.path.getsize(f"{clips_dir}/{name}.{ext}") // 1024 for ext in ("glb", "clip")]
    print(f"{name}: {frames} frames, {joint_count} joints, gear {sizes[0]} KB, clip {sizes[1]} KB")
