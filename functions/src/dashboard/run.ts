import { BigQuery } from "@google-cloud/bigquery";
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";

import { dayAt, endingAt } from "./dates";
import {
  ReportContext,
  ReportSource,
  buildReport,
  buildRetention,
} from "./report";
import {
  RevenueSnapshot,
  fetchOverview,
  revenueCatApiKey,
} from "./revenuecat_metrics";
import {
  TIME_ZONE,
  eventDays,
  projectConfig,
  warehouseSource,
} from "./warehouse";

/** `details.reason` of a refusal, which the panel maps on. */
export const Reason = {
  notAdmin: "not-admin",
  invalidInput: "invalid-input",
  /** No Analytics export has landed yet. */
  noData: "no-data",
} as const;

/** The preset periods, in days, stored as `dashboard/p<days>`. */
export const PRESETS = [7, 30, 90];

/** `dashboard/status`. */
export interface DashboardStatus {
  /** The latest day with Analytics data, null before the first export. */
  lastDay: string | null;
  updatedAtMillis: number;
  state: "ok" | "no-data" | "error";
  /** The parts that failed, when any did. */
  message?: string;
}

export interface DashboardDeps {
  /** The first and latest day with Analytics data; null when none. */
  eventDays(): Promise<{ first: string; last: string } | null>;
  source: ReportSource;
  context: Omit<ReportContext, "first" | "last">;
  fetchRevenue(): Promise<RevenueSnapshot>;
  /** Sets the Firestore document at [path]. */
  write(path: string, data: object): Promise<void>;
  nowMillis: number;
}

export const requireAdmin = (auth: CallableRequest["auth"]) => {
  if (!auth) throw new HttpsError("unauthenticated", "Sign in first.");
  if (auth.token.admin !== true) {
    throw new HttpsError("permission-denied", "Admins only.", {
      reason: Reason.notAdmin,
    });
  }
};

/**
 * Stores the revenue snapshot, the preset reports and retention, then
 * the status. Each part is tried on its own: a failing one is named in
 * the status and leaves the others, and its own previous document, as
 * they are.
 */
export async function refreshDashboard(
  deps: DashboardDeps,
): Promise<DashboardStatus> {
  const failures: string[] = [];
  const fail = (part: string, error: unknown) => {
    logger.error("dashboard part failed", { part, error: String(error) });
    failures.push(`${part}: ${error instanceof Error ? error.message : error}`);
  };
  const attempt = (part: string, work: () => Promise<void>) =>
    work().catch((error: unknown) => fail(part, error));

  // First, so the reports' MRR tile already finds today's snapshot.
  await attempt("revenue", async () => {
    const snapshot = await deps.fetchRevenue();
    const day = dayAt(deps.nowMillis, deps.context.timeZone);
    const stored = { ...snapshot, day, takenAtMillis: deps.nowMillis };
    await deps.write(`dashboardRevenue/${day}`, stored);
    await deps.write("dashboard/revenue", stored);
  });

  // Undefined when BigQuery could not tell.
  const days = await deps
    .eventDays()
    .catch((error: unknown) => fail("analytics", error));
  if (days) {
    const context = { ...deps.context, ...days };
    for (const preset of PRESETS) {
      await attempt(`p${preset}`, async () => {
        const range = endingAt(days.last, preset);
        await deps.write(
          `dashboard/p${preset}`,
          await buildReport(deps.source, range, context),
        );
      });
    }
    await attempt("retention", async () => {
      await deps.write(
        "dashboard/retention",
        await buildRetention(deps.source, days.last),
      );
    });
  }

  const status: DashboardStatus = {
    lastDay: days?.last ?? null,
    updatedAtMillis: deps.nowMillis,
    state: failures.length > 0 ? "error" : days === null ? "no-data" : "ok",
    ...(failures.length > 0 ? { message: failures.join("\n") } : {}),
  };
  await deps.write("dashboard/status", status);
  return status;
}

/** [DashboardDeps] on this project's BigQuery, Firestore and RevenueCat. */
export const liveDeps = (): DashboardDeps => {
  const config = projectConfig();
  const bigQuery = new BigQuery({ projectId: config.projectId });
  const db = getFirestore();
  return {
    eventDays: () => eventDays(bigQuery, config.analytics),
    source: warehouseSource(bigQuery, db, config),
    context: { environments: config.environments, timeZone: TIME_ZONE },
    fetchRevenue: () => fetchOverview(revenueCatApiKey.value()),
    async write(path, data) {
      await db.doc(path).set(data);
    },
    nowMillis: Date.now(),
  };
};
