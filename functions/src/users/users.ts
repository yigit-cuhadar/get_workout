import { logger } from "firebase-functions/v2";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";

import { requireAdmin } from "../dashboard/run";
import { AccountStore, deleteUserData } from "../delete_account";
import { NEVER_EXPIRES_MS } from "../revenuecat_webhook";
import { Customer, PremiumGrants, RevenueCatError } from "./revenuecat_customers";

/** `details.reason` of a refusal, which the panel maps on. */
export const Reason = {
  invalidInput: "invalid-input",
  userNotFound: "user-not-found",
  /** An admin's own account: neither demoted nor deleted from the panel. */
  ownAccount: "own-account",
  /** RevenueCat refused or failed; `details.status` is its HTTP status. */
  revenueCatFailed: "revenuecat-failed",
} as const;

/** How many sign-ups a page of the list holds. */
export const PAGE_SIZE = 25;

/** A Firebase Auth user as the panel shows it. */
export interface AuthUser {
  uid: string;
  email: string | null;
  /** `password`, `google.com`, `apple.com`; none for a guest. */
  providers: string[];
  createdAtMillis: number;
  /** The last ID token refresh: the app was last open around then. */
  lastActiveAtMillis: number | null;
  admin: boolean;
}

/** `entitlements/{uid}`: the Premium the rules grant. */
export interface ServerPremium {
  premium: boolean;
  expiresAtMillis: number | null;
  productId: string | null;
  /** The latest RevenueCat event applied. */
  lastEventMillis: number | null;
}

export interface Activity {
  workouts: number;
  lastWorkoutMillis: number | null;
  /** The active program's name. */
  activeProgram: string | null;
}

/** Auth and Firestore, as far as the Users page reads and changes them. */
export interface UserDirectory {
  allUsers(): Promise<AuthUser[]>;
  user(uid: string): Promise<AuthUser | null>;
  userByEmail(email: string): Promise<AuthUser | null>;
  /** Sets or removes the `admin` claim, keeping the others. */
  setAdmin(uid: string, admin: boolean): Promise<void>;
  /** By uid; a uid without an `entitlements` document is left out. */
  serverPremium(uids: string[]): Promise<Map<string, ServerPremium>>;
  /** The latest workout's `finishedAt` by uid; none left out. */
  lastWorkouts(uids: string[]): Promise<Map<string, number>>;
  activity(uid: string): Promise<Activity>;
}

export interface UsersDeps {
  directory: UserDirectory;
  grants: PremiumGrants;
  account: AccountStore;
  nowMillis: number;
}

/** A row of the list. */
export interface UserRow {
  uid: string;
  email: string | null;
  guest: boolean;
  /** Whether the rules grant Premium now. */
  premium: boolean;
  signedUpMillis: number;
  lastWorkoutMillis: number | null;
}

/** Where the next page starts: after this sign-up. */
export interface Cursor {
  createdAtMillis: number;
  uid: string;
}

export interface UserDetail {
  uid: string;
  email: string | null;
  guest: boolean;
  providers: string[];
  admin: boolean;
  signedUpMillis: number;
  lastActiveMillis: number | null;
  server: ServerPremium | null;
  activity: Activity;
  /** Null unless [revenueCatState] is `ok`. */
  revenueCat: Customer | null;
  revenueCatState: "ok" | "no-customer" | "failed";
}

export type Duration = "week" | "month" | "year" | "lifetime";

const DURATIONS: Duration[] = ["week", "month", "year", "lifetime"];

/** When a grant of [duration] from [nowMillis] ends (UTC calendar). */
export function grantEnd(duration: Duration, nowMillis: number): number {
  const end = new Date(nowMillis);
  switch (duration) {
    case "week":
      end.setUTCDate(end.getUTCDate() + 7);
      break;
    case "month":
      end.setUTCMonth(end.getUTCMonth() + 1);
      break;
    case "year":
      end.setUTCFullYear(end.getUTCFullYear() + 1);
      break;
    case "lifetime":
      return NEVER_EXPIRES_MS;
  }
  return end.getTime();
}

type Auth = CallableRequest["auth"];
type Input = { [key: string]: unknown };

const invalid = (field: string) =>
  new HttpsError("invalid-argument", `Invalid ${field}.`, {
    reason: Reason.invalidInput,
    field,
  });

const input = (data: unknown): Input =>
  typeof data === "object" && data !== null ? (data as Input) : {};

const uidOf = (data: Input): string => {
  const { uid } = data;
  if (typeof uid !== "string" || uid.length === 0 || uid.length > 128) {
    throw invalid("uid");
  }
  return uid;
};

const notFound = () =>
  new HttpsError("not-found", "No such user.", {
    reason: Reason.userNotFound,
  });

/** Requires the admin claim; the admin's uid. */
const admin = (auth: Auth): string => {
  requireAdmin(auth);
  return (auth as NonNullable<Auth>).uid;
};

const existing = async (deps: UsersDeps, uid: string) => {
  const user = await deps.directory.user(uid);
  if (!user) throw notFound();
  return user;
};

const notOwn = (adminUid: string, uid: string) => {
  if (adminUid === uid) {
    throw new HttpsError(
      "failed-precondition",
      "Not on your own account.",
      { reason: Reason.ownAccount },
    );
  }
};

const isPremium = (server: ServerPremium | undefined, nowMillis: number) =>
  server !== undefined &&
  server.premium &&
  (server.expiresAtMillis === null || server.expiresAtMillis > nowMillis);

const newestFirst = (a: AuthUser, b: AuthUser) =>
  b.createdAtMillis - a.createdAtMillis || a.uid.localeCompare(b.uid);

const after = (user: AuthUser, cursor: Cursor) =>
  user.createdAtMillis < cursor.createdAtMillis ||
  (user.createdAtMillis === cursor.createdAtMillis &&
    user.uid.localeCompare(cursor.uid) > 0);

const parseCursor = (value: unknown): Cursor | null => {
  if (value === undefined || value === null) return null;
  const { createdAtMillis, uid } = input(value);
  if (typeof createdAtMillis !== "number" || typeof uid !== "string") {
    throw invalid("cursor");
  }
  return { createdAtMillis, uid };
};

/**
 * A page of sign-ups, newest first, starting after `data.cursor`; `next`
 * is null on the last page. Auth lists users in no useful order, so every
 * user is listed and sorted.
 */
export async function listUsers(
  auth: Auth,
  data: unknown,
  deps: UsersDeps,
): Promise<{ users: UserRow[]; next: Cursor | null }> {
  admin(auth);
  const cursor = parseCursor(input(data).cursor);
  const sorted = (await deps.directory.allUsers()).sort(newestFirst);
  const rest = cursor ? sorted.filter((u) => after(u, cursor)) : sorted;
  const page = rest.slice(0, PAGE_SIZE);
  const uids = page.map((u) => u.uid);
  const [premium, workouts] = await Promise.all([
    deps.directory.serverPremium(uids),
    deps.directory.lastWorkouts(uids),
  ]);
  const last = page.at(-1);
  return {
    users: page.map((u) => ({
      uid: u.uid,
      email: u.email,
      guest: u.providers.length === 0,
      premium: isPremium(premium.get(u.uid), deps.nowMillis),
      signedUpMillis: u.createdAtMillis,
      lastWorkoutMillis: workouts.get(u.uid) ?? null,
    })),
    next:
      rest.length > PAGE_SIZE && last
        ? { createdAtMillis: last.createdAtMillis, uid: last.uid }
        : null,
  };
}

/** The uid of the user whose email (with an `@`) or uid is `data.query`. */
export async function findUser(
  auth: Auth,
  data: unknown,
  deps: UsersDeps,
): Promise<{ uid: string }> {
  admin(auth);
  const { query } = input(data);
  if (typeof query !== "string" || query.trim() === "") throw invalid("query");
  const needle = query.trim();
  const user = needle.includes("@")
    ? await deps.directory.userByEmail(needle)
    : await deps.directory.user(needle);
  if (!user) throw notFound();
  return { uid: user.uid };
}

/**
 * Everything the user's page shows. RevenueCat failing (or the key
 * lacking a permission) leaves the rest: `revenueCatState` says so.
 */
export async function getUser(
  auth: Auth,
  data: unknown,
  deps: UsersDeps,
): Promise<UserDetail> {
  admin(auth);
  const uid = uidOf(input(data));
  const user = await existing(deps, uid);
  const [server, activity, revenueCat] = await Promise.all([
    deps.directory.serverPremium([uid]),
    deps.directory.activity(uid),
    deps.grants.customer(uid).then(
      (customer) => ({ customer, failed: false }),
      (error: unknown) => {
        logRevenueCat("customer read failed", uid, error);
        return { customer: null, failed: true };
      },
    ),
  ]);
  return {
    uid,
    email: user.email,
    guest: user.providers.length === 0,
    providers: user.providers,
    admin: user.admin,
    signedUpMillis: user.createdAtMillis,
    lastActiveMillis: user.lastActiveAtMillis,
    server: server.get(uid) ?? null,
    activity,
    revenueCat: revenueCat.customer,
    revenueCatState: revenueCat.failed
      ? "failed"
      : revenueCat.customer
        ? "ok"
        : "no-customer",
  };
}

const logRevenueCat = (message: string, uid: string, error: unknown) =>
  logger.error(
    message,
    error instanceof RevenueCatError
      ? { uid, path: error.path, status: error.status, body: error.body }
      : { uid, error: String(error) },
  );

const throughRevenueCat = async (
  uid: string,
  action: string,
  work: () => Promise<void>,
) => {
  try {
    await work();
  } catch (error) {
    logRevenueCat(`${action} failed`, uid, error);
    throw new HttpsError("unavailable", `RevenueCat: ${action} failed.`, {
      reason: Reason.revenueCatFailed,
      status: error instanceof RevenueCatError ? error.status : null,
    });
  }
};

/**
 * Grants promotional Premium for `data.duration` (week, month, year,
 * lifetime) in RevenueCat; the end time.
 */
export async function grantPremium(
  auth: Auth,
  data: unknown,
  deps: UsersDeps,
): Promise<{ expiresAtMillis: number }> {
  const by = admin(auth);
  const fields = input(data);
  const uid = uidOf(fields);
  const duration = fields.duration as Duration;
  if (!DURATIONS.includes(duration)) throw invalid("duration");
  await existing(deps, uid);
  const expiresAtMillis = grantEnd(duration, deps.nowMillis);
  await throughRevenueCat(uid, "grant", () =>
    deps.grants.grant(uid, expiresAtMillis),
  );
  logger.info("premium granted", { uid, by, duration, expiresAtMillis });
  return { expiresAtMillis };
}

/** Ends the user's promotional Premium in RevenueCat now. */
export async function revokePremium(
  auth: Auth,
  data: unknown,
  deps: UsersDeps,
): Promise<void> {
  const by = admin(auth);
  const uid = uidOf(input(data));
  await existing(deps, uid);
  await throughRevenueCat(uid, "revoke", () => deps.grants.revoke(uid));
  logger.info("premium revoked", { uid, by });
}

/**
 * Sets the `admin` claim to `data.admin`; it reaches the user's sign-in
 * when their token next refreshes (within an hour).
 */
export async function setAdmin(
  auth: Auth,
  data: unknown,
  deps: UsersDeps,
): Promise<void> {
  const by = admin(auth);
  const fields = input(data);
  const uid = uidOf(fields);
  if (typeof fields.admin !== "boolean") throw invalid("admin");
  notOwn(by, uid);
  await existing(deps, uid);
  await deps.directory.setAdmin(uid, fields.admin);
  logger.info("admin claim set", { uid, by, admin: fields.admin });
}

/**
 * Deletes the account as the app's own deletion does (`deleteUserData`).
 * A store subscription is not cancelled, and Apple's tokens are not
 * revoked: that needs the user's fresh Apple sign-in.
 */
export async function deleteUser(
  auth: Auth,
  data: unknown,
  deps: UsersDeps,
): Promise<void> {
  const by = admin(auth);
  const uid = uidOf(input(data));
  notOwn(by, uid);
  await deleteUserData(uid, deps.account);
  logger.info("account deleted by an admin", { uid, by });
}
