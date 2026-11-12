import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  EntitlementStore,
  NEVER_EXPIRES_MS,
  Reason,
  StoredEntitlement,
  TEMPORARY_GRANT_MS,
  WebhookRequest,
  isUid,
  parseEvent,
  revenueCatWebhookOf,
  sameSecret,
  targetUid,
} from "./revenuecat_webhook";
import { samples, webhookBody } from "./revenuecat_webhook.samples";

const secret = "Bearer s3cret-value";
const hour = 60 * 60 * 1000;
const day = 24 * hour;

type Event = Record<string, unknown>;

/** [base] with [changes]; undefined removes a field. */
const event = (base: Event, changes: Event = {}): Event =>
  Object.fromEntries(
    Object.entries({ ...base, ...changes }).filter(([, v]) => v !== undefined),
  );

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
  const deleted: string[] = [];
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
      deleted.push(uid);
      docs.delete(uid);
    },
  };
  return { store, docs, users, deleted };
}

type Fake = ReturnType<typeof fakeStore>;

const deliver = (fake: Fake, request: WebhookRequest) =>
  revenueCatWebhookOf(request, { authorization: secret, store: fake.store });

/** Delivers [payload] as an event and expects 200 with [reason]. */
async function expect200(fake: Fake, payload: Event, reason: string) {
  const response = await deliver(fake, post(webhookBody(payload)));
  assert.deepEqual(response, { status: 200, body: { reason } });
}

const doc = (fake: Fake, uid = "u1") => fake.docs.get(uid);

describe("authorization and request", () => {
  test("a wrong, missing or empty header is refused and nothing is read", async () => {
    const fake = fakeStore({ failing: "userExists" });
    const body = webhookBody(samples.INITIAL_PURCHASE);
    for (const authorization of [undefined, "", "Bearer wrong", `${secret} `]) {
      const response = await deliver(fake, post(body, { authorization }));
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
      post(webhookBody(samples.INITIAL_PURCHASE), { authorization: "" }),
      { authorization: "", store: fake.store },
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
    const body = webhookBody(samples.INITIAL_PURCHASE);
    const get = await deliver(fake, post(body, { method: "GET" }));
    assert.equal(get.status, 405);
    const text = await deliver(fake, post(body, { isJson: false }));
    assert.equal(text.status, 415);
    assert.equal(fake.docs.size, 0);
  });

  test("a handled event that is malformed is a 400", async () => {
    const fake = fakeStore();
    const base = samples.INITIAL_PURCHASE;
    for (const payload of [
      null,
      {},
      { event: null },
      webhookBody(event(base, { type: undefined })),
      webhookBody(event(base, { id: 7 })),
      webhookBody(event(base, { event_timestamp_ms: "now" })),
      webhookBody(event(base, { expiration_at_ms: -1 })),
      webhookBody(event(base, { expiration_at_ms: 1e20 })),
    ]) {
      const response = await deliver(fake, post(payload));
      assert.deepEqual(response, {
        status: 400,
        body: { reason: Reason.invalidEvent },
      });
    }
  });

  test("TEST and unhandled types answer 200 whatever their shape", async () => {
    const fake = fakeStore({ failing: "userExists" });
    // The docs give TEST no sample, only "a purchase-like payload".
    await expect200(
      fake,
      event(samples.INITIAL_PURCHASE, { type: "TEST" }),
      Reason.testEvent,
    );
    for (const type of ["SUBSCRIBER_ALIAS", "INVOICE_ISSUANCE", "NEW_TYPE"]) {
      await expect200(
        fake,
        { type, id: 1, expiration_at_ms: "soon" },
        Reason.unhandledType,
      );
    }
    assert.equal(fake.docs.size, 0);
  });
});

describe("event types", () => {
  for (const name of [
    "INITIAL_PURCHASE",
    "RENEWAL",
    "UNCANCELLATION",
    "SUBSCRIPTION_PAUSED",
    "SUBSCRIPTION_EXTENDED",
    "REFUND_REVERSED",
  ] as const) {
    test(`${name} grants premium until its expiry, with its product`, async () => {
      const fake = fakeStore();
      const sample = samples[name];
      await expect200(fake, sample, Reason.applied);
      assert.deepEqual(doc(fake), {
        premium: true,
        expiresAtMs: sample.expiration_at_ms,
        productId: sample.product_id,
        lastEventMs: sample.event_timestamp_ms,
        lastEventIds: [sample.id],
      });
    });
  }

  test("CANCELLATION (unsubscribed) keeps premium to the end of the period", async () => {
    // The sample's app_user_id is anonymous; its alias is the uid.
    const fake = fakeStore();
    const sample = samples.CANCELLATION;
    await expect200(fake, sample, Reason.applied);
    assert.equal(doc(fake)?.premium, true);
    assert.equal(doc(fake)?.expiresAtMs, sample.expiration_at_ms);
  });

  test("CANCELLATION never shortens premium already known", async () => {
    const fake = fakeStore();
    const sample = samples.CANCELLATION;
    const later = sample.expiration_at_ms + 30 * day;
    await expect200(
      fake,
      event(samples.RENEWAL, {
        product_id: sample.product_id,
        expiration_at_ms: later,
        event_timestamp_ms: sample.event_timestamp_ms - hour,
      }),
      Reason.applied,
    );
    await expect200(fake, sample, Reason.applied);
    assert.equal(doc(fake)?.expiresAtMs, later);
  });

  test("a refund (CUSTOMER_SUPPORT) ends premium at once", async () => {
    const fake = fakeStore();
    const refund = samples.REFUND;
    await expect200(
      fake,
      event(samples.RENEWAL, {
        product_id: refund.product_id,
        expiration_at_ms: refund.event_timestamp_ms + 20 * day,
        event_timestamp_ms: refund.event_timestamp_ms - day,
      }),
      Reason.applied,
    );
    await expect200(fake, refund, Reason.applied);
    assert.equal(doc(fake)?.premium, false);
    assert.equal(doc(fake)?.expiresAtMs, refund.expiration_at_ms);
  });

  test("a refund of another product keeps the premium still running", async () => {
    const fake = fakeStore();
    const refund = samples.REFUND;
    const until = refund.event_timestamp_ms + 300 * day;
    await expect200(
      fake,
      event(samples.RENEWAL, {
        product_id: "com.revenuecat.myapp.yearly",
        expiration_at_ms: until,
        event_timestamp_ms: refund.event_timestamp_ms - day,
      }),
      Reason.applied,
    );
    await expect200(fake, refund, Reason.applied);
    assert.equal(doc(fake)?.premium, true);
    assert.equal(doc(fake)?.expiresAtMs, until);
  });

  test("EXPIRATION ends premium", async () => {
    const fake = fakeStore();
    const expiration = samples.EXPIRATION;
    await expect200(
      fake,
      event(samples.SUBSCRIPTION_EXTENDED, {
        event_timestamp_ms: expiration.event_timestamp_ms - 7 * day,
      }),
      Reason.applied,
    );
    await expect200(
      fake,
      event(expiration, { id: "expiration" }),
      Reason.applied,
    );
    assert.deepEqual(doc(fake), {
      premium: false,
      expiresAtMs: expiration.expiration_at_ms,
      productId: expiration.product_id,
      lastEventMs: expiration.event_timestamp_ms,
      lastEventIds: ["expiration"],
    });
  });

  test("EXPIRATION of another product keeps premium still running", async () => {
    // A plan switch: the old weekly product expires, the yearly runs on.
    const fake = fakeStore();
    const expiration = samples.EXPIRATION;
    const until = expiration.event_timestamp_ms + 300 * day;
    await expect200(
      fake,
      event(samples.RENEWAL, {
        product_id: "com.subscription.yearly",
        expiration_at_ms: until,
        event_timestamp_ms: expiration.event_timestamp_ms - day,
      }),
      Reason.applied,
    );
    await expect200(fake, expiration, Reason.applied);
    assert.equal(doc(fake)?.premium, true);
    assert.equal(doc(fake)?.expiresAtMs, until);
    assert.equal(doc(fake)?.productId, "com.subscription.yearly");
  });

  test("BILLING_ISSUE keeps premium through the grace period", async () => {
    const fake = fakeStore();
    const sample = samples.BILLING_ISSUE;
    await expect200(fake, sample, Reason.applied);
    assert.equal(doc(fake)?.premium, true);
    assert.equal(doc(fake)?.expiresAtMs, sample.grace_period_expiration_at_ms);
  });

  describe("BILLING_ISSUE and the billing error's CANCELLATION", () => {
    // No sample of a BILLING_ERROR cancellation exists: the CANCELLATION
    // sample with that documented reason, for the BILLING_ISSUE's period.
    const issue = samples.BILLING_ISSUE;
    const cancellation = event(samples.CANCELLATION, {
      cancel_reason: "BILLING_ERROR",
      product_id: issue.product_id,
      expiration_at_ms: issue.expiration_at_ms,
      event_timestamp_ms: issue.event_timestamp_ms + hour,
    });
    for (const [label, order] of [
      ["issue first", [issue, cancellation]],
      ["cancellation first", [cancellation, issue]],
    ] as const) {
      test(`keep premium until the grace period ends (${label})`, async () => {
        const fake = fakeStore();
        for (const payload of order) {
          await deliver(fake, post(webhookBody(payload)));
        }
        assert.equal(doc(fake)?.premium, true);
        assert.equal(
          doc(fake)?.expiresAtMs,
          issue.grace_period_expiration_at_ms,
        );
        assert.equal(doc(fake)?.lastEventMs, issue.event_timestamp_ms + hour);
      });
    }
  });

  test("PRODUCT_CHANGE stores the new product and never shortens", async () => {
    const fake = fakeStore();
    const change = samples.PRODUCT_CHANGE;
    const until = change.event_timestamp_ms + 20 * day;
    await expect200(
      fake,
      event(samples.RENEWAL, {
        product_id: change.product_id,
        expiration_at_ms: until,
        event_timestamp_ms: change.event_timestamp_ms - day,
      }),
      Reason.applied,
    );
    await expect200(fake, change, Reason.applied);
    assert.equal(doc(fake)?.productId, change.new_product_id);
    assert.equal(doc(fake)?.expiresAtMs, until);
  });

  test("NON_RENEWING_PURCHASE without an expiry never expires", async () => {
    const fake = fakeStore();
    await expect200(fake, samples.NON_RENEWING_PURCHASE, Reason.applied);
    assert.equal(doc(fake)?.premium, true);
    assert.equal(doc(fake)?.expiresAtMs, NEVER_EXPIRES_MS);
  });

  test("a refunded lifetime purchase loses premium", async () => {
    const fake = fakeStore();
    const purchase = samples.NON_RENEWING_PURCHASE;
    await expect200(fake, purchase, Reason.applied);
    await expect200(
      fake,
      event(samples.REFUND, {
        ...purchase,
        id: "refund",
        type: "CANCELLATION",
        cancel_reason: "CUSTOMER_SUPPORT",
        event_timestamp_ms: purchase.event_timestamp_ms + day,
      }),
      Reason.applied,
    );
    assert.equal(doc(fake)?.premium, false);
    assert.equal(doc(fake)?.expiresAtMs, purchase.event_timestamp_ms + day);
  });

  test("another type without an expiry is never lifetime", async () => {
    const fake = fakeStore();
    const renewal = event(samples.RENEWAL, { expiration_at_ms: null });
    await expect200(fake, renewal, Reason.noExpiry);
    assert.equal(fake.docs.size, 0);
    const known = samples.INITIAL_PURCHASE;
    await expect200(fake, known, Reason.applied);
    await expect200(
      fake,
      event(renewal, {
        id: "r2",
        event_timestamp_ms: known.event_timestamp_ms + 1,
      }),
      Reason.applied,
    );
    assert.equal(doc(fake)?.expiresAtMs, known.expiration_at_ms);
  });

  describe("TEMPORARY_ENTITLEMENT_GRANT", () => {
    const grant = samples.TEMPORARY_ENTITLEMENT_GRANT;

    test("grants premium for 24 hours from the event", async () => {
      const fake = fakeStore();
      await expect200(fake, grant, Reason.applied);
      assert.deepEqual(doc(fake), {
        premium: true,
        expiresAtMs: grant.event_timestamp_ms + TEMPORARY_GRANT_MS,
        lastEventMs: grant.event_timestamp_ms,
        lastEventIds: [grant.id],
      });
    });

    test("never shortens a later expiry", async () => {
      const fake = fakeStore();
      const until = grant.event_timestamp_ms + 30 * day;
      await expect200(
        fake,
        event(samples.RENEWAL, {
          expiration_at_ms: until,
          event_timestamp_ms: grant.event_timestamp_ms - day,
        }),
        Reason.applied,
      );
      await expect200(fake, grant, Reason.applied);
      assert.equal(doc(fake)?.expiresAtMs, until);
      assert.equal(doc(fake)?.productId, samples.RENEWAL.product_id);
    });

    test("an EXPIRATION after it ends premium", async () => {
      const fake = fakeStore();
      await expect200(fake, grant, Reason.applied);
      await expect200(
        fake,
        event(samples.EXPIRATION, {
          event_timestamp_ms: grant.event_timestamp_ms + hour,
          expiration_at_ms: grant.event_timestamp_ms + hour,
        }),
        Reason.applied,
      );
      assert.equal(doc(fake)?.premium, false);
    });
  });

  test("a product without the premium entitlement writes nothing", async () => {
    const fake = fakeStore();
    const sample = samples.INITIAL_PURCHASE;
    for (const ids of [null, ["pro"]]) {
      await expect200(
        fake,
        event(sample, { entitlement_ids: ids }),
        Reason.notPremium,
      );
    }
    await expect200(
      fake,
      event(samples.EXPIRATION, { entitlement_ids: ["pro"] }),
      Reason.notPremium,
    );
    assert.equal(fake.docs.size, 0);
  });

  test("sandbox purchases are applied like production ones", async () => {
    const fake = fakeStore();
    await expect200(
      fake,
      event(samples.INITIAL_PURCHASE, { environment: "SANDBOX" }),
      Reason.applied,
    );
    assert.equal(doc(fake)?.premium, true);
  });
});

describe("ordering and redelivery", () => {
  test("an older revocation or grant cannot undo a newer state", async () => {
    const fake = fakeStore();
    const expiration = samples.EXPIRATION;
    await expect200(fake, expiration, Reason.applied);
    await expect200(
      fake,
      event(samples.RENEWAL, {
        id: "late",
        event_timestamp_ms: expiration.event_timestamp_ms - day,
        expiration_at_ms: expiration.event_timestamp_ms + 6 * day,
      }),
      Reason.stale,
    );
    assert.equal(doc(fake)?.premium, false);
  });

  test("the same event delivered again is applied once", async () => {
    const fake = fakeStore();
    await expect200(fake, samples.INITIAL_PURCHASE, Reason.applied);
    const first = doc(fake);
    await expect200(fake, samples.INITIAL_PURCHASE, Reason.duplicate);
    assert.equal(doc(fake), first);
  });

  test("a redelivery after another event of its millisecond is still a no-op", async () => {
    const fake = fakeStore();
    const purchase = samples.INITIAL_PURCHASE;
    const twin = event(samples.EXPIRATION, {
      id: "twin",
      product_id: purchase.product_id,
      event_timestamp_ms: purchase.event_timestamp_ms,
    });
    await expect200(fake, purchase, Reason.applied);
    await expect200(fake, twin, Reason.applied);
    await expect200(fake, purchase, Reason.duplicate);
    await expect200(fake, twin, Reason.duplicate);
    assert.deepEqual(doc(fake)?.lastEventIds, [purchase.id, "twin"]);
  });

  describe("events of one millisecond end the same in either order", () => {
    const purchase = samples.INITIAL_PURCHASE;
    const at = purchase.event_timestamp_ms;
    const pairs: [string, Event, Event][] = [
      [
        "a purchase and an expiry",
        purchase,
        event(samples.EXPIRATION, {
          id: "expiry",
          product_id: purchase.product_id,
          event_timestamp_ms: at,
          expiration_at_ms: at,
        }),
      ],
      [
        "two products",
        purchase,
        event(purchase, {
          id: "other",
          product_id: "com.subscription.yearly",
          expiration_at_ms: purchase.expiration_at_ms,
        }),
      ],
    ];
    for (const [label, a, b] of pairs) {
      test(label, async () => {
        const ab = fakeStore();
        await expect200(ab, a, Reason.applied);
        await expect200(ab, b, Reason.applied);
        const ba = fakeStore();
        await expect200(ba, b, Reason.applied);
        await expect200(ba, a, Reason.applied);
        const [docAb, docBa] = [doc(ab), doc(ba)];
        assert.ok(docAb && docBa);
        const { lastEventIds: idsAb, ...stateAb } = docAb;
        const { lastEventIds: idsBa, ...stateBa } = docBa;
        assert.deepEqual(stateAb, stateBa);
        assert.deepEqual([...idsAb].sort(), [...idsBa].sort());
        assert.equal(stateAb.premium, true);
      });
    }
  });
});

describe("users", () => {
  test("anonymous RevenueCat ids are never written", async () => {
    const fake = fakeStore();
    await expect200(
      fake,
      event(samples.CANCELLATION, {
        aliases: [samples.CANCELLATION.original_app_user_id],
      }),
      Reason.noUser,
    );
    assert.equal(fake.docs.size, 0);
  });

  test("targetUid refuses to pick between two uids", () => {
    const parsed = parseEvent(
      webhookBody(
        event(samples.CANCELLATION, {
          aliases: ["u1", "u2"],
        }),
      ),
    );
    assert.ok(parsed);
    assert.equal(targetUid(parsed), undefined);
  });

  test("isUid refuses ids that cannot be a document id", () => {
    assert.ok(isUid("abcDEF123"));
    for (const id of ["", "a/b", "x".repeat(129), "$RCAnonymousID:1"]) {
      assert.ok(!isUid(id), id);
    }
  });

  test("a deleted account is not written, and what was left is deleted", async () => {
    const fake = fakeStore({ users: ["u2"] });
    // Left by an earlier delivery that failed after writing.
    fake.docs.set("u1", {
      premium: true,
      expiresAtMs: 1,
      lastEventMs: 0,
      lastEventIds: [],
    });
    await expect200(fake, samples.INITIAL_PURCHASE, Reason.deletedUser);
    assert.equal(fake.docs.size, 0);
    assert.deepEqual(fake.deleted, ["u1"]);
  });

  test("an account deleted while the event was written is cleaned up", async () => {
    const fake = fakeStore({ duringApply: (users) => users.delete("u1") });
    await expect200(fake, samples.INITIAL_PURCHASE, Reason.applied);
    assert.equal(fake.docs.size, 0);
  });
});

describe("TRANSFER", () => {
  const transfer = samples.TRANSFER;
  const purchase = samples.INITIAL_PURCHASE;

  test("moves premium from the old uid to the new one", async () => {
    const fake = fakeStore();
    await expect200(fake, purchase, Reason.applied);
    await expect200(fake, transfer, Reason.applied);
    assert.deepEqual(doc(fake, "u1"), {
      premium: false,
      expiresAtMs: purchase.expiration_at_ms,
      productId: purchase.product_id,
      lastEventMs: transfer.event_timestamp_ms,
      lastEventIds: [transfer.id],
    });
    assert.deepEqual(doc(fake, "u2"), {
      premium: true,
      expiresAtMs: purchase.expiration_at_ms,
      productId: purchase.product_id,
      lastEventMs: transfer.event_timestamp_ms,
      lastEventIds: [transfer.id],
    });
  });

  test("an older event for the old uid cannot grant it again", async () => {
    const fake = fakeStore();
    await expect200(fake, purchase, Reason.applied);
    await expect200(fake, transfer, Reason.applied);
    await expect200(fake, event(samples.RENEWAL, { id: "late" }), Reason.stale);
    assert.equal(doc(fake, "u1")?.premium, false);
  });

  test("keeps a later expiry the new uid already has", async () => {
    const fake = fakeStore();
    await expect200(fake, purchase, Reason.applied);
    const later = purchase.expiration_at_ms + 90 * day;
    await expect200(
      fake,
      event(purchase, {
        id: "u2-purchase",
        app_user_id: "u2",
        expiration_at_ms: later,
      }),
      Reason.applied,
    );
    await expect200(fake, transfer, Reason.applied);
    assert.equal(doc(fake, "u2")?.expiresAtMs, later);
  });

  test("from an anonymous id there is nothing known to move", async () => {
    const fake = fakeStore();
    await expect200(
      fake,
      event(transfer, { transferred_from: ["$RCAnonymousID:1"] }),
      Reason.nothingToTransfer,
    );
    assert.equal(fake.docs.size, 0);
  });

  test("only anonymous ids, or only deleted accounts, write nothing", async () => {
    const fake = fakeStore({ users: [] });
    await expect200(
      fake,
      event(transfer, {
        transferred_from: ["$RCAnonymousID:1"],
        transferred_to: [],
      }),
      Reason.noUser,
    );
    await expect200(fake, transfer, Reason.deletedUser);
    assert.deepEqual(fake.deleted.sort(), ["u1", "u2"]);
  });

  test("a deleted new owner gets nothing; the old one still loses it", async () => {
    const fake = fakeStore({ users: ["u1"] });
    await expect200(fake, purchase, Reason.applied);
    await expect200(
      fake,
      event(transfer, { transferred_to: ["u9"] }),
      Reason.applied,
    );
    assert.equal(doc(fake, "u1")?.premium, false);
    assert.ok(!fake.docs.has("u9"));
    assert.ok(fake.deleted.includes("u9"));
  });

  test("redelivered, it changes nothing", async () => {
    const fake = fakeStore();
    await expect200(fake, purchase, Reason.applied);
    await expect200(fake, transfer, Reason.applied);
    await expect200(fake, transfer, Reason.duplicate);
  });
});

describe("failures", () => {
  test("Auth or Firestore failing is a 500, so RevenueCat retries", async () => {
    for (const failing of ["userExists", "apply"] as const) {
      const fake = fakeStore({ failing });
      const response = await deliver(
        fake,
        post(webhookBody(samples.INITIAL_PURCHASE)),
      );
      assert.deepEqual(response, {
        status: 500,
        body: { reason: Reason.retry },
      });
    }
  });
});
