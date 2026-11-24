import { HttpsError } from "firebase-functions/v2/https";
import { onTaskDispatched } from "firebase-functions/v2/tasks";
import { logger } from "firebase-functions/v2";

import {
  AnnouncementStore,
  REQUEST_ID,
  firebaseAnnouncementStore,
  sendClaimed,
} from "./send_announcement";

/**
 * Sends the scheduled announcement of the task `{id}` as `sendAnnouncement`
 * sends one, once: only a request still `scheduled` is claimed, so a
 * cancelled one, or a task delivered twice, sends nothing. Only a failure
 * to claim throws, so Cloud Tasks tries again; once claimed, a failed send
 * is recorded (`failed`, or left `sending` when unclear), never retried.
 */
export async function sendScheduledOf(
  data: unknown,
  store: AnnouncementStore,
  nowMillis: number,
): Promise<void> {
  const id = (data as { id?: unknown } | null)?.id;
  if (typeof id !== "string" || !REQUEST_ID.test(id)) {
    logger.error("scheduled announcement task without an id", { data });
    return;
  }
  const announcement = await store.claimScheduled(id);
  if (announcement === undefined) {
    logger.info("scheduled announcement not due", { requestId: id });
    return;
  }
  try {
    const messageId = await sendClaimed(
      id,
      announcement,
      store,
      Math.floor(nowMillis / 1000),
    );
    logger.info("scheduled announcement sent", { requestId: id, messageId });
  } catch (error) {
    // Already logged and recorded by sendClaimed.
    if (!(error instanceof HttpsError)) throw error;
  }
}

export const sendScheduledAnnouncement = onTaskDispatched(
  {
    retryConfig: { maxAttempts: 5, minBackoffSeconds: 60 },
    rateLimits: { maxConcurrentDispatches: 1 },
  },
  (request) =>
    sendScheduledOf(request.data, firebaseAnnouncementStore(), Date.now()),
);
