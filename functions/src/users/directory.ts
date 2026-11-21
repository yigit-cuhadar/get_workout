import { UserRecord, getAuth } from "firebase-admin/auth";
import { Timestamp, getFirestore } from "firebase-admin/firestore";

import { firebaseAccountStore } from "../delete_account";
import { revenueCatApiKey } from "../dashboard/revenuecat_metrics";
import { revenueCatGrants } from "./revenuecat_customers";
import { AuthUser, DeviceDoc, UserDirectory, UsersDeps } from "./users";

const millisOf = (value: string | undefined): number | null => {
  const millis = value ? Date.parse(value) : NaN;
  return Number.isNaN(millis) ? null : millis;
};

const authUser = (record: UserRecord): AuthUser => ({
  uid: record.uid,
  email: record.email ?? null,
  providers: record.providerData.map((p) => p.providerId),
  createdAtMillis: millisOf(record.metadata.creationTime) ?? 0,
  lastActiveAtMillis:
    millisOf(record.metadata.lastRefreshTime ?? undefined) ??
    millisOf(record.metadata.lastSignInTime),
  admin: record.customClaims?.admin === true,
});

const missing = (error: unknown) =>
  (error as { code?: string }).code === "auth/user-not-found";

const timestampMillis = (value: unknown): number | null =>
  value instanceof Timestamp ? value.toMillis() : null;

/** [UserDirectory] on the Admin SDK. */
export const firebaseUserDirectory = (): UserDirectory => {
  const auth = getAuth();
  const db = getFirestore();
  const lookup = async (find: () => Promise<UserRecord>) => {
    try {
      return authUser(await find());
    } catch (error) {
      if (missing(error)) return null;
      throw error;
    }
  };
  const devices = (uid: string) =>
    db.collection(`users/${uid}/devices`).orderBy("lastSeenAt", "desc");
  const lastWorkout = async (uid: string) => {
    const latest = await db
      .collection(`users/${uid}/workouts`)
      .orderBy("finishedAt", "desc")
      .limit(1)
      .get();
    return timestampMillis(latest.docs[0]?.get("finishedAt"));
  };
  return {
    async allUsers() {
      const users: AuthUser[] = [];
      let pageToken: string | undefined;
      do {
        const page = await auth.listUsers(1000, pageToken);
        users.push(...page.users.map(authUser));
        pageToken = page.pageToken;
      } while (pageToken);
      return users;
    },
    user: (uid) => lookup(() => auth.getUser(uid)),
    userByEmail: (email) => lookup(() => auth.getUserByEmail(email)),
    async setAdmin(uid, admin) {
      const claims = { ...(await auth.getUser(uid)).customClaims };
      if (admin) claims.admin = true;
      else delete claims.admin;
      await auth.setCustomUserClaims(uid, claims);
    },
    async serverPremium(uids) {
      if (uids.length === 0) return new Map();
      const docs = await db.getAll(
        ...uids.map((uid) => db.collection("entitlements").doc(uid)),
      );
      return new Map(
        docs
          .filter((doc) => doc.exists)
          .map((doc) => [
            doc.id,
            {
              premium: doc.get("premium") === true,
              expiresAtMillis: timestampMillis(doc.get("expiresAt")),
              productId: doc.get("productId") ?? null,
              lastEventMillis: doc.get("lastEventMs") ?? null,
            },
          ]),
      );
    },
    async lastWorkouts(uids) {
      const last = await Promise.all(uids.map(lastWorkout));
      return new Map(
        uids.flatMap((uid, i) => (last[i] === null ? [] : [[uid, last[i]]])),
      );
    },
    async devices(uid) {
      const docs = await devices(uid).get();
      return docs.docs.map(
        (doc): DeviceDoc => ({
          model: doc.get("model") ?? "",
          platform: doc.get("platform") ?? "",
          osVersion: doc.get("osVersion") ?? "",
          appVersion: doc.get("appVersion") ?? "",
          lastSeenMillis: timestampMillis(doc.get("lastSeenAt")),
        }),
      );
    },
    async lastPlatforms(uids) {
      const latest = await Promise.all(
        uids.map((uid) => devices(uid).limit(1).get()),
      );
      return new Map(
        uids.flatMap((uid, i): [string, string][] => {
          const platform = latest[i].docs[0]?.get("platform");
          return typeof platform === "string" ? [[uid, platform]] : [];
        }),
      );
    },
    async activity(uid) {
      const user = db.collection("users").doc(uid);
      const [count, lastWorkoutMillis, profile] = await Promise.all([
        user.collection("workouts").count().get(),
        lastWorkout(uid),
        user.get(),
      ]);
      const programId = profile.get("activeProgram.programId");
      const program =
        typeof programId === "string"
          ? await user.collection("programs").doc(programId).get()
          : null;
      return {
        workouts: count.data().count,
        lastWorkoutMillis,
        activeProgram: program?.get("name") ?? null,
      };
    },
  };
};

/** [UsersDeps] on this project's Auth, Firestore and RevenueCat. */
export const liveUsersDeps = (): UsersDeps => ({
  directory: firebaseUserDirectory(),
  grants: revenueCatGrants(revenueCatApiKey.value(), fetch),
  account: firebaseAccountStore(),
  nowMillis: Date.now(),
});
