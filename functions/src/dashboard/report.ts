import {
  DayRange,
  addDays,
  dayAt,
  daysOf,
  endingAt,
  lengthOf,
  mondayOf,
  previousOf,
} from "./dates";

/** Active and new users of one day. */
export interface DayRow {
  day: string;
  active: number;
  new: number;
}

/** How often the counted events fired in a range. */
export interface EventCounts {
  workoutsCompleted: number;
  programStarts: number;
  customExercisesCreated: number;
  weightsLogged: number;
  notificationsOpened: number;
}

/**
 * The users who first opened the app in a range, and how many of them
 * reached each step by the latest day.
 */
export interface Funnel {
  installed: number;
  onboardingComplete: number;
  firstWorkout: number;
  paywallSeen: number;
  trialStarted: number;
  paid: number;
}

export interface Issue {
  title: string;
  users: number;
}

/** Crashlytics in a range; users are installations, as Crashlytics counts. */
export interface CrashCounts {
  crashedUsers: number;
  handledErrors: number;
  topIssues: Issue[];
}

/** A weekly install cohort, with how many were active on day 1, 7 and 30. */
export interface CohortRow {
  week: string;
  users: number;
  d1: number;
  d7: number;
  d30: number;
}

/** `revenueEvents/{id}` as far as the reports read it. */
export interface RevenueEventRow {
  type: string;
  periodType: string | null;
  isTrialConversion?: boolean;
  appUserId: string | null;
  environment: string | null;
  atMillis: number;
}

/** Where the numbers come from: BigQuery and Firestore in production. */
export interface ReportSource {
  daily(range: DayRange): Promise<DayRow[]>;
  activeUsers(range: DayRange): Promise<number>;
  eventCounts(range: DayRange): Promise<EventCounts>;
  /** The ready-made program started most often, or null when none was. */
  topProgram(range: DayRange): Promise<{ id: string; starts: number } | null>;
  /**
   * The funnel of [range]'s new users, followed up to [last]. A user
   * started a trial or paid when their Analytics user id is among
   * [trialUids] or [paidUids].
   */
  funnel(
    range: DayRange,
    last: string,
    trialUids: string[],
    paidUids: string[],
  ): Promise<Funnel>;
  /** Null when there is no Crashlytics table. */
  crashes(range: DayRange): Promise<CrashCounts | null>;
  /** Cohorts of the weeks in [weeks], followed up to [last]. */
  cohorts(weeks: DayRange, last: string): Promise<CohortRow[]>;
  /** The INITIAL_PURCHASE and RENEWAL events received. */
  revenueEvents(): Promise<RevenueEventRow[]>;
  /** MRR of the latest revenue snapshot in the week up to [day], else null. */
  mrrOn(day: string): Promise<number | null>;
}

/** What the reports need to know about the project and its data. */
export interface ReportContext {
  /** The first and the latest day with an `events_` table. */
  first: string;
  last: string;
  /** RevenueCat environments that count (sandbox only on dev). */
  environments: string[];
  /** The zone revenue event times are turned into days in. */
  timeZone: string;
}

export interface Tile {
  value: number | null;
  /** The same over the equally long range before; null when unknown. */
  previous: number | null;
}

export interface Report {
  status: "ok";
  from: string;
  to: string;
  tiles: {
    dailyActiveUsers: Tile;
    monthlyActiveUsers: Tile;
    newUsers: Tile;
    onboardingCompleted: Tile;
    firstWorkout: Tile;
    workoutsCompleted: Tile;
    trialStarts: Tile;
    paidConversion: Tile;
    mrr: Tile;
    crashFreeUsers: Tile;
  };
  growth: DayRow[];
  funnel: Funnel;
  usage: {
    programStarts: number;
    workoutsPerActiveUser: number | null;
    customExercisesCreated: number;
    weightsLogged: number;
    notificationsOpened: number;
    topProgram: { id: string; starts: number } | null;
  };
  quality: {
    crashFreeUsers: number | null;
    handledErrors: number | null;
    topIssues: Issue[] | null;
  };
}

export interface Retention {
  status: "ok";
  cohorts: {
    week: string;
    users: number;
    d1: number | null;
    d7: number | null;
    d30: number | null;
  }[];
}

/** How many weekly cohorts Retention shows. */
export const COHORT_WEEKS = 8;

const share = (part: number, whole: number) =>
  whole === 0 ? null : part / whole;

const isTrialStart = (event: RevenueEventRow) =>
  event.type === "INITIAL_PURCHASE" && event.periodType === "TRIAL";

const isPaid = (event: RevenueEventRow) =>
  (event.type === "INITIAL_PURCHASE" && event.periodType === "NORMAL") ||
  (event.type === "RENEWAL" && event.isTrialConversion === true);

const uidsOf = (events: RevenueEventRow[]) => [
  ...new Set(events.flatMap((e) => (e.appUserId ? [e.appUserId] : []))),
];

/** Every metric of [range]: tiles against the range before, and sections. */
export async function buildReport(
  source: ReportSource,
  range: DayRange,
  context: ReportContext,
): Promise<Report> {
  const previous = previousOf(range);
  // Before the export started nothing is known, not zero.
  const known = previous.from >= context.first;
  const month = endingAt(range.to, 30);
  const monthBefore = previousOf(month);
  const events = (await source.revenueEvents()).filter(
    (e) =>
      e.environment !== null && context.environments.includes(e.environment),
  );
  const trials = events.filter(isTrialStart);
  const trialUids = uidsOf(trials);
  const paidUids = uidsOf(events.filter(isPaid));
  const trialStartsIn = ({ from, to }: DayRange) =>
    trials.filter((e) => {
      const day = dayAt(e.atMillis, context.timeZone);
      return day >= from && day <= to;
    }).length;

  /** Range-bound numbers, fetched alike for [range] and the one before. */
  const measure = async (r: DayRange) => {
    const [daily, active, counts, funnel, crashes] = await Promise.all([
      source.daily(r),
      source.activeUsers(r),
      source.eventCounts(r),
      source.funnel(r, context.last, trialUids, paidUids),
      source.crashes(r),
    ]);
    const byDay = new Map(daily.map((row) => [row.day, row]));
    const growth = daysOf(r).map(
      (day) => byDay.get(day) ?? { day, active: 0, new: 0 },
    );
    const crashFree =
      crashes === null || active === 0
        ? null
        : Math.max(0, 1 - crashes.crashedUsers / active);
    return {
      growth,
      dailyActive: growth.reduce((sum, d) => sum + d.active, 0) / lengthOf(r),
      newUsers: growth.reduce((sum, d) => sum + d.new, 0),
      active,
      counts,
      funnel,
      crashes,
      crashFree,
    };
  };

  const [now, before, mau, mauBefore, topProgram, mrr, mrrBefore] =
    await Promise.all([
      measure(range),
      known ? measure(previous) : null,
      source.activeUsers(month),
      monthBefore.from >= context.first
        ? source.activeUsers(monthBefore)
        : null,
      source.topProgram(range),
      // A snapshot is taken the morning after the day it describes.
      source.mrrOn(addDays(range.to, 1)),
      source.mrrOn(addDays(previous.to, 1)),
    ]);

  const tile = (
    of: (m: Awaited<ReturnType<typeof measure>>) => number | null,
  ): Tile => ({
    value: of(now),
    previous: before === null ? null : of(before),
  });

  return {
    status: "ok",
    from: range.from,
    to: range.to,
    tiles: {
      dailyActiveUsers: tile((m) => m.dailyActive),
      monthlyActiveUsers: { value: mau, previous: mauBefore },
      newUsers: tile((m) => m.newUsers),
      onboardingCompleted: tile((m) =>
        share(m.funnel.onboardingComplete, m.funnel.installed),
      ),
      firstWorkout: tile((m) =>
        share(m.funnel.firstWorkout, m.funnel.installed),
      ),
      workoutsCompleted: tile((m) => m.counts.workoutsCompleted),
      trialStarts: {
        value: trialStartsIn(range),
        previous: known ? trialStartsIn(previous) : null,
      },
      paidConversion: tile((m) => share(m.funnel.paid, m.funnel.installed)),
      mrr: { value: mrr, previous: mrrBefore },
      crashFreeUsers: tile((m) => m.crashFree),
    },
    growth: now.growth,
    funnel: now.funnel,
    usage: {
      programStarts: now.counts.programStarts,
      workoutsPerActiveUser: share(now.counts.workoutsCompleted, now.active),
      customExercisesCreated: now.counts.customExercisesCreated,
      weightsLogged: now.counts.weightsLogged,
      notificationsOpened: now.counts.notificationsOpened,
      topProgram,
    },
    quality: {
      crashFreeUsers: now.crashFree,
      handledErrors: now.crashes?.handledErrors ?? null,
      topIssues: now.crashes?.topIssues ?? null,
    },
  };
}

/**
 * The last [COHORT_WEEKS] complete install weeks up to [last]; a day-N
 * share is null until day N has passed for the week's last installs.
 */
export async function buildRetention(
  source: ReportSource,
  last: string,
): Promise<Retention> {
  const monday = mondayOf(last);
  const lastWeek = addDays(monday, 6) === last ? monday : addDays(monday, -7);
  const weeks = {
    from: addDays(lastWeek, -7 * (COHORT_WEEKS - 1)),
    to: addDays(lastWeek, 6),
  };
  const rows = new Map(
    (await source.cohorts(weeks, last)).map((row) => [row.week, row]),
  );
  return {
    status: "ok",
    cohorts: Array.from({ length: COHORT_WEEKS }, (_, i) => {
      const week = addDays(weeks.from, 7 * i);
      const row = rows.get(week) ?? { week, users: 0, d1: 0, d7: 0, d30: 0 };
      const at = (n: number, count: number) =>
        addDays(week, 6 + n) > last ? null : share(count, row.users);
      return {
        week,
        users: row.users,
        d1: at(1, row.d1),
        d7: at(7, row.d7),
        d30: at(30, row.d30),
      };
    }),
  };
}
