#!/usr/bin/env node
import { createHash } from "node:crypto";
import { codepointCompare } from "../lib/codepoint-compare.mjs";
import { isMainModule } from "../lib/is-main-module.mjs";

const SHA256_HEX_REGEX = /^[a-f0-9]{64}$/;
const GIT_SHA40_HEX_REGEX = /^[a-f0-9]{40}$/;
const ISSUE_REF_REGEX =
  /^AquilaXk\/(easysubway|easysubway-data|easysubway-platform|easysubway-backend|easysubway-mobile)#[1-9][0-9]*$/;
const RELEASE_CANDIDATE_ID_REGEX = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;

const MAX_EVIDENCE_RECORDS = 32;
const MAX_VULNERABILITY_FINDINGS_PER_ARTIFACT = 512;
const MAX_VEX_STATEMENTS_PER_ARTIFACT = 512;
const MAX_OBSERVED_LICENSES_PER_ARTIFACT = 128;

const SLSA_PROVENANCE_PREDICATE_V1 = "https://slsa.dev/provenance/v1";

const ALLOWED_SBOM_FORMATS = Object.freeze(["CycloneDX-1.5", "CycloneDX-1.6", "SPDX-2.3"]);
const ALLOWED_SBOM_FORMAT_SET = new Set(ALLOWED_SBOM_FORMATS);

const FORBIDDEN_COPYLEFT_LICENSES = Object.freeze([
  "AGPL-3.0",
  "AGPL-3.0-only",
  "AGPL-3.0-or-later",
  "GPL-2.0",
  "GPL-2.0-only",
  "GPL-2.0-or-later",
  "GPL-3.0",
  "GPL-3.0-only",
  "GPL-3.0-or-later",
  "LGPL-2.1",
  "LGPL-3.0",
  "SSPL-1.0",
]);
const FORBIDDEN_LICENSE_SET = new Set(FORBIDDEN_COPYLEFT_LICENSES);

const ALLOWED_VEX_JUSTIFICATIONS = new Set([
  "component_not_present",
  "inline_mitigations_already_exist",
  "vulnerable_code_cannot_be_controlled_by_adversary",
  "vulnerable_code_not_in_execute_path",
  "vulnerable_code_not_present",
]);

export class SupplyChainBindingError extends Error {
  constructor(code, message, details = null) {
    super(`${code}: ${message}`);
    this.name = "SupplyChainBindingError";
    this.code = code;
    this.details = details;
  }
}

function deepFreeze(value) {
  if (!value || typeof value !== "object" || Object.isFrozen(value)) {
    return value;
  }
  for (const key of Object.keys(value)) {
    deepFreeze(value[key]);
  }
  return Object.freeze(value);
}

export const PRODUCTION_ARTIFACT_SUPPLY_CHAIN_CATALOG = deepFreeze({
  schemaVersion: 1,
  catalogId: "easysubway-5-repo-production-supply-chain-catalog",
  slsaPredicateType: SLSA_PROVENANCE_PREDICATE_V1,
  allowedSbomFormats: ALLOWED_SBOM_FORMATS,
  forbiddenLicenses: FORBIDDEN_COPYLEFT_LICENSES,
  repositories: [
    "AquilaXk/easysubway",
    "AquilaXk/easysubway-data",
    "AquilaXk/easysubway-backend",
    "AquilaXk/easysubway-mobile",
    "AquilaXk/easysubway-platform",
  ],
  artifacts: [
    {
      artifactId: "hub-contract-bundle",
      producerRepository: "AquilaXk/easysubway",
      requiredWorkflowPrefix: ".github/workflows/",
      requireSbom: true,
      requireSlsaProvenance: true,
      requireLicenseNoticeSha256: true,
    },
    {
      artifactId: "datapack-bundle",
      producerRepository: "AquilaXk/easysubway-data",
      requiredWorkflowPrefix: ".github/workflows/",
      requireSbom: true,
      requireSlsaProvenance: true,
      requireLicenseNoticeSha256: true,
    },
    {
      artifactId: "server-route-bundle",
      producerRepository: "AquilaXk/easysubway-data",
      requiredWorkflowPrefix: ".github/workflows/",
      requireSbom: true,
      requireSlsaProvenance: true,
      requireLicenseNoticeSha256: true,
    },
    {
      artifactId: "map-catalog-bundle",
      producerRepository: "AquilaXk/easysubway-data",
      requiredWorkflowPrefix: ".github/workflows/",
      requireSbom: true,
      requireSlsaProvenance: true,
      requireLicenseNoticeSha256: true,
    },
    {
      artifactId: "backend-oci-image",
      producerRepository: "AquilaXk/easysubway-backend",
      requiredWorkflowPrefix: ".github/workflows/",
      requireSbom: true,
      requireSlsaProvenance: true,
      requireLicenseNoticeSha256: true,
    },
    {
      artifactId: "mobile-android-aab",
      producerRepository: "AquilaXk/easysubway-mobile",
      requiredWorkflowPrefix: ".github/workflows/",
      requireSbom: true,
      requireSlsaProvenance: true,
      requireLicenseNoticeSha256: true,
    },
    {
      artifactId: "platform-deployment-receipt",
      producerRepository: "AquilaXk/easysubway-platform",
      requiredWorkflowPrefix: ".github/workflows/",
      requireSbom: true,
      requireSlsaProvenance: true,
      requireLicenseNoticeSha256: true,
    },
  ],
});

function canonicalJson(value) {
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(",")}]`;
  }
  if (value && typeof value === "object") {
    const keys = Object.keys(value).sort(codepointCompare);
    return `{${keys.map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function sha256Canonical(value) {
  return createHash("sha256").update(canonicalJson(value)).digest("hex");
}

function assertSha256(value, fieldName, errorCode = "E_SUPPLY_CHAIN_INVALID_DIGEST") {
  if (typeof value !== "string" || !SHA256_HEX_REGEX.test(value)) {
    throw new SupplyChainBindingError(
      errorCode,
      `${fieldName} must be a 64-character lowercase hex SHA-256 digest`,
    );
  }
}

export function validateSupplyChainCatalog(catalog = PRODUCTION_ARTIFACT_SUPPLY_CHAIN_CATALOG) {
  if (!catalog || typeof catalog !== "object" || Array.isArray(catalog)) {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_CATALOG_INVALID",
      "Supply chain catalog must be a non-null object",
    );
  }
  if (!Array.isArray(catalog.repositories) || catalog.repositories.length !== 5) {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_CATALOG_INVALID",
      "Catalog must define all 5 canonical repositories",
    );
  }
  if (!Array.isArray(catalog.artifacts) || catalog.artifacts.length !== 7) {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_CATALOG_INVALID",
      "Catalog must define all 7 canonical production artifacts",
    );
  }

  const repoSet = new Set(catalog.repositories);
  const coveredRepos = new Set();
  const seenArtifacts = new Set();

  for (const item of catalog.artifacts) {
    if (!item || typeof item.artifactId !== "string" || seenArtifacts.has(item.artifactId)) {
      throw new SupplyChainBindingError(
        "E_SUPPLY_CHAIN_CATALOG_INVALID",
        "Duplicate or invalid artifactId in supply chain catalog",
      );
    }
    if (!repoSet.has(item.producerRepository)) {
      throw new SupplyChainBindingError(
        "E_SUPPLY_CHAIN_CATALOG_INVALID",
        `Unknown producerRepository '${String(item.producerRepository)}'`,
      );
    }
    seenArtifacts.add(item.artifactId);
    coveredRepos.add(item.producerRepository);
  }

  if (coveredRepos.size !== repoSet.size) {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_CATALOG_INVALID",
      "Every repository in the 5-repo split must produce at least one governed artifact",
    );
  }

  return {
    valid: true,
    catalogSha256: sha256Canonical(catalog),
  };
}

function indexValidVexByVulnerabilityId(vexStatements, artifactSha256, evaluatedMs) {
  if (!Array.isArray(vexStatements)) {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_INVALID_INPUT",
      "vexStatements must be an array",
    );
  }
  if (vexStatements.length > MAX_VEX_STATEMENTS_PER_ARTIFACT) {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_BUDGET_EXCEEDED",
      `vexStatements exceeds maximum budget of ${MAX_VEX_STATEMENTS_PER_ARTIFACT}`,
    );
  }

  const validVexMap = new Map();
  for (const vex of vexStatements) {
    if (!vex || typeof vex !== "object" || typeof vex.vulnerabilityId !== "string" || vex.vulnerabilityId.length === 0) {
      throw new SupplyChainBindingError(
        "E_SUPPLY_CHAIN_VULNERABILITY_UNRESOLVED",
        "Malformed VEX statement entry",
      );
    }
    const expiresMs = Date.parse(vex.reviewExpiresAt ?? "");
    const isValidNotAffected =
      vex.status === "not_affected" &&
      vex.targetArtifactSha256 === artifactSha256 &&
      ALLOWED_VEX_JUSTIFICATIONS.has(vex.justification) &&
      typeof vex.boundedReachability === "string" &&
      vex.boundedReachability.trim().length > 0 &&
      typeof vex.ownerIssue === "string" &&
      ISSUE_REF_REGEX.test(vex.ownerIssue) &&
      !Number.isNaN(expiresMs) &&
      expiresMs > evaluatedMs;

    if (isValidNotAffected) {
      validVexMap.set(vex.vulnerabilityId, vex);
    }
  }
  return validVexMap;
}

function verifyVulnerabilitiesAndVex(record, evaluatedMs) {
  const report = record.vulnerabilityReport;
  if (!report || typeof report !== "object" || Array.isArray(report)) {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_INVALID_INPUT",
      `Missing vulnerabilityReport for ${record.artifactId}`,
    );
  }
  assertSha256(report.reportSha256, `${record.artifactId}.vulnerabilityReport.reportSha256`);

  const findings = report.findings;
  if (!Array.isArray(findings)) {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_INVALID_INPUT",
      `vulnerabilityReport.findings must be an array for ${record.artifactId}`,
    );
  }
  if (findings.length > MAX_VULNERABILITY_FINDINGS_PER_ARTIFACT) {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_BUDGET_EXCEEDED",
      `vulnerabilityReport.findings exceeds maximum budget of ${MAX_VULNERABILITY_FINDINGS_PER_ARTIFACT}`,
    );
  }

  const validVexMap = indexValidVexByVulnerabilityId(
    record.vexStatements ?? [],
    record.artifactSha256,
    evaluatedMs,
  );

  let exemptedCount = 0;
  for (const finding of findings) {
    if (!finding || typeof finding !== "object" || typeof finding.vulnerabilityId !== "string") {
      throw new SupplyChainBindingError(
        "E_SUPPLY_CHAIN_INVALID_INPUT",
        `Malformed vulnerability finding in ${record.artifactId}`,
      );
    }
    if (finding.severity === "CRITICAL" || finding.severity === "HIGH") {
      if (!validVexMap.has(finding.vulnerabilityId)) {
        throw new SupplyChainBindingError(
          "E_SUPPLY_CHAIN_VULNERABILITY_UNRESOLVED",
          `Unresolved ${finding.severity} vulnerability '${finding.vulnerabilityId}' on artifact '${record.artifactId}' without active valid VEX statement`,
        );
      }
      exemptedCount += 1;
    }
  }

  return exemptedCount;
}

function verifyArtifactRecord(record, catalogEntry, releaseCandidateId, evaluatedMs) {
  if (record.releaseCandidateId !== releaseCandidateId) {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_CROSS_RC_MIX",
      `Artifact '${record.artifactId}' belongs to RC '${String(record.releaseCandidateId)}', expected '${releaseCandidateId}'`,
    );
  }

  if (record.producerRepository !== catalogEntry.producerRepository) {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_PRODUCER_MISMATCH",
      `Artifact '${record.artifactId}' producer '${String(record.producerRepository)}' does not match canonical producer '${catalogEntry.producerRepository}'`,
    );
  }

  if (typeof record.sourceCommitSha !== "string" || !GIT_SHA40_HEX_REGEX.test(record.sourceCommitSha)) {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_PROVENANCE_INVALID",
      `Artifact '${record.artifactId}' has invalid 40-hex sourceCommitSha`,
    );
  }

  assertSha256(record.artifactSha256, `${record.artifactId}.artifactSha256`);
  assertSha256(record.sbomSha256, `${record.artifactId}.sbomSha256`);
  assertSha256(
    record.sbomSubjectSha256,
    `${record.artifactId}.sbomSubjectSha256`,
    "E_SUPPLY_CHAIN_SUBJECT_DIGEST_MISMATCH",
  );

  if (!ALLOWED_SBOM_FORMAT_SET.has(record.sbomFormat)) {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_SBOM_FORMAT_INVALID",
      `Unsupported SBOM format '${String(record.sbomFormat)}' for '${record.artifactId}'`,
    );
  }

  if (record.sbomSubjectSha256 !== record.artifactSha256) {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_SUBJECT_DIGEST_MISMATCH",
      `SBOM subject digest mismatch for '${record.artifactId}'`,
    );
  }

  const prov = record.provenanceAttestation;
  if (!prov || typeof prov !== "object" || Array.isArray(prov)) {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_PROVENANCE_INVALID",
      `Missing provenanceAttestation for '${record.artifactId}'`,
    );
  }

  assertSha256(
    prov.subjectSha256,
    `${record.artifactId}.provenanceAttestation.subjectSha256`,
    "E_SUPPLY_CHAIN_SUBJECT_DIGEST_MISMATCH",
  );
  assertSha256(prov.attestationSha256, `${record.artifactId}.provenanceAttestation.attestationSha256`);

  if (prov.subjectSha256 !== record.artifactSha256) {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_SUBJECT_DIGEST_MISMATCH",
      `SLSA provenance subject digest mismatch for '${record.artifactId}'`,
    );
  }

  if (
    prov.predicateType !== SLSA_PROVENANCE_PREDICATE_V1 ||
    prov.sourceRepository !== catalogEntry.producerRepository ||
    prov.sourceCommitSha !== record.sourceCommitSha ||
    typeof prov.builderWorkflow !== "string" ||
    !prov.builderWorkflow.startsWith(catalogEntry.requiredWorkflowPrefix)
  ) {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_PROVENANCE_INVALID",
      `SLSA provenance attestation binding failed for '${record.artifactId}'`,
    );
  }

  assertSha256(
    record.licenseNoticeSha256,
    `${record.artifactId}.licenseNoticeSha256`,
    "E_SUPPLY_CHAIN_LICENSE_VIOLATION",
  );
  if (record.licensePolicyStatus !== "APPROVED") {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_LICENSE_VIOLATION",
      `Artifact '${record.artifactId}' licensePolicyStatus must be APPROVED`,
    );
  }

  const observedLicenses = record.observedLicenses ?? [];
  if (!Array.isArray(observedLicenses) || observedLicenses.length > MAX_OBSERVED_LICENSES_PER_ARTIFACT) {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_BUDGET_EXCEEDED",
      `Invalid or oversized observedLicenses on '${record.artifactId}'`,
    );
  }
  for (const licenseId of observedLicenses) {
    if (typeof licenseId !== "string" || FORBIDDEN_LICENSE_SET.has(licenseId)) {
      throw new SupplyChainBindingError(
        "E_SUPPLY_CHAIN_LICENSE_VIOLATION",
        `Forbidden license '${String(licenseId)}' detected in '${record.artifactId}'`,
      );
    }
  }

  const exemptedCount = verifyVulnerabilitiesAndVex(record, evaluatedMs);

  return {
    boundArtifact: {
      artifactId: record.artifactId,
      producerRepository: record.producerRepository,
      sourceCommitSha: record.sourceCommitSha,
      artifactSha256: record.artifactSha256,
      sbomFormat: record.sbomFormat,
      sbomSha256: record.sbomSha256,
      provenanceAttestationSha256: prov.attestationSha256,
      vulnerabilityReportSha256: record.vulnerabilityReport.reportSha256,
      licenseNoticeSha256: record.licenseNoticeSha256,
      verifiedVexExemptionCount: exemptedCount,
    },
    exemptedCount,
  };
}

export function bindSystemReleaseSupplyChainEvidence(
  { releaseCandidateId, evaluatedAt, evidenceRecords },
  catalog = PRODUCTION_ARTIFACT_SUPPLY_CHAIN_CATALOG,
) {
  if (
    typeof releaseCandidateId !== "string" ||
    !RELEASE_CANDIDATE_ID_REGEX.test(releaseCandidateId)
  ) {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_INVALID_INPUT",
      "releaseCandidateId must be a valid non-empty identifier",
    );
  }

  const evaluatedMs = Date.parse(evaluatedAt ?? "");
  if (Number.isNaN(evaluatedMs)) {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_INVALID_INPUT",
      "evaluatedAt must be a valid ISO-8601 timestamp",
    );
  }

  if (!Array.isArray(evidenceRecords)) {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_INVALID_INPUT",
      "evidenceRecords must be an array",
    );
  }

  if (evidenceRecords.length > MAX_EVIDENCE_RECORDS) {
    throw new SupplyChainBindingError(
      "E_SUPPLY_CHAIN_BUDGET_EXCEEDED",
      `evidenceRecords exceeds maximum budget of ${MAX_EVIDENCE_RECORDS}`,
    );
  }

  const catalogByArtifactId = new Map(
    catalog.artifacts.map((entry) => [entry.artifactId, entry]),
  );

  const seenArtifactIds = new Set();
  const boundByArtifactId = new Map();
  let totalExemptedCount = 0;

  for (const record of evidenceRecords) {
    if (!record || typeof record !== "object" || typeof record.artifactId !== "string") {
      throw new SupplyChainBindingError(
        "E_SUPPLY_CHAIN_INVALID_INPUT",
        "Each evidence record must be an object with a string artifactId",
      );
    }

    const catalogEntry = catalogByArtifactId.get(record.artifactId);
    if (!catalogEntry) {
      throw new SupplyChainBindingError(
        "E_SUPPLY_CHAIN_UNKNOWN_ARTIFACT",
        `Unknown production artifactId '${record.artifactId}'`,
      );
    }

    if (seenArtifactIds.has(record.artifactId)) {
      throw new SupplyChainBindingError(
        "E_SUPPLY_CHAIN_DUPLICATE_ARTIFACT",
        `Duplicate supply-chain evidence record for '${record.artifactId}'`,
      );
    }
    seenArtifactIds.add(record.artifactId);

    const { boundArtifact, exemptedCount } = verifyArtifactRecord(
      record,
      catalogEntry,
      releaseCandidateId,
      evaluatedMs,
    );
    boundByArtifactId.set(record.artifactId, boundArtifact);
    totalExemptedCount += exemptedCount;
  }

  for (const requiredArtifactId of catalogByArtifactId.keys()) {
    if (!boundByArtifactId.has(requiredArtifactId)) {
      throw new SupplyChainBindingError(
        "E_SUPPLY_CHAIN_MISSING_ARTIFACT",
        `Missing required production artifact supply-chain evidence: '${requiredArtifactId}'`,
      );
    }
  }

  const orderedArtifacts = catalog.artifacts
    .map((entry) => boundByArtifactId.get(entry.artifactId))
    .sort((left, right) => codepointCompare(left.artifactId, right.artifactId));

  const fragmentPayload = {
    schemaVersion: 1,
    artifactKind: "system-release-supply-chain-fragment",
    releaseCandidateId,
    evaluatedAt,
    unresolvedCriticalOrHighCount: 0,
    verifiedVexExemptionCount: totalExemptedCount,
    artifacts: orderedArtifacts,
  };

  return {
    ...fragmentPayload,
    fragmentSha256: sha256Canonical(fragmentPayload),
  };
}

if (isMainModule(import.meta.url)) {
  const result = validateSupplyChainCatalog(PRODUCTION_ARTIFACT_SUPPLY_CHAIN_CATALOG);
  process.stdout.write(`supply-chain-sbom-provenance-binding: OK ${result.catalogSha256}\n`);
}
