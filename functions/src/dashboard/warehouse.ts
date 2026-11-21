import { BigQuery } from "@google-cloud/bigquery";
import { FieldPath, Firestore } from "firebase-admin/firestore";

import { addDays, DayRange, suffixOf } from "./dates";
import {
  CohortRow,
  CrashCounts,
  DayRow,
  EventCounts,
  Funnel,
  ReportSource,
  RevenueEventRow,
} from "./report";

/**
 * The owner's zone: the nightly run's clock, and the days revenue events
 * and crashes are counted in (Analytics counts in its property's zone).
 */
export const TIME_ZONE = "Europe/Istanbul";

/** Where the exports land: the `EU` multi-region. */
const LOCATION = "EU";

/** Each project's Analytics export and the purchases that count there. */
const PROJECTS: Record<string, { analytics: string; environments: string[] }> =
  {
    "getworkout-dev": {
      analytics: "analytics_565325900",
      environments: ["PRODUCTION", "SANDBOX"],
    },
    "getworkout-prod": {
      analytics: "analytics_565341735",
      environments: ["PRODUCTION"],
    },
  };

const CRASHLYTICS = "firebase_crashlytics";

/** Crashlytics' batch tables: the app id, dots as underscores, platform. */
const CRASHLYTICS_TABLES = [
  "com_getworkout_app_IOS",
  "com_getworkout_app_ANDROID",
];

const DAILY_TABLE = /^events_(\d{4})(\d{2})(\d{2})$/;

export const projectConfig = (projectId = process.env.GCLOUD_PROJECT) => {
  const config = projectId === undefined ? undefined : PROJECTS[projectId];
  if (config === undefined || projectId === undefined) {
    throw new Error(`No dashboard configuration for project ${projectId}.`);
  }
  return { projectId, ...config };
};

/** The SQL of every report query; `@` names are query parameters. */
export const sql = (project: string, analytics: string) => {
  const events = `\`${project}.${analytics}.events_*\``;
  // Intraday tables (`events_intraday_…`) sort after every date.
  const inRange = "_TABLE_SUFFIX BETWEEN @from AND @to";
  const param = (key: string) =>
    `(SELECT value.string_value FROM UNNEST(event_params) WHERE key = '${key}')`;
  return {
    daily: `
      SELECT FORMAT_DATE('%F', PARSE_DATE('%Y%m%d', event_date)) AS day,
        COUNT(DISTINCT user_pseudo_id) AS active,
        COUNTIF(event_name = 'first_open') AS installs
      FROM ${events}
      WHERE ${inRange}
      GROUP BY day`,
    activeUsers: `
      SELECT COUNT(DISTINCT user_pseudo_id) AS users
      FROM ${events}
      WHERE ${inRange}`,
    eventCounts: `
      SELECT
        COUNTIF(event_name = 'workout_complete') AS workoutsCompleted,
        COUNTIF(event_name = 'program_start') AS programStarts,
        COUNTIF(event_name = 'custom_exercise_create') AS customExercisesCreated,
        COUNTIF(event_name = 'weight_log') AS weightsLogged,
        COUNTIF(event_name = 'notification_tap') AS notificationsOpened
      FROM ${events}
      WHERE ${inRange}`,
    topProgram: `
      SELECT ${param("program_id")} AS id, COUNT(*) AS starts
      FROM ${events}
      WHERE ${inRange} AND event_name = 'program_start'
      GROUP BY id
      HAVING id IS NOT NULL
      ORDER BY starts DESC, id
      LIMIT 1`,
    // The user id is set after first_open, so it is read from later events.
    funnel: `
      WITH installs AS (
        SELECT DISTINCT user_pseudo_id
        FROM ${events}
        WHERE ${inRange} AND event_name = 'first_open'
      ),
      later AS (
        SELECT user_pseudo_id,
          LOGICAL_OR(event_name = 'onboarding_complete') AS onboarded,
          LOGICAL_OR(event_name = 'first_workout_complete') AS worked_out,
          LOGICAL_OR(event_name = 'paywall_view') AS saw_paywall,
          ARRAY_AGG(user_id IGNORE NULLS ORDER BY event_timestamp DESC LIMIT 1)[SAFE_OFFSET(0)] AS uid
        FROM ${events}
        WHERE _TABLE_SUFFIX BETWEEN @from AND @last
          AND user_pseudo_id IN (SELECT user_pseudo_id FROM installs)
        GROUP BY user_pseudo_id
      )
      SELECT COUNT(*) AS installed,
        COUNTIF(later.onboarded) AS onboardingComplete,
        COUNTIF(later.worked_out) AS firstWorkout,
        COUNTIF(later.saw_paywall) AS paywallSeen,
        COUNTIF(later.uid IN UNNEST(@trialUids)) AS trialStarted,
        COUNTIF(later.uid IN UNNEST(@paidUids)) AS paid
      FROM installs LEFT JOIN later USING (user_pseudo_id)`,
    cohorts: `
      WITH firsts AS (
        SELECT user_pseudo_id, MIN(PARSE_DATE('%Y%m%d', event_date)) AS first_day
        FROM ${events}
        WHERE ${inRange} AND event_name = 'first_open'
        GROUP BY user_pseudo_id
      ),
      active AS (
        SELECT DISTINCT user_pseudo_id, PARSE_DATE('%Y%m%d', event_date) AS day
        FROM ${events}
        WHERE _TABLE_SUFFIX BETWEEN @from AND @last
      ),
      returns AS (
        SELECT firsts.user_pseudo_id, DATE_DIFF(active.day, firsts.first_day, DAY) AS n
        FROM firsts JOIN active USING (user_pseudo_id)
        WHERE DATE_DIFF(active.day, firsts.first_day, DAY) IN (1, 7, 30)
      )
      SELECT FORMAT_DATE('%F', DATE_TRUNC(firsts.first_day, ISOWEEK)) AS week,
        COUNT(DISTINCT firsts.user_pseudo_id) AS users,
        COUNT(DISTINCT IF(returns.n = 1, returns.user_pseudo_id, NULL)) AS d1,
        COUNT(DISTINCT IF(returns.n = 7, returns.user_pseudo_id, NULL)) AS d7,
        COUNT(DISTINCT IF(returns.n = 30, returns.user_pseudo_id, NULL)) AS d30
      FROM firsts LEFT JOIN returns USING (user_pseudo_id)
      GROUP BY week`,
    /** Over the Crashlytics tables that exist, at least one. */
    crashes: (tables: string[]) => `
      WITH crashes AS (
        ${tables
          .map(
            (table) => `
        SELECT installation_uuid, error_type, issue_id, blame_frame.symbol AS symbol
        FROM \`${project}.${CRASHLYTICS}.${table}\`
        WHERE event_timestamp >= TIMESTAMP(@from, @timeZone)
          AND event_timestamp < TIMESTAMP(DATE_ADD(DATE(@to), INTERVAL 1 DAY), @timeZone)`,
          )
          .join("\n        UNION ALL")}
      )
      SELECT
        (SELECT COUNT(DISTINCT installation_uuid) FROM crashes WHERE error_type = 'FATAL') AS crashedUsers,
        (SELECT COUNTIF(error_type = 'NON_FATAL') FROM crashes) AS handledErrors,
        ARRAY(
          SELECT AS STRUCT COALESCE(ANY_VALUE(symbol), issue_id) AS title,
            COUNT(DISTINCT installation_uuid) AS users
          FROM crashes
          GROUP BY issue_id
          ORDER BY users DESC, title
          LIMIT 3
        ) AS topIssues`,
  };
};

/** The first and latest day with an `events_` table; null when none. */
export async function eventDays(
  bigQuery: BigQuery,
  analytics: string,
): Promise<{ first: string; last: string } | null> {
  const dataset = bigQuery.dataset(analytics);
  const [exists] = await dataset.exists();
  if (!exists) return null;
  const [tables] = await dataset.getTables();
  const days = tables
    .map((table) => DAILY_TABLE.exec(table.id ?? ""))
    .flatMap((match) => (match ? [`${match[1]}-${match[2]}-${match[3]}`] : []))
    .sort();
  return days.length === 0
    ? null
    : { first: days[0], last: days[days.length - 1] };
}

/** How many days back a revenue snapshot still stands for a day. */
const snapshotReach = 7;

/** [ReportSource] on BigQuery and Firestore. */
export function warehouseSource(
  bigQuery: BigQuery,
  db: Firestore,
  config: { projectId: string; analytics: string },
): ReportSource {
  const queries = sql(config.projectId, config.analytics);
  const run = async <T>(
    query: string,
    params: Record<string, unknown>,
    types?: Record<string, string[]>,
  ) => {
    const [rows] = await bigQuery.query({
      query,
      params,
      types,
      location: LOCATION,
    });
    return rows as T[];
  };
  const suffixes = ({ from, to }: DayRange) => ({
    from: suffixOf(from),
    to: suffixOf(to),
  });
  let crashTables: Promise<string[]> | undefined;
  const existingCrashTables = () =>
    (crashTables ??= (async () => {
      const dataset = bigQuery.dataset(CRASHLYTICS);
      const exists = await Promise.all(
        CRASHLYTICS_TABLES.map(
          async (t) => (await dataset.table(t).exists())[0],
        ),
      );
      return CRASHLYTICS_TABLES.filter((_, i) => exists[i]);
    })());

  return {
    async daily(range) {
      const rows = await run<{ day: string; active: number; installs: number }>(
        queries.daily,
        suffixes(range),
      );
      return rows.map(
        (row): DayRow => ({
          day: row.day,
          active: row.active,
          new: row.installs,
        }),
      );
    },
    async activeUsers(range) {
      const [row] = await run<{ users: number }>(
        queries.activeUsers,
        suffixes(range),
      );
      return row?.users ?? 0;
    },
    async eventCounts(range) {
      const [row] = await run<EventCounts>(
        queries.eventCounts,
        suffixes(range),
      );
      return row;
    },
    async topProgram(range) {
      const [row] = await run<{ id: string; starts: number }>(
        queries.topProgram,
        suffixes(range),
      );
      return row ?? null;
    },
    async funnel(range, last, trialUids, paidUids) {
      const [row] = await run<Funnel>(
        queries.funnel,
        { ...suffixes(range), last: suffixOf(last), trialUids, paidUids },
        { trialUids: ["STRING"], paidUids: ["STRING"] },
      );
      return row;
    },
    async crashes(range) {
      const tables = await existingCrashTables();
      if (tables.length === 0) return null;
      const [row] = await run<CrashCounts>(queries.crashes(tables), {
        ...range,
        timeZone: TIME_ZONE,
      });
      return row;
    },
    async cohorts(weeks, last) {
      return run<CohortRow>(queries.cohorts, {
        ...suffixes(weeks),
        last: suffixOf(last),
      });
    },
    async revenueEvents() {
      const snapshot = await db
        .collection("revenueEvents")
        .where("type", "in", ["INITIAL_PURCHASE", "RENEWAL"])
        .get();
      return snapshot.docs.map((doc) => doc.data() as RevenueEventRow);
    },
    async mrrOn(day) {
      const snapshot = await db
        .collection("dashboardRevenue")
        .where(FieldPath.documentId(), ">=", addDays(day, -snapshotReach))
        .where(FieldPath.documentId(), "<=", day)
        .get();
      // Ascending on purpose: a descending id query needs an index.
      const mrr = snapshot.docs.at(-1)?.get("mrr");
      return typeof mrr === "number" ? mrr : null;
    },
  };
}
