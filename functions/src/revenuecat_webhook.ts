import { createHash, timingSafeEqual } from "node:crypto";

import { getAuth } from "firebase-admin/auth";
import {
  DocumentData,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { defineSecret, projectID } from "firebase-functions/params";
import { onRequest } from "firebase-functions/v2/https";

/**
 * The exact `Authorization` header value set on the webhook in the
 * RevenueCat dashboard; RevenueCat sends it with every event.
 */
export const webhookAuthorization = defineSecret(
  "REVENUECAT_WEBHOOK_AUTHORIZATION",
);

/** The RevenueCat entitlement every Premium product is attached to. */
export const PREMIUM_ENTITLEMENT = "premium";

/** The prefix of the ids RevenueCat makes up before a user is identified. */
const ANONYMOUS_PREFIX = "$RCAnonymousID:";

/**
 * The expiry written for a premium purchase without one (a lifetime
 * product): the last day Firestore timestamps hold, as the rules compare it.
 */
export const NEVER_EXPIRES_MS = Date.UTC(9999, 11, 31);

/**
 * Events after which the user has Premium until the event's expiry: a
 * cancelled, paused or failing subscription runs to the end of what was
 * paid (or the grace period). A refund arrives as a CANCELLATION whose
 * expiry is already past.
 */
const GRANTING = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "PRODUCT_CHANGE",
  "UNCANCELLATION",
  "NON_RENEWING_PURCHASE",
  "CANCELLATION",
  "BILLING_ISSUE",
  "SUBSCRIPTION_PAUSED",
  "SUBSCRIPTION_EXTENDED",
  "TEMPORARY_ENTITLEMENT_GRANT",
  "REFUND_REVERSED",
]);

/** Every event type that may change an entitlement. */
const HANDLED = new Set([...GRANTING, "EXPIRATION", "TRANSFER"]);

/** `reason` in every response body, for RevenueCat's delivery log. */
export const Reason = {
  applied: "applied",
  unauthorized: "unauthorized",
  methodNotAllowed: "method-not-allowed",
  notJson: "not-json",
  invalidEvent: "invalid-event",
  testEvent: "test-event",
  unhandledType: "unhandled-type",
  sandboxIgnored: "sandbox-ignored",
  notPremium: "not-premium",
  /** Only anonymous or unusable RevenueCat ids. */
  noUser: "no-user",
  /** No Auth user: a deleted account is never written again. */
  deletedUser: "deleted-user",
  /** An event older than the last one applied for the user. */
  stale: "stale",
  /** The last event applied, delivered again. */
  duplicate: "duplicate",
  /** A transfer with nothing known to move. */
  nothingToTransfer: "nothing-to-transfer",
  /** Firestore or Auth failed; RevenueCat retries. */
  retry: "retry",
} as const;

type ReasonValue = (typeof Reason)[keyof typeof Reason];

/** A RevenueCat webhook event, as far as this function reads it. */
export interface RevenueCatEvent {
  id: string;
  type: string;
  timestampMs: number;
  environment?: string;
  appUserId?: string;
  originalAppUserId?: string;
  aliases: string[];
  /** Null when the product grants no entitlement. */
  entitlementIds: string[] | null;
  productId?: string;
  /** Null for a purchase that never expires. */
  expirationMs: number | null;
  gracePeriodExpirationMs: number | null;
  transferredFrom: string[];
  transferredTo: string[];
}

/** `entitlements/{uid}`, with `expiresAt` in milliseconds. */
export interface StoredEntitlement {
  premium: boolean;
  expiresAtMs: number;
  /** Absent when only a transfer away from the user was recorded. */
  productId?: string;
  /** `event_timestamp_ms` of the last event applied. */
  lastEventMs: number;
  lastEventId: string;
}

/** What one event writes, by uid, or why it writes nothing. */
export interface Plan {
  writes: Map<string, StoredEntitlement>;
  reason: ReasonValue;
}

export interface EntitlementStore {
  /** Whether Auth has a user [uid]; throws when Auth cannot tell. */
  userExists(uid: string): Promise<boolean>;
  /**
   * In one transaction: reads `entitlements/{uid}` of each of [uids],
   * passes them to [decide] and writes its plan.
   */
  apply(
    uids: string[],
    decide: (stored: Map<string, StoredEntitlement | undefined>) => Plan,
  ): Promise<Plan>;
  delete(uid: string): Promise<void>;
}

export interface WebhookRequest {
  method: string;
  isJson: boolean;
  authorization: string | undefined;
  body: unknown;
}

export interface WebhookResponse {
  status: number;
  body: { reason: ReasonValue };
}

const respond = (status: number, reason: ReasonValue): WebhookResponse => ({
  status,
  body: { reason },
});

/** Compares in constant time, whatever the lengths. */
export const sameSecret = (given: string | undefined, expected: string) => {
  if (given === undefined || expected.length === 0) return false;
  const digest = (value: string) => createHash("sha256").update(value).digest();
  return timingSafeEqual(digest(given), digest(expected));
};

const isMillis = (value: unknown): value is number =>
  typeof value === "number" &&
  Number.isSafeInteger(value) &&
  value >= 0 &&
  value <= NEVER_EXPIRES_MS;

const strings = (value: unknown): string[] =>
  Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];

const optionalString = (value: unknown): string | undefined =>
  typeof value === "string" ? value : undefined;

/** The event in a webhook body, or null when it is not one. */
export function parseEvent(body: unknown): RevenueCatEvent | null {
  const event = (body as { event?: unknown } | null)?.event;
  if (typeof event !== "object" || event === null) return null;
  const fields = event as { [key: string]: unknown };
  const { id, type, event_timestamp_ms: timestampMs } = fields;
  if (typeof id !== "string" || id.length === 0) return null;
  if (typeof type !== "string" || !isMillis(timestampMs)) return null;
  const nullableMillis = (value: unknown): number | null | undefined =>
    value === null || value === undefined
      ? null
      : isMillis(value)
        ? value
        : undefined;
  const expirationMs = nullableMillis(fields.expiration_at_ms);
  const gracePeriodExpirationMs = nullableMillis(
    fields.grace_period_expiration_at_ms,
  );
  if (expirationMs === undefined || gracePeriodExpirationMs === undefined) {
    return null;
  }
  return {
    id,
    type,
    timestampMs,
    environment: optionalString(fields.environment),
    appUserId: optionalString(fields.app_user_id),
    originalAppUserId: optionalString(fields.original_app_user_id),
    aliases: strings(fields.aliases),
    entitlementIds: Array.isArray(fields.entitlement_ids)
      ? strings(fields.entitlement_ids)
      : null,
    productId: optionalString(fields.product_id),
    expirationMs,
    gracePeriodExpirationMs,
    transferredFrom: strings(fields.transferred_from),
    transferredTo: strings(fields.transferred_to),
  };
}

/**
 * Whether [id] can be a Firebase uid: the app identifies the store user by
 * uid, so anything else (RevenueCat's anonymous ids) is never written.
 */
export const isUid = (id: string | undefined): id is string =>
  id !== undefined &&
  id.length > 0 &&
  id.length <= 128 &&
  !id.includes("/") &&
  !id.startsWith(ANONYMOUS_PREFIX);

/**
 * The uid an event is about: `app_user_id`, or else the one uid among
 * `original_app_user_id` and `aliases`; none when there is no uid or more
 * than one.
 */
export function targetUid(event: RevenueCatEvent): string | undefined {
  if (isUid(event.appUserId)) return event.appUserId;
  const uids = new Set(
    [event.originalAppUserId, ...event.aliases].filter(isUid),
  );
  return uids.size === 1 ? [...uids][0] : undefined;
}

/** Why [event] must not change [stored], if it must not. */
function staleness(
  event: RevenueCatEvent,
  stored: StoredEntitlement | undefined,
): ReasonValue | undefined {
  if (stored === undefined) return undefined;
  if (event.timestampMs < stored.lastEventMs) return Reason.stale;
  const same =
    event.timestampMs === stored.lastEventMs && event.id === stored.lastEventId;
  return same ? Reason.duplicate : undefined;
}

/** What a premium event other than TRANSFER writes for [uid]. */
export function planUpdate(
  event: RevenueCatEvent,
  uid: string,
  stored: StoredEntitlement | undefined,
): Plan {
  const skip = staleness(event, stored);
  if (skip) return { writes: new Map(), reason: skip };
  const { type, timestampMs, expirationMs } = event;
  let premium = true;
  let expiresAtMs: number;
  if (type === "EXPIRATION") {
    premium = false;
    expiresAtMs = expirationMs ?? timestampMs;
  } else if (expirationMs === null) {
    // Only a refund cancels a purchase that never expires.
    premium = type !== "CANCELLATION";
    expiresAtMs = premium ? NEVER_EXPIRES_MS : timestampMs;
  } else if (type === "BILLING_ISSUE") {
    // Premium lasts through the store's grace period.
    expiresAtMs = Math.max(expirationMs, event.gracePeriodExpirationMs ?? 0);
  } else if (type === "PRODUCT_CHANGE" && stored?.premium) {
    // The change may take effect later; its own renewal sets the expiry.
    expiresAtMs = Math.max(expirationMs, stored.expiresAtMs);
  } else {
    expiresAtMs = expirationMs;
  }
  const productId = event.productId ?? stored?.productId;
  return {
    writes: new Map([
      [
        uid,
        {
          premium,
          expiresAtMs,
          ...(productId === undefined ? {} : { productId }),
          lastEventMs: timestampMs,
          lastEventId: event.id,
        },
      ],
    ]),
    reason: Reason.applied,
  };
}

/**
 * What a TRANSFER writes: TRANSFER carries no entitlement, so Premium
 * known for the [from] uids moves to the [to] uids; the [from] uids lose
 * it now.
 */
export function planTransfer(
  event: RevenueCatEvent,
  from: string[],
  to: string[],
  stored: Map<string, StoredEntitlement | undefined>,
): Plan {
  const writes = new Map<string, StoredEntitlement>();
  const bookkeeping = { lastEventMs: event.timestampMs, lastEventId: event.id };
  let source: StoredEntitlement | undefined;
  for (const uid of from) {
    const entitlement = stored.get(uid);
    if (
      entitlement?.premium &&
      entitlement.expiresAtMs > (source?.expiresAtMs ?? -1)
    ) {
      source = entitlement;
    }
  }
  let skipped: ReasonValue | undefined;
  for (const uid of from) {
    const entitlement = stored.get(uid);
    const skip = staleness(event, entitlement);
    if (skip) {
      skipped ??= skip;
      continue;
    }
    writes.set(uid, {
      premium: false,
      expiresAtMs: Math.min(
        entitlement?.expiresAtMs ?? event.timestampMs,
        event.timestampMs,
      ),
      ...(entitlement?.productId === undefined
        ? {}
        : { productId: entitlement.productId }),
      ...bookkeeping,
    });
  }
  if (source) {
    for (const uid of to) {
      const entitlement = stored.get(uid);
      const skip = staleness(event, entitlement);
      if (skip) {
        skipped ??= skip;
        continue;
      }
      const keepsLater =
        entitlement?.premium && entitlement.expiresAtMs > source.expiresAtMs;
      const kept = keepsLater ? entitlement : source;
      writes.set(uid, {
        premium: true,
        expiresAtMs: kept.expiresAtMs,
        ...(kept.productId === undefined ? {} : { productId: kept.productId }),
        ...bookkeeping,
      });
    }
  }
  const reason =
    writes.size > 0 ? Reason.applied : (skipped ?? Reason.nothingToTransfer);
  return { writes, reason };
}

/** The uids among [ids] that Auth has, in order. */
async function existing(
  store: EntitlementStore,
  ids: string[],
): Promise<string[]> {
  const uids = [...new Set(ids.filter(isUid))];
  const exists = await Promise.all(uids.map((uid) => store.userExists(uid)));
  return uids.filter((_, i) => exists[i]);
}

/**
 * Applies [event] to `entitlements/{uid}`; the response says why when
 * nothing was written.
 */
async function applyEvent(
  event: RevenueCatEvent,
  store: EntitlementStore,
): Promise<WebhookResponse> {
  let plan: Plan;
  if (event.type === "TRANSFER") {
    const toIds = event.transferredTo.filter(isUid);
    const fromIds = event.transferredFrom.filter(
      (id) => isUid(id) && !toIds.includes(id),
    );
    if (fromIds.length === 0 && toIds.length === 0) {
      return respond(200, Reason.noUser);
    }
    const [from, to] = await Promise.all([
      existing(store, fromIds),
      existing(store, toIds),
    ]);
    if (from.length === 0 && to.length === 0) {
      return respond(200, Reason.deletedUser);
    }
    plan = await store.apply([...from, ...to], (stored) =>
      planTransfer(event, from, to, stored),
    );
  } else {
    if (!event.entitlementIds?.includes(PREMIUM_ENTITLEMENT)) {
      return respond(200, Reason.notPremium);
    }
    const uid = targetUid(event);
    if (uid === undefined) return respond(200, Reason.noUser);
    if (!(await store.userExists(uid))) return respond(200, Reason.deletedUser);
    plan = await store.apply([uid], (stored) =>
      planUpdate(event, uid, stored.get(uid)),
    );
  }
  // An account deleted while this was written: `deleteAccount` deletes
  // the entitlement again after the auth user, and this catches the rest.
  for (const uid of plan.writes.keys()) {
    if (!(await store.userExists(uid))) {
      await store.delete(uid);
      logger.warn("entitlement of a deleted account removed", { uid });
    }
  }
  logger.info("revenuecat event", {
    id: event.id,
    type: event.type,
    uids: [...plan.writes.keys()],
    reason: plan.reason,
  });
  return respond(200, plan.reason);
}

/**
 * Handles one webhook delivery. RevenueCat counts only 200 as delivered
 * and retries anything else, so every event handled or deliberately
 * ignored answers 200, a request that is not RevenueCat's 4xx, and only a
 * failure a retry may fix 500. [acceptSandbox] is the dev project's.
 */
export async function revenueCatWebhookOf(
  request: WebhookRequest,
  deps: {
    authorization: string;
    acceptSandbox: boolean;
    store: EntitlementStore;
  },
): Promise<WebhookResponse> {
  // Never log the header or the body: either may hold the secret.
  if (!sameSecret(request.authorization, deps.authorization)) {
    logger.warn("revenuecat webhook refused: authorization");
    return respond(401, Reason.unauthorized);
  }
  if (request.method !== "POST") {
    return respond(405, Reason.methodNotAllowed);
  }
  if (!request.isJson) return respond(415, Reason.notJson);
  const event = parseEvent(request.body);
  if (event === null) {
    logger.error("revenuecat webhook: not an event");
    return respond(400, Reason.invalidEvent);
  }
  if (event.type === "TEST") return respond(200, Reason.testEvent);
  if (!HANDLED.has(event.type)) return respond(200, Reason.unhandledType);
  if (event.environment === "SANDBOX" && !deps.acceptSandbox) {
    return respond(200, Reason.sandboxIgnored);
  }
  try {
    return await applyEvent(event, deps.store);
  } catch (error) {
    logger.error("revenuecat event not applied", {
      id: event.id,
      type: event.type,
      error: String(error),
    });
    return respond(500, Reason.retry);
  }
}

const toStored = (data: DocumentData): StoredEntitlement => ({
  premium: data.premium === true,
  expiresAtMs:
    data.expiresAt instanceof Timestamp ? data.expiresAt.toMillis() : 0,
  ...(typeof data.productId === "string" ? { productId: data.productId } : {}),
  lastEventMs: typeof data.lastEventMs === "number" ? data.lastEventMs : 0,
  lastEventId: typeof data.lastEventId === "string" ? data.lastEventId : "",
});

/** The Admin SDK behind [EntitlementStore]. */
export const firebaseEntitlementStore = (): EntitlementStore => {
  const db = getFirestore();
  const entitlements = db.collection("entitlements");
  return {
    async userExists(uid) {
      try {
        await getAuth().getUser(uid);
        return true;
      } catch (error) {
        if ((error as { code?: string }).code === "auth/user-not-found") {
          return false;
        }
        throw error;
      }
    },
    apply: (uids, decide) =>
      db.runTransaction(async (transaction) => {
        const refs = uids.map((uid) => entitlements.doc(uid));
        const snapshots = await transaction.getAll(...refs);
        const plan = decide(
          new Map(
            snapshots.map((snapshot, i) => {
              const data = snapshot.data();
              return [uids[i], data === undefined ? undefined : toStored(data)];
            }),
          ),
        );
        for (const [uid, { expiresAtMs, ...rest }] of plan.writes) {
          transaction.set(entitlements.doc(uid), {
            ...rest,
            expiresAt: Timestamp.fromMillis(expiresAtMs),
          });
        }
        return plan;
      }),
    async delete(uid) {
      await entitlements.doc(uid).delete();
    },
  };
};

/**
 * RevenueCat's webhook. The dev project (id ending in `-dev`) also applies
 * sandbox purchases; prod ignores them.
 */
export const revenueCatWebhook = onRequest(
  { secrets: [webhookAuthorization] },
  async (req, res) => {
    const response = await revenueCatWebhookOf(
      {
        method: req.method,
        isJson: req.is("application/json") === "application/json",
        authorization: req.get("authorization"),
        body: req.body,
      },
      {
        authorization: webhookAuthorization.value(),
        acceptSandbox: projectID.value().endsWith("-dev"),
        store: firebaseEntitlementStore(),
      },
    );
    res.status(response.status).json(response.body);
  },
);
