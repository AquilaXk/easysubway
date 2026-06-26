import assert from "node:assert/strict";
import { execFile, execFileSync } from "node:child_process";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { existsSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";
import { inflateSync } from "node:zlib";

const root = process.cwd();
const execFileAsync = promisify(execFile);

function read(relativePath) {
  return readFileSync(path.join(root, relativePath), "utf8");
}

function readJson(relativePath) {
  return JSON.parse(read(relativePath));
}

function ignoredVulnBlocks(osvConfig) {
  return osvConfig.split(/\[\[IgnoredVulns\]\]\n/).slice(1);
}

function privacyCollectedDataTypeEntry(privacyManifest, dataType) {
  const dataTypesStart = privacyManifest.indexOf("<key>NSPrivacyCollectedDataTypes</key>");
  assert.notEqual(dataTypesStart, -1, "PrivacyInfo.xcprivacy must declare collected data types");

  const dataTypes = privacyManifest.slice(dataTypesStart);
  const entries = [...dataTypes.matchAll(/<dict>([\s\S]*?)<\/dict>/g)].map((entry) => entry[1]);
  return entries.find((entry) => entry.includes(`<string>${dataType}</string>`));
}

function assertPrivacyCollectedDataType(privacyManifest, dataType) {
  const entry = privacyCollectedDataTypeEntry(privacyManifest, dataType);
  assert.ok(entry, `PrivacyInfo.xcprivacy must declare ${dataType}`);
  assert.match(entry, /<key>NSPrivacyCollectedDataTypeLinked<\/key>\s*<true\/>/);
  assert.match(entry, /<key>NSPrivacyCollectedDataTypeTracking<\/key>\s*<false\/>/);
  assert.match(entry, /<key>NSPrivacyCollectedDataTypePurposes<\/key>\s*<array>[\s\S]*?<string>NSPrivacyCollectedDataTypePurposeAppFunctionality<\/string>[\s\S]*?<\/array>/);
}

function androidManifestPermissions(androidManifest) {
  return [...androidManifest.matchAll(/<uses-permission\b[^>]*>/g)]
    .map((match) => match[0].match(/\bandroid:name="([^"]+)"/)?.[1])
    .filter(Boolean)
    .filter((permission) => permission.startsWith("android.permission."))
    .sort();
}

function jobBlock(workflow, startJob, nextJob) {
  const pattern = new RegExp(`(^|\\n)  ${startJob}:[\\s\\S]*?\\n  ${nextJob}:`);
  const match = workflow.match(pattern);
  assert.ok(match, `${startJob} job block not found`);
  return match[0];
}

function workflowFiles() {
  return execFileSync("git", ["ls-files", ".github/workflows/*.yml", ".github/workflows/*.yaml"], {
    cwd: root,
    encoding: "utf8",
  }).trim().split("\n").filter(Boolean);
}

function assertActionsEnvSecretPolicy(file, source) {
  const disallowedSecretAccess = /secrets(?:\.EASYSUBWAY_(?!ENV\b)[A-Z0-9_]+|\[['"]EASYSUBWAY_(?!ENV['"]?\])[A-Z0-9_]+['"]\])/;
  const disallowedVarsAccess = /vars(?:\.EASYSUBWAY_[A-Z0-9_]+|\[['"]EASYSUBWAY_[A-Z0-9_]+['"]\])/;

  assert.doesNotMatch(source, disallowedSecretAccess, `${file} must use only secrets.EASYSUBWAY_ENV`);
  assert.doesNotMatch(source, disallowedVarsAccess, `${file} must not use GitHub Actions vars for app env`);
}

function assertMobileCatchPolicy(file, source) {
  const catchPattern = /catch\s*\(([^)]*)\)/g;
  for (const match of source.matchAll(catchPattern)) {
    const lineStart = source.lastIndexOf("\n", match.index) + 1;
    const linePrefix = source.slice(lineStart, match.index);
    if (/\bon\s+\w+/.test(linePrefix)) {
      continue;
    }

    const names = match[1].split(",").map((name) => name.trim());
    assert.deepEqual(names, ["error", "stackTrace"], `${file} has catch without named error and stackTrace`);
  }
}

function inMemoryRepositoryFiles() {
  return execFileSync("git", ["ls-files", "backend/src/main/java/**/InMemory*Repository.java"], {
    cwd: root,
    encoding: "utf8",
  }).trim().split("\n").filter(Boolean);
}

function prodJdbcRepositoryFiles() {
  return execFileSync("git", ["ls-files", "backend/src/main/java/**/Jdbc*Repository.java"], {
    cwd: root,
    encoding: "utf8",
  }).trim().split("\n").filter(Boolean);
}

test("backend production schema is managed by Flyway versioned migrations", () => {
  const build = read("backend/build.gradle");
  const application = read("backend/src/main/resources/application.yml");
  const applicationProd = read("backend/src/main/resources/application-prod.yml");
  const baselineMigration = read("backend/src/main/resources/db/migration/postgresql/V1__baseline_schema.sql");
  const h2BaselineMigration = read("backend/src/main/resources/db/migration/h2/V1__baseline_schema.sql");
  const anonymousAuthDropMigration = read(
    "backend/src/main/resources/db/migration/postgresql/V5__drop_anonymous_auth_tables.sql",
  );
  const h2AnonymousAuthDropMigration = read(
    "backend/src/main/resources/db/migration/h2/V5__drop_anonymous_auth_tables.sql",
  );

  assert.match(build, /implementation 'org\.flywaydb:flyway-core'/);
  assert.match(build, /runtimeOnly 'org\.flywaydb:flyway-database-postgresql'/);
  assert.match(application, /flyway:[\s\S]*enabled: true/);
  assert.match(application, /locations: classpath:db\/migration\/\{vendor\}/);
  assert.match(applicationProd, /flyway:[\s\S]*enabled: true/);
  assert.match(applicationProd, /locations: classpath:db\/migration\/postgresql/);
  assert.match(applicationProd, /baseline-on-migrate: true/);
  assert.match(applicationProd, /baseline-version: 1/);
  assert.doesNotMatch(applicationProd, /schema-locations: classpath:db\/batch\/schema-postgresql\.sql/);
  assert.equal(
    existsSync(path.join(root, "backend/src/main/resources/db/batch/schema-postgresql.sql")),
    false,
    "legacy one-shot schema-postgresql.sql must be replaced by versioned migrations",
  );
  assert.match(baselineMigration, /CREATE TABLE IF NOT EXISTS BATCH_JOB_INSTANCE/);
  assert.match(baselineMigration, /CREATE TABLE IF NOT EXISTS facility_reports/);
  assert.match(baselineMigration, /CONSTRAINT fk_facility_report_review_audits_report/);
  assert.match(baselineMigration, /CREATE TABLE IF NOT EXISTS guest_accounts/);
  assert.match(h2BaselineMigration, /CREATE TABLE IF NOT EXISTS guest_accounts/);
  assert.match(baselineMigration, /CREATE TABLE IF NOT EXISTS anonymous_auth_tokens/);
  assert.match(h2BaselineMigration, /CREATE TABLE IF NOT EXISTS anonymous_auth_tokens/);
  assert.match(
    anonymousAuthDropMigration,
    /UPDATE route_feedbacks[\s\S]*UPDATE facility_reports[\s\S]*DELETE FROM user_activity_events[\s\S]*DELETE FROM push_notification_outbox[\s\S]*DELETE FROM registered_devices[\s\S]*DELETE FROM notification_settings[\s\S]*DELETE FROM mobility_profiles[\s\S]*DELETE FROM favorite_route_stations[\s\S]*DELETE FROM favorite_routes[\s\S]*DELETE FROM favorite_facilities[\s\S]*DELETE FROM favorite_stations[\s\S]*DROP TABLE IF EXISTS anonymous_auth_audit_events;[\s\S]*DROP TABLE IF EXISTS anonymous_auth_tokens;[\s\S]*DROP TABLE IF EXISTS guest_accounts;/,
  );
  assert.match(
    h2AnonymousAuthDropMigration,
    /UPDATE route_feedbacks[\s\S]*UPDATE facility_reports[\s\S]*DELETE FROM user_activity_events[\s\S]*DELETE FROM push_notification_outbox[\s\S]*DELETE FROM registered_devices[\s\S]*DELETE FROM notification_settings[\s\S]*DELETE FROM mobility_profiles[\s\S]*DELETE FROM favorite_route_stations[\s\S]*DELETE FROM favorite_routes[\s\S]*DELETE FROM favorite_facilities[\s\S]*DELETE FROM favorite_stations[\s\S]*DROP TABLE IF EXISTS anonymous_auth_audit_events;[\s\S]*DROP TABLE IF EXISTS anonymous_auth_tokens;[\s\S]*DROP TABLE IF EXISTS guest_accounts;/,
  );
  assert.doesNotMatch(h2BaselineMigration, /WHERE revoked_at IS NULL/);
});

function readPngPixelBounds(relativePath) {
  const png = readFileSync(path.join(root, relativePath));
  const signature = png.subarray(0, 8);
  assert.equal(signature.toString("hex"), "89504e470d0a1a0a", `${relativePath} must be a PNG file`);

  let offset = 8;
  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colorType = 0;
  const idatChunks = [];

  while (offset < png.length) {
    const length = png.readUInt32BE(offset);
    const type = png.subarray(offset + 4, offset + 8).toString("ascii");
    const dataStart = offset + 8;
    const dataEnd = dataStart + length;
    const data = png.subarray(dataStart, dataEnd);

    if (type === "IHDR") {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colorType = data[9];
    } else if (type === "IDAT") {
      idatChunks.push(data);
    } else if (type === "IEND") {
      break;
    }

    offset = dataEnd + 4;
  }

  assert.ok(width > 0 && height > 0, `${relativePath} must declare image size`);
  assert.ok([8, 16].includes(bitDepth), `${relativePath} must use 8-bit or 16-bit channels`);
  assert.ok([2, 6].includes(colorType), `${relativePath} must use RGB or RGBA pixels`);

  const hasAlpha = colorType === 6;
  const channels = hasAlpha ? 4 : 3;
  const bytesPerSample = bitDepth / 8;
  const bytesPerPixel = channels * bytesPerSample;
  const stride = width * bytesPerPixel;
  const inflated = inflateSync(Buffer.concat(idatChunks));
  const pixels = Buffer.alloc(height * stride);

  for (let y = 0; y < height; y++) {
    const sourceOffset = y * (stride + 1);
    const filter = inflated[sourceOffset];
    const source = inflated.subarray(sourceOffset + 1, sourceOffset + 1 + stride);
    const targetOffset = y * stride;

    for (let x = 0; x < stride; x++) {
      const left = x >= bytesPerPixel ? pixels[targetOffset + x - bytesPerPixel] : 0;
      const up = y > 0 ? pixels[targetOffset + x - stride] : 0;
      const upperLeft = y > 0 && x >= bytesPerPixel ? pixels[targetOffset + x - stride - bytesPerPixel] : 0;
      let reconstructed;

      if (filter === 0) {
        reconstructed = source[x];
      } else if (filter === 1) {
        reconstructed = source[x] + left;
      } else if (filter === 2) {
        reconstructed = source[x] + up;
      } else if (filter === 3) {
        reconstructed = source[x] + Math.floor((left + up) / 2);
      } else if (filter === 4) {
        const p = left + up - upperLeft;
        const pa = Math.abs(p - left);
        const pb = Math.abs(p - up);
        const pc = Math.abs(p - upperLeft);
        const predictor = pa <= pb && pa <= pc ? left : pb <= pc ? up : upperLeft;
        reconstructed = source[x] + predictor;
      } else {
        throw new Error(`${relativePath} uses unsupported PNG filter ${filter}`);
      }

      pixels[targetOffset + x] = reconstructed & 0xff;
    }
  }

  let minX = width;
  let minY = height;
  let maxX = -1;
  let maxY = -1;
  let maxCenterDistance = 0;
  const centerX = (width - 1) / 2;
  const centerY = (height - 1) / 2;

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const pixelOffset = y * stride + x * bytesPerPixel;
      const visible = hasAlpha
        ? pixels[pixelOffset + (channels - 1) * bytesPerSample] > 0
        : true;

      if (visible) {
        minX = Math.min(minX, x);
        minY = Math.min(minY, y);
        maxX = Math.max(maxX, x);
        maxY = Math.max(maxY, y);
        maxCenterDistance = Math.max(maxCenterDistance, Math.hypot(x - centerX, y - centerY));
      }
    }
  }

  return {
    width,
    height,
    hasAlpha,
    bounds: { minX, minY, maxX, maxY },
    maxCenterDistance,
  };
}

function assertAndroidLauncherIconSafeArea(relativePath, minimumInsetRatio) {
  const info = readPngPixelBounds(relativePath);
  assert.equal(info.width, info.height, `${relativePath} must be square`);
  assert.equal(info.hasAlpha, true, `${relativePath} must keep transparent launcher padding`);

  const minimumInset = info.width * minimumInsetRatio;
  assert.ok(info.bounds.minX >= minimumInset, `${relativePath} left padding is too small`);
  assert.ok(info.bounds.minY >= minimumInset, `${relativePath} top padding is too small`);
  assert.ok(info.width - 1 - info.bounds.maxX >= minimumInset, `${relativePath} right padding is too small`);
  assert.ok(info.height - 1 - info.bounds.maxY >= minimumInset, `${relativePath} bottom padding is too small`);
  assert.ok(
    info.maxCenterDistance <= info.width * 0.45,
    `${relativePath} has visible pixels too close to a circular launcher mask`,
  );
}

test("로컬 에이전트 문서와 README 외 Markdown은 gitignore로 추적되지 않는다", () => {
  const gitignore = read(".gitignore");

  assert.match(gitignore, /^\*\.md$/m);
  assert.match(gitignore, /^!\/README\.md$/m);
  assert.match(gitignore, /^!\/\.github\/pull_request_template\.md$/m);
  assert.match(gitignore, /^AGENTS\.md$/m);
  assert.match(gitignore, /^docs\/$/m);
  assert.match(gitignore, /^\.codex\/$/m);
});

test("지속적 통합은 README 외 Markdown과 로컬 에이전트 문서 추적 금지를 검사한다", () => {
  const workflow = read(".github/workflows/ci.yml");

  assert.match(workflow, /git ls-files '\*\.md' ':!:README\.md' ':!:\.github\/pull_request_template\.md'/);
  assert.match(workflow, /Unexpected tracked Markdown file/);
  assert.match(workflow, /git ls-files AGENTS\.md CLAUDE\.md GEMINI\.md CURSOR\.md COPILOT\.md docs \.codex/);
  assert.match(workflow, /Unexpected tracked local agent file/);
});

test("지속적 통합 작업과 스텝 이름은 실패 영역을 구분할 수 있게 표시된다", () => {
  const workflow = read(".github/workflows/ci.yml");

  assert.match(workflow, /workflow_dispatch:/);
  assert.match(workflow, /name: Changes/);
  assert.match(workflow, /name: Repository CI/);
  assert.match(workflow, /name: Backend CI/);
  assert.match(workflow, /name: Mobile App CI/);
  assert.match(workflow, /name: Android CI/);
  assert.doesNotMatch(workflow, /name: iOS CI/);
  assert.doesNotMatch(workflow, /runs-on: macos-latest/);
  assert.match(workflow, /Repository CI \/ Run contract tests/);
  assert.match(workflow, /Repository CI \/ Set up Chrome for route map tests/);
  assert.match(workflow, /CHROME_PATH: \$\{\{ steps\.setup-chrome\.outputs\.chrome-path \}\}/);
  assert.match(workflow, /ROUTE_MAP_CHROME_NO_SANDBOX: "1"/);
  assert.match(workflow, /Repository CI \/ Run route map tool tests/);
  assert.match(workflow, /Backend CI \/ Detect backend scaffold/);
  assert.match(workflow, /Mobile App CI \/ Run Flutter analyzer and tests/);
  assert.match(workflow, /Mobile App CI \/ Run mobile contracts/);
  assert.match(workflow, /Android CI \/ Build Flutter Android debug APK/);
  assert.doesNotMatch(workflow, /iOS CI \/ Build Flutter iOS simulator app/);
});

test("필수 지속적 통합 작업은 변경 없는 영역도 성공 상태로 종료한다", () => {
  const workflow = read(".github/workflows/ci.yml");
  const androidJob = workflow.match(/\n  android:[\s\S]*$/)?.[0] ?? "";

  assert.match(workflow, /Repository CI \/ Skip unchanged area/);
  assert.match(workflow, /Backend CI \/ Skip unchanged area/);
  assert.match(workflow, /Mobile App CI \/ Skip unchanged area/);
  assert.match(workflow, /Android CI \/ Skip unchanged area/);
  assert.doesNotMatch(workflow, /iOS CI \/ Skip unchanged area/);

  assert.doesNotMatch(jobBlock(workflow, "repository-contracts", "backend"), /\n    if:/);
  assert.doesNotMatch(jobBlock(workflow, "backend", "mobile-app"), /\n    if:/);
  assert.doesNotMatch(jobBlock(workflow, "mobile-app", "android"), /\n    if:/);
  assert.doesNotMatch(androidJob, /\n    if:/);
});

test("지속적 배포 준비 상태는 단일 dotenv secret과 배포 설정을 검증한다", () => {
  const workflow = read(".github/workflows/cd.yml");

  assert.match(workflow, /name: CD/);
  assert.match(workflow, /push:\s*\n\s*branches:\s*\n\s*-\s*main/);
  assert.match(workflow, /workflow_dispatch:/);
  assert.match(workflow, /permissions:\s*\n\s*contents:\s*read/);
  assert.match(workflow, /name: CD Readiness/);
  assert.match(workflow, /secrets\.EASYSUBWAY_ENV/);
  assert.match(workflow, /CD Readiness \/ Restore GitHub Actions dotenv secret/);
  assert.match(workflow, /CD Readiness \/ Restore GitHub Actions dotenv secret[\s\S]*?env:\s*\n\s*EASYSUBWAY_ENV_SECRET: \$\{\{ secrets\.EASYSUBWAY_ENV \}\}/);
  assert.match(workflow, /printf '%s' "\$\{EASYSUBWAY_ENV_SECRET\}" > "\$\{env_file\}"/);
  assert.doesNotMatch(workflow, /printf '%s\\n' "\$\{EASYSUBWAY_ENV_SECRET\}"/);
  assert.match(workflow, /CD Readiness \/ Validate deployment dotenv contract/);
  assert.match(workflow, /CD Readiness \/ Validate Docker Compose deployment config/);
  assert.match(workflow, /docker compose --env-file "\$\{EASYSUBWAY_ENV_FILE\}" -f infra\/docker-compose\.yml config --quiet/);
  assert.match(workflow, /EASYSUBWAY_ENV secret is not configured/);
  assert.doesNotMatch(workflow, /runs-on: ubuntu-latest\s*\n\s*env:\s*\n\s*EASYSUBWAY_ENV_SECRET/);
  assert.doesNotMatch(workflow, /secrets\.EASYSUBWAY_(DATASOURCE|REDIS|TRUSTED_PROXY|POSTGRES)/);
});

test("풀 리퀘스트 템플릿은 리뷰와 배포 확인 게이트를 포함한다", () => {
  const template = read(".github/pull_request_template.md");

  assert.match(template, /## 관련 이슈/);
  assert.match(template, /## 검증/);
  assert.match(template, /실행한 명령과 결과/);
  assert.match(template, /리뷰어가 먼저 봐야 할 지점/);
  assert.match(template, /CodeRabbit 리뷰를 확인했다/);
  assert.match(template, /Codex CLI code review 결과를 확인했다/);
  assert.match(template, /CD 상태를 확인했다/);
});

test("이슈 템플릿은 에이전트 서술 없이 개발자 판단 정보를 수집한다", () => {
  const templates = [
    read(".github/ISSUE_TEMPLATE/bug_report.yml"),
    read(".github/ISSUE_TEMPLATE/feature_request.yml"),
    read(".github/ISSUE_TEMPLATE/task_request.yml"),
  ].join("\n");

  assert.match(templates, /실제 개발자가 바로 판단할 수 있게/);
  assert.match(templates, /사용자 또는 운영 영향/);
  assert.match(templates, /실행할 검증/);
  assert.doesNotMatch(templates, /AI 에이전트|자동 생성|제가 작업/);
});

test("한국어 저장소 리뷰 기준으로 CodeRabbit이 설정된다", () => {
  const config = read(".coderabbit.yaml");

  assert.match(config, /language: "ko-KR"/);
  assert.match(config, /path: "backend\/\*\*"/);
  assert.match(config, /path: "apps\/mobile\/lib\/\*\*"/);
  assert.match(config, /path: "\.github\/workflows\/\*\*"/);
  assert.match(config, /auto_review:/);
});

test("환경 예시는 비밀값 없는 로컬 데이터 인프라 기본값을 제공한다", () => {
  const envExample = read(".env.example");

  assert.match(envExample, /^EASYSUBWAY_POSTGRES_DB=easysubway$/m);
  assert.match(envExample, /^EASYSUBWAY_POSTGRES_USER=easysubway$/m);
  assert.match(envExample, /^EASYSUBWAY_POSTGRES_PASSWORD=easysubway_local$/m);
  assert.match(envExample, /^EASYSUBWAY_POSTGRES_PORT=5432$/m);
  assert.match(envExample, /^EASYSUBWAY_DATASOURCE_URL=jdbc:postgresql:\/\/localhost:5432\/easysubway$/m);
  assert.match(envExample, /^EASYSUBWAY_DATASOURCE_USERNAME=easysubway$/m);
  assert.match(envExample, /^EASYSUBWAY_DATASOURCE_PASSWORD=easysubway_local$/m);
  assert.match(envExample, /^EASYSUBWAY_DATA_PACK_BASE_URL=http:\/\/localhost:9000\/easysubway-datapacks$/m);
  assert.match(envExample, /^EASYSUBWAY_REPORT_API_BASE_URL=http:\/\/localhost:8080$/m);
  assert.match(envExample, /^EASYSUBWAY_REPORT_RECEIPT_PEPPER=$/m);
  assert.match(envExample, /^EASYSUBWAY_REPORT_UPLOAD_BUCKET=easysubway-report-uploads$/m);
  assert.match(envExample, /^EASYSUBWAY_REPORT_UPLOAD_MAX_BYTES=921600$/m);
  assert.match(envExample, /^EASYSUBWAY_REPORT_UPLOAD_URL_TTL_SECONDS=900$/m);
  assert.match(envExample, /^EASYSUBWAY_REPORT_UPLOAD_INTENT_SIGNING_KEY=$/m);
  assert.match(envExample, /^EASYSUBWAY_OBJECT_STORAGE_ENDPOINT=http:\/\/localhost:9000$/m);
  assert.match(envExample, /^EASYSUBWAY_OBJECT_STORAGE_ACCESS_KEY=easysubway_local$/m);
  assert.match(envExample, /^EASYSUBWAY_OBJECT_STORAGE_SECRET_KEY=$/m);
  assert.match(envExample, /^EASYSUBWAY_OBJECT_STORAGE_REGION=us-east-1$/m);
  assert.match(envExample, /^EASYSUBWAY_OBJECT_STORAGE_PREAUTH_BASE_URL=$/m);
  assert.match(envExample, /^EASYSUBWAY_DATAPACK_BUCKET=easysubway-datapacks$/m);
  assert.match(envExample, /^EASYSUBWAY_DATAPACK_SIGNING_PRIVATE_KEY_PEM=$/m);
  assert.match(envExample, /^EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_PEM=$/m);
  assert.match(envExample, /^EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_N=$/m);
  assert.match(envExample, /^EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_E=$/m);
  assert.doesNotMatch(envExample, /^EASYSUBWAY_REDIS_/m);
  assert.match(envExample, /^EASYSUBWAY_TRUSTED_PROXY_CIDRS=$/m);
  assert.match(envExample, /^EASYSUBWAY_PUSH_EXTERNAL_ENABLED=false$/m);
  assert.match(envExample, /^EASYSUBWAY_ADMIN_USERNAME=$/m);
  assert.match(envExample, /^EASYSUBWAY_ADMIN_PASSWORD=$/m);
  assert.match(envExample, /^EASYSUBWAY_SECURITY_EMAIL=$/m);
  assert.doesNotMatch(envExample, /prod|production/i);
  assert.doesNotMatch(
    envExample,
    /^EASYSUBWAY_(REPORT_RECEIPT_PEPPER|OBJECT_STORAGE_SECRET_KEY|OBJECT_STORAGE_PREAUTH_BASE_URL|DATAPACK_SIGNING_PRIVATE_KEY_PEM|DATAPACK_SIGNING_PUBLIC_KEY_PEM|DATAPACK_SIGNING_PUBLIC_KEY_N|DATAPACK_SIGNING_PUBLIC_KEY_E)=.+$/m,
  );
});

test("OCI Terraform 기준선은 비밀 파일을 추적하지 않고 데이터팩 출력 계약을 제공한다", () => {
  const terraformDir = "infra/terraform/oci/always-free-a1-flex";
  const trackedInfraFiles = execFileSync("git", ["ls-files", "--cached", terraformDir], {
    cwd: root,
    encoding: "utf8",
  }).trim().split("\n").filter(Boolean);

  assert.ok(trackedInfraFiles.includes(`${terraformDir}/terraform.tfvars.example`));
  assert.ok(trackedInfraFiles.includes(`${terraformDir}/datapack_object_storage.tf`));
  assert.equal(
    trackedInfraFiles.some((file) => /(?:^|\/)(terraform\.tfvars|terraform\.tfvars\.json|[^/]+\.auto\.tfvars|[^/]+\.auto\.tfvars\.json)$/.test(file)),
    false,
    "real Terraform variable files must stay untracked",
  );
  assert.equal(
    trackedInfraFiles.some((file) =>
      /\.(tfstate|tfplan|pem|key|ppk)$/.test(file)
      || /(?:^|\/)id_(?:rsa|dsa|ecdsa|ed25519)(?:\.pub)?$/.test(file)
      || file.includes("/.terraform/")
    ),
    false,
    "Terraform state, plan, provider cache, and private keys must stay untracked",
  );

  const gitignore = read(".gitignore");
  assert.match(gitignore, /^\*\*\/\.terraform\/$/m);
  assert.match(gitignore, /^\*\*\/\*\.tfstate$/m);
  assert.match(gitignore, /^\*\*\/\*\.tfplan$/m);
  assert.match(gitignore, /^\*\*\/terraform\.tfvars$/m);
  assert.match(gitignore, /^!\*\*\/terraform\.tfvars\.example$/m);

  const variables = read(`${terraformDir}/variables.tf`);
  const locals = read(`${terraformDir}/locals.tf`);
  const providers = read(`${terraformDir}/providers.tf`);
  const datapackStorage = read(`${terraformDir}/datapack_object_storage.tf`);
  const outputs = read(`${terraformDir}/outputs.tf`);
  const tfvarsExample = read(`${terraformDir}/terraform.tfvars.example`);

  assert.match(variables, /default\s+= "easysubway-a1"/);
  assert.match(variables, /default\s+= "easysubway-datapacks"/);
  assert.match(variables, /variable "identity_home_region"/);
  assert.match(variables, /variable "datapack_object_prefix"[\s\S]*?default\s+= ""/);
  assert.match(variables, /default\s+= "ObjectReadWithoutList"/);
  assert.match(variables, /datapack_public_base_url_override/);
  assert.match(providers, /alias\s+= "identity_home"/);
  assert.match(providers, /region\s+= coalesce\(var\.identity_home_region, var\.region\)/);
  assert.match(locals, /datapack\.aquilaxk\.site|datapack_oci_base_url/);
  assert.match(datapackStorage, /resource "oci_objectstorage_bucket" "datapack"/);
  assert.match(datapackStorage, /access_type\s+= var\.datapack_bucket_public_access_type/);
  assert.match(datapackStorage, /versioning\s+= "Enabled"/);
  assert.match(datapackStorage, /resource "oci_identity_customer_secret_key" "datapack_publisher"/);
  assert.match(datapackStorage, /provider\s+= oci\.identity_home/);
  assert.match(datapackStorage, /display_name\s+= "\$\{var\.name_prefix\}-datapack-publisher"/);
  assert.match(datapackStorage, /user_id\s+= var\.user_ocid/);
  assert.match(outputs, /EASYSUBWAY_DATA_PACK_BASE_URL/);
  assert.match(outputs, /EASYSUBWAY_DATAPACK_BUCKET/);
  assert.match(outputs, /EASYSUBWAY_OBJECT_STORAGE_ENDPOINT/);
  assert.match(outputs, /EASYSUBWAY_OBJECT_STORAGE_REGION/);
  assert.doesNotMatch(outputs, /EASYSUBWAY_OBJECT_STORAGE_(?:ACCESS_KEY|SECRET_KEY)/);
  assert.doesNotMatch(outputs, /oci_identity_customer_secret_key\.datapack_publisher\.(?:id|key)/);
  assert.match(tfvarsExample, /fingerprint\s+= "00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00"/);
  assert.match(tfvarsExample, /identity_home_region = "ap-chuncheon-1"/);
  assert.match(tfvarsExample, /datapack\.aquilaxk\.site/);
  assert.doesNotMatch(tfvarsExample, /ocid1\.(?:tenancy|user|compartment)\.oc1\.[a-z0-9]{20,}/);
});

test("GitHub Actions 환경값은 dotenv secret 하나로 관리한다", () => {
  const readme = read("README.md");
  const script = read("scripts/github/sync-actions-env-secret.sh");
  const cdWorkflow = read(".github/workflows/cd.yml");

  assert.match(readme, /`EASYSUBWAY_ENV` secret 하나/);
  assert.match(readme, /GitHub Actions secret 이름은 반드시 `EASYSUBWAY_ENV`만 사용합니다/);
  assert.match(readme, /scripts\/github\/sync-actions-env-secret\.sh \.env/);
  assert.match(readme, /secrets\.EASYSUBWAY_ENV/);
  assert.match(readme, /CD workflow는 `EASYSUBWAY_ENV` secret이 있으면 배포 dotenv 계약을 검증/);
  assert.match(script, /readonly SECRET_NAME="EASYSUBWAY_ENV"/);
  assert.doesNotMatch(script, /EASYSUBWAY_ACTIONS_ENV_SECRET_NAME/);
  assert.match(script, /gh secret set "\$\{SECRET_NAME\}" --repo "\$\{REPO\}" < "\$\{ENV_FILE\}"/);
  assert.match(script, /\.env\.example is a template/);
  assert.match(cdWorkflow, /tools\/ci\/validate-deployment-env\.sh "\$\{EASYSUBWAY_ENV_FILE\}"/);

  for (const file of workflowFiles()) {
    const source = read(file);
    assertActionsEnvSecretPolicy(file, source);
  }
});

test("CD dotenv 검증은 운영 fallback env 계약을 반영한다", async () => {
  const dir = await mkdtemp(path.join(tmpdir(), "easysubway-cd-env-"));
  const envFile = path.join(dir, "deploy.env");
  await writeFile(envFile, [
    "EASYSUBWAY_POSTGRES_DB=easysubway",
    "EASYSUBWAY_POSTGRES_USER=easysubway",
    "EASYSUBWAY_POSTGRES_PASSWORD=secret",
    "EASYSUBWAY_POSTGRES_PORT=5432",
    "EASYSUBWAY_DATASOURCE_URL=jdbc:postgresql://db:5432/easysubway",
    "EASYSUBWAY_DATASOURCE_USERNAME=easysubway",
    "EASYSUBWAY_DATASOURCE_PASSWORD=secret",
    "EASYSUBWAY_DATA_PACK_BASE_URL=https://cdn.example.com/easysubway-datapacks",
    "EASYSUBWAY_REPORT_API_BASE_URL=https://api.example.com",
    "EASYSUBWAY_REPORT_RECEIPT_TOKEN_PEPPER=legacy-pepper-with-enough-entropy",
    "EASYSUBWAY_REPORT_UPLOAD_BUCKET=easysubway-report-uploads",
    "EASYSUBWAY_REPORT_UPLOAD_MAX_BYTES=921600",
    "EASYSUBWAY_REPORT_UPLOAD_URL_TTL_SECONDS=900",
    "EASYSUBWAY_OBJECT_STORAGE_ENDPOINT=https://object-storage.example.com",
    "EASYSUBWAY_OBJECT_STORAGE_ACCESS_KEY=access-key",
    "EASYSUBWAY_OBJECT_STORAGE_SECRET_KEY=secret-key",
    "EASYSUBWAY_DATAPACK_BUCKET=easysubway-datapacks",
    "EASYSUBWAY_DATAPACK_SIGNING_PRIVATE_KEY_PEM=private-key-pem",
    "EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_PEM=public-key-pem",
    "EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_N=public-key-modulus",
    "EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_E=AQAB",
    "EASYSUBWAY_TRUSTED_PROXY_CIDRS=",
    "EASYSUBWAY_PUSH_EXTERNAL_ENABLED=false",
    "EASYSUBWAY_ENABLE_PUSH_NOTIFICATIONS=false",
    "EASYSUBWAY_ADMIN_USERNAME=admin",
    "EASYSUBWAY_ADMIN_PASSWORD=secret",
    "EASYSUBWAY_PRIVACY_POLICY_URL=https://example.com/privacy",
    "EASYSUBWAY_SUPPORT_EMAIL=support@example.com",
    "EASYSUBWAY_SECURITY_EMAIL=security@example.com",
    "EASYSUBWAY_DATA_DELETION_EMAIL=privacy@example.com",
    "EASYSUBWAY_ANDROID_KEYSTORE_PATH=",
    "EASYSUBWAY_ANDROID_STORE_PASSWORD=",
    "EASYSUBWAY_ANDROID_KEY_ALIAS=",
    "EASYSUBWAY_ANDROID_KEY_PASSWORD=",
    "",
  ].join("\n"));

  await execFileAsync("tools/ci/validate-deployment-env.sh", [envFile], { cwd: root });

  await writeFile(envFile, "EASYSUBWAY_POSTGRES_DB=easysubway\n");
  await assert.rejects(
    execFileAsync("tools/ci/validate-deployment-env.sh", [envFile], { cwd: root }),
    /Missing required deployment env names/
  );
});

test("GitHub Actions 환경값 계약은 bracket notation 우회를 차단한다", () => {
  assert.throws(
    () => assertActionsEnvSecretPolicy("example.yml", "env:\n  DB: ${{ secrets['EASYSUBWAY_DATABASE_URL'] }}"),
    /example\.yml must use only secrets\.EASYSUBWAY_ENV/,
  );
  assert.throws(
    () => assertActionsEnvSecretPolicy("example.yml", "env:\n  DB: ${{ vars['EASYSUBWAY_DATABASE_URL'] }}"),
    /example\.yml must not use GitHub Actions vars for app env/,
  );
});

test("모바일 generic catch는 원본 예외와 스택을 버리지 않는다", () => {
  const mobileFiles = execFileSync("git", ["ls-files", "apps/mobile/lib/*.dart"], {
    cwd: root,
    encoding: "utf8",
  }).trim().split("\n").filter(Boolean);

  assert.ok(mobileFiles.length > 0, "mobile Dart files not found");
  for (const file of mobileFiles) {
    assertMobileCatchPolicy(file, read(file));
  }
});

test("Android 권한 파서는 속성 순서와 추가 속성이 달라도 권한명을 추출한다", () => {
  const permissions = androidManifestPermissions(`
    <manifest xmlns:android="http://schemas.android.com/apk/res/android">
      <uses-permission android:maxSdkVersion="32" android:name="android.permission.READ_EXTERNAL_STORAGE" />
      <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="35" />
      <uses-permission android:name="com.easysubway.easysubway_mobile.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION" />
    </manifest>
  `);

  assert.deepEqual(permissions, [
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.READ_EXTERNAL_STORAGE",
  ]);
});

test("모바일 변경 CI는 모바일 계약 테스트를 실행한다", () => {
  const workflow = read(".github/workflows/ci.yml");
  const mobileJob = jobBlock(workflow, "mobile-app", "android");

  assert.match(mobileJob, /Mobile App CI \/ Set up Node\.js for mobile contracts/);
  assert.match(mobileJob, /Mobile App CI \/ Generate Android release merged manifest/);
  assert.match(mobileJob, /EASYSUBWAY_ANDROID_KEYSTORE_PATH: ci-release-manifest-only\.jks/);
  assert.match(mobileJob, /EASYSUBWAY_ANDROID_STORE_PASSWORD: ci-release-manifest-only/);
  assert.match(mobileJob, /EASYSUBWAY_ANDROID_KEY_ALIAS: ci-release-manifest-only/);
  assert.match(mobileJob, /EASYSUBWAY_ANDROID_KEY_PASSWORD: ci-release-manifest-only/);
  assert.match(mobileJob, /flutter pub get/);
  assert.match(mobileJob, /flutter build apk --config-only/);
  assert.match(mobileJob, /android\/gradlew -p android :app:processReleaseMainManifest --no-daemon/);
  assert.match(mobileJob, /Mobile App CI \/ Run mobile contracts/);
  assert.match(mobileJob, /EASYSUBWAY_EXPECT_ANDROID_RELEASE_MANIFEST: "true"/);
  assert.match(
    mobileJob,
    /node --test --test-name-pattern "모바일 generic catch\|모바일 접근성 출시 QA\|릴리즈 보안 기준선\|모바일 스토어 심사 정보 기준선\|모바일 스토어 개인정보 인벤토리\|Android 릴리즈 권한\|iOS 앱은 개인정보 매니페스트\|Android 런처 아이콘" tools\/ci\/repository-contract\.test\.mjs/,
  );
});

test("OSV 의존성 취약점 게이트는 PR 의존성 취약점을 차단한다", () => {
  const workflow = read(".github/workflows/ci.yml");
  const dependencyScanJob = jobBlock(workflow, "dependency-vulnerability-scan", "repository-contracts");

  assert.match(workflow, /permissions:\s*\n\s*contents:\s*read/);
  assert.match(dependencyScanJob, /name: Dependency Vulnerability Scan/);
  assert.match(dependencyScanJob, /needs: changes/);
  assert.match(dependencyScanJob, /github\.event_name == 'pull_request'/);
  assert.match(dependencyScanJob, /needs\.changes\.outputs\.docs_only != 'true'/);
  assert.match(dependencyScanJob, /actions:\s*read/);
  assert.match(dependencyScanJob, /security-events:\s*write/);
  assert.match(dependencyScanJob, /contents:\s*read/);
  assert.match(
    dependencyScanJob,
    /uses: google\/osv-scanner-action\/\.github\/workflows\/osv-scanner-reusable-pr\.yml@9a498708959aeaef5ef730655706c5a1df1edbc2/,
  );
  assert.match(dependencyScanJob, /scan-args:\s*\|-/);
  assert.match(dependencyScanJob, /--lockfile=apps\/mobile\/pubspec\.lock/);
  assert.match(dependencyScanJob, /--lockfile=apps\/mobile\/android\/app\/gradle\.lockfile/);
  assert.match(dependencyScanJob, /--lockfile=backend\/gradle\.lockfile/);
  assert.doesNotMatch(dependencyScanJob, /--config=/);
  assert.doesNotMatch(dependencyScanJob, /-r \.\/|--recursive/);
});

test("OSV 의존성 취약점 게이트는 Gradle lockfile을 스캔 근거로 추적한다", () => {
  const backendBuild = read("backend/build.gradle");
  const androidBuild = read("apps/mobile/android/build.gradle.kts");
  const backendLockfile = read("backend/gradle.lockfile");
  const androidLockfile = read("apps/mobile/android/app/gradle.lockfile");

  assert.match(backendBuild, /dependencyLocking\s*\{\s*lockAllConfigurations\(\)\s*\}/);
  assert.match(
    androidBuild,
    /dependencyLocking\s*\{[\s\S]*?lockAllConfigurations\(\)[\s\S]*?ignoredDependencies\.add\("io\.flutter:\*"\)[\s\S]*?\}/,
  );
  assert.match(backendLockfile, /This is a Gradle generated file for dependency locking/);
  assert.match(androidLockfile, /This is a Gradle generated file for dependency locking/);
  assert.match(backendLockfile, /\n[^#\n][^=\n]+=/);
  assert.match(androidLockfile, /\n[^#\n][^=\n]+=/);
  assert.doesNotMatch(androidLockfile, /^io\.flutter:/m);
});

test("릴리즈 산출물 워크플로우는 모바일 스토어 산출물과 backend image 검증을 생성한다", () => {
  assert.equal(
    existsSync(path.join(root, ".github/workflows/release-artifacts.yml")),
    true,
    "release artifact workflow must exist",
  );

  const workflow = read(".github/workflows/release-artifacts.yml");

  assert.match(workflow, /^name: Release Artifacts$/m);
  assert.match(workflow, /pull_request:[\s\S]*branches:[\s\S]*- main/);
  assert.match(workflow, /push:[\s\S]*branches:[\s\S]*- main/);
  assert.match(workflow, /workflow_dispatch:/);
  assert.match(workflow, /permissions:\s*\n\s*contents: read/);
  assert.match(workflow, /group: release-artifacts-\$\{\{ github\.workflow \}\}-\$\{\{ github\.ref \}\}/);

  assertActionsEnvSecretPolicy(".github/workflows/release-artifacts.yml", workflow);

  assert.match(workflow, /android-release:/);
  assert.match(workflow, /name: Android Release Artifact/);
  assert.match(workflow, /keytool -genkeypair/);
  assert.match(workflow, /EASYSUBWAY_ANDROID_KEYSTORE_PATH: \$\{\{ runner\.temp \}\}\/easysubway-ci-release\.jks/);
  assert.match(workflow, /EASYSUBWAY_ANDROID_STORE_PASSWORD: ci-release-password/);
  assert.match(workflow, /EASYSUBWAY_ANDROID_KEY_ALIAS: ci-release/);
  assert.match(workflow, /EASYSUBWAY_ANDROID_KEY_PASSWORD: ci-release-password/);
  assert.match(workflow, /flutter build appbundle --release/);
  assert.equal(
    (workflow.match(/--dart-define=EASYSUBWAY_API_BASE_URL=https:\/\/\S+\.local/g) ?? []).length,
    0,
  );
  assert.match(workflow, /Release Artifacts \/ Restore GitHub Actions dotenv secret/);
  assert.match(workflow, /tools\/ci\/validate-store-privacy-env\.mjs --env-file "\$\{env_file\}" --github-env "\$\{GITHUB_ENV\}"/);
  assert.match(workflow, /EASYSUBWAY_ENV_SECRET: \$\{\{ secrets\.EASYSUBWAY_ENV \}\}/);
  assert.match(workflow, /GITHUB_EVENT_NAME[^=]+== "pull_request"/);
  assert.match(workflow, /EASYSUBWAY_RELEASE_ARTIFACTS_SKIP_BUILD=true/);
  assert.match(workflow, /Release Artifact \/ Record non-store-ready PR gate/);
  assert.match(workflow, /if: \$\{\{ env\.EASYSUBWAY_RELEASE_ARTIFACTS_SKIP_BUILD != 'true' \}\}/);
  assert.match(workflow, /--dart-define=EASYSUBWAY_PRIVACY_POLICY_URL="\$\{EASYSUBWAY_PRIVACY_POLICY_URL\}"/);
  assert.match(workflow, /--dart-define=EASYSUBWAY_SUPPORT_EMAIL="\$\{EASYSUBWAY_SUPPORT_EMAIL\}"/);
  assert.match(workflow, /--dart-define=EASYSUBWAY_DATA_DELETION_EMAIL="\$\{EASYSUBWAY_DATA_DELETION_EMAIL\}"/);
  assert.match(workflow, /--dart-define=EASYSUBWAY_SECURITY_EMAIL="\$\{EASYSUBWAY_SECURITY_EMAIL\}"/);
  assert.match(workflow, /--dart-define=EASYSUBWAY_ENABLE_PUSH_NOTIFICATIONS=false/);
  assert.match(workflow, /build\/app\/outputs\/bundle\/release\/app-release\.aab/);
  assert.match(workflow, /build\/app\/outputs\/mapping\/release\/mapping\.txt/);
  assert.match(workflow, /name: easysubway-android-release-\$\{\{ github\.sha \}\}/);

  assert.doesNotMatch(workflow, /ios-release:/);
  assert.doesNotMatch(workflow, /name: iOS Release Artifact/);
  assert.doesNotMatch(workflow, /runs-on: macos-latest/);
  assert.doesNotMatch(workflow, /flutter build ios --release --no-codesign/);
  assert.doesNotMatch(workflow, /name: easysubway-ios-release-\$\{\{ github\.sha \}\}/);

  assert.match(workflow, /backend-release:/);
  assert.match(workflow, /name: Backend Release Image/);
  assert.match(workflow, /working-directory: backend[\s\S]*?\.\/gradlew bootJar --no-daemon/);
  assert.match(workflow, /docker build -f backend\/Dockerfile -t easysubway-backend:\$\{\{ github\.sha \}\} backend/);
  assert.match(workflow, /docker image inspect easysubway-backend:\$\{\{ github\.sha \}\}/);
  assert.match(workflow, /docker compose --env-file \.env\.example -f infra\/docker-compose\.yml config --quiet/);
  assert.match(workflow, /name: easysubway-backend-release-\$\{\{ github\.sha \}\}/);
});

test("모바일 signed release artifact gate는 CI 산출물과 스토어 제출 준비 상태를 분리한다", () => {
  const gatePath = "apps/mobile/release/signed-release-artifact-gate.json";

  assert.equal(existsSync(path.join(root, gatePath)), true, "signed release artifact gate must exist");

  const gate = readJson(gatePath);
  const workflow = read(".github/workflows/release-artifacts.yml");
  const readme = read("README.md");

  assert.equal(gate.schemaVersion, 1);
  assert.equal(gate.applicationId, "easysubway");
  assert.equal(gate.androidApplicationId, "com.easysubway.app");
  assert.equal(gate.releaseGate, "mobile-signed-release-artifacts");
  assert.equal(gate.storeReadyStatus, "blocked_external_distribution_evidence_missing");

  assert.equal(gate.officialRequirements.android.targetApiLevelMinimum, 35);
  assert.equal(gate.officialRequirements.android.requiredFrom, "2025-08-31");
  assert.match(gate.officialRequirements.android.source, /^https:\/\/support\.google\.com\/googleplay\/android-developer\/answer\/11926878/);
  assert.equal(gate.officialRequirements.ios.minimumXcodeMajor, 26);
  assert.equal(gate.officialRequirements.ios.minimumSdkMajor, 26);
  assert.equal(gate.officialRequirements.ios.requiredFrom, "2026-04-28");
  assert.match(gate.officialRequirements.ios.source, /^https:\/\/developer\.apple\.com\/news\/upcoming-requirements\//);

  assert.equal(gate.artifacts.android.format, "aab");
  assert.equal(gate.artifacts.android.ciArtifactStoreReady, false);
  assert.equal(gate.artifacts.android.ciSigningKeyType, "temporary-self-signed");
  assert.equal(gate.artifacts.android.symbolArtifact, "mapping.txt");
  assert.equal(gate.artifacts.android.symbolRetentionDays, 90);
  assert.ok(gate.artifacts.android.storeReadyRequires.includes("production signing key material"));
  assert.ok(gate.artifacts.android.storeReadyRequires.includes("Play internal track upload or pre-launch report evidence"));

  assert.equal(gate.artifacts.ios.format, "Runner.app.zip");
  assert.equal(gate.artifacts.ios.ciArtifactStoreReady, false);
  assert.equal(gate.artifacts.ios.ciArtifactProducer, "deferred_until_ios_release_phase");
  assert.equal(gate.artifacts.ios.ciSigningKeyType, "not-produced");
  assert.equal(gate.artifacts.ios.symbolArtifact, "dSYM");
  assert.equal(gate.artifacts.ios.symbolRetentionDays, 90);
  assert.ok(gate.artifacts.ios.storeReadyRequires.includes("Apple distribution signing"));
  assert.ok(gate.artifacts.ios.storeReadyRequires.includes("TestFlight or signed-device install evidence"));

  assert.equal(gate.evidencePolicy.localOnlyEvidencePath, ".codex/evidence/release/mobile-signed-artifacts/");
  assert.equal(gate.evidencePolicy.githubUploadPolicy, "summary-only");

  assert.match(workflow, /toolchain_policy=apps\/mobile\/release\/signed-release-artifact-gate\.json/);
  assert.match(workflow, /store_ready=false/);
  assert.match(workflow, /signing_key_type=temporary-self-signed/);
  assert.match(workflow, /play_submission_evidence=blocked_missing_internal_track_or_prelaunch_report/);
  assert.match(workflow, /cp release\/signed-release-artifact-gate\.json release-artifacts\/android\/signed-release-artifact-gate\.json/);
  assert.doesNotMatch(workflow, /signing_key_type=no-codesign/);
  assert.doesNotMatch(workflow, /testflight_evidence=blocked_missing_testflight_or_signed_device_install/);
  assert.doesNotMatch(workflow, /cp release\/signed-release-artifact-gate\.json release-artifacts\/ios\/signed-release-artifact-gate\.json/);

  assert.match(readme, /signed release artifact gate/);
  assert.match(readme, /Android-first 배포 파이프라인은 Android AAB와 backend image만 생성/);
  assert.match(readme, /Android 15 \(API 35\)/);
  assert.match(readme, /Xcode 26/);
  assert.match(readme, /TestFlight/);
  assert.match(readme, /dSYM 90일 보관 workflow/);
  assert.match(readme, /Play internal track/);
});

test("Android release 100 governance gate는 Android-only 범위와 evidence schema를 고정한다", () => {
  const gatePath = "apps/mobile/release/release-governance-gate.json";
  assert.equal(existsSync(path.join(root, gatePath)), true, "release governance gate must exist");

  const gate = readJson(gatePath);
  const readme = read("README.md");

  assert.equal(gate.schemaVersion, 1);
  assert.equal(gate.applicationId, "easysubway");
  assert.equal(gate.releaseGate, "android-release-100-governance");
  assert.equal(gate.releaseTarget.platform.android, "RELEASE_REQUIRED");
  assert.equal(gate.releaseTarget.platform.ios, "DEFERRED_OUT_OF_SCOPE");
  assert.equal(gate.releaseTarget.distribution, "google-play");
  assert.equal(gate.releaseTarget.packageId, "com.easysubway.app");
  assert.equal(gate.releaseTarget.primaryLocale, "ko-KR");
  assert.deepEqual(gate.releaseTarget.initialCountries, ["KR"]);
  assert.equal(gate.releaseTarget.targetApiMinimum, 35);
  assert.equal(gate.releaseTarget.appAccountCreation, false);
  assert.equal(gate.releaseTarget.ads, false);
  assert.equal(gate.releaseTarget.payment, false);

  assert.deepEqual(gate.gateStatusEnum, [
    "NOT_STARTED",
    "IN_PROGRESS",
    "BLOCKED_EXTERNAL",
    "BLOCKED_TECHNICAL",
    "SATISFIED",
    "DEFERRED_OUT_OF_SCOPE",
    "WAIVED_UNTIL",
    "INVALIDATED",
  ]);

  assert.deepEqual(gate.requiredRcEvidenceFields, [
    "gitSha",
    "appVersionName",
    "versionCode",
    "aabSha256",
    "backendArtifactSha256",
    "dataPackManifestSha256",
    "releaseSequence",
    "routeContractVersion",
    "realtimeContractVersion",
    "device",
    "androidVersion",
    "testedAt",
    "evidencePaths",
    "expiresWhen",
  ]);

  assert.equal(gate.releaseReadiness.openAndroidP0BlocksGo, true);
  assert.equal(gate.releaseReadiness.iosBlocksAndroidRelease, false);
  assert.ok(gate.releaseReadiness.p0EscalationRules.includes("measured_performance_budget_failure"));
  assert.ok(gate.releaseReadiness.p0EscalationRules.includes("play_prelaunch_crash"));
  assert.ok(gate.gates.some((item) => item.issue === 917 && item.id === "G7_ANDROID_QUALITY"));
  assert.ok(gate.gates.some((item) => item.issue === 907 && item.id === "G9_GOOGLE_PLAY"));
  assert.doesNotMatch(JSON.stringify(gate), /\b(TBD|TODO|PLACEHOLDER)\b|\.{3}/i);

  assert.match(readme, /release-governance-gate\.json/);
  assert.match(readme, /Android Google Play v1/);
  assert.match(readme, /iOS는 `DEFERRED_OUT_OF_SCOPE`/);
});

test("릴리즈 산출물 워크플로우는 관련 변경에서만 비용 큰 산출물 빌드를 실행한다", async () => {
  const workflow = read(".github/workflows/release-artifacts.yml");
  const detector = read("tools/ci/detect-changed-paths.sh");
  const androidReleaseJob = jobBlock(workflow, "android-release", "backend-release");
  const backendReleaseJob = workflow.match(/\n  backend-release:[\s\S]*$/)?.[0] ?? "";

  assert.match(workflow, /changes:\s*\n\s*name: Changes/);
  assert.match(workflow, /outputs:[\s\S]*android: \$\{\{ steps\.filter\.outputs\.android \}\}/);
  assert.match(workflow, /bash tools\/ci\/detect-changed-paths\.sh changed-files\.txt/);
  assert.match(androidReleaseJob, /needs: changes/);
  assert.match(androidReleaseJob, /if: \$\{\{ needs\.changes\.outputs\.android == 'true' \|\| needs\.changes\.outputs\.mobile == 'true' \}\}/);
  assert.doesNotMatch(workflow, /ios-release:/);
  assert.match(backendReleaseJob, /needs: changes/);
  assert.match(backendReleaseJob, /if: \$\{\{ needs\.changes\.outputs\.backend == 'true' \|\| needs\.changes\.outputs\.deploy == 'true' \}\}/);
  assert.match(detector, /apps\/mobile\/release\/\*\*/);
  assert.match(detector, /apps\/mobile\/android\/app\/build\.gradle\.kts/);
  assert.match(detector, /apps\/mobile\/ios\/Runner\.xcodeproj\/\*\*/);

  const tempDir = await mkdtemp(path.join(tmpdir(), "easysubway-release-paths-"));
  const changedFiles = path.join(tempDir, "changed-files.txt");
  await writeFile(
    changedFiles,
    [
      "apps/mobile/release/store-submission-readiness.json",
      "apps/mobile/android/app/build.gradle.kts",
      "apps/mobile/ios/Runner.xcodeproj/project.pbxproj",
      "tools/datapack/build-datapack.mjs",
    ].join("\n") + "\n",
  );
  const detectorEnv = { ...process.env };
  delete detectorEnv.GITHUB_OUTPUT;
  delete detectorEnv.GITHUB_STEP_SUMMARY;
  const { stdout } = await execFileAsync("bash", ["tools/ci/detect-changed-paths.sh", changedFiles], {
    cwd: root,
    env: detectorEnv,
  });
  assert.match(stdout, /^android=true$/m);
  assert.match(stdout, /^mobile=true$/m);
  assert.match(stdout, /^ios=true$/m);
  assert.match(stdout, /^repository=true$/m);
  assert.match(stdout, /^deploy=true$/m);
});

test("스토어 개인정보 제출 기준선은 release artifact placeholder 값을 거부한다", async () => {
  const workflow = read(".github/workflows/release-artifacts.yml");
  const readme = read("README.md");
  const storeReadiness = readJson("apps/mobile/release/store-submission-readiness.json");
  const privacyInventory = readJson("apps/mobile/release/store-privacy-inventory.json");

  assert.doesNotMatch(workflow, /easysubway\.local|@easysubway\.local/);
  assert.match(workflow, /Release Artifacts \/ Restore GitHub Actions dotenv secret/);
  assert.match(workflow, /tools\/ci\/validate-store-privacy-env\.mjs/);
  assert.match(workflow, /EASYSUBWAY_ENV_SECRET: \$\{\{ secrets\.EASYSUBWAY_ENV \}\}/);
  assert.match(workflow, /Store privacy release values are unavailable; skipping store-ready artifact build for this PR/);
  assert.match(workflow, /EASYSUBWAY_RELEASE_ARTIFACTS_STORE_READY=false/);
  assert.match(workflow, /EASYSUBWAY_RELEASE_ARTIFACTS_STORE_READY=true/);
  assert.match(workflow, /artifact=skipped/);
  assert.match(workflow, /--dart-define=EASYSUBWAY_PRIVACY_POLICY_URL="\$\{EASYSUBWAY_PRIVACY_POLICY_URL\}"/);
  assert.match(workflow, /--dart-define=EASYSUBWAY_SUPPORT_EMAIL="\$\{EASYSUBWAY_SUPPORT_EMAIL\}"/);
  assert.match(workflow, /--dart-define=EASYSUBWAY_DATA_DELETION_EMAIL="\$\{EASYSUBWAY_DATA_DELETION_EMAIL\}"/);
  assert.match(workflow, /--dart-define=EASYSUBWAY_SECURITY_EMAIL="\$\{EASYSUBWAY_SECURITY_EMAIL\}"/);

  assert.equal(privacyInventory.privacyPolicyUrlSource, "EASYSUBWAY_PRIVACY_POLICY_URL dart-define");
  assert.equal(privacyInventory.userDataDeletionSupported, true);
  assert.equal(privacyInventory.encryptionInTransitRequired, true);
  assert.equal(privacyInventory.tracking, false);
  assert.equal(privacyInventory.sharesDataWithThirdParties, false);

  const readinessItems = new Map(storeReadiness.items.map((item) => [item.id, item]));
  for (const id of [
    "play_privacy_policy_url",
    "play_account_data_deletion",
    "appstore_privacy_policy_url",
    "appstore_support_url",
    "cross_store_privacy_consistency",
  ]) {
    const item = readinessItems.get(id);
    assert.ok(item, `${id} must be present in store submission readiness`);
    assert.ok(item.linkedArtifacts.includes("README.md"), `${id} must link README for public user-facing path`);
  }

  assert.match(readme, /EASYSUBWAY_PRIVACY_POLICY_URL/);
  assert.match(readme, /EASYSUBWAY_DATA_DELETION_EMAIL/);
  assert.match(readme, /## Privacy Policy/);
  assert.match(readme, /https:\/\/github\.com\/AquilaXk\/easysubway#privacy-policy/);
  assert.match(readme, /EasySubway does not sell personal or sensitive user data\./);
  assert.match(readme, /support@easysubway\.app/);
  assert.match(readme, /security@easysubway\.app/);
  assert.match(readme, /privacy@easysubway\.app/);
  assert.doesNotMatch(readme, /easysubway\.local|@easysubway\.local/);

  const dir = await mkdtemp(path.join(tmpdir(), "easysubway-store-privacy-env-"));
  const validEnv = path.join(dir, "valid.env");
  await writeFile(validEnv, [
    "EASYSUBWAY_PRIVACY_POLICY_URL=https://easysubway.app/privacy",
    "EASYSUBWAY_SUPPORT_EMAIL=support@easysubway.app",
    "EASYSUBWAY_SECURITY_EMAIL=security@easysubway.app",
    "EASYSUBWAY_DATA_DELETION_EMAIL=privacy@easysubway.app",
    "",
  ].join("\n"));
  const githubEnv = path.join(dir, "github.env");
  await execFileAsync(
    process.execPath,
    ["tools/ci/validate-store-privacy-env.mjs", "--env-file", validEnv, "--github-env", githubEnv],
    {
      cwd: root,
    },
  );
  const githubEnvOutput = readFileSync(githubEnv, "utf8");
  assert.match(githubEnvOutput, /^EASYSUBWAY_PRIVACY_POLICY_URL=https:\/\/easysubway\.app\/privacy$/m);
  assert.match(githubEnvOutput, /^EASYSUBWAY_SUPPORT_EMAIL=support@easysubway\.app$/m);
  assert.match(githubEnvOutput, /^EASYSUBWAY_SECURITY_EMAIL=security@easysubway\.app$/m);
  assert.match(githubEnvOutput, /^EASYSUBWAY_DATA_DELETION_EMAIL=privacy@easysubway\.app$/m);

  const invalidEnv = path.join(dir, "invalid.env");
  await writeFile(invalidEnv, [
    "EASYSUBWAY_PRIVACY_POLICY_URL=https://easysubway.local/privacy",
    "EASYSUBWAY_SUPPORT_EMAIL=support@easysubway.local",
    "EASYSUBWAY_SECURITY_EMAIL=security@easysubway.local",
    "EASYSUBWAY_DATA_DELETION_EMAIL=privacy@easysubway.local",
    "",
  ].join("\n"));
  await assert.rejects(
    execFileAsync(process.execPath, ["tools/ci/validate-store-privacy-env.mjs", "--env-file", invalidEnv], {
      cwd: root,
    }),
    /must not use local or placeholder values/,
  );
});

test("공개 source contract 불변식은 README와 public interfaces에 남는다", () => {
  const readme = read("README.md");
  const facilityReportUseCase = read(
    "backend/src/main/java/com/easysubway/report/application/port/in/FacilityReportUseCase.java",
  );
  const storePhotoPort = read(
    "backend/src/main/java/com/easysubway/report/application/port/out/StoreFacilityReportPhotoPort.java",
  );
  const storeUploadedPhotoPort = read(
    "backend/src/main/java/com/easysubway/report/application/port/out/StoreFacilityReportUploadedPhotoPort.java",
  );
  const loadPhotoPort = read(
    "backend/src/main/java/com/easysubway/report/application/port/out/LoadFacilityReportPhotoPort.java",
  );
  const dataPackInstaller = read("apps/mobile/lib/core/datapack/data_pack_installer.dart");
  const dataPackManifest = read("apps/mobile/lib/core/datapack/data_pack_manifest.dart");
  const catalogDatabase = read("apps/mobile/lib/core/database/catalog/catalog_database.dart");
  const userDatabase = read("apps/mobile/lib/core/database/user/user_database.dart");

  for (const marker of [
    "local-first mobile runtime",
    "backend control-plane runtime",
    "receipt-token report boundary",
    "data-pack pointer contract",
    "user-data preservation contract",
  ]) {
    assert.match(readme, new RegExp(marker), `README must document ${marker}`);
  }

  assert.match(facilityReportUseCase, /receipt-token report boundary/);
  assert.match(facilityReportUseCase, /plain receipt token must never be logged or returned after issuance/);
  assert.match(storePhotoPort, /object key is the durable photo reference/);
  assert.match(storeUploadedPhotoPort, /object key is the durable photo reference/);
  assert.match(loadPhotoPort, /photo bytes must only be loaded through authorized review or receipt-token flows/);
  assert.match(dataPackInstaller, /data-pack pointer contract/);
  assert.match(dataPackManifest, /production signatures bind the pack URL/);
  assert.match(catalogDatabase, /catalog database is replaceable installed-pack state/);
  assert.match(userDatabase, /user-data preservation contract/);
});

test("경로 source contract 불변식은 접근성 안전과 metric fallback 의미를 고정한다", () => {
  const networkGraph = read("apps/mobile/lib/features/routes/application/network_graph.dart");
  const accessibilityCostCalculator = read(
    "apps/mobile/lib/features/routes/application/accessibility_cost_calculator.dart",
  );
  const localRouteRepository = read("apps/mobile/lib/features/routes/data/local_route_repository.dart");
  const routeSearch = read("apps/mobile/lib/route_search.dart");

  assert.match(networkGraph, /route contract: baseCost seconds/);
  assert.match(networkGraph, /route contract: reliability thresholds/);
  assert.match(networkGraph, /route contract: generated connector ratio/);
  assert.match(accessibilityCostCalculator, /route contract: unknown accessibility data/);
  assert.match(accessibilityCostCalculator, /route contract: stair-only block/);
  assert.match(accessibilityCostCalculator, /route contract: generated connector strict block/);
  assert.match(localRouteRepository, /route contract: synthetic connector edge/);
  assert.match(localRouteRepository, /isGeneratedConnector: true/);
  assert.match(localRouteRepository, /route contract: local metric fallback/);
  assert.match(routeSearch, /route contract: realtime ETA fallback/);
});

test("운영 관측성과 알림 기준선은 필수 release 신호와 심볼 보관 계약을 고정한다", () => {
  const gatePath = "apps/mobile/release/operations-observability-gate.json";
  assert.ok(existsSync(path.join(root, gatePath)), "operations observability gate artifact must exist");

  const gate = readJson(gatePath);
  const readme = read("README.md");
  const datapackWorkflow = read(".github/workflows/datapack-release.yml");
  const releaseArtifactsWorkflow = read(".github/workflows/release-artifacts.yml");
  const applicationProd = read("backend/src/main/resources/application-prod.yml");

  assert.equal(gate.schemaVersion, 1);
  assert.equal(gate.applicationId, "easysubway");
  assert.equal(gate.releaseGate, "operations-observability");
  assert.equal(gate.releaseBlockerPolicy, true);
  assert.equal(gate.sensitiveLogPolicy.forbidReceiptTokens, true);
  assert.equal(gate.sensitiveLogPolicy.forbidUploadUrls, true);
  assert.equal(gate.sensitiveLogPolicy.forbidPhotoMetadata, true);
  assert.doesNotMatch(JSON.stringify(gate), /\b(TBD|TODO)\b|\.{3}/i);

  const signals = new Map(gate.signals.map((signal) => [signal.id, signal]));
  const requiredSignalIds = [
    "backend_health_readiness_storage_datapack_report",
    "report_api_error_rate",
    "admin_review_latency",
    "datapack_release_publish_result",
    "mobile_crash_free_rate",
    "mobile_anr_rate",
    "mobile_app_start_failure_rate",
    "route_search_found_blocked_unknown_distribution",
    "datapack_install_rollback_failure_rate",
    "realtime_provider_success_stale_timeout_latency_eta_error",
    "report_upload_failure_duplicate_orphan_cleanup_rate",
    "cross_version_correlation_ids",
    "android_mapping_retention",
    "ios_dsym_retention",
  ];
  assert.deepEqual([...signals.keys()].sort(), requiredSignalIds.toSorted());

  for (const id of requiredSignalIds) {
    const signal = signals.get(id);
    assert.match(signal.area, /^(backend|datapack|mobile|realtime|release)$/);
    assert.equal(typeof signal.ownerKo, "string", `${id} must define owner`);
    assert.ok(signal.ownerKo.length > 0, `${id} owner must not be empty`);
    assert.equal(typeof signal.thresholdKo, "string", `${id} must define threshold`);
    assert.ok(signal.thresholdKo.length > 0, `${id} threshold must not be empty`);
    assert.equal(typeof signal.firstResponseKo, "string", `${id} must define first response`);
    assert.ok(signal.firstResponseKo.length > 0, `${id} first response must not be empty`);
    assert.ok(Array.isArray(signal.evidence), `${id} must list evidence`);
    assert.ok(signal.evidence.length > 0, `${id} must require evidence`);
    assert.ok(Array.isArray(signal.linkedArtifacts), `${id} must list linked artifacts`);
    for (const artifact of signal.linkedArtifacts) {
      assert.ok(existsSync(path.join(root, artifact)), `${id} linked artifact must exist: ${artifact}`);
    }
  }

  assert.ok(signals.get("android_mapping_retention").evidence.includes("android-mapping-artifact-retention"));
  assert.ok(signals.get("ios_dsym_retention").evidence.includes("ios-dsym-artifact-retention-deferred"));
  assert.match(signals.get("ios_dsym_retention").thresholdKo, /Android-first 배포에서는 후순위 범위/);
  assert.ok(signals.get("cross_version_correlation_ids").evidence.includes("app-datapack-route-provider-correlation"));

  assert.match(readme, /## Operations/);
  assert.match(readme, /operations-observability-gate\.json/);
  assert.match(readme, /backend_health_readiness_storage_datapack_report/);
  assert.match(readme, /realtime_provider_success_stale_timeout_latency_eta_error/);
  assert.match(readme, /receipt token|upload URL|photo metadata/i);

  assert.match(applicationProd, /management:[\s\S]*health:[\s\S]*readiness:[\s\S]*productionReadiness/);
  assert.match(datapackWorkflow, /Data Pack Release \/ Write observability metadata/);
  assert.match(datapackWorkflow, /datapack-observability\.txt/);
  assert.match(datapackWorkflow, /pack_version=/);
  assert.match(datapackWorkflow, /manifest\.activePack/);
  assert.match(datapackWorkflow, /\$\{activePack\.id\}@\$\{activePack\.version\}/);
  assert.match(datapackWorkflow, /source_updated_at=/);
  assert.match(datapackWorkflow, /publish_result=/);
  assert.match(datapackWorkflow, /EASYSUBWAY_DATAPACK_REMOTE_PUBLISH_RESULT=success/);
  assert.match(datapackWorkflow, /remotePublishEnabled !== "false"/);
  assert.match(datapackWorkflow, /if \(isMainBranch && remotePublishEnabled !== "false"\)/);
  assert.match(datapackWorkflow, /remotePublishResult === "success" \? "success" : "failed"/);
  assert.match(releaseArtifactsWorkflow, /mapping_retention_days=90/);
  assert.doesNotMatch(releaseArtifactsWorkflow, /dsym_retention_days=90/);
  assert.match(releaseArtifactsWorkflow, /retention-days: 90/);
});

test("서버 최소화 PR10 QA gate는 최종 인수 증거를 로컬 전용 정책으로 고정한다", () => {
  const gatePath = "apps/mobile/release/server-minimized-qa-gate.json";
  assert.ok(existsSync(path.join(root, gatePath)), "server minimized QA gate artifact must exist");

  const gate = readJson(gatePath);
  assert.equal(gate.schemaVersion, 1);
  assert.equal(gate.applicationId, "easysubway");
  assert.equal(gate.releaseGate, "server-minimized-device-qa");
  assert.equal(gate.localOnlyEvidence, true);
  assert.match(gate.evidenceRoot, /^\.codex\/evidence\/server-minimization\/pr10$/);
  assert.doesNotMatch(
    JSON.stringify(gate),
    /com\.easysubway\.mobile/,
    "server minimized QA gate must not reference the retired Android package",
  );
  assert.equal(gate.platformCompletionRule.androidRequired, true);
  assert.equal(gate.platformCompletionRule.iosRequired, true);
  assert.equal(gate.platformCompletionRule.singlePlatformEvidenceIsInsufficient, true);
  assert.doesNotMatch(JSON.stringify(gate), /\b(TBD|TODO)\b|\.{3}/i);

  const requiredFinalAcceptanceIds = [
    "app_starts_without_backend",
    "airplane_station_search",
    "airplane_route_search",
    "airplane_station_detail",
    "no_api_call_on_app_start",
    "manifest_ttl_or_etag_only",
    "datapack_failure_keeps_existing_pack",
    "datapack_update_preserves_user_data",
    "no_anonymous_auth_tokens",
    "no_report_photo_base64",
    "receipt_token_only_report_status",
    "admin_review_reaches_override_or_next_pack",
    "redis_push_not_mvp_required",
  ];
  const coveredFinalAcceptanceIds = new Set(gate.checks.flatMap((check) => check.finalAcceptanceIds));
  assert.deepEqual([...coveredFinalAcceptanceIds].sort(), requiredFinalAcceptanceIds.toSorted());

  const requiredAndroidChecks = [
    "android_app_start_backend_down",
    "android_airplane_station_search",
    "android_airplane_route_search",
    "android_corrupt_datapack_keeps_previous_pack",
    "android_app_update_user_db_migration",
    "android_photo_picker_process_death_recovery",
    "android_cdn_timeout_behavior",
    "android_talkback_search_route_report_error",
    "android_font_scale_150_no_overflow",
    "android_high_contrast_visible_controls",
    "android_location_permission_denied_fallback",
    "android_internal_test_track_install",
  ];
  const requiredIosChecks = [
    "ios_app_start_backend_down",
    "ios_voiceover_focus_order",
    "ios_dynamic_type_max_no_overflow",
    "ios_bold_text_increase_contrast_reduce_motion",
    "ios_permission_dialog_copy",
    "ios_signed_upload_failure_message",
    "ios_receipt_token_missing_message",
    "ios_archive_contains_baseline_pack",
    "ios_archive_contains_privacy_manifest",
    "ios_testflight_or_signed_device_install",
  ];
  const idsByPlatform = new Map([
    ["android", gate.checks.filter((check) => check.platform === "android").map((check) => check.id).sort()],
    ["ios", gate.checks.filter((check) => check.platform === "ios").map((check) => check.id).sort()],
  ]);
  assert.deepEqual(idsByPlatform.get("android"), requiredAndroidChecks.toSorted());
  assert.deepEqual(idsByPlatform.get("ios"), requiredIosChecks.toSorted());

  for (const check of gate.checks) {
    if (check.id === "android_app_start_backend_down") {
      assert.equal(
        check.command,
        "adb shell am start -n com.easysubway.app/com.easysubway.easysubway_mobile.MainActivity",
        "Android app start command must use the production applicationId and actual Activity class",
      );
    }
    if (check.platform === "android" && check.command?.includes("com.easysubway")) {
      assert.match(
        check.command,
        /com\.easysubway\.app/,
        `${check.id} Android adb command must target the production applicationId`,
      );
    }
    assert.match(check.platform, /^(android|ios)$/);
    assert.ok(Array.isArray(check.finalAcceptanceIds), `${check.id} must map final acceptance ids`);
    assert.ok(check.finalAcceptanceIds.length > 0, `${check.id} must map at least one final acceptance id`);
    assert.ok(Array.isArray(check.evidence), `${check.id} must list evidence`);
    assert.ok(check.evidence.length > 0, `${check.id} must require evidence`);
    assert.ok(check.command || check.manualTarget, `${check.id} must define command or manual target`);
    assert.ok(check.localEvidencePath.startsWith(`${gate.evidenceRoot}/${check.platform}/`));
    assert.doesNotMatch(check.localEvidencePath, /\.md$/i, `${check.id} evidence must not be tracked Markdown`);
    for (const artifact of check.linkedArtifacts ?? []) {
      assert.ok(existsSync(path.join(root, artifact)), `${check.id} linked artifact must exist: ${artifact}`);
    }
  }
});

test("데이터팩 workflow는 pack 검증 이후 manifest 배포 순서를 강제한다", () => {
  assert.ok(
    existsSync(path.join(root, ".github/workflows/datapack-release.yml")),
    "data pack release workflow must exist",
  );

  const workflow = read(".github/workflows/datapack-release.yml");
  const overrideIndex = workflow.indexOf("Data Pack Release / Apply admin review overrides");
  const routeMapAuditIndex = workflow.indexOf("Data Pack Release / Audit route map coordinate coverage");
  const buildIndex = workflow.indexOf("Data Pack Release / Build data packs");
  const validateIndex = workflow.indexOf("Data Pack Release / Validate generated data packs");
  const packIndex = workflow.indexOf("Data Pack Release / Stage pack files");
  const verifyIndex = workflow.indexOf("Data Pack Release / Verify uploaded pack checksums before manifest publish");
  const preflightIndex = workflow.indexOf("Data Pack Release / Create manifest-last publish preflight plan");
  const executorDryRunIndex = workflow.indexOf("Data Pack Release / Validate object storage publish executor dry run");
  const restoreSecretIndex = workflow.indexOf("Data Pack Release / Restore GitHub Actions dotenv secret");
  const remoteEnvIndex = workflow.indexOf("Data Pack Release / Validate remote object storage publish env");
  const remotePublishIndex = workflow.indexOf("Data Pack Release / Publish staged data packs to object storage");
  const artifactIndex = workflow.indexOf("Data Pack Release / Upload staged data packs");
  const manifestIndex = workflow.indexOf("Data Pack Release / Stage manifest");
  const jobEnvBlock = workflow.match(/\n    env:\n[\s\S]*?\n\n    steps:/)?.[0] ?? "";

  assert.match(workflow, /^name: Data Pack Release$/m);
  assert.match(workflow, /workflow_dispatch:/);
  assert.match(workflow, /push:[\s\S]*branches:[\s\S]*- main/);
  assert.match(workflow, /paths:[\s\S]*- tools\/route-map\/\*\*/);
  assert.doesNotMatch(jobEnvBlock, /runner\.temp/, "job-level env cannot use runner context");
  assert.match(workflow, /Data Pack Release \/ Configure temp directories/);
  assert.match(workflow, /GITHUB_ENV/);
  assert.match(workflow, /EASYSUBWAY_DATAPACK_OUTPUT=\$\{\{ runner\.temp \}\}\/easysubway-datapacks/);
  assert.match(workflow, /EASYSUBWAY_DATAPACK_STAGE=\$\{\{ runner\.temp \}\}\/easysubway-datapack-stage/);
  assert.match(workflow, /EASYSUBWAY_DATAPACK_PUBLISH_PLAN=\$\{\{ runner\.temp \}\}\/easysubway-datapack-stage\/publish-plan\.json/);
  assert.match(workflow, /EASYSUBWAY_ROUTE_MAP_AUDIT_REPORT=\$\{\{ runner\.temp \}\}\/easysubway-datapack-stage\/route-map-audit\.json/);
  assert.match(workflow, /Data Pack Release \/ Audit route map coordinate coverage/);
  assert.match(workflow, /node tools\/route-map\/audit-route-map\.mjs/);
  assert.match(workflow, /--fixture "\$\{EASYSUBWAY_DATAPACK_REVIEWED_FIXTURE\}"/);
  assert.match(workflow, /--reviewed-ambiguities tools\/route-map\/fixtures\/reviewed-ambiguities\.json/);
  assert.match(workflow, /--fail-on BLOCKER,HIGH/);
  assert.match(workflow, /test -s "\$\{EASYSUBWAY_ROUTE_MAP_AUDIT_REPORT\}"/);
  assert.match(workflow, /node tools\/datapack\/validate-source-inventory\.mjs/);
  assert.match(workflow, /tools\/datapack\/build-datapack\.mjs/);
  assert.match(workflow, /tools\/datapack\/validate-datapack\.mjs/);
  assert.match(workflow, /tools\/datapack\/create-publish-plan\.mjs/);
  assert.match(workflow, /tools\/datapack\/publish-object-storage\.mjs/);
  assert.match(workflow, /--manifest "\$\{EASYSUBWAY_DATAPACK_STAGE\}\/catalog\/current\.json"/);
  assert.match(workflow, /--plan "\$\{EASYSUBWAY_DATAPACK_PUBLISH_PLAN\}"/);
  assert.match(workflow, /--dry-run/);
  assert.match(workflow, /--output "\$\{EASYSUBWAY_DATAPACK_PUBLISH_PLAN\}"/);
  assert.match(workflow, /tools\/datapack\/schema\/manifest\.schema\.json/);
  assert.match(workflow, /sourceInventory/);
  assert.match(workflow, /Verify uploaded pack checksums before manifest publish/);
  assert.match(workflow, /Create manifest-last publish preflight plan/);
  assert.match(workflow, /Validate object storage publish executor dry run/);
  assert.match(workflow, /Data Pack Release \/ Restore GitHub Actions dotenv secret[\s\S]*?EASYSUBWAY_ENV_SECRET: \$\{\{ secrets\.EASYSUBWAY_ENV \}\}/);
  assert.match(workflow, /printf '%s' "\$\{EASYSUBWAY_ENV_SECRET\}" > "\$\{env_file\}"/);
  assert.doesNotMatch(workflow, /printf '%s\\n' "\$\{EASYSUBWAY_ENV_SECRET\}"/);
  assert.doesNotMatch(workflow, /tools\/ci\/validate-deployment-env\.sh "\$\{EASYSUBWAY_ENV_FILE\}"/);
  assert.match(workflow, /tools\/datapack\/export-publish-env\.mjs/);
  assert.match(workflow, /--github-output "\$\{GITHUB_OUTPUT\}"/);
  assert.match(workflow, /--allow-invalid-disabled/);
  assert.match(workflow, /id: remote-publish-env/);
  assert.match(workflow, /steps\.remote-publish-env\.outputs\.enabled == 'true'/);
  assert.match(workflow, /github\.ref == 'refs\/heads\/main'/);
  assert.match(workflow, /Data Pack Release \/ Upload staged data packs[\s\S]*?if: \$\{\{ always\(\) \}\}/);
  assert.match(workflow, /\$\{EASYSUBWAY_DATAPACK_STAGE\}\/catalog\/current\.json/);
  assert.match(workflow, /publish-plan\.json/);
  assert.doesNotMatch(workflow, /\$\{EASYSUBWAY_DATAPACK_STAGE\}\/current\.json/);
  assert.ok(overrideIndex >= 0, "workflow must apply admin review overrides");
  assert.ok(routeMapAuditIndex > overrideIndex, "workflow must audit reviewed route map coordinates after admin review overrides");
  assert.ok(buildIndex > routeMapAuditIndex, "workflow must build data packs after route map coordinate audit");
  assert.ok(validateIndex >= 0, "workflow must validate generated data packs");
  assert.ok(packIndex > validateIndex, "workflow must stage pack files after validation");
  assert.ok(verifyIndex > packIndex, "workflow must verify staged pack checksums before manifest staging");
  assert.ok(manifestIndex > verifyIndex, "workflow must stage manifest after pack checksum verification");
  assert.ok(preflightIndex > manifestIndex, "workflow must create publish preflight plan after manifest staging");
  assert.ok(executorDryRunIndex > preflightIndex, "workflow must validate publish executor after plan creation");
  assert.ok(restoreSecretIndex > executorDryRunIndex, "workflow must restore dotenv secret after dry-run validation");
  assert.ok(remoteEnvIndex > restoreSecretIndex, "workflow must validate remote publish env after secret restore");
  assert.ok(remotePublishIndex > remoteEnvIndex, "workflow must publish remotely after env validation");
  assert.ok(artifactIndex > remotePublishIndex, "workflow must keep artifact upload after remote publish attempt");
  assert.match(workflow, /name: easysubway-datapacks-\$\{\{ github\.sha \}\}/);
  assert.match(workflow, /path: \$\{\{ runner\.temp \}\}\/easysubway-datapack-stage/);
});

test("스토어 배포 증거 workflow는 단일 dotenv secret과 명시적 credential preflight를 사용한다", () => {
  assert.ok(
    existsSync(path.join(root, ".github/workflows/store-distribution-evidence.yml")),
    "store distribution evidence workflow must exist",
  );
  assert.ok(
    existsSync(path.join(root, "tools/ci/check-store-distribution-evidence-env.mjs")),
    "store distribution evidence env preflight must exist",
  );

  const workflow = read(".github/workflows/store-distribution-evidence.yml");
  const preflight = read("tools/ci/check-store-distribution-evidence-env.mjs");

  assert.match(workflow, /^name: Store Distribution Evidence$/m);
  assert.match(workflow, /workflow_dispatch:/);
  assertActionsEnvSecretPolicy(".github/workflows/store-distribution-evidence.yml", workflow);
  assert.match(workflow, /EASYSUBWAY_ENV_SECRET: \$\{\{ secrets\.EASYSUBWAY_ENV \}\}/);
  assert.match(workflow, /printf '%s' "\$\{EASYSUBWAY_ENV_SECRET\}" > "\$\{env_file\}"/);
  assert.doesNotMatch(workflow, /printf '%s\\n' "\$\{EASYSUBWAY_ENV_SECRET\}"/);
  assert.match(workflow, /node tools\/ci\/check-store-distribution-evidence-env\.mjs/);
  assert.match(workflow, /--env-file "\$\{EASYSUBWAY_ENV_FILE\}"/);
  assert.match(workflow, /--github-output "\$\{GITHUB_OUTPUT\}"/);
  assert.match(workflow, /--report "\$\{RUNNER_TEMP\}\/store-distribution-evidence-preflight\.txt"/);
  assert.match(workflow, /node tools\/datapack\/export-publish-env\.mjs/);
  assert.doesNotMatch(workflow, /--allow-invalid-disabled/);
  assert.match(workflow, /store-distribution-evidence-preflight-\$\{\{ github\.sha \}\}/);

  assert.match(preflight, /EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON/);
  assert.match(preflight, /EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME/);
  assert.match(preflight, /EASYSUBWAY_APP_STORE_CONNECT_KEY_ID/);
  assert.match(preflight, /EASYSUBWAY_APP_STORE_CONNECT_ISSUER_ID/);
  assert.match(preflight, /EASYSUBWAY_APP_STORE_CONNECT_PRIVATE_KEY_PEM/);
  assert.match(preflight, /EASYSUBWAY_APP_STORE_APPLE_ID/);
  assert.match(preflight, /EASYSUBWAY_DATAPACK_REMOTE_PUBLISH_ENABLED/);
  assert.match(preflight, /EASYSUBWAY_OBJECT_STORAGE_PREAUTH_BASE_URL/);
  assert.doesNotMatch(preflight, /console\.log\(.*env\[/, "preflight must not print secret values");
});

test("스토어 배포 증거 preflight는 legacy S3와 PAR 데이터팩 publish env를 모두 허용한다", async () => {
  const commonEnvLines = [
    "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64=base64-json",
    "EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME=com.easysubway.app",
    "EASYSUBWAY_APP_STORE_CONNECT_KEY_ID=key-id",
    "EASYSUBWAY_APP_STORE_CONNECT_ISSUER_ID=issuer-id",
    "EASYSUBWAY_APP_STORE_CONNECT_PRIVATE_KEY_PEM=private-key",
    "EASYSUBWAY_APP_STORE_APPLE_ID=123456789",
    "EASYSUBWAY_APP_STORE_BUNDLE_ID=com.easysubway.app",
    "EASYSUBWAY_DATAPACK_REMOTE_PUBLISH_ENABLED=true",
    "EASYSUBWAY_DATA_PACK_BASE_URL=https://cdn.example.com/easysubway-datapacks",
  ];
  const cases = [
    {
      name: "legacy",
      lines: [
        "EASYSUBWAY_OBJECT_STORAGE_ENDPOINT=https://object-storage.example.com",
        "EASYSUBWAY_OBJECT_STORAGE_ACCESS_KEY=access-key",
        "EASYSUBWAY_OBJECT_STORAGE_SECRET_KEY=secret-key",
        "EASYSUBWAY_OBJECT_STORAGE_REGION=ap-northeast-2",
        "EASYSUBWAY_DATAPACK_BUCKET=easysubway-datapacks",
      ],
    },
    {
      name: "par",
      lines: [
        "EASYSUBWAY_OBJECT_STORAGE_PREAUTH_BASE_URL=https://objectstorage.example.com/p/token/n/ns/b/bucket/o/",
      ],
    },
  ];

  for (const testCase of cases) {
    const dir = await mkdtemp(path.join(tmpdir(), `easysubway-store-env-${testCase.name}-`));
    const envFile = path.join(dir, "deploy.env");
    const outputFile = path.join(dir, "github-output.txt");
    const reportFile = path.join(dir, "report.txt");
    await writeFile(envFile, [...commonEnvLines, ...testCase.lines, ""].join("\n"));

    await execFileAsync(
      process.execPath,
      [
        "tools/ci/check-store-distribution-evidence-env.mjs",
        "--env-file",
        envFile,
        "--github-output",
        outputFile,
        "--report",
        reportFile,
      ],
      { cwd: root },
    );

    const report = readFileSync(reportFile, "utf8");
    assert.match(report, /^datapack_object_storage_publish\.ready=true$/m);
    assert.match(readFileSync(outputFile, "utf8"), /^datapack_object_storage_publish_ready=true$/m);
  }
});

test("데이터팩 도구는 앱 manifest 계약과 SQLite 검증 계약을 고정한다", () => {
  const fixture = JSON.parse(read("tools/datapack/fixtures/catalog-fixture.json"));
  const schema = read("tools/datapack/schema/catalog-schema.sql");
  const builder = read("tools/datapack/build-datapack.mjs");
  const validator = read("tools/datapack/validate-datapack.mjs");

  assert.equal(fixture.manifest.ttlSeconds, 3600);
  assert.deepEqual(fixture.manifest.activePack, { id: "capital", version: "1" });
  assert.ok(fixture.packs.some((pack) => pack.id === "capital" && pack.version === "1"));
  assert.match(schema, /CREATE TABLE catalog_metadata/);
  assert.match(schema, /PRAGMA user_version = 4/);
  assert.match(schema, /CREATE TABLE stations/);
  assert.match(schema, /CREATE TABLE realtime_provider_line_mappings/);
  assert.match(schema, /CREATE TABLE realtime_provider_station_mappings/);
  assert.match(schema, /source_id TEXT NOT NULL DEFAULT ''/);
  assert.match(schema, /provenance_kind TEXT NOT NULL DEFAULT 'UNKNOWN'/);
  assert.match(schema, /verification_status TEXT NOT NULL DEFAULT 'UNKNOWN'/);
  assert.match(schema, /label_polygon TEXT NOT NULL DEFAULT ''/);
  assert.match(schema, /UNIQUE \(provider_id, provider_line_id, line_id\)/);
  assert.match(
    schema,
    /FOREIGN KEY \(provider_id, provider_line_id, line_id\) REFERENCES realtime_provider_line_mappings\(provider_id, provider_line_id, line_id\)/,
  );
  assert.match(schema, /FOREIGN KEY \(station_id, line_id\) REFERENCES station_lines\(station_id, line_id\)/);
  assert.match(builder, /sqliteSha256/);
  assert.match(builder, /artifactKind/);
  assert.match(builder, /sourceInventory/);
  assert.match(builder, /regionalQualityMetrics/);
  assert.match(builder, /representativeRouteRegressions/);
  assert.match(builder, /sha256-pack-manifest-v1/);
  assert.match(builder, /schemaVersion/);
  assert.match(validator, /PRAGMA quick_check/);
  assert.match(validator, /PRAGMA foreign_key_check/);
  assert.match(validator, /PRAGMA user_version/);
  assert.match(validator, /minimumTableRows/);
  assert.match(validator, /sourceInventory/);
  assert.match(validator, /validateNetworkEdgeStationLineEndpoints/);
  assert.match(validator, /validateProductionNetworkEdgeProvenance/);
  assert.match(validator, /datapack_verified_edge_coverage/);
  assert.match(validator, /validateRepresentativeRouteRegressions/);
  assert.match(validator, /manifest\.schema\.json/);
  assert.match(validator, /validateManifestJsonSchema/);
  assert.match(validator, /validateRegionalQualityMetricsMatchDatabase/);
  assert.match(validator, /validateAccessEdgeEndpointShape/);
  assert.match(validator, /stationIdFromStationLineNode/);
  assert.match(validator, /routeGraphConnectivityEdgeType/);
  assert.match(validator, /addGeneratedStationTransferEdges/);
  assert.match(validator, /parts\.slice\(2\)\.some/);
  assert.match(validator, /network_edges access edge must connect station and station-line/);
  assert.match(validator, /network_edges access edge station mismatch/);
  assert.match(validator, /representativeRouteRegressions missing required pattern/);
  assert.match(validator, /representativeRouteRegressions required edge missing/);
  assert.match(validator, /representativeRouteRegressions required edge not on route/);
  assert.match(validator, /regionalQualityMetrics mismatch/);
  assert.match(validator, /network_edges endpoint references missing station-line/);
  assert.match(validator, /station-line node is isolated from route graph/);
  assert.match(validator, /route graph has disconnected component/);
  assert.match(validator, /route graph has unreachable directed path/);
  assert.equal(
    existsSync(path.join(root, "tools/datapack/schema/manifest.schema.json")),
    true,
    "data pack manifest schema must be tracked",
  );
});

test("운영 환경 placeholder 계약은 production 데이터팩 URL에서 local host를 거부한다", () => {
  const readme = read("README.md");
  const fixture = readJson("tools/datapack/fixtures/catalog-fixture.json");
  const manifestSchema = readJson("tools/datapack/schema/manifest.schema.json");
  const builder = read("tools/datapack/build-datapack.mjs");
  const validator = read("tools/datapack/validate-datapack.mjs");

  assert.equal(fixture.packs[0].artifactKind, "fixture");
  assert.match(fixture.packs[0].sourceInventory[0].url, /^https:\/\/easysubway\.local\/fixtures\//);
  assert.match(manifestSchema.$id, /^https:\/\/easysubway\.local\/schema\//);
  assert.deepEqual(manifestSchema.properties.packs.items.properties.payloadKind.enum, ["sqlite_catalog"]);
  assert.equal(
    manifestSchema.properties.packs.items.properties.dependencies.items.$ref,
    "#/$defs/packIdentity",
  );
  assert.match(builder, /production pack url must not use a local placeholder host/);
  assert.match(builder, /production sourceInventory\.url must not use a local placeholder host/);
  assert.match(validator, /production pack url must not use a local placeholder host/);
  assert.match(validator, /production sourceInventory\.url must not use a local placeholder host/);
  assert.match(readme, /local placeholder host/);
  assert.match(readme, /production data pack/);
  assert.match(readme, /fixture artifact/);
});

test("모바일 데이터팩 updater는 published manifest rollback 검증을 유지한다", () => {
  const updaterTest = read("apps/mobile/test/core/datapack/data_pack_updater_test.dart");
  const manifestTest = read("apps/mobile/test/core/datapack/data_pack_manifest_test.dart");

  assert.match(updaterTest, /rollback manifest가 이미 설치된 이전 pack을 current로 활성화한다/);
  assert.match(updaterTest, /active pack history와 명시 dependency만 다운로드한다/);
  assert.match(manifestTest, /SQLite catalog 외 self-update payload를 거부한다/);
  assert.match(updaterTest, /\/datapacks\/catalog\/current\.json/);
  assert.match(updaterTest, /'activePack': \{'id': 'capital', 'version': '18'\}/);
  assert.match(updaterTest, /'packs': const \[\]/);
  assert.match(updaterTest, /expect\(rollbackPointer\?\.version, '18'\)/);
});

test("운영 데이터팩 공식 출처 inventory는 라이선스와 갱신 기준을 기계 검증 가능하게 고정한다", () => {
  const inventory = readJson("tools/datapack/source-inventory.json");
  const targets = readJson("tools/datapack/nationwide-coverage-targets.json");
  const gapReporter = read("tools/datapack/report-coverage-gaps.mjs");

  assert.equal(inventory.schemaVersion, 1);
  assert.equal(inventory.region, "nationwide");
  assert.equal(inventory.artifactKind, "production-source-inventory");
  assert.ok(Array.isArray(inventory.sources));
  assert.ok(inventory.sources.length >= 6);
  assert.equal(targets.artifactKind, "nationwide-datapack-coverage-targets");
  assert.deepEqual(
    targets.requiredSourceDomains.map((domain) => domain.id),
    ["station_line_membership", "route_graph_topology", "accessibility_facilities", "realtime_arrivals", "demand_reference"],
  );
  assert.ok(targets.regions.some((region) => region.id === "capital"));
  assert.ok(targets.regions.some((region) => region.id !== "capital"));
  assert.match(gapReporter, /nationwide coverage gaps remain/);
  assert.match(gapReporter, /coverageScope/);
  assert.match(gapReporter, /coverageComplete/);
  assert.match(gapReporter, /datapack-field-provenance/);
  assert.match(gapReporter, /minimumOfficialFieldCoverageRatio/);
  assert.match(gapReporter, /MANUAL_OVERRIDE/);
  assert.match(read(".github/workflows/datapack-release.yml"), /Write coverage gap evidence/);

  const sourceIds = inventory.sources.map((source) => source.id).sort();
  assert.deepEqual(sourceIds, [
    "busan-transportation-urban-rail-station-info",
    "kric-braille-displays",
    "kric-disabled-toilet",
    "kric-elevator-car-number",
    "kric-metropolitan-rail-station-info",
    "kric-platform-train-distance",
    "kric-safety-platform",
    "kric-station-elevator",
    "kric-station-elevator-movement",
    "kric-station-escalator",
    "kric-wheelchair-lift-location",
    "kric-wheelchair-lift-movement",
    "molit-tago-subway-info",
    "molit-urban-rail-full-route",
    "seoul-realtime-arrival-station-info",
    "seoul-subway-hourly-boarding",
    "seoulmetro-station-line-info",
  ]);

  for (const source of inventory.sources) {
    assert.equal(source.requiredForProductionPack, true, `${source.id} must be required for production pack`);
    assert.ok(
      ["KOGL-1", "PUBLIC_DATA_FREE_USE"].includes(source.license.type),
      `${source.id} must use an explicit public data license type`,
    );
    assert.equal(source.license.commercialUseAllowed, true, `${source.id} must allow commercial use`);
    assert.equal(source.license.derivativeWorkAllowed, true, `${source.id} must allow derivative work`);
    assert.equal(source.license.redistributionAllowed, true, `${source.id} must allow redistribution`);
    assert.match(source.license.attribution, /공공누리 제1유형|공공데이터포털 이용허락범위 제한 없음/);
    assert.match(
      source.datasetUrl,
      /^https:\/\/(?:data\.seoul\.go\.kr\/dataList\/OA-[0-9]+\/[FS]\/1\/datasetView\.do|www\.data\.go\.kr\/data\/[0-9]+\/(?:openapi|fileData)\.do)$/,
    );
    assert.match(source.observedDataUpdatedAt, /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/);
    assert.match(source.retrievedAt, /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/);
    assert.ok(source.owner);
    assert.ok(source.provider);
    assert.ok(source.updateFrequency);
    assert.ok(source.coverageScope);
    assert.ok(Array.isArray(source.coverageScope.regionIds));
    assert.ok(Array.isArray(source.coverageScope.operatorIds));
    assert.ok(Array.isArray(source.coverageScope.sourceDomains));
  }
});

test("KRIC source 후보는 상세 근거 완료 상태와 production 분리를 고정한다", () => {
  const inventory = readJson("tools/datapack/source-inventory.json");
  const candidates = readJson("tools/datapack/source-candidates.json");
  const productionSourceIds = new Set(inventory.sources.map((source) => source.id));
  const kricCandidates = candidates.candidates.filter((candidate) => candidate.id.startsWith("kric-"));

  assert.equal(candidates.schemaVersion, 1);
  assert.equal(candidates.artifactKind, "production-source-candidates");
  assert.equal(candidates.source, "easysubway_public_subway_api_inventory.xlsx");
  assert.deepEqual(
    kricCandidates.map((candidate) => candidate.id).sort(),
    [
      "kric-station-convenience-standard",
      "kric-station-info",
      "kric-station-movement-detailed",
      "kric-station-movement-standard",
      "kric-station-platform",
      "kric-station-transfer-info",
      "kric-subway-route-info",
      "kric-train-operation-organ",
      "kric-transfer-movement-detailed",
      "kric-transfer-movement-standard",
    ],
  );

  for (const candidate of kricCandidates) {
    assert.equal(candidate.priority, "P0");
    assert.equal(candidate.licenseEvidenceStatus, "confirmed_attribution");
    assert.equal(candidate.sampleEvidenceStatus, "sample_url_documented_key_required");
    assert.equal(candidate.admissionStatus, "evidence_recorded_admin_review_required");
    assert.equal(productionSourceIds.has(candidate.id), false, `${candidate.id} must not be in production source inventory`);
    assert.match(candidate.detailUrl, /^https:\/\/data\.kric\.go\.kr\/rips\/M_01_02\//);
    assert.match(candidate.requestUrl, /^https:\/\/openapi\.kric\.go\.kr\/openapi\//);
    assert.equal(candidate.evidence.detailPageUrl, candidate.detailUrl);
    assert.equal(candidate.evidence.endpoint, candidate.requestUrl);
    assert.equal(candidate.evidence.usePermissionRange, "저작권표시");
    assert.deepEqual(candidate.evidence.formats.sort(), ["JSON", "XML"]);
    assert.match(candidate.evidence.sampleUrl, /serviceKey=\[서비스키값\]/);
    assert.ok(candidate.evidence.outputFields.length > 0);
    assert.deepEqual(candidate.evidence.missingEvidence, ["sampleResponse"]);
    assert.ok(candidate.nextAction);
  }
});

test("서울 TOPIS 실시간 후보는 backend-only key 경계와 production 분리를 고정한다", () => {
  const inventory = readJson("tools/datapack/source-inventory.json");
  const candidates = readJson("tools/datapack/source-candidates.json");
  const productionSourceIds = new Set(inventory.sources.map((source) => source.id));
  const productionSourceByDatasetUrl = new Map(inventory.sources.map((source) => [source.datasetUrl, source]));
  const topisCandidates = candidates.candidates.filter((candidate) => candidate.id.startsWith("seoul-topis-realtime-"));

  assert.deepEqual(
    topisCandidates.map((candidate) => candidate.id).sort(),
    ["seoul-topis-realtime-station-arrival", "seoul-topis-realtime-train-position"],
  );

  for (const candidate of topisCandidates) {
    assert.equal(candidate.priority, "P0");
    assert.equal(candidate.licenseEvidenceStatus, "confirmed_attribution");
    assert.equal(candidate.sampleEvidenceStatus, "sample_url_documented_key_required");
    assert.equal(candidate.admissionStatus, "evidence_recorded_admin_review_required");
    assert.equal(candidate.serviceKeyHandling, "backend_secret_only");
    assert.equal(candidate.mobileEmbeddingAllowed, false);
    assert.equal(candidate.dataRetentionPolicy, "provider_does_not_offer_past_realtime_data");
    assert.equal(productionSourceIds.has(candidate.id), false, `${candidate.id} must not be in production source inventory`);
    assert.match(candidate.detailUrl, /^https:\/\/data\.seoul\.go\.kr\/dataList\/OA-/);
    assert.match(candidate.requestUrl, /^http:\/\/swopenapi\.seoul\.go\.kr\/api\/subway\/\{serviceKey\}\/json\/realtime/);
    assert.equal(candidate.evidence.detailPageUrl, candidate.detailUrl);
    assert.equal(candidate.evidence.endpoint, candidate.requestUrl);
    assert.equal(candidate.evidence.usePermissionRange, "공공누리 1유형");
    assert.deepEqual(candidate.evidence.formats, ["JSON"]);
    assert.match(candidate.evidence.sampleUrl, /\[서비스키값\]/);
    assert.ok(candidate.evidence.coverageLimitations.length >= 2);
    assert.ok(candidate.evidence.outputFields.includes("recptnDt"));
    assert.deepEqual(candidate.evidence.missingEvidence, ["sampleResponse"]);
    assert.ok(candidate.nextAction);

    const productionSource = productionSourceByDatasetUrl.get(candidate.detailUrl);
    if (productionSource) {
      assert.equal(candidate.productionInventoryReferenceId, productionSource.id);
      assert.match(candidate.productionInventoryRelationship, /live_provider_contract_remains_candidate/);
    }
  }
});

test("KRIC 환승 이동경로 후보는 상세 근거가 있어도 route graph edge로 자동 승격하지 않는다", () => {
  const candidates = readJson("tools/datapack/source-candidates.json");
  const candidate = candidates.candidates.find(({ id }) => id === "kric-transfer-movement-detailed");

  assert.ok(candidate);
  assert.equal(candidate.licenseEvidenceStatus, "confirmed_attribution");
  assert.equal(candidate.sampleEvidenceStatus, "sample_url_documented_key_required");
  assert.equal(candidate.admissionStatus, "evidence_recorded_admin_review_required");
  assert.equal(candidate.automaticRouteGraphEdgeAllowed, false);
  assert.equal(candidate.evidence.detailPageUrl, candidate.detailUrl);
  assert.equal(candidate.evidence.endpoint, candidate.requestUrl);
  assert.equal(candidate.evidence.usePermissionRange, "저작권표시");
  assert.deepEqual(candidate.evidence.formats.sort(), ["JSON", "XML"]);
  assert.match(candidate.evidence.sampleUrl, /serviceKey=\[서비스키값\]/);
  assert.deepEqual(
    candidate.evidence.outputFields.sort(),
    [
      "chtnMvTpOrdr",
      "edMovePath",
      "elvtSttCd",
      "elvtTpCd",
      "imgPath",
      "mvContDtl",
      "mvPathMgNo",
      "stMovePath",
    ],
  );
  assert.deepEqual(candidate.evidence.missingConfirmedEdgeFields.sort(), ["distanceMeters", "durationSeconds"]);
});

test("KRIC 출입구 승강장 이동경로 후보는 상세 근거가 있어도 route graph edge로 자동 승격하지 않는다", () => {
  const candidates = readJson("tools/datapack/source-candidates.json");
  const candidate = candidates.candidates.find(({ id }) => id === "kric-station-movement-detailed");

  assert.ok(candidate);
  assert.equal(candidate.licenseEvidenceStatus, "confirmed_attribution");
  assert.equal(candidate.sampleEvidenceStatus, "sample_url_documented_key_required");
  assert.equal(candidate.admissionStatus, "evidence_recorded_admin_review_required");
  assert.equal(candidate.automaticRouteGraphEdgeAllowed, false);
  assert.equal(
    candidate.detailUrl,
    "https://data.kric.go.kr/rips/M_01_02/detail.do?id=306&service=vulnerableUserInfo&operation=stationMovement&page=2",
  );
  assert.equal(candidate.evidence.detailPageUrl, candidate.detailUrl);
  assert.equal(candidate.evidence.endpoint, candidate.requestUrl);
  assert.equal(candidate.evidence.usePermissionRange, "저작권표시");
  assert.match(candidate.evidence.sampleUrl, /serviceKey=\[서비스키값\]/);
  assert.deepEqual(candidate.evidence.formats.sort(), ["JSON", "XML"]);
  assert.deepEqual(candidate.evidence.outputFields.sort(), [
    "edMovePath",
    "elvtSttCd",
    "elvtTpCd",
    "exitMvTpOrdr",
    "imgPath",
    "mvContDtl",
    "mvPathMgNo",
    "stMovePath",
  ]);
  assert.deepEqual(candidate.evidence.missingConfirmedEdgeFields.sort(), ["distanceMeters", "durationSeconds"]);
  assert.deepEqual(candidate.evidence.missingEvidence, ["sampleResponse"]);
});

test("KRIC 출입구 승강장 이동경로 표준 후보는 상세 페이지 라이선스와 출력변수 근거를 기록한다", () => {
  const candidates = readJson("tools/datapack/source-candidates.json");
  const candidate = candidates.candidates.find(({ id }) => id === "kric-station-movement-standard");

  assert.ok(candidate);
  assert.equal(candidate.licenseEvidenceStatus, "confirmed_attribution");
  assert.equal(candidate.sampleEvidenceStatus, "sample_url_documented_key_required");
  assert.equal(candidate.admissionStatus, "evidence_recorded_admin_review_required");
  assert.equal(candidate.automaticRouteGraphEdgeAllowed, false);
  assert.equal(candidate.detailUrl, "https://data.kric.go.kr/rips/M_01_02/detail.do?id=429&service=handicapped&operation=stationMovement&page=1");
  assert.equal(candidate.evidence.detailPageUrl, candidate.detailUrl);
  assert.equal(candidate.evidence.usePermissionRange, "저작권표시");
  assert.equal(candidate.evidence.endpoint, candidate.requestUrl);
  assert.match(candidate.evidence.sampleUrl, /serviceKey=\[서비스키값\]/);
  assert.deepEqual(candidate.evidence.formats.sort(), ["JSON", "XML"]);
  assert.deepEqual(candidate.evidence.outputFields.sort(), [
    "edMovePath",
    "elvtSttCd",
    "elvtTpCd",
    "exitMvTpOrdr",
    "imgPath",
    "mvContDtl",
    "mvPathMgNo",
    "stMovePath",
  ]);
  assert.deepEqual(candidate.evidence.missingEvidence, ["sampleResponse"]);
  assert.deepEqual(candidate.evidence.missingConfirmedEdgeFields.sort(), ["distanceMeters", "durationSeconds"]);
});

test("KRIC 환승 이동경로 표준 후보는 상세 페이지 라이선스와 출력변수 근거를 기록한다", () => {
  const candidates = readJson("tools/datapack/source-candidates.json");
  const candidate = candidates.candidates.find(({ id }) => id === "kric-transfer-movement-standard");

  assert.ok(candidate);
  assert.equal(candidate.licenseEvidenceStatus, "confirmed_attribution");
  assert.equal(candidate.sampleEvidenceStatus, "sample_url_documented_key_required");
  assert.equal(candidate.admissionStatus, "evidence_recorded_admin_review_required");
  assert.equal(candidate.automaticRouteGraphEdgeAllowed, false);
  assert.equal(candidate.detailUrl, "https://data.kric.go.kr/rips/M_01_02/detail.do?id=428&service=handicapped&operation=transferMovement&page=2");
  assert.equal(candidate.evidence.detailPageUrl, candidate.detailUrl);
  assert.equal(candidate.evidence.usePermissionRange, "저작권표시");
  assert.equal(candidate.evidence.endpoint, candidate.requestUrl);
  assert.match(candidate.evidence.sampleUrl, /serviceKey=\[서비스키값\]/);
  assert.deepEqual(candidate.evidence.formats.sort(), ["JSON", "XML"]);
  assert.deepEqual(candidate.evidence.outputFields.sort(), [
    "chtnMvTpOrdr",
    "edMovePath",
    "elvtSttCd",
    "elvtTpCd",
    "imgPath",
    "mvContDtl",
    "mvPathMgNo",
    "stMovePath",
  ]);
  assert.deepEqual(candidate.evidence.missingEvidence, ["sampleResponse"]);
  assert.deepEqual(candidate.evidence.missingConfirmedEdgeFields.sort(), ["distanceMeters", "durationSeconds"]);
});

test("KRIC 편의정보 표준 후보는 상세 페이지 라이선스와 출력변수 근거를 기록한다", () => {
  const candidates = readJson("tools/datapack/source-candidates.json");
  const candidate = candidates.candidates.find(({ id }) => id === "kric-station-convenience-standard");

  assert.ok(candidate);
  assert.equal(candidate.licenseEvidenceStatus, "confirmed_attribution");
  assert.equal(candidate.sampleEvidenceStatus, "sample_url_documented_key_required");
  assert.equal(candidate.admissionStatus, "evidence_recorded_admin_review_required");
  assert.equal(candidate.evidence.detailPageUrl, candidate.detailUrl);
  assert.equal(candidate.evidence.endpoint, candidate.requestUrl);
  assert.equal(candidate.evidence.usePermissionRange, "저작권표시");
  assert.match(candidate.evidence.sampleUrl, /serviceKey=\[서비스키값\]/);
  assert.deepEqual(candidate.evidence.formats.sort(), ["JSON", "XML"]);
  assert.deepEqual(
    candidate.evidence.outputFields.sort(),
    ["dtlLoc", "grndDvCd", "gubun", "imgPath", "mlFmlDvCd", "stinFlor", "trfcWeakDvCd"],
  );
  assert.deepEqual(candidate.evidence.missingEvidence.sort(), ["sampleResponse"]);
});

test("KRIC 도시철도 전체노선정보 후보는 상세 페이지 라이선스와 출력변수 근거를 기록한다", () => {
  const candidates = readJson("tools/datapack/source-candidates.json");
  const candidate = candidates.candidates.find(({ id }) => id === "kric-subway-route-info");

  assert.ok(candidate);
  assert.equal(candidate.licenseEvidenceStatus, "confirmed_attribution");
  assert.equal(candidate.sampleEvidenceStatus, "sample_url_documented_key_required");
  assert.equal(candidate.admissionStatus, "evidence_recorded_admin_review_required");
  assert.equal(candidate.detailUrl, "https://data.kric.go.kr/rips/M_01_02/detail.do?id=431&service=trainUseInfo&operation=subwayRouteInfo&page=2");
  assert.equal(candidate.evidence.detailPageUrl, candidate.detailUrl);
  assert.equal(candidate.evidence.usePermissionRange, "저작권표시");
  assert.equal(candidate.evidence.endpoint, candidate.requestUrl);
  assert.match(candidate.evidence.sampleUrl, /serviceKey=\[서비스키값\]/);
  assert.deepEqual(candidate.evidence.formats.sort(), ["JSON", "XML"]);
  assert.deepEqual(candidate.evidence.outputFields.sort(), [
    "lnCd",
    "mreaWideCd",
    "railOprIsttCd",
    "routCd",
    "routNm",
    "stinCd",
    "stinConsOrdr",
    "stinNm",
  ]);
  assert.deepEqual(candidate.evidence.missingEvidence, ["sampleResponse"]);
});

test("KRIC 역사별 정보 후보는 상세 페이지 라이선스와 출력변수 근거를 기록한다", () => {
  const candidates = readJson("tools/datapack/source-candidates.json");
  const candidate = candidates.candidates.find(({ id }) => id === "kric-station-info");

  assert.ok(candidate);
  assert.equal(candidate.licenseEvidenceStatus, "confirmed_attribution");
  assert.equal(candidate.sampleEvidenceStatus, "sample_url_documented_key_required");
  assert.equal(candidate.admissionStatus, "evidence_recorded_admin_review_required");
  assert.equal(candidate.detailUrl, "https://data.kric.go.kr/rips/M_01_02/detail.do?id=183&service=convenientInfo&operation=stationInfo&page=2");
  assert.equal(candidate.evidence.detailPageUrl, candidate.detailUrl);
  assert.equal(candidate.evidence.usePermissionRange, "저작권표시");
  assert.equal(candidate.evidence.endpoint, candidate.requestUrl);
  assert.match(candidate.evidence.sampleUrl, /serviceKey=\[서비스키값\]/);
  assert.deepEqual(candidate.evidence.formats.sort(), ["JSON", "XML"]);
  assert.deepEqual(candidate.evidence.outputFields.sort(), [
    "lnCd",
    "lonmAdr",
    "mapCordX",
    "mapCordY",
    "railOprIsttCd",
    "roadNmAdr",
    "stinCd",
    "stinLocLat",
    "stinLocLon",
    "stinNm",
    "stinNmEng",
    "stinNmJpn",
    "stinNmRom",
    "stinNmSimpcina",
    "stinNmTradcina",
    "strkZone",
  ]);
  assert.deepEqual(candidate.evidence.missingEvidence, ["sampleResponse"]);
});

test("KRIC 열차운영기관정보 후보는 상세 페이지 라이선스와 출력변수 근거를 기록한다", () => {
  const candidates = readJson("tools/datapack/source-candidates.json");
  const candidate = candidates.candidates.find(({ id }) => id === "kric-train-operation-organ");

  assert.ok(candidate);
  assert.equal(candidate.licenseEvidenceStatus, "confirmed_attribution");
  assert.equal(candidate.sampleEvidenceStatus, "sample_url_documented_key_required");
  assert.equal(candidate.admissionStatus, "evidence_recorded_admin_review_required");
  assert.equal(
    candidate.detailUrl,
    "https://data.kric.go.kr/rips/M_01_02/detail.do?id=266&service=convenientInfo&operation=trainOperationOrgan&page=3",
  );
  assert.equal(candidate.evidence.detailPageUrl, candidate.detailUrl);
  assert.equal(candidate.evidence.endpoint, candidate.requestUrl);
  assert.equal(candidate.evidence.usePermissionRange, "저작권표시");
  assert.match(candidate.evidence.sampleUrl, /serviceKey=\[서비스키값\]/);
  assert.deepEqual(candidate.evidence.formats.sort(), ["JSON", "XML"]);
  assert.deepEqual(candidate.evidence.outputFields.sort(), ["railOprIsttCd", "railOprIsttNm"]);
  assert.deepEqual(candidate.evidence.missingEvidence, ["sampleResponse"]);
});

test("KRIC 역사별 환승정보 후보는 상세 페이지 라이선스와 출력변수 근거를 기록한다", () => {
  const candidates = readJson("tools/datapack/source-candidates.json");
  const candidate = candidates.candidates.find(({ id }) => id === "kric-station-transfer-info");

  assert.ok(candidate);
  assert.equal(candidate.licenseEvidenceStatus, "confirmed_attribution");
  assert.equal(candidate.sampleEvidenceStatus, "sample_url_documented_key_required");
  assert.equal(candidate.admissionStatus, "evidence_recorded_admin_review_required");
  assert.equal(candidate.detailUrl, "https://data.kric.go.kr/rips/M_01_02/detail.do?id=181&service=convenientInfo&operation=stationTransferInfo&page=2");
  assert.equal(candidate.evidence.detailPageUrl, candidate.detailUrl);
  assert.equal(candidate.evidence.usePermissionRange, "저작권표시");
  assert.equal(candidate.evidence.endpoint, candidate.requestUrl);
  assert.match(candidate.evidence.sampleUrl, /serviceKey=\[서비스키값\]/);
  assert.deepEqual(candidate.evidence.formats.sort(), ["JSON", "XML"]);
  assert.deepEqual(candidate.evidence.outputFields.sort(), [
    "chtnDst",
    "chtnLn",
    "clsLocCont",
    "lnCd",
    "railOprIsttCd",
    "stLocCont",
    "stinCd",
  ]);
  assert.deepEqual(candidate.evidence.missingEvidence, ["sampleResponse"]);
});

test("KRIC 역사별 승강장 정보 후보는 상세 페이지 라이선스와 출력변수 근거를 기록한다", () => {
  const candidates = readJson("tools/datapack/source-candidates.json");
  const candidate = candidates.candidates.find(({ id }) => id === "kric-station-platform");

  assert.ok(candidate);
  assert.equal(candidate.licenseEvidenceStatus, "confirmed_attribution");
  assert.equal(candidate.sampleEvidenceStatus, "sample_url_documented_key_required");
  assert.equal(candidate.admissionStatus, "evidence_recorded_admin_review_required");
  assert.equal(candidate.detailUrl, "https://data.kric.go.kr/rips/M_01_02/detail.do?id=433&service=convenientInfo&operation=stPlf&page=1");
  assert.equal(candidate.evidence.detailPageUrl, candidate.detailUrl);
  assert.equal(candidate.evidence.usePermissionRange, "저작권표시");
  assert.equal(candidate.evidence.endpoint, candidate.requestUrl);
  assert.match(candidate.evidence.sampleUrl, /serviceKey=\[서비스키값\]/);
  assert.deepEqual(candidate.evidence.formats.sort(), ["JSON", "XML"]);
  assert.deepEqual(candidate.evidence.outputFields.sort(), [
    "grndDvCd",
    "lnCd",
    "plfCplFlg",
    "plfNo",
    "plfTpCd",
    "plfTpNm",
    "railOprIsttCd",
    "runDirTmnStinCd",
    "scrCharExt",
    "sfFotExt",
    "stinCd",
    "stinFlor",
    "updnDvcd",
  ]);
  assert.deepEqual(candidate.evidence.missingEvidence, ["sampleResponse"]);
});

test("운영 데이터팩 공식 출처 ingest adapter는 stable id mapping과 retired id 재사용 금지를 강제한다", () => {
  const importer = read("tools/datapack/import-official-sources.mjs");

  assert.match(importer, /source inventory missing/);
  assert.match(importer, /source inventory schemaVersion must be 1/);
  assert.match(importer, /inventory\.region must match input\.region/);
  assert.match(importer, /source mapping missing/);
  assert.match(importer, /station id reuse is forbidden/);
  assert.match(importer, /station line mapping conflict/);
  assert.match(importer, /stationLineId must equal stationId:lineId/);
  assert.match(importer, /station mapping evidence is required/);
  assert.match(importer, /minimumProductionCoverage must be an object for production pack/);
  assert.match(importer, /production coverage \${label} \${actualCount} is below required minimum \${value}/);
  assert.match(importer, /coverageEvidence must be a non-empty array for production pack/);
  assert.match(importer, /coverage evidence unsupported by source inventory/);
  assert.match(importer, /production coverage evidence missing/);
  assert.match(importer, /productionCoverageEvidence: JSON\.stringify\(productionCoverageEvidence\)/);
  assert.match(importer, /coverageScope: \{/);
  assert.match(importer, /duplicate argument/);
  assert.match(importer, /sourceIngestAdapter: "official-source-ingest-v1"/);

  const builder = read("tools/datapack/build-datapack.mjs");
  const validator = read("tools/datapack/validate-datapack.mjs");
  for (const source of [builder, validator]) {
    assert.match(source, /productionMinimumTableRowNames = \["stations", "station_lines", "network_edges", "facilities"\]/);
    assert.match(source, /production minimumTableRows must define positive stations, station_lines, network_edges, and facilities/);
    assert.match(source, /validateSourceInventoryCoverageScope/);
    assert.match(source, /production sourceInventory\.coverageScope/);
    assert.match(source, /sourceInventory\.coverageScope/);
  }
});

test("backend release image는 bootJar 산출물만 포함하는 runtime image로 패키징된다", () => {
  assert.equal(existsSync(path.join(root, "backend/Dockerfile")), true, "backend Dockerfile must exist");
  assert.equal(existsSync(path.join(root, "backend/.dockerignore")), true, "backend .dockerignore must exist");

  const dockerfile = read("backend/Dockerfile");
  const dockerignore = read("backend/.dockerignore");

  assert.match(dockerfile, /^FROM eclipse-temurin:21-jre$/m);
  assert.match(dockerfile, /^WORKDIR \/app$/m);
  assert.match(dockerfile, /^COPY build\/libs\/\*\.jar app\.jar$/m);
  assert.match(dockerfile, /^EXPOSE 8080$/m);
  assert.match(dockerfile, /^ENV SPRING_PROFILES_ACTIVE=prod$/m);
  assert.match(dockerfile, /^ENTRYPOINT \["java", "-jar", "\/app\/app\.jar"\]$/m);
  assert.doesNotMatch(dockerfile, /EASYSUBWAY_/);
  assert.doesNotMatch(dockerfile, /COPY \. \./);
  assert.match(dockerignore, /^\*$/m);
  assert.match(dockerignore, /^!build$/m);
  assert.match(dockerignore, /^!build\/libs$/m);
  assert.match(dockerignore, /^!build\/libs\/\*\.jar$/m);
  assert.doesNotMatch(dockerignore, /^!\.env/m);
});

test("OSV baseline은 기존 취약점 ID를 lockfile 위치별로 좁게 예외 처리한다", () => {
  assert.equal(existsSync(path.join(root, ".github/osv-scanner-release-baseline.toml")), false);

  const baselineConfigs = [
    {
      configPath: "apps/mobile/android/app/osv-scanner.toml",
      lockfilePath: "apps/mobile/android/app/gradle.lockfile",
      expectedCount: 33,
      reasonPattern: /^reason = "기존 Android Gradle lockfile 기준선에서 발견된 취약점은 별도 업그레이드 작업으로 처리한다\."/m,
    },
    {
      configPath: "backend/osv-scanner.toml",
      lockfilePath: "backend/gradle.lockfile",
      expectedCount: 3,
      reasonPattern: /^reason = "기존 backend Gradle lockfile 기준선에서 발견된 취약점은 별도 업그레이드 작업으로 처리한다\."/m,
    },
  ];
  const allIds = new Set();
  let totalIds = 0;

  for (const { configPath, lockfilePath, expectedCount, reasonPattern } of baselineConfigs) {
    assert.equal(path.dirname(configPath), path.dirname(lockfilePath));
    const config = read(configPath);
    const blocks = ignoredVulnBlocks(config);
    const ids = new Set();

    assert.equal(blocks.length, expectedCount, `${configPath} must document the current vulnerable advisory IDs`);
    assert.doesNotMatch(config, /\[\[PackageOverrides\]\]/);
    assert.doesNotMatch(config, /^vulnerability\.ignore = true/m);
    assert.doesNotMatch(config, /^ignore = true/m);

    for (const block of blocks) {
      const id = block.match(/^id = "([^"]+)"/m)?.[1];

      assert.ok(id, "OSV baseline ignore must include a vulnerability id");
      assert.match(id, /^GHSA-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}$/);
      assert.ok(!ids.has(id), `${configPath} must not duplicate vulnerability IDs`);
      assert.match(block, reasonPattern);
      ids.add(id);
      allIds.add(id);
      totalIds += 1;
    }
  }

  assert.equal(totalIds, 36, "OSV baseline must keep per-lockfile findings explicit");
  assert.equal(allIds.size, 36, "OSV baseline must track the current unique advisory ID set");
});

test("백엔드 런타임 의존성은 보안 패치 기준 버전을 사용한다", () => {
  const backendBuild = read("backend/build.gradle");
  const backendLockfile = read("backend/gradle.lockfile");

  assert.match(backendBuild, /id 'org\.springframework\.boot' version '3\.5\.(?:1[5-9]|[2-9][0-9]|[1-9][0-9]{2,})'/);
  assert.match(backendLockfile, /^org\.apache\.tomcat\.embed:tomcat-embed-core:10\.1\.(?:5[5-9]|[6-9][0-9]|[1-9][0-9]{2,})=/m);
  assert.match(backendLockfile, /^org\.springframework\.security:spring-security-web:6\.5\.(?:1[1-9]|[2-9][0-9]|[1-9][0-9]{2,})=/m);
  assert.match(backendLockfile, /^org\.thymeleaf:thymeleaf-spring6:3\.1\.(?:5|[6-9]|[1-9][0-9]+)\.RELEASE=/m);
  assert.match(backendLockfile, /^org\.springframework:spring-webmvc:6\.2\.(?:19|[2-9][0-9]|[1-9][0-9]{2,})=/m);
  assert.match(backendLockfile, /^org\.apache\.commons:commons-lang3:3\.(?:18|19|[2-9][0-9]|[1-9][0-9]{2,})\.[0-9]+=/m);
  assert.match(backendLockfile, /^org\.apache\.commons:commons-compress:1\.(?:26\.[2-9]|2[7-9]\.[0-9]+|[3-9][0-9]\.[0-9]+)=/m);
  assert.match(backendLockfile, /^org\.apache\.logging\.log4j:log4j-core:2\.(?:25\.(?:[3-9]|[1-9][0-9]+)|(?:2[6-9]|[3-9][0-9]|[1-9][0-9]{2,})\.[0-9]+)=/m);
  assert.match(backendLockfile, /^org\.testcontainers:database-commons:1\.21\.4=/m);
  assert.match(backendLockfile, /^org\.testcontainers:jdbc:1\.21\.4=/m);
  assert.match(backendLockfile, /^org\.testcontainers:junit-jupiter:1\.21\.4=/m);
  assert.match(backendLockfile, /^org\.testcontainers:postgresql:1\.21\.4=/m);
  assert.match(backendLockfile, /^org\.testcontainers:testcontainers:1\.21\.4=/m);
  assert.doesNotMatch(backendLockfile, /^org\.apache\.tomcat\.embed:tomcat-embed-core:10\.1\.46=/m);
  assert.doesNotMatch(backendLockfile, /^org\.springframework\.security:spring-security-web:6\.5\.5=/m);
  assert.doesNotMatch(backendLockfile, /^org\.thymeleaf:thymeleaf-spring6:3\.1\.3\.RELEASE=/m);
  assert.doesNotMatch(backendLockfile, /^org\.apache\.commons:commons-lang3:3\.17\.0=/m);
  assert.doesNotMatch(backendLockfile, /^org\.apache\.commons:commons-compress:1\.24\.0=/m);
  assert.doesNotMatch(backendLockfile, /^org\.apache\.logging\.log4j:log4j-core:2\.24\.3=/m);
});

test("Docker Compose는 backend 필수 서비스를 기본값으로 노출하고 관측성 선택 서비스를 profile로 분리한다", () => {
  const compose = read("infra/docker-compose.yml");
  const postgresBlock = compose.match(/  postgres:\n[\s\S]*?\n\n  object-storage:/)?.[0] ?? "";
  const objectStorageBlock = compose.match(/  object-storage:\n[\s\S]*?\n\n  prometheus:/)?.[0] ?? "";

  assert.match(compose, /postgres:\n/);
  assert.match(compose, /image: postgis\/postgis:16-3\.5/);
  assert.doesNotMatch(postgresBlock, /profiles:/);
  assert.match(compose, /POSTGRES_DB: \$\{EASYSUBWAY_POSTGRES_DB:-easysubway\}/);
  assert.match(compose, /POSTGRES_USER: \$\{EASYSUBWAY_POSTGRES_USER:-easysubway\}/);
  assert.match(compose, /POSTGRES_PASSWORD: \$\{EASYSUBWAY_POSTGRES_PASSWORD:-easysubway_local\}/);
  assert.match(compose, /"\$\{EASYSUBWAY_POSTGRES_PORT:-5432\}:5432"/);
  assert.match(compose, /pg_isready -U \$\$\{POSTGRES_USER\} -d \$\$\{POSTGRES_DB\}/);
  assert.match(compose, /postgres-data:\/var\/lib\/postgresql\/data/);

  assert.match(compose, /object-storage:\n/);
  assert.match(compose, /image: minio\/minio:/);
  assert.doesNotMatch(objectStorageBlock, /profiles:/);
  assert.match(compose, /MINIO_ROOT_USER: \$\{EASYSUBWAY_OBJECT_STORAGE_ACCESS_KEY:-easysubway_local\}/);
  assert.match(compose, /MINIO_ROOT_PASSWORD: \$\{EASYSUBWAY_OBJECT_STORAGE_SECRET_KEY:-easysubway_local_secret\}/);
  assert.match(compose, /"\$\{EASYSUBWAY_OBJECT_STORAGE_PORT:-9000\}:9000"/);
  assert.match(compose, /object-storage-data:\/data/);

  assert.doesNotMatch(compose, /redis:\n/);
  assert.doesNotMatch(compose, /EASYSUBWAY_REDIS_/);
  assert.match(compose, /prometheus:[\s\S]*profiles:\s*\n\s*-\s*observability/);
  assert.match(compose, /loki:[\s\S]*profiles:\s*\n\s*-\s*observability/);
  assert.match(compose, /grafana:[\s\S]*profiles:\s*\n\s*-\s*observability/);
  assert.match(compose, /^volumes:\n  postgres-data:\n  object-storage-data:\n  prometheus-data:/m);
  assert.doesNotMatch(compose, /^  redis-data:/m);
});

test("로컬 PostgreSQL 백업과 복구 리허설 기준선을 제공한다", () => {
  const backupScript = read("tools/ops/postgres-backup.sh");
  const restoreScript = read("tools/ops/postgres-restore-rehearsal.sh");

  assert.match(backupScript, /set -euo pipefail/);
  assert.match(backupScript, /EASYSUBWAY_ENV_FILE:-\$\{ROOT_DIR\}\/\.env\.example/);
  assert.match(backupScript, /EASYSUBWAY_BACKUP_DIR:-\$\{ROOT_DIR\}\/\.codex\/backups/);
  assert.match(backupScript, /umask 077/);
  assert.match(backupScript, /chmod 700 "\$\{BACKUP_DIR\}"/);
  assert.match(backupScript, /mktemp "\$\{BACKUP_DIR\}\/easysubway-postgres-\$\{timestamp\}\.XXXXXX"/);
  assert.match(backupScript, /backup_file="\$\{temp_file\}\.dump"/);
  assert.match(backupScript, /trap cleanup EXIT/);
  assert.match(backupScript, /docker compose --env-file "\$\{ENV_FILE\}" -f "\$\{COMPOSE_FILE\}" exec -T postgres sh -lc/);
  assert.match(backupScript, /pg_dump --format=custom --no-owner --no-privileges -U "\$POSTGRES_USER" "\$POSTGRES_DB"/);
  assert.match(backupScript, /> "\$\{temp_file\}"/);
  assert.match(backupScript, /test -s "\$\{temp_file\}"/);
  assert.match(backupScript, /mv "\$\{temp_file\}" "\$\{backup_file\}"/);
  assert.match(backupScript, /trap - EXIT/);

  assert.match(restoreScript, /set -euo pipefail/);
  assert.match(restoreScript, /Usage: tools\/ops\/postgres-restore-rehearsal\.sh <backup-file>/);
  assert.match(restoreScript, /EASYSUBWAY_RESTORE_DB:-easysubway_restore_rehearsal/);
  assert.match(restoreScript, /docker compose --env-file "\$\{ENV_FILE\}" -f "\$\{COMPOSE_FILE\}" exec -T -e RESTORE_DB="\$\{RESTORE_DB\}" postgres sh -lc/);
  assert.match(restoreScript, /sh -lc '\nset -eu\n/);
  assert.match(restoreScript, /"\$POSTGRES_DB"\|postgres\|template0\|template1/);
  assert.match(restoreScript, /Refusing to use protected restore database/);
  assert.match(restoreScript, /dropdb --if-exists -U "\$POSTGRES_USER" "\$RESTORE_DB"/);
  assert.match(restoreScript, /createdb -U "\$POSTGRES_USER" "\$RESTORE_DB"/);
  assert.match(restoreScript, /pg_restore --clean --if-exists --no-owner --no-privileges -U "\$POSTGRES_USER" -d "\$RESTORE_DB"/);
  assert.match(restoreScript, /trap cleanup EXIT/);
});

test("시설 신고 사진 백업은 로컬 전용 객체와 manifest 기준선을 제공한다", () => {
  const backupScript = read("tools/ops/facility-report-photo-backup.sh");

  assert.match(backupScript, /set -euo pipefail/);
  assert.match(backupScript, /EASYSUBWAY_ENV_FILE:-\$\{ROOT_DIR\}\/\.env\.example/);
  assert.match(backupScript, /EASYSUBWAY_PHOTO_BACKUP_DIR:-\$\{ROOT_DIR\}\/\.codex\/backups\/facility-report-photos/);
  assert.match(backupScript, /EASYSUBWAY_REPORTS_PHOTOS_STORAGE_DIR:-\$\{TMPDIR:-\/tmp\}\/easysubway-report-photos/);
  assert.match(backupScript, /facility report photo object not found/);
  assert.match(backupScript, /umask 077/);
  assert.match(backupScript, /chmod 700 "\$\{BACKUP_DIR\}"/);
  assert.match(backupScript, /objects_dir="\$\{run_dir\}\/objects"/);
  assert.match(backupScript, /manifest_file="\$\{run_dir\}\/manifest\.tsv"/);
  assert.match(backupScript, /psql -v ON_ERROR_STOP=1 -U "\$POSTGRES_USER" "\$POSTGRES_DB"/);
  assert.match(backupScript, /COPY \(\nSELECT report_id,/);
  assert.match(backupScript, /REPLACE\(REPLACE\(ENCODE\(CONVERT_TO\(COALESCE\(photo_file_name, ''\), 'UTF8'\), 'base64'\), E'\\n', ''\), E'\\r', ''\)/);
  assert.match(backupScript, /REPLACE\(REPLACE\(ENCODE\(CONVERT_TO\(COALESCE\(photo_content_type, ''\), 'UTF8'\), 'base64'\), E'\\n', ''\), E'\\r', ''\)/);
  assert.match(backupScript, /COALESCE\(photo_object_key, ''\) AS photo_object_key/);
  assert.match(backupScript, /COALESCE\(photo_thumbnail_object_key, ''\) AS photo_thumbnail_object_key/);
  assert.match(backupScript, /photo_object_key IS NOT NULL/);
  assert.match(backupScript, /photo_object_key <> ''/);
  assert.match(backupScript, /ORDER BY report_id ASC/);
  assert.match(backupScript, /TO STDOUT WITH \(FORMAT text, DELIMITER E'\\t'\)/);
  assert.match(backupScript, /copy_object\(\) \{/);
  assert.match(backupScript, /cp "\$\{source_file\}" "\$\{target_path\}"/);
  assert.match(backupScript, /manifest_field\(\) \{/);
  assert.match(backupScript, /tr '\\t\\r\\n' ' '/);
  assert.match(backupScript, /printf 'report_id\\tfile_name\\tcontent_type\\tobject_key\\tthumbnail_object_key\\tsha256\\tsize_bytes\\tobject_path\\tthumbnail_path\\n'/);
  assert.match(backupScript, /printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n'/);
  assert.match(backupScript, /trap cleanup EXIT/);
  assert.match(backupScript, /printf 'facility report photo backup written: %s\\n' "\$\{run_dir\}"/);
});

test("시설 신고 사진 복구 리허설은 manifest와 object 산출물을 검증한다", async () => {
  const restoreCheckPath = "tools/ops/facility-report-photo-restore-check.mjs";
  const restoreCheckScript = read(restoreCheckPath);
  const fixtureDir = await mkdtemp(path.join(tmpdir(), "easysubway-photo-restore-"));
  const objectsDir = path.join(fixtureDir, "objects", "facility-reports", "report-1");
  const objectPath = path.join(objectsDir, "photo.jpg");
  const objectBytes = Buffer.from("photo-bytes");
  const objectSha256 = "dac6f451810bc38390a3b6e278d686b332a77cf21b2ea95145ad73722b77035d";

  await mkdir(objectsDir, { recursive: true });
  await writeFile(objectPath, objectBytes);
  await writeFile(
    path.join(fixtureDir, "manifest.tsv"),
    [
      "report_id\tfile_name\tcontent_type\tobject_key\tthumbnail_object_key\tsha256\tsize_bytes\tobject_path\tthumbnail_path",
      `report-1\televator.jpg\timage/jpeg\tfacility-reports/report-1/photo.jpg\t\t${objectSha256}\t${objectBytes.length}\tobjects/facility-reports/report-1/photo.jpg\tobjects/`,
    ].join("\n"),
  );

  assert.match(restoreCheckScript, /Usage: node tools\/ops\/facility-report-photo-restore-check\.mjs <restored-photo-backup-dir>/);
  assert.match(restoreCheckScript, /manifest\.tsv/);
  assert.match(restoreCheckScript, /object_path must match object_key/);
  assert.match(restoreCheckScript, /object size mismatch/);
  assert.match(restoreCheckScript, /object sha256 mismatch/);

  const result = execFileSync(process.execPath, [restoreCheckPath, fixtureDir], { cwd: root, encoding: "utf8" });
  assert.match(result, /facility report photo restore rehearsal ok/);
});

test("운영 백업 복구 리허설 gate는 필수 백업 대상과 dry-run 검증 명령을 고정한다", () => {
  const gatePath = "apps/mobile/release/backup-restore-rehearsal-gate.json";
  const checkScriptPath = "tools/ops/backup-restore-rehearsal-check.mjs";
  const photoRestoreCheckPath = "tools/ops/facility-report-photo-restore-check.mjs";
  assert.ok(existsSync(path.join(root, gatePath)), "backup restore rehearsal gate artifact must exist");
  assert.ok(existsSync(path.join(root, checkScriptPath)), "backup restore rehearsal check script must exist");
  assert.ok(existsSync(path.join(root, photoRestoreCheckPath)), "photo restore rehearsal check script must exist");

  const gate = readJson(gatePath);
  const checkScript = read(checkScriptPath);
  const photoRestoreCheckScript = read(photoRestoreCheckPath);
  const readme = read("README.md");

  assert.equal(gate.schemaVersion, 1);
  assert.equal(gate.applicationId, "easysubway");
  assert.equal(gate.releaseGate, "backup-restore-rehearsal");
  assert.equal(gate.releaseBlockerPolicy, true);
  assert.doesNotMatch(JSON.stringify(gate), /\b(TBD|TODO|PLACEHOLDER)\b|\.{3}/i);

  const backupTargets = new Map(gate.backupTargets.map((target) => [target.id, target]));
  const requiredBackupTargetIds = [
    "postgres_application_database",
    "facility_report_photo_objects",
    "datapack_source_inventory",
    "datapack_release_manifest_history",
  ];
  assert.deepEqual([...backupTargets.keys()].sort(), requiredBackupTargetIds.toSorted());

  for (const id of requiredBackupTargetIds) {
    const target = backupTargets.get(id);
    assert.match(target.ownerKo, /담당자/);
    assert.ok(target.backupCommand.length > 0, `${id} must define backup command`);
    assert.ok(target.restoreRehearsalCommand.length > 0, `${id} must define restore rehearsal command`);
    assert.ok(target.successEvidence.length > 0, `${id} must define success evidence`);
    assert.ok(target.failureConditions.length > 0, `${id} must define failure conditions`);
    for (const artifact of target.linkedArtifacts) {
      assert.ok(existsSync(path.join(root, artifact)), `${id} linked artifact must exist: ${artifact}`);
    }
  }

  const photoTarget = backupTargets.get("facility_report_photo_objects");
  assert.equal(
    photoTarget.restoreRehearsalCommand,
    'node tools/ops/facility-report-photo-restore-check.mjs "$EASYSUBWAY_PHOTO_RESTORE_DIR"',
  );
  assert.ok(
    photoTarget.linkedArtifacts.includes(photoRestoreCheckPath),
    "facility photo restore target must link the restore check script",
  );

  assert.match(gate.rehearsalPolicy.frequencyKo, /월 1회|릴리즈/);
  assert.match(gate.rehearsalPolicy.dataSafetyKo, /운영 데이터 직접 복원 금지|격리/);
  assert.match(gate.rehearsalPolicy.requiredOutputKo, /backup-restore-rehearsal/);
  assert.match(checkScript, /backup-restore-rehearsal-gate\.json/);
  assert.match(checkScript, /postgres_application_database/);
  assert.match(checkScript, /datapack_release_manifest_history/);
  assert.match(photoRestoreCheckScript, /manifest\.tsv/);
  assert.match(photoRestoreCheckScript, /sha256/);
  assert.match(readme, /backup-restore-rehearsal-gate\.json/);
  assert.match(readme, /tools\/ops\/backup-restore-rehearsal-check\.mjs/);
  assert.match(readme, /tools\/ops\/facility-report-photo-restore-check\.mjs/);
  assert.doesNotMatch(readme, /backup secret|restore secret/i);

  execFileSync(process.execPath, [checkScriptPath], { cwd: root, encoding: "utf8" });
});

test("저장소 지속적 통합은 Docker Compose 설정을 검증한다", () => {
  const workflow = read(".github/workflows/ci.yml");

  assert.match(workflow, /Repository CI \/ Validate Docker Compose config/);
  assert.match(workflow, /docker compose --env-file \.env\.example -f infra\/docker-compose\.yml config --quiet/);
});

test("로컬 관측성 스택은 Prometheus와 Grafana 기준선을 제공한다", () => {
  const build = read("backend/build.gradle");
  const applicationYml = read("backend/src/main/resources/application.yml");
  const applicationDevYml = read("backend/src/main/resources/application-dev.yml");
  const compose = read("infra/docker-compose.yml");
  const prometheusConfig = read("infra/prometheus/prometheus.yml");
  const grafanaDatasource = read("infra/grafana/provisioning/datasources/prometheus.yml");

  assert.match(build, /implementation 'io\.micrometer:micrometer-registry-prometheus'/);
  assert.match(applicationYml, /management:\s*\n\s*endpoints:\s*\n\s*web:\s*\n\s*exposure:\s*\n\s*include:\s*["']?health\s*,\s*info["']?/);
  assert.doesNotMatch(applicationYml, /prometheus/);
  assert.match(applicationDevYml, /management:\s*\n\s*endpoints:\s*\n\s*web:\s*\n\s*exposure:\s*\n\s*include:\s*["']?health\s*,\s*info\s*,\s*prometheus["']?/);

  assert.match(compose, /prometheus:\n/);
  assert.match(compose, /prometheus:[\s\S]*profiles:\s*\n\s*-\s*observability/);
  assert.match(compose, /image: prom\/prometheus:v[0-9]+\.[0-9]+\.[0-9]+/);
  assert.match(compose, /\.\/prometheus\/prometheus\.yml:\/etc\/prometheus\/prometheus\.yml:ro/);
  assert.match(compose, /"\$\{EASYSUBWAY_PROMETHEUS_PORT:-9090\}:9090"/);
  assert.match(compose, /prometheus-data:\/prometheus/);
  assert.match(compose, /wget --spider -q http:\/\/localhost:9090\/-\/healthy/);

  assert.match(compose, /grafana:\n/);
  assert.match(compose, /grafana:[\s\S]*profiles:\s*\n\s*-\s*observability/);
  assert.match(compose, /image: grafana\/grafana:[0-9]+\.[0-9]+\.[0-9]+/);
  assert.match(compose, /"\$\{EASYSUBWAY_GRAFANA_PORT:-3000\}:3000"/);
  assert.match(compose, /GF_SECURITY_ADMIN_PASSWORD: \$\{EASYSUBWAY_GRAFANA_ADMIN_PASSWORD:-easysubway_local\}/);
  assert.match(compose, /grafana-data:\/var\/lib\/grafana/);
  assert.match(compose, /\.\/grafana\/provisioning:\/etc\/grafana\/provisioning:ro/);
  assert.match(compose, /depends_on:\s*\n\s*prometheus:\s*\n\s*condition: service_healthy[\s\S]*loki:\s*\n\s*condition: service_healthy/);

  assert.match(prometheusConfig, /job_name: "easysubway-backend"/);
  assert.match(prometheusConfig, /metrics_path: "\/actuator\/prometheus"/);
  assert.match(prometheusConfig, /targets: \["host\.docker\.internal:8080"\]/);

  assert.match(grafanaDatasource, /name: easysubway-prometheus/);
  assert.match(grafanaDatasource, /type: prometheus/);
  assert.match(grafanaDatasource, /url: http:\/\/prometheus:9090/);
  assert.match(grafanaDatasource, /isDefault: true/);
});

test("로컬 로그 관측성 스택은 Loki 기준선을 제공한다", () => {
  const compose = read("infra/docker-compose.yml");
  const lokiConfig = read("infra/loki/loki.yml");
  const lokiDatasource = read("infra/grafana/provisioning/datasources/loki.yml");
  const prometheusDatasource = read("infra/grafana/provisioning/datasources/prometheus.yml");

  assert.match(compose, /loki:\n/);
  assert.match(compose, /loki:[\s\S]*profiles:\s*\n\s*-\s*observability/);
  assert.match(compose, /image: grafana\/loki:3\.6\.0/);
  assert.match(compose, /--config\.file=\/etc\/loki\/loki\.yml/);
  assert.match(compose, /\.\/loki\/loki\.yml:\/etc\/loki\/loki\.yml:ro/);
  assert.match(compose, /"127\.0\.0\.1:\$\{EASYSUBWAY_LOKI_PORT:-3100\}:3100"/);
  assert.match(compose, /loki-data:\/loki/);
  assert.match(compose, /test: \["CMD", "loki", "-config\.file=\/etc\/loki\/loki\.yml", "-verify-config"\]/);

  assert.match(lokiConfig, /auth_enabled: false/);
  assert.match(lokiConfig, /http_listen_port: 3100/);
  assert.match(lokiConfig, /path_prefix: \/loki/);
  assert.match(lokiConfig, /chunks_directory: \/loki\/chunks/);
  assert.match(lokiConfig, /rules_directory: \/loki\/rules/);
  assert.match(lokiConfig, /store: tsdb/);
  assert.match(lokiConfig, /object_store: filesystem/);

  assert.match(lokiDatasource, /name: easysubway-loki/);
  assert.match(lokiDatasource, /type: loki/);
  assert.match(lokiDatasource, /url: http:\/\/loki:3100/);
  assert.match(lokiDatasource, /isDefault: false/);
  assert.match(prometheusDatasource, /isDefault: true/);
});

test("백엔드 스캐폴드는 eGovFrame 5.0 Spring Boot Java 21 헥사고날 프로젝트다", () => {
  const build = read("backend/build.gradle");
  const wrapper = read("backend/gradle/wrapper/gradle-wrapper.properties");
  const application = read("backend/src/main/java/com/easysubway/EasySubwayBackendApplication.java");
  const domain = read("backend/src/main/java/com/easysubway/health/domain/HealthStatus.java");
  const port = read("backend/src/main/java/com/easysubway/health/application/port/in/CheckHealthUseCase.java");
  const service = read("backend/src/main/java/com/easysubway/health/application/service/HealthCheckService.java");
  const controller = read("backend/src/main/java/com/easysubway/health/adapter/in/web/HealthCheckController.java");
  const apiResponse = read("backend/src/main/java/com/easysubway/common/web/ApiResponse.java");
  const applicationYml = read("backend/src/main/resources/application.yml");
  const applicationDevYml = read("backend/src/main/resources/application-dev.yml");
  const applicationProdYml = read("backend/src/main/resources/application-prod.yml");

  assert.ok(existsSync(path.join(root, "backend/gradlew")));
  assert.ok(existsSync(path.join(root, "backend/gradle/wrapper/gradle-wrapper.jar")));
  assert.match(wrapper, /gradle-8\.14\.5-bin\.zip/);

  assert.match(build, /id 'org\.springframework\.boot' version '3\.5\.(?:1[5-9]|[2-9][0-9]|[1-9][0-9]{2,})'/);
  assert.match(build, /languageVersion = JavaLanguageVersion\.of\(21\)/);
  assert.match(build, /https:\/\/maven\.egovframe\.go\.kr\/maven/);
  assert.match(build, /mavenBom 'org\.egovframe\.boot:egovframe-boot-starter-parent:5\.0\.0'/);
  assert.match(build, /implementation 'org\.egovframe\.rte:egovframe-rte-ptl-mvc'/);
  assert.match(build, /implementation 'org\.springframework\.boot:spring-boot-starter-web'/);
  assert.match(build, /implementation 'org\.springframework\.boot:spring-boot-starter-security'/);
  assert.match(build, /implementation 'org\.springframework\.boot:spring-boot-starter-actuator'/);
  assert.match(build, /testImplementation 'org\.springframework\.boot:spring-boot-starter-test'/);
  assert.match(build, /testImplementation 'org\.springframework\.security:spring-security-test'/);

  assert.match(application, /@SpringBootApplication/);
  assert.match(domain, /record HealthStatus/);
  assert.match(port, /interface CheckHealthUseCase/);
  assert.match(service, /implements CheckHealthUseCase/);
  assert.match(service, /easysubway-backend/);
  assert.match(controller, /@GetMapping\("\/api\/health"\)/);
  assert.match(controller, /CheckHealthUseCase/);
  assert.match(apiResponse, /record ApiResponse/);
  assert.equal(existsSync(path.join(root, "backend/src/main/resources/application.properties")), false);
  assert.match(applicationYml, /spring:\s*\n\s*application:\s*\n\s*name:\s*["']?easysubway-backend["']?/);
  assert.match(applicationYml, /profiles:\s*\n\s*default:\s*["']?dev["']?/);
  assert.match(applicationYml, /management:\s*\n\s*endpoints:\s*\n\s*web:\s*\n\s*exposure:\s*\n\s*include:\s*["']?health\s*,\s*info["']?/);
  assert.match(applicationDevYml, /logging:\s*\n\s*level:\s*\n\s*com\.easysubway:\s*["']?DEBUG["']?/);
  assert.match(applicationDevYml, /datasource:[\s\S]*jdbc:h2:mem:easysubway/);
  assert.doesNotMatch(applicationYml, /driver-class-name: org\.h2\.Driver/);
  assert.match(applicationProdYml, /logging:\s*\n\s*level:\s*\n\s*com\.easysubway:\s*["']?INFO["']?/);
  assert.doesNotMatch(applicationDevYml, /spring\.profiles\.active|on-profile/);
  assert.doesNotMatch(applicationProdYml, /spring\.profiles\.active|on-profile/);
});

test("eGovFrame pagination import는 common web pagination 경계에만 둔다", () => {
  const javaFiles = execFileSync("git", [
    "ls-files",
    "--cached",
    "--others",
    "--exclude-standard",
    "backend/src/main/java",
    "backend/src/test/java",
  ], {
    cwd: root,
    encoding: "utf8",
  }).trim().split("\n").filter(Boolean);
  const egovFrameFiles = javaFiles
    .filter((file) => read(file).includes("org.egovframe"))
    .sort();

  assert.deepEqual(egovFrameFiles, [
    "backend/src/main/java/com/easysubway/common/web/pagination/EgovPaginationView.java",
    "backend/src/test/java/com/easysubway/support/EgovFrameRuntimeTest.java",
  ]);
});

test("백엔드 web message source는 기본 한국어 bundle과 code 기반 validation을 사용한다", () => {
  const applicationYml = read("backend/src/main/resources/application.yml");
  const messages = read("backend/src/main/resources/messages.properties");
  const resolver = read("backend/src/main/java/com/easysubway/common/web/WebMessageResolver.java");
  const exceptionHandler = read("backend/src/main/java/com/easysubway/common/web/CommonExceptionHandler.java");
  const dataCollectionController = read(
    "backend/src/main/java/com/easysubway/collection/adapter/in/web/DataCollectionController.java",
  );
  const notificationController = read(
    "backend/src/main/java/com/easysubway/notification/adapter/in/web/PushNotificationController.java",
  );
  const transitController = read(
    "backend/src/main/java/com/easysubway/transit/adapter/in/web/TransitMasterController.java",
  );
  const fieldVerificationController = read(
    "backend/src/main/java/com/easysubway/field/adapter/in/web/FieldVerificationAdminController.java",
  );
  const reportAdminController = read(
    "backend/src/main/java/com/easysubway/report/adapter/in/web/FacilityReportAdminPageController.java",
  );
  const qualityAdminController = read(
    "backend/src/main/java/com/easysubway/quality/adapter/in/web/DataQualityAdminPageController.java",
  );
  const resolverTest = read("backend/src/test/java/com/easysubway/common/web/WebMessageResolverTest.java");

  assert.match(applicationYml, /messages:\s*\n\s*fallback-to-system-locale:\s*false/);
  assert.doesNotMatch(applicationYml, /use-code-as-default-message:\s*true/);
  assert.match(messages, /^common\.error\.unreadable-body=요청 본문을 확인해야 합니다\.$/m);
  assert.match(messages, /^common\.error\.invalid-body=요청 값을 확인해야 합니다\.$/m);
  assert.match(messages, /^validation\.collection\.source\.required=수집 대상을 선택해야 합니다\.$/m);
  assert.match(messages, /^validation\.notification\.user-id\.required=사용자 식별자가 필요합니다\.$/m);
  assert.match(messages, /^validation\.notification\.type\.required=알림 종류를 선택해야 합니다\.$/m);
  assert.match(messages, /^validation\.notification\.title\.required=알림 제목이 필요합니다\.$/m);
  assert.match(messages, /^validation\.notification\.body\.required=알림 본문이 필요합니다\.$/m);
  assert.match(messages, /^validation\.transit\.facility-status\.required=시설 상태를 선택해야 합니다\.$/m);
  assert.match(messages, /^validation\.transit\.layout-status\.required=구조도 상태를 선택해야 합니다\.$/m);
  assert.match(messages, /^validation\.transit\.route-node-display-coordinate\.required=노드 표시 좌표가 필요합니다\.$/m);
  assert.match(messages, /^validation\.field-verification\.status\.required=현장 검증 상태를 선택해야 합니다\.$/m);
  assert.match(messages, /^admin\.report\.status\.SUBMITTED=접수됨$/m);
  assert.match(messages, /^admin\.report\.type\.BROKEN=고장$/m);
  assert.match(messages, /^admin\.report\.review-decision\.ACCEPT=승인$/m);
  assert.match(messages, /^admin\.facility\.status\.NORMAL=정상$/m);
  assert.match(resolver, /class WebMessageResolver/);
  assert.match(resolver, /setFallbackToSystemLocale\(false\)/);
  assert.match(exceptionHandler, /WebMessageResolver/);
  assert.match(exceptionHandler, /common\.error\.unreadable-body/);
  assert.match(exceptionHandler, /common\.error\.invalid-body/);
  assert.match(exceptionHandler, /common\.error\.invalid-parameter/);
  assert.match(dataCollectionController, /@NotNull\(message = "\{validation\.collection\.source\.required\}"\)/);
  assert.match(notificationController, /@Valid @RequestBody PushNotificationDispatchRequest request/);
  assert.match(notificationController, /@Valid @RequestBody PushNotificationDeliveryRequest request/);
  assert.match(notificationController, /@NotBlank\(message = "\{validation\.notification\.user-id\.required\}"\)/);
  assert.match(notificationController, /@NotNull\(message = "\{validation\.notification\.type\.required\}"\)/);
  assert.match(notificationController, /@NotBlank\(message = "\{validation\.notification\.title\.required\}"\)/);
  assert.match(notificationController, /@NotBlank\(message = "\{validation\.notification\.body\.required\}"\)/);
  assert.match(transitController, /@Valid @RequestBody UpdateAccessibilityFacilityStatusRequest request/);
  assert.match(transitController, /@Valid @RequestBody UpdateSimplifiedStationLayoutStatusRequest request/);
  assert.match(transitController, /@Valid @RequestBody UpdateRouteNodeDisplayRequest request/);
  assert.match(transitController, /@NotNull\(message = "\{validation\.transit\.facility-status\.required\}"\)/);
  assert.match(transitController, /@NotNull\(message = "\{validation\.transit\.layout-status\.required\}"\)/);
  assert.match(transitController, /@NotNull\(message = "\{validation\.transit\.route-node-display-coordinate\.required\}"\)/);
  assert.match(fieldVerificationController, /@Valid @RequestBody UpdateFieldVerificationItemStatusRequest request/);
  assert.match(fieldVerificationController, /@NotNull\(message = "\{validation\.field-verification\.status\.required\}"\)/);
  assert.match(reportAdminController, /messages\.enumLabel\("admin\.report\.status"/);
  assert.match(reportAdminController, /messages\.enumLabel\("admin\.report\.type"/);
  assert.match(reportAdminController, /messages\.enumLabel\("admin\.report\.review-decision"/);
  assert.match(qualityAdminController, /messages\.enumLabel\("admin\.facility\.status"/);
  assert.match(qualityAdminController, /messages\.enumLabel\("admin\.report\.status"/);
  assert.match(resolverTest, /missing\.backend\.message\.key/);
  assert.match(resolverTest, /Locale\.JAPAN/);
});

test("백엔드 품질 gate feasibility는 정적 분석 도입 조건을 계약으로 고정한다", () => {
  const gatePath = "backend/quality/static-analysis-gate.json";

  assert.equal(existsSync(path.join(root, gatePath)), true, "backend static analysis gate must exist");

  const gate = readJson(gatePath);
  const build = read("backend/build.gradle");
  const ci = read(".github/workflows/ci.yml");
  const readme = read("README.md");

  assert.equal(gate.schemaVersion, 1);
  assert.equal(gate.gateId, "backend-static-analysis-feasibility");
  assert.equal(gate.defaultPolicy, "contract-only-before-enforcement");
  assert.equal(gate.enforcementStatus, "deferred_until_p0_release_contracts_stabilize");
  assert.equal(gate.ciRuntimeBudgetMinutes.maxAdditionalMinutes, 3);
  assert.equal(gate.ciRuntimeBudgetMinutes.measurementRequiredBeforeEnforcement, true);

  const tools = new Map(gate.tools.map((tool) => [tool.id, tool]));
  for (const id of ["checkstyle", "spotbugs", "errorprone", "archunit", "jacoco"]) {
    const tool = tools.get(id);
    assert.ok(tool, `${id} must be listed in backend static analysis gate`);
    assert.equal(tool.enforcement, "not_enabled_in_this_slice");
    assert.ok(tool.requires.length > 0, `${id} must declare enforcement prerequisites`);
  }

  assert.equal(tools.get("archunit").firstAllowedGate, "public_mobile_api_absence");
  assert.equal(tools.get("jacoco").firstAllowedGate, "coverage_baseline_after_p0_tests_stabilize");
  assert.ok(gate.mustNotDo.includes("enable_style_or_coverage_plugins_without_runtime_budget_evidence"));
  assert.ok(gate.mustNotDo.includes("reformat_unrelated_backend_sources"));
  assert.ok(gate.mustNotDo.includes("weaken_security_route_or_release_contract_tests"));

  assert.match(ci, /Repository CI \/ Run contract tests/);
  assert.doesNotMatch(build, /id ['"]checkstyle['"]/);
  assert.doesNotMatch(build, /id ['"]com\.github\.spotbugs['"]/);
  assert.doesNotMatch(build, /id ['"]net\.ltgt\.errorprone['"]/);
  assert.doesNotMatch(build, /id ['"]jacoco['"]/);
  assert.doesNotMatch(build, /com\.tngtech\.archunit/);

  assert.match(readme, /backend static analysis feasibility gate/);
  assert.match(readme, /Checkstyle/);
  assert.match(readme, /SpotBugs/);
  assert.match(readme, /ArchUnit/);
  assert.match(readme, /JaCoCo/);
});

test("MVP 기본 경로는 익명 계정과 bearer token 인증을 발급하지 않는다", () => {
  const removedPaths = [
    "apps/mobile/lib/anonymous_auth.dart",
    "apps/mobile/test/anonymous_auth_test.dart",
    "backend/src/main/java/com/easysubway/auth/adapter/in/web/AnonymousAuthController.java",
    "backend/src/main/java/com/easysubway/auth/adapter/out/persistence/JdbcAnonymousAuthRepository.java",
    "backend/src/main/java/com/easysubway/auth/adapter/out/security/AnonymousBearerAuthenticationFilter.java",
    "backend/src/main/java/com/easysubway/auth/domain/AnonymousAuthTokenSession.java",
  ];

  for (const removedPath of removedPaths) {
    assert.equal(
      existsSync(path.join(root, removedPath)),
      false,
      `${removedPath} must be removed from the MVP release path`,
    );
  }

  const main = read("apps/mobile/lib/main.dart");
  const appBootstrap = read("apps/mobile/lib/app/app_bootstrap.dart");
  const appDependencies = read("apps/mobile/lib/app/app_dependencies.dart");
  const facilityReport = read("apps/mobile/lib/facility_report.dart");
  const legacyCredentialCleanup = read("apps/mobile/lib/legacy_credential_cleanup.dart");
  const security = read("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java");
  const postgresBaseline = read("backend/src/main/resources/db/migration/postgresql/V1__baseline_schema.sql");
  const h2Baseline = read("backend/src/main/resources/db/migration/h2/V1__baseline_schema.sql");
  const postgresAnonymousAuthDrop = read(
    "backend/src/main/resources/db/migration/postgresql/V5__drop_anonymous_auth_tables.sql",
  );
  const h2AnonymousAuthDrop = read(
    "backend/src/main/resources/db/migration/h2/V5__drop_anonymous_auth_tables.sql",
  );

  assert.doesNotMatch(`${main}\n${appBootstrap}\n${appDependencies}`, /AnonymousAuth|enableAnonymousAuth|anonymousAuth/);
  assert.doesNotMatch(facilityReport, /anonymous-mobile-user|anonymousReportUserId/);
  assert.doesNotMatch(security, /AnonymousBearerAuthenticationFilter/);
  assert.match(postgresBaseline, /guest_accounts|anonymous_auth_tokens|anonymous_auth_audit_events/);
  assert.match(h2Baseline, /guest_accounts|anonymous_auth_tokens|anonymous_auth_audit_events/);
  assert.match(
    postgresAnonymousAuthDrop,
    /UPDATE route_feedbacks[\s\S]*UPDATE facility_reports[\s\S]*DELETE FROM user_activity_events[\s\S]*DELETE FROM push_notification_outbox[\s\S]*DELETE FROM registered_devices[\s\S]*DELETE FROM notification_settings[\s\S]*DELETE FROM mobility_profiles[\s\S]*DELETE FROM favorite_route_stations[\s\S]*DELETE FROM favorite_routes[\s\S]*DELETE FROM favorite_facilities[\s\S]*DELETE FROM favorite_stations[\s\S]*DROP TABLE IF EXISTS anonymous_auth_audit_events;[\s\S]*DROP TABLE IF EXISTS anonymous_auth_tokens;[\s\S]*DROP TABLE IF EXISTS guest_accounts;/,
  );
  assert.match(
    h2AnonymousAuthDrop,
    /UPDATE route_feedbacks[\s\S]*UPDATE facility_reports[\s\S]*DELETE FROM user_activity_events[\s\S]*DELETE FROM push_notification_outbox[\s\S]*DELETE FROM registered_devices[\s\S]*DELETE FROM notification_settings[\s\S]*DELETE FROM mobility_profiles[\s\S]*DELETE FROM favorite_route_stations[\s\S]*DELETE FROM favorite_routes[\s\S]*DELETE FROM favorite_facilities[\s\S]*DELETE FROM favorite_stations[\s\S]*DROP TABLE IF EXISTS anonymous_auth_audit_events;[\s\S]*DROP TABLE IF EXISTS anonymous_auth_tokens;[\s\S]*DROP TABLE IF EXISTS guest_accounts;/,
  );
  assert.match(legacyCredentialCleanup, /easysubway\.anonymousAuth\.credentials/);
});

test("백엔드는 모바일 기본 경로용 public transit, route, me API를 노출하지 않는다", () => {
  const removedControllerPaths = [
    "backend/src/main/java/com/easysubway/favorite/adapter/in/web/FavoriteFacilityController.java",
    "backend/src/main/java/com/easysubway/favorite/adapter/in/web/FavoriteRouteController.java",
    "backend/src/main/java/com/easysubway/favorite/adapter/in/web/FavoriteStationController.java",
    "backend/src/main/java/com/easysubway/notification/adapter/in/web/NotificationPreferenceController.java",
    "backend/src/main/java/com/easysubway/profile/adapter/in/web/MobilityProfileController.java",
    "backend/src/main/java/com/easysubway/route/adapter/in/web/RouteSearchController.java",
    "backend/src/main/java/com/easysubway/user/adapter/in/web/UserDataController.java",
  ];
  const javaFiles = execFileSync("git", ["ls-files", "backend/src/main/java/**/*.java"], {
    cwd: root,
    encoding: "utf8",
  }).trim().split("\n").filter(Boolean);
  const backendSources = javaFiles.map(read).join("\n");

  for (const removedPath of removedControllerPaths) {
    assert.equal(existsSync(path.join(root, removedPath)), false, `${removedPath} must not expose mobile-local APIs`);
  }

  assert.doesNotMatch(backendSources, /@(?:Get|Post|Put|Patch|Delete)Mapping\("\/api\/v1\/stations(?:\/|\")/);
  assert.doesNotMatch(backendSources, /@(?:Get|Post|Put|Patch|Delete)Mapping\("\/api\/v1\/routes(?:\/|\")/);
  assert.doesNotMatch(backendSources, /@(?:Get|Post|Put|Patch|Delete)Mapping\("\/api\/v1\/me(?:\/|\")/);
  assert.doesNotMatch(backendSources, /@(?:Get|Post|Put|Patch|Delete)Mapping\("\/api\/v1\/devices(?:\/|\")/);
  assert.match(backendSources, /@(?:Get|Post|Put|Patch|Delete)Mapping\("\/api\/v1\/reports(?:\/|\")/);
  assert.match(backendSources, /@(?:Get|Post|Put|Patch|Delete)Mapping\("\/admin\//);
});

test("백엔드 운영 프로필은 인메모리 bean을 제외하고 임시 master seed fallback을 명시한다", () => {
  const files = inMemoryRepositoryFiles();
  const readinessConfiguration = read(
    "backend/src/main/java/com/easysubway/common/persistence/ProductionPersistenceReadinessConfiguration.java",
  );
  const unavailableTransitMaster = read(
    "backend/src/main/java/com/easysubway/transit/adapter/out/persistence/UnavailableTransitMasterRepository.java",
  );
  const applicationYml = read("backend/src/main/resources/application.yml");
  const applicationProdYml = read("backend/src/main/resources/application-prod.yml");

  assert.ok(files.length >= 1, "InMemory repository files must be discovered");
  for (const file of files) {
    const source = read(file);
    assert.match(source, /import org\.springframework\.context\.annotation\.Profile;/, `${file} must import Profile`);
    assert.match(source, /@Repository\s+@Profile\("!prod"\)/, `${file} must be disabled on prod profile`);
  }
  assert.match(readinessConfiguration, /@Profile\("prod"\)/);
  assert.match(readinessConfiguration, /HealthIndicator/);
  assert.match(readinessConfiguration, /Status\.DOWN/);
  assert.match(readinessConfiguration, /productionReadinessHealthIndicator/);
  assert.doesNotMatch(readinessConfiguration, /BeanFactoryPostProcessor/);
  assert.doesNotMatch(readinessConfiguration, /BeanCreationException/);
  assert.doesNotMatch(readinessConfiguration, /운영 영속 저장소 구현이 필요합니다\./);
  assert.match(unavailableTransitMaster, /@Profile\("prod"\)/);
  assert.match(unavailableTransitMaster, /implements[\s\S]*LoadTransitMasterPort/);
  assert.match(
    unavailableTransitMaster,
    /private final InMemoryTransitMasterRepository seedRepository = new InMemoryTransitMasterRepository\(\);/,
  );
  assert.match(
    unavailableTransitMaster,
    /public List<TransitOperator> loadOperators\(\) \{\s*return seedRepository\.loadOperators\(\);/,
  );
  assert.match(
    unavailableTransitMaster,
    /public List<SubwayLine> loadLines\(\) \{\s*return seedRepository\.loadLines\(\);/,
  );
  assert.match(
    unavailableTransitMaster,
    /public List<Station> loadStations\(\) \{\s*return seedRepository\.loadStations\(\);/,
  );
  assert.match(unavailableTransitMaster, /UnsupportedOperationException/);
  assert.match(unavailableTransitMaster, /saveFacilityStatus[\s\S]*unsupportedWriteOperation\("saveFacilityStatus"\)/);
  assert.match(
    unavailableTransitMaster,
    /saveAccessibilityFacility[\s\S]*unsupportedWriteOperation\("saveAccessibilityFacility"\)/,
  );
  assert.match(unavailableTransitMaster, /saveStationLayoutSource[\s\S]*unsupportedWriteOperation\("saveStationLayoutSource"\)/);
  assert.match(
    unavailableTransitMaster,
    /saveSimplifiedStationLayoutStatus[\s\S]*unsupportedWriteOperation\("saveSimplifiedStationLayoutStatus"\)/,
  );
  assert.match(unavailableTransitMaster, /saveRouteNode[\s\S]*unsupportedWriteOperation\("saveRouteNode"\)/);
  assert.match(unavailableTransitMaster, /saveRouteEdge[\s\S]*unsupportedWriteOperation\("saveRouteEdge"\)/);
  for (const file of prodJdbcRepositoryFiles()) {
    const source = read(file);
    if (/JdbcTemplate jdbcTemplate/.test(source) && /public Jdbc[A-Za-z0-9]+Repository\(DataSource/.test(source)) {
      assert.match(source, /@Autowired\s+public Jdbc[A-Za-z0-9]+Repository\(/, `${file} must mark its Spring constructor`);
    }
  }
  assert.match(applicationYml, /management:[\s\S]*endpoint:\s*\n\s*health:\s*\n\s*probes:\s*\n\s*enabled:\s*true/);
  assert.doesNotMatch(applicationYml, /productionReadiness/);
  assert.match(applicationProdYml, /readiness:\s*\n\s*include:\s*["']?readinessState\s*,\s*db\s*,\s*productionReadiness["']?/);
  assert.doesNotMatch(applicationProdYml, /redis/);
  assert.doesNotMatch(readinessConfiguration, /RedisConnectionFactory|RedisConnection|redisReady/);
  assert.doesNotMatch(readinessConfiguration, /pushExternalEnabled|pushReady/);
  assert.match(applicationProdYml, /external-enabled: \$\{EASYSUBWAY_PUSH_EXTERNAL_ENABLED:false\}/);
});

test("백엔드 사용자 데이터 삭제는 헥사고날 API 경계를 따른다", () => {
  const result = read("backend/src/main/java/com/easysubway/user/domain/UserDataDeletionResult.java");
  const invalidDeletion = read("backend/src/main/java/com/easysubway/user/domain/InvalidUserDataDeletionException.java");
  const useCase = read("backend/src/main/java/com/easysubway/user/application/port/in/UserDataDeletionUseCase.java");
  const favoriteStationPort = read(
    "backend/src/main/java/com/easysubway/user/application/port/out/DeleteUserFavoriteStationPort.java",
  );
  const favoriteFacilityPort = read(
    "backend/src/main/java/com/easysubway/user/application/port/out/DeleteUserFavoriteFacilityPort.java",
  );
  const favoriteRoutePort = read(
    "backend/src/main/java/com/easysubway/user/application/port/out/DeleteUserFavoriteRoutePort.java",
  );
  const routeFeedbackPort = read(
    "backend/src/main/java/com/easysubway/user/application/port/out/AnonymizeUserRouteFeedbackPort.java",
  );
  const notificationPort = read(
    "backend/src/main/java/com/easysubway/user/application/port/out/DeleteUserNotificationPreferencePort.java",
  );
  const pushNotificationPort = read(
    "backend/src/main/java/com/easysubway/user/application/port/out/DeleteUserPushNotificationPort.java",
  );
  const mobilityProfilePort = read(
    "backend/src/main/java/com/easysubway/user/application/port/out/DeleteUserMobilityProfilePort.java",
  );
  const reportPort = read(
    "backend/src/main/java/com/easysubway/user/application/port/out/AnonymizeUserFacilityReportPort.java",
  );
  const service = read("backend/src/main/java/com/easysubway/user/application/service/UserDataDeletionService.java");
  const userDataControllerPath = "backend/src/main/java/com/easysubway/user/adapter/in/web/UserDataController.java";
  const favoriteStationRepository = read(
    "backend/src/main/java/com/easysubway/favorite/adapter/out/persistence/InMemoryFavoriteStationRepository.java",
  );
  const favoriteFacilityRepository = read(
    "backend/src/main/java/com/easysubway/favorite/adapter/out/persistence/InMemoryFavoriteFacilityRepository.java",
  );
  const favoriteRouteRepository = read(
    "backend/src/main/java/com/easysubway/favorite/adapter/out/persistence/InMemoryFavoriteRouteRepository.java",
  );
  const routeSearchRepository = read(
    "backend/src/main/java/com/easysubway/route/adapter/out/persistence/InMemoryRouteSearchRepository.java",
  );
  const jdbcRouteSearchRepository = read(
    "backend/src/main/java/com/easysubway/route/adapter/out/persistence/JdbcRouteSearchRepository.java",
  );
  const notificationRepository = read(
    "backend/src/main/java/com/easysubway/notification/adapter/out/persistence/InMemoryNotificationPreferenceRepository.java",
  );
  const pushNotificationRepository = read(
    "backend/src/main/java/com/easysubway/notification/adapter/out/persistence/InMemoryPushNotificationOutboxRepository.java",
  );
  const profileRepository = read(
    "backend/src/main/java/com/easysubway/profile/adapter/out/persistence/InMemoryMobilityProfileRepository.java",
  );
  const reportRepository = read(
    "backend/src/main/java/com/easysubway/report/adapter/out/persistence/InMemoryFacilityReportRepository.java",
  );
  const facilityReport = read("backend/src/main/java/com/easysubway/report/domain/FacilityReport.java");
  const reportService = read("backend/src/main/java/com/easysubway/report/application/service/FacilityReportService.java");
  const security = read("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java");

  assert.match(result, /record UserDataDeletionResult/);
  assert.match(result, /deletedFavoriteStationCount/);
  assert.match(result, /deletedFavoriteFacilityCount/);
  assert.match(result, /deletedFavoriteRouteCount/);
  assert.match(result, /anonymizedRouteFeedbackCount/);
  assert.match(result, /notificationSettingsDeleted/);
  assert.match(result, /deletedRegisteredDeviceCount/);
  assert.match(result, /deletedPushNotificationCount/);
  assert.match(result, /mobilityProfileDeleted/);
  assert.match(result, /anonymizedReportCount/);
  assert.doesNotMatch(result, /anonymousCredentialsDeleted/);
  assert.match(invalidDeletion, /extends RuntimeException/);
  assert.match(useCase, /interface UserDataDeletionUseCase/);
  assert.match(useCase, /deleteUserData\(String userId\)/);
  assert.match(favoriteStationPort, /deleteFavoriteStationsByUserId/);
  assert.match(favoriteFacilityPort, /deleteFavoriteFacilitiesByUserId/);
  assert.match(favoriteRoutePort, /deleteFavoriteRoutesByUserId/);
  assert.match(routeFeedbackPort, /anonymizeRouteFeedbacksByUserId/);
  assert.match(notificationPort, /deleteNotificationSettings/);
  assert.match(notificationPort, /deleteRegisteredDevices/);
  assert.match(pushNotificationPort, /deletePushNotifications/);
  assert.match(mobilityProfilePort, /deleteMobilityProfile/);
  assert.match(reportPort, /anonymizeFacilityReportsByUserId/);
  assert.match(service, /implements UserDataDeletionUseCase/);
  assert.doesNotMatch(service, /RegisterAnonymousUserPort|deleteAnonymousUser/);
  assert.match(service, /DeleteUserFavoriteStationPort/);
  assert.match(service, /DeleteUserFavoriteFacilityPort/);
  assert.match(service, /DeleteUserFavoriteRoutePort/);
  assert.match(service, /AnonymizeUserRouteFeedbackPort/);
  assert.match(service, /DeleteUserNotificationPreferencePort/);
  assert.match(service, /DeleteUserPushNotificationPort/);
  assert.match(service, /DeleteUserMobilityProfilePort/);
  assert.match(service, /AnonymizeUserFacilityReportPort/);
  assert.equal(existsSync(path.join(root, userDataControllerPath)), false);
  assert.match(favoriteStationRepository, /DeleteUserFavoriteStationPort/);
  assert.match(favoriteFacilityRepository, /DeleteUserFavoriteFacilityPort/);
  assert.match(favoriteRouteRepository, /DeleteUserFavoriteRoutePort/);
  assert.match(routeSearchRepository, /AnonymizeUserRouteFeedbackPort/);
  assert.match(routeSearchRepository, /DELETED_USER_ID = "deleted-user"/);
  assert.match(routeSearchRepository, /DELETED_COMMENT = "사용자 데이터 삭제로 경로 피드백 내용이 삭제되었습니다\."/);
  assert.match(jdbcRouteSearchRepository, /AnonymizeUserRouteFeedbackPort/);
  assert.match(jdbcRouteSearchRepository, /UPDATE route_feedbacks/);
  assert.match(jdbcRouteSearchRepository, /DELETED_USER_ID = "deleted-user"/);
  assert.match(jdbcRouteSearchRepository, /DELETED_COMMENT = "사용자 데이터 삭제로 경로 피드백 내용이 삭제되었습니다\."/);
  assert.match(notificationRepository, /DeleteUserNotificationPreferencePort/);
  assert.match(pushNotificationRepository, /DeleteUserPushNotificationPort/);
  assert.match(profileRepository, /DeleteUserMobilityProfilePort/);
  assert.match(reportRepository, /AnonymizeUserFacilityReportPort/);
  assert.match(facilityReport, /ANONYMIZED_USER_ID = "__easysubway_deleted_facility_report__"/);
  assert.match(facilityReport, /boolean isAnonymizedUserData\(\)/);
  assert.match(reportRepository, /FacilityReport\.ANONYMIZED_USER_ID/);
  assert.match(reportRepository, /DELETED_DESCRIPTION = "사용자 데이터 삭제로 신고 내용이 삭제되었습니다\."/);
  assert.match(reportRepository, /null,\s*\n\s*null,\s*\n\s*null,\s*\n\s*null,\s*\n\s*null,/);
  assert.match(reportService, /!report\.isAnonymizedUserData\(\)/);
  assert.doesNotMatch(security, /"\/api\/v1\/me"/);
});

test("백엔드 도시철도 마스터데이터는 헥사고날 API 경계를 따른다", () => {
  const operator = read("backend/src/main/java/com/easysubway/transit/domain/TransitOperator.java");
  const line = read("backend/src/main/java/com/easysubway/transit/domain/SubwayLine.java");
  const station = read("backend/src/main/java/com/easysubway/transit/domain/Station.java");
  const stationExit = read("backend/src/main/java/com/easysubway/transit/domain/StationExit.java");
  const facility = read("backend/src/main/java/com/easysubway/transit/domain/AccessibilityFacility.java");
  const quality = read("backend/src/main/java/com/easysubway/transit/domain/DataQualityLevel.java");
  const confidence = read("backend/src/main/java/com/easysubway/transit/domain/DataConfidenceLevel.java");
  const facilityType = read("backend/src/main/java/com/easysubway/transit/domain/AccessibilityFacilityType.java");
  const facilityStatus = read("backend/src/main/java/com/easysubway/transit/domain/AccessibilityFacilityStatus.java");
  const facilityNotFound = read("backend/src/main/java/com/easysubway/transit/domain/AccessibilityFacilityNotFoundException.java");
  const invalidFacility = read("backend/src/main/java/com/easysubway/transit/domain/InvalidAccessibilityFacilityException.java");
  const source = read("backend/src/main/java/com/easysubway/transit/domain/DataSourceType.java");
  const useCase = read("backend/src/main/java/com/easysubway/transit/application/port/in/TransitMasterQueryUseCase.java");
  const stationMasterDataCounts = read(
    "backend/src/main/java/com/easysubway/transit/application/port/in/StationMasterDataCounts.java",
  );
  const adminUseCase = read("backend/src/main/java/com/easysubway/transit/application/port/in/TransitMasterAdminUseCase.java");
  const createFacilityCommand = read(
    "backend/src/main/java/com/easysubway/transit/application/port/in/CreateAccessibilityFacilityCommand.java",
  );
  const updateFacilityCommand = read(
    "backend/src/main/java/com/easysubway/transit/application/port/in/UpdateAccessibilityFacilityCommand.java",
  );
  const updateStatusCommand = read(
    "backend/src/main/java/com/easysubway/transit/application/port/in/UpdateAccessibilityFacilityStatusCommand.java",
  );
  const updateRouteNodeDisplayCommand = read(
    "backend/src/main/java/com/easysubway/transit/application/port/in/UpdateRouteNodeDisplayCommand.java",
  );
  const updateLayoutStatusCommand = read(
    "backend/src/main/java/com/easysubway/transit/application/port/in/UpdateSimplifiedStationLayoutStatusCommand.java",
  );
  const outboundPort = read("backend/src/main/java/com/easysubway/transit/application/port/out/LoadTransitMasterPort.java");
  const saveFacilityStatusPort = read(
    "backend/src/main/java/com/easysubway/transit/application/port/out/SaveAccessibilityFacilityStatusPort.java",
  );
  const saveLayoutStatusPort = read(
    "backend/src/main/java/com/easysubway/transit/application/port/out/SaveSimplifiedStationLayoutStatusPort.java",
  );
  const saveRouteNodePort = read(
    "backend/src/main/java/com/easysubway/transit/application/port/out/SaveRouteNodePort.java",
  );
  const service = read("backend/src/main/java/com/easysubway/transit/application/service/TransitMasterService.java");
  const repository = read("backend/src/main/java/com/easysubway/transit/adapter/out/persistence/InMemoryTransitMasterRepository.java");
  const controller = read("backend/src/main/java/com/easysubway/transit/adapter/in/web/TransitMasterController.java");
  const facilityAdminPageController = read(
    "backend/src/main/java/com/easysubway/transit/adapter/in/web/TransitFacilityAdminPageController.java",
  );
  const stationLayoutAdminPageController = read(
    "backend/src/main/java/com/easysubway/transit/adapter/in/web/TransitStationLayoutAdminPageController.java",
  );
  const facilityAdminApiController = read(
    "backend/src/main/java/com/easysubway/transit/adapter/in/web/TransitFacilityAdminApiController.java",
  );
  const facilityStatusAssembler = read(
    "backend/src/main/java/com/easysubway/transit/adapter/in/web/TransitFacilityStatusAssembler.java",
  );
  const facilityStatusRow = read(
    "backend/src/main/java/com/easysubway/transit/adapter/in/web/FacilityStatusRow.java",
  );
  const stationLayoutAdminTemplate = read("backend/src/main/resources/templates/admin/stations/layouts.html");
  const exceptionHandler = read("backend/src/main/java/com/easysubway/common/web/CommonExceptionHandler.java");

  assert.match(operator, /record TransitOperator/);
  assert.match(line, /record SubwayLine/);
  assert.match(station, /record Station/);
  assert.match(stationExit, /record StationExit/);
  assert.match(stationExit, /hasElevatorConnection/);
  assert.match(facility, /record AccessibilityFacility/);
  assert.match(facility, /lastUpdatedAt/);
  assert.match(quality, /LEVEL_1/);
  assert.match(confidence, /HIGH/);
  assert.match(facilityType, /ELEVATOR/);
  assert.match(facilityStatus, /UNDER_CONSTRUCTION/);
  assert.match(facilityNotFound, /extends ResourceNotFoundException/);
  assert.match(invalidFacility, /extends InvalidRequestException/);
  assert.match(source, /OFFICIAL_FILE/);
  assert.match(useCase, /interface TransitMasterQueryUseCase/);
  assert.match(useCase, /countStationMasterDataByStationId/);
  assert.match(useCase, /listStationExits/);
  assert.match(useCase, /listStationFacilities/);
  assert.match(stationMasterDataCounts, /record StationMasterDataCounts/);
  assert.match(stationMasterDataCounts, /int routeEdgeCount/);
  assert.match(adminUseCase, /interface TransitMasterAdminUseCase/);
  assert.match(adminUseCase, /createAccessibilityFacility/);
  assert.match(adminUseCase, /updateAccessibilityFacility/);
  assert.match(adminUseCase, /updateFacilityStatus/);
  assert.match(createFacilityCommand, /record CreateAccessibilityFacilityCommand/);
  assert.match(createFacilityCommand, /AccessibilityFacilityType type/);
  assert.match(createFacilityCommand, /DataConfidenceLevel dataConfidence/);
  assert.match(updateFacilityCommand, /record UpdateAccessibilityFacilityCommand/);
  assert.match(updateFacilityCommand, /DataSourceType dataSourceType/);
  assert.match(updateStatusCommand, /record UpdateAccessibilityFacilityStatusCommand/);
  assert.match(updateStatusCommand, /AccessibilityFacilityStatus status/);
  assert.match(updateStatusCommand, /String updatedBy/);
  assert.match(updateRouteNodeDisplayCommand, /record UpdateRouteNodeDisplayCommand/);
  assert.match(updateRouteNodeDisplayCommand, /String stationId/);
  assert.match(updateRouteNodeDisplayCommand, /String nodeId/);
  assert.match(updateRouteNodeDisplayCommand, /int displayX/);
  assert.match(updateRouteNodeDisplayCommand, /String displayLabel/);
  assert.match(updateLayoutStatusCommand, /record UpdateSimplifiedStationLayoutStatusCommand/);
  assert.match(updateLayoutStatusCommand, /SimplifiedStationLayoutStatus status/);
  assert.match(updateLayoutStatusCommand, /String reviewedBy/);
  assert.match(outboundPort, /interface LoadTransitMasterPort/);
  assert.match(outboundPort, /loadStationExits/);
  assert.match(outboundPort, /loadAccessibilityFacilities/);
  assert.match(outboundPort, /loadStation\(String stationId\)/);
  assert.match(outboundPort, /loadAccessibilityFacility\(String facilityId\)/);
  assert.match(saveFacilityStatusPort, /interface SaveAccessibilityFacilityStatusPort/);
  assert.match(saveFacilityStatusPort, /saveFacilityStatus/);
  assert.match(saveFacilityStatusPort, /saveAccessibilityFacility/);
  assert.match(saveLayoutStatusPort, /interface SaveSimplifiedStationLayoutStatusPort/);
  assert.match(saveLayoutStatusPort, /saveSimplifiedStationLayoutStatus/);
  assert.match(saveRouteNodePort, /interface SaveRouteNodePort/);
  assert.match(saveRouteNodePort, /saveRouteNode/);
  assert.match(service, /implements TransitMasterQueryUseCase, TransitMasterAdminUseCase/);
  assert.match(service, /countStationMasterDataByStationId\(\)/);
  assert.match(service, /countByStationId/);
  assert.match(service, /SaveAccessibilityFacilityStatusPort/);
  assert.match(service, /createAccessibilityFacility\(CreateAccessibilityFacilityCommand command\)/);
  assert.match(service, /updateAccessibilityFacility\(UpdateAccessibilityFacilityCommand command\)/);
  assert.match(service, /InvalidAccessibilityFacilityException\("이미 등록된 시설입니다\."\)/);
  assert.match(service, /InvalidAccessibilityFacilityException\("시설 출구가 역에 포함되어 있지 않습니다\."\)/);
  assert.match(service, /updateFacilityStatus\(UpdateAccessibilityFacilityStatusCommand command\)/);
  assert.match(service, /InvalidAccessibilityFacilityException\("시설 상태를 선택해야 합니다\."\)/);
  assert.match(service, /updateSimplifiedStationLayoutStatus\(UpdateSimplifiedStationLayoutStatusCommand command\)/);
  assert.match(service, /InvalidSimplifiedStationLayoutException\("구조도 상태를 선택해야 합니다\."\)/);
  assert.match(service, /updateRouteNodeDisplay\(UpdateRouteNodeDisplayCommand command\)/);
  assert.match(service, /InvalidRouteNodeException\("노드 표시 좌표는 0 이상이어야 합니다\."\)/);
  assert.match(service, /RouteNodeNotFoundException/);
  assert.match(repository, /implements[\s\S]*LoadTransitMasterPort[\s\S]*SaveAccessibilityFacilityStatusPort[\s\S]*SaveSimplifiedStationLayoutStatusPort[\s\S]*SaveRouteNodePort/);
  assert.match(repository, /saveAccessibilityFacility\(AccessibilityFacility facility\)/);
  assert.match(
    repository,
    /saveSimplifiedStationLayoutStatus\([\s\S]*String layoutId,[\s\S]*SimplifiedStationLayoutStatus status,[\s\S]*String reviewedBy,[\s\S]*LocalDate updatedAt/,
  );
  assert.match(repository, /saveRouteNode\(RouteNode routeNode\)/);
  assert.doesNotMatch(controller, /\/api\/v1\/operators|\/api\/v1\/lines|\/api\/v1\/stations/);
  assert.match(controller, /@GetMapping\("\/admin\/stations"\)/);
  assert.match(controller, /@GetMapping\("\/admin\/stations\/\{stationId\}"\)/);
  assert.match(controller, /record AdminStationSummaryResponse/);
  assert.match(controller, /StationMasterDataCounts/);
  assert.match(controller, /int exitCount/);
  assert.match(controller, /int facilityCount/);
  assert.match(controller, /int layoutSourceCount/);
  assert.match(controller, /record AdminStationDetailResponse/);
  assert.match(controller, /List<StationExitResponse> exits/);
  assert.match(controller, /List<RouteEdgeResponse> routeEdges/);
  assert.match(controller, /@PostMapping\("\/admin\/facilities"\)/);
  assert.match(controller, /@PutMapping\("\/admin\/facilities\/\{facilityId\}"\)/);
  assert.match(controller, /@PatchMapping\("\/admin\/facilities\/\{facilityId\}\/status"\)/);
  assert.match(controller, /@PatchMapping\("\/admin\/stations\/layouts\/\{layoutId\}\/status"\)/);
  assert.match(controller, /@PatchMapping\("\/admin\/stations\/\{stationId\}\/route-nodes\/\{nodeId\}"\)/);
  assert.match(controller, /TransitMasterAdminUseCase/);
  assert.match(controller, /Principal principal/);
  assert.match(facilityAdminPageController, /@GetMapping\("\/admin\/facilities\/page"\)/);
  assert.match(facilityAdminPageController, /TransitFacilityStatusAssembler/);
  assert.match(facilityAdminPageController, /facilityStatusAssembler\.assemble\(\)/);
  assert.match(stationLayoutAdminPageController, /@GetMapping\("\/admin\/stations\/\{stationId\}\/layouts\/page"\)/);
  assert.match(stationLayoutAdminPageController, /@PostMapping\("\/admin\/stations\/\{stationId\}\/layouts\/\{layoutId\}\/page\/status"\)/);
  assert.match(stationLayoutAdminPageController, /@PostMapping\("\/admin\/stations\/\{stationId\}\/route-nodes\/\{nodeId\}\/page"\)/);
  assert.match(stationLayoutAdminPageController, /TransitMasterQueryUseCase/);
  assert.match(stationLayoutAdminPageController, /TransitMasterAdminUseCase/);
  assert.match(stationLayoutAdminPageController, /getStation\(stationId\)/);
  assert.match(stationLayoutAdminPageController, /listStationLayoutSources\(stationId\)/);
  assert.match(stationLayoutAdminPageController, /listSimplifiedStationLayouts\(stationId\)/);
  assert.match(stationLayoutAdminPageController, /requireLayoutInStation\(stationId, layoutId\)/);
  assert.match(stationLayoutAdminPageController, /SimplifiedStationLayoutNotFoundException/);
  assert.match(stationLayoutAdminPageController, /SimplifiedStationLayoutStatus\.values\(\)/);
  assert.match(stationLayoutAdminPageController, /listRouteNodes\(stationId\)/);
  assert.match(stationLayoutAdminPageController, /listRouteEdges\(stationId\)/);
  assert.match(stationLayoutAdminPageController, /requireRouteNodeInStation\(stationId, nodeId\)/);
  assert.match(stationLayoutAdminPageController, /return "admin\/stations\/layouts"/);
  assert.match(facilityAdminApiController, /@RestController/);
  assert.match(facilityAdminApiController, /@GetMapping\("\/admin\/facilities\/summary"\)/);
  assert.match(facilityAdminApiController, /ApiResponse<List<FacilityStatusRow>>/);
  assert.match(facilityAdminApiController, /facilityStatusAssembler\.assemble\(\)/);
  assert.match(facilityStatusAssembler, /TransitMasterQueryUseCase/);
  assert.match(facilityStatusAssembler, /searchStations\(new StationSearchCommand\(null, null\)\)/);
  assert.match(facilityStatusAssembler, /listStationFacilities\(station\.station\(\)\.id\(\)\)/);
  assert.match(facilityStatusRow, /record FacilityStatusRow/);
  assert.match(facilityStatusRow, /String stationName/);
  assert.match(stationLayoutAdminTemplate, /역 구조도 요약/);
  assert.match(stationLayoutAdminTemplate, /구조도 기준 자료/);
  assert.match(stationLayoutAdminTemplate, /쉬운 내부 구조도/);
  assert.match(stationLayoutAdminTemplate, /name="status"/);
  assert.match(stationLayoutAdminTemplate, /name="displayX"/);
  assert.match(stationLayoutAdminTemplate, /name="displayY"/);
  assert.match(stationLayoutAdminTemplate, /name="displayLabel"/);
  assert.match(stationLayoutAdminTemplate, /name="accessibilityNote"/);
  assert.match(stationLayoutAdminTemplate, /th:action="@\{\/admin\/stations\/\{stationId\}\/layouts\/\{layoutId\}\/page\/status/);
  assert.match(stationLayoutAdminTemplate, /내부 이동 노드/);
  assert.match(stationLayoutAdminTemplate, /내부 이동 간선/);
  assert.match(stationLayoutAdminTemplate, /상업적 사용/);
  assert.match(stationLayoutAdminTemplate, /출처 표시/);
  assert.doesNotMatch(stationLayoutAdminTemplate, /<img|layoutJson/);
  assert.match(facilityStatusRow, /AccessibilityFacilityStatus status/);
  assert.match(facilityStatusRow, /String confidenceLabel/);
  assert.doesNotMatch(facilityStatusRow, /userId|deviceToken|photoDataBase64|description/);
  assert.match(exceptionHandler, /@ExceptionHandler\(HttpMessageNotReadableException\.class\)/);
  assert.match(exceptionHandler, /@ExceptionHandler\(InvalidRequestException\.class\)/);
  assert.match(exceptionHandler, /@ExceptionHandler\(ResourceNotFoundException\.class\)/);
});

test("데이터팩 release workflow는 관리자 검수 override를 다음 pack fixture에 적용한다", () => {
  const workflow = read(".github/workflows/datapack-release.yml");
  const script = read("tools/datapack/apply-admin-review-overrides.mjs");
  const datapackTest = read("tools/datapack/datapack-tools.test.mjs");

  assert.match(workflow, /EASYSUBWAY_DATAPACK_REVIEWED_FIXTURE=/);
  assert.match(workflow, /tools\/datapack\/apply-admin-review-overrides\.mjs/);
  assert.match(workflow, /--fixture tools\/datapack\/fixtures\/catalog-fixture\.json/);
  assert.match(workflow, /--overrides tools\/datapack\/fixtures\/admin-review-overrides\.json/);
  assert.match(workflow, /--fixture "\$\{EASYSUBWAY_DATAPACK_REVIEWED_FIXTURE\}"/);
  assert.match(script, /facilityStatusUpdates/);
  assert.match(script, /facilityStatusUpdates\.facilityId was not found in fixture/);
  assert.match(script, /adminReviewOverrideCount/);
  assert.match(datapackTest, /승인된 관리자 검수 결과는 다음 data pack fixture 시설 상태에 반영된다/);
});

test("백엔드 시설 신고는 헥사고날 API 경계를 따른다", () => {
  const report = read("backend/src/main/java/com/easysubway/report/domain/FacilityReport.java");
  const reportReviewDecision = read("backend/src/main/java/com/easysubway/report/domain/FacilityReportReviewDecision.java");
  const reportType = read("backend/src/main/java/com/easysubway/report/domain/FacilityReportType.java");
  const reportStatus = read("backend/src/main/java/com/easysubway/report/domain/FacilityReportStatus.java");
  const invalidReport = read("backend/src/main/java/com/easysubway/report/domain/InvalidFacilityReportException.java");
  const useCase = read("backend/src/main/java/com/easysubway/report/application/port/in/FacilityReportUseCase.java");
  const command = read("backend/src/main/java/com/easysubway/report/application/port/in/CreateFacilityReportCommand.java");
  const reviewCommand = read("backend/src/main/java/com/easysubway/report/application/port/in/ReviewFacilityReportCommand.java");
  const loadPort = read("backend/src/main/java/com/easysubway/report/application/port/out/LoadFacilityReportPort.java");
  const savePort = read("backend/src/main/java/com/easysubway/report/application/port/out/SaveFacilityReportPort.java");
  const photoStoragePortPath = "backend/src/main/java/com/easysubway/report/application/port/out/StoreFacilityReportPhotoPort.java";
  const uploadedPhotoStoragePortPath =
    "backend/src/main/java/com/easysubway/report/application/port/out/StoreFacilityReportUploadedPhotoPort.java";
  const deletePhotoPortPath = "backend/src/main/java/com/easysubway/report/application/port/out/DeleteFacilityReportPhotoPort.java";
  const saveFacilityStatusPort = read(
    "backend/src/main/java/com/easysubway/transit/application/port/out/SaveAccessibilityFacilityStatusPort.java",
  );
  const service = read("backend/src/main/java/com/easysubway/report/application/service/FacilityReportService.java");
  const repository = read("backend/src/main/java/com/easysubway/report/adapter/out/persistence/InMemoryFacilityReportRepository.java");
  const jdbcRepository = read("backend/src/main/java/com/easysubway/report/adapter/out/persistence/JdbcFacilityReportRepository.java");
  const transitRepository = read(
    "backend/src/main/java/com/easysubway/transit/adapter/out/persistence/InMemoryTransitMasterRepository.java",
  );
  const batchPostgresSchema = read("backend/src/main/resources/db/migration/postgresql/V1__baseline_schema.sql");
  const photoObjectMigrationPath =
    "backend/src/main/resources/db/migration/postgresql/V2__facility_report_photo_object_storage.sql";
  const receiptTokenMigrationPath =
    "backend/src/main/resources/db/migration/postgresql/V3__facility_report_receipt_tokens.sql";
  const dropBase64MigrationPath =
    "backend/src/main/resources/db/migration/postgresql/V4__drop_facility_report_base64_payload.sql";
  const prodConfig = read("backend/src/main/resources/application-prod.yml");
  const controller = read("backend/src/main/java/com/easysubway/report/adapter/in/web/FacilityReportController.java");
  const abuseControl = read("backend/src/main/java/com/easysubway/report/adapter/in/web/FacilityReportAbuseControl.java");
  const adminPageController = read(
    "backend/src/main/java/com/easysubway/report/adapter/in/web/FacilityReportAdminPageController.java",
  );
  const security = read("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java");
  const adminOperatorAuditFilter = read(
    "backend/src/main/java/com/easysubway/common/security/AdminOperatorAuditFilter.java",
  );
  const operatorReportController = read(
    "backend/src/main/java/com/easysubway/operator/adapter/in/web/OperatorAccessibilityReportController.java",
  );
  const operatorReportPageController = read(
    "backend/src/main/java/com/easysubway/operator/adapter/in/web/OperatorAccessibilityReportPageController.java",
  );
  const operatorReportAssembler = read(
    "backend/src/main/java/com/easysubway/operator/adapter/in/web/OperatorAccessibilityReportAssembler.java",
  );
  const operatorReportView = read(
    "backend/src/main/java/com/easysubway/operator/adapter/in/web/OperatorAccessibilityReportView.java",
  );
  const operatorRepeatedBrokenFacilitiesController = read(
    "backend/src/main/java/com/easysubway/operator/adapter/in/web/OperatorRepeatedBrokenFacilitiesController.java",
  );
  const operatorRepeatedBrokenFacilitiesPageController = read(
    "backend/src/main/java/com/easysubway/operator/adapter/in/web/OperatorRepeatedBrokenFacilitiesPageController.java",
  );
  const operatorRepeatedBrokenFacilitiesAssembler = read(
    "backend/src/main/java/com/easysubway/operator/adapter/in/web/OperatorRepeatedBrokenFacilitiesAssembler.java",
  );
  const operatorRepeatedBrokenFacilitiesView = read(
    "backend/src/main/java/com/easysubway/operator/adapter/in/web/OperatorRepeatedBrokenFacilitiesView.java",
  );
  const operatorDataCollectionFailuresController = read(
    "backend/src/main/java/com/easysubway/operator/adapter/in/web/OperatorDataCollectionFailuresController.java",
  );
  const operatorDataCollectionFailuresPageController = read(
    "backend/src/main/java/com/easysubway/operator/adapter/in/web/OperatorDataCollectionFailuresPageController.java",
  );
  const operatorDataCollectionFailuresAssembler = read(
    "backend/src/main/java/com/easysubway/operator/adapter/in/web/OperatorDataCollectionFailuresAssembler.java",
  );
  const operatorDataCollectionFailuresView = read(
    "backend/src/main/java/com/easysubway/operator/adapter/in/web/OperatorDataCollectionFailuresView.java",
  );
  const operatorReportTemplate = read("backend/src/main/resources/templates/operator/accessibility-report.html");
  const operatorRepeatedBrokenFacilitiesTemplate = read(
    "backend/src/main/resources/templates/operator/repeated-broken-facilities.html",
  );
  const operatorDataCollectionFailuresTemplate = read(
    "backend/src/main/resources/templates/operator/data-collection-failures.html",
  );
  const adminReportListTemplate = read("backend/src/main/resources/templates/admin/reports/list.html");
  const adminReportDetailTemplate = read("backend/src/main/resources/templates/admin/reports/detail.html");

  assert.match(report, /record FacilityReport/);
  assert.match(report, /reviewedAt/);
  assert.match(report, /photoObjectKey/);
  assert.match(report, /photoThumbnailObjectKey/);
  assert.match(report, /photoSha256/);
  assert.match(report, /photoSizeBytes/);
  assert.doesNotMatch(report, /photoDataBase64/);
  assert.match(reportReviewDecision, /ACCEPT/);
  assert.match(reportReviewDecision, /REJECT/);
  assert.match(reportReviewDecision, /MARK_DUPLICATE/);
  assert.match(reportType, /BROKEN/);
  assert.match(reportType, /LOCATION_WRONG/);
  assert.match(reportStatus, /SUBMITTED/);
  assert.match(reportStatus, /RESOLVED/);
  assert.match(invalidReport, /extends InvalidRequestException/);
  assert.match(useCase, /interface FacilityReportUseCase/);
  assert.match(useCase, /createReport/);
  assert.match(useCase, /createReportWithReceipt/);
  assert.match(useCase, /getReportByReceiptToken/);
  assert.match(useCase, /getReport/);
  assert.match(useCase, /listReports/);
  assert.match(useCase, /listUserReportSummaries/);
  assert.match(useCase, /listReportSummaries/);
  assert.match(useCase, /summarizeReportProcessingTime/);
  assert.match(useCase, /reviewReport/);
  assert.match(useCase, /confirmReportResult\(String reportId, String userId\)/);
  assert.match(command, /record CreateFacilityReportCommand/);
  assert.match(reviewCommand, /record ReviewFacilityReportCommand/);
  assert.match(loadPort, /interface LoadFacilityReportPort/);
  assert.match(loadPort, /loadReports/);
  assert.match(loadPort, /loadReportByClientSubmissionId/);
  assert.match(loadPort, /loadUserReportSummaries/);
  assert.match(loadPort, /loadReportSummaries/);
  assert.match(loadPort, /countReportsCreatedSince/);
  assert.match(loadPort, /loadReportProcessingTimeSummary/);
  assert.match(savePort, /interface SaveFacilityReportPort/);
  assert.equal(existsSync(path.join(root, photoStoragePortPath)), true);
  assert.equal(existsSync(path.join(root, uploadedPhotoStoragePortPath)), true);
  assert.equal(existsSync(path.join(root, deletePhotoPortPath)), true);
  assert.match(read(photoStoragePortPath), /interface StoreFacilityReportPhotoPort/);
  assert.match(read(photoStoragePortPath), /storeFacilityReportPhoto/);
  assert.match(read(photoStoragePortPath), /storedBytes/);
  assert.match(read(uploadedPhotoStoragePortPath), /interface StoreFacilityReportUploadedPhotoPort/);
  assert.match(read(uploadedPhotoStoragePortPath), /storeUploadedReportPhoto/);
  assert.match(read(deletePhotoPortPath), /interface DeleteFacilityReportPhotoPort/);
  assert.match(read(deletePhotoPortPath), /deleteFacilityReportPhoto/);
  assert.match(saveFacilityStatusPort, /interface SaveAccessibilityFacilityStatusPort/);
  assert.match(saveFacilityStatusPort, /saveFacilityStatus/);
  assert.match(service, /implements FacilityReportUseCase/);
  assert.match(service, /LoadTransitMasterPort/);
  assert.match(service, /SaveAccessibilityFacilityStatusPort/);
  assert.match(service, /applyAcceptedReportToFacilityStatus/);
  assert.match(service, /case BROKEN -> Optional\.of\(AccessibilityFacilityStatus\.BROKEN\)/);
  assert.match(service, /case RECOVERED -> Optional\.of\(AccessibilityFacilityStatus\.NORMAL\)/);
  assert.match(service, /listReports\(FacilityReportStatus status\)/);
  assert.match(service, /listReportSummaries\(\s*FacilityReportStatus status,\s*FacilityReportPageRequest pageRequest\s*\)/);
  assert.match(service, /summarizeReportProcessingTime\(\)/);
  assert.match(service, /Comparator\.comparing\(FacilityReport::createdAt\)\.reversed\(\)/);
  assert.match(service, /FacilityReportStatus\.SUBMITTED/);
  assert.match(service, /FacilityReportStatus\.ACCEPTED/);
  assert.match(service, /FacilityReportStatus\.REJECTED/);
  assert.match(service, /FacilityReportStatus\.RESOLVED/);
  assert.match(service, /FacilityReportStatus\.DUPLICATE/);
  assert.match(service, /confirmReportResult\(String reportId, String userId\)/);
  assert.match(service, /requireConfirmableStatus/);
  assert.match(repository, /implements[\s\S]*LoadFacilityReportPort[\s\S]*SaveFacilityReportPort/);
  assert.match(repository, /List<FacilityReport> loadReports\(\)/);
  assert.match(repository, /PageResult<FacilityReportSummary> loadReportSummaries/);
  assert.match(jdbcRepository, /@Profile\("prod"\)/);
  assert.match(jdbcRepository, /implements[\s\S]*LoadFacilityReportPort[\s\S]*SaveFacilityReportPort[\s\S]*AnonymizeUserFacilityReportPort/);
  assert.match(jdbcRepository, /Optional<FacilityReport> loadReport\(String reportId\)/);
  assert.match(jdbcRepository, /List<FacilityReport> loadReports\(\)/);
  assert.match(jdbcRepository, /PageResult<FacilityReportSummary> loadReportSummaries/);
  assert.match(jdbcRepository, /Optional<FacilityReport> loadReportByClientSubmissionId/);
  assert.match(jdbcRepository, /LIMIT \?/);
  assert.match(jdbcRepository, /OFFSET \?/);
  assert.match(jdbcRepository, /FacilityReport saveReport\(FacilityReport report\)/);
  assert.match(jdbcRepository, /int anonymizeFacilityReportsByUserId\(String userId\)/);
  assert.match(jdbcRepository, /ON CONFLICT \(report_id\) DO UPDATE/);
  assert.match(jdbcRepository, /FacilityReport\.ANONYMIZED_USER_ID/);
  assert.doesNotMatch(jdbcRepository, /photo_data_base64 = NULL/);
  assert.doesNotMatch(jdbcRepository, /resultSet\.getString\("photo_data_base64"\)/);
  assert.doesNotMatch(jdbcRepository, /report\.photoDataBase64/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS facility_reports/);
  assert.equal(existsSync(path.join(root, photoObjectMigrationPath)), true);
  const photoObjectMigration = read(photoObjectMigrationPath);
  assert.doesNotMatch(photoObjectMigration, /DROP COLUMN IF EXISTS photo_data_base64/);
  assert.match(photoObjectMigration, /ADD COLUMN IF NOT EXISTS photo_object_key VARCHAR\(255\)/);
  assert.match(photoObjectMigration, /ADD COLUMN IF NOT EXISTS photo_thumbnail_object_key VARCHAR\(255\)/);
  assert.match(photoObjectMigration, /ADD COLUMN IF NOT EXISTS photo_sha256 CHAR\(64\)/);
  assert.match(photoObjectMigration, /ADD COLUMN IF NOT EXISTS photo_size_bytes BIGINT/);
  assert.equal(existsSync(path.join(root, dropBase64MigrationPath)), true);
  const dropBase64Migration = read(dropBase64MigrationPath);
  assert.match(dropBase64Migration, /DROP COLUMN IF EXISTS photo_data_base64/);
  assert.equal(existsSync(path.join(root, receiptTokenMigrationPath)), true);
  const receiptTokenMigration = read(receiptTokenMigrationPath);
  assert.match(receiptTokenMigration, /ADD COLUMN IF NOT EXISTS client_submission_id VARCHAR\(120\)/);
  assert.match(receiptTokenMigration, /ADD COLUMN IF NOT EXISTS receipt_token_hash CHAR\(64\)/);
  assert.match(receiptTokenMigration, /chk_facility_reports_receipt_hash_requires_submission/);
  assert.match(receiptTokenMigration, /ux_facility_reports_client_submission/);
  assert.equal(existsSync(path.join(root, dropBase64MigrationPath)), true);
  assert.match(read(dropBase64MigrationPath), /DROP COLUMN IF EXISTS photo_data_base64/);
  assert.match(batchPostgresSchema, /CONSTRAINT fk_facility_reports_duplicate/);
  assert.match(batchPostgresSchema, /FOREIGN KEY \(duplicate_of_report_id\) REFERENCES facility_reports\(report_id\)/);
  assert.match(batchPostgresSchema, /CONSTRAINT chk_facility_reports_report_type/);
  assert.match(batchPostgresSchema, /CHECK \(report_type IN \('BROKEN', 'UNDER_CONSTRUCTION', 'CLOSED', 'LOCATION_WRONG', 'INFORMATION_WRONG', 'RECOVERED'\)\)/);
  assert.match(batchPostgresSchema, /CONSTRAINT chk_facility_reports_status/);
  assert.match(batchPostgresSchema, /CHECK \(status IN \('SUBMITTED', 'DUPLICATE', 'UNDER_REVIEW', 'ACCEPTED', 'REJECTED', 'RESOLVED'\)\)/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_facility_reports_created/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_facility_reports_user/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_facility_reports_status_created/);
  assert.match(
    transitRepository,
    /implements[\s\S]*LoadTransitMasterPort[\s\S]*SaveAccessibilityFacilityStatusPort/,
  );
  assert.match(transitRepository, /saveFacilityStatus\(String facilityId, AccessibilityFacilityStatus status, LocalDate updatedAt\)/);
  assert.match(controller, /@PostMapping\("\/api\/v1\/reports"\)/);
  assert.match(controller, /@GetMapping\("\/api\/v1\/reports\/\{reportId\}"\)/);
  assert.match(controller, /@PostMapping\("\/api\/v1\/reports\/\{reportId\}\/confirm"\)/);
  assert.match(controller, /confirmReportResult\(reportId, principal\.getName\(\)\)/);
  assert.match(controller, /@GetMapping\("\/admin\/reports"\)/);
  assert.match(controller, /@GetMapping\("\/admin\/reports\/\{reportId\}"\)/);
  assert.match(controller, /@RequestParam\(required = false\) FacilityReportStatus status/);
  assert.match(controller, /@PostMapping\("\/admin\/reports\/\{reportId\}\/review"\)/);
  assert.match(controller, /Principal principal/);
  assert.match(controller, /principal\.getName\(\)/);
  assert.match(controller, /@ResponseStatus\(HttpStatus\.CREATED\)/);
  assert.match(abuseControl, /extends OncePerRequestFilter/);
  assert.match(abuseControl, /TOO_MANY_REQUESTS/);
  assert.match(abuseControl, /UPLOAD_INTENT[\s\S]*UPLOAD_CLAIM[\s\S]*REPORT_SUBMIT[\s\S]*STATUS[\s\S]*CONFIRM/);
  assert.match(abuseControl, /"\/api\/v1\/report-uploads"/);
  assert.match(abuseControl, /"\/api\/v1\/reports"/);
  assert.match(abuseControl, /Pattern\.compile\("\^\/api\/v1\/reports\/\[\^\/\]\+\/confirm\$/);
  assert.match(abuseControl, /easysubway\.report\.abuse-control\.window-seconds/);
  assert.match(abuseControl, /easysubway\.report\.abuse-control\.upload-intent-limit/);
  assert.match(abuseControl, /easysubway\.report\.abuse-control\.upload-claim-limit/);
  assert.match(abuseControl, /easysubway\.report\.abuse-control\.report-submit-limit/);
  assert.match(abuseControl, /easysubway\.report\.abuse-control\.status-limit/);
  assert.match(abuseControl, /easysubway\.report\.abuse-control\.confirm-limit/);
  assert.match(abuseControl, /easysubway\.report\.abuse-control\.max-counter-keys/);
  assert.match(abuseControl, /maxCounterKeys/);
  assert.match(abuseControl, /ReportAbuseGroup\.values\(\)/);
  assert.match(abuseControl, /easysubway\.auth\.client-ip\.trusted-proxies/);
  assert.match(abuseControl, /X-Forwarded-For/);
  assert.match(abuseControl, /trustedClientAddress/);
  assert.match(abuseControl, /isValidIpv4/);
  assert.match(abuseControl, /split\("\/", -1\)/);
  assert.doesNotMatch(abuseControl, /receiptToken|uploadUrl|privateNote|latitude|longitude/);
  assert.match(prodConfig, /EASYSUBWAY_REPORT_ABUSE_WINDOW_SECONDS:60/);
  assert.match(prodConfig, /EASYSUBWAY_REPORT_ABUSE_UPLOAD_INTENT_LIMIT:60/);
  assert.match(prodConfig, /EASYSUBWAY_REPORT_ABUSE_UPLOAD_CLAIM_LIMIT:120/);
  assert.match(prodConfig, /EASYSUBWAY_REPORT_ABUSE_REPORT_SUBMIT_LIMIT:30/);
  assert.match(prodConfig, /EASYSUBWAY_REPORT_ABUSE_STATUS_LIMIT:120/);
  assert.match(prodConfig, /EASYSUBWAY_REPORT_ABUSE_CONFIRM_LIMIT:30/);
  assert.match(prodConfig, /EASYSUBWAY_REPORT_ABUSE_MAX_COUNTER_KEYS:4096/);
  assert.match(adminPageController, /REPORT_SURGE_ALERT_THRESHOLD = 10/);
  assert.match(adminPageController, /REPORT_SURGE_LOOKBACK_HOURS = 24/);
  assert.match(adminPageController, /ReportSurgeAlertView/);
  assert.match(adminPageController, /reportSurgeAlert/);
  assert.match(adminPageController, /점검 필요/);
  assert.doesNotMatch(adminPageController, /listReports\(status\)/);
  assert.match(adminPageController, /ReportProcessingTimeView/);
  assert.match(adminPageController, /processingTime/);
  assert.match(adminPageController, /summarizeReportProcessingTime\(\)/);
  assert.match(adminPageController, /ReportProcessingTimeSummary/);
  assert.match(adminReportListTemplate, /신고 급증/);
  assert.doesNotMatch(adminReportDetailTemplate, /data:\s*'\s*\+|photoDataBase64/);
  assert.match(adminReportDetailTemplate, /photoObjectKey/);
  assert.match(adminReportListTemplate, /최근 24시간 신고/);
  assert.match(adminReportListTemplate, /신고 처리 시간/);
  assert.match(adminReportListTemplate, /처리 완료 신고 없음/);
  assert.match(adminReportListTemplate, /신고 목록 페이지/);
  assert.match(adminReportListTemplate, /page\.hasNext/);
  assert.match(security, /@Order\(1\)[\s\S]*?securityMatcher\("\/admin\/\*\*"\)/);
  assert.match(security, /securityMatcher\("\/admin\/\*\*"\)/);
  assert.match(security, /anyRequest\(\)\.hasRole\("ADMIN"\)/);
  assert.match(security, /adminSecurityFilterChain\(HttpSecurity http, AdminOperatorAuditFilter auditFilter\)/);
  assert.match(security, /adminSecurityFilterChain[\s\S]*addFilterAfter\(auditFilter, BasicAuthenticationFilter\.class\)/);
  assert.match(security, /@Order\(2\)[\s\S]*?securityMatcher\("\/operator\/\*\*"\)/);
  assert.match(security, /securityMatcher\("\/operator\/\*\*"\)/);
  assert.match(security, /anyRequest\(\)\.hasRole\("OPERATOR_ADMIN"\)/);
  assert.match(security, /operatorSecurityFilterChain\(HttpSecurity http, AdminOperatorAuditFilter auditFilter\)/);
  assert.match(security, /operatorSecurityFilterChain[\s\S]*addFilterAfter\(auditFilter, BasicAuthenticationFilter\.class\)/);
  assert.match(security, /@Order\(3\)[\s\S]*?reportSecurityFilterChain/);
  assert.doesNotMatch(security, /"\/api\/v1\/me"/);
  assert.match(security, /"\/api\/v1\/reports\/\*"/);
  assert.match(security, /"\/api\/v1\/reports\/\*\/confirm"/);
  assert.match(security, /@Order\(4\)[\s\S]*?publicSecurityFilterChain/);
  assert.match(
    security,
    /requestMatchers\([\s\S]*"\/api\/health"[\s\S]*"\/actuator\/health"[\s\S]*"\/actuator\/health\/\*\*"[\s\S]*"\/actuator\/prometheus"[\s\S]*\)\.permitAll\(\)/,
  );
  assert.match(security, /@Order\(4\)[\s\S]*?anyRequest\(\)\.denyAll\(\)/);
  assert.match(security, /easysubway\.operator\.username/);
  assert.match(security, /easysubway\.operator\.password/);
  assert.match(security, /roles\("OPERATOR_ADMIN"\)/);
  assert.match(security, /validateOperatorCredentials/);
  assert.doesNotMatch(security, /publicSecurityFilterChain[\s\S]*?anyRequest\(\)\.permitAll\(\)/);
  assert.match(security, /httpBasic/);
  assert.match(security, /PasswordEncoder/);
  assert.match(security, /passwordEncoder\.encode\(adminPassword\)/);
  assert.match(security, /passwordEncoder\.encode\(operatorPassword\)/);
  assert.match(security, /AdminOperatorAuditFilter adminOperatorAuditFilter\(\)/);
  assert.match(security, /return new AdminOperatorAuditFilter\(\)/);
  assert.match(adminOperatorAuditFilter, /extends OncePerRequestFilter/);
  assert.match(adminOperatorAuditFilter, /MUTATING_METHODS = Set\.of\("POST", "PUT", "PATCH", "DELETE"\)/);
  assert.match(adminOperatorAuditFilter, /path\.startsWith\("\/admin\/"\) \|\| path\.startsWith\("\/operator\/"\)/);
  assert.match(adminOperatorAuditFilter, /admin_operator_state_change_audit method=\{\} path=\{\} principal=\{\} roles=\{\} status=\{\}/);
  assert.match(adminOperatorAuditFilter, /HandlerMapping\.BEST_MATCHING_PATTERN_ATTRIBUTE/);
  assert.doesNotMatch(adminOperatorAuditFilter, /getQueryString|getParameter|getParameterMap|getInputStream|getReader/);
  assert.doesNotMatch(adminOperatorAuditFilter, /receiptToken|uploadUrl|privateNote|latitude|longitude/);
  assert.match(operatorReportController, /@GetMapping\("\/operator\/api\/accessibility-report"\)/);
  assert.match(operatorReportController, /ApiResponse<OperatorAccessibilityReportView>/);
  assert.match(operatorReportController, /reportAssembler\.assemble\(\)/);
  assert.match(operatorReportPageController, /@GetMapping\("\/operator\/accessibility-report\/page"\)/);
  assert.match(operatorReportPageController, /reportAssembler\.assemble\(\)/);
  assert.match(operatorReportPageController, /return "operator\/accessibility-report"/);
  assert.match(operatorReportAssembler, /DataQualityUseCase/);
  assert.match(operatorReportAssembler, /TransitMasterQueryUseCase/);
  assert.match(operatorReportView, /record AccessibilityImprovementPriorityRow\([\s\S]*String stationName,[\s\S]*String facilityName,[\s\S]*int priorityScore,[\s\S]*List<String> reasons/);
  assert.doesNotMatch(operatorReportView, /facilityId/);
  assert.match(
    operatorRepeatedBrokenFacilitiesController,
    /@GetMapping\("\/operator\/api\/repeated-broken-facilities"\)/,
  );
  assert.match(operatorRepeatedBrokenFacilitiesController, /ApiResponse<OperatorRepeatedBrokenFacilitiesView>/);
  assert.match(operatorRepeatedBrokenFacilitiesController, /repeatedBrokenFacilitiesAssembler\.assemble\(\)/);
  assert.match(
    operatorRepeatedBrokenFacilitiesPageController,
    /@GetMapping\("\/operator\/repeated-broken-facilities\/page"\)/,
  );
  assert.match(operatorRepeatedBrokenFacilitiesPageController, /OperatorRepeatedBrokenFacilitiesAssembler/);
  assert.match(operatorRepeatedBrokenFacilitiesPageController, /repeatedBrokenFacilitiesAssembler\.assemble\(\)/);
  assert.match(operatorRepeatedBrokenFacilitiesPageController, /return "operator\/repeated-broken-facilities"/);
  assert.match(operatorRepeatedBrokenFacilitiesAssembler, /FacilityReportUseCase/);
  assert.match(operatorRepeatedBrokenFacilitiesAssembler, /TransitMasterQueryUseCase/);
  assert.match(operatorRepeatedBrokenFacilitiesAssembler, /listRepeatedBrokenReportFacilities/);
  assert.match(operatorRepeatedBrokenFacilitiesAssembler, /StationNotFoundException/);
  assert.match(operatorRepeatedBrokenFacilitiesView, /record OperatorRepeatedBrokenFacilitiesView/);
  assert.match(operatorRepeatedBrokenFacilitiesView, /int totalRepeatedFacilityCount/);
  assert.match(operatorRepeatedBrokenFacilitiesView, /record RepeatedBrokenFacilityRow/);
  assert.doesNotMatch(operatorRepeatedBrokenFacilitiesView, /stationId|facilityId|userId|description/);
  assert.match(
    operatorDataCollectionFailuresController,
    /@GetMapping\("\/operator\/api\/data-collection-failures"\)/,
  );
  assert.match(operatorDataCollectionFailuresController, /ApiResponse<OperatorDataCollectionFailuresView>/);
  assert.match(operatorDataCollectionFailuresController, /dataCollectionFailuresAssembler\.assemble\(\)/);
  assert.match(
    operatorDataCollectionFailuresPageController,
    /@GetMapping\("\/operator\/data-collection-failures\/page"\)/,
  );
  assert.match(operatorDataCollectionFailuresPageController, /OperatorDataCollectionFailuresAssembler/);
  assert.match(operatorDataCollectionFailuresPageController, /dataCollectionFailuresAssembler\.assemble\(\)/);
  assert.match(operatorDataCollectionFailuresPageController, /return "operator\/data-collection-failures"/);
  assert.match(operatorDataCollectionFailuresAssembler, /DataCollectionUseCase/);
  assert.match(operatorDataCollectionFailuresAssembler, /listRecentRuns/);
  assert.match(operatorDataCollectionFailuresAssembler, /getLatestCompletedRun\(DataCollectionSource\.TRANSIT_MASTER\)/);
  assert.match(operatorDataCollectionFailuresAssembler, /DataCollectionStatus\.FAILED/);
  assert.match(operatorDataCollectionFailuresAssembler, /Duration\.ofHours\(24\)/);
  assert.match(operatorDataCollectionFailuresView, /record OperatorDataCollectionFailuresView/);
  assert.match(operatorDataCollectionFailuresView, /int totalRunCount/);
  assert.match(operatorDataCollectionFailuresView, /long failedRunCount/);
  assert.match(operatorDataCollectionFailuresView, /long retryableRunCount/);
  assert.match(operatorDataCollectionFailuresView, /String latestCompletedAtLabel/);
  assert.match(operatorDataCollectionFailuresView, /String freshnessAlertLabel/);
  assert.match(operatorDataCollectionFailuresView, /String freshnessAlertDescription/);
  assert.match(operatorDataCollectionFailuresView, /String freshnessAlertClass/);
  assert.match(operatorDataCollectionFailuresView, /record DataCollectionRunRow/);
  assert.doesNotMatch(operatorDataCollectionFailuresView, /runId|requestedBy/);
  assert.match(operatorReportTemplate, /운영기관 접근성 시설 현황/);
  assert.match(operatorReportTemplate, /읽기 전용 리포트/);
  assert.match(operatorReportTemplate, /역별 접근성 점수/);
  assert.match(operatorReportTemplate, /접근성 개선 우선순위/);
  assert.doesNotMatch(operatorReportTemplate, /<form/);
  assert.match(operatorRepeatedBrokenFacilitiesTemplate, /운영기관 반복 고장 시설 통계/);
  assert.match(operatorRepeatedBrokenFacilitiesTemplate, /읽기 전용 리포트/);
  assert.match(operatorRepeatedBrokenFacilitiesTemplate, /반복 고장 시설/);
  assert.match(operatorRepeatedBrokenFacilitiesTemplate, /시설별 반복 신고/);
  assert.doesNotMatch(
    operatorRepeatedBrokenFacilitiesTemplate,
    /<form|_csrf|stationId|facilityId|userId|description|\/admin\/reports/,
  );
  assert.match(operatorDataCollectionFailuresTemplate, /운영기관 데이터 수집 실패 현황/);
  assert.match(operatorDataCollectionFailuresTemplate, /읽기 전용 리포트/);
  assert.match(operatorDataCollectionFailuresTemplate, /전체 수집 실행/);
  assert.match(operatorDataCollectionFailuresTemplate, /데이터 갱신 상태/);
  assert.match(operatorDataCollectionFailuresTemplate, /최신 완료 수집/);
  assert.match(operatorDataCollectionFailuresTemplate, /report\.freshnessAlertLabel/);
  assert.match(operatorDataCollectionFailuresTemplate, /report\.freshnessAlertDescription/);
  assert.match(operatorDataCollectionFailuresTemplate, /report\.freshnessAlertClass/);
  assert.match(operatorDataCollectionFailuresTemplate, /report\.latestCompletedAtLabel/);
  assert.match(operatorDataCollectionFailuresTemplate, /최근 수집 실행/);
  assert.doesNotMatch(
    operatorDataCollectionFailuresTemplate,
    /<form|_csrf|runId|requestedBy|\/admin\/collections/,
  );
});

test("신고 조회와 경로 피드백 권한 경계는 인증 사용자 기준이다", () => {
  const reportUseCase = read("backend/src/main/java/com/easysubway/report/application/port/in/FacilityReportUseCase.java");
  const reportService = read("backend/src/main/java/com/easysubway/report/application/service/FacilityReportService.java");
  const reportController = read("backend/src/main/java/com/easysubway/report/adapter/in/web/FacilityReportController.java");
  const uploadIntents = read("backend/src/main/java/com/easysubway/report/adapter/in/web/FacilityReportUploadIntents.java");
  const uploadUrlSigner = read("backend/src/main/java/com/easysubway/report/adapter/in/web/FacilityReportUploadUrlSigner.java");
  const objectStorage = read("backend/src/main/java/com/easysubway/report/adapter/out/storage/ObjectStorageFacilityReportPhotoStorage.java");
  const applicationProd = read("backend/src/main/resources/application-prod.yml");
  const security = read("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java");
  const routeControllerPath = "backend/src/main/java/com/easysubway/route/adapter/in/web/RouteSearchController.java";

  assert.match(security, /"\/api\/v1\/reports\/\*"/);
  assert.match(security, /"\/api\/v1\/report-uploads"/);
  assert.match(security, /"\/api\/v1\/report-uploads\/\*"/);
  assert.doesNotMatch(security, /"\/api\/v1\/routes\/\*\/feedback"/);
  assert.match(reportUseCase, /getUserReport\(String reportId, String userId\)/);
  assert.match(reportUseCase, /getReportByReceiptToken\(String reportId, String receiptToken\)/);
  assert.match(reportUseCase, /confirmReportResultByReceiptToken\(String reportId, String receiptToken\)/);
  assert.match(reportService, /getUserReport\(String reportId, String userId\)/);
  assert.match(reportService, /getReportByReceiptToken\(String reportId, String receiptToken\)/);
  assert.match(reportService, /confirmReportResultByReceiptToken\(String reportId, String receiptToken\)/);
  assert.match(reportService, /requireReportOwner\(report, userId\)/);
  assert.match(reportController, /report\(\s*@PathVariable String reportId,\s*Principal principal,\s*@RequestHeader\(name = "X-Easysubway-Report-Receipt-Token"/);
  assert.match(reportController, /confirmReportResult\(\s*@PathVariable String reportId,\s*Principal principal,\s*@RequestHeader\(name = "X-Easysubway-Report-Receipt-Token"/);
  assert.match(reportController, /facilityReportUseCase\.getReportByReceiptToken\(reportId, receiptToken\)/);
  assert.match(reportController, /facilityReportUseCase\.getUserReport\(reportId, principal\.getName\(\)\)/);
  assert.match(reportController, /facilityReportUseCase\.confirmReportResultByReceiptToken\(reportId, receiptToken\)/);
  assert.match(reportController, /environment\.getActiveProfiles\(\)[\s\S]*contains\("prod"\)/);
  assert.match(reportController, /"content-type", request\.normalizedPhotoContentType\(\)/);
  assert.match(reportController, /@RequestHeader\(name = "Content-Type", required = false\) String contentType/);
  assert.match(reportController, /uploadIntents\.requireUpload\(\s*uploadId,\s*contentType,/);
  assert.match(uploadIntents, /OBJECT_KEY_PREFIX = "facility-reports\/unclaimed\/"/);
  assert.match(uploadIntents, /cleanupExpired/);
  assert.match(uploadIntents, /maxPendingCount/);
  assert.match(uploadIntents, /maxPendingBytes/);
  assert.match(uploadIntents, /maxTotalPendingCount/);
  assert.match(uploadIntents, /maxTotalPendingBytes/);
  assert.match(uploadIntents, /String normalizedClientSubmissionId = clientSubmissionId\.trim\(\)/);
  assert.match(uploadIntents, /record UploadIntent\([\s\S]*String uploadId,[\s\S]*String clientSubmissionId,[\s\S]*String objectKey,/);
  assert.match(uploadIntents, /pendingCount\(String clientSubmissionId\)/);
  assert.match(uploadIntents, /intent\.contentType\(\)\.equals\(normalizedContentType\(contentType\)\)/);
  assert.match(uploadIntents, /void consumeObjectKey\(String objectKey\)/);
  assert.match(uploadIntents, /void discardPendingObjectKey\(\s*String clientSubmissionId,\s*String objectKey,\s*String contentType,\s*String sha256,\s*Long sizeBytes,\s*Consumer<String> deleteObject/);
  assert.match(uploadIntents, /isValidSignedObjectKey\(clientSubmissionId, normalizedObjectKey, contentType, sha256, sizeBytes\)/);
  assert.match(uploadIntents, /clientSubmissionId\.length\(\) <= 120 && clientSubmissionId\.matches\("\[A-Za-z0-9_-\]\+"\)/);
  assert.match(uploadUrlSigner, /@Profile\("prod"\)[\s\S]*ObjectStorageFacilityReportUploadUrlSigner/);
  assert.match(uploadUrlSigner, /AWS4-HMAC-SHA256/);
  assert.match(uploadUrlSigner, /X-Amz-Credential/);
  assert.match(uploadUrlSigner, /X-Amz-SignedHeaders/);
  assert.match(objectStorage, /@Profile\("prod"\)/);
  assert.match(objectStorage, /implements[\s\S]*StoreFacilityReportPhotoPort,[\s\S]*LoadFacilityReportPhotoPort,[\s\S]*DeleteFacilityReportPhotoPort,[\s\S]*StoreFacilityReportUploadedPhotoPort/);
  assert.match(objectStorage, /HttpRequest signedRequest\(String method, String objectKey, String contentType, byte\[] body\)/);
  assert.match(applicationProd, /receipt-token-pepper: \$\{EASYSUBWAY_REPORT_RECEIPT_PEPPER:\$\{EASYSUBWAY_REPORT_RECEIPT_TOKEN_PEPPER:\}\}/);
  assert.match(applicationProd, /intent-signing-key: \$\{EASYSUBWAY_REPORT_UPLOAD_INTENT_SIGNING_KEY:\$\{EASYSUBWAY_REPORT_RECEIPT_PEPPER:\$\{EASYSUBWAY_REPORT_RECEIPT_TOKEN_PEPPER:\}\}\}/);
  assert.match(applicationProd, /object-storage-endpoint: \$\{EASYSUBWAY_OBJECT_STORAGE_ENDPOINT:\}/);
  assert.match(applicationProd, /object-storage-access-key: \$\{EASYSUBWAY_OBJECT_STORAGE_ACCESS_KEY:\}/);
  assert.match(applicationProd, /object-storage-secret-key: \$\{EASYSUBWAY_OBJECT_STORAGE_SECRET_KEY:\}/);
  assert.match(applicationProd, /object-storage-region: \$\{EASYSUBWAY_OBJECT_STORAGE_REGION:us-east-1\}/);
  assert.doesNotMatch(reportController, /myReports|\/api\/v1\/me\/reports/);
  assert.match(reportController, /record PageResponse<T>/);
  assert.match(reportController, /record FacilityReportStatusResponse\([^)]*String id,[^)]*String stationId,[^)]*String facilityId,[^)]*FacilityReportType reportType,[^)]*FacilityReportStatus status,[^)]*LocalDateTime createdAt,[^)]*LocalDateTime reviewedAt/);
  assert.doesNotMatch(reportController, /record FacilityReportStatusResponse\([^)]*String userId/);
  assert.doesNotMatch(reportController, /record FacilityReportStatusResponse\([^)]*photoFileName/);
  assert.doesNotMatch(reportController, /record FacilityReportStatusResponse\([^)]*BigDecimal latitude/);
  assert.doesNotMatch(reportController, /record FacilityReportStatusResponse\([^)]*String reviewedBy/);
  assert.equal(existsSync(path.join(root, routeControllerPath)), false);
});

test("운영기관 제휴 제안 export는 접근성 리포트 CSV를 제공한다", () => {
  const operatorReportController = read(
    "backend/src/main/java/com/easysubway/operator/adapter/in/web/OperatorAccessibilityReportController.java",
  );
  const operatorReportView = read(
    "backend/src/main/java/com/easysubway/operator/adapter/in/web/OperatorAccessibilityReportView.java",
  );
  const controllerTest = read(
    "backend/src/test/java/com/easysubway/operator/adapter/in/web/OperatorAccessibilityReportControllerTest.java",
  );

  assert.match(operatorReportController, /@GetMapping\("\/operator\/api\/accessibility-report\/proposal\.csv"\)/);
  assert.match(operatorReportController, /TEXT_CSV_UTF8/);
  assert.match(operatorReportController, /HttpHeaders\.CONTENT_DISPOSITION/);
  assert.match(operatorReportController, /easysubway-operator-accessibility-proposal\.csv/);
  assert.match(operatorReportController, /section,metric,value,detail\\n/);
  assert.match(operatorReportController, /"summary", "totalStations"/);
  assert.match(operatorReportController, /"summary", "totalFacilities"/);
  assert.match(operatorReportController, /"summary", "needsVerificationFacilityCount"/);
  assert.match(operatorReportController, /"summary", "delayedFacilityStatusCount"/);
  assert.match(operatorReportController, /stationScore/);
  assert.match(operatorReportController, /priority/);
  assert.match(operatorReportController, /csvValue/);
  assert.match(operatorReportView, /reasonText\(\)/);
  assert.match(controllerTest, /proposal\.csv/);
  assert.match(controllerTest, /text\/csv;charset=UTF-8/);
  assert.match(controllerTest, /stationScore,상록수/);
  assert.match(controllerTest, /priority,상록수,장애인 화장실,\\"60 - 확인 필요 상태/);
  assert.match(controllerTest, /admin-user/);
  assert.match(controllerTest, /isForbidden/);
});

test("백엔드 이동 프로필은 헥사고날 API 경계를 따른다", () => {
  const profile = read("backend/src/main/java/com/easysubway/profile/domain/MobilityProfile.java");
  const mobilityType = read("backend/src/main/java/com/easysubway/profile/domain/MobilityType.java");
  const invalidProfile = read("backend/src/main/java/com/easysubway/profile/domain/InvalidMobilityProfileException.java");
  const useCase = read("backend/src/main/java/com/easysubway/profile/application/port/in/MobilityProfileUseCase.java");
  const command = read("backend/src/main/java/com/easysubway/profile/application/port/in/SaveMobilityProfileCommand.java");
  const loadPort = read("backend/src/main/java/com/easysubway/profile/application/port/out/LoadMobilityProfilePort.java");
  const savePort = read("backend/src/main/java/com/easysubway/profile/application/port/out/SaveMobilityProfilePort.java");
  const service = read("backend/src/main/java/com/easysubway/profile/application/service/MobilityProfileService.java");
  const repository = read("backend/src/main/java/com/easysubway/profile/adapter/out/persistence/InMemoryMobilityProfileRepository.java");
  const jdbcRepository = read(
    "backend/src/main/java/com/easysubway/profile/adapter/out/persistence/JdbcMobilityProfileRepository.java",
  );
  const batchPostgresSchema = read("backend/src/main/resources/db/migration/postgresql/V1__baseline_schema.sql");
  const controllerPath = "backend/src/main/java/com/easysubway/profile/adapter/in/web/MobilityProfileController.java";

  assert.match(profile, /record MobilityProfile/);
  assert.match(profile, /largeText/);
  assert.match(profile, /highContrast/);
  assert.match(profile, /simpleView/);
  assert.match(mobilityType, /SENIOR/);
  assert.match(mobilityType, /STROLLER/);
  assert.match(mobilityType, /WHEELCHAIR/);
  assert.match(mobilityType, /PREGNANT/);
  assert.match(mobilityType, /TEMPORARY_INJURY/);
  assert.match(mobilityType, /LUGGAGE/);
  assert.match(invalidProfile, /extends InvalidRequestException/);
  assert.match(useCase, /interface MobilityProfileUseCase/);
  assert.match(useCase, /getProfile/);
  assert.match(useCase, /saveProfile/);
  assert.match(command, /record SaveMobilityProfileCommand/);
  assert.match(loadPort, /interface LoadMobilityProfilePort/);
  assert.match(savePort, /interface SaveMobilityProfilePort/);
  assert.match(service, /implements MobilityProfileUseCase/);
  assert.match(service, /defaultProfile/);
  assert.match(service, /MobilityType\.WHEELCHAIR/);
  assert.match(repository, /implements[\s\S]*LoadMobilityProfilePort[\s\S]*SaveMobilityProfilePort/);
  assert.match(jdbcRepository, /@Profile\("prod"\)/);
  assert.match(jdbcRepository, /implements[\s\S]*LoadMobilityProfilePort[\s\S]*SaveMobilityProfilePort[\s\S]*DeleteUserMobilityProfilePort/);
  assert.match(jdbcRepository, /Optional<MobilityProfile> loadProfile\(String userId\)/);
  assert.match(jdbcRepository, /MobilityProfile saveProfile\(MobilityProfile profile\)/);
  assert.match(jdbcRepository, /boolean deleteMobilityProfile\(String userId\)/);
  assert.match(jdbcRepository, /mobility_profiles/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS mobility_profiles/);
  assert.match(batchPostgresSchema, /user_id VARCHAR\(120\) NOT NULL PRIMARY KEY/);
  assert.match(batchPostgresSchema, /mobility_type VARCHAR\(40\) NOT NULL/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_mobility_profiles_updated_at/);
  assert.equal(existsSync(path.join(root, controllerPath)), false);
});

test("백엔드 즐겨찾기 역은 헥사고날 API 경계를 따른다", () => {
  const favorite = read("backend/src/main/java/com/easysubway/favorite/domain/FavoriteStation.java");
  const favoriteDetails = read("backend/src/main/java/com/easysubway/favorite/domain/FavoriteStationWithDetails.java");
  const invalidFavorite = read("backend/src/main/java/com/easysubway/favorite/domain/InvalidFavoriteStationException.java");
  const useCase = read("backend/src/main/java/com/easysubway/favorite/application/port/in/FavoriteStationUseCase.java");
  const listCommand = read("backend/src/main/java/com/easysubway/favorite/application/port/in/ListFavoriteStationsCommand.java");
  const saveCommand = read("backend/src/main/java/com/easysubway/favorite/application/port/in/SaveFavoriteStationCommand.java");
  const removeCommand = read("backend/src/main/java/com/easysubway/favorite/application/port/in/RemoveFavoriteStationCommand.java");
  const loadPort = read("backend/src/main/java/com/easysubway/favorite/application/port/out/LoadFavoriteStationPort.java");
  const alertTargetPort = read(
    "backend/src/main/java/com/easysubway/favorite/application/port/out/LoadFavoriteStationAlertTargetPort.java",
  );
  const savePort = read("backend/src/main/java/com/easysubway/favorite/application/port/out/SaveFavoriteStationPort.java");
  const deletePort = read("backend/src/main/java/com/easysubway/favorite/application/port/out/DeleteFavoriteStationPort.java");
  const service = read("backend/src/main/java/com/easysubway/favorite/application/service/FavoriteStationService.java");
  const repository = read("backend/src/main/java/com/easysubway/favorite/adapter/out/persistence/InMemoryFavoriteStationRepository.java");
  const jdbcRepository = read(
    "backend/src/main/java/com/easysubway/favorite/adapter/out/persistence/JdbcFavoriteStationRepository.java",
  );
  const batchPostgresSchema = read("backend/src/main/resources/db/migration/postgresql/V1__baseline_schema.sql");
  const controllerPath = "backend/src/main/java/com/easysubway/favorite/adapter/in/web/FavoriteStationController.java";
  const security = read("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java");

  assert.match(favorite, /record FavoriteStation/);
  assert.match(favorite, /addedAt/);
  assert.match(favorite, /InvalidFavoriteStationException/);
  assert.match(favoriteDetails, /StationWithLines/);
  assert.match(invalidFavorite, /extends InvalidRequestException/);
  assert.match(useCase, /interface FavoriteStationUseCase/);
  assert.match(useCase, /listFavoriteStations/);
  assert.match(useCase, /saveFavoriteStation/);
  assert.match(useCase, /removeFavoriteStation/);
  assert.match(listCommand, /record ListFavoriteStationsCommand/);
  assert.match(saveCommand, /record SaveFavoriteStationCommand/);
  assert.match(removeCommand, /record RemoveFavoriteStationCommand/);
  assert.match(loadPort, /interface LoadFavoriteStationPort/);
  assert.match(alertTargetPort, /interface LoadFavoriteStationAlertTargetPort/);
  assert.match(alertTargetPort, /loadUserIdsByFavoriteStationId/);
  assert.match(savePort, /interface SaveFavoriteStationPort/);
  assert.match(deletePort, /interface DeleteFavoriteStationPort/);
  assert.match(service, /implements FavoriteStationUseCase/);
  assert.match(service, /LoadTransitMasterPort/);
  assert.match(service, /StationNotFoundException/);
  assert.match(repository, /implements[\s\S]*LoadFavoriteStationPort[\s\S]*LoadFavoriteStationAlertTargetPort[\s\S]*SaveFavoriteStationPort[\s\S]*DeleteFavoriteStationPort/);
  assert.match(repository, /loadUserIdsByFavoriteStationId/);
  assert.match(jdbcRepository, /@Profile\("prod"\)/);
  assert.match(jdbcRepository, /implements[\s\S]*LoadFavoriteStationPort[\s\S]*LoadFavoriteStationAlertTargetPort[\s\S]*SaveFavoriteStationPort[\s\S]*DeleteFavoriteStationPort[\s\S]*DeleteUserFavoriteStationPort/);
  assert.match(jdbcRepository, /List<FavoriteStation> loadFavoriteStations\(String userId\)/);
  assert.match(jdbcRepository, /Optional<FavoriteStation> loadFavoriteStation\(String userId, String stationId\)/);
  assert.match(jdbcRepository, /List<String> loadUserIdsByFavoriteStationId\(String stationId\)/);
  assert.match(jdbcRepository, /FavoriteStation saveFavoriteStation\(FavoriteStation favoriteStation\)/);
  assert.match(jdbcRepository, /int deleteFavoriteStationsByUserId\(String userId\)/);
  assert.match(jdbcRepository, /favorite_stations/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS favorite_stations/);
  assert.match(batchPostgresSchema, /PRIMARY KEY \(user_id, station_id\)/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_favorite_stations_station_user/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_favorite_stations_user_added/);
  assert.equal(existsSync(path.join(root, controllerPath)), false);
  assert.doesNotMatch(security, /"\/api\/v1\/me\/favorites\/\*\*"/);
});

test("백엔드 즐겨찾기 시설은 시설 마스터 기반 헥사고날 API 경계를 따른다", () => {
  const favorite = read("backend/src/main/java/com/easysubway/favorite/domain/FavoriteFacility.java");
  const favoriteDetails = read("backend/src/main/java/com/easysubway/favorite/domain/FavoriteFacilityWithDetails.java");
  const invalidFavorite = read("backend/src/main/java/com/easysubway/favorite/domain/InvalidFavoriteFacilityException.java");
  const notFound = read("backend/src/main/java/com/easysubway/favorite/domain/FavoriteFacilityNotFoundException.java");
  const useCase = read("backend/src/main/java/com/easysubway/favorite/application/port/in/FavoriteFacilityUseCase.java");
  const listCommand = read("backend/src/main/java/com/easysubway/favorite/application/port/in/ListFavoriteFacilitiesCommand.java");
  const saveCommand = read("backend/src/main/java/com/easysubway/favorite/application/port/in/SaveFavoriteFacilityCommand.java");
  const removeCommand = read("backend/src/main/java/com/easysubway/favorite/application/port/in/RemoveFavoriteFacilityCommand.java");
  const loadPort = read("backend/src/main/java/com/easysubway/favorite/application/port/out/LoadFavoriteFacilityPort.java");
  const alertTargetPort = read(
    "backend/src/main/java/com/easysubway/favorite/application/port/out/LoadFavoriteFacilityAlertTargetPort.java",
  );
  const savePort = read("backend/src/main/java/com/easysubway/favorite/application/port/out/SaveFavoriteFacilityPort.java");
  const deletePort = read("backend/src/main/java/com/easysubway/favorite/application/port/out/DeleteFavoriteFacilityPort.java");
  const service = read("backend/src/main/java/com/easysubway/favorite/application/service/FavoriteFacilityService.java");
  const repository = read("backend/src/main/java/com/easysubway/favorite/adapter/out/persistence/InMemoryFavoriteFacilityRepository.java");
  const jdbcRepository = read(
    "backend/src/main/java/com/easysubway/favorite/adapter/out/persistence/JdbcFavoriteFacilityRepository.java",
  );
  const batchPostgresSchema = read("backend/src/main/resources/db/migration/postgresql/V1__baseline_schema.sql");
  const controllerPath = "backend/src/main/java/com/easysubway/favorite/adapter/in/web/FavoriteFacilityController.java";
  const security = read("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java");

  assert.match(favorite, /record FavoriteFacility/);
  assert.match(favorite, /facilityId/);
  assert.match(favorite, /addedAt/);
  assert.match(favorite, /InvalidFavoriteFacilityException/);
  assert.match(favoriteDetails, /AccessibilityFacility/);
  assert.match(favoriteDetails, /Station/);
  assert.match(invalidFavorite, /extends InvalidRequestException/);
  assert.match(notFound, /extends ResourceNotFoundException/);
  assert.match(notFound, /시설 정보를 찾을 수 없습니다\./);
  assert.match(useCase, /interface FavoriteFacilityUseCase/);
  assert.match(useCase, /listFavoriteFacilities/);
  assert.match(useCase, /saveFavoriteFacility/);
  assert.match(useCase, /removeFavoriteFacility/);
  assert.match(listCommand, /record ListFavoriteFacilitiesCommand/);
  assert.match(saveCommand, /record SaveFavoriteFacilityCommand/);
  assert.match(removeCommand, /record RemoveFavoriteFacilityCommand/);
  assert.match(loadPort, /interface LoadFavoriteFacilityPort/);
  assert.match(alertTargetPort, /interface LoadFavoriteFacilityAlertTargetPort/);
  assert.match(alertTargetPort, /loadUserIdsByFavoriteFacilityId/);
  assert.match(savePort, /interface SaveFavoriteFacilityPort/);
  assert.match(deletePort, /interface DeleteFavoriteFacilityPort/);
  assert.match(service, /implements FavoriteFacilityUseCase/);
  assert.match(service, /LoadTransitMasterPort/);
  assert.match(service, /loadAccessibilityFacilities/);
  assert.match(service, /FavoriteFacilityNotFoundException/);
  assert.match(repository, /implements[\s\S]*LoadFavoriteFacilityPort[\s\S]*LoadFavoriteFacilityAlertTargetPort[\s\S]*SaveFavoriteFacilityPort[\s\S]*DeleteFavoriteFacilityPort/);
  assert.match(repository, /loadUserIdsByFavoriteFacilityId/);
  assert.match(jdbcRepository, /@Profile\("prod"\)/);
  assert.match(jdbcRepository, /implements[\s\S]*LoadFavoriteFacilityPort[\s\S]*LoadFavoriteFacilityAlertTargetPort[\s\S]*SaveFavoriteFacilityPort[\s\S]*DeleteFavoriteFacilityPort[\s\S]*DeleteUserFavoriteFacilityPort/);
  assert.match(jdbcRepository, /List<FavoriteFacility> loadFavoriteFacilities\(String userId\)/);
  assert.match(jdbcRepository, /Optional<FavoriteFacility> loadFavoriteFacility\(String userId, String facilityId\)/);
  assert.match(jdbcRepository, /List<String> loadUserIdsByFavoriteFacilityId\(String facilityId\)/);
  assert.match(jdbcRepository, /FavoriteFacility saveFavoriteFacility\(FavoriteFacility favoriteFacility\)/);
  assert.match(jdbcRepository, /int deleteFavoriteFacilitiesByUserId\(String userId\)/);
  assert.match(jdbcRepository, /favorite_facilities/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS favorite_facilities/);
  assert.match(batchPostgresSchema, /PRIMARY KEY \(user_id, facility_id\)/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_favorite_facilities_facility_user/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_favorite_facilities_user_added/);
  assert.equal(existsSync(path.join(root, controllerPath)), false);
  assert.doesNotMatch(security, /"\/api\/v1\/me\/favorites\/\*\*"/);
});

test("백엔드 즐겨찾기 경로는 경로 검색 결과 기반 헥사고날 API 경계를 따른다", () => {
  const favorite = read("backend/src/main/java/com/easysubway/favorite/domain/FavoriteRoute.java");
  const favoriteDetails = read("backend/src/main/java/com/easysubway/favorite/domain/FavoriteRouteWithDetails.java");
  const invalidFavorite = read("backend/src/main/java/com/easysubway/favorite/domain/InvalidFavoriteRouteException.java");
  const useCase = read("backend/src/main/java/com/easysubway/favorite/application/port/in/FavoriteRouteUseCase.java");
  const listCommand = read("backend/src/main/java/com/easysubway/favorite/application/port/in/ListFavoriteRoutesCommand.java");
  const saveCommand = read("backend/src/main/java/com/easysubway/favorite/application/port/in/SaveFavoriteRouteCommand.java");
  const removeCommand = read("backend/src/main/java/com/easysubway/favorite/application/port/in/RemoveFavoriteRouteCommand.java");
  const loadPort = read("backend/src/main/java/com/easysubway/favorite/application/port/out/LoadFavoriteRoutePort.java");
  const alertTargetPort = read(
    "backend/src/main/java/com/easysubway/favorite/application/port/out/LoadFavoriteRouteAlertTargetPort.java",
  );
  const savePort = read("backend/src/main/java/com/easysubway/favorite/application/port/out/SaveFavoriteRoutePort.java");
  const deletePort = read("backend/src/main/java/com/easysubway/favorite/application/port/out/DeleteFavoriteRoutePort.java");
  const service = read("backend/src/main/java/com/easysubway/favorite/application/service/FavoriteRouteService.java");
  const repository = read("backend/src/main/java/com/easysubway/favorite/adapter/out/persistence/InMemoryFavoriteRouteRepository.java");
  const jdbcRepository = read("backend/src/main/java/com/easysubway/favorite/adapter/out/persistence/JdbcFavoriteRouteRepository.java");
  const batchPostgresSchema = read("backend/src/main/resources/db/migration/postgresql/V1__baseline_schema.sql");
  const controllerPath = "backend/src/main/java/com/easysubway/favorite/adapter/in/web/FavoriteRouteController.java";
  const security = read("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java");

  assert.match(favorite, /record FavoriteRoute/);
  assert.match(favorite, /RouteSearchResult/);
  assert.match(favorite, /routeSearchId/);
  assert.match(favorite, /addedAt/);
  assert.match(favorite, /InvalidFavoriteRouteException/);
  assert.match(favoriteDetails, /RouteSearchResult/);
  assert.match(invalidFavorite, /extends InvalidRequestException/);
  assert.match(useCase, /interface FavoriteRouteUseCase/);
  assert.match(useCase, /listFavoriteRoutes/);
  assert.match(useCase, /saveFavoriteRoute/);
  assert.match(useCase, /removeFavoriteRoute/);
  assert.match(listCommand, /record ListFavoriteRoutesCommand/);
  assert.match(saveCommand, /record SaveFavoriteRouteCommand/);
  assert.match(removeCommand, /record RemoveFavoriteRouteCommand/);
  assert.match(loadPort, /interface LoadFavoriteRoutePort/);
  assert.match(alertTargetPort, /interface LoadFavoriteRouteAlertTargetPort/);
  assert.match(alertTargetPort, /loadUserIdsByRouteStationId/);
  assert.match(savePort, /interface SaveFavoriteRoutePort/);
  assert.match(deletePort, /interface DeleteFavoriteRoutePort/);
  assert.match(service, /implements FavoriteRouteUseCase/);
  assert.match(service, /LoadRouteSearchPort/);
  assert.match(service, /RouteSearchNotFoundException/);
  assert.match(repository, /implements[\s\S]*LoadFavoriteRoutePort[\s\S]*LoadFavoriteRouteAlertTargetPort[\s\S]*SaveFavoriteRoutePort[\s\S]*DeleteFavoriteRoutePort/);
  assert.match(repository, /loadUserIdsByRouteStationId/);
  assert.match(jdbcRepository, /@Profile\("prod"\)/);
  assert.match(jdbcRepository, /implements[\s\S]*LoadFavoriteRoutePort[\s\S]*LoadFavoriteRouteAlertTargetPort[\s\S]*SaveFavoriteRoutePort[\s\S]*DeleteFavoriteRoutePort[\s\S]*DeleteUserFavoriteRoutePort/);
  assert.match(jdbcRepository, /List<FavoriteRoute> loadFavoriteRoutes\(String userId\)/);
  assert.match(jdbcRepository, /Optional<FavoriteRoute> loadFavoriteRoute\(String userId, String routeSearchId\)/);
  assert.match(jdbcRepository, /List<String> loadUserIdsByRouteStationId\(String stationId\)/);
  assert.match(jdbcRepository, /FavoriteRoute saveFavoriteRoute\(FavoriteRoute favoriteRoute\)/);
  assert.match(jdbcRepository, /ON CONFLICT \(user_id, route_search_id\) DO UPDATE/);
  assert.match(jdbcRepository, /int deleteFavoriteRoutesByUserId\(String userId\)/);
  assert.match(jdbcRepository, /favorite_routes/);
  assert.match(jdbcRepository, /favorite_route_stations/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS favorite_routes/);
  assert.match(batchPostgresSchema, /PRIMARY KEY \(user_id, route_search_id\)/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS favorite_route_stations/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_favorite_routes_user_added/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_favorite_route_stations_station_user/);
  assert.equal(existsSync(path.join(root, controllerPath)), false);
  assert.doesNotMatch(security, /"\/api\/v1\/me\/favorites\/\*\*"/);
});

test("백엔드 알림 설정은 인증 사용자 기준 헥사고날 API 경계를 따른다", () => {
  const device = read("backend/src/main/java/com/easysubway/notification/domain/RegisteredDevice.java");
  const settings = read("backend/src/main/java/com/easysubway/notification/domain/NotificationSettings.java");
  const platform = read("backend/src/main/java/com/easysubway/notification/domain/DevicePlatform.java");
  const invalidNotification = read("backend/src/main/java/com/easysubway/notification/domain/InvalidNotificationPreferenceException.java");
  const useCase = read("backend/src/main/java/com/easysubway/notification/application/port/in/NotificationPreferenceUseCase.java");
  const registerCommand = read("backend/src/main/java/com/easysubway/notification/application/port/in/RegisterDeviceCommand.java");
  const saveCommand = read("backend/src/main/java/com/easysubway/notification/application/port/in/SaveNotificationSettingsCommand.java");
  const loadPort = read("backend/src/main/java/com/easysubway/notification/application/port/out/LoadNotificationPreferencePort.java");
  const saveDevicePort = read("backend/src/main/java/com/easysubway/notification/application/port/out/SaveRegisteredDevicePort.java");
  const saveSettingsPort = read("backend/src/main/java/com/easysubway/notification/application/port/out/SaveNotificationSettingsPort.java");
  const service = read("backend/src/main/java/com/easysubway/notification/application/service/NotificationPreferenceService.java");
  const repository = read("backend/src/main/java/com/easysubway/notification/adapter/out/persistence/InMemoryNotificationPreferenceRepository.java");
  const jdbcRepository = read(
    "backend/src/main/java/com/easysubway/notification/adapter/out/persistence/JdbcNotificationPreferenceRepository.java",
  );
  const batchPostgresSchema = read("backend/src/main/resources/db/migration/postgresql/V1__baseline_schema.sql");
  const controllerPath = "backend/src/main/java/com/easysubway/notification/adapter/in/web/NotificationPreferenceController.java";
  const security = read("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java");

  assert.match(device, /record RegisteredDevice/);
  assert.match(device, /registeredAt/);
  assert.match(settings, /record NotificationSettings/);
  assert.match(settings, /favoriteStationFacilityAlerts/);
  assert.match(settings, /favoriteRouteFacilityAlerts/);
  assert.match(settings, /reportStatusAlerts/);
  assert.match(settings, /dataQualityAlerts/);
  assert.match(platform, /ANDROID/);
  assert.match(platform, /IOS/);
  assert.match(invalidNotification, /extends InvalidRequestException/);
  assert.match(useCase, /interface NotificationPreferenceUseCase/);
  assert.match(useCase, /registerDevice/);
  assert.match(useCase, /getNotificationSettings/);
  assert.match(useCase, /saveNotificationSettings/);
  assert.match(registerCommand, /record RegisterDeviceCommand/);
  assert.match(saveCommand, /record SaveNotificationSettingsCommand/);
  assert.match(loadPort, /interface LoadNotificationPreferencePort/);
  assert.match(saveDevicePort, /interface SaveRegisteredDevicePort/);
  assert.match(saveSettingsPort, /interface SaveNotificationSettingsPort/);
  assert.match(service, /implements NotificationPreferenceUseCase/);
  assert.match(repository, /implements[\s\S]*LoadNotificationPreferencePort[\s\S]*SaveRegisteredDevicePort[\s\S]*SaveNotificationSettingsPort/);
  assert.match(jdbcRepository, /@Profile\("prod"\)/);
  assert.match(jdbcRepository, /implements[\s\S]*LoadNotificationPreferencePort[\s\S]*SaveRegisteredDevicePort[\s\S]*SaveNotificationSettingsPort[\s\S]*DeleteUserNotificationPreferencePort/);
  assert.match(jdbcRepository, /Optional<NotificationSettings> loadNotificationSettings\(String userId\)/);
  assert.match(jdbcRepository, /List<RegisteredDevice> loadDevices\(String userId\)/);
  assert.match(jdbcRepository, /RegisteredDevice saveRegisteredDevice\(RegisteredDevice device\)/);
  assert.match(jdbcRepository, /ON CONFLICT \(platform, device_token\) DO UPDATE/);
  assert.match(jdbcRepository, /NotificationSettings saveNotificationSettings\(NotificationSettings settings\)/);
  assert.match(jdbcRepository, /boolean deleteNotificationSettings\(String userId\)/);
  assert.match(jdbcRepository, /int deleteRegisteredDevices\(String userId\)/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS notification_settings/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS registered_devices/);
  assert.match(batchPostgresSchema, /CONSTRAINT uq_registered_devices_platform_token/);
  assert.match(batchPostgresSchema, /CHECK \(platform IN \('ANDROID', 'IOS'\)\)/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_registered_devices_user_registered/);
  assert.equal(existsSync(path.join(root, controllerPath)), false);
  assert.doesNotMatch(security, /"\/api\/v1\/devices"|\"\/api\/v1\/me\/notification-settings"/);
});

test("백엔드 푸시 알림 outbox는 관리자 API와 헥사고날 경계를 따른다", () => {
  const notification = read("backend/src/main/java/com/easysubway/notification/domain/PushNotification.java");
  const result = read("backend/src/main/java/com/easysubway/notification/domain/PushNotificationDispatchResult.java");
  const dashboardSummary = read(
    "backend/src/main/java/com/easysubway/notification/domain/PushNotificationDashboardSummary.java",
  );
  const type = read("backend/src/main/java/com/easysubway/notification/domain/PushNotificationType.java");
  const status = read("backend/src/main/java/com/easysubway/notification/domain/PushNotificationStatus.java");
  const invalidPush = read("backend/src/main/java/com/easysubway/notification/domain/InvalidPushNotificationException.java");
  const useCase = read("backend/src/main/java/com/easysubway/notification/application/port/in/PushNotificationDispatchUseCase.java");
  const dashboardUseCase = read(
    "backend/src/main/java/com/easysubway/notification/application/port/in/PushNotificationDashboardUseCase.java",
  );
  const command = read("backend/src/main/java/com/easysubway/notification/application/port/in/DispatchPushNotificationCommand.java");
  const loadOutboxPort = read("backend/src/main/java/com/easysubway/notification/application/port/out/LoadPushNotificationOutboxPort.java");
  const saveOutboxPort = read("backend/src/main/java/com/easysubway/notification/application/port/out/SavePushNotificationOutboxPort.java");
  const summarizeOutboxPort = read(
    "backend/src/main/java/com/easysubway/notification/application/port/out/SummarizePushNotificationOutboxPort.java",
  );
  const service = read("backend/src/main/java/com/easysubway/notification/application/service/PushNotificationDispatchService.java");
  const dashboardService = read(
    "backend/src/main/java/com/easysubway/notification/application/service/PushNotificationDashboardService.java",
  );
  const repository = read("backend/src/main/java/com/easysubway/notification/adapter/out/persistence/InMemoryPushNotificationOutboxRepository.java");
  const jdbcRepository = read(
    "backend/src/main/java/com/easysubway/notification/adapter/out/persistence/JdbcPushNotificationOutboxRepository.java",
  );
  const batchPostgresSchema = read("backend/src/main/resources/db/migration/postgresql/V1__baseline_schema.sql");
  const pushProcessingMigration = read(
    "backend/src/main/resources/db/migration/postgresql/V6__push_notification_processing_claim.sql",
  );
  const controller = read("backend/src/main/java/com/easysubway/notification/adapter/in/web/PushNotificationController.java");
  const dashboardController = read(
    "backend/src/main/java/com/easysubway/notification/adapter/in/web/PushNotificationAdminPageController.java",
  );
  const dashboardApiController = read(
    "backend/src/main/java/com/easysubway/notification/adapter/in/web/PushNotificationAdminApiController.java",
  );
  const dashboardView = read(
    "backend/src/main/java/com/easysubway/notification/adapter/in/web/PushNotificationDashboardView.java",
  );
  const operatorPushNotificationReportController = read(
    "backend/src/main/java/com/easysubway/operator/adapter/in/web/OperatorPushNotificationReportController.java",
  );
  const operatorPushNotificationReportPageController = read(
    "backend/src/main/java/com/easysubway/operator/adapter/in/web/OperatorPushNotificationReportPageController.java",
  );
  const operatorPushNotificationReportAssembler = read(
    "backend/src/main/java/com/easysubway/operator/adapter/in/web/OperatorPushNotificationReportAssembler.java",
  );
  const operatorPushNotificationReportView = read(
    "backend/src/main/java/com/easysubway/operator/adapter/in/web/OperatorPushNotificationReportView.java",
  );
  const dashboardTemplate = read("backend/src/main/resources/templates/admin/notifications/push.html");
  const operatorPushNotificationReportTemplate = read(
    "backend/src/main/resources/templates/operator/push-notification-report.html",
  );
  const security = read("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java");

  assert.match(notification, /record PushNotification/);
  assert.match(notification, /deviceToken/);
  assert.match(notification, /failureReason/);
  assert.match(notification, /PushNotificationStatus/);
  assert.match(result, /record PushNotificationDispatchResult/);
  assert.match(dashboardSummary, /record PushNotificationDashboardSummary/);
  assert.match(dashboardSummary, /pendingCount/);
  assert.match(dashboardSummary, /sentCount/);
  assert.match(dashboardSummary, /failedCount/);
  assert.match(type, /FAVORITE_STATION_FACILITY/);
  assert.match(type, /FAVORITE_ROUTE_FACILITY/);
  assert.match(type, /REPORT_STATUS/);
  assert.match(type, /DATA_QUALITY/);
  assert.match(status, /PENDING/);
  assert.match(status, /PROCESSING/);
  assert.match(invalidPush, /extends InvalidRequestException/);
  assert.match(useCase, /interface PushNotificationDispatchUseCase/);
  assert.match(useCase, /dispatch/);
  assert.match(dashboardUseCase, /interface PushNotificationDashboardUseCase/);
  assert.match(dashboardUseCase, /summarizePushNotifications/);
  assert.match(command, /record DispatchPushNotificationCommand/);
  assert.match(loadOutboxPort, /interface LoadPushNotificationOutboxPort/);
  assert.match(saveOutboxPort, /interface SavePushNotificationOutboxPort/);
  assert.match(summarizeOutboxPort, /interface SummarizePushNotificationOutboxPort/);
  assert.match(summarizeOutboxPort, /summarizePushNotificationOutbox/);
  assert.match(service, /implements PushNotificationDispatchUseCase/);
  assert.match(service, /LoadNotificationPreferencePort/);
  assert.match(service, /SavePushNotificationOutboxPort/);
  assert.match(dashboardService, /implements PushNotificationDashboardUseCase/);
  assert.match(dashboardService, /SummarizePushNotificationOutboxPort/);
  assert.match(repository, /implements[\s\S]*LoadPushNotificationOutboxPort[\s\S]*SavePushNotificationOutboxPort[\s\S]*SummarizePushNotificationOutboxPort/);
  assert.match(jdbcRepository, /@Profile\("prod"\)/);
  assert.match(jdbcRepository, /implements[\s\S]*LoadPushNotificationOutboxPort[\s\S]*SavePushNotificationOutboxPort[\s\S]*SummarizePushNotificationOutboxPort[\s\S]*DeleteUserPushNotificationPort/);
  assert.match(jdbcRepository, /List<PushNotification> loadPushNotifications\(String userId\)/);
  assert.match(jdbcRepository, /PushNotification savePushNotification\(PushNotification notification\)/);
  assert.match(jdbcRepository, /boolean claimPendingPushNotification\(PushNotification notification\)/);
  assert.match(jdbcRepository, /processing_claimed_at = \?/);
  assert.match(jdbcRepository, /processing_claimed_at < \?/);
  assert.match(jdbcRepository, /PushNotificationDashboardSummary summarizePushNotificationOutbox\(\)/);
  assert.match(jdbcRepository, /int deletePushNotifications\(String userId\)/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS push_notification_outbox/);
  assert.match(batchPostgresSchema, /failure_reason VARCHAR\(1000\)/);
  assert.match(batchPostgresSchema, /CONSTRAINT chk_push_notification_outbox_platform/);
  assert.match(batchPostgresSchema, /CONSTRAINT chk_push_notification_outbox_type/);
  assert.match(batchPostgresSchema, /CONSTRAINT chk_push_notification_outbox_status/);
  assert.match(pushProcessingMigration, /ADD COLUMN IF NOT EXISTS processing_claimed_at TIMESTAMP/);
  assert.match(pushProcessingMigration, /DROP CONSTRAINT IF EXISTS chk_push_notification_outbox_status/);
  assert.match(pushProcessingMigration, /status IN \('PENDING', 'PROCESSING', 'SENT', 'FAILED'\)/);
  assert.match(batchPostgresSchema, /CONSTRAINT chk_push_notification_outbox_failure_reason/);
  assert.match(batchPostgresSchema, /failure_reason IS NULL OR status = 'FAILED'/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_push_notification_outbox_user_created/);
  assert.match(controller, /@PostMapping\("\/admin\/notifications\/push"\)/);
  assert.match(controller, /PushNotificationDispatchUseCase/);
  assert.doesNotMatch(controller, /deviceToken/);
  assert.match(dashboardController, /@GetMapping\("\/admin\/notifications\/push\/page"\)/);
  assert.match(dashboardController, /PushNotificationDashboardUseCase/);
  assert.match(dashboardApiController, /@GetMapping\("\/admin\/notifications\/push\/summary"\)/);
  assert.match(dashboardApiController, /ApiResponse<PushNotificationDashboardView>/);
  assert.match(dashboardView, /record PushNotificationDashboardView/);
  assert.match(dashboardView, /deliveryAttemptCount/);
  assert.match(dashboardView, /successRateLabel/);
  assert.match(dashboardView, /failureRateLabel/);
  assert.match(dashboardView, /failureAlertLabel/);
  assert.match(dashboardView, /failureAlertClass/);
  assert.match(dashboardView, /StatusCountRow/);
  assert.doesNotMatch(dashboardView, /notificationId|userId|deviceToken/);
  assert.match(operatorPushNotificationReportController, /@GetMapping\("\/operator\/api\/push-notification-report"\)/);
  assert.match(operatorPushNotificationReportController, /ApiResponse<OperatorPushNotificationReportView>/);
  assert.match(operatorPushNotificationReportController, /pushNotificationReportAssembler\.assemble\(\)/);
  assert.match(
    operatorPushNotificationReportPageController,
    /@GetMapping\("\/operator\/push-notification-report\/page"\)/,
  );
  assert.match(operatorPushNotificationReportPageController, /OperatorPushNotificationReportAssembler/);
  assert.match(operatorPushNotificationReportPageController, /pushNotificationReportAssembler\.assemble\(\)/);
  assert.match(operatorPushNotificationReportPageController, /return "operator\/push-notification-report"/);
  assert.match(operatorPushNotificationReportAssembler, /PushNotificationDashboardUseCase/);
  assert.match(operatorPushNotificationReportAssembler, /summarizePushNotifications/);
  assert.match(operatorPushNotificationReportAssembler, /OPERATOR_SAFE_FAILURE_REASON/);
  assert.doesNotMatch(operatorPushNotificationReportAssembler, /summary\.latestFailureReason\(\),/);
  assert.doesNotMatch(operatorPushNotificationReportAssembler, /" \+ summary\.latestFailureReason\(\)/);
  assert.match(operatorPushNotificationReportView, /record OperatorPushNotificationReportView/);
  assert.match(operatorPushNotificationReportView, /long totalCount/);
  assert.match(operatorPushNotificationReportView, /long pendingCount/);
  assert.match(operatorPushNotificationReportView, /long sentCount/);
  assert.match(operatorPushNotificationReportView, /long failedCount/);
  assert.match(operatorPushNotificationReportView, /String latestFailureReason/);
  assert.match(operatorPushNotificationReportView, /record StatusCountRow/);
  assert.doesNotMatch(operatorPushNotificationReportView, /notificationId|userId|deviceToken/);
  assert.match(dashboardTemplate, /푸시 알림 현황/);
  assert.match(dashboardTemplate, /전체 알림/);
  assert.match(dashboardTemplate, /발송 시도/);
  assert.match(dashboardTemplate, /발송 성공률/);
  assert.match(dashboardTemplate, /발송 실패율/);
  assert.match(dashboardTemplate, /점검 필요/);
  assert.match(dashboardTemplate, /delivery-alert/);
  assert.match(dashboardTemplate, /상태별 알림/);
  assert.match(dashboardTemplate, /최근 실패/);
  assert.doesNotMatch(dashboardTemplate, /deviceToken/);
  assert.match(operatorPushNotificationReportTemplate, /운영기관 알림 발송 현황/);
  assert.match(operatorPushNotificationReportTemplate, /읽기 전용 리포트/);
  assert.match(operatorPushNotificationReportTemplate, /전체 알림/);
  assert.match(operatorPushNotificationReportTemplate, /상태별 발송 현황/);
  assert.match(operatorPushNotificationReportTemplate, /최근 실패 안내/);
  assert.doesNotMatch(
    operatorPushNotificationReportTemplate,
    /<form|_csrf|notificationId|userId|deviceToken|\/admin\/notifications/,
  );
  assert.match(security, /securityMatcher\("\/admin\/\*\*"\)/);
});

test("백엔드 시설 상태 변경 알림은 즐겨찾기와 푸시 outbox 경계를 따른다", () => {
  const useCase = read("backend/src/main/java/com/easysubway/notification/application/port/in/FacilityStatusAlertUseCase.java");
  const command = read("backend/src/main/java/com/easysubway/notification/application/port/in/FacilityStatusChangedAlertCommand.java");
  const service = read("backend/src/main/java/com/easysubway/notification/application/service/FacilityStatusAlertService.java");
  const facilityTargetPort = read(
    "backend/src/main/java/com/easysubway/favorite/application/port/out/LoadFavoriteFacilityAlertTargetPort.java",
  );
  const stationTargetPort = read(
    "backend/src/main/java/com/easysubway/favorite/application/port/out/LoadFavoriteStationAlertTargetPort.java",
  );
  const routeTargetPort = read(
    "backend/src/main/java/com/easysubway/favorite/application/port/out/LoadFavoriteRouteAlertTargetPort.java",
  );
  const reportService = read("backend/src/main/java/com/easysubway/report/application/service/FacilityReportService.java");
  const transitService = read("backend/src/main/java/com/easysubway/transit/application/service/TransitMasterService.java");

  assert.match(useCase, /interface FacilityStatusAlertUseCase/);
  assert.match(useCase, /alertFacilityStatusChanged/);
  assert.match(command, /record FacilityStatusChangedAlertCommand/);
  assert.match(command, /String facilityId/);
  assert.match(command, /AccessibilityFacilityStatus status/);
  assert.match(facilityTargetPort, /interface LoadFavoriteFacilityAlertTargetPort/);
  assert.match(stationTargetPort, /interface LoadFavoriteStationAlertTargetPort/);
  assert.match(routeTargetPort, /interface LoadFavoriteRouteAlertTargetPort/);
  assert.match(service, /implements FacilityStatusAlertUseCase/);
  assert.match(service, /LoadTransitMasterPort/);
  assert.match(service, /LoadFavoriteFacilityAlertTargetPort/);
  assert.match(service, /LoadFavoriteStationAlertTargetPort/);
  assert.match(service, /LoadFavoriteRouteAlertTargetPort/);
  assert.match(service, /PushNotificationDispatchUseCase/);
  assert.match(service, /new LinkedHashSet<String>\(\)/);
  assert.match(service, /PushNotificationType\.FAVORITE_STATION_FACILITY/);
  assert.match(service, /PushNotificationType\.FAVORITE_ROUTE_FACILITY/);
  assert.doesNotMatch(service, /\.distinct\(\)/);
  assert.doesNotMatch(service, /filter\(Station::active\)/);
  assert.match(reportService, /FacilityStatusAlertUseCase/);
  assert.match(reportService, /FacilityStatusChangedAlertCommand/);
  assert.match(reportService, /isFacilityStatusChanged/);
  assert.match(reportService, /alertFacilityStatusChanged/);
  assert.match(transitService, /FacilityStatusAlertUseCase/);
  assert.match(transitService, /FacilityStatusChangedAlertCommand/);
  assert.match(transitService, /facility\.status\(\) != command\.status\(\)/);
  assert.match(transitService, /alertFacilityStatusChanged/);
});

test("백엔드 신고 처리 결과 알림은 신고 서비스와 푸시 outbox 경계를 따른다", () => {
  const useCase = read("backend/src/main/java/com/easysubway/notification/application/port/in/ReportStatusAlertUseCase.java");
  const command = read("backend/src/main/java/com/easysubway/notification/application/port/in/ReportStatusChangedAlertCommand.java");
  const service = read("backend/src/main/java/com/easysubway/notification/application/service/ReportStatusAlertService.java");
  const reportService = read("backend/src/main/java/com/easysubway/report/application/service/FacilityReportService.java");

  assert.match(useCase, /interface ReportStatusAlertUseCase/);
  assert.match(useCase, /alertReportStatusChanged/);
  assert.match(command, /record ReportStatusChangedAlertCommand/);
  assert.match(command, /String userId/);
  assert.match(command, /String reportId/);
  assert.match(command, /FacilityReportStatus status/);
  assert.match(service, /implements ReportStatusAlertUseCase/);
  assert.match(service, /PushNotificationDispatchUseCase/);
  assert.match(service, /PushNotificationType\.REPORT_STATUS/);
  assert.match(service, /case ACCEPTED/);
  assert.match(service, /case REJECTED/);
  assert.match(service, /case DUPLICATE/);
  assert.match(service, /case UNDER_REVIEW/);
  assert.match(service, /case RESOLVED/);
  assert.match(service, /case SUBMITTED/);
  assert.match(reportService, /ReportStatusAlertUseCase/);
  assert.match(reportService, /ReportStatusChangedAlertCommand/);
  assert.match(reportService, /report\.status\(\) != saved\.status\(\)/);
  assert.match(reportService, /catch \(RuntimeException exception\)/);
  assert.match(reportService, /alertReportStatusChanged/);
});

test("백엔드 데이터 수집 배치는 관리자 API와 Spring Batch 경계를 따른다", () => {
  const buildGradle = read("backend/build.gradle");
  const application = read("backend/src/main/resources/application.yml");
  const applicationDev = read("backend/src/main/resources/application-dev.yml");
  const applicationProd = read("backend/src/main/resources/application-prod.yml");
  const batchPostgresSchema = read("backend/src/main/resources/db/migration/postgresql/V1__baseline_schema.sql");
  const run = read("backend/src/main/java/com/easysubway/collection/domain/DataCollectionRun.java");
  const source = read("backend/src/main/java/com/easysubway/collection/domain/DataCollectionSource.java");
  const status = read("backend/src/main/java/com/easysubway/collection/domain/DataCollectionStatus.java");
  const invalidCollection = read("backend/src/main/java/com/easysubway/collection/domain/InvalidDataCollectionException.java");
  const useCase = read("backend/src/main/java/com/easysubway/collection/application/port/in/DataCollectionUseCase.java");
  const command = read("backend/src/main/java/com/easysubway/collection/application/port/in/RunDataCollectionCommand.java");
  const loadRunPort = read("backend/src/main/java/com/easysubway/collection/application/port/out/LoadDataCollectionRunPort.java");
  const saveRunPort = read("backend/src/main/java/com/easysubway/collection/application/port/out/SaveDataCollectionRunPort.java");
  const service = read("backend/src/main/java/com/easysubway/collection/application/service/DataCollectionService.java");
  const recorder = read("backend/src/main/java/com/easysubway/collection/application/service/DataCollectionRunRecorder.java");
  const repository = read("backend/src/main/java/com/easysubway/collection/adapter/out/persistence/InMemoryDataCollectionRunRepository.java");
  const jdbcRepository = read(
    "backend/src/main/java/com/easysubway/collection/adapter/out/persistence/JdbcDataCollectionRunRepository.java",
  );
  const controller = read("backend/src/main/java/com/easysubway/collection/adapter/in/web/DataCollectionController.java");
  const adminController = read("backend/src/main/java/com/easysubway/collection/adapter/in/web/DataCollectionAdminPageController.java");
  const adminTemplate = read("backend/src/main/resources/templates/admin/collections/list.html");
  const batchConfig = read("backend/src/main/java/com/easysubway/collection/adapter/out/batch/TransitMasterCollectionBatchConfig.java");
  const security = read("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java");

  assert.match(buildGradle, /spring-boot-starter-batch/);
  assert.match(buildGradle, /spring-boot-starter-validation/);
  assert.match(buildGradle, /spring-batch-test/);
  assert.match(buildGradle, /runtimeOnly 'com\.h2database:h2'/);
  assert.doesNotMatch(buildGradle, /developmentOnly 'com\.h2database:h2'/);
  assert.match(application, /batch:[\s\S]*job:[\s\S]*enabled: false/);
  assert.doesNotMatch(application, /jdbc:h2:mem:easysubway/);
  assert.match(applicationDev, /jdbc:h2:mem:easysubway-\$\{random\.uuid\}/);
  assert.match(applicationProd, /datasource:[\s\S]*url: \$\{EASYSUBWAY_DATASOURCE_URL\}/);
  assert.match(applicationProd, /driver-class-name: org\.postgresql\.Driver/);
  assert.match(applicationProd, /sql:[\s\S]*init:[\s\S]*mode: never/);
  assert.match(applicationProd, /flyway:[\s\S]*enabled: true/);
  assert.match(applicationProd, /locations: classpath:db\/migration\/postgresql/);
  assert.match(applicationProd, /batch:[\s\S]*jdbc:[\s\S]*initialize-schema: never/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS BATCH_JOB_INSTANCE/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS BATCH_JOB_EXECUTION/);
  assert.match(batchPostgresSchema, /CREATE SEQUENCE IF NOT EXISTS BATCH_JOB_SEQ/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS data_collection_runs/);
  assert.match(batchPostgresSchema, /run_id VARCHAR\(80\) NOT NULL PRIMARY KEY/);
  assert.match(batchPostgresSchema, /retryable BOOLEAN NOT NULL DEFAULT FALSE/);
  assert.match(batchPostgresSchema, /operator_action VARCHAR\(500\) NOT NULL DEFAULT/);
  assert.match(batchPostgresSchema, /ALTER TABLE data_collection_runs[\s\S]*ADD COLUMN IF NOT EXISTS retryable BOOLEAN NOT NULL DEFAULT FALSE/);
  assert.match(batchPostgresSchema, /ALTER TABLE data_collection_runs[\s\S]*ADD COLUMN IF NOT EXISTS operator_action VARCHAR\(500\) NOT NULL DEFAULT/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_data_collection_runs_started_at/);
  assert.match(run, /record DataCollectionRun/);
  assert.match(run, /requestedBy/);
  assert.match(run, /collectedCount/);
  assert.match(run, /retryable/);
  assert.match(run, /operatorAction/);
  assert.match(run, /status == DataCollectionStatus\.COMPLETED[\s\S]*completedAt == null/);
  assert.match(run, /status == DataCollectionStatus\.FAILED[\s\S]*failureMessage/);
  assert.match(run, /status != DataCollectionStatus\.FAILED && retryable/);
  assert.match(source, /TRANSIT_MASTER/);
  assert.match(status, /RUNNING/);
  assert.match(status, /COMPLETED/);
  assert.match(status, /FAILED/);
  assert.match(invalidCollection, /extends InvalidRequestException/);
  assert.match(invalidCollection, /Throwable cause/);
  assert.match(useCase, /interface DataCollectionUseCase/);
  assert.match(useCase, /runCollection/);
  assert.match(useCase, /getLatestCompletedRun\(DataCollectionSource source\)/);
  assert.match(useCase, /listRecentRuns/);
  assert.match(command, /record RunDataCollectionCommand/);
  assert.match(loadRunPort, /interface LoadDataCollectionRunPort/);
  assert.match(loadRunPort, /loadLatestCompletedRun\(DataCollectionSource source\)/);
  assert.match(saveRunPort, /interface SaveDataCollectionRunPort/);
  assert.match(service, /implements DataCollectionUseCase/);
  assert.match(service, /JobLauncher/);
  assert.match(service, /transitMasterCollectionJob/);
  assert.match(service, /InvalidDataCollectionException\("데이터 수집 배치를 실행하지 못했습니다\.", exception\)/);
  assert.match(service, /loadRun\(runId\)/);
  assert.match(service, /loadLatestCompletedRun\(source\)/);
  assert.match(recorder, /LoadTransitMasterPort/);
  assert.match(recorder, /recordTransitMasterRun/);
  assert.match(recorder, /catch \(RuntimeException exception\)/);
  assert.match(recorder, /DataCollectionStatus\.FAILED/);
  assert.match(recorder, /COMPLETED_OPERATOR_ACTION/);
  assert.match(recorder, /FAILED_OPERATOR_ACTION/);
  assert.match(repository, /implements[\s\S]*LoadDataCollectionRunPort[\s\S]*SaveDataCollectionRunPort/);
  assert.match(repository, /@Profile\("!prod"\)/);
  assert.match(repository, /loadRun\(String runId\)/);
  assert.match(repository, /loadLatestCompletedRun\(DataCollectionSource source\)/);
  assert.match(jdbcRepository, /@Profile\("prod"\)/);
  assert.match(jdbcRepository, /implements[\s\S]*LoadDataCollectionRunPort[\s\S]*SaveDataCollectionRunPort/);
  assert.match(jdbcRepository, /JdbcTemplate/);
  assert.match(jdbcRepository, /INSERT INTO data_collection_runs/);
  assert.match(jdbcRepository, /retryable/);
  assert.match(jdbcRepository, /operator_action/);
  assert.match(jdbcRepository, /WHERE source = \?/);
  assert.match(jdbcRepository, /ORDER BY completed_at DESC, run_id DESC/);
  assert.match(jdbcRepository, /ORDER BY started_at DESC, run_id DESC/);
  assert.match(controller, /@GetMapping\("\/admin\/data-sources"\)/);
  assert.match(controller, /@PostMapping\("\/admin\/data-sources\/\{dataSourceId\}\/sync"\)/);
  assert.match(controller, /dataCollectionSource\(String dataSourceId\)/);
  assert.match(controller, /InvalidDataCollectionException\("알 수 없는 데이터 소스입니다\."/);
  assert.match(controller, /record DataCollectionSourceResponse/);
  assert.match(controller, /String syncPath/);
  assert.match(controller, /@PostMapping\("\/admin\/data-collections\/runs"\)/);
  assert.match(controller, /@GetMapping\("\/admin\/data-collections\/runs"\)/);
  assert.match(controller, /@Valid @RequestBody RunDataCollectionRequest/);
  assert.match(controller, /@NotNull\(message = "\{validation\.collection\.source\.required\}"\)/);
  assert.match(controller, /Principal principal/);
  assert.match(controller, /boolean retryable/);
  assert.match(controller, /String operatorAction/);
  assert.match(adminController, /retryableLabel/);
  assert.match(adminTemplate, />재시도</);
  assert.match(adminTemplate, />다음 행동</);
  assert.match(batchConfig, /new JobBuilder\(JOB_NAME, jobRepository\)/);
  assert.match(batchConfig, /new StepBuilder\(STEP_NAME, jobRepository\)/);
  assert.match(batchConfig, /DataCollectionRunRecorder/);
  assert.doesNotMatch(batchConfig, /getOrDefault\("requestedBy"/);
  assert.match(security, /securityMatcher\("\/admin\/\*\*"\)/);
});

test("데이터 소스 원본 archive는 로컬 전용 산출물 기준선을 제공한다", () => {
  const batchPostgresSchema = read("backend/src/main/resources/db/migration/postgresql/V1__baseline_schema.sql");
  const archiveScript = read("tools/ops/data-source-raw-archive.sh");

  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS data_source_raw_archives/);
  assert.match(batchPostgresSchema, /archive_id VARCHAR\(120\) NOT NULL PRIMARY KEY/);
  assert.match(batchPostgresSchema, /run_id VARCHAR\(80\) NOT NULL/);
  assert.match(batchPostgresSchema, /source VARCHAR\(40\) NOT NULL/);
  assert.match(batchPostgresSchema, /source_url VARCHAR\(1000\) NOT NULL/);
  assert.match(batchPostgresSchema, /storage_uri VARCHAR\(1000\) NOT NULL/);
  assert.match(batchPostgresSchema, /payload_sha256 VARCHAR\(64\) NOT NULL/);
  assert.match(batchPostgresSchema, /captured_at TIMESTAMP NOT NULL/);
  assert.match(batchPostgresSchema, /FOREIGN KEY \(run_id\) REFERENCES data_collection_runs\(run_id\)/);
  assert.match(batchPostgresSchema, /ON DELETE RESTRICT ON UPDATE CASCADE/);
  assert.match(batchPostgresSchema, /CONSTRAINT chk_data_source_raw_archives_source/);
  assert.match(batchPostgresSchema, /CONSTRAINT chk_data_source_raw_archives_sha256/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_data_source_raw_archives_run/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_data_source_raw_archives_source_captured/);

  assert.match(archiveScript, /set -euo pipefail/);
  assert.match(archiveScript, /EASYSUBWAY_ENV_FILE:-\$\{ROOT_DIR\}\/\.env\.example/);
  assert.match(archiveScript, /EASYSUBWAY_DATA_SOURCE_ARCHIVE_DIR:-\$\{ROOT_DIR\}\/\.codex\/backups\/data-sources/);
  assert.match(archiveScript, /umask 077/);
  assert.match(archiveScript, /chmod 700 "\$\{BACKUP_DIR\}"/);
  assert.match(archiveScript, /mktemp -d "\$\{BACKUP_DIR\}\/easysubway-data-sources-\$\{timestamp\}\.XXXXXX"/);
  assert.match(archiveScript, /collection_runs_file="\$\{run_dir\}\/collection-runs\.csv"/);
  assert.match(archiveScript, /raw_archives_file="\$\{run_dir\}\/raw-archives\.csv"/);
  assert.match(archiveScript, /stream_file="\$\{run_dir\}\/archive-stream\.txt"/);
  assert.match(archiveScript, /psql -v ON_ERROR_STOP=1 -A -t -U "\$POSTGRES_USER" "\$POSTGRES_DB"/);
  assert.match(archiveScript, /BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY/);
  assert.match(archiveScript, /SELECT '__EASYSUBWAY_COLLECTION_RUNS__'/);
  assert.match(archiveScript, /SELECT '__EASYSUBWAY_RAW_ARCHIVES__'/);
  assert.match(archiveScript, /COMMIT/);
  assert.match(archiveScript, /awk -v collection_runs_file/);
  assert.match(archiveScript, /FROM data_collection_runs/);
  assert.match(archiveScript, /FROM data_source_raw_archives/);
  assert.match(archiveScript, /TO STDOUT WITH \(FORMAT csv, HEADER true\)/);
  assert.match(archiveScript, /ORDER BY started_at DESC, run_id ASC/);
  assert.match(archiveScript, /ORDER BY captured_at DESC, archive_id ASC/);
  assert.match(archiveScript, /printf 'data source archive written: %s\\n' "\$\{run_dir\}"/);
});

test("현장 검증 기준선은 세션과 항목을 관리자 API로 추적한다", () => {
  const batchPostgresSchema = read("backend/src/main/resources/db/migration/postgresql/V1__baseline_schema.sql");
  const session = read("backend/src/main/java/com/easysubway/field/domain/FieldVerificationSession.java");
  const item = read("backend/src/main/java/com/easysubway/field/domain/FieldVerificationItem.java");
  const history = read("backend/src/main/java/com/easysubway/field/domain/FieldVerificationChangeHistory.java");
  const itemType = read("backend/src/main/java/com/easysubway/field/domain/FieldVerificationItemType.java");
  const status = read("backend/src/main/java/com/easysubway/field/domain/FieldVerificationStatus.java");
  const useCase = read("backend/src/main/java/com/easysubway/field/application/port/in/FieldVerificationUseCase.java");
  const historyRepositoryPort = read("backend/src/main/java/com/easysubway/field/application/port/out/FieldVerificationChangeHistoryRepository.java");
  const inMemoryHistoryRepository = read("backend/src/main/java/com/easysubway/field/adapter/out/persistence/InMemoryFieldVerificationChangeHistoryRepository.java");
  const jdbcHistoryRepository = read("backend/src/main/java/com/easysubway/field/adapter/out/persistence/JdbcFieldVerificationChangeHistoryRepository.java");
  const service = read("backend/src/main/java/com/easysubway/field/application/service/FieldVerificationService.java");
  const controller = read("backend/src/main/java/com/easysubway/field/adapter/in/web/FieldVerificationAdminController.java");
  const security = read("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java");

  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS field_verification_sessions/);
  assert.match(batchPostgresSchema, /session_id VARCHAR\(120\) NOT NULL PRIMARY KEY/);
  assert.match(batchPostgresSchema, /station_id VARCHAR\(120\) NOT NULL/);
  assert.match(batchPostgresSchema, /verified_at DATE NOT NULL/);
  assert.match(batchPostgresSchema, /verified_by VARCHAR\(120\) NOT NULL/);
  assert.match(batchPostgresSchema, /CONSTRAINT chk_field_verification_sessions_status/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_field_verification_sessions_station/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS field_verification_items/);
  assert.match(batchPostgresSchema, /item_type VARCHAR\(40\) NOT NULL/);
  assert.match(batchPostgresSchema, /FOREIGN KEY \(session_id\) REFERENCES field_verification_sessions\(session_id\)/);
  assert.match(batchPostgresSchema, /CONSTRAINT chk_field_verification_items_type/);
  assert.match(batchPostgresSchema, /CONSTRAINT chk_field_verification_items_status/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_field_verification_items_session/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS field_verification_change_history/);
  assert.match(batchPostgresSchema, /history_id VARCHAR\(120\) NOT NULL PRIMARY KEY/);
  assert.match(batchPostgresSchema, /previous_status VARCHAR\(40\) NOT NULL/);
  assert.match(batchPostgresSchema, /new_status VARCHAR\(40\) NOT NULL/);
  assert.match(batchPostgresSchema, /changed_by VARCHAR\(120\) NOT NULL/);
  assert.match(batchPostgresSchema, /changed_at TIMESTAMP NOT NULL/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_field_verification_change_history_station/);

  assert.match(session, /record FieldVerificationSession/);
  assert.match(session, /List<FieldVerificationItem> items/);
  assert.match(item, /record FieldVerificationItem/);
  assert.match(history, /record FieldVerificationChangeHistory/);
  assert.match(history, /FieldVerificationStatus previousStatus/);
  assert.match(history, /FieldVerificationStatus newStatus/);
  assert.match(history, /LocalDateTime changedAt/);
  assert.match(itemType, /EXIT\("출구"\)/);
  assert.match(itemType, /PLATFORM_TRANSFER\("승강장\/환승 동선"\)/);
  assert.match(status, /PLANNED/);
  assert.match(status, /IN_PROGRESS/);
  assert.match(status, /VERIFIED/);
  assert.match(status, /NEEDS_RECHECK/);
  assert.match(useCase, /FieldVerificationSession getStationVerification\(String stationId\)/);
  assert.match(useCase, /List<FieldVerificationSession> listStationVerifications\(\)/);
  assert.match(useCase, /FieldVerificationSession updateItemStatus\(UpdateFieldVerificationItemStatusCommand command\)/);
  assert.match(useCase, /List<FieldVerificationChangeHistory> listStationChangeHistory\(String stationId\)/);
  assert.match(historyRepositoryPort, /void save\(FieldVerificationChangeHistory history\)/);
  assert.match(historyRepositoryPort, /List<FieldVerificationChangeHistory> listByStationId\(String stationId\)/);
  assert.match(inMemoryHistoryRepository, /@Repository\s+@Profile\("!prod"\)/);
  assert.match(inMemoryHistoryRepository, /implements FieldVerificationChangeHistoryRepository/);
  assert.match(jdbcHistoryRepository, /@Repository\s+@Profile\("prod"\)/);
  assert.match(jdbcHistoryRepository, /JdbcTemplate/);
  assert.match(jdbcHistoryRepository, /INSERT INTO field_verification_change_history/);
  assert.match(jdbcHistoryRepository, /ORDER BY changed_at DESC, history_id ASC/);
  assert.match(service, /SANGNOKSU_STATION_ID = "station-sangnoksu"/);
  assert.doesNotMatch(service, /historiesByStationId/);
  assert.match(service, /FieldVerificationChangeHistoryRepository/);
  assert.match(service, /field-verification-sangnoksu-2026-06/);
  assert.match(service, /SADANG_STATION_ID = "station-sadang"/);
  assert.match(service, /field-verification-sadang-2026-06/);
  assert.match(service, /주요 환승역 현장 검증 확대 기준선/);
  assert.match(service, /FieldVerificationItemType\.EXIT/);
  assert.match(service, /FieldVerificationItemType\.ELEVATOR/);
  assert.match(service, /FieldVerificationItemType\.ESCALATOR/);
  assert.match(service, /FieldVerificationItemType\.RESTROOM/);
  assert.match(service, /FieldVerificationItemType\.PLATFORM_TRANSFER/);
  assert.match(controller, /@GetMapping\("\/admin\/field-verifications\/stations"\)/);
  assert.match(controller, /listStationVerifications\(\)/);
  assert.match(controller, /@GetMapping\("\/admin\/field-verifications\/stations\/\{stationId\}"\)/);
  assert.match(controller, /@GetMapping\("\/admin\/field-verifications\/stations\/\{stationId\}\/export\.csv"\)/);
  assert.match(controller, /@PatchMapping\("\/admin\/field-verifications\/stations\/\{stationId\}\/items\/\{itemId\}\/status"\)/);
  assert.match(controller, /@GetMapping\("\/admin\/field-verifications\/stations\/\{stationId\}\/history"\)/);
  assert.match(controller, /Principal principal/);
  assert.match(controller, /UpdateFieldVerificationItemStatusRequest/);
  assert.match(controller, /TEXT_CSV_UTF8/);
  assert.match(controller, /HttpHeaders\.CONTENT_DISPOSITION/);
  assert.match(controller, /easysubway-field-verification-/);
  assert.match(controller, /sessionId,stationId,stationName,verifiedAt,verifiedBy,sessionStatus,itemType,itemLabel,targetName,itemStatus,note/);
  assert.match(controller, /FieldVerificationItemType/);
  assert.match(controller, /csvValue/);
  assert.match(controller, /safeFilenameStationId/);
  assert.match(controller, /replaceAll\("\[\^A-Za-z0-9_-\]"/);
  assert.match(controller, /escapeSpreadsheetFormula/);
  assert.match(controller, /first == '=' \|\| first == '\+' \|\| first == '-'/);
  assert.match(controller, /ApiResponse<FieldVerificationView>/);
  assert.match(controller, /record FieldVerificationItemView/);
  assert.match(controller, /record FieldVerificationChangeHistoryView/);
  assert.match(security, /securityMatcher\("\/admin\/\*\*"\)/);
});

test("현장 검증 세션 저장소는 운영/비운영 저장소 경계를 분리한다", () => {
  const sessionRepositoryPort = read("backend/src/main/java/com/easysubway/field/application/port/out/FieldVerificationSessionRepository.java");
  const inMemorySessionRepository = read("backend/src/main/java/com/easysubway/field/adapter/out/persistence/InMemoryFieldVerificationSessionRepository.java");
  const jdbcSessionRepository = read("backend/src/main/java/com/easysubway/field/adapter/out/persistence/JdbcFieldVerificationSessionRepository.java");
  const service = read("backend/src/main/java/com/easysubway/field/application/service/FieldVerificationService.java");
  const profileTest = read("backend/src/test/java/com/easysubway/common/persistence/InMemoryRepositoryProfileTest.java");

  assert.match(sessionRepositoryPort, /List<FieldVerificationSession> listAll\(\)/);
  assert.match(sessionRepositoryPort, /Optional<FieldVerificationSession> findByStationId\(String stationId\)/);
  assert.match(sessionRepositoryPort, /void save\(FieldVerificationSession session\)/);
  assert.match(inMemorySessionRepository, /@Repository\s+@Profile\("!prod"\)/);
  assert.match(inMemorySessionRepository, /implements FieldVerificationSessionRepository/);
  assert.match(inMemorySessionRepository, /LinkedHashMap/);
  assert.match(jdbcSessionRepository, /@Repository\s+@Profile\("prod"\)/);
  assert.match(jdbcSessionRepository, /ROW_NUMBER\(\) OVER/);
  assert.match(jdbcSessionRepository, /PARTITION BY station_id/);
  assert.match(jdbcSessionRepository, /INSERT INTO field_verification_sessions/);
  assert.match(jdbcSessionRepository, /ON CONFLICT \(session_id\) DO UPDATE/);
  assert.match(jdbcSessionRepository, /station_id = EXCLUDED\.station_id/);
  assert.match(jdbcSessionRepository, /INSERT INTO field_verification_items/);
  assert.match(jdbcSessionRepository, /ON CONFLICT \(item_id\) DO UPDATE/);
  assert.match(jdbcSessionRepository, /session_id = EXCLUDED\.session_id/);
  assert.doesNotMatch(jdbcSessionRepository, /DuplicateKeyException/);
  assert.match(jdbcSessionRepository, /@Transactional\s+public void save\(FieldVerificationSession session\)/);
  assert.match(jdbcSessionRepository, /ORDER BY verified_at DESC, station_id DESC, session_id ASC/);
  assert.match(jdbcSessionRepository, /WHEN 'EXIT' THEN 1/);
  assert.match(jdbcSessionRepository, /WHEN 'PLATFORM_TRANSFER' THEN 5/);
  assert.match(jdbcSessionRepository, /END ASC, item_id ASC/);
  assert.match(service, /FieldVerificationSessionRepository/);
  assert.match(service, /sessionRepository\.save/);
  assert.match(service, /sessionRepository\.findByStationId/);
  assert.doesNotMatch(service, /Map<String, FieldVerificationSession>/);
  assert.doesNotMatch(service, /sessionsByStationId/);
  assert.match(profileTest, /InMemoryFieldVerificationSessionRepository/);
});

test("백엔드 데이터 품질 요약은 관리자 API와 헥사고날 경계를 따른다", () => {
  const summary = read("backend/src/main/java/com/easysubway/quality/domain/DataQualitySummary.java");
  const useCase = read("backend/src/main/java/com/easysubway/quality/application/port/in/DataQualityUseCase.java");
  const service = read("backend/src/main/java/com/easysubway/quality/application/service/DataQualityService.java");
  const controller = read("backend/src/main/java/com/easysubway/quality/adapter/in/web/DataQualityController.java");
  const adminController = read("backend/src/main/java/com/easysubway/quality/adapter/in/web/DataQualityAdminPageController.java");
  const adminTemplate = read("backend/src/main/resources/templates/admin/quality/dashboard.html");
  const security = read("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java");

  assert.match(summary, /record DataQualitySummary/);
  assert.match(summary, /stationQualityCounts/);
  assert.match(summary, /exitConfidenceCounts/);
  assert.match(summary, /facilityConfidenceCounts/);
  assert.match(summary, /needsVerificationFacilityCount/);
  assert.match(summary, /delayedFacilityStatusCount/);
  assert.match(summary, /delayedFacilityStatusCounts/);
  assert.match(summary, /stationAccessibilityScores/);
  assert.match(summary, /accessibilityImprovementPriorities/);
  assert.match(useCase, /interface DataQualityUseCase/);
  assert.match(useCase, /summarizeDataQuality/);
  assert.match(service, /implements DataQualityUseCase/);
  assert.match(service, /LoadTransitMasterPort/);
  assert.match(service, /DataConfidenceLevel\.NEEDS_VERIFICATION/);
  assert.match(service, /AccessibilityFacilityStatus\.UNKNOWN/);
  assert.match(service, /FACILITY_STATUS_DELAY_DAYS = 30/);
  assert.match(service, /IMPROVEMENT_PRIORITY_LIMIT = 5/);
  assert.match(controller, /@GetMapping\("\/admin\/data-quality\/summary"\)/);
  assert.match(controller, /DataQualityUseCase/);
  assert.match(controller, /accessibilityImprovementPriorities/);
  assert.match(adminController, /@GetMapping\("\/admin\/data-quality\/page"\)/);
  assert.match(adminController, /TransitMasterQueryUseCase/);
  assert.match(adminController, /listRegions/);
  assert.match(adminController, /FacilityReportUseCase/);
  assert.match(adminController, /countReportsByStatus/);
  assert.match(adminController, /listRepeatedBrokenReportFacilities/);
  assert.match(adminController, /StationAccessibilityScoreRow/);
  assert.match(adminController, /AccessibilityImprovementPriorityRow/);
  assert.doesNotMatch(adminController, /listReports\(null\)/);
  assert.match(adminController, /isVerifiedReportStatus/);
  assert.match(adminTemplate, /지역별 데이터 품질/);
  assert.match(adminTemplate, /갱신 지연 시설/);
  assert.match(adminTemplate, /시설 상태 갱신 지연/);
  assert.match(adminTemplate, /사용자 제보 검증률/);
  assert.match(adminTemplate, /제보 검증률/);
  assert.match(adminTemplate, /역별 접근성 점수/);
  assert.match(adminTemplate, /접근성 점수/);
  assert.match(adminTemplate, /접근성 개선 우선순위/);
  assert.match(adminTemplate, /우선순위 점수/);
  assert.match(adminTemplate, /반복 고장 신고 시설/);
  assert.match(adminTemplate, /고장 신고 수/);
  assert.match(adminTemplate, /Level 1/);
  assert.match(adminTemplate, /Level 4/);
  assert.doesNotMatch(adminTemplate, /reportId|stationId|exitId|facilityId/);
  assert.match(security, /securityMatcher\("\/admin\/\*\*"\)/);
});

test("백엔드 사용자 활동 현황은 관리자 대시보드와 헥사고날 경계를 따른다", () => {
  const summary = read("backend/src/main/java/com/easysubway/usage/domain/UserActivityDashboardSummary.java");
  const dashboardUseCase = read(
    "backend/src/main/java/com/easysubway/usage/application/port/in/UserActivityDashboardUseCase.java",
  );
  const recordPort = read("backend/src/main/java/com/easysubway/usage/application/port/out/RecordUserActivityPort.java");
  const summarizePort = read(
    "backend/src/main/java/com/easysubway/usage/application/port/out/SummarizeUserActivityPort.java",
  );
  const service = read("backend/src/main/java/com/easysubway/usage/application/service/UserActivityDashboardService.java");
  const repository = read(
    "backend/src/main/java/com/easysubway/usage/adapter/out/persistence/InMemoryUserActivityRepository.java",
  );
  const filter = read("backend/src/main/java/com/easysubway/usage/adapter/in/web/UserActivityTrackingFilter.java");
  const controller = read(
    "backend/src/main/java/com/easysubway/usage/adapter/in/web/UserActivityAdminPageController.java",
  );
  const apiController = read(
    "backend/src/main/java/com/easysubway/usage/adapter/in/web/UserActivityAdminApiController.java",
  );
  const dashboardView = read(
    "backend/src/main/java/com/easysubway/usage/adapter/in/web/UserActivityDashboardView.java",
  );
  const template = read("backend/src/main/resources/templates/admin/usage/activity.html");

  assert.match(summary, /record UserActivityDashboardSummary/);
  assert.match(summary, /totalActiveUsers/);
  assert.match(summary, /DailyUserActivity/);
  assert.match(dashboardUseCase, /interface UserActivityDashboardUseCase/);
  assert.match(dashboardUseCase, /summarizeUserActivity/);
  assert.match(recordPort, /interface RecordUserActivityPort/);
  assert.match(recordPort, /recordUserActivity/);
  assert.match(summarizePort, /interface SummarizeUserActivityPort/);
  assert.match(service, /implements UserActivityDashboardUseCase/);
  assert.match(service, /SUMMARY_DAYS = 7/);
  assert.match(repository, /implements[\s\S]*RecordUserActivityPort[\s\S]*SummarizeUserActivityPort/);
  assert.match(repository, /Map<LocalDate, Set<String>>/);
  assert.match(filter, /extends OncePerRequestFilter/);
  assert.match(filter, /"\/api\/v1\/"/);
  assert.match(filter, /response\.getStatus\(\) < 400/);
  assert.match(controller, /@GetMapping\("\/admin\/usage\/activity\/page"\)/);
  assert.match(controller, /UserActivityDashboardUseCase/);
  assert.match(apiController, /@GetMapping\("\/admin\/usage\/activity\/summary"\)/);
  assert.match(apiController, /ApiResponse<UserActivityDashboardView>/);
  assert.match(dashboardView, /record UserActivityDashboardView/);
  assert.match(dashboardView, /totalApiRequests/);
  assert.match(dashboardView, /apiErrorRatePercent/);
  assert.match(dashboardView, /API_ERROR_ALERT_THRESHOLD_PERCENT = 5/);
  assert.match(dashboardView, /apiErrorAlertLabel/);
  assert.match(dashboardView, /apiErrorAlertDescription/);
  assert.match(dashboardView, /apiErrorAlertClass/);
  assert.match(dashboardView, /DailyUserActivityRow/);
  assert.doesNotMatch(dashboardView, /userId|anonymous-user/);
  assert.match(template, /사용자 활동 현황/);
  assert.match(template, /최근 7일 활성 사용자/);
  assert.match(template, /API 오류율 상태/);
  assert.match(template, /summary\.apiErrorAlertLabel/);
  assert.match(template, /summary\.apiErrorAlertDescription/);
  assert.match(template, /summary\.apiErrorAlertClass/);
  assert.match(template, /일별 활성 사용자/);
  assert.doesNotMatch(template, /userId|anonymous-user/);
});

test("사용자 활동 JDBC 저장소는 운영 프로필에서 활동 지표를 영속화한다", () => {
  const schema = read("backend/src/main/resources/db/migration/postgresql/V1__baseline_schema.sql");
  const repository = read(
    "backend/src/main/java/com/easysubway/usage/adapter/out/persistence/JdbcUserActivityRepository.java",
  );
  const repositoryTest = read(
    "backend/src/test/java/com/easysubway/usage/adapter/out/persistence/JdbcUserActivityRepositoryTest.java",
  );

  assert.match(schema, /CREATE TABLE IF NOT EXISTS user_activity_events/);
  assert.match(schema, /user_id VARCHAR\(120\) NOT NULL/);
  assert.match(schema, /chk_user_activity_events_user_id[\s\S]*CHECK \(char_length\(trim\(user_id\)\) > 0\)/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS api_traffic_events/);
  assert.match(schema, /duration_millis BIGINT NOT NULL/);
  assert.match(schema, /CREATE INDEX IF NOT EXISTS idx_user_activity_events_occurred[\s\S]*ON user_activity_events \(occurred_at DESC, user_id ASC\)/);
  assert.match(schema, /CREATE INDEX IF NOT EXISTS idx_api_traffic_events_occurred[\s\S]*ON api_traffic_events \(occurred_at DESC, status_code ASC\)/);
  assert.match(schema, /chk_api_traffic_events_status_code[\s\S]*CHECK \(status_code BETWEEN 100 AND 599\)/);
  assert.match(schema, /chk_api_traffic_events_duration[\s\S]*CHECK \(duration_millis >= 0\)/);
  assert.match(repository, /@Profile\("prod"\)/);
  assert.match(repository, /implements[\s\S]*RecordUserActivityPort[\s\S]*RecordApiTrafficPort[\s\S]*SummarizeUserActivityPort/);
  assert.match(repository, /USER_ID_MAX_LENGTH = 120/);
  assert.match(repository, /사용자 활동 식별자는 120자 이하여야 합니다\./);
  assert.match(repository, /INSERT INTO user_activity_events/);
  assert.match(repository, /INSERT INTO api_traffic_events/);
  assert.match(repository, /COUNT\(DISTINCT user_id\)/);
  assert.match(repository, /status_code >= 400/);
  assert.match(repositoryTest, /summarizeUserActivityAfterRepositoryRecreation/);
});

test("신고 검수 감사 로그 JDBC 저장소는 운영 프로필에서 검수 이력을 영속화한다", () => {
  const schema = read("backend/src/main/resources/db/migration/postgresql/V1__baseline_schema.sql");
  const repository = read(
    "backend/src/main/java/com/easysubway/report/adapter/out/persistence/JdbcFacilityReportReviewAuditRepository.java",
  );
  const repositoryTest = read(
    "backend/src/test/java/com/easysubway/report/adapter/out/persistence/JdbcFacilityReportReviewAuditRepositoryTest.java",
  );

  assert.match(schema, /CREATE TABLE IF NOT EXISTS facility_report_review_audits/);
  assert.match(schema, /audit_id VARCHAR\(120\) NOT NULL PRIMARY KEY/);
  assert.match(schema, /report_id VARCHAR\(120\) NOT NULL/);
  assert.match(schema, /reviewer_id VARCHAR\(120\) NOT NULL/);
  assert.match(schema, /CONSTRAINT chk_facility_report_review_audits_decision/);
  assert.match(schema, /CHECK \(decision IN \('ACCEPT', 'REJECT', 'MARK_DUPLICATE'\)\)/);
  assert.match(schema, /CONSTRAINT chk_facility_report_review_audits_previous_status/);
  assert.match(schema, /CONSTRAINT chk_facility_report_review_audits_next_status/);
  assert.match(
    schema,
    /CREATE INDEX IF NOT EXISTS idx_facility_report_review_audits_report[\s\S]*ON facility_report_review_audits \(report_id, created_at ASC, audit_id ASC\)/,
  );
  assert.match(repository, /@Profile\("prod"\)/);
  assert.match(repository, /implements[\s\S]*LoadFacilityReportReviewAuditPort[\s\S]*SaveFacilityReportReviewAuditPort/);
  assert.match(repository, /INSERT INTO facility_report_review_audits/);
  assert.match(repository, /WHERE report_id = \?/);
  assert.match(repository, /ORDER BY created_at ASC, audit_id ASC/);
  assert.match(repositoryTest, /loadAuditsByReportIdAfterRepositoryRecreation/);
});

test("백엔드 경로 검색은 헥사고날 API 경계를 따른다", () => {
  const result = read("backend/src/main/java/com/easysubway/route/domain/RouteSearchResult.java");
  const searchSummary = read("backend/src/main/java/com/easysubway/route/domain/RouteSearchDashboardSummary.java");
  const feedbackSummary = read("backend/src/main/java/com/easysubway/route/domain/RouteFeedbackDashboardSummary.java");
  const status = read("backend/src/main/java/com/easysubway/route/domain/RouteSearchStatus.java");
  const warning = read("backend/src/main/java/com/easysubway/route/domain/RouteWarning.java");
  const warningCode = read("backend/src/main/java/com/easysubway/route/domain/RouteWarningCode.java");
  const profileWeight = read("backend/src/main/java/com/easysubway/route/domain/RouteProfileWeight.java");
  const step = read("backend/src/main/java/com/easysubway/route/domain/RouteStep.java");
  const invalidSearch = read("backend/src/main/java/com/easysubway/route/domain/InvalidRouteSearchException.java");
  const routeNotFound = read("backend/src/main/java/com/easysubway/route/domain/RouteNotFoundException.java");
  const searchNotFound = read("backend/src/main/java/com/easysubway/route/domain/RouteSearchNotFoundException.java");
  const useCase = read("backend/src/main/java/com/easysubway/route/application/port/in/RouteSearchUseCase.java");
  const searchDashboardUseCase = read(
    "backend/src/main/java/com/easysubway/route/application/port/in/RouteSearchDashboardUseCase.java",
  );
  const feedbackDashboardUseCase = read(
    "backend/src/main/java/com/easysubway/route/application/port/in/RouteFeedbackDashboardUseCase.java",
  );
  const command = read("backend/src/main/java/com/easysubway/route/application/port/in/SearchRouteCommand.java");
  const loadPort = read("backend/src/main/java/com/easysubway/route/application/port/out/LoadRouteSearchPort.java");
  const savePort = read("backend/src/main/java/com/easysubway/route/application/port/out/SaveRouteSearchPort.java");
  const summarizeSearchPort = read(
    "backend/src/main/java/com/easysubway/route/application/port/out/SummarizeRouteSearchPort.java",
  );
  const summarizeFeedbackPort = read(
    "backend/src/main/java/com/easysubway/route/application/port/out/SummarizeRouteFeedbackPort.java",
  );
  const service = read("backend/src/main/java/com/easysubway/route/application/service/RouteSearchService.java");
  const searchDashboardService = read(
    "backend/src/main/java/com/easysubway/route/application/service/RouteSearchDashboardService.java",
  );
  const feedbackDashboardService = read(
    "backend/src/main/java/com/easysubway/route/application/service/RouteFeedbackDashboardService.java",
  );
  const repository = read("backend/src/main/java/com/easysubway/route/adapter/out/persistence/InMemoryRouteSearchRepository.java");
  const jdbcRepository = read("backend/src/main/java/com/easysubway/route/adapter/out/persistence/JdbcRouteSearchRepository.java");
  const controllerPath = "backend/src/main/java/com/easysubway/route/adapter/in/web/RouteSearchController.java";
  const searchDashboardController = read(
    "backend/src/main/java/com/easysubway/route/adapter/in/web/RouteSearchAdminPageController.java",
  );
  const searchDashboardApiController = read(
    "backend/src/main/java/com/easysubway/route/adapter/in/web/RouteSearchAdminApiController.java",
  );
  const searchDashboardView = read(
    "backend/src/main/java/com/easysubway/route/adapter/in/web/RouteSearchDashboardView.java",
  );
  const feedbackDashboardController = read(
    "backend/src/main/java/com/easysubway/route/adapter/in/web/RouteFeedbackAdminPageController.java",
  );
  const feedbackDashboardApiController = read(
    "backend/src/main/java/com/easysubway/route/adapter/in/web/RouteFeedbackAdminApiController.java",
  );
  const feedbackDashboardAssembler = read(
    "backend/src/main/java/com/easysubway/route/adapter/in/web/RouteFeedbackDashboardAssembler.java",
  );
  const feedbackDashboardView = read(
    "backend/src/main/java/com/easysubway/route/adapter/in/web/RouteFeedbackDashboardView.java",
  );
  const operatorRouteFeedbackReportController = read(
    "backend/src/main/java/com/easysubway/operator/adapter/in/web/OperatorRouteFeedbackReportController.java",
  );
  const operatorRouteFeedbackReportPageController = read(
    "backend/src/main/java/com/easysubway/operator/adapter/in/web/OperatorRouteFeedbackReportPageController.java",
  );
  const searchDashboardTemplate = read("backend/src/main/resources/templates/admin/routes/searches.html");
  const feedbackDashboardTemplate = read("backend/src/main/resources/templates/admin/routes/feedback.html");
  const operatorRouteFeedbackReportTemplate = read(
    "backend/src/main/resources/templates/operator/route-feedback-report.html",
  );
  const batchPostgresSchema = read("backend/src/main/resources/db/migration/postgresql/V1__baseline_schema.sql");

  assert.match(result, /record RouteSearchResult/);
  assert.match(result, /mobilityType/);
  assert.match(result, /blockedReasons/);
  assert.match(searchSummary, /record RouteSearchDashboardSummary/);
  assert.match(searchSummary, /foundCount/);
  assert.match(searchSummary, /blockedCount/);
  assert.match(searchSummary, /MobilityTypeCount/);
  assert.match(searchSummary, /RegionUsageCount/);
  assert.match(searchSummary, /originCount/);
  assert.match(searchSummary, /destinationCount/);
  assert.match(feedbackSummary, /record RouteFeedbackDashboardSummary/);
  assert.match(feedbackSummary, /helpfulCount/);
  assert.match(feedbackSummary, /notHelpfulCount/);
  assert.match(feedbackSummary, /blockedByRealWorldCount/);
  assert.match(feedbackSummary, /recentBlockedFeedbacks/);
  assert.match(feedbackSummary, /RecentBlockedFeedback/);
  assert.match(status, /FOUND/);
  assert.match(status, /BLOCKED/);
  assert.match(warning, /record RouteWarning/);
  assert.match(warningCode, /LOW_DATA_CONFIDENCE/);
  assert.match(profileWeight, /record RouteProfileWeight/);
  assert.match(profileWeight, /MobilityType/);
  assert.match(profileWeight, /blocksStairOnlyAccess/);
  assert.match(profileWeight, /entryGuidance/);
  assert.match(step, /record RouteStep/);
  assert.match(invalidSearch, /extends InvalidRequestException/);
  assert.match(routeNotFound, /extends ResourceNotFoundException/);
  assert.match(searchNotFound, /extends ResourceNotFoundException/);
  assert.match(useCase, /interface RouteSearchUseCase/);
  assert.match(useCase, /searchRoute/);
  assert.match(useCase, /getRouteSearch/);
  assert.match(searchDashboardUseCase, /interface RouteSearchDashboardUseCase/);
  assert.match(searchDashboardUseCase, /summarizeRouteSearches/);
  assert.match(feedbackDashboardUseCase, /interface RouteFeedbackDashboardUseCase/);
  assert.match(feedbackDashboardUseCase, /summarizeRouteFeedbacks/);
  assert.match(command, /record SearchRouteCommand/);
  assert.match(loadPort, /interface LoadRouteSearchPort/);
  assert.match(savePort, /interface SaveRouteSearchPort/);
  assert.match(summarizeSearchPort, /interface SummarizeRouteSearchPort/);
  assert.match(summarizeSearchPort, /summarizeRouteSearches/);
  assert.match(summarizeSearchPort, /loadRouteSearchStationPairsForDashboard/);
  assert.match(summarizeSearchPort, /record RouteSearchStationPair/);
  assert.match(summarizeSearchPort, /loadRouteSearchBlockedReasonsForDashboard/);
  assert.match(summarizeSearchPort, /record RouteSearchBlockedReasons/);
  assert.match(summarizeFeedbackPort, /interface SummarizeRouteFeedbackPort/);
  assert.match(summarizeFeedbackPort, /summarizeRouteFeedbacks/);
  assert.match(service, /implements RouteSearchUseCase/);
  assert.match(service, /LoadTransitMasterPort/);
  assert.match(service, /RouteProfileWeight\.from/);
  assert.match(service, /RouteSearchStatus\.BLOCKED/);
  assert.match(service, /hasStairOnlyAccess/);
  assert.match(service, /routeScore/);
  assert.match(searchDashboardService, /implements RouteSearchDashboardUseCase/);
  assert.match(searchDashboardService, /SummarizeRouteSearchPort/);
  assert.match(searchDashboardService, /LoadTransitMasterPort/);
  assert.match(searchDashboardService, /Station::region/);
  assert.match(searchDashboardService, /RegionUsageCount/);
  assert.match(searchDashboardService, /BlockedReasonCount/);
  assert.match(feedbackDashboardService, /implements RouteFeedbackDashboardUseCase/);
  assert.match(feedbackDashboardService, /SummarizeRouteFeedbackPort/);
  assert.match(repository, /implements[\s\S]*LoadRouteSearchPort[\s\S]*SaveRouteSearchPort[\s\S]*SaveRouteFeedbackPort[\s\S]*SummarizeRouteFeedbackPort[\s\S]*SummarizeRouteSearchPort/);
  assert.match(repository, /@Profile\("!prod"\)/);
  assert.match(jdbcRepository, /@Profile\("prod"\)/);
  assert.match(jdbcRepository, /implements[\s\S]*LoadRouteSearchPort[\s\S]*SaveRouteSearchPort[\s\S]*SaveRouteFeedbackPort[\s\S]*SummarizeRouteFeedbackPort[\s\S]*SummarizeRouteSearchPort[\s\S]*AnonymizeUserRouteFeedbackPort/);
  assert.match(jdbcRepository, /JdbcTemplate/);
  assert.match(jdbcRepository, /INSERT INTO route_search_results/);
  assert.match(jdbcRepository, /INSERT INTO route_feedbacks/);
  assert.match(jdbcRepository, /RouteSearchDashboardSummary summarizeRouteSearches\(\)/);
  assert.match(jdbcRepository, /List<RouteSearchStationPair> loadRouteSearchStationPairsForDashboard\(\)/);
  assert.match(jdbcRepository, /SELECT origin_station_id,\s+destination_station_id/);
  assert.match(jdbcRepository, /List<RouteSearchBlockedReasons> loadRouteSearchBlockedReasonsForDashboard\(\)/);
  assert.match(jdbcRepository, /SELECT blocked_reasons_json/);
  assert.match(jdbcRepository, /GROUP BY status, mobility_type/);
  assert.match(jdbcRepository, /same DB statement snapshot|같은 DB statement snapshot/);
  assert.match(jdbcRepository, /RouteFeedbackDashboardSummary summarizeRouteFeedbacks\(\)/);
  assert.match(jdbcRepository, /SUM\(CASE WHEN rating = 'HELPFUL' THEN 1 ELSE 0 END\)/);
  assert.match(jdbcRepository, /rating = 'BLOCKED_BY_REAL_WORLD'/);
  assert.match(jdbcRepository, /JOIN route_search_results/);
  assert.match(jdbcRepository, /ORDER BY feedback_created_at DESC/);
  assert.match(jdbcRepository, /ON CONFLICT \(route_search_id\) DO UPDATE/);
  assert.match(jdbcRepository, /ON CONFLICT \(feedback_id\) DO UPDATE/);
  assert.match(jdbcRepository, /steps_json/);
  assert.match(jdbcRepository, /warnings_json/);
  assert.match(jdbcRepository, /blocked_reasons_json/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS route_search_results/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS route_feedbacks/);
  assert.match(batchPostgresSchema, /CHECK \(status IN \('FOUND', 'BLOCKED'\)\)/);
  assert.match(batchPostgresSchema, /CHECK \(rating IN \('HELPFUL', 'NOT_HELPFUL', 'BLOCKED_BY_REAL_WORLD'\)\)/);
  assert.equal(existsSync(path.join(root, controllerPath)), false);
  assert.match(searchDashboardController, /@GetMapping\("\/admin\/routes\/searches\/page"\)/);
  assert.match(searchDashboardController, /RouteSearchDashboardUseCase/);
  assert.match(searchDashboardController, /RouteSearchDashboardView\.from\(summary\)/);
  assert.match(searchDashboardApiController, /@RestController/);
  assert.match(searchDashboardApiController, /@GetMapping\("\/admin\/routes\/searches\/summary"\)/);
  assert.match(searchDashboardApiController, /ApiResponse<RouteSearchDashboardView>/);
  assert.match(searchDashboardApiController, /RouteSearchDashboardView\.from\(routeSearchDashboardUseCase\.summarizeRouteSearches\(\)\)/);
  assert.match(searchDashboardView, /record RouteSearchDashboardView/);
  assert.match(searchDashboardView, /blockedRateLabel/);
  assert.match(searchDashboardView, /blockedAlertLabel/);
  assert.match(searchDashboardView, /blockedAlertDescription/);
  assert.match(searchDashboardView, /blockedAlertClass/);
  assert.match(searchDashboardView, /record MobilityTypeCountRow/);
  assert.match(searchDashboardView, /record RegionUsageCountRow/);
  assert.match(searchDashboardView, /record BlockedReasonCountRow/);
  assert.doesNotMatch(searchDashboardView, /routeSearchId|stationId/);
  assert.match(searchDashboardTemplate, /경로 검색 현황/);
  assert.match(searchDashboardTemplate, /전체 검색/);
  assert.match(searchDashboardTemplate, /경로 차단율/);
  assert.match(searchDashboardTemplate, /운영 상태/);
  assert.match(searchDashboardTemplate, /summary\.blockedRateLabel/);
  assert.match(searchDashboardTemplate, /summary\.blockedAlertLabel/);
  assert.match(searchDashboardTemplate, /summary\.blockedAlertDescription/);
  assert.match(searchDashboardTemplate, /이동 프로필별 검색/);
  assert.match(searchDashboardTemplate, /지역별 사용량/);
  assert.match(searchDashboardTemplate, /출발 검색/);
  assert.match(searchDashboardTemplate, /도착 검색/);
  assert.doesNotMatch(searchDashboardTemplate, /routeSearchId/);
  assert.match(feedbackDashboardController, /@GetMapping\("\/admin\/routes\/feedback\/page"\)/);
  assert.match(feedbackDashboardController, /RouteFeedbackDashboardAssembler/);
  assert.match(feedbackDashboardController, /routeFeedbackDashboardAssembler\.assemble\(\)/);
  assert.match(feedbackDashboardApiController, /@RestController/);
  assert.match(feedbackDashboardApiController, /@GetMapping\("\/admin\/routes\/feedback\/summary"\)/);
  assert.match(feedbackDashboardApiController, /ApiResponse<RouteFeedbackDashboardView>/);
  assert.match(feedbackDashboardApiController, /routeFeedbackDashboardAssembler\.assemble\(\)/);
  assert.match(feedbackDashboardAssembler, /RouteFeedbackDashboardUseCase/);
  assert.match(feedbackDashboardAssembler, /summarizeRouteFeedbacks/);
  assert.match(feedbackDashboardAssembler, /recentBlockedFeedbacks/);
  assert.match(feedbackDashboardAssembler, /mobilityTypeLabel/);
  assert.match(feedbackDashboardView, /record RouteFeedbackDashboardView/);
  assert.match(feedbackDashboardView, /record RatingCountRow/);
  assert.match(feedbackDashboardView, /record RecentBlockedFeedbackRow/);
  assert.doesNotMatch(feedbackDashboardView, /routeSearchId|userId|comment/);
  assert.match(operatorRouteFeedbackReportController, /@GetMapping\("\/operator\/api\/route-feedback-report"\)/);
  assert.match(operatorRouteFeedbackReportController, /ApiResponse<RouteFeedbackDashboardView>/);
  assert.match(operatorRouteFeedbackReportController, /routeFeedbackDashboardAssembler\.assemble\(\)/);
  assert.match(operatorRouteFeedbackReportPageController, /@GetMapping\("\/operator\/route-feedback-report\/page"\)/);
  assert.match(operatorRouteFeedbackReportPageController, /RouteFeedbackDashboardAssembler/);
  assert.match(operatorRouteFeedbackReportPageController, /routeFeedbackDashboardAssembler\.assemble\(\)/);
  assert.match(operatorRouteFeedbackReportPageController, /return "operator\/route-feedback-report"/);
  assert.match(feedbackDashboardTemplate, /경로 피드백 현황/);
  assert.match(feedbackDashboardTemplate, /전체 피드백/);
  assert.match(feedbackDashboardTemplate, /평점별 피드백/);
  assert.match(feedbackDashboardTemplate, /최근 현장 차단 신고/);
  assert.match(feedbackDashboardTemplate, /출발역/);
  assert.match(feedbackDashboardTemplate, /도착역/);
  assert.match(feedbackDashboardTemplate, /이동 프로필/);
  assert.doesNotMatch(feedbackDashboardTemplate, /userId/);
  assert.doesNotMatch(feedbackDashboardTemplate, /routeSearchId/);
  assert.doesNotMatch(feedbackDashboardTemplate, /comment/);
  assert.match(operatorRouteFeedbackReportTemplate, /운영기관 이동 불편 신고 분석/);
  assert.match(operatorRouteFeedbackReportTemplate, /읽기 전용 리포트/);
  assert.match(operatorRouteFeedbackReportTemplate, /평점별 피드백/);
  assert.match(operatorRouteFeedbackReportTemplate, /최근 현장 차단 신고/);
  assert.doesNotMatch(operatorRouteFeedbackReportTemplate, /<form|_csrf|routeSearchId|userId|comment|\/admin\/reports/);
});

test("모바일 async lint 기준선은 Future 처리 누락을 analyzer에서 잡는다", () => {
  const analysisOptions = read("apps/mobile/analysis_options.yaml");
  const asyncLintBaseline = readJson("apps/mobile/analysis/async-lint-baseline.json");

  assert.match(analysisOptions, /package:flutter_lints\/flutter\.yaml/);
  assert.match(analysisOptions, /^analyzer:\n  language:\n    strict-casts: true\n    strict-inference: true\n    strict-raw-types: true$/m);
  assert.match(analysisOptions, /^\s{4}unawaited_futures: true$/m);
  assert.match(analysisOptions, /^\s{4}discarded_futures: false # staged in apps\/mobile\/analysis\/async-lint-baseline\.json$/m);
  assert.equal(asyncLintBaseline.schema, "easysubway.mobile_async_lint_baseline.v1");
  assert.deepEqual(asyncLintBaseline.enabledNow, ["unawaited_futures"]);
  assert.equal(asyncLintBaseline.staged.discarded_futures.status, "staged_existing_findings");
  assert.ok(asyncLintBaseline.staged.discarded_futures.findingCount > 0);
  assert.deepEqual(asyncLintBaseline.staged.discarded_futures.target, [
    "convert callback-only Future calls to unawaited() when fire-and-forget is intentional",
    "await Future-returning test matchers and setup operations where order matters",
  ]);
});

test("모바일 스캐폴드는 Flutter Android와 iOS 앱 구조를 가진다", () => {
  const pubspec = read("apps/mobile/pubspec.yaml");
  const analysisOptions = read("apps/mobile/analysis_options.yaml");
  const androidManifest = read("apps/mobile/android/app/src/main/AndroidManifest.xml");
  const androidDebugManifest = read("apps/mobile/android/app/src/debug/AndroidManifest.xml");
  const androidProfileManifest = read("apps/mobile/android/app/src/profile/AndroidManifest.xml");
  const androidBuildGradle = read("apps/mobile/android/app/build.gradle.kts");
  const envExample = read(".env.example");
  const iosInfoPlist = read("apps/mobile/ios/Runner/Info.plist");
  const main = read("apps/mobile/lib/main.dart");
  const appDependencies = read("apps/mobile/lib/app/app_dependencies.dart");
  const authHeaders = read("apps/mobile/lib/auth_headers.dart");
  const secureKeyValueStorage = read("apps/mobile/lib/secure_key_value_storage.dart");
  const userDataDeletion = read("apps/mobile/lib/user_data_deletion.dart");
  const userDataDeletionTest = read("apps/mobile/test/user_data_deletion_test.dart");
  const onboarding = read("apps/mobile/lib/onboarding.dart");
  const onboardingTest = read("apps/mobile/test/onboarding_test.dart");
  const routeSearch = read("apps/mobile/lib/route_search.dart");
  const stationSearch = read("apps/mobile/lib/station_search.dart");
  const stationLineBadges = read("apps/mobile/lib/features/stations/presentation/station_line_badges.dart");
  const stationLine = read("apps/mobile/lib/features/stations/domain/station_line.dart");
  const stationApiRepository = read(
    "apps/mobile/lib/features/stations/data/station_api_repository.dart",
  );
  const mapAdapter = read("apps/mobile/lib/map_adapter.dart");
  const mapAdapterTest = read("apps/mobile/test/map_adapter_test.dart");
  const facilityReport = read("apps/mobile/lib/facility_report.dart");
  const facilityReportTest = read("apps/mobile/test/facility_report_test.dart");
  const notificationSettings = read("apps/mobile/lib/notification_settings.dart");
  const notificationSettingsTest = read("apps/mobile/test/notification_settings_test.dart");
  const widgetTest = read("apps/mobile/test/widget_test.dart");
  const supportAccessInfoTest = read("apps/mobile/test/support_access_info_test.dart");
  const easySubwayAppDefaultsTest = read("apps/mobile/test/easy_subway_app_defaults_test.dart");
  const onboardingAppFlowTest = read("apps/mobile/test/onboarding_app_flow_test.dart");
  const apiClient = read("apps/mobile/lib/core/network/api_client.dart");
  const apiError = read("apps/mobile/lib/core/network/api_error.dart");
  const apiClientTest = read("apps/mobile/test/core/network/api_client_test.dart");
  const accessibilityBaselineTest = read("apps/mobile/test/accessibility_baseline_test.dart");

  assert.ok(existsSync(path.join(root, "apps/mobile/android")));
  assert.ok(existsSync(path.join(root, "apps/mobile/ios")));
  assert.ok(existsSync(path.join(root, "apps/mobile/pubspec.lock")));

  assert.match(pubspec, /^name: easysubway_mobile$/m);
  assert.match(pubspec, /sdk: \^3\./);
  assert.match(pubspec, /flutter_lints:/);
  assert.match(pubspec, /flutter_secure_storage:/);
  assert.match(pubspec, /uses-material-design: true/);
  assert.match(analysisOptions, /package:flutter_lints\/flutter\.yaml/);
  assert.match(analysisOptions, /^analyzer:\n  language:\n    strict-casts: true\n    strict-inference: true\n    strict-raw-types: true$/m);
  assert.match(androidManifest, /android:label="쉬운 지하철"/);
  assert.match(androidManifest, /android:allowBackup="false"/);
  assert.match(androidManifest, /android:fullBackupContent="false"/);
  assert.match(androidManifest, /android:usesCleartextTraffic="false"/);
  assert.match(androidDebugManifest, /xmlns:tools="http:\/\/schemas\.android\.com\/tools"/);
  assert.match(androidDebugManifest, /android:usesCleartextTraffic="true"/);
  assert.match(androidDebugManifest, /tools:replace="android:usesCleartextTraffic"/);
  assert.match(androidProfileManifest, /xmlns:tools="http:\/\/schemas\.android\.com\/tools"/);
  assert.match(androidProfileManifest, /android:usesCleartextTraffic="true"/);
  assert.match(androidProfileManifest, /tools:replace="android:usesCleartextTraffic"/);
  assert.match(androidManifest, /<uses-permission android:name="android\.permission\.INTERNET"\/>/);
  assert.match(androidBuildGradle, /applicationId\s*=\s*"com\.easysubway\.app"/);
  assert.match(androidBuildGradle, /targetSdk\s*=\s*maxOf\(35,\s*flutter\.targetSdkVersion\)/);
  assert.match(androidBuildGradle, /create\("release"\)/);
  assert.doesNotMatch(androidBuildGradle, /signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)/);
  assert.match(androidBuildGradle, /"EASYSUBWAY_ANDROID_KEYSTORE_PATH"/);
  assert.match(androidBuildGradle, /"EASYSUBWAY_ANDROID_STORE_PASSWORD"/);
  assert.match(androidBuildGradle, /"EASYSUBWAY_ANDROID_KEY_ALIAS"/);
  assert.match(androidBuildGradle, /"EASYSUBWAY_ANDROID_KEY_PASSWORD"/);
  assert.match(androidBuildGradle, /providers\.environmentVariable\(name\)/);
  assert.match(androidBuildGradle, /throw GradleException\([\s\S]*Android release signing values are missing:/);
  assert.match(envExample, /^EASYSUBWAY_ANDROID_KEYSTORE_PATH=$/m);
  assert.match(envExample, /^EASYSUBWAY_ANDROID_STORE_PASSWORD=$/m);
  assert.match(envExample, /^EASYSUBWAY_ANDROID_KEY_ALIAS=$/m);
  assert.match(envExample, /^EASYSUBWAY_ANDROID_KEY_PASSWORD=$/m);
  assert.match(iosInfoPlist, /CFBundleDisplayName[\s\S]*?<string>쉬운 지하철<\/string>/);
  assert.match(main, /class EasySubwayApp extends StatelessWidget/);
  assert.match(main, /역 검색/);
  assert.match(main, /길찾기/);
  assert.match(main, /이동 조건/);
  assert.match(main, /알림 설정/);
  assert.match(main, /EASYSUBWAY_ENABLE_PUSH_NOTIFICATIONS/);
  assert.match(main, /defaultValue: false/);
  assert.match(main, /enablePushNotifications/);
  assert.doesNotMatch(`${main}\n${appDependencies}`, /AnonymousAuth|enableAnonymousAuth|anonymousAuth/);
  assert.match(`${main}\n${appDependencies}`, /FavoriteStationApiRepository/);
  assert.match(`${main}\n${appDependencies}`, /NotificationSettingsApiRepository/);
  assert.match(main, /OnboardingScreen/);
  assert.match(main, /initialOnboardingState/);
  assert.match(onboardingAppFlowTest, /첫 실행 앱은 온보딩을 완료한 뒤 홈으로 이동한다/);
  assert.match(onboardingAppFlowTest, /첫 실행 앱은 온보딩에서 위치 권한을 준비할 수 있다/);
  assert.match(onboardingAppFlowTest, /첫 실행 앱은 온보딩에서 알림 권한을 준비할 수 있다/);
  assert.match(onboardingAppFlowTest, /첫 실행 앱은 온보딩 알림 권한 실패 다음 행동을 안내한다/);
  assert.match(onboardingAppFlowTest, /첫 실행 앱은 알림 설정이 꺼진 구성에서 온보딩 알림 권한을 요청하지 않는다/);
  assert.match(onboardingAppFlowTest, /첫 실행 앱은 알림 권한 제공자가 직접 주입되면 온보딩 알림 권한을 요청한다/);
  assert.match(onboardingAppFlowTest, /앱은 저장된 온보딩 설정으로 홈을 바로 보여준다/);
  assert.match(onboardingAppFlowTest, /앱은 온보딩 저장소를 읽지 못하면 다시 설정을 고르게 한다/);
  assert.match(stationSearch, /stationSearchFailureNextAction/);
  assert.match(stationSearch, /역명으로 검색하면 위치 권한 없이도 계속 이용할 수 있습니다\./);
  assert.match(widgetTest, /역명으로 검색하면 위치 권한 없이도 계속 이용할 수 있습니다\./);
  assert.match(main, /initialMobilityType: onboardingResult\?\.profile\.mobilityType/);
  assert.match(main, /initialMobilityType: initialMobilityType/);
  assert.match(main, /_OnboardingPreferenceScope/);
  assert.match(main, /mediaQuery\.textScaler\.clamp\(minScaleFactor: 1\.18\)/);
  assert.match(main, /highContrast:[\s\S]*preferences\.highContrastEnabled \|\| mediaQuery\.highContrast/);
  assert.match(main, /mediaQuery\.boldText/);
  assert.match(main, /_themeForPlatformAccessibility/);
  assert.match(main, /WidgetStateProperty\.resolveWith/);
  assert.match(main, /_themeForPreferences/);
  assert.match(main, /simpleViewEnabled: preferences\.simpleViewEnabled/);
  assert.match(main, /RouteSearchScreen\([\s\S]*simpleViewEnabled: simpleViewEnabled/);
  assert.match(main, /label: '즐겨찾기'/);
  assert.match(main, /FavoriteHomeScreen/);
  assert.match(main, /FavoriteRouteListContent/);
  assert.match(main, /FavoriteStationListContent/);
  assert.match(main, /FavoriteFacilityListContent/);
  assert.match(onboarding, /class OnboardingViewPreferences/);
  assert.match(onboarding, /const OnboardingViewPreferences\.defaults/);
  assert.match(onboarding, /class OnboardingResult/);
  assert.match(onboarding, /class OnboardingState/);
  assert.match(onboarding, /class OnboardingScreen extends StatefulWidget/);
  assert.match(onboarding, /먼저 이동 조건을 골라 주세요/);
  assert.match(onboarding, /보기 설정/);
  assert.match(onboarding, /큰 글자/);
  assert.match(onboarding, /고대비/);
  assert.match(onboarding, /간편 보기/);
  assert.match(onboarding, /onTap: \(\) => onChanged\(!value\)/);
  assert.match(routeSearch, /final String initialMobilityType/);
  assert.match(routeSearch, /final bool simpleViewEnabled/);
  assert.match(routeSearch, /_resolveInitialMobilityType/);
  assert.match(routeSearch, /_selectedMobilityType = widget\.initialMobilityType/);
  assert.match(routeSearch, /_RouteMobilityTypeSummary\([\s\S]*mobilityType: _selectedMobilityType[\s\S]*onChangeRequested: _showMobilityTypePicker/);
  assert.match(routeSearch, /routeSimpleMobilityTypeButton/);
  assert.match(routeSearch, /routeMobilityOption-\$\{option\.mobilityType\}/);
  assert.doesNotMatch(widgetTest, /첫 실행 앱은 온보딩을 완료한 뒤 홈으로 이동한다/);
  assert.match(widgetTest, /온보딩 이동 조건은 경로 검색 기본값으로 이어진다/);
  assert.match(widgetTest, /온보딩 보기 설정은 완료 뒤 홈 UI에 적용된다/);
  assert.match(widgetTest, /MediaQuery\.textScalerOf/);
  assert.match(accessibilityBaselineTest, /모바일 접근성 QA 기준선은 큰 글씨와 고대비 홈 화면을 검증한다/);
  assert.match(accessibilityBaselineTest, /tester\.ensureSemantics\(\)/);
  assert.match(accessibilityBaselineTest, /FakeAccessibilityFeatures\([\s\S]*boldText: true[\s\S]*disableAnimations: true[\s\S]*reduceMotion: true/);
  assert.match(accessibilityBaselineTest, /MediaQuery\.boldTextOf/);
  assert.match(accessibilityBaselineTest, /MediaQuery\.disableAnimationsOf/);
  assert.match(accessibilityBaselineTest, /androidTapTargetGuideline/);
  assert.match(accessibilityBaselineTest, /iOSTapTargetGuideline/);
  assert.match(accessibilityBaselineTest, /labeledTapTargetGuideline/);
  assert.match(accessibilityBaselineTest, /textContrastGuideline/);
  assert.match(onboardingTest, /온보딩은 이동 조건과 보기 설정을 선택한 뒤 완료 결과를 반환한다/);
  assert.match(onboardingTest, /hasTapAction: true/);
  assert.match(authHeaders, /abstract class AuthorizationHeaderProvider/);
  assert.match(authHeaders, /class BasicAuthorizationHeaderProvider implements AuthorizationHeaderProvider/);
  assert.match(authHeaders, /authorizationHeader/);
  assert.match(authHeaders, /invalidateAuthorization/);
  assert.match(secureKeyValueStorage, /abstract interface class SecureKeyValueStorage/);
  assert.match(secureKeyValueStorage, /class FlutterSecureKeyValueStorage implements SecureKeyValueStorage/);
  assert.match(secureKeyValueStorage, /FlutterSecureStorage/);
  assert.match(onboarding, /SecureKeyValueStorage/);
  assert.match(onboarding, /_clearResultAfterReadFailure/);
  assert.match(onboardingTest, /온보딩 저장소는 secure storage 복원 실패 시 저장값을 지운다/);
  assert.match(onboardingTest, /온보딩 저장소는 secure storage 삭제 실패에도 null로 복구한다/);
  assert.match(facilityReport, /SecureKeyValueStorage/);
  assert.match(facilityReport, /_clearTargetAfterReadFailure/);
  assert.match(facilityReportTest, /시설 신고 임시 대상 저장소는 secure storage 복원 실패 시 저장값을 지운다/);
  assert.match(facilityReportTest, /시설 신고 임시 대상 저장소는 secure storage 삭제 실패에도 null로 복구한다/);
  assert.ok(existsSync(path.join(root, "apps/mobile/lib/station_search.dart")));
  assert.match(stationSearch, /features\/stations\/presentation\/station_line_badges\.dart/);
  assert.doesNotMatch(stationSearch, /class StationLineBadges|class StationLineBadge/);
  assert.match(stationLineBadges, /class StationLineBadges extends StatelessWidget/);
  assert.match(stationLineBadges, /class StationLineBadge extends StatelessWidget/);
  assert.match(stationLine, /class StationSearchLine/);
  assert.match(routeSearch, /features\/stations\/presentation\/station_line_badges\.dart/);
  assert.match(stationApiRepository, /typedef FavoriteStationAuthProvider = AuthorizationHeaderProvider/);
  assert.match(stationSearch, /final double\? latitude/);
  assert.match(stationSearch, /final double\? longitude/);
  assert.match(stationSearch, /_optionalDouble\(json, 'latitude'\)/);
  assert.match(stationSearch, /_optionalDouble\(json, 'longitude'\)/);
  assert.doesNotMatch(stationSearch, /import 'core\/network\/api_client\.dart';/);
  assert.doesNotMatch(stationSearch, /class StationSearchApiRepository/);
  assert.match(stationApiRepository, /class StationSearchApiRepository[\s\S]*final ApiClient _apiClient;/);
  assert.match(stationApiRepository, /_apiClient\.getJson\(/);
  assert.doesNotMatch(
    stationApiRepository,
    /class StationSearchApiRepository[\s\S]*?_httpClient[\s\S]*?typedef FavoriteStationAuthProvider/,
  );
  assert.doesNotMatch(stationSearch, /class FavoriteStationApiRepository/);
  assert.match(stationApiRepository, /class FavoriteStationApiRepository[\s\S]*final ApiClient _apiClient;/);
  assert.match(stationApiRepository, /class FavoriteStationApiRepository[\s\S]*_apiClient\.getJson\(/);
  assert.match(stationApiRepository, /class FavoriteStationApiRepository[\s\S]*_apiClient\.putJson\(/);
  assert.match(stationApiRepository, /class FavoriteStationApiRepository[\s\S]*_apiClient\.deleteJson\(/);
  assert.doesNotMatch(
    stationApiRepository,
    /class FavoriteStationApiRepository[\s\S]*?_httpClient/,
  );
  assert.match(stationApiRepository, /HttpStatus\.unauthorized/);
  assert.match(stationApiRepository, /invalidateAuthorization\(\)/);
  assert.match(stationSearch, /package:flutter\/foundation\.dart/);
  assert.match(stationSearch, /const configuredBaseUrl = String\.fromEnvironment\('EASYSUBWAY_API_BASE_URL'\)/);
  assert.match(stationSearch, /isReleaseMode: kReleaseMode/);
  assert.match(stationSearch, /Uri stationApiBaseUriForEnvironment\(/);
  assert.match(stationSearch, /Release API base URL must be configured\./);
  assert.match(stationSearch, /Release API base URL must use HTTPS\./);
  assert.match(stationSearch, /baseUri\.host\.isEmpty/);
  assert.match(stationSearch, /Release API base URL must include a host\./);
  assert.match(stationSearch, /Text\(\s*result\.dataQualityLabel,/);
  assert.match(widgetTest, /expect\(find\.text\('출처 확인 필요'\), findsNothing\);/);
  assert.match(widgetTest, /상록수역, 수도권 4호선, 경의중앙선, 수도권, 기본 정보만 있음/);
  assert.match(read("apps/mobile/test/station_search_test.dart"), /인증 실패 시 인증을 지우고 한 번 재시도한다/);
  assert.match(read("apps/mobile/test/station_search_test.dart"), /릴리즈 빌드는 API 기본 주소를 반드시 설정해야 한다/);
  assert.match(read("apps/mobile/test/station_search_test.dart"), /릴리즈 빌드는 HTTPS API 주소만 사용한다/);
  assert.match(read("apps/mobile/test/station_search_test.dart"), /릴리즈 빌드는 호스트가 없는 API 주소를 거부한다/);
  assert.match(read("apps/mobile/test/station_search_test.dart"), /개발 빌드는 Android 에뮬레이터 로컬 API 주소를 유지한다/);
  assert.match(mapAdapter, /enum MapProviderType/);
  assert.match(mapAdapter, /MapProviderType\.naver => '네이버 지도'/);
  assert.match(mapAdapter, /MapProviderType\.kakao => '카카오 지도'/);
  assert.match(mapAdapter, /const MapProviderConfiguration\.defaults\(\)/);
  assert.match(mapAdapter, /primary = MapProviderType\.naver/);
  assert.match(mapAdapter, /fallbacks = const \[MapProviderType\.kakao\]/);
  assert.match(mapAdapter, /abstract interface class MapAdapter/);
  assert.match(mapAdapter, /class EasySubwayMapAdapter implements MapAdapter/);
  assert.match(mapAdapter, /markersForStationDetail/);
  assert.match(mapAdapter, /_coordinateFrom\(station\.latitude, station\.longitude\)/);
  assert.match(mapAdapter, /_coordinateFrom\(exit\.latitude, exit\.longitude\)/);
  assert.match(mapAdapter, /_coordinateFrom\(facility\.latitude, facility\.longitude\)/);
  assert.match(stationSearch, /EasySubwayMapAdapter\(\)\.markersForStationDetail/);
  assert.match(stationSearch, /지도 위치 목록/);
  assert.match(stationSearch, /지도를 열 수 없어도 아래 위치 목록으로 확인할 수 있습니다\./);
  assert.match(mapAdapterTest, /지도 제공자는 네이버를 기본값으로 두고 카카오를 대체 후보로 둔다/);
  assert.match(mapAdapterTest, /지도 어댑터는 좌표가 있는 역 출구 시설만 쉬운 이름의 마커로 만든다/);
  assert.match(widgetTest, /지도 대체 위치 목록/);
  assert.match(widgetTest, /상록수역 상세 정보[\s\S]*지도 위치/);
  assert.match(widgetTest, /1번 출구, 엘리베이터 연결, 계단 없는 이동 가능[\s\S]*지도 위치/);
  assert.match(facilityReport, /Future<FacilityReportResult> getReport\(String reportId\)/);
  assert.match(facilityReport, /\/api\/v1\/reports\/\$\{Uri\.encodeComponent\(trimmedReportId\)\}/);
  assert.match(facilityReport, /refreshCurrentReport/);
  assert.match(facilityReport, /처리 상태 확인 중/);
  assert.match(facilityReport, /제보 번호/);
  assert.match(facilityReport, /facilityReportRefreshButton/);
  assert.match(facilityReport, /facilityReportFailureNextAction/);
  assert.match(facilityReport, /내용을 확인한 뒤 네트워크 상태를 보고 다시 보내 주세요\./);
  assert.match(facilityReportTest, /접수번호로 처리 상태를 조회한다/);
  assert.match(facilityReportTest, /접수 후 처리 상태를 다시 확인한다/);
  assert.match(widgetTest, /제보 번호 ES-1001, 현재 상태 반영됨/);
  assert.match(widgetTest, /시설 신고 실패는 다음 행동을 쉬운 문구로 안내한다/);
  assert.match(notificationSettings, /class NotificationSettingsApiRepository/);
  assert.match(notificationSettings, /\/api\/v1\/me\/notification-settings/);
  assert.match(notificationSettings, /AuthorizationHeaderProvider/);
  assert.match(notificationSettings, /HttpStatus\.unauthorized/);
  assert.match(notificationSettings, /class NotificationSettingsController extends ChangeNotifier/);
  assert.match(notificationSettings, /class NotificationSettingsScreen extends StatefulWidget/);
  assert.match(notificationSettings, /역 시설 알림/);
  assert.match(notificationSettings, /경로 시설 알림/);
  assert.match(notificationSettings, /제보 처리 알림/);
  assert.match(notificationSettings, /최신 안내 알림/);
  assert.match(notificationSettings, /즐겨찾는 역과 경로의 시설 변경/);
  assert.match(notificationSettings, /알림 설정에서 언제든 끌 수 있습니다/);
  assert.match(notificationSettings, /notificationRegistrationFailureNextAction/);
  assert.match(notificationSettings, /휴대전화 알림 설정과 인터넷 연결을 확인한 뒤 다시 시도해 주세요\./);
  assert.match(notificationSettingsTest, /인증 실패 시 인증을 지우고 한 번 재시도한다/);
  assert.match(notificationSettingsTest, /알림 설정 컨트롤러는 조회와 저장 상태를 구분한다/);
  assert.match(widgetTest, /알림 설정 화면은 기기 알림 실패 다음 행동을 안내한다/);
  assert.match(read("apps/mobile/lib/onboarding.dart"), /onboardingNotificationFailureNextAction/);
  assert.match(read("apps/mobile/lib/onboarding.dart"), /나중에 알림 설정에서 다시 켤 수 있습니다\./);
  assert.match(read("apps/mobile/test/onboarding_test.dart"), /온보딩은 알림 권한 요청 실패 다음 행동을 안내한다/);
  assert.match(onboardingAppFlowTest, /첫 실행 앱은 온보딩 알림 권한 실패 다음 행동을 안내한다/);
  assert.doesNotMatch(widgetTest, /첫 실행 앱은 온보딩 알림 권한 실패 다음 행동을 안내한다/);
  assert.match(stationSearch, /가까운 역 찾기와 시설 제보 위치 확인에만 현재 위치를 사용합니다/);
  assert.match(stationSearch, /위치 권한을 거부해도 역명 검색, 즐겨찾기, 접근성 정보 조회는 계속 사용할 수 있습니다/);
  assert.match(facilityReport, /사진과 제보 위치는 시설 제보 확인에만 사용됩니다/);
  assert.match(facilityReport, /제보 내용은 접수 담당자에게 전달되며 앱 사용자에게 공개되지 않습니다/);
  assert.match(widgetTest, /역 검색은 첫 위치 권한 요청 전에 사용 목적을 안내한다/);
  assert.match(widgetTest, /시설 신고 화면은 첫 위치 권한 요청 전에 사용 목적을 안내한다/);
  assert.match(widgetTest, /시설 신고 화면은 사진과 위치를 보내기 전에 공개 범위를 안내한다/);
  assert.match(widgetTest, /시설 신고 화면은 현재 위치를 보내기 전에 공개 범위를 안내한다/);
  assert.doesNotMatch(main, /빠른 길보다, 갈 수 있는 길을 먼저 안내합니다|고령자, 임산부, 장애인도 편하게 이동할 수 있도록|현장에서 발견한 불편 정보를 신고하고 검수할 수 있게/);
  assert.match(widgetTest, /EasySubwayApp/);
  assert.match(easySubwayAppDefaultsTest, /기본 앱은 출시 범위에서 원격 개인 데이터 저장소를 만들지 않는다/);
  assert.match(easySubwayAppDefaultsTest, /푸시 알림을 명시적으로 켜도 인증 없는 원격 저장소는 만들지 않는다/);
  assert.match(easySubwayAppDefaultsTest, /enablePushNotifications: true/);
  assert.match(easySubwayAppDefaultsTest, /인증 저장소가 없으면 홈 즐겨찾기를 노출하지 않는다/);
  assert.match(widgetTest, /홈 화면은 핵심 행동과 보조 행동을 나누어 보여준다/);
  assert.match(widgetTest, /홈 즐겨찾기는 하나의 진입점에서 탭 목록을 바로 보여준다/);
  assert.match(widgetTest, /도움말은 개인정보 사용 목적과 삭제 요청 대상을 쉬운 문구로 안내한다/);
  assert.match(widgetTest, /도움말은 안전과 데이터 안내를 함께 보여준다/);
  assert.match(widgetTest, /도움말은 보안 문의와 취약점 접수 경로를 안내한다/);
  assert.match(main, /보안 문의 안내/);
  assert.match(main, /취약점이나 개인정보 보호 우려를 발견하면 보안 문의로 알려주세요\./);
  assert.match(main, /EASYSUBWAY_SECURITY_EMAIL/);
  assert.match(main, /validatedForBuild\(\{required bool isReleaseMode\}\)/);
  assert.match(main, /Release \$label must use HTTPS\./);
  assert.match(main, /Release \$label must be a valid email address\./);
  assert.match(main, /Release \$label must be configured\./);
  assert.match(main, /supportAccessInfo\.validatedForBuild\([\s\S]*isReleaseMode: kReleaseMode/);
  assert.match(read("README.md"), /EASYSUBWAY_SECURITY_EMAIL/);
  assert.match(read("README.md"), /릴리즈 빌드는 아래 값이 비어 있으면 시작 단계에서 실패/);
  assert.match(supportAccessInfoTest, /릴리즈 도움말 연락 경로는 모두 설정되어야 한다/);
  assert.match(supportAccessInfoTest, /릴리즈 도움말 연락 경로는 HTTPS와 메일 주소 형식만 허용한다/);
  assert.match(supportAccessInfoTest, /Release privacy policy URL must use HTTPS\./);
  assert.match(supportAccessInfoTest, /Release support email must be a valid email address\./);
  assert.match(supportAccessInfoTest, /Release data deletion email must be configured\./);
  assert.match(supportAccessInfoTest, /Release security email must be configured\./);
  assert.match(routeSearch, /routeSearchFailureNextAction/);
  assert.match(routeSearch, /역을 다시 선택하거나 이동 조건을 바꾼 뒤 경로를 다시 찾아보세요\./);
  assert.match(routeSearch, /다음 행동 \$_routeSearchFailureNextAction/);
  assert.match(routeSearch, /routeBlockedNextActionNotice/);
  assert.doesNotMatch(
    routeSearch,
    /label: '다음 행동, \$_routeSearchFailureNextAction'[\s\S]{0,120}child: const SizedBox\.shrink\(\)/,
  );
  assert.match(widgetTest, /경로 검색 실패는 다음 행동을 쉬운 문구로 안내한다/);
  assert.match(widgetTest, /안내 불가 이유[\s\S]*다음 행동/);
  assert.match(routeSearch, /routeFeedbackFailureNextAction/);
  assert.match(routeSearch, /잠시 후 다시 보내거나 경로 조건을 바꿔 다시 찾아보세요\./);
  assert.match(widgetTest, /경로 피드백 실패는 다음 행동을 쉬운 문구로 안내한다/);
  assert.match(routeSearch, /favoriteRouteSaveFailureNextAction/);
  assert.match(routeSearch, /네트워크 상태를 확인한 뒤 자주 쓰는 경로 저장을 다시 눌러 주세요\./);
  assert.match(routeSearch, /favoriteRouteLoadFailureNextAction/);
  assert.match(routeSearch, /네트워크 상태를 확인한 뒤 다시 불러와 주세요\./);
  assert.match(widgetTest, /즐겨찾기 경로 저장 실패는 다음 행동을 쉬운 문구로 안내한다/);
  assert.match(widgetTest, /즐겨찾기 경로 목록 실패는 다음 행동을 쉬운 문구로 안내한다/);
  assert.match(routeSearch, /import 'core\/network\/api_client\.dart';/);
  assert.match(routeSearch, /class RouteSearchApiRepository[\s\S]*final ApiClient _apiClient;/);
  assert.match(routeSearch, /class RouteSearchApiRepository[\s\S]*_apiClient\.postJson\(/);
  assert.doesNotMatch(
    routeSearch,
    /class RouteSearchApiRepository[\s\S]*?_httpClient[\s\S]*?class RouteFeedbackApiRepository/,
  );
  assert.match(routeSearch, /class RouteFeedbackApiRepository[\s\S]*final ApiClient _apiClient;/);
  assert.match(routeSearch, /class RouteFeedbackApiRepository[\s\S]*_apiClient\.postJson\(/);
  assert.doesNotMatch(
    routeSearch,
    /class RouteFeedbackApiRepository[\s\S]*?_httpClient[\s\S]*?class RouteFeedbackException/,
  );
  assert.match(routeSearch, /class FavoriteRouteApiRepository[\s\S]*final ApiClient _apiClient;/);
  assert.match(routeSearch, /class FavoriteRouteApiRepository[\s\S]*_apiClient\.getJson\(/);
  assert.match(routeSearch, /class FavoriteRouteApiRepository[\s\S]*_apiClient\.postJson\(/);
  assert.match(routeSearch, /class FavoriteRouteApiRepository[\s\S]*_apiClient\.deleteJson\(/);
  assert.doesNotMatch(
    routeSearch,
    /class FavoriteRouteApiRepository[\s\S]*?_httpClient[\s\S]*?class FavoriteRouteException/,
  );
  assert.match(main, /개인정보 사용 안내/);
  assert.match(main, /안전과 데이터 안내/);
  assert.match(main, /현재 위치는 가까운 역 찾기와 시설 제보 위치 확인에만 사용됩니다/);
  assert.match(main, /경로와 시설 정보는 이동을 돕는 참고 정보입니다/);
  assert.match(main, /현장 안내, 역무원 안내, 운영기관 공지를 먼저 확인해 주세요/);
  assert.match(main, /실시간 상태나 무조건 안전한 경로를 보장하지 않습니다/);
  assert.match(main, /데이터 삭제 요청 시 즐겨찾기, 이동 조건, 신고 접수 기록, 신고 내용·사진·위치와 경로 피드백을 삭제하거나 익명화합니다/);
  assert.match(apiClient, /class ApiClient/);
  assert.match(apiClient, /const defaultApiTimeout = Duration\(seconds: 8\)/);
  assert.match(apiClient, /Future<ApiResponse> getJson/);
  assert.match(apiClient, /Future<ApiResponse> deleteJson/);
  assert.match(apiClient, /Future<ApiResponse> postJson/);
  assert.match(apiClient, /HttpHeaders\.acceptHeader/);
  assert.match(apiClient, /ContentType\.json\.mimeType/);
  assert.match(apiClient, /jsonDecode\(body\)/);
  assert.match(apiClient, /class ApiResponse/);
  assert.match(apiError, /class ApiException implements Exception/);
  assert.match(facilityReport, /import 'core\/network\/api_client\.dart';/);
  assert.match(facilityReport, /final ApiClient _apiClient;/);
  assert.match(
    facilityReport,
    /_apiClient\.getJson\([\s\S]*'\/api\/v1\/reports\/\$\{Uri\.encodeComponent\(trimmedReportId\)\}'/,
  );
  assert.match(facilityReport, /X-Easysubway-Report-Receipt-Token/);
  assert.match(facilityReport, /_apiClient\.postJson\([\s\S]*'\/api\/v1\/report-uploads'/);
  assert.doesNotMatch(facilityReport, /postUrl\(baseUri\.resolve\('\/api\/v1\/report-uploads'\)\)/);
  assert.match(facilityReport, /_apiClient\.putBytes\([\s\S]*uploadIntent\.uploadUri\(baseUri\)/);
  assert.doesNotMatch(facilityReport, /putUrl\(uploadIntent\.uploadUri\(baseUri\)\)/);
  assert.match(facilityReport, /_apiClient\.postJson\([\s\S]*'\/api\/v1\/reports'/);
  assert.match(appDependencies, /FacilityReportApiRepository\([\s\S]*apiClient: ApiClient\(baseUri: resolvedBaseUri\)/);
  assert.match(apiClientTest, /ApiClient는 GET 요청에 공통 header와 custom header를 적용한다/);
  assert.match(apiClientTest, /ApiClient는 POST 요청에 JSON body와 공통 header를 적용한다/);
  assert.match(apiClientTest, /ApiClient는 DELETE 요청에 공통 timeout과 JSON decode 경계를 적용한다/);
  assert.match(apiClientTest, /ApiClient 예외는 인증 토큰을 노출하지 않는다/);
  assert.match(userDataDeletion, /class UserDataDeletionApiRepository implements UserDataDeletionRepository/);
  assert.match(userDataDeletion, /_apiClient\.deleteJson\([\s\S]*'\/api\/v1\/me'/);
  assert.match(userDataDeletion, /HttpHeaders\.authorizationHeader/);
  assert.match(userDataDeletion, /refreshExistingAuthorization/);
  assert.match(
    userDataDeletion,
    /userDataDeletionErrorMessage = '데이터 삭제를 완료하지 못했습니다\. 잠시 후 다시 시도해 주세요\.'/,
  );
  assert.match(userDataDeletionTest, /인증 헤더로 DELETE \/api\/v1\/me를 호출한다/);
  assert.match(userDataDeletionTest, /기존 인증 갱신 실패 시 새 사용자 삭제로 처리하지 않는다/);
  assert.match(widgetTest, /도움말은 앱 안에서 데이터 삭제를 재확인하고 로컬 상태를 정리한다/);
  assert.match(widgetTest, /데이터 삭제 실패 시 로컬 상태를 유지하고 오류를 안내한다/);
  assert.match(main, /UserDataDeletionScreen/);
  assert.match(main, /dataDeletionConfirmButton/);
  assert.match(widgetTest, /알림 설정 화면은 현재 설정을 불러오고 바꾼 값을 저장한다/);
  assert.match(widgetTest, /bySemanticsLabel/);
  assert.match(widgetTest, /greaterThanOrEqualTo\(60\)/);
});

test("모바일 접근성 출시 QA 기준선은 Android와 iOS 제출 전 확인 항목을 고정한다", () => {
  const qaPath = "apps/mobile/release/accessibility-release-qa.json";
  assert.ok(existsSync(path.join(root, qaPath)));

  const qa = readJson(qaPath);

  assert.equal(qa.schemaVersion, 1);
  assert.equal(qa.applicationId, "easysubway");
  assert.equal(qa.releaseGate, "store-accessibility-qa");
  assert.ok(Array.isArray(qa.checks));

  const checks = new Map(qa.checks.map((check) => [check.id, check]));
  const requiredIds = [
    "android_talkback_home_navigation",
    "android_font_scale_150",
    "android_high_contrast",
    "android_location_permission_denied",
    "android_network_error_recovery",
    "android_server_error_recovery",
    "android_reinstall_secure_storage_restore",
    "ios_voiceover_home_navigation",
    "ios_dynamic_type_accessibility_size",
    "ios_bold_text",
    "ios_increase_contrast",
    "ios_reduce_motion",
    "ios_location_permission_denied",
    "ios_network_error_recovery",
    "ios_safe_area_small_screen_tap_targets",
  ];
  assert.deepEqual([...checks.keys()].sort(), requiredIds.toSorted());

  for (const id of requiredIds) {
    const check = checks.get(id);
    assert.match(check.platform, /^(android|ios)$/);
    assert.equal(typeof check.titleKo, "string", `${id} must have Korean title`);
    assert.ok(check.titleKo.length > 0, `${id} title must not be empty`);
    assert.equal(typeof check.environmentKo, "string", `${id} must describe environment`);
    assert.equal(typeof check.flowKo, "string", `${id} must describe flow`);
    assert.equal(typeof check.passCriteriaKo, "string", `${id} must describe pass criteria`);
    assert.equal(typeof check.automation, "string", `${id} must describe automation level`);
    assert.ok(Array.isArray(check.evidence), `${id} must list evidence`);
    assert.ok(check.evidence.length > 0, `${id} must require evidence`);
  }

  assert.match(checks.get("android_talkback_home_navigation").environmentKo, /TalkBack/);
  assert.match(checks.get("android_font_scale_150").environmentKo, /150%|1\.5/);
  assert.match(checks.get("android_reinstall_secure_storage_restore").flowKo, /재설치|복원/);
  assert.match(checks.get("ios_voiceover_home_navigation").environmentKo, /VoiceOver/);
  assert.match(checks.get("ios_dynamic_type_accessibility_size").environmentKo, /Dynamic Type/);
  assert.match(checks.get("ios_safe_area_small_screen_tap_targets").passCriteriaKo, /터치|safe area/);
});

test("모바일 스토어 심사 정보 기준선은 제출 전 필수 항목을 고정한다", () => {
  const readinessPath = "apps/mobile/release/store-submission-readiness.json";
  assert.ok(existsSync(path.join(root, readinessPath)));

  const readiness = readJson(readinessPath);

  assert.equal(readiness.schemaVersion, 1);
  assert.equal(readiness.applicationId, "easysubway");
  assert.equal(readiness.androidApplicationId, "com.easysubway.app");
  assert.equal(readiness.releaseGate, "store-submission-readiness");
  assert.equal(readiness.appNameKo, "쉬운 지하철");
  assert.equal(readiness.appNameEn, "easysubway");
  assert.ok(readiness.appNameKo.length <= readiness.appNameLengthLimits.googlePlay);
  assert.match(readiness.policyRefreshKo, /제출 직전|최신/);
  assert.doesNotMatch(JSON.stringify(readiness), /\b(TBD|TODO)\b|\.{3}/i);
  assert.ok(Array.isArray(readiness.items));

  const items = new Map(readiness.items.map((item) => [item.id, item]));
  const requiredIds = [
    "play_data_safety",
    "play_privacy_policy_url",
    "play_app_access",
    "play_content_rating",
    "play_target_audience",
    "play_ads_declaration",
    "play_app_category",
    "play_store_contact",
    "play_permissions_declaration",
    "play_account_data_deletion",
    "play_listing_assets_truthfulness",
    "appstore_app_privacy",
    "appstore_privacy_policy_url",
    "appstore_support_url",
    "appstore_age_rating",
    "appstore_app_category",
    "appstore_review_contact",
    "appstore_review_notes_or_demo_access",
    "appstore_content_rights",
    "appstore_backend_api_availability",
    "appstore_screenshot_truthfulness",
    "cross_store_app_name",
    "cross_store_privacy_consistency",
    "cross_store_accessibility_claims",
  ];
  assert.deepEqual([...items.keys()].sort(), requiredIds.toSorted());

  const stores = new Set(readiness.items.map((item) => item.store));
  assert.deepEqual([...stores].sort(), ["app-store", "cross-store", "google-play"]);

  for (const id of requiredIds) {
    const item = items.get(id);
    assert.match(item.store, /^(google-play|app-store|cross-store)$/);
    assert.equal(typeof item.category, "string", `${id} must have category`);
    assert.equal(typeof item.titleKo, "string", `${id} must have Korean title`);
    assert.ok(item.titleKo.length > 0, `${id} title must not be empty`);
    assert.equal(typeof item.decisionOwnerKo, "string", `${id} must have decision owner`);
    assert.equal(typeof item.readyWhenKo, "string", `${id} must define ready state`);
    assert.ok(Array.isArray(item.evidence), `${id} must list evidence`);
    assert.ok(item.evidence.length > 0, `${id} must require evidence`);
    assert.ok(Array.isArray(item.configurationSources), `${id} must list configuration sources`);
    assert.ok(item.configurationSources.length > 0, `${id} must require configuration sources`);
    assert.ok(Array.isArray(item.linkedArtifacts), `${id} must list linked artifacts`);
    for (const artifact of item.linkedArtifacts) {
      assert.ok(existsSync(path.join(root, artifact)), `${id} linked artifact must exist: ${artifact}`);
    }
  }

  assert.ok(items.get("play_data_safety").linkedArtifacts.includes("apps/mobile/release/store-privacy-inventory.json"));
  assert.match(items.get("play_privacy_policy_url").configurationSources.join("\n"), /EASYSUBWAY_PRIVACY_POLICY_URL/);
  assert.match(items.get("play_app_access").readyWhenKo, /로그인 없음|제한 접근|심사 계정/);
  assert.match(items.get("play_content_rating").readyWhenKo, /등급/);
  assert.match(items.get("play_target_audience").readyWhenKo, /전체 사용자|어린이 대상 아님/);
  assert.match(items.get("play_permissions_declaration").readyWhenKo, /위치|권한/);
  assert.match(items.get("play_account_data_deletion").configurationSources.join("\n"), /EASYSUBWAY_DATA_DELETION_EMAIL/);
  assert.ok(items.get("appstore_app_privacy").linkedArtifacts.includes("apps/mobile/ios/Runner/PrivacyInfo.xcprivacy"));
  assert.match(items.get("appstore_review_notes_or_demo_access").readyWhenKo, /심사 메모|데모|로그인 없음/);
  assert.match(items.get("appstore_backend_api_availability").readyWhenKo, /심사 기간|API/);
  assert.ok(items.get("cross_store_privacy_consistency").linkedArtifacts.includes("apps/mobile/release/store-privacy-inventory.json"));
  assert.ok(items.get("cross_store_accessibility_claims").linkedArtifacts.includes("apps/mobile/release/accessibility-release-qa.json"));
});

test("릴리즈 보안 기준선은 제출 전 차단 항목을 고정한다", () => {
  const gatePath = "apps/mobile/release/release-security-gate.json";
  assert.ok(existsSync(path.join(root, gatePath)));

  const gate = readJson(gatePath);
  const androidManifest = read("apps/mobile/android/app/src/main/AndroidManifest.xml");
  const androidDebugManifest = read("apps/mobile/android/app/src/debug/AndroidManifest.xml");
  const androidProfileManifest = read("apps/mobile/android/app/src/profile/AndroidManifest.xml");
  const androidBuildGradle = read("apps/mobile/android/app/build.gradle.kts");
  const releaseArtifactsWorkflow = read(".github/workflows/release-artifacts.yml");
  const gitignore = read(".gitignore");
  const commonExceptionHandler = read("backend/src/main/java/com/easysubway/common/web/CommonExceptionHandler.java");
  const messages = read("backend/src/main/resources/messages.properties");
  const securityConfig = read("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java");
  const adminOperatorLockoutProvider = read(
    "backend/src/main/java/com/easysubway/common/security/AdminOperatorLockoutAuthenticationProvider.java",
  );
  const facilityReportPhotoProcessor = read(
    "backend/src/main/java/com/easysubway/report/application/service/FacilityReportPhotoProcessor.java",
  );

  assert.equal(gate.schemaVersion, 1);
  assert.equal(gate.applicationId, "easysubway");
  assert.equal(gate.androidApplicationId, "com.easysubway.app");
  assert.equal(gate.releaseGate, "release-security-gate");
  assert.equal(gate.releaseBlockerPolicy, true);
  assert.match(gate.policyRefreshKo, /출시 전|최신/);
  assert.doesNotMatch(JSON.stringify(gate), /\b(TBD|TODO)\b|\.{3}/i);
  assert.ok(Array.isArray(gate.items));

  const items = new Map(gate.items.map((item) => [item.id, item]));
  const requiredIds = [
    "mobile_cleartext_disabled",
    "mobile_debug_network_overrides_limited",
    "mobile_release_signing_externalized",
    "mobile_test_credentials_absent",
    "mobile_error_stacktrace_sanitized",
    "backend_admin_auth_required",
    "backend_admin_basic_auth_transition_gate",
    "backend_role_authorization",
    "backend_report_photo_upload_limits",
    "backend_error_response_sanitized",
    "backend_api_traffic_monitoring",
    "backend_sensitive_log_minimization",
    "repository_secrets_not_tracked",
    "repository_provider_storage_exposure_guard",
    "repository_dependency_review",
    "repository_codex_security_scan_before_release",
    "cross_store_privacy_security_consistency",
  ];
  assert.deepEqual([...items.keys()].sort(), requiredIds.toSorted());

  const areas = new Set(gate.items.map((item) => item.area));
  assert.deepEqual([...areas].sort(), ["backend", "cross-store", "mobile", "repository"]);

  for (const id of requiredIds) {
    const item = items.get(id);
    assert.match(item.area, /^(mobile|backend|repository|cross-store)$/);
    assert.equal(item.severity, "release-blocker", `${id} must be release-blocker`);
    assert.equal(typeof item.titleKo, "string", `${id} must have Korean title`);
    assert.ok(item.titleKo.length > 0, `${id} title must not be empty`);
    assert.equal(typeof item.ownerKo, "string", `${id} must have owner`);
    assert.equal(typeof item.readyWhenKo, "string", `${id} must define ready state`);
    assert.ok(Array.isArray(item.evidence), `${id} must list evidence`);
    assert.ok(item.evidence.length > 0, `${id} must require evidence`);
    assert.ok(Array.isArray(item.linkedArtifacts), `${id} must list linked artifacts`);
    for (const artifact of item.linkedArtifacts) {
      assert.ok(existsSync(path.join(root, artifact)), `${id} linked artifact must exist: ${artifact}`);
    }
  }

  assert.match(androidManifest, /android:usesCleartextTraffic="false"/);
  assert.match(androidDebugManifest, /android:usesCleartextTraffic="true"/);
  assert.match(androidProfileManifest, /android:usesCleartextTraffic="true"/);
  assert.match(androidBuildGradle, /throw GradleException\([\s\S]*Android release signing values are missing:/);
  assert.doesNotMatch(androidBuildGradle, /signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)/);
  assert.match(commonExceptionHandler, /messages\.message\("common\.error\.invalid-parameter"\)/);
  assert.match(messages, /^common\.error\.invalid-parameter=요청 값을 확인해야 합니다\.$/m);
  assert.doesNotMatch(commonExceptionHandler, /StackTrace|printStackTrace|getStackTrace/);
  assert.match(securityConfig, /securityMatcher\("\/admin\/\*\*"\)/);
  assert.match(securityConfig, /hasRole\("ADMIN"\)/);
  assert.match(securityConfig, /hasRole\("OPERATOR_ADMIN"\)/);
  assert.match(securityConfig, /validateProdAdminCredentials/);
  const adminBasicAuthGate = items.get("backend_admin_basic_auth_transition_gate");
  assert.match(adminBasicAuthGate.readyWhenKo, /lockout|OIDC|MFA|SSO/i);
  assert.match(adminBasicAuthGate.readyWhenKo, /Basic auth/);
  assert.ok(adminBasicAuthGate.evidence.includes("admin-auth-transition-decision-record"));
  assert.ok(adminBasicAuthGate.evidence.includes("lockout-or-oidc-mfa-implementation-evidence"));
  assert.ok(adminBasicAuthGate.evidence.includes("admin-basic-auth-lockout-tests"));
  assert.ok(adminBasicAuthGate.linkedArtifacts.includes("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java"));
  assert.ok(adminBasicAuthGate.linkedArtifacts.includes("backend/src/main/java/com/easysubway/common/security/AdminOperatorLockoutAuthenticationProvider.java"));
  assert.ok(adminBasicAuthGate.linkedArtifacts.includes("backend/src/test/java/com/easysubway/common/security/AdminOperatorLockoutAuthenticationProviderTest.java"));
  assert.ok(adminBasicAuthGate.linkedArtifacts.includes(".github/pull_request_template.md"));
  assert.match(adminOperatorLockoutProvider, /LockedException/);
  assert.match(adminOperatorLockoutProvider, /BadCredentialsException/);
  assert.match(adminOperatorLockoutProvider, /lockedUntil/);
  assert.match(facilityReportPhotoProcessor, /MAX_PHOTO_BYTES = 900 \* 1024/);
  assert.match(facilityReportPhotoProcessor, /MAX_PHOTO_WIDTH = 4_096/);
  assert.match(facilityReportPhotoProcessor, /MAX_PHOTO_PIXELS = 12_000_000/);
  assert.match(facilityReportPhotoProcessor, /ALLOWED_PHOTO_CONTENT_TYPES/);
  assert.match(facilityReportPhotoProcessor, /"image\/webp"/);
  assert.match(facilityReportPhotoProcessor, /Base64\.getDecoder\(\)\.decode/);
  assert.match(facilityReportPhotoProcessor, /requireSupportedMagic/);
  assert.match(facilityReportPhotoProcessor, /readDimensions/);
  assert.match(facilityReportPhotoProcessor, /ImageIO\.read/);
  assert.match(gitignore, /^\*.pem$/m);
  assert.match(gitignore, /^\*.key$/m);
  assert.match(gitignore, /^google-services\.json$/m);
  const providerStorageExposureGuard = items.get("repository_provider_storage_exposure_guard");
  assert.match(providerStorageExposureGuard.readyWhenKo, /provider key|object storage|signed URL/i);
  assert.ok(providerStorageExposureGuard.evidence.includes("release-artifact-credential-search"));
  assert.ok(providerStorageExposureGuard.evidence.includes("signed-upload-url-expiry-contract"));
  assert.ok(providerStorageExposureGuard.linkedArtifacts.includes(".github/workflows/release-artifacts.yml"));
  assert.ok(providerStorageExposureGuard.linkedArtifacts.includes("backend/src/test/java/com/easysubway/report/adapter/in/web/FacilityReportUploadIntentsTest.java"));
  assert.ok(providerStorageExposureGuard.linkedArtifacts.includes("tools/ci/repository-contract.test.mjs"));
  assert.doesNotMatch(releaseArtifactsWorkflow, /EASYSUBWAY_OBJECT_STORAGE_(?:ACCESS_KEY|SECRET_KEY|ENDPOINT|REGION)/);
  assert.doesNotMatch(releaseArtifactsWorkflow, /EASYSUBWAY_[A-Z0-9_]*(?:PROVIDER|REALTIME)[A-Z0-9_]*KEY/);
  assert.doesNotMatch(androidBuildGradle, /EASYSUBWAY_OBJECT_STORAGE|PROVIDER_API_KEY|REALTIME_PROVIDER_KEY/);
  const dependencyReview = items.get("repository_dependency_review");
  assert.ok(dependencyReview.evidence.includes("osv-scanner-pr-result"));
  assert.match(dependencyReview.readyWhenKo, /OSV Scanner|취약/);
  assert.ok(dependencyReview.linkedArtifacts.includes(".github/workflows/ci.yml"));
  assert.ok(dependencyReview.linkedArtifacts.includes("backend/gradle.lockfile"));
  assert.ok(dependencyReview.linkedArtifacts.includes("backend/osv-scanner.toml"));
  assert.ok(dependencyReview.linkedArtifacts.includes("backend/build.gradle"));
  assert.ok(dependencyReview.linkedArtifacts.includes("apps/mobile/android/app/gradle.lockfile"));
  assert.ok(dependencyReview.linkedArtifacts.includes("apps/mobile/android/app/osv-scanner.toml"));
  assert.ok(dependencyReview.linkedArtifacts.includes("apps/mobile/android/app/build.gradle.kts"));
  assert.ok(dependencyReview.linkedArtifacts.includes("apps/mobile/android/build.gradle.kts"));
  assert.ok(items.get("cross_store_privacy_security_consistency").linkedArtifacts.includes("apps/mobile/release/store-privacy-inventory.json"));
  assert.ok(items.get("cross_store_privacy_security_consistency").linkedArtifacts.includes("apps/mobile/release/store-submission-readiness.json"));
});

test("관리자 사용자 활동 화면은 API 오류율 운영 지표를 표시한다", () => {
  const userActivityFilter = read("backend/src/main/java/com/easysubway/usage/adapter/in/web/UserActivityTrackingFilter.java");
  const summary = read("backend/src/main/java/com/easysubway/usage/domain/UserActivityDashboardSummary.java");
  const repository = read("backend/src/main/java/com/easysubway/usage/adapter/out/persistence/InMemoryUserActivityRepository.java");
  const dashboardView = read("backend/src/main/java/com/easysubway/usage/adapter/in/web/UserActivityDashboardView.java");
  const template = read("backend/src/main/resources/templates/admin/usage/activity.html");
  const filterTest = read("backend/src/test/java/com/easysubway/usage/adapter/in/web/UserActivityTrackingFilterTest.java");
  const repositoryTest = read("backend/src/test/java/com/easysubway/usage/adapter/out/persistence/InMemoryUserActivityRepositoryTest.java");

  assert.match(userActivityFilter, /RecordApiTrafficPort/);
  assert.match(userActivityFilter, /recordApiTraffic\(\s*response\.getStatus\(\),\s*durationMillis,\s*LocalDateTime\.now\(clock\)\s*\)/);
  assert.match(userActivityFilter, /response\.getStatus\(\) < 400/);
  assert.match(summary, /totalApiRequests/);
  assert.match(summary, /totalApiErrors/);
  assert.match(summary, /totalApiResponseMillis/);
  assert.match(summary, /apiErrorRatePercent\(\)/);
  assert.match(summary, /averageApiResponseTimeLabel\(\)/);
  assert.match(repository, /recordApiTraffic\(int statusCode, long durationMillis, LocalDateTime occurredAt\)/);
  assert.match(repository, /statusCode >= 400/);
  assert.match(repository, /durationMillis/);
  assert.match(dashboardView, /apiErrorRatePercent/);
  assert.match(dashboardView, /averageApiResponseTimeLabel/);
  assert.match(template, /API 오류율/);
  assert.match(template, /평균 응답 시간/);
  assert.match(template, /API 요청/);
  assert.match(template, /오류 응답/);
  assert.match(filterTest, /실패 응답은 API 오류율에 기록하고 활성 사용자 지표에서는 제외한다/);
  assert.match(repositoryTest, /최근 기간의 API 요청 수와 오류율을 일별로 집계한다/);
  assert.match(repositoryTest, /음수 API 응답 시간은 운영 지표로 저장하지 않는다/);
});

test("iOS 앱은 개인정보 매니페스트를 번들 리소스로 포함한다", () => {
  const privacyManifestPath = "apps/mobile/ios/Runner/PrivacyInfo.xcprivacy";
  assert.ok(existsSync(path.join(root, privacyManifestPath)));

  const privacyManifest = read(privacyManifestPath);
  const project = read("apps/mobile/ios/Runner.xcodeproj/project.pbxproj");

  assert.match(privacyManifest, /<key>NSPrivacyTracking<\/key>[\s\S]*?<false\/>/);
  assert.match(privacyManifest, /<key>NSPrivacyTrackingDomains<\/key>[\s\S]*?<array\/>/);
  assert.match(privacyManifest, /<key>NSPrivacyAccessedAPITypes<\/key>[\s\S]*?<array\/>/);
  assertPrivacyCollectedDataType(privacyManifest, "NSPrivacyCollectedDataTypePreciseLocation");
  assertPrivacyCollectedDataType(privacyManifest, "NSPrivacyCollectedDataTypePhotosorVideos");
  assertPrivacyCollectedDataType(privacyManifest, "NSPrivacyCollectedDataTypeOtherUserContent");
  assert.doesNotMatch(privacyManifest, /NSPrivacyCollectedDataTypeDeviceID/);
  assert.match(project, /PrivacyInfo\.xcprivacy \*\/ = \{isa = PBXFileReference;[\s\S]*?path = PrivacyInfo\.xcprivacy;/);
  assert.match(project, /PrivacyInfo\.xcprivacy in Resources/);
});

test("모바일 스토어 개인정보 인벤토리는 앱 동작과 심사 분류를 고정한다", () => {
  const inventoryPath = "apps/mobile/release/store-privacy-inventory.json";
  assert.ok(existsSync(path.join(root, inventoryPath)));

  const inventory = readJson(inventoryPath);
  const privacyManifest = read("apps/mobile/ios/Runner/PrivacyInfo.xcprivacy");
  const main = read("apps/mobile/lib/main.dart");
  const stationSearch = read("apps/mobile/lib/station_search.dart");
  const facilityReport = read("apps/mobile/lib/facility_report.dart");

  assert.equal(inventory.schemaVersion, 1);
  assert.equal(inventory.applicationId, "easysubway");
  assert.equal(inventory.tracking, false);
  assert.equal(inventory.sharesDataWithThirdParties, false);
  assert.equal(inventory.encryptionInTransitRequired, true);
  assert.equal(inventory.userDataDeletionSupported, true);
  assert.match(inventory.privacyPolicyUrlSource, /EASYSUBWAY_PRIVACY_POLICY_URL/);
  assert.match(main, /EASYSUBWAY_PRIVACY_POLICY_URL/);
  assert.match(main, /EASYSUBWAY_DATA_DELETION_EMAIL/);

  const items = new Map(inventory.dataTypes.map((item) => [item.id, item]));
  const requiredIds = [
    "precise_location",
    "search_queries",
    "favorite_stations_routes_facilities",
    "mobility_profile",
    "facility_report_content",
    "facility_report_photo",
    "facility_report_location",
    "diagnostics_crash_logs",
    "diagnostics_performance_logs",
  ];
  assert.deepEqual([...items.keys()].sort(), requiredIds.toSorted());

  for (const id of requiredIds) {
    const item = items.get(id);
    assert.equal(typeof item.displayNameKo, "string", `${id} must have Korean display name`);
    assert.ok(item.displayNameKo.length > 0, `${id} display name must not be empty`);
    assert.equal(typeof item.purposeKo, "string", `${id} must have purpose`);
    assert.ok(item.purposeKo.length > 0, `${id} purpose must not be empty`);
    assert.match(
      item.implementationStatus,
      /^(collected|local-only|backend-collected)$/,
      `${id} must declare implementation status`,
    );
    assert.match(item.introducedInVersion, /^\d+\.\d+\.\d+$/, `${id} must declare introduced version`);
    assert.equal(typeof item.codeOwner, "string", `${id} must declare code owner`);
    assert.ok(item.codeOwner.length > 0, `${id} code owner must not be empty`);
    assert.equal(typeof item.collectionTrigger, "string", `${id} must declare collection trigger`);
    assert.ok(item.collectionTrigger.length > 0, `${id} collection trigger must not be empty`);
    assert.ok(
      Array.isArray(item.backendTableOrService),
      `${id} must list backend tables or services`,
    );
    assert.ok(
      item.backendTableOrService.length > 0,
      `${id} must have at least one backend table or service`,
    );
    assert.ok(Array.isArray(item.storageLocations), `${id} must list storage locations`);
    assert.ok(item.storageLocations.length > 0, `${id} must have at least one storage location`);
    assert.equal(typeof item.retentionKo, "string", `${id} must have retention`);
    assert.equal(typeof item.deletionKo, "string", `${id} must have deletion path`);
    assert.equal(typeof item.deletionImplementation, "string", `${id} must have deletion implementation`);
    assert.ok(item.deletionImplementation.length > 0, `${id} deletion implementation must not be empty`);
    assert.ok(Array.isArray(item.evidence), `${id} must list evidence artifacts`);
    assert.ok(item.evidence.length > 0, `${id} must have at least one evidence artifact`);
    for (const evidencePath of item.evidence) {
      assert.ok(
        existsSync(path.join(root, evidencePath)),
        `${id} evidence artifact must exist: ${evidencePath}`,
      );
    }
    assert.equal(item.lastVerifiedAt, "2026-06-19", `${id} verification date must be current`);
    assert.equal(item.sharedWithThirdParties, false, `${id} must not be shared with third parties`);
    assert.equal(item.usedForTracking, false, `${id} must not be used for tracking`);
    assert.ok(item.googlePlayDataSafety?.dataType, `${id} must map to Play Data safety`);
    assert.equal(
      item.googlePlayDataSafety.encryptedInTransit,
      true,
      `${id} must require encrypted transport`,
    );
  }

  const appStoreTypes = [...new Set(
    inventory.dataTypes
      .map((item) => item.appStorePrivacy?.dataType)
      .filter(Boolean),
  )].sort();
  assert.deepEqual(appStoreTypes, [
    "NSPrivacyCollectedDataTypeCrashData",
    "NSPrivacyCollectedDataTypeOtherUserContent",
    "NSPrivacyCollectedDataTypePerformanceData",
    "NSPrivacyCollectedDataTypePhotosorVideos",
    "NSPrivacyCollectedDataTypePreciseLocation",
    "NSPrivacyCollectedDataTypeSearchHistory",
    "NSPrivacyCollectedDataTypeSensitiveInfo",
  ]);
  for (const dataType of appStoreTypes) {
    assertPrivacyCollectedDataType(privacyManifest, dataType);
  }

  assert.equal(items.get("precise_location").appStorePrivacy.dataType, "NSPrivacyCollectedDataTypePreciseLocation");
  assert.equal(items.get("search_queries").appStorePrivacy.dataType, "NSPrivacyCollectedDataTypeSearchHistory");
  assert.equal(items.get("mobility_profile").appStorePrivacy.dataType, "NSPrivacyCollectedDataTypeSensitiveInfo");
  assert.equal(items.get("facility_report_photo").appStorePrivacy.dataType, "NSPrivacyCollectedDataTypePhotosorVideos");
  assert.equal(items.get("facility_report_content").appStorePrivacy.dataType, "NSPrivacyCollectedDataTypeOtherUserContent");
  assert.equal(items.get("facility_report_location").appStorePrivacy.dataType, "NSPrivacyCollectedDataTypePreciseLocation");
  assert.equal(items.get("diagnostics_crash_logs").appStorePrivacy.dataType, "NSPrivacyCollectedDataTypeCrashData");
  assert.equal(items.get("diagnostics_performance_logs").appStorePrivacy.dataType, "NSPrivacyCollectedDataTypePerformanceData");
  assert.ok(
    items.get("favorite_stations_routes_facilities").evidence.includes("apps/mobile/lib/station_search.dart"),
    "favorite station evidence must include the station search implementation",
  );
  assert.deepEqual(items.get("facility_report_photo").storageLocations.toSorted(), [
    "backend-database-legacy-column",
    "backend-database-metadata",
    "backend-object-storage",
    "mobile-memory",
  ]);
  assert.match(
    items.get("facility_report_photo").backendTableOrService.join("\n"),
    /facility_reports\.photo_object_key[\s\S]*facility_reports\.photo_thumbnail_object_key[\s\S]*facility_reports\.photo_data_base64/,
  );
  assert.match(
    items.get("facility_report_photo").deletionImplementation,
    /deleteFacilityReportPhoto[\s\S]*photo_data_base64 = NULL/,
  );

  const excludedItems = new Map((inventory.excludedDataTypes ?? []).map((item) => [item.id, item]));
  assert.deepEqual([...excludedItems.keys()].sort(), ["push_notification_token"]);
  const pushToken = excludedItems.get("push_notification_token");
  assert.equal(pushToken.implementationStatus, "excluded-from-release");
  assert.match(pushToken.collectionTrigger, /EASYSUBWAY_ENABLE_PUSH_NOTIFICATIONS=true/);
  assert.equal(pushToken.sharedWithThirdParties, false);
  assert.equal(pushToken.usedForTracking, false);
  assert.equal(pushToken.googlePlayDataSafety.includedInRelease, false);
  assert.equal(pushToken.appStorePrivacy.includedInRelease, false);
  assert.equal(pushToken.lastVerifiedAt, "2026-06-19");
  for (const evidencePath of pushToken.evidence) {
    assert.ok(
      existsSync(path.join(root, evidencePath)),
      `push token evidence artifact must exist: ${evidencePath}`,
    );
  }
  assert.doesNotMatch(privacyManifest, /NSPrivacyCollectedDataTypeDeviceID/);

  assert.match(stationSearch, /currentLocation\(\)/);
  assert.match(facilityReport, /photoDataBase64/);
  assert.match(facilityReport, /latitude/);
  const appDependencies = read("apps/mobile/lib/app/app_dependencies.dart");
  assert.match(`${main}\n${appDependencies}`, /pushNotificationsEnabled/);
});

test("iOS 위치 권한은 앱 사용 중 목적만 설명한다", () => {
  const infoPlist = read("apps/mobile/ios/Runner/Info.plist");

  assert.match(infoPlist, /<key>NSLocationWhenInUseUsageDescription<\/key>/);
  assert.match(infoPlist, /앱을 사용하는 동안 가까운 역을 찾고 시설 신고 위치를 확인하는 데 사용합니다\./);
  assert.doesNotMatch(infoPlist, /NSLocationAlways/);
  assert.doesNotMatch(infoPlist, /UIBackgroundModes/);
});

test("iOS 릴리즈는 푸시 알림 entitlement를 출시 범위에서 제외한다", () => {
  const debugEntitlementsPath =
    "apps/mobile/ios/Runner/Runner-Debug.entitlements";
  const releaseEntitlementsPath =
    "apps/mobile/ios/Runner/Runner-Release.entitlements";
  assert.ok(existsSync(path.join(root, debugEntitlementsPath)));
  assert.ok(existsSync(path.join(root, releaseEntitlementsPath)));

  const debugEntitlements = read(debugEntitlementsPath);
  const releaseEntitlements = read(releaseEntitlementsPath);
  const project = read("apps/mobile/ios/Runner.xcodeproj/project.pbxproj");
  const main = read("apps/mobile/lib/main.dart");
  const notificationSettings = read("apps/mobile/lib/notification_settings.dart");

  assert.match(debugEntitlements, /<key>aps-environment<\/key>\s*<string>development<\/string>/);
  assert.doesNotMatch(releaseEntitlements, /<key>aps-environment<\/key>/);
  assert.doesNotMatch(releaseEntitlements, /<string>production<\/string>/);
  assert.match(project, /Runner-Debug\.entitlements \*\/ = \{isa = PBXFileReference;[\s\S]*?path = "Runner-Debug\.entitlements";/);
  assert.match(project, /Runner-Release\.entitlements \*\/ = \{isa = PBXFileReference;[\s\S]*?path = "Runner-Release\.entitlements";/);
  assert.match(project, /CODE_SIGN_ENTITLEMENTS = "Runner\/Runner-Debug\.entitlements";/);
  assert.equal([...project.matchAll(/CODE_SIGN_ENTITLEMENTS = "Runner\/Runner-Debug\.entitlements";/g)].length, 1);
  assert.equal([...project.matchAll(/CODE_SIGN_ENTITLEMENTS = "Runner\/Runner-Release\.entitlements";/g)].length, 2);
  assert.match(notificationSettings, /즐겨찾는 역과 경로의 시설 변경/);
  assert.match(notificationSettings, /알림 설정에서 언제든 끌 수 있습니다/);
  assert.match(main, /EASYSUBWAY_ENABLE_PUSH_NOTIFICATIONS/);
  assert.match(main, /defaultValue: false/);
});

test("Android 릴리즈 권한은 앱 기능에 필요한 항목만 선언한다", () => {
  const mergedManifestPath = "apps/mobile/build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml";
  const expectsGeneratedManifest = process.env.EASYSUBWAY_EXPECT_ANDROID_RELEASE_MANIFEST === "true";
  // Repository CI는 산출물을 만들지 않으므로, Mobile App CI에서만 생성 결과를 필수로 검사한다.
  if (!existsSync(path.join(root, mergedManifestPath)) && !expectsGeneratedManifest) {
    return;
  }

  assert.ok(
    existsSync(path.join(root, mergedManifestPath)),
    "Android release merged manifest must be generated before running this contract.",
  );

  const androidManifest = read(mergedManifestPath);
  const permissions = androidManifestPermissions(androidManifest);

  assert.deepEqual(permissions, [
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.INTERNET",
  ]);
  assert.doesNotMatch(androidManifest, /android\.permission\.ACCESS_BACKGROUND_LOCATION/);
  assert.doesNotMatch(androidManifest, /android\.permission\.CAMERA/);
  assert.doesNotMatch(androidManifest, /android\.permission\.READ_EXTERNAL_STORAGE/);
  assert.doesNotMatch(androidManifest, /android\.permission\.READ_MEDIA_IMAGES/);
  assert.doesNotMatch(androidManifest, /android\.permission\.READ_MEDIA_VIDEO/);
  assert.doesNotMatch(androidManifest, /android\.permission\.WRITE_EXTERNAL_STORAGE/);
});

test("Android 런처 아이콘은 원형 마스크 안전 여백을 가진다", () => {
  const densities = ["mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"];

  for (const density of densities) {
    assertAndroidLauncherIconSafeArea(
      `apps/mobile/android/app/src/main/res/mipmap-${density}/ic_launcher.png`,
      0.12,
    );
    assertAndroidLauncherIconSafeArea(
      `apps/mobile/android/app/src/main/res/mipmap-${density}/ic_launcher_foreground.png`,
      0.18,
    );
  }
});

test("경로 분류기는 README를 문서 전용 변경으로 처리한다", async () => {
  const outputs = await classifyChangedFiles(["README.md"]);

  assert.equal(outputs.docs_only, "true");
  assert.equal(outputs.repository, "false");
  assert.equal(outputs.backend, "false");
  assert.equal(outputs.mobile, "false");
  assert.equal(outputs.android, "false");
  assert.equal(outputs.ios, "false");
  assert.equal(outputs.ci, "false");
  assert.equal(outputs.deploy, "false");
});

test("경로 분류기는 저장소, 백엔드, 모바일, Android, iOS 변경을 구분한다", async () => {
  const repository = await classifyChangedFiles([".github/ISSUE_TEMPLATE/task_request.yml"]);
  assert.equal(repository.repository, "true");
  assert.equal(repository.docs_only, "false");

  const backend = await classifyChangedFiles(["backend/easysubway-api/src/main/java/com/easysubway/App.java"]);
  assert.equal(backend.backend, "true");
  assert.equal(backend.deploy, "true");

  const mobile = await classifyChangedFiles(["apps/mobile/lib/main.dart"]);
  assert.equal(mobile.mobile, "true");
  assert.equal(mobile.android, "true");
  assert.equal(mobile.ios, "true");

  const android = await classifyChangedFiles(["apps/mobile/android/app/build.gradle.kts"]);
  assert.equal(android.mobile, "true");
  assert.equal(android.android, "true");

  const ios = await classifyChangedFiles(["apps/mobile/ios/Runner/AppDelegate.swift"]);
  assert.equal(ios.mobile, "true");
  assert.equal(ios.ios, "true");

  const ci = await classifyChangedFiles([".github/workflows/ci.yml"]);
  assert.equal(ci.repository, "true");
  assert.equal(ci.ci, "true");

  const infra = await classifyChangedFiles(["infra/docker-compose.yml"]);
  assert.equal(infra.repository, "true");
  assert.equal(infra.deploy, "true");

  const datapack = await classifyChangedFiles(["tools/datapack/build-datapack.mjs"]);
  assert.equal(datapack.repository, "true");
  assert.equal(datapack.mobile, "true");
  assert.equal(datapack.android, "true");
  assert.equal(datapack.ios, "true");
  assert.equal(datapack.deploy, "true");

  const routeMapTool = await classifyChangedFiles(["tools/route-map/extract-svg-geometry.mjs"]);
  assert.equal(routeMapTool.repository, "true");
  assert.equal(routeMapTool.mobile, "false");
  assert.equal(routeMapTool.android, "false");
  assert.equal(routeMapTool.ios, "false");
  assert.equal(routeMapTool.deploy, "false");

  const realtimeTool = await classifyChangedFiles(["tools/realtime/seoul-topis-provider-contract.json"]);
  assert.equal(realtimeTool.repository, "true");
  assert.equal(realtimeTool.mobile, "false");
  assert.equal(realtimeTool.android, "false");
  assert.equal(realtimeTool.ios, "false");
  assert.equal(realtimeTool.deploy, "false");
});

test("경로 분류기는 백엔드 품질 gate 변경을 repository contract 대상으로 처리한다", async () => {
  const outputs = await classifyChangedFiles(["backend/quality/static-analysis-gate.json"]);

  assert.equal(outputs.repository, "true");
  assert.equal(outputs.ci, "true");
  assert.equal(outputs.backend, "true");
  assert.equal(outputs.deploy, "true");
  assert.equal(outputs.mobile, "true");
  assert.equal(outputs.android, "true");
  assert.equal(outputs.ios, "true");
  assert.equal(outputs.docs_only, "false");
});

test("경로 분류기 테스트는 CI의 GITHUB_OUTPUT을 물려받아도 안정적이다", async () => {
  const dir = await mkdtemp(path.join(tmpdir(), "easysubway-gh-output-"));
  const previousGithubOutput = process.env.GITHUB_OUTPUT;
  process.env.GITHUB_OUTPUT = path.join(dir, "github-output.txt");

  try {
    const outputs = await classifyChangedFiles(["README.md"]);

    assert.equal(outputs.docs_only, "true");
    assert.equal(outputs.repository, "false");
  } finally {
    if (previousGithubOutput === undefined) {
      delete process.env.GITHUB_OUTPUT;
    } else {
      process.env.GITHUB_OUTPUT = previousGithubOutput;
    }
  }
});

test("노선도 Android 실기기 evidence runner는 frame, memory, renderer reclaim 증거를 수집한다", () => {
  const scriptPath = "tools/mobile/run-route-map-android-evidence.sh";
  const script = read(scriptPath);

  assert.equal(existsSync(path.join(root, scriptPath)), true);
  assert.match(script, /^Usage:/m);
  assert.match(script, /--serial <adb-serial>/);
  assert.match(script, /--artifact-dir <dir>/);
  assert.match(script, /--build-mode <mode>/);
  assert.match(script, /--measure-after-route-map-settle/);
  assert.match(script, /Install a debug or profile APK first/);
  assert.match(script, /Unsupported build mode/);
  assert.match(script, /measurement_scope=/);
  assert.match(script, /gfxinfo_reset_after_route_map_settle=/);
  assert.match(script, /dumpsys gfxinfo "\$PACKAGE" reset/);
  assert.match(script, /dumpsys gfxinfo "\$PACKAGE" > "\$ARTIFACT_DIR\/gfxinfo\.txt"/);
  assert.match(script, /dumpsys gfxinfo "\$PACKAGE" framestats > "\$ARTIFACT_DIR\/gfxinfo-framestats\.txt"/);
  assert.match(script, /dumpsys meminfo "\$PACKAGE" > "\$ARTIFACT_DIR\/meminfo\.txt"/);
  assert.match(script, /logcat -c/);
  assert.match(script, /logcat -d -v time > "\$ARTIFACT_DIR\/logcat\.txt"/);
  assert.match(script, /uiautomator dump/);
  assert.match(script, /screencap -p/);
  assert.match(script, /routeMapRenderer disposed/);
  assert.match(script, /input tap "\$ROUTE_TAB_X" "\$BOTTOM_NAV_Y"/);
  assert.match(script, /input tap "\$HOME_TAB_X" "\$BOTTOM_NAV_Y"/);
  assert.match(script, /input swipe "\$PAN_RIGHT_X" "\$PAN_Y" "\$PAN_LEFT_X" "\$PAN_Y"/);
  assert.match(script, /summary\.md/);
});

test("노선도 Android evidence analyzer는 profile frame, memory, camera latency를 요약한다", async () => {
  const dir = await mkdtemp(path.join(tmpdir(), "easysubway-route-map-evidence-"));
  const artifactDir = path.join(dir, "run-1");
  await mkdir(artifactDir, { recursive: true });
  await writeFile(
    path.join(artifactDir, "metadata.env"),
    [
      "serial=RFKYA01VMQY",
      "package=com.easysubway.app",
      "width=1080",
      "height=2340",
      "build_mode=profile",
      "pan_count=3",
      "measurement_scope=gesture_after_route_map_settle",
      "gfxinfo_reset_after_route_map_settle=true",
      "captured_at_utc=2026-06-26T01:00:00Z",
    ].join("\n"),
  );
  await writeFile(
    path.join(artifactDir, "gfxinfo.txt"),
    [
      "Total frames rendered: 56",
      "Janky frames: 3 (5.36%)",
      "50th percentile: 10ms",
      "90th percentile: 18ms",
      "95th percentile: 25ms",
      "99th percentile: 33ms",
    ].join("\n"),
  );
  await writeFile(
    path.join(artifactDir, "meminfo.txt"),
    [
      "Java Heap:    15256",
      "Native Heap:    92580",
      "Graphics:   183577",
      "TOTAL PSS:   591090            TOTAL RSS:   723053       TOTAL SWAP PSS:      272",
    ].join("\n"),
  );
  await writeFile(
    path.join(artifactDir, "route-map-renderer.log"),
    [
      "06-26 10:25:37.509 I/flutter: routeMapRenderer cameraLatency revision=0 elapsedMs=12",
      "06-26 10:25:42.432 I/flutter: routeMapRenderer cameraLatency revision=1 elapsedMs=48",
      "06-26 10:25:46.185 I/flutter: routeMapRenderer disposed",
    ].join("\n"),
  );

  const { stdout } = await execFileAsync(
    process.execPath,
    [
      "tools/mobile/analyze-route-map-android-evidence.mjs",
      "--artifact-dir",
      artifactDir,
      "--format",
      "json",
    ],
    { cwd: root },
  );
  const output = JSON.parse(stdout);

  assert.equal(output.artifactKind, "route-map-android-evidence-summary");
  assert.equal(output.runs[0].buildMode, "profile");
  assert.equal(output.runs[0].measurementScope, "gesture_after_route_map_settle");
  assert.equal(output.runs[0].gfxinfoResetAfterRouteMapSettle, true);
  assert.equal(output.runs[0].gfxinfo.jankyPercent, 5.36);
  assert.equal(output.runs[0].gfxinfo.p99Ms, 33);
  assert.equal(output.runs[0].meminfo.totalPssKb, 591090);
  assert.equal(output.runs[0].renderer.cameraLatencyP95Ms, 48);
  assert.deepEqual(output.aggregate.measurementScopes, ["gesture_after_route_map_settle"]);
  assert.equal(output.aggregate.maxP95FrameMs, 25);
  assert.equal(output.aggregate.disposeObservedInAllRuns, true);
});

async function classifyChangedFiles(files) {
  const dir = await mkdtemp(path.join(tmpdir(), "easysubway-ci-"));
  const changedFilesPath = path.join(dir, "changed-files.txt");
  await writeFile(changedFilesPath, `${files.join("\n")}\n`);

  const scriptPath = path.join(root, "tools/ci/detect-changed-paths.sh");
  assert.ok(existsSync(scriptPath), "Expected tools/ci/detect-changed-paths.sh to exist");

  const { stdout } = await execFileAsync("bash", [scriptPath, changedFilesPath], {
    cwd: root,
    env: {
      ...process.env,
      GITHUB_OUTPUT: "",
      GITHUB_STEP_SUMMARY: "",
    },
  });
  return Object.fromEntries(stdout.trim().split("\n").map((line) => line.split("=")));
}
