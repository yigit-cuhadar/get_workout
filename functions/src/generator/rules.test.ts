import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, test } from "node:test";

import { Rules, optionsOf, rulesProblems } from "./rules";

const seed = (): Rules =>
  JSON.parse(
    readFileSync(
      join(__dirname, "../../../content/generator/rules.json"),
      "utf8",
    ),
  );

/** The problems of the seed after [change]. */
const problemsAfter = (change: (rules: Rules) => void) => {
  const rules = seed();
  change(rules);
  return rulesProblems(rules);
};

describe("rulesProblems", () => {
  test("accepts the seed", () => {
    assert.deepEqual(rulesProblems(seed()), []);
  });

  test("refuses what is not an object", () => {
    assert.deepEqual(rulesProblems(null), ["rules: must be an object"]);
    assert.deepEqual(rulesProblems([]), ["rules: must be an object"]);
  });

  test("names an unknown or a missing field by its path", () => {
    assert.deepEqual(
      problemsAfter((r) => Object.assign(r, { extra: 1 })),
      ["rules.extra: unknown field"],
    );
    assert.deepEqual(
      problemsAfter((r) => {
        delete (r.dosing.lose_fat as Partial<typeof r.dosing.lose_fat>).core;
      }),
      ["dosing.lose_fat.core: is missing"],
    );
  });

  test("checks codes, ranges and references", () => {
    assert.deepEqual(
      problemsAfter((r) => {
        r.templates[0].split = "nope";
        r.templates[0].dayList[0].slots[0].pick.muscles = ["wing"];
        r.dosing.build_muscle.primary.reps = [12, 8];
        r.dosing.build_muscle.primary.sets.beginner = [0, 3];
        r.time.sessionMinutes = [60, 45];
      }),
      [
        "templates[0].split: must be the id of a split",
        "templates[0].dayList[0].slots[0].pick.muscles[0]: must be one of " +
          "pec, lat, trap, front_delt, mid_delt, rear_delt, biceps, triceps, " +
          "forearm, abdominal, oblique, erector, glute, abductor, adductor, " +
          "quads, hamstring, calf",
        "dosing.build_muscle.primary.sets.beginner[0]: must be a whole number from 1 to 10",
        "dosing.build_muscle.primary.reps: min is above max",
        "time.sessionMinutes: must rise",
      ],
    );
  });

  test("a template has as many days as it is for, each with a priority 1 slot", () => {
    assert.deepEqual(
      problemsAfter((r) => {
        r.templates[0].dayList.pop();
      }),
      ["templates[0].dayList: must have 2 days"],
    );
    assert.deepEqual(
      problemsAfter((r) => {
        for (const slot of r.templates[0].dayList[0].slots) slot.priority = 2;
      }),
      ["templates[0].dayList[0].slots: needs a slot of priority 1"],
    );
  });

  test("a slot picks by pattern or muscle", () => {
    assert.deepEqual(
      problemsAfter((r) => {
        r.templates[0].dayList[0].slots[0].pick = { mechanic: "compound" };
      }),
      ["templates[0].dayList[0].slots[0].pick: needs patterns or muscles"],
    );
  });

  test("names fit what the app stores", () => {
    assert.deepEqual(
      problemsAfter((r) => {
        r.templates[0].dayList[0].l10n.en.name = "x".repeat(41);
        r.splits[0].l10n.en.name = "x".repeat(41);
        r.splits[0].l10n.en.info = "x".repeat(200);
      }),
      [
        "splits[0].l10n.en.name: must be a text of 1 to 40 characters",
        "templates[0].dayList[0].l10n.en.name: must be a text of 1 to 40 characters",
      ],
    );
  });

  test("ids are used once", () => {
    assert.deepEqual(
      problemsAfter((r) => {
        r.templates[1].id = r.templates[0].id;
        r.splits.push(r.splits[0]);
      }),
      ["splits[5].id: is used twice", "templates[1].id: is used twice"],
    );
  });
});

describe("optionsOf", () => {
  test("lists each split with the days, levels and goals its templates fit", () => {
    const options = optionsOf(seed());
    assert.deepEqual(options.sessionMinutes, [30, 45, 60, 75, 90]);
    assert.equal(options.maxFocusAreas, 2);
    assert.deepEqual(
      options.splits.map((split) => split.id),
      ["full_body", "upper_lower", "push_pull_legs", "upper_lower_ppl", "body_part"],
    );
    const fullBody = options.splits[0];
    assert.equal(fullBody.l10n.en.name, "Full body");
    assert.deepEqual(
      fullBody.fits.find((fit) => fit.goals),
      {
        days: 3,
        levels: ["beginner", "intermediate", "advanced"],
        goals: ["get_stronger"],
      },
    );
  });
});
