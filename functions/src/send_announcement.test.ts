import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { MulticastMessage, TopicMessage } from "firebase-admin/messaging";
import { HttpsError } from "firebase-functions/v2/https";

import { NOT_SCHEDULED, cancelAnnouncementOf } from "./cancel_announcement";
import {
  AnnouncementStore,
  MAX_BODY,
  MAX_SCHEDULE_AHEAD_MS,
  MAX_TITLE,
  MIN_SCHEDULE_AHEAD_MS,
  Reason,
  StoredAnnouncement,
  TIME_TO_LIVE_SECONDS,
  sendAnnouncementOf,
} from "./send_announcement";
import { sendScheduledOf } from "./send_scheduled_announcement";

/** Seconds; the functions take milliseconds. */
const now = 1_000_000;
const nowMs = now * 1000;

type Auth = Parameters<typeof sendAnnouncementOf>[0];

const caller = (
  claims: Record<string, unknown> = { admin: true, email: "a@x.com" },
): Auth => ({ uid: "admin1", token: claims, rawToken: "" }) as unknown as Auth;

const request = (overrides: Record<string, unknown> = {}) => ({
  requestId: "req_12345678",
  locale: "en",
  title: "New programs",
  body: "Three new programs are live.",
  ...overrides,
});

const send = (auth: Auth, data: unknown, store: AnnouncementStore) =>
  sendAnnouncementOf(auth, data, store, nowMs);

/** An error as the Admin SDK's messaging throws it. */
const fcmError = (code: string) =>
  Object.assign(new Error(code), { code: `messaging/${code}` });

type Doc = StoredAnnouncement & {
  sentBy: string;
  senderEmail?: string;
  cancelledBy?: string;
};

/**
 * `announcements`, the devices' tokens and the task queue in memory. A
 * claim reads and writes with no await in between, so like the Firestore
 * transaction a second claimant of an id sees the first one's `sending`.
 * FCM fails with [options.sendError], and waits for [options.gate] when
 * given; the queue fails with [options.queueError].
 */
function fakeStore(
  options: {
    sendError?: Error;
    gate?: Promise<void>;
    queueError?: Error;
    tokens?: Record<string, string[]>;
  } = {},
) {
  const docs = new Map<string, Doc>();
  const sent: TopicMessage[] = [];
  const multicasts: MulticastMessage[] = [];
  const tasks = new Map<string, number>();
  const stored = (id: string) => {
    const doc = docs.get(id);
    assert.ok(doc, `no announcements/${id}`);
    return doc;
  };
  const store: AnnouncementStore = {
    async claim(id, sender, decide) {
      const claim = decide(docs.get(id));
      if (claim.kind === "send" || claim.kind === "schedule") {
        docs.set(id, {
          ...claim.announcement,
          status: claim.kind === "send" ? "sending" : "scheduled",
          ...(claim.kind === "schedule"
            ? { scheduledForMillis: claim.scheduledForMillis }
            : {}),
          sentBy: sender.uid,
          ...(sender.email ? { senderEmail: sender.email } : {}),
          requestedAtMillis: nowMs,
        });
      }
      return claim;
    },
    async claimScheduled(id) {
      const doc = docs.get(id);
      if (doc?.status !== "scheduled") return undefined;
      docs.set(id, { ...doc, status: "sending" });
      const { locale, title, body, audience } = doc;
      return { locale, title, body, audience };
    },
    async cancel(id, by, decide) {
      if (decide(docs.get(id))) {
        docs.set(id, { ...stored(id), status: "cancelled", cancelledBy: by });
      }
    },
    async markSent(id, messageId) {
      docs.set(id, { ...stored(id), status: "sent", messageId });
    },
    async markFailed(id) {
      docs.set(id, { ...stored(id), status: "failed" });
    },
    async send(message) {
      await options.gate;
      if (options.sendError) throw options.sendError;
      sent.push(message);
      return `projects/p/messages/${sent.length}`;
    },
    async deviceTokens(uid) {
      return options.tokens?.[uid] ?? [];
    },
    async sendToDevices(message) {
      if (options.sendError) throw options.sendError;
      multicasts.push(message);
      const bad = message.tokens.filter((t) => t.startsWith("stale")).length;
      return {
        successCount: message.tokens.length - bad,
        failureCount: bad,
      };
    },
    async enqueue(id, atMillis) {
      if (options.queueError) throw options.queueError;
      tasks.set(id, atMillis);
    },
    async deleteTask(id) {
      tasks.delete(id);
    },
  };
  return { store, docs, sent, multicasts, tasks, stored };
}

const refusedWith =
  (code: string, reason: string, field?: string) => (error: HttpsError) => {
    const details = error.details as { reason: string; field?: string };
    return (
      error.code === code &&
      details.reason === reason &&
      (field === undefined || details.field === field)
    );
  };

describe("sendAnnouncementOf", () => {
  test("sends a notification message to the language's topic", async () => {
    const { store, docs, sent } = fakeStore();
    const result = await send(
      caller(),
      request({
        title: "  New programs ",
        body: " Three new programs are live.\n",
      }),
      store,
    );
    assert.deepEqual(result, {
      id: "req_12345678",
      status: "sent",
      messageId: "projects/p/messages/1",
      alreadySent: false,
    });
    assert.deepEqual(sent, [
      {
        topic: "announcements_en",
        notification: {
          title: "New programs",
          body: "Three new programs are live.",
        },
        android: {
          ttl: 3 * 24 * 60 * 60 * 1000,
          notification: { channelId: "workout" },
        },
        apns: {
          headers: { "apns-expiration": `${now + 3 * 24 * 60 * 60}` },
          payload: { aps: { sound: "default" } },
        },
      },
    ]);
    assert.equal(TIME_TO_LIVE_SECONDS, 3 * 24 * 60 * 60);
    assert.deepEqual(docs.get("req_12345678"), {
      locale: "en",
      title: "New programs",
      body: "Three new programs are live.",
      audience: "everyone",
      status: "sent",
      sentBy: "admin1",
      senderEmail: "a@x.com",
      requestedAtMillis: nowMs,
      messageId: "projects/p/messages/1",
    });
  });

  test("a request id sends once; a retry gets the first send", async () => {
    const { store, sent } = fakeStore();
    await send(caller(), request(), store);
    const again = await send(caller(), request(), store);
    assert.equal(sent.length, 1);
    assert.deepEqual(again, {
      id: "req_12345678",
      status: "sent",
      messageId: "projects/p/messages/1",
      alreadySent: true,
    });
  });

  test("two calls with one id at once send once", async () => {
    let release = () => {};
    const gate = new Promise<void>((resolve) => (release = resolve));
    const { store, sent } = fakeStore({ gate });
    const both = Promise.allSettled([
      send(caller(), request(), store),
      send(caller(), request(), store),
    ]);
    await new Promise((resolve) => setImmediate(resolve));
    release();
    const [first, second] = await both;
    assert.equal(sent.length, 1);
    assert.equal(first.status, "fulfilled");
    assert.equal(second.status, "rejected");
    assert.ok(
      refusedWith("already-exists", Reason.inProgress)(
        (second as PromiseRejectedResult).reason,
      ),
    );
  });

  test("refuses a request id being sent, or used for other text", async () => {
    const { store, docs, sent } = fakeStore();
    docs.set("req_12345678", {
      locale: "en",
      title: "New programs",
      body: "Three new programs are live.",
      audience: "everyone",
      status: "sending",
      sentBy: "admin1",
      requestedAtMillis: 42,
    });
    await assert.rejects(
      send(caller(), request(), store),
      (error: HttpsError) =>
        refusedWith("already-exists", Reason.inProgress)(error) &&
        (error.details as { requestedAt: number }).requestedAt === 42,
    );
    await assert.rejects(
      send(caller(), request({ title: "Other" }), store),
      refusedWith("invalid-argument", Reason.requestIdReused),
    );
    assert.equal(sent.length, 0);
  });

  test("a certain FCM refusal is recorded failed and retryable", async () => {
    for (const code of [
      "invalid-argument",
      "mismatched-credential",
      "authentication-error",
      "third-party-auth-error",
      "message-rate-exceeded",
    ]) {
      const failing = fakeStore({ sendError: fcmError(code) });
      await assert.rejects(
        send(caller(), request(), failing.store),
        refusedWith("internal", Reason.sendFailed),
      );
      const failed = failing.stored("req_12345678");
      assert.equal(failed.status, "failed", code);

      const { store, docs, sent } = fakeStore();
      docs.set("req_12345678", failed);
      const result = await send(caller(), request(), store);
      assert.equal(result.status, "sent");
      assert.equal(sent.length, 1);
      assert.equal(docs.get("req_12345678")?.status, "sent");
    }
  });

  test("an unclear FCM error stays sending, never sent again", async () => {
    for (const error of [
      fcmError("internal-error"),
      fcmError("server-unavailable"),
      fcmError("unknown-error"),
      Object.assign(new Error("timeout"), { code: "ETIMEDOUT" }),
      new Error("socket hang up"),
    ]) {
      const { store, stored } = fakeStore({ sendError: error });
      await assert.rejects(
        send(caller(), request(), store),
        refusedWith("unknown", Reason.outcomeUnknown),
      );
      assert.equal(stored("req_12345678").status, "sending", error.message);
      await assert.rejects(
        send(caller(), request(), store),
        refusedWith("already-exists", Reason.inProgress),
      );
    }
  });

  test("a send that was not recorded still succeeds", async () => {
    const { store, sent } = fakeStore();
    store.markSent = async () => {
      throw new Error("firestore down");
    };
    const result = await send(caller(), request(), store);
    assert.equal(result.status, "sent");
    assert.equal(sent.length, 1);
  });

  test("refuses a caller signed out or without the admin claim", async () => {
    const { store, docs, sent } = fakeStore();
    await assert.rejects(
      send(undefined, request(), store),
      (error: HttpsError) => error.code === "unauthenticated",
    );
    for (const claims of [{}, { admin: "true" }, { admin: false }]) {
      await assert.rejects(
        send(caller(claims), request(), store),
        refusedWith("permission-denied", Reason.notAdmin),
      );
    }
    assert.equal(sent.length, 0);
    assert.equal(docs.size, 0);
  });

  test("refuses invalid input, naming the field", async () => {
    const { store, docs, sent } = fakeStore();
    const cases: [unknown, string][] = [
      [null, "requestId"],
      [request({ requestId: undefined }), "requestId"],
      [request({ requestId: "short" }), "requestId"],
      [request({ requestId: "has/slash_123" }), "requestId"],
      [request({ locale: "de" }), "locale"],
      [request({ locale: undefined }), "locale"],
      [request({ title: "   " }), "title"],
      [request({ title: 42 }), "title"],
      [request({ title: "x".repeat(MAX_TITLE + 1) }), "title"],
      [request({ body: "" }), "body"],
      [request({ body: "x".repeat(MAX_BODY + 1) }), "body"],
      [request({ audience: "vip" }), "audience"],
      [request({ scheduleAt: "tomorrow" }), "scheduleAt"],
      [request({ scheduleAt: nowMs + MIN_SCHEDULE_AHEAD_MS - 1 }), "scheduleAt"],
      [request({ scheduleAt: nowMs + MAX_SCHEDULE_AHEAD_MS + 1 }), "scheduleAt"],
      [request({ scheduleAt: nowMs + 3_600_000.5 }), "scheduleAt"],
      [request({ test: "yes" }), "test"],
      [request({ test: true, scheduleAt: nowMs + 3_600_000 }), "scheduleAt"],
    ];
    for (const [data, field] of cases) {
      await assert.rejects(
        send(caller(), data, store),
        refusedWith("invalid-argument", Reason.invalidInput, field),
        `expected ${field} to be refused`,
      );
    }
    assert.equal(sent.length, 0);
    assert.equal(docs.size, 0);
  });

  test("accepts text at the length limits", async () => {
    const { store, sent } = fakeStore();
    await send(
      caller(),
      request({ title: "t".repeat(MAX_TITLE), body: "b".repeat(MAX_BODY) }),
      store,
    );
    assert.equal(sent.length, 1);
  });
});

describe("sendAnnouncementOf, audiences and tests", () => {
  test("free and premium go to their topics, everyone to the plain one", async () => {
    for (const [audience, topic] of [
      ["everyone", "announcements_en"],
      ["free", "announcements_en_free"],
      ["premium", "announcements_en_premium"],
    ]) {
      const { store, sent, stored } = fakeStore();
      await send(caller(), request({ audience }), store);
      assert.equal(sent[0].topic, topic);
      assert.equal(stored("req_12345678").audience, audience);
    }
  });

  test("the same id for another audience is another request", async () => {
    const { store } = fakeStore();
    await send(caller(), request({ audience: "free" }), store);
    await assert.rejects(
      send(caller(), request({ audience: "premium" }), store),
      refusedWith("invalid-argument", Reason.requestIdReused),
    );
  });

  test("an old row without audience counts as everyone", async () => {
    const { store, docs, sent } = fakeStore();
    docs.set("req_12345678", {
      locale: "en",
      title: "New programs",
      body: "Three new programs are live.",
      status: "failed",
      sentBy: "admin1",
    } as Doc);
    await send(caller(), request(), store);
    assert.equal(sent.length, 1);
  });

  test("records no email for a caller without one", async () => {
    const { store, stored } = fakeStore();
    await send(caller({ admin: true }), request(), store);
    assert.equal(stored("req_12345678").senderEmail, undefined);
  });

  test("a test goes to the caller's devices only, unrecorded", async () => {
    const { store, docs, sent, multicasts } = fakeStore({
      tokens: { admin1: ["t1", "stale1"], other: ["t9"] },
    });
    const result = await send(
      caller(),
      request({ requestId: undefined, test: true, audience: "premium" }),
      store,
    );
    assert.deepEqual(result, { status: "test", delivered: 1, failed: 1 });
    assert.equal(sent.length, 0);
    assert.equal(docs.size, 0);
    assert.deepEqual(multicasts[0].tokens, ["t1", "stale1"]);
    assert.deepEqual(multicasts[0].notification, {
      title: "New programs",
      body: "Three new programs are live.",
    });
    assert.equal(multicasts[0].android?.notification?.channelId, "workout");
  });

  test("a test without devices, or reaching none, fails", async () => {
    await assert.rejects(
      send(caller(), request({ test: true }), fakeStore().store),
      refusedWith("failed-precondition", Reason.noDevices),
    );
    await assert.rejects(
      send(
        caller(),
        request({ test: true }),
        fakeStore({ tokens: { admin1: ["stale1"] } }).store,
      ),
      refusedWith("internal", Reason.sendFailed),
    );
    await assert.rejects(
      send(
        caller(),
        request({ test: true }),
        fakeStore({ tokens: { admin1: ["t1"] }, sendError: new Error("x") })
          .store,
      ),
      refusedWith("internal", Reason.sendFailed),
    );
  });

  test("a test needs the admin claim", async () => {
    const { store, multicasts } = fakeStore({ tokens: { admin1: ["t1"] } });
    await assert.rejects(
      send(caller({}), request({ test: true }), store),
      refusedWith("permission-denied", Reason.notAdmin),
    );
    assert.equal(multicasts.length, 0);
  });
});

describe("scheduled announcements", () => {
  const at = nowMs + 3_600_000;

  test("is stored scheduled with a task, nothing sent", async () => {
    const { store, sent, tasks, stored } = fakeStore();
    const result = await send(
      caller(),
      request({ scheduleAt: at, audience: "free" }),
      store,
    );
    assert.deepEqual(result, {
      id: "req_12345678",
      status: "scheduled",
      scheduledFor: at,
      alreadySent: false,
    });
    assert.equal(sent.length, 0);
    assert.deepEqual([...tasks], [["req_12345678", at]]);
    assert.equal(stored("req_12345678").status, "scheduled");
    assert.equal(stored("req_12345678").scheduledForMillis, at);
  });

  test("a retry is answered without a second task", async () => {
    const { store, tasks } = fakeStore();
    await send(caller(), request({ scheduleAt: at }), store);
    tasks.clear();
    const again = await send(caller(), request({ scheduleAt: at }), store);
    assert.deepEqual(again, {
      id: "req_12345678",
      status: "scheduled",
      scheduledFor: at,
      alreadySent: true,
    });
    assert.equal(tasks.size, 0);
    await assert.rejects(
      send(caller(), request({ scheduleAt: at + 60_000 }), store),
      refusedWith("invalid-argument", Reason.requestIdReused),
    );
  });

  test("a task that was not created leaves it failed, retryable", async () => {
    const failing = fakeStore({ queueError: new Error("no queue") });
    await assert.rejects(
      send(caller(), request({ scheduleAt: at }), failing.store),
      refusedWith("internal", Reason.scheduleFailed),
    );
    const failed = failing.stored("req_12345678");
    assert.equal(failed.status, "failed");

    const { store, docs, tasks } = fakeStore();
    docs.set("req_12345678", failed);
    await send(caller(), request({ scheduleAt: at }), store);
    assert.equal(tasks.size, 1);
  });

  test("the task sends it once, to its audience's topic", async () => {
    const { store, sent, stored } = fakeStore();
    await send(
      caller(),
      request({ scheduleAt: at, audience: "premium" }),
      store,
    );
    await sendScheduledOf({ id: "req_12345678" }, store, at);
    await sendScheduledOf({ id: "req_12345678" }, store, at);
    assert.equal(sent.length, 1);
    assert.equal(sent[0].topic, "announcements_en_premium");
    assert.equal(
      sent[0].apns?.headers?.["apns-expiration"],
      `${at / 1000 + TIME_TO_LIVE_SECONDS}`,
    );
    const doc = stored("req_12345678");
    assert.equal(doc.status, "sent");
    assert.equal(doc.senderEmail, "a@x.com");
  });

  test("the task records a failed send and does not throw", async () => {
    const refused = fakeStore({ sendError: fcmError("invalid-argument") });
    await send(caller(), request({ scheduleAt: at }), refused.store);
    await sendScheduledOf({ id: "req_12345678" }, refused.store, at);
    assert.equal(refused.stored("req_12345678").status, "failed");

    const unclear = fakeStore({ sendError: fcmError("internal-error") });
    await send(caller(), request({ scheduleAt: at }), unclear.store);
    await sendScheduledOf({ id: "req_12345678" }, unclear.store, at);
    assert.equal(unclear.stored("req_12345678").status, "sending");
  });

  test("the task skips a missing id, or one not scheduled", async () => {
    const { store, sent } = fakeStore();
    await sendScheduledOf({}, store, at);
    await sendScheduledOf({ id: "req_nothing1" }, store, at);
    assert.equal(sent.length, 0);
  });

  test("a claim that fails throws, so Cloud Tasks retries", async () => {
    const { store } = fakeStore();
    store.claimScheduled = async () => {
      throw new Error("firestore down");
    };
    await assert.rejects(sendScheduledOf({ id: "req_12345678" }, store, at));
  });
});

describe("cancelAnnouncementOf", () => {
  const at = nowMs + 3_600_000;

  test("cancels a scheduled one: marked, task gone, never sent", async () => {
    const { store, sent, tasks, stored } = fakeStore();
    await send(caller(), request({ scheduleAt: at }), store);
    assert.deepEqual(
      await cancelAnnouncementOf(caller(), { id: "req_12345678" }, store),
      { id: "req_12345678" },
    );
    assert.equal(stored("req_12345678").status, "cancelled");
    assert.equal(stored("req_12345678").cancelledBy, "admin1");
    assert.equal(tasks.size, 0);
    await sendScheduledOf({ id: "req_12345678" }, store, at);
    assert.equal(sent.length, 0);
    // Cancelling again is a retry; sending the id again is refused.
    await cancelAnnouncementOf(caller(), { id: "req_12345678" }, store);
    await assert.rejects(
      send(caller(), request({ scheduleAt: at }), store),
      refusedWith("failed-precondition", Reason.cancelled),
    );
  });

  test("a task left behind still cancels", async () => {
    const { store, stored } = fakeStore();
    await send(caller(), request({ scheduleAt: at }), store);
    store.deleteTask = async () => {
      throw new Error("tasks down");
    };
    await cancelAnnouncementOf(caller(), { id: "req_12345678" }, store);
    assert.equal(stored("req_12345678").status, "cancelled");
  });

  test("refuses one sent, sending or missing", async () => {
    const { store, docs } = fakeStore();
    await send(caller(), request(), store);
    await assert.rejects(
      cancelAnnouncementOf(caller(), { id: "req_12345678" }, store),
      refusedWith("failed-precondition", NOT_SCHEDULED),
    );
    await assert.rejects(
      cancelAnnouncementOf(caller(), { id: "req_missing1" }, store),
      refusedWith("not-found", NOT_SCHEDULED),
    );
    assert.equal(docs.get("req_12345678")?.status, "sent");
  });

  test("refuses a non-admin or a bad id", async () => {
    const { store } = fakeStore();
    await assert.rejects(
      cancelAnnouncementOf(caller({}), { id: "req_12345678" }, store),
      refusedWith("permission-denied", Reason.notAdmin),
    );
    await assert.rejects(
      cancelAnnouncementOf(caller(), { id: "x" }, store),
      refusedWith("invalid-argument", Reason.invalidInput, "id"),
    );
  });
});
