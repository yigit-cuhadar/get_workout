// `generateProgram`'s logic: who may generate, what a request may hold, and
// where the rules and the exercises come from.
import { Firestore, Timestamp, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";

import { Answers, Exercise, Item, generate } from "./engine";
import { Rules, rulesProblems } from "./rules";
import { Reason, invalid, isObject, validRules, withoutNulls } from "./store";
import {
  EQUIPMENT,
  EQUIPMENT_STYLES,
  EquipmentStyle,
  FOCUS_AREAS,
  GOALS,
  Goal,
  LEVELS,
  Level,
  MAX_DAYS,
  MIN_DAYS,
  SENSITIVE_AREAS,
} from "./vocabulary";

/** `entitlements/{uid}` as the Firestore rules read it. */
export interface Entitlement {
  premium: unknown;
  expiresAtMs: number | null;
}

export interface GenerateDeps {
  entitlement(uid: string): Promise<Entitlement | null>;
  /**
   * `generator/rules`, null when nothing valid was published; [fresh]
   * reads past a cache.
   */
  publishedRules(
    fresh?: boolean,
  ): Promise<{ version: number; rules: Rules } | null>;
  exercises(): Promise<Exercise[]>;
  nowMs(): number;
}

/** [load]'s value, loaded again once it is [ttlMs] old or when asked
 * [fresh]; a failed load is not kept. */
export function cached<T>(
  load: () => Promise<T>,
  ttlMs: number,
  nowMs: () => number = Date.now,
): (fresh?: boolean) => Promise<T> {
  let value: { promise: Promise<T>; atMs: number } | undefined;
  return (fresh = false) => {
    const now = nowMs();
    if (fresh || !value || now - value.atMs >= ttlMs) {
      const promise = load();
      const entry = { promise, atMs: now };
      value = entry;
      promise.catch(() => {
        if (value === entry) value = undefined;
      });
    }
    return value.promise;
  };
}

export const RULES_TTL_MS = 60_000;
export const EXERCISES_TTL_MS = 5 * 60_000;

const MAX_SEED = 2147483647;
const MAX_ITEMS = 20;

export interface GenerateRequest {
  answers: Answers;
  seed: number;
  lang: string;
  kept?: Item[][];
}

type Json = { [key: string]: unknown };

const isInt = (value: unknown, min: number, max: number): value is number =>
  typeof value === "number" &&
  Number.isInteger(value) &&
  value >= min &&
  value <= max;

/** A list of distinct [allowed] codes, or `invalid-input` at [field]. */
const codes = (
  field: string,
  value: unknown,
  allowed: readonly string[],
): string[] => {
  if (
    !Array.isArray(value) ||
    value.some((v) => typeof v !== "string" || !allowed.includes(v)) ||
    new Set(value).size !== value.length
  ) {
    throw invalid(field, `${field} must be distinct codes.`);
  }
  return value as string[];
};

const code = <T extends string>(
  field: string,
  value: unknown,
  allowed: readonly T[],
): T => {
  if (typeof value !== "string" || !allowed.includes(value as T)) {
    throw invalid(field, `${field} must be one of ${allowed.join(", ")}.`);
  }
  return value as T;
};

/** A kept item with only the fields a program item has. */
function keptItem(field: string, value: unknown): Item {
  if (!isObject(value)) throw invalid(field, `${field} must be an item.`);
  const { exerciseId, sets, repMin, repMax, durationS, restS } =
    withoutNulls(value);
  const bad = (name: string) =>
    invalid(`${field}.${name}`, `${field}.${name} is invalid.`);
  if (typeof exerciseId !== "string" || exerciseId === "") {
    throw bad("exerciseId");
  }
  if (!isInt(sets, 1, 10)) throw bad("sets");
  if (!isInt(restS, 0, 600)) throw bad("restS");
  const item: Item = { exerciseId, sets, restS };
  if (durationS !== undefined) {
    if (!isInt(durationS, 5, 3600)) throw bad("durationS");
    if (repMin !== undefined || repMax !== undefined) throw bad("durationS");
    item.durationS = durationS;
  } else {
    if (!isInt(repMin, 1, 100)) throw bad("repMin");
    if (!isInt(repMax, 1, 100) || repMax < repMin) throw bad("repMax");
    item.repMin = repMin;
    item.repMax = repMax;
  }
  return item;
}

/** The request in [data], checked against [rules]; `invalid-input` with
 * the first wrong field. */
export function parseGenerate(data: unknown, rules: Rules): GenerateRequest {
  const input: Json = isObject(data) ? withoutNulls(data) : {};
  if (!isObject(input.answers)) {
    throw invalid("answers", "answers must be an object.");
  }
  const a = withoutNulls(input.answers);
  const daysPerWeek = a.daysPerWeek;
  if (!isInt(daysPerWeek, MIN_DAYS, MAX_DAYS)) {
    throw invalid("answers.daysPerWeek", "daysPerWeek is out of range.");
  }
  if (
    typeof a.sessionMinutes !== "number" ||
    !rules.time.sessionMinutes.includes(a.sessionMinutes)
  ) {
    throw invalid("answers.sessionMinutes", "sessionMinutes is not offered.");
  }
  const focus = codes("answers.focus", a.focus, FOCUS_AREAS);
  if (focus.length > rules.focus.max) {
    throw invalid("answers.focus", "Too many focus areas.");
  }
  const skip = codes("answers.skip", a.skip, FOCUS_AREAS);
  if (skip.length > rules.skip.max || skip.some((s) => focus.includes(s))) {
    throw invalid("answers.skip", "Too many areas left out, or one in focus.");
  }
  if (
    a.split !== undefined &&
    !rules.splits.some((split) => split.id === a.split)
  ) {
    throw invalid("answers.split", "split is not a split of the rules.");
  }
  const answers: Answers = {
    goal: code<Goal>("answers.goal", a.goal, GOALS),
    level: code<Level>("answers.level", a.level, LEVELS),
    daysPerWeek,
    sessionMinutes: a.sessionMinutes,
    equipment: codes("answers.equipment", a.equipment, EQUIPMENT).filter(
      (item) => item !== "bodyweight",
    ),
    focus,
    skip,
    sensitive: codes("answers.sensitive", a.sensitive, SENSITIVE_AREAS),
    equipmentStyle: code<EquipmentStyle>(
      "answers.equipmentStyle",
      a.equipmentStyle,
      EQUIPMENT_STYLES,
    ),
    ...(typeof a.split === "string" ? { split: a.split } : {}),
  };

  const seed = input.seed ?? 0;
  if (!isInt(seed, 0, MAX_SEED)) throw invalid("seed", "seed is out of range.");
  const lang = input.lang ?? "en";
  if (typeof lang !== "string" || lang.length < 2 || lang.length > 10) {
    throw invalid("lang", "lang must be a language code.");
  }
  const request: GenerateRequest = { answers, seed, lang };
  if (input.kept !== undefined) {
    const kept = input.kept;
    if (!Array.isArray(kept) || kept.length > daysPerWeek) {
      throw invalid("kept", "kept must hold at most one list per day.");
    }
    request.kept = kept.map((day: unknown, d) => {
      if (!Array.isArray(day) || day.length > MAX_ITEMS) {
        throw invalid(`kept[${d}]`, `kept[${d}] must be a list of items.`);
      }
      return day.map((item: unknown, i) => keptItem(`kept[${d}][${i}]`, item));
    });
  }
  return request;
}

/** An active entitlement, as the Firestore rules' `hasEntitlement` reads
 * it. */
const hasPremium = (entitlement: Entitlement | null, nowMs: number) =>
  entitlement !== null &&
  entitlement.premium === true &&
  entitlement.expiresAtMs !== null &&
  entitlement.expiresAtMs > nowMs;

/** An admin's unpublished rules and the request parsed against them. */
const ownRules = (input: Json) => {
  const rules = validRules(input.rules);
  return { rules, rulesVersion: 0, request: parseGenerate(input, rules) };
};

/**
 * The published rules and the request parsed against them. A split or a
 * session length they do not offer may come from options newer than the
 * cached rules, so those are read once more before refusing.
 */
async function publishedRules(input: Json, deps: GenerateDeps) {
  const parse = async (fresh: boolean) => {
    const published = await deps.publishedRules(fresh);
    if (!published) {
      throw new HttpsError("failed-precondition", "No rules are published.", {
        reason: Reason.noRules,
      });
    }
    return {
      rules: published.rules,
      rulesVersion: published.version,
      request: parseGenerate(input, published.rules),
    };
  };
  try {
    return await parse(false);
  } catch (error) {
    const field = ((error as HttpsError).details as { field?: string })
      ?.field;
    if (field !== "answers.split" && field !== "answers.sessionMinutes") {
      throw error;
    }
    return parse(true);
  }
}

/** A program for the caller's answers; see SPEC.md, `generateProgram`. */
export async function generateFor(
  auth: CallableRequest["auth"],
  data: unknown,
  deps: GenerateDeps,
) {
  if (!auth) throw new HttpsError("unauthenticated", "Sign in first.");
  const admin = auth.token.admin === true;
  const input: Json = isObject(data) ? withoutNulls(data) : {};
  if (!admin && (input.rules !== undefined || input.explain !== undefined)) {
    throw new HttpsError("permission-denied", "Admins only.", {
      reason: Reason.notAdmin,
    });
  }
  if (input.explain !== undefined && typeof input.explain !== "boolean") {
    throw invalid("explain", "explain must be true or false.");
  }
  if (!admin && !hasPremium(await deps.entitlement(auth.uid), deps.nowMs())) {
    throw new HttpsError("permission-denied", "Premium only.", {
      reason: Reason.notPremium,
    });
  }

  const { rules, rulesVersion, request } =
    input.rules !== undefined
      ? ownRules(input)
      : await publishedRules(input, deps);
  const result = generate({
    ...request,
    rules,
    exercises: await deps.exercises(),
    explain: input.explain === true,
  });
  if (!result.ok) {
    throw new HttpsError(
      "failed-precondition",
      "No program fits these answers.",
      { reason: result.refusal },
    );
  }
  const value = result.value;
  return {
    program: {
      name: value.splitName,
      lengthWeeks: value.lengthWeeks,
      days: value.days,
    },
    split: value.split,
    template: value.template,
    weeklySets: value.weeklySets,
    uncovered: value.uncovered,
    rulesVersion,
    ...(value.trace ? { trace: value.trace } : {}),
  };
}

const isStrings = (value: unknown): value is string[] =>
  Array.isArray(value) && value.every((v) => typeof v === "string");

/**
 * The engine's view of an `exercises` document; the name of the first
 * field it cannot read when there is one.
 */
export function exerciseOf(id: string, data: Json): Exercise | string {
  for (const field of [
    "loggingType",
    "mechanic",
    "level",
    "movementPattern",
    "family",
  ]) {
    if (typeof data[field] !== "string") return field;
  }
  for (const field of ["equipment", "mainMuscles", "secondaryMuscles"]) {
    if (!isStrings(data[field])) return field;
  }
  if (typeof data.popularity !== "number") return "popularity";
  const alternatives = data.equipmentAlternatives ?? [];
  if (
    !Array.isArray(alternatives) ||
    !alternatives.every((set) => isObject(set) && isStrings(set.items))
  ) {
    return "equipmentAlternatives";
  }
  const tier = data.generatorTier ?? "standard";
  if (typeof tier !== "string") return "generatorTier";
  const stressAreas = data.stressAreas ?? [];
  if (!isStrings(stressAreas)) return "stressAreas";
  return {
    id,
    loggingType: data.loggingType as string,
    mechanic: data.mechanic as string,
    level: data.level as string,
    movementPattern: data.movementPattern as string,
    equipment: data.equipment as string[],
    equipmentAlternatives: alternatives.map(
      (set: Json) => set.items as string[],
    ),
    mainMuscles: data.mainMuscles as string[],
    secondaryMuscles: data.secondaryMuscles as string[],
    family: data.family as string,
    popularity: data.popularity,
    generatorTier: tier,
    stressAreas,
  };
}

/** The readable ones of [docs]; the rest are logged in one warning. */
export function exercisesOf(docs: { id: string; data: Json }[]): Exercise[] {
  const exercises: Exercise[] = [];
  const skipped: { id: string; field: string }[] = [];
  for (const { id, data } of docs) {
    const exercise = exerciseOf(id, data);
    if (typeof exercise === "string") skipped.push({ id, field: exercise });
    else exercises.push(exercise);
  }
  if (skipped.length > 0) {
    logger.warn("generator skipped unreadable exercises", { skipped });
  }
  return exercises;
}

/** [GenerateDeps] on [db], uncached. */
export const firestoreGenerateDeps = (db: Firestore): GenerateDeps => ({
  async entitlement(uid: string): Promise<Entitlement | null> {
    const data = (await db.collection("entitlements").doc(uid).get()).data();
    if (data === undefined) return null;
    return {
      premium: data.premium,
      expiresAtMs:
        data.expiresAt instanceof Timestamp ? data.expiresAt.toMillis() : null,
    };
  },
  async publishedRules() {
    const data = (await db.doc("generator/rules").get()).data();
    if (data === undefined) return null;
    const problems = rulesProblems(data.rules);
    if (problems.length > 0) {
      logger.error("generator rules unusable", {
        version: data.version,
        problems,
      });
      return null;
    }
    return { version: data.version as number, rules: data.rules as Rules };
  },
  async exercises() {
    const snapshot = await db
      .collection("exercises")
      .where("status", "==", "live")
      .get();
    return exercisesOf(
      snapshot.docs.map((doc) => ({ id: doc.id, data: doc.data() })),
    );
  },
  nowMs: Date.now,
});

/** [deps] with the rules and the exercises cached in the instance's
 * memory. */
export const cachedGenerateDeps = (
  deps: GenerateDeps,
  nowMs: () => number = Date.now,
): GenerateDeps => ({
  ...deps,
  publishedRules: cached(() => deps.publishedRules(), RULES_TTL_MS, nowMs),
  exercises: cached(() => deps.exercises(), EXERCISES_TTL_MS, nowMs),
});

let live: GenerateDeps | undefined;

/** [GenerateDeps] on this project, cached. */
export const liveGenerateDeps = (): GenerateDeps =>
  (live ??= cachedGenerateDeps(firestoreGenerateDeps(getFirestore())));
