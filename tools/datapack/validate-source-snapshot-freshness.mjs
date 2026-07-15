#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { deriveFreshness } from "./freshness-policy.mjs";
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

export function validateSourceSnapshotFreshness({
  buildSpec,
  snapshots,
  policy,
  evaluationAt,
  governancePolicy = null,
  inventory = null,
  governancePolicySha256 = null,
}) {
  if (!Array.isArray(buildSpec?.sourceSnapshotIds) || buildSpec.sourceSnapshotIds.length === 0) {
    throw new Error("SOURCE_FRESHNESS_POLICY_MISSING: buildSpec.sourceSnapshotIds");
  }
  if (!Array.isArray(snapshots) || snapshots.length === 0) {
    throw new Error("SOURCE_FRESHNESS_POLICY_MISSING: source snapshots");
  }
  validateLineage(snapshots);
  const selectedSnapshots = selectSnapshots(snapshots, buildSpec.sourceSnapshotIds);
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
  const [snapshots, policy, governancePolicyText, inventory] = await Promise.all([
    readFile(resolvedEvidencePath, "utf8").then(JSON.parse),
    readFile(policyPath, "utf8").then(JSON.parse),
    governancePolicyPath ? readFile(governancePolicyPath, "utf8") : null,
    inventoryPath ? readFile(inventoryPath, "utf8").then(JSON.parse) : null,
  ]);
  const governancePolicy = governancePolicyText ? JSON.parse(governancePolicyText) : null;
  const result = validateSourceSnapshotFreshness({
    buildSpec,
    snapshots,
    policy,
    evaluationAt: args.get("evaluation-at") ?? new Date().toISOString(),
    governancePolicy,
    inventory,
    governancePolicySha256: governancePolicyText ? sha256(governancePolicyText) : null,
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
  const selected = ids.map((id) => byId.get(id));
  if (selected.some((snapshot) => snapshot == null)) {
    throw new Error("SOURCE_FRESHNESS_DERIVATION_MISMATCH: source snapshot IDs");
  }
  return selected;
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
  return snapshots.map((snapshot, index) => Object.fromEntries(fields.map((field) => [
    field,
    requiredString(snapshot?.[field], `${label}[${index}].${field}`),
  ])));
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
