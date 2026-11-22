import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, mock, test } from "node:test";

import { DocumentData, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { HttpsError } from "firebase-functions/v2/https";

import { Exercise } from "./engine";
import { fakeFirestore } from "./firestore.fake";
import {
  Entitlement,
  GenerateDeps,
  cached,
  cachedGenerateDeps,
  exerciseOf,
  exercisesOf,
  firestoreGenerateDeps,
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
  skip: [],
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
      ["answers.skip", { answers: answers({ skip: ["wings"] }) }],
      [
        "answers.skip",
        {
          answers: answers({
            skip: ["chest", "back", "arms", "legs"].slice(0, seed.skip.max + 1),
          }),
        },
      ],
      [
        "answers.skip",
        { answers: answers({ focus: ["legs"], skip: ["legs"] }) },
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

/** Every exercise id of [result]'s week. */
const idsOf = (result: {
  program: { days: { items: { exerciseId: string }[] }[] };
}) =>
  new Set(
    result.program.days.flatMap((d) => d.items.map((i) => i.exerciseId)),
  );

describe("the answers reach the engine", () => {
  const run = (
    changes: { [key: string]: unknown },
    exercises: Exercise[] = library,
    more: { [key: string]: unknown } = {},
    rules: Rules = seed,
  ) =>
    generateFor(
      user,
      { answers: answers(changes), ...more },
      deps({
        exercises: async () => exercises,
        publishedRules: async () => ({ version: 3, rules }),
      }),
    );

  test("sensitive leaves out exercises that stress the area", async () => {
    const lib = library.map((e) =>
      e.id === "squat" ? { ...e, stressAreas: ["knees"] } : e,
    );
    assert.ok(idsOf(await run({}, lib)).has("squat"));
    assert.ok(!idsOf(await run({ sensitive: ["knees"] }, lib)).has("squat"));
  });

  test("skip leaves out the area's muscles", async () => {
    assert.ok(idsOf(await run({})).has("squat"));
    const skipped = await run({ skip: ["legs"] });
    assert.ok(!idsOf(skipped).has("squat"));
    assert.ok(!idsOf(skipped).has("hinge"));
  });

  test("focus gives the area more sets", async () => {
    const lib = [
      ...library,
      ex("curl", {
        mechanic: "isolation",
        movementPattern: "isolation",
        mainMuscles: ["biceps"],
      }),
    ];
    const plain = await run({}, lib);
    const focused = await run({ focus: ["arms"] }, lib);
    assert.ok(focused.weeklySets.biceps > plain.weeklySets.biceps);
  });

  test("equipmentStyle picks between equipment", async () => {
    const lib = [
      ...library,
      ex("press_machine", {
        movementPattern: "horizontal_push",
        mainMuscles: ["pec"],
        equipment: ["machine"],
      }),
      ex("press_dumbbell", {
        movementPattern: "horizontal_push",
        mainMuscles: ["pec"],
        equipment: ["dumbbell"],
      }),
    ];
    const firstDay = async (equipmentStyle: string) =>
      (
        await run(
          { equipmentStyle, equipment: ["pull_up_bar", "machine", "dumbbell"] },
          lib,
        )
      ).program.days[0].items.map((i) => i.exerciseId);
    assert.ok((await firstDay("machines")).includes("press_machine"));
    assert.ok((await firstDay("free_weights")).includes("press_dumbbell"));
  });

  test("seed varies the pick between equals", async () => {
    const lib = [...library, ex("squat_twin")];
    const picks = new Set<string>();
    for (let seed = 0; seed < 20; seed++) {
      const result = await run({}, lib, { seed });
      const first = result.program.days[0].items.map((i) => i.exerciseId);
      picks.add(first.includes("squat") ? "squat" : "squat_twin");
    }
    assert.equal(picks.size, 2);
  });

  test("lang names the program and its days", async () => {
    const rules = structuredClone(seed);
    for (const split of rules.splits) {
      split.l10n.tr = { ...split.l10n.en, name: `TR ${split.l10n.en.name}` };
    }
    for (const template of rules.templates) {
      for (const day of template.dayList) {
        day.l10n.tr = { name: `TR ${day.l10n.en.name}` };
      }
    }
    const english = await run({}, library, {}, rules);
    assert.ok(!english.program.name.startsWith("TR "));
    const turkish = await run({}, library, { lang: "tr" }, rules);
    assert.ok(turkish.program.name.startsWith("TR "));
    assert.ok(turkish.program.days.every((d) => d.name.startsWith("TR ")));
  });
});

describe("null counts as absent", () => {
  test("for a user's optional fields", async () => {
    const result = await generateFor(
      user,
      {
        answers: answers({ split: null }),
        kept: null,
        seed: null,
        lang: null,
        rules: null,
        explain: null,
      },
      deps(),
    );
    assert.equal(result.rulesVersion, 3);
    assert.equal(result.program.days.length, 3);
  });

  test("for an admin's rules and explain, and in kept items", async () => {
    const result = await generateFor(
      admin,
      {
        answers: answers(),
        rules: null,
        explain: null,
        kept: [
          [
            {
              exerciseId: "squat",
              sets: 3,
              repMin: 8,
              repMax: 12,
              durationS: null,
              restS: 90,
            },
          ],
        ],
      },
      deps(),
    );
    assert.equal(result.rulesVersion, 3);
    assert.ok(!("trace" in result));
  });
});

/** An exercise as the import stores it. */
const stored = (e: Exercise, status = "live"): DocumentData => {
  const document: DocumentData = {
    ...e,
    equipmentAlternatives: e.equipmentAlternatives.map((items) => ({ items })),
    status,
  };
  delete document.id;
  return document;
};

describe("firestoreGenerateDeps", () => {
  const HOUR = 3_600_000;
  // Its clock is the real one.
  const always = async () => ({
    premium: true,
    expiresAtMs: Number.MAX_SAFE_INTEGER,
  });
  const project = (more: { [path: string]: DocumentData } = {}) =>
    fakeFirestore({
      "generator/rules": { version: 1, rules: seed },
      ...Object.fromEntries(
        library.map((e) => [`exercises/${e.id}`, stored(e)]),
      ),
      ...more,
    });
  const generateWith = (more: { [path: string]: DocumentData }) =>
    generateFor(
      user,
      { answers: answers() },
      firestoreGenerateDeps(project(more).db),
    );

  test("takes only an unexpired timestamped entitlement", async () => {
    for (const entitlement of [
      { premium: true },
      { premium: true, expiresAt: "2999-01-01" },
      { premium: true, expiresAt: Date.now() + HOUR },
      { premium: true, expiresAt: Timestamp.fromMillis(Date.now() - HOUR) },
      { premium: false, expiresAt: Timestamp.fromMillis(Date.now() + HOUR) },
    ]) {
      await assert.rejects(
        generateWith({ "entitlements/user-uid": entitlement }),
        refused("permission-denied", Reason.notPremium),
        JSON.stringify(entitlement),
      );
    }
    const result = await generateWith({
      "entitlements/user-uid": {
        premium: true,
        expiresAt: Timestamp.fromMillis(Date.now() + HOUR),
      },
    });
    assert.equal(result.rulesVersion, 1);
  });

  test("reads only live exercises, alternative sets as lists", async () => {
    const { db } = project({
      "exercises/draft": stored(ex("draft"), "draft"),
      "exercises/retired": stored(ex("retired"), "retired"),
      "exercises/alt": stored(
        ex("alt", { equipmentAlternatives: [["dumbbell", "bench"]] }),
      ),
    });
    const exercises = await firestoreGenerateDeps(db).exercises();
    assert.deepEqual(
      exercises.map((e) => e.id).sort(),
      [...library.map((e) => e.id), "alt"].sort(),
    );
    assert.deepEqual(
      exercises.find((e) => e.id === "alt")?.equipmentAlternatives,
      [["dumbbell", "bench"]],
    );
  });

  test("takes invalid stored rules as none, logged per load", async () => {
    const errors = mock.method(logger, "error", () => {});
    try {
      let now = 0;
      const { db } = project({
        "generator/rules": { version: 4, rules: { ...seed, templates: [] } },
      });
      const live = cachedGenerateDeps(
        { ...firestoreGenerateDeps(db), entitlement: always },
        () => now,
      );
      for (const at of [0, 1000, 61_000]) {
        now = at;
        await assert.rejects(
          generateFor(user, { answers: answers() }, live),
          refused("failed-precondition", Reason.noRules),
        );
      }
      assert.equal(errors.mock.callCount(), 2);
    } finally {
      errors.mock.restore();
    }
  });

  test("a warm instance takes a split published since at once", async () => {
    let now = 0;
    let reads = 0;
    const fake = project();
    const backing = firestoreGenerateDeps(fake.db);
    const live = cachedGenerateDeps(
      {
        ...backing,
        entitlement: always,
        publishedRules: () => {
          reads++;
          return backing.publishedRules();
        },
      },
      () => now,
    );
    const generateAt = (changes: { [key: string]: unknown } = {}) =>
      generateFor(user, { answers: answers(changes) }, live);

    assert.equal((await generateAt()).rulesVersion, 1);
    const rules = structuredClone(seed);
    rules.splits.push({
      id: "new_split",
      l10n: { en: { name: "New", info: "A new split." } },
    });
    rules.templates.push({
      ...structuredClone(rules.templates[1]),
      id: "new_split_3",
      split: "new_split",
    });
    fake.set("generator/rules", { version: 2, rules });
    now = 1000;
    assert.equal((await generateAt()).rulesVersion, 1);
    const fresh = await generateAt({ split: "new_split" });
    assert.equal(fresh.rulesVersion, 2);
    assert.equal(fresh.split, "new_split");
    assert.equal((await generateAt()).rulesVersion, 2);
    assert.equal(reads, 2);
    await assert.rejects(
      generateAt({ split: "bro" }),
      (e) => detailsOf(e).field === "answers.split",
    );
    assert.equal(reads, 3);
  });
});
