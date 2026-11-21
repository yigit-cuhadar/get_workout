import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { HttpsError } from "firebase-functions/v2/https";

import { parseRange, rangeReportOf } from "./dashboard_range";
import { ReportSource } from "./report";
import { DashboardDeps, Reason, refreshDashboard } from "./run";

const emptySource: ReportSource = {
  daily: async () => [],
  activeUsers: async () => 0,
  eventCounts: async () => ({
    workoutsCompleted: 0,
    programStarts: 0,
    customExercisesCreated: 0,
    weightsLogged: 0,
    notificationsOpened: 0,
  }),
  topProgram: async () => null,
  funnel: async () => ({
    installed: 0,
    onboardingComplete: 0,
    firstWorkout: 0,
    paywallSeen: 0,
    trialStarted: 0,
    paid: 0,
  }),
  crashes: async () => null,
  cohorts: async () => [],
  revenueEvents: async () => [],
  mrrOn: async () => null,
};

const snapshot = {
  mrr: 10,
  revenue28d: 20,
  activeSubscriptions: 2,
  activeTrials: 1,
  newCustomers28d: 5,
  currency: "USD",
};

// 2026-11-21 06:00 UTC, 09:00 in Istanbul.
const now = Date.UTC(2026, 10, 21, 6);

function fakeDeps(changes: Partial<DashboardDeps> = {}) {
  const written = new Map<string, object>();
  const deps: DashboardDeps = {
    eventDays: async () => ({ first: "2026-10-01", last: "2026-11-20" }),
    source: emptySource,
    context: { environments: ["PRODUCTION"], timeZone: "Europe/Istanbul" },
    fetchRevenue: async () => snapshot,
    async write(path, data) {
      written.set(path, data);
    },
    nowMillis: now,
    ...changes,
  };
  return { deps, written };
}

describe("refreshDashboard", () => {
  test("writes revenue, the presets, retention and an ok status", async () => {
    const { deps, written } = fakeDeps();
    const status = await refreshDashboard(deps);
    assert.deepEqual(status, {
      lastDay: "2026-11-20",
      updatedAtMillis: now,
      state: "ok",
    });
    assert.deepEqual(
      [...written.keys()],
      [
        "dashboardRevenue/2026-11-21",
        "dashboard/revenue",
        "dashboard/p7",
        "dashboard/p30",
        "dashboard/p90",
        "dashboard/retention",
        "dashboard/status",
      ],
    );
    assert.deepEqual(written.get("dashboard/revenue"), {
      ...snapshot,
      day: "2026-11-21",
      takenAtMillis: now,
    });
    const p30 = written.get("dashboard/p30") as { from: string; to: string };
    assert.equal(p30.from, "2026-10-22");
    assert.equal(p30.to, "2026-11-20");
  });

  test("before the first export: revenue only, status no-data", async () => {
    const { deps, written } = fakeDeps({ eventDays: async () => null });
    const status = await refreshDashboard(deps);
    assert.equal(status.state, "no-data");
    assert.equal(status.lastDay, null);
    assert.deepEqual(
      [...written.keys()],
      ["dashboardRevenue/2026-11-21", "dashboard/revenue", "dashboard/status"],
    );
  });

  test("without a RevenueCat overview no revenue is written", async () => {
    const { deps, written } = fakeDeps({ fetchRevenue: null });
    const status = await refreshDashboard(deps);
    assert.equal(status.state, "ok");
    assert.ok(!written.has("dashboard/revenue"));
    assert.ok(
      ![...written.keys()].some((k) => k.startsWith("dashboardRevenue/")),
    );
  });

  test("a failing part is named and the others are still written", async () => {
    const { deps, written } = fakeDeps({
      fetchRevenue: async () => {
        throw new Error("RevenueCat answered 401.");
      },
      source: {
        ...emptySource,
        cohorts: async () => {
          throw new Error("quota");
        },
      },
    });
    const status = await refreshDashboard(deps);
    assert.equal(status.state, "error");
    assert.equal(
      status.message,
      "revenue: RevenueCat answered 401.\nretention: quota",
    );
    assert.ok(written.has("dashboard/p7"));
    assert.ok(!written.has("dashboard/revenue"));
    assert.ok(!written.has("dashboard/retention"));
    assert.deepEqual(written.get("dashboard/status"), status);
  });

  test("BigQuery failing to list the tables is an error, not no-data", async () => {
    const { deps } = fakeDeps({
      eventDays: async () => {
        throw new Error("denied");
      },
    });
    const status = await refreshDashboard(deps);
    assert.equal(status.state, "error");
    assert.equal(status.message, "analytics: denied");
  });
});

type Auth = Parameters<typeof rangeReportOf>[0];

const admin = { uid: "a", token: { admin: true } } as unknown as Auth;

const reason = (error: unknown) =>
  (error as HttpsError).details as { reason: string; field?: string };

describe("parseRange", () => {
  test("takes an ordered range of real days up to 366 days", () => {
    assert.deepEqual(parseRange({ from: "2026-11-01", to: "2026-11-01" }), {
      from: "2026-11-01",
      to: "2026-11-01",
    });
    assert.deepEqual(parseRange({ from: "2025-11-21", to: "2026-11-21" }), {
      from: "2025-11-21",
      to: "2026-11-21",
    });
  });

  test("refuses anything else, naming the field", () => {
    const cases: [unknown, string][] = [
      [null, "from"],
      [{ to: "2026-11-01" }, "from"],
      [{ from: "2026-11-01" }, "to"],
      [{ from: "2026-02-30", to: "2026-03-01" }, "from"],
      [{ from: "2026-11-02", to: "2026-11-01" }, "from"],
      [{ from: "2025-11-20", to: "2026-11-21" }, "from"],
    ];
    for (const [data, field] of cases) {
      assert.throws(
        () => parseRange(data),
        (error) =>
          reason(error).reason === Reason.invalidInput &&
          reason(error).field === field,
        JSON.stringify(data),
      );
    }
  });
});

describe("rangeReportOf", () => {
  const { deps } = fakeDeps();

  test("only admins", async () => {
    await assert.rejects(
      rangeReportOf(undefined, {}, deps),
      (error: HttpsError) => error.code === "unauthenticated",
    );
    const user = { uid: "u", token: {} } as unknown as Auth;
    await assert.rejects(
      rangeReportOf(user, { from: "2026-11-01", to: "2026-11-02" }, deps),
      (error) => reason(error).reason === Reason.notAdmin,
    );
  });

  test("no export yet is no-data", async () => {
    await assert.rejects(
      rangeReportOf(
        admin,
        { from: "2026-11-01", to: "2026-11-02" },
        { ...deps, eventDays: async () => null },
      ),
      (error) => reason(error).reason === Reason.noData,
    );
  });

  test("not after the latest day", async () => {
    await assert.rejects(
      rangeReportOf(admin, { from: "2026-11-01", to: "2026-11-21" }, deps),
      (error) =>
        reason(error).reason === Reason.invalidInput &&
        reason(error).field === "to",
    );
  });

  test("answers the range's report", async () => {
    const report = await rangeReportOf(
      admin,
      { from: "2026-11-01", to: "2026-11-20" },
      deps,
    );
    assert.equal(report.from, "2026-11-01");
    assert.equal(report.growth.length, 20);
  });
});
