import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdirSync, rmdirSync, unlinkSync, writeFileSync } from "node:fs";
import { evaluateReadiness } from "./check-split-readiness.mjs";

test("datapack split readiness checks id와 상태를 고정한다", () => {
  const result = evaluateReadiness("datapack");

  assert.deepEqual(result.checks.map((check) => check.id), [
    "boundary.datapack",
    "datapack.producer-test",
    "datapack.mobile-consumer-test",
    "datapack.compatibility-matrix",
    "datapack.release-workflow-no-flutter",
    "datapack.env-scope-isolated",
    "datapack.no-mobile-release-paths",
    "datapack.candidate-promotion-separated",
    "datapack.component-manifest",
    "release.system-manifest-v2",
    "contracts.explicit-workspace",
  ]);
  for (const check of result.checks) {
    assert.ok(["pass", "fail"].includes(check.status), `${check.id} status`);
  }
});

test("canonical data와 platform target은 legacy readiness checks를 유지한다", () => {
  for (const [canonical, legacy] of [["data", "datapack"], ["platform", "infra"]]) {
    const result = evaluateReadiness(canonical);
    assert.equal(result.target, canonical);
    assert.deepEqual(result.checks, evaluateReadiness(legacy).checks);
  }
});

test("split readiness target별 check id와 현재 pass 상태를 고정한다", () => {
  const expected = new Map([
    ["datapack", [
      "boundary.datapack",
      "datapack.producer-test",
      "datapack.mobile-consumer-test",
      "datapack.compatibility-matrix",
      "datapack.release-workflow-no-flutter",
      "datapack.env-scope-isolated",
      "datapack.no-mobile-release-paths",
      "datapack.candidate-promotion-separated",
      "datapack.component-manifest",
      "release.system-manifest-v2",
      "contracts.explicit-workspace",
    ]],
    ["backend", [
      "backend.openapi-golden",
      "backend.archunit",
      "backend.cd-ghcr-digest",
      "backend.boundary",
      "backend.no-external-process-resources",
      "backend.contract-lock",
      "backend.contract-bundle",
      "backend.contract-staging",
      "backend.prelaunch-contract-bundle",
      "backend.component-manifest",
      "release.system-manifest-v2",
      "contracts.explicit-workspace",
    ]],
    ["infra", [
      "infra.compose-no-build",
      "infra.local-build-override",
      "infra.env-scope-shared-explicit",
      "infra.observability-required-metrics",
      "infra.deploy-consumes-digest-only",
      "infra.no-backend-build",
      "release.system-manifest-v2",
      "contracts.explicit-workspace",
    ]],
    ["mobile", [
      "mobile.golden-fixture-test",
      "mobile.datapack-consumer-test",
      "mobile.store-env-isolated",
      "mobile.datapack-lock",
      "mobile.artifact-staging",
      "mobile.component-manifest",
      "release.system-manifest-v2",
      "contracts.explicit-workspace",
    ]],
  ]);

  for (const [target, ids] of expected.entries()) {
    const result = evaluateReadiness(target);
    assert.deepEqual(result.checks.map((check) => check.id), ids);
    for (const check of result.checks) {
      assert.ok(["pass", "fail"].includes(check.status), `${target}: ${check.id} status`);
    }
  }
});

test("현재 분리 blocker를 readiness 결과에 fail로 드러낸다", () => {
  const datapack = evaluateReadiness("datapack");
  const infra = evaluateReadiness("infra");
  const backend = evaluateReadiness("backend");
  const mobile = evaluateReadiness("mobile");

  assert.equal(byId(datapack, "datapack.no-mobile-release-paths").status, "pass");
  assert.equal(byId(datapack, "datapack.candidate-promotion-separated").status, "fail");
  assert.equal(byId(infra, "infra.deploy-consumes-digest-only").status, "pass");
  assert.equal(byId(infra, "infra.no-backend-build").status, "pass");
  assert.equal(byId(backend, "backend.no-external-process-resources").status, "pass");
  assert.equal(byId(backend, "backend.contract-lock").status, "pass");
  assert.equal(byId(backend, "backend.contract-bundle").status, "pass");
  assert.equal(byId(backend, "backend.contract-staging").status, "pass");
  assert.equal(byId(backend, "backend.prelaunch-contract-bundle").status, "pass");
  assert.equal(byId(backend, "release.system-manifest-v2").status, "fail");
  assert.equal(byId(backend, "contracts.explicit-workspace").status, "pass");
  assert.equal(byId(mobile, "mobile.datapack-lock").status, "fail");
  assert.equal(byId(mobile, "mobile.artifact-staging").status, "fail");
});

test("datapack prelaunch backend Gradle은 hash-pinned contract bundle을 제공한다", () => {
  const backend = evaluateReadiness("backend");
  assert.equal(byId(backend, "backend.prelaunch-contract-bundle").status, "pass");
});

test("component manifest를 추가하면 해당 blocker만 pass가 된다", () => {
  const componentDirectory = "contracts/components";
  const componentPath = `${componentDirectory}/backend.json`;
  const componentDirectoryExisted = existsSync(componentDirectory);
  assert.equal(existsSync(componentPath), false);

  mkdirSync(componentDirectory, { recursive: true });
  writeFileSync(componentPath, "{}\n");
  try {
    const backend = evaluateReadiness("backend");
    assert.equal(byId(backend, "backend.component-manifest").status, "pass");
  } finally {
    unlinkSync(componentPath);
    if (!componentDirectoryExisted) rmdirSync(componentDirectory);
  }
});

function byId(result, id) {
  const check = result.checks.find((candidate) => candidate.id === id);
  assert.ok(check, `${id} check is required`);
  return check;
}
