import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const workflow = (name) => readFileSync(new URL(`../../.github/workflows/${name}`, import.meta.url), "utf8");
const cd = workflow("cd.yml");
const prelaunchGates = workflow("datapack-prelaunch-gates.yml");

test("cd.yml은 Release Artifacts가 만든 image digest와 manifest 계약만 소비한다", () => {
  for (const required of [
    "Release Artifacts",
    "needs.plan.outputs.image_digest",
    'manifest?.contractVersion !== "1.0.0"',
    "manifest?.artifactIdentity?.apiContractVersion !== manifest.contractVersion",
    'createHash("sha256").update(evidence).digest("hex") !== manifest.evidenceSha256',
    "process.stdout.write(`image_digest=${digest}\\n`);",
  ]) {
    assert.ok(cd.includes(required), required);
  }
  assert.ok(!cd.includes("build-image"));
});

test("cd.yml은 backend를 직접 빌드하지 않는다", () => {
  for (const forbidden of ["working-directory: backend", "backend/Dockerfile", "gradlew bootJar", "docker buildx build"]) {
    assert.ok(!cd.includes(forbidden), forbidden);
  }
});

test("cd.yml은 GHCR backend 이미지를 digest로 pull하고 tag를 붙인다", () => {
  assert.ok(cd.includes("ghcr.io/aquilaxk/easysubway-backend"));
  assert.ok(cd.includes("DEPLOY_IMAGE_DIGEST"));
  assert.ok(cd.includes('docker tag "${IMAGE}@${DEPLOY_IMAGE_DIGEST}"'));
});

test("datapack-prelaunch-gates.yml은 backend 테스트에 contract bundle을 주입한다", () => {
  assert.match(
    prelaunchGates,
    /EASYSUBWAY_CONTRACTS_BUNDLE:\s*\$\{\{ github\.workspace \}\}\/contracts\/bundles\/backend-contracts-v1\.0\.0\.json[\s\S]*backend\/gradlew -p backend test/,
  );
});
