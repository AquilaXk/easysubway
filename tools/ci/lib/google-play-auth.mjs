// Shared Google Play (Android Publisher API v3) service-account auth and request
// helpers. Extracted from check-google-play-api-access.mjs so the internal-track
// upload tool can reuse the exact JWT flow instead of a third-party action
// (issue #1689 — keeps the supply-chain surface minimal).
import { createSign } from "node:crypto";

export const androidPublisherScope = "https://www.googleapis.com/auth/androidpublisher";
export const defaultTokenUri = "https://oauth2.googleapis.com/token";
export const defaultApiBaseUrl = "https://androidpublisher.googleapis.com/androidpublisher/v3";

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
  const response = await fetchImpl(tokenUri, {
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
  const response = await fetchImpl(url, {
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
  const parsed = text.length === 0 ? {} : JSON.parse(text);
  if (!response.ok) {
    throw new Error(`google play api ${method} failed: ${response.status} ${apiErrorSummary(parsed)}`);
  }
  return parsed;
}

// Uploads a binary body (AAB / mapping) to an Android Publisher upload endpoint.
export async function uploadMedia(url, { token, contentType, data }, fetchImpl = fetch) {
  const response = await fetchImpl(url, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": contentType },
    body: data,
  });
  const text = await response.text();
  const parsed = text.length === 0 ? {} : JSON.parse(text);
  if (!response.ok) {
    throw new Error(`google play upload failed: ${response.status} ${apiErrorSummary(parsed)}`);
  }
  return parsed;
}

export function apiErrorSummary(parsed) {
  const error = parsed.error;
  if (!error || typeof error !== "object") {
    return "status=unknown";
  }
  const status = typeof error.status === "string" ? error.status : "unknown";
  const message = typeof error.message === "string" ? error.message.replace(/\s+/g, " ").slice(0, 180) : "none";
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
