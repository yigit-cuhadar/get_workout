"""The spike's five exercises: key poses, gear and the muscles they work.

Every exercise is a function of the rig returning
  title, keys [(seconds, pose)], gear(rig, R, p) -> [(shape, matrix, colour)],
  main and secondary muscle codes, views [(azimuth, elevation)], and the
  centre and height of the picture.
Poses are described in pose.py.
"""

import numpy as np

from pose import unit


def cyl(a, b, radius, colour="gear"):
    """A cylinder from a to b."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    axis = unit(b - a)
    side = unit(np.cross(axis, (0, 0, 1) if abs(axis[2]) < 0.9 else (1, 0, 0)))
    m = np.eye(4)
    m[:3, 0], m[:3, 1] = side * radius, np.cross(axis, side) * radius
    m[:3, 2], m[:3, 3] = b - a, (a + b) / 2
    return "cyl", m, colour


def box(centre, size, colour="gear", rotation=np.eye(3)):
    m = np.eye(4)
    m[:3, :3], m[:3, 3] = rotation * np.asarray(size, float), centre
    return "box", m, colour


def barbell(rig, R, p, plate=0.225):
    left, right = rig.grip(R, p, "L"), rig.grip(R, p, "R")
    centre, axis = (left + right) / 2, unit(left - right)
    out = [cyl(centre - axis * 1.1, centre + axis * 1.1, 0.014, "steel")]
    for s in (-1, 1):
        out.append(cyl(centre + s * axis * 0.66, centre + s * axis * 0.70, 0.03, "steel"))
        out.append(cyl(centre + s * axis * 0.70, centre + s * axis * 0.76, plate, "plate"))
    return out


def squat(rig):
    def pose(pelvis, lean, lumbar, chest, neck):
        return dict(
            pelvis=pelvis,
            pelvis_rot=(lean, 0, 0),
            lumbar=lumbar,
            chest=chest,
            neck=neck,
            foot=dict(pos=(0.20, 0.037, rig.ankle), yaw=25),
            hand=dict(pos=(0.40, 0.134, 0.20), fingers=(0, 0.25, 1), palm=(0, -1, 0), curl=75, rel="chest"),
            elbow=(0.2, 0.8, -1),
            clavicle=(5, -10),
        )

    top = pose((0, 0.0, 0.965), 3, 0, 0, 0)
    bottom = pose((0, 0.22, 0.52), 35, 3, 3, -22)
    return dict(
        title="Back squat",
        keys=[(0, top), (1.6, bottom), (1.8, bottom), (2.8, top), (3.3, top)],
        gear=barbell,
        main={"quads", "glute"},
        secondary={"adductor", "hamstring", "erector", "abdominal"},
        views=[(35, 8), (90, 4)],
        centre=(0, 0.05, 0.92),
        height=2.1,
    )


def bench_press(rig):
    def pose(bar_y, bar_z):
        return dict(
            pelvis=(0, 0.05, 0.535),
            # A slight arch: the hips and shoulders stay down, the chest rises.
            pelvis_rot=(-80, 0, 0),
            lumbar=-10,
            chest=-10,
            neck=12,
            foot=dict(pos=(0.30, -0.40, rig.ankle), yaw=25),
            hand=dict(pos=(0.38, bar_y, bar_z), fingers=(0, 0, 1), palm=(0, -1, 0), curl=75),
            elbow=(1, -0.45, -0.25),
            clavicle=(0, -12),
        )

    top, bottom = pose(0.48, 1.05), pose(0.37, 0.75)

    def gear(rig, R, p):
        return barbell(rig, R, p) + [
            box((0, 0.48, 0.38), (0.30, 1.25, 0.08), "pad"),
            box((0, -0.05, 0.17), (0.34, 0.06, 0.34)),
            box((0, 1.0, 0.17), (0.34, 0.06, 0.34)),
        ]

    return dict(
        title="Bench press",
        keys=[(0, top), (1.5, bottom), (1.7, bottom), (2.6, top), (3.1, top)],
        gear=gear,
        main={"pec"},
        secondary={"front_delt", "triceps"},
        views=[(50, 14), (90, 4)],
        centre=(0, 0.12, 0.6),
        height=2.1,
    )


def pull_up(rig):
    bar = 2.25

    def pose(pelvis, lean, clavicle, neck):
        return dict(
            pelvis=pelvis,
            pelvis_rot=(lean, 0, 0),
            neck=neck,
            foot=dict(pos=(0.09, -0.10, -0.86), yaw=5, pitch=35, rel="pelvis"),
            hand=dict(pos=(0.32, 0, bar), fingers=(0, 0, 1), palm=(0, -1, 0), curl=80),
            elbow=(0.8, 0.3, -1),
            clavicle=clavicle,
        )

    hang = pose((0, -0.04, 1.115), 0, (30, 0), 0)
    top = pose((0, 0.10, 1.70), -12, (-5, -12), -8)

    def gear(rig, R, p):
        return [cyl((-0.75, 0, bar), (0.75, 0, bar), 0.016, "steel")] + [
            cyl((x, 0, 0), (x, 0, bar + 0.03), 0.03) for x in (-0.75, 0.75)
        ]

    return dict(
        title="Pull-up",
        keys=[(0, hang), (1.2, top), (1.5, top), (2.9, hang), (3.3, hang)],
        gear=gear,
        main={"lat"},
        secondary={"biceps", "rear_delt", "trap", "forearm"},
        views=[(160, 5), (90, 3)],
        centre=(0, 0, 1.25),
        height=2.7,
    )


def lat_pulldown(rig):
    pulley = np.array([0, -0.05, 2.10])
    high = 1.66

    def pose(bar_y, bar_z, lean, chest, clavicle):
        return dict(
            pelvis=(0, 0, 0.567),
            pelvis_rot=(lean, 0, 0),
            chest=chest,
            foot=dict(pos=(0.17, -0.42, rig.ankle), yaw=10),
            hand=dict(pos=(0.42, bar_y, bar_z), fingers=(0, 0, 1), palm=(0, -1, 0), curl=80),
            elbow=(1, 0.25, -0.8),
            clavicle=clavicle,
        )

    top = pose(-0.05, high, 0, 0, (28, 0))
    bottom = pose(-0.04, 1.07, -14, -6, (-5, -12))

    def gear(rig, R, p):
        left, right = rig.grip(R, p, "L"), rig.grip(R, p, "R")
        centre, axis = (left + right) / 2, unit(left - right)
        stack = 0.35 + high - centre[2]
        return [
            cyl(centre - axis * 0.62, centre + axis * 0.62, 0.014, "steel"),
            cyl(pulley - (0, 0, 0.05), centre, 0.006, "steel"),
            cyl(pulley + (0, 0, 0.05), (0, -0.68, 2.15), 0.006, "steel"),
            cyl((0, -0.68, 2.15), (0, -0.68, stack + 0.25), 0.006, "steel"),
            cyl(pulley - (0.02, 0, 0), pulley + (0.02, 0, 0), 0.05, "steel"),
            box((0, -0.68, stack), (0.26, 0.14, 0.5), "plate"),
            box((0, -0.80, 1.1), (0.10, 0.10, 2.2)),
            box((0, -0.42, 2.2), (0.08, 0.86, 0.08)),
            box((0, -0.80, 0.03), (0.6, 0.24, 0.06)),
            box((0, 0.03, 0.40), (0.36, 0.38, 0.08), "pad"),
            box((0, 0.03, 0.2), (0.08, 0.08, 0.34)),
            box((0, 0.03, 0.02), (0.44, 0.3, 0.04)),
            cyl((-0.27, -0.26, 0.68), (0.27, -0.26, 0.68), 0.05, "pad"),
            box((0, -0.53, 0.68), (0.05, 0.54, 0.05)),
        ]

    return dict(
        title="Lat pulldown",
        keys=[(0, top), (1.2, bottom), (1.5, bottom), (2.9, top), (3.3, top)],
        gear=gear,
        main={"lat"},
        secondary={"biceps", "rear_delt", "trap", "forearm"},
        views=[(145, 8), (90, 4)],
        centre=(0, -0.3, 1.12),
        height=2.4,
    )


def deadlift(rig):
    def pose(pelvis, lean, neck, bar_y, bar_z):
        return dict(
            pelvis=pelvis,
            pelvis_rot=(lean, 0, 0),
            neck=neck,
            foot=dict(pos=(0.13, 0.037, rig.ankle), yaw=12),
            hand=dict(pos=(0.27, bar_y, bar_z), fingers=(0, 0, -1), palm=(0, 1, 0), curl=80),
            elbow=(0.3, 1, 0),
            clavicle=(-5, 5),
        )

    bottom = pose((0, 0.34, 0.70), 75, -40, -0.10, 0.225)
    top = pose((0, 0.0, 0.97), 0, 0, -0.12, 0.81)
    return dict(
        title="Deadlift",
        keys=[(0, bottom), (1.3, top), (1.8, top), (3.2, bottom), (3.6, bottom)],
        gear=barbell,
        main={"hamstring", "glute", "erector"},
        secondary={"quads", "trap", "lat", "forearm"},
        views=[(35, 8), (90, 4)],
        centre=(0, 0.05, 0.92),
        height=2.1,
    )


EXERCISES = {
    "squat": squat,
    "bench_press": bench_press,
    "pull_up": pull_up,
    "lat_pulldown": lat_pulldown,
    "deadlift": deadlift,
}

