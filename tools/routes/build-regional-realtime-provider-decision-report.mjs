#!/usr/bin/env node
import { readFile, writeFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

import { buildRealtimeProviderCoverageReport } from "./build-realtime-provider-coverage-report.mjs";

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}

export async function main(argv) {
  const args = parseArgs(argv);
  const targets = JSON.parse(await readFile(args.targets, "utf8"));
  const contract = JSON.parse(await readFile(args.contract, "utf8"));
  const report = buildRegionalRealtimeProviderDecisionReport({ targets, contract });
  await writeFile(args.output, `${JSON.stringify(report, null, 2)}\n`);
  return report;
}

export function buildRegionalRealtimeProviderDecisionReport({ targets, contract } = {}) {
  validateContractHeader(targets, contract);
  const excludedRegionIds = uniqueStrings(contract.scope?.excludedRegionIds, "scope.excludedRegionIds");
  const excluded = new Set(excludedRegionIds);
  const scopes = targets.activeLineScopes.filter(({ regionId }) => !excluded.has(regionId));
  if (scopes.length === 0) throw new Error("regional realtime scope must not be empty");

  const sources = validateOfficialSources(contract.officialSources);
  const sourcesById = new Map(sources.map((source) => [source.id, source]));

  const decisionsByKey = new Map();
  for (const [index, decision] of contract.decisions.entries()) {
    const normalized = validateDecision(decision, index, sourcesById);
    const key = scopeKey(normalized);
    if (decisionsByKey.has(key)) throw new Error(`duplicate regional realtime decision: ${key}`);
    decisionsByKey.set(key, normalized);
  }

  const scopeKeys = new Set(scopes.map(scopeKey));
  for (const key of decisionsByKey.keys()) {
    if (!scopeKeys.has(key)) throw new Error(`unknown regional realtime decision: ${key}`);
  }
  const decisions = scopes.map((scope) => {
    const key = scopeKey(scope);
    const decision = decisionsByKey.get(key);
    if (!decision) throw new Error(`missing regional realtime decision: ${key}`);
    return decision;
  });
  const supportedDecisionCount = decisions.filter(({ state }) => state === "SUPPORTED").length;
  validatePublicApiAudit(contract.publicApiAudit, scopes.length, supportedDecisionCount);

  const regionIds = [...new Set(scopes.map(({ regionId }) => regionId))]
    .sort((left, right) => left.localeCompare(right, "en"));
  const scope = {
    excludedRegionIds,
    regionIds,
    activeLineOperatorScopeCount: scopes.length,
  };
  const coverageRequirements = decisions.map((decision) => ({
    regionId: decision.regionId,
    operatorId: decision.operatorId,
    lineId: decision.lineId,
    sourceDomain: "realtime_arrivals",
    state: decision.state,
    fallback: decision.fallback,
    userMessageKo: decision.userMessageKo,
  }));
  const coverage = buildRealtimeProviderCoverageReport({
    scope,
    stationLinePairs: [],
    samples: [],
    coverageRequirements,
    unsupportedRegions: regionIds.map((region) => ({
      region,
      reason: "실시간 미지원",
    })),
  });

  return {
    ...coverage,
    artifactKind: "regional-realtime-provider-decision-report",
    issue: contract.issue,
    targetVersion: contract.targetVersion,
    verifiedAt: contract.verifiedAt,
    officialSources: sources,
    publicApiAudit: contract.publicApiAudit,
    decisionEvidence: decisions,
  };
}

function validateContractHeader(targets, contract) {
  if (!targets || !Array.isArray(targets.activeLineScopes) || targets.activeLineScopes.length === 0) {
    throw new Error("nationwide activeLineScopes are required");
  }
  if (!contract || contract.schemaVersion !== 1
    || contract.artifactKind !== "regional-realtime-provider-decisions") {
    throw new Error("regional realtime provider decision contract is invalid");
  }
  if (contract.issue !== 1621) throw new Error("regional realtime provider decision issue must be 1621");
  if (requiredString(contract.targetVersion, "targetVersion") !== targets.targetVersion) {
    throw new Error("regional realtime targetVersion must match nationwide targets");
  }
  if (!Number.isFinite(Date.parse(requiredString(contract.verifiedAt, "verifiedAt")))) {
    throw new Error("verifiedAt must be an ISO timestamp");
  }
  if (!Array.isArray(contract.decisions) || contract.decisions.length === 0) {
    throw new Error("regional realtime decisions are required");
  }
}

function validateOfficialSources(value) {
  if (!Array.isArray(value) || value.length === 0) throw new Error("officialSources are required");
  const seen = new Set();
  return value.map((source, index) => {
    const label = `officialSources[${index}]`;
    const id = requiredString(source?.id, `${label}.id`);
    if (seen.has(id)) throw new Error(`duplicate official source: ${id}`);
    seen.add(id);
    const url = new URL(requiredString(source.url, `${label}.url`));
    if (url.protocol !== "https:" || url.hostname !== "www.data.go.kr") {
      throw new Error(`${label}.url must be an official data.go.kr HTTPS URL`);
    }
    return {
      ...source,
      id,
      url: url.href,
      decision: requiredString(source.decision, `${label}.decision`),
    };
  });
}

function validatePublicApiAudit(audit, scopeCount, supportedDecisionCount) {
  if (!audit || typeof audit !== "object" || Array.isArray(audit)) {
    throw new Error("publicApiAudit is required");
  }
  for (const field of [
    "targetCount",
    "credentialSafeCallCount",
    "supportedCount",
    "explicitNoDataCount",
    "falsePositiveClassifiedCount",
    "boundedRetryCount",
  ]) {
    if (!Number.isInteger(audit[field]) || audit[field] < 0) {
      throw new Error(`publicApiAudit.${field} must be a non-negative integer`);
    }
  }
  if (audit.targetCount !== scopeCount
    || audit.supportedCount + audit.explicitNoDataCount + audit.falsePositiveClassifiedCount !== scopeCount) {
    throw new Error("publicApiAudit counts must resolve every regional scope");
  }
  if (audit.supportedCount !== supportedDecisionCount) {
    throw new Error("publicApiAudit.supportedCount must match supported decisions");
  }
  if (audit.credentialSafeCallCount < audit.targetCount) {
    throw new Error("publicApiAudit credential-safe calls must cover every target");
  }
  if (!/^[a-f0-9]{64}$/.test(audit.searchPlanSha256 ?? "")) {
    throw new Error("publicApiAudit.searchPlanSha256 is invalid");
  }
}

function validateDecision(decision, index, sourcesById) {
  const label = `decisions[${index}]`;
  const normalized = {};
  for (const field of ["regionId", "operatorId", "lineId", "state", "fallback", "routeFallbackCapability", "userMessageKo"]) {
    normalized[field] = requiredString(decision?.[field], `${label}.${field}`);
  }
  if (!new Set(["SUPPORTED", "EXPLICITLY_UNSUPPORTED_WITH_EVIDENCE"]).has(normalized.state)) {
    throw new Error(`${label}.state must be terminal`);
  }
  if (normalized.state === "SUPPORTED") {
    normalized.providerId = requiredString(decision.providerId, `${label}.providerId`);
    if (normalized.fallback !== "NONE") throw new Error(`${label} supported fallback must be NONE`);
  } else {
    if (normalized.fallback === "REALTIME") throw new Error(`${label} unsupported fallback must not be REALTIME`);
    if (normalized.routeFallbackCapability !== "PLANNED") {
      throw new Error(`${label}.routeFallbackCapability must be PLANNED`);
    }
  }
  if (/(coverage|provider|승격|게이트|검증|pilot)/iu.test(normalized.userMessageKo)) {
    throw new Error(`${label}.userMessageKo contains internal release vocabulary`);
  }
  normalized.evidenceRefs = uniqueStrings(decision.evidenceRefs, `${label}.evidenceRefs`);
  for (const evidenceRef of normalized.evidenceRefs) {
    if (!sourcesById.has(evidenceRef)) throw new Error(`${label} has unknown evidence ref: ${evidenceRef}`);
  }
  for (const field of ["evidenceHash", "reviewedAt", "nextReviewAt", "reasonCode"]) {
    if (decision[field] !== undefined) normalized[field] = requiredString(decision[field], `${label}.${field}`);
  }
  if (normalized.evidenceHash && !/^[a-f0-9]{64}$/.test(normalized.evidenceHash)) {
    throw new Error(`${label}.evidenceHash is invalid`);
  }
  return normalized;
}

function uniqueStrings(value, label) {
  if (!Array.isArray(value) || value.length === 0
    || value.some((item) => typeof item !== "string" || item.trim() === "")) {
    throw new Error(`${label} must be a non-empty string array`);
  }
  if (new Set(value).size !== value.length) throw new Error(`${label} must not contain duplicates`);
  return [...value];
}

function requiredString(value, label) {
  if (typeof value !== "string" || value.trim() === "") throw new Error(`${label} is required`);
  return value;
}

function scopeKey({ regionId, operatorId, lineId }) {
  return `${regionId}:${operatorId}:${lineId}`;
}

function parseArgs(argv) {
  if (argv.length !== 6 || argv[0] !== "--targets" || argv[2] !== "--contract" || argv[4] !== "--output") {
    throw new Error("usage: build-regional-realtime-provider-decision-report.mjs --targets <targets.json> --contract <decisions.json> --output <report.json>");
  }
  return { targets: argv[1], contract: argv[3], output: argv[5] };
}
