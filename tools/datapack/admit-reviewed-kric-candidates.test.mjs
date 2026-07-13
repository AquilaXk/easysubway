import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { buildReviewedKricAdmission, REVIEWED_KRIC_CANDIDATE_IDS } from "./admit-reviewed-kric-candidates.mjs";

const root = new URL("../../", import.meta.url);

async function readJson(path) {
  return JSON.parse(await readFile(new URL(path, root), "utf8"));
}

test("KRIC live sample 8건은 admin review 후 provenance 전용 inventory source로 승격한다", async () => {
  const candidates = await readJson("tools/datapack/source-candidates.json");
  const inventory = await readJson("tools/datapack/source-inventory.json");
  const fixture = await readJson("tools/datapack/fixtures/catalog-fixture.json");
  const overrides = await readJson("tools/datapack/fixtures/admin-review-overrides.json");

  const result = buildReviewedKricAdmission({ candidates, inventory, fixture, overrides });

  assert.equal(REVIEWED_KRIC_CANDIDATE_IDS.length, 8);
  for (const candidateId of REVIEWED_KRIC_CANDIDATE_IDS) {
    const candidate = result.candidates.candidates.find(({ id }) => id === candidateId);
    const source = result.inventory.sources.find(({ id }) => id === candidateId);

    assert.ok(candidate, candidateId);
    assert.ok(source, candidateId);
    assert.equal(candidate.sampleEvidenceStatus, "validated_live_sample");
    assert.equal(candidate.admissionStatus, "admitted_to_production_inventory");
    assert.equal(candidate.productionInventoryReferenceId, candidateId);
    assert.equal(candidate.evidence.adminReview.decision, "APPROVED");
    assert.equal(candidate.evidence.adminReview.approvedBy, "AquilaXk");
    assert.equal(source.requiredForProductionPack, false);
    assert.equal(source.admissionEvidence.issue, 1397);
    assert.equal(source.admissionEvidence.sampleEvidenceHash, candidate.evidence.liveSampleEvidenceHash);
    assert.equal(source.admissionEvidence.rawSha256, candidate.evidence.liveSampleRawSha256);
    assert.equal(source.admissionEvidence.schemaFingerprint, candidate.evidence.liveSampleSchemaFingerprint);
    assert.equal(source.admissionEvidence.quotaEvidence.productionUseAllowed, false);
    assert.equal(source.admissionEvidence.quotaEvidence.defaultDailyLimit, "unlimited");
    assert.ok(Object.values(source.capabilities).every(({ productionUseAllowed }) => productionUseAllowed === false));
  }

  const standard = result.candidates.candidates.find(({ id }) => id === "kric-transfer-movement-standard");
  assert.equal(standard.admissionStatus, "evidence_recorded_admin_review_required");
  assert.equal(standard.sampleEvidenceStatus, "sample_url_documented_key_required");
  assert.equal(standard.automaticRouteGraphEdgeAllowed, false);
  assert.equal(standard.evidence.adminReview.decision, "REJECTED_NO_DATA");
  assert.equal(standard.evidence.adminReview.approvedBy, "AquilaXk");
  assert.match(standard.evidence.adminReview.reasonKo, /resultCode=03/);
  assert.match(standard.evidence.adminReview.reasonKo, /29252661883/);
  assert.equal(result.inventory.sources.some(({ id }) => id === standard.id), false);

  assert.deepEqual(
    buildReviewedKricAdmission({ candidates: result.candidates, inventory: result.inventory }),
    result,
    "동일한 admin review를 재적용해도 admission hash와 inventory가 바뀌면 안 된다",
  );
});
