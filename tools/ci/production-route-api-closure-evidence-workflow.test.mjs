import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const workflowPath = ".github/workflows/production-route-api-closure-evidence.yml";
const cdWorkflowPath = ".github/workflows/cd.yml";
const snapshotGatePath = "tools/ops/route-search-purge-snapshot-gate.sh";

test("production route API closure evidence는 현재 배포와 origin 403·row 불변을 검증한다", async () => {
  const workflow = await readFile(workflowPath, "utf8");

  assert.match(workflow, /^on:\n  push:\n    branches:\n      - main\n    paths:/m);
  assert.match(workflow, /workflow_dispatch:/);
  assert.match(workflow, /CLOSURE_BASE_SHA: cba25764de4ed646e398b2141b64fa41767ed3cc/);
  assert.doesNotMatch(workflow, /EXPECTED_IMAGE_DIGEST/);
  assert.match(workflow, /runs-on:\n\s+- self-hosted\n\s+- easysubway-production/);
  assert.doesNotMatch(workflow, /environment:\n\s+name: production/);
  assert.doesNotMatch(workflow, /^permissions:/m);
  assert.match(workflow, /verify:[\s\S]*?permissions:\n\s+contents: read[\s\S]*?steps:/);
  assert.match(workflow, /group: cd-production-deploy/);

  assert.match(workflow, /shared\/current-sha/);
  assert.match(workflow, /shared\/current-image-digest/);
  assert.match(workflow, /merge-base --is-ancestor "\$\{CLOSURE_BASE_SHA\}" "\$\{current_sha\}"/);
  assert.match(workflow, /\.Config\.Image/);
  assert.match(workflow, /\.RepoDigests/);
  assert.match(workflow, /org\.opencontainers\.image\.revision/);
  assert.match(workflow, /image_revision[^\n]+!=[^\n]+current_sha/);
  assert.match(workflow, /--format '\{\{\.Image\}\}'/);
  assert.match(workflow, /easysubway-backend/);
  assert.match(workflow, /easysubway-back-worker/);
  assert.match(workflow, /\/api\/v1\/routes\/search/);
  assert.match(workflow, /\/api\/v2\/routes\/search/);
  assert.match(workflow, /\/api\/v2\/routes\/closure-probe\/refresh/);
  assert.match(workflow, /--noproxy '\*'/);
  assert.match(workflow, /status[^\n]+!= "403"/);
  assert.doesNotMatch(workflow, /retry|acceptedStatuses|404/);

  assert.match(workflow, /SELECT count\(\*\) FROM route_search_results/);
  assert.match(workflow, /row_count_before/);
  assert.match(workflow, /row_count_after/);
  assert.match(workflow, /row_count_before[^\n]+!=[^\n]+row_count_after/);
  assert.match(workflow, /outputs:\n\s+deployed_sha: \$\{\{ steps\.closure\.outputs\.deployed_sha \}\}/);
  assert.match(workflow, /id: closure/);
  assert.match(workflow, /deployed_sha=%s\\n[^\n]+GITHUB_OUTPUT/);
});

test("production snapshot gate는 main-only runner에서 backup·격리 restore·purge plan만 수집한다", async () => {
  const workflow = await readFile(workflowPath, "utf8");
  const snapshotGate = await readFile(snapshotGatePath, "utf8").catch(() => "");

  assert.match(workflow, /tools\/ops\/route-search-purge-snapshot-gate\.sh/);
  assert.match(workflow, /tools\/ops\/postgres-backup\.sh/);
  assert.match(workflow, /backend\/src\/main\/resources\/db\/migration\/postgresql\/V51__/);
  assert.match(workflow, /backend\/src\/main\/resources\/db\/migration\/h2\/V51__/);
  assert.match(workflow, /snapshot-gate:[\s\S]*needs: verify/);
  assert.match(workflow, /snapshot-gate:[\s\S]*runs-on:\n\s+- self-hosted\n\s+- easysubway-production/);
  assert.match(workflow, /snapshot-gate:[\s\S]*environment: production/);
  assert.match(workflow, /snapshot-gate:[\s\S]*?permissions:\n\s+contents: read[\s\S]*?steps:/);
  assert.match(workflow, /snapshot-gate:[\s\S]*group: cd-production-deploy/);
  assert.match(workflow, /manual snapshot revalidation must run from main/);
  assert.match(workflow, /EXPECTED_DEPLOYED_SHA: \$\{\{ needs\.verify\.outputs\.deployed_sha \}\}/);
  assert.match(workflow, /SNAPSHOT_REQUEST_SHA: \$\{\{ github\.sha \}\}/);
  assert.match(workflow, /snapshot-gate:[\s\S]*Checkout reviewed main[\s\S]*persist-credentials: false/);
  assert.doesNotMatch(workflow, /upload-artifact/);

  assert.match(snapshotGate, /^set -euo pipefail$/m);
  assert.match(snapshotGate, /^umask 077$/m);
  assert.match(snapshotGate, /if ! flock -w 300 9/);
  assert.match(snapshotGate, /could not acquire deploy lock within timeout/);
  assert.match(snapshotGate, /EXPECTED_DEPLOYED_SHA/);
  assert.match(snapshotGate, /SNAPSHOT_REQUEST_SHA/);
  assert.match(snapshotGate, /snapshot-\$\{SNAPSHOT_REQUEST_SHA\}\.env/);
  assert.match(snapshotGate, /rm -f "\$\{MARKER_FILE\}"/);
  assert.match(snapshotGate, /current_sha[^\n]+!=[^\n]+EXPECTED_DEPLOYED_SHA/);
  assert.match(snapshotGate, /tools\/ops\/postgres-backup\.sh/);
  assert.match(snapshotGate, /pg_restore/);
  assert.match(snapshotGate, /--pull never/);
  assert.match(snapshotGate, /--cpus "\$\{RESTORE_CPU_LIMIT\}"/);
  assert.match(snapshotGate, /--memory "\$\{RESTORE_MEMORY_LIMIT\}"/);
  assert.match(snapshotGate, /--memory-swap "\$\{RESTORE_MEMORY_LIMIT\}"/);
  assert.match(snapshotGate, /--pids-limit "\$\{RESTORE_PIDS_LIMIT\}"/);
  assert.match(snapshotGate, /restore resource limits/);
  assert.match(snapshotGate, /source_database_bytes/);
  assert.match(snapshotGate, /SPACE_CLASS='\[:space:\]'/);
  assert.doesNotMatch(snapshotGate, /tr -d '\[:space:\]'/);
  assert.match(snapshotGate, /storage_probe/);
  assert.match(snapshotGate, /--mount type=volume,target=\/probe\/docker/);
  assert.doesNotMatch(snapshotGate, /df -PB1 "\$\{docker_root_dir\}"/);
  assert.match(snapshotGate, /backup_required_before/);
  assert.match(snapshotGate, /operational_reserve_bytes/);
  assert.match(snapshotGate, /restore_cluster_reserve_bytes/);
  assert.match(snapshotGate, /restore_wal_reserve_bytes/);
  assert.match(snapshotGate, /docker_available_after_backup/);
  assert.match(snapshotGate, /insufficient Docker filesystem headroom/);
  assert.match(snapshotGate, /ANALYZE route_search_results, favorite_routes, favorite_route_stations, route_feedbacks/);
  assert.ok(
    snapshotGate.indexOf("ANALYZE route_search_results") < snapshotGate.indexOf("EXPLAIN (ANALYZE, BUFFERS, WAL)"),
    "restored purge tables must be analyzed before the measured plan",
  );
  assert.match(snapshotGate, /EXPLAIN \(ANALYZE, BUFFERS, WAL/);
  assert.match(snapshotGate, /ROLLBACK/);
  assert.match(snapshotGate, /favorite_routes/);
  assert.match(snapshotGate, /favorite_route_stations/);
  assert.match(snapshotGate, /route_feedbacks/);
  assert.match(snapshotGate, /org\.opencontainers\.image\.revision/);
  assert.match(snapshotGate, /production_image=.*\{\{\.Image\}\}/);
  assert.doesNotMatch(snapshotGate, /production_image=.*\{\{\.Config\.Image\}\}/);
  assert.match(snapshotGate, /production_settings_sql=/);
  assert.match(snapshotGate, /-c "\$1"' sh/);
  assert.match(snapshotGate, /report_file/);
  assert.match(snapshotGate, /cat "\$\{report_file\}"/);
  assert.match(snapshotGate, /snapshot-complete/);
  assert.match(snapshotGate, /snapshot_request_sha/);
  assert.doesNotMatch(snapshotGate, /existing verified backup/);
  assert.doesNotMatch(snapshotGate, /\b(curl|scp)\b|upload-artifact/);

  const reportAppend = snapshotGate.indexOf('cat "${report_file}" >> "${SUMMARY_FILE}"');
  const markerPublish = snapshotGate.lastIndexOf('mv "${marker_tmp}" "${MARKER_FILE}"');
  assert.notEqual(reportAppend, -1);
  assert.notEqual(markerPublish, -1);
  assert.ok(reportAppend < markerPublish, "success marker must be published after required evidence");
});

test("V51 CD는 exact SHA의 성공한 snapshot gate 없이는 mutation 전에 중단한다", async () => {
  const workflow = await readFile(cdWorkflowPath, "utf8");

  assert.match(workflow, /CD Deploy \/ Detect route purge migration/);
  assert.match(workflow, /current_sha="\$\(<"\$\{DEPLOY_ROOT\}\/shared\/current-sha"\)"/);
  assert.match(workflow, /git diff --name-only "\$\{current_sha\}" "\$\{DEPLOY_SHA\}"/);
  assert.match(
    workflow,
    /backend\/src\/main\/resources\/db\/migration\/\(postgresql\|h2\)\/V51__/,
  );
  assert.match(workflow, /CD Deploy \/ Require route purge snapshot evidence/);
  assert.match(
    workflow,
    /if: \$\{\{ steps\.route-purge\.outputs\.required == 'true' \}\}/,
  );
  assert.match(
    workflow,
    /actions\/workflows\/production-route-api-closure-evidence\.yml\/runs\?head_sha=\$\{DEPLOY_SHA\}&branch=main&status=success&per_page=20/,
  );
  assert.match(
    workflow,
    /node tools\/ci\/require-successful-workflow-run\.mjs[\s\S]*?"\$\{snapshot_runs_file\}"[\s\S]*?"\$\{DEPLOY_SHA\}"[\s\S]*?"Production route API closure evidence"[\s\S]*?"push,workflow_dispatch"[\s\S]*?main[\s\S]*?3600/,
  );
  assert.match(workflow, /echo "current_sha=\$\{current_sha\}" >> "\$\{GITHUB_OUTPUT\}"/);
  assert.match(workflow, /snapshot-\$\{DEPLOY_SHA\}\.env/);
  assert.match(workflow, /marker_request_sha[^\n]+!=[^\n]+DEPLOY_SHA/);
  assert.match(workflow, /marker_current_sha[^\n]+!=[^\n]+CURRENT_DEPLOYED_SHA/);
  assert.match(workflow, /snapshot marker backup checksum mismatch/);

  const rangeDetectionIndex = workflow.indexOf('git diff --name-only "${current_sha}" "${DEPLOY_SHA}"');
  const latchIndex = workflow.indexOf("CD Deploy / Require route purge snapshot evidence");
  const mutationPreparationIndex = workflow.indexOf("CD Deploy / Restore GitHub Actions dotenv secret");

  assert.notEqual(rangeDetectionIndex, -1);
  assert.notEqual(latchIndex, -1);
  assert.notEqual(mutationPreparationIndex, -1);
  assert.ok(latchIndex < mutationPreparationIndex, "snapshot evidence must gate production mutation");
});
