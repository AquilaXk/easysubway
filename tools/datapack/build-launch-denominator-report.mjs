import { createHash } from "node:crypto";

export function canonicalScopeHash(scope) {
  return createHash("sha256").update(JSON.stringify(canonicalize(scope))).digest("hex");
}

export function buildLaunchDenominatorReport(scope, evidence) {
  const blockers = collectV1Blockers(scope, evidence);
  const identities = ["source", "server", "mobile"].map((consumer) => evidence?.[consumer]?.identity);
  const sharedFields = scope?.identityMatrix?.requiredSharedFields ?? [];
  const sharedIdentity = Object.fromEntries(sharedFields.map((field) => [field, identities[0]?.[field] ?? null]));
  return {
    decision: blockers.length === 0 ? "GO" : "NO_GO",
    blockers,
    nationwideBlocksV1: false,
    scopes: {
      verifiedAccessibilityScope: scopeSummary(scope?.verifiedAccessibilityScope),
      routingLaunchScope: scopeSummary(scope?.routingLaunchScope),
      nationwideRoadmapScope: scopeSummary(scope?.nationwideRoadmapScope),
    },
    identityLinkage: {
      compatible: !blockers.some((blocker) => blocker.startsWith("IDENTITY_")),
      shared: sharedIdentity,
      artifactHashes: {
        source: evidence?.source?.artifactHash ?? null,
        server: evidence?.server?.artifactHash ?? null,
        mobile: evidence?.mobile?.artifactHash ?? null,
      },
    },
  };
}

function collectV1Blockers(scope, evidence) {
  const blockers = [];
  const accessibilityScope = scope?.verifiedAccessibilityScope;
  const routingScope = scope?.routingLaunchScope;
  const identityMatrix = scope?.identityMatrix;

  if (!sameSet(requiredPilotRowIds(accessibilityScope), evidence?.pilot?.coveredRowIds)) {
    blockers.push("PILOT_ROW_GAP");
  }

  const admittedStations = evidence?.routing?.admittedStationIds;
  if (
    !nonEmptyStringSet(admittedStations)
    || !isSubset(admittedStations, routingScope?.candidateStationIds)
    || !sameSet(admittedStations, evidence?.routing?.materializedStationIds)
  ) {
    blockers.push("ROUTING_STATION_ID_GAP");
  }
  if (!sameSet(routingScope?.requiredBaseEdgeIds, evidence?.routing?.baseEdgeIds)) {
    blockers.push("ROUTING_BASE_EDGE_ID_GAP");
  }
  if (!sameSet(routingScope?.requiredTransferEdgeIds, evidence?.routing?.transferEdgeIds)) {
    blockers.push("ROUTING_TRANSFER_EDGE_ID_GAP");
  }
  if (!sameSet(routingScope?.serviceIds, evidence?.routing?.serviceIds)) {
    blockers.push("ROUTING_SERVICE_SCOPE_MISMATCH");
  }

  if (evidence?.source?.status !== "ADMITTED") blockers.push("SOURCE_NOT_ADMITTED");
  if (evidence?.source?.freshness !== "FRESH") blockers.push("SOURCE_STALE");
  if (evidence?.source?.routingScopeHash !== canonicalScopeHash(routingScope)) {
    blockers.push("ROUTING_SCOPE_HASH_MISMATCH");
  }
  if (evidence?.server?.status !== "ACTIVE") blockers.push("SERVER_NOT_ACTIVE");
  if (evidence?.server?.routingReady !== true) blockers.push("SERVER_ROUTING_NOT_READY");
  if (evidence?.mobile?.status !== "READY") blockers.push("MOBILE_NOT_READY");
  if (evidence?.mobile?.topologyReady !== true) blockers.push("MOBILE_TOPOLOGY_NOT_READY");

  const consumers = ["source", "server", "mobile"];
  for (const field of identityMatrix?.requiredSharedFields ?? []) {
    const values = consumers.map((consumer) => evidence?.[consumer]?.identity?.[field]);
    if (values.some((value) => value === undefined || value === null) || new Set(values).size !== 1) {
      blockers.push(`IDENTITY_FIELD_MISMATCH:${field}`);
    }
  }
  const artifactHashes = consumers.map((consumer) => evidence?.[consumer]?.artifactHash);
  if (artifactHashes.some((hash) => !/^[a-f0-9]{64}$/.test(hash ?? ""))) {
    blockers.push("IDENTITY_ARTIFACT_HASH_INVALID");
  } else if (identityMatrix?.differentArtifactHashesAllowed !== true && new Set(artifactHashes).size !== 1) {
    blockers.push("IDENTITY_ARTIFACT_HASH_MISMATCH");
  }

  if (evidence?.safety?.signatureValid !== true) blockers.push("SIGNATURE_INVALID");
  if (evidence?.safety?.rollbackVerified !== true) blockers.push("ROLLBACK_UNVERIFIED");
  if (evidence?.safety?.freshness !== "FRESH") blockers.push("EVIDENCE_STALE");
  if (evidence?.safety?.lineage !== "VERIFIED") blockers.push("LINEAGE_UNVERIFIED");

  if (
    evidence?.claims?.accessibilityScopeId !== accessibilityScope?.id
    || evidence?.claims?.routingScopeId !== routingScope?.id
    || !sameSet(evidence?.claims?.serviceIds, routingScope?.serviceIds)
  ) {
    blockers.push("CLAIM_SCOPE_MISMATCH");
  }
  if ((evidence?.forbiddenEvidence ?? []).some(({ evidenceClass }) =>
    ["FIXTURE", "LEGACY", "OTHER_SERVICE"].includes(evidenceClass))) {
    blockers.push("FORBIDDEN_EVIDENCE_CLASS");
  }

  return [...new Set(blockers)];
}

function requiredPilotRowIds(scope) {
  if (nonEmptyStringSet(scope?.requiredRowIds)) return scope.requiredRowIds;
  if (!nonEmptyStringSet(scope?.includedStationIds) || !nonEmptyStringSet(scope?.requiredFacilityTypes)) return [];
  return scope.includedStationIds.flatMap((stationId) =>
    scope.requiredFacilityTypes.map((facilityType) => `${stationId}|${scope.includedLineIds?.[0] ?? ""}|${facilityType}`));
}

function scopeSummary(value) {
  return {
    id: value?.id ?? null,
    sha256: canonicalScopeHash(value),
  };
}

function sameSet(left, right) {
  if (!nonEmptyStringSet(left) || !nonEmptyStringSet(right)) return false;
  if (left.length !== right.length) return false;
  const expected = new Set(left);
  return expected.size === left.length && new Set(right).size === right.length
    && right.every((value) => expected.has(value));
}

function isSubset(values, allowedValues) {
  if (!nonEmptyStringSet(allowedValues)) return false;
  const allowed = new Set(allowedValues);
  return values.every((value) => allowed.has(value));
}

function nonEmptyStringSet(values) {
  return Array.isArray(values) && values.length > 0
    && values.every((value) => typeof value === "string" && value.length > 0)
    && new Set(values).size === values.length;
}

function canonicalize(value) {
  if (Array.isArray(value)) {
    return value.map(canonicalize).sort((left, right) =>
      JSON.stringify(left).localeCompare(JSON.stringify(right)));
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]),
    );
  }
  return value;
}
