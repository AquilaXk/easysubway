import assert from "node:assert/strict";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
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

test("현재 tracked 원본에 대해 실행하면 SATISFIED와 모순 0을 산출한다", () => {
  const evidence = buildPrivacyConsistencyEvidence({
    candidate: candidate(),
    repoRoot: REPO_ROOT,
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
  assert.equal(evidence.checks.inventoryFormConsistent, "SATISFIED");
  assert.equal(evidence.checks.inventoryPolicyConsistent, "SATISFIED");
  for (const boundary of evidence.policyBoundaryConsistency.boundaries) {
    assert.equal(boundary.inventoryFactHolds, true, `${boundary.id} inventory fact`);
    assert.deepEqual(boundary.missingAnchors, [], `${boundary.id} anchors`);
  }
  assert.match(evidence.inputs.inventory.sha256, /^[0-9a-f]{64}$/);
  assert.match(evidence.inputs.privacyPolicy.sha256, /^[0-9a-f]{64}$/);
});

// 네 BLOCKED 회귀는 "fixtureRepoRoot로 특정 원본만 오염 → 실행 → status가
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
    name: "inventory가 경계를 더 이상 선언하지 않으면 정책 anchor가 있어도 BLOCKED한다",
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
