import assert from "node:assert/strict";
import { beforeEach, describe, test } from "node:test";

import {
  ListVersionsOptions,
  RemoteConfigTemplate,
  Version,
} from "firebase-admin/remote-config";
import { HttpsError } from "firebase-functions/v2/https";

import {
  HISTORY_LENGTH,
  MAX_TEXT,
  Reason,
  RemoteConfigPort,
  loadHistory,
  loadSettings,
  parsePublish,
  publishSettings,
} from "./settings";

type Auth = Parameters<typeof loadSettings>[0];

const admin = {
  uid: "admin-uid",
  token: { admin: true, email: "admin@example.com" },
  rawToken: "",
} as unknown as Auth;
const user = {
  uid: "user-uid",
  token: { email: "user@example.com" },
  rawToken: "",
} as unknown as Auth;

const clone = <T>(value: T): T => structuredClone(value);

/**
 * Remote Config in memory: a list of published templates, the last one
 * current, each with etag `etag-<version>`. A publish whose etag is not
 * the current one is refused as the API does.
 */
class FakeRemoteConfig implements RemoteConfigPort {
  versions: RemoteConfigTemplate[] = [];
  validated: RemoteConfigTemplate[] = [];
  refuseValidation: Error | null = null;

  constructor(first: Omit<RemoteConfigTemplate, "etag" | "version">) {
    this.push(first, {
      updateOrigin: "CONSOLE",
      updateUser: { email: "owner@example.com" },
    });
  }

  private push(
    template: Omit<RemoteConfigTemplate, "etag" | "version">,
    version: Version,
  ) {
    const number = this.versions.length + 1;
    const stored = {
      conditions: clone(template.conditions),
      parameters: clone(template.parameters),
      parameterGroups: clone(template.parameterGroups),
      etag: `etag-${number}`,
      version: {
        ...version,
        versionNumber: `${number}`,
        updateTime: new Date(Date.UTC(2026, 10, number)).toUTCString(),
      },
    };
    this.versions.push(stored);
    return clone(stored);
  }

  /** A console edit: a new version by someone else. */
  consoleEdit(edit: (template: RemoteConfigTemplate) => void) {
    const next = clone(this.current);
    edit(next);
    this.push(next, {
      updateOrigin: "CONSOLE",
      updateUser: { email: "owner@example.com" },
    });
  }

  get current() {
    return this.versions[this.versions.length - 1];
  }

  async getTemplate() {
    return clone(this.current);
  }

  async validateTemplate(template: RemoteConfigTemplate) {
    if (this.refuseValidation) throw this.refuseValidation;
    this.validated.push(clone(template));
    return clone(template);
  }

  async publishTemplate(template: RemoteConfigTemplate) {
    if (template.etag !== this.current.etag) {
      throw Object.assign(new Error("etag mismatch"), {
        code: "remote-config/failed-precondition",
      });
    }
    return this.push(template, {
      updateOrigin: "ADMIN_SDK_NODE",
      updateUser: { email: "functions@example.iam.gserviceaccount.com" },
      description: template.version?.description,
    });
  }

  async listVersions(options?: ListVersionsOptions) {
    const newestFirst = [...this.versions].reverse();
    return {
      versions: newestFirst
        .slice(0, options?.pageSize ?? 300)
        .map((t) => clone(t.version ?? {})),
    };
  }

  async getTemplateAtVersion(versionNumber: number | string) {
    return clone(this.versions[Number(versionNumber) - 1]);
  }
}

/**
 * A template like the dev project's: the paywall layout at the top level
 * with an A/B test condition, the app gate keys in a group, one parameter
 * the panel does not know.
 */
const template = (): Omit<RemoteConfigTemplate, "etag" | "version"> => ({
  conditions: [
    { name: "paywall_test_b", expression: "percent <= 50" },
    { name: "turkish", expression: "device.language in ['tr']" },
  ],
  parameters: {
    paywall_layout: {
      defaultValue: { value: "a" },
      conditionalValues: { paywall_test_b: { value: "b" } },
      valueType: "STRING",
    },
    other_flag: { defaultValue: { value: "x" }, valueType: "STRING" },
  },
  parameterGroups: {
    "App gate": {
      description: "Update and maintenance",
      parameters: {
        maintenance: {
          defaultValue: { useInAppDefault: true },
          valueType: "BOOLEAN",
        },
        maintenance_message: {
          defaultValue: { value: "" },
          conditionalValues: { turkish: { value: "Bakımdayız" } },
          valueType: "STRING",
        },
        min_version_ios: {
          defaultValue: { value: "1.0.0" },
          valueType: "STRING",
        },
      },
    },
  },
});

const reasonOf = (error: unknown) =>
  ((error as HttpsError).details as { reason: string; field?: string })?.reason;

describe("loadSettings", () => {
  test("refuses a caller without the admin claim", async () => {
    const fake = new FakeRemoteConfig(template());
    await assert.rejects(
      loadSettings(user, fake),
      (e) => reasonOf(e) === Reason.notAdmin,
    );
    await assert.rejects(
      loadSettings(undefined, fake),
      (e: HttpsError) => e.code === "unauthenticated",
    );
  });

  test("reads every known key, in groups too, with conditional values", async () => {
    const fake = new FakeRemoteConfig(template());
    const snapshot = await loadSettings(admin, fake);
    assert.equal(snapshot.etag, "etag-1");
    assert.equal(snapshot.version.number, 1);
    assert.equal(snapshot.version.origin, "console");
    assert.equal(snapshot.version.by, "owner@example.com");
    assert.deepEqual(Object.keys(snapshot.keys), [
      "paywall_layout",
      "maintenance",
      "maintenance_message",
      "min_version_ios",
      "min_version_android",
      "recommended_version_ios",
      "recommended_version_android",
    ]);
    assert.deepEqual(snapshot.keys.paywall_layout, {
      current: { kind: "value", value: "a" },
      conditional: [
        { condition: "paywall_test_b", setting: { kind: "value", value: "b" } },
      ],
    });
    assert.deepEqual(snapshot.keys.maintenance.current, {
      kind: "inAppDefault",
    });
    // Absent from the template: the app's own default.
    assert.deepEqual(snapshot.keys.min_version_android, {
      current: { kind: "inAppDefault" },
      conditional: [],
    });
  });

  test("shows an experiment-owned default as such", async () => {
    const fake = new FakeRemoteConfig(template());
    fake.consoleEdit((t) => {
      t.parameters.paywall_layout.defaultValue = {
        experimentValue: {
          experimentId: "7",
          variantValue: [{ variantId: "A", value: "a" }],
        },
      };
    });
    const snapshot = await loadSettings(admin, fake);
    assert.deepEqual(snapshot.keys.paywall_layout.current, {
      kind: "experiment",
      id: "7",
    });
  });
});

describe("parsePublish", () => {
  const field = (data: unknown) => {
    try {
      parsePublish(data);
    } catch (error) {
      assert.equal(reasonOf(error), Reason.invalidInput);
      return ((error as HttpsError).details as { field: string }).field;
    }
    assert.fail("accepted");
  };

  test("accepts valid values of every kind and null", () => {
    assert.deepEqual(
      parsePublish({
        etag: "e",
        changes: {
          paywall_layout: "c",
          maintenance: "true",
          maintenance_message: "Back soon.",
          min_version_ios: "1.2.0",
          recommended_version_ios: "",
          min_version_android: null,
        },
        restoring: 4,
      }),
      {
        etag: "e",
        changes: {
          paywall_layout: "c",
          maintenance: "true",
          maintenance_message: "Back soon.",
          min_version_ios: "1.2.0",
          recommended_version_ios: "",
          min_version_android: null,
        },
        restoring: 4,
      },
    );
  });

  test("refuses a missing etag, no changes and unknown keys", () => {
    assert.equal(field({ changes: { maintenance: "true" } }), "etag");
    assert.equal(field({ etag: "e", changes: {} }), "changes");
    assert.equal(
      field({ etag: "e", changes: { other_flag: "y" } }),
      "other_flag",
    );
    assert.equal(field({ etag: "e", changes: { __proto__: "y" } }), "changes");
  });

  test("refuses values that break a key's rule", () => {
    const bad = (key: string, value: unknown) =>
      field({ etag: "e", changes: { [key]: value } });
    assert.equal(bad("paywall_layout", "d"), "paywall_layout");
    assert.equal(bad("maintenance", "yes"), "maintenance");
    assert.equal(bad("maintenance", true), "maintenance");
    assert.equal(bad("min_version_ios", "v1.2"), "min_version_ios");
    assert.equal(bad("min_version_ios", "1.2.0+7"), "min_version_ios");
    assert.equal(
      bad("maintenance_message", "x".repeat(MAX_TEXT + 1)),
      "maintenance_message",
    );
    assert.equal(
      field({ etag: "e", changes: { maintenance: "true" }, restoring: 1.5 }),
      "restoring",
    );
  });
});

describe("publishSettings", () => {
  let fake: FakeRemoteConfig;

  beforeEach(() => {
    fake = new FakeRemoteConfig(template());
  });

  test("refuses a caller without the admin claim, publishing nothing", async () => {
    await assert.rejects(
      publishSettings(
        user,
        { etag: "etag-1", changes: { maintenance: "true" } },
        fake,
      ),
      (e) => reasonOf(e) === Reason.notAdmin,
    );
    assert.equal(fake.versions.length, 1);
  });

  test("writes only the changed defaults and keeps everything else", async () => {
    const version = await publishSettings(
      admin,
      {
        etag: "etag-1",
        changes: {
          paywall_layout: "c",
          maintenance_message: "Back soon.",
          min_version_android: "1.1.0",
        },
      },
      fake,
    );
    assert.deepEqual(version, {
      number: 2,
      updatedAtMillis: Date.UTC(2026, 10, 2),
      by: "admin@example.com",
      origin: "panel",
      restoredFrom: null,
    });
    const before = fake.versions[0];
    const after = fake.current;
    assert.deepEqual(after.conditions, before.conditions);
    assert.deepEqual(after.parameters.other_flag, before.parameters.other_flag);
    // The A/B test's conditional value survives.
    assert.deepEqual(after.parameters.paywall_layout, {
      defaultValue: { value: "c" },
      conditionalValues: { paywall_test_b: { value: "b" } },
      valueType: "STRING",
    });
    const group = after.parameterGroups["App gate"];
    assert.equal(group.description, "Update and maintenance");
    assert.deepEqual(group.parameters.maintenance_message, {
      defaultValue: { value: "Back soon." },
      conditionalValues: { turkish: { value: "Bakımdayız" } },
      valueType: "STRING",
    });
    assert.deepEqual(
      group.parameters.maintenance,
      before.parameterGroups["App gate"].parameters.maintenance,
    );
    // A key missing from the template is added at the top level.
    assert.deepEqual(after.parameters.min_version_android, {
      defaultValue: { value: "1.1.0" },
      valueType: "STRING",
    });
    assert.equal(fake.validated.length, 1);
  });

  test("null sets the app's own default; a restore is named", async () => {
    const version = await publishSettings(
      admin,
      {
        etag: "etag-1",
        changes: { min_version_ios: null, recommended_version_ios: null },
        restoring: 1,
      },
      fake,
    );
    assert.equal(version.restoredFrom, 1);
    assert.equal(
      fake.current.version?.description,
      "Admin panel · admin@example.com · restores version 1",
    );
    const group = fake.current.parameterGroups["App gate"];
    assert.deepEqual(group.parameters.min_version_ios.defaultValue, {
      useInAppDefault: true,
    });
    assert.ok(!("recommended_version_ios" in fake.current.parameters));
  });

  test("refuses as stale when the template changed since it was loaded", async () => {
    fake.consoleEdit((t) => {
      t.parameters.other_flag.defaultValue = { value: "y" };
    });
    await assert.rejects(
      publishSettings(
        admin,
        { etag: "etag-1", changes: { maintenance: "true" } },
        fake,
      ),
      (e) => reasonOf(e) === Reason.stale,
    );
    assert.equal(fake.versions.length, 2);
  });

  test("refuses as stale when the publish itself meets a newer etag", async () => {
    const racing = Object.create(fake) as FakeRemoteConfig;
    racing.validateTemplate = async (t) => {
      fake.consoleEdit(() => {});
      return t;
    };
    await assert.rejects(
      publishSettings(
        admin,
        { etag: "etag-1", changes: { maintenance: "true" } },
        racing,
      ),
      (e) => reasonOf(e) === Reason.stale,
    );
    assert.equal(fake.current.version?.updateOrigin, "CONSOLE");
  });

  test("refuses a key whose default an experiment owns", async () => {
    fake.consoleEdit((t) => {
      t.parameters.paywall_layout.defaultValue = {
        rolloutValue: { rolloutId: "r1", value: "b", percent: 10 },
      };
    });
    await assert.rejects(
      publishSettings(
        admin,
        { etag: "etag-2", changes: { paywall_layout: "c" } },
        fake,
      ),
      (e) => reasonOf(e) === Reason.locked,
    );
    assert.equal(fake.versions.length, 2);
  });

  test("a template Remote Config refuses is not published", async () => {
    fake.refuseValidation = Object.assign(new Error("bad"), {
      code: "remote-config/invalid-argument",
    });
    await assert.rejects(
      publishSettings(
        admin,
        { etag: "etag-1", changes: { maintenance: "true" } },
        fake,
      ),
      (e) => reasonOf(e) === Reason.invalidInput,
    );
    assert.equal(fake.versions.length, 1);
  });
});

describe("loadHistory", () => {
  test("refuses a caller without the admin claim", async () => {
    await assert.rejects(
      loadHistory(user, new FakeRemoteConfig(template())),
      (e) => reasonOf(e) === Reason.notAdmin,
    );
  });

  test("lists versions newest first with what each changed", async () => {
    const fake = new FakeRemoteConfig(template());
    await publishSettings(
      admin,
      { etag: "etag-1", changes: { min_version_ios: "1.1.0" } },
      fake,
    );
    fake.consoleEdit((t) => {
      t.conditions.push({ name: "beta", expression: "true" });
      t.parameters.other_flag.defaultValue = { value: "z" };
    });
    const history = await loadHistory(admin, fake);
    assert.deepEqual(
      history.map((v) => [
        v.number,
        v.origin,
        v.by,
        v.changed,
        v.conditionsChanged,
      ]),
      [
        [3, "console", "owner@example.com", ["other_flag"], true],
        [2, "panel", "admin@example.com", ["min_version_ios"], false],
        [
          1,
          "console",
          "owner@example.com",
          [
            "maintenance",
            "maintenance_message",
            "min_version_ios",
            "other_flag",
            "paywall_layout",
          ],
          true,
        ],
      ],
    );
    assert.deepEqual(history[1].values.min_version_ios, {
      kind: "value",
      value: "1.1.0",
    });
    assert.deepEqual(history[2].values.min_version_ios, {
      kind: "value",
      value: "1.0.0",
    });
    assert.deepEqual(history[2].values.min_version_android, {
      kind: "inAppDefault",
    });
  });

  test("lists at most HISTORY_LENGTH versions and diffs the oldest shown", async () => {
    const fake = new FakeRemoteConfig(template());
    for (let i = 0; i < HISTORY_LENGTH + 4; i++) {
      fake.consoleEdit((t) => {
        t.parameters.other_flag.defaultValue = { value: `${i}` };
      });
    }
    const history = await loadHistory(admin, fake);
    assert.equal(history.length, HISTORY_LENGTH);
    assert.equal(history[0].number, HISTORY_LENGTH + 5);
    assert.deepEqual(history[HISTORY_LENGTH - 1].changed, ["other_flag"]);
  });
});
