import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, test } from "node:test";

import { HttpsError } from "firebase-functions/v2/https";

import { Exercise } from "./engine";
import {
  Entitlement,
  GenerateDeps,
  cached,
  exerciseOf,
  exercisesOf,
  generateFor,
} from "./generation";
import { Rules } from "./rules";
import { Reason } from "./store";

type Auth = Parameters<typeof generateFor>[0];

const admin = {
  uid: "admin-uid",
  token: { admin: true },
  rawToken: "",
} as unknown as Auth;
const user = { uid: "user-uid", token: {}, rawToken: "" } as unknown as Auth;

const root = join(__dirname, "../../..");
const seed: Rules = JSON.parse(
  readFileSync(join(root, "content/generator/rules.json"), "utf8"),
);

const NOW = Date.UTC(2026, 10, 22);

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
const library = [
  ex("squat"),
  ex("hinge", { movementPattern: "hinge", mainMuscles: ["hamstring"] }),
  ex("push", { movementPattern: "horizontal_push", mainMuscles: ["pec"] }),
  ex("pull", {
    movementPattern: "vertical_pull",
    mainMuscles: ["lat"],
    equipment: ["pull_up_bar"],
  }),
  ex("plank", {
    loggingType: "duration",
    movementPattern: "core_stability",
    mainMuscles: ["abdominal"],
  }),
];

const premium: Entitlement = { premium: true, expiresAtMs: NOW + 1 };

const deps = (changes: Partial<GenerateDeps> = {}): GenerateDeps => ({
  entitlement: async () => premium,
  publishedRules: async () => ({ version: 3, rules: seed }),
  exercises: async () => library,
  nowMs: () => NOW,
  ...changes,
});

const answers = (changes: { [key: string]: unknown } = {}) => ({
  goal: "build_muscle",
  level: "beginner",
  daysPerWeek: 3,
  sessionMinutes: 60,
  equipment: ["pull_up_bar"],
  focus: [],
  sensitive: [],
  equipmentStyle: "any",
  ...changes,
});

const detailsOf = (error: unknown) =>
  (error as HttpsError).details as { reason: string; field?: string };

const refused = (code: string, reason: string) => (error: unknown) =>
  (error as HttpsError).code === code && detailsOf(error).reason === reason;

describe("generateFor", () => {
  test("refuses a caller who is not signed in", async () => {
    await assert.rejects(
      generateFor(undefined, { answers: answers() }, deps()),
      (e: HttpsError) => e.code === "unauthenticated",
    );
  });

  test("gives a premium user a program from the published rules", async () => {
    const result = await generateFor(user, { answers: answers() }, deps());
    assert.equal(result.rulesVersion, 3);
    assert.equal(result.program.days.length, 3);
    assert.equal(result.program.lengthWeeks, seed.lengthWeeks.beginner);
    assert.equal(result.split, "full_body");
    assert.ok(result.template);
    assert.equal(typeof result.program.name, "string");
    assert.ok(result.weeklySets.quads > 0);
    assert.ok(result.uncovered.includes("biceps"));
    assert.ok(!("trace" in result));
    // Equipment the user does not have leaves its exercises out.
    const ids = result.program.days.flatMap((d) =>
      d.items.map((i) => i.exerciseId),
    );
    assert.ok(ids.includes("pull"));
    const without = await generateFor(
      user,
      { answers: answers({ equipment: [] }) },
      deps(),
    );
    assert.ok(
      without.program.days.every((d) =>
        d.items.every((i) => i.exerciseId !== "pull"),
      ),
    );
  });

  test("refuses a user without an active entitlement", async () => {
    for (const entitlement of [
      null,
      { premium: false, expiresAtMs: NOW + 1 },
      { premium: "true", expiresAtMs: NOW + 1 },
      { premium: true, expiresAtMs: NOW },
      { premium: true, expiresAtMs: null },
    ]) {
      await assert.rejects(
        generateFor(
          user,
          { answers: answers() },
          deps({ entitlement: async () => entitlement }),
        ),
        refused("permission-denied", Reason.notPremium),
        JSON.stringify(entitlement),
      );
    }
  });

  test("lets an admin generate without an entitlement", async () => {
    let asked = false;
    const result = await generateFor(
      admin,
      { answers: answers() },
      deps({
        entitlement: async () => {
          asked = true;
          return null;
        },
      }),
    );
    assert.equal(result.program.days.length, 3);
    assert.equal(asked, false);
  });

  test("lets an admin try own rules and ask why", async () => {
    let read = false;
    const rules = {
      ...seed,
      lengthWeeks: { ...seed.lengthWeeks, beginner: 3 },
    };
    const result = await generateFor(
      admin,
      { answers: answers(), rules, explain: true },
      deps({
        publishedRules: async () => {
          read = true;
          return null;
        },
      }),
    );
    assert.equal(read, false);
    assert.equal(result.rulesVersion, 0);
    assert.equal(result.program.lengthWeeks, 3);
    assert.equal(result.trace?.length, 3);
    await assert.rejects(
      generateFor(
        admin,
        { answers: answers(), rules: { ...seed, templates: [] } },
        deps(),
      ),
      (e) => detailsOf(e).reason === Reason.invalidInput,
    );
  });

  test("refuses rules or explain from anyone but an admin", async () => {
    for (const extra of [{ rules: seed }, { explain: true }]) {
      await assert.rejects(
        generateFor(user, { answers: answers(), ...extra }, deps()),
        refused("permission-denied", Reason.notAdmin),
      );
    }
  });

  test("refuses when no rules were published", async () => {
    await assert.rejects(
      generateFor(
        user,
        { answers: answers() },
        deps({ publishedRules: async () => null }),
      ),
      refused("failed-precondition", Reason.noRules),
    );
  });

  test("maps the engine's refusals", async () => {
    await assert.rejects(
      generateFor(
        user,
        { answers: answers() },
        deps({ exercises: async () => [] }),
      ),
      refused("failed-precondition", Reason.noExercises),
    );
    await assert.rejects(
      generateFor(
        user,
        { answers: answers({ daysPerWeek: 2, split: "body_part" }) },
        deps(),
      ),
      refused("failed-precondition", Reason.noTemplate),
    );
  });

  test("ignores bodyweight in the equipment and keeps kept items", async () => {
    const kept = [
      [
        {
          exerciseId: "plank",
          sets: 2,
          durationS: 45,
          restS: 30,
          group: "A",
          targetKg: 10,
        },
      ],
    ];
    const result = await generateFor(
      user,
      { answers: answers({ equipment: ["bodyweight", "pull_up_bar"] }), kept },
      deps(),
    );
    const plank = result.program.days[0].items.find(
      (i) => i.exerciseId === "plank",
    );
    assert.equal(plank?.sets, 2);
    assert.equal(plank?.durationS, 45);
    assert.ok(!("targetKg" in (plank ?? {})));
  });

  test("refuses each invalid field, naming it", async () => {
    const item = {
      exerciseId: "squat",
      sets: 3,
      repMin: 8,
      repMax: 12,
      restS: 90,
    };
    const cases: [string, { [key: string]: unknown }][] = [
      ["answers", {}],
      ["answers.goal", { answers: answers({ goal: "fun" }) }],
      ["answers.level", { answers: answers({ level: undefined }) }],
      ["answers.daysPerWeek", { answers: answers({ daysPerWeek: 7 }) }],
      ["answers.daysPerWeek", { answers: answers({ daysPerWeek: 2.5 }) }],
      ["answers.sessionMinutes", { answers: answers({ sessionMinutes: 61 }) }],
      ["answers.equipment", { answers: answers({ equipment: ["rocket"] }) }],
      [
        "answers.equipment",
        { answers: answers({ equipment: ["bench", "bench"] }) },
      ],
      ["answers.focus", { answers: answers({ focus: ["chest", "chest"] }) }],
      [
        "answers.focus",
        {
          answers: answers({
            focus: ["chest", "back", "arms", "legs"].slice(
              0,
              seed.focus.max + 1,
            ),
          }),
        },
      ],
      ["answers.sensitive", { answers: answers({ sensitive: "knees" }) }],
      ["answers.equipmentStyle", { answers: answers({ equipmentStyle: "" }) }],
      ["answers.split", { answers: answers({ split: "bro" }) }],
      ["seed", { answers: answers(), seed: -1 }],
      ["seed", { answers: answers(), seed: 2147483648 }],
      ["lang", { answers: answers(), lang: "e" }],
      ["kept", { answers: answers(), kept: [[], [], [], []] }],
      ["kept[0]", { answers: answers(), kept: [Array(21).fill(item)] }],
      ["kept[0][0]", { answers: answers(), kept: [["squat"]] }],
      [
        "kept[0][0].exerciseId",
        { answers: answers(), kept: [[{ ...item, exerciseId: "" }]] },
      ],
      [
        "kept[0][0].sets",
        { answers: answers(), kept: [[{ ...item, sets: 11 }]] },
      ],
      [
        "kept[0][0].restS",
        { answers: answers(), kept: [[{ ...item, restS: 601 }]] },
      ],
      [
        "kept[0][0].repMax",
        { answers: answers(), kept: [[{ ...item, repMax: 7 }]] },
      ],
      [
        "kept[0][0].repMin",
        { answers: answers(), kept: [[{ ...item, repMin: undefined }]] },
      ],
      [
        "kept[0][0].durationS",
        { answers: answers(), kept: [[{ ...item, durationS: 30 }]] },
      ],
      [
        "kept[0][0].durationS",
        {
          answers: answers(),
          kept: [[{ exerciseId: "plank", sets: 2, durationS: 4, restS: 0 }]],
        },
      ],
    ];
    for (const [field, data] of cases) {
      await assert.rejects(
        generateFor(user, data, deps()),
        (e) =>
          (e as HttpsError).code === "invalid-argument" &&
          detailsOf(e).reason === Reason.invalidInput &&
          detailsOf(e).field === field,
        field,
      );
    }
  });
});

describe("exerciseOf", () => {
  const doc = {
    status: "live",
    loggingType: "weight_reps",
    mechanic: "compound",
    level: "beginner",
    movementPattern: "squat",
    equipment: ["barbell"],
    equipmentAlternatives: [{ items: ["dumbbell"] }, { items: ["kettlebell"] }],
    mainMuscles: ["quads"],
    secondaryMuscles: ["glute"],
    family: "squat",
    popularity: 4,
    l10n: { en: { name: "Squat" } },
  };

  test("reads the alternative sets and fills the optional fields", () => {
    assert.deepEqual(exerciseOf("sq", doc), {
      id: "sq",
      loggingType: "weight_reps",
      mechanic: "compound",
      level: "beginner",
      movementPattern: "squat",
      equipment: ["barbell"],
      equipmentAlternatives: [["dumbbell"], ["kettlebell"]],
      mainMuscles: ["quads"],
      secondaryMuscles: ["glute"],
      family: "squat",
      popularity: 4,
      generatorTier: "standard",
      stressAreas: [],
    });
    const rated = exerciseOf("sq", {
      ...doc,
      equipmentAlternatives: undefined,
      generatorTier: "staple",
      stressAreas: ["knees"],
    });
    assert.ok(typeof rated !== "string");
    assert.deepEqual(rated.equipmentAlternatives, []);
    assert.equal(rated.generatorTier, "staple");
    assert.deepEqual(rated.stressAreas, ["knees"]);
  });

  test("names the first field it cannot read", () => {
    assert.equal(exerciseOf("x", { ...doc, mechanic: undefined }), "mechanic");
    assert.equal(
      exerciseOf("x", { ...doc, equipment: "barbell" }),
      "equipment",
    );
    assert.equal(
      exerciseOf("x", { ...doc, equipmentAlternatives: [["dumbbell"]] }),
      "equipmentAlternatives",
    );
    assert.equal(exerciseOf("x", { ...doc, popularity: "4" }), "popularity");
    assert.equal(exerciseOf("x", { ...doc, stressAreas: [1] }), "stressAreas");
  });

  test("exercisesOf skips unreadable documents", () => {
    const exercises = exercisesOf([
      { id: "a", data: doc },
      { id: "b", data: { ...doc, mainMuscles: null } },
      { id: "c", data: doc },
    ]);
    assert.deepEqual(exercises.map((e) => e.id), ["a", "c"]);
  });
});

describe("cached", () => {
  test("loads once per period and again once it is over", async () => {
    let now = 0;
    let loads = 0;
    const get = cached(async () => ++loads, 1000, () => now);
    assert.equal(await get(), 1);
    now = 999;
    assert.equal(await get(), 1);
    now = 1000;
    assert.equal(await get(), 2);
    now = 1500;
    assert.equal(await get(), 2);
  });

  test("shares a load in flight and does not keep a failed one", async () => {
    let loads = 0;
    const get = cached(
      async () => {
        loads++;
        if (loads === 1) throw new Error("down");
        return loads;
      },
      1000,
      () => 0,
    );
    await Promise.all([assert.rejects(get()), assert.rejects(get())]);
    assert.equal(loads, 1);
    assert.equal(await get(), 2);
  });
});
