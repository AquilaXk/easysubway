import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const workflowPath = ".github/workflows/production-route-v2-capacity-evidence.yml";
const runnerPath = "tools/ops/verify-production-route-v2-capacity.sh";

test("Route V2 capacity evidence는 main-only production approval을 강제한다", async () => {
  const workflow = await readFile(workflowPath, "utf8");

  assert.match(workflow, /workflow_dispatch:/);
  assert.match(workflow, /runs-on:\n\s+- self-hosted\n\s+- easysubway-production/);
  assert.match(workflow, /environment: production/);
  assert.match(workflow, /permissions:\n\s+contents: read/);
  assert.match(workflow, /persist-credentials: false/);
  assert.match(workflow, /timeout-minutes: 30/);
  assert.match(workflow, /cancel-in-progress: false/);
  assert.match(workflow, /group: production-route-v2-capacity-evidence/);
  assert.match(workflow, /EXPECTED_DEPLOYED_SHA: \$\{\{ github\.sha \}\}/);
  assert.match(workflow, /actions\/setup-node@48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e/);
  assert.match(workflow, /node-version: "24"/);
  assert.match(workflow, /bash tools\/ops\/verify-production-route-v2-capacity\.sh/);
  assert.match(
    workflow,
    /if \[\[ "\$\{GITHUB_REF\}" != "refs\/heads\/main" \]\]; then\s+echo "production Route V2 capacity evidence must run from main" >&2\s+exit 1\s+fi/,
  );
});

test("capacity runner는 동일 candidate·격리 load·privacy·closed ingress를 검증한다", async () => {
  const runner = await readFile(runnerPath, "utf8");

  assert.match(runner, /^set -euo pipefail$/m);
  assert.match(runner, /^umask 077$/m);
  assert.match(runner, /EXPECTED_DEPLOYED_SHA/);
  assert.match(runner, /PUBLIC_BASE_URL.*https:\/\/easysubway-api\.aquilaxk\.site/);
  assert.match(runner, /PUBLIC_BASE_URL.*==.*https:\/\/easysubway-api\.aquilaxk\.site/);
  assert.match(runner, /shared\/current-sha/);
  assert.match(runner, /shared\/current-image-digest/);
  assert.match(runner, /org\.opencontainers\.image\.revision/);
  assert.match(runner, /docker network create --internal/);
  assert.match(runner, /gateway_image="\$\(docker inspect --format '\{\{\.Image\}\}' easysubway-route-v2-gateway\)"/);
  assert.match(runner, /gateway image ID is invalid/);
  assert.match(runner, /--cpus 1 --memory 1g --memory-swap 1g --pids-limit 256/);
  assert.match(runner, /clone_db_password/);
  assert.match(runner, /synthetic_secret/);
  assert.match(runner, /synthetic_certificate_digest/);
  assert.doesNotMatch(runner, /range \.Config\.Env/);
  assert.match(runner, /--publish 127\.0\.0\.1::8080 "\$\{expected_image_id\}"/);
  const gatewayRun = runner.match(/docker run -d --name "\$\{clone_gateway\}"[\s\S]*?nginx -g 'daemon off;' >\/dev\/null/)?.[0] ?? "";
  assert.match(gatewayRun, /--cpus 1 --memory 256m --memory-swap 256m --pids-limit 128/);
  assert.match(runner, /profile=normal/);
  assert.match(runner, /profile=burst/);
  assert.match(runner, /profile=unavailable/);
  assert.match(runner, /EASYSUBWAY_ROUTE_V2_SESSION_RATE_PER_MINUTE/);
  assert.match(runner, /EASYSUBWAY_ROUTE_V2_SEARCH_RATE_PER_MINUTE/);
  assert.match(runner, /Retry-After/);
  assert.match(runner, /route_v2_states/);
  assert.match(runner, /route_v2_sessions/);
  assert.match(runner, /Cache-Control/);
  assert.match(runner, /private, no-store/);
  assert.match(runner, /no-store\[\[:space:\]\]\*\\r\?\$/);
  assert.doesNotMatch(runner, /\^Cache-Control: private, no-store'/);
  assert.match(runner, /undeclared_data_transfer_count=0/);
  assert.match(runner, /sensitive_payload_count=0/);
  assert.match(runner, /ingress_closed=true/);
  assert.match(runner, /trap cleanup_on_exit EXIT/);
  assert.match(runner, /departure_time="\$\(node[\s\S]*?snapshot_fresh_until/);
  assert.doesNotMatch(runner, /2026-07-17T15:00:00\+09:00/);
  assert.match(runner, /burst_pids/);
  assert.match(runner, /wait "\$\{burst_pid\}"/);
  assert.match(runner, /application purge scheduler evidence is missing/);
  assert.match(runner, /cleanup_failed/);
  assert.doesNotMatch(runner, /docker rm[^\n]*\|\| true/);
  assert.match(runner, /database_size_bytes/);
  assert.match(runner, /required_copy_bytes/);
  assert.match(runner, /history\.fresh_until::timestamptz AT TIME ZONE 'UTC'/);
  assert.match(runner, /history\.fresh_until::timestamptz > CURRENT_TIMESTAMP/);
  assert.match(runner, /SET fresh_until = TO_CHAR\(\(CURRENT_TIMESTAMP - INTERVAL '1 second'\) AT TIME ZONE 'UTC'/);
  assert.match(runner, /docker_root_dir/);
  assert.match(runner, /dump_available_bytes/);
  assert.match(runner, /docker_available_bytes/);
  assert.match(runner, /EASYSUBWAY_SCHEDULING_ENABLED=true/);
  assert.match(runner, /EASYSUBWAY_ROUTE_V2_STATE_PURGE_INTERVAL_MS=1000/);
  assert.doesNotMatch(runner, /EASYSUBWAY_SCHEDULING_ENABLED=false/);
  assert.doesNotMatch(runner, /WITH states AS \(DELETE FROM route_v2_states/);
  assert.match(runner, /synthetic_purge_remaining/);
  assert.match(runner, /purge_budget_ms=600000/);
  assert.match(runner, /purge_deadline_ms=\$\(\(purge_started_ms \+ purge_budget_ms\)\)/);
  assert.match(runner, /synthetic_purge_remaining="1\|1\|1"\nwhile true; do/);
  assert.doesNotMatch(runner, /synthetic_purge_remaining="1\|1\|1"\nfor _ in \$\(seq 1 120\)/);
  assert.match(runner, /resource_sampler_pid/);
  assert.match(runner, /memory_peak/);
  assert.match(runner, /cpu_peak/);
  assert.match(runner, /backend_memory_peak/);
  assert.match(runner, /gateway_memory_peak/);
  assert.match(runner, /gateway_oom_killed/);
  assert.match(runner, /gateway_restart_count/);
  assert.match(runner, /docker stats[\s\S]*?"\$\{clone_backend\}"[\s\S]*?"\$\{clone_gateway\}"/);
  assert.ok(runner.indexOf("resource_sampler_pid=$!") < runner.indexOf("send_session normal"));
  assert.match(runner, /docker container ls -a/);
  assert.match(runner, /docker volume ls/);
  assert.match(runner, /docker network ls/);
  assert.ok(runner.indexOf("trap - EXIT") < runner.indexOf("### Production Route V2 capacity evidence"));
  assert.match(runner, /profile=normal: PASS, session_requests=\$\{session_rate\}, search_requests=\$\{search_rate\}/);
  assert.doesNotMatch(runner, /upload-artifact|set -x/);
  assert.doesNotMatch(runner, /gh secret set|EASYSUBWAY_ROUTE_V2_INGRESS_ENABLED=true/);
});
