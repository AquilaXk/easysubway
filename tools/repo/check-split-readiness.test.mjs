import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
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

  assert.equal(byId(datapack, "datapack.no-mobile-release-paths").status, "fail");
  assert.equal(byId(datapack, "datapack.candidate-promotion-separated").status, "fail");
  assert.equal(byId(infra, "infra.deploy-consumes-digest-only").status, "fail");
  assert.equal(byId(infra, "infra.no-backend-build").status, "fail");
  assert.equal(byId(backend, "backend.no-external-process-resources").status, "fail");
  assert.equal(byId(backend, "release.system-manifest-v2").status, "fail");
  assert.equal(byId(backend, "contracts.explicit-workspace").status, "fail");
  assert.equal(byId(mobile, "mobile.datapack-lock").status, "fail");
  assert.equal(byId(mobile, "mobile.artifact-staging").status, "fail");
});

test("component manifest와 backend contract lock을 추가하면 해당 blocker만 pass가 된다", () => {
  const componentDirectory = "contracts/components";
  const backendDirectory = "contracts/backend";
  const componentPath = `${componentDirectory}/backend.json`;
  const lockPath = `${backendDirectory}/contract-lock.json`;
  assert.equal(existsSync(componentPath), false);
  assert.equal(existsSync(lockPath), false);

  mkdirSync(componentDirectory, { recursive: true });
  mkdirSync(backendDirectory, { recursive: true });
  writeFileSync(componentPath, "{}\n");
  writeFileSync(lockPath, "{}\n");
  try {
    const backend = evaluateReadiness("backend");
    assert.equal(byId(backend, "backend.component-manifest").status, "pass");
    assert.equal(byId(backend, "backend.contract-lock").status, "pass");
  } finally {
    rmSync(componentPath, { force: true });
    rmSync(lockPath, { force: true });
    rmSync(componentDirectory, { recursive: true, force: true });
    rmSync(backendDirectory, { recursive: true, force: true });
  }
});

function byId(result, id) {
  const check = result.checks.find((candidate) => candidate.id === id);
  assert.ok(check, `${id} check is required`);
  return check;
}
