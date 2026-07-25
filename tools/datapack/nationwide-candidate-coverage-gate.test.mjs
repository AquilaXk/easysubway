// #2514 (#2510 B0) 전국 candidate pack 게이트 하네스 회귀.
//
// 검증 축:
//   1. tracked evidence가 현행 입력에서 바이트 단위로 재생성된다(오프라인·서명 키 없이).
//   2. 파일럿 scope가 line-scope 재기술 전 MISSING → 후 SUPPORTED로 전이한다.
//   3. spec의 line-scope 재기술과 tracked source-inventory가 어긋나면 하네스가 fail closed 한다.
//   4. production 게시 트랙 fixture는 candidate 조립에 영향받지 않는다.
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { promisify } from "node:util";

import { EVIDENCE_PATH, runNationwideCandidateCoverageGate } from "./run-nationwide-candidate-coverage-gate.mjs";

const execFileAsync = promisify(execFile);
const root = path.resolve(import.meta.dirname, "../..");
const TOOL_PATH = "tools/datapack/run-nationwide-candidate-coverage-gate.mjs";
const SPEC_PATH = "tools/datapack/nationwide-candidate-pack-spec.json";
const TARGETS_PATH = "tools/datapack/nationwide-coverage-targets.json";
const INVENTORY_PATH = "tools/datapack/source-inventory.json";
const APP_INVENTORY_PATH = "apps/mobile/assets/datapacks/source-inventory.json";
const RESOLUTION_PLAN_PATH =
  "tools/datapack/release/nationwide-public-api-coverage-search-plan-20260725.json";
const RESOLUTIONS_PATH =
  "tools/datapack/release/nationwide-public-api-coverage-resolutions-20260725.json";
const REVIEWED_PACK_PATH = "tools/datapack/release/capital-production-reviewed-pack.json";
const PILOT_REQUIREMENT_KEY = "capital:seoul-metro:seoul-4:route_map_positions";
const PILOT_SOURCE_ID = "seoulmetro-cyberstation-route-map";

const INPUT_PATHS = {
  spec: SPEC_PATH,
  targets: TARGETS_PATH,
  inventory: INVENTORY_PATH,
  resolutionPlan: RESOLUTION_PLAN_PATH,
  resolutions: RESOLUTIONS_PATH,
};

async function readJson(relativePath) {
  return JSON.parse(await readFile(path.join(root, relativePath), "utf8"));
}

async function sha256Of(relativePath) {
  return createHash("sha256").update(await readFile(path.join(root, relativePath))).digest("hex");
}

test("커밋된 candidate 게이트 evidence는 현행 입력에서 바이트 단위로 재생성된다", async () => {
  const workspace = await mkdtemp(path.join(tmpdir(), "nationwide-candidate-gate-"));
  try {
    const output = path.join(workspace, "evidence.json");
    await execFileAsync(process.execPath, [
      path.join(root, TOOL_PATH),
      "--spec", SPEC_PATH,
      "--targets", TARGETS_PATH,
      "--inventory", INVENTORY_PATH,
      "--resolution-plan", RESOLUTION_PLAN_PATH,
      "--resolutions", RESOLUTIONS_PATH,
      "--output", output,
    ], { cwd: root });

    const regenerated = await readFile(output, "utf8");
    const tracked = await readFile(path.join(root, EVIDENCE_PATH), "utf8");
    assert.equal(regenerated, tracked, "evidence는 재생성 결과와 바이트 단위로 같아야 한다");

    const evidence = JSON.parse(tracked);
    assert.equal(evidence.artifactKind, "nationwide-candidate-coverage-gate-evidence");
    assert.equal(evidence.issue, 2514);
    assert.deepEqual(evidence.parentIssues, [2510, 2138]);
    assert.equal(evidence.regeneration.evidencePath, EVIDENCE_PATH);
    assert.equal(
      evidence.regeneration.command,
      `node ${TOOL_PATH} --spec ${SPEC_PATH} --targets ${TARGETS_PATH} --inventory ${INVENTORY_PATH}`
        + ` --resolution-plan ${RESOLUTION_PLAN_PATH} --resolutions ${RESOLUTIONS_PATH}`
        + ` --output ${EVIDENCE_PATH}`,
    );

    // 기록된 입력 해시는 tracked 입력 파일의 실제 해시여야 한다(입력 drift 감지축).
    for (const [name, relativePath] of Object.entries(INPUT_PATHS)) {
      assert.equal(evidence.inputs[name].path, relativePath);
      assert.equal(evidence.inputs[name].sha256, await sha256Of(relativePath));
    }

    // 임시 RSA 키·SQLite 바이트·wall-clock 의존 집계는 기록 축이 아니다(결정성 계약).
    assert.equal(evidence.harness.signing.mode, "EPHEMERAL_RSA_2048");
    assert.equal(evidence.determinism.packPayloadIdenticalAcrossVariants, true);
    assert.equal(JSON.stringify(evidence).includes("manifestSha256\":\""), false);
  } finally {
    await rm(workspace, { recursive: true, force: true });
  }
});

test("파일럿 scope는 line-scope 재기술로 MISSING에서 SUPPORTED로 전이한다", async () => {
  const evidence = await readJson(EVIDENCE_PATH);

  // candidate는 root가 되는 단일 pack이어야 게이트가 단독 계약으로 판정한다.
  assert.equal(evidence.candidatePack.id, "nationwide-candidate");
  assert.equal(evidence.candidatePack.artifactKind, "production");
  assert.equal(evidence.candidatePack.inheritsFrom.path, REVIEWED_PACK_PATH);

  assert.deepEqual(evidence.variants.baseline.supportedRequirementKeys, []);
  assert.equal(evidence.variants.baseline.launchRequired.supportedCount, 0);
  assert.deepEqual(evidence.variants.lineScoped.supportedRequirementKeys, [PILOT_REQUIREMENT_KEY]);
  assert.equal(evidence.variants.lineScoped.launchRequired.supportedCount, 1);
  assert.equal(evidence.variants.lineScoped.launchRequired.totalCount, 270);

  const [before] = evidence.variants.baseline.pilotRequirements;
  const [after] = evidence.variants.lineScoped.pilotRequirements;
  assert.equal(before.requirementKey, PILOT_REQUIREMENT_KEY);
  assert.equal(before.status, "MISSING");
  assert.deepEqual(before.missingFields, ["route_map_position", "route_map_label_polygon"]);
  assert.equal(after.status, "SUPPORTED");
  assert.equal(after.releaseTier, "LAUNCH_REQUIRED");
  assert.equal(after.coveredFields, 2);
  assert.equal(after.denominator, 2);
  assert.deepEqual(after.sourceIds, [PILOT_SOURCE_ID]);
  assert.deepEqual(after.missingFields, []);

  assert.deepEqual(evidence.transitions, [{
    requirementKey: PILOT_REQUIREMENT_KEY,
    before: "MISSING",
    after: "SUPPORTED",
    sourceIds: [PILOT_SOURCE_ID],
    coveredFields: 2,
    denominator: 2,
  }]);
});

test("candidate spec의 line-scope 재기술은 tracked source inventory와 동기다", async (context) => {
  const spec = await readJson(SPEC_PATH);
  const inventory = await readJson(INVENTORY_PATH);
  const appInventory = await readJson(APP_INVENTORY_PATH);
  const [redescription] = spec.lineScopeRedescriptions;
  assert.equal(redescription.sourceId, PILOT_SOURCE_ID);
  assert.deepEqual(redescription.lineIds, ["seoul-4"]);
  assert.deepEqual(redescription.requirementKeys, [PILOT_REQUIREMENT_KEY]);

  const source = inventory.sources.find(({ id }) => id === PILOT_SOURCE_ID);
  assert.deepEqual(source.coverageScope.lineIds, redescription.lineIds);
  assert.ok(source.coverageScope.sourceDomains.includes(redescription.sourceDomain));
  assert.deepEqual(appInventory, inventory, "앱 번들 사본은 datapack 정본과 같아야 한다");

  await context.test("inventory lineIds가 spec과 어긋나면 하네스가 거부한다", async () => {
    const workspace = await mkdtemp(path.join(tmpdir(), "nationwide-candidate-gate-drift-"));
    const drifted = structuredClone(inventory);
    delete drifted.sources.find(({ id }) => id === PILOT_SOURCE_ID).coverageScope.lineIds;
    try {
      await assert.rejects(
        runNationwideCandidateCoverageGate({
          spec,
          specInput: { path: SPEC_PATH, sha256: "a".repeat(64) },
          targetsInput: { path: TARGETS_PATH, sha256: "b".repeat(64) },
          inventory: drifted,
          inventoryInput: { path: INVENTORY_PATH, sha256: "c".repeat(64) },
          resolutionPlanInput: { path: RESOLUTION_PLAN_PATH, sha256: "d".repeat(64) },
          resolutionsInput: { path: RESOLUTIONS_PATH, sha256: "e".repeat(64) },
          workDir: workspace,
        }),
        /source inventory coverageScope\.lineIds must match the spec redescription/,
      );
    } finally {
      await rm(workspace, { recursive: true, force: true });
    }
  });
});

test("production 게시 트랙 fixture는 candidate 조립에 영향받지 않는다", async () => {
  const spec = await readJson(SPEC_PATH);
  const reviewed = await readJson(REVIEWED_PACK_PATH);
  const [pack] = reviewed.packs;

  assert.equal(reviewed.packs.length, 1);
  assert.equal(pack.id, "capital");
  assert.equal(pack.version, "1");
  assert.equal(pack.artifactKind, "production");
  assert.equal(reviewed.manifest.channel, "production");
  assert.deepEqual(reviewed.manifest.activePack, { id: "capital", version: "1" });
  assert.notEqual(spec.pack.id, pack.id);
  assert.notEqual(spec.pack.url, pack.url);

  // 게시 트랙 fixture는 operator-scope 기술을 유지한다. line-scope 재기술은 candidate 조립에서만 일어난다.
  const source = pack.sourceInventory.find(({ id }) => id === PILOT_SOURCE_ID);
  assert.equal(source.coverageScope.lineIds, undefined);
});
