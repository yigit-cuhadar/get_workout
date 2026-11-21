import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { HttpsError } from "firebase-functions/v2/https";

import {
  MAX_REPLY,
  Mail,
  Mailer,
  Reason,
  ReplyStore,
  StoredReply,
  StoredThread,
  isDefiniteRefusal,
  mailText,
  sendSupportReplyOf,
} from "./send_support_reply";

type Auth = Parameters<typeof sendSupportReplyOf>[0];

const caller = (claims: Record<string, unknown> = { admin: true }): Auth =>
  ({
    uid: "admin1",
    token: { email: "admin@example.com", ...claims },
    rawToken: "",
  }) as unknown as Auth;

const THREAD = "users/u1/feedback/f1";

const request = (overrides: Record<string, unknown> = {}) => ({
  requestId: "req_12345678",
  threadPath: THREAD,
  message: "Thanks for writing.",
  ...overrides,
});

/** An error as nodemailer throws it. */
const smtpError = (code: string, responseCode?: number) =>
  Object.assign(new Error(code), { code, responseCode });

type Reply = StoredReply & {
  to: string;
  subject: string;
  sentBy: string;
  sentByEmail: string | null;
};

/**
 * One thread and its replies in memory. A claim reads and writes with no
 * await in between, so like the Firestore transaction a second claimant of
 * an id sees the first one's `sending`. The mailer fails with
 * [options.sendError], and waits for [options.gate] when given.
 */
function fake(
  options: {
    thread?: StoredThread | null;
    sendError?: Error;
    gate?: Promise<void>;
  } = {},
) {
  const thread =
    options.thread === null
      ? undefined
      : (options.thread ?? {
          email: "person@example.com",
          message: "My program days moved.",
        });
  let threadStatus = "open";
  const replies = new Map<string, Reply>();
  const sent: Mail[] = [];
  const stored = (id: string) => {
    const reply = replies.get(id);
    assert.ok(reply, `no reply ${id}`);
    return reply;
  };
  const store: ReplyStore = {
    async claim(threadPath, requestId, message, sender, decide) {
      const claim = decide(
        threadPath === THREAD ? thread : undefined,
        replies.get(requestId),
      );
      if (claim.kind === "send") {
        replies.set(requestId, {
          message,
          to: claim.mail.to,
          subject: claim.mail.subject,
          status: "sending",
          sentBy: sender.uid,
          sentByEmail: sender.email,
          requestedAtMillis: 42,
        });
      }
      return claim;
    },
    async markSent(_, requestId, messageId, status) {
      replies.set(requestId, { ...stored(requestId), status: "sent", messageId });
      threadStatus = status;
    },
    async markFailed(_, requestId) {
      replies.set(requestId, { ...stored(requestId), status: "failed" });
    },
  };
  const mailer: Mailer = async (mail) => {
    await options.gate;
    if (options.sendError) throw options.sendError;
    sent.push(mail);
    return `<${sent.length}@smtp.gmail.com>`;
  };
  return {
    store,
    mailer,
    replies,
    sent,
    stored,
    threadStatus: () => threadStatus,
  };
}

const send = (auth: Auth, data: unknown, f: ReturnType<typeof fake>) =>
  sendSupportReplyOf(auth, data, f.store, f.mailer);

const refusedWith =
  (code: string, reason: string, field?: string) => (error: HttpsError) => {
    const details = error.details as { reason: string; field?: string };
    return (
      error.code === code &&
      details.reason === reason &&
      (field === undefined || details.field === field)
    );
  };

describe("sendSupportReplyOf", () => {
  test("emails the reply and keeps it on the thread, now replied", async () => {
    const f = fake();
    const result = await send(
      caller(),
      request({ message: "  Thanks for writing.\n" }),
      f,
    );
    assert.deepEqual(result, {
      id: "req_12345678",
      messageId: "<1@smtp.gmail.com>",
      alreadySent: false,
    });
    assert.deepEqual(f.sent, [
      {
        from: "getworkout.support@gmail.com",
        to: "person@example.com",
        subject: "Re: Your message to GetWorkout",
        text:
          "Thanks for writing.\n\nYou wrote:\n> My program days moved.\n",
      },
    ]);
    assert.deepEqual(f.replies.get("req_12345678"), {
      message: "Thanks for writing.",
      to: "person@example.com",
      subject: "Re: Your message to GetWorkout",
      status: "sent",
      sentBy: "admin1",
      sentByEmail: "admin@example.com",
      requestedAtMillis: 42,
      messageId: "<1@smtp.gmail.com>",
    });
    assert.equal(f.threadStatus(), "replied");
  });

  test("with close, the thread ends closed", async () => {
    const f = fake();
    await send(caller(), request({ close: true }), f);
    assert.equal(f.threadStatus(), "closed");
  });

  test("a request id sends once; a retry gets the first send", async () => {
    const f = fake();
    await send(caller(), request(), f);
    const again = await send(caller(), request(), f);
    assert.equal(f.sent.length, 1);
    assert.deepEqual(again, {
      id: "req_12345678",
      messageId: "<1@smtp.gmail.com>",
      alreadySent: true,
    });
  });

  test("two calls with one id at once send once", async () => {
    let release = () => {};
    const gate = new Promise<void>((resolve) => (release = resolve));
    const f = fake({ gate });
    const both = Promise.allSettled([
      send(caller(), request(), f),
      send(caller(), request(), f),
    ]);
    await new Promise((resolve) => setImmediate(resolve));
    release();
    const [first, second] = await both;
    assert.equal(f.sent.length, 1);
    assert.equal(first.status, "fulfilled");
    assert.ok(
      refusedWith("already-exists", Reason.inProgress)(
        (second as PromiseRejectedResult).reason,
      ),
    );
  });

  test("refuses an id being sent, or used for another reply", async () => {
    const f = fake();
    f.replies.set("req_12345678", {
      message: "Thanks for writing.",
      to: "person@example.com",
      subject: "",
      status: "sending",
      sentBy: "admin1",
      sentByEmail: null,
      requestedAtMillis: 42,
    });
    await assert.rejects(
      send(caller(), request(), f),
      (error: HttpsError) =>
        refusedWith("already-exists", Reason.inProgress)(error) &&
        (error.details as { requestedAt: number }).requestedAt === 42,
    );
    await assert.rejects(
      send(caller(), request({ message: "Other" }), f),
      refusedWith("invalid-argument", Reason.requestIdReused),
    );
    assert.equal(f.sent.length, 0);
  });

  test("refuses a missing thread or one without an email", async () => {
    for (const [thread, code, reason] of [
      [null, "not-found", Reason.noThread],
      [{ message: "Hi" }, "failed-precondition", Reason.noEmail],
      [{ message: "Hi", email: "" }, "failed-precondition", Reason.noEmail],
    ] as const) {
      const f = fake({ thread });
      await assert.rejects(
        send(caller(), request(), f),
        refusedWith(code, reason),
      );
      assert.equal(f.sent.length, 0);
      assert.equal(f.replies.size, 0);
    }
  });

  test("a certain SMTP refusal is recorded failed and retryable", async () => {
    for (const error of [
      smtpError("EAUTH", 535),
      smtpError("EENVELOPE", 550),
      smtpError("EMESSAGE", 552),
      smtpError("EDNS"),
    ]) {
      const failing = fake({ sendError: error });
      await assert.rejects(
        send(caller(), request(), failing),
        refusedWith("internal", Reason.sendFailed),
      );
      const failed = failing.stored("req_12345678");
      assert.equal(failed.status, "failed", error.message);

      const f = fake();
      f.replies.set("req_12345678", failed);
      const result = await send(caller(), request(), f);
      assert.equal(result.alreadySent, false);
      assert.equal(f.sent.length, 1);
      assert.equal(f.stored("req_12345678").status, "sent");
    }
  });

  test("an unclear SMTP error stays sending, never sent again", async () => {
    for (const error of [
      smtpError("ETIMEDOUT"),
      smtpError("ECONNECTION"),
      smtpError("ESOCKET"),
      new Error("socket hang up"),
    ]) {
      const f = fake({ sendError: error });
      await assert.rejects(
        send(caller(), request(), f),
        refusedWith("unknown", Reason.outcomeUnknown),
      );
      assert.equal(f.stored("req_12345678").status, "sending", error.message);
      await assert.rejects(
        send(caller(), request(), f),
        refusedWith("already-exists", Reason.inProgress),
      );
    }
  });

  test("a send that was not recorded still succeeds", async () => {
    const f = fake();
    f.store.markSent = async () => {
      throw new Error("firestore down");
    };
    const result = await send(caller(), request(), f);
    assert.equal(result.alreadySent, false);
    assert.equal(f.sent.length, 1);
  });

  test("refuses a caller signed out or without the admin claim", async () => {
    const f = fake();
    await assert.rejects(
      send(undefined, request(), f),
      (error: HttpsError) => error.code === "unauthenticated",
    );
    for (const claims of [{ admin: undefined }, { admin: "true" }, { admin: false }]) {
      await assert.rejects(
        send(caller(claims), request(), f),
        refusedWith("permission-denied", Reason.notAdmin),
      );
    }
    assert.equal(f.sent.length, 0);
    assert.equal(f.replies.size, 0);
  });

  test("refuses invalid input, naming the field", async () => {
    const f = fake();
    const cases: [unknown, string][] = [
      [null, "requestId"],
      [request({ requestId: "short" }), "requestId"],
      [request({ threadPath: undefined }), "threadPath"],
      [request({ threadPath: "users/u1" }), "threadPath"],
      [request({ threadPath: "users/u1/workouts/w1" }), "threadPath"],
      [request({ threadPath: "users/u1/feedback/f1/replies/r" }), "threadPath"],
      [request({ message: "   " }), "message"],
      [request({ message: 42 }), "message"],
      [request({ message: "x".repeat(MAX_REPLY + 1) }), "message"],
      [request({ close: "yes" }), "close"],
    ];
    for (const [data, field] of cases) {
      await assert.rejects(
        send(caller(), data, f),
        refusedWith("invalid-argument", Reason.invalidInput, field),
        `expected ${field} to be refused`,
      );
    }
    assert.equal(f.sent.length, 0);
  });

  test("accepts a reply at the length limit", async () => {
    const f = fake();
    await send(caller(), request({ message: "x".repeat(MAX_REPLY) }), f);
    assert.equal(f.sent.length, 1);
  });
});

describe("mailText", () => {
  test("quotes every line of the user's message", () => {
    assert.equal(
      mailText("Done.", "Line one\n\nLine two"),
      "Done.\n\nYou wrote:\n> Line one\n>\n> Line two\n",
    );
  });
});

describe("isDefiniteRefusal", () => {
  test("only an SMTP reply code or a failure before handing over", () => {
    assert.equal(isDefiniteRefusal(smtpError("EMESSAGE", 421)), true);
    assert.equal(isDefiniteRefusal(smtpError("EAUTH")), true);
    assert.equal(isDefiniteRefusal(smtpError("ETIMEDOUT")), false);
    assert.equal(isDefiniteRefusal(null), false);
  });
});
