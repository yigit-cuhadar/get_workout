import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { HttpsError } from "firebase-functions/v2/https";

import {
  AccountStore,
  Reason,
  deleteAccountOf,
  deleteUserFiles,
} from "./delete_account";

const now = 1_000_000;

type Auth = Parameters<typeof deleteAccountOf>[0];

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
    deleteFiles: step("files"),
    deleteAuthUser: step("auth"),
  };
  return { store, done };
}

describe("deleteAccountOf", () => {
  test("deletes documents, entitlement and files, then the sign-in", async () => {
    const { store, done } = fakeStore();
    await deleteAccountOf(caller("password", now - 10), store, now);
    assert.deepEqual(done.slice(0, 3).sort(), [
      "documents u1",
      "entitlement u1",
      "files u1",
    ]);
    assert.equal(done[3], "auth u1");
  });

  test("deletes the entitlement again after the sign-in", async () => {
    // A webhook event that found the user before the sign-in went may have
    // written it again.
    const { store, done } = fakeStore();
    await deleteAccountOf(caller("password", now), store, now);
    assert.equal(done[4], "entitlement u1");
  });

  test("an entitlement left at the end does not fail the deletion", async () => {
    const { store, done } = fakeStore();
    let calls = 0;
    store.deleteEntitlement = async (uid) => {
      if (++calls === 2) throw new Error("unavailable");
      done.push(`entitlement ${uid}`);
    };
    await deleteAccountOf(caller("password", now), store, now);
    assert.equal(done.at(-1), "auth u1");
  });

  test("refuses a caller who is not signed in", async () => {
    const { store, done } = fakeStore();
    await assert.rejects(
      deleteAccountOf(undefined, store, now),
      (error: HttpsError) => error.code === "unauthenticated",
    );
    assert.deepEqual(done, []);
  });

  test("asks for a recent sign-in and deletes nothing", async () => {
    const { store, done } = fakeStore();
    await assert.rejects(
      deleteAccountOf(caller("password", now - 301), store, now),
      (error: HttpsError) =>
        error.code === "failed-precondition" &&
        (error.details as { reason: string }).reason === Reason.recentSignIn,
    );
    assert.deepEqual(done, []);
  });

  test("a guest is deleted whenever it signed in", async () => {
    const { store, done } = fakeStore();
    await deleteAccountOf(caller("anonymous", 0), store, now);
    assert.equal(done.length, 5);
  });

  test("keeps the sign-in when data is left, so a retry can finish", async () => {
    const { store, done } = fakeStore(["files"]);
    await assert.rejects(
      deleteAccountOf(caller("password", now), store, now),
    );
    assert.ok(!done.includes("auth u1"));
  });

  test("says when only the sign-in is left, so the app retries", async () => {
    const { store, done } = fakeStore(["auth"]);
    await assert.rejects(
      deleteAccountOf(caller("password", now), store, now),
      (error: HttpsError) =>
        error.code === "internal" &&
        (error.details as { reason: string }).reason ===
          Reason.signInNotDeleted,
    );
    assert.equal(done.length, 3);
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
