import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { exportLedgerHash } from "./export-ledger-hashes.mjs";
import {
  materializeSourceAdmissionInputs,
  resolveAdmissionSpecification,
} from "./materialize-source-admission-inputs.mjs";

test("source admission finalizer는 검토된 specification 값을 그대로 사용한다", () => {
  const specification = resolveAdmissionSpecification(
    { id: "source-next", admissionEvidence: { productionUseNoteKo: "승인된 production 범위" } },
    {
      id: "source-next",
      evidence: {
        liveSampleNote: "승인된 live sample 근거",
        reconstructionValidation: { reproductionNote: "승인된 재현 절차" },
      },
    },
    { candidateId: "capital-candidate-next" },
  );

  assert.deepEqual(specification, {
    productionUseNoteKo: "승인된 production 범위",
    liveSampleNote: "승인된 live sample 근거",
    reproductionNote: "승인된 재현 절차",
    buildCandidateId: "capital-candidate-next",
  });
});

test("source admission 입력은 tracked 원장에서만 materialize된다", async () => {
  const outputDir = await mkdtemp(path.join(tmpdir(), "source-admission-inputs-"));
  const args = {
    inventory: "tools/datapack/source-inventory.json",
    fixture: "tools/datapack/fixtures/catalog-fixture.json",
    overrides: "tools/datapack/fixtures/admin-review-overrides.json",
    "source-id": "kric-subway-timetable",
    "retrieved-at": "2026-07-13",
    "output-dir": outputDir,
  };

  try {
    await materializeSourceAdmissionInputs(args);

    const license = JSON.parse(await readFile(path.join(outputDir, "license-hash.json"), "utf8"));
    assert.deepEqual(license, await exportLedgerHash("license", args));

    const source = JSON.parse(await readFile(path.join(outputDir, "production-source.json"), "utf8"));
    assert.equal(source.id, "kric-subway-timetable");
    assert.equal(source.retrievedAt, "2026-07-13");
    assert.equal(source.admissionEvidence.artifactKind, "source-admission-pipeline-evidence-summary");

    const quota = JSON.parse(await readFile(path.join(outputDir, "quota-evidence.json"), "utf8"));
    assert.deepEqual(source.admissionEvidence.quotaEvidence, quota);
  } finally {
    await rm(outputDir, { recursive: true, force: true });
  }
});
