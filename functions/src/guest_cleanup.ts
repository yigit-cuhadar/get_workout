import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { TIME_ZONE } from "./dashboard/warehouse";
import {
  AccountStore,
  deleteUserData,
  firebaseAccountStore,
} from "./delete_account";

/** A guest unused this long is deleted with its data (owner's pick). */
export const GUEST_RETENTION_DAYS = 90;

/** At most this many guests are deleted per run, to stay in the timeout. */
export const MAX_DELETIONS_PER_RUN = 500;

const DAY_MS = 24 * 60 * 60 * 1000;

/** What the cleanup needs to know of a sign-in. */
export interface SignIn {
  uid: string;
  /** Linked providers (email, Google, Apple); none for a guest. */
  providerCount: number;
  /** The last time the app used the sign-in, in milliseconds. */
  lastActiveMs: number;
}

/** The sign-ins, a page at a time, and who has a purchase on record. */
export interface GuestDirectory {
  page(pageToken?: string): Promise<{ users: SignIn[]; pageToken?: string }>;
  /** `entitlements/{uid}` exists: the guest bought or was granted Premium. */
  hasEntitlement(uid: string): Promise<boolean>;
}

/** A guest (no provider) the app has not used for [GUEST_RETENTION_DAYS]. */
export const isStaleGuest = (user: SignIn, nowMs: number): boolean =>
  user.providerCount === 0 &&
  user.lastActiveMs < nowMs - GUEST_RETENTION_DAYS * DAY_MS;

/**
 * Deletes every stale guest with no entitlement on record, its data and
 * files as an account deletion does, up to [MAX_DELETIONS_PER_RUN]; the
 * rest wait for the next run. One that fails is logged and left for the
 * next run. Returns how many were deleted.
 */
export async function cleanUpGuests(
  directory: GuestDirectory,
  store: AccountStore,
  nowMs: number,
): Promise<{ deleted: number; failed: number }> {
  let deleted = 0;
  let failed = 0;
  let pageToken: string | undefined;
  do {
    const page = await directory.page(pageToken);
    for (const user of page.users) {
      if (deleted + failed >= MAX_DELETIONS_PER_RUN) {
        return { deleted, failed };
      }
      if (!isStaleGuest(user, nowMs)) continue;
      if (await directory.hasEntitlement(user.uid)) continue;
      try {
        await deleteUserData(user.uid, store);
        deleted++;
      } catch (error) {
        failed++;
        logger.error("guest not deleted", {
          uid: user.uid,
          error: String(error),
        });
      }
    }
    pageToken = page.pageToken;
  } while (pageToken);
  return { deleted, failed };
}

/** The Admin SDK behind [GuestDirectory]. */
export const firebaseGuestDirectory = (): GuestDirectory => ({
  async page(pageToken) {
    const result = await getAuth().listUsers(1000, pageToken);
    return {
      users: result.users.map((user) => ({
        uid: user.uid,
        providerCount: user.providerData.length,
        // The ID token refreshes hourly while the app runs, so this is the
        // last use; a sign-in that never refreshed falls back to its start.
        lastActiveMs: Date.parse(
          user.metadata.lastRefreshTime ??
            user.metadata.lastSignInTime ??
            user.metadata.creationTime,
        ),
      })),
      pageToken: result.pageToken,
    };
  },
  async hasEntitlement(uid) {
    const doc = await getFirestore().collection("entitlements").doc(uid).get();
    return doc.exists;
  },
});

/** Every night: deletes guests unused for [GUEST_RETENTION_DAYS]. */
export const guestCleanupNightly = onSchedule(
  { schedule: "30 3 * * *", timeZone: TIME_ZONE, timeoutSeconds: 540 },
  async () => {
    const result = await cleanUpGuests(
      firebaseGuestDirectory(),
      firebaseAccountStore(),
      Date.now(),
    );
    logger.info("guest cleanup", result);
  },
);
