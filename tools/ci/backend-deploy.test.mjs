import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, readFile, stat, writeFile } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";

const root = process.cwd();
const execFileAsync = promisify(execFile);

function read(relativePath) {
  return readFileSync(path.join(root, relativePath), "utf8");
}

function fixtureEnv() {
  return read("tools/ci/fixtures/deployment-prod-valid.env");
}

async function prepare(source) {
  const dir = await mkdtemp(path.join(tmpdir(), "easysubway-deploy-env-"));
  const sourceFile = path.join(dir, "source.env");
  const outputDir = path.join(dir, "prepared");
  await writeFile(sourceFile, source);
  await execFileAsync("bash", [
    "tools/deploy/prepare-deployment-env.sh",
    sourceFile,
    "tools/deploy/compose-server-env.allowlist",
    "tools/deploy/backend-app-env.allowlist",
    outputDir,
  ], { cwd: root });
  return outputDir;
}

test("배포 env 준비는 Compose 서버 env와 backend 앱 env를 분리한다", async () => {
  const outputDir = await prepare(fixtureEnv());
  const composeEnv = await readFile(path.join(outputDir, "compose.env"), "utf8");
  const backendEnv = await readFile(path.join(outputDir, "backend.env"), "utf8");
  const composeMode = (await stat(path.join(outputDir, "compose.env"))).mode & 0o777;
  const backendMode = (await stat(path.join(outputDir, "backend.env"))).mode & 0o777;

  assert.match(composeEnv, /^EASYSUBWAY_BACKEND_IMAGE_TAG=fixture$/m);
  assert.match(composeEnv, /^EASYSUBWAY_BACKEND_JAR_SHA256=fixture$/m);
  assert.match(composeEnv, /^EASYSUBWAY_POSTGRES_PORT=15432$/m);
  assert.doesNotMatch(composeEnv, /^EASYSUBWAY_PUSH_DELIVERY_ENABLED=/m);
  assert.doesNotMatch(composeEnv, /^EASYSUBWAY_DATASOURCE_PASSWORD=/m);
  assert.doesNotMatch(composeEnv, /^EASYSUBWAY_REPORT_UPLOAD_INTENT_SIGNING_KEY=/m);
  assert.match(backendEnv, /^EASYSUBWAY_DATASOURCE_URL=jdbc:postgresql:\/\/postgres:5432\/easysubway$/m);
  assert.match(backendEnv, /^EASYSUBWAY_SEOUL_TOPIS_SERVICE_KEY=prod-topis-service-key$/m);
  assert.match(backendEnv, /^EASYSUBWAY_REPORT_OBJECT_STORAGE_INTERNAL_ENDPOINT=http:\/\/object-storage:9000$/m);
  assert.match(backendEnv, /^EASYSUBWAY_REPORT_UPLOAD_PUBLIC_BASE_URL=https:\/\/uploads.easysubway.example$/m);
  assert.match(backendEnv, /^EASYSUBWAY_REPORT_ABUSE_WINDOW_SECONDS=45$/m);
  assert.match(backendEnv, /^EASYSUBWAY_REPORT_ABUSE_UPLOAD_INTENT_LIMIT=30$/m);
  assert.match(backendEnv, /^EASYSUBWAY_REPORT_ABUSE_UPLOAD_CLAIM_LIMIT=45$/m);
  assert.match(backendEnv, /^EASYSUBWAY_REPORT_ABUSE_REPORT_SUBMIT_LIMIT=12$/m);
  assert.match(backendEnv, /^EASYSUBWAY_REPORT_ABUSE_STATUS_LIMIT=90$/m);
  assert.match(backendEnv, /^EASYSUBWAY_REPORT_ABUSE_CONFIRM_LIMIT=15$/m);
  assert.match(backendEnv, /^EASYSUBWAY_REPORT_ABUSE_MAX_COUNTER_KEYS=2048$/m);
  assert.match(backendEnv, /^EASYSUBWAY_REPORT_ABUSE_STORE_MODE=local$/m);
  assert.match(backendEnv, /^EASYSUBWAY_ADMIN_BASIC_AUTH_ENABLED=false$/m);
  assert.match(backendEnv, /^EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_OWNER=$/m);
  assert.match(backendEnv, /^EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_EXPIRES_AT=$/m);
  assert.doesNotMatch(backendEnv, /^EASYSUBWAY_OBJECT_STORAGE_ENDPOINT=/m);
  assert.doesNotMatch(backendEnv, /^EASYSUBWAY_POSTGRES_PASSWORD=/m);
  assert.doesNotMatch(backendEnv, /^EASYSUBWAY_ALERT_SMTP_PASSWORD=/m);
  assert.equal(composeMode, 0o600);
  assert.equal(backendMode, 0o600);
});

test("배포 env 준비는 중복, interpolation, 내부 공개 URL을 차단한다", async () => {
  await assert.rejects(
    prepare(`${fixtureEnv()}EASYSUBWAY_ADMIN_USERNAME=duplicate\n`),
    /duplicate dotenv key: EASYSUBWAY_ADMIN_USERNAME/,
  );
  await assert.rejects(
    prepare(fixtureEnv().replace("EASYSUBWAY_ADMIN_PASSWORD=prod-admin-password", "EASYSUBWAY_ADMIN_PASSWORD=$PASSWORD")),
    /cross-key interpolation is not allowed: EASYSUBWAY_ADMIN_PASSWORD/,
  );
  await assert.rejects(
    prepare(fixtureEnv().replace("jdbc:postgresql://postgres:5432/easysubway", "jdbc:postgresql://localhost:5432/easysubway")),
    /datasource must target postgres:5432 inside Compose/,
  );
  await assert.rejects(
    prepare(fixtureEnv().replace("EASYSUBWAY_POSTGRES_PORT=15432", "EASYSUBWAY_POSTGRES_PORT=5432")),
    /postgres host port 5432 is reserved on the production host/,
  );
  await assert.rejects(
    prepare(fixtureEnv().replace("EASYSUBWAY_DATASOURCE_PASSWORD=prod-postgres-password", "EASYSUBWAY_DATASOURCE_PASSWORD=wrong-password")),
    /datasource password must match Compose postgres password/,
  );
  await assert.rejects(
    prepare(fixtureEnv().replace("EASYSUBWAY_REPORT_OBJECT_STORAGE_INTERNAL_ENDPOINT=http://object-storage:9000", "EASYSUBWAY_REPORT_OBJECT_STORAGE_INTERNAL_ENDPOINT=https://object-storage.easysubway.example")),
    /report object storage internal endpoint must be http:\/\/object-storage:9000/,
  );
  await assert.rejects(
    prepare(fixtureEnv().replace("https://uploads.easysubway.example", "http://object-storage:9000")),
    /public upload URL must be an HTTPS origin/,
  );
  await assert.rejects(
    prepare(fixtureEnv().replace("https://uploads.easysubway.example", "https://LOCALHOST")),
    /public upload URL must not be internal/,
  );
  await assert.rejects(
    prepare(`${fixtureEnv()}EASYSUBWAY_ALERT_EMAIL_ENABLED=true\nEASYSUBWAY_ALERTMANAGER_EXTERNAL_URL=http://127.0.0.1:9093\nEASYSUBWAY_ALERT_EMAIL_TO=ops@example.com\nEASYSUBWAY_ALERT_EMAIL_FROM=alerts@example.com\nEASYSUBWAY_ALERT_SMTP_SMARTHOST=smtp.example.com:587\nEASYSUBWAY_ALERT_SMTP_USERNAME=alerts@example.com\nEASYSUBWAY_ALERT_SMTP_PASSWORD=secret\n`),
    /alertmanager external URL must be an HTTPS URL/,
  );
  await assert.rejects(
    prepare(`${fixtureEnv()}EASYSUBWAY_ALERT_EMAIL_ENABLED=true\nEASYSUBWAY_ALERTMANAGER_EXTERNAL_URL=https://alertmanager\nEASYSUBWAY_ALERT_EMAIL_TO=ops@example.com\nEASYSUBWAY_ALERT_EMAIL_FROM=alerts@example.com\nEASYSUBWAY_ALERT_SMTP_SMARTHOST=smtp.example.com:587\nEASYSUBWAY_ALERT_SMTP_USERNAME=alerts@example.com\nEASYSUBWAY_ALERT_SMTP_PASSWORD=secret\n`),
    /alertmanager external URL must not be internal/,
  );
  const outputDir = await prepare(`${fixtureEnv()}EASYSUBWAY_ALERT_EMAIL_ENABLED=true\nEASYSUBWAY_ALERTMANAGER_EXTERNAL_URL=https://ops.easysubway.example/alertmanager\nEASYSUBWAY_ALERT_EMAIL_TO=ops@example.com\nEASYSUBWAY_ALERT_EMAIL_FROM=alerts@example.com\nEASYSUBWAY_ALERT_SMTP_SMARTHOST=smtp.example.com:587\nEASYSUBWAY_ALERT_SMTP_USERNAME=alerts@example.com\nEASYSUBWAY_ALERT_SMTP_PASSWORD=secret\nEASYSUBWAY_ALERT_SMTP_REQUIRE_TLS=true\n`);
  const composeEnv = await readFile(path.join(outputDir, "compose.env"), "utf8");
  const backendEnv = await readFile(path.join(outputDir, "backend.env"), "utf8");
  assert.match(composeEnv, /^EASYSUBWAY_ALERT_EMAIL_ENABLED=true$/m);
  assert.match(composeEnv, /^EASYSUBWAY_ALERTMANAGER_EXTERNAL_URL=https:\/\/ops\.easysubway\.example\/alertmanager$/m);
  assert.match(composeEnv, /^EASYSUBWAY_ALERT_SMTP_PASSWORD=secret$/m);
  assert.doesNotMatch(backendEnv, /^EASYSUBWAY_ALERT_SMTP_PASSWORD=/m);
});

test("백엔드 SSH 배포 스크립트는 상태, drift, 백업, readiness 롤백 계약을 포함한다", async () => {
  await execFileAsync("bash", ["-n", "tools/deploy/prepare-deployment-env.sh"], { cwd: root });
  await execFileAsync("bash", ["-n", "tools/deploy/deploy-backend.sh"], { cwd: root });
  await execFileAsync("bash", ["-n", "tools/ops/postgres-backup.sh"], { cwd: root });

  const deploy = read("tools/deploy/deploy-backend.sh");
  const backup = read("tools/ops/postgres-backup.sh");

  assert.match(deploy, /^set -Eeuo pipefail$/m);
  assert.match(deploy, /flock 9/);
  assert.match(deploy, /"\$\{DEPLOY_ROOT\}"\/incoming\/\*/);
  assert.match(deploy, /deployment-state\.env/);
  assert.match(deploy, /last-result\.env/);
  assert.match(deploy, /git merge-base --is-ancestor "\$\{DEPLOY_SHA\}" origin\/main/);
  assert.match(deploy, /git merge-base --is-ancestor "\$\{current_sha\}" "\$\{DEPLOY_SHA\}"/);
  const checkoutTarget = 'git checkout --detach "${DEPLOY_SHA}"';
  const composeConfig = 'compose "${BACKEND_ENV}" "${COMPOSE_ENV}" "${DEPLOY_SHA}" config --quiet';
  assert.equal(deploy.match(/git checkout --detach "\$\{DEPLOY_SHA\}"/g)?.length, 1);
  assert.ok(deploy.indexOf(checkoutTarget) < deploy.indexOf(composeConfig));
  assert.match(deploy, /sha256sum -c/);
  assert.match(deploy, /up -d --no-build postgres object-storage/);
  assert.doesNotMatch(deploy, /timeout [0-9]+ compose/);
  assert.match(deploy, /timeout 600 docker compose/);
  assert.match(deploy, /timeout 900 docker compose/);
  assert.match(deploy, /wait_stateful_service/);
  assert.match(deploy, /report_upload_bucket="\$\(read_env_value "\$\{BACKEND_ENV\}" EASYSUBWAY_REPORT_UPLOAD_BUCKET\)"/);
  assert.match(deploy, /stop_legacy_backend_service\(\)/);
  assert.match(deploy, /restore_legacy_backend_service\(\)/);
  assert.match(deploy, /systemctl stop "\$\{LEGACY_BACKEND_UNIT\}"/);
  assert.match(deploy, /systemctl disable "\$\{LEGACY_BACKEND_UNIT\}"/);
  assert.match(deploy, /systemctl start "\$\{LEGACY_BACKEND_UNIT\}"/);
  assert.match(deploy, /legacy_backend_still_running/);
  assert.match(deploy, /legacy_backend_was_active=1/);
  assert.match(deploy, /legacy_backend_was_enabled=1/);
  assert.match(deploy, /legacy_restore_on_error=1/);
  assert.match(deploy, /restore_legacy_on_unhandled_error\(\)/);
  assert.match(deploy, /restore_legacy_on_interruption\(\)/);
  assert.match(deploy, /trap restore_legacy_on_unhandled_error ERR/);
  assert.match(deploy, /trap 'restore_legacy_on_interruption INT' INT/);
  assert.match(deploy, /trap 'restore_legacy_on_interruption TERM' TERM/);
  assert.match(deploy, /trap 'restore_legacy_on_interruption HUP' HUP/);
  assert.match(deploy, /legacy_restore_unhandled_error/);
  const unhandledRestoreTrap = deploy.slice(
    deploy.indexOf("restore_legacy_on_unhandled_error()"),
    deploy.indexOf("stop_legacy_backend_service()"),
  );
  assert.match(unhandledRestoreTrap, /legacy_restore_unhandled_error"[\s\S]*write_phase "interrupted"/);
  assert.doesNotMatch(unhandledRestoreTrap, /write_phase "completed"/);
  assert.match(deploy, /legacy_restore_interrupted_int/);
  assert.match(deploy, /legacy_restore_interrupted_term/);
  assert.match(deploy, /legacy_restore_interrupted_hup/);
  assert.match(deploy, /legacy_restore_attempted/);
  assert.match(deploy, /legacy_restore_failed/);
  assert.match(deploy, /legacy_backend_still_running"[\s\S]*write_phase "completed"/);
  assert.match(deploy, /mc alias set local http:\/\/127\.0\.0\.1:9000 "\$\{MINIO_ROOT_USER\}" "\$\{MINIO_ROOT_PASSWORD\}"/);
  assert.match(deploy, /mc mb --ignore-existing "local\/\$\{REPORT_UPLOAD_BUCKET\}"/);
  assert.match(deploy, /report_upload_bucket_init_failed/);
  const legacyStopCall = "\nstop_legacy_backend_service\n";
  const legacyStopCallIndex = deploy.lastIndexOf(legacyStopCall);
  assert.notEqual(legacyStopCallIndex, -1);
  assert.ok(deploy.indexOf("wait_stateful_service \"${service}\"") < deploy.indexOf("mc mb --ignore-existing"));
  assert.ok(deploy.indexOf("mc alias set local") < deploy.indexOf("mc mb --ignore-existing"));
  assert.ok(deploy.indexOf("mc mb --ignore-existing") < deploy.indexOf("backend_id="));
  assert.ok(deploy.indexOf("backend_id=") < legacyStopCallIndex);
  assert.ok(deploy.indexOf("timeout 300 tools/ops/postgres-backup.sh") < legacyStopCallIndex);
  assert.ok(legacyStopCallIndex < deploy.indexOf('write_phase "started"'));
  assert.ok(legacyStopCallIndex < deploy.indexOf('mv -Tf "${SHARED_DIR}/current-env.next"'));
  assert.ok(legacyStopCallIndex < deploy.indexOf('if ! compose "${SHARED_DIR}/current-env/backend.env"'));
  assert.ok(legacyStopCallIndex < deploy.indexOf("trap restore_legacy_on_unhandled_error ERR"));
  assert.ok(legacyStopCallIndex < deploy.indexOf("trap 'restore_legacy_on_interruption TERM' TERM"));
  const legacyRestoreDisableIndex = deploy.lastIndexOf("legacy_restore_on_error=0");
  assert.ok(deploy.indexOf('fail_backend_deployment "readiness_failed"') < legacyRestoreDisableIndex);
  assert.ok(legacyRestoreDisableIndex < deploy.indexOf('printf \'%s\\n\' "${DEPLOY_SHA}" > "${SHARED_DIR}/current-sha"'));
  assert.ok(deploy.indexOf("trap - ERR INT TERM HUP") < deploy.indexOf('printf \'%s\\n\' "${DEPLOY_SHA}" > "${SHARED_DIR}/current-sha"'));
  assert.match(deploy, /managed_image_drift/);
  assert.match(deploy, /printf 'compose\.env\\0'/);
  assert.match(deploy, /printf '\\nbackend\.env\\0'/);
  assert.doesNotMatch(deploy, /sha256sum "\$\{COMPOSE_ENV\}" "\$\{BACKEND_ENV\}" \| sha256sum/);
  assert.match(deploy, /tools\/ops\/postgres-backup\.sh/);
  assert.match(deploy, /EASYSUBWAY_BACKEND_ENV_FILE="\$\{BACKEND_ENV\}"/);
  assert.match(deploy, /RUNTIME_SERVICES=\(backend back-worker\)/);
  assert.match(deploy, /OBSERVABILITY_SERVICES=\(public-edge-probe docker-runtime-probe alertmanager prometheus loki grafana\)/);
  assert.match(deploy, /EASYSUBWAY_ALERTMANAGER_CONFIG_FILE=/);
  assert.match(deploy, /write_alertmanager_config "\$\{tmp_env_set\}\/alertmanager\.yml"/);
  assert.match(deploy, /chmod 600 "\$\{tmp_env_set\}\/compose\.env" "\$\{tmp_env_set\}\/backend\.env" "\$\{tmp_env_set\}\/alertmanager\.yml" "\$\{tmp_env_set\}\/metadata\.env"/);
  assert.match(deploy, /compose_services_running\(\)/);
  assert.match(deploy, /compose_services_running "\$\{BACKEND_ENV\}" "\$\{COMPOSE_ENV\}" "\$\{DEPLOY_SHA\}" "\$\{RUNTIME_SERVICES\[@\]\}" "\$\{OBSERVABILITY_SERVICES\[@\]\}"/);
  assert.match(deploy, /same_sha_same_env_services_ready/);
  assert.doesNotMatch(deploy, /same_sha_same_env_ready/);
  assert.match(deploy, /up -d --no-deps --no-build "\$\{RUNTIME_SERVICES\[@\]\}"/);
  assert.match(deploy, /--profile observability up -d --no-build --force-recreate "\$\{OBSERVABILITY_SERVICES\[@\]\}"/);
  assert.match(deploy, /fail_backend_deployment\(\)/);
  assert.match(deploy, /fail_backend_deployment "backend_start_failed"/);
  assert.match(deploy, /fail_backend_deployment "observability_start_failed"/);
  assert.match(deploy, /"\$\{detail\}_rollback_attempted"/);
  assert.match(deploy, /"\$\{detail\}_rollback_unavailable"/);
  assert.match(deploy, /"\$\{current_sha\}" --profile observability up -d --no-build --force-recreate "\$\{OBSERVABILITY_SERVICES\[@\]\}" \|\| true/);
  assert.match(deploy, /rm -f -s "\$\{RUNTIME_SERVICES\[@\]\}"/);
  assert.match(deploy, /logs --no-color --tail=200 "\$\{RUNTIME_SERVICES\[@\]\}"/);
  assert.match(deploy, /if ! compose "\$\{SHARED_DIR\}\/current-env\/backend\.env" "\$\{SHARED_DIR\}\/current-env\/compose\.env" "\$\{DEPLOY_SHA\}" up -d --no-deps --no-build "\$\{RUNTIME_SERVICES\[@\]\}"; then/);
  assert.match(deploy, /actuator\/health\/readiness/);
  assert.match(deploy, /fail_backend_deployment "readiness_failed"/);
  assert.match(deploy, /diagnostics/);
  assert.match(backup, /pg_restore --list/);
  assert.doesNotMatch(backup, /pg_restore --list -/);
  assert.match(backup, /\.sha256/);

  const cd = read(".github/workflows/cd.yml");
  assert.match(cd, /uses: actions\/setup-java@be666c2fcd27ec809703dec50e508c2fdc7f6654/);
  assert.doesNotMatch(cd, /uses: actions\/setup-java@be66141d4002b0e783cc31e5449d3f9f3267ffd9/);
  assert.match(cd, /if \[\[ -n "\$\{EASYSUBWAY_ENV_FILE:-\}" \]\]; then/);
  assert.doesNotMatch(cd, /EASYSUBWAY_ENV_FILE:-\/dev\/null/);
});

test("Compose backend 서비스는 bootJar 기반 이미지와 제한된 바인딩을 사용한다", () => {
  const compose = read("infra/docker-compose.yml");

  assert.match(compose, /\n  backend:\n[\s\S]*?context: \.\.\/backend/);
  assert.match(compose, /image: easysubway-backend:\$\{EASYSUBWAY_BACKEND_IMAGE_TAG:-local\}/);
  assert.match(compose, /com\.easysubway\.jar\.sha256: \$\{EASYSUBWAY_BACKEND_JAR_SHA256:-unknown\}/);
  assert.match(compose, /env_file:\s*\n\s*-\s*\$\{EASYSUBWAY_BACKEND_ENV_FILE:-\.\.\/\.env\.example\}/);
  assert.match(compose, /EASYSUBWAY_DATASOURCE_URL: jdbc:postgresql:\/\/postgres:5432\/\$\{EASYSUBWAY_POSTGRES_DB:-easysubway\}/);
  assert.match(compose, /EASYSUBWAY_REPORT_OBJECT_STORAGE_INTERNAL_ENDPOINT: http:\/\/object-storage:9000/);
  assert.match(compose, /"\$\{EASYSUBWAY_BACKEND_BIND:-127\.0\.0\.1\}:\$\{EASYSUBWAY_BACKEND_PORT:-8080\}:8080"/);
  assert.match(compose, /max-size: "10m"/);
  assert.match(compose, /postgres:\s*\n\s*condition: service_healthy/);
  assert.match(compose, /object-storage:\s*\n\s*condition: service_healthy/);
});
