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
  assert.doesNotMatch(composeEnv, /^EASYSUBWAY_DATASOURCE_PASSWORD=/m);
  assert.doesNotMatch(composeEnv, /^EASYSUBWAY_REPORT_UPLOAD_INTENT_SIGNING_KEY=/m);
  assert.match(backendEnv, /^EASYSUBWAY_DATASOURCE_URL=jdbc:postgresql:\/\/postgres:5432\/easysubway$/m);
  assert.match(backendEnv, /^EASYSUBWAY_REPORT_OBJECT_STORAGE_INTERNAL_ENDPOINT=http:\/\/object-storage:9000$/m);
  assert.match(backendEnv, /^EASYSUBWAY_REPORT_UPLOAD_PUBLIC_BASE_URL=https:\/\/uploads.easysubway.example$/m);
  assert.doesNotMatch(backendEnv, /^EASYSUBWAY_OBJECT_STORAGE_ENDPOINT=/m);
  assert.doesNotMatch(backendEnv, /^EASYSUBWAY_POSTGRES_PASSWORD=/m);
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
    prepare(fixtureEnv().replace("EASYSUBWAY_REPORT_OBJECT_STORAGE_INTERNAL_ENDPOINT=http://object-storage:9000", "EASYSUBWAY_REPORT_OBJECT_STORAGE_INTERNAL_ENDPOINT=https://object-storage.easysubway.example")),
    /report object storage internal endpoint must be http:\/\/object-storage:9000/,
  );
  await assert.rejects(
    prepare(fixtureEnv().replace("https://uploads.easysubway.example", "http://object-storage:9000")),
    /public upload URL must be an HTTPS origin/,
  );
});

test("백엔드 SSH 배포 스크립트는 상태, drift, 백업, readiness 롤백 계약을 포함한다", async () => {
  await execFileAsync("bash", ["-n", "tools/deploy/prepare-deployment-env.sh"], { cwd: root });
  await execFileAsync("bash", ["-n", "tools/deploy/deploy-backend.sh"], { cwd: root });
  await execFileAsync("bash", ["-n", "tools/ops/postgres-backup.sh"], { cwd: root });

  const deploy = read("tools/deploy/deploy-backend.sh");
  const backup = read("tools/ops/postgres-backup.sh");

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
  assert.match(deploy, /mc mb --ignore-existing "local\/\$\{REPORT_UPLOAD_BUCKET\}"/);
  assert.match(deploy, /report_upload_bucket_init_failed/);
  assert.ok(deploy.indexOf("wait_stateful_service \"${service}\"") < deploy.indexOf("mc mb --ignore-existing"));
  assert.ok(deploy.indexOf("mc mb --ignore-existing") < deploy.indexOf("backend_id="));
  assert.match(deploy, /managed_image_drift/);
  assert.match(deploy, /printf 'compose\.env\\0'/);
  assert.match(deploy, /printf '\\nbackend\.env\\0'/);
  assert.doesNotMatch(deploy, /sha256sum "\$\{COMPOSE_ENV\}" "\$\{BACKEND_ENV\}" \| sha256sum/);
  assert.match(deploy, /tools\/ops\/postgres-backup\.sh/);
  assert.match(deploy, /EASYSUBWAY_BACKEND_ENV_FILE="\$\{BACKEND_ENV\}"/);
  assert.match(deploy, /up -d --no-deps --no-build backend/);
  assert.match(deploy, /actuator\/health\/readiness/);
  assert.match(deploy, /readiness_failed_rollback_attempted/);
  assert.match(deploy, /diagnostics/);
  assert.match(backup, /pg_restore --list/);
  assert.match(backup, /\.sha256/);

  const cd = read(".github/workflows/cd.yml");
  assert.match(cd, /if \[\[ -n "\$\{EASYSUBWAY_ENV_FILE:-\}" \]\]; then/);
  assert.doesNotMatch(cd, /EASYSUBWAY_ENV_FILE:-\/dev\/null/);
});

test("Compose backend 서비스는 bootJar 기반 이미지와 제한된 바인딩을 사용한다", () => {
  const compose = read("infra/docker-compose.yml");

  assert.match(compose, /\n  backend:\n[\s\S]*?context: \.\.\/backend/);
  assert.match(compose, /image: easysubway-backend:\$\{EASYSUBWAY_BACKEND_IMAGE_TAG:-local\}/);
  assert.match(compose, /com\.easysubway\.jar\.sha256: \$\{EASYSUBWAY_BACKEND_JAR_SHA256:-unknown\}/);
  assert.match(compose, /env_file:\s*\n\s*-\s*\$\{EASYSUBWAY_BACKEND_ENV_FILE:-\.\.\/\.env\.example\}/);
  assert.match(compose, /"\$\{EASYSUBWAY_BACKEND_BIND:-127\.0\.0\.1\}:\$\{EASYSUBWAY_BACKEND_PORT:-8080\}:8080"/);
  assert.match(compose, /max-size: "10m"/);
  assert.match(compose, /postgres:\s*\n\s*condition: service_healthy/);
  assert.match(compose, /object-storage:\s*\n\s*condition: service_healthy/);
});
