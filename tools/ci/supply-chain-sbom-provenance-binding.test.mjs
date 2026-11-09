import assert from "node:assert/strict";
import test from "node:test";

import {
  PRODUCTION_ARTIFACT_SUPPLY_CHAIN_CATALOG,
  SupplyChainBindingError,
  bindSystemReleaseSupplyChainEvidence,
  validateSupplyChainCatalog,
} from "./supply-chain-sbom-provenance-binding.mjs";

const RC_ID = "rc-2026-11-09-01";
const EVALUATED_AT = "2026-11-09T12:00:00.000Z";

function hex64(char) {
  return char.repeat(64);
}

function hex40(char) {
  return char.repeat(40);
}

function buildValidEvidenceRecords(rcId = RC_ID) {
  const specs = [
    {
      artifactId: "hub-contract-bundle",
      producerRepository: "AquilaXk/easysubway",
      builderWorkflow: ".github/workflows/ci.yml",
      seed: "1",
    },
    {
      artifactId: "datapack-bundle",
      producerRepository: "AquilaXk/easysubway-data",
      builderWorkflow: ".github/workflows/datapack-release.yml",
      seed: "2",
    },
    {
      artifactId: "server-route-bundle",
      producerRepository: "AquilaXk/easysubway-data",
      builderWorkflow: ".github/workflows/datapack-release.yml",
      seed: "3",
    },
    {
      artifactId: "map-catalog-bundle",
      producerRepository: "AquilaXk/easysubway-data",
      builderWorkflow: ".github/workflows/datapack-release.yml",
      seed: "4",
    },
    {
      artifactId: "backend-oci-image",
      producerRepository: "AquilaXk/easysubway-backend",
      builderWorkflow: ".github/workflows/release-backend-image.yml",
      seed: "5",
    },
    {
      artifactId: "mobile-android-aab",
      producerRepository: "AquilaXk/easysubway-mobile",
      builderWorkflow: ".github/workflows/release-mobile-aab.yml",
      seed: "6",
    },
    {
      artifactId: "platform-deployment-receipt",
      producerRepository: "AquilaXk/easysubway-platform",
      builderWorkflow: ".github/workflows/deploy-k3s-production.yml",
      seed: "7",
    },
  ];

  return specs.map((spec) => {
    const artifactSha256 = hex64(spec.seed);
    const sourceCommitSha = hex40(spec.seed);
    return {
      artifactId: spec.artifactId,
      releaseCandidateId: rcId,
      artifactSha256,
      producerRepository: spec.producerRepository,
      sourceCommitSha,
      sbomFormat: "CycloneDX-1.6",
      sbomSha256: hex64("a"),
      sbomSubjectSha256: artifactSha256,
      provenanceAttestation: {
        predicateType: "https://slsa.dev/provenance/v1",
        subjectSha256: artifactSha256,
        sourceRepository: spec.producerRepository,
        sourceCommitSha,
        builderWorkflow: spec.builderWorkflow,
        attestationSha256: hex64("b"),
      },
      vulnerabilityReport: {
        scanner: "trivy",
        reportSha256: hex64("c"),
        findings: [],
      },
      vexStatements: [],
      licenseNoticeSha256: hex64("d"),
      licensePolicyStatus: "APPROVED",
      observedLicenses: ["MIT", "Apache-2.0"],
    };
  });
}

test("PRODUCTION_ARTIFACT_SUPPLY_CHAIN_CATALOG covers all 5 repositories and 7 canonical production artifacts", () => {
  const validation = validateSupplyChainCatalog(PRODUCTION_ARTIFACT_SUPPLY_CHAIN_CATALOG);
  assert.equal(validation.valid, true);
  assert.equal(PRODUCTION_ARTIFACT_SUPPLY_CHAIN_CATALOG.repositories.length, 5);
  assert.equal(PRODUCTION_ARTIFACT_SUPPLY_CHAIN_CATALOG.artifacts.length, 7);

  const artifactIds = PRODUCTION_ARTIFACT_SUPPLY_CHAIN_CATALOG.artifacts.map((entry) => entry.artifactId);
  assert.deepEqual(artifactIds, [
    "hub-contract-bundle",
    "datapack-bundle",
    "server-route-bundle",
    "map-catalog-bundle",
    "backend-oci-image",
    "mobile-android-aab",
    "platform-deployment-receipt",
  ]);
});

test("bindSystemReleaseSupplyChainEvidence produces deterministic systemSupplyChainFragment when all 7 artifacts bind 1:1", () => {
  const records = buildValidEvidenceRecords();
  const fragmentA = bindSystemReleaseSupplyChainEvidence({
    releaseCandidateId: RC_ID,
    evaluatedAt: EVALUATED_AT,
    evidenceRecords: records,
  });
  const fragmentB = bindSystemReleaseSupplyChainEvidence({
    releaseCandidateId: RC_ID,
    evaluatedAt: EVALUATED_AT,
    evidenceRecords: [...records].reverse(),
  });

  assert.equal(fragmentA.schemaVersion, 1);
  assert.equal(fragmentA.releaseCandidateId, RC_ID);
  assert.equal(fragmentA.artifacts.length, 7);
  assert.match(fragmentA.fragmentSha256, /^[a-f0-9]{64}$/);
  assert.equal(fragmentA.fragmentSha256, fragmentB.fragmentSha256);
});

test("bindSystemReleaseSupplyChainEvidence rejects SBOM or SLSA provenance subject digest mismatch", () => {
  const sbomMismatchRecords = buildValidEvidenceRecords();
  sbomMismatchRecords[4] = {
    ...sbomMismatchRecords[4],
    sbomSubjectSha256: hex64("9"),
  };

  assert.throws(
    () =>
      bindSystemReleaseSupplyChainEvidence({
        releaseCandidateId: RC_ID,
        evaluatedAt: EVALUATED_AT,
        evidenceRecords: sbomMismatchRecords,
      }),
    (err) => err instanceof SupplyChainBindingError && err.code === "E_SUPPLY_CHAIN_SUBJECT_DIGEST_MISMATCH",
  );

  const provenanceMismatchRecords = buildValidEvidenceRecords();
  provenanceMismatchRecords[5] = {
    ...provenanceMismatchRecords[5],
    provenanceAttestation: {
      ...provenanceMismatchRecords[5].provenanceAttestation,
      subjectSha256: hex64("8"),
    },
  };

  assert.throws(
    () =>
      bindSystemReleaseSupplyChainEvidence({
        releaseCandidateId: RC_ID,
        evaluatedAt: EVALUATED_AT,
        evidenceRecords: provenanceMismatchRecords,
      }),
    (err) => err instanceof SupplyChainBindingError && err.code === "E_SUPPLY_CHAIN_SUBJECT_DIGEST_MISMATCH",
  );
});

test("bindSystemReleaseSupplyChainEvidence rejects cross-RC mixing, wrong producer repo, missing artifact, or duplicate conflicting bytes", () => {
  // Cross-RC mixing
  const crossRcRecords = buildValidEvidenceRecords();
  crossRcRecords[1] = {
    ...crossRcRecords[1],
    releaseCandidateId: "rc-2026-11-08-99",
  };
  assert.throws(
    () =>
      bindSystemReleaseSupplyChainEvidence({
        releaseCandidateId: RC_ID,
        evaluatedAt: EVALUATED_AT,
        evidenceRecords: crossRcRecords,
      }),
    (err) => err instanceof SupplyChainBindingError && err.code === "E_SUPPLY_CHAIN_CROSS_RC_MIX",
  );

  // Wrong producer repository
  const wrongProducerRecords = buildValidEvidenceRecords();
  wrongProducerRecords[2] = {
    ...wrongProducerRecords[2],
    producerRepository: "AquilaXk/easysubway-backend",
    provenanceAttestation: {
      ...wrongProducerRecords[2].provenanceAttestation,
      sourceRepository: "AquilaXk/easysubway-backend",
    },
  };
  assert.throws(
    () =>
      bindSystemReleaseSupplyChainEvidence({
        releaseCandidateId: RC_ID,
        evaluatedAt: EVALUATED_AT,
        evidenceRecords: wrongProducerRecords,
      }),
    (err) => err instanceof SupplyChainBindingError && err.code === "E_SUPPLY_CHAIN_PRODUCER_MISMATCH",
  );

  // Missing required artifact
  const missingRecords = buildValidEvidenceRecords().slice(0, 6);
  assert.throws(
    () =>
      bindSystemReleaseSupplyChainEvidence({
        releaseCandidateId: RC_ID,
        evaluatedAt: EVALUATED_AT,
        evidenceRecords: missingRecords,
      }),
    (err) => err instanceof SupplyChainBindingError && err.code === "E_SUPPLY_CHAIN_MISSING_ARTIFACT",
  );

  // Duplicate artifact ID
  const duplicateRecords = [...buildValidEvidenceRecords(), buildValidEvidenceRecords()[0]];
  assert.throws(
    () =>
      bindSystemReleaseSupplyChainEvidence({
        releaseCandidateId: RC_ID,
        evaluatedAt: EVALUATED_AT,
        evidenceRecords: duplicateRecords,
      }),
    (err) => err instanceof SupplyChainBindingError && err.code === "E_SUPPLY_CHAIN_DUPLICATE_ARTIFACT",
  );
});

test("bindSystemReleaseSupplyChainEvidence enforces Fail-Closed VEX rules for CRITICAL and HIGH vulnerabilities", () => {
  // Unresolved HIGH vulnerability without VEX -> E_SUPPLY_CHAIN_VULNERABILITY_UNRESOLVED
  const unresolvedRecords = buildValidEvidenceRecords();
  unresolvedRecords[4] = {
    ...unresolvedRecords[4],
    vulnerabilityReport: {
      scanner: "trivy",
      reportSha256: hex64("c"),
      findings: [
        {
          vulnerabilityId: "CVE-2026-10001",
          severity: "HIGH",
          packageName: "org.example:codec",
        },
      ],
    },
    vexStatements: [],
  };

  assert.throws(
    () =>
      bindSystemReleaseSupplyChainEvidence({
        releaseCandidateId: RC_ID,
        evaluatedAt: EVALUATED_AT,
        evidenceRecords: unresolvedRecords,
      }),
    (err) => err instanceof SupplyChainBindingError && err.code === "E_SUPPLY_CHAIN_VULNERABILITY_UNRESOLVED",
  );

  // Expired VEX statement -> E_SUPPLY_CHAIN_VULNERABILITY_UNRESOLVED
  const expiredVexRecords = buildValidEvidenceRecords();
  expiredVexRecords[4] = {
    ... unresolvedRecords[4],
    vexStatements: [
      {
        vulnerabilityId: "CVE-2026-10001",
        targetArtifactSha256: expiredVexRecords[4].artifactSha256,
        status: "not_affected",
        justification: "vulnerable_code_not_in_execute_path",
        boundedReachability: "Unused XML parser path excluded by Graal/Spring config",
        ownerIssue: "AquilaXk/easysubway-backend#142",
        reviewExpiresAt: "2026-11-09T11:59:59.000Z",
      },
    ],
  };

  assert.throws(
    () =>
      bindSystemReleaseSupplyChainEvidence({
        releaseCandidateId: RC_ID,
        evaluatedAt: EVALUATED_AT,
        evidenceRecords: expiredVexRecords,
      }),
    (err) => err instanceof SupplyChainBindingError && err.code === "E_SUPPLY_CHAIN_VULNERABILITY_UNRESOLVED",
  );

  // Valid, non-expired not_affected VEX statement with justification and ownerIssue -> passes
  const validVexRecords = buildValidEvidenceRecords();
  validVexRecords[4] = {
    ...unresolvedRecords[4],
    vexStatements: [
      {
        vulnerabilityId: "CVE-2026-10001",
        targetArtifactSha256: validVexRecords[4].artifactSha256,
        status: "not_affected",
        justification: "vulnerable_code_not_in_execute_path",
        boundedReachability: "Unused XML parser path excluded by Spring configuration",
        ownerIssue: "AquilaXk/easysubway-backend#142",
        reviewExpiresAt: "2026-12-09T12:00:00.000Z",
      },
    ],
  };

  const result = bindSystemReleaseSupplyChainEvidence({
    releaseCandidateId: RC_ID,
    evaluatedAt: EVALUATED_AT,
    evidenceRecords: validVexRecords,
  });
  assert.equal(result.unresolvedCriticalOrHighCount, 0);
  assert.equal(result.verifiedVexExemptionCount, 1);
});

test("bindSystemReleaseSupplyChainEvidence rejects copyleft/forbidden licenses and oversized vulnerability payloads", () => {
  const forbiddenLicenseRecords = buildValidEvidenceRecords();
  forbiddenLicenseRecords[5] = {
    ...forbiddenLicenseRecords[5],
    observedLicenses: ["MIT", "AGPL-3.0"],
  };

  assert.throws(
    () =>
      bindSystemReleaseSupplyChainEvidence({
        releaseCandidateId: RC_ID,
        evaluatedAt: EVALUATED_AT,
        evidenceRecords: forbiddenLicenseRecords,
      }),
    (err) => err instanceof SupplyChainBindingError && err.code === "E_SUPPLY_CHAIN_LICENSE_VIOLATION",
  );

  const oversizedFindingsRecords = buildValidEvidenceRecords();
  oversizedFindingsRecords[0] = {
    ...oversizedFindingsRecords[0],
    vulnerabilityReport: {
      scanner: "trivy",
      reportSha256: hex64("c"),
      findings: Array.from({ length: 600 }, (_, i) => ({
        vulnerabilityId: `CVE-2026-${i}`,
        severity: "LOW",
        packageName: "pkg",
      })),
    },
  };

  assert.throws(
    () =>
      bindSystemReleaseSupplyChainEvidence({
        releaseCandidateId: RC_ID,
        evaluatedAt: EVALUATED_AT,
        evidenceRecords: oversizedFindingsRecords,
      }),
    (err) => err instanceof SupplyChainBindingError && err.code === "E_SUPPLY_CHAIN_BUDGET_EXCEEDED",
  );
});
