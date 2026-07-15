import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const workflowPath = ".github/workflows/production-route-api-closure-evidence.yml";
const cdWorkflowPath = ".github/workflows/cd.yml";
const snapshotGatePath = "tools/ops/route-search-purge-snapshot-gate.sh";
const rollbackRehearsalPath = "tools/ops/route-search-purge-rollback-rehearsal.sh";
const purgeSqlPath = "tools/ops/route-search-purge.sql";
const postgresV51Path =
  "backend/src/main/resources/db/migration/postgresql/V51__purge_unreferenced_route_search_results.sql";
const h2V51Path =
  "backend/src/main/resources/db/migration/h2/V51__purge_unreferenced_route_search_results.sql";
const postgresV51TimeoutPrefix = `SET LOCAL lock_timeout = '30s';
SET LOCAL statement_timeout = '30s';

`;

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
  assert.match(workflow, /group: production-route-api-closure-evidence/);

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
  const purgeSql = await readFile(purgeSqlPath, "utf8").catch(() => "");
  const postgresV51 = await readFile(postgresV51Path, "utf8");
  const h2V51 = await readFile(h2V51Path, "utf8");

  assert.match(workflow, /tools\/ops\/route-search-purge-snapshot-gate\.sh/);
  assert.match(workflow, /tools\/ops\/route-search-purge\.sql/);
  assert.match(workflow, /tools\/ops\/postgres-backup\.sh/);
  assert.match(workflow, /backend\/src\/main\/resources\/db\/migration\/postgresql\/V51__/);
  assert.match(workflow, /backend\/src\/main\/resources\/db\/migration\/h2\/V51__/);
  assert.match(workflow, /snapshot-gate:[\s\S]*needs: verify/);
  assert.match(workflow, /snapshot-gate:[\s\S]*runs-on:\n\s+- self-hosted\n\s+- easysubway-production/);
  assert.match(workflow, /snapshot-gate:[\s\S]*environment: production/);
  assert.match(workflow, /snapshot-gate:[\s\S]*?permissions:\n\s+contents: read[\s\S]*?steps:/);
  assert.match(workflow, /verify:[\s\S]*group: production-route-api-closure-evidence/);
  assert.match(workflow, /snapshot-gate:[\s\S]*group: production-route-api-closure-evidence/);
  assert.doesNotMatch(workflow, /group: cd-production-deploy/);
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
  assert.match(snapshotGate, /purge_sql_sha256/);
  assert.match(snapshotGate, /EXECUTION_BUDGET_MS="30000"/);
  assert.match(snapshotGate, /WAL_BUDGET_BYTES="\$\(\(256 \* 1024 \* 1024\)\)"/);
  assert.match(snapshotGate, /production_schema_version/);
  assert.match(snapshotGate, /restore_schema_version/);
  assert.match(snapshotGate, /shopt -s nullglob/);
  assert.match(snapshotGate, /POSTGRES_V51_FILES=\([^\n]+V51__\*\.sql/);
  assert.match(snapshotGate, /H2_V51_FILES=\([^\n]+V51__\*\.sql/);
  assert.match(snapshotGate, /#POSTGRES_V51_FILES\[@\][^\n]+!= 1/);
  assert.match(snapshotGate, /POSTGRES_V51_FILES\[0\][^\n]+!=[^\n]+POSTGRES_V51/);
  assert.match(snapshotGate, /cmp -s "\$\{PURGE_SQL_FILE\}"/);
  assert.match(snapshotGate, /SET LOCAL lock_timeout = '30s'/);
  assert.match(snapshotGate, /SET LOCAL statement_timeout = '30s'/);
  assert.match(snapshotGate, /tail -n \+4 "\$\{POSTGRES_V51\}"/);
  assert.doesNotMatch(snapshotGate, /if \[\[ -e "\$\{POSTGRES_V51\}" \|\| -e "\$\{H2_V51\}" \]\]/);
  assert.match(purgeSql, /^DELETE FROM route_search_results AS route/m);
  assert.doesNotMatch(purgeSql, /BEGIN|EXPLAIN|ROLLBACK/);
  assert.equal(postgresV51, postgresV51TimeoutPrefix + purgeSql);
  assert.equal(h2V51, purgeSql);
  assert.match(snapshotGate, /tools\/ops\/postgres-backup\.sh/);
  assert.match(snapshotGate, /pg_restore --clean --if-exists --no-owner --no-privileges/);
  assert.match(snapshotGate, /cat \/proc\/1\/comm/);
  assert.match(snapshotGate, /restore_init_process[^\n]+==[^\n]+postgres/);
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
  const analyzeIndex = snapshotGate.indexOf("ANALYZE route_search_results");
  const checkpointIndex = snapshotGate.indexOf("restore_psql -c 'CHECKPOINT;'");
  const explainIndex = snapshotGate.indexOf("EXPLAIN (ANALYZE, BUFFERS, WAL)");
  assert.notEqual(analyzeIndex, -1, "the restored purge tables must be analyzed");
  assert.notEqual(checkpointIndex, -1, "the restore database must be checkpointed");
  assert.notEqual(explainIndex, -1, "the measured purge plan must be present");
  assert.ok(
    analyzeIndex < explainIndex,
    "restored purge tables must be analyzed before the measured plan",
  );
  assert.match(snapshotGate, /restore_psql -c 'CHECKPOINT;'/);
  assert.ok(
    analyzeIndex < checkpointIndex,
    "checkpoint must include the restored and analyzed table state",
  );
  assert.ok(
    checkpointIndex < explainIndex,
    "checkpoint must precede the WAL measurement",
  );
  assert.ok(
    snapshotGate.indexOf("cat /proc/1/comm") < snapshotGate.indexOf("pg_restore"),
    "restore must wait for the final PostgreSQL server, not the temporary init server",
  );
  assert.match(snapshotGate, /EXPLAIN \(ANALYZE, BUFFERS, WAL/);
  assert.match(snapshotGate, /ROLLBACK/);
  assert.match(snapshotGate, /favorite_routes/);
  assert.match(snapshotGate, /favorite_route_stations/);
  assert.match(snapshotGate, /route_feedbacks/);
  assert.match(snapshotGate, /favorite_routes_null/);
  assert.match(snapshotGate, /favorite_route_stations_null/);
  assert.match(snapshotGate, /route_feedbacks_null/);
  assert.match(snapshotGate, /route reference NULL anomaly/);
  assert.match(snapshotGate, /route purge aggregate invariant failed/);
  assert.match(snapshotGate, /org\.opencontainers\.image\.revision/);
  assert.match(snapshotGate, /production_image=.*\{\{\.Image\}\}/);
  assert.doesNotMatch(snapshotGate, /production_image=.*\{\{\.Config\.Image\}\}/);
  assert.match(snapshotGate, /production_settings_sql=/);
  assert.match(snapshotGate, /-c "\$1"' sh/);
  assert.match(snapshotGate, /report_file/);
  assert.match(snapshotGate, /cat "\$\{report_file\}"/);
  assert.match(snapshotGate, /snapshot-complete/);
  assert.match(snapshotGate, /snapshot_request_sha/);
  assert.match(snapshotGate, /deployed_sha/);
  assert.match(snapshotGate, /image_revision/);
  assert.match(snapshotGate, /postgresql_major/);
  assert.match(snapshotGate, /schema_version/);
  assert.match(snapshotGate, /purge_sql_sha256/);
  assert.match(snapshotGate, /owner approved on #1913 — 30 seconds execution\/lock and 256 MiB WAL/);
  assert.match(snapshotGate, /adjusted purge execution exceeds approved 30 second budget/);
  assert.match(snapshotGate, /purge WAL exceeds approved 256 MiB budget/);
  assert.doesNotMatch(snapshotGate, /budget decision: pending/);
  assert.doesNotMatch(snapshotGate, /existing verified backup/);
  assert.doesNotMatch(snapshotGate, /\b(curl|scp)\b|upload-artifact/);

  const reportAppend = snapshotGate.indexOf('cat "${report_file}" >> "${SUMMARY_FILE}"');
  const executionBudgetCheck = snapshotGate.indexOf("adjusted purge execution exceeds approved 30 second budget");
  const walBudgetCheck = snapshotGate.indexOf("purge WAL exceeds approved 256 MiB budget");
  const markerPublish = snapshotGate.lastIndexOf('mv "${marker_tmp}" "${MARKER_FILE}"');
  assert.notEqual(reportAppend, -1);
  assert.notEqual(executionBudgetCheck, -1);
  assert.notEqual(walBudgetCheck, -1);
  assert.notEqual(markerPublish, -1);
  assert.ok(executionBudgetCheck < markerPublish, "execution budget must fail closed before marker publish");
  assert.ok(walBudgetCheck < markerPublish, "WAL budget must fail closed before marker publish");
  assert.ok(reportAppend < markerPublish, "success marker must be published after required evidence");
});

test("V51 CD는 exact SHA의 성공한 snapshot gate 없이는 mutation 전에 중단한다", async () => {
  const workflow = await readFile(cdWorkflowPath, "utf8");

  assert.match(workflow, /CD Deploy \/ Set up Node\.js/);
  assert.match(
    workflow,
    /CD Deploy \/ Set up Node\.js[\s\S]*?actions\/setup-node@48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e[\s\S]*?node-version: "24"/,
  );
  assert.match(workflow, /CD Deploy \/ Detect route purge migration/);
  assert.match(
    workflow,
    /if \[\[ ! -f "\$\{DEPLOY_ROOT\}\/shared\/current-sha" \]\]; then[\s\S]*?echo "required=false"[\s\S]*?exit 0/,
  );
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
  assert.match(workflow, /marker_deployed_sha[^\n]+!=[^\n]+CURRENT_DEPLOYED_SHA/);
  assert.match(workflow, /marker_image_revision[^\n]+!=[^\n]+current_image_revision/);
  assert.match(workflow, /marker_postgresql_major[^\n]+!=[^\n]+current_postgresql_major/);
  assert.match(workflow, /marker_schema_version[^\n]+!=[^\n]+current_schema_version/);
  assert.match(workflow, /marker_purge_sql_sha[^\n]+!=[^\n]+current_purge_sql_sha/);
  assert.match(workflow, /snapshot marker backup checksum mismatch/);
  assert.match(workflow, /snapshot_wait_deadline="\$\(\(SECONDS \+ 3600\)\)"/);
  assert.match(
    workflow,
    /if curl -fsS[\s\S]*?--connect-timeout 5[\s\S]*?--max-time 20[\s\S]*?then[\s\S]*?require-successful-workflow-run\.mjs/,
  );
  assert.match(workflow, /snapshot evidence query failed; retrying within bounded deadline/);
  assert.match(workflow, /while true; do[\s\S]*?require-successful-workflow-run\.mjs[\s\S]*?break[\s\S]*?sleep 15[\s\S]*?done/);

  const rangeDetectionIndex = workflow.indexOf('git diff --name-only "${current_sha}" "${DEPLOY_SHA}"');
  const nodeSetupIndex = workflow.indexOf("CD Deploy / Set up Node.js");
  const latchIndex = workflow.indexOf("CD Deploy / Require route purge snapshot evidence");
  const mutationPreparationIndex = workflow.indexOf("CD Deploy / Restore GitHub Actions dotenv secret");

  assert.notEqual(rangeDetectionIndex, -1);
  assert.notEqual(nodeSetupIndex, -1);
  assert.notEqual(latchIndex, -1);
  assert.notEqual(mutationPreparationIndex, -1);
  assert.ok(nodeSetupIndex < latchIndex, "Node.js must be available before the snapshot evidence gate");
  assert.ok(latchIndex < mutationPreparationIndex, "snapshot evidence must gate production mutation");
});

test("V51 CD는 production mutation 전에 exact PR1 image rollback을 격리 rehearsal한다", async () => {
  const workflow = await readFile(cdWorkflowPath, "utf8");
  const rehearsal = await readFile(rollbackRehearsalPath, "utf8").catch(() => "");

  assert.match(workflow, /CD Deploy \/ Rehearse PR1 image rollback after V51/);
  assert.match(workflow, /bash tools\/ops\/route-search-purge-rollback-rehearsal\.sh/);
  assert.match(workflow, /CURRENT_DEPLOYED_SHA: \$\{\{ steps\.route-purge\.outputs\.current_sha \}\}/);
  const imagePullIndex = workflow.indexOf("CD Deploy / Pull backend image by digest");
  const rehearsalIndex = workflow.indexOf("CD Deploy / Rehearse PR1 image rollback after V51");
  const productionMutationIndex = workflow.indexOf("CD Deploy / Run local deployment");
  assert.notEqual(imagePullIndex, -1);
  assert.notEqual(rehearsalIndex, -1);
  assert.notEqual(productionMutationIndex, -1);
  assert.ok(imagePullIndex < rehearsalIndex);
  assert.ok(rehearsalIndex < productionMutationIndex);

  assert.match(rehearsal, /^set -euo pipefail$/m);
  assert.match(rehearsal, /snapshot-\$\{DEPLOY_SHA\}\.env/);
  assert.match(rehearsal, /docker network create --internal/);
  assert.match(rehearsal, /pg_restore --clean --if-exists --no-owner --no-privileges/);
  assert.match(rehearsal, /org\.opencontainers\.image\.revision/);
  assert.match(rehearsal, /TARGET_IMAGE/);
  assert.match(rehearsal, /PR1_IMAGE/);
  assert.match(rehearsal, /schema_after[^\n]+== 51/);
  assert.match(rehearsal, /ROLLBACK_BACKEND/);
  assert.match(rehearsal, /ROLLBACK_WORKER/);
  assert.match(rehearsal, /readiness=backend:200,back-worker:200/);
  assert.match(rehearsal, /route_statuses=403\/403\/403/);
  assert.match(rehearsal, /Flyway validation error/);
  assert.doesNotMatch(rehearsal, /--publish|-p [0-9]/);
});
