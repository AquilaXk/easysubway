import test from "node:test";
import assert from "node:assert/strict";
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
    ]],
    ["backend", [
      "backend.openapi-golden",
      "backend.archunit",
      "backend.cd-ghcr-digest",
      "backend.boundary",
    ]],
    ["infra", [
      "infra.compose-no-build",
      "infra.local-build-override",
      "infra.env-scope-shared-explicit",
      "infra.observability-required-metrics",
    ]],
    ["mobile", [
      "mobile.golden-fixture-test",
      "mobile.datapack-consumer-test",
      "mobile.store-env-isolated",
    ]],
  ]);

  for (const [target, ids] of expected.entries()) {
    const result = evaluateReadiness(target);
    assert.deepEqual(result.checks.map((check) => check.id), ids);
    assert.deepEqual(result.checks.map((check) => check.status), ids.map(() => "pass"), target);
  }
});
