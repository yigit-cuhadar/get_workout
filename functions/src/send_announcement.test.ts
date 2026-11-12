import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { TopicMessage } from "firebase-admin/messaging";
import { HttpsError } from "firebase-functions/v2/https";

import {
  AnnouncementStore,
  MAX_BODY,
  MAX_TITLE,
  Reason,
  StoredAnnouncement,
  sendAnnouncementOf,
} from "./send_announcement";

type Auth = Parameters<typeof sendAnnouncementOf>[0];

const caller = (claims: Record<string, unknown> = { admin: true }): Auth =>
  ({ uid: "admin1", token: claims, rawToken: "" }) as unknown as Auth;

const request = (overrides: Record<string, unknown> = {}) => ({
  requestId: "req_12345678",
  locale: "en",
  title: "New programs",
  body: "Three new programs are live.",
  ...overrides,
});

/**
 * `announcements` in memory, claimed as the Firestore transaction does;
 * [sendError] fails FCM.
 */
function fakeStore(sendError?: Error) {
  const docs = new Map<string, StoredAnnouncement & { sentBy: string }>();
  const sent: TopicMessage[] = [];
  const stored = (id: string) => {
    const doc = docs.get(id);
    assert.ok(doc, `no announcements/${id}`);
    return doc;
  };
  const store: AnnouncementStore = {
    async claim(id, sentBy, decide) {
      const claim = decide(docs.get(id));
      if (claim.kind === "send") {
        docs.set(id, { ...claim.announcement, status: "sending", sentBy });
      }
      return claim;
    },
    async markSent(id, messageId) {
      docs.set(id, { ...stored(id), status: "sent", messageId });
    },
    async markFailed(id) {
      docs.set(id, { ...stored(id), status: "failed" });
    },
    async send(message) {
      if (sendError) throw sendError;
      sent.push(message);
      return `projects/p/messages/${sent.length}`;
    },
  };
  return { store, docs, sent, stored };
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
    const result = await sendAnnouncementOf(
      caller(),
      request({
        title: "  New programs ",
        body: " Three new programs are live.\n",
      }),
      store,
    );
    assert.deepEqual(result, {
      id: "req_12345678",
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
        android: { notification: { channelId: "workout" } },
        apns: { payload: { aps: { sound: "default" } } },
      },
    ]);
    assert.deepEqual(docs.get("req_12345678"), {
      locale: "en",
      title: "New programs",
      body: "Three new programs are live.",
      status: "sent",
      sentBy: "admin1",
      messageId: "projects/p/messages/1",
    });
  });

  test("a request id sends once; a retry gets the first send", async () => {
    const { store, sent } = fakeStore();
    await sendAnnouncementOf(caller(), request(), store);
    const again = await sendAnnouncementOf(caller(), request(), store);
    assert.equal(sent.length, 1);
    assert.deepEqual(again, {
      id: "req_12345678",
      messageId: "projects/p/messages/1",
      alreadySent: true,
    });
  });

  test("refuses a request id being sent, or used for other text", async () => {
    const { store, docs, sent } = fakeStore();
    docs.set("req_12345678", {
      ...request(),
      status: "sending",
      sentBy: "admin1",
    });
    await assert.rejects(
      sendAnnouncementOf(caller(), request(), store),
      refusedWith("already-exists", Reason.inProgress),
    );
    await assert.rejects(
      sendAnnouncementOf(caller(), request({ title: "Other" }), store),
      refusedWith("invalid-argument", Reason.requestIdReused),
    );
    assert.equal(sent.length, 0);
  });

  test("a failed send is recorded and can be retried", async () => {
    const failing = fakeStore(new Error("fcm down"));
    await assert.rejects(
      sendAnnouncementOf(caller(), request(), failing.store),
      refusedWith("internal", Reason.sendFailed),
    );
    const failed = failing.stored("req_12345678");
    assert.equal(failed.status, "failed");

    const { store, docs, sent } = fakeStore();
    docs.set("req_12345678", failed);
    const result = await sendAnnouncementOf(caller(), request(), store);
    assert.equal(result.alreadySent, false);
    assert.equal(sent.length, 1);
    assert.equal(docs.get("req_12345678")?.status, "sent");
  });

  test("a send that was not recorded still succeeds", async () => {
    const { store, sent } = fakeStore();
    store.markSent = async () => {
      throw new Error("firestore down");
    };
    const result = await sendAnnouncementOf(caller(), request(), store);
    assert.equal(result.alreadySent, false);
    assert.equal(sent.length, 1);
  });

  test("refuses a caller signed out or without the admin claim", async () => {
    const { store, docs, sent } = fakeStore();
    await assert.rejects(
      sendAnnouncementOf(undefined, request(), store),
      (error: HttpsError) => error.code === "unauthenticated",
    );
    for (const claims of [{}, { admin: "true" }, { admin: false }]) {
      await assert.rejects(
        sendAnnouncementOf(caller(claims), request(), store),
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
    ];
    for (const [data, field] of cases) {
      await assert.rejects(
        sendAnnouncementOf(caller(), data, store),
        refusedWith("invalid-argument", Reason.invalidInput, field),
        `expected ${field} to be refused`,
      );
    }
    assert.equal(sent.length, 0);
    assert.equal(docs.size, 0);
  });

  test("accepts text at the length limits", async () => {
    const { store, sent } = fakeStore();
    await sendAnnouncementOf(
      caller(),
      request({ title: "t".repeat(MAX_TITLE), body: "b".repeat(MAX_BODY) }),
      store,
    );
    assert.equal(sent.length, 1);
  });
});
