import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

/** How recent a sign-in must be to delete an account that has one. */
export const RECENT_SIGN_IN_SECONDS = 5 * 60;

/**
 * `details.reason` of a refusal, which the app maps on (never the message):
 * sign in again first, or the data is gone but the sign-in is left, so call
 * again to finish.
 */
export const Reason = {
  recentSignIn: "recent-sign-in",
  signInNotDeleted: "sign-in-not-deleted",
} as const;

/** What is deleted for a user; each step does nothing when already done. */
export interface AccountStore {
  /** `users/{uid}` with every subcollection. */
  deleteUserDocuments(uid: string): Promise<void>;
  /** `entitlements/{uid}`. */
  deleteEntitlement(uid: string): Promise<void>;
  /** Everything in Storage under `users/{uid}/`. */
  deleteFiles(uid: string): Promise<void>;
  deleteAuthUser(uid: string): Promise<void>;
}

type CallerAuth = CallableRequest["auth"];

/**
 * Deletes the caller's account. Data and files go first and the sign-in
 * last, so after a partial failure the user can still call again; every
 * step succeeds when there is nothing left to delete.
 *
 * A guest has no credential to sign in again with, so only an account with
 * one must have signed in within [RECENT_SIGN_IN_SECONDS].
 */
export async function deleteAccountOf(
  auth: CallerAuth,
  store: AccountStore,
  nowSeconds: number,
): Promise<void> {
  if (!auth) throw new HttpsError("unauthenticated", "Sign in first.");
  const { uid, token } = auth;
  const guest = token.firebase?.sign_in_provider === "anonymous";
  if (!guest && nowSeconds - token.auth_time > RECENT_SIGN_IN_SECONDS) {
    throw new HttpsError("failed-precondition", "Sign in again first.", {
      reason: Reason.recentSignIn,
    });
  }
  await Promise.all([
    store.deleteUserDocuments(uid),
    store.deleteEntitlement(uid),
    store.deleteFiles(uid),
  ]);
  try {
    await store.deleteAuthUser(uid);
  } catch (error) {
    logger.error("data deleted, sign-in left", { uid, error: String(error) });
    throw new HttpsError("internal", "The sign-in was not deleted.", {
      reason: Reason.signInNotDeleted,
    });
  }
  logger.info("account deleted", { uid });
}

/** The part of a Storage bucket [deleteUserFiles] uses. */
export interface Bucket {
  deleteFiles(query: { prefix: string }): Promise<unknown>;
}

/**
 * Deletes `users/{uid}/` in the default bucket. A project without one (no
 * photo was ever backed up) has nothing to delete: logged, not failed.
 */
export async function deleteUserFiles(
  bucket: () => Bucket,
  uid: string,
): Promise<void> {
  try {
    await bucket().deleteFiles({ prefix: `users/${uid}/` });
  } catch (error) {
    if (!isMissingBucket(error)) throw error;
    logger.warn("no default bucket; no files to delete", { uid });
  }
}

const isMissingBucket = (error: unknown): boolean => {
  const { code, message } = error as { code?: unknown; message?: unknown };
  // 404: the bucket does not exist; the message: none is configured.
  return (
    code === 404 ||
    (typeof message === "string" && message.includes("Bucket name"))
  );
};

/** The Admin SDK behind [AccountStore]. */
export const firebaseAccountStore = (): AccountStore => ({
  async deleteUserDocuments(uid) {
    const db = getFirestore();
    await db.recursiveDelete(db.collection("users").doc(uid));
  },
  async deleteEntitlement(uid) {
    await getFirestore().collection("entitlements").doc(uid).delete();
  },
  deleteFiles: (uid) => deleteUserFiles(() => getStorage().bucket(), uid),
  async deleteAuthUser(uid) {
    try {
      await getAuth().deleteUser(uid);
    } catch (error) {
      if ((error as { code?: string }).code !== "auth/user-not-found") {
        throw error;
      }
    }
  },
});

export const deleteAccount = onCall((request) =>
  deleteAccountOf(
    request.auth,
    firebaseAccountStore(),
    Math.floor(Date.now() / 1000),
  ),
);
