import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { buildPrivacyConsistencyEvidence } from "./build-privacy-consistency-evidence.mjs";

const REPO_ROOT = path.resolve(import.meta.dirname, "../..");
const INVENTORY_FILE = "apps/mobile/release/store-privacy-inventory.json";
const PLAY_FORM_FILE = "apps/mobile/release/play-store-submission-content.json";
const PRIVACY_POLICY_FILE = "backend/src/main/resources/templates/legal/privacy.html";

const identity = {
  gitSha: "1".repeat(40),
  appVersionName: "1.0.4",
  versionCode: "10005",
};

function candidate(overrides = {}) {
  return { phase: "CANDIDATE", issue: 2056, releaseCandidateIdentity: identity, ...overrides };
}

// tracked 원본을 그대로 복사한 임시 repoRoot를 만들고, mutate 콜백으로 특정 파일만
// 오염시켜 fail-closed 회귀를 강제한다.
async function fixtureRepoRoot({ mutateInventory, mutatePlayForm, mutatePolicy } = {}) {
  const root = await mkdtemp(path.join(tmpdir(), "easysubway-privacy-evidence-"));
  const inventory = JSON.parse(readFileSync(path.join(REPO_ROOT, INVENTORY_FILE), "utf8"));
  const playForm = JSON.parse(readFileSync(path.join(REPO_ROOT, PLAY_FORM_FILE), "utf8"));
  let policy = readFileSync(path.join(REPO_ROOT, PRIVACY_POLICY_FILE), "utf8");
  if (mutateInventory) mutateInventory(inventory);
  if (mutatePlayForm) mutatePlayForm(playForm);
  if (mutatePolicy) policy = mutatePolicy(policy);
  await mkdir(path.join(root, "apps/mobile/release"), { recursive: true });
  await mkdir(path.join(root, "backend/src/main/resources/templates/legal"), { recursive: true });
  await writeFile(path.join(root, INVENTORY_FILE), `${JSON.stringify(inventory, null, 2)}\n`);
  await writeFile(path.join(root, PLAY_FORM_FILE), `${JSON.stringify(playForm, null, 2)}\n`);
  await writeFile(path.join(root, PRIVACY_POLICY_FILE), policy);
  return root;
}

// PR #2357 폴백 리뷰(review id 4732563185)의 aggregate flag 지적(모든 dataType이 4개
// boolean을 명시)을 만족하는 fixture. tracked play-store-submission-content.json은 이제
// 5개 dataType의 containsDeletionUnsupportedData를 명시적 boolean으로 보정해 이 요구를
// 충족하므로 이 helper는 tracked 원본에는 no-op이지만, 명시 flag가 빠진 폼에서도 happy
// path("데이터가 완전할 때 SATISFIED가 나온다")를 안정적으로 재현하기 위한 조건부
// 안전망으로 남긴다.
function fillExplicitAggregateFlags(playForm) {
  for (const entry of playForm.dataSafetyDeclarations.answerMatrix) {
    if (typeof entry.containsDeletionUnsupportedData !== "boolean") {
      entry.containsDeletionUnsupportedData = false;
    }
  }
}

async function sha256File(filePath) {
  return createHash("sha256").update(await readFile(filePath)).digest("hex");
}

test("aggregate flag가 모두 명시적 boolean이고 provenance가 검토 revision과 일치하면 SATISFIED와 모순 0을 산출한다", async () => {
  const repoRoot = await fixtureRepoRoot({ mutatePlayForm: fillExplicitAggregateFlags });
  const reviewedPlayFormSha256 = await sha256File(path.join(repoRoot, PLAY_FORM_FILE));

  const evidence = buildPrivacyConsistencyEvidence({
    candidate: candidate(),
    repoRoot,
    reviewedPlayFormSha256,
    generatedAt: "2026-07-20T00:00:00.000Z",
  });

  assert.equal(evidence.schemaVersion, 1);
  assert.equal(evidence.artifactKind, "store-privacy-consistency-evidence");
  assert.equal(evidence.sourceIssue, 1018);
  assert.equal(evidence.consumerIssue, 2056);
  assert.equal(evidence.status, "SATISFIED");
  assert.deepEqual(evidence.releaseCandidateIdentity, identity);
  assert.equal(evidence.answerMatrixConsistency.contradictions.length, 0);
  assert.equal(evidence.answerMatrixConsistency.uncoveredCollected.length, 0);
  assert.equal(evidence.policyBoundaryConsistency.consistent, true);
  assert.equal(evidence.playConsoleProvenanceConsistency.consistent, true);
  assert.equal(evidence.playConsoleProvenanceConsistency.matchesReviewedRevision, true);
  assert.equal(evidence.checks.inventoryFormConsistent, "SATISFIED");
  assert.equal(evidence.checks.inventoryPolicyConsistent, "SATISFIED");
  assert.equal(evidence.checks.playConsoleProvenanceCurrent, "SATISFIED");
  for (const boundary of evidence.policyBoundaryConsistency.boundaries) {
    assert.equal(boundary.inventoryFactHolds, true, `${boundary.id} inventory fact`);
    assert.deepEqual(boundary.missingAnchors, [], `${boundary.id} anchors`);
  }
  assert.match(evidence.inputs.inventory.sha256, /^[0-9a-f]{64}$/);
  assert.match(evidence.inputs.privacyPolicy.sha256, /^[0-9a-f]{64}$/);
});

// [Major, PR #2357 review 4732563185] 2026-07-18 커밋(7ca86806)이 Play Console 재제출·검토
// 당시의 play-store-submission-content.json이고, 그 sha256을 BOUND_EVIDENCE_REFERENCES에
// 고정했다. 이후 커밋(train_search_queries 추가 등)이 그 뒤로 파일을 바꿨으므로 현재
// tracked 파일은 검토된 revision과 다르다 — provenance는 여전히 STALE이어야 한다(위조 금지).
// 반면 그 review가 지적한 5개 dataType의 containsDeletionUnsupportedData 누락은 이제
// 폼에 명시적 boolean으로 보정돼 answerMatrix 집계 flag 모순은 0이다. 정책 anchor·inventory
// boundary fact도 무관하게 여전히 일치한다. 따라서 남은 결함은 provenance STALE 하나뿐이며
// 전체 status는 그 하나 때문에 여전히 BLOCKED다(reviewedFormSha256은 오너가 Play Console에서
// 보정본을 재제출·재검토한 뒤에만 후속 PR로 재고정한다).
test("현재 tracked 원본에 대해 실행하면 집계 flag 누락은 보정됐지만 폼 provenance stale은 fail-closed로 남는다", () => {
  const evidence = buildPrivacyConsistencyEvidence({
    candidate: candidate(),
    repoRoot: REPO_ROOT,
    generatedAt: "2026-07-20T00:00:00.000Z",
  });

  assert.equal(evidence.playConsoleProvenanceConsistency.consistent, false);
  assert.equal(evidence.playConsoleProvenanceConsistency.matchesReviewedRevision, false);
  assert.equal(
    evidence.playConsoleProvenanceConsistency.reviewedFormSha256,
    "67cc31f63c90e1a28fd5d1a0e372ffaa1d1dfe6f41f3a55d439ce3b376af1803",
  );
  assert.notEqual(
    evidence.playConsoleProvenanceConsistency.currentFormSha256,
    evidence.playConsoleProvenanceConsistency.reviewedFormSha256,
  );
  assert.equal(evidence.checks.playConsoleProvenanceCurrent, "STALE");

  // 5개 dataType 집계 flag 보정 후 answerMatrix 집계 flag 모순은 0이고 판정은 SATISFIED다.
  assert.equal(evidence.checks.inventoryFormConsistent, "SATISFIED");
  const missingFlagTypes = evidence.answerMatrixConsistency.contradictions
    .filter((item) => item.code === "aggregate_flag_missing_or_not_boolean")
    .map((item) => item.dataType)
    .sort();
  assert.deepEqual(missingFlagTypes, []);
  assert.equal(evidence.answerMatrixConsistency.consistent, true);

  assert.equal(evidence.checks.inventoryPolicyConsistent, "SATISFIED");
  assert.equal(evidence.policyBoundaryConsistency.consistent, true);

  // provenance STALE 하나만 남아 전체 status는 여전히 BLOCKED다.
  assert.equal(evidence.status, "BLOCKED_PRIVACY_CONSISTENCY");
});

// reviewedPlayFormSha256 override로 provenance 판정 로직 자체를 git 이력과 분리해
// 단위 검증한다: answerMatrix·policy는 fixture에서 완전히 일치하지만 검토 revision이
// 현재 폼과 다르면 그 사실 하나만으로 BLOCKED되는지 확인한다.
test("reviewedPlayFormSha256이 현재 폼 sha256과 다르면 다른 판정이 전부 통과해도 STALE로 BLOCKED한다", async () => {
  const repoRoot = await fixtureRepoRoot({ mutatePlayForm: fillExplicitAggregateFlags });

  const evidence = buildPrivacyConsistencyEvidence({
    candidate: candidate(),
    repoRoot,
    reviewedPlayFormSha256: "f".repeat(64),
  });

  assert.equal(evidence.answerMatrixConsistency.consistent, true);
  assert.equal(evidence.policyBoundaryConsistency.consistent, true);
  assert.equal(evidence.playConsoleProvenanceConsistency.consistent, false);
  assert.equal(evidence.checks.playConsoleProvenanceCurrent, "STALE");
  assert.equal(evidence.status, "BLOCKED_PRIVACY_CONSISTENCY");
});

// 아래 BLOCKED 회귀는 "fixtureRepoRoot로 특정 원본만 오염 → 실행 → status가
// BLOCKED_PRIVACY_CONSISTENCY" 구조가 모두 같다. 그 반복되는 실행·공통 assert 골격을
// 한 곳(아래 for 루프)에만 두고, 케이스마다 다른 mutate 콜백과 세부 assert만 테이블로 둔다.
const BLOCKED_CONSISTENCY_CASES = [
  {
    name: "폼 answerMatrix 집계가 inventory 값과 모순되면 fail-closed BLOCKED한다",
    mutatePlayForm(playForm) {
      const location = playForm.dataSafetyDeclarations.answerMatrix.find((item) => item.dataType === "Location");
      location.containsRequiredData = true; // inventory Location은 required 항목이 없다.
    },
    assertEvidence(evidence) {
      assert.equal(evidence.checks.inventoryFormConsistent, "FAILED");
      assert.ok(
        evidence.answerMatrixConsistency.contradictions.some(
          (item) => item.dataType === "Location" && item.code === "required_flag_mismatch",
        ),
      );
    },
  },
  {
    name: "inventory의 collected 항목이 폼 matrix에서 누락되면 coverage 모순으로 BLOCKED한다",
    mutatePlayForm(playForm) {
      const appActivity = playForm.dataSafetyDeclarations.answerMatrix.find((item) => item.dataType === "App activity");
      appActivity.inventoryDataIds = appActivity.inventoryDataIds.filter((id) => id !== "search_queries");
    },
    assertEvidence(evidence) {
      assert.ok(evidence.answerMatrixConsistency.uncoveredCollected.includes("search_queries"));
    },
  },
  {
    // [Minor, review 4732563185] aggregate flag 문자열("true")이 truthy 변환으로 우연히
    // 통과하지 않는지 확인한다. Boolean("true")===true이므로 예전 구현이면 이 mutation은
    // 오히려 "일치"로 오판했을 것이다.
    name: "aggregate flag가 boolean이 아닌 문자열이면 truthy 변환 없이 fail-closed BLOCKED한다",
    mutatePlayForm(playForm) {
      const location = playForm.dataSafetyDeclarations.answerMatrix.find((item) => item.dataType === "Location");
      location.containsCollectedData = "true";
    },
    assertEvidence(evidence) {
      assert.ok(
        evidence.answerMatrixConsistency.contradictions.some(
          (item) => item.dataType === "Location"
            && item.code === "aggregate_flag_missing_or_not_boolean"
            && item.detail.includes("containsCollectedData"),
        ),
      );
    },
  },
  {
    name: "정책 원본에서 경계 문구 anchor가 사라지면 fail-closed BLOCKED한다",
    mutatePolicy(policy) {
      return policy.replace("DB나 access log에는 저장하지 않습니다", "생략");
    },
    assertEvidence(evidence) {
      assert.equal(evidence.checks.inventoryPolicyConsistent, "FAILED");
      const gateway = evidence.policyBoundaryConsistency.boundaries.find(
        (item) => item.id === "gateway_shared_memory_non_persistence",
      );
      assert.equal(gateway.consistent, false);
      assert.ok(gateway.missingAnchors.includes("DB나 access log에는 저장하지 않습니다"));
    },
  },
  {
    // [Minor, review 4732563185] 같은 anchor 문구가 HTML 주석 안으로만 옮겨져도 원문
    // includes()는 여전히 true를 반환한다 — 렌더링되지 않는 주석은 anchor 검사에서
    // 제외돼야 한다.
    name: "정책 anchor 문구가 HTML 주석 안에만 남으면 렌더링되지 않은 것으로 보아 fail-closed BLOCKED한다",
    mutatePolicy(policy) {
      return policy.replace(
        "DB나 access log에는 저장하지 않습니다",
        "<!-- DB나 access log에는 저장하지 않습니다 -->",
      );
    },
    assertEvidence(evidence) {
      const gateway = evidence.policyBoundaryConsistency.boundaries.find(
        (item) => item.id === "gateway_shared_memory_non_persistence",
      );
      assert.equal(gateway.consistent, false);
      assert.ok(gateway.missingAnchors.includes("DB나 access log에는 저장하지 않습니다"));
    },
  },
  {
    name: "inventory가 raw/hash 경계를 더 이상 선언하지 않으면 정책 anchor가 있어도 BLOCKED한다",
    mutateInventory(inventory) {
      const integrity = inventory.dataTypes.find((item) => item.id === "route_v2_itx_integrity");
      integrity.backendNeverPersistedOrLogged = integrity.backendNeverPersistedOrLogged.filter(
        (field) => field !== "rawIntegrityToken",
      );
    },
    assertEvidence(evidence) {
      const boundary = evidence.policyBoundaryConsistency.boundaries.find(
        (item) => item.id === "route_v2_raw_hash_boundary",
      );
      assert.equal(boundary.inventoryFactHolds, false);
      assert.equal(boundary.consistent, false);
    },
  },
  {
    // [Minor, review 4732563185] raw 필드가 backendStoredFields에 실제로 추가되면(내부
    // 모순) backendNeverPersistedOrLogged에 두 raw 필드가 남아 있어도 boundary는 거짓이어야
    // 한다 — hash 필드 존재만으로 통과시키지 않는다.
    name: "backendStoredFields에 raw 필드가 추가되면 raw/hash 경계가 fail-closed BLOCKED한다",
    mutateInventory(inventory) {
      const integrity = inventory.dataTypes.find((item) => item.id === "route_v2_itx_integrity");
      integrity.backendStoredFields = [...integrity.backendStoredFields, "rawIntegrityToken"];
    },
    assertEvidence(evidence) {
      const boundary = evidence.policyBoundaryConsistency.boundaries.find(
        (item) => item.id === "route_v2_raw_hash_boundary",
      );
      assert.equal(boundary.inventoryFactHolds, false);
      assert.equal(boundary.consistent, false);
    },
  },
  {
    // [Minor, review 4732563185] integrityPayloadOrVerdict 비저장 선언이 사라지면
    // sharedOnward=false만으로는 Play Integrity boundary가 성립하지 않아야 한다.
    name: "route_v2_itx_integrity가 integrityPayloadOrVerdict 비저장을 더 이상 선언하지 않으면 Play Integrity 경계가 BLOCKED한다",
    mutateInventory(inventory) {
      const integrity = inventory.dataTypes.find((item) => item.id === "route_v2_itx_integrity");
      integrity.backendNeverPersistedOrLogged = integrity.backendNeverPersistedOrLogged.filter(
        (field) => field !== "integrityPayloadOrVerdict",
      );
    },
    assertEvidence(evidence) {
      const boundary = evidence.policyBoundaryConsistency.boundaries.find(
        (item) => item.id === "play_integrity_boundary",
      );
      assert.equal(boundary.inventoryFactHolds, false);
      assert.equal(boundary.consistent, false);
    },
  },
];

for (const testCase of BLOCKED_CONSISTENCY_CASES) {
  test(testCase.name, async () => {
    const repoRoot = await fixtureRepoRoot(testCase);
    const evidence = buildPrivacyConsistencyEvidence({ candidate: candidate(), repoRoot });

    assert.equal(evidence.status, "BLOCKED_PRIVACY_CONSISTENCY");
    testCase.assertEvidence(evidence);
  });
}

test("입력 원본이 없으면 fail-closed BLOCKED_PRIVACY_CONSISTENCY_INPUTS를 산출한다", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "easysubway-privacy-evidence-empty-"));
  const evidence = buildPrivacyConsistencyEvidence({ candidate: candidate(), repoRoot: root });

  assert.equal(evidence.status, "BLOCKED_PRIVACY_CONSISTENCY_INPUTS");
  assert.deepEqual(evidence.missingInputs, [INVENTORY_FILE, PLAY_FORM_FILE, PRIVACY_POLICY_FILE]);
  assert.equal(evidence.checks.inventoryFormConsistent, "BLOCKED");
  assert.equal(evidence.checks.playConsoleProvenanceCurrent, "BLOCKED");
});

test("CANDIDATE context가 아니면 거부한다", () => {
  assert.throws(
    () => buildPrivacyConsistencyEvidence({
      candidate: { phase: "FINAL", issue: 2056, releaseCandidateIdentity: identity },
      repoRoot: REPO_ROOT,
    }),
    /CANDIDATE context/,
  );
  assert.throws(
    () => buildPrivacyConsistencyEvidence({
      candidate: { phase: "CANDIDATE", issue: 1020, releaseCandidateIdentity: identity },
      repoRoot: REPO_ROOT,
    }),
    /CANDIDATE context/,
  );
});
