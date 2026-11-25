"""Poses the rig from a few targets and skins the body.

Axes: z up, the body faces -y, its left is +x. Lengths in metres, angles in
degrees. A pose is a dict:

  pelvis      position of the pelvis joint
  pelvis_rot  (pitch, yaw, roll); pitch leans forward, yaw turns left
  lumbar, chest, neck, head   (pitch, yaw, roll) against the parent
  clavicle    (elevation, protraction) of both shoulders
  hand        {pos, fingers, palm, curl}: the grip point, the directions the
              fingers and the palm face, and how far the fingers close
  elbow       where the elbow points
  foot        {pos, yaw, pitch}: the ankle, the toe-out and the toes-down angle
  knee        where the knee points (default: over the toes)

`hand`, `elbow`, `foot`, `knee` and `clavicle` describe the left side and are
mirrored to the right; `hand_R` and the like override one side. A hand or
foot with `rel` names the bone its position, its directions and its elbow or
knee are given in.
"""

import numpy as np

SIDES = (("L", 1.0), ("R", -1.0))
# How far the grip point sits from the wrist: along the fingers, into the palm.
GRIP = (0.10, 0.028)


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


def rot_x(deg):
    c, s = np.cos(np.radians(deg)), np.sin(np.radians(deg))
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def rot_y(deg):
    c, s = np.cos(np.radians(deg)), np.sin(np.radians(deg))
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rot_z(deg):
    c, s = np.cos(np.radians(deg)), np.sin(np.radians(deg))
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def euler(angles):
    pitch, yaw, roll = angles
    return rot_z(yaw) @ rot_x(pitch) @ rot_y(roll)


def rot_axis(axis, rad):
    x, y, z = unit(axis)
    k = np.array([[0, -z, y], [z, 0, -x], [-y, x, 0]])
    return np.eye(3) + np.sin(rad) * k + (1 - np.cos(rad)) * (k @ k)


def halfway(a, b):
    """The rotation half way from a to b."""
    turn = a.T @ b
    angle = np.arccos(np.clip((np.trace(turn) - 1) / 2, -1, 1))
    if angle < 1e-6:
        return a
    axis = np.array([turn[2, 1] - turn[1, 2], turn[0, 2] - turn[2, 0], turn[1, 0] - turn[0, 1]])
    if np.linalg.norm(axis) < 1e-6:
        # Half a turn: the axis is the largest column of turn + 1.
        columns = (turn + np.eye(3)).T
        axis = columns[np.argmax(np.linalg.norm(columns, axis=1))]
    return a @ rot_axis(axis, angle / 2)


def frame(axis, normal):
    """Orthonormal frame along `axis` whose third column is nearest `normal`."""
    a = unit(axis)
    n = unit(normal - (normal @ a) * a)
    return np.stack([a, np.cross(n, a), n], axis=1)


def twist_about(rotation, axis, reference):
    """Angle by which `rotation` turns `reference` around `axis`."""
    a = unit(axis)
    before = reference - (reference @ a) * a
    after = rotation @ reference
    after = after - (after @ a) * a
    return np.arctan2(np.cross(before, after) @ a, before @ after)


def solve_limb(root, target, upper, lower, pole):
    """Two-bone IK: the middle joint, the reached end and the bend normal."""
    to_target = target - root
    distance = np.linalg.norm(to_target)
    reach = np.clip(distance, abs(upper - lower) + 1e-4, (upper + lower) * 0.999)
    a = to_target / distance
    side = unit(pole - (pole @ a) * a)
    cos = (upper**2 + reach**2 - lower**2) / (2 * upper * reach)
    mid = root + upper * (cos * a + np.sqrt(1 - cos**2) * side)
    return mid, root + reach * a, np.cross(a, side)


def mirrored(value):
    if isinstance(value, dict):
        return {k: mirrored(v) for k, v in value.items()}
    if isinstance(value, np.ndarray) and value.shape == (3,):
        return value * (-1, 1, 1)
    return value


def lerp(a, b, t):
    if isinstance(a, dict):
        return {k: lerp(a[k], b[k], t) for k in a}
    if isinstance(a, str) or a is None:
        return a
    return a + (b - a) * t


def normalized(pose):
    """Arrays everywhere and both sides spelled out, so poses interpolate."""
    def arrays(value):
        if isinstance(value, dict):
            return {k: arrays(v) for k, v in value.items()}
        if isinstance(value, str) or value is None:
            return value
        return np.asarray(value, float)

    pose = arrays(pose)
    out = {
        "pelvis": pose["pelvis"],
        "pelvis_rot": pose.get("pelvis_rot", np.zeros(3)),
    }
    for joint in ("lumbar", "chest", "neck", "head"):
        angles = pose.get(joint, np.zeros(3))
        out[joint] = angles if angles.ndim else np.array([angles, 0.0, 0.0])
    for side, _ in SIDES:
        for key, default in (
            ("clavicle", np.zeros(2)),
            ("hand", None),
            ("elbow", np.array([0.3, 1.0, -0.3])),
            ("foot", None),
            ("knee", None),
        ):
            value = pose.get(f"{key}_{side}")
            if value is None:
                value = pose.get(key, default)
                if side == "R" and key != "clavicle":
                    value = mirrored(value)
            out[f"{key}_{side}"] = value
        foot = out[f"foot_{side}"]
        out[f"foot_{side}"] = {"yaw": np.float64(10), "pitch": np.float64(0), "rel": None} | foot
        out[f"hand_{side}"] = {"curl": np.float64(0), "rel": None} | out[f"hand_{side}"]
    return out


class Rig:
    def __init__(self, path):
        data = np.load(path)
        self.verts = data["verts"].astype(float)
        self.tris = data["tris"]
        self.tri_part = data["tri_part"]
        self.part_names = [str(n) for n in data["part_names"]]
        self.bones = [str(n) for n in data["bone_names"]]
        self.index = {name: i for i, name in enumerate(self.bones)}
        self.heads = dict(zip(self.bones, data["bone_heads"].astype(float)))
        self.tails = dict(zip(self.bones, data["bone_tails"].astype(float)))
        self.skin_bones = data["skin_bones"]
        self.skin_weights = data["skin_weights"].astype(float)
        palms = dict(zip("LR", data["palms"].astype(float)))
        self.ankle = self.heads["foot_L"][2]
        self.rest = {}
        for side, sign in SIDES:
            shoulder, elbow = self.heads[f"upper_arm_{side}"], self.heads[f"forearm_{side}"]
            wrist, fingers = self.heads[f"hand_{side}"], self.tails[f"fingertips_{side}"]
            hip, knee, ankle = (self.heads[f"{b}_{side}"] for b in ("thigh", "shin", "foot"))
            arm_normal = np.cross(unit(wrist - shoulder), (0, 1, 0))
            leg_normal = np.cross(unit(ankle - hip), (0, -1, 0))
            self.rest[side] = {
                "upper_arm": frame(elbow - shoulder, arm_normal),
                "forearm": frame(wrist - elbow, arm_normal),
                "hand": frame(fingers - wrist, np.cross(fingers - wrist, palms[side])),
                "thigh": frame(knee - hip, leg_normal),
                "shin": frame(ankle - knee, leg_normal),
                "arm": (np.linalg.norm(elbow - shoulder), np.linalg.norm(wrist - elbow)),
                "leg": (np.linalg.norm(knee - hip), np.linalg.norm(ankle - knee)),
            }

    def solve(self, pose):
        """World rotation and position of every bone for a normalized pose."""
        h = self.heads
        R, p = {}, {}

        def place(bone, parent, rotation):
            R[bone] = rotation
            p[bone] = p[parent] + R[parent] @ (h[bone] - h[parent])

        R["pelvis"], p["pelvis"] = euler(pose["pelvis_rot"]), pose["pelvis"]
        for bone, parent in (("lumbar", "pelvis"), ("chest", "lumbar"), ("neck", "chest"), ("head", "neck")):
            place(bone, parent, R[parent] @ euler(pose[bone]))

        def world(spec, key):
            value = spec[key]
            if spec["rel"] is None:
                return value
            rel = spec["rel"]
            return R[rel] @ value + (p[rel] if key == "pos" else 0)

        for side, sign in SIDES:
            rest = self.rest[side]
            elevation, protraction = pose[f"clavicle_{side}"]
            place(f"clavicle_{side}", "chest", R["chest"] @ rot_z(-sign * protraction) @ rot_y(-sign * elevation))

            hand = pose[f"hand_{side}"]
            fingers, palm = unit(world(hand, "fingers")), world(hand, "palm")
            hand_frame = frame(fingers, np.cross(fingers, palm))
            R[f"hand_{side}"] = hand_frame @ rest["hand"].T
            curl = rot_axis(hand_frame[:, 2], np.radians(hand["curl"]))
            R[f"fingers_{side}"] = curl @ R[f"hand_{side}"]
            R[f"fingertips_{side}"] = curl @ curl @ R[f"hand_{side}"]
            grip = hand_frame @ (GRIP[0], GRIP[1], 0)
            shoulder = p[f"clavicle_{side}"] + R[f"clavicle_{side}"] @ (h[f"upper_arm_{side}"] - h[f"clavicle_{side}"])
            elbow_pole = pose[f"elbow_{side}"]
            if hand["rel"] is not None:
                elbow_pole = R[hand["rel"]] @ elbow_pole
            elbow, wrist, normal = solve_limb(shoulder, world(hand, "pos") - grip, *rest["arm"], elbow_pole)
            R[f"upper_arm_{side}"] = frame(elbow - shoulder, normal) @ rest["upper_arm"].T
            swing = frame(wrist - elbow, normal) @ rest["forearm"].T
            twist = twist_about(R[f"hand_{side}"] @ swing.T, wrist - elbow, swing @ rest["forearm"][:, 1])
            R[f"forearm_{side}"] = rot_axis(wrist - elbow, twist / 3) @ swing
            R[f"wrist_{side}"] = rot_axis(wrist - elbow, twist * 2 / 3) @ swing
            p[f"upper_arm_{side}"], p[f"forearm_{side}"] = shoulder, elbow
            p[f"wrist_{side}"], p[f"hand_{side}"] = (elbow + wrist) / 2, wrist
            # The thumb closes round the fingers' direction, toward the palm.
            R[f"thumb_{side}"] = rot_axis(fingers, sign * np.radians(hand["curl"]) * 0.8) @ R[f"hand_{side}"]
            for bone, parent in (("fingers", "hand"), ("fingertips", "fingers"), ("thumb", "hand")):
                p[f"{bone}_{side}"] = p[f"{parent}_{side}"] + R[f"{parent}_{side}"] @ (h[f"{bone}_{side}"] - h[f"{parent}_{side}"])

            foot = pose[f"foot_{side}"]
            R[f"foot_{side}"] = rot_z(sign * (foot["yaw"] - 10)) @ rot_x(foot["pitch"])
            if foot["rel"] is not None:
                R[f"foot_{side}"] = R[foot["rel"]] @ R[f"foot_{side}"]
            knee_pole = pose[f"knee_{side}"]
            if knee_pole is None:
                knee_pole = R[f"foot_{side}"] @ rot_z(sign * 10) @ (0, -1, 0)
            elif foot["rel"] is not None:
                knee_pole = R[foot["rel"]] @ knee_pole
            hip = p["pelvis"] + R["pelvis"] @ (h[f"thigh_{side}"] - h["pelvis"])
            knee, ankle, normal = solve_limb(hip, world(foot, "pos"), *rest["leg"], knee_pole)
            R[f"thigh_{side}"] = frame(knee - hip, normal) @ rest["thigh"].T
            R[f"shin_{side}"] = frame(ankle - knee, normal) @ rest["shin"].T
            p[f"thigh_{side}"], p[f"shin_{side}"], p[f"foot_{side}"] = hip, knee, ankle

            for helper, above, below in (
                ("shoulder", f"clavicle_{side}", "upper_arm"),
                ("elbow", f"upper_arm_{side}", "forearm"),
                ("hip", "pelvis", "thigh"),
                ("knee", f"thigh_{side}", "shin"),
            ):
                R[f"{helper}_{side}"] = halfway(R[above], R[f"{below}_{side}"])
                p[f"{helper}_{side}"] = p[f"{below}_{side}"]
        return R, p

    def grip(self, R, p, side):
        """Where the hand holds: the point the pose's `hand.pos` asked for."""
        return p[f"hand_{side}"] + R[f"hand_{side}"] @ self.rest[side]["hand"] @ (GRIP[0], GRIP[1], 0)

    def skin(self, R, p):
        rotations = np.stack([R[b] for b in self.bones])
        offsets = np.stack([p[b] - R[b] @ self.heads[b] for b in self.bones])
        out = np.zeros_like(self.verts)
        for k in range(self.skin_bones.shape[1]):
            bone = self.skin_bones[:, k]
            moved = np.einsum("nij,nj->ni", rotations[bone], self.verts) + offsets[bone]
            out += self.skin_weights[:, k, None] * moved
        return out


def ease(t):
    return t * t * (3 - 2 * t)


def pose_at(keys, time):
    """The pose at `time` seconds from [(time, normalized pose), ...]."""
    for (t0, a), (t1, b) in zip(keys, keys[1:]):
        if time <= t1:
            return lerp(a, b, ease((time - t0) / (t1 - t0)))
    return keys[-1][1]
