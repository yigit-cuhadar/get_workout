import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  EntitlementStore,
  NEVER_EXPIRES_MS,
  Reason,
  StoredEntitlement,
  WebhookRequest,
  isUid,
  parseEvent,
  revenueCatWebhookOf,
  sameSecret,
  targetUid,
} from "./revenuecat_webhook";

const secret = "Bearer s3cret-value";
const t0 = 1_700_000_000_000;
const day = 24 * 60 * 60 * 1000;

/** A webhook body as RevenueCat sends it (`api_version` and `event`). */
const body = (event: Record<string, unknown>) => ({
  api_version: "1.0",
  event: {
    id: "evt-1",
    type: "INITIAL_PURCHASE",
    event_timestamp_ms: t0,
    app_user_id: "u1",
    original_app_user_id: "u1",
    aliases: ["u1"],
    entitlement_ids: ["premium"],
    entitlement_id: "premium",
    product_id: "premium_monthly",
    period_type: "NORMAL",
    purchased_at_ms: t0,
    expiration_at_ms: t0 + 30 * day,
    environment: "PRODUCTION",
    store: "APP_STORE",
    ...event,
  },
});

const post = (
  payload: unknown,
  overrides: Partial<WebhookRequest> = {},
): WebhookRequest => ({
  method: "POST",
  isJson: true,
  authorization: secret,
  body: payload,
  ...overrides,
});

/**
 * `entitlements` and Auth in memory. [options.failing] names a step that
 * throws; [options.duringApply] runs inside the transaction (e.g. an
 * account deleted meanwhile).
 */
function fakeStore(
  options: {
    users?: string[];
    failing?: "userExists" | "apply";
    duringApply?: (users: Set<string>) => void;
  } = {},
) {
  const users = new Set(options.users ?? ["u1", "u2", "u3"]);
  const docs = new Map<string, StoredEntitlement>();
  const store: EntitlementStore = {
    async userExists(uid) {
      if (options.failing === "userExists") throw new Error("auth down");
      return users.has(uid);
    },
    async apply(uids, decide) {
      if (options.failing === "apply") throw new Error("aborted");
      const plan = decide(new Map(uids.map((uid) => [uid, docs.get(uid)])));
      options.duringApply?.(users);
      for (const [uid, entitlement] of plan.writes) docs.set(uid, entitlement);
      return plan;
    },
    async delete(uid) {
      docs.delete(uid);
    },
  };
  return { store, docs, users };
}

type Fake = ReturnType<typeof fakeStore>;

const deliver = (
  fake: Fake,
  request: WebhookRequest,
  acceptSandbox = false,
) =>
  revenueCatWebhookOf(request, {
    authorization: secret,
    acceptSandbox,
    store: fake.store,
  });

/** Delivers [event] and expects 200 with [reason]. */
async function expect200(
  fake: Fake,
  event: Record<string, unknown>,
  reason: string,
  acceptSandbox = false,
) {
  const response = await deliver(fake, post(body(event)), acceptSandbox);
  assert.deepEqual(response, { status: 200, body: { reason } });
}

describe("authorization and request", () => {
  test("a wrong, missing or empty header is refused and nothing is read", async () => {
    const fake = fakeStore({ failing: "userExists" });
    for (const authorization of [undefined, "", "Bearer wrong", `${secret} `]) {
      const response = await deliver(fake, post(body({}), { authorization }));
      assert.deepEqual(response, {
        status: 401,
        body: { reason: Reason.unauthorized },
      });
    }
    assert.equal(fake.docs.size, 0);
  });

  test("an unset secret refuses everything", async () => {
    const fake = fakeStore();
    const response = await revenueCatWebhookOf(
      post(body({}), { authorization: "" }),
      { authorization: "", acceptSandbox: false, store: fake.store },
    );
    assert.equal(response.status, 401);
  });

  test("sameSecret compares the whole value", () => {
    assert.ok(sameSecret(secret, secret));
    assert.ok(!sameSecret("Bearer s3cret", secret));
    assert.ok(!sameSecret(undefined, secret));
  });

  test("only POST with JSON", async () => {
    const fake = fakeStore();
    const get = await deliver(fake, post(body({}), { method: "GET" }));
    assert.equal(get.status, 405);
    const text = await deliver(fake, post(body({}), { isJson: false }));
    assert.equal(text.status, 415);
    assert.equal(fake.docs.size, 0);
  });

  test("a body that is not an event is a 400", async () => {
    const fake = fakeStore();
    for (const payload of [
      null,
      {},
      { event: null },
      body({ id: 7 }),
      body({ type: undefined }),
      body({ event_timestamp_ms: "now" }),
      body({ expiration_at_ms: -1 }),
      body({ expiration_at_ms: 1e20 }),
    ]) {
      const response = await deliver(fake, post(payload));
      assert.deepEqual(response, {
        status: 400,
        body: { reason: Reason.invalidEvent },
      });
    }
  });
});

describe("event types", () => {
  test("INITIAL_PURCHASE grants premium until the expiry, with the product", async () => {
    const fake = fakeStore();
    await expect200(fake, {}, Reason.applied);
    assert.deepEqual(fake.docs.get("u1"), {
      premium: true,
      expiresAtMs: t0 + 30 * day,
      productId: "premium_monthly",
      lastEventMs: t0,
      lastEventId: "evt-1",
    });
  });

  for (const type of [
    "RENEWAL",
    "UNCANCELLATION",
    "SUBSCRIPTION_PAUSED",
    "SUBSCRIPTION_EXTENDED",
    "TEMPORARY_ENTITLEMENT_GRANT",
    "REFUND_REVERSED",
  ]) {
    test(`${type} keeps premium until the event's expiry`, async () => {
      const fake = fakeStore();
      const expiry = t0 + 9 * day;
      await expect200(fake, { type, expiration_at_ms: expiry }, Reason.applied);
      assert.equal(fake.docs.get("u1")?.premium, true);
      assert.equal(fake.docs.get("u1")?.expiresAtMs, expiry);
    });
  }

  test("CANCELLATION stays premium until the end of the period", async () => {
    const fake = fakeStore();
    await expect200(fake, {}, Reason.applied);
    await expect200(
      fake,
      {
        id: "evt-2",
        type: "CANCELLATION",
        cancel_reason: "UNSUBSCRIBE",
        event_timestamp_ms: t0 + day,
      },
      Reason.applied,
    );
    assert.equal(fake.docs.get("u1")?.premium, true);
    assert.equal(fake.docs.get("u1")?.expiresAtMs, t0 + 30 * day);
  });

  test("a refund's CANCELLATION carries a past expiry, which the rules refuse", async () => {
    const fake = fakeStore();
    await expect200(
      fake,
      {
        type: "CANCELLATION",
        cancel_reason: "CUSTOMER_SUPPORT",
        expiration_at_ms: t0 - 1000,
      },
      Reason.applied,
    );
    assert.equal(fake.docs.get("u1")?.expiresAtMs, t0 - 1000);
  });

  test("EXPIRATION removes premium", async () => {
    const fake = fakeStore();
    await expect200(fake, {}, Reason.applied);
    await expect200(
      fake,
      {
        id: "evt-2",
        type: "EXPIRATION",
        expiration_reason: "UNSUBSCRIBE",
        event_timestamp_ms: t0 + 30 * day,
      },
      Reason.applied,
    );
    assert.deepEqual(fake.docs.get("u1"), {
      premium: false,
      expiresAtMs: t0 + 30 * day,
      productId: "premium_monthly",
      lastEventMs: t0 + 30 * day,
      lastEventId: "evt-2",
    });
  });

  test("BILLING_ISSUE keeps premium through the grace period", async () => {
    const fake = fakeStore();
    await expect200(
      fake,
      {
        type: "BILLING_ISSUE",
        expiration_at_ms: t0 - day,
        grace_period_expiration_at_ms: t0 + 6 * day,
      },
      Reason.applied,
    );
    assert.equal(fake.docs.get("u1")?.premium, true);
    assert.equal(fake.docs.get("u1")?.expiresAtMs, t0 + 6 * day);
  });

  test("BILLING_ISSUE without a grace period ends at the expiry", async () => {
    const fake = fakeStore();
    await expect200(
      fake,
      {
        type: "BILLING_ISSUE",
        expiration_at_ms: t0 - day,
        grace_period_expiration_at_ms: null,
      },
      Reason.applied,
    );
    assert.equal(fake.docs.get("u1")?.expiresAtMs, t0 - day);
  });

  test("PRODUCT_CHANGE never shortens premium already known", async () => {
    const fake = fakeStore();
    await expect200(
      fake,
      { product_id: "premium_yearly", expiration_at_ms: t0 + 365 * day },
      Reason.applied,
    );
    await expect200(
      fake,
      {
        id: "evt-2",
        type: "PRODUCT_CHANGE",
        event_timestamp_ms: t0 + day,
        product_id: "premium_yearly",
        new_product_id: "premium_monthly",
        expiration_at_ms: t0 + 30 * day,
      },
      Reason.applied,
    );
    assert.equal(fake.docs.get("u1")?.expiresAtMs, t0 + 365 * day);
    assert.equal(fake.docs.get("u1")?.premium, true);
  });

  test("NON_RENEWING_PURCHASE without an expiry never expires", async () => {
    const fake = fakeStore();
    await expect200(
      fake,
      { type: "NON_RENEWING_PURCHASE", expiration_at_ms: null },
      Reason.applied,
    );
    assert.equal(fake.docs.get("u1")?.expiresAtMs, NEVER_EXPIRES_MS);
    assert.equal(fake.docs.get("u1")?.premium, true);
  });

  test("a refunded purchase that never expires loses premium", async () => {
    const fake = fakeStore();
    await expect200(
      fake,
      { type: "NON_RENEWING_PURCHASE", expiration_at_ms: null },
      Reason.applied,
    );
    await expect200(
      fake,
      {
        id: "evt-2",
        type: "CANCELLATION",
        event_timestamp_ms: t0 + day,
        expiration_at_ms: null,
      },
      Reason.applied,
    );
    assert.equal(fake.docs.get("u1")?.premium, false);
    assert.equal(fake.docs.get("u1")?.expiresAtMs, t0 + day);
  });

  test("TEST and unknown types are answered without writing", async () => {
    const fake = fakeStore({ failing: "userExists" });
    await expect200(fake, { type: "TEST" }, Reason.testEvent);
    for (const type of ["SUBSCRIBER_ALIAS", "INVOICE_ISSUANCE", "NEW_TYPE"]) {
      await expect200(fake, { type }, Reason.unhandledType);
    }
    assert.equal(fake.docs.size, 0);
  });

  test("a product without the premium entitlement writes nothing", async () => {
    const fake = fakeStore();
    await expect200(fake, { entitlement_ids: null }, Reason.notPremium);
    await expect200(fake, { entitlement_ids: ["other"] }, Reason.notPremium);
    await expect200(
      fake,
      { type: "EXPIRATION", entitlement_ids: ["other"] },
      Reason.notPremium,
    );
    assert.equal(fake.docs.size, 0);
  });
});

describe("environments", () => {
  test("prod ignores sandbox purchases", async () => {
    const fake = fakeStore();
    await expect200(fake, { environment: "SANDBOX" }, Reason.sandboxIgnored);
    assert.equal(fake.docs.size, 0);
  });

  test("dev applies sandbox and production purchases", async () => {
    const fake = fakeStore();
    await expect200(fake, { environment: "SANDBOX" }, Reason.applied, true);
    await expect200(
      fake,
      { id: "evt-2", environment: "PRODUCTION", event_timestamp_ms: t0 + 1 },
      Reason.applied,
      true,
    );
  });
});

describe("ordering and redelivery", () => {
  test("an older event arriving late changes nothing", async () => {
    const fake = fakeStore();
    await expect200(
      fake,
      { id: "evt-2", type: "EXPIRATION", event_timestamp_ms: t0 + 30 * day },
      Reason.applied,
    );
    await expect200(fake, { id: "evt-1", type: "RENEWAL" }, Reason.stale);
    assert.equal(fake.docs.get("u1")?.premium, false);
    assert.equal(fake.docs.get("u1")?.lastEventId, "evt-2");
  });

  test("the same event delivered again is applied once", async () => {
    const fake = fakeStore();
    await expect200(fake, {}, Reason.applied);
    const first = fake.docs.get("u1");
    await expect200(fake, {}, Reason.duplicate);
    assert.equal(fake.docs.get("u1"), first);
  });

  test("another event at the same millisecond is applied", async () => {
    const fake = fakeStore();
    await expect200(fake, {}, Reason.applied);
    const cancellation = { id: "evt-2", type: "CANCELLATION" };
    await expect200(fake, cancellation, Reason.applied);
    assert.equal(fake.docs.get("u1")?.lastEventId, "evt-2");
  });
});

describe("users", () => {
  test("anonymous RevenueCat ids are never written", async () => {
    const fake = fakeStore();
    const anonymous = "$RCAnonymousID:8cd1a2b0e3f94c4f";
    await expect200(
      fake,
      {
        app_user_id: anonymous,
        original_app_user_id: anonymous,
        aliases: [anonymous],
      },
      Reason.noUser,
    );
    assert.equal(fake.docs.size, 0);
  });

  test("an anonymous app_user_id falls back to its one uid alias", async () => {
    const fake = fakeStore();
    const anonymous = "$RCAnonymousID:8cd1a2b0e3f94c4f";
    await expect200(
      fake,
      {
        app_user_id: anonymous,
        original_app_user_id: anonymous,
        aliases: [anonymous, "u2"],
      },
      Reason.applied,
    );
    assert.deepEqual([...fake.docs.keys()], ["u2"]);
  });

  test("targetUid refuses to pick between two uids", () => {
    const event = parseEvent(
      body({
        app_user_id: "$RCAnonymousID:x",
        original_app_user_id: "u1",
        aliases: ["u1", "u2"],
      }),
    );
    assert.ok(event);
    assert.equal(targetUid(event), undefined);
  });

  test("isUid refuses ids that cannot be a document id", () => {
    assert.ok(isUid("abcDEF123"));
    for (const id of ["", "a/b", "x".repeat(129), "$RCAnonymousID:1"]) {
      assert.ok(!isUid(id), id);
    }
  });

  test("a deleted account is not written again", async () => {
    const fake = fakeStore({ users: ["u2"] });
    await expect200(fake, {}, Reason.deletedUser);
    assert.equal(fake.docs.size, 0);
  });

  test("an account deleted while the event was written is cleaned up", async () => {
    const fake = fakeStore({ duringApply: (users) => users.delete("u1") });
    await expect200(fake, {}, Reason.applied);
    assert.equal(fake.docs.size, 0);
  });
});

describe("TRANSFER", () => {
  /** A TRANSFER as the sample: no user, entitlement or expiry fields. */
  const transfer = (from: string[], to: string[], extra = {}) =>
    body({
      id: "evt-t",
      type: "TRANSFER",
      event_timestamp_ms: t0 + day,
      app_user_id: undefined,
      original_app_user_id: undefined,
      aliases: undefined,
      entitlement_ids: undefined,
      entitlement_id: undefined,
      product_id: undefined,
      expiration_at_ms: undefined,
      transferred_from: from,
      transferred_to: to,
      ...extra,
    });

  test("moves premium from the old uid to the new one", async () => {
    const fake = fakeStore();
    await expect200(fake, {}, Reason.applied);
    const response = await deliver(fake, post(transfer(["u1"], ["u2"])));
    assert.deepEqual(response.body, { reason: Reason.applied });
    assert.deepEqual(fake.docs.get("u1"), {
      premium: false,
      expiresAtMs: t0 + day,
      productId: "premium_monthly",
      lastEventMs: t0 + day,
      lastEventId: "evt-t",
    });
    assert.deepEqual(fake.docs.get("u2"), {
      premium: true,
      expiresAtMs: t0 + 30 * day,
      productId: "premium_monthly",
      lastEventMs: t0 + day,
      lastEventId: "evt-t",
    });
  });

  test("an older event for the old uid cannot grant it again", async () => {
    const fake = fakeStore();
    await expect200(fake, {}, Reason.applied);
    await deliver(fake, post(transfer(["u1"], ["u2"])));
    await expect200(
      fake,
      { id: "evt-r", type: "RENEWAL", event_timestamp_ms: t0 + 1 },
      Reason.stale,
    );
    assert.equal(fake.docs.get("u1")?.premium, false);
  });

  test("keeps a later expiry the new uid already has", async () => {
    const fake = fakeStore();
    await expect200(fake, {}, Reason.applied);
    await expect200(
      fake,
      { id: "evt-2", app_user_id: "u2", expiration_at_ms: t0 + 90 * day },
      Reason.applied,
    );
    await deliver(fake, post(transfer(["u1"], ["u2"])));
    assert.equal(fake.docs.get("u2")?.expiresAtMs, t0 + 90 * day);
  });

  test("from an anonymous id there is nothing known to move", async () => {
    const fake = fakeStore();
    const response = await deliver(
      fake,
      post(transfer(["$RCAnonymousID:1"], ["u2"])),
    );
    assert.deepEqual(response, {
      status: 200,
      body: { reason: Reason.nothingToTransfer },
    });
    assert.equal(fake.docs.size, 0);
  });

  test("only anonymous ids, or only deleted accounts, write nothing", async () => {
    const fake = fakeStore({ users: [] });
    assert.deepEqual(
      (await deliver(fake, post(transfer(["$RCAnonymousID:1"], [])))).body,
      { reason: Reason.noUser },
    );
    const deleted = await deliver(fake, post(transfer(["u1"], ["u2"])));
    assert.deepEqual(deleted.body, { reason: Reason.deletedUser });
  });

  test("a deleted new owner gets nothing; the old one still loses it", async () => {
    const fake = fakeStore({ users: ["u1"] });
    await expect200(fake, {}, Reason.applied);
    await deliver(fake, post(transfer(["u1"], ["u9"])));
    assert.equal(fake.docs.get("u1")?.premium, false);
    assert.ok(!fake.docs.has("u9"));
  });

  test("redelivered, it changes nothing", async () => {
    const fake = fakeStore();
    await expect200(fake, {}, Reason.applied);
    await deliver(fake, post(transfer(["u1"], ["u2"])));
    const response = await deliver(fake, post(transfer(["u1"], ["u2"])));
    assert.deepEqual(response.body, { reason: Reason.duplicate });
  });

  test("sandbox transfers are ignored in prod", async () => {
    const fake = fakeStore();
    const response = await deliver(
      fake,
      post(transfer(["u1"], ["u2"], { environment: "SANDBOX" })),
    );
    assert.deepEqual(response.body, { reason: Reason.sandboxIgnored });
  });
});

describe("failures", () => {
  test("Auth or Firestore failing is a 500, so RevenueCat retries", async () => {
    for (const failing of ["userExists", "apply"] as const) {
      const fake = fakeStore({ failing });
      const response = await deliver(fake, post(body({})));
      assert.deepEqual(response, {
        status: 500,
        body: { reason: Reason.retry },
      });
    }
  });

});
