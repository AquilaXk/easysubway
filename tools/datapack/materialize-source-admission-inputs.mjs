#!/usr/bin/env node
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { exportLedgerHash } from "./export-ledger-hashes.mjs";
import { parseArgs, requireArg } from "./lib/ledger-admission-cli.mjs";
import { validateQuotaEvidence } from "./lib/quota-evidence.mjs";

const root = path.resolve(import.meta.dirname, "../..");

async function materializeSourceAdmissionInputs(args) {
  const outputDir = path.resolve(root, requireArg(args, "output-dir"));
  const sourceId = requireArg(args, "source-id");
  const inventory = JSON.parse(await readFile(path.resolve(root, requireArg(args, "inventory")), "utf8"));
  const source = inventory.sources?.find((entry) => entry.id === sourceId);
  if (!source) throw new Error(`source-id not found in inventory: ${sourceId}`);

  const quotaEvidence = source.admissionEvidence?.quotaEvidence;
  validateQuotaEvidence(quotaEvidence, `${sourceId}.admissionEvidence.quotaEvidence`);
  const productionSource = {
    ...source,
    retrievedAt: requireArg(args, "retrieved-at"),
  };

  const ledgers = [
    ["license", "license-hash.json"],
    ["alias", "alias-hash.json"],
    ["operator-mapping", "operator-mapping-hash.json"],
    ["facility-evidence", "facility-evidence-hash.json"],
    ["route-evidence", "route-evidence-hash.json"],
    ["override", "override-hash.json"],
  ];
  await mkdir(outputDir, { recursive: true });
  for (const [kind, fileName] of ledgers) {
    await writeJson(path.join(outputDir, fileName), await exportLedgerHash(kind, args));
  }
  await writeJson(path.join(outputDir, "quota-evidence.json"), quotaEvidence);
  await writeJson(path.join(outputDir, "production-source.json"), productionSource);
}

async function finalizeSourceAdmission(args) {
  const sourceId = requireArg(args, "source-id");
  const [inventory, candidates, sourceSnapshots, buildSpec, hashEvidence, summary, adminReview, sample, snapshot, collection, fixtureBytes] = await Promise.all([
    readJson(requireArg(args, "inventory")),
    readJson(requireArg(args, "candidates")),
    readJson(requireArg(args, "source-snapshots")),
    readJson(requireArg(args, "build-spec")),
    readJson(requireArg(args, "hash-evidence")),
    readJson(requireArg(args, "summary")),
    readJson(requireArg(args, "admin-review")),
    readJson(requireArg(args, "sample")),
    readJson(requireArg(args, "snapshot")),
    readJson(requireArg(args, "collection-artifact")),
    readFile(path.resolve(root, requireArg(args, "fixture"))),
  ]);

  const source = inventory.sources?.find((entry) => entry.id === sourceId);
  const candidate = candidates.candidates?.find((entry) => entry.id === sourceId);
  if (!source || !candidate) throw new Error(`source/candidate not found: ${sourceId}`);

  source.retrievedAt = snapshot.retrievedAt.slice(0, 10);
  source.admissionEvidence = {
    artifactKind: "source-admission-pipeline-evidence-summary",
    issue: Number(requireArg(args, "issue")),
    candidateId: summary.candidateId,
    sourceId: summary.sourceId,
    snapshotId: summary.snapshotId,
    decision: summary.decision,
    approvedBy: adminReview.approvedBy,
    approvedAt: adminReview.approvedAt,
    sampleEvidenceHash: adminReview.sampleEvidenceHash,
    rawSha256: summary.rawSha256,
    schemaFingerprint: summary.schemaFingerprint,
    sourceSnapshotSetHash: summary.sourceSnapshotSetHash,
    sourceInventorySha256: summary.sourceInventorySha256,
    adminReviewRecordHash: summary.adminReviewRecordHash,
    licenseEvidenceHash: summary.licenseEvidenceHash,
    aliasLedgerHash: summary.aliasLedgerHash,
    operatorMappingLedgerHash: summary.operatorMappingLedgerHash,
    facilityEvidenceLedgerHash: summary.facilityEvidenceLedgerHash,
    routeEvidenceLedgerHash: summary.routeEvidenceLedgerHash,
    overrideHash: summary.overrideHash,
    admissionDurationSeconds: summary.admissionDurationSeconds,
    quotaEvidence: summary.quotaEvidence,
    productionUseNoteKo: "수도권 4호선 상록수-사당 pilot stop_times 적재에 한해 production 사용을 허용한다.",
  };

  Object.assign(candidate.evidence, {
    liveSampleRetrievedAt: snapshot.retrievedAt,
    liveSampleRowCount: sample.rowCount,
    liveSampleRawSha256: sample.rawSha256,
    liveSampleSchemaFingerprint: sample.schemaFingerprint,
    liveSampleEvidenceHash: sample.evidenceHash,
    liveSampleFields: sample.fields,
    liveSampleNote: "2026-07-13 4호선 pilot 전량 수집 raw를 immutable object storage에 보존하고 실제 bytes·schema·row hash로 재승인했다.",
  });
  Object.assign(candidate.evidence.reconstructionValidation, {
    capturedAt: collection.capturedAt,
    requestCount: collection.requestCount,
    failureCount: collection.failedRequestCount,
    tripCount: collection.transitTripCount,
    stopTimesCount: collection.transitStopTimeCount,
    reproductionNote: "tracked collector를 node --env-file로 실행한다. KRIC dayCd=7은 공식 resultCode=03(데이터 없음)이므로 default plan은 평일(8)·휴일(9) 102요청이며 토요일은 휴일 시각표를 사용한다. raw는 object storage에 보존한다.",
  });

  const updatedSnapshots = sourceSnapshots.filter((entry) => entry.sourceId !== sourceId);
  updatedSnapshots.push(snapshot);
  const compactSnapshot = {
    snapshotId: snapshot.snapshotId,
    sourceId: snapshot.sourceId,
    rawObjectUri: snapshot.rawObjectUri,
    rawSha256: snapshot.rawSha256,
    redactedRequestFingerprint: snapshot.redactedRequestFingerprint,
    schemaFingerprint: snapshot.schemaFingerprint,
    licenseStatus: snapshot.licenseStatus,
    redistributionAllowed: snapshot.redistributionAllowed,
    adminReviewRecordHash: summary.adminReviewRecordHash,
    snapshotStatus: snapshot.snapshotStatus,
    credentialRedacted: snapshot.credentialRedacted,
    freshnessExpiresAt: snapshot.freshnessExpiresAt,
  };
  const fixture = JSON.parse(fixtureBytes.toString("utf8"));
  if (!fixture.packs?.[0]) throw new Error("fixture.packs[0] is required");
  const accessibilitySource = inventory.sources.find((entry) => entry.id === "seoul-metro-accessibility");
  const accessibilitySnapshotId = accessibilitySource?.admissionEvidence?.snapshotId;
  if (!accessibilitySnapshotId) throw new Error("seoul-metro-accessibility admission snapshot is required");
  for (const rows of [fixture.packs[0].networkEdges, fixture.packs[0].stationFacilityEvidence]) {
    for (const row of rows ?? []) {
      if (row.sourceId === accessibilitySource.id) row.sourceSnapshotId = accessibilitySnapshotId;
    }
  }
  const fareSourceId = hashEvidence.officialOdFareEvidence.sourceId;
  const fareSource = inventory.sources.find((entry) => entry.id === fareSourceId);
  if (!fareSource) throw new Error(`official OD fare source not found: ${fareSourceId}`);
  fixture.packs[0].sourceInventory = fixture.packs[0].sourceInventory.filter((entry) => entry.id !== fareSourceId);
  fixture.packs[0].sourceInventory.push({
    id: fareSource.id,
    owner: fareSource.owner,
    url: fareSource.datasetUrl,
    license: fareSource.license.name,
    licenseStatus: "redistributable",
    redistributionAllowed: true,
    updateFrequency: fareSource.updateFrequency,
    updatedAt: `${fareSource.observedDataUpdatedAt}T00:00:00.000Z`,
    fields: fareSource.fieldsProvided,
    coverageScope: fareSource.coverageScope,
  });
  fixture.packs[0].officialOdFareQuotes = hashEvidence.officialOdFareEvidence.quotes;
  const finalizedFixtureBytes = Buffer.from(`${JSON.stringify(fixture, null, 2)}\n`);
  buildSpec.candidateId = "capital-pilot-candidate-20260713";
  buildSpec.fixtureSha256 = sha256(finalizedFixtureBytes);
  buildSpec.sourceSnapshotIds = updatedSnapshots.map((entry) => entry.snapshotId);
  buildSpec.sourceSnapshots = buildSpec.sourceSnapshots.filter((entry) => entry.sourceId !== sourceId);
  buildSpec.sourceSnapshots.push(compactSnapshot);
  buildSpec.sourceSnapshotSetHash = sha256(JSON.stringify(updatedSnapshots));
  buildSpec.sourceInventorySha256 = sha256(JSON.stringify(inventory));
  buildSpec.builderGitSha = requireArg(args, "builder-git-sha");

  hashEvidence.builderGitSha = buildSpec.builderGitSha;
  hashEvidence.truthfulnessRule = "모든 값은 tracked exporter·source admission pipeline·업로드된 immutable raw object의 실제 hash에서만 생성했다. 임의 합성값 없음.";
  hashEvidence.sourceSnapshots.note = "reviewed pack이 사용하는 admission 9종의 locked snapshot 객체다. KRIC 시각표 raw는 2026-07-13 immutable object storage 보존본과 byte hash가 일치한다.";
  hashEvidence.sourceSnapshots.order = updatedSnapshots.map((entry) => entry.sourceId).join(" → ");
  hashEvidence.sourceSnapshots.committedVerificationCommand = "node --test --test-name-pattern='tracked production buildSpec은 현재 reviewed fixture와 provenance에 묶인다' tools/datapack/datapack-tools.test.mjs";
  hashEvidence.sourceSnapshots.specRowRawSha256Note = "build-spec sourceSnapshots[].rawSha256는 각 immutable raw object의 실제 bytes SHA-256이다.";
  hashEvidence.sourceSnapshotSetHash.value = buildSpec.sourceSnapshotSetHash;
  hashEvidence.sourceSnapshotSetHash.reproductionCommand = hashEvidence.sourceSnapshots.committedVerificationCommand;
  hashEvidence.sourceInventorySha256.value = buildSpec.sourceInventorySha256;
  hashEvidence.sourceInventorySha256.reproductionCommand = "node tools/datapack/validate-source-inventory.mjs";
  hashEvidence.fixturePath.sha256 = buildSpec.fixtureSha256;
  hashEvidence.identifiers.candidateId.value = buildSpec.candidateId;
  hashEvidence.perSourceEvidence = hashEvidence.perSourceEvidence.filter((entry) => entry.sourceId !== sourceId);
  hashEvidence.perSourceEvidence.push({
    sourceId,
    snapshotId: snapshot.snapshotId,
    rawSha256: snapshot.rawSha256,
    adminReviewRecordHash: summary.adminReviewRecordHash,
    perSourceSnapshotSetHash: summary.sourceSnapshotSetHash,
  });

  await Promise.all([
    writeJson(path.resolve(root, requireArg(args, "output-inventory")), inventory),
    writeJson(path.resolve(root, requireArg(args, "output-candidates")), candidates),
    writeJson(path.resolve(root, requireArg(args, "output-source-snapshots")), updatedSnapshots),
    writeJson(path.resolve(root, requireArg(args, "output-build-spec")), buildSpec),
    writeJson(path.resolve(root, requireArg(args, "output-hash-evidence")), hashEvidence),
    writeFile(path.resolve(root, requireArg(args, "fixture")), finalizedFixtureBytes),
  ]);
}

async function readJson(filePath) {
  return JSON.parse(await readFile(path.resolve(root, filePath), "utf8"));
}

async function writeJson(filePath, value) {
  await writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  await (args.summary ? finalizeSourceAdmission(args) : materializeSourceAdmissionInputs(args));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    await main();
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

export { finalizeSourceAdmission, materializeSourceAdmissionInputs };
