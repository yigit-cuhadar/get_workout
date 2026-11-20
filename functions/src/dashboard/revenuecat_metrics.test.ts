import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { parseOverview } from "./revenuecat_metrics";

const metric = (id: string, period: string, value: number) => ({
  object: "overview_metric",
  id,
  name: id,
  description: "",
  unit: "#",
  period,
  value,
  last_updated_at: null,
  last_updated_at_iso8601: null,
});

/** The project's real response (2026-11-21), values changed. */
const sample = {
  object: "overview_metrics",
  currency: "USD",
  metrics: [
    metric("active_trials", "P0D", 3),
    metric("active_subscriptions", "P0D", 12),
    metric("mrr", "P28D", 95.5),
    metric("revenue", "P28D", 120.25),
    metric("new_customers", "P28D", 14),
    metric("active_users", "P28D", 40),
  ],
};

describe("parseOverview", () => {
  test("reads each metric by its id", () => {
    assert.deepEqual(parseOverview(sample), {
      mrr: 95.5,
      revenue28d: 120.25,
      activeSubscriptions: 12,
      activeTrials: 3,
      newCustomers28d: 14,
      currency: "USD",
    });
  });

  test("a metric left out is null", () => {
    const snapshot = parseOverview({
      ...sample,
      metrics: [metric("mrr", "P28D", 0), { id: "revenue", value: "12" }],
    });
    assert.equal(snapshot.mrr, 0);
    assert.equal(snapshot.revenue28d, null);
    assert.equal(snapshot.activeTrials, null);
  });

  test("anything else is refused", () => {
    for (const body of [
      null,
      {},
      { ...sample, object: "error" },
      { ...sample, metrics: {} },
      { object: "overview_metrics", metrics: [] },
    ]) {
      assert.throws(() => parseOverview(body));
    }
  });
});
