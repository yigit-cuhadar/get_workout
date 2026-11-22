// The generator's rules (SPEC.md, Data model, `generator/rules`): their
// shape, the one validator the panel, the seed import and the publish
// share, and what the app is told of them (`generator/options`).
import {
  EQUIPMENT,
  EQUIPMENT_STYLES,
  EquipmentStyle,
  FOCUS_AREAS,
  GENERATOR_TIERS,
  GOALS,
  Goal,
  LEVELS,
  Level,
  MAX_DAYS,
  MECHANICS,
  MIN_DAYS,
  MOVEMENT_PATTERNS,
  MUSCLES,
  SLOT_ROLES,
  SlotRole,
} from "./vocabulary";

export type L10n<T> = { [lang: string]: T };

export interface Pick {
  patterns?: string[];
  muscles?: string[];
  mechanic?: string;
}

export interface Slot {
  role: SlotRole;
  pick: Pick;
  priority: number;
  key?: string;
}

export interface DayTemplate {
  l10n: L10n<{ name: string }>;
  slots: Slot[];
  extras: string[];
}

export interface Template {
  id: string;
  split: string;
  days: number;
  levels: Level[];
  goals?: Goal[];
  priority: number;
  dayList: DayTemplate[];
}

export interface Split {
  id: string;
  l10n: L10n<{ name: string; info: string }>;
}

export interface Dose {
  sets: Record<Level, [number, number]>;
  reps: [number, number];
  bodyweightReps: [number, number];
  holdS: Record<Level, number>;
  restS: number;
}

export interface Grouping {
  goals?: Goal[];
  sessionMax?: number;
  roles: SlotRole[];
  size: number;
  restS: number;
}

export interface Rules {
  splits: Split[];
  templates: Template[];
  dosing: Record<Goal, Record<SlotRole, Dose>>;
  grouping: Grouping[];
  volume: {
    targets: Record<Level, { [muscle: string]: number }>;
    cap: Record<Level, number>;
  };
  focus: {
    areas: { [area: string]: string[] };
    extraSets: number;
    max: number;
  };
  selection: {
    tier: { [tier: string]: number };
    equipment: Record<EquipmentStyle, { [equipment: string]: number }>;
    goalEquipment: { [goal: string]: { [equipment: string]: number } };
    aboveLevel: number;
    repeat: number;
    family: number;
    popularity: number;
    variety: number;
  };
  time: { setupS: number; sessionMinutes: number[] };
  lengthWeeks: Record<Level, number>;
}

/** What `generator/options` tells the app. */
export interface Options {
  splits: {
    id: string;
    l10n: Split["l10n"];
    fits: { days: number; levels: Level[]; goals?: Goal[] }[];
  }[];
  sessionMinutes: number[];
  maxFocusAreas: number;
}

export const optionsOf = (rules: Rules): Options => ({
  splits: rules.splits.map((split) => ({
    id: split.id,
    l10n: split.l10n,
    fits: rules.templates
      .filter((template) => template.split === split.id)
      .map(({ days, levels, goals }) => ({
        days,
        levels,
        ...(goals ? { goals } : {}),
      })),
  })),
  sessionMinutes: rules.time.sessionMinutes,
  maxFocusAreas: rules.focus.max,
});

const ID = /^[a-z][a-z0-9_]{0,39}$/;
const MAX_SLOTS = 20;
const MAX_TEXT = 200;

/** A split's name heads the program's ("<name>, 4 days", at most 60), a
 * day's name is stored as it is: the app's `ProgramLimits`. */
const MAX_NAME = 40;

type Json = { [key: string]: unknown };

const isObject = (value: unknown): value is Json =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/**
 * Why [value] cannot be the rules, each as "<path>: <problem>"; empty when
 * it can. A valid value is a [Rules].
 */
export function rulesProblems(value: unknown): string[] {
  const problems: string[] = [];
  const err = (path: string, problem: string) =>
    problems.push(`${path}: ${problem}`);

  const object = (path: string, v: unknown, keys: string[]): Json | null => {
    if (!isObject(v)) {
      err(path, "must be an object");
      return null;
    }
    for (const key of Object.keys(v)) {
      if (!keys.includes(key)) err(`${path}.${key}`, "unknown field");
    }
    return v;
  };
  const int = (path: string, v: unknown, min: number, max: number) => {
    if (typeof v !== "number" || !Number.isInteger(v) || v < min || v > max) {
      err(path, `must be a whole number from ${min} to ${max}`);
      return false;
    }
    return true;
  };
  const num = (path: string, v: unknown, min: number, max: number) => {
    if (typeof v !== "number" || !Number.isFinite(v) || v < min || v > max) {
      err(path, `must be a number from ${min} to ${max}`);
    }
  };
  const text = (path: string, v: unknown, max: number) => {
    if (typeof v !== "string" || v.trim() === "" || v.length > max) {
      err(path, `must be a text of 1 to ${max} characters`);
    }
  };
  const id = (path: string, v: unknown): v is string => {
    if (typeof v !== "string" || !ID.test(v)) {
      err(path, `must match ${ID.source}`);
      return false;
    }
    return true;
  };
  const code = (path: string, v: unknown, allowed: readonly string[]) => {
    if (typeof v !== "string" || !allowed.includes(v)) {
      err(path, `must be one of ${allowed.join(", ")}`);
    }
  };
  const codes = (
    path: string,
    v: unknown,
    allowed: readonly string[],
    min: number,
  ) => {
    if (!Array.isArray(v) || v.length < min) {
      err(path, `must be a list of at least ${min}`);
      return;
    }
    v.forEach((item, i) => code(`${path}[${i}]`, item, allowed));
    if (new Set(v).size !== v.length) err(path, "names a value twice");
  };
  const list = (path: string, v: unknown, min: number, max: number) => {
    if (!Array.isArray(v) || v.length < min || v.length > max) {
      err(path, `must be a list of ${min} to ${max}`);
      return [];
    }
    return v as unknown[];
  };
  /** A map with exactly [keys], each checked by [each]. */
  const table = (
    path: string,
    v: unknown,
    keys: readonly string[],
    each: (path: string, v: unknown) => void,
  ) => {
    const map = object(path, v, [...keys]);
    if (!map) return;
    for (const key of keys) {
      if (!(key in map)) err(`${path}.${key}`, "is missing");
      else each(`${path}.${key}`, map[key]);
    }
  };
  const range = (
    path: string,
    v: unknown,
    min: number,
    max: number,
  ) => {
    if (!Array.isArray(v) || v.length !== 2) {
      err(path, "must be [min, max]");
      return;
    }
    const low = int(`${path}[0]`, v[0], min, max);
    const high = int(`${path}[1]`, v[1], min, max);
    if (low && high && v[0] > v[1]) err(path, "min is above max");
  };
  const l10n = (path: string, v: unknown, fields: string[]) => {
    if (!isObject(v) || !("en" in v)) {
      err(path, "must have an en entry");
      return;
    }
    for (const [lang, entry] of Object.entries(v)) {
      const map = object(`${path}.${lang}`, entry, fields);
      if (!map) continue;
      for (const field of fields) {
        text(
          `${path}.${lang}.${field}`,
          map[field],
          field === "name" ? MAX_NAME : MAX_TEXT,
        );
      }
    }
  };

  const rules = object("rules", value, [
    "splits",
    "templates",
    "dosing",
    "grouping",
    "volume",
    "focus",
    "selection",
    "time",
    "lengthWeeks",
  ]);
  if (!rules) return problems;

  const splitIds = new Set<string>();
  list("splits", rules.splits, 1, 20).forEach((entry, i) => {
    const path = `splits[${i}]`;
    const split = object(path, entry, ["id", "l10n"]);
    if (!split) return;
    if (id(`${path}.id`, split.id)) {
      if (splitIds.has(split.id)) err(`${path}.id`, "is used twice");
      splitIds.add(split.id);
    }
    l10n(`${path}.l10n`, split.l10n, ["name", "info"]);
  });

  const templateIds = new Set<string>();
  list("templates", rules.templates, 1, 100).forEach((entry, i) => {
    const path = `templates[${i}]`;
    const template = object(path, entry, [
      "id",
      "split",
      "days",
      "levels",
      "goals",
      "priority",
      "dayList",
    ]);
    if (!template) return;
    if (id(`${path}.id`, template.id)) {
      if (templateIds.has(template.id)) err(`${path}.id`, "is used twice");
      templateIds.add(template.id);
    }
    if (typeof template.split !== "string" || !splitIds.has(template.split)) {
      err(`${path}.split`, "must be the id of a split");
    }
    const days = int(`${path}.days`, template.days, MIN_DAYS, MAX_DAYS);
    codes(`${path}.levels`, template.levels, LEVELS, 1);
    if (template.goals !== undefined) {
      codes(`${path}.goals`, template.goals, GOALS, 1);
    }
    int(`${path}.priority`, template.priority, 0, 1000);
    const dayList = list(`${path}.dayList`, template.dayList, 1, MAX_DAYS);
    if (days && dayList.length !== template.days) {
      err(`${path}.dayList`, `must have ${template.days} days`);
    }
    dayList.forEach((dayEntry, d) => {
      const dayPath = `${path}.dayList[${d}]`;
      const day = object(dayPath, dayEntry, ["l10n", "slots", "extras"]);
      if (!day) return;
      l10n(`${dayPath}.l10n`, day.l10n, ["name"]);
      codes(`${dayPath}.extras`, day.extras, MUSCLES, 0);
      const slots = list(`${dayPath}.slots`, day.slots, 1, MAX_SLOTS);
      slots.forEach((slotEntry, s) => {
        const slotPath = `${dayPath}.slots[${s}]`;
        const slot = object(slotPath, slotEntry, [
          "role",
          "pick",
          "priority",
          "key",
        ]);
        if (!slot) return;
        code(`${slotPath}.role`, slot.role, SLOT_ROLES);
        int(`${slotPath}.priority`, slot.priority, 1, 3);
        if (slot.key !== undefined) id(`${slotPath}.key`, slot.key);
        const pick = object(`${slotPath}.pick`, slot.pick, [
          "patterns",
          "muscles",
          "mechanic",
        ]);
        if (!pick) return;
        if (pick.patterns === undefined && pick.muscles === undefined) {
          err(`${slotPath}.pick`, "needs patterns or muscles");
        }
        if (pick.patterns !== undefined) {
          codes(`${slotPath}.pick.patterns`, pick.patterns, MOVEMENT_PATTERNS, 1);
        }
        if (pick.muscles !== undefined) {
          codes(`${slotPath}.pick.muscles`, pick.muscles, MUSCLES, 1);
        }
        if (pick.mechanic !== undefined) {
          code(`${slotPath}.pick.mechanic`, pick.mechanic, MECHANICS);
        }
      });
      if (!slots.some((slot) => isObject(slot) && slot.priority === 1)) {
        err(`${dayPath}.slots`, "needs a slot of priority 1");
      }
    });
  });

  table("dosing", rules.dosing, GOALS, (goalPath, byRole) =>
    table(goalPath, byRole, SLOT_ROLES, (path, entry) => {
      const dose = object(path, entry, [
        "sets",
        "reps",
        "bodyweightReps",
        "holdS",
        "restS",
      ]);
      if (!dose) return;
      table(`${path}.sets`, dose.sets, LEVELS, (p, v) => range(p, v, 1, 10));
      range(`${path}.reps`, dose.reps, 1, 100);
      range(`${path}.bodyweightReps`, dose.bodyweightReps, 1, 100);
      table(`${path}.holdS`, dose.holdS, LEVELS, (p, v) => int(p, v, 5, 3600));
      int(`${path}.restS`, dose.restS, 0, 600);
    }),
  );

  list("grouping", rules.grouping, 0, 20).forEach((entry, i) => {
    const path = `grouping[${i}]`;
    const grouping = object(path, entry, [
      "goals",
      "sessionMax",
      "roles",
      "size",
      "restS",
    ]);
    if (!grouping) return;
    if (grouping.goals !== undefined) {
      codes(`${path}.goals`, grouping.goals, GOALS, 1);
    }
    if (grouping.sessionMax !== undefined) {
      int(`${path}.sessionMax`, grouping.sessionMax, 1, 600);
    }
    codes(`${path}.roles`, grouping.roles, SLOT_ROLES, 1);
    int(`${path}.size`, grouping.size, 2, 4);
    int(`${path}.restS`, grouping.restS, 0, 600);
  });

  const volume = object("volume", rules.volume, ["targets", "cap"]);
  if (volume) {
    table("volume.targets", volume.targets, LEVELS, (path, entry) => {
      const targets = object(path, entry, [...MUSCLES]);
      if (!targets) return;
      for (const [muscle, sets] of Object.entries(targets)) {
        int(`${path}.${muscle}`, sets, 0, 40);
      }
    });
    table("volume.cap", volume.cap, LEVELS, (p, v) => int(p, v, 1, 40));
  }

  const focus = object("focus", rules.focus, ["areas", "extraSets", "max"]);
  if (focus) {
    table("focus.areas", focus.areas, FOCUS_AREAS, (p, v) =>
      codes(p, v, MUSCLES, 1),
    );
    int("focus.extraSets", focus.extraSets, 0, 20);
    int("focus.max", focus.max, 1, FOCUS_AREAS.length);
  }

  const selection = object("selection", rules.selection, [
    "tier",
    "equipment",
    "goalEquipment",
    "aboveLevel",
    "repeat",
    "family",
    "popularity",
    "variety",
  ]);
  if (selection) {
    table(
      "selection.tier",
      selection.tier,
      GENERATOR_TIERS.filter((tier) => tier !== "never"),
      (p, v) => num(p, v, -1000, 1000),
    );
    table(
      "selection.equipment",
      selection.equipment,
      EQUIPMENT_STYLES,
      (path, entry) =>
        table(path, entry, EQUIPMENT, (p, v) => num(p, v, -1000, 1000)),
    );
    const byGoal = object("selection.goalEquipment", selection.goalEquipment, [
      ...GOALS,
    ]);
    for (const [goal, entry] of Object.entries(byGoal ?? {})) {
      const path = `selection.goalEquipment.${goal}`;
      const scores = object(path, entry, [...EQUIPMENT]);
      for (const [equipment, score] of Object.entries(scores ?? {})) {
        num(`${path}.${equipment}`, score, -1000, 1000);
      }
    }
    for (const key of ["aboveLevel", "repeat", "family"]) {
      num(`selection.${key}`, selection[key], -1000, 0);
    }
    for (const key of ["popularity", "variety"]) {
      num(`selection.${key}`, selection[key], 0, 1000);
    }
  }

  const time = object("time", rules.time, ["setupS", "sessionMinutes"]);
  if (time) {
    int("time.setupS", time.setupS, 0, 600);
    const minutes = list("time.sessionMinutes", time.sessionMinutes, 1, 10);
    minutes.forEach((m, i) => int(`time.sessionMinutes[${i}]`, m, 10, 240));
    if (minutes.some((m, i) => i > 0 && Number(m) <= Number(minutes[i - 1]))) {
      err("time.sessionMinutes", "must rise");
    }
  }

  table("lengthWeeks", rules.lengthWeeks, LEVELS, (p, v) => int(p, v, 1, 52));

  return problems;
}
