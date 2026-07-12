// Shared Google Play (Android Publisher API v3) service-account auth and request
// helpers. Extracted from check-google-play-api-access.mjs so the internal-track
// upload tool can reuse the exact JWT flow instead of a third-party action
// (issue #1689 — keeps the supply-chain surface minimal).
import { createSign } from "node:crypto";

export const androidPublisherScope = "https://www.googleapis.com/auth/androidpublisher";
export const defaultTokenUri = "https://oauth2.googleapis.com/token";
export const defaultApiBaseUrl = "https://androidpublisher.googleapis.com/androidpublisher/v3";

// Validate a request URL before it reaches fetch: only absolute HTTPS URLs are
// allowed, so a bad token_uri / base-url cannot be used to reach an arbitrary
// (e.g. http or internal) endpoint.
export function assertRequestUrl(url) {
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    throw new Error("invalid google play request url");
  }
  if (parsed.protocol !== "https:") {
    throw new Error("google play request url must be https");
  }
  return parsed.toString();
}

export async function fetchAccessToken(serviceAccount, fetchImpl = fetch) {
  const tokenUri = serviceAccount.token_uri || defaultTokenUri;
  const nowSeconds = Math.floor(Date.now() / 1000);
  const header = base64UrlJson({ alg: "RS256", typ: "JWT" });
  const claim = base64UrlJson({
    iss: requireJsonString(serviceAccount, "client_email"),
    scope: androidPublisherScope,
    aud: tokenUri,
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  });
  const unsignedToken = `${header}.${claim}`;
  const signature = createSign("RSA-SHA256").update(unsignedToken).sign(requireJsonString(serviceAccount, "private_key"));
  const assertion = `${unsignedToken}.${signature.toString("base64url")}`;
  const response = await fetchImpl(assertRequestUrl(tokenUri), {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok || typeof body.access_token !== "string") {
    throw new Error(`google play oauth failed: ${response.status}`);
  }
  return body.access_token;
}

export async function requestJson(url, { method, token, body }, fetchImpl = fetch) {
  const response = await fetchImpl(assertRequestUrl(url), {
    method,
    headers: {
      authorization: `Bearer ${token}`,
      ...(body === undefined ? {} : { "content-type": "application/json" }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (response.status === 204) {
    return {};
  }
  const text = await response.text();
  const parsed = readResponseBody(text, `google play api ${method}`, response);
  if (!response.ok) {
    throw new PlayApiError(`google play api ${method} failed`, response.status, text, parsed);
  }
  return parsed;
}

// Uploads a binary body (AAB / mapping) to an Android Publisher upload endpoint.
export async function uploadMedia(url, { token, contentType, data }, fetchImpl = fetch) {
  const response = await fetchImpl(assertRequestUrl(url), {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": contentType },
    body: data,
  });
  const text = await response.text();
  const parsed = readResponseBody(text, "google play upload", response);
  if (!response.ok) {
    throw new PlayApiError("google play upload failed", response.status, text, parsed);
  }
  return parsed;
}

// Error carrying the HTTP status plus the *raw* (masked) response body. The raw
// body is the load-bearing diagnostic: Google occasionally returns a plaintext
// error (e.g. "Could not commit changes for edit ... app is in draft status")
// instead of JSON, and the previous unconditional JSON.parse discarded it —
// leaving only the useless "... is not valid JSON" (issue #2011).
export class PlayApiError extends Error {
  constructor(label, status, rawBody, parsed) {
    super(`${label}: ${status} ${apiErrorSummary(parsed, rawBody)}`);
    this.name = "PlayApiError";
    this.status = status;
    this.rawBody = rawBody;
    this.parsed = parsed;
  }
}

// Parse a response body as JSON when it *is* JSON; when it is not (a 2xx is
// still expected to be JSON, but a plaintext error must not blow up parsing),
// return the raw text under `_raw` so callers/summaries can surface it verbatim.
export function readResponseBody(text, label, response) {
  if (!text || text.length === 0) {
    return {};
  }
  try {
    return JSON.parse(text);
  } catch {
    // Non-JSON body. On a successful status this is unexpected and must still
    // fail loudly; on an error status the caller emits the raw body.
    if (response && response.ok) {
      throw new PlayApiError(`${label} returned non-JSON on success`, response.status, text, { _raw: text });
    }
    return { _raw: text };
  }
}

// Mask anything that looks like a bearer/access token so a raw body echoed back
// by the server never leaks a credential into logs.
export function maskSecrets(text) {
  if (typeof text !== "string") {
    return text;
  }
  return text
    .replace(/(Bearer\s+)[A-Za-z0-9._~+/-]+=*/gi, "$1***")
    .replace(/("?access_token"?\s*[:=]\s*"?)[A-Za-z0-9._~+/-]+=*/gi, "$1***")
    .replace(/(ya29\.)[A-Za-z0-9._~+/-]+/g, "$1***");
}

export function apiErrorSummary(parsed, rawBody) {
  const error = parsed?.error;
  if (!error || typeof error !== "object") {
    // No structured error object — surface the raw body verbatim (masked,
    // whitespace-collapsed, capped) so plaintext errors are diagnosable at a
    // glance instead of being reduced to "status=unknown".
    const raw = typeof rawBody === "string" && rawBody.length > 0
      ? rawBody
      : (typeof parsed?._raw === "string" ? parsed._raw : "");
    if (raw) {
      return `status=unknown body=${maskSecrets(raw).replace(/\s+/g, " ").trim().slice(0, 400)}`;
    }
    return "status=unknown";
  }
  const status = typeof error.status === "string" ? error.status : "unknown";
  const message = typeof error.message === "string" ? maskSecrets(error.message).replace(/\s+/g, " ").slice(0, 180) : "none";
  return `status=${status} message=${message}`;
}

export function detectServiceAccountSource(env) {
  if (hasValue(env, "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")) {
    return "json";
  }
  if (hasValue(env, "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64")) {
    return "base64";
  }
  return "missing";
}

export function readServiceAccount(env) {
  try {
    if (hasValue(env, "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")) {
      return JSON.parse(env.EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON);
    }
    if (hasValue(env, "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64")) {
      return JSON.parse(Buffer.from(env.EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64.trim(), "base64").toString("utf8"));
    }
  } catch {
    throw new Error("invalid google play service account json");
  }
  throw new Error("missing google play service account json");
}

export function parseDotenv(source) {
  const values = {};
  for (const line of source.split(/\r?\n/)) {
    if (!line || line.trimStart().startsWith("#")) {
      continue;
    }
    const match = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (match) {
      values[match[1]] = unquote(match[2]);
    }
  }
  return values;
}

export function unquote(value) {
  const trimmed = value.trim();
  if (
    (trimmed.startsWith("\"") && trimmed.endsWith("\""))
    || (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1);
  }
  return value;
}

export function hasValue(env, name) {
  return typeof env[name] === "string" && env[name].trim().length > 0;
}

export function requireEnv(env, name) {
  if (!hasValue(env, name)) {
    throw new Error(`missing required env: ${name}`);
  }
  return env[name].trim();
}

export function requireJsonString(value, field) {
  if (typeof value[field] !== "string" || value[field].trim().length === 0) {
    throw new Error(`missing service account field: ${field}`);
  }
  return value[field];
}

export function base64UrlJson(value) {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

export function encodePath(value) {
  return encodeURIComponent(value).replaceAll("%2E", ".");
}
