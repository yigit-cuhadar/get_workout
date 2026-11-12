import { createHash, timingSafeEqual } from "node:crypto";

import { Auth, getAuth } from "firebase-admin/auth";
import {
  DocumentData,
  Firestore,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { defineSecret } from "firebase-functions/params";
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
 * The expiry written for a non-renewing purchase without one (a lifetime
 * product): the last day Firestore timestamps hold, as the rules compare it.
 */
export const NEVER_EXPIRES_MS = Date.UTC(9999, 11, 31);

/** How long RevenueCat's TEMPORARY_ENTITLEMENT_GRANT lasts at most. */
export const TEMPORARY_GRANT_MS = 24 * 60 * 60 * 1000;

/** The one `cancel_reason` that means a refund. */
const REFUND = "CUSTOMER_SUPPORT";

/**
 * How many ids of events applied at the latest event time are kept, to
 * tell a redelivery from another event of the same millisecond.
 */
const KEPT_EVENT_IDS = 20;

/**
 * Events after which the user has Premium: a cancelled (not refunded),
 * paused or failing subscription runs to the end of what was paid, or of
 * the grace period.
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
  notPremium: "not-premium",
  /** A subscription event without an expiry, for a user with none known. */
  noExpiry: "no-expiry",
  /** Only anonymous or unusable RevenueCat ids. */
  noUser: "no-user",
  /** No Auth user: a deleted account is never written again. */
  deletedUser: "deleted-user",
  /** An event older than the state stored, which it cannot change. */
  stale: "stale",
  /** An event already applied, delivered again. */
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
  /** Null when absent or when the product grants no entitlement. */
  entitlementIds: string[] | null;
  productId?: string;
  newProductId?: string;
  cancelReason?: string;
  /** Null when absent: a non-renewing purchase that never expires. */
  expirationMs: number | null;
  gracePeriodExpirationMs: number | null;
  transferredFrom: string[];
  transferredTo: string[];
}

/** `entitlements/{uid}`, with `expiresAt` in milliseconds. */
export interface StoredEntitlement {
  premium: boolean;
  expiresAtMs: number;
  /** Absent when no event named a product for the user. */
  productId?: string;
  /** `event_timestamp_ms` of the latest event applied. */
  lastEventMs: number;
  /** Ids of the events applied at [lastEventMs], at most [KEPT_EVENT_IDS]. */
  lastEventIds: string[];
}

/** The entitlement an event leads to, before ordering is considered. */
interface Outcome {
  premium: boolean;
  expiresAtMs: number;
  productId?: string;
  /** Only grants may still extend Premium when they arrive late. */
  grant: boolean;
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
   * passes them to [decide] and writes its plan, all or nothing.
   */
  apply(
    uids: string[],
    decide: (stored: Map<string, StoredEntitlement | undefined>) => Plan,
  ): Promise<Plan>;
  /** Deletes `entitlements/{uid}`; nothing to delete is fine. */
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

/** The event's fields, when the body holds an event object. */
const eventFields = (body: unknown): { [key: string]: unknown } | null => {
  const event = (body as { event?: unknown } | null)?.event;
  return typeof event === "object" && event !== null
    ? (event as { [key: string]: unknown })
    : null;
};

/** The event in a webhook body, or null when it is not one. */
export function parseEvent(body: unknown): RevenueCatEvent | null {
  const fields = eventFields(body);
  if (fields === null) return null;
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
    newProductId: optionalString(fields.new_product_id),
    cancelReason: optionalString(fields.cancel_reason),
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

/**
 * Whether [event] is about Premium. TEMPORARY_ENTITLEMENT_GRANT names no
 * entitlement; the app has only Premium, so it is.
 */
const isPremiumEvent = (event: RevenueCatEvent) =>
  event.type === "TEMPORARY_ENTITLEMENT_GRANT" ||
  (event.entitlementIds?.includes(PREMIUM_ENTITLEMENT) ?? false);

const optionalProduct = (productId: string | undefined) =>
  productId === undefined ? {} : { productId };

/** The expiry of Premium [stored] still grants, else 0. */
const premiumUntil = (stored: StoredEntitlement | undefined) =>
  stored?.premium ? stored.expiresAtMs : 0;

/**
 * What a premium event other than TRANSFER leads to from [stored], or null
 * when it has no expiry to grant. Grants never shorten Premium already
 * known: only EXPIRATION and a refund end it, and not when they are about
 * another product than the one Premium runs on and that is still running
 * (a plan switch, a temporary grant expiring next to a subscription).
 */
export function outcomeOf(
  event: RevenueCatEvent,
  stored: StoredEntitlement | undefined,
): Outcome | null {
  const { type, timestampMs, expirationMs, productId } = event;
  const until = premiumUntil(stored);
  const revokes =
    type === "EXPIRATION" ||
    (type === "CANCELLATION" && event.cancelReason === REFUND);
  if (revokes) {
    const otherProduct =
      stored?.productId !== undefined &&
      productId !== undefined &&
      stored.productId !== productId &&
      until > timestampMs;
    if (stored && otherProduct) {
      const { premium, expiresAtMs } = stored;
      return {
        premium,
        expiresAtMs,
        ...optionalProduct(stored.productId),
        grant: false,
      };
    }
    return {
      premium: false,
      expiresAtMs: Math.min(expirationMs ?? timestampMs, timestampMs),
      ...optionalProduct(productId ?? stored?.productId),
      grant: false,
    };
  }
  let expiresAtMs: number | null;
  let product = productId;
  switch (type) {
    case "TEMPORARY_ENTITLEMENT_GRANT":
      expiresAtMs = timestampMs + TEMPORARY_GRANT_MS;
      product = stored?.productId;
      break;
    case "NON_RENEWING_PURCHASE":
      expiresAtMs = expirationMs ?? NEVER_EXPIRES_MS;
      break;
    case "BILLING_ISSUE":
      expiresAtMs = Math.max(
        expirationMs ?? 0,
        event.gracePeriodExpirationMs ?? 0,
      );
      break;
    case "PRODUCT_CHANGE":
      expiresAtMs = expirationMs;
      product = event.newProductId ?? productId;
      break;
    default:
      expiresAtMs = expirationMs;
  }
  const kept = Math.max(expiresAtMs ?? 0, until);
  if (kept === 0) return null;
  return {
    premium: true,
    expiresAtMs: kept,
    ...optionalProduct(product ?? stored?.productId),
    grant: true,
  };
}

/** Orders outcomes of one millisecond: later Premium, then product id. */
const ranksAbove = (
  a: { premium: boolean; expiresAtMs: number; productId?: string },
  b: { premium: boolean; expiresAtMs: number; productId?: string },
) => {
  const rank = (o: typeof a) => (o.premium ? o.expiresAtMs : -1);
  if (rank(a) !== rank(b)) return rank(a) > rank(b);
  return (a.productId ?? "") > (b.productId ?? "");
};

/**
 * What [outcome] of [event] makes of [stored], whatever order events
 * arrive in: a newer event replaces the state; events of one millisecond
 * keep the outcome that ranks highest; an older event only extends
 * Premium still granted (a late grant, e.g. BILLING_ISSUE's grace after
 * the billing error's CANCELLATION), else changes nothing. An event id
 * already applied changes nothing.
 */
export function settle(
  event: RevenueCatEvent,
  stored: StoredEntitlement | undefined,
  outcome: Outcome,
): StoredEntitlement | ReasonValue {
  const { premium, expiresAtMs, productId } = outcome;
  const state = { premium, expiresAtMs, ...optionalProduct(productId) };
  if (stored === undefined || event.timestampMs > stored.lastEventMs) {
    const { timestampMs: lastEventMs, id } = event;
    return { ...state, lastEventMs, lastEventIds: [id] };
  }
  if (stored.lastEventIds.includes(event.id)) return Reason.duplicate;
  if (event.timestampMs === stored.lastEventMs) {
    const lastEventIds = [...stored.lastEventIds, event.id].slice(
      -KEPT_EVENT_IDS,
    );
    return ranksAbove(state, stored)
      ? { ...state, lastEventMs: stored.lastEventMs, lastEventIds }
      : { ...stored, lastEventIds };
  }
  if (outcome.grant && stored.premium && expiresAtMs > stored.expiresAtMs) {
    return { ...stored, expiresAtMs };
  }
  return Reason.stale;
}

/** What a premium event other than TRANSFER writes for [uid]. */
export function planUpdate(
  event: RevenueCatEvent,
  uid: string,
  stored: StoredEntitlement | undefined,
): Plan {
  const outcome = outcomeOf(event, stored);
  if (outcome === null) return { writes: new Map(), reason: Reason.noExpiry };
  const settled = settle(event, stored, outcome);
  return typeof settled === "string"
    ? { writes: new Map(), reason: settled }
    : { writes: new Map([[uid, settled]]), reason: Reason.applied };
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
  let skipped: ReasonValue | undefined;
  const put = (uid: string, outcome: Outcome) => {
    const settled = settle(event, stored.get(uid), outcome);
    if (typeof settled === "string") {
      skipped ??= settled;
    } else {
      writes.set(uid, settled);
    }
  };
  let source: StoredEntitlement | undefined;
  for (const uid of from) {
    const entitlement = stored.get(uid);
    if (premiumUntil(entitlement) > premiumUntil(source)) source = entitlement;
  }
  for (const uid of from) {
    const entitlement = stored.get(uid);
    put(uid, {
      premium: false,
      expiresAtMs: Math.min(
        entitlement?.expiresAtMs ?? event.timestampMs,
        event.timestampMs,
      ),
      ...optionalProduct(entitlement?.productId),
      grant: false,
    });
  }
  if (source) {
    for (const uid of to) {
      const entitlement = stored.get(uid);
      const keepsLater = premiumUntil(entitlement) > source.expiresAtMs;
      const kept = keepsLater && entitlement ? entitlement : source;
      put(uid, {
        premium: true,
        expiresAtMs: kept.expiresAtMs,
        ...optionalProduct(kept.productId),
        grant: true,
      });
    }
  }
  const reason =
    writes.size > 0 ? Reason.applied : (skipped ?? Reason.nothingToTransfer);
  return { writes, reason };
}

/**
 * The uids among [ids] that Auth has, in order. Those it does not have
 * get their entitlement deleted, so a retry after a failure, or an event
 * racing `deleteAccount`, leaves nothing behind.
 */
async function existing(
  store: EntitlementStore,
  ids: string[],
): Promise<string[]> {
  const uids = [...new Set(ids.filter(isUid))];
  const exists = await Promise.all(uids.map((uid) => store.userExists(uid)));
  await Promise.all(
    uids.filter((_, i) => !exists[i]).map((uid) => store.delete(uid)),
  );
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
    if (!isPremiumEvent(event)) return respond(200, Reason.notPremium);
    const uid = targetUid(event);
    if (uid === undefined) return respond(200, Reason.noUser);
    if ((await existing(store, [uid])).length === 0) {
      return respond(200, Reason.deletedUser);
    }
    plan = await store.apply([uid], (stored) =>
      planUpdate(event, uid, stored.get(uid)),
    );
  }
  // An account deleted while this was written: `deleteAccount` deletes
  // the entitlement again after the auth user, and this catches the rest.
  await existing(store, [...plan.writes.keys()]);
  logger.info("revenuecat event", {
    id: event.id,
    type: event.type,
    environment: event.environment,
    uids: [...plan.writes.keys()],
    reason: plan.reason,
  });
  return respond(200, plan.reason);
}

/**
 * Handles one webhook delivery. RevenueCat counts only 200 as delivered
 * and retries anything else, so every event handled or deliberately
 * ignored answers 200, a request that is not RevenueCat's 4xx, and only a
 * failure a retry may fix 500. Sandbox and production events are treated
 * alike: with a release build only testers and App Review can buy in the
 * sandbox, and their purchases must unlock what they paid for.
 */
export async function revenueCatWebhookOf(
  request: WebhookRequest,
  deps: { authorization: string; store: EntitlementStore },
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
  // The type first: an event this function ignores may have any shape.
  const type = eventFields(request.body)?.type;
  if (type === "TEST") return respond(200, Reason.testEvent);
  if (typeof type === "string" && !HANDLED.has(type)) {
    return respond(200, Reason.unhandledType);
  }
  const event = parseEvent(request.body);
  if (event === null) {
    logger.error("revenuecat webhook: not an event");
    return respond(400, Reason.invalidEvent);
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
  ...optionalProduct(
    typeof data.productId === "string" ? data.productId : undefined,
  ),
  lastEventMs: typeof data.lastEventMs === "number" ? data.lastEventMs : 0,
  lastEventIds: strings(data.lastEventIds),
});

/** `entitlements/{uid}` as written: `expiresAt` a timestamp. */
const toDocument = ({ expiresAtMs, ...rest }: StoredEntitlement) => ({
  ...rest,
  expiresAt: Timestamp.fromMillis(expiresAtMs),
});

/** [EntitlementStore] on [db] and [auth]. */
export const firebaseEntitlementStore = (
  db: Firestore,
  auth: Pick<Auth, "getUser">,
): EntitlementStore => {
  const entitlements = db.collection("entitlements");
  return {
    async userExists(uid) {
      try {
        await auth.getUser(uid);
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
        for (const [uid, entitlement] of plan.writes) {
          transaction.set(entitlements.doc(uid), toDocument(entitlement));
        }
        return plan;
      }),
    async delete(uid) {
      await entitlements.doc(uid).delete();
    },
  };
};

/** RevenueCat's webhook; public, as RevenueCat calls it without Google auth. */
export const revenueCatWebhook = onRequest(
  { secrets: [webhookAuthorization], invoker: "public", maxInstances: 10 },
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
        store: firebaseEntitlementStore(getFirestore(), getAuth()),
      },
    );
    res.status(response.status).json(response.body);
  },
);
