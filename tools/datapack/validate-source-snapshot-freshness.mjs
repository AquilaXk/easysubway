#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { deriveFreshness } from "./freshness-policy.mjs";
import { requiredUtcInstant } from "./lib/utc-instant.mjs";
import {
  evaluateSourceGovernance,
  validateSourceGovernancePolicy,
} from "./source-governance-policy.mjs";
import { validateLineage } from "./source-snapshot-policy.mjs";

const buildProvenanceStringFields = [
  "snapshotId",
  "sourceId",
  "rawObjectUri",
  "redactedRequestFingerprint",
  "licenseStatus",
  "snapshotStatus",
];
const policyBoundProvenanceStringFields = [
  "freshnessExpiresAt",
  "rawRetentionExpiresAt",
  "governancePolicyVersion",
  "governancePolicySha256",
];
const buildProvenanceBooleanFields = ["redistributionAllowed", "credentialRedacted"];
const approvedLegacyGovernanceSnapshotHashes = new Map([
  ["molit-urban-rail-full-route-capital-admission-20260712", "3f676f7ffd29b1a1b5872d65c9926284ba6c88f9a64e00d31323c8617131f452"],
  ["seoulmetro-station-line-info-capital-admission-20260712", "8a171105588371f087f8ee58e2c207c0ed1a32dc6b459aa0427d7262ad393e07"],
  ["seoulmetro-cyberstation-route-map-capital-admission-20260712", "ae9d8e6b2f188418d9c1ee0fda785d9fd3665b771eafdd3c5e15ef0b34f957b4"],
  ["kric-station-elevator-capital-admission-20260712", "c1351b184a737276d3dcc914e3db5df7d9e5c7ff82326cd5fbadbe6da2eba097"],
  ["kric-station-elevator-movement-capital-admission-20260712", "0bf00ab2ad3505dc0ade0c5d42d7500fe5891e6f9a961502323e387a3474980c"],
  ["kric-station-escalator-capital-admission-20260712", "7e2047e4cd54fe6c1aba05a3880537851159bd6a59a0a89e75c737bec3706df5"],
  ["kric-wheelchair-lift-location-capital-admission-20260712", "5e8639bfa85a3113362ebb413bc8ef9ca9b282deddde4f7c08d562959d26cd8e"],
  ["kric-wheelchair-lift-movement-capital-admission-20260712", "07fb9337abf08aa4b08c845989552c1c076a7b32c9698431edcee4c8490c77a0"],
  ["seoul-metro-accessibility-capital-admission-20260712", "4e9ba33455d89b68e6e9e0708c07fa2ab2aaa31bb7fe8b5c3930cfe71a315340"],
  ["kric-subway-timetable-line4-pilot-20260709", "09323a9ebd2f7398c0baf18fb40100936790e571ce1ae00d6e8aae9f044ad80a"],
]);

export function validateSourceSnapshotFreshness({
  buildSpec,
  snapshots,
  policy,
  evaluationAt,
  governancePolicy = null,
  inventory = null,
  governancePolicySha256 = null,
  purgeReport = null,
}) {
  if (!Array.isArray(buildSpec?.sourceSnapshotIds) || buildSpec.sourceSnapshotIds.length === 0) {
    throw new Error("SOURCE_FRESHNESS_POLICY_MISSING: buildSpec.sourceSnapshotIds");
  }
  if (!Array.isArray(snapshots) || snapshots.length === 0) {
    throw new Error("SOURCE_FRESHNESS_POLICY_MISSING: source snapshots");
  }
  const { headsBySource } = validateLineage(snapshots);
  const selectedSnapshots = selectSnapshots(snapshots, buildSpec.sourceSnapshotIds);
  for (const snapshot of selectedSnapshots) {
    if (headsBySource[snapshot.sourceId] !== snapshot.snapshotId) {
      throw new Error("SOURCE_LINEAGE_BROKEN: selected snapshot is not source head");
    }
  }
  if (inventory != null) validateRequiredProductionSources(selectedSnapshots, inventory);
  const includeGovernance = governancePolicy != null;
  const evidenceProvenance = canonicalBuildProvenance(selectedSnapshots, "snapshots");
  const buildProvenance = canonicalBuildProvenance(
    buildSpec.sourceSnapshots,
    "buildSpec.sourceSnapshots",
  );
  if (JSON.stringify(evidenceProvenance) !== JSON.stringify(buildProvenance)) {
    throw new Error("SOURCE_FRESHNESS_DERIVATION_MISMATCH: source snapshot provenance");
  }
  const effectiveSnapshots = includeGovernance
    ? bindGovernanceProvenance(selectedSnapshots, buildSpec.sourceSnapshots)
    : selectedSnapshots;
  if (!includeGovernance) {
    const evidencePolicyProvenance = canonicalPolicyProvenance(selectedSnapshots, "snapshots", false);
    const buildPolicyProvenance = canonicalPolicyProvenance(
      buildSpec.sourceSnapshots,
      "buildSpec.sourceSnapshots",
      false,
    );
    if (JSON.stringify(evidencePolicyProvenance) !== JSON.stringify(buildPolicyProvenance)) {
      throw new Error("SOURCE_FRESHNESS_DERIVATION_MISMATCH: source snapshot provenance");
    }
  }
  const snapshotSetHash = sha256(JSON.stringify(selectedSnapshots));
  if (snapshotSetHash !== buildSpec.sourceSnapshotSetHash) {
    throw new Error("SOURCE_FRESHNESS_DERIVATION_MISMATCH: source snapshot set hash");
  }

  const results = effectiveSnapshots.map((snapshot) => {
    const sourceId = requiredString(snapshot.sourceId, "sourceId");
    const sourceClasses = policy?.sourceClasses?.filter((entry) => entry.sourceIds?.includes(sourceId)) ?? [];
    if (sourceClasses.length !== 1) {
      throw new Error(`SOURCE_FRESHNESS_POLICY_MISSING: ${sourceId}`);
    }
    const sourceClass = sourceClasses[0];
    return {
      snapshotId: snapshot.snapshotId,
      sourceClassId: sourceClass.id,
      ...deriveFreshness({
        policy,
        sourceClassId: sourceClass.id,
        basisAt: snapshot[sourceClass.basisField],
        providerValidUntil: sourceClass.providerValidityEndField
          ? snapshot[sourceClass.providerValidityEndField]
          : undefined,
        storedExpiresAt: snapshot.freshnessExpiresAt,
        evaluationAt,
      }),
    };
  });
  if (results.some((result) => result.status !== "FRESH")) {
    throw new Error("SOURCE_SNAPSHOT_EXPIRED");
  }
  let governanceResults = [];
  const purgeEvidence = purgeReport == null ? new Map() : purgeEvidenceBySnapshot(purgeReport);
  if (governancePolicy != null || inventory != null) {
    if (governancePolicy == null || inventory == null) {
      throw new Error("SOURCE_GOVERNANCE_OWNER_MISSING: governance policy and inventory are required together");
    }
    validateSourceGovernancePolicy({ policy: governancePolicy, inventory, freshnessPolicy: policy });
    if (!/^[0-9a-f]{64}$/.test(governancePolicySha256 ?? "")) {
      throw new Error("SOURCE_GOVERNANCE_OWNER_MISSING: governance policy hash");
    }
    if (effectiveSnapshots.some((snapshot) => (
      snapshot.governancePolicyVersion !== governancePolicy.policyVersion
      || snapshot.governancePolicySha256 !== governancePolicySha256
    ))) {
      throw new Error("SOURCE_FRESHNESS_POLICY_MISSING: governance policy binding");
    }
    const sources = new Map(inventory.sources.map((source) => [source.id, source]));
    governanceResults = effectiveSnapshots.map((snapshot) => evaluateSourceGovernance({
      source: sources.get(snapshot.sourceId),
      snapshot,
      policy: governancePolicy,
      freshnessPolicy: policy,
      evaluationAt,
      purgeEvidence: purgeEvidence.get(`${snapshot.sourceId}\0${snapshot.snapshotId}`) ?? null,
    }));
    const reasonCodes = [...new Set(governanceResults.flatMap((result) => result.reasonCodes))].sort();
    if (reasonCodes.length > 0) throw new Error(reasonCodes.join(","));
  }
  return { snapshotSetHash, results, governanceResults };
}

async function main(argv) {
  const args = parseArgs(argv);
  const buildSpecPath = requiredArg(args, "build-spec");
  const policyPath = requiredArg(args, "policy");
  const buildSpec = JSON.parse(await readFile(buildSpecPath, "utf8"));
  const snapshotsPath = requiredString(
    buildSpec.sourceSnapshotEvidencePath,
    "buildSpec.sourceSnapshotEvidencePath",
  );
  const root = process.cwd();
  const resolvedEvidencePath = path.resolve(root, snapshotsPath);
  assertRepositoryRelativePath(path.relative(root, resolvedEvidencePath));
  const governancePolicyPath = args.get("governance-policy");
  const inventoryPath = args.get("inventory");
  if ((governancePolicyPath == null) !== (inventoryPath == null)) {
    throw new Error("--governance-policy and --inventory must be provided together");
  }
  const purgeReportPath = buildSpec.sourceRawPurgeReportPath;
  const [snapshots, policy, governancePolicyText, inventory, purgeReportText] = await Promise.all([
    readFile(resolvedEvidencePath, "utf8").then(JSON.parse),
    readFile(policyPath, "utf8").then(JSON.parse),
    governancePolicyPath ? readFile(governancePolicyPath, "utf8") : null,
    inventoryPath ? readFile(inventoryPath, "utf8").then(JSON.parse) : null,
    purgeReportPath ? readRepositoryArtifact(root, purgeReportPath, "buildSpec.sourceRawPurgeReportPath") : null,
  ]);
  if (purgeReportText != null
    && sha256(purgeReportText) !== requiredSha256(
      buildSpec.sourceRawPurgeReportSha256,
      "buildSpec.sourceRawPurgeReportSha256",
    )) {
    throw new Error("SOURCE_FRESHNESS_DERIVATION_MISMATCH: purge report hash");
  }
  const governancePolicy = governancePolicyText ? JSON.parse(governancePolicyText) : null;
  const result = validateSourceSnapshotFreshness({
    buildSpec,
    snapshots,
    policy,
    evaluationAt: args.get("evaluation-at") ?? new Date().toISOString(),
    governancePolicy,
    inventory,
    governancePolicySha256: governancePolicyText ? sha256(governancePolicyText) : null,
    purgeReport: purgeReportText ? JSON.parse(purgeReportText) : null,
  });
  process.stdout.write(`${JSON.stringify({
    status: "PASS",
    sourceSnapshotSetHash: result.snapshotSetHash,
    snapshotCount: result.results.length,
    governanceDecision: result.governanceResults.length > 0 ? "GO" : "NOT_EVALUATED",
  })}\n`);
}

export function assertRepositoryRelativePath(relativePath) {
  if (relativePath.startsWith("..") || path.isAbsolute(relativePath)) {
    throw new Error("buildSpec.sourceSnapshotEvidencePath must stay within the repository");
  }
}

async function readRepositoryArtifact(root, artifactPath, label) {
  const relativePath = requiredString(artifactPath, label);
  const resolvedPath = path.resolve(root, relativePath);
  assertRepositoryRelativePath(path.relative(root, resolvedPath));
  return readFile(resolvedPath, "utf8");
}

function parseArgs(argv) {
  const args = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const token = argv[index];
    const value = argv[index + 1];
    if (!token?.startsWith("--") || value == null || value.startsWith("--")) {
      throw new Error(`invalid argument: ${token ?? "<end>"}`);
    }
    args.set(token.slice(2), value);
  }
  return args;
}

function requiredArg(args, name) {
  return requiredString(args.get(name), `--${name}`);
}

function requiredString(value, label) {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${label} must be a non-empty string`);
  }
  return value;
}

function requiredSha256(value, label) {
  const normalized = requiredString(value, label);
  if (!/^[0-9a-f]{64}$/.test(normalized)) throw new Error(`${label} must be sha256`);
  return normalized;
}

export function purgeEvidenceBySnapshot(report) {
  const expectedHash = sha256(JSON.stringify({ ...report, reportSha256: undefined }));
  let completedMillis = Number.NaN;
  let evaluatedMillis = Number.NaN;
  try {
    completedMillis = requiredUtcInstant(report?.completedAt, "purge report completedAt");
    evaluatedMillis = requiredUtcInstant(report?.evaluatedAt, "purge report evaluatedAt");
  } catch {
    // The identity check below reports one stable contract error.
  }
  if (report?.schemaVersion !== 1
    || report?.artifactKind !== "source-raw-purge-report"
    || report.dryRun !== false
    || report.decision !== "PASS"
    || report.reportSha256 !== expectedHash
    || !Array.isArray(report.reasonCodes)
    || report.reasonCodes.length !== 0
    || !Array.isArray(report.failed)
    || report.failed.length !== 0
    || !Number.isFinite(completedMillis)
    || !Number.isFinite(evaluatedMillis)
    || completedMillis < evaluatedMillis
    || !Array.isArray(report.deleted)
    || !Array.isArray(report.alreadyAbsent)) {
    throw new Error("SOURCE_FRESHNESS_DERIVATION_MISMATCH: purge report");
  }
  const purgedAt = new Date(completedMillis).toISOString();
  const evidence = new Map();
  for (const entry of [...report.deleted, ...report.alreadyAbsent]) {
    const sourceId = requiredString(entry?.sourceId, "purge report sourceId");
    const snapshotId = requiredString(entry?.snapshotId, "purge report snapshotId");
    const rawSha256 = requiredSha256(entry?.rawSha256, "purge report rawSha256");
    const key = `${sourceId}\0${snapshotId}`;
    if (evidence.has(key)) {
      throw new Error("SOURCE_FRESHNESS_DERIVATION_MISMATCH: purge report duplicate snapshot");
    }
    evidence.set(key, { sourceId, snapshotId, rawSha256, purgedAt });
  }
  return evidence;
}

function selectSnapshots(snapshots, selectedIds) {
  const ids = selectedIds.map((id, index) => requiredString(id, `buildSpec.sourceSnapshotIds[${index}]`));
  if (new Set(ids).size !== ids.length) {
    throw new Error("SOURCE_FRESHNESS_DERIVATION_MISMATCH: source snapshot IDs");
  }
  const byId = new Map();
  for (const snapshot of snapshots) {
    const snapshotId = requiredString(snapshot?.snapshotId, "snapshotId");
    if (byId.has(snapshotId)) {
      throw new Error("SOURCE_FRESHNESS_DERIVATION_MISMATCH: source snapshot IDs");
    }
    byId.set(snapshotId, snapshot);
  }
  if (ids.some((id) => !byId.has(id))) {
    throw new Error("SOURCE_FRESHNESS_DERIVATION_MISMATCH: source snapshot IDs");
  }
  const selectedIdsSet = new Set(ids);
  return snapshots.filter((snapshot) => selectedIdsSet.has(snapshot.snapshotId));
}

function validateRequiredProductionSources(snapshots, inventory) {
  const counts = new Map();
  for (const snapshot of snapshots) {
    counts.set(snapshot.sourceId, (counts.get(snapshot.sourceId) ?? 0) + 1);
  }
  for (const source of inventory?.sources ?? []) {
    if (source.requiredForProductionPack === true && counts.get(source.id) !== 1) {
      throw new Error(`SOURCE_FRESHNESS_POLICY_MISSING: required production source ${source.id}`);
    }
  }
}

function bindGovernanceProvenance(snapshots, buildSnapshots) {
  const buildById = new Map(buildSnapshots.map((snapshot) => [snapshot?.snapshotId, snapshot]));
  return snapshots.map((snapshot, index) => {
    const buildSnapshot = buildById.get(snapshot.snapshotId);
    const hasPolicyBinding = snapshot.governancePolicyVersion != null
      || snapshot.governancePolicySha256 != null;
    if (hasPolicyBinding) {
      const evidence = canonicalPolicyProvenance([snapshot], `snapshots[${index}]`, true);
      const build = canonicalPolicyProvenance([buildSnapshot], `buildSpec.sourceSnapshots[${index}]`, true);
      if (JSON.stringify(evidence) !== JSON.stringify(build)) {
        throw new Error("SOURCE_FRESHNESS_DERIVATION_MISMATCH: source snapshot provenance");
      }
      return snapshot;
    }
    if (approvedLegacyGovernanceSnapshotHashes.get(snapshot.snapshotId)
      !== sha256(JSON.stringify(snapshot))) {
      throw new Error("SOURCE_FRESHNESS_POLICY_MISSING: governance policy binding");
    }
    const policyProvenance = canonicalPolicyProvenance(
      [buildSnapshot],
      `buildSpec.sourceSnapshots[${index}]`,
      true,
    )[0];
    return { ...snapshot, ...policyProvenance };
  });
}

function canonicalBuildProvenance(snapshots, label) {
  if (!Array.isArray(snapshots) || snapshots.length === 0) {
    throw new Error(`SOURCE_FRESHNESS_POLICY_MISSING: ${label}`);
  }
  return snapshots.map((snapshot, index) => {
    if (!snapshot || typeof snapshot !== "object" || Array.isArray(snapshot)) {
      throw new Error(`SOURCE_FRESHNESS_POLICY_MISSING: ${label}[${index}]`);
    }
    const canonical = Object.fromEntries(buildProvenanceStringFields.map((field) => [
      field,
      requiredString(snapshot[field], `${label}[${index}].${field}`),
    ]));
    for (const field of buildProvenanceBooleanFields) {
      if (typeof snapshot[field] !== "boolean") {
        throw new Error(`SOURCE_FRESHNESS_POLICY_MISSING: ${label}[${index}].${field}`);
      }
      canonical[field] = snapshot[field];
    }
    return canonical;
  }).sort((left, right) => left.snapshotId.localeCompare(right.snapshotId));
}

function canonicalPolicyProvenance(snapshots, label, includeGovernance) {
  if (!Array.isArray(snapshots) || snapshots.length === 0) {
    throw new Error(`SOURCE_FRESHNESS_POLICY_MISSING: ${label}`);
  }
  const fields = includeGovernance
    ? policyBoundProvenanceStringFields
    : policyBoundProvenanceStringFields.filter((field) => !field.startsWith("governancePolicy"));
  return snapshots.map((snapshot, index) => ({
    snapshotId: requiredString(snapshot?.snapshotId, `${label}[${index}].snapshotId`),
    provenance: Object.fromEntries(fields.map((field) => [
      field,
      requiredString(snapshot?.[field], `${label}[${index}].${field}`),
    ])),
  }))
    .sort((left, right) => left.snapshotId.localeCompare(right.snapshotId))
    .map((entry) => entry.provenance);
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main(process.argv.slice(2)).catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
