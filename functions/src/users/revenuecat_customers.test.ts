import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { REVENUECAT_PROJECT_URL } from "../dashboard/revenuecat_metrics";
import {
  RevenueCatError,
  entitlementIdIn,
  parseCustomer,
  revenueCatGrants,
} from "./revenuecat_customers";

const entitlements = {
  object: "list",
  items: [
    { object: "entitlement", id: "entl_other", lookup_key: "other" },
    { object: "entitlement", id: "entl_premium", lookup_key: "premium" },
  ],
};

/** The documented customer shape, values changed. */
const customerBody = {
  object: "customer",
  id: "u1",
  last_seen_at: 1_700_000_000_000,
  last_seen_app_version: "1.0.0",
  last_seen_platform: "iOS",
  last_seen_platform_version: "18.1",
  active_entitlements: {
    object: "list",
    items: [
      { object: "customer.active_entitlement", entitlement_id: "entl_other", expires_at: 5 },
      { object: "customer.active_entitlement", entitlement_id: "entl_premium", expires_at: null },
    ],
  },
};

const subscriptionsBody = {
  object: "list",
  items: [
    {
      object: "subscription",
      store: "promotional",
      status: "active",
      gives_access: true,
      product_id: null,
      current_period_ends_at: 1_800_000_000_000,
      auto_renewal_status: "will_not_renew",
    },
  ],
};

describe("entitlementIdIn", () => {
  test("finds the id by lookup key, or throws", () => {
    assert.equal(entitlementIdIn(entitlements, "premium"), "entl_premium");
    assert.throws(() => entitlementIdIn(entitlements, "gold"));
    assert.throws(() => entitlementIdIn(null, "premium"));
  });
});

describe("parseCustomer", () => {
  test("reads Premium and the subscriptions", () => {
    assert.deepEqual(
      parseCustomer(customerBody, subscriptionsBody, "entl_premium"),
      {
        premium: { expiresAtMillis: null },
        subscriptions: [
          {
            store: "promotional",
            status: "active",
            givesAccess: true,
            productId: null,
            periodEndsAtMillis: 1_800_000_000_000,
            autoRenewal: "will_not_renew",
          },
        ],
      },
    );
  });

  test("no premium entitlement and missing fields read as none", () => {
    const customer = parseCustomer({}, {}, "entl_premium");
    assert.equal(customer.premium, null);
    assert.deepEqual(customer.subscriptions, []);
  });
});

/** Answers each path with [routes]' status and body; records requests. */
function fakeFetch(routes: Record<string, [number, unknown]>) {
  const requests: { path: string; method: string; body: unknown }[] = [];
  const fetcher = (async (url: string, init: RequestInit) => {
    const path = url.slice(REVENUECAT_PROJECT_URL.length);
    requests.push({
      path,
      method: init.method ?? "GET",
      body: init.body ? JSON.parse(init.body as string) : undefined,
    });
    assert.equal(
      (init.headers as Record<string, string>).Authorization,
      "Bearer key",
    );
    const [status, body] = routes[path] ?? [404, {}];
    return new Response(JSON.stringify(body), { status });
  }) as typeof fetch;
  return { fetcher, requests };
}

describe("revenueCatGrants", () => {
  const base = {
    "/entitlements?limit=100": [200, entitlements] as [number, unknown],
  };

  test("grants and revokes premium by its API v2 id, looked up once", async () => {
    const { fetcher, requests } = fakeFetch({
      ...base,
      "/customers/u%2F1/actions/grant_entitlement": [201, customerBody],
      "/customers/u%2F1/actions/revoke_granted_entitlement": [200, customerBody],
    });
    const grants = revenueCatGrants("key", fetcher);
    await grants.grant("u/1", 1234);
    await grants.revoke("u/1");
    assert.deepEqual(requests, [
      { path: "/entitlements?limit=100", method: "GET", body: undefined },
      {
        path: "/customers/u%2F1/actions/grant_entitlement",
        method: "POST",
        body: { entitlement_id: "entl_premium", expires_at: 1234 },
      },
      {
        path: "/customers/u%2F1/actions/revoke_granted_entitlement",
        method: "POST",
        body: { entitlement_id: "entl_premium" },
      },
    ]);
  });

  test("reads a customer, or null when RevenueCat has none", async () => {
    const { fetcher } = fakeFetch({
      ...base,
      "/customers/u1": [200, customerBody],
      "/customers/u1/subscriptions": [200, subscriptionsBody],
    });
    const grants = revenueCatGrants("key", fetcher);
    assert.deepEqual((await grants.customer("u1"))?.premium, {
      expiresAtMillis: null,
    });
    assert.equal(await grants.customer("u2"), null);
  });

  test("a refusal throws with RevenueCat's status", async () => {
    const { fetcher } = fakeFetch({
      ...base,
      "/customers/u1/actions/grant_entitlement": [403, { type: "authorization_error" }],
    });
    await assert.rejects(
      revenueCatGrants("key", fetcher).grant("u1", 1),
      (error: RevenueCatError) => error.status === 403,
    );
  });

  test("a failed entitlement lookup is tried again next time", async () => {
    const routes: Record<string, [number, unknown]> = {
      "/entitlements?limit=100": [500, {}],
      "/customers/u1/actions/revoke_granted_entitlement": [200, {}],
    };
    const { fetcher } = fakeFetch(routes);
    const grants = revenueCatGrants("key", fetcher);
    await assert.rejects(grants.revoke("u1"));
    routes["/entitlements?limit=100"] = [200, entitlements];
    await grants.revoke("u1");
  });
});
