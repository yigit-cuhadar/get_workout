import { defineSecret } from "firebase-functions/params";

/**
 * A RevenueCat API v2 secret key with `charts_metrics:overview:read`, and
 * for the panel's Users page `customer_information:customers:read_write`,
 * `customer_information:subscriptions:read` and
 * `project_configuration:entitlements:read`.
 */
export const revenueCatApiKey = defineSecret("REVENUECAT_API_KEY");

/** The app's one RevenueCat project, as API v2 addresses it. */
export const REVENUECAT_PROJECT_URL =
  "https://api.revenuecat.com/v2/projects/proj994e814e";

const OVERVIEW_URL = `${REVENUECAT_PROJECT_URL}/metrics/overview`;

/**
 * RevenueCat's overview metrics: subscriptions and trials now, the rest
 * over the last 28 days; money in [currency]. A metric RevenueCat left out
 * is null.
 */
export interface RevenueSnapshot {
  mrr: number | null;
  revenue28d: number | null;
  activeSubscriptions: number | null;
  activeTrials: number | null;
  newCustomers28d: number | null;
  currency: string;
}

/** Overview metric ids by snapshot field. */
const METRICS = {
  mrr: "mrr",
  revenue28d: "revenue",
  activeSubscriptions: "active_subscriptions",
  activeTrials: "active_trials",
  newCustomers28d: "new_customers",
} as const;

/** The snapshot in an overview response; throws when it is not one. */
export function parseOverview(body: unknown): RevenueSnapshot {
  const { object, metrics, currency } = (body ?? {}) as {
    [key: string]: unknown;
  };
  if (
    object !== "overview_metrics" ||
    !Array.isArray(metrics) ||
    typeof currency !== "string"
  ) {
    throw new Error("Not an overview_metrics response.");
  }
  const value = (id: string) => {
    const metric = metrics.find(
      (m: { id?: unknown } | null) => m?.id === id,
    ) as { value?: unknown } | undefined;
    return typeof metric?.value === "number" ? metric.value : null;
  };
  return {
    mrr: value(METRICS.mrr),
    revenue28d: value(METRICS.revenue28d),
    activeSubscriptions: value(METRICS.activeSubscriptions),
    activeTrials: value(METRICS.activeTrials),
    newCustomers28d: value(METRICS.newCustomers28d),
    currency,
  };
}

/** Reads the overview metrics, in USD. */
export async function fetchOverview(apiKey: string): Promise<RevenueSnapshot> {
  const response = await fetch(`${OVERVIEW_URL}?currency=USD`, {
    headers: { Authorization: `Bearer ${apiKey}` },
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) {
    throw new Error(`RevenueCat answered ${response.status}.`);
  }
  return parseOverview(await response.json());
}
