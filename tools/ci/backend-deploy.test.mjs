import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test, { afterEach } from "node:test";
import { promisify } from "node:util";
import {
  DEFAULT_MARGIN_SECONDS,
  evaluateSnapshotFreshnessPrecheck,
} from "../deploy/check-snapshot-freshness-precheck.mjs";

const root = process.cwd();
const execFileAsync = promisify(execFile);
const ASSET_ORIGIN = "https://ads-assets.fixture.test-only.dev";
const ASSET_ORIGIN_LINE = `EASYSUBWAY_ADS_ASSET_ORIGIN=${ASSET_ORIGIN}`;
const EVENT_DAILY_CAP_LINE = "EASYSUBWAY_ADS_EVENT_DAILY_CAP=1000000";
const BACKEND_BIND_LINE = "EASYSUBWAY_BACKEND_BIND=127.0.0.1";
const TRUSTED_PROXY_LINE = "EASYSUBWAY_TRUSTED_PROXY_CIDRS=172.16.0.0/12";
const ROUTE_V2_ORIGIN_SECRET_LINE = `EASYSUBWAY_ROUTE_V2_ORIGIN_SECRET=${"O".repeat(43)}`;
const ROUTE_V2_CERTIFICATE_LINE = `EASYSUBWAY_ROUTE_V2_PLAY_INTEGRITY_CERTIFICATE_SHA256=${"A".repeat(43)}`;
const deploymentTempDirs = new Set();

function read(relativePath) {
  return readFileSync(path.join(root, relativePath), "utf8");
}

function fixtureEnv() {
  return read("tools/ci/fixtures/deployment-prod-valid.env");
}

function dotenvValues(source) {
  return Object.fromEntries(source.split("\n").filter(Boolean).map((line) => {
    const separator = line.indexOf("=");
    return [line.slice(0, separator), line.slice(separator + 1)];
  }));
}

afterEach(async () => {
  await Promise.all(
    [...deploymentTempDirs].map((dir) => rm(dir, { recursive: true, force: true })),
  );
  deploymentTempDirs.clear();
});

function withAssetOrigin(origin) {
  return fixtureEnv().replace(
    ASSET_ORIGIN_LINE,
    `EASYSUBWAY_ADS_ASSET_ORIGIN=${origin}`,
  );
}

function withEventDailyCap(value) {
  return fixtureEnv().replace(EVENT_DAILY_CAP_LINE, `EASYSUBWAY_ADS_EVENT_DAILY_CAP=${value}`);
}

function withBackendBind(value) {
  return fixtureEnv().replace(BACKEND_BIND_LINE, `EASYSUBWAY_BACKEND_BIND=${value}`);
}

async function assertInvalidAssetOrigin(origin) {
  await assert.rejects(
    prepare(withAssetOrigin(origin)),
    (error) => {
      const stderr = String(error.stderr ?? "");
      assert.equal(
        stderr,
        "invalid public HTTPS origin: EASYSUBWAY_ADS_ASSET_ORIGIN\n",
      );
      return true;
    },
  );
}

async function prepare(source) {
  const dir = await mkdtemp(path.join(tmpdir(), "easysubway-deploy-env-"));
  deploymentTempDirs.add(dir);
  try {
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
  } catch (error) {
    try {
      await rm(dir, { recursive: true, force: true });
      deploymentTempDirs.delete(dir);
    } catch {
      // Preserve the original prepare error; afterEach retries registered dirs.
    }
    throw error;
  }
}

test("광고 asset origin은 backend env에만 변형 없이 전달한다", async () => {
  const outputDir = await prepare(fixtureEnv());
  const composeEnv = await readFile(path.join(outputDir, "compose.env"), "utf8");
  const backendEnv = await readFile(path.join(outputDir, "backend.env"), "utf8");
  const assetOriginPrefix = "EASYSUBWAY_ADS_ASSET_ORIGIN=";

  assert.ok(
    backendEnv.split("\n").includes(ASSET_ORIGIN_LINE),
    "backend.env must contain the exact asset origin line",
  );
  assert.ok(
    !composeEnv.split("\n").includes(ASSET_ORIGIN_LINE),
    "compose.env must not contain the asset origin line",
  );
  assert.equal(
    backendEnv.split("\n").filter((line) => line.startsWith(assetOriginPrefix)).length,
    1,
    "backend.env must contain exactly one asset origin key",
  );
  assert.equal(
    composeEnv.split("\n").filter((line) => line.startsWith(assetOriginPrefix)).length,
    0,
    "compose.env must not contain an asset origin key",
  );
});

test("callback reconciliation catalog trust 설정은 backend env에 전달한다", async () => {
  const source = `${fixtureEnv()}\nEASYSUBWAY_DATAPACK_CATALOG_BASE_URL=https://datapacks.example.test\nEASYSUBWAY_DATAPACK_SIGNING_KEY_ID=production-v1\n`;
  const outputDir = await prepare(source);
  const backendEnv = await readFile(path.join(outputDir, "backend.env"), "utf8");
  const composeEnv = await readFile(path.join(outputDir, "compose.env"), "utf8");
  const sourceValues = dotenvValues(source);
  const backendValues = dotenvValues(backendEnv);

  for (const name of [
    "EASYSUBWAY_DATAPACK_CATALOG_BASE_URL",
    "EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_PEM",
    "EASYSUBWAY_DATAPACK_SIGNING_KEY_ID",
  ]) {
    assert.ok(Object.hasOwn(sourceValues, name), `${name} is required in source`);
    assert.ok(Object.hasOwn(backendValues, name), `${name} is required in backend.env`);
    assert.equal(backendValues[name], sourceValues[name]);
    assert.doesNotMatch(composeEnv, new RegExp(`^${name}=`, "m"));
  }
});

test("광고 asset origin production preflight는 unsafe 값을 차단한다", async () => {
  await assert.rejects(
    prepare(fixtureEnv().replace(`${ASSET_ORIGIN_LINE}\n`, "")),
    /required deployment env is empty: EASYSUBWAY_ADS_ASSET_ORIGIN/,
  );
  await assert.rejects(
    prepare(withAssetOrigin("")),
    /required deployment env is empty: EASYSUBWAY_ADS_ASSET_ORIGIN/,
  );
  await assert.rejects(
    prepare(`${fixtureEnv()}${ASSET_ORIGIN_LINE}\n`),
    /duplicate dotenv key: EASYSUBWAY_ADS_ASSET_ORIGIN/,
  );

  for (const origin of [
    " ",
    "http://ads-assets.fixture.easysubway.example",
    "https://user@ads-assets.fixture.easysubway.example",
    "https://ads-assets.fixture.easysubway.example/ads",
    "https://ads-assets.fixture.easysubway.example?revision=1",
    "https://ads-assets.fixture.easysubway.example#creative",
    "https://localhost",
    "https://127.0.0.1",
    `https://${"a".repeat(64)}.example`,
    `https://${["a", "b", "c", "d"].map((label) => label.repeat(63)).join(".")}`,
    "https://127.1",
    "https://0x7f.1",
    "https://[::1]",
    "https://10.0.0.1",
    "https://object-storage",
    "https://assets.internal",
    "https://assets.home.arpa",
    "https://1.0.0.127.in-addr.arpa",
    "https://b.a.9.8.7.6.5.0.ip6.arpa",
    "https://resolver.arpa",
    "https://assets.onion",
    "https://assets.alt",
    "https://assets.easysubway.example",
    "https://assets.easysubway.invalid",
    "https://assets.easysubway.test",
    "https://example.com",
    "https://assets.example.com",
    "https://example.net",
    "https://assets.example.net",
    "https://example.org",
    "https://assets.example.org",
    "https://assets.placeholder.test-only.dev",
    "https://assets.todo.test-only.dev",
    "https://-assets.test-only.dev",
    "https://assets.test-only.dev:0",
    "https://assets.test-only.dev:08",
    "https://assets.test-only.dev:65536",
  ]) {
    await assertInvalidAssetOrigin(origin);
  }

  for (const origin of [
    `${ASSET_ORIGIN}/`,
    "https://ads-assets.fixture.test-only.dev:8443",
    `https://${"a".repeat(63)}.127.test-only.dev`,
  ]) {
    const outputDir = await prepare(withAssetOrigin(origin));
    const backendEnv = await readFile(path.join(outputDir, "backend.env"), "utf8");
    assert.ok(
      backendEnv.split("\n").includes(`EASYSUBWAY_ADS_ASSET_ORIGIN=${origin}`),
      "backend.env must preserve an allowed origin exactly",
    );
  }
});

test("광고 event daily cap은 positive PostgreSQL INTEGER로 backend env에만 전달한다", async () => {
  const outputDir = await prepare(fixtureEnv());
  const composeEnv = await readFile(path.join(outputDir, "compose.env"), "utf8");
  const backendEnv = await readFile(path.join(outputDir, "backend.env"), "utf8");
  assert.match(backendEnv, /^EASYSUBWAY_ADS_EVENT_DAILY_CAP=1000000$/m);
  assert.doesNotMatch(composeEnv, /^EASYSUBWAY_ADS_EVENT_DAILY_CAP=/m);

  for (const value of ["", "0", "-1", "1.5", "value", "2147483648", "99999999999999999999"]) {
    await assert.rejects(
      prepare(withEventDailyCap(value)),
      /invalid positive integer: EASYSUBWAY_ADS_EVENT_DAILY_CAP/,
    );
  }
  await assert.rejects(
    prepare(fixtureEnv().replace(`${EVENT_DAILY_CAP_LINE}\n`, "")),
    /required deployment env is empty: EASYSUBWAY_ADS_EVENT_DAILY_CAP/,
  );
});

test("production backend bind는 loopback만 허용한다", async () => {
  for (const value of ["", "0.0.0.0", "::", "10.52.1.10"]) {
    await assert.rejects(
      prepare(withBackendBind(value)),
      /backend bind must be 127.0.0.1/,
    );
  }
});

test("production train-search rate limit은 sanitized Nginx peer 경계를 필수로 신뢰한다", async () => {
  for (const value of ["", "10.0.0.0/8,192.168.0.0/16", "172.16.0.0/16", "0.0.0.0/0"]) {
    await assert.rejects(
      prepare(fixtureEnv().replace(
        TRUSTED_PROXY_LINE,
        `EASYSUBWAY_TRUSTED_PROXY_CIDRS=${value}`,
      )),
      /trusted proxy CIDRs must equal the Docker ingress boundary/,
    );
  }

  const proxy = read("infra/nginx/host-default-proxy.conf");
  const host = read("infra/nginx/host-easysubway.conf.template");
  assert.match(proxy, /real_ip_header CF-Connecting-IP;/);
  assert.match(proxy, /proxy_set_header X-Forwarded-For \$remote_addr;/);
  assert.doesNotMatch(proxy, /proxy_add_x_forwarded_for/);
  assert.equal((host.match(/access_log off;/g) ?? []).length, 3);
});

test("Route V2 배포 secret과 certificate digest는 config injection을 차단한다", async () => {
  await assert.rejects(
    prepare(fixtureEnv().replace(ROUTE_V2_ORIGIN_SECRET_LINE, "EASYSUBWAY_ROUTE_V2_ORIGIN_SECRET=short;include")),
    /invalid Route V2 origin secret/,
  );
  await assert.rejects(
    prepare(fixtureEnv().replace(ROUTE_V2_CERTIFICATE_LINE, "EASYSUBWAY_ROUTE_V2_PLAY_INTEGRITY_CERTIFICATE_SHA256=not-a-digest")),
    /invalid Play Integrity certificate SHA-256/,
  );
  await assert.rejects(
    prepare(fixtureEnv().replace("EASYSUBWAY_ROUTE_V2_SESSION_RATE_PER_MINUTE=5", "EASYSUBWAY_ROUTE_V2_SESSION_RATE_PER_MINUTE=6")),
    /invalid or relaxed Route V2 limit: EASYSUBWAY_ROUTE_V2_SESSION_RATE_PER_MINUTE/,
  );
  for (const cidr of ["", "0.0.0.0/0", "172.16.0.0/12;include", "172.16.0.0/16"]) {
    await assert.rejects(
      prepare(fixtureEnv().replace("EASYSUBWAY_ROUTE_V2_TRUSTED_PROXY_CIDR=172.16.0.0/12", `EASYSUBWAY_ROUTE_V2_TRUSTED_PROXY_CIDR=${cidr}`)),
      /Route V2 trusted proxy CIDR/,
    );
  }
});

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
  assert.match(backendEnv, /^EASYSUBWAY_TAGO_TRAIN_SERVICE_KEY=prod-tago-train-service-key$/m);
  assert.match(backendEnv, /^EASYSUBWAY_TAGO_TRAIN_CALL_LIMIT_PER_MINUTE=60$/m);
  assert.match(backendEnv, /^EASYSUBWAY_TAGO_TRAIN_CALL_LIMIT_PER_DAY=1000$/m);
  assert.match(backendEnv, /^EASYSUBWAY_TRAIN_SEARCH_RATE_LIMIT_PER_DAY=64$/m);
  assert.match(backendEnv, /^EASYSUBWAY_TRUSTED_PROXY_CIDRS=172\.16\.0\.0\/12$/m);
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
  assert.doesNotMatch(backendEnv, /^DATA_GO_KR_SERVICE_KEY=/m);
  assert.equal(composeMode, 0o600);
  assert.equal(backendMode, 0o600);
});

test("TAGO 기차검색 key는 공용 GitHub secret에서 backend 전용 env로만 주입한다", () => {
  const cd = read(".github/workflows/cd.yml");
  const example = read(".env.example");
  const allowlist = read("tools/deploy/backend-app-env.allowlist");
  const scopeMap = JSON.parse(read("contracts/env/env-scope-map.json"));

  assert.match(cd, /DATA_GO_KR_SERVICE_KEY_SECRET: \$\{\{ secrets\.DATA_GO_KR_SERVICE_KEY \}\}/);
  assert.match(cd, /EASYSUBWAY_TAGO_TRAIN_SERVICE_KEY=%s/);
  assert.match(cd, /drop\["EASYSUBWAY_TAGO_TRAIN_CALL_LIMIT_PER_MINUTE"\] = 1/);
  assert.match(cd, /drop\["EASYSUBWAY_TAGO_TRAIN_CALL_LIMIT_PER_DAY"\] = 1/);
  assert.match(cd, /drop\["EASYSUBWAY_TRAIN_SEARCH_RATE_LIMIT_PER_DAY"\] = 1/);
  assert.match(cd, /printf 'EASYSUBWAY_TAGO_TRAIN_CALL_LIMIT_PER_MINUTE=60\\n'/);
  assert.match(cd, /printf 'EASYSUBWAY_TAGO_TRAIN_CALL_LIMIT_PER_DAY=1000\\n'/);
  assert.match(cd, /printf 'EASYSUBWAY_TRAIN_SEARCH_RATE_LIMIT_PER_DAY=64\\n'/);
  assert.match(
    cd,
    /node --env-file="\$\{PREPARED_ENV_DIR\}\/backend\.env" tools\/ops\/probe-tago-train-provider\.mjs/,
  );
  assert.match(allowlist, /^EASYSUBWAY_TAGO_TRAIN_SERVICE_KEY$/m);
  assert.doesNotMatch(allowlist, /^DATA_GO_KR_SERVICE_KEY$/m);
  assert.deepEqual(scopeMap.keys.EASYSUBWAY_TAGO_TRAIN_SERVICE_KEY, ["backend"]);
  assert.equal(scopeMap.keys.DATA_GO_KR_SERVICE_KEY, undefined);
  for (const [key, value] of [
    ["EASYSUBWAY_TAGO_TRAIN_CALL_LIMIT_PER_MINUTE", "60"],
    ["EASYSUBWAY_TAGO_TRAIN_CALL_LIMIT_PER_DAY", "1000"],
    ["EASYSUBWAY_TRAIN_SEARCH_RATE_LIMIT_PER_DAY", "64"],
  ]) {
    assert.match(example, new RegExp(`^${key}=${value}$`, "m"));
    assert.match(allowlist, new RegExp(`^${key}$`, "m"));
    assert.deepEqual(scopeMap.keys[key], ["backend"]);
  }
});

test("production 배포 env는 TAGO 기차검색 key 누락을 거부한다", async () => {
  await assert.rejects(
    prepare(fixtureEnv().replace(/^EASYSUBWAY_TAGO_TRAIN_SERVICE_KEY=.*\n/m, "")),
    /required deployment env is empty: EASYSUBWAY_TAGO_TRAIN_SERVICE_KEY/,
  );
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
  await assert.rejects(
    prepare(`${fixtureEnv()}EASYSUBWAY_ALERT_EMAIL_ENABLED=true\nEASYSUBWAY_ALERTMANAGER_EXTERNAL_URL=https://[::1]:9093\nEASYSUBWAY_ALERT_EMAIL_TO=ops@example.com\nEASYSUBWAY_ALERT_EMAIL_FROM=alerts@example.com\nEASYSUBWAY_ALERT_SMTP_SMARTHOST=smtp.example.com:587\nEASYSUBWAY_ALERT_SMTP_USERNAME=alerts@example.com\nEASYSUBWAY_ALERT_SMTP_PASSWORD=secret\n`),
    /alertmanager external URL must not be internal/,
  );
  await prepare(`${fixtureEnv()}EASYSUBWAY_ALERT_EMAIL_ENABLED=true\nEASYSUBWAY_ALERTMANAGER_EXTERNAL_URL=https://[2001:db8::10]:9093/alertmanager\nEASYSUBWAY_ALERT_EMAIL_TO=ops@example.com\nEASYSUBWAY_ALERT_EMAIL_FROM=alerts@example.com\nEASYSUBWAY_ALERT_SMTP_SMARTHOST=smtp.example.com:587\nEASYSUBWAY_ALERT_SMTP_USERNAME=alerts@example.com\nEASYSUBWAY_ALERT_SMTP_PASSWORD=secret\nEASYSUBWAY_ALERT_SMTP_REQUIRE_TLS=true\n`);
  const outputDir = await prepare(`${fixtureEnv()}EASYSUBWAY_ALERT_EMAIL_ENABLED=true\nEASYSUBWAY_ALERTMANAGER_EXTERNAL_URL=https://ops.easysubway.example/alertmanager\nEASYSUBWAY_ALERT_EMAIL_TO=ops@example.com\nEASYSUBWAY_ALERT_EMAIL_FROM=alerts@example.com\nEASYSUBWAY_ALERT_SMTP_SMARTHOST=smtp.example.com:587\nEASYSUBWAY_ALERT_SMTP_USERNAME=alerts@example.com\nEASYSUBWAY_ALERT_SMTP_PASSWORD=secret\nEASYSUBWAY_ALERT_SMTP_REQUIRE_TLS=true\n`);
  const composeEnv = await readFile(path.join(outputDir, "compose.env"), "utf8");
  const backendEnv = await readFile(path.join(outputDir, "backend.env"), "utf8");
  assert.match(composeEnv, /^EASYSUBWAY_ALERT_EMAIL_ENABLED=true$/m);
  assert.match(composeEnv, /^EASYSUBWAY_ALERTMANAGER_EXTERNAL_URL=https:\/\/ops\.easysubway\.example\/alertmanager$/m);
  assert.match(composeEnv, /^EASYSUBWAY_ALERT_SMTP_PASSWORD=secret$/m);
  assert.doesNotMatch(backendEnv, /^EASYSUBWAY_ALERT_SMTP_PASSWORD=/m);
});

test("백엔드 SSH 배포 스크립트는 상태, drift, 백업, standby 승격 계약을 포함한다", async () => {
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
  // The deployed artifact is verified by GHCR digest, not by re-hashing a jar,
  // and there is no on-server image build (issue #1686).
  assert.doesNotMatch(deploy, /sha256sum -c/);
  assert.match(deploy, /docker image inspect "easysubway-backend:\$\{DEPLOY_SHA\}"/);
  assert.match(deploy, /image_digest_mismatch/);
  assert.match(deploy, /up -d --no-build postgres object-storage/);
  assert.doesNotMatch(deploy, /timeout [0-9]+ compose/);
  assert.match(deploy, /timeout 600 docker compose/);
  assert.doesNotMatch(deploy, /timeout 900 docker compose/);
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
  assert.ok(deploy.indexOf('abort_deploy "observability_readiness_failed"') < legacyRestoreDisableIndex);
  assert.ok(legacyRestoreDisableIndex < deploy.indexOf('printf \'%s\\n\' "${DEPLOY_SHA}" > "${SHARED_DIR}/current-sha"'));
  assert.ok(deploy.indexOf("trap - ERR INT TERM HUP") < deploy.indexOf('printf \'%s\\n\' "${DEPLOY_SHA}" > "${SHARED_DIR}/current-sha"'));
  assert.match(deploy, /managed_image_drift/);
  assert.match(deploy, /printf 'compose\.env\\0'/);
  assert.match(deploy, /printf '\\nbackend\.env\\0'/);
  assert.doesNotMatch(deploy, /sha256sum "\$\{COMPOSE_ENV\}" "\$\{BACKEND_ENV\}" \| sha256sum/);
  assert.match(deploy, /tools\/ops\/postgres-backup\.sh/);
  assert.match(deploy, /EASYSUBWAY_BACKEND_ENV_FILE="\$\{BACKEND_ENV\}"/);
  assert.match(deploy, /RUNTIME_SERVICES=\(backend back-worker route-v2-gateway\)/);
  assert.match(deploy, /OBSERVABILITY_SERVICES=\(public-edge-probe docker-runtime-probe alertmanager prometheus loki grafana alloy\)/);
  assert.match(deploy, /OBSERVABILITY_CONFIG_SERVICES=\(alertmanager prometheus loki grafana alloy\)/);
  assert.match(deploy, /EASYSUBWAY_ALERTMANAGER_CONFIG_FILE=/);
  assert.match(deploy, /write_alertmanager_config "\$\{tmp_env_set\}\/alertmanager\.yml"/);
  assert.match(deploy, /chmod 600 "\$\{tmp_env_set\}\/compose\.env" "\$\{tmp_env_set\}\/backend\.env" "\$\{tmp_env_set\}\/metadata\.env"/);
  assert.match(deploy, /chmod 644 "\$\{tmp_env_set\}\/alertmanager\.yml"/);
  assert.match(deploy, /compose_services_running\(\)/);
  assert.match(deploy, /start_observability_services\(\)/);
  assert.match(deploy, /compose_services_running "\$\{BACKEND_ENV\}" "\$\{COMPOSE_ENV\}" "\$\{DEPLOY_SHA\}" "\$\{RUNTIME_SERVICES\[@\]\}" "\$\{OBSERVABILITY_SERVICES\[@\]\}"/);
  assert.match(deploy, /same_sha_same_env_services_ready/);
  assert.doesNotMatch(deploy, /same_sha_same_env_ready/);
  // The 3-service RUNTIME_SERVICES force-recreate is gone: canonical "backend"
  // is recreated alone during promotion (asserted in the blue/green contract
  // block below).
  assert.match(deploy, /--profile observability up -d --no-build "\$\{OBSERVABILITY_SERVICES\[@\]\}" \|\| return 1/);
  assert.match(deploy, /--profile observability up -d --no-build --force-recreate "\$\{OBSERVABILITY_CONFIG_SERVICES\[@\]\}" \|\| return 1/);
  assert.match(deploy, /--profile observability up -d --no-build --force-recreate alertmanager \|\| return 1/);
  assert.match(deploy, /if \[\[ "\$\{current_env_hash\}" != "\$\{target_env_hash\}" \]\]; then/);
  assert.match(deploy, /git diff --quiet "\$\{current_sha\}" "\$\{DEPLOY_SHA\}" -- infra\/prometheus infra\/alertmanager\/templates infra\/loki infra\/grafana\/provisioning/);
  assert.doesNotMatch(deploy, /--force-recreate "\$\{OBSERVABILITY_SERVICES\[@\]\}"/);
  assert.match(deploy, /verify_runtime_hardening\(\)/);
  assert.match(deploy, /runtime_services_hardened\(\)/);
  assert.match(deploy, /docker inspect --format '\{\{\.Config\.User\}\}\|\{\{\.HostConfig\.ReadonlyRootfs\}\}\|\{\{json \.HostConfig\.Tmpfs\}\}\|\{\{json \.HostConfig\.CapDrop\}\}\|\{\{json \.HostConfig\.SecurityOpt\}\}'/);
  assert.match(deploy, /docker exec "\$\{container_id\}" id -u/);
  assert.match(deploy, /docker exec "\$\{container_id\}" id -g/);
  assert.match(deploy, /docker exec "\$\{container_id\}" touch \/app\/app\.jar/);
  assert.match(deploy, /docker exec "\$\{container_id\}" sh -c 'probe="\$\(mktemp \/tmp\/easysubway-hardening\.XXXXXX\)" && rm -f "\$probe"'/);
  assert.match(deploy, /docker exec "\$\{container_id\}" cat \/proc\/1\/status/);
  assert.match(deploy, /CapEff:/);
  assert.match(deploy, /NoNewPrivs:/);
  assert.ok(
    deploy.indexOf("runtime_services_hardened()") < deploy.indexOf('if [[ "${current_sha}" == "${DEPLOY_SHA}"'),
    "runtime hardening helper must be available to the same-SHA no-op path",
  );
  assert.match(deploy, /compose_services_running[\s\S]*&& runtime_services_hardened "\$\{RUNTIME_SERVICES\[@\]\}"; then/);
  assert.match(deploy, /if ! runtime_services_hardened backend-standby; then/);
  assert.match(deploy, /if ! runtime_services_hardened backend; then/);
  assert.match(deploy, /if ! runtime_services_hardened back-worker route-v2-gateway; then/);
  assert.match(deploy, /observability_ready=0/);
  assert.match(deploy, /compose_services_running "\$\{SHARED_DIR\}\/current-env\/backend\.env" "\$\{SHARED_DIR\}\/current-env\/compose\.env" "\$\{DEPLOY_SHA\}" "\$\{RUNTIME_SERVICES\[@\]\}" "\$\{OBSERVABILITY_SERVICES\[@\]\}"/);
  assert.match(deploy, /actuator\/health\/readiness/);
  assert.match(deploy, /diagnostics/);

  // --- Blue/green standby+promotion contract (issue #2331). The old
  // reboot-the-previous-image rollback path is fully removed: no image
  // restart, no `previous-env` symlink, no per-detail "_rollback_attempted"/
  // "_rollback_unavailable" suffixes. Instead a candidate is proven on a
  // standby container before the canonical "backend" container is ever
  // touched, and a single "leave the proven-healthy server as-is" fallback
  // covers every post-promotion failure.
  assert.doesNotMatch(deploy, /fail_backend_deployment/);
  assert.doesNotMatch(deploy, /ensure_rollback_image/);
  assert.doesNotMatch(deploy, /GHCR_IMAGE/);
  assert.doesNotMatch(deploy, /previous-env/);
  assert.doesNotMatch(deploy, /_rollback_attempted/);
  assert.doesNotMatch(deploy, /_rollback_unavailable/);
  assert.match(deploy, /backend_standby_port="\$\(read_env_value "\$\{COMPOSE_ENV\}" EASYSUBWAY_BACKEND_STANDBY_PORT\)"/);
  assert.match(deploy, /backend_standby_port="\$\{backend_standby_port:-8082\}"/);
  assert.match(deploy, /STANDBY_STATE_FILE="\$\{SHARED_DIR\}\/deployment-standby-state\.env"/);
  assert.match(deploy, /write_standby_state\(\)/);
  assert.match(deploy, /wait_backend_http_ready\(\)/);
  assert.match(deploy, /dump_diagnostics\(\)/);
  assert.match(deploy, /cleanup_standby\(\)/);
  assert.match(deploy, /abort_deploy\(\)/);
  assert.match(deploy, /abort_standby_stage\(\)/);
  assert.match(deploy, /install_route_v2_host_ingress\(\) \{\n\tlocal target_backend_port="\$1"/);

  // Stage order: no-op < freshness precheck < standby up < standby hardening
  // + readiness < Nginx -> alt < promotion recreate < promotion hardening +
  // readiness < Nginx -> canonical < standby cleanup < back-worker/gateway
  // recreate < current-sha recorded.
  const noopExitIndex = deploy.indexOf('write_result "noop" "same_sha_same_env_services_ready"');
  const precheckIndex = deploy.indexOf("check-snapshot-freshness-precheck.mjs");
  const logsInitPhaseIndex = deploy.indexOf('write_phase "backend_logs_init"');
  const logsInitRunIndex = deploy.indexOf("run --rm --no-deps backend-logs-init");
  const standbyUpIndex = deploy.indexOf('write_phase "standby_starting"');
  const standbyForceRecreateIndex = deploy.indexOf("up -d --no-deps --no-build --force-recreate backend-standby");
  const standbyHardenedIndex = deploy.indexOf("if ! runtime_services_hardened backend-standby; then");
  const standbyReadyWaitIndex = deploy.indexOf('if ! wait_backend_http_ready "${backend_standby_port}"; then');
  const standbyReadyPhaseIndex = deploy.indexOf('write_phase "standby_ready"');
  const nginxAltIndex = deploy.indexOf('if ! install_route_v2_host_ingress "${backend_standby_port}"; then');
  const nginxAltPhaseIndex = deploy.indexOf('write_phase "nginx_alt"');
  const promotingPhaseIndex = deploy.indexOf('write_phase "promoting"');
  const canonicalForceRecreateIndex = deploy.indexOf("up -d --no-deps --no-build --force-recreate backend; then");
  const canonicalHardenedIndex = deploy.indexOf("if ! runtime_services_hardened backend; then");
  const canonicalReadyWaitIndex = deploy.indexOf('if ! wait_backend_http_ready "${backend_port}"; then');
  const promotedPhaseIndex = deploy.indexOf('write_phase "promoted"');
  const nginxCanonicalIndex = deploy.indexOf('if ! install_route_v2_host_ingress "${backend_port}"; then');
  const standbyCleanupPhaseIndex = deploy.indexOf('write_phase "standby_cleanup"');
  const standbyRmIndex = deploy.indexOf("rm -f -s backend-standby; then");
  const finalizingPhaseIndex = deploy.indexOf('write_phase "finalizing"');
  const backWorkerGatewayForceRecreateIndex = deploy.indexOf(
    "up -d --no-deps --no-build --force-recreate back-worker route-v2-gateway",
  );
  const currentShaWriteIndex = deploy.indexOf('printf \'%s\\n\' "${DEPLOY_SHA}" > "${SHARED_DIR}/current-sha"');

  for (const index of [
    noopExitIndex, precheckIndex, logsInitPhaseIndex, logsInitRunIndex, standbyUpIndex, standbyForceRecreateIndex, standbyHardenedIndex,
    standbyReadyWaitIndex, standbyReadyPhaseIndex, nginxAltIndex, nginxAltPhaseIndex, promotingPhaseIndex,
    canonicalForceRecreateIndex, canonicalHardenedIndex, canonicalReadyWaitIndex, promotedPhaseIndex,
    nginxCanonicalIndex, standbyCleanupPhaseIndex, standbyRmIndex, finalizingPhaseIndex,
    backWorkerGatewayForceRecreateIndex, currentShaWriteIndex,
  ]) {
    assert.notEqual(index, -1);
  }

  assert.ok(noopExitIndex < precheckIndex, "no-op success must exit before the freshness precheck runs");
  assert.ok(precheckIndex < logsInitPhaseIndex, "freshness precheck must run before backend log volume init");
  assert.ok(logsInitPhaseIndex < logsInitRunIndex, "backend_logs_init phase must precede the init container run");
  assert.ok(logsInitRunIndex < standbyUpIndex, "log volume init must run before the standby container starts");
  assert.ok(precheckIndex < standbyUpIndex, "freshness precheck must run before the standby container starts");
  assert.ok(standbyUpIndex < standbyForceRecreateIndex);
  assert.ok(standbyForceRecreateIndex < standbyHardenedIndex, "standby must exist before it is hardening-checked");
  assert.ok(standbyHardenedIndex < standbyReadyWaitIndex, "standby hardening must pass before its readiness is polled");
  assert.ok(standbyReadyWaitIndex < standbyReadyPhaseIndex);
  assert.ok(standbyReadyPhaseIndex < nginxAltIndex, "standby must be proven ready before Nginx switches to it");
  assert.ok(nginxAltIndex < nginxAltPhaseIndex);
  assert.ok(nginxAltPhaseIndex < promotingPhaseIndex, "Nginx must be on the standby before the canonical container is recreated");
  assert.ok(promotingPhaseIndex < canonicalForceRecreateIndex);
  assert.ok(canonicalForceRecreateIndex < canonicalHardenedIndex);
  assert.ok(canonicalHardenedIndex < canonicalReadyWaitIndex, "canonical hardening must pass before its readiness is polled");
  assert.ok(canonicalReadyWaitIndex < promotedPhaseIndex);
  assert.ok(promotedPhaseIndex < nginxCanonicalIndex, "canonical must be proven ready before Nginx switches back to it");
  assert.ok(nginxCanonicalIndex < standbyCleanupPhaseIndex, "Nginx must be back on canonical before the standby is retired");
  assert.ok(standbyCleanupPhaseIndex < standbyRmIndex);
  assert.ok(standbyRmIndex < finalizingPhaseIndex, "standby must be retired before back-worker/route-v2-gateway are recreated");
  assert.ok(finalizingPhaseIndex < backWorkerGatewayForceRecreateIndex);
  assert.ok(
    backWorkerGatewayForceRecreateIndex < currentShaWriteIndex,
    "current-sha is only recorded once every stage above has succeeded",
  );

  // --- Review follow-up (PR #2356): legacy-restore trap must be disarmed
  // before promotion recreates the canonical container, so a trap firing
  // mid-promotion cannot start the legacy systemd jar on the same port the
  // Docker canonical container may already hold.
  const promotionLegacyDisarmIndex = deploy.indexOf("legacy_restore_on_error=0", promotingPhaseIndex);
  assert.notEqual(promotionLegacyDisarmIndex, -1);
  assert.ok(
    promotingPhaseIndex < promotionLegacyDisarmIndex,
    "legacy_restore_on_error must be disarmed at or after the promoting phase begins",
  );
  assert.ok(
    promotionLegacyDisarmIndex < canonicalForceRecreateIndex,
    "legacy_restore_on_error must be disarmed before the canonical container is force-recreated",
  );

  // --- Review follow-up: current-env is captured and restored on a
  // pre-promotion standby-stage abort, so external tools that read
  // current-env/compose.env as ground truth for "what canonical is actually
  // running" (capacity/canary rollback scripts) never see an uncommitted
  // candidate env after an abort that never touched canonical.
  assert.match(deploy, /previous_env_set=""/);
  assert.match(deploy, /if \[\[ -L "\$\{SHARED_DIR\}\/current-env" \]\]; then/);
  assert.match(deploy, /previous_env_set="\$\(readlink "\$\{SHARED_DIR\}\/current-env"\)"/);
  const abortStandbyStageBody = deploy.slice(
    deploy.indexOf("abort_standby_stage() {"),
    deploy.indexOf("abort_standby_stage() {") + deploy.slice(deploy.indexOf("abort_standby_stage() {")).indexOf("\n}\n"),
  );
  assert.match(abortStandbyStageBody, /if \[\[ -n "\$\{previous_env_set\}" \]\]; then/);
  assert.match(abortStandbyStageBody, /ln -sfn "\$\{previous_env_set\}" "\$\{SHARED_DIR\}\/current-env\.next"/);
  assert.match(abortStandbyStageBody, /rm -f "\$\{SHARED_DIR\}\/current-env"/);
  const previousEnvSetCaptureIndex = deploy.indexOf('previous_env_set=""');
  const currentEnvSwapIndex = deploy.indexOf('ln -sfn "${env_set}" "${SHARED_DIR}/current-env.next"');
  assert.ok(
    previousEnvSetCaptureIndex < currentEnvSwapIndex,
    "the previous current-env target must be captured before it is overwritten",
  );

  // --- Review follow-up: the standby state file is reset to idle right
  // after the deploy lock is acquired, so a stale "*_standby_serving" from a
  // prior run does not linger across unrelated, later-blocked attempts.
  const flockIndex = deploy.indexOf("flock 9");
  const sessionStartResetIndex = deploy.indexOf('write_standby_state "idle"');
  const interruptedStateCheckIndex = deploy.indexOf('write_result "blocked" "interrupted_state"');
  const writeStandbyStateDefIndex = deploy.indexOf("write_standby_state() {");
  assert.notEqual(flockIndex, -1);
  assert.notEqual(sessionStartResetIndex, -1);
  assert.ok(
    writeStandbyStateDefIndex < flockIndex,
    "write_standby_state must be defined before flock so it can reset state right after lock acquisition",
  );
  assert.ok(flockIndex < sessionStartResetIndex, "the standby state reset must run after the deploy lock is acquired");
  assert.ok(
    sessionStartResetIndex < interruptedStateCheckIndex,
    "the standby state reset must run before any early-blocked exit",
  );

  // --- Review follow-up: manual recovery runbook for "*_standby_serving"
  // degraded exits, and the expand/contract migration contract header.
  assert.match(deploy, /Manual recovery runbook for a "\*_standby_serving" degraded exit/);
  assert.match(deploy, /managed_image_drift — it is not a/);
  assert.match(deploy, /expand\/contract \(purely additive\)/);
  assert.match(deploy, /mechanically enforced by tools\/ci\/check-migration-ddl-compat\.mjs/);

  // Pre-promotion standby failures never touch the canonical container or
  // Nginx (fall back to the pre-Docker legacy unit only for the narrow
  // very-first-deploy case, exactly like the old rollback path did).
  const standbyFailureBlock = deploy.slice(standbyUpIndex, nginxAltPhaseIndex);
  assert.match(standbyFailureBlock, /abort_standby_stage "standby_start_failed"/);
  assert.match(standbyFailureBlock, /abort_standby_stage "standby_hardening_failed"/);
  assert.match(standbyFailureBlock, /abort_standby_stage "standby_readiness_failed"/);
  assert.match(standbyFailureBlock, /abort_standby_stage "nginx_alt_switch_failed"/);
  assert.doesNotMatch(standbyFailureBlock, /up -d --no-deps --no-build --force-recreate backend;/);

  // Post-promotion failures leave the proven-healthy standby serving and are
  // tagged with a "_standby_serving" detail so an operator can find them —
  // the one place the standby is deliberately NOT cleaned up.
  const postPromotionBlock = deploy.slice(promotingPhaseIndex, standbyCleanupPhaseIndex);
  assert.match(postPromotionBlock, /abort_deploy "canonical_promotion_failed_standby_serving"/);
  assert.match(postPromotionBlock, /abort_deploy "canonical_hardening_failed_standby_serving"/);
  assert.match(postPromotionBlock, /abort_deploy "canonical_readiness_failed_standby_serving"/);
  assert.match(postPromotionBlock, /abort_deploy "nginx_canonical_switchback_failed_standby_serving"/);
  assert.doesNotMatch(postPromotionBlock, /cleanup_standby/);
  assert.match(deploy, /write_standby_state "serving_standby_degraded" "\$\{backend_standby_port\}"/);

  // The trailing back-worker/route-v2-gateway recreate and observability
  // start no longer roll the already-promoted, already-serving canonical
  // backend back to an old image on failure.
  const tailBlock = deploy.slice(finalizingPhaseIndex);
  assert.match(tailBlock, /abort_deploy "back_worker_gateway_recreate_failed"/);
  assert.match(tailBlock, /abort_deploy "back_worker_gateway_hardening_failed"/);
  assert.match(tailBlock, /abort_deploy "observability_start_failed"/);
  assert.match(tailBlock, /abort_deploy "observability_readiness_failed"/);

  assert.match(backup, /pg_restore --list/);
  assert.doesNotMatch(backup, /pg_restore --list -/);
  assert.match(backup, /\.sha256/);

  const cd = read(".github/workflows/cd.yml");
  assert.match(cd, /uses: actions\/setup-java@be666c2fcd27ec809703dec50e508c2fdc7f6654/);
  assert.doesNotMatch(cd, /uses: actions\/setup-java@be66141d4002b0e783cc31e5449d3f9f3267ffd9/);
  assert.match(cd, /if \[\[ -n "\$\{EASYSUBWAY_ENV_FILE:-\}" \]\]; then/);
  assert.doesNotMatch(cd, /EASYSUBWAY_ENV_FILE:-\/dev\/null/);
  // 파괴적 DDL 게이트는 배포 대상 checkout에서도 재검사한다(#2365).
  assert.match(cd, /CD Deploy \/ Check migration DDL compatibility/);
  assert.match(cd, /node tools\/ci\/check-migration-ddl-compat\.mjs/);
  // pre-#2365 SHA 롤백 재배포 시 검사기 파일 부재를 skip하는 가드가 있어야 한다.
  assert.match(cd, /if \[\[ ! -f tools\/ci\/check-migration-ddl-compat\.mjs \]\]; then/);
  assert.match(cd, /migration DDL gate absent at deploy target \(pre-#2365 SHA\); skipping/);
});

test("CD 배포 후 검증은 readiness 단일 프로브가 아니라 핵심 API 스모크로 게이트한다", () => {
  const cd = read(".github/workflows/cd.yml");

  // The old skip-on-unset public readiness step is removed: "not configured, so
  // it passed" is not a gate (issue #1688).
  assert.doesNotMatch(cd, /DEPLOY_PUBLIC_API_BASE_URL is not configured; remote local readiness was already checked/);

  // A dedicated ubuntu-latest smoke job runs the contract-driven smoke script,
  // requires the public base URL, and fails when it is unset.
  assert.match(cd, /post-deploy-smoke:/);
  assert.match(cd, /node tools\/ops\/post-deploy-smoke\.mjs/);
  assert.match(cd, /DEPLOY_PUBLIC_API_BASE_URL repo variable is not configured/);
  assert.match(cd, /route_v2_ingress_enabled: \$\{\{ steps\.ingress-state\.outputs\.enabled \}\}/);
  assert.match(cd, /state_file="\$\{DEPLOY_ROOT\}\/shared\/current-route-v2-ingress-enabled"/);
  assert.match(cd, /--route-v2-ingress-enabled "\$\{ROUTE_V2_INGRESS_ENABLED\}"/);
  assert.match(cd, /if: \$\{\{ needs\.deploy\.outputs\.deploy_ready == 'true' \}\}/);

  // Smoke failures must propagate into the CD result Slack notification.
  assert.match(cd, /needs:\n {6}- plan\n {6}- build-image\n {6}- deploy\n {6}- record-deploy\n {6}- post-deploy-smoke/);
});

test("Route V2 host ingress는 두 exact 경로만 gateway로 보내고 실패 시 Nginx 설정을 복원한다", () => {
  const deploy = read("tools/deploy/deploy-backend.sh");
  const host = read("infra/nginx/host-easysubway.conf.template");
  const routeHeaders = read("infra/nginx/host-route-v2-proxy.conf");
  const cloudflareCidrs = [
    ...read("infra/terraform/oci/always-free-a1-flex/locals.tf")
      .match(/cloudflare_ipv4_ingress_cidrs\s*=\s*toset\(\[([\s\S]*?)\]\)/)[1]
      .matchAll(/"([0-9.]+\/[0-9]+)"/g),
  ].map((match) => match[1]);

  const httpServer = host.slice(0, host.indexOf("server {", 1));
  const httpsServer = host.slice(host.indexOf("server {", 1));
  assert.match(httpServer, /location \^~ \/\.well-known\/acme-challenge\//);
  assert.match(httpServer, /location \/ \{\s*return 308 https:\/\/\$host\$request_uri;\s*\}/);
  assert.doesNotMatch(httpServer, /proxy_pass|__ROUTE_V2_ACTION__/);
  assert.equal((httpsServer.match(/location = \/api\/v2\/routes\/session/g) ?? []).length, 1);
  assert.equal((httpsServer.match(/location = \/api\/v2\/routes\/search/g) ?? []).length, 1);
  assert.equal((httpsServer.match(/__ROUTE_V2_ACTION__/g) ?? []).length, 2);
  assert.match(httpsServer, /location \/ \{[\s\S]*proxy_pass http:\/\/127\.0\.0\.1:__BACKEND_PORT__;/);
  assert.deepEqual(
    [...routeHeaders.matchAll(/set_real_ip_from ([0-9.]+\/[0-9]+);/g)].map((match) => match[1]),
    cloudflareCidrs,
  );
  assert.match(routeHeaders, /real_ip_header CF-Connecting-IP;/);
  assert.match(routeHeaders, /real_ip_recursive on;/);
  assert.match(routeHeaders, /proxy_set_header CF-Connecting-IP \$remote_addr;/);
  assert.doesNotMatch(routeHeaders, /proxy_set_header CF-Connecting-IP \$http_cf_connecting_ip;/);
  assert.match(routeHeaders, /proxy_set_header X-Forwarded-For "";/);
  assert.match(host, /listen 443 ssl default_server;[\s\S]*server_name _;[\s\S]*return 444;/);
  assert.match(host, /listen 443 ssl;[\s\S]*server_name easysubway-api\.aquilaxk\.site;/);
  assert.equal((host.match(/listen 443 ssl default_server;/g) ?? []).length, 1);
  assert.match(deploy, /sudo nginx -t/);
  assert.match(deploy, /sudo systemctl reload nginx/);
  assert.match(deploy, /sudo install -m 0644 "\$\{site_backup\}" "\$\{site_target\}"/);
  assert.match(deploy, /sudo install -m 0644 "\$\{route_snippet_backup\}" "\$\{route_snippet_target\}"/);
  assert.match(deploy, /sudo install -m 0644 "\$\{default_snippet_backup\}" "\$\{default_snippet_target\}"/);
  assert.match(deploy, /sudo rm -f "\$\{route_snippet_target\}"/);
  assert.match(deploy, /sudo rm -f "\$\{default_snippet_target\}"/);
  assert.match(deploy, /if ! sudo cp "\$\{site_target\}" "\$\{site_backup\}"; then/);
  assert.match(deploy, /if ! sudo install -m 0644 infra\/nginx\/host-route-v2-proxy\.conf/);
  assert.match(deploy, /install_failed=1/);
  assert.match(deploy, /restore_failed=1/);
  assert.match(deploy, /failed to restore Route V2 host ingress/);
  assert.doesNotMatch(deploy, /sudo nginx -t[^\n]+&& sudo systemctl reload nginx \|\| true/);
  assert.match(deploy, /current-route-v2-ingress-enabled/);
  // install_route_v2_host_ingress now takes the backend port to render as a
  // parameter (issue #2331) — it is invoked once to point Nginx at the
  // standby port and once to switch it back to the canonical port, instead
  // of the old single call against a closed-over `backend_port` global.
  assert.match(deploy, /install_route_v2_host_ingress\(\) \{\n\tlocal target_backend_port="\$1"/);
  assert.match(deploy, /-e "s\/__BACKEND_PORT__\/\$\{target_backend_port\}\/g"/);
  assert.match(deploy, /if ! install_route_v2_host_ingress "\$\{backend_standby_port\}"; then/);
  assert.match(deploy, /if ! install_route_v2_host_ingress "\$\{backend_port\}"; then/);
  // The old single-shot 3-service RUNTIME_SERVICES force-recreate (and its
  // current_sha-based rollback twin) is gone: the canonical "backend"
  // container is recreated alone during promotion, after a standby on an
  // alternate port has already proven the candidate image.
  assert.doesNotMatch(deploy, /up -d --no-deps --no-build --force-recreate "\$\{RUNTIME_SERVICES\[@\]\}"/);
  assert.doesNotMatch(deploy, /"\$\{current_sha\}" up -d --no-deps --no-build --force-recreate/);
  assert.match(deploy, /route_v2_host_action="return 404;"/);
  assert.match(deploy, /route_v2_host_action="proxy_pass http:\/\/127\.0\.0\.1:\$\{route_v2_gateway_port\};"/);

  // A prior signed-RC canary budget breach (issue #2095) closes Route V2
  // ingress and leaves a durable lock file; a routine, unrelated deploy must
  // not silently re-open ingress by re-rendering the (stale)
  // EASYSUBWAY_ROUTE_V2_INGRESS_ENABLED=true desired state from compose.env.
  assert.match(
    deploy,
    /route_v2_canary_rollback_lock="\$\{SHARED_DIR\}\/route-v2-canary-rollback-lock\.json"/,
  );
  assert.match(deploy, /if \[\[ -f "\$\{route_v2_canary_rollback_lock\}" \]\]; then/);
  const rollbackLockOverrideBlock = deploy.match(
    /if \[\[ -f "\$\{route_v2_canary_rollback_lock\}" \]\]; then([\s\S]*?)\nfi\n/,
  )?.[1] ?? "";
  assert.match(rollbackLockOverrideBlock, /route_v2_ingress_enabled_normalized=false/);
  assert.match(rollbackLockOverrideBlock, /route_v2_host_action="return 404;"/);
  // The lock check must run AFTER the configured-value case statement (so it
  // overrides whatever compose.env says) and BEFORE the host ingress render.
  assert.ok(
    deploy.indexOf("invalid Route V2 ingress enabled value") < deploy.indexOf('route_v2_canary_rollback_lock=')
      && deploy.indexOf('route_v2_canary_rollback_lock=') < deploy.indexOf('install_route_v2_host_ingress()'),
  );
});

test("호스트 ingress는 actuator 공개를 차단하되 readiness/liveness probe만 예외로 둔다", () => {
  // #2376: actuator Prometheus 메트릭은 docker network 내부에서만 scrape하고 공개 경로로는 노출하지 않는다.
  const host = read("infra/nginx/host-easysubway.conf.template");
  const httpsServer = host.slice(host.indexOf("server {", 1));

  // 공개 probe 계약(공개 edge readiness probe·배포 검증)은 무회귀 — readiness/liveness는 계속 proxy된다.
  assert.match(
    httpsServer,
    /location = \/actuator\/health\/readiness \{\s*proxy_pass http:\/\/127\.0\.0\.1:__BACKEND_PORT__;/,
  );
  assert.match(
    httpsServer,
    /location = \/actuator\/health\/liveness \{\s*proxy_pass http:\/\/127\.0\.0\.1:__BACKEND_PORT__;/,
  );
  // 나머지 /actuator/* (특히 /actuator/prometheus)와 bare /actuator는 공개 경로에서 404로 차단한다.
  assert.match(httpsServer, /location = \/actuator \{\s*return 404;\s*\}/);
  assert.match(httpsServer, /location \^~ \/actuator\/ \{\s*return 404;\s*\}/);
  // /actuator/prometheus 를 프록시하는 location은 존재하지 않아야 한다.
  assert.doesNotMatch(httpsServer, /location[^\n]*\/actuator\/prometheus[\s\S]*?proxy_pass/);
  // 기존 catch-all proxy는 그대로 유지된다.
  assert.match(httpsServer, /location \/ \{[\s\S]*proxy_pass http:\/\/127\.0\.0\.1:__BACKEND_PORT__;/);
});

test("CD Deploy는 canary rollback lock이 있으면 lock을 모르는 구버전 deploy-backend.sh를 거부한다", () => {
  // Redeploying a HISTORICAL main SHA copies and runs THAT SHA's own
  // tools/deploy/deploy-backend.sh (see "CD Deploy / Run local deployment"),
  // which may predate the canary rollback lock check entirely (issue #2095) —
  // deploy-backend.sh's own internal lock check (tested above) cannot help in
  // that case, since it is version-skewed with the checked-out SHA. This gate
  // must live in cd.yml's own step script instead, which is loaded from the
  // ref that dispatched/triggered the CD run, not from the historical
  // deploy_sha checkout, so it stays authoritative regardless of which
  // deploy-backend.sh copy is about to run.
  const cd = read(".github/workflows/cd.yml");
  const runLocalDeploymentStep = cd.match(
    /name: CD Deploy \/ Run local deployment\n([\s\S]*?)\n {6}- name:/,
  )?.[1] ?? "";
  assert.match(
    runLocalDeploymentStep,
    /if \[\[ -f "\$\{DEPLOY_ROOT\}\/shared\/route-v2-canary-rollback-lock\.json" \]\] \\\n\s*&& ! grep -Fq 'route-v2-canary-rollback-lock\.json' "\$\{incoming\}\/deploy-backend\.sh"; then/,
  );
  assert.match(runLocalDeploymentStep, /refusing to deploy until an operator resolves the lock/);
  // The lock check must run AFTER deploy-backend.sh is copied into `incoming`
  // (it inspects that copy) and BEFORE the copied script is actually invoked.
  assert.ok(
    runLocalDeploymentStep.indexOf('tools/deploy/deploy-backend.sh') < runLocalDeploymentStep.indexOf('route-v2-canary-rollback-lock.json') &&
      runLocalDeploymentStep.indexOf("&& ! grep -Fq 'route-v2-canary-rollback-lock.json'") <
        runLocalDeploymentStep.indexOf('bash "${incoming}/deploy-backend.sh"'),
  );
});

test("Compose backend 서비스는 bootJar 기반 이미지와 제한된 바인딩을 사용한다", () => {
  const compose = read("infra/docker-compose.yml");
  const localBuildCompose = read("infra/docker-compose.local-build.yml");

  assert.doesNotMatch(compose, /\n  backend:\n[\s\S]*?context: \.\.\/backend/);
  assert.match(localBuildCompose, /\n  backend:\n[\s\S]*?context: \.\.\/backend/);
  assert.match(localBuildCompose, /\n  back-worker:\n[\s\S]*?context: \.\.\/backend/);
  assert.match(compose, /image: easysubway-backend:\$\{EASYSUBWAY_BACKEND_IMAGE_TAG:-local\}/);
  assert.match(localBuildCompose, /com\.easysubway\.jar\.sha256: \$\{EASYSUBWAY_BACKEND_JAR_SHA256:-unknown\}/);
  assert.match(compose, /env_file:\s*\n\s*-\s*\$\{EASYSUBWAY_BACKEND_ENV_FILE:-\.\.\/\.env\.example\}/);
  assert.match(compose, /EASYSUBWAY_DATASOURCE_URL: jdbc:postgresql:\/\/postgres:5432\/\$\{EASYSUBWAY_POSTGRES_DB:-easysubway\}/);
  assert.match(compose, /EASYSUBWAY_REPORT_OBJECT_STORAGE_INTERNAL_ENDPOINT: http:\/\/object-storage:9000/);
  assert.match(compose, /"\$\{EASYSUBWAY_BACKEND_BIND:-127\.0\.0\.1\}:\$\{EASYSUBWAY_BACKEND_PORT:-8080\}:8080"/);
  assert.match(compose, /max-size: "10m"/);
  assert.match(compose, /postgres:\s*\n\s*condition: service_healthy/);
  assert.match(compose, /object-storage:\s*\n\s*condition: service_healthy/);

  for (const service of ["backend", "backend-standby", "back-worker"]) {
    const block = compose.match(new RegExp(`\\n  ${service}:\\n[\\s\\S]*?(?=\\n  [a-z0-9-]+:\\n|\\nvolumes:)`))?.[0] ?? "";
    assert.match(block, /^    user: "10001:10001"$/m, `${service} numeric user`);
    assert.match(block, /^    read_only: true$/m, `${service} read-only rootfs`);
    assert.match(block, /^    tmpfs:\s*\n      - \/tmp:rw,nosuid,nodev$/m, `${service} tmpfs`);
    assert.match(block, /^    cap_drop:\s*\n      - ALL$/m, `${service} capabilities`);
    assert.match(block, /^    security_opt:\s*\n      - no-new-privileges:true$/m, `${service} no-new-privileges`);
  }

  // Blue/green standby (issue #2331): a transient container on an alternate,
  // internal-only port, never auto-restarted by Docker.
  const standbyBlock = compose.match(/\n  backend-standby:\n[\s\S]*?(?=\n  [a-z0-9-]+:\n|\nvolumes:)/)?.[0] ?? "";
  assert.match(standbyBlock, /^    container_name: easysubway-backend-standby$/m);
  assert.match(standbyBlock, /^    restart: "no"$/m, "standby must not be auto-restarted by Docker");
  assert.match(
    standbyBlock,
    /"\$\{EASYSUBWAY_BACKEND_BIND:-127\.0\.0\.1\}:\$\{EASYSUBWAY_BACKEND_STANDBY_PORT:-8082\}:8080"/,
  );
  assert.doesNotMatch(standbyBlock, /EASYSUBWAY_BACKEND_PORT/, "standby must bind its own alternate port, not the canonical one");

  // Review follow-up (PR #2356): the standby shares canonical's live
  // datasource, so migrations/snapshot swap commit against production data
  // before canonical is touched — "old backend untouched" must not be
  // overclaimed as a data-layer guarantee.
  assert.match(compose, /same Postgres datasource as canonical "backend"/i);
  assert.match(compose, /process\/Nginx-level guarantee, not\s*\n\s*# a data-layer one/);
});

const FRESHNESS_PRECHECK = "tools/deploy/check-snapshot-freshness-precheck.mjs";

async function runFreshnessPrecheck(evidence, extraArgs = []) {
  const dir = await mkdtemp(path.join(tmpdir(), "easysubway-snapshot-precheck-"));
  deploymentTempDirs.add(dir);
  const evidencePath = path.join(dir, "server-timetable-snapshot-evidence.json");
  await writeFile(evidencePath, typeof evidence === "string" ? evidence : JSON.stringify(evidence));
  try {
    const { stdout } = await execFileAsync("node", [FRESHNESS_PRECHECK, evidencePath, ...extraArgs], { cwd: root });
    return { exitCode: 0, stdout };
  } catch (error) {
    return { exitCode: error.code ?? 1, stdout: String(error.stdout ?? ""), stderr: String(error.stderr ?? "") };
  }
}

test("snapshot freshness precheck는 만료·마진 내 만료·유효를 판정한다", () => {
  const now = new Date("2026-07-20T00:00:00Z");
  const margin = 2 * 60 * 60;

  const expired = evaluateSnapshotFreshnessPrecheck({
    freshUntil: "2026-07-19T23:00:00Z",
    now,
    marginSeconds: margin,
  });
  assert.equal(expired.expired, true);
  assert.equal(expired.stale, true);
  assert.equal(expired.ok, false);

  const withinMargin = evaluateSnapshotFreshnessPrecheck({
    freshUntil: "2026-07-20T01:00:00Z",
    now,
    marginSeconds: margin,
  });
  assert.equal(withinMargin.expired, false);
  assert.equal(withinMargin.stale, true);
  assert.equal(withinMargin.ok, false);

  const boundary = evaluateSnapshotFreshnessPrecheck({
    freshUntil: "2026-07-20T02:00:00Z",
    now,
    marginSeconds: margin,
  });
  assert.equal(boundary.stale, true, "freshUntil == now + margin is treated as stale");

  const fresh = evaluateSnapshotFreshnessPrecheck({
    freshUntil: "2026-07-20T02:00:01Z",
    now,
    marginSeconds: margin,
  });
  assert.equal(fresh.expired, false);
  assert.equal(fresh.stale, false);
  assert.equal(fresh.ok, true);
});

test("snapshot freshness precheck는 timezone offset을 가진 freshUntil을 파싱한다", () => {
  const now = new Date("2026-07-19T14:59:59Z");
  const result = evaluateSnapshotFreshnessPrecheck({
    freshUntil: "2026-07-20T00:00:00+09:00",
    now,
    marginSeconds: 0,
  });
  // 2026-07-20T00:00:00+09:00 == 2026-07-19T15:00:00Z, still 1s ahead of now.
  assert.equal(result.expired, false);
  assert.equal(result.ok, true);
});

test("snapshot freshness precheck는 잘못된 입력을 거부한다", () => {
  assert.throws(
    () => evaluateSnapshotFreshnessPrecheck({ freshUntil: "not-a-dateZ", now: new Date(), marginSeconds: 0 }),
    /invalid freshUntil timestamp/,
  );
  assert.throws(
    () => evaluateSnapshotFreshnessPrecheck({ freshUntil: "2026-07-20T00:00:00Z", now: new Date(), marginSeconds: -1 }),
    /marginSeconds must be a non-negative integer/,
  );
  assert.equal(DEFAULT_MARGIN_SECONDS, 2 * 60 * 60);
});

test("snapshot freshness precheck는 timezone offset 없는 freshUntil을 backend 게이트와 동일하게 거부한다", () => {
  // backend TimetableSeedLoader의 활성 경로는 OffsetDateTime.parse로 offset 없는
  // timestamp를 예외로 거부한다. 이 안전망이 Date.parse의 관대한 로컬-타임존 파싱으로
  // offset 없는 값을 통과시키면, precheck는 fresh로 오판하고 force-recreate된 새
  // 컨테이너가 부팅 fail-closed로 죽는다 — 정확히 이 사전 검사가 막으려는 장애다.
  for (const naive of [
    "2026-07-20T00:00:00", // naive datetime, offset 없음
    "2026-07-20", // date-only
    "2026-07-20 00:00:00", // space-separated naive datetime
  ]) {
    assert.throws(
      () => evaluateSnapshotFreshnessPrecheck({ freshUntil: naive, now: new Date(), marginSeconds: 0 }),
      /freshUntil must carry a timezone offset/,
      `expected rejection for offset-less freshUntil: ${naive}`,
    );
  }
  // Z, +09:00, -0500 표기는 모두 허용된다.
  for (const withOffset of ["2026-07-20T00:00:00Z", "2026-07-20T00:00:00+09:00", "2026-07-20T00:00:00-0500"]) {
    assert.doesNotThrow(() =>
      evaluateSnapshotFreshnessPrecheck({ freshUntil: withOffset, now: new Date("2000-01-01T00:00:00Z"), marginSeconds: 0 }));
  }
});

test("snapshot freshness precheck CLI는 유효 snapshot을 통과시킨다", async () => {
  const { exitCode } = await runFreshnessPrecheck(
    { freshUntil: "2099-01-01T00:00:00+09:00" },
    ["--margin-seconds", "0"],
  );
  assert.equal(exitCode, 0);
});

test("snapshot freshness precheck CLI는 만료 snapshot에서 non-zero로 종료한다", async () => {
  const { exitCode, stdout } = await runFreshnessPrecheck(
    { freshUntil: "2000-01-01T00:00:00+09:00" },
    ["--margin-seconds", "0"],
  );
  assert.equal(exitCode, 1);
  assert.match(stdout, /verdict=expired/);
});

test("snapshot freshness precheck CLI는 마진 내 만료 snapshot을 차단한다", async () => {
  const soon = new Date(Date.now() + 30 * 60 * 1000).toISOString();
  const { exitCode, stdout } = await runFreshnessPrecheck(
    { freshUntil: soon },
    ["--margin-seconds", "7200"],
  );
  assert.equal(exitCode, 1);
  assert.match(stdout, /verdict=expiring_within_margin/);
});

test("snapshot freshness precheck CLI는 값 없는 --margin-seconds를 무음 기본값 폴백 대신 명시적으로 거부한다", async () => {
  const { exitCode, stderr } = await runFreshnessPrecheck(
    { freshUntil: "2099-01-01T00:00:00+09:00" },
    ["--margin-seconds"],
  );
  assert.equal(exitCode, 1);
  assert.match(stderr, /--margin-seconds requires a value/);
});

test("snapshot freshness precheck CLI는 evidence 누락·손상 시 fail closed 한다", async () => {
  const missingFreshUntil = await runFreshnessPrecheck({ schemaVersion: 1 }, ["--margin-seconds", "0"]);
  assert.equal(missingFreshUntil.exitCode, 1);

  const corrupt = await runFreshnessPrecheck("{ not json", ["--margin-seconds", "0"]);
  assert.equal(corrupt.exitCode, 1);
});

test("CD 배포는 컨테이너 교체 전에 timetable snapshot freshness를 사전 검사한다", () => {
  const deploy = read("tools/deploy/deploy-backend.sh");

  assert.match(
    deploy,
    /SNAPSHOT_FRESHNESS_PRECHECK_MARGIN_SECONDS="\$\{SNAPSHOT_FRESHNESS_PRECHECK_MARGIN_SECONDS:-7200\}"/,
  );
  assert.match(
    deploy,
    /SNAPSHOT_EVIDENCE_PATH="backend\/src\/main\/resources\/timetable\/server-timetable-snapshot-evidence\.json"/,
  );
  assert.match(
    deploy,
    /node tools\/deploy\/check-snapshot-freshness-precheck\.mjs \\\n\t"\$\{SNAPSHOT_EVIDENCE_PATH\}" \\\n\t--margin-seconds "\$\{SNAPSHOT_FRESHNESS_PRECHECK_MARGIN_SECONDS\}"/,
  );
  assert.match(deploy, /write_result "blocked" "stale_snapshot_precheck_failed"/);

  const precheckIndex = deploy.indexOf("check-snapshot-freshness-precheck.mjs");
  const noopExitIndex = deploy.indexOf('write_result "noop" "same_sha_same_env_services_ready"');
  const standbyStartIndex = deploy.indexOf('write_phase "standby_starting"');
  const backupIndex = deploy.indexOf("needs_backup=0");
  const legacyStopIndex = deploy.lastIndexOf("\nstop_legacy_backend_service\n");
  assert.notEqual(precheckIndex, -1);
  assert.ok(noopExitIndex < precheckIndex, "precheck must not disturb the same-SHA no-op success path");
  assert.ok(precheckIndex < backupIndex, "precheck must run before postgres backup");
  assert.ok(precheckIndex < legacyStopIndex, "precheck must run before stopping the legacy backend");
  assert.ok(precheckIndex < standbyStartIndex, "precheck must run before the standby container is started");

  // The stale abort must not go through abort_deploy/abort_standby_stage (the
  // failure helpers used once containers are actually touched); it must leave
  // the running backend untouched. Assert the stale-abort block writes a
  // blocked result and exits directly, without going through either helper
  // between the precheck and the abort.
  const staleBlock = deploy.slice(precheckIndex, deploy.indexOf("needs_backup=0", precheckIndex));
  assert.doesNotMatch(staleBlock, /abort_deploy|abort_standby_stage/);
  assert.match(staleBlock, /write_result "blocked" "stale_snapshot_precheck_failed"\n\texit 1/);
});

test("배포 성공 종단은 로컬 backend 이미지를 최신 10개+실행 중으로 정리하되 실패를 전파하지 않는다", async () => {
  await execFileAsync("bash", ["-n", "tools/deploy/deploy-backend.sh"], { cwd: root });
  const deploy = read("tools/deploy/deploy-backend.sh");

  // 정리 함수가 존재한다.
  assert.match(deploy, /prune_stale_backend_images\(\) \{/);
  const fnStart = deploy.indexOf("prune_stale_backend_images() {");
  const fnEnd = deploy.indexOf("\n}\n", fnStart);
  assert.notEqual(fnStart, -1);
  assert.notEqual(fnEnd, -1);
  const fnBody = deploy.slice(fnStart, fnEnd);

  // 실패 무전파 구조: errexit-off 서브셸에서 실행되고, 서브셸 종료코드는
  // `|| true`로 흡수한 뒤 항상 0을 반환한다(마지막 명령 실패가 errexit를
  // 발화시켜 성공 기록 후 exit code를 뒤집지 못하게 한다).
  assert.match(fnBody, /\(\n\t\tset \+e/);
  assert.match(fnBody, /\n\t\) \|\| true\n/);
  assert.match(fnBody, /\n\treturn 0$/);

  // 보존: 실행 중 컨테이너의 이미지 ID 전부.
  assert.match(
    fnBody,
    /running_ids="\$\(docker ps -q \| xargs -r docker inspect --format '\{\{\.Image\}\}'/,
  );
  // 보존: easysubway-backend 이미지 중 생성일 최신 10개.
  assert.match(fnBody, /docker images easysubway-backend --no-trunc --format '\{\{\.ID\}\}'/);
  assert.match(fnBody, /head -n 10/);
  // 보존 대상(실행 중·최신 10개)은 삭제 루프에서 continue로 건너뛴다.
  assert.match(fnBody, /grep -qxF "\$\{id\}" <<<"\$\{running_ids\}" && continue/);
  assert.match(fnBody, /grep -qxF "\$\{id\}" <<<"\$\{keep_ids\}" && continue/);

  // 삭제: 그 외 이미지 → dangling prune → build cache prune (이 순서로).
  // -f: 다중 repository/tag·GHCR RepoDigest 참조를 가진 이미지도 강제 삭제한다.
  assert.match(fnBody, /docker rmi -f "\$\{id\}"/);
  assert.match(fnBody, /docker image prune -f/);
  assert.match(fnBody, /docker builder prune -af/);
  const rmiIdx = fnBody.indexOf("docker rmi");
  const imagePruneIdx = fnBody.indexOf("docker image prune -f");
  const builderPruneIdx = fnBody.indexOf("docker builder prune -af");
  assert.ok(rmiIdx < imagePruneIdx, "삭제는 dangling prune보다 먼저 수행된다");
  assert.ok(imagePruneIdx < builderPruneIdx, "dangling prune은 build cache prune보다 먼저 수행된다");

  // 로그: 삭제 개수·회수 공간을 남긴다.
  assert.match(fnBody, /image-cleanup\(#2397\): removed %s stale easysubway-backend image\(s\)/);
  assert.match(fnBody, /dangling reclaimed %s, build-cache reclaimed %s/);

  // 성공 종단 이후에만 호출된다: 모든 trap 해제 → 성공 결과 기록 → 정리 호출.
  const trapDisarmIdx = deploy.lastIndexOf("trap - ERR INT TERM HUP");
  const successIdx = deploy.indexOf('write_result "success" "backend_ready"');
  const callMatches = deploy.match(/\nprune_stale_backend_images\n/g);
  const callIdx = deploy.indexOf("\nprune_stale_backend_images\n");
  assert.notEqual(successIdx, -1);
  assert.notEqual(callIdx, -1);
  assert.equal(callMatches?.length, 1, "정리는 최종 성공 경로에서 한 번만 호출된다");
  assert.ok(trapDisarmIdx !== -1 && trapDisarmIdx < successIdx, "정리 호출 전에 모든 trap이 해제되어 있어야 한다");
  assert.ok(successIdx < callIdx, "정리는 성공 결과(last-result.env)가 기록된 이후에만 호출된다");
  assert.ok(fnEnd < callIdx, "정리 호출은 함수 정의 이후에 온다");
});
