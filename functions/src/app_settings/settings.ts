import {
  ListVersionsOptions,
  ListVersionsResult,
  ParameterValueType,
  RemoteConfigParameter,
  RemoteConfigParameterValue,
  RemoteConfigTemplate,
  Version,
} from "firebase-admin/remote-config";
import { logger } from "firebase-functions/v2";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";

import { requireAdmin } from "../dashboard/run";

/**
 * `details.reason` of a refusal, which the panel maps on (never the
 * message).
 */
export const Reason = {
  notAdmin: "not-admin",
  invalidInput: "invalid-input",
  /** The template changed since the panel loaded it (`etag`). */
  stale: "stale",
  /**
   * The key's default is not a plain value (an experiment, a rollout or
   * a personalization) and is edited only in the console.
   */
  locked: "locked",
} as const;

type Kind = "choice" | "boolean" | "text" | "version";

interface KeySpec {
  kind: Kind;
  valueType: ParameterValueType;
  choices?: string[];
}

/**
 * The keys the panel edits: the app's Remote Config defaults
 * (`SubscriptionModule.remoteConfigDefaults`,
 * `AppGateModule.remoteConfigDefaults`). Every other parameter is left as
 * it is.
 */
export const KEYS: { [key: string]: KeySpec } = {
  paywall_layout: {
    kind: "choice",
    valueType: "STRING",
    choices: ["a", "b", "c"],
  },
  maintenance: { kind: "boolean", valueType: "BOOLEAN" },
  maintenance_message: { kind: "text", valueType: "STRING" },
  min_version_ios: { kind: "version", valueType: "STRING" },
  min_version_android: { kind: "version", valueType: "STRING" },
  recommended_version_ios: { kind: "version", valueType: "STRING" },
  recommended_version_android: { kind: "version", valueType: "STRING" },
};

/** Longest maintenance message, in UTF-16 code units like Dart's. */
export const MAX_TEXT = 300;

/** Empty (no rule) or dot-separated numbers, as the app gate reads them. */
const VERSION = /^\d{1,6}(\.\d{1,6}){0,3}$/;

/** How many versions the history lists, newest first. */
export const HISTORY_LENGTH = 20;

/** Starts the description of a version the panel published. */
const PANEL = "Admin panel";
const PANEL_DESCRIPTION = /^Admin panel · (.+?)(?: · restores version (\d+))?$/;

/**
 * What a parameter value is: a `value`, the app's own default
 * (`inAppDefault`, also for an absent parameter), or one the console
 * owns (`experiment`, `rollout`, `personalization`, with its `id`).
 */
export type Setting =
  | { kind: "value"; value: string }
  | { kind: "inAppDefault" }
  | { kind: "experiment" | "rollout" | "personalization"; id: string };

export interface KeyState {
  /** The default value, what every app gets outside the conditions. */
  current: Setting;
  /** Values under conditions (A/B tests among them), in template order. */
  conditional: { condition: string; setting: Setting }[];
}

export interface VersionInfo {
  number: number;
  updatedAtMillis: number | null;
  /** The admin's email for a panel publish, else the publisher's. */
  by: string | null;
  origin: "panel" | "console" | "other";
  /** The version this one restores or rolls back to. */
  restoredFrom: number | null;
}

export interface SettingsSnapshot {
  etag: string;
  version: VersionInfo;
  keys: { [key: string]: KeyState };
}

export interface HistoryEntry extends VersionInfo {
  /** Parameters whose values differ from the version before, sorted. */
  changed: string[];
  conditionsChanged: boolean;
  values: { [key: string]: Setting };
}

export interface PublishRequest {
  etag: string;
  /** New default values; null is the app's own default. */
  changes: { [key: string]: string | null };
  restoring: number | null;
}

/** The Admin SDK's `RemoteConfig`, as far as this file uses it. */
export interface RemoteConfigPort {
  getTemplate(): Promise<RemoteConfigTemplate>;
  validateTemplate(
    template: RemoteConfigTemplate,
  ): Promise<RemoteConfigTemplate>;
  publishTemplate(
    template: RemoteConfigTemplate,
  ): Promise<RemoteConfigTemplate>;
  listVersions(options?: ListVersionsOptions): Promise<ListVersionsResult>;
  getTemplateAtVersion(
    versionNumber: number | string,
  ): Promise<RemoteConfigTemplate>;
}

type Auth = CallableRequest["auth"];

const invalid = (field: string, message: string) =>
  new HttpsError("invalid-argument", message, {
    reason: Reason.invalidInput,
    field,
  });

const stale = () =>
  new HttpsError(
    "failed-precondition",
    "Remote Config changed since this page loaded.",
    { reason: Reason.stale },
  );

/** Why [value] is not a valid value of [key], or null. */
export function problemOf(key: string, value: string): string | null {
  const spec = KEYS[key];
  switch (spec.kind) {
    case "choice":
      return spec.choices?.includes(value)
        ? null
        : `must be one of ${spec.choices?.join(", ")}`;
    case "boolean":
      return value === "true" || value === "false"
        ? null
        : "must be true or false";
    case "text":
      return value.length <= MAX_TEXT
        ? null
        : `is longer than ${MAX_TEXT} characters`;
    case "version":
      return value === "" || VERSION.test(value)
        ? null
        : "must be empty or a version such as 1.2.0";
  }
}

/** The request's etag and changes, or an `invalid-input` error. */
export function parsePublish(data: unknown): PublishRequest {
  const input = (typeof data === "object" && data !== null ? data : {}) as {
    [key: string]: unknown;
  };
  const { etag, changes, restoring } = input;
  if (typeof etag !== "string" || etag.length === 0) {
    throw invalid("etag", "etag is missing.");
  }
  if (typeof changes !== "object" || changes === null) {
    throw invalid("changes", "changes must be an object.");
  }
  const entries = Object.entries(changes);
  if (entries.length === 0) throw invalid("changes", "Nothing to publish.");
  const parsed: { [key: string]: string | null } = {};
  for (const [key, value] of entries) {
    if (!Object.hasOwn(KEYS, key)) {
      throw invalid(key, `${key} is not a setting the panel edits.`);
    }
    if (value !== null && typeof value !== "string") {
      throw invalid(key, `${key} must be a string or null.`);
    }
    if (value !== null) {
      const problem = problemOf(key, value);
      if (problem !== null) throw invalid(key, `${key} ${problem}.`);
    }
    parsed[key] = value;
  }
  if (
    restoring !== undefined &&
    restoring !== null &&
    !(Number.isInteger(restoring) && (restoring as number) > 0)
  ) {
    throw invalid("restoring", "restoring must be a version number.");
  }
  return {
    etag,
    changes: parsed,
    restoring: (restoring as number | null | undefined) ?? null,
  };
}

/** [key]'s parameter, top-level or in a parameter group; undefined if none. */
function parameterOf(
  template: RemoteConfigTemplate,
  key: string,
): RemoteConfigParameter | undefined {
  if (Object.hasOwn(template.parameters, key)) return template.parameters[key];
  for (const group of Object.values(template.parameterGroups ?? {})) {
    if (Object.hasOwn(group.parameters, key)) return group.parameters[key];
  }
  return undefined;
}

/** Every parameter, top-level and in groups, by key. */
function allParameters(template: RemoteConfigTemplate) {
  const all: { [key: string]: RemoteConfigParameter } = {
    ...template.parameters,
  };
  for (const group of Object.values(template.parameterGroups ?? {})) {
    Object.assign(all, group.parameters);
  }
  return all;
}

export function settingOf(
  value: RemoteConfigParameterValue | undefined,
): Setting {
  if (value === undefined) return { kind: "inAppDefault" };
  if ("value" in value) return { kind: "value", value: value.value };
  if ("experimentValue" in value) {
    return { kind: "experiment", id: value.experimentValue.experimentId };
  }
  if ("rolloutValue" in value) {
    return { kind: "rollout", id: value.rolloutValue.rolloutId };
  }
  if ("personalizationValue" in value) {
    return {
      kind: "personalization",
      id: value.personalizationValue.personalizationId,
    };
  }
  return { kind: "inAppDefault" };
}

function keyStateOf(template: RemoteConfigTemplate, key: string): KeyState {
  const parameter = parameterOf(template, key);
  return {
    current: settingOf(parameter?.defaultValue),
    conditional: Object.entries(parameter?.conditionalValues ?? {}).map(
      ([condition, value]) => ({ condition, setting: settingOf(value) }),
    ),
  };
}

export function versionInfoOf(version: Version | undefined): VersionInfo {
  const panel = version?.description?.match(PANEL_DESCRIPTION);
  const rollback = version?.rollbackSource;
  const updatedAt = version?.updateTime ? Date.parse(version.updateTime) : NaN;
  return {
    number: Number(version?.versionNumber ?? 0),
    updatedAtMillis: Number.isNaN(updatedAt) ? null : updatedAt,
    by: panel ? panel[1] : (version?.updateUser?.email ?? null),
    origin: panel
      ? "panel"
      : version?.updateOrigin === "CONSOLE"
        ? "console"
        : "other",
    restoredFrom: panel?.[2]
      ? Number(panel[2])
      : rollback
        ? Number(rollback)
        : null,
  };
}

/** The template's known keys and its version, for the panel. */
export async function loadSettings(
  auth: Auth,
  remoteConfig: RemoteConfigPort,
): Promise<SettingsSnapshot> {
  requireAdmin(auth);
  const template = await remoteConfig.getTemplate();
  return {
    etag: template.etag,
    version: versionInfoOf(template.version),
    keys: Object.fromEntries(
      Object.keys(KEYS).map((key) => [key, keyStateOf(template, key)]),
    ),
  };
}

const isConflict = (error: unknown) => {
  const code = (error as { code?: unknown } | null)?.code;
  return (
    code === "remote-config/failed-precondition" ||
    code === "remote-config/aborted"
  );
};

/**
 * Publishes the request's default values onto the template as it was when
 * the panel loaded it ([PublishRequest.etag]); a template changed since,
 * in the console or another panel, is refused as `stale`. Only the
 * defaults of the changed keys are written: their conditional values
 * (A/B tests among them), every other parameter, the groups and the
 * conditions stay as they are. A key whose default the console owns
 * (an experiment, a rollout) is refused as `locked`.
 */
export async function publishSettings(
  auth: Auth,
  data: unknown,
  remoteConfig: RemoteConfigPort,
): Promise<VersionInfo> {
  requireAdmin(auth);
  const request = parsePublish(data);
  const template = await remoteConfig.getTemplate();
  if (template.etag !== request.etag) throw stale();
  for (const [key, value] of Object.entries(request.changes)) {
    const parameter = parameterOf(template, key);
    const kind = settingOf(parameter?.defaultValue).kind;
    if (kind !== "value" && kind !== "inAppDefault") {
      throw new HttpsError(
        "failed-precondition",
        `${key} is set by a ${kind} in the Firebase console.`,
        { reason: Reason.locked, field: key },
      );
    }
    if (parameter) {
      parameter.defaultValue =
        value === null ? { useInAppDefault: true } : { value };
    } else if (value !== null) {
      template.parameters[key] = {
        defaultValue: { value },
        valueType: KEYS[key].valueType,
      };
    }
  }
  const by = auth?.token.email ?? auth?.uid;
  template.version = {
    description:
      `${PANEL} · ${by}` +
      (request.restoring ? ` · restores version ${request.restoring}` : ""),
  };
  try {
    await remoteConfig.validateTemplate(template);
  } catch (error) {
    if (isConflict(error)) throw stale();
    throw new HttpsError(
      "invalid-argument",
      `Remote Config refused the template: ${(error as Error).message}`,
      { reason: Reason.invalidInput },
    );
  }
  let published: RemoteConfigTemplate;
  try {
    published = await remoteConfig.publishTemplate(template);
  } catch (error) {
    if (isConflict(error)) throw stale();
    throw error;
  }
  const version = versionInfoOf(published.version);
  logger.info("app settings published", {
    version: version.number,
    keys: Object.keys(request.changes),
    by: auth?.uid,
  });
  return version;
}

/** Keys sorted, so equal values compare equal however they were ordered. */
const stable = (value: unknown): string =>
  JSON.stringify(value, (_, v) =>
    v !== null && typeof v === "object" && !Array.isArray(v)
      ? Object.fromEntries(
          Object.entries(v).sort(([a], [b]) => (a < b ? -1 : 1)),
        )
      : v,
  );

/** The parameters whose values or type differ between two templates. */
export function changedBetween(
  before: RemoteConfigTemplate | undefined,
  after: RemoteConfigTemplate,
): { changed: string[]; conditionsChanged: boolean } {
  const old = before ? allParameters(before) : {};
  const now = allParameters(after);
  const keys = new Set([...Object.keys(old), ...Object.keys(now)]);
  const valuesOf = (p: RemoteConfigParameter | undefined) =>
    p && {
      defaultValue: p.defaultValue,
      conditionalValues: p.conditionalValues,
      valueType: p.valueType,
    };
  return {
    changed: [...keys]
      .filter(
        (key) => stable(valuesOf(old[key])) !== stable(valuesOf(now[key])),
      )
      .sort(),
    conditionsChanged:
      stable(before?.conditions ?? []) !== stable(after.conditions),
  };
}

/**
 * The latest [HISTORY_LENGTH] versions, newest first, each with what
 * changed since the version before it and its values of the known keys.
 */
export async function loadHistory(
  auth: Auth,
  remoteConfig: RemoteConfigPort,
): Promise<HistoryEntry[]> {
  requireAdmin(auth);
  // One more than shown, to tell what the oldest shown one changed.
  const { versions } = await remoteConfig.listVersions({
    pageSize: HISTORY_LENGTH + 1,
  });
  const templates = await Promise.all(
    versions.map((version) =>
      remoteConfig.getTemplateAtVersion(version.versionNumber ?? 0),
    ),
  );
  return versions.slice(0, HISTORY_LENGTH).map((version, i) => {
    const template = templates[i];
    return {
      ...versionInfoOf(version),
      ...changedBetween(templates[i + 1], template),
      values: Object.fromEntries(
        Object.keys(KEYS).map((key) => [
          key,
          settingOf(parameterOf(template, key)?.defaultValue),
        ]),
      ),
    };
  });
}
