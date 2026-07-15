#!/usr/bin/env node
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

import {
  deriveRawRetentionExpiresAt,
  isValidLegalHold,
} from "./source-governance-policy.mjs";
import { requiredUtcInstant } from "./lib/utc-instant.mjs";

const ALLOWED_ARGS = new Set([
  "ledger",
  "policy",
  "snapshots",
  "source-authority",
  "evaluation-at",
  "base-url",
  "output",
]);
const PROTECTION_REASONS = new Set(["ACTIVE_RELEASE", "ROLLBACK_WINDOW"]);
const DELETE_CONCURRENCY = 4;
const DELETE_TIMEOUT_MS = 30_000;
const EXECUTION_EVIDENCE_MAX_AGE_MS = 5 * 60 * 1_000;
const PREAUTH_BASE_URL_ENV = "EASYSUBWAY_SOURCE_RAW_PURGE_PREAUTH_BASE_URL";
const SNAPSHOT_EVIDENCE_SHA256_ENV = "EASYSUBWAY_SOURCE_RAW_PURGE_SNAPSHOT_EVIDENCE_SHA256";
const LEDGER_SHA256_ENV = "EASYSUBWAY_SOURCE_RAW_PURGE_LEDGER_SHA256";
const OBJECT_AUTHORITY_ENV = "EASYSUBWAY_SOURCE_RAW_PURGE_OBJECT_AUTHORITY";

async function main(argv) {
  const args = parseArgs(argv);
  const outputPath = path.resolve(requiredArg(args, "output"));
  const evaluationAt = requiredArg(args, "evaluation-at");
  const evaluatedMillis = requiredUtcInstant(evaluationAt, "evaluationAt");
  if (!args.dryRun) {
    const executionMillis = Date.now();
    if (evaluatedMillis > executionMillis) {
      throw new Error("evaluationAt must not be in the future for actual DELETE");
    }
    if (executionMillis - evaluatedMillis > EXECUTION_EVIDENCE_MAX_AGE_MS) {
      throw new Error("evaluationAt must be recent for actual DELETE");
    }
  }
  const baseUrl = args.dryRun
    ? validatedBaseUrl(requiredArg(args, "base-url"), false)
    : executionBaseUrl(args);
  const sourceAuthority = args.dryRun
    ? validatedSourceAuthority(requiredArg(args, "source-authority"))
    : executionSourceAuthority(args);
  const [ledgerText, snapshotText, policyFiles] = await Promise.all([
    readFile(path.resolve(requiredArg(args, "ledger")), "utf8"),
    readFile(path.resolve(requiredArg(args, "snapshots")), "utf8"),
    Promise.all(requiredPolicies(args).map(async (policyPath) => {
      const text = await readFile(path.resolve(policyPath), "utf8");
      return { policy: JSON.parse(text), sha256: sha256(text) };
    })),
  ]);
  if (!args.dryRun) requireTrustedExecutionEvidence({ ledgerText, snapshotText });
  const plan = buildPurgePlan({
    ledger: JSON.parse(ledgerText),
    snapshots: JSON.parse(snapshotText),
    policyFiles,
    evaluationAt,
    evaluatedMillis,
    baseUrl,
    sourceAuthority,
  });
  const report = emptyReport(evaluationAt, args.dryRun);
  const deleteItems = [];

  for (const item of plan) {
    if (item.disposition === "PROTECTED") {
      report.protected.push(sanitizedProtection(item));
      continue;
    }
    if (item.disposition === "NOT_EXPIRED") {
      report.retained.push(sanitized(item));
      continue;
    }
    if (args.dryRun) {
      report.wouldDelete.push(sanitized(item));
      continue;
    }
    deleteItems.push(item);
  }

  for (const { item, status } of await deleteExpiredItems(deleteItems)) {
    if (status === 200 || status === 204) {
      report.deleted.push(sanitized(item));
    } else if (status === 404 || status === 410) {
      report.alreadyAbsent.push(sanitized(item));
    } else {
      report.failed.push(sanitized(item));
    }
  }

  report.completedAt = args.dryRun ? null : new Date().toISOString();
  if (report.failed.length > 0) report.reasonCodes.push("RAW_RETENTION_OVERDUE");
  report.decision = report.reasonCodes.length === 0 ? "PASS" : "FAIL";
  report.reportSha256 = sha256(JSON.stringify({ ...report, reportSha256: undefined }));
  await writeJson(outputPath, report);
  if (report.decision !== "PASS") throw new Error(report.reasonCodes.join(","));
}

function requireTrustedExecutionEvidence({ ledgerText, snapshotText }) {
  const expectedSnapshot = process.env[SNAPSHOT_EVIDENCE_SHA256_ENV]?.trim();
  if (!/^[0-9a-f]{64}$/.test(expectedSnapshot ?? "")) {
    throw new Error(`${SNAPSHOT_EVIDENCE_SHA256_ENV} snapshot evidence sha256 environment variable is required`);
  }
  if (sha256(snapshotText) !== expectedSnapshot) {
    throw new Error("RAW_RETENTION_OVERDUE: snapshot evidence sha256 mismatch");
  }
  const expectedLedger = process.env[LEDGER_SHA256_ENV]?.trim();
  if (!/^[0-9a-f]{64}$/.test(expectedLedger ?? "")) {
    throw new Error(`${LEDGER_SHA256_ENV} ledger sha256 environment variable is required`);
  }
  if (sha256(ledgerText) !== expectedLedger) {
    throw new Error("RAW_RETENTION_OVERDUE: ledger sha256 mismatch");
  }
}

export async function deleteExpiredItems(
  items,
  { fetchImpl = fetch, timeoutMs = DELETE_TIMEOUT_MS, concurrency = DELETE_CONCURRENCY } = {},
) {
  const results = [];
  for (let index = 0; index < items.length; index += concurrency) {
    const batch = items.slice(index, index + concurrency);
    results.push(...await Promise.all(batch.map(async (item) => {
      let status;
      try {
        const current = await fetchImpl(item.objectUrl, {
          method: "GET",
          redirect: "error",
          signal: AbortSignal.timeout(timeoutMs),
        });
        if (current.status === 404 || current.status === 410) {
          return { item, status: current.status };
        }
        const etag = current.headers?.get?.("etag");
        if (current.status !== 200
          || typeof etag !== "string"
          || !/^"[^"\r\n]+"$/.test(etag)
          || await responseSha256(current) !== item.rawSha256) {
          return { item, status: 412 };
        }
        status = (await fetchImpl(item.objectUrl, {
          method: "DELETE",
          headers: { "If-Match": etag },
          redirect: "error",
          signal: AbortSignal.timeout(timeoutMs),
        })).status;
      } catch {
        status = 0;
      }
      return { item, status };
    })));
  }
  return results;
}

export function buildPurgePlan({
  ledger,
  snapshots,
  policyFiles,
  evaluationAt,
  evaluatedMillis,
  baseUrl,
  sourceAuthority,
}) {
  if (ledger?.schemaVersion !== 1 || ledger?.artifactKind !== "source-raw-retention-ledger") {
    throw new Error("RAW_RETENTION_OVERDUE: ledger identity");
  }
  if (!Array.isArray(ledger.entries) || ledger.entries.length === 0) {
    throw new Error("RAW_RETENTION_OVERDUE: ledger entries");
  }
  if (requiredUtcInstant(ledger.evaluatedAt, "ledger.evaluatedAt") !== evaluatedMillis) {
    throw new Error("RAW_RETENTION_OVERDUE: ledger evaluatedAt mismatch");
  }
  const snapshotIds = new Set();
  const objectKeys = new Set();
  const policies = policyBindings(policyFiles);
  const snapshotEvidence = snapshotBindings(snapshots, sourceAuthority);
  const plan = ledger.entries.map((entry) => {
    const sourceId = requiredText(entry?.sourceId, "sourceId");
    const snapshotId = requiredText(entry?.snapshotId, "snapshotId");
    if (snapshotIds.has(snapshotId)) throw new Error("RAW_RETENTION_OVERDUE: duplicate snapshot");
    snapshotIds.add(snapshotId);
    const policy = policies.get(`${entry.governancePolicyVersion}:${entry.governancePolicySha256}`);
    if (policy == null) {
      throw new Error("RAW_RETENTION_OVERDUE: governance policy binding");
    }
    if (!/^[0-9a-f]{64}$/.test(entry.rawSha256 ?? "")) {
      throw new Error("RAW_RETENTION_OVERDUE: raw hash");
    }
    const objectKey = validatedObjectKey(entry.objectKey);
    if (objectKeys.has(objectKey)) throw new Error("RAW_RETENTION_OVERDUE: duplicate object key");
    objectKeys.add(objectKey);
    const evidence = snapshotEvidence.get(snapshotId);
    if (evidence == null
      || evidence.sourceId !== sourceId
      || evidence.rawSha256 !== entry.rawSha256
      || evidence.objectKey !== objectKey
      || evidence.retrievedMillis !== requiredUtcInstant(entry.retrievedAt, "retrievedAt")) {
      throw new Error("RAW_RETENTION_OVERDUE: snapshot evidence mismatch");
    }
    const derivedExpiry = deriveRawRetentionExpiresAt({ policy, sourceId, retrievedAt: entry.retrievedAt });
    const storedMillis = requiredUtcInstant(entry.rawRetentionExpiresAt, "rawRetentionExpiresAt");
    if (new Date(storedMillis).toISOString() !== derivedExpiry) {
      throw new Error("RAW_RETENTION_OVERDUE: retention derivation mismatch");
    }
    const protectedBy = validateProtectedBy(entry.protectedBy);
    const holdValid = entry.legalHold == null ? false : isValidLegalHold({
      hold: entry.legalHold,
      policy,
      sourceId,
      snapshotId,
      evaluationAt,
    });
    if (entry.legalHold != null && !holdValid) throw new Error("LEGAL_HOLD_INVALID");
    const disposition = protectedBy.length > 0 || holdValid
      ? "PROTECTED"
      : evaluatedMillis >= storedMillis ? "DELETE" : "NOT_EXPIRED";
    return {
      sourceId,
      snapshotId,
      rawSha256: entry.rawSha256,
      objectUrl: objectUrl(baseUrl, objectKey),
      protectedBy,
      legalHold: holdValid ? entry.legalHold : null,
      disposition,
    };
  });
  return plan.sort((left, right) => (
    left.sourceId.localeCompare(right.sourceId) || left.snapshotId.localeCompare(right.snapshotId)
  ));
}

function snapshotBindings(snapshots, expectedSourceAuthority) {
  if (!Array.isArray(snapshots) || snapshots.length === 0) {
    throw new Error("RAW_RETENTION_OVERDUE: snapshot evidence");
  }
  const bindings = new Map();
  for (const snapshot of snapshots) {
    const snapshotId = requiredText(snapshot?.snapshotId, "snapshotId");
    if (bindings.has(snapshotId) || snapshot.snapshotStatus !== "LOCKED") {
      throw new Error("RAW_RETENTION_OVERDUE: snapshot evidence");
    }
    const rawSha256 = snapshot.rawSha256;
    if (!/^[0-9a-f]{64}$/.test(rawSha256 ?? "")) {
      throw new Error("RAW_RETENTION_OVERDUE: snapshot evidence");
    }
    const rawObject = objectKeyFromRawUri(snapshot.rawObjectUri);
    if (rawObject.sourceAuthority !== expectedSourceAuthority) {
      throw new Error("RAW_RETENTION_OVERDUE: storage authority mismatch");
    }
    bindings.set(snapshotId, {
      sourceId: requiredText(snapshot.sourceId, "sourceId"),
      rawSha256,
      objectKey: rawObject.objectKey,
      retrievedMillis: requiredUtcInstant(snapshot.retrievedAt, "retrievedAt"),
    });
  }
  return bindings;
}

function objectKeyFromRawUri(value) {
  let uri;
  try {
    uri = new URL(requiredText(value, "rawObjectUri"));
  } catch {
    throw new Error("RAW_RETENTION_OVERDUE: snapshot evidence");
  }
  if (!["s3:", "oci:"].includes(uri.protocol)
    || uri.username || uri.password || uri.search || uri.hash || !uri.hostname) {
    throw new Error("RAW_RETENTION_OVERDUE: snapshot evidence");
  }
  let objectKey;
  try {
    objectKey = decodeURIComponent(uri.pathname.slice(1));
  } catch {
    throw new Error("RAW_RETENTION_OVERDUE: snapshot evidence");
  }
  return {
    objectKey: validatedObjectKey(objectKey),
    sourceAuthority: `${uri.protocol}//${uri.hostname}`,
  };
}

function parseArgs(argv) {
  const args = { dryRun: false, policy: [] };
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    if (flag === "--dry-run") {
      if (args.dryRun) throw new Error("duplicate --dry-run");
      args.dryRun = true;
      continue;
    }
    const name = flag?.startsWith("--") ? flag.slice(2) : "";
    if (!ALLOWED_ARGS.has(name)) throw new Error("unknown purge argument");
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) throw new Error(`invalid --${name}`);
    if (name === "policy") {
      args.policy.push(value);
    } else {
      if (args[name] != null) throw new Error(`invalid --${name}`);
      args[name] = value;
    }
    index += 1;
  }
  return args;
}

function executionBaseUrl(args) {
  if (args["base-url"] != null) {
    throw new Error(
      `actual DELETE requires the ${PREAUTH_BASE_URL_ENV} preauthenticated base URL environment variable, not --base-url`,
    );
  }
  const value = process.env[PREAUTH_BASE_URL_ENV]?.trim();
  if (!value) {
    throw new Error(`${PREAUTH_BASE_URL_ENV} preauthenticated base URL environment variable is required`);
  }
  return validatedBaseUrl(value, true);
}

function executionSourceAuthority(args) {
  if (args["source-authority"] != null) {
    throw new Error(
      `actual DELETE requires ${OBJECT_AUTHORITY_ENV}, not --source-authority`,
    );
  }
  return validatedSourceAuthority(process.env[OBJECT_AUTHORITY_ENV]);
}

function validatedSourceAuthority(value) {
  let url;
  try {
    url = new URL(requiredText(value, OBJECT_AUTHORITY_ENV));
  } catch {
    throw new Error(`${OBJECT_AUTHORITY_ENV} storage authority is invalid`);
  }
  if (!["s3:", "oci:"].includes(url.protocol)
    || !url.hostname || url.port || url.username || url.password || url.search || url.hash
    || (url.pathname !== "" && url.pathname !== "/")) {
    throw new Error(`${OBJECT_AUTHORITY_ENV} storage authority is invalid`);
  }
  return `${url.protocol}//${url.hostname}`;
}

function validatedBaseUrl(value, execution) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error("base URL is invalid");
  }
  const loopback = new Set(["127.0.0.1", "localhost", "::1"]).has(url.hostname);
  if (url.protocol !== "https:" && !(execution && loopback && url.protocol === "http:")
    && !(!execution && url.protocol === "http:")) {
    throw new Error("base URL protocol is invalid");
  }
  if (url.username || url.password || url.search || url.hash) throw new Error("base URL must not contain credentials");
  if (execution && !loopback && url.pathname === "/") {
    throw new Error("preauthenticated base URL must include a secret path");
  }
  if (!url.pathname.endsWith("/")) url.pathname += "/";
  return url;
}

function requiredPolicies(args) {
  if (!Array.isArray(args.policy) || args.policy.length === 0) {
    throw new Error("--policy is required");
  }
  return args.policy;
}

function policyBindings(policyFiles) {
  const bindings = new Map();
  for (const file of policyFiles) {
    const version = requiredText(file?.policy?.policyVersion, "policyVersion");
    if (!/^[0-9a-f]{64}$/.test(file?.sha256 ?? "")) {
      throw new Error("RAW_RETENTION_OVERDUE: governance policy hash");
    }
    const key = `${version}:${file.sha256}`;
    if (bindings.has(key)) throw new Error("RAW_RETENTION_OVERDUE: duplicate governance policy");
    bindings.set(key, file.policy);
  }
  return bindings;
}

function validatedObjectKey(value) {
  const key = requiredText(value, "objectKey");
  if (key.startsWith("/") || key.split("/").some((segment) => (
    segment === "" || segment === "." || segment === ".." || !/^[A-Za-z0-9._-]+$/.test(segment)
  ))) {
    throw new Error("RAW_RETENTION_OVERDUE: object key");
  }
  return key;
}

function objectUrl(baseUrl, objectKey) {
  const url = new URL(objectKey.split("/").map(encodeURIComponent).join("/"), baseUrl);
  if (url.origin !== baseUrl.origin || !url.pathname.startsWith(baseUrl.pathname)) {
    throw new Error("RAW_RETENTION_OVERDUE: object path");
  }
  return url;
}

function validateProtectedBy(value) {
  if (!Array.isArray(value) || new Set(value).size !== value.length) {
    throw new Error("RAW_RETENTION_OVERDUE: protectedBy");
  }
  for (const reason of value) {
    if (!PROTECTION_REASONS.has(reason)) throw new Error("RAW_RETENTION_OVERDUE: protection reason");
  }
  return value;
}

function emptyReport(evaluationAt, dryRun) {
  return {
    schemaVersion: 1,
    artifactKind: "source-raw-purge-report",
    evaluatedAt: new Date(requiredUtcInstant(evaluationAt, "evaluationAt")).toISOString(),
    completedAt: null,
    dryRun,
    decision: "PASS",
    deleted: [],
    alreadyAbsent: [],
    protected: [],
    retained: [],
    wouldDelete: [],
    failed: [],
    reasonCodes: [],
  };
}

function sanitized(item) {
  return { sourceId: item.sourceId, snapshotId: item.snapshotId, rawSha256: item.rawSha256 };
}

function sanitizedProtection(item) {
  return {
    ...sanitized(item),
    protectedBy: item.protectedBy,
    legalHold: item.legalHold,
  };
}

async function responseSha256(response) {
  if (response.body == null) return null;
  const hash = createHash("sha256");
  for await (const chunk of response.body) hash.update(chunk);
  return hash.digest("hex");
}

async function writeJson(outputPath, value) {
  await mkdir(path.dirname(outputPath), { recursive: true });
  await writeFile(outputPath, `${JSON.stringify(value, null, 2)}\n`);
}

function requiredArg(args, name) {
  return requiredText(args[name], `--${name}`);
}

function requiredText(value, label) {
  if (typeof value !== "string" || value.trim() === "") throw new Error(`${label} is required`);
  return value;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main(process.argv.slice(2)).catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  });
}
