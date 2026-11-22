// The program generator (SPEC.md, "Program generator, rebuild"): a week of
// training from the user's answers, the rules and the live exercises. Pure:
// the same inputs give the same program.
//
// It picks the template that fits the answers, fills its slots with the
// best-scoring exercises, doses them by goal and role, keeps each day inside
// the session, and adds sets towards the weekly targets while there is room.
import { DayTemplate, Grouping, Pick, Rules, Slot, Template } from "./rules";
import {
  EquipmentStyle,
  Goal,
  LEVELS,
  Level,
  MUSCLES,
  SLOT_ROLES,
  SlotRole,
  TIMED_LOGGING_TYPES,
  UNLOADED_LOGGING_TYPES,
} from "./vocabulary";

/** What the engine reads of an exercise document. */
export interface Exercise {
  id: string;
  loggingType: string;
  mechanic: string;
  level: string;
  movementPattern: string;
  equipment: string[];
  equipmentAlternatives: string[][];
  mainMuscles: string[];
  secondaryMuscles: string[];
  family: string;
  popularity: number;
  generatorTier: string;
  stressAreas: string[];
}

/** [equipment] holds what the user owns; bodyweight is always there. */
export interface Answers {
  goal: Goal;
  level: Level;
  daysPerWeek: number;
  sessionMinutes: number;
  equipment: string[];
  focus: string[];
  /** Areas the user does not want to train. */
  skip: string[];
  sensitive: string[];
  equipmentStyle: EquipmentStyle;
  /** A split id; absent lets the rules choose. */
  split?: string;
}

/** A program item, as the app stores it. */
export interface Item {
  exerciseId: string;
  sets: number;
  repMin?: number;
  repMax?: number;
  durationS?: number;
  restS: number;
  group?: string;
}

/** Why an item is in the program, for the admin simulator. */
export interface Why {
  exerciseId: string;
  role: SlotRole;
  priority: number;
  /** `kept` by the user, `key` shared with an earlier slot, `extra` focus
   * work, or `slot`. */
  source: "kept" | "key" | "extra" | "slot";
  score?: { [part: string]: number };
  /** The next best candidates and their scores. */
  others: { exerciseId: string; score: number }[];
}

export interface Generated {
  split: string;
  template: string;
  splitName: string;
  lengthWeeks: number;
  days: { name: string; items: Item[] }[];
  /** 1 per set for each main muscle, 0.5 for each secondary one. */
  weeklySets: { [muscle: string]: number };
  /** The muscles that have a weekly target for these answers. */
  targeted: string[];
  /** Those of them that no exercise trains as a main muscle. */
  uncovered: string[];
  trace?: Why[][];
}

/** No template fits the answers, or a day is left without an exercise. */
export type Refusal = "no-template" | "no-exercises";

export type Result =
  | { ok: true; value: Generated }
  | { ok: false; refusal: Refusal };

export interface Input {
  answers: Answers;
  rules: Rules;
  exercises: Exercise[];
  seed?: number;
  /** Per day, items the user keeps: their exercise, sets and reps stay. */
  kept?: Item[][];
  lang?: string;
  explain?: boolean;
}

const SECONDS_PER_REP = 3;

/** A day never drops below this many exercises to fit the session. */
const MIN_EXERCISES = 3;

/** The most items the app stores on a day (`ProgramLimits`). */
const MAX_ITEMS = 20;

/**
 * The app's `estimateDay`, in seconds: per set its work (3 s a rep at the
 * middle of the range, or the hold) plus rest; in a group, rest follows
 * only the last item, once per round.
 */
export function estimateDayS(items: Item[]): number {
  const work = (item: Item) =>
    item.durationS ??
    Math.round(
      (((item.repMin ?? 0) + (item.repMax ?? item.repMin ?? 0)) *
        SECONDS_PER_REP) /
        2,
    );
  let seconds = 0;
  for (let start = 0; start < items.length; ) {
    // Stored items may carry a null group; it is no group, as in the app.
    const group = items[start].group ?? undefined;
    let end = start + 1;
    while (
      group !== undefined &&
      end < items.length &&
      items[end].group === group
    ) {
      end++;
    }
    const members = items.slice(start, end);
    if (members.length === 1) {
      seconds += members[0].sets * (work(members[0]) + members[0].restS);
    } else {
      for (const item of members) seconds += item.sets * work(item);
      seconds +=
        Math.max(...members.map((item) => item.sets)) *
        members[members.length - 1].restS;
    }
    start = end;
  }
  return seconds;
}

/** mulberry32: a small seeded generator of numbers in [0, 1). */
const random = (seed: number) => {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
};

const fitsPick = (pick: Pick, exercise: Exercise) =>
  (!pick.patterns || pick.patterns.includes(exercise.movementPattern)) &&
  (!pick.muscles || exercise.mainMuscles.some((m) => pick.muscles?.includes(m))) &&
  (!pick.mechanic || pick.mechanic === exercise.mechanic);

/** The template for [answers]: the fitting one with the highest priority. */
export function templateFor(
  rules: Rules,
  answers: Answers,
): Template | undefined {
  let best: Template | undefined;
  for (const template of rules.templates) {
    if (
      template.days !== answers.daysPerWeek ||
      !template.levels.includes(answers.level) ||
      (template.goals && !template.goals.includes(answers.goal)) ||
      (answers.split !== undefined && template.split !== answers.split)
    ) {
      continue;
    }
    if (!best || template.priority > best.priority) best = template;
  }
  return best;
}

interface Placed {
  role: SlotRole;
  /** The slot's place in the template; extras come after every slot. */
  order: number;
  exercise: Exercise;
  item: Item;
  maxSets: number;
  /** Kept by the user: no pass changes it. */
  fixed: boolean;
  /** The focus muscle it was added for, when it is extra focus work. */
  extraFor?: string;
  why: Why;
}

interface Day {
  template: DayTemplate;
  placed: Placed[];
  /** The orders of the slots that were tried. */
  tried: Set<number>;
}

export function generate(input: Input): Result {
  const { answers, rules } = input;
  const template = templateFor(rules, answers);
  if (!template) return { ok: false, refusal: "no-template" };

  const rand = random(input.seed ?? 0);
  const lang = input.lang ?? "en";
  const levelIndex = LEVELS.indexOf(answers.level);
  const owned = new Set([...answers.equipment, "bodyweight"]);
  const sensitive = new Set(answers.sensitive);
  const budget = answers.sessionMinutes * 60;
  const selection = rules.selection;
  const equipmentScores = selection.equipment[answers.equipmentStyle];
  const goalScores = selection.goalEquipment[answers.goal] ?? {};

  const skipped = new Set(
    answers.skip.flatMap((area) => rules.skip.areas[area] ?? []),
  );
  const library = new Map(input.exercises.map((e) => [e.id, e]));
  /** The best score among the equipment sets the user can do it with; a
   * set scores as its first, main item. */
  const equipmentScore = (exercise: Exercise): number | undefined => {
    let best: number | undefined;
    for (const set of [exercise.equipment, ...exercise.equipmentAlternatives]) {
      if (set.length === 0 || !set.every((item) => owned.has(item))) continue;
      const score = (equipmentScores[set[0]] ?? 0) + (goalScores[set[0]] ?? 0);
      if (best === undefined || score > best) best = score;
    }
    return best;
  };
  const pool = input.exercises
    .filter(
      (e) =>
        e.generatorTier !== "never" &&
        LEVELS.indexOf(e.level as Level) >= 0 &&
        LEVELS.indexOf(e.level as Level) <= levelIndex + 1 &&
        !e.stressAreas.some((area) => sensitive.has(area)) &&
        !e.mainMuscles.some((m) => skipped.has(m)) &&
        equipmentScore(e) !== undefined,
    )
    .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  /** Each exercise's place in the popularity order, 0 the best known. */
  const popularityPlace = new Map(
    [...input.exercises]
      .sort((a, b) => a.popularity - b.popularity || (a.id < b.id ? -1 : 1))
      .map((e, place) => [e.id, place]),
  );
  const lastPlace = Math.max(1, input.exercises.length - 1);

  const focusMuscles = new Set(
    answers.focus.flatMap((area) => rules.focus.areas[area] ?? []),
  );
  const target = (muscle: string) =>
    skipped.has(muscle)
      ? 0
      : (rules.volume.targets[answers.level][muscle] ?? 0) +
        (focusMuscles.has(muscle) ? rules.focus.extraSets : 0);
  const cap = (muscle: string) =>
    rules.volume.cap[answers.level] +
    (focusMuscles.has(muscle) ? rules.focus.extraSets : 0);

  const grouping: Grouping | undefined = rules.grouping.find(
    (g) =>
      (!g.goals || g.goals.includes(answers.goal)) &&
      (g.sessionMax === undefined || answers.sessionMinutes <= g.sessionMax),
  );

  // A day none of whose priority 1 slots has a candidate (a leg day for a
  // user leaving legs out) gives its place to the other days, in turn.
  const usable = template.dayList.filter((day) =>
    day.slots.some(
      (slot) =>
        slot.priority === 1 && pool.some((e) => fitsPick(slot.pick, e)),
    ),
  );
  if (usable.length === 0) return { ok: false, refusal: "no-exercises" };
  const whole = usable.length === template.dayList.length;
  const days: (Day & { name: string })[] = template.dayList.map((_, i) => {
    const day = usable[i % usable.length];
    const round = Math.floor(i / usable.length) + 1;
    const name = Object.hasOwn(day.l10n, lang) ? day.l10n[lang].name : day.l10n.en.name;
    return {
      template: day,
      name: whole || round === 1 ? name : `${name} ${round}`.slice(0, 40),
      placed: [],
      tried: new Set<number>(),
    };
  });
  /** The exercise the slots sharing a key take. */
  const keyed = new Map<string, Exercise>();

  /** A day runs primary, secondary, accessory, core; inside a role focus
   * muscles first, then the template's order. */
  const inOrder = (day: Day) =>
    [...day.placed].sort(
      (a, b) =>
        SLOT_ROLES.indexOf(a.role) - SLOT_ROLES.indexOf(b.role) ||
        Number(isFocus(b)) - Number(isFocus(a)) ||
        a.order - b.order,
    );
  const isFocus = (placed: Placed) =>
    placed.exercise.mainMuscles.some((m) => focusMuscles.has(m));

  /** The day's items as stored: in order, grouped as the rules say. */
  const layout = (day: Day): Item[] => {
    const placed = inOrder(day);
    const items = placed.map((p) => ({ ...p.item }));
    if (!grouping) return items;
    let groups = 0;
    let run: number[] = [];
    const close = () => {
      if (run.length > 1) {
        const letter = String.fromCharCode(65 + groups++);
        run.forEach((index, i) => {
          items[index].group = letter;
          items[index].restS = i === run.length - 1 ? grouping.restS : 0;
        });
      }
      run = [];
    };
    placed.forEach((p, index) => {
      if (!grouping.roles.includes(p.role)) {
        close();
        return;
      }
      const muscle = p.exercise.mainMuscles[0];
      if (
        run.length === grouping.size ||
        run.some((i) => placed[i].exercise.mainMuscles[0] === muscle)
      ) {
        close();
      }
      run.push(index);
    });
    close();
    return items;
  };
  const cost = (day: Day) =>
    estimateDayS(layout(day)) + rules.time.setupS * day.placed.length;

  const weekly = () => {
    const sets: { [muscle: string]: number } = {};
    for (const day of days) {
      for (const { exercise, item } of day.placed) {
        for (const m of exercise.mainMuscles) {
          sets[m] = (sets[m] ?? 0) + item.sets;
        }
        for (const m of exercise.secondaryMuscles) {
          sets[m] = (sets[m] ?? 0) + item.sets * 0.5;
        }
      }
    }
    return sets;
  };

  const dose = (exercise: Exercise, role: SlotRole) => {
    const d = rules.dosing[answers.goal][role];
    const [minSets, maxSets] = d.sets[answers.level];
    const item: Item = {
      exerciseId: exercise.id,
      sets: minSets,
      restS: d.restS,
    };
    if ((TIMED_LOGGING_TYPES as readonly string[]).includes(exercise.loggingType)) {
      item.durationS = d.holdS[answers.level];
    } else {
      const unloaded = (UNLOADED_LOGGING_TYPES as readonly string[]).includes(
        exercise.loggingType,
      );
      [item.repMin, item.repMax] = unloaded ? d.bodyweightReps : d.reps;
    }
    return { item, maxSets };
  };

  /**
   * The exercises fitting [pick] on [day], best first, with the scores
   * behind them. A `fallback` exercise only fills a priority 1 slot.
   */
  const choose = (pick: Pick, priority: number, day: Day) => {
    const onDay = new Set(day.placed.map((p) => p.exercise.id));
    const familiesOnDay = new Set(day.placed.map((p) => p.exercise.family));
    const inWeek = new Set<string>();
    const familiesInWeek = new Set<string>();
    for (const other of days) {
      if (other === day) continue;
      for (const p of other.placed) {
        inWeek.add(p.exercise.id);
        familiesInWeek.add(p.exercise.family);
      }
    }
    const scored: { exercise: Exercise; total: number; parts: Why["score"] }[] =
      [];
    for (const exercise of pool) {
      if (!fitsPick(pick, exercise) || onDay.has(exercise.id)) continue;
      if (priority > 1 && exercise.generatorTier === "fallback") continue;
      const parts: { [part: string]: number } = {
        tier: selection.tier[exercise.generatorTier] ?? 0,
        equipment: equipmentScore(exercise) ?? 0,
        // Cubed, so the few best known stand well clear of the rest.
        popularity:
          selection.popularity *
          (1 - (popularityPlace.get(exercise.id) ?? lastPlace) / lastPlace) ** 3,
        variety: selection.variety * rand(),
      };
      if (LEVELS.indexOf(exercise.level as Level) > levelIndex) {
        parts.aboveLevel = selection.aboveLevel;
      }
      if (inWeek.has(exercise.id)) parts.repeat = selection.repeat;
      else if (familiesInWeek.has(exercise.family)) parts.family = selection.family;
      // Two of one family on a day only when nothing else fits.
      if (familiesOnDay.has(exercise.family)) parts.sameDayFamily = -1000;
      const total = Object.values(parts).reduce((a, b) => a + b, 0);
      scored.push({ exercise, total, parts });
    }
    scored.sort((a, b) => b.total - a.total);
    return scored;
  };

  /** Fills [slot] on [day]; undefined when no exercise fits it. */
  const place = (
    day: Day,
    slot: Slot,
    order: number,
    extraFor?: string,
  ): Placed | undefined => {
    const shared = slot.key === undefined ? undefined : keyed.get(slot.key);
    let exercise: Exercise | undefined;
    let why: Omit<Why, "exerciseId" | "role" | "priority">;
    if (shared && !day.placed.some((p) => p.exercise.id === shared.id)) {
      exercise = shared;
      why = { source: "key", others: [] };
    } else {
      const scored = choose(slot.pick, slot.priority, day);
      if (scored.length === 0) return undefined;
      exercise = scored[0].exercise;
      why = {
        source: extraFor === undefined ? "slot" : "extra",
        score: scored[0].parts,
        others: scored
          .slice(1, 4)
          .map((s) => ({ exerciseId: s.exercise.id, score: s.total })),
      };
    }
    const { item, maxSets } = dose(exercise, slot.role);
    return {
      role: slot.role,
      order,
      exercise,
      item,
      maxSets,
      fixed: false,
      extraFor,
      why: {
        exerciseId: exercise.id,
        role: slot.role,
        priority: slot.priority,
        ...why,
      },
    };
  };

  // Kept items take the first slot of their day they fit, or stand as
  // extra: their exercise, sets and reps stay, whatever the session; rest
  // and grouping are the role's, as for any slot.
  days.forEach((day, d) => {
    (input.kept?.[d] ?? []).slice(0, MAX_ITEMS).forEach((kept, i) => {
      const exercise = library.get(kept.exerciseId);
      if (!exercise || day.placed.some((p) => p.exercise.id === exercise.id)) {
        return;
      }
      const order = day.template.slots.findIndex(
        (slot, index) => !day.tried.has(index) && fitsPick(slot.pick, exercise),
      );
      const slot = order < 0 ? undefined : day.template.slots[order];
      if (slot) day.tried.add(order);
      if (slot?.key !== undefined && !keyed.has(slot.key)) {
        keyed.set(slot.key, exercise);
      }
      const role = slot?.role ?? "accessory";
      const priority = slot?.priority ?? 1;
      const item: Item = {
        exerciseId: kept.exerciseId,
        sets: kept.sets,
        restS: rules.dosing[answers.goal][role].restS,
      };
      if (kept.durationS !== undefined) item.durationS = kept.durationS;
      else [item.repMin, item.repMax] = [kept.repMin, kept.repMax];
      day.placed.push({
        role,
        order: slot ? order : day.template.slots.length + i,
        exercise,
        item,
        maxSets: item.sets,
        fixed: true,
        why: { exerciseId: exercise.id, role, priority, source: "kept", others: [] },
      });
    });
  });

  /** Whether [placed] would take one of its main muscles past its cap. */
  const overCap = (placed: Placed) => {
    const sets = weekly();
    return placed.exercise.mainMuscles.some(
      (m) => (sets[m] ?? 0) + placed.item.sets > cap(m),
    );
  };

  /** Adds [placed] to [day] unless the day, the session or a muscle's cap
   * has no room for it. */
  const addIfRoom = (day: Day, placed: Placed) => {
    if (day.placed.length >= MAX_ITEMS || overCap(placed)) return false;
    day.placed.push(placed);
    if (cost(day) <= budget) return true;
    day.placed.pop();
    return false;
  };

  /** A slot for a focus muscle counts one priority higher. */
  const priorityOf = (slot: Slot) =>
    slot.pick.muscles?.some((m) => focusMuscles.has(m))
      ? Math.max(1, slot.priority - 1)
      : slot.priority;

  /** Fills the slots of [priority]; past the first, only while there is
   * room. */
  const fill = (priority: number) => {
    for (const day of days) {
      day.template.slots.forEach((template, order) => {
        const slot = { ...template, priority: priorityOf(template) };
        if (slot.priority !== priority || day.tried.has(order)) return;
        day.tried.add(order);
        const placed = place(day, slot, order);
        if (!placed) return;
        if (priority === 1) {
          if (day.placed.length >= MAX_ITEMS) return;
          day.placed.push(placed);
        } else if (!addIfRoom(day, placed)) {
          return;
        }
        // Only a slot that stays hands its exercise to the key's others.
        if (slot.key !== undefined && !keyed.has(slot.key)) {
          keyed.set(slot.key, placed.exercise);
        }
      });
    }
  };

  /**
   * Adds sets one at a time to the slot whose main muscle is furthest
   * below its target (to the targets), or lowest against it (then to the
   * cap), inside the role's most sets, the cap and the session. With
   * [only], just for those muscles.
   */
  const raise = (toCap: boolean, only?: Set<string>) => {
    const full = new Set<Placed>();
    for (;;) {
      const sets = weekly();
      let best: { day: Day; placed: Placed; need: number } | undefined;
      for (const day of days) {
        for (const placed of day.placed) {
          if (placed.fixed || full.has(placed)) continue;
          if (placed.item.sets >= placed.maxSets) continue;
          const mains = placed.exercise.mainMuscles;
          if (mains.some((m) => (sets[m] ?? 0) + 1 > cap(m))) continue;
          let need = -Infinity;
          for (const m of mains) {
            const aim = target(m);
            if (aim <= 0 || (only && !only.has(m))) continue;
            const has = sets[m] ?? 0;
            need = Math.max(need, toCap ? -has / aim : (aim - has) / aim);
          }
          if (need === -Infinity || (!toCap && need <= 0)) continue;
          const tie = best !== undefined && Math.abs(need - best.need) < 1e-9;
          if (
            !best ||
            (tie
              ? placed.item.sets < best.placed.item.sets
              : need > best.need)
          ) {
            best = { day, placed, need };
          }
        }
      }
      if (!best) return;
      best.placed.item.sets++;
      if (cost(best.day) > budget) {
        best.placed.item.sets--;
        full.add(best.placed);
      }
    }
  };

  /** Extra accessory work for focus muscles still short of their target. */
  const addFocusWork = () => {
    for (const muscle of focusMuscles) {
      const tried = new Set<Day>();
      for (;;) {
        if ((weekly()[muscle] ?? 0) >= target(muscle)) break;
        const day = days
          .filter(
            (d) =>
              !tried.has(d) &&
              d.template.extras.includes(muscle) &&
              !d.placed.some((p) => p.extraFor === muscle),
          )
          .sort((a, b) => cost(a) - cost(b))[0];
        if (!day) break;
        tried.add(day);
        const placed = place(
          day,
          { role: "accessory", pick: { muscles: [muscle] }, priority: 2 },
          day.template.slots.length + 100 + day.placed.length,
          muscle,
        );
        if (placed) addIfRoom(day, placed);
      }
    }
  };

  fill(1);
  // A session too short for its priority 1 slots loses the last ones.
  for (const day of days) {
    while (cost(day) > budget && day.placed.length > MIN_EXERCISES) {
      const loose = inOrder(day)
        .reverse()
        .filter((p) => !p.fixed);
      const last = loose.find((p) => !isFocus(p)) ?? loose[0];
      if (!last) break;
      day.placed.splice(day.placed.indexOf(last), 1);
    }
  }
  // Days repeated for a left-out area can stack a muscle past its cap:
  // the latest days give up such slots while they keep their few exercises.
  for (const day of [...days].reverse()) {
    for (const placed of inOrder(day).reverse()) {
      if (placed.fixed || day.placed.length <= MIN_EXERCISES) continue;
      const sets = weekly();
      if (placed.exercise.mainMuscles.some((m) => (sets[m] ?? 0) > cap(m))) {
        day.placed.splice(day.placed.indexOf(placed), 1);
      }
    }
  }
  // Focus muscles get their sets before the session fills up.
  raise(false, focusMuscles);
  fill(2);
  raise(false, focusMuscles);
  raise(false);
  addFocusWork();
  fill(3);
  raise(false);
  // A targeted muscle no slot trains directly (its slots sat on days that
  // gave their place away, or nothing fitted them) gets one accessory
  // exercise on the shortest day that has room.
  for (const muscle of MUSCLES) {
    if (target(muscle) <= 0) continue;
    if (days.some((d) => d.placed.some((p) => p.exercise.mainMuscles.includes(muscle)))) {
      continue;
    }
    for (const day of [...days].sort((a, b) => cost(a) - cost(b))) {
      const placed = place(
        day,
        { role: "accessory", pick: { muscles: [muscle] }, priority: 2 },
        day.template.slots.length + 200 + day.placed.length,
      );
      if (placed && addIfRoom(day, placed)) break;
    }
  }
  raise(false);
  raise(true);

  if (days.some((day) => day.placed.length === 0)) {
    return { ok: false, refusal: "no-exercises" };
  }

  const split = rules.splits.find((s) => s.id === template.split);
  const weeklySets = weekly();
  const trained = new Set(
    days.flatMap((day) => day.placed.flatMap((p) => p.exercise.mainMuscles)),
  );
  const value: Generated = {
    split: template.split,
    template: template.id,
    splitName: split
      ? (Object.hasOwn(split.l10n, lang) ? split.l10n[lang] : split.l10n.en).name
      : template.split,
    lengthWeeks: rules.lengthWeeks[answers.level],
    days: days.map((day) => ({ name: day.name, items: layout(day) })),
    weeklySets,
    targeted: MUSCLES.filter((m) => target(m) > 0),
    uncovered: MUSCLES.filter((m) => target(m) > 0 && !trained.has(m)),
  };
  if (input.explain) {
    value.trace = days.map((day) => inOrder(day).map((p) => p.why));
  }
  return { ok: true, value };
}
