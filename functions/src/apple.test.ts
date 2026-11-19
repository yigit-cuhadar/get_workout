import assert from "node:assert/strict";
import { generateKeyPairSync, verify } from "node:crypto";
import { describe, test } from "node:test";

import {
  APPLE_CLIENT_ID,
  APPLE_KEY_ID,
  APPLE_TEAM_ID,
  AppleError,
  appleClientSecret,
  revokeAppleCode,
} from "./apple";

const decode = (part: string) =>
  JSON.parse(Buffer.from(part, "base64url").toString());

describe("appleClientSecret", () => {
  test("is an ES256 JWT for the app, valid five minutes", () => {
    const { privateKey, publicKey } = generateKeyPairSync("ec", {
      namedCurve: "prime256v1",
    });
    const pem = privateKey.export({ type: "pkcs8", format: "pem" }).toString();

    const [header, payload, signature] = appleClientSecret(pem, 1000).split(
      ".",
    );

    assert.deepEqual(decode(header), { alg: "ES256", kid: APPLE_KEY_ID });
    assert.deepEqual(decode(payload), {
      iss: APPLE_TEAM_ID,
      iat: 1000,
      exp: 1300,
      aud: "https://appleid.apple.com",
      sub: APPLE_CLIENT_ID,
    });
    const raw = Buffer.from(signature, "base64url");
    assert.equal(raw.length, 64);
    assert.ok(
      verify(
        "sha256",
        Buffer.from(`${header}.${payload}`),
        { key: publicKey, dsaEncoding: "ieee-p1363" },
        raw,
      ),
    );
  });
});

/** Answers each request with the next of [answers] and records it. */
function fakeFetch(answers: [number, string][]) {
  const requests: { url: string; form: Record<string, string> }[] = [];
  const fetcher = (async (url: string, init: RequestInit) => {
    requests.push({
      url,
      form: Object.fromEntries(init.body as URLSearchParams),
    });
    const [status, body] = answers[requests.length - 1];
    return new Response(body, { status });
  }) as typeof fetch;
  return { fetcher, requests };
}

const client = { client_id: APPLE_CLIENT_ID, client_secret: "secret" };

describe("revokeAppleCode", () => {
  test("exchanges the code, then revokes the refresh token", async () => {
    const { fetcher, requests } = fakeFetch([
      [200, '{"access_token":"a","refresh_token":"r"}'],
      [200, ""],
    ]);
    await revokeAppleCode("code-1", "secret", fetcher);
    assert.deepEqual(requests, [
      {
        url: "https://appleid.apple.com/auth/token",
        form: { ...client, grant_type: "authorization_code", code: "code-1" },
      },
      {
        url: "https://appleid.apple.com/auth/revoke",
        form: { ...client, token: "r", token_type_hint: "refresh_token" },
      },
    ]);
  });

  test("revokes the access token when there is no refresh token", async () => {
    const { fetcher, requests } = fakeFetch([
      [200, '{"access_token":"a"}'],
      [200, ""],
    ]);
    await revokeAppleCode("code-1", "secret", fetcher);
    assert.deepEqual(requests[1].form, {
      ...client,
      token: "a",
      token_type_hint: "access_token",
    });
  });

  test("a refused exchange carries Apple's answer and revokes nothing", async () => {
    const { fetcher, requests } = fakeFetch([
      [400, '{"error":"invalid_grant"}'],
    ]);
    await assert.rejects(
      revokeAppleCode("code-1", "secret", fetcher),
      (error: AppleError) =>
        error.endpoint === "token" &&
        error.status === 400 &&
        error.body === '{"error":"invalid_grant"}',
    );
    assert.equal(requests.length, 1);
  });

  test("a refused revocation carries Apple's answer", async () => {
    const { fetcher } = fakeFetch([
      [200, '{"refresh_token":"r"}'],
      [400, '{"error":"invalid_client"}'],
    ]);
    await assert.rejects(
      revokeAppleCode("code-1", "secret", fetcher),
      (error: AppleError) =>
        error.endpoint === "revoke" &&
        error.status === 400 &&
        error.body === '{"error":"invalid_client"}',
    );
  });
});
