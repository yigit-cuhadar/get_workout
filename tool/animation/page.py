"""Builds a batch's review page from the loops preview.sh rendered.

  python3 page.py <out.html> <title> <notes.json> <exercise id> ...

notes.json maps an exercise id to the lines the owner should read first.
The page and its smaller loops (in a folder beside it) are in Turkish.
"""

import html
import json
import os
import sys

from PIL import Image

import recipe

out, title, notes_path, *ids = sys.argv[1:]
folder = os.path.splitext(out)[0]
source = os.path.dirname(out)
os.makedirs(folder, exist_ok=True)
with open(notes_path) as f:
    notes = json.load(f)
catalogue = recipe.catalogue()


def clip(name):
    """A half-size copy of a loop; its path as the page links it."""
    loop = Image.open(f"{source}/{name}.webp")
    frames = []
    for i in range(loop.n_frames):
        loop.seek(i)
        frames.append(loop.convert("RGB").resize((loop.width // 2, loop.height // 2), Image.LANCZOS))
    frames[0].save(f"{folder}/{name}.webp", save_all=True, append_images=frames[1:], duration=loop.info["duration"], loop=0, quality=68)
    return f"{os.path.basename(folder)}/{name}.webp"


def figure(src, alt, caption):
    return f'<figure><img src="{src}" width="720" height="360" alt="{alt}"><figcaption>{caption}</figcaption></figure>'


cards, count = [], 0
for name in ids:
    text, spec = catalogue[name]["l10n"]["tr"], recipe.load(name)
    clips = figure(clip(name), f"{html.escape(text['name'])}, doğru yapılış", "<b>Doğru yapılış</b>")
    count += 1
    for mistake in spec["mistakes"]:
        line = html.escape(text["mistakes"][mistake["line"]])
        if mistake.get("shown", True):
            clips += figure(clip(f"{name}-m{mistake['line']}"), f"Hata: {line}", f'<b class="bad">Hata</b> {line}')
            count += 1
        else:
            clips += f'<p class="skip"><b>Animasyonu yok:</b> {line} <span>Poz ile gösterilemiyor.</span></p>'
    lines = "".join(f"<li>{html.escape(n)}</li>" for n in notes.get(name, []))
    cards.append(f'<article><h2>{html.escape(text["name"])}</h2><ul>{lines}</ul><div class="clips">{clips}</div></article>')

page = f"""<title>{html.escape(title)}</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=Space+Grotesk:wght@500;600&display=swap">
<style>
  /* Layout: one column of exercises; each lists what to look at, then its loops in a wrapping grid. */
  :root{{--bg:#F1F3F6;--surface:#FFFFFF;--ink:#101213;--muted:#586273;--line:#DCE0E7;--bad:#A6473C;--plate:#F1F3F6}}
  @media (prefers-color-scheme: dark){{:root:not([data-theme="light"]){{--bg:#15191C;--surface:#1D2226;--ink:#E6E9EB;--muted:#9AA3AB;--line:#2E353B;--bad:#D98C80;--plate:#F1F3F6;color-scheme:dark}}}}
  :root[data-theme="dark"]{{--bg:#15191C;--surface:#1D2226;--ink:#E6E9EB;--muted:#9AA3AB;--line:#2E353B;--bad:#D98C80;--plate:#F1F3F6;color-scheme:dark}}
  body{{background:var(--bg);color:var(--ink);font:400 16px/1.55 Inter,system-ui,sans-serif;padding-block:40px 64px;padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px))}}
  main{{max-width:1120px;margin-inline:auto;display:grid;gap:28px}}
  h1{{font:600 2rem/1.15 "Space Grotesk",Inter,sans-serif;margin:0;text-wrap:balance}}
  h2{{font:600 1.25rem/1.25 "Space Grotesk",Inter,sans-serif;margin:0}}
  header p{{color:var(--muted);max-width:68ch;margin:10px 0 0}}
  article{{background:var(--surface);border:1px solid var(--line);border-radius:12px;padding:16px;display:grid;gap:12px}}
  ul{{margin:0;padding-left:1.1em;color:var(--muted);font-size:.9375rem;display:grid;gap:4px}}
  .clips{{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,340px),1fr));gap:12px}}
  figure{{margin:0;min-width:0}}
  figure img{{display:block;width:100%;height:auto;background:var(--plate);border-radius:8px}}
  figcaption{{font-size:.875rem;margin-top:6px}}
  .bad{{color:var(--bad)}}
  .skip{{margin:0;font-size:.875rem;align-self:center;color:var(--muted)}}
  .skip b{{color:var(--ink)}} .skip span{{display:block}}
</style>
<main>
<header><h1>{html.escape(title)}</h1>
<p>{len(ids)} hareket, her biri doğru yapılışı ve pozla gösterilebilen hatalarıyla: {count} animasyon. Her karede solda hareketin kendi açısı, sağda yandan görünüş var. Hatalarda hatalı eklem kırmızı halkayla işaretli. Görüntüler önizlemeden; uygulamada henüz oynamıyor.</p></header>
{chr(10).join(cards)}
</main>
"""
with open(out, "w") as f:
    f.write(page)
print(f"{out}: {len(ids)} exercises, {count} animations")
