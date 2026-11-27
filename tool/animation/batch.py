"""Where the work stands and what comes next.

  python3 batch.py [size]     (default: 5 exercises)

Prints the count of live exercises by recipe status, the kits and their
status, and the next batch: whole families, the family whose most popular
exercise still lacks an approved recipe first, then by family rank.
"""

import os
import sys
from collections import Counter

import recipe

GROUPS = [
    ("barbell", {"barbell", "ez_bar", "trap_bar", "smith_machine", "landmine", "plate"}),
    ("dumbbell", {"dumbbell", "kettlebell"}),
    ("cable", {"cable"}),
    ("machine", {"machine", "sled", "back_extension_bench"}),
    ("bars", {"pull_up_bar", "dip_station", "rings", "suspension_trainer"}),
    ("bands", {"resistance_band"}),
]
size = int(sys.argv[1]) if len(sys.argv) > 1 else 5
live = [e for e in recipe.catalogue().values() if e["status"] == "live"]
status = {
    e["id"]: recipe.load(e["id"])["status"] if os.path.exists(os.path.join(recipe.RECIPES, f"{e['id']}.json")) else "none"
    for e in live
}


def group(exercise):
    return next((i for i, (_, codes) in enumerate(GROUPS) if codes & set(exercise["equipment"])), len(GROUPS))


families = {}
for e in live:
    families.setdefault((group(e), e["family"]), []).append(e)


def first_todo(members):
    return min((e["popularity"] for e in members if status[e["id"]] != "approved"), default=len(live) + 1)


order = sorted(families.items(), key=lambda kv: (first_todo(kv[1]), kv[0][1]))

counts = Counter(status.values())
print(f"{len(live)} live exercises: " + ", ".join(f"{counts[s]} {s}" for s in (*recipe.STATUSES, "none") if counts[s]))
print("kits: " + ", ".join(f"{name} ({kit['status']})" for name, kit in recipe.kits().items()))
batch = []
for (index, family), members in order:
    todo = [e for e in sorted(members, key=lambda e: e["familyRank"]) if status[e["id"]] != "approved"]
    if todo and (not batch or len(batch) + len(todo) <= size):
        batch += [(index, family, e) for e in todo]
    if len(batch) >= size:
        break
print("next batch:")
for index, family, e in batch:
    name = GROUPS[index][0] if index < len(GROUPS) else "bodyweight and the rest"
    mistakes = len(e["l10n"]["en"].get("mistakes", []))
    print(f"  {e['id']}  ({name}, family {family}, {mistakes} mistakes, recipe {status[e['id']]})")
