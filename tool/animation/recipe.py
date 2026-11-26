"""Reads an exercise's animation recipe, `content/animations/<id>.json`.

  status   draft | review | approved | fix, with the owner's `note` on a fix
  view     [yaw, pitch] in degrees the camera starts from
  poses    name -> pose (fields in pose.py); `extends` names the pose it
           starts from. A standing foot is {"at": [x, y], "floor": height}.
  keys     [[seconds, pose name], ...]; the last pose equals the first
  gear     [{"kit": name, "at"?: [x, y, z], "turn"?: degrees, ...values}]
  mistakes [{"line": index into the catalogue's mistakes, "status", "ring":
           [bones], "poses": {name: changed fields, or a new pose}, "keys"?}], or
           {"line", "shown": false, "why"} for one no pose can show

Gear is designed once: a recipe only names kits from `_kits.json` and says
where they stand. A kit is

  status   draft | approved
  values   name -> default, used in the pieces as "$name"
  pieces   {"cyl": [point, point], "r": radius} or {"box": point, "size":
           [x, y, z]}, each with a `colour`
  movers   name -> {"follows": point, "axis": [..], "along": [..]}: how far
           the point has moved along `axis` since the first key, as a shift
           along `along` (a weight stack rising as the bar comes down)

A point is [x, y, z] from the kit's own origin on the floor,
{"grips": [along the bar, forward of it, above it]} between the two hands,
{"at": [x, y, z], "with": mover}, or {"between": [point, point], "t": how far
from the first to the second, past it above 1}.
"""

import json
import os

import numpy as np

from pose import rot_z, unit

HERE = os.path.dirname(os.path.abspath(__file__))
RECIPES = os.path.join(HERE, "..", "..", "content", "animations")
CATALOGUE = os.path.join(HERE, "..", "..", "content", "exercises")
STATUSES = ("draft", "review", "approved", "fix")
PLACING = ("kit", "at", "turn")


def load(exercise):
    with open(os.path.join(RECIPES, f"{exercise}.json")) as f:
        return json.load(f)


def kits(path=None):
    with open(path or os.path.join(RECIPES, "_kits.json")) as f:
        return json.load(f)


def catalogue():
    """Every exercise of the catalogue by id."""
    out = {}
    for name in sorted(os.listdir(CATALOGUE)):
        with open(os.path.join(CATALOGUE, name)) as f:
            out |= {e["id"]: e for e in json.load(f)}
    return out


def merged(base, change):
    out = dict(base)
    for key, value in change.items():
        both = isinstance(value, dict) and isinstance(out.get(key), dict)
        out[key] = merged(out[key], value) if both else value
    return out


def poses_of(recipe, mistake=None):
    """Every pose with what it extends folded in. A mistake changes fields of
    the recipe's poses and may add poses of its own."""
    changes = recipe["mistakes"][mistake].get("poses", {}) if mistake is not None else {}
    done = {}

    def pose(name):
        if name not in done:
            own = merged(recipe["poses"].get(name, {}), changes.get(name, {}))
            base = own.pop("extends", None)
            done[name] = merged(pose(base), own) if base else own
        return done[name]

    return {name: pose(name) for name in {**recipe["poses"], **changes}}


def clip(recipe, mistake=None):
    """[(seconds, pose)] of the correct form, or of mistake number `mistake`."""
    poses = poses_of(recipe, mistake)
    keys = recipe["keys"] if mistake is None else recipe["mistakes"][mistake].get("keys", recipe["keys"])
    return [(t, poses[name]) for t, name in keys]


def filled(value, values):
    if isinstance(value, dict):
        return {k: filled(v, values) for k, v in value.items()}
    if isinstance(value, list):
        return [filled(v, values) for v in value]
    return values[value[1:]] if isinstance(value, str) and value.startswith("$") else value


def gear_of(uses, kit_set=None):
    """gear(rig, now, first) -> [(shape, 4x4 matrix, colour)] for the kits a
    recipe uses; `now` and `first` are the solved (R, p) of this frame and of
    the first key."""
    placed, kit_set = [], kit_set or kits()
    for use in uses:
        kit = kit_set[use["kit"]]
        values = kit.get("values", {}) | {k: v for k, v in use.items() if k not in PLACING}
        turn, at = rot_z(use.get("turn", 0)), np.array(use.get("at", (0, 0, 0)), float)
        placed.append((filled(kit["pieces"], values), filled(kit.get("movers", {}), values), turn, at))

    def gear(rig, now, first):
        out = []
        for pieces, movers, turn, at in placed:

            def point(spec, solved=now):
                if isinstance(spec, list):
                    return turn @ spec + at
                if "grips" in spec:
                    left, right = rig.grip(*solved, "L"), rig.grip(*solved, "R")
                    along = unit(left - right)
                    up = unit((0, 0, 1) - along[2] * along)
                    return (left + right) / 2 + np.stack([along, np.cross(up, along), up], axis=1) @ spec["grips"]
                if "between" in spec:
                    a, b = (point(end, solved) for end in spec["between"])
                    return a + (b - a) * spec["t"]
                mover = movers[spec["with"]]
                moved = point(mover["follows"]) - point(mover["follows"], first)
                return turn @ (np.array(spec["at"], float) + np.array(mover["along"], float) * (moved @ (turn @ mover["axis"]))) + at

            for piece in pieces:
                m = np.eye(4)
                if "cyl" in piece:
                    a, b = (point(end) for end in piece["cyl"])
                    axis = unit(b - a)
                    side = unit(np.cross(axis, (0, 0, 1) if abs(axis[2]) < 0.9 else (1, 0, 0)))
                    m[:3, 0], m[:3, 1] = side * piece["r"], np.cross(axis, side) * piece["r"]
                    m[:3, 2], m[:3, 3] = b - a, (a + b) / 2
                else:
                    m[:3, :3], m[:3, 3] = turn @ np.diag(piece["size"]), point(piece["box"])
                out.append(("cyl" if "cyl" in piece else "box", m, piece.get("colour", "gear")))
        return out

    return gear
