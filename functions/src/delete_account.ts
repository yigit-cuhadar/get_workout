import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

/** How recent a sign-in must be to delete an account that has one. */
export const RECENT_SIGN_IN_SECONDS = 5 * 60;

/** The message the app reads as "sign in again first". */
export const RECENT_LOGIN_REQUIRED = "requires-recent-login";

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
    throw new HttpsError("failed-precondition", RECENT_LOGIN_REQUIRED);
  }
  await Promise.all([
    store.deleteUserDocuments(uid),
    store.deleteEntitlement(uid),
    store.deleteFiles(uid),
  ]);
  await store.deleteAuthUser(uid);
  logger.info("account deleted", { uid });
}

/** The Admin SDK behind [AccountStore]. */
export const firebaseAccountStore = (): AccountStore => ({
  async deleteUserDocuments(uid) {
    const db = getFirestore();
    await db.recursiveDelete(db.collection("users").doc(uid));
  },
  async deleteEntitlement(uid) {
    await getFirestore().collection("entitlements").doc(uid).delete();
  },
  async deleteFiles(uid) {
    try {
      await getStorage().bucket().deleteFiles({ prefix: `users/${uid}/` });
    } catch (error) {
      // No default bucket yet means no files to delete.
      if ((error as { code?: number }).code !== 404) throw error;
    }
  },
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
