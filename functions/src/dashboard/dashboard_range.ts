import {
  CallableRequest,
  HttpsError,
  onCall,
} from "firebase-functions/v2/https";

import { DayRange, isDay, lengthOf } from "./dates";
import { Report, buildReport } from "./report";
import { DashboardDeps, Reason, liveDeps, requireAdmin } from "./run";

/** The longest custom range, in days. */
export const MAX_RANGE_DAYS = 366;

const invalid = (field: string, message: string) =>
  new HttpsError("invalid-argument", message, {
    reason: Reason.invalidInput,
    field,
  });

/** `{from, to}` of a request, or an `invalid-input` error. */
export function parseRange(data: unknown): DayRange {
  const { from, to } = (
    typeof data === "object" && data !== null ? data : {}
  ) as { [key: string]: unknown };
  if (!isDay(from)) throw invalid("from", "from must be a YYYY-MM-DD day.");
  if (!isDay(to)) throw invalid("to", "to must be a YYYY-MM-DD day.");
  if (from > to) throw invalid("from", "from must not be after to.");
  if (lengthOf({ from, to }) > MAX_RANGE_DAYS) {
    throw invalid("from", `A range has at most ${MAX_RANGE_DAYS} days.`);
  }
  return { from, to };
}

/** The report of the admin's range, queried now. */
export async function rangeReportOf(
  auth: CallableRequest["auth"],
  data: unknown,
  deps: Pick<DashboardDeps, "eventDays" | "source" | "context">,
): Promise<Report> {
  requireAdmin(auth);
  const range = parseRange(data);
  const days = await deps.eventDays();
  if (days === null) {
    throw new HttpsError("failed-precondition", "No Analytics data yet.", {
      reason: Reason.noData,
    });
  }
  if (range.to > days.last) {
    throw invalid("to", `The latest day with data is ${days.last}.`);
  }
  return buildReport(deps.source, range, { ...deps.context, ...days });
}

export const dashboardRange = onCall({ timeoutSeconds: 300 }, (request) =>
  rangeReportOf(request.auth, request.data, liveDeps()),
);
