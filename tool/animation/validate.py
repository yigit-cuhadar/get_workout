"""Checks the recipes before anything is shown to the owner or imported.

  python3 validate.py [exercise id ...]     (default: every recipe)

Reads the rigs preview.sh built in build/animation; without them only the
files' shape is checked. Exits 1 when anything is wrong.
"""

import os
import sys

import numpy as np

import recipe
from pose import SIDES, Rig, normalized

REACH = 0.005  # metres a hand or foot may end from its target
FLOOR = -0.001
POSE_KEYS = {"pelvis", "pelvis_rot", "lumbar", "chest", "neck", "head", "clavicle", "hand", "elbow", "foot", "knee"}
POSE_KEYS |= {f"{k}_{side}" for k in ("clavicle", "hand", "elbow", "foot", "knee") for side, _ in SIDES}

catalogue, kits = recipe.catalogue(), recipe.kits()
rigs = {
    body: Rig(path)
    for body in ("male", "female")
    for path in [os.path.join(recipe.HERE, "..", "..", "build", "animation", f"rig_{body}.npz")]
    if os.path.exists(path)
}
problems = []


def check(name):
    def bad(text):
        problems.append(f"{name}: {text}")

    if name not in catalogue:
        return bad("no such exercise in the catalogue")
    spec = recipe.load(name)
    if spec.get("status") not in recipe.STATUSES:
        bad(f"status is {spec.get('status')!r}")
    if spec.get("status") == "fix" and not spec.get("note"):
        bad("a fix needs the owner's note")
    for use in spec["gear"]:
        if set(use) - {"kit", "at", "turn"} - set(kits.get(use.get("kit"), {}).get("values", {})):
            bad(f"gear {use} is not a kit with its values: gear is designed in _kits.json only")
        elif use["kit"] not in kits:
            bad(f"no kit {use['kit']!r}")
        elif spec["status"] in ("review", "approved") and kits[use["kit"]]["status"] != "approved":
            bad(f"kit {use['kit']!r} is not approved yet")
    for pose_name, pose in recipe.poses_of(spec).items():
        if set(pose) - POSE_KEYS:
            bad(f"pose {pose_name!r} has unknown fields {sorted(set(pose) - POSE_KEYS)}")

    lines = catalogue[name]["l10n"]["en"].get("mistakes", [])
    seen = [m["line"] for m in spec["mistakes"]]
    if len(set(seen)) != len(seen) or any(not 0 <= line < len(lines) for line in seen):
        bad(f"mistake lines {seen} do not match the catalogue's {len(lines)}")
    if spec["status"] in ("review", "approved") and set(seen) != set(range(len(lines))):
        bad(f"mistakes {sorted(set(range(len(lines))) - set(seen))} are neither animated nor marked as not shown")
    for mistake in spec["mistakes"]:
        if mistake.get("shown", True):
            if mistake.get("status") not in recipe.STATUSES or not mistake.get("ring"):
                bad(f"mistake {mistake['line']} needs a status and joints to ring")
        elif not mistake.get("why"):
            bad(f"mistake {mistake['line']} is not shown and does not say why")

    clips = [("correct form", recipe.clip(spec), [])]
    clips += [
        (f"mistake {m['line']}", recipe.clip(spec, i), m["ring"])
        for i, m in enumerate(spec["mistakes"])
        if m.get("shown", True)
    ]
    gear = recipe.gear_of(spec["gear"])
    for label, keys, ring in clips:
        times = [t for t, _ in keys]
        if times[0] != 0 or times != sorted(times) or keys[0][1] is not keys[-1][1]:
            bad(f"{label}: keys must start at 0, run forward and end on the first pose")
        for body, rig in rigs.items():
            if set(ring) - set(rig.bones):
                bad(f"{label}: no joints {sorted(set(ring) - set(rig.bones))}")
            first = rig.solve(normalized(keys[0][1]))
            for t, pose in keys:
                solved = rig.solve(normalized(pose))
                for limb, miss in rig.missed.items():
                    if miss > REACH:
                        bad(f"{label} at {t}s on the {body} body: {limb} ends {miss * 100:.1f} cm short of its target")
                for kind, m, _ in gear(rig, solved, first):
                    r = 1 if kind == "cyl" else 0.5
                    low = min((m[:3, :3] @ (x, y, z) + m[:3, 3])[2] for x in (-r, r) for y in (-r, r) for z in (-0.5, 0.5))
                    if kind == "box" and low < FLOOR:
                        bad(f"{label} at {t}s: a box of the gear goes {-low * 100:.1f} cm under the floor")
        # A foot that stands does not slide: it may turn on the spot, and it
        # stands somewhere else only after a key that lifts it.
        for side, _ in SIDES:
            feet = [normalized(pose)[f"foot_{side}"] for _, pose in keys]
            for here, there in zip(feet, feet[1:]):
                if "at" in here and "at" in there and not np.allclose(here["at"], there["at"]):
                    bad(f"{label}: foot {side} slides from one standing place to another; lift it in a key between")
                if ("at" in here) != ("at" in there) and (here["rel"] is not None or there["rel"] is not None):
                    bad(f"{label}: foot {side} steps to or from a foot given in a bone")


names = sys.argv[1:] or sorted(f[:-5] for f in os.listdir(recipe.RECIPES) if not f.startswith("_"))
for kit_name, kit in kits.items():
    if kit.get("status") not in ("draft", "approved"):
        problems.append(f"kit {kit_name}: status is {kit.get('status')!r}")
for name in names:
    check(name)
print("\n".join(problems) or f"{len(names)} recipes hold on {' and '.join(rigs) or 'no'} bodies")
sys.exit(1 if problems else 0)
