import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { getFunctions } from "firebase-admin/functions";
import {
  BaseMessage,
  MulticastMessage,
  TopicMessage,
  getMessaging,
} from "firebase-admin/messaging";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

import { REGION } from "./config";

/** The languages announcements can go to; the app's (`languages`). */
export const LOCALES = ["en"];

/**
 * Who an announcement goes to. The app follows `announcements_<locale>`
 * and the topic of its Premium state, `announcements_<locale>_free` or
 * `_premium` (FollowAnnouncements); everyone stays on the plain
 * topic, which app versions before the split also follow.
 */
export const AUDIENCES = ["everyone", "free", "premium"] as const;
export type Audience = (typeof AUDIENCES)[number];

/**
 * Longest title and body, in UTF-16 code units like Dart's `String.length`
 * (the panel counts the same). Longer text is cut off on most lock screens.
 */
export const MAX_TITLE = 65;
export const MAX_BODY = 240;

/**
 * How far ahead an announcement may be scheduled: at least a minute, so it
 * is never due before its task exists, and at most Cloud Tasks' 30 days.
 */
export const MIN_SCHEDULE_AHEAD_MS = 60 * 1000;
export const MAX_SCHEDULE_AHEAD_MS = 30 * 24 * 60 * 60 * 1000;

/** The Android channel every notification of the app uses. */
export const ANDROID_CHANNEL = "workout";

/**
 * How long FCM keeps trying to deliver an announcement to a device that is
 * offline; after that a dated announcement is dropped, not shown late.
 */
export const TIME_TO_LIVE_SECONDS = 3 * 24 * 60 * 60;

/** The task queue function that sends scheduled announcements. */
export const SCHEDULED_FUNCTION = "sendScheduledAnnouncement";

/**
 * FCM error codes (`messaging/<code>`) after which FCM certainly did not
 * accept the message, so sending the request again cannot duplicate it.
 * Any other error (timeouts, `internal-error`, `server-unavailable`,
 * unknown) may hide an accepted message.
 */
const DEFINITE_REFUSALS = new Set([
  "invalid-argument",
  "invalid-recipient",
  "invalid-payload",
  "invalid-data-payload-key",
  "payload-size-limit-exceeded",
  "invalid-options",
  "invalid-package-name",
  "mismatched-credential",
  "authentication-error",
  "third-party-auth-error",
  "message-rate-exceeded",
  "topics-message-rate-exceeded",
  "device-message-rate-exceeded",
]);

/** Whether FCM certainly did not accept the message when it threw [error]. */
export const isDefiniteRefusal = (error: unknown): boolean => {
  const code = (error as { code?: unknown } | null)?.code;
  return (
    typeof code === "string" &&
    code.startsWith("messaging/") &&
    DEFINITE_REFUSALS.has(code.slice("messaging/".length))
  );
};

/** A request id: a Firestore auto id or another short random token. */
export const REQUEST_ID = /^[A-Za-z0-9_-]{8,64}$/;

/**
 * `details.reason` of a refusal, which the panel maps on (never the
 * message).
 */
export const Reason = {
  notAdmin: "not-admin",
  invalidInput: "invalid-input",
  inProgress: "in-progress",
  requestIdReused: "request-id-reused",
  /** FCM refused the message; nothing was sent, a retry may send. */
  sendFailed: "send-failed",
  /**
   * FCM may or may not have accepted the message; the request stays
   * `sending` and is never sent again.
   */
  outcomeUnknown: "outcome-unknown",
  /** The task was not created; nothing is scheduled, a retry may. */
  scheduleFailed: "schedule-failed",
  /** The request id was cancelled; it is never sent. */
  cancelled: "cancelled",
  /** A test send: the caller has no device with a push token. */
  noDevices: "no-devices",
} as const;

export interface Announcement {
  locale: string;
  title: string;
  body: string;
  audience: Audience;
}

export type AnnouncementStatus =
  | "scheduled"
  | "sending"
  | "sent"
  | "failed"
  | "cancelled";

/** `announcements/{requestId}` as far as these functions read it. */
export interface StoredAnnouncement extends Announcement {
  status: AnnouncementStatus;
  messageId?: string;
  /** `requestedAt` in milliseconds since the epoch. */
  requestedAtMillis?: number;
  /** `scheduledFor` in milliseconds; only on a scheduled request. */
  scheduledForMillis?: number;
}

/** The admin making a request, as recorded on it. */
export interface Sender {
  uid: string;
  /** From the ID token; absent for an account without one. */
  email?: string;
}

/** What [AnnouncementStore.claim]'s decision says. */
export type Claim =
  | { kind: "send"; announcement: Announcement }
  | {
      kind: "schedule";
      announcement: Announcement;
      scheduledForMillis: number;
    }
  | { kind: "sent"; messageId: string }
  | { kind: "scheduled"; scheduledForMillis: number };

export interface AnnouncementStore {
  /**
   * In one transaction: reads `announcements/{id}` and passes it to
   * [decide]; for `send` writes it as `sending`, for `schedule` as
   * `scheduled` with `scheduledFor`, either with [sender] (`sentBy`,
   * `senderEmail`) and the server time as `requestedAt`. [decide] may
   * throw, writing nothing.
   */
  claim(
    id: string,
    sender: Sender,
    decide: (stored: StoredAnnouncement | undefined) => Claim,
  ): Promise<Claim>;
  /**
   * In one transaction: a `scheduled` request becomes `sending` and is
   * returned; any other (cancelled, already sent, missing) is left alone
   * and undefined is returned.
   */
  claimScheduled(id: string): Promise<Announcement | undefined>;
  /**
   * In one transaction: reads the request and passes it to [decide]; when
   * it returns true, writes `cancelled`, `cancelledBy` and `cancelledAt`.
   */
  cancel(
    id: string,
    by: string,
    decide: (stored: StoredAnnouncement | undefined) => boolean,
  ): Promise<void>;
  /** Sets `sent`, the FCM message id and `sentAt` (server time). */
  markSent(id: string, messageId: string): Promise<void>;
  /** Sets `failed`: nothing was sent, so the id may be sent again. */
  markFailed(id: string): Promise<void>;
  /** Sends through FCM; the message id. */
  send(message: TopicMessage): Promise<string>;
  /** The push tokens on [uid]'s devices (`users/{uid}/devices`). */
  deviceTokens(uid: string): Promise<string[]>;
  /** Sends to each token; how many FCM accepted and refused. */
  sendToDevices(
    message: MulticastMessage,
  ): Promise<{ successCount: number; failureCount: number }>;
  /**
   * Creates the task, named [id], that sends the request at [atMillis];
   * one that exists already counts as created.
   */
  enqueue(id: string, atMillis: number): Promise<void>;
  /** Deletes the task named [id]; a missing one counts as deleted. */
  deleteTask(id: string): Promise<void>;
}

export type SendResult =
  | {
      id: string;
      status: "sent";
      messageId: string;
      /** This request id was sent before; nothing was sent now. */
      alreadySent: boolean;
    }
  | {
      id: string;
      status: "scheduled";
      scheduledFor: number;
      /** This request id was scheduled before; nothing changed now. */
      alreadySent: boolean;
    }
  | {
      status: "test";
      /** How many of the caller's devices FCM accepted and refused. */
      delivered: number;
      failed: number;
    };

type CallerAuth = CallableRequest["auth"];

/** The caller, when it has the `admin` claim. */
export function requireAdmin(auth: CallerAuth): Sender {
  if (!auth) throw new HttpsError("unauthenticated", "Sign in first.");
  if (auth.token.admin !== true) {
    throw new HttpsError("permission-denied", "Admins only.", {
      reason: Reason.notAdmin,
    });
  }
  const email = auth.token.email;
  return typeof email === "string" ? { uid: auth.uid, email } : { uid: auth.uid };
}

export const invalid = (field: string, message: string) =>
  new HttpsError("invalid-argument", message, {
    reason: Reason.invalidInput,
    field,
  });

export type ParsedRequest =
  | { test: true; announcement: Announcement }
  | {
      test: false;
      requestId: string;
      announcement: Announcement;
      scheduledForMillis?: number;
    };

/**
 * The request, trimmed, or an `invalid-input` error. `audience` defaults
 * to everyone (panels from before it), `scheduleAt` is epoch milliseconds
 * [MIN_SCHEDULE_AHEAD_MS] to [MAX_SCHEDULE_AHEAD_MS] after [nowMillis], and
 * `test: true` needs no request id and takes no `scheduleAt`.
 */
export function parseRequest(data: unknown, nowMillis: number): ParsedRequest {
  const input = (typeof data === "object" && data !== null ? data : {}) as {
    [key: string]: unknown;
  };
  const { requestId, locale, audience = "everyone", scheduleAt, test } = input;
  if (test !== undefined && typeof test !== "boolean") {
    throw invalid("test", "test must be a boolean.");
  }
  if (
    test !== true &&
    (typeof requestId !== "string" || !REQUEST_ID.test(requestId))
  ) {
    throw invalid(
      "requestId",
      "requestId must be 8-64 letters, digits, _ or -.",
    );
  }
  if (typeof locale !== "string" || !LOCALES.includes(locale)) {
    throw invalid("locale", `locale must be one of ${LOCALES.join(", ")}.`);
  }
  if (!AUDIENCES.includes(audience as Audience)) {
    throw invalid(
      "audience",
      `audience must be one of ${AUDIENCES.join(", ")}.`,
    );
  }
  const text = (field: "title" | "body", max: number): string => {
    const value = input[field];
    const trimmed = typeof value === "string" ? value.trim() : "";
    if (trimmed.length === 0) throw invalid(field, `${field} is empty.`);
    if (trimmed.length > max) {
      throw invalid(field, `${field} is longer than ${max} characters.`);
    }
    return trimmed;
  };
  const announcement: Announcement = {
    locale,
    title: text("title", MAX_TITLE),
    body: text("body", MAX_BODY),
    audience: audience as Audience,
  };
  if (scheduleAt !== undefined && scheduleAt !== null) {
    if (test === true) {
      throw invalid("scheduleAt", "A test is sent now, never scheduled.");
    }
    if (
      typeof scheduleAt !== "number" ||
      !Number.isInteger(scheduleAt) ||
      scheduleAt < nowMillis + MIN_SCHEDULE_AHEAD_MS ||
      scheduleAt > nowMillis + MAX_SCHEDULE_AHEAD_MS
    ) {
      throw invalid(
        "scheduleAt",
        "scheduleAt must be epoch milliseconds from a minute to 30 days ahead.",
      );
    }
  }
  if (test === true) return { test: true, announcement };
  return {
    test: false,
    requestId: requestId as string,
    announcement,
    ...(typeof scheduleAt === "number"
      ? { scheduledForMillis: scheduleAt }
      : {}),
  };
}

/**
 * What a request does given what is stored under its id: a new or failed
 * request sends (or is scheduled, with [scheduledForMillis]); a sent or
 * scheduled one is not done again; one being sent, a cancelled one, or an
 * id holding another request, is refused.
 */
export function decideClaim(
  stored: StoredAnnouncement | undefined,
  announcement: Announcement,
  scheduledForMillis?: number,
): Claim {
  const fresh: Claim =
    scheduledForMillis === undefined
      ? { kind: "send", announcement }
      : { kind: "schedule", announcement, scheduledForMillis };
  if (stored === undefined) return fresh;
  const same =
    stored.locale === announcement.locale &&
    stored.title === announcement.title &&
    stored.body === announcement.body &&
    (stored.audience ?? "everyone") === announcement.audience &&
    stored.scheduledForMillis === scheduledForMillis;
  if (!same) {
    throw new HttpsError(
      "invalid-argument",
      "This request id was used for another announcement.",
      { reason: Reason.requestIdReused },
    );
  }
  switch (stored.status) {
    case "sent":
      return { kind: "sent", messageId: stored.messageId ?? "" };
    case "scheduled":
      return {
        kind: "scheduled",
        scheduledForMillis: stored.scheduledForMillis ?? 0,
      };
    case "sending":
      // Also a send whose outcome is unknown; the panel tells them apart
      // by the age of the request.
      throw new HttpsError(
        "already-exists",
        "This announcement is being sent.",
        { reason: Reason.inProgress, requestedAt: stored.requestedAtMillis },
      );
    case "cancelled":
      throw new HttpsError(
        "failed-precondition",
        "This announcement was cancelled.",
        { reason: Reason.cancelled },
      );
    default:
      return fresh;
  }
}

/** The topic of [announcement]'s language and audience. */
export function topicOf(announcement: Announcement): string {
  const { locale, audience } = announcement;
  return audience === "everyone"
    ? `announcements_${locale}`
    : `announcements_${locale}_${audience}`;
}

/**
 * The notification of [announcement], dropped [TIME_TO_LIVE_SECONDS] after
 * [nowSeconds].
 */
function notification(
  announcement: Announcement,
  nowSeconds: number,
): BaseMessage {
  const { title, body } = announcement;
  return {
    notification: { title, body },
    android: {
      ttl: TIME_TO_LIVE_SECONDS * 1000,
      notification: { channelId: ANDROID_CHANNEL },
    },
    apns: {
      headers: { "apns-expiration": `${nowSeconds + TIME_TO_LIVE_SECONDS}` },
      payload: { aps: { sound: "default" } },
    },
  };
}

/** [announcement] to its language's and audience's topic. */
export function topicMessage(
  announcement: Announcement,
  nowSeconds: number,
): TopicMessage {
  return {
    topic: topicOf(announcement),
    ...notification(announcement, nowSeconds),
  };
}

/**
 * Sends the claimed (`sending`) request [id] to its topic and records the
 * outcome. FCM's refusal records it `failed`; an unclear error leaves it
 * `sending`. Either throws an [HttpsError] with the reason.
 */
export async function sendClaimed(
  id: string,
  announcement: Announcement,
  store: AnnouncementStore,
  nowSeconds: number,
): Promise<string> {
  let messageId: string;
  try {
    messageId = await store.send(topicMessage(announcement, nowSeconds));
  } catch (error) {
    if (!isDefiniteRefusal(error)) {
      // FCM may have taken it: left `sending`, so no retry sends it again.
      logger.error("announcement outcome unknown", {
        requestId: id,
        error: String(error),
      });
      throw new HttpsError(
        "unknown",
        "The announcement may or may not have been sent.",
        { reason: Reason.outcomeUnknown },
      );
    }
    logger.error("announcement not sent", {
      requestId: id,
      error: String(error),
    });
    // Left `sending` instead, a retry is refused as in progress; that is
    // safe, only less convenient.
    await store.markFailed(id).catch((markError: unknown) =>
      logger.error("failed send not recorded", {
        requestId: id,
        error: String(markError),
      }),
    );
    throw new HttpsError("internal", "The announcement was not sent.", {
      reason: Reason.sendFailed,
    });
  }
  // Sent: a failure to record it must not make it go again.
  try {
    await store.markSent(id, messageId);
  } catch (error) {
    logger.error("announcement sent, not recorded", {
      requestId: id,
      messageId,
      error: String(error),
    });
  }
  return messageId;
}

/**
 * A test: [announcement] to the caller's own devices only, unrecorded (a
 * test is sent as often as asked). Fails when the caller has no device
 * with a push token, or FCM took it for none of them.
 */
async function sendTest(
  sender: Sender,
  announcement: Announcement,
  store: AnnouncementStore,
  nowSeconds: number,
): Promise<SendResult> {
  const tokens = await store.deviceTokens(sender.uid);
  if (tokens.length === 0) {
    throw new HttpsError(
      "failed-precondition",
      "None of your devices can receive announcements.",
      { reason: Reason.noDevices },
    );
  }
  let result: { successCount: number; failureCount: number };
  try {
    result = await store.sendToDevices({
      tokens,
      ...notification(announcement, nowSeconds),
    });
  } catch (error) {
    logger.error("test announcement not sent", {
      by: sender.uid,
      error: String(error),
    });
    throw new HttpsError("internal", "The test was not sent.", {
      reason: Reason.sendFailed,
    });
  }
  logger.info("test announcement sent", { by: sender.uid, ...result });
  if (result.successCount === 0) {
    throw new HttpsError("internal", "The test reached no device.", {
      reason: Reason.sendFailed,
    });
  }
  return {
    status: "test",
    delivered: result.successCount,
    failed: result.failureCount,
  };
}

/**
 * Sends the caller's announcement to every device following its language
 * and audience, once per request id: a retry of a sent request answers
 * with the first send. With `scheduleAt` it is stored `scheduled` and a
 * Cloud Task sends it then ([sendScheduledAnnouncement]); with `test` it
 * goes to the caller's own devices only. Only a caller with the `admin`
 * claim may send.
 */
export async function sendAnnouncementOf(
  auth: CallerAuth,
  data: unknown,
  store: AnnouncementStore,
  nowMillis: number,
): Promise<SendResult> {
  const sender = requireAdmin(auth);
  const request = parseRequest(data, nowMillis);
  const nowSeconds = Math.floor(nowMillis / 1000);
  if (request.test) {
    return sendTest(sender, request.announcement, store, nowSeconds);
  }
  const { requestId, announcement, scheduledForMillis } = request;
  const claim = await store.claim(requestId, sender, (stored) =>
    decideClaim(stored, announcement, scheduledForMillis),
  );
  switch (claim.kind) {
    case "sent":
      return {
        id: requestId,
        status: "sent",
        messageId: claim.messageId,
        alreadySent: true,
      };
    case "scheduled":
      return {
        id: requestId,
        status: "scheduled",
        scheduledFor: claim.scheduledForMillis,
        alreadySent: true,
      };
    case "schedule":
      try {
        await store.enqueue(requestId, claim.scheduledForMillis);
      } catch (error) {
        logger.error("announcement not scheduled", {
          requestId,
          error: String(error),
        });
        // A task that exists after all finds the request `failed` and
        // sends nothing; scheduling again recreates the claim.
        await store.markFailed(requestId).catch((markError: unknown) =>
          logger.error("failed schedule not recorded", {
            requestId,
            error: String(markError),
          }),
        );
        throw new HttpsError("internal", "The announcement was not scheduled.", {
          reason: Reason.scheduleFailed,
        });
      }
      logger.info("announcement scheduled", {
        requestId,
        scheduledFor: claim.scheduledForMillis,
        by: sender.uid,
      });
      return {
        id: requestId,
        status: "scheduled",
        scheduledFor: claim.scheduledForMillis,
        alreadySent: false,
      };
    case "send": {
      const messageId = await sendClaimed(
        requestId,
        announcement,
        store,
        nowSeconds,
      );
      logger.info("announcement sent", { requestId, messageId, by: sender.uid });
      return { id: requestId, status: "sent", messageId, alreadySent: false };
    }
  }
}

const millisOf = (value: unknown): number | undefined =>
  value instanceof Timestamp ? value.toMillis() : undefined;

/** A stored document as [StoredAnnouncement]; old ones went to everyone. */
const storedOf = (data: FirebaseFirestore.DocumentData): StoredAnnouncement =>
  ({
    ...data,
    audience: data.audience ?? "everyone",
    requestedAtMillis: millisOf(data.requestedAt),
    scheduledForMillis: millisOf(data.scheduledFor),
  }) as StoredAnnouncement;

const announcementOf = (stored: StoredAnnouncement): Announcement => ({
  locale: stored.locale,
  title: stored.title,
  body: stored.body,
  audience: stored.audience,
});

const hasCode = (error: unknown, code: string) =>
  (error as { code?: unknown } | null)?.code === code;

/** The Admin SDK behind [AnnouncementStore]. */
export const firebaseAnnouncementStore = (): AnnouncementStore => {
  const db = getFirestore();
  const announcements = db.collection("announcements");
  const queue = () =>
    getFunctions().taskQueue<{ id: string }>(
      `locations/${REGION}/functions/${SCHEDULED_FUNCTION}`,
    );
  return {
    claim: (id, sender, decide) =>
      db.runTransaction(async (transaction) => {
        const doc = announcements.doc(id);
        const data = (await transaction.get(doc)).data();
        const claim = decide(data === undefined ? undefined : storedOf(data));
        if (claim.kind === "send" || claim.kind === "schedule") {
          transaction.set(doc, {
            ...claim.announcement,
            ...(claim.kind === "schedule"
              ? {
                  status: "scheduled",
                  scheduledFor: Timestamp.fromMillis(claim.scheduledForMillis),
                }
              : { status: "sending" }),
            sentBy: sender.uid,
            ...(sender.email === undefined
              ? {}
              : { senderEmail: sender.email }),
            requestedAt: FieldValue.serverTimestamp(),
          });
        }
        return claim;
      }),
    claimScheduled: (id) =>
      db.runTransaction(async (transaction) => {
        const doc = announcements.doc(id);
        const data = (await transaction.get(doc)).data();
        if (data?.status !== "scheduled") return undefined;
        transaction.update(doc, { status: "sending" });
        return announcementOf(storedOf(data));
      }),
    cancel: (id, by, decide) =>
      db.runTransaction(async (transaction) => {
        const doc = announcements.doc(id);
        const data = (await transaction.get(doc)).data();
        if (!decide(data === undefined ? undefined : storedOf(data))) return;
        transaction.update(doc, {
          status: "cancelled",
          cancelledBy: by,
          cancelledAt: FieldValue.serverTimestamp(),
        });
      }),
    async markSent(id, messageId) {
      await announcements.doc(id).update({
        status: "sent",
        messageId,
        sentAt: FieldValue.serverTimestamp(),
      });
    },
    async markFailed(id) {
      await announcements.doc(id).update({ status: "failed" });
    },
    send: (message) => getMessaging().send(message),
    async deviceTokens(uid) {
      const devices = await db.collection(`users/${uid}/devices`).get();
      const tokens = devices.docs
        .map((doc) => doc.get("pushToken"))
        .filter((token): token is string => typeof token === "string");
      return [...new Set(tokens)];
    },
    sendToDevices: (message) => getMessaging().sendEachForMulticast(message),
    async enqueue(id, atMillis) {
      try {
        await queue().enqueue({ id }, { id, scheduleTime: new Date(atMillis) });
      } catch (error) {
        if (!hasCode(error, "functions/task-already-exists")) throw error;
      }
    },
    async deleteTask(id) {
      try {
        await queue().delete(id);
      } catch (error) {
        if (!hasCode(error, "functions/not-found")) throw error;
      }
    },
  };
};

export const sendAnnouncement = onCall((request) =>
  sendAnnouncementOf(
    request.auth,
    request.data,
    firebaseAnnouncementStore(),
    Date.now(),
  ),
);
