import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { beforeEach, describe, test } from "node:test";

import { HttpsError } from "firebase-functions/v2/https";

import { Exercise } from "./engine";
import { Rules, optionsOf } from "./rules";
import {
  HISTORY_LENGTH,
  MAX_NOTE,
  PRESETS,
  Publication,
  Reason,
  RulesStore,
  StoredRules,
  checkRules,
  getRules,
  publishRules,
  rulesHistory,
} from "./store";
import { GOALS, LEVELS } from "./vocabulary";

type Auth = Parameters<typeof getRules>[0];

const admin = {
  uid: "admin-uid",
  token: { admin: true, email: "admin@example.com" },
  rawToken: "",
} as unknown as Auth;
const user = {
  uid: "user-uid",
  token: { email: "user@example.com" },
  rawToken: "",
} as unknown as Auth;

const root = join(__dirname, "../../..");
const seed: Rules = JSON.parse(
  readFileSync(join(root, "content/generator/rules.json"), "utf8"),
);

/**
 * `generator/rules`, its versions and `generator/options` in memory. A
 * publish writes everything [decide] returns at once, or nothing.
 */
class FakeStore implements RulesStore {
  versions: StoredRules[] = [];
  options: Publication["options"] | null = null;

  async current() {
    return structuredClone(this.versions.at(-1) ?? null);
  }

  async version(version: number) {
    return structuredClone(
      this.versions.find((v) => v.version === version) ?? null,
    );
  }

  async history(limit: number) {
    return [...this.versions]
      .reverse()
      .slice(0, limit)
      .map((v) => ({
        version: v.version,
        publishedAtMs: v.publishedAtMs,
        publishedByEmail: v.publishedByEmail,
        note: v.note,
        restores: v.restores,
      }));
  }

  async publish(decide: (current: number) => Publication | null) {
    const publication = decide(this.versions.at(-1)?.version ?? 0);
    if (publication) {
      this.versions.push({
        ...structuredClone(publication.document),
        publishedAtMs: Date.UTC(2026, 10, publication.document.version),
      });
      this.options = structuredClone(publication.options);
    }
    return publication;
  }
}

const reasonOf = (error: unknown) =>
  ((error as HttpsError).details as { reason: string } | undefined)?.reason;

const refusesNonAdmins = async (call: (auth: Auth) => Promise<unknown>) => {
  await assert.rejects(call(user), (e) => reasonOf(e) === Reason.notAdmin);
  await assert.rejects(
    call(undefined),
    (e: HttpsError) => e.code === "unauthenticated",
  );
};

describe("getRules", () => {
  let store: FakeStore;

  beforeEach(async () => {
    store = new FakeStore();
  });

  test("is for admins only", async () => {
    await refusesNonAdmins((auth) => getRules(auth, {}, store));
  });

  test("gives version 0 when nothing was published", async () => {
    assert.deepEqual(await getRules(admin, {}, store), {
      version: 0,
      rules: null,
    });
  });

  test("gives the current rules or a version of them", async () => {
    await publishRules(admin, { base: 0, rules: seed, note: "Seed" }, store);
    const changed = {
      ...seed,
      lengthWeeks: { ...seed.lengthWeeks, beginner: 4 },
    };
    await publishRules(admin, { base: 1, rules: changed, restores: 1 }, store);

    assert.deepEqual(await getRules(admin, null, store), {
      version: 2,
      rules: changed,
      publishedAtMs: Date.UTC(2026, 10, 2),
      publishedByEmail: "admin@example.com",
      note: null,
      restores: 1,
    });
    const first = await getRules(admin, { version: 1 }, store);
    assert.equal(first.version, 1);
    assert.deepEqual(first.rules, seed);
    assert.equal(first.note, "Seed");
    assert.equal(first.restores, null);
  });

  test("refuses an unknown or malformed version", async () => {
    await assert.rejects(
      getRules(admin, { version: 7 }, store),
      (e: HttpsError) => e.code === "not-found",
    );
    await assert.rejects(
      getRules(admin, { version: 0 }, store),
      (e) => reasonOf(e) === Reason.invalidInput,
    );
  });
});

describe("publishRules", () => {
  let store: FakeStore;

  beforeEach(() => {
    store = new FakeStore();
  });

  test("is for admins only, and writes nothing then", async () => {
    await refusesNonAdmins((auth) =>
      publishRules(auth, { base: 0, rules: seed }, store),
    );
    assert.equal(store.versions.length, 0);
  });

  test("writes rules, version copy and options as base + 1", async () => {
    assert.deepEqual(
      await publishRules(admin, { base: 0, rules: seed, note: "First" }, store),
      { version: 1 },
    );
    assert.deepEqual(store.versions, [
      {
        version: 1,
        publishedAtMs: Date.UTC(2026, 10, 1),
        publishedBy: "admin-uid",
        publishedByEmail: "admin@example.com",
        note: "First",
        rules: seed,
      },
    ]);
    assert.deepEqual(store.options, { version: 1, ...optionsOf(seed) });
    assert.deepEqual(
      await publishRules(admin, { base: 1, rules: seed }, store),
      { version: 2 },
    );
    assert.equal(store.options?.version, 2);
  });

  test("an admin without an email is stored as null", async () => {
    const noEmail = {
      uid: "admin-2",
      token: { admin: true },
      rawToken: "",
    } as unknown as Auth;
    await publishRules(noEmail, { base: 0, rules: seed }, store);
    assert.equal(store.versions[0].publishedByEmail, null);
  });

  test("refuses a stale base and writes nothing", async () => {
    await publishRules(admin, { base: 0, rules: seed }, store);
    for (const base of [0, 2]) {
      await assert.rejects(
        publishRules(admin, { base, rules: seed }, store),
        (e: HttpsError) =>
          e.code === "failed-precondition" && reasonOf(e) === Reason.stale,
      );
    }
    assert.equal(store.versions.length, 1);
    assert.equal(store.options?.version, 1);
  });

  test("refuses invalid rules with their problems", async () => {
    const broken = { ...seed, templates: [] };
    await assert.rejects(
      publishRules(admin, { base: 0, rules: broken }, store),
      (e: HttpsError) => {
        const details = e.details as { reason: string; problems: string[] };
        return (
          e.code === "invalid-argument" &&
          details.reason === Reason.invalidInput &&
          details.problems.some((p) => p.startsWith("templates"))
        );
      },
    );
    assert.equal(store.versions.length, 0);
  });

  test("refuses a wrong base, note or restores", async () => {
    for (const data of [
      { rules: seed },
      { base: -1, rules: seed },
      { base: 1.5, rules: seed },
      { base: 0, rules: seed, note: "x".repeat(MAX_NOTE + 1) },
      { base: 0, rules: seed, note: 3 },
      { base: 0, rules: seed, restores: 0 },
    ]) {
      await assert.rejects(
        publishRules(admin, data, store),
        (e) => reasonOf(e) === Reason.invalidInput,
        JSON.stringify({ ...data, rules: undefined }),
      );
    }
    assert.equal(store.versions.length, 0);
  });
});

describe("rulesHistory", () => {
  test("is for admins only", async () => {
    await refusesNonAdmins((auth) => rulesHistory(auth, new FakeStore()));
  });

  test("lists the latest versions newest first, without rules", async () => {
    const store = new FakeStore();
    for (let base = 0; base < HISTORY_LENGTH + 3; base++) {
      const note = `v${base + 1}`;
      await publishRules(admin, { base, rules: seed, note }, store);
    }
    const history = await rulesHistory(admin, store);
    assert.equal(history.length, HISTORY_LENGTH);
    assert.deepEqual(
      history.map((v) => v.version),
      Array.from({ length: HISTORY_LENGTH }, (_, i) => HISTORY_LENGTH + 3 - i),
    );
    assert.deepEqual(history[0], {
      version: HISTORY_LENGTH + 3,
      publishedAtMs: Date.UTC(2026, 10, HISTORY_LENGTH + 3),
      publishedByEmail: "admin@example.com",
      note: `v${HISTORY_LENGTH + 3}`,
      restores: null,
    });
  });
});

describe("checkRules", () => {
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
  const exercises = [
    ex("squat"),
    ex("hinge", { movementPattern: "hinge", mainMuscles: ["hamstring"] }),
    ex("push", { movementPattern: "horizontal_push", mainMuscles: ["pec"] }),
    ex("pull", { movementPattern: "vertical_pull", mainMuscles: ["lat"] }),
  ];
  const deps = { exercises: async () => exercises };

  test("is for admins only", async () => {
    await refusesNonAdmins((auth) => checkRules(auth, { rules: seed }, deps));
  });

  test("gives the problems and no findings for invalid rules", async () => {
    const result = await checkRules(
      admin,
      { rules: { ...seed, lengthWeeks: {} } },
      deps,
    );
    assert.ok(result.problems.length > 0);
    assert.deepEqual(result.findings, []);
  });

  test("runs every goal, level, days and preset of the grid", async () => {
    const { problems, findings } = await checkRules(
      admin,
      { rules: seed },
      deps,
    );
    assert.deepEqual(problems, []);
    // Four exercises leave muscles without direct work in every program.
    const uncovered = findings.filter((f) => f.kind === "uncovered");
    assert.equal(
      uncovered.length,
      GOALS.length * LEVELS.length * 5 * Object.keys(PRESETS).length,
    );
    assert.ok(findings.every((f) => f.kind !== "refused"));
    const short = findings.find((f) => f.kind === "short");
    assert.match(short?.detail ?? "", /^.+: \d+ min$/);
  });

  test("names the answers the rules refuse", async () => {
    const rules = {
      ...seed,
      templates: seed.templates.filter((t) => t.days !== 2),
    };
    const { problems, findings } = await checkRules(admin, { rules }, deps);
    assert.deepEqual(problems, []);
    const refused = findings.filter((f) => f.kind === "refused");
    assert.equal(
      refused.length,
      GOALS.length * LEVELS.length * Object.keys(PRESETS).length,
    );
    assert.ok(
      refused.every((f) => f.daysPerWeek === 2 && f.detail === "no-template"),
    );
    assert.ok(
      refused.some(
        (f) =>
          f.goal === "lose_fat" &&
          f.level === "advanced" &&
          f.equipment === "bands",
      ),
    );
  });
});
