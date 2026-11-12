import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { Auth } from "firebase-admin/auth";
import { DocumentData, Firestore, Timestamp } from "firebase-admin/firestore";

import {
  NEVER_EXPIRES_MS,
  Plan,
  Reason,
  StoredEntitlement,
  firebaseEntitlementStore,
  revenueCatWebhookOf,
} from "./revenuecat_webhook";
import { samples, webhookBody } from "./revenuecat_webhook.samples";

/**
 * The part of Firestore the store uses, in memory. A transaction's writes
 * land only once its function has finished, so one that throws (or whose
 * write of [failingPath] throws) applies none.
 */
function fakeFirestore(failingPath?: string) {
  const data = new Map<string, DocumentData>();
  const reads: string[][] = [];
  const ref = (path: string) => ({
    path,
    async delete() {
      data.delete(path);
    },
  });
  type Ref = ReturnType<typeof ref>;
  const db = {
    collection: (name: string) => ({
      doc: (id: string) => ref(`${name}/${id}`),
    }),
    async runTransaction<T>(
      run: (transaction: unknown) => Promise<T>,
    ): Promise<T> {
      const pending = new Map<string, DocumentData>();
      const result = await run({
        async getAll(...refs: Ref[]) {
          reads.push(refs.map((r) => r.path));
          return refs.map((r) => ({ data: () => data.get(r.path) }));
        },
        set(r: Ref, document: DocumentData) {
          if (r.path === failingPath) throw new Error("write failed");
          pending.set(r.path, document);
        },
      });
      for (const [path, document] of pending) data.set(path, document);
      return result;
    },
  };
  return { db: db as unknown as Firestore, data, reads };
}

/** Auth with [uids]; [failing] makes every lookup fail. */
const fakeAuth = (uids: string[], failing = false) =>
  ({
    async getUser(uid: string) {
      if (failing) {
        throw Object.assign(new Error("down"), { code: "auth/internal-error" });
      }
      if (uids.includes(uid)) return { uid };
      throw Object.assign(new Error("none"), { code: "auth/user-not-found" });
    },
  }) as unknown as Pick<Auth, "getUser">;

const entitlement = (
  changes: Partial<StoredEntitlement> = {},
): StoredEntitlement => ({
  premium: true,
  expiresAtMs: 1_700_000_000_123,
  productId: "com.subscription.weekly",
  lastEventMs: 1_690_000_000_000,
  lastEventIds: ["evt-1"],
  ...changes,
});

const writing = (writes: [string, StoredEntitlement][]) => (): Plan => ({
  writes: new Map(writes),
  reason: Reason.applied,
});

describe("firebaseEntitlementStore", () => {
  test("writes expiresAt as a timestamp and reads it back the same", async () => {
    const { db, data, reads } = fakeFirestore();
    const store = firebaseEntitlementStore(db, fakeAuth([]));
    const written = entitlement();
    await store.apply(["u1"], writing([["u1", written]]));
    const stored = data.get("entitlements/u1");
    assert.ok(stored?.expiresAt instanceof Timestamp);
    assert.equal(stored.expiresAt.toMillis(), written.expiresAtMs);
    assert.equal(stored.premium, true);
    assert.equal(stored.productId, written.productId);
    assert.ok(!("expiresAtMs" in stored));

    let read: StoredEntitlement | undefined;
    await store.apply(["u1"], (map) => {
      read = map.get("u1");
      return { writes: new Map(), reason: Reason.stale };
    });
    assert.deepEqual(read, written);
    assert.deepEqual(reads, [["entitlements/u1"], ["entitlements/u1"]]);
  });

  test("the lifetime date round-trips", async () => {
    const { db, data } = fakeFirestore();
    const store = firebaseEntitlementStore(db, fakeAuth([]));
    await store.apply(
      ["u1"],
      writing([["u1", entitlement({ expiresAtMs: NEVER_EXPIRES_MS })]]),
    );
    const expiresAt = data.get("entitlements/u1")?.expiresAt as Timestamp;
    assert.equal(expiresAt.toDate().toISOString(), "9999-12-31T00:00:00.000Z");
  });

  test("an entitlement without a product writes no productId", async () => {
    const { db, data } = fakeFirestore();
    const store = firebaseEntitlementStore(db, fakeAuth([]));
    const { productId, ...withoutProduct } = entitlement();
    assert.ok(productId);
    await store.apply(["u1"], writing([["u1", withoutProduct]]));
    assert.ok(!("productId" in (data.get("entitlements/u1") ?? {})));
  });

  test("reads every uid in one getAll, absent documents as undefined", async () => {
    const { db, data, reads } = fakeFirestore();
    data.set("entitlements/u1", {
      premium: true,
      expiresAt: Timestamp.fromMillis(5),
      lastEventMs: 1,
      lastEventIds: ["a"],
    });
    const store = firebaseEntitlementStore(db, fakeAuth([]));
    let seen: Map<string, StoredEntitlement | undefined> | undefined;
    await store.apply(["u1", "u2"], (map) => {
      seen = map;
      return { writes: new Map(), reason: Reason.stale };
    });
    assert.deepEqual(reads, [["entitlements/u1", "entitlements/u2"]]);
    assert.deepEqual(seen?.get("u1"), {
      premium: true,
      expiresAtMs: 5,
      lastEventMs: 1,
      lastEventIds: ["a"],
    });
    assert.equal(seen?.get("u2"), undefined);
  });

  test("tells a missing user from an Auth failure", async () => {
    const { db } = fakeFirestore();
    const store = firebaseEntitlementStore(db, fakeAuth(["u1"]));
    assert.equal(await store.userExists("u1"), true);
    assert.equal(await store.userExists("u2"), false);
    const failing = firebaseEntitlementStore(db, fakeAuth([], true));
    await assert.rejects(failing.userExists("u1"));
  });

  test("delete removes the document, and nothing to delete is fine", async () => {
    const { db, data } = fakeFirestore();
    data.set("entitlements/u1", { premium: true });
    const store = firebaseEntitlementStore(db, fakeAuth([]));
    await store.delete("u1");
    await store.delete("u1");
    assert.equal(data.size, 0);
  });

  describe("a TRANSFER through the webhook", () => {
    const transfer = webhookBody(samples.TRANSFER);
    const later = Timestamp.fromMillis(samples.TRANSFER.event_timestamp_ms + 1);
    const request = {
      method: "POST",
      isJson: true,
      authorization: "secret",
      body: transfer,
    };

    test("writes both documents in one transaction", async () => {
      const { db, data, reads } = fakeFirestore();
      data.set("entitlements/u1", {
        premium: true,
        expiresAt: later,
        productId: "com.subscription.weekly",
        lastEventMs: 1,
        lastEventIds: ["a"],
      });
      const response = await revenueCatWebhookOf(request, {
        authorization: "secret",
        store: firebaseEntitlementStore(db, fakeAuth(["u1", "u2"])),
      });
      assert.equal(response.status, 200);
      assert.deepEqual(reads, [["entitlements/u1", "entitlements/u2"]]);
      assert.equal(data.get("entitlements/u1")?.premium, false);
      assert.equal(data.get("entitlements/u2")?.premium, true);
    });

    test("a failed write applies none of them and asks for a retry", async () => {
      const { db, data } = fakeFirestore("entitlements/u2");
      const before = {
        premium: true,
        expiresAt: later,
        productId: "com.subscription.weekly",
        lastEventMs: 1,
        lastEventIds: ["a"],
      };
      data.set("entitlements/u1", before);
      const response = await revenueCatWebhookOf(request, {
        authorization: "secret",
        store: firebaseEntitlementStore(db, fakeAuth(["u1", "u2"])),
      });
      assert.deepEqual(response, {
        status: 500,
        body: { reason: Reason.retry },
      });
      assert.equal(data.get("entitlements/u1"), before);
      assert.ok(!data.has("entitlements/u2"));
    });
  });
});
