"""Lays an exercise's renders out for review.

  python3 sheet.py keys <dir> <exercise> <out.png>   key poses: a row per view
  python3 sheet.py loop <dir> <exercise> <out.webp>  the loop, views side by side
"""

import glob
import json
import re
import sys

from PIL import Image, ImageDraw, ImageFilter

mode, folder, name, out = sys.argv[1:5]
FPS = 15
BACKGROUND = "#F1F3F6"
DISC, DISC_EDGE, SHADOW = "#E3E7EE", "#DCE0E7", (16, 18, 19, 70)


def grid(step):
    """{step index: [image per view]} for files <name>_<step><n>_v<view>.png."""
    cells = {}
    for path in sorted(glob.glob(f"{folder}/{name}_{step}*_v*.png")):
        index, view = map(int, re.search(rf"_{step}(\d+)_v(\d+)\.png$", path).groups())
        render = Image.open(path).convert("RGBA")
        cell = Image.new("RGBA", render.size, BACKGROUND)
        # The owner's pick: a light floor disc with the body's soft shadow on it.
        with open(path[:-4] + ".json") as f:
            floor = json.load(f)
        x, y, w, h = floor["disc"]
        ImageDraw.Draw(cell).ellipse((x - w, y - h, x + w, y + h), fill=DISC, outline=DISC_EDGE)
        x, y, w, h = floor["shadow"]
        shadow = Image.new("RGBA", render.size, (0, 0, 0, 0))
        ImageDraw.Draw(shadow).ellipse((x - w, y - h, x + w, y + h), fill=SHADOW)
        cell.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(max(4, h * 0.6))))
        cell.alpha_composite(render)
        cells.setdefault(index, {})[view] = cell.convert("RGB")
    return [[views[v] for v in sorted(views)] for _, views in sorted(cells.items())]


if mode == "keys":
    columns = grid("k")
    w, h = columns[0][0].size
    sheet = Image.new("RGB", (w * len(columns), h * len(columns[0])), "white")
    for c, views in enumerate(columns):
        for r, image in enumerate(views):
            sheet.paste(image, (c * w, r * h))
    sheet.save(out)
else:
    frames = []
    for views in grid("f"):
        w, h = views[0].size
        frame = Image.new("RGB", (w * len(views), h), "white")
        for i, image in enumerate(views):
            frame.paste(image, (i * w, 0))
        frames.append(frame)
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=round(1000 / FPS), loop=0, quality=82)
