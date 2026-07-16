import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const workflowPath = ".github/workflows/datapack-callback-reconciliation-evidence.yml";
const workflow = readFileSync(workflowPath, "utf8");
const releaseArtifactsWorkflow = readFileSync(".github/workflows/release-artifacts.yml", "utf8");

test("callback reconciliation evidence는 default branch 수동 실행과 세 identity 입력만 허용한다", () => {
  const inputsBlock = workflow.slice(workflow.indexOf("    inputs:"), workflow.indexOf("\njobs:"));
  assert.match(workflow, /workflow_dispatch:\s*\n\s*inputs:/);
  assert.match(inputsBlock, /release_artifacts_run_id:/);
  assert.match(inputsBlock, /datapack_run_id:/);
  assert.match(inputsBlock, /release_request_id:/);
  assert.doesNotMatch(inputsBlock, /\b(callback_?secret|token|authorization|manifest_sha256|release_sequence):/i);
  assert.match(workflow,
    /github\.ref\s*==\s*format\('refs\/heads\/\{0\}',\s*github\.event\.repository\.default_branch\)/);
});

test("job-level env는 runner가 배정되기 전 runner context를 참조하지 않는다", () => {
  const jobStart = workflow.indexOf("  rehearse:");
  const stepsStart = workflow.indexOf("\n    steps:", jobStart);
  assert.notEqual(jobStart, -1);
  assert.notEqual(stepsStart, -1);
  assert.ok(jobStart < stepsStart);
  const jobPrelude = workflow.slice(jobStart, stepsStart);
  assert.doesNotMatch(jobPrelude, /\$\{\{\s*runner\./);
});

test("pinned Node 24·Java 21과 동일 SHA의 final RC·publish binding을 사용한다", () => {
  assert.match(workflow, /actions\/setup-node@48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e/);
  assert.match(workflow, /node-version:\s*["']24["']/);
  assert.match(workflow, /actions\/setup-java@be666c2fcd27ec809703dec50e508c2fdc7f6654/);
  assert.match(workflow, /java-version:\s*["']21["']/);
  assert.match(workflow, /actions\/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093/);
  assert.match(workflow, /run-id:\s*\$\{\{ inputs\.release_artifacts_run_id \}\}/);
  assert.match(workflow, /easysubway-rc-evidence-manifest-\$\{\{ github\.sha \}\}/);
  assert.match(workflow, /run-id:\s*\$\{\{ inputs\.datapack_run_id \}\}/);
  assert.match(workflow,
    /easysubway-published-release-request-binding-\$\{\{ github\.sha \}\}/);
  assert.match(workflow, /environment:\s*\n\s*name:\s*production-datapack/);
  assert.match(workflow, /EASYSUBWAY_ENV_SECRET:\s*\$\{\{ secrets\.EASYSUBWAY_ENV \}\}/);
  assert.match(workflow, /EASYSUBWAY_CALLBACK_VALIDATION_ENV=\$\{env_file\}/);
  assert.match(workflow, /node --env-file="\$\{EASYSUBWAY_CALLBACK_VALIDATION_ENV\}"/);
  assert.match(workflow, /--prepare-from-rc-manifest[\s\S]*?--expected-git-sha "\$\{GITHUB_SHA\}"/);
  assert.match(workflow,
    /--release-request-binding "\$\{RUNNER_TEMP\}\/datapack-release\/release-request-binding\.json"/);
  assert.match(workflow,
    /if:\s*\$\{\{ always\(\) \}\}[\s\S]*?rm -f "\$\{RUNNER_TEMP\}\/easysubway-callback-validation\.env"/);
});

test("실제 H2 rehearsal과 canonical regression tests를 실행한다", () => {
  assert.match(workflow,
    /node tools\/datapack\/run-callback-backend-outage-rehearsal\.mjs[\s\S]*?--output "\$\{RAW_CALLBACK_OUTAGE_PATH\}"/);
  assert.match(workflow,
    /EASYSUBWAY_CALLBACK_OUTAGE_ARTIFACT:\s*\$\{\{ runner\.temp \}\}\/datapack-callback-backend-outage\.json/);
  for (const testClass of [
    "DatapackCallbackReconciliationRehearsalTest",
    "DatapackReleaseCallbackServiceTest",
    "DatapackReleaseReconciliationServiceTest",
    "JdbcDatapackReleaseDeliveryRepositoryTest",
    "DatapackReleaseRequestAdminPageControllerTest",
  ]) {
    assert.match(workflow, new RegExp(`--tests ['\"][^'\"]*${testClass}['\"]`));
  }
  assert.match(workflow, /node --test tools\/datapack\/build-callback-reconciliation-evidence\.test\.mjs/);
  assert.match(workflow, /node --test tools\/ci\/datapack-release-workflow\.test\.mjs/);
});

test("result 검증 뒤 #2056 gate envelope만 sanitized JSON artifact로 보존한다", () => {
  assert.match(workflow, /--validate-evidence[\s\S]*?--artifact-dir/);
  assert.match(workflow, /--wrap-result[\s\S]*?--rc-manifest/);
  assert.match(workflow, /actions\/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02/);
  assert.match(workflow, /\$\{\{ runner\.temp \}\}\/datapack-callback-reconciliation-evidence\/\*\.json/);
  assert.match(workflow, /if-no-files-found:\s*error/);
  assert.match(workflow, /retention-days:\s*14/);
  const uploadStep = workflow.slice(workflow.indexOf("      - name: Callback reconciliation / Upload sanitized evidence"),
    workflow.indexOf("      - name: Callback reconciliation / Remove signing validation environment"));
  assert.doesNotMatch(uploadStep, /\.env|backend\/build\/test-results/);
});

test("Release Artifacts 재실행은 callback gate evidence를 final readiness에 직접 소비한다", () => {
  assert.match(releaseArtifactsWorkflow, /callback_reconciliation_run_id:/);
  assert.match(releaseArtifactsWorkflow,
    /run-id:\s*\$\{\{ inputs\.callback_reconciliation_run_id \}\}/);
  assert.match(releaseArtifactsWorkflow,
    /datapack-callback-reconciliation-evidence-\$\{\{ github\.sha \}\}/);
  assert.match(releaseArtifactsWorkflow,
    /--datapack-gate-status callback_reconciliation=SATISFIED/);
  assert.match(releaseArtifactsWorkflow,
    /--datapack-gate-evidence callback_reconciliation=release-artifacts\/downloaded\/callback-reconciliation\/callback-reconciliation-gate-evidence\.json/);
});
