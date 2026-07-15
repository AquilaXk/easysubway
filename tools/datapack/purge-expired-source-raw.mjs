#!/usr/bin/env node
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

import {
  deriveRawRetentionExpiresAt,
  isValidLegalHold,
} from "./source-governance-policy.mjs";
import { requiredUtcInstant } from "./lib/utc-instant.mjs";

const ALLOWED_ARGS = new Set(["ledger", "policy", "evaluation-at", "base-url", "output"]);
const PROTECTION_REASONS = new Set(["ACTIVE_RELEASE", "ROLLBACK_WINDOW"]);

async function main(argv) {
  const args = parseArgs(argv);
  const outputPath = path.resolve(requiredArg(args, "output"));
  const evaluationAt = requiredArg(args, "evaluation-at");
  const evaluatedMillis = requiredUtcInstant(evaluationAt, "evaluationAt");
  const baseUrl = validatedBaseUrl(requiredArg(args, "base-url"));
  const [ledger, policyText] = await Promise.all([
    readFile(path.resolve(requiredArg(args, "ledger")), "utf8").then(JSON.parse),
    readFile(path.resolve(requiredArg(args, "policy")), "utf8"),
  ]);
  const policy = JSON.parse(policyText);
  const plan = buildPurgePlan({
    ledger,
    policy,
    policySha256: sha256(policyText),
    evaluationAt,
    evaluatedMillis,
    baseUrl,
  });
  const report = emptyReport(evaluationAt, args.dryRun);

  for (const item of plan) {
    if (item.disposition === "PROTECTED") {
      report.protected.push(sanitized(item));
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
    let status;
    try {
      status = (await fetch(item.objectUrl, { method: "DELETE", redirect: "error" })).status;
    } catch {
      status = 0;
    }
    if (status >= 200 && status < 300) {
      report.deleted.push(sanitized(item));
    } else if (status === 404) {
      report.alreadyAbsent.push(sanitized(item));
    } else {
      report.failed.push(sanitized(item));
    }
  }

  if (report.failed.length > 0) report.reasonCodes.push("RAW_RETENTION_OVERDUE");
  report.decision = report.reasonCodes.length === 0 ? "PASS" : "FAIL";
  report.reportSha256 = sha256(JSON.stringify({ ...report, reportSha256: undefined }));
  await writeJson(outputPath, report);
  if (report.decision !== "PASS") throw new Error(report.reasonCodes.join(","));
}

export function buildPurgePlan({ ledger, policy, policySha256, evaluationAt, evaluatedMillis, baseUrl }) {
  if (ledger?.schemaVersion !== 1 || ledger?.artifactKind !== "source-raw-retention-ledger") {
    throw new Error("RAW_RETENTION_OVERDUE: ledger identity");
  }
  if (!Array.isArray(ledger.entries) || ledger.entries.length === 0) {
    throw new Error("RAW_RETENTION_OVERDUE: ledger entries");
  }
  const snapshotIds = new Set();
  const objectKeys = new Set();
  const plan = ledger.entries.map((entry) => {
    const sourceId = requiredText(entry?.sourceId, "sourceId");
    const snapshotId = requiredText(entry?.snapshotId, "snapshotId");
    if (snapshotIds.has(snapshotId)) throw new Error("RAW_RETENTION_OVERDUE: duplicate snapshot");
    snapshotIds.add(snapshotId);
    if (entry.governancePolicyVersion !== policy.policyVersion || entry.governancePolicySha256 !== policySha256) {
      throw new Error("RAW_RETENTION_OVERDUE: governance policy binding");
    }
    if (!/^[0-9a-f]{64}$/.test(entry.rawSha256 ?? "")) {
      throw new Error("RAW_RETENTION_OVERDUE: raw hash");
    }
    const objectKey = validatedObjectKey(entry.objectKey);
    if (objectKeys.has(objectKey)) throw new Error("RAW_RETENTION_OVERDUE: duplicate object key");
    objectKeys.add(objectKey);
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
      disposition,
    };
  });
  return plan.sort((left, right) => (
    left.sourceId.localeCompare(right.sourceId) || left.snapshotId.localeCompare(right.snapshotId)
  ));
}

function parseArgs(argv) {
  const args = { dryRun: false };
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
    if (!value || value.startsWith("--") || args[name] != null) throw new Error(`invalid --${name}`);
    args[name] = value;
    index += 1;
  }
  return args;
}

function validatedBaseUrl(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error("base URL is invalid");
  }
  if (!new Set(["http:", "https:"]).has(url.protocol)) throw new Error("base URL protocol is invalid");
  if (url.username || url.password || url.search || url.hash) throw new Error("base URL must not contain credentials");
  if (!url.pathname.endsWith("/")) url.pathname += "/";
  return url;
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

main(process.argv.slice(2)).catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
});
