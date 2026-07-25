import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

import { evaluateReleaseDecision } from "./decide-datapack-release.mjs";
import { releaseRequestBindingViolations } from "./verify-release-request-binding.mjs";

const hash = (value) => value.repeat(64);
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

function buildSpec() {
  return {
    schemaVersion: 1,
    artifactKind: "datapack-candidate-build-spec",
    candidateId: "candidate-2521",
    sourceSnapshotSetHash: hash("c"),
    approvedAliasLedgerHash: hash("d"),
  };
}

function releaseRequest(buildSpecSha256, overrides = {}) {
  return {
    schemaVersion: 1,
    artifactKind: "datapack-release-request",
    candidateId: "candidate-2521",
    scopeId: "capital_pilot_android_v1",
    buildSpecSha256,
    sourceSnapshotSetHash: hash("c"),
    approvedLedgerHash: hash("d"),
    requestedBy: "data-operator",
    approvedBy: "release-approver",
    approvalId: "release-request-2026-07-26-01",
    targetChannel: "production",
    ...overrides,
  };
}

function boundPair(overrides = {}) {
  const spec = buildSpec();
  const buildSpecSha256 = sha256(JSON.stringify(spec));
  return { buildSpec: spec, buildSpecSha256, releaseRequest: releaseRequest(buildSpecSha256, overrides) };
}

async function writePair(overrides = {}) {
  const dir = await mkdtemp(path.join(tmpdir(), "release-request-binding-"));
  const buildSpecPath = path.join(dir, "candidate-build-spec.json");
  const requestPath = path.join(dir, "release-request.json");
  const specBytes = JSON.stringify(buildSpec());
  await writeFile(buildSpecPath, specBytes);
  await writeFile(requestPath, JSON.stringify(releaseRequest(sha256(specBytes), overrides)));
  return { buildSpecPath, requestPath };
}

function runCli(buildSpecPath, requestPath) {
  return spawnSync(process.execPath, [
    "tools/datapack/verify-release-request-binding.mjs",
    "--build-spec", buildSpecPath,
    "--release-request", requestPath,
  ], { encoding: "utf8" });
}

test("현행 build spec에 결속된 release request는 위반이 없다", () => {
  assert.deepEqual(releaseRequestBindingViolations(boundPair()), []);
});

test("stale buildSpecSha256는 어긋난 필드를 지목하며 검출된다", () => {
  const pair = boundPair({ buildSpecSha256: hash("e") });
  const violations = releaseRequestBindingViolations(pair);

  assert.equal(violations.length, 1);
  assert.match(violations[0], /buildSpecSha256가 build spec과 어긋났다/);
  assert.match(violations[0], new RegExp(pair.buildSpecSha256));
});

test("결속 위반은 release 판정의 approvalValid=false와 항상 함께 발생한다", () => {
  const drifts = [
    { buildSpecSha256: hash("e") },
    { candidateId: "candidate-other" },
    { sourceSnapshotSetHash: hash("f") },
    { approvedLedgerHash: hash("f") },
    { targetChannel: "staging" },
    { approvalId: "" },
    { approvedBy: "data-operator" },
  ];
  for (const drift of drifts) {
    const pair = boundPair(drift);
    assert.ok(releaseRequestBindingViolations(pair).length > 0, `${JSON.stringify(drift)} 위반 미검출`);
    const decision = evaluateReleaseDecision({
      candidateManifest: manifest(11),
      currentManifest: manifest(10),
      candidateManifestSha256: hash("1"),
      currentManifestSha256: hash("2"),
      buildSpec: pair.buildSpec,
      buildSpecSha256: pair.buildSpecSha256,
      releaseRequest: pair.releaseRequest,
      strictValidationPassed: true,
      publishAttempted: false,
      remoteValidationPassed: false,
      evaluationAt: "2026-07-26T00:00:00.000Z",
    });
    assert.equal(decision.approvalValid, false, `${JSON.stringify(drift)} approvalValid 불일치`);
    assert.ok(decision.reasonCodes.includes("MATERIAL_CHANGE_UNAPPROVED"));
  }
});

test("CLI는 결속된 pair에서 PASS 요약을 내고 성공한다", async () => {
  const { buildSpecPath, requestPath } = await writePair();
  const result = runCli(buildSpecPath, requestPath);

  assert.equal(result.status, 0, result.stderr);
  const summary = JSON.parse(result.stdout);
  assert.equal(summary.status, "PASS");
  assert.equal(summary.candidateId, "candidate-2521");
  assert.equal(summary.buildSpecSha256, sha256(JSON.stringify(buildSpec())));
});

test("CLI는 결속 drift를 fail-closed로 종료한다", async () => {
  const { buildSpecPath, requestPath } = await writePair({ buildSpecSha256: hash("e") });
  const result = runCli(buildSpecPath, requestPath);

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /release request가 현행 build spec에 결속돼 있지 않다/);
  assert.match(result.stderr, /buildSpecSha256/);
  assert.equal(result.stdout, "");
});

test("CLI는 필수 인자 누락을 거부한다", () => {
  const result = spawnSync(process.execPath, [
    "tools/datapack/verify-release-request-binding.mjs",
    "--build-spec", "tools/datapack/release/candidate-build-spec.json",
  ], { encoding: "utf8" });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /--release-request is required/);
});

function manifest(releaseSequence) {
  return {
    manifestVersion: 2,
    channel: "production",
    releaseSequence,
    publishedAt: "2026-07-20T00:00:00.000Z",
    expiresAt: "2026-08-20T00:00:00.000Z",
    packs: [{
      id: "capital",
      version: String(releaseSequence),
      sha256: hash("a"),
      sqliteSha256: hash("b"),
      schemaVersion: "1",
    }],
  };
}
