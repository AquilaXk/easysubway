import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import test from "node:test";

const workflowPath = ".github/workflows/production-route-v2-capacity-evidence.yml";
const runnerPath = "tools/ops/verify-production-route-v2-capacity.sh";
const execFileAsync = promisify(execFile);

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
  const capacityDecoder = await readFile(
    "backend/src/main/java/com/easysubway/route/adapter/out/integrity/CapacityEvidencePlayIntegrityDecoder.java",
    "utf8",
  );

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
  assert.match(runner, /"\$\{expected_image_id\}" >\/dev\/null/);
  assert.doesNotMatch(runner, /--publish 127\.0\.0\.1::8080/);
  assert.doesNotMatch(runner, /--publish 127\.0\.0\.1::8081/);
  assert.doesNotMatch(runner, /docker port "\$\{clone_backend\}"/);
  assert.doesNotMatch(runner, /docker port "\$\{clone_gateway\}"/);
  assert.match(runner, /clone_curl="\$\{prefix\}-curl"/);
  assert.match(runner, /docker run -d --name "\$\{clone_curl\}" --network "\$\{network\}" --user "\$\(id -u\):\$\(id -g\)" --entrypoint sh/);
  assert.doesNotMatch(runner, /--user 0:0/);
  assert.match(runner, /docker exec "\$\{clone_curl\}" curl --version/);
  assert.match(runner, /docker exec "\$\{clone_curl\}" curl/);
  assert.match(runner, /--network-alias gateway/);
  assert.match(runner, /gateway_base="http:\/\/gateway:8081"/);
  const gatewayRun = runner.match(/docker run -d --name "\$\{clone_gateway\}"[\s\S]*?nginx -g 'daemon off;' >\/dev\/null/)?.[0] ?? "";
  assert.match(gatewayRun, /--cpus 1 --memory 256m --memory-swap 256m --pids-limit 128/);
  assert.match(runner, /profile=normal/);
  assert.match(runner, /profile=burst/);
  assert.match(runner, /profile=unavailable/);
  assert.match(runner, /normal search profile did not return exact 200/);
  assert.match(runner, /search burst profile did not return exact 200 before rate limiting/);
  assert.doesNotMatch(runner, /capacity accepts its current 200\/503 contract states/);
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
  assert.match(runner, /generate_series/);
  assert.match(runner, /service_calendars/);
  assert.match(runner, /service_calendar_dates/);
  assert.match(runner, /trips\.service_class = 'ITX_CHEONGCHUN'/);
  assert.match(runner, /fresh_until::timestamptz/);
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
  assert.match(runner, /resource_ready_file/);
  assert.match(runner, /sampled_at_ms="\$\(date \+%s%3N\)"/);
  assert.match(runner, /load_started_ms="\$\(date \+%s%3N\)"/);
  assert.match(runner, /load_finished_ms="\$\(date \+%s%3N\)"/);
  assert.match(runner, /sample_resources\(\)/);
  assert.match(runner, /load_started_ms="\$\(date \+%s%3N\)"\n(?:[^\n]*\n)*?sample_resources/);
  assert.match(runner, /sample_resources\nload_finished_ms="\$\(date \+%s%3N\)"/);
  assert.match(runner, /sampledAtMs >= loadStartedMs && sampledAtMs <= loadFinishedMs/);
  assert.match(runner, /load interval has no resource sample/);
  assert.match(runner, /normal search response has no itinerary/);
  assert.match(runner, /normal search response has no ITX-청춘 ride/);
  assert.match(runner, /normal search response planner identity mismatch/);
  for (const field of [
    "timetableSnapshotSha256",
    "canonicalPackSha256",
    "canonicalPackSqliteSha256",
    "canonicalStationVersion",
    "canonicalStationSetSha256",
    "sourceLineageSha256",
    "evidenceHash",
  ]) {
    assert.match(runner, new RegExp(`identity\\?\\.${field} !== expected\\.${field}`));
  }
  assert.match(runner, /SPRING_PROFILES_ACTIVE=prod,capacity-evidence/);
  assert.match(runner, /EASYSUBWAY_ROUTE_V2_CAPACITY_EVIDENCE_ATTESTATION_KEY/);
  assert.match(runner, /normal session profile did not return exact 200/);
  assert.match(runner, /normal session response is invalid/);
  assert.doesNotMatch(runner, /case "\$\{last_status\}" in\s+403\|503/);
  assert.match(capacityDecoder, /@Profile\("capacity-evidence"\)/);
  assert.match(capacityDecoder, /MessageDigest\.isEqual/);
  assert.match(capacityDecoder, /MEETS_DEVICE_INTEGRITY/);
  // Spring cannot implicitly resolve which of this class's two constructors to
  // autowire (neither is a lone/no-arg constructor), so the @Value-based
  // constructor must be explicitly marked. Without this, bean creation fails
  // with "No default constructor found" and the isolated backend never
  // becomes ready — see #2095 run 29625986367.
  assert.match(capacityDecoder, /@Autowired\s+CapacityEvidencePlayIntegrityDecoder\(/);
  assert.match(runner, /dump_readiness_diagnostics\(\) \{/);
  assert.match(runner, /docker logs --tail 40 "\$\{container\}"/);
  assert.match(runner, /grep -Ev '\^\[A-Za-z_\]\[A-Za-z0-9_\]\*=\|PASSWORD\|SECRET\|_KEY\|PEPPER\|ATTESTATION'/);
  assert.match(runner, /dump_readiness_diagnostics "\$\{clone_backend\}"/);
  assert.match(runner, /dump_readiness_diagnostics "\$\{clone_gateway\}"/);
  assert.match(runner, /timetable snapshot identity is invalid/);
  assert.match(runner, /normal_state_count_before/);
  assert.match(runner, /normal_state_count_after/);
  assert.match(runner, /normal search profile did not persist one state per request/);
  assert.match(runner, /synthetic credential appeared in service logs/);
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

test("capacity runner dotenv parser는 배포 parser와 동일하게 외부 따옴표를 제거한다", async () => {
  const tempDir = await mkdtemp(path.join(os.tmpdir(), "route-capacity-env-"));
  const envPath = path.join(tempDir, "compose.env");
  try {
    await writeFile(envPath, [
      'EASYSUBWAY_ROUTE_V2_INGRESS_ENABLED="false"',
      "EASYSUBWAY_ROUTE_V2_SESSION_RATE_PER_MINUTE='5'",
      "",
    ].join("\n"));
    const ingress = await execFileAsync("bash", [runnerPath, "--test-read-env-value", envPath, "EASYSUBWAY_ROUTE_V2_INGRESS_ENABLED"]);
    const rate = await execFileAsync("bash", [runnerPath, "--test-read-env-value", envPath, "EASYSUBWAY_ROUTE_V2_SESSION_RATE_PER_MINUTE"]);
    assert.equal(ingress.stdout, "false\n");
    assert.equal(rate.stdout, "5\n");
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
});

test("capacity runner dotenv parser는 중복 정의된 키를 fail-closed로 거부한다", async () => {
  const tempDir = await mkdtemp(path.join(os.tmpdir(), "route-capacity-env-dup-"));
  const envPath = path.join(tempDir, "compose.env");
  try {
    await writeFile(envPath, [
      "EASYSUBWAY_ROUTE_V2_SESSION_RATE_PER_MINUTE=5",
      "EASYSUBWAY_ROUTE_V2_SESSION_RATE_PER_MINUTE=99",
      "",
    ].join("\n"));
    await assert.rejects(
      execFileAsync("bash", [
        runnerPath,
        "--test-read-env-value",
        envPath,
        "EASYSUBWAY_ROUTE_V2_SESSION_RATE_PER_MINUTE",
      ]),
    );
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
});
