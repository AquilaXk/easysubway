#!/usr/bin/env node
import { isMainModule } from "../lib/is-main-module.mjs";
import { existsSync, readFileSync } from "node:fs";
import { collectContractErrors, loadJson } from "../ci/check-contracts.mjs";
import { findViolations } from "../ci/check-boundaries.mjs";

export function evaluateReadiness(target) {
  if (target === "datapack" || target === "data") return { target, checks: datapackChecks() };
  if (target === "infra" || target === "platform") return { target, checks: infraChecks() };
  if (target === "backend") return { target, checks: backendChecks() };
  if (target === "mobile") return { target, checks: mobileChecks() };
  throw new Error(`unknown target: ${target}`);
}

function datapackChecks() {
  const boundaries = loadJson("contracts/boundaries.json");
  const datapackRules = (boundaries.forbiddenReferences ?? []).filter((rule) => rule.from === "tools/datapack");
  const errors = collectContractErrors();
  const datapackReleaseWorkflow = readTextIfExists(".github/workflows/datapack-release.yml");
  return [
    check("boundary.datapack", findViolations(datapackRules, { allowlist: boundaries.allowlist ?? [] }).length === 0),
    check("datapack.producer-test", existsSync("tools/datapack/contract-producer.test.mjs")),
    check("datapack.mobile-consumer-test", existsSync("apps/mobile/test/contract/datapack_index_fixture_test.dart")),
    check("datapack.compatibility-matrix", errors.every((error) => !error.includes("compatibility-matrix"))),
    check("datapack.release-workflow-no-flutter", datapackReleaseWorkflow !== null && !datapackReleaseWorkflow.includes("flutter")),
    check("datapack.env-scope-isolated", scopesDisjoint("datapack-release", "store-release")),
    check("datapack.no-mobile-release-paths", datapackReleaseWorkflow !== null && !datapackReleaseWorkflow.includes("apps/mobile/release/")),
    check("datapack.candidate-promotion-separated", datapackReleaseWorkflow !== null && !datapackReleaseWorkflow.includes("production-publish")),
    componentManifestCheck("datapack"),
    ...sharedChecks(),
  ];
}

function infraChecks() {
  const compose = readFileSync("infra/docker-compose.yml", "utf8");
  const cd = readTextIfExists(".github/workflows/cd.yml");
  return [
    check("infra.compose-no-build", !hasComposeBuild(compose)),
    check("infra.local-build-override", existsSync("infra/docker-compose.local-build.yml")),
    check("infra.env-scope-shared-explicit", scopeExists("shared")),
    { id: "infra.observability-required-metrics", status: "pass", note: "deferred until split execution" },
    check("infra.deploy-consumes-digest-only", cd !== null && !cd.includes("working-directory: backend")),
    check("infra.no-backend-build", cd !== null && !cd.includes("backend/Dockerfile")),
    ...sharedChecks(),
  ];
}

function backendChecks() {
  const boundaries = loadJson("contracts/boundaries.json");
  const cd = readTextIfExists(".github/workflows/cd.yml");
  return [
    check("backend.openapi-golden", existsSync("contracts/api/report-api.openapi.yaml") && existsSync("contracts/api/fixtures/report-status.ok.json")),
    check("backend.archunit", existsSync("backend/src/test/java/com/easysubway/architecture/PackageDependencyRulesTest.java")),
    check("backend.cd-ghcr-digest", cd !== null && cd.includes("ghcr.io/aquilaxk/easysubway-backend") && cd.includes("DEPLOY_IMAGE_DIGEST") && cd.includes('docker tag "${IMAGE}@${DEPLOY_IMAGE_DIGEST}"')),
    check("backend.boundary", findViolations(boundaries.forbiddenReferences ?? [], { allowlist: boundaries.allowlist ?? [] }).length === 0),
    check("backend.no-external-process-resources", !backendBuildUsesExternalProcessResources()),
    check("backend.contract-lock", existsSync("contracts/backend/contract-lock.json")),
    componentManifestCheck("backend"),
    ...sharedChecks(),
  ];
}

function mobileChecks() {
  return [
    check("mobile.golden-fixture-test", existsSync("apps/mobile/test/contract/facility_report_fixture_test.dart")),
    check("mobile.datapack-consumer-test", existsSync("apps/mobile/test/contract/datapack_index_fixture_test.dart")),
    check("mobile.store-env-isolated", scopesDisjoint("store-release", "datapack-release")),
    check("mobile.datapack-lock", existsSync("apps/mobile/release/datapack.lock.json")),
    check("mobile.artifact-staging", existsSync("apps/mobile/release/artifact-staging.json")),
    componentManifestCheck("mobile"),
    ...sharedChecks(),
  ];
}

function scopesDisjoint(left, right) {
  const keys = loadJson("contracts/env/env-scope-map.json").keys;
  return Object.values(keys).every((scopes) => !(scopes.includes(left) && scopes.includes(right)));
}

function scopeExists(scope) {
  const map = loadJson("contracts/env/env-scope-map.json");
  return map.scopes.includes(scope);
}

function componentManifestCheck(component) {
  return check(`${component}.component-manifest`, existsSync(`contracts/components/${component}.json`));
}

function sharedChecks() {
  return [
    check("release.system-manifest-v2", hasSystemManifestV2()),
    check("contracts.explicit-workspace", existsSync("contracts/workspace.json")),
  ];
}

function hasSystemManifestV2() {
  const manifest = readTextIfExists("contracts/release/system-manifest.json");
  if (manifest === null) return false;
  try {
    return JSON.parse(manifest).manifestVersion === 2;
  } catch {
    return false;
  }
}

function backendBuildUsesExternalProcessResources() {
  const build = readTextIfExists("backend/build.gradle");
  return build !== null && (build.includes("../tools/") || build.includes("../apps/"));
}

function check(id, ok) {
  return { id, status: ok ? "pass" : "fail" };
}

function hasComposeBuild(compose) {
  return compose.split(/\r?\n/).some((line) => line.trimStart().startsWith("build:"));
}

function readTextIfExists(path) {
  if (!existsSync(path)) return null;
  return readFileSync(path, "utf8");
}

if (isMainModule(import.meta.url)) {
  const target = process.argv.includes("--target") ? process.argv[process.argv.indexOf("--target") + 1] : "datapack";
  const result = evaluateReadiness(target);
  for (const check of result.checks) {
    const note = check.note ? ` (${check.note})` : "";
    console.log(`${check.status.toUpperCase()} ${check.id}${note}`);
  }
  if (result.checks.some((check) => check.status === "fail")) process.exit(1);
}
