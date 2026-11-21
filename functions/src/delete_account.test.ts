import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { logger } from "firebase-functions/v2";
import { HttpsError } from "firebase-functions/v2/https";

import { AppleError } from "./apple";
import {
  AccountStore,
  Reason,
  deleteAccountOf,
  deleteUserFiles,
} from "./delete_account";

const now = 1_000_000;

/** Records the codes revoked at Apple; refuses when [error] is given. */
function fakeApple(error?: Error) {
  const revoked: string[] = [];
  const revoke = async (code: string) => {
    if (error) throw error;
    revoked.push(code);
  };
  return { revoke, revoked };
}

type Auth = Parameters<typeof deleteAccountOf>[0];

/** Deletes without an Apple code. */
const deleteOf = (auth: Auth, store: AccountStore, nowSeconds: number) =>
  deleteAccountOf(auth, undefined, store, fakeApple().revoke, nowSeconds);

const caller = (provider: string, authTime: number): Auth =>
  ({
    uid: "u1",
    token: { auth_time: authTime, firebase: { sign_in_provider: provider } },
    rawToken: "",
  }) as unknown as Auth;

/** Records the steps; fails the steps named in [failing]. */
function fakeStore(failing: string[] = []) {
  const done: string[] = [];
  const step = (name: string) => async (uid: string) => {
    if (failing.includes(name)) throw new Error(`${name} failed`);
    done.push(`${name} ${uid}`);
  };
  const store: AccountStore = {
    deleteUserDocuments: step("documents"),
    deleteEntitlement: step("entitlement"),
    unlinkRevenueEvents: step("revenue"),
    deleteFiles: step("files"),
    deleteAuthUser: step("auth"),
  };
  return { store, done };
}

describe("deleteAccountOf", () => {
  test("deletes documents, entitlement, files and revenue links, then the sign-in", async () => {
    const { store, done } = fakeStore();
    await deleteOf(caller("password", now - 10), store, now);
    assert.deepEqual(done.slice(0, 4).sort(), [
      "documents u1",
      "entitlement u1",
      "files u1",
      "revenue u1",
    ]);
    assert.equal(done[4], "auth u1");
  });

  test("clears the entitlement and revenue links again after the sign-in", async () => {
    // A webhook event that found the user before the sign-in went may have
    // written them again.
    const { store, done } = fakeStore();
    await deleteOf(caller("password", now), store, now);
    assert.deepEqual(done.slice(5).sort(), ["entitlement u1", "revenue u1"]);
  });

  test("data left at the end does not fail the deletion", async () => {
    const { store, done } = fakeStore();
    let calls = 0;
    store.deleteEntitlement = async (uid) => {
      if (++calls === 2) throw new Error("unavailable");
      done.push(`entitlement ${uid}`);
    };
    await deleteOf(caller("password", now), store, now);
    assert.equal(done[4], "auth u1");
    assert.equal(done.length, 6);
  });

  test("refuses a caller who is not signed in", async () => {
    const { store, done } = fakeStore();
    await assert.rejects(
      deleteOf(undefined, store, now),
      (error: HttpsError) => error.code === "unauthenticated",
    );
    assert.deepEqual(done, []);
  });

  test("asks for a recent sign-in and deletes nothing", async () => {
    const { store, done } = fakeStore();
    await assert.rejects(
      deleteOf(caller("password", now - 301), store, now),
      (error: HttpsError) =>
        error.code === "failed-precondition" &&
        (error.details as { reason: string }).reason === Reason.recentSignIn,
    );
    assert.deepEqual(done, []);
  });

  test("a guest is deleted whenever it signed in", async () => {
    const { store, done } = fakeStore();
    await deleteOf(caller("anonymous", 0), store, now);
    assert.equal(done.length, 7);
  });

  test("keeps the sign-in when data is left, so a retry can finish", async () => {
    const { store, done } = fakeStore(["files"]);
    await assert.rejects(deleteOf(caller("password", now), store, now));
    assert.ok(!done.includes("auth u1"));
  });

  test("says when only the sign-in is left, so the app retries", async () => {
    const { store, done } = fakeStore(["auth"]);
    await assert.rejects(
      deleteOf(caller("password", now), store, now),
      (error: HttpsError) =>
        error.code === "internal" &&
        (error.details as { reason: string }).reason ===
          Reason.signInNotDeleted,
    );
    assert.equal(done.length, 4);
  });
});

describe("deleteAccountOf with an Apple code", () => {
  test("revokes at Apple before deleting anything", async () => {
    const { store, done } = fakeStore();
    const apple = fakeApple();
    await deleteAccountOf(
      caller("apple.com", now),
      "code-1",
      store,
      async (code) => {
        assert.deepEqual(done, []);
        await apple.revoke(code);
      },
      now,
    );
    assert.deepEqual(apple.revoked, ["code-1"]);
    assert.equal(done.length, 7);
  });

  test("a refused revocation logs Apple's answer, deleting nothing", async (t) => {
    const logged = t.mock.method(logger, "error", () => {});
    const { store, done } = fakeStore();
    const apple = fakeApple(
      new AppleError("token", 400, '{"error":"invalid_grant"}'),
    );
    await assert.rejects(
      deleteAccountOf(
        caller("apple.com", now),
        "code-1",
        store,
        apple.revoke,
        now,
      ),
      (error: HttpsError) =>
        error.code === "failed-precondition" &&
        (error.details as { reason: string }).reason ===
          Reason.appleRevokeFailed,
    );
    assert.deepEqual(done, []);
    const [, fields] = logged.mock.calls[0].arguments;
    assert.deepEqual(fields, {
      uid: "u1",
      endpoint: "token",
      status: 400,
      body: '{"error":"invalid_grant"}',
    });
    assert.ok(!JSON.stringify(logged.mock.calls).includes("code-1"));
  });

  test("an old sign-in is refused before asking Apple", async () => {
    const { store } = fakeStore();
    const apple = fakeApple();
    await assert.rejects(
      deleteAccountOf(
        caller("apple.com", now - 301),
        "code-1",
        store,
        apple.revoke,
        now,
      ),
      (error: HttpsError) =>
        (error.details as { reason: string }).reason === Reason.recentSignIn,
    );
    assert.deepEqual(apple.revoked, []);
  });

  test("without a code nothing is revoked", async () => {
    const { store, done } = fakeStore();
    const apple = fakeApple();
    await deleteAccountOf(
      caller("apple.com", now),
      undefined,
      store,
      apple.revoke,
      now,
    );
    assert.deepEqual(apple.revoked, []);
    assert.equal(done.length, 7);
  });

  test("a code that is not a string is refused, deleting nothing", async () => {
    const { store, done } = fakeStore();
    const apple = fakeApple();
    await assert.rejects(
      deleteAccountOf(caller("apple.com", now), 42, store, apple.revoke, now),
      (error: HttpsError) => error.code === "invalid-argument",
    );
    assert.deepEqual([...done, ...apple.revoked], []);
  });
});

describe("deleteUserFiles", () => {
  test("deletes the user's folder only", async () => {
    const prefixes: string[] = [];
    await deleteUserFiles(
      () => ({
        deleteFiles: async ({ prefix }) => prefixes.push(prefix),
      }),
      "u1",
    );
    assert.deepEqual(prefixes, ["users/u1/"]);
  });

  test("a missing default bucket is nothing to delete", async () => {
    await deleteUserFiles(
      () => ({
        deleteFiles: async () => {
          throw Object.assign(new Error("Not Found"), { code: 404 });
        },
      }),
      "u1",
    );
    await deleteUserFiles(() => {
      throw new Error("Bucket name not specified or invalid.");
    }, "u1");
  });

  test("other failures fail the deletion", async () => {
    await assert.rejects(
      deleteUserFiles(
        () => ({
          deleteFiles: async () => {
            throw Object.assign(new Error("Forbidden"), { code: 403 });
          },
        }),
        "u1",
      ),
    );
  });
});
