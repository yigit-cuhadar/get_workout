import { sign } from "node:crypto";

import { defineSecret } from "firebase-functions/params";

/** The app's Apple developer team. */
export const APPLE_TEAM_ID = "A8J42TV74R";

/** The Sign in with Apple key the client secret is signed with. */
export const APPLE_KEY_ID = "W3KP8AP8K2";

/** The app's bundle id, the client the authorization codes are issued to. */
export const APPLE_CLIENT_ID = "com.getworkout.app";

/** The private key of [APPLE_KEY_ID], as Apple's `.p8` PEM. */
export const appleSignInKey = defineSecret("APPLE_SIGN_IN_KEY");

const AUDIENCE = "https://appleid.apple.com";

/** How long a client secret is valid; each call makes its own. */
const CLIENT_SECRET_SECONDS = 5 * 60;

/** An Apple endpoint's refusal, with its exact answer for the logs. */
export class AppleError extends Error {
  constructor(
    readonly endpoint: string,
    readonly status: number,
    readonly body: string,
  ) {
    super(`Apple ${endpoint} answered ${status}`);
  }
}

const base64url = (value: object): string =>
  Buffer.from(JSON.stringify(value)).toString("base64url");

/** Apple's client secret: an ES256 JWT signed with [privateKeyPem]. */
export function appleClientSecret(
  privateKeyPem: string,
  nowSeconds: number,
): string {
  const unsigned = [
    base64url({ alg: "ES256", kid: APPLE_KEY_ID }),
    base64url({
      iss: APPLE_TEAM_ID,
      iat: nowSeconds,
      exp: nowSeconds + CLIENT_SECRET_SECONDS,
      aud: AUDIENCE,
      sub: APPLE_CLIENT_ID,
    }),
  ].join(".");
  const signature = sign("sha256", Buffer.from(unsigned), {
    key: privateKeyPem,
    dsaEncoding: "ieee-p1363",
  });
  return `${unsigned}.${signature.toString("base64url")}`;
}

async function post(
  fetcher: typeof fetch,
  endpoint: string,
  form: Record<string, string>,
): Promise<string> {
  const response = await fetcher(`${AUDIENCE}/auth/${endpoint}`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(form),
  });
  const body = await response.text();
  if (!response.ok) throw new AppleError(endpoint, response.status, body);
  return body;
}

/**
 * Exchanges the app's single-use authorization [code] for the user's Apple
 * tokens and revokes them, as the App Store requires when an account is
 * deleted. Throws [AppleError] when Apple refuses either step.
 */
export async function revokeAppleCode(
  code: string,
  clientSecret: string,
  fetcher: typeof fetch,
): Promise<void> {
  const client = { client_id: APPLE_CLIENT_ID, client_secret: clientSecret };
  const tokens = JSON.parse(
    await post(fetcher, "token", {
      ...client,
      grant_type: "authorization_code",
      code,
    }),
  ) as { refresh_token?: string; access_token?: string };
  const hint = tokens.refresh_token ? "refresh_token" : "access_token";
  const token = tokens[hint];
  // The body holds the tokens, so it is never logged.
  if (!token) throw new AppleError("token", 200, "no token in the answer");
  await post(fetcher, "revoke", {
    ...client,
    token,
    token_type_hint: hint,
  });
}
