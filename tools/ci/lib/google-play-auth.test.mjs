import assert from "node:assert/strict";
import test from "node:test";

import {
  apiErrorSummary,
  maskSecrets,
  PlayApiError,
  readResponseBody,
} from "./google-play-auth.mjs";

test("maskSecrets redacts bearer tokens and access_token values", () => {
  assert.equal(maskSecrets("authorization: Bearer ya29.abcDEF-123_xyz"), "authorization: Bearer ***");
  assert.equal(maskSecrets('{"access_token":"ya29.secretValue-123"}'), '{"access_token":"***"}');
  assert.equal(maskSecrets("token=ya29.longsecretstring"), "token=ya29.***");
  // Ordinary text is untouched.
  assert.equal(maskSecrets("app is in draft status"), "app is in draft status");
  assert.equal(maskSecrets(undefined), undefined);
});

test("maskSecrets redacts a bare (non-Bearer) authorization header value", () => {
  assert.equal(maskSecrets("authorization: rawTokenValue-123_abc"), "authorization: ***");
  assert.equal(maskSecrets('{"authorization":"rawTokenValue-123"}'), '{"authorization":"***"}');
  // A Bearer scheme is still handled by the Bearer rule, not double-masked.
  assert.equal(maskSecrets("authorization: Bearer ya29.abc-123"), "authorization: Bearer ***");
  // Not a credential-bearing field: an unrelated word after "authorization" text
  // (no `:`/`=` separator) is left alone.
  assert.equal(maskSecrets("authorization failed for user"), "authorization failed for user");
});

test("maskSecrets redacts a Google OAuth refresh token", () => {
  assert.equal(
    maskSecrets('{"refresh_token":"1//0abcDEF-123_ghi.jkl"}'),
    '{"refresh_token":"1//***"}',
  );
  assert.equal(maskSecrets("token=1//longRefreshValue-xyz"), "token=1//***");
  // A plain "1//" not followed by token characters is untouched.
  assert.equal(maskSecrets("ratio is 1// or so"), "ratio is 1// or so");
});

test("maskSecrets redacts a client_secret value", () => {
  assert.equal(
    maskSecrets('{"client_secret":"GOCSPX-secretValue123"}'),
    '{"client_secret":"***"}',
  );
  assert.equal(maskSecrets("client_secret=GOCSPX-abcdef"), "client_secret=***");
  // A field merely mentioning the term without a value separator is untouched.
  assert.equal(maskSecrets("the client_secret is missing"), "the client_secret is missing");
});

test("maskSecrets redacts a PEM private-key block", () => {
  const pem = "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBg\nkqhkiG9w0B\n-----END PRIVATE KEY-----";
  assert.equal(maskSecrets(pem), "-----BEGIN PRIVATE KEY-----***-----END PRIVATE KEY-----");
  const rsaPem = "-----BEGIN RSA PRIVATE KEY-----\nAAAA\nBBBB\n-----END RSA PRIVATE KEY-----";
  assert.equal(maskSecrets(rsaPem), "-----BEGIN RSA PRIVATE KEY-----***-----END RSA PRIVATE KEY-----");
  // A public-key block is not a secret and stays intact.
  const pub = "-----BEGIN PUBLIC KEY-----\nAAAA\n-----END PUBLIC KEY-----";
  assert.equal(maskSecrets(pub), pub);
});

test("readResponseBody parses JSON and passes through empty bodies", () => {
  assert.deepEqual(readResponseBody("", "label", { ok: true }), {});
  assert.deepEqual(readResponseBody('{"a":1}', "label", { ok: true }), { a: 1 });
});

test("readResponseBody returns raw text for a non-JSON error body without throwing", () => {
  const raw = "Could not commit changes for edit ... app is in draft status.";
  const result = readResponseBody(raw, "google play api POST", { ok: false, status: 400 });
  assert.equal(result._raw, raw);
});

test("readResponseBody throws when a successful response is unexpectedly non-JSON", () => {
  assert.throws(
    () => readResponseBody("not json", "google play upload", { ok: true, status: 200 }),
    (error) => {
      assert.ok(error instanceof PlayApiError);
      assert.match(error.message, /non-JSON on success/);
      return true;
    },
  );
});

test("apiErrorSummary surfaces the raw plaintext body when there is no structured error", () => {
  const raw = "Could not commit changes for edit edit-1 because the app is in draft status.";
  const summary = apiErrorSummary({ _raw: raw }, raw);
  assert.match(summary, /status=unknown/);
  assert.match(summary, /draft status/);
});

test("apiErrorSummary formats a structured error and masks secrets in the message", () => {
  const summary = apiErrorSummary(
    { error: { status: "PERMISSION_DENIED", message: "denied Bearer ya29.leaked-token here" } },
  );
  assert.match(summary, /status=PERMISSION_DENIED/);
  assert.match(summary, /Bearer \*\*\*/);
  assert.doesNotMatch(summary, /ya29\.leaked-token/);
});

test("apiErrorSummary caps an overlong raw body", () => {
  const raw = "x".repeat(1000);
  const summary = apiErrorSummary({ _raw: raw }, raw);
  assert.ok(summary.length < 450, "raw body must be capped");
});

test("PlayApiError carries status, raw body, and parsed payload", () => {
  const error = new PlayApiError("google play upload failed", 500, "boom", { _raw: "boom" });
  assert.equal(error.name, "PlayApiError");
  assert.equal(error.status, 500);
  assert.equal(error.rawBody, "boom");
  assert.match(error.message, /google play upload failed: 500/);
});
