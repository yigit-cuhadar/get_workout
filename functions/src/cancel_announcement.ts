import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

import {
  AnnouncementStore,
  REQUEST_ID,
  StoredAnnouncement,
  firebaseAnnouncementStore,
  invalid,
  requireAdmin,
} from "./send_announcement";

/** `details.reason` when the request is not (or no longer) scheduled. */
export const NOT_SCHEDULED = "not-scheduled";

/**
 * Whether a cancel writes: only a `scheduled` request is cancelled; one
 * cancelled already is left as it is (a retry), anything else is refused.
 */
export function decideCancel(stored: StoredAnnouncement | undefined): boolean {
  if (stored === undefined) {
    throw new HttpsError("not-found", "No such announcement.", {
      reason: NOT_SCHEDULED,
    });
  }
  switch (stored.status) {
    case "scheduled":
      return true;
    case "cancelled":
      return false;
    default:
      throw new HttpsError(
        "failed-precondition",
        "This announcement is not scheduled.",
        { reason: NOT_SCHEDULED, status: stored.status },
      );
  }
}

/**
 * Cancels the caller's scheduled announcement `{id}`: marks it
 * `cancelled`, which the task handler skips, then deletes its task. Only a
 * caller with the `admin` claim may cancel.
 */
export async function cancelAnnouncementOf(
  auth: CallableRequest["auth"],
  data: unknown,
  store: AnnouncementStore,
): Promise<{ id: string }> {
  const { uid } = requireAdmin(auth);
  const id = (data as { id?: unknown } | null)?.id;
  if (typeof id !== "string" || !REQUEST_ID.test(id)) {
    throw invalid("id", "id must be 8-64 letters, digits, _ or -.");
  }
  await store.cancel(id, uid, decideCancel);
  // Marked first: a task this leaves behind finds it cancelled.
  try {
    await store.deleteTask(id);
  } catch (error) {
    logger.warn("cancelled announcement's task left", {
      requestId: id,
      error: String(error),
    });
  }
  logger.info("announcement cancelled", { requestId: id, by: uid });
  return { id };
}

export const cancelAnnouncement = onCall((request) =>
  cancelAnnouncementOf(request.auth, request.data, firebaseAnnouncementStore()),
);
