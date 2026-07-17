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
  assert.match(runner, /shared\/current-sha/);
  assert.match(runner, /shared\/current-image-digest/);
  assert.match(runner, /org\.opencontainers\.image\.revision/);
  assert.match(runner, /docker network create --internal/);
  assert.match(runner, /--cpus 1 --memory 1g --memory-swap 1g --pids-limit 256/);
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
  assert.match(runner, /undeclared_data_transfer_count=0/);
  assert.match(runner, /sensitive_payload_count=0/);
  assert.match(runner, /ingress_closed=true/);
  assert.match(runner, /trap cleanup_on_exit EXIT/);
  assert.match(runner, /departure_time="\$\(node[\s\S]*?snapshot_fresh_until/);
  assert.doesNotMatch(runner, /2026-07-17T15:00:00\+09:00/);
  assert.match(runner, /burst_pids/);
  assert.match(runner, /wait "\$\{burst_pid\}"/);
  assert.match(runner, /expired_baseline/);
  assert.match(runner, /expected_purged_states/);
  assert.doesNotMatch(runner, /purged_counts.*1\|1\|0/);
  assert.match(runner, /cleanup_failed/);
  assert.doesNotMatch(runner, /docker rm[^\n]*\|\| true/);
  assert.ok(runner.indexOf("trap - EXIT") < runner.indexOf("### Production Route V2 capacity evidence"));
  assert.match(runner, /profile=normal: PASS, session_requests=\$\{session_rate\}, search_requests=\$\{search_rate\}/);
  assert.doesNotMatch(runner, /upload-artifact|set -x/);
  assert.doesNotMatch(runner, /gh secret set|EASYSUBWAY_ROUTE_V2_INGRESS_ENABLED=true/);
});
