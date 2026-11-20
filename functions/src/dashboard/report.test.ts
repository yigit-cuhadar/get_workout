import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { DayRange } from "./dates";
import {
  CohortRow,
  CrashCounts,
  DayRow,
  EventCounts,
  Funnel,
  ReportContext,
  ReportSource,
  RevenueEventRow,
  buildReport,
  buildRetention,
} from "./report";

const key = ({ from, to }: DayRange) => `${from}..${to}`;

const counts = (workouts: number): EventCounts => ({
  workoutsCompleted: workouts,
  programStarts: 3,
  customExercisesCreated: 1,
  weightsLogged: 2,
  notificationsOpened: 4,
});

const funnel = (installed: number): Funnel => ({
  installed,
  onboardingComplete: installed / 2,
  firstWorkout: installed / 4,
  paywallSeen: installed / 2,
  trialStarted: 1,
  paid: 1,
});

/** A source answering from tables keyed by range; misses are empty. */
function fakeSource(
  data: {
    days?: DayRow[];
    active?: Record<string, number>;
    counts?: Record<string, EventCounts>;
    funnels?: Record<string, Funnel>;
    crashes?: Record<string, CrashCounts> | null;
    cohorts?: CohortRow[];
    revenue?: RevenueEventRow[];
    mrr?: Record<string, number>;
  } = {},
) {
  const calls = { funnel: [] as unknown[][], cohorts: [] as unknown[][] };
  const source: ReportSource = {
    async daily({ from, to }) {
      return (data.days ?? []).filter((d) => d.day >= from && d.day <= to);
    },
    async activeUsers(range) {
      return data.active?.[key(range)] ?? 0;
    },
    async eventCounts(range) {
      return data.counts?.[key(range)] ?? counts(0);
    },
    async topProgram() {
      return { id: "ppl", starts: 3 };
    },
    async funnel(range, last, trialUids, paidUids) {
      calls.funnel.push([range, last, trialUids, paidUids]);
      return data.funnels?.[key(range)] ?? funnel(0);
    },
    async crashes(range) {
      if (data.crashes === null) return null;
      return (
        data.crashes?.[key(range)] ?? {
          crashedUsers: 0,
          handledErrors: 0,
          topIssues: [],
        }
      );
    },
    async cohorts(weeks, last) {
      calls.cohorts.push([weeks, last]);
      return data.cohorts ?? [];
    },
    async revenueEvents() {
      return data.revenue ?? [];
    },
    async mrrOn(day) {
      const mrr = data.mrr ?? {};
      const days = Object.keys(mrr)
        .filter((d) => d <= day)
        .sort();
      return days.length === 0 ? null : mrr[days[days.length - 1]];
    },
  };
  return { source, calls };
}

const context: ReportContext = {
  first: "2026-10-01",
  last: "2026-11-20",
  environments: ["PRODUCTION"],
  timeZone: "UTC",
};

const week = { from: "2026-11-14", to: "2026-11-20" };
const weekBefore = { from: "2026-11-07", to: "2026-11-13" };

const at = (day: string, hour = 12) => Date.parse(`${day}T${hour}:00:00Z`);

const purchase = (changes: Partial<RevenueEventRow> = {}): RevenueEventRow => ({
  type: "INITIAL_PURCHASE",
  periodType: "TRIAL",
  appUserId: "u1",
  environment: "PRODUCTION",
  atMillis: at("2026-11-15"),
  ...changes,
});

describe("buildReport", () => {
  test("tiles hold the range and the equally long range before", async () => {
    const { source } = fakeSource({
      days: [
        { day: "2026-11-08", active: 7, new: 2 },
        { day: "2026-11-15", active: 14, new: 4 },
        { day: "2026-11-16", active: 7, new: 1 },
      ],
      active: {
        [key(week)]: 20,
        [key(weekBefore)]: 10,
        "2026-10-22..2026-11-20": 50,
        "2026-09-22..2026-10-21": 40,
      },
      counts: { [key(week)]: counts(30), [key(weekBefore)]: counts(12) },
      funnels: { [key(week)]: funnel(8), [key(weekBefore)]: funnel(4) },
      crashes: {
        [key(week)]: {
          crashedUsers: 2,
          handledErrors: 5,
          topIssues: [{ title: "main.crash", users: 2 }],
        },
        [key(weekBefore)]: { crashedUsers: 0, handledErrors: 0, topIssues: [] },
      },
      mrr: { "2026-11-14": 70, "2026-11-21": 80 },
    });
    const report = await buildReport(source, week, context);
    assert.equal(report.status, "ok");
    assert.deepEqual(report.tiles.dailyActiveUsers, { value: 3, previous: 1 });
    // The month before starts before the first day: unknown.
    assert.deepEqual(report.tiles.monthlyActiveUsers, {
      value: 50,
      previous: null,
    });
    assert.deepEqual(report.tiles.newUsers, { value: 5, previous: 2 });
    assert.deepEqual(report.tiles.onboardingCompleted, {
      value: 0.5,
      previous: 0.5,
    });
    assert.deepEqual(report.tiles.firstWorkout, {
      value: 0.25,
      previous: 0.25,
    });
    assert.deepEqual(report.tiles.workoutsCompleted, {
      value: 30,
      previous: 12,
    });
    assert.deepEqual(report.tiles.paidConversion, {
      value: 1 / 8,
      previous: 1 / 4,
    });
    assert.deepEqual(report.tiles.mrr, { value: 80, previous: 70 });
    assert.deepEqual(report.tiles.crashFreeUsers, { value: 0.9, previous: 1 });
    assert.equal(report.growth.length, 7);
    assert.deepEqual(report.growth[0], {
      day: "2026-11-14",
      active: 0,
      new: 0,
    });
    assert.deepEqual(report.growth[1], {
      day: "2026-11-15",
      active: 14,
      new: 4,
    });
    assert.deepEqual(report.funnel, funnel(8));
    assert.deepEqual(report.usage, {
      programStarts: 3,
      workoutsPerActiveUser: 1.5,
      customExercisesCreated: 1,
      weightsLogged: 2,
      notificationsOpened: 4,
      topProgram: { id: "ppl", starts: 3 },
    });
    assert.deepEqual(report.quality, {
      crashFreeUsers: 0.9,
      handledErrors: 5,
      topIssues: [{ title: "main.crash", users: 2 }],
    });
  });

  test("before the export started, previous values are null", async () => {
    const { source } = fakeSource();
    const report = await buildReport(source, week, {
      ...context,
      first: "2026-11-10",
    });
    for (const name of [
      "dailyActiveUsers",
      "monthlyActiveUsers",
      "newUsers",
      "trialStarts",
      "crashFreeUsers",
    ] as const) {
      assert.equal(report.tiles[name].previous, null, name);
    }
  });

  test("no users gives null shares, not zero or NaN", async () => {
    const { source } = fakeSource();
    const report = await buildReport(source, week, context);
    assert.equal(report.tiles.onboardingCompleted.value, null);
    assert.equal(report.tiles.paidConversion.value, null);
    assert.equal(report.tiles.crashFreeUsers.value, null);
    assert.equal(report.usage.workoutsPerActiveUser, null);
    assert.equal(report.tiles.mrr.value, null);
  });

  test("without Crashlytics tables, quality is unknown", async () => {
    const { source } = fakeSource({
      crashes: null,
      active: { [key(week)]: 10 },
    });
    const report = await buildReport(source, week, context);
    assert.deepEqual(report.quality, {
      crashFreeUsers: null,
      handledErrors: null,
      topIssues: null,
    });
    assert.deepEqual(report.tiles.crashFreeUsers, {
      value: null,
      previous: null,
    });
  });

  test("trial starts count the range's trials in the allowed environments", async () => {
    const { source, calls } = fakeSource({
      revenue: [
        purchase(),
        purchase({ appUserId: "u2", atMillis: at("2026-11-20", 23) }),
        purchase({ appUserId: "u3", atMillis: at("2026-11-10") }),
        purchase({ appUserId: "u4", environment: "SANDBOX" }),
        purchase({ appUserId: "u5", periodType: "NORMAL" }),
        purchase({ appUserId: null, atMillis: at("2026-11-16") }),
        purchase({
          type: "RENEWAL",
          periodType: "NORMAL",
          isTrialConversion: true,
        }),
        purchase({
          type: "RENEWAL",
          periodType: "NORMAL",
          appUserId: "u6",
          isTrialConversion: false,
        }),
      ],
    });
    const report = await buildReport(source, week, context);
    assert.deepEqual(report.tiles.trialStarts, { value: 3, previous: 1 });
    assert.deepEqual(calls.funnel[0], [
      week,
      "2026-11-20",
      ["u1", "u2", "u3"],
      ["u5", "u1"],
    ]);
  });

  test("sandbox purchases count where the context allows them", async () => {
    const { source } = fakeSource({
      revenue: [purchase({ environment: "SANDBOX" })],
    });
    const report = await buildReport(source, week, {
      ...context,
      environments: ["PRODUCTION", "SANDBOX"],
    });
    assert.equal(report.tiles.trialStarts.value, 1);
  });

  test("trial days are counted in the context's zone", async () => {
    const { source } = fakeSource({
      revenue: [purchase({ atMillis: Date.parse("2026-11-20T22:30:00Z") })],
    });
    const utc = await buildReport(source, week, context);
    assert.equal(utc.tiles.trialStarts.value, 1);
    const istanbul = await buildReport(source, week, {
      ...context,
      timeZone: "Europe/Istanbul",
    });
    assert.equal(istanbul.tiles.trialStarts.value, 0);
  });
});

describe("buildRetention", () => {
  test("eight complete weeks; young cohorts have null days", async () => {
    const { source, calls } = fakeSource({
      cohorts: [
        { week: "2026-11-09", users: 10, d1: 5, d7: 2, d30: 0 },
        { week: "2026-10-12", users: 4, d1: 2, d7: 1, d30: 1 },
      ],
    });
    // A Friday: its week is not complete, the one before is the last.
    const retention = await buildRetention(source, "2026-11-20");
    assert.deepEqual(calls.cohorts[0], [
      { from: "2026-09-21", to: "2026-11-15" },
      "2026-11-20",
    ]);
    assert.equal(retention.cohorts.length, 8);
    assert.equal(retention.cohorts[0].week, "2026-09-21");
    assert.deepEqual(retention.cohorts[7], {
      week: "2026-11-09",
      users: 10,
      d1: 0.5,
      d7: null,
      d30: null,
    });
    assert.deepEqual(retention.cohorts[3], {
      week: "2026-10-12",
      users: 4,
      d1: 0.5,
      d7: 0.25,
      d30: 0.25,
    });
    assert.deepEqual(retention.cohorts[0], {
      week: "2026-09-21",
      users: 0,
      d1: null,
      d7: null,
      d30: null,
    });
  });

  test("a Sunday completes its own week", async () => {
    const { source, calls } = fakeSource();
    await buildRetention(source, "2026-11-22");
    assert.deepEqual(calls.cohorts[0][0], {
      from: "2026-09-28",
      to: "2026-11-22",
    });
  });
});
