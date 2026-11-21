import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { createTransport } from "nodemailer";

import { requireAdmin } from "./dashboard/run";

/** The Gmail app password of [SUPPORT_ADDRESS], for SMTP. */
export const supportGmailAppPassword = defineSecret(
  "SUPPORT_GMAIL_APP_PASSWORD",
);

/** Where every reply comes from; the user's answer comes back here. */
export const SUPPORT_ADDRESS = "getworkout.support@gmail.com";

/** The subject of every reply (the T1 board's). */
export const SUBJECT = "Re: Your message to GetWorkout";

/** The longest reply, in UTF-16 code units like Dart's `String.length`. */
export const MAX_REPLY = 5000;

/** A request id: a Firestore auto id or another short random token. */
const REQUEST_ID = /^[A-Za-z0-9_-]{8,64}$/;

/** `users/{uid}/feedback/{id}`, the only documents replied to. */
const THREAD_PATH = /^users\/[A-Za-z0-9_-]{1,128}\/feedback\/[A-Za-z0-9_-]{1,128}$/;

/**
 * Nodemailer error codes after which the mail was certainly not accepted:
 * the login failed, the address could not be resolved or the envelope was
 * refused before any data went out.
 */
const DEFINITE_CODES = new Set(["EAUTH", "EDNS", "EENVELOPE"]);

/**
 * Whether Gmail certainly did not accept the mail when sending threw
 * [error]: it said so with an SMTP reply code, or it failed before the mail
 * was handed over. Timeouts and dropped connections may hide an accepted
 * mail.
 */
export const isDefiniteRefusal = (error: unknown): boolean => {
  const { code, responseCode } = (error ?? {}) as {
    code?: unknown;
    responseCode?: unknown;
  };
  return (
    typeof responseCode === "number" ||
    (typeof code === "string" && DEFINITE_CODES.has(code))
  );
};

/** `details.reason` of a refusal, which the panel maps on. */
export const Reason = {
  notAdmin: "not-admin",
  invalidInput: "invalid-input",
  /** The thread does not exist. */
  noThread: "no-thread",
  /** The sender left no email, so there is nobody to reply to. */
  noEmail: "no-email",
  inProgress: "in-progress",
  requestIdReused: "request-id-reused",
  /** Gmail refused the mail; nothing was sent, a retry may send. */
  sendFailed: "send-failed",
  /** Gmail may have taken the mail; the reply stays `sending`. */
  outcomeUnknown: "outcome-unknown",
} as const;

/** What closes the thread after the reply, or leaves it replied. */
export type ThreadStatusAfter = "replied" | "closed";

export interface ReplyInput {
  requestId: string;
  threadPath: string;
  message: string;
  close: boolean;
}

/** `users/{uid}/feedback/{id}` as far as this function reads it. */
export interface StoredThread {
  email?: string;
  message: string;
}

/** `{threadPath}/replies/{requestId}` as far as this function reads it. */
export interface StoredReply {
  message: string;
  status: "sending" | "sent" | "failed";
  messageId?: string;
  /** `requestedAt` in milliseconds since the epoch. */
  requestedAtMillis?: number;
}

export interface Mail {
  from: string;
  to: string;
  subject: string;
  text: string;
}

/** What [ReplyStore.claim]'s decision says. */
export type Claim =
  | { kind: "send"; mail: Mail }
  | { kind: "sent"; messageId: string };

/** Who sends, as the reply records it. */
export interface Sender {
  uid: string;
  email: string | null;
}

export interface ReplyStore {
  /**
   * In one transaction: reads the thread and its reply [requestId] and
   * passes them to [decide]; for `send`, writes the reply as `sending`
   * with its message, `to`, `subject`, [sender] and the server time as
   * `requestedAt`. [decide] may throw, writing nothing.
   */
  claim(
    threadPath: string,
    requestId: string,
    message: string,
    sender: Sender,
    decide: (
      thread: StoredThread | undefined,
      reply: StoredReply | undefined,
    ) => Claim,
  ): Promise<Claim>;
  /**
   * In one batch: the reply `sent` with the SMTP message id and `sentAt`,
   * the thread [status] with `lastReplyAt` (both server time).
   */
  markSent(
    threadPath: string,
    requestId: string,
    messageId: string,
    status: ThreadStatusAfter,
  ): Promise<void>;
  /** Sets the reply `failed`: nothing was sent, so the id may send again. */
  markFailed(threadPath: string, requestId: string): Promise<void>;
}

/** Sends [mail]; the SMTP message id. */
export type Mailer = (mail: Mail) => Promise<string>;

export interface ReplyResult {
  id: string;
  messageId: string;
  /** This request id was sent before; nothing was sent now. */
  alreadySent: boolean;
}

const invalid = (field: string, message: string) =>
  new HttpsError("invalid-argument", message, {
    reason: Reason.invalidInput,
    field,
  });

/** The request, its message trimmed, or an `invalid-input` error. */
export function parseRequest(data: unknown): ReplyInput {
  const input = (typeof data === "object" && data !== null ? data : {}) as {
    [key: string]: unknown;
  };
  const { requestId, threadPath, message, close } = input;
  if (typeof requestId !== "string" || !REQUEST_ID.test(requestId)) {
    throw invalid(
      "requestId",
      "requestId must be 8-64 letters, digits, _ or -.",
    );
  }
  if (typeof threadPath !== "string" || !THREAD_PATH.test(threadPath)) {
    throw invalid("threadPath", "threadPath must be users/{uid}/feedback/{id}.");
  }
  const text = typeof message === "string" ? message.trim() : "";
  if (text.length === 0) throw invalid("message", "message is empty.");
  if (text.length > MAX_REPLY) {
    throw invalid("message", `message is longer than ${MAX_REPLY} characters.`);
  }
  if (close !== undefined && typeof close !== "boolean") {
    throw invalid("close", "close must be true or false.");
  }
  return { requestId, threadPath, message: text, close: close === true };
}

/** The reply above the user's message, quoted. */
export function mailText(reply: string, original: string): string {
  const quoted = original
    .split("\n")
    .map((line) => (line.length === 0 ? ">" : `> ${line}`))
    .join("\n");
  return `${reply}\n\nYou wrote:\n${quoted}\n`;
}

/**
 * What a request does given the thread and what is stored under its id:
 * a new or failed request sends; a sent one is not sent again; one being
 * sent, an id holding another message, a missing thread or one without an
 * email is refused.
 */
export function decideClaim(
  thread: StoredThread | undefined,
  reply: StoredReply | undefined,
  message: string,
): Claim {
  if (thread === undefined) {
    throw new HttpsError("not-found", "This thread does not exist.", {
      reason: Reason.noThread,
    });
  }
  const to = typeof thread.email === "string" ? thread.email : "";
  if (to.length === 0) {
    throw new HttpsError(
      "failed-precondition",
      "The sender left no email to reply to.",
      { reason: Reason.noEmail },
    );
  }
  const send: Claim = {
    kind: "send",
    mail: {
      from: SUPPORT_ADDRESS,
      to,
      subject: SUBJECT,
      text: mailText(message, thread.message),
    },
  };
  if (reply === undefined) return send;
  if (reply.message !== message) {
    throw new HttpsError(
      "invalid-argument",
      "This request id was used for another reply.",
      { reason: Reason.requestIdReused },
    );
  }
  switch (reply.status) {
    case "sent":
      return { kind: "sent", messageId: reply.messageId ?? "" };
    case "sending":
      // Also a send whose outcome is unknown; the panel tells them apart
      // by the age of the request.
      throw new HttpsError("already-exists", "This reply is being sent.", {
        reason: Reason.inProgress,
        requestedAt: reply.requestedAtMillis,
      });
    default:
      return send;
  }
}

/**
 * Emails the caller's reply to the thread's sender from [SUPPORT_ADDRESS],
 * once per request id, and keeps it on the thread, which becomes replied
 * or, with `close`, closed. A retry of a sent request answers with the
 * first send. Only a caller with the `admin` claim may reply.
 */
export async function sendSupportReplyOf(
  auth: CallableRequest["auth"],
  data: unknown,
  store: ReplyStore,
  mailer: Mailer,
): Promise<ReplyResult> {
  requireAdmin(auth);
  const { uid, token } = auth as NonNullable<typeof auth>;
  const sender: Sender = {
    uid,
    email: typeof token.email === "string" ? token.email : null,
  };
  const { requestId, threadPath, message, close } = parseRequest(data);
  const claim = await store.claim(
    threadPath,
    requestId,
    message,
    sender,
    (thread, reply) => decideClaim(thread, reply, message),
  );
  if (claim.kind === "sent") {
    return { id: requestId, messageId: claim.messageId, alreadySent: true };
  }
  const log = { threadPath, requestId };
  let messageId: string;
  try {
    messageId = await mailer(claim.mail);
  } catch (error) {
    if (!isDefiniteRefusal(error)) {
      // Gmail may have taken it: left `sending`, so no retry sends it again.
      logger.error("reply outcome unknown", { ...log, error: String(error) });
      throw new HttpsError(
        "unknown",
        "The reply may or may not have been sent.",
        { reason: Reason.outcomeUnknown },
      );
    }
    logger.error("reply not sent", { ...log, error: String(error) });
    await store.markFailed(threadPath, requestId).catch((markError: unknown) =>
      logger.error("failed reply not recorded", {
        ...log,
        error: String(markError),
      }),
    );
    throw new HttpsError("internal", "The reply was not sent.", {
      reason: Reason.sendFailed,
    });
  }
  // Sent: a failure to record it must not make the panel send it again.
  try {
    await store.markSent(
      threadPath,
      requestId,
      messageId,
      close ? "closed" : "replied",
    );
  } catch (error) {
    logger.error("reply sent, not recorded", {
      ...log,
      messageId,
      error: String(error),
    });
  }
  logger.info("reply sent", { ...log, messageId, by: sender.uid });
  return { id: requestId, messageId, alreadySent: false };
}

/** The Admin SDK behind [ReplyStore]. */
export const firebaseReplyStore = (): ReplyStore => {
  const db = getFirestore();
  const replyDoc = (threadPath: string, requestId: string) =>
    db.doc(threadPath).collection("replies").doc(requestId);
  return {
    claim: (threadPath, requestId, message, sender, decide) =>
      db.runTransaction(async (transaction) => {
        const doc = replyDoc(threadPath, requestId);
        const [thread, reply] = await Promise.all([
          transaction.get(db.doc(threadPath)),
          transaction.get(doc),
        ]);
        const replyData = reply.data();
        const requestedAt = replyData?.requestedAt;
        const claim = decide(
          thread.data() as StoredThread | undefined,
          replyData === undefined
            ? undefined
            : ({
                ...replyData,
                requestedAtMillis:
                  requestedAt instanceof Timestamp
                    ? requestedAt.toMillis()
                    : undefined,
              } as StoredReply),
        );
        if (claim.kind === "send") {
          transaction.set(doc, {
            message,
            to: claim.mail.to,
            subject: claim.mail.subject,
            status: "sending",
            sentBy: sender.uid,
            sentByEmail: sender.email,
            requestedAt: FieldValue.serverTimestamp(),
          });
        }
        return claim;
      }),
    async markSent(threadPath, requestId, messageId, status) {
      await db
        .batch()
        .update(replyDoc(threadPath, requestId), {
          status: "sent",
          messageId,
          sentAt: FieldValue.serverTimestamp(),
        })
        .update(db.doc(threadPath), {
          status,
          lastReplyAt: FieldValue.serverTimestamp(),
        })
        .commit();
    },
    async markFailed(threadPath, requestId) {
      await replyDoc(threadPath, requestId).update({ status: "failed" });
    },
  };
};

/** Gmail's SMTP server, signed in as [SUPPORT_ADDRESS]. */
const gmailMailer = (): Mailer => {
  const transport = createTransport({
    host: "smtp.gmail.com",
    port: 465,
    secure: true,
    auth: { user: SUPPORT_ADDRESS, pass: supportGmailAppPassword.value() },
  });
  return async (mail) => (await transport.sendMail(mail)).messageId;
};

export const sendSupportReply = onCall(
  { secrets: [supportGmailAppPassword] },
  (request) =>
    sendSupportReplyOf(
      request.auth,
      request.data,
      firebaseReplyStore(),
      gmailMailer(),
    ),
);
