"""Solves recipes on a joints-only rig and writes the answers, so a solver in
another language can be checked against this one.

  python3 golden.py <rig.json> <kits.json> <out.json> <recipe.json> ...

For every recipe and clip (the correct form, then each shown mistake) at three
times: per bone the 3x4 matrix that moves a vertex of the body file, and per
gear piece its shape, colour and the 3x4 matrix that places the unit shape (a
cube of side 1, or a cylinder of radius 1 and height 1 along z), all in the
body file's space (y up, facing +z, the file's own unit).
"""

import json
import sys

import numpy as np

import recipe
from pose import Rig, normalized, pose_at

rig_path, kits_path, out, *recipes = sys.argv[1:]
rig = Rig(rig_path)
with open(rig_path) as f:
    metres = json.load(f)["metres"]
kit_set = recipe.kits(kits_path)
to_file = np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]], float)


def in_file(linear, offset, unit=False):
    """A rig-space transform in the file's space: of a vertex of the file, or
    of a unit shape given in metres."""
    linear = to_file @ linear / metres if unit else to_file @ linear @ to_file.T
    return np.hstack([linear, (to_file @ offset / metres)[:, None]]).round(6).tolist()


answers = {}
for path in recipes:
    with open(path) as f:
        spec = json.load(f)
    gear = recipe.gear_of(spec["gear"], kit_set)
    clips = []
    shown = [None] + [i for i, m in enumerate(spec["mistakes"]) if m.get("shown", True)]
    for mistake in shown:
        raw = recipe.clip(spec, mistake)
        poses = {id(p): normalized(p) for _, p in raw}
        keys = [(t, poses[id(p)]) for t, p in raw]
        first = rig.solve(keys[0][1])
        samples = []
        for t in (0.0, round(keys[-1][0] * 0.37, 3), round(keys[-1][0] * 0.71, 3)):
            R, p = rig.solve(pose_at(keys, t))
            samples.append(
                {
                    "t": t,
                    "joints": [in_file(R[b], p[b] - R[b] @ rig.heads[b]) for b in rig.bones],
                    "gear": [
                        {"shape": kind, "colour": colour, "matrix": in_file(m[:3, :3], m[:3, 3], unit=True)}
                        for kind, m, colour in gear(rig, (R, p), first)
                    ],
                }
            )
        clips.append({"mistake": mistake, "duration": keys[-1][0], "samples": samples})
    answers[path.split("/")[-1][:-5]] = clips
with open(out, "w") as f:
    json.dump(answers, f)
print(f"{out}: {len(answers)} recipes")
