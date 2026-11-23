import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { logger } from "firebase-functions/v2";

import { AccountStore } from "./delete_account";
import {
  GUEST_RETENTION_DAYS,
  GuestDirectory,
  MAX_DELETIONS_PER_RUN,
  SignIn,
  cleanUpGuests,
  isStaleGuest,
} from "./guest_cleanup";

const DAY_MS = 24 * 60 * 60 * 1000;
const now = 1_800_000_000_000;
const daysAgo = (days: number) => now - days * DAY_MS;

const guest = (uid: string, idleDays: number): SignIn => ({
  uid,
  providerCount: 0,
  lastActiveMs: daysAgo(idleDays),
});

/** Pages of [pages]; [entitled] uids have an entitlement on record. */
function fakeDirectory(pages: SignIn[][], entitled: string[] = []) {
  const directory: GuestDirectory = {
    async page(token) {
      const index = token === undefined ? 0 : Number(token);
      return {
        users: pages[index],
        pageToken: index + 1 < pages.length ? String(index + 1) : undefined,
      };
    },
    hasEntitlement: async (uid) => entitled.includes(uid),
  };
  return directory;
}

/** Records the uids whose sign-in was deleted; fails for [failing]. */
function fakeStore(failing: string[] = []) {
  const deleted: string[] = [];
  const ok = async () => {};
  const store: AccountStore = {
    deleteUserDocuments: ok,
    deleteEntitlement: ok,
    unlinkRevenueEvents: ok,
    deleteFiles: ok,
    async deleteAuthUser(uid) {
      if (failing.includes(uid)) throw new Error("refused");
      deleted.push(uid);
    },
  };
  return { store, deleted };
}

describe("isStaleGuest", () => {
  test(`a guest unused for over ${GUEST_RETENTION_DAYS} days`, () => {
    assert.equal(isStaleGuest(guest("g", GUEST_RETENTION_DAYS + 1), now), true);
    assert.equal(isStaleGuest(guest("g", GUEST_RETENTION_DAYS - 1), now), false);
  });

  test("never an account with a provider", () => {
    const linked = { ...guest("a", 400), providerCount: 1 };
    assert.equal(isStaleGuest(linked, now), false);
  });
});

describe("cleanUpGuests", () => {
  test("deletes stale guests across pages, keeping active ones and buyers", async () => {
    const directory = fakeDirectory(
      [
        [guest("old1", 120), guest("recent", 10)],
        [guest("buyer", 200), { ...guest("linked", 300), providerCount: 2 }],
        [guest("old2", 91)],
      ],
      ["buyer"],
    );
    const { store, deleted } = fakeStore();
    const result = await cleanUpGuests(directory, store, now);
    assert.deepEqual(deleted, ["old1", "old2"]);
    assert.deepEqual(result, { deleted: 2, failed: 0 });
  });

  test("a failure is logged and the run goes on", async (t) => {
    t.mock.method(logger, "error", () => {});
    const directory = fakeDirectory([[guest("bad", 100), guest("good", 100)]]);
    const { store, deleted } = fakeStore(["bad"]);
    const result = await cleanUpGuests(directory, store, now);
    assert.deepEqual(deleted, ["good"]);
    assert.deepEqual(result, { deleted: 1, failed: 1 });
  });

  test(`stops after ${MAX_DELETIONS_PER_RUN} per run`, async () => {
    const many = Array.from({ length: MAX_DELETIONS_PER_RUN + 5 }, (_, i) =>
      guest(`g${i}`, 100),
    );
    const { store, deleted } = fakeStore();
    const result = await cleanUpGuests(fakeDirectory([many]), store, now);
    assert.equal(deleted.length, MAX_DELETIONS_PER_RUN);
    assert.equal(result.deleted, MAX_DELETIONS_PER_RUN);
  });
});
