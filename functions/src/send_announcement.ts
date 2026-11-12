import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { TopicMessage, getMessaging } from "firebase-admin/messaging";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

/** The languages announcements can go to; the app's (`languages`). */
export const LOCALES = ["en"];

/**
 * Longest title and body, in UTF-16 code units like Dart's `String.length`
 * (the panel counts the same). Longer text is cut off on most lock screens.
 */
export const MAX_TITLE = 65;
export const MAX_BODY = 240;

/** The Android channel every notification of the app uses. */
export const ANDROID_CHANNEL = "workout";

/** A request id: a Firestore auto id or another short random token. */
const REQUEST_ID = /^[A-Za-z0-9_-]{8,64}$/;

/**
 * `details.reason` of a refusal, which the panel maps on (never the
 * message).
 */
export const Reason = {
  notAdmin: "not-admin",
  invalidInput: "invalid-input",
  inProgress: "in-progress",
  requestIdReused: "request-id-reused",
  sendFailed: "send-failed",
} as const;

export interface Announcement {
  locale: string;
  title: string;
  body: string;
}

/** `announcements/{requestId}` as far as this function reads it. */
export interface StoredAnnouncement extends Announcement {
  status: "sending" | "sent" | "failed";
  messageId?: string;
}

/** What [AnnouncementStore.claim]'s decision says. */
export type Claim =
  | { kind: "send"; announcement: Announcement }
  | { kind: "sent"; messageId: string };

export interface AnnouncementStore {
  /**
   * In one transaction: reads `announcements/{id}` and passes it to
   * [decide]; for `send`, writes it as `sending`, with [sentBy] and the
   * server time as `requestedAt`. [decide] may throw, writing nothing.
   */
  claim(
    id: string,
    sentBy: string,
    decide: (stored: StoredAnnouncement | undefined) => Claim,
  ): Promise<Claim>;
  /** Sets `sent`, the FCM message id and `sentAt` (server time). */
  markSent(id: string, messageId: string): Promise<void>;
  markFailed(id: string): Promise<void>;
  /** Sends through FCM; the message id. */
  send(message: TopicMessage): Promise<string>;
}

export interface SendResult {
  id: string;
  messageId: string;
  /** This request id was sent before; nothing was sent now. */
  alreadySent: boolean;
}

type CallerAuth = CallableRequest["auth"];

const invalid = (field: string, message: string) =>
  new HttpsError("invalid-argument", message, {
    reason: Reason.invalidInput,
    field,
  });

/** The request's id and announcement, trimmed, or an `invalid-input` error. */
export function parseRequest(data: unknown): {
  requestId: string;
  announcement: Announcement;
} {
  const input = (typeof data === "object" && data !== null ? data : {}) as {
    [key: string]: unknown;
  };
  const { requestId, locale } = input;
  if (typeof requestId !== "string" || !REQUEST_ID.test(requestId)) {
    throw invalid(
      "requestId",
      "requestId must be 8-64 letters, digits, _ or -.",
    );
  }
  if (typeof locale !== "string" || !LOCALES.includes(locale)) {
    throw invalid("locale", `locale must be one of ${LOCALES.join(", ")}.`);
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
  return {
    requestId,
    announcement: {
      locale,
      title: text("title", MAX_TITLE),
      body: text("body", MAX_BODY),
    },
  };
}

/**
 * What a request does given what is stored under its id: a new or failed
 * request sends; a sent one is not sent again; one being sent, or an id
 * holding other text, is refused.
 */
export function decideClaim(
  stored: StoredAnnouncement | undefined,
  announcement: Announcement,
): Claim {
  if (stored === undefined) return { kind: "send", announcement };
  const same =
    stored.locale === announcement.locale &&
    stored.title === announcement.title &&
    stored.body === announcement.body;
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
    case "sending":
      throw new HttpsError(
        "already-exists",
        "This announcement is being sent.",
        { reason: Reason.inProgress },
      );
    default:
      return { kind: "send", announcement };
  }
}

/** The notification message of [announcement] to its language's topic. */
export function topicMessage(announcement: Announcement): TopicMessage {
  const { locale, title, body } = announcement;
  return {
    // The app follows `announcements_<language>` (FcmAnnouncementRepository).
    topic: `announcements_${locale}`,
    notification: { title, body },
    android: { notification: { channelId: ANDROID_CHANNEL } },
    apns: { payload: { aps: { sound: "default" } } },
  };
}

/**
 * Sends the caller's announcement to every device following its language,
 * once per request id: a retry of a sent request answers with the first
 * send. Only a caller with the `admin` claim may send.
 */
export async function sendAnnouncementOf(
  auth: CallerAuth,
  data: unknown,
  store: AnnouncementStore,
): Promise<SendResult> {
  if (!auth) throw new HttpsError("unauthenticated", "Sign in first.");
  if (auth.token.admin !== true) {
    throw new HttpsError("permission-denied", "Admins only.", {
      reason: Reason.notAdmin,
    });
  }
  const { requestId, announcement } = parseRequest(data);
  const claim = await store.claim(requestId, auth.uid, (stored) =>
    decideClaim(stored, announcement),
  );
  if (claim.kind === "sent") {
    return { id: requestId, messageId: claim.messageId, alreadySent: true };
  }
  let messageId: string;
  try {
    messageId = await store.send(topicMessage(announcement));
  } catch (error) {
    logger.error("announcement not sent", { requestId, error: String(error) });
    // Left `sending`, a retry of this id is refused as in progress; the
    // panel then needs an edit, which makes a new id.
    await store.markFailed(requestId).catch((markError: unknown) =>
      logger.error("failed send not recorded", {
        requestId,
        error: String(markError),
      }),
    );
    throw new HttpsError("internal", "The announcement was not sent.", {
      reason: Reason.sendFailed,
    });
  }
  // Sent: a failure to record it must not make the panel send it again.
  try {
    await store.markSent(requestId, messageId);
  } catch (error) {
    logger.error("announcement sent, not recorded", {
      requestId,
      messageId,
      error: String(error),
    });
  }
  logger.info("announcement sent", { requestId, messageId, by: auth.uid });
  return { id: requestId, messageId, alreadySent: false };
}

/** The Admin SDK behind [AnnouncementStore]. */
export const firebaseAnnouncementStore = (): AnnouncementStore => {
  const announcements = getFirestore().collection("announcements");
  return {
    claim: (id, sentBy, decide) =>
      getFirestore().runTransaction(async (transaction) => {
        const doc = announcements.doc(id);
        const stored = (await transaction.get(doc)).data() as
          | StoredAnnouncement
          | undefined;
        const claim = decide(stored);
        if (claim.kind === "send") {
          transaction.set(doc, {
            ...claim.announcement,
            status: "sending",
            sentBy,
            requestedAt: FieldValue.serverTimestamp(),
          });
        }
        return claim;
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
  };
};

export const sendAnnouncement = onCall((request) =>
  sendAnnouncementOf(request.auth, request.data, firebaseAnnouncementStore()),
);
