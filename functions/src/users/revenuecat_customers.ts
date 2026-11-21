import { REVENUECAT_PROJECT_URL } from "../dashboard/revenuecat_metrics";
import { PREMIUM_ENTITLEMENT } from "../revenuecat_webhook";

/** A RevenueCat API refusal, with its exact answer for the logs. */
export class RevenueCatError extends Error {
  constructor(
    readonly path: string,
    readonly status: number,
    readonly body: string,
  ) {
    super(`RevenueCat ${path} answered ${status}`);
  }
}

/** One of the customer's subscriptions, promotional grants included. */
export interface Subscription {
  /** `app_store`, `play_store`, `promotional`, ... */
  store: string;
  /** `trialing`, `active`, `expired`, `in_grace_period`, ... */
  status: string;
  givesAccess: boolean;
  /** Null for a promotional grant. */
  productId: string | null;
  /** Null while paused indefinitely. */
  periodEndsAtMillis: number | null;
  /** `will_renew`, `will_not_renew`, ... */
  autoRenewal: string;
}

/** What RevenueCat knows of a customer (app user id = Firebase uid). */
export interface Customer {
  /** The `premium` entitlement while active; `expiresAtMillis` null never ends. */
  premium: { expiresAtMillis: number | null } | null;
  subscriptions: Subscription[];
  /** The device the app last reported from. */
  lastSeen: {
    atMillis: number | null;
    platform: string | null;
    platformVersion: string | null;
    appVersion: string | null;
  };
}

/** Promotional Premium in RevenueCat for a Firebase uid. */
export interface PremiumGrants {
  /** Null when RevenueCat has no such customer. */
  customer(uid: string): Promise<Customer | null>;
  /** Grants `premium` until [expiresAtMillis]; a store subscription stays. */
  grant(uid: string, expiresAtMillis: number): Promise<void>;
  /** Ends every promotional grant of `premium` now. */
  revoke(uid: string): Promise<void>;
}

type Json = { [key: string]: unknown };

const asObject = (value: unknown): Json =>
  typeof value === "object" && value !== null ? (value as Json) : {};

const items = (value: unknown): Json[] => {
  const list = asObject(value).items;
  return Array.isArray(list) ? list.map(asObject) : [];
};

const text = (value: unknown): string | null =>
  typeof value === "string" ? value : null;

const millis = (value: unknown): number | null =>
  typeof value === "number" ? value : null;

/** The id API v2 gives the entitlement with [lookupKey], or throws. */
export function entitlementIdIn(body: unknown, lookupKey: string): string {
  const found = items(body).find((e) => e.lookup_key === lookupKey);
  const id = text(found?.id);
  if (id === null) throw new Error(`No entitlement ${lookupKey}.`);
  return id;
}

/** A customer response and its subscriptions response as a [Customer]. */
export function parseCustomer(
  customer: unknown,
  subscriptions: unknown,
  premiumId: string,
): Customer {
  const body = asObject(customer);
  const premium = items(body.active_entitlements).find(
    (e) => e.entitlement_id === premiumId,
  );
  return {
    premium: premium ? { expiresAtMillis: millis(premium.expires_at) } : null,
    subscriptions: items(subscriptions).map((s) => ({
      store: text(s.store) ?? "unknown",
      status: text(s.status) ?? "unknown",
      givesAccess: s.gives_access === true,
      productId: text(s.product_id),
      periodEndsAtMillis: millis(s.current_period_ends_at),
      autoRenewal: text(s.auto_renewal_status) ?? "unknown",
    })),
    lastSeen: {
      atMillis: millis(body.last_seen_at),
      platform: text(body.last_seen_platform),
      platformVersion: text(body.last_seen_platform_version),
      appVersion: text(body.last_seen_app_version),
    },
  };
}

/**
 * [PremiumGrants] on RevenueCat's API v2 with a secret key ([apiKey]).
 * API v2 names entitlements by id, so the id of `premium` is looked up
 * once per instance.
 */
export function revenueCatGrants(
  apiKey: string,
  fetcher: typeof fetch,
): PremiumGrants {
  const request = async (
    path: string,
    body?: object,
  ): Promise<{ status: number; json: unknown }> => {
    const response = await fetcher(`${REVENUECAT_PROJECT_URL}${path}`, {
      method: body ? "POST" : "GET",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        ...(body ? { "Content-Type": "application/json" } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(30_000),
    });
    const raw = await response.text();
    if (!response.ok && response.status !== 404) {
      throw new RevenueCatError(path, response.status, raw);
    }
    return { status: response.status, json: raw ? JSON.parse(raw) : null };
  };
  const ok = async (path: string, body?: object) => {
    const { status, json } = await request(path, body);
    if (status === 404) throw new RevenueCatError(path, status, "");
    return json;
  };
  let premiumId: Promise<string> | null = null;
  const premium = () => {
    premiumId ??= ok("/entitlements?limit=100").then((body) =>
      entitlementIdIn(body, PREMIUM_ENTITLEMENT),
    );
    premiumId.catch(() => (premiumId = null));
    return premiumId;
  };
  const customerPath = (uid: string) =>
    `/customers/${encodeURIComponent(uid)}`;
  return {
    async customer(uid) {
      const id = await premium();
      const customer = await request(customerPath(uid));
      if (customer.status === 404) return null;
      const subscriptions = await ok(`${customerPath(uid)}/subscriptions`);
      return parseCustomer(customer.json, subscriptions, id);
    },
    async grant(uid, expiresAtMillis) {
      await ok(`${customerPath(uid)}/actions/grant_entitlement`, {
        entitlement_id: await premium(),
        expires_at: expiresAtMillis,
      });
    },
    async revoke(uid) {
      await ok(`${customerPath(uid)}/actions/revoke_granted_entitlement`, {
        entitlement_id: await premium(),
      });
    },
  };
}
