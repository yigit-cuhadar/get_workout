import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, test } from "node:test";

import {
  Answers,
  Exercise,
  Item,
  estimateDayS,
  generate,
  templateFor,
} from "./engine";
import { Rules, Slot, rulesProblems } from "./rules";
import { GOALS, LEVELS, MUSCLES } from "./vocabulary";

const root = join(__dirname, "../../..");
const readJson = (path: string) =>
  JSON.parse(readFileSync(join(root, path), "utf8"));

const seed: Rules = readJson("content/generator/rules.json");
const library: Exercise[] = readdirSync(join(root, "content/exercises"))
  .flatMap((file) => readJson(`content/exercises/${file}`) as Exercise[])
  .filter((e) => (e as unknown as { status: string }).status === "live")
  .map((e) => ({
    ...e,
    equipmentAlternatives: e.equipmentAlternatives ?? [],
    generatorTier: e.generatorTier ?? "standard",
    stressAreas: e.stressAreas ?? [],
  }));
const byId = new Map(library.map((e) => [e.id, e]));

/** The app's equipment presets (`EquipmentProfile`). */
const presets: { [name: string]: string[] } = {
  fullGym: [...new Set(library.flatMap((e) => e.equipment))],
  homeGym: ["barbell", "plate", "dumbbell", "bench", "pull_up_bar"],
  dumbbells: ["dumbbell", "bench"],
  bodyweight: ["pull_up_bar", "dip_station"],
  bands: ["resistance_band"],
};

const answers = (changes: Partial<Answers> = {}): Answers => ({
  goal: "build_muscle",
  level: "intermediate",
  daysPerWeek: 4,
  sessionMinutes: 60,
  equipment: presets.fullGym,
  focus: [],
  skip: [],
  sensitive: [],
  equipmentStyle: "any",
  ...changes,
});

const program = (changes: Partial<Answers> = {}, more = {}) => {
  const result = generate({
    answers: answers(changes),
    rules: seed,
    exercises: library,
    ...more,
  });
  assert.ok(result.ok, "a program is generated");
  return result.value;
};

const exercise = (id: string) => {
  const found = byId.get(id);
  assert.ok(found, id);
  return found;
};

describe("estimateDayS", () => {
  test("gives the app's estimate for the shared vectors", () => {
    const vectors: { items: Item[]; seconds: number }[] = readJson(
      "test/fixtures/estimate_vectors.json",
    );
    for (const { items, seconds } of vectors) {
      assert.equal(estimateDayS(items), seconds);
    }
  });
});

describe("the seed rules with the content library", () => {
  test("are valid", () => {
    assert.deepEqual(rulesProblems(seed), []);
  });

  test("give every answer the app can send a sound program", () => {
    for (const goal of GOALS) {
      for (const level of LEVELS) {
        for (let days = 2; days <= 6; days++) {
          for (const [preset, equipment] of Object.entries(presets)) {
            for (const sessionMinutes of [30, 60, 90]) {
              const a = answers({
                goal,
                level,
                daysPerWeek: days,
                sessionMinutes,
                equipment,
              });
              const label = `${goal} ${level} ${days}d ${sessionMinutes}m ${preset}`;
              const result = generate({ answers: a, rules: seed, exercises: library });
              assert.ok(result.ok, label);
              const { days: week, weeklySets } = result.value;
              assert.equal(week.length, days, label);
              const levelIndex = LEVELS.indexOf(level);
              for (const day of week) {
                assert.ok(day.items.length >= 1 && day.items.length <= 20, label);
                const ids = day.items.map((item) => item.exerciseId);
                assert.equal(new Set(ids).size, ids.length, `${label}: twice a day`);
                // Past three exercises, a day fits the session.
                if (day.items.length > 3) {
                  const cost =
                    estimateDayS(day.items) +
                    seed.time.setupS * day.items.length;
                  assert.ok(cost <= sessionMinutes * 60, `${label}: ${day.name}`);
                }
                for (const item of day.items) {
                  const e = exercise(item.exerciseId);
                  assert.notEqual(e.generatorTier, "never", label);
                  assert.ok(
                    LEVELS.indexOf(e.level as (typeof LEVELS)[number]) <=
                      levelIndex + 1,
                    `${label}: ${e.id} is two levels up`,
                  );
                  assert.ok(item.sets >= 1 && item.sets <= 10, label);
                  assert.ok(
                    item.durationS !== undefined ||
                      (item.repMin !== undefined && item.repMax !== undefined),
                    label,
                  );
                }
              }
              for (const muscle of Object.keys(weeklySets)) {
                assert.ok((MUSCLES as readonly string[]).includes(muscle), label);
              }
            }
          }
        }
      }
    }
  });

  test("the same answers and seed give the same program, another seed may differ", () => {
    assert.deepEqual(program({}, { seed: 3 }), program({}, { seed: 3 }));
    const seeds = [0, 1, 2, 3, 4].map((s) =>
      JSON.stringify(program({}, { seed: s }).days),
    );
    assert.ok(new Set(seeds).size > 1);
  });

  test("never uses an exercise stressing an area the user marked", () => {
    for (const area of ["shoulders", "elbows_wrists", "lower_back", "hips", "knees"]) {
      const value = program({ sensitive: [area] });
      for (const day of value.days) {
        for (const item of day.items) {
          assert.ok(
            !exercise(item.exerciseId).stressAreas.includes(area),
            `${area}: ${item.exerciseId}`,
          );
        }
      }
    }
  });

  test("still trains the quads of a user with sensitive knees", () => {
    const value = program({ sensitive: ["knees"] });
    assert.ok((value.weeklySets.quads ?? 0) >= 8);
  });

  test("only uses equipment the user has", () => {
    const owned = new Set([...presets.dumbbells, "bodyweight"]);
    for (const day of program({ equipment: presets.dumbbells }).days) {
      for (const item of day.items) {
        const e = exercise(item.exerciseId);
        assert.ok(
          [e.equipment, ...e.equipmentAlternatives].some((set) =>
            set.every((q) => owned.has(q)),
          ),
          e.id,
        );
      }
    }
  });

  test("an area left out is not trained, and its days go to the others", () => {
    const noLegs = program({ skip: ["legs"] });
    for (const muscle of seed.skip.areas.legs) {
      for (const day of noLegs.days) {
        for (const item of day.items) {
          assert.ok(!exercise(item.exerciseId).mainMuscles.includes(muscle));
        }
      }
    }
    assert.deepEqual(
      noLegs.days.map((day) => day.name),
      ["Upper A", "Upper B", "Upper A 2", "Upper B 2"],
    );
    assert.ok(!noLegs.uncovered.includes("quads"));
    assert.ok(!noLegs.targeted.includes("quads"));
    // Full-body days stay, without their leg work.
    const fullBody = program({ daysPerWeek: 3, skip: ["legs"] });
    assert.deepEqual(
      fullBody.days.map((day) => day.name),
      ["Full Body A", "Full Body B", "Full Body C"],
    );
    assert.ok(
      fullBody.days.every((day) =>
        day.items.every(
          (item) => !exercise(item.exerciseId).mainMuscles.includes("quads"),
        ),
      ),
    );
  });

  test("without legs the abs and glutes still get direct work, inside the caps", () => {
    const value = program({ skip: ["legs"], focus: ["chest"] });
    assert.ok(!value.uncovered.includes("abdominal"));
    assert.ok(!value.uncovered.includes("glute"));
    const cap = seed.volume.cap.intermediate;
    const direct: { [m: string]: number } = {};
    for (const day of value.days) {
      for (const item of day.items) {
        for (const m of exercise(item.exerciseId).mainMuscles) {
          direct[m] = (direct[m] ?? 0) + item.sets;
        }
      }
    }
    // Four upper days at their fewest sets would give the lats 24.
    assert.ok(direct.lat < 24 && direct.lat <= cap + 3, `lat ${direct.lat}`);
  });

  test("leaving out every area a template trains is refused", () => {
    const r: Rules = { ...seed, skip: { ...seed.skip, max: 6 } };
    assert.deepEqual(
      generate({
        answers: answers({
          skip: ["chest", "back", "shoulders", "arms", "legs", "glutes"],
        }),
        rules: r,
        exercises: library,
      }),
      { ok: false, refusal: "no-exercises" },
    );
  });

  test("a focus area gets more weekly sets", () => {
    const plain = program({ daysPerWeek: 3, sessionMinutes: 45 });
    const focused = program({
      daysPerWeek: 3,
      sessionMinutes: 45,
      focus: ["arms"],
    });
    const arms = (sets: { [m: string]: number }) =>
      (sets.biceps ?? 0) + (sets.triceps ?? 0);
    assert.ok(arms(focused.weeklySets) > arms(plain.weeklySets));
  });

  test("the equipment style moves the choice between machines and free weights", () => {
    const share = (style: Answers["equipmentStyle"]) => {
      const items = program({ equipmentStyle: style }).days.flatMap(
        (day) => day.items,
      );
      const machines = items.filter((item) =>
        ["machine", "cable", "smith_machine"].includes(
          exercise(item.exerciseId).equipment[0],
        ),
      );
      return machines.length / items.length;
    };
    assert.ok(share("machines") > share("free_weights"));
  });

  test("the strength template repeats its squat and press", () => {
    const value = program({ goal: "get_stronger", daysPerWeek: 3 });
    assert.equal(value.template, "full_body_3_strength");
    assert.deepEqual(
      value.days[0].items.slice(0, 2).map((item) => item.exerciseId),
      value.days[2].items.slice(0, 2).map((item) => item.exerciseId),
    );
  });

  test("fat loss groups accessories into circuits that rest once a round", () => {
    const value = program({ goal: "lose_fat" });
    const grouped = value.days.flatMap((day) =>
      day.items.filter((item) => item.group !== undefined),
    );
    assert.ok(grouped.length > 0);
    for (const day of value.days) {
      day.items.forEach((item, i) => {
        if (item.group === undefined) return;
        const last = day.items[i + 1]?.group !== item.group;
        assert.equal(item.restS === 0, !last);
      });
    }
  });

  test("the chosen split is used, and refused when it does not fit the days", () => {
    assert.equal(
      program({ daysPerWeek: 3, split: "push_pull_legs" }).split,
      "push_pull_legs",
    );
    assert.deepEqual(
      generate({
        answers: answers({ daysPerWeek: 2, split: "push_pull_legs" }),
        rules: seed,
        exercises: library,
      }),
      { ok: false, refusal: "no-template" },
    );
  });

  test("kept items stay on their day with their sets and reps", () => {
    const first = program();
    const kept = first.days.map((day, d) =>
      d === 0 ? [{ ...day.items[0], sets: 7 }] : [],
    );
    const second = program({}, { seed: 9, kept });
    const again = second.days[0].items.find(
      (item) => item.exerciseId === kept[0][0].exerciseId,
    );
    assert.equal(again?.sets, 7);
    assert.equal(again?.repMin, kept[0][0].repMin);
  });

  test("a kept item of a circuit gets the rest of its new place", () => {
    const circuits = program({ goal: "lose_fat" });
    const inCircuit = circuits.days[0].items.find((item) => item.restS === 0);
    assert.ok(inCircuit);
    const again = program({}, { kept: [[inCircuit]] }).days[0].items.find(
      (item) => item.exerciseId === inCircuit.exerciseId,
    );
    assert.ok(again && again.group === undefined && again.restS > 0);
  });

  test("a kept squat is still the one the strength template repeats", () => {
    const strength = { goal: "get_stronger", daysPerWeek: 3 } as const;
    const squat = program(strength).days[0].items[0];
    for (const seed of [1, 2, 3]) {
      const value = program(strength, { seed, kept: [[squat]] });
      assert.equal(value.days[2].items[0].exerciseId, squat.exerciseId);
    }
  });

  test("an unknown language falls back to English names", () => {
    for (const lang of ["tr", "constructor", "toString"]) {
      const value = program({}, { lang });
      assert.equal(value.splitName, "Upper / Lower");
      assert.equal(value.days[0].name, "Upper A");
    }
  });

  test("the order the exercises arrive in does not change the program", () => {
    const reversed = generate({
      answers: answers(),
      rules: seed,
      exercises: [...library].reverse(),
    });
    assert.deepEqual(reversed, { ok: true, value: program() });
  });

  test("explain adds why each item was picked", () => {
    const value = program({}, { explain: true });
    assert.ok(value.trace);
    value.days.forEach((day, d) => {
      assert.deepEqual(
        value.trace?.[d].map((why) => why.exerciseId),
        day.items.map((item) => item.exerciseId),
      );
    });
  });
});

describe("generate, with small rules", () => {
  const ex = (id: string, changes: Partial<Exercise> = {}): Exercise => ({
    id,
    loggingType: "weight_reps",
    mechanic: "compound",
    level: "beginner",
    movementPattern: "squat",
    equipment: ["bodyweight"],
    equipmentAlternatives: [],
    mainMuscles: ["quads"],
    secondaryMuscles: [],
    family: id,
    popularity: 1,
    generatorTier: "standard",
    stressAreas: [],
    ...changes,
  });
  /** The seed with one template of [slots] for two days a week; the seed
   * and the popularity never decide. */
  const rules = (
    slots: Slot[],
    selection: Partial<Rules["selection"]> = {},
    extras: string[] = [],
  ): Rules => ({
    ...seed,
    selection: { ...seed.selection, variety: 0, popularity: 0, ...selection },
    grouping: [],
    templates: [
      {
        id: "t",
        split: "full_body",
        days: 2,
        levels: [...LEVELS],
        priority: 1,
        dayList: [0, 1].map(() => ({
          l10n: { en: { name: "Day" } },
          slots,
          extras,
        })),
      },
    ],
  });
  const squat: Omit<Slot, "priority"> = {
    role: "primary",
    pick: { patterns: ["squat"] },
  };
  const run = (r: Rules, exercises: Exercise[], changes: Partial<Answers> = {}) => {
    const result = generate({
      answers: answers({ daysPerWeek: 2, equipment: [], ...changes }),
      rules: r,
      exercises,
    });
    assert.ok(result.ok);
    return result.value.days.map((day) => day.items);
  };

  const firstOfEachDay = (r: Rules, exercises: Exercise[]) =>
    run(r, exercises).map((items) => items[0].exerciseId);

  test("the higher tier wins, and a repeat in the week loses to a fresh one", () => {
    const r = rules([{ ...squat, priority: 1 }], { family: 0 });
    const staples = [
      ex("a", { generatorTier: "staple" }),
      ex("b", { generatorTier: "staple" }),
    ];
    assert.deepEqual(firstOfEachDay(r, [...staples, ex("c")]), ["a", "b"]);
    // With no penalty the best one comes back.
    assert.deepEqual(
      firstOfEachDay(rules([{ ...squat, priority: 1 }], { family: 0, repeat: 0 }), [
        ...staples,
        ex("c"),
      ]),
      ["a", "a"],
    );
  });

  test("a family used in the week loses to another family", () => {
    const exercises = [
      ex("a", { generatorTier: "staple", family: "f" }),
      ex("b", { generatorTier: "staple", family: "f" }),
      ex("c", { generatorTier: "staple", family: "g" }),
    ];
    const slot = [{ ...squat, priority: 1 }];
    assert.deepEqual(firstOfEachDay(rules(slot), exercises), ["a", "c"]);
    assert.deepEqual(firstOfEachDay(rules(slot, { family: 0 }), exercises), ["a", "b"]);
  });

  test("a second exercise of a family on one day only when nothing else fits", () => {
    const twice = [
      { ...squat, priority: 1 },
      { ...squat, role: "secondary" as const, priority: 1 },
    ];
    const family = [
      ex("a", { generatorTier: "staple", family: "f" }),
      ex("b", { generatorTier: "staple", family: "f" }),
    ];
    assert.deepEqual(
      run(rules(twice), [...family, ex("c", { family: "g" })])[0].map(
        (item) => item.exerciseId,
      ),
      ["a", "c"],
    );
    assert.equal(run(rules(twice), family)[0].length, 2);
  });

  test("names the targeted muscles nothing trains directly", () => {
    const result = generate({
      answers: answers({ daysPerWeek: 2, equipment: [] }),
      rules: rules([{ ...squat, priority: 1 }]),
      exercises: [ex("a")],
    });
    assert.ok(result.ok);
    assert.ok(result.value.uncovered.includes("pec"));
    assert.ok(!result.value.uncovered.includes("quads"));
    assert.ok(result.value.targeted.includes("quads"));
    assert.ok(result.value.targeted.includes("pec"));
    assert.ok(!result.value.targeted.includes("forearm"));
  });

  describe("focus", () => {
    const curl = ex("curl", {
      mechanic: "isolation",
      movementPattern: "isolation",
      mainMuscles: ["biceps"],
    });
    const calf = ex("calf", {
      mechanic: "isolation",
      movementPattern: "isolation",
      mainMuscles: ["calf"],
    });
    const accessory = (muscle: string, priority: number): Slot => ({
      role: "accessory",
      pick: { muscles: [muscle] },
      priority,
    });
    const arms = { focus: ["arms"] };

    test("a focus muscle gets extra work on the days listing it", () => {
      const r = rules([{ ...squat, priority: 1 }], {}, ["biceps"]);
      const ids = (changes: Partial<Answers>) =>
        run(r, [ex("a"), curl], changes).flat().map((item) => item.exerciseId);
      // Without the focus the biceps get the one exercise every targeted
      // muscle is owed; with it, one on each day listing them.
      const curls = (changes: Partial<Answers>) =>
        ids(changes).filter((id) => id === "curl").length;
      assert.equal(curls({}), 1);
      assert.equal(curls(arms), 2);
    });

    test("its target and cap rise by the extra sets", () => {
      const r = rules([accessory("biceps", 1)]);
      const total = (changes: Partial<Answers>) =>
        run(r, [curl], changes)
          .flat()
          .reduce((sum, item) => sum + item.sets, 0);
      // One slot a day, capped by the role's most sets either way, so the
      // cap is lowered until it binds.
      const capped: Rules = {
        ...r,
        volume: { ...r.volume, cap: { ...r.volume.cap, intermediate: 5 } },
      };
      const sets = (changes: Partial<Answers>) =>
        run(capped, [curl], changes)
          .flat()
          .reduce((sum, item) => sum + item.sets, 0);
      assert.equal(sets({}), 5);
      assert.equal(sets(arms), Math.min(5 + seed.focus.extraSets, total(arms)));
    });

    test("it comes first inside its role", () => {
      const r = rules([accessory("calf", 1), accessory("biceps", 1)]);
      const order = (changes: Partial<Answers>) =>
        run(r, [calf, curl], changes)[0].map((item) => item.exerciseId);
      assert.deepEqual(order({}), ["calf", "curl"]);
      assert.deepEqual(order(arms), ["curl", "calf"]);
    });

    test("a session too short drops other work before it", () => {
      const slots = [
        ...[1, 2, 3, 4].map(() => ({ ...squat, priority: 1 })),
        accessory("biceps", 2),
      ];
      const exercises = [...["a", "b", "c", "d", "e"].map((id) => ex(id)), curl];
      const ids = run(rules(slots), exercises, {
        ...arms,
        sessionMinutes: 10,
      })[0].map((item) => item.exerciseId);
      assert.equal(ids.length, 3);
      assert.ok(ids.includes("curl"));
    });
  });

  test("grouped slots rest once a round and never pair one main muscle", () => {
    const accessory = (muscle: string): Slot => ({
      role: "accessory",
      pick: { muscles: [muscle] },
      priority: 1,
    });
    const iso = (id: string, muscle: string) =>
      ex(id, { mechanic: "isolation", movementPattern: "isolation", mainMuscles: [muscle] });
    const r: Rules = {
      ...rules([accessory("biceps"), accessory("biceps"), accessory("calf")]),
      grouping: [{ roles: ["accessory"], size: 2, restS: 50 }],
    };
    const [day] = run(r, [iso("b1", "biceps"), iso("b2", "biceps"), iso("c1", "calf"), iso("c2", "calf")]);
    assert.deepEqual(
      day.map((item) => [item.group, item.restS]),
      [
        [undefined, seed.dosing.build_muscle.accessory.restS],
        ["A", 0],
        ["A", 50],
      ],
    );
  });

  test("a day never has more than twenty items", () => {
    const slots = Array.from({ length: 20 }, () => ({ ...squat, priority: 1 }));
    const exercises = [
      ...Array.from({ length: 30 }, (_, i) => ex(`s${String(i).padStart(2, "0")}`)),
      ex("curl", { mechanic: "isolation", movementPattern: "isolation", mainMuscles: ["biceps"] }),
    ];
    const r: Rules = {
      ...rules(slots, {}, ["biceps"]),
      volume: { ...seed.volume, cap: { ...seed.volume.cap, intermediate: 40 } },
    };
    const kept = [[{ exerciseId: "curl", sets: 2, repMin: 8, repMax: 12, restS: 60 }]];
    const result = generate({
      answers: answers({ daysPerWeek: 2, equipment: [], sessionMinutes: 240, focus: ["arms"] }),
      rules: { ...r, time: { ...r.time, sessionMinutes: [240] } },
      exercises,
      kept,
    });
    assert.ok(result.ok);
    for (const day of result.value.days) assert.ok(day.items.length <= 20);
  });

  test("a fallback exercise only fills a priority 1 slot", () => {
    const only = [ex("f", { generatorTier: "fallback" })];
    assert.equal(run(rules([{ ...squat, priority: 1 }]), only)[0].length, 1);
    const withSecond = run(
      rules([
        { ...squat, priority: 1 },
        { role: "accessory", pick: { muscles: ["calf"] }, priority: 2 },
      ]),
      [...only, ex("g", { generatorTier: "fallback", mainMuscles: ["calf"] })],
    );
    assert.deepEqual(withSecond[0].map((item) => item.exerciseId), ["f"]);
  });

  test("an exercise above the user's level is used only when nothing at it fits", () => {
    const r = rules([{ ...squat, priority: 1 }]);
    const hard = ex("hard", { level: "advanced", generatorTier: "staple" });
    assert.equal(run(r, [hard, ex("easy")])[0][0].exerciseId, "easy");
    assert.equal(run(r, [hard])[0][0].exerciseId, "hard");
    assert.deepEqual(
      generate({
        answers: answers({ daysPerWeek: 2, level: "beginner" }),
        rules: r,
        exercises: [hard],
      }),
      { ok: false, refusal: "no-exercises" },
    );
  });

  test("doses by logging type", () => {
    const r = rules([{ ...squat, priority: 1 }]);
    const dose = seed.dosing.build_muscle.primary;
    const [loaded] = run(r, [ex("a")])[0];
    assert.deepEqual([loaded.repMin, loaded.repMax], dose.reps);
    assert.equal(loaded.restS, dose.restS);
    const [unloaded] = run(r, [ex("a", { loggingType: "reps" })])[0];
    assert.deepEqual([unloaded.repMin, unloaded.repMax], dose.bodyweightReps);
    const [timed] = run(r, [ex("a", { loggingType: "duration" })])[0];
    assert.equal(timed.durationS, dose.holdS.intermediate);
    assert.equal(timed.repMin, undefined);
  });

  test("sets rise to the role's most while the target is short, never past the cap", () => {
    const r = rules([{ ...squat, priority: 1 }]);
    const [, max] = seed.dosing.build_muscle.primary.sets.intermediate;
    assert.equal(run(r, [ex("a"), ex("b")])[0][0].sets, max);
    const capped: Rules = {
      ...r,
      volume: { ...r.volume, cap: { ...r.volume.cap, intermediate: 7 } },
    };
    const total = run(capped, [ex("a"), ex("b")])
      .flat()
      .reduce((sum, item) => sum + item.sets, 0);
    assert.equal(total, 7);
  });

  test("a session too short keeps three exercises", () => {
    const slots = [1, 2, 3, 4, 5].map(() => ({ ...squat, priority: 1 }));
    const exercises = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"].map(
      (id) => ex(id),
    );
    const days = run(rules(slots), exercises, { sessionMinutes: 10 });
    assert.deepEqual(days.map((items) => items.length), [3, 3]);
  });

  test("picks the fitting template with the highest priority", () => {
    const base = rules([{ ...squat, priority: 1 }]);
    const r: Rules = {
      ...base,
      templates: [
        base.templates[0],
        { ...base.templates[0], id: "strong", goals: ["get_stronger"], priority: 9 },
        { ...base.templates[0], id: "low", priority: 0 },
      ],
    };
    assert.equal(templateFor(r, answers({ daysPerWeek: 2 }))?.id, "t");
    assert.equal(
      templateFor(r, answers({ daysPerWeek: 2, goal: "get_stronger" }))?.id,
      "strong",
    );
    assert.equal(templateFor(r, answers({ daysPerWeek: 3 })), undefined);
  });
});
