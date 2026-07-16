import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { gunzipSync } from "node:zlib";

const workflowPath = ".github/workflows/production-timetable-snapshot-evidence.yml";
const scriptPath = "tools/ops/verify-production-timetable-snapshot.sh";
const candidatePath = "tools/ops/prepare-timetable-rollback-candidate.mjs";
const applicationPath = "backend/src/main/java/com/easysubway/EasySubwayBackendApplication.java";

test("production timetable evidence는 exact deploy에서 cache와 격리 rollback을 검증한다", async () => {
  const workflow = await readFile(workflowPath, "utf8");
  const script = await readFile(scriptPath, "utf8");
  const candidate = await readFile(candidatePath, "utf8");
  const application = await readFile(applicationPath, "utf8");

  assert.match(workflow, /workflow_dispatch:/);
  assert.match(workflow, /GITHUB_REF[^\n]+refs\/heads\/main[\s\S]*exit 1/);
  assert.doesNotMatch(workflow, /if: github\.ref == 'refs\/heads\/main'/);
  assert.match(workflow, /runs-on:\n\s+- self-hosted\n\s+- easysubway-production/);
  assert.match(workflow, /environment: production/);
  assert.match(workflow, /EXPECTED_DEPLOYED_SHA: \$\{\{ github\.sha \}\}/);
  assert.match(workflow, /bash tools\/ops\/verify-production-timetable-snapshot\.sh/);
  assert.doesNotMatch(workflow, /pull_request|upload-artifact/);

  assert.match(script, /flock -w 300 9/);
  assert.match(script, /current_sha[^\n]+!=[^\n]+EXPECTED_DEPLOYED_SHA/);
  assert.match(script, /runtime_config_image[^\n]+backend_image/);
  assert.match(script, /runtime_image_id[^\n]+expected_image_id/);
  assert.match(script, /shared\/current-image-digest/);
  assert.match(script, /current_image_digest[^\n]+\^sha256:/);
  assert.match(script, /ghcr\.io\/aquilaxk\/easysubway-backend@\$\{current_image_digest\}/);
  assert.match(script, /RepoDigests/);
  assert.match(script, /timetable_snapshot_active/);
  assert.match(script, /history\.fresh_until::timestamptz/);
  assert.match(script, /fresh_until::timestamptz > CURRENT_TIMESTAMP/);
  assert.doesNotMatch(script, /history\.schema_identity, history\.fresh_until/);
  assert.match(script, /replace\(\/\\\.\\d\{3\}Z\$\/, "Z"\)/);
  assert.match(script, /active_identity[^\n]+!=[^\n]+expected_identity/);
  assert.match(script, /history\.source_artifact_sha256/);
  assert.match(script, /history\.completeness_evidence_sha256/);
  assert.match(script, /history\.canonical_pack_sha256/);
  assert.match(script, /history\.canonical_pack_sqlite_sha256/);
  assert.match(script, /history\.canonical_station_set_sha256/);
  assert.match(script, /history\.source_lineage_sha256/);
  assert.match(script, /history\.evidence_hash/);
  assert.match(script, /routeServiceEvidence/);
  assert.match(script, /route V2 timetable cache result=miss/);
  assert.match(script, /route V2 timetable cache result=hit/);
  assert.match(script, /randomBytes\(32\)\.toString\("base64url"\)/);
  assert.match(script, /session_hashes/);
  assert.match(script, /deleted_session_count/);
  assert.match(script, /route_state_ids/);
  assert.match(script, /DELETE FROM route_v2_states/);
  assert.doesNotMatch(script, /printf -v session_token/);
  assert.match(script, /EASYSUBWAY_SCHEDULING_ENABLED=false/);
  assert.match(script, /--publish 127\.0\.0\.1::8080/);
  assert.match(script, /docker port "\$\{cache_app\}" 8080\/tcp/);
  assert.match(script, /curl[^\n]+"\$\{cache_base_url\}/);
  assert.doesNotMatch(script, /docker exec[^\n]+"\$\{cache_app\}"[^\n]+curl/);
  assert.match(application, /@ConditionalOnProperty\([\s\S]*prefix = "easysubway\.scheduling"[\s\S]*matchIfMissing = true[\s\S]*@EnableScheduling/);
  assert.match(script, /pg_database_size\(current_database\(\)\)/);
  assert.match(script, /docker info --format '\{\{\.DockerRootDir\}\}'/);
  assert.match(script, /df -Pk/);
  assert.match(script, /database_size_bytes \* 4 \+ 2147483648/);
  assert.match(script, /dump_available_bytes[\s\S]*docker_available_bytes/);
  const capacityPreflight = script.indexOf('database_size_bytes="$(production_psql');
  assert.ok(capacityPreflight > 0);
  assert.ok(capacityPreflight < script.indexOf("pg_dump --format=custom"));
  assert.ok(capacityPreflight < script.indexOf('docker volume create "${volume}"'));
  assert.match(script, /pg_dump --format=custom/);
  assert.match(script, /pg_restore --clean --if-exists --no-owner --no-privileges/);
  assert.match(script, /issue_2145_reject_trip/);
  assert.match(script, /prepare-timetable-rollback-candidate\.mjs/);
  assert.match(script, /row_to_json/);
  assert.match(script, /transit_stop_times/);
  assert.match(script, /fingerprint_before[^\n]+!=[^\n]+fingerprint_after/);
  assert.doesNotMatch(script, /docker pull|curl .*(github|aquilaxk\.site)/);
  assert.match(candidate, /repositoryRoot/);
  assert.match(candidate, /RUNNER_TEMP/);
  assert.match(candidate, /tmpdir\(\)/);
  assert.match(candidate, /realpath/);
  assert.match(candidate, /path\.relative/);
  assert.match(candidate, /path escapes allowed root/);
});

test("rollback 후보는 현재 seed를 다른 immutable identity로 만든다", async () => {
  const runnerTemp = await mkdtemp(path.join(tmpdir(), "issue-2145-runner-"));
  const output = path.join(runnerTemp, "candidate");
  try {
    execFileSync("node", [
      candidatePath,
      "backend/src/main/resources/timetable/line4-timetable-seed.sql.gz",
      "backend/src/main/resources/timetable/server-timetable-snapshot-evidence.json",
      output,
    ], { env: { ...process.env, RUNNER_TEMP: runnerTemp } });
    const original = JSON.parse(await readFile(
      "backend/src/main/resources/timetable/server-timetable-snapshot-evidence.json",
      "utf8",
    ));
    const candidate = JSON.parse(await readFile(path.join(output, "evidence.json"), "utf8"));
    const seed = await readFile("backend/src/main/resources/timetable/line4-timetable-seed.sql.gz");
    const compressed = await readFile(path.join(output, "candidate.sql.gz"));
    const sqlBytes = gunzipSync(compressed);
    const expectedSql = Buffer.concat([gunzipSync(seed), Buffer.from("SELECT 1;\n")]);
    const sql = sqlBytes.toString("utf8");
    const { evidenceHash, ...withoutHash } = candidate;

    assert.deepEqual(sqlBytes, expectedSql);
    assert.notEqual(candidate.snapshotSha256, original.snapshotSha256);
    assert.match(candidate.snapshotId, /^server-timetable-snapshot-[0-9a-f]{16}$/);
    assert.match(sql, /SELECT 1;\n$/);
    assert.equal(candidate.snapshotSha256, createHash("sha256").update(sqlBytes).digest("hex"));
    assert.equal(candidate.snapshotGzipSha256, createHash("sha256").update(compressed).digest("hex"));
    assert.equal(evidenceHash, createHash("sha256").update(JSON.stringify(withoutHash)).digest("hex"));

    const tamperedEvidence = path.join(output, "tampered-evidence.json");
    await writeFile(tamperedEvidence, JSON.stringify({ ...original, snapshotSha256: "0".repeat(64) }));
    assert.throws(() => execFileSync(
      "node",
      [
        candidatePath,
        "backend/src/main/resources/timetable/line4-timetable-seed.sql.gz",
        tamperedEvidence,
        output,
      ],
      { stdio: "pipe" },
    ));
  } finally {
    await rm(runnerTemp, { recursive: true, force: true });
  }
});
