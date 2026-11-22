// The generator's rules as the admin panel reads, checks and publishes them
// (SPEC.md, Data model, `generator/rules` and `generator/options`).
import {
  DocumentReference,
  FieldValue,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";

import { requireAdmin } from "../dashboard/run";
import { Exercise, estimateDayS, generate } from "./engine";
import { Options, Rules, optionsOf, rulesProblems } from "./rules";
import { EQUIPMENT, GOALS, LEVELS, MAX_DAYS, MIN_DAYS } from "./vocabulary";

/**
 * `details.reason` of a refusal, which the panel and the app map on (never
 * the message).
 */
export const Reason = {
  notAdmin: "not-admin",
  invalidInput: "invalid-input",
  /** The rules changed since the panel loaded them (`base`). */
  stale: "stale",
  notPremium: "not-premium",
  /** No rules were ever published. */
  noRules: "no-rules",
  noTemplate: "no-template",
  noExercises: "no-exercises",
} as const;

/** How many versions the history lists, newest first. */
export const HISTORY_LENGTH = 20;

/** Longest publish note. */
export const MAX_NOTE = 300;

/** `generator/rules` and each `generator/rules/versions/{n}`. */
export interface StoredRules {
  version: number;
  publishedAtMs: number | null;
  publishedBy: string;
  publishedByEmail: string | null;
  note?: string;
  /** The version this one brings back. */
  restores?: number;
  rules: Rules;
}

export type RulesSummary = Omit<StoredRules, "rules" | "publishedBy">;

/** What a publish writes; `publishedAt` is the server's time. */
export interface Publication {
  document: Omit<StoredRules, "publishedAtMs">;
  options: Options & { version: number };
}

/** Firestore, as far as the rules functions use it. */
export interface RulesStore {
  current(): Promise<StoredRules | null>;
  version(version: number): Promise<StoredRules | null>;
  /** The latest [limit] versions, newest first. */
  history(limit: number): Promise<RulesSummary[]>;
  /**
   * In one transaction: reads the current version (0 when none) and
   * writes what [decide] returns for it, if anything.
   */
  publish(
    decide: (current: number) => Publication | null,
  ): Promise<Publication | null>;
}

type Auth = CallableRequest["auth"];
type Json = { [key: string]: unknown };

export const isObject = (value: unknown): value is Json =>
  typeof value === "object" && value !== null && !Array.isArray(value);

export const invalid = (field: string, message: string) =>
  new HttpsError("invalid-argument", message, {
    reason: Reason.invalidInput,
    field,
  });

const isInt = (value: unknown, min: number): value is number =>
  typeof value === "number" && Number.isInteger(value) && value >= min;

/** The rules, or `invalid-input` with their problems. */
export function validRules(value: unknown): Rules {
  const problems = rulesProblems(value);
  if (problems.length > 0) {
    throw new HttpsError("invalid-argument", "The rules have problems.", {
      reason: Reason.invalidInput,
      field: "rules",
      problems,
    });
  }
  return value as Rules;
}

/** The current rules, or version `data.version`; version 0 when none. */
export async function getRules(auth: Auth, data: unknown, store: RulesStore) {
  requireAdmin(auth);
  const version = isObject(data) ? data.version : undefined;
  if (version !== undefined && version !== null && !isInt(version, 1)) {
    throw invalid("version", "version must be a version number.");
  }
  const stored =
    typeof version === "number"
      ? await store.version(version)
      : await store.current();
  if (!stored) {
    if (typeof version === "number") {
      throw new HttpsError("not-found", `There is no version ${version}.`);
    }
    return { version: 0, rules: null };
  }
  return {
    version: stored.version,
    rules: stored.rules,
    ...summaryOf(stored),
  };
}

const summaryOf = (stored: RulesSummary) => ({
  publishedAtMs: stored.publishedAtMs,
  publishedByEmail: stored.publishedByEmail,
  note: stored.note ?? null,
  restores: stored.restores ?? null,
});

/** The app's equipment presets (`EquipmentProfile`). */
export const PRESETS: { [name: string]: string[] } = {
  full_gym: EQUIPMENT.filter((code) => code !== "bodyweight"),
  home_gym: ["barbell", "plate", "dumbbell", "bench", "pull_up_bar"],
  dumbbells: ["dumbbell", "bench"],
  bodyweight: ["pull_up_bar", "dip_station"],
  bands: ["resistance_band"],
};

/** The session length the check runs at. */
const CHECK_MINUTES = 60;

/** Something the check found in a program of its grid. */
export interface Finding {
  goal: string;
  level: string;
  daysPerWeek: number;
  equipment: string;
  kind: "refused" | "uncovered" | "short";
  detail: string;
}

/**
 * The validator's problems with `data.rules`, and when there are none, what
 * the engine makes of them over every goal, level, days per week and
 * equipment preset.
 */
export async function checkRules(
  auth: Auth,
  data: unknown,
  deps: { exercises(): Promise<Exercise[]> },
) {
  requireAdmin(auth);
  const rules = isObject(data) ? data.rules : undefined;
  const problems = rulesProblems(rules);
  if (problems.length > 0) return { problems, findings: [] };
  const exercises = await deps.exercises();
  const findings: Finding[] = [];
  for (const goal of GOALS) {
    for (const level of LEVELS) {
      for (let daysPerWeek = MIN_DAYS; daysPerWeek <= MAX_DAYS; daysPerWeek++) {
        for (const [preset, equipment] of Object.entries(PRESETS)) {
          const at = { goal, level, daysPerWeek, equipment: preset };
          const result = generate({
            answers: {
              goal,
              level,
              daysPerWeek,
              sessionMinutes: CHECK_MINUTES,
              equipment,
              focus: [],
              sensitive: [],
              equipmentStyle: "any",
            },
            rules: rules as Rules,
            exercises,
            seed: 0,
          });
          if (!result.ok) {
            findings.push({ ...at, kind: "refused", detail: result.refusal });
            continue;
          }
          if (result.value.uncovered.length > 0) {
            findings.push({
              ...at,
              kind: "uncovered",
              detail: result.value.uncovered.join(", "),
            });
          }
          for (const day of result.value.days) {
            const seconds = estimateDayS(day.items);
            if (seconds < (CHECK_MINUTES * 60) / 2) {
              findings.push({
                ...at,
                kind: "short",
                detail: `${day.name}: ${Math.round(seconds / 60)} min`,
              });
            }
          }
        }
      }
    }
  }
  return { problems, findings };
}

/**
 * Publishes `data.rules` as version `base + 1`, with `generator/options`,
 * unless the current version is no longer `base` (`stale`).
 */
export async function publishRules(
  auth: Auth,
  data: unknown,
  store: RulesStore,
) {
  requireAdmin(auth);
  const input = isObject(data) ? data : {};
  const { base, note, restores } = input;
  if (!isInt(base, 0)) throw invalid("base", "base must be a version number.");
  if (
    note !== undefined &&
    (typeof note !== "string" || note.length > MAX_NOTE)
  ) {
    throw invalid("note", `note must be a text of at most ${MAX_NOTE}.`);
  }
  if (restores !== undefined && !isInt(restores, 1)) {
    throw invalid("restores", "restores must be a version number.");
  }
  const rules = validRules(input.rules);
  const uid = auth?.uid ?? "";
  const version = base + 1;
  const published = await store.publish((current) =>
    current !== base
      ? null
      : {
          document: {
            version,
            publishedBy: uid,
            publishedByEmail: auth?.token.email ?? null,
            ...(note ? { note } : {}),
            ...(restores !== undefined ? { restores } : {}),
            rules,
          },
          options: { version, ...optionsOf(rules) },
        },
  );
  if (!published) {
    throw new HttpsError(
      "failed-precondition",
      "The rules changed since this page loaded.",
      { reason: Reason.stale },
    );
  }
  logger.info("generator rules published", { version, by: uid, restores });
  return { version };
}

/** The latest [HISTORY_LENGTH] versions, newest first, without rules. */
export async function rulesHistory(auth: Auth, store: RulesStore) {
  requireAdmin(auth);
  const versions = await store.history(HISTORY_LENGTH);
  return versions.map((stored) => ({
    version: stored.version,
    ...summaryOf(stored),
  }));
}

const RULES = "generator/rules";

const toStored = (data: Json): StoredRules => ({
  version: data.version as number,
  publishedAtMs:
    data.publishedAt instanceof Timestamp ? data.publishedAt.toMillis() : null,
  publishedBy: data.publishedBy as string,
  publishedByEmail: (data.publishedByEmail as string | null) ?? null,
  ...(typeof data.note === "string" ? { note: data.note } : {}),
  ...(typeof data.restores === "number" ? { restores: data.restores } : {}),
  rules: data.rules as Rules,
});

/** [RulesStore] on [db]. */
export const firestoreRulesStore = (db: Firestore): RulesStore => {
  const rules = db.doc(RULES);
  const versions = rules.collection("versions");
  const read = async (ref: DocumentReference) => {
    const data = (await ref.get()).data();
    return data === undefined ? null : toStored(data);
  };
  return {
    current: () => read(rules),
    version: (version) => read(versions.doc(`${version}`)),
    async history(limit) {
      const snapshot = await versions
        .orderBy("version", "desc")
        .limit(limit)
        .select(
          "version",
          "publishedAt",
          "publishedByEmail",
          "note",
          "restores",
        )
        .get();
      return snapshot.docs.map((doc) => toStored(doc.data()));
    },
    publish: (decide) =>
      db.runTransaction(async (transaction) => {
        const current = (await transaction.get(rules)).data();
        const publication = decide(
          typeof current?.version === "number" ? current.version : 0,
        );
        if (!publication) return null;
        const { document, options } = publication;
        const stored = {
          ...document,
          publishedAt: FieldValue.serverTimestamp(),
        };
        transaction.set(rules, stored);
        transaction.set(versions.doc(`${document.version}`), stored);
        transaction.set(db.doc("generator/options"), options);
        return publication;
      }),
  };
};
