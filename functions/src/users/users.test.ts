import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { HttpsError } from "firebase-functions/v2/https";

import { AccountStore } from "../delete_account";
import { NEVER_EXPIRES_MS } from "../revenuecat_webhook";
import { Customer, PremiumGrants, RevenueCatError } from "./revenuecat_customers";
import {
  AuthUser,
  DeviceDoc,
  PAGE_SIZE,
  Reason,
  ServerPremium,
  UserDirectory,
  UsersDeps,
  deleteUser,
  findUser,
  getUser,
  grantEnd,
  grantPremium,
  listUsers,
  revokePremium,
  setAdmin,
} from "./users";

const now = Date.UTC(2026, 10, 21, 12);
const day = 24 * 60 * 60 * 1000;

type Auth = Parameters<typeof listUsers>[0];

const caller = (claims: Record<string, unknown> = { admin: true }): Auth =>
  ({ uid: "admin1", token: claims, rawToken: "" }) as unknown as Auth;

const user = (uid: string, overrides: Partial<AuthUser> = {}): AuthUser => ({
  uid,
  email: `${uid}@example.com`,
  providers: ["password"],
  createdAtMillis: now - day,
  lastActiveAtMillis: now,
  admin: false,
  ...overrides,
});

const customer: Customer = {
  premium: { expiresAtMillis: now + day },
  subscriptions: [],
};

const iphone: DeviceDoc = {
  model: "iPhone15,2",
  platform: "ios",
  osVersion: "18.1",
  appVersion: "1.0.0+12",
  lastSeenMillis: now,
};

/** Auth, Firestore and RevenueCat in memory, recording every change. */
function fakeDeps(
  users: AuthUser[],
  options: {
    premium?: Map<string, ServerPremium>;
    workouts?: Map<string, number>;
    platforms?: Map<string, string>;
    customer?: () => Promise<Customer | null>;
    grantError?: Error;
  } = {},
) {
  const changes: string[] = [];
  const byUid = new Map(users.map((u) => [u.uid, u]));
  const directory: UserDirectory = {
    allUsers: async () => [...users],
    user: async (uid) => byUid.get(uid) ?? null,
    userByEmail: async (email) =>
      users.find((u) => u.email === email) ?? null,
    async setAdmin(uid, admin) {
      changes.push(`admin ${uid} ${admin}`);
    },
    serverPremium: async (uids) =>
      new Map(
        [...(options.premium ?? new Map())].filter(([uid]) =>
          uids.includes(uid),
        ),
      ),
    lastWorkouts: async () => options.workouts ?? new Map(),
    activity: async () => ({
      workouts: 3,
      lastWorkoutMillis: now - day,
      activeProgram: "Push pull legs",
    }),
    devices: async () => [iphone],
    lastPlatforms: async () => options.platforms ?? new Map(),
  };
  const grants: PremiumGrants = {
    customer: options.customer ?? (async () => customer),
    async grant(uid, expiresAtMillis) {
      if (options.grantError) throw options.grantError;
      changes.push(`grant ${uid} ${expiresAtMillis}`);
    },
    async revoke(uid) {
      if (options.grantError) throw options.grantError;
      changes.push(`revoke ${uid}`);
    },
  };
  const step = (name: string) => async (uid: string) => {
    changes.push(`${name} ${uid}`);
  };
  const account: AccountStore = {
    deleteUserDocuments: step("documents"),
    deleteEntitlement: step("entitlement"),
    unlinkRevenueEvents: step("revenue"),
    deleteFiles: step("files"),
    deleteAuthUser: step("auth"),
  };
  const deps: UsersDeps = { directory, grants, account, nowMillis: now };
  return { deps, changes };
}

/** The `details.reason` [work] is refused with. */
async function reasonOf(work: Promise<unknown>): Promise<unknown> {
  try {
    await work;
  } catch (error) {
    assert.ok(error instanceof HttpsError);
    return (error.details as { reason?: unknown } | undefined)?.reason;
  }
  assert.fail("not refused");
}

describe("every function", () => {
  const { deps } = fakeDeps([user("u1")]);
  const calls = [
    (auth: Auth) => listUsers(auth, {}, deps),
    (auth: Auth) => findUser(auth, { query: "u1" }, deps),
    (auth: Auth) => getUser(auth, { uid: "u1" }, deps),
    (auth: Auth) => grantPremium(auth, { uid: "u1", duration: "week" }, deps),
    (auth: Auth) => revokePremium(auth, { uid: "u1" }, deps),
    (auth: Auth) => setAdmin(auth, { uid: "u1", admin: true }, deps),
    (auth: Auth) => deleteUser(auth, { uid: "u1" }, deps),
  ];

  test("refuses a caller without the admin claim", async () => {
    for (const call of calls) {
      assert.equal(await reasonOf(call(caller({}))), "not-admin");
    }
  });

  test("refuses no caller", async () => {
    for (const call of calls) {
      await assert.rejects(call(undefined), { code: "unauthenticated" });
    }
  });
});

describe("listUsers", () => {
  test("pages sign-ups newest first, with Premium and the last workout", async () => {
    const users = Array.from({ length: PAGE_SIZE + 2 }, (_, i) =>
      user(`u${String(i).padStart(2, "0")}`, { createdAtMillis: now - i }),
    );
    const { deps } = fakeDeps([...users].reverse(), {
      premium: new Map([
        ["u00", premium(now + day)],
        ["u01", premium(now - 1)],
      ]),
      workouts: new Map([["u00", now - day]]),
      platforms: new Map([["u00", "android"]]),
    });

    const first = await listUsers(caller(), {}, deps);
    assert.equal(first.users.length, PAGE_SIZE);
    assert.equal(first.users[0].uid, "u00");
    assert.equal(first.users[0].premium, true);
    assert.equal(first.users[0].lastWorkoutMillis, now - day);
    assert.equal(first.users[1].premium, false, "expired");
    assert.equal(first.users[1].lastWorkoutMillis, null);
    assert.equal(first.users[0].platform, "android");
    assert.equal(first.users[1].platform, null);
    assert.deepEqual(first.next, {
      createdAtMillis: now - (PAGE_SIZE - 1),
      uid: `u${PAGE_SIZE - 1}`,
    });

    const second = await listUsers(caller(), { cursor: first.next }, deps);
    assert.deepEqual(
      second.users.map((u) => u.uid),
      [`u${PAGE_SIZE}`, `u${PAGE_SIZE + 1}`],
    );
    assert.equal(second.next, null);
  });

  test("orders sign-ups of the same time by uid, across pages", async () => {
    const same = Array.from({ length: PAGE_SIZE + 1 }, (_, i) =>
      user(`s${String(i).padStart(2, "0")}`, { createdAtMillis: now }),
    );
    const { deps } = fakeDeps(same);
    const first = await listUsers(caller(), {}, deps);
    const second = await listUsers(caller(), { cursor: first.next }, deps);
    assert.deepEqual(
      second.users.map((u) => u.uid),
      [`s${PAGE_SIZE}`],
    );
  });

  test("marks a guest, with no email", async () => {
    const { deps } = fakeDeps([user("g", { email: null, providers: [] })]);
    const { users } = await listUsers(caller(), {}, deps);
    assert.equal(users[0].guest, true);
    assert.equal(users[0].email, null);
  });

  test("refuses a cursor that is not one", async () => {
    const { deps } = fakeDeps([]);
    assert.equal(
      await reasonOf(listUsers(caller(), { cursor: { uid: 1 } }, deps)),
      Reason.invalidInput,
    );
  });
});

const premium = (expiresAtMillis: number): ServerPremium => ({
  premium: true,
  expiresAtMillis,
  productId: "monthly",
  lastEventMillis: now - day,
});

describe("findUser", () => {
  const { deps } = fakeDeps([user("u1")]);

  test("finds by email or uid", async () => {
    assert.deepEqual(
      await findUser(caller(), { query: " u1@example.com " }, deps),
      { uid: "u1" },
    );
    assert.deepEqual(await findUser(caller(), { query: "u1" }, deps), {
      uid: "u1",
    });
  });

  test("says when nobody has it", async () => {
    assert.equal(
      await reasonOf(findUser(caller(), { query: "x@example.com" }, deps)),
      Reason.userNotFound,
    );
    assert.equal(
      await reasonOf(findUser(caller(), { query: " " }, deps)),
      Reason.invalidInput,
    );
  });
});

describe("getUser", () => {
  test("joins Auth, Firestore and RevenueCat", async () => {
    const { deps } = fakeDeps([user("u1", { admin: true })], {
      premium: new Map([["u1", premium(now + day)]]),
    });
    const detail = await getUser(caller(), { uid: "u1" }, deps);
    assert.equal(detail.admin, true);
    assert.equal(detail.guest, false);
    assert.deepEqual(detail.server, premium(now + day));
    assert.equal(detail.activity.activeProgram, "Push pull legs");
    assert.deepEqual(detail.devices, [iphone]);
    assert.deepEqual(detail.revenueCat, customer);
    assert.equal(detail.revenueCatState, "ok");
  });

  test("shows the rest when RevenueCat fails or has no customer", async () => {
    const failing = fakeDeps([user("u1")], {
      customer: async () => {
        throw new RevenueCatError("/customers/u1", 403, "{}");
      },
    });
    const failed = await getUser(caller(), { uid: "u1" }, failing.deps);
    assert.equal(failed.revenueCatState, "failed");
    assert.equal(failed.revenueCat, null);
    assert.equal(failed.server, null);

    const none = fakeDeps([user("u1")], { customer: async () => null });
    const detail = await getUser(caller(), { uid: "u1" }, none.deps);
    assert.equal(detail.revenueCatState, "no-customer");
  });

  test("refuses an unknown uid", async () => {
    const { deps } = fakeDeps([]);
    assert.equal(
      await reasonOf(getUser(caller(), { uid: "nobody" }, deps)),
      Reason.userNotFound,
    );
    assert.equal(
      await reasonOf(getUser(caller(), { uid: 5 }, deps)),
      Reason.invalidInput,
    );
  });
});

describe("grantEnd", () => {
  test("adds a week, a calendar month or year, or never ends", () => {
    assert.equal(grantEnd("week", now), now + 7 * day);
    assert.equal(grantEnd("month", now), Date.UTC(2026, 11, 21, 12));
    assert.equal(grantEnd("year", now), Date.UTC(2027, 10, 21, 12));
    assert.equal(grantEnd("lifetime", now), NEVER_EXPIRES_MS);
  });
});

describe("grantPremium and revokePremium", () => {
  test("grant RevenueCat's promotional Premium until the duration's end", async () => {
    const { deps, changes } = fakeDeps([user("u1")]);
    const granted = await grantPremium(
      caller(),
      { uid: "u1", duration: "month" },
      deps,
    );
    assert.equal(granted.expiresAtMillis, grantEnd("month", now));
    await revokePremium(caller(), { uid: "u1" }, deps);
    assert.deepEqual(changes, [
      `grant u1 ${grantEnd("month", now)}`,
      "revoke u1",
    ]);
  });

  test("refuse another duration or an unknown user", async () => {
    const { deps, changes } = fakeDeps([user("u1")]);
    assert.equal(
      await reasonOf(
        grantPremium(caller(), { uid: "u1", duration: "day" }, deps),
      ),
      Reason.invalidInput,
    );
    assert.equal(
      await reasonOf(
        grantPremium(caller(), { uid: "u2", duration: "week" }, deps),
      ),
      Reason.userNotFound,
    );
    assert.equal(
      await reasonOf(revokePremium(caller(), { uid: "u2" }, deps)),
      Reason.userNotFound,
    );
    assert.deepEqual(changes, []);
  });

  test("carry RevenueCat's status when it refuses", async () => {
    const { deps } = fakeDeps([user("u1")], {
      grantError: new RevenueCatError("/x", 403, "{}"),
    });
    for (const work of [
      grantPremium(caller(), { uid: "u1", duration: "week" }, deps),
      revokePremium(caller(), { uid: "u1" }, deps),
    ]) {
      await assert.rejects(work, (error: HttpsError) => {
        assert.equal(error.code, "unavailable");
        assert.deepEqual(error.details, {
          reason: Reason.revenueCatFailed,
          status: 403,
        });
        return true;
      });
    }
  });
});

describe("setAdmin", () => {
  test("sets or removes the claim", async () => {
    const { deps, changes } = fakeDeps([user("u1")]);
    await setAdmin(caller(), { uid: "u1", admin: true }, deps);
    await setAdmin(caller(), { uid: "u1", admin: false }, deps);
    assert.deepEqual(changes, ["admin u1 true", "admin u1 false"]);
  });

  test("refuses the caller's own account, a missing flag or user", async () => {
    const { deps, changes } = fakeDeps([user("u1"), user("admin1")]);
    assert.equal(
      await reasonOf(setAdmin(caller(), { uid: "admin1", admin: false }, deps)),
      Reason.ownAccount,
    );
    assert.equal(
      await reasonOf(setAdmin(caller(), { uid: "u1" }, deps)),
      Reason.invalidInput,
    );
    assert.equal(
      await reasonOf(setAdmin(caller(), { uid: "u2", admin: true }, deps)),
      Reason.userNotFound,
    );
    assert.deepEqual(changes, []);
  });
});

describe("deleteUser", () => {
  test("deletes as the app's own deletion does, the sign-in after the data", async () => {
    const { deps, changes } = fakeDeps([user("u1")]);
    await deleteUser(caller(), { uid: "u1" }, deps);
    assert.deepEqual(changes.slice(0, 4).sort(), [
      "documents u1",
      "entitlement u1",
      "files u1",
      "revenue u1",
    ]);
    assert.equal(changes[4], "auth u1");
  });

  test("refuses the caller's own account", async () => {
    const { deps, changes } = fakeDeps([user("admin1")]);
    assert.equal(
      await reasonOf(deleteUser(caller(), { uid: "admin1" }, deps)),
      Reason.ownAccount,
    );
    assert.deepEqual(changes, []);
  });
});
