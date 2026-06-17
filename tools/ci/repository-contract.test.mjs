import assert from "node:assert/strict";
import { execFile, execFileSync } from "node:child_process";
import { mkdtemp, writeFile } from "node:fs/promises";
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
  const pattern = new RegExp(`  ${startJob}:[\\s\\S]*?\\n  ${nextJob}:`);
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

  assert.match(workflow, /name: Changes/);
  assert.match(workflow, /name: Repository CI/);
  assert.match(workflow, /name: Backend CI/);
  assert.match(workflow, /name: Mobile App CI/);
  assert.match(workflow, /name: Android CI/);
  assert.match(workflow, /name: iOS CI/);
  assert.match(workflow, /Repository CI \/ Run contract tests/);
  assert.match(workflow, /Backend CI \/ Detect backend scaffold/);
  assert.match(workflow, /Mobile App CI \/ Run Flutter analyzer and tests/);
  assert.match(workflow, /Mobile App CI \/ Run mobile contracts/);
  assert.match(workflow, /Android CI \/ Build Flutter Android debug APK/);
  assert.match(workflow, /iOS CI \/ Build Flutter iOS simulator app/);
});

test("필수 지속적 통합 작업은 변경 없는 영역도 성공 상태로 종료한다", () => {
  const workflow = read(".github/workflows/ci.yml");

  assert.match(workflow, /Repository CI \/ Skip unchanged area/);
  assert.match(workflow, /Backend CI \/ Skip unchanged area/);
  assert.match(workflow, /Mobile App CI \/ Skip unchanged area/);
  assert.match(workflow, /Android CI \/ Skip unchanged area/);
  assert.match(workflow, /iOS CI \/ Skip unchanged area/);

  assert.doesNotMatch(jobBlock(workflow, "repository-contracts", "backend"), /\n    if:/);
  assert.doesNotMatch(jobBlock(workflow, "backend", "mobile-app"), /\n    if:/);
  assert.doesNotMatch(jobBlock(workflow, "mobile-app", "android"), /\n    if:/);
  assert.doesNotMatch(jobBlock(workflow, "android", "ios"), /\n    if:/);
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
  assert.match(envExample, /^EASYSUBWAY_REDIS_HOST=localhost$/m);
  assert.match(envExample, /^EASYSUBWAY_REDIS_PORT=6379$/m);
  assert.match(envExample, /^EASYSUBWAY_TRUSTED_PROXY_CIDRS=$/m);
  assert.match(envExample, /^EASYSUBWAY_ADMIN_USERNAME=$/m);
  assert.match(envExample, /^EASYSUBWAY_ADMIN_PASSWORD=$/m);
  assert.doesNotMatch(envExample, /prod|production|secret|token/i);
});

test("GitHub Actions 환경값은 dotenv secret 하나로 관리한다", () => {
  const readme = read("README.md");
  const script = read("scripts/github/sync-actions-env-secret.sh");

  assert.match(readme, /`EASYSUBWAY_ENV` secret 하나/);
  assert.match(readme, /GitHub Actions secret 이름은 반드시 `EASYSUBWAY_ENV`만 사용합니다/);
  assert.match(readme, /scripts\/github\/sync-actions-env-secret\.sh \.env/);
  assert.match(readme, /secrets\.EASYSUBWAY_ENV/);
  assert.match(readme, /CD workflow는 `EASYSUBWAY_ENV` secret이 있으면 배포 dotenv 계약을 검증/);
  assert.match(script, /readonly SECRET_NAME="EASYSUBWAY_ENV"/);
  assert.doesNotMatch(script, /EASYSUBWAY_ACTIONS_ENV_SECRET_NAME/);
  assert.match(script, /gh secret set "\$\{SECRET_NAME\}" --repo "\$\{REPO\}" < "\$\{ENV_FILE\}"/);
  assert.match(script, /\.env\.example is a template/);

  for (const file of workflowFiles()) {
    const source = read(file);
    assertActionsEnvSecretPolicy(file, source);
  }
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
    /node --test --test-name-pattern "모바일 generic catch\|Android 릴리즈 권한\|iOS 앱은 개인정보 매니페스트\|Android 런처 아이콘" tools\/ci\/repository-contract\.test\.mjs/,
  );
});

test("로컬 PostGIS와 Redis 서비스가 Docker Compose에 정의된다", () => {
  const compose = read("infra/docker-compose.yml");

  assert.match(compose, /postgres:\n/);
  assert.match(compose, /image: postgis\/postgis:16-3\.5/);
  assert.match(compose, /POSTGRES_DB: \$\{EASYSUBWAY_POSTGRES_DB:-easysubway\}/);
  assert.match(compose, /POSTGRES_USER: \$\{EASYSUBWAY_POSTGRES_USER:-easysubway\}/);
  assert.match(compose, /POSTGRES_PASSWORD: \$\{EASYSUBWAY_POSTGRES_PASSWORD:-easysubway_local\}/);
  assert.match(compose, /"\$\{EASYSUBWAY_POSTGRES_PORT:-5432\}:5432"/);
  assert.match(compose, /pg_isready -U \$\$\{POSTGRES_USER\} -d \$\$\{POSTGRES_DB\}/);
  assert.match(compose, /postgres-data:\/var\/lib\/postgresql\/data/);

  assert.match(compose, /redis:\n/);
  assert.match(compose, /image: redis:7\.4-alpine/);
  assert.match(compose, /"\$\{EASYSUBWAY_REDIS_PORT:-6379\}:6379"/);
  assert.match(compose, /redis-cli ping/);
  assert.match(compose, /redis-data:\/data/);

  assert.match(compose, /^volumes:\n  postgres-data:\n  redis-data:/m);
});

test("저장소 지속적 통합은 Docker Compose 설정을 검증한다", () => {
  const workflow = read(".github/workflows/ci.yml");

  assert.match(workflow, /Repository CI \/ Validate Docker Compose config/);
  assert.match(workflow, /docker compose --env-file \.env\.example -f infra\/docker-compose\.yml config --quiet/);
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

  assert.match(build, /id 'org\.springframework\.boot' version '3\.5\.6'/);
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

test("백엔드 익명 사용자 인증은 헥사고날 API 경계를 따른다", () => {
  const credentials = read("backend/src/main/java/com/easysubway/auth/domain/AnonymousUserCredentials.java");
  const authenticatedUser = read("backend/src/main/java/com/easysubway/auth/domain/AuthenticatedUser.java");
  const invalidAuth = read("backend/src/main/java/com/easysubway/auth/domain/InvalidAnonymousAuthException.java");
  const rateLimitExceeded = read("backend/src/main/java/com/easysubway/auth/domain/AnonymousAuthRateLimitExceededException.java");
  const useCase = read("backend/src/main/java/com/easysubway/auth/application/port/in/AnonymousAuthUseCase.java");
  const rateLimitUseCase = read("backend/src/main/java/com/easysubway/auth/application/port/in/AnonymousAuthRateLimitUseCase.java");
  const registerPort = read("backend/src/main/java/com/easysubway/auth/application/port/out/RegisterAnonymousUserPort.java");
  const consumeRateLimitPort = read(
    "backend/src/main/java/com/easysubway/auth/application/port/out/ConsumeAnonymousAuthRateLimitPort.java",
  );
  const service = read("backend/src/main/java/com/easysubway/auth/application/service/AnonymousAuthService.java");
  const rateLimitProperties = read(
    "backend/src/main/java/com/easysubway/auth/application/service/AnonymousAuthRateLimitProperties.java",
  );
  const rateLimitService = read("backend/src/main/java/com/easysubway/auth/application/service/AnonymousAuthRateLimitService.java");
  const registry = read("backend/src/main/java/com/easysubway/auth/adapter/out/security/SpringSecurityAnonymousUserRegistry.java");
  const redisRateLimitAdapter = read(
    "backend/src/main/java/com/easysubway/auth/adapter/out/redis/RedisAnonymousAuthRateLimitAdapter.java",
  );
  const clientIpProperties = read(
    "backend/src/main/java/com/easysubway/auth/adapter/in/web/AnonymousAuthClientIpProperties.java",
  );
  const clientIpResolver = read("backend/src/main/java/com/easysubway/auth/adapter/in/web/AnonymousAuthClientIpResolver.java");
  const controller = read("backend/src/main/java/com/easysubway/auth/adapter/in/web/AnonymousAuthController.java");
  const security = read("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java");
  const userDetailsManager = read("backend/src/main/java/com/easysubway/common/security/ConcurrentUserDetailsManager.java");
  const build = read("backend/build.gradle");
  const applicationDev = read("backend/src/main/resources/application-dev.yml");
  const applicationProd = read("backend/src/main/resources/application-prod.yml");

  assert.match(credentials, /record AnonymousUserCredentials/);
  assert.match(credentials, /userId/);
  assert.match(credentials, /password/);
  assert.match(credentials, /createdAt/);
  assert.match(authenticatedUser, /record AuthenticatedUser/);
  assert.match(authenticatedUser, /authType/);
  assert.match(authenticatedUser, /anonymous/);
  assert.match(invalidAuth, /extends InvalidRequestException/);
  assert.match(rateLimitExceeded, /extends RuntimeException/);
  assert.match(useCase, /interface AnonymousAuthUseCase/);
  assert.match(useCase, /issueAnonymousUser/);
  assert.match(useCase, /currentUser/);
  assert.match(rateLimitUseCase, /interface AnonymousAuthRateLimitUseCase/);
  assert.match(rateLimitUseCase, /check\(String clientKey\)/);
  assert.match(registerPort, /interface RegisterAnonymousUserPort/);
  assert.match(registerPort, /existsByUserId/);
  assert.match(registerPort, /isAnonymousUser/);
  assert.match(registerPort, /registerAnonymousUser/);
  assert.match(consumeRateLimitPort, /interface ConsumeAnonymousAuthRateLimitPort/);
  assert.match(consumeRateLimitPort, /consume\(String clientKey, Duration window\)/);
  assert.match(service, /implements AnonymousAuthUseCase/);
  assert.match(service, /RegisterAnonymousUserPort/);
  assert.match(rateLimitProperties, /@ConfigurationProperties\(prefix = "easysubway\.auth\.rate-limit\.anonymous"\)/);
  assert.match(rateLimitProperties, /maxRequests = 20/);
  assert.match(rateLimitProperties, /Duration\.ofMinutes\(10\)/);
  assert.match(rateLimitService, /implements AnonymousAuthRateLimitUseCase/);
  assert.match(rateLimitService, /ConsumeAnonymousAuthRateLimitPort/);
  assert.match(rateLimitService, /AnonymousAuthRateLimitExceededException/);
  assert.match(registry, /implements RegisterAnonymousUserPort/);
  assert.match(registry, /UserDetailsManager/);
  assert.match(registry, /PasswordEncoder/);
  assert.match(registry, /MAX_ANONYMOUS_USERS/);
  assert.match(registry, /deleteUser/);
  assert.match(userDetailsManager, /implements UserDetailsManager, UserDetailsPasswordService/);
  assert.match(userDetailsManager, /ConcurrentHashMap/);
  assert.doesNotMatch(security, /InMemoryUserDetailsManager/);
  assert.match(build, /spring-boot-starter-data-redis/);
  assert.match(redisRateLimitAdapter, /implements ConsumeAnonymousAuthRateLimitPort/);
  assert.match(redisRateLimitAdapter, /StringRedisTemplate/);
  assert.match(redisRateLimitAdapter, /RedisScript\.of/);
  assert.match(redisRateLimitAdapter, /redis\.call\('INCR'/);
  assert.match(redisRateLimitAdapter, /redis\.call\('PEXPIRE'/);
  assert.match(redisRateLimitAdapter, /easysubway:auth:anonymous:rate-limit:/);
  assert.doesNotMatch(redisRateLimitAdapter, /synchronized/);
  assert.match(clientIpProperties, /@ConfigurationProperties\(prefix = "easysubway\.auth\.client-ip"\)/);
  assert.match(clientIpProperties, /trustedProxies/);
  assert.match(clientIpResolver, /X-Forwarded-For/);
  assert.match(clientIpResolver, /firstUntrustedForwardedClientIp/);
  assert.match(clientIpResolver, /isTrustedProxy/);
  assert.match(clientIpResolver, /matchesCidr/);
  assert.match(clientIpResolver, /parseIpAddress/);
  assert.match(controller, /@PostMapping\("\/api\/v1\/auth\/anonymous"\)/);
  assert.match(controller, /AnonymousAuthRateLimitUseCase/);
  assert.match(controller, /AnonymousAuthClientIpResolver/);
  assert.doesNotMatch(controller, /request\.getRemoteAddr\(\)/);
  assert.match(controller, /HttpStatus\.TOO_MANY_REQUESTS/);
  assert.match(controller, /@GetMapping\("\/api\/v1\/me"\)/);
  assert.match(controller, /Principal principal/);
  assert.match(security, /securityMatcher\([\s\S]*"\/api\/v1\/me"/);
  assert.match(security, /Environment environment/);
  assert.match(security, /validateProdAdminCredentials/);
  assert.match(security, /getActiveProfiles\(\)/);
  assert.match(security, /운영 관리자 계정 설정이 필요합니다\./);
  assert.match(applicationDev, /redis:[\s\S]*host: \$\{EASYSUBWAY_REDIS_HOST:localhost\}/);
  assert.match(applicationDev, /redis:[\s\S]*port: \$\{EASYSUBWAY_REDIS_PORT:6379\}/);
  assert.match(applicationDev, /trusted-proxies: \$\{EASYSUBWAY_TRUSTED_PROXY_CIDRS:\}/);
  assert.match(applicationProd, /admin:[\s\S]*username: \$\{EASYSUBWAY_ADMIN_USERNAME\}/);
  assert.match(applicationProd, /admin:[\s\S]*password: \$\{EASYSUBWAY_ADMIN_PASSWORD\}/);
  assert.match(applicationProd, /redis:[\s\S]*host: \$\{EASYSUBWAY_REDIS_HOST\}/);
  assert.match(applicationProd, /redis:[\s\S]*port: \$\{EASYSUBWAY_REDIS_PORT:6379\}/);
  assert.match(applicationProd, /trusted-proxies: \$\{EASYSUBWAY_TRUSTED_PROXY_CIDRS\}/);
});

test("백엔드 인메모리 저장소는 운영 프로필에서 제외된다", () => {
  const files = inMemoryRepositoryFiles();
  const readinessConfiguration = read(
    "backend/src/main/java/com/easysubway/common/persistence/ProductionPersistenceReadinessConfiguration.java",
  );

  assert.ok(files.length >= 1, "InMemory repository files must be discovered");
  for (const file of files) {
    const source = read(file);
    assert.match(source, /import org\.springframework\.context\.annotation\.Profile;/, `${file} must import Profile`);
    assert.match(source, /@Repository\s+@Profile\("!prod"\)/, `${file} must be disabled on prod profile`);
  }
  assert.match(readinessConfiguration, /@Profile\("prod"\)/);
  assert.match(readinessConfiguration, /BeanFactoryPostProcessor/);
  assert.match(readinessConfiguration, /운영 영속 저장소 구현이 필요합니다\./);
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
  const controller = read("backend/src/main/java/com/easysubway/user/adapter/in/web/UserDataController.java");
  const registry = read("backend/src/main/java/com/easysubway/auth/adapter/out/security/SpringSecurityAnonymousUserRegistry.java");
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
  assert.match(result, /anonymousCredentialsDeleted/);
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
  assert.match(service, /RegisterAnonymousUserPort/);
  assert.match(service, /DeleteUserFavoriteStationPort/);
  assert.match(service, /DeleteUserFavoriteFacilityPort/);
  assert.match(service, /DeleteUserFavoriteRoutePort/);
  assert.match(service, /AnonymizeUserRouteFeedbackPort/);
  assert.match(service, /DeleteUserNotificationPreferencePort/);
  assert.match(service, /DeleteUserPushNotificationPort/);
  assert.match(service, /DeleteUserMobilityProfilePort/);
  assert.match(service, /AnonymizeUserFacilityReportPort/);
  assert.match(service, /deleteAnonymousUser\(normalizedUserId\)/);
  assert.match(controller, /@DeleteMapping\("\/api\/v1\/me"\)/);
  assert.match(controller, /Principal principal/);
  assert.match(controller, /principal\.getName\(\)/);
  assert.match(controller, /UserDataDeletionUseCase/);
  assert.match(registry, /boolean deleteAnonymousUser\(String userId\)/);
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
  assert.match(security, /securityMatcher\([\s\S]*"\/api\/v1\/me"/);
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
  const adminUseCase = read("backend/src/main/java/com/easysubway/transit/application/port/in/TransitMasterAdminUseCase.java");
  const updateStatusCommand = read(
    "backend/src/main/java/com/easysubway/transit/application/port/in/UpdateAccessibilityFacilityStatusCommand.java",
  );
  const outboundPort = read("backend/src/main/java/com/easysubway/transit/application/port/out/LoadTransitMasterPort.java");
  const saveFacilityStatusPort = read(
    "backend/src/main/java/com/easysubway/transit/application/port/out/SaveAccessibilityFacilityStatusPort.java",
  );
  const service = read("backend/src/main/java/com/easysubway/transit/application/service/TransitMasterService.java");
  const repository = read("backend/src/main/java/com/easysubway/transit/adapter/out/persistence/InMemoryTransitMasterRepository.java");
  const controller = read("backend/src/main/java/com/easysubway/transit/adapter/in/web/TransitMasterController.java");
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
  assert.match(useCase, /listStationExits/);
  assert.match(useCase, /listStationFacilities/);
  assert.match(adminUseCase, /interface TransitMasterAdminUseCase/);
  assert.match(adminUseCase, /updateFacilityStatus/);
  assert.match(updateStatusCommand, /record UpdateAccessibilityFacilityStatusCommand/);
  assert.match(updateStatusCommand, /AccessibilityFacilityStatus status/);
  assert.match(updateStatusCommand, /String updatedBy/);
  assert.match(outboundPort, /interface LoadTransitMasterPort/);
  assert.match(outboundPort, /loadStationExits/);
  assert.match(outboundPort, /loadAccessibilityFacilities/);
  assert.match(outboundPort, /loadStation\(String stationId\)/);
  assert.match(outboundPort, /loadAccessibilityFacility\(String facilityId\)/);
  assert.match(saveFacilityStatusPort, /interface SaveAccessibilityFacilityStatusPort/);
  assert.match(saveFacilityStatusPort, /saveFacilityStatus/);
  assert.match(service, /implements TransitMasterQueryUseCase, TransitMasterAdminUseCase/);
  assert.match(service, /SaveAccessibilityFacilityStatusPort/);
  assert.match(service, /updateFacilityStatus\(UpdateAccessibilityFacilityStatusCommand command\)/);
  assert.match(service, /InvalidAccessibilityFacilityException\("시설 상태를 선택해야 합니다\."\)/);
  assert.match(repository, /implements LoadTransitMasterPort, SaveAccessibilityFacilityStatusPort/);
  assert.match(controller, /@GetMapping\("\/api\/v1\/operators"\)/);
  assert.match(controller, /@GetMapping\("\/api\/v1\/lines"\)/);
  assert.match(controller, /@GetMapping\("\/api\/v1\/stations"\)/);
  assert.match(controller, /@GetMapping\("\/api\/v1\/stations\/\{stationId\}"\)/);
  assert.match(controller, /@GetMapping\("\/api\/v1\/stations\/\{stationId\}\/exits"\)/);
  assert.match(controller, /@GetMapping\("\/api\/v1\/stations\/\{stationId\}\/facilities"\)/);
  assert.match(controller, /@PatchMapping\("\/admin\/facilities\/\{facilityId\}\/status"\)/);
  assert.match(controller, /TransitMasterAdminUseCase/);
  assert.match(controller, /Principal principal/);
  assert.match(exceptionHandler, /@ExceptionHandler\(HttpMessageNotReadableException\.class\)/);
  assert.match(exceptionHandler, /@ExceptionHandler\(InvalidRequestException\.class\)/);
  assert.match(exceptionHandler, /@ExceptionHandler\(ResourceNotFoundException\.class\)/);
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
  const saveFacilityStatusPort = read(
    "backend/src/main/java/com/easysubway/transit/application/port/out/SaveAccessibilityFacilityStatusPort.java",
  );
  const service = read("backend/src/main/java/com/easysubway/report/application/service/FacilityReportService.java");
  const repository = read("backend/src/main/java/com/easysubway/report/adapter/out/persistence/InMemoryFacilityReportRepository.java");
  const jdbcRepository = read("backend/src/main/java/com/easysubway/report/adapter/out/persistence/JdbcFacilityReportRepository.java");
  const transitRepository = read(
    "backend/src/main/java/com/easysubway/transit/adapter/out/persistence/InMemoryTransitMasterRepository.java",
  );
  const batchPostgresSchema = read("backend/src/main/resources/db/batch/schema-postgresql.sql");
  const controller = read("backend/src/main/java/com/easysubway/report/adapter/in/web/FacilityReportController.java");
  const security = read("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java");

  assert.match(report, /record FacilityReport/);
  assert.match(report, /reviewedAt/);
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
  assert.match(useCase, /getReport/);
  assert.match(useCase, /listReports/);
  assert.match(useCase, /reviewReport/);
  assert.match(command, /record CreateFacilityReportCommand/);
  assert.match(reviewCommand, /record ReviewFacilityReportCommand/);
  assert.match(loadPort, /interface LoadFacilityReportPort/);
  assert.match(loadPort, /loadReports/);
  assert.match(savePort, /interface SaveFacilityReportPort/);
  assert.match(saveFacilityStatusPort, /interface SaveAccessibilityFacilityStatusPort/);
  assert.match(saveFacilityStatusPort, /saveFacilityStatus/);
  assert.match(service, /implements FacilityReportUseCase/);
  assert.match(service, /LoadTransitMasterPort/);
  assert.match(service, /SaveAccessibilityFacilityStatusPort/);
  assert.match(service, /applyAcceptedReportToFacilityStatus/);
  assert.match(service, /case BROKEN -> Optional\.of\(AccessibilityFacilityStatus\.BROKEN\)/);
  assert.match(service, /case RECOVERED -> Optional\.of\(AccessibilityFacilityStatus\.NORMAL\)/);
  assert.match(service, /listReports\(FacilityReportStatus status\)/);
  assert.match(service, /Comparator\.comparing\(FacilityReport::createdAt\)\.reversed\(\)/);
  assert.match(service, /FacilityReportStatus\.SUBMITTED/);
  assert.match(service, /FacilityReportStatus\.ACCEPTED/);
  assert.match(service, /FacilityReportStatus\.REJECTED/);
  assert.match(service, /FacilityReportStatus\.DUPLICATE/);
  assert.match(repository, /implements[\s\S]*LoadFacilityReportPort[\s\S]*SaveFacilityReportPort/);
  assert.match(repository, /List<FacilityReport> loadReports\(\)/);
  assert.match(jdbcRepository, /@Profile\("prod"\)/);
  assert.match(jdbcRepository, /implements[\s\S]*LoadFacilityReportPort[\s\S]*SaveFacilityReportPort[\s\S]*AnonymizeUserFacilityReportPort/);
  assert.match(jdbcRepository, /Optional<FacilityReport> loadReport\(String reportId\)/);
  assert.match(jdbcRepository, /List<FacilityReport> loadReports\(\)/);
  assert.match(jdbcRepository, /FacilityReport saveReport\(FacilityReport report\)/);
  assert.match(jdbcRepository, /int anonymizeFacilityReportsByUserId\(String userId\)/);
  assert.match(jdbcRepository, /ON CONFLICT \(report_id\) DO UPDATE/);
  assert.match(jdbcRepository, /FacilityReport\.ANONYMIZED_USER_ID/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS facility_reports/);
  assert.match(batchPostgresSchema, /photo_data_base64 TEXT/);
  assert.match(batchPostgresSchema, /CONSTRAINT fk_facility_reports_duplicate/);
  assert.match(batchPostgresSchema, /FOREIGN KEY \(duplicate_of_report_id\) REFERENCES facility_reports\(report_id\)/);
  assert.match(batchPostgresSchema, /CONSTRAINT chk_facility_reports_report_type/);
  assert.match(batchPostgresSchema, /CHECK \(report_type IN \('BROKEN', 'UNDER_CONSTRUCTION', 'CLOSED', 'LOCATION_WRONG', 'INFORMATION_WRONG', 'RECOVERED'\)\)/);
  assert.match(batchPostgresSchema, /CONSTRAINT chk_facility_reports_status/);
  assert.match(batchPostgresSchema, /CHECK \(status IN \('SUBMITTED', 'DUPLICATE', 'UNDER_REVIEW', 'ACCEPTED', 'REJECTED', 'RESOLVED'\)\)/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_facility_reports_created/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_facility_reports_user/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_facility_reports_status_created/);
  assert.match(transitRepository, /implements LoadTransitMasterPort, SaveAccessibilityFacilityStatusPort/);
  assert.match(transitRepository, /saveFacilityStatus\(String facilityId, AccessibilityFacilityStatus status, LocalDate updatedAt\)/);
  assert.match(controller, /@PostMapping\("\/api\/v1\/reports"\)/);
  assert.match(controller, /@GetMapping\("\/api\/v1\/reports\/\{reportId\}"\)/);
  assert.match(controller, /@GetMapping\("\/admin\/reports"\)/);
  assert.match(controller, /@GetMapping\("\/admin\/reports\/\{reportId\}"\)/);
  assert.match(controller, /@RequestParam\(required = false\) FacilityReportStatus status/);
  assert.match(controller, /@PostMapping\("\/admin\/reports\/\{reportId\}\/review"\)/);
  assert.match(controller, /Principal principal/);
  assert.match(controller, /principal\.getName\(\)/);
  assert.match(controller, /@ResponseStatus\(HttpStatus\.CREATED\)/);
  assert.match(security, /securityMatcher\("\/admin\/\*\*"\)/);
  assert.match(security, /anyRequest\(\)\.hasRole\("ADMIN"\)/);
  assert.match(security, /anyRequest\(\)\.permitAll\(\)/);
  assert.match(security, /httpBasic/);
  assert.match(security, /PasswordEncoder/);
  assert.match(security, /passwordEncoder\.encode\(adminPassword\)/);
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
  const batchPostgresSchema = read("backend/src/main/resources/db/batch/schema-postgresql.sql");
  const controller = read("backend/src/main/java/com/easysubway/profile/adapter/in/web/MobilityProfileController.java");

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
  assert.match(controller, /@GetMapping\("\/api\/v1\/me\/mobility-profile"\)/);
  assert.match(controller, /@PutMapping\("\/api\/v1\/me\/mobility-profile"\)/);
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
  const batchPostgresSchema = read("backend/src/main/resources/db/batch/schema-postgresql.sql");
  const controller = read("backend/src/main/java/com/easysubway/favorite/adapter/in/web/FavoriteStationController.java");
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
  assert.match(controller, /@GetMapping\("\/api\/v1\/me\/favorites\/stations"\)/);
  assert.match(controller, /@PutMapping\("\/api\/v1\/me\/favorites\/stations\/\{stationId\}"\)/);
  assert.match(controller, /@DeleteMapping\("\/api\/v1\/me\/favorites\/stations\/\{stationId\}"\)/);
  assert.match(controller, /Principal principal/);
  assert.doesNotMatch(controller, /RequestParam\(required = false\) String userId/);
  assert.match(security, /securityMatcher\([\s\S]*"\/api\/v1\/me\/favorites\/\*\*"/);
  assert.match(security, /anyRequest\(\)\.authenticated\(\)/);
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
  const batchPostgresSchema = read("backend/src/main/resources/db/batch/schema-postgresql.sql");
  const controller = read("backend/src/main/java/com/easysubway/favorite/adapter/in/web/FavoriteFacilityController.java");
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
  assert.match(controller, /@GetMapping\("\/api\/v1\/me\/favorites\/facilities"\)/);
  assert.match(controller, /@PutMapping\("\/api\/v1\/me\/favorites\/facilities\/\{facilityId\}"\)/);
  assert.match(controller, /@DeleteMapping\("\/api\/v1\/me\/favorites\/facilities\/\{facilityId\}"\)/);
  assert.match(controller, /Principal principal/);
  assert.match(controller, /AccessibilityFacilityStatus/);
  assert.match(controller, /DataConfidenceLevel/);
  assert.doesNotMatch(controller, /RequestParam\(required = false\) String userId/);
  assert.match(security, /securityMatcher\([\s\S]*"\/api\/v1\/me\/favorites\/\*\*"/);
  assert.match(security, /anyRequest\(\)\.authenticated\(\)/);
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
  const batchPostgresSchema = read("backend/src/main/resources/db/batch/schema-postgresql.sql");
  const controller = read("backend/src/main/java/com/easysubway/favorite/adapter/in/web/FavoriteRouteController.java");
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
  assert.match(controller, /@GetMapping\("\/api\/v1\/me\/favorites\/routes"\)/);
  assert.match(controller, /@PostMapping\("\/api\/v1\/me\/favorites\/routes"\)/);
  assert.match(controller, /@DeleteMapping\("\/api\/v1\/me\/favorites\/routes\/\{favoriteRouteId\}"\)/);
  assert.match(controller, /Principal principal/);
  assert.doesNotMatch(controller, /RequestParam\(required = false\) String userId/);
  assert.match(security, /securityMatcher\([\s\S]*"\/api\/v1\/me\/favorites\/\*\*"/);
  assert.match(security, /anyRequest\(\)\.authenticated\(\)/);
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
  const batchPostgresSchema = read("backend/src/main/resources/db/batch/schema-postgresql.sql");
  const controller = read("backend/src/main/java/com/easysubway/notification/adapter/in/web/NotificationPreferenceController.java");
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
  assert.match(controller, /@PostMapping\("\/api\/v1\/devices"\)/);
  assert.match(controller, /@GetMapping\("\/api\/v1\/me\/notification-settings"\)/);
  assert.match(controller, /@PutMapping\("\/api\/v1\/me\/notification-settings"\)/);
  assert.match(controller, /Principal principal/);
  assert.doesNotMatch(controller, /RequestParam\(required = false\) String userId/);
  assert.match(security, /securityMatcher\([\s\S]*"\/api\/v1\/me\/favorites\/\*\*"[\s\S]*"\/api\/v1\/devices"[\s\S]*"\/api\/v1\/me\/notification-settings"[\s\S]*\)/);
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
  const batchPostgresSchema = read("backend/src/main/resources/db/batch/schema-postgresql.sql");
  const controller = read("backend/src/main/java/com/easysubway/notification/adapter/in/web/PushNotificationController.java");
  const dashboardController = read(
    "backend/src/main/java/com/easysubway/notification/adapter/in/web/PushNotificationAdminPageController.java",
  );
  const dashboardTemplate = read("backend/src/main/resources/templates/admin/notifications/push.html");
  const security = read("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java");

  assert.match(notification, /record PushNotification/);
  assert.match(notification, /deviceToken/);
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
  assert.match(jdbcRepository, /PushNotificationDashboardSummary summarizePushNotificationOutbox\(\)/);
  assert.match(jdbcRepository, /int deletePushNotifications\(String userId\)/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS push_notification_outbox/);
  assert.match(batchPostgresSchema, /CONSTRAINT chk_push_notification_outbox_platform/);
  assert.match(batchPostgresSchema, /CONSTRAINT chk_push_notification_outbox_type/);
  assert.match(batchPostgresSchema, /CONSTRAINT chk_push_notification_outbox_status/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_push_notification_outbox_user_created/);
  assert.match(controller, /@PostMapping\("\/admin\/notifications\/push"\)/);
  assert.match(controller, /PushNotificationDispatchUseCase/);
  assert.doesNotMatch(controller, /deviceToken/);
  assert.match(dashboardController, /@GetMapping\("\/admin\/notifications\/push\/page"\)/);
  assert.match(dashboardController, /PushNotificationDashboardUseCase/);
  assert.match(dashboardTemplate, /푸시 알림 현황/);
  assert.match(dashboardTemplate, /전체 알림/);
  assert.match(dashboardTemplate, /상태별 알림/);
  assert.doesNotMatch(dashboardTemplate, /deviceToken/);
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
  const batchPostgresSchema = read("backend/src/main/resources/db/batch/schema-postgresql.sql");
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
  assert.match(applicationProd, /schema-locations: classpath:db\/batch\/schema-postgresql\.sql/);
  assert.match(applicationProd, /batch:[\s\S]*jdbc:[\s\S]*initialize-schema: never/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS BATCH_JOB_INSTANCE/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS BATCH_JOB_EXECUTION/);
  assert.match(batchPostgresSchema, /CREATE SEQUENCE IF NOT EXISTS BATCH_JOB_SEQ/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS data_collection_runs/);
  assert.match(batchPostgresSchema, /run_id VARCHAR\(80\) NOT NULL PRIMARY KEY/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_data_collection_runs_started_at/);
  assert.match(run, /record DataCollectionRun/);
  assert.match(run, /requestedBy/);
  assert.match(run, /collectedCount/);
  assert.match(run, /status == DataCollectionStatus\.COMPLETED[\s\S]*completedAt == null/);
  assert.match(run, /status == DataCollectionStatus\.FAILED[\s\S]*failureMessage/);
  assert.match(source, /TRANSIT_MASTER/);
  assert.match(status, /RUNNING/);
  assert.match(status, /COMPLETED/);
  assert.match(status, /FAILED/);
  assert.match(invalidCollection, /extends InvalidRequestException/);
  assert.match(invalidCollection, /Throwable cause/);
  assert.match(useCase, /interface DataCollectionUseCase/);
  assert.match(useCase, /runCollection/);
  assert.match(useCase, /listRecentRuns/);
  assert.match(command, /record RunDataCollectionCommand/);
  assert.match(loadRunPort, /interface LoadDataCollectionRunPort/);
  assert.match(saveRunPort, /interface SaveDataCollectionRunPort/);
  assert.match(service, /implements DataCollectionUseCase/);
  assert.match(service, /JobLauncher/);
  assert.match(service, /transitMasterCollectionJob/);
  assert.match(service, /InvalidDataCollectionException\("데이터 수집 배치를 실행하지 못했습니다\.", exception\)/);
  assert.match(service, /loadRun\(runId\)/);
  assert.match(recorder, /LoadTransitMasterPort/);
  assert.match(recorder, /recordTransitMasterRun/);
  assert.match(recorder, /catch \(RuntimeException exception\)/);
  assert.match(recorder, /DataCollectionStatus\.FAILED/);
  assert.match(repository, /implements[\s\S]*LoadDataCollectionRunPort[\s\S]*SaveDataCollectionRunPort/);
  assert.match(repository, /@Profile\("!prod"\)/);
  assert.match(repository, /loadRun\(String runId\)/);
  assert.match(jdbcRepository, /@Profile\("prod"\)/);
  assert.match(jdbcRepository, /implements[\s\S]*LoadDataCollectionRunPort[\s\S]*SaveDataCollectionRunPort/);
  assert.match(jdbcRepository, /JdbcTemplate/);
  assert.match(jdbcRepository, /INSERT INTO data_collection_runs/);
  assert.match(jdbcRepository, /ORDER BY started_at DESC, run_id DESC/);
  assert.match(controller, /@PostMapping\("\/admin\/data-collections\/runs"\)/);
  assert.match(controller, /@GetMapping\("\/admin\/data-collections\/runs"\)/);
  assert.match(controller, /@Valid @RequestBody RunDataCollectionRequest/);
  assert.match(controller, /@NotNull\(message = "수집 대상을 선택해야 합니다\."\)/);
  assert.match(controller, /Principal principal/);
  assert.match(batchConfig, /new JobBuilder\(JOB_NAME, jobRepository\)/);
  assert.match(batchConfig, /new StepBuilder\(STEP_NAME, jobRepository\)/);
  assert.match(batchConfig, /DataCollectionRunRecorder/);
  assert.doesNotMatch(batchConfig, /getOrDefault\("requestedBy"/);
  assert.match(security, /securityMatcher\("\/admin\/\*\*"\)/);
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
  assert.match(useCase, /interface DataQualityUseCase/);
  assert.match(useCase, /summarizeDataQuality/);
  assert.match(service, /implements DataQualityUseCase/);
  assert.match(service, /LoadTransitMasterPort/);
  assert.match(service, /DataConfidenceLevel\.NEEDS_VERIFICATION/);
  assert.match(service, /AccessibilityFacilityStatus\.UNKNOWN/);
  assert.match(service, /FACILITY_STATUS_DELAY_DAYS = 30/);
  assert.match(controller, /@GetMapping\("\/admin\/data-quality\/summary"\)/);
  assert.match(controller, /DataQualityUseCase/);
  assert.match(adminController, /@GetMapping\("\/admin\/data-quality\/page"\)/);
  assert.match(adminController, /TransitMasterQueryUseCase/);
  assert.match(adminController, /listRegions/);
  assert.match(adminController, /FacilityReportUseCase/);
  assert.match(adminController, /listReports\(null\)/);
  assert.match(adminController, /isVerifiedReportStatus/);
  assert.match(adminTemplate, /지역별 데이터 품질/);
  assert.match(adminTemplate, /갱신 지연 시설/);
  assert.match(adminTemplate, /시설 상태 갱신 지연/);
  assert.match(adminTemplate, /사용자 제보 검증률/);
  assert.match(adminTemplate, /제보 검증률/);
  assert.match(adminTemplate, /Level 1/);
  assert.match(adminTemplate, /Level 4/);
  assert.doesNotMatch(adminTemplate, /reportId|stationId|exitId|facilityId/);
  assert.match(security, /securityMatcher\("\/admin\/\*\*"\)/);
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
  const controller = read("backend/src/main/java/com/easysubway/route/adapter/in/web/RouteSearchController.java");
  const searchDashboardController = read(
    "backend/src/main/java/com/easysubway/route/adapter/in/web/RouteSearchAdminPageController.java",
  );
  const feedbackDashboardController = read(
    "backend/src/main/java/com/easysubway/route/adapter/in/web/RouteFeedbackAdminPageController.java",
  );
  const searchDashboardTemplate = read("backend/src/main/resources/templates/admin/routes/searches.html");
  const feedbackDashboardTemplate = read("backend/src/main/resources/templates/admin/routes/feedback.html");
  const batchPostgresSchema = read("backend/src/main/resources/db/batch/schema-postgresql.sql");

  assert.match(result, /record RouteSearchResult/);
  assert.match(result, /mobilityType/);
  assert.match(result, /blockedReasons/);
  assert.match(searchSummary, /record RouteSearchDashboardSummary/);
  assert.match(searchSummary, /foundCount/);
  assert.match(searchSummary, /blockedCount/);
  assert.match(searchSummary, /MobilityTypeCount/);
  assert.match(feedbackSummary, /record RouteFeedbackDashboardSummary/);
  assert.match(feedbackSummary, /helpfulCount/);
  assert.match(feedbackSummary, /notHelpfulCount/);
  assert.match(feedbackSummary, /blockedByRealWorldCount/);
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
  assert.match(jdbcRepository, /GROUP BY status, mobility_type/);
  assert.match(jdbcRepository, /same DB statement snapshot|같은 DB statement snapshot/);
  assert.match(jdbcRepository, /RouteFeedbackDashboardSummary summarizeRouteFeedbacks\(\)/);
  assert.match(jdbcRepository, /SUM\(CASE WHEN rating = 'HELPFUL' THEN 1 ELSE 0 END\)/);
  assert.match(jdbcRepository, /ON CONFLICT \(route_search_id\) DO UPDATE/);
  assert.match(jdbcRepository, /ON CONFLICT \(feedback_id\) DO UPDATE/);
  assert.match(jdbcRepository, /steps_json/);
  assert.match(jdbcRepository, /warnings_json/);
  assert.match(jdbcRepository, /blocked_reasons_json/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS route_search_results/);
  assert.match(batchPostgresSchema, /CREATE TABLE IF NOT EXISTS route_feedbacks/);
  assert.match(batchPostgresSchema, /CHECK \(status IN \('FOUND', 'BLOCKED'\)\)/);
  assert.match(batchPostgresSchema, /CHECK \(rating IN \('HELPFUL', 'NOT_HELPFUL', 'BLOCKED_BY_REAL_WORLD'\)\)/);
  assert.match(controller, /@PostMapping\("\/api\/v1\/routes\/search"\)/);
  assert.match(controller, /@GetMapping\("\/api\/v1\/routes\/\{routeSearchId\}"\)/);
  assert.match(searchDashboardController, /@GetMapping\("\/admin\/routes\/searches\/page"\)/);
  assert.match(searchDashboardController, /RouteSearchDashboardUseCase/);
  assert.match(searchDashboardTemplate, /경로 검색 현황/);
  assert.match(searchDashboardTemplate, /전체 검색/);
  assert.match(searchDashboardTemplate, /이동 프로필별 검색/);
  assert.doesNotMatch(searchDashboardTemplate, /routeSearchId/);
  assert.match(feedbackDashboardController, /@GetMapping\("\/admin\/routes\/feedback\/page"\)/);
  assert.match(feedbackDashboardController, /RouteFeedbackDashboardUseCase/);
  assert.match(feedbackDashboardTemplate, /경로 피드백 현황/);
  assert.match(feedbackDashboardTemplate, /전체 피드백/);
  assert.match(feedbackDashboardTemplate, /평점별 피드백/);
  assert.doesNotMatch(feedbackDashboardTemplate, /userId/);
});

test("모바일 스캐폴드는 Flutter Android와 iOS 앱 구조를 가진다", () => {
  const pubspec = read("apps/mobile/pubspec.yaml");
  const analysisOptions = read("apps/mobile/analysis_options.yaml");
  const androidManifest = read("apps/mobile/android/app/src/main/AndroidManifest.xml");
  const androidBuildGradle = read("apps/mobile/android/app/build.gradle.kts");
  const envExample = read(".env.example");
  const iosInfoPlist = read("apps/mobile/ios/Runner/Info.plist");
  const main = read("apps/mobile/lib/main.dart");
  const authHeaders = read("apps/mobile/lib/auth_headers.dart");
  const anonymousAuth = read("apps/mobile/lib/anonymous_auth.dart");
  const anonymousAuthTest = read("apps/mobile/test/anonymous_auth_test.dart");
  const onboarding = read("apps/mobile/lib/onboarding.dart");
  const onboardingTest = read("apps/mobile/test/onboarding_test.dart");
  const routeSearch = read("apps/mobile/lib/route_search.dart");
  const stationSearch = read("apps/mobile/lib/station_search.dart");
  const mapAdapter = read("apps/mobile/lib/map_adapter.dart");
  const mapAdapterTest = read("apps/mobile/test/map_adapter_test.dart");
  const facilityReport = read("apps/mobile/lib/facility_report.dart");
  const facilityReportTest = read("apps/mobile/test/facility_report_test.dart");
  const notificationSettings = read("apps/mobile/lib/notification_settings.dart");
  const notificationSettingsTest = read("apps/mobile/test/notification_settings_test.dart");
  const widgetTest = read("apps/mobile/test/widget_test.dart");

  assert.ok(existsSync(path.join(root, "apps/mobile/android")));
  assert.ok(existsSync(path.join(root, "apps/mobile/ios")));
  assert.ok(existsSync(path.join(root, "apps/mobile/pubspec.lock")));

  assert.match(pubspec, /^name: easysubway_mobile$/m);
  assert.match(pubspec, /sdk: \^3\./);
  assert.match(pubspec, /flutter_lints:/);
  assert.match(pubspec, /flutter_secure_storage:/);
  assert.match(pubspec, /uses-material-design: true/);
  assert.match(analysisOptions, /package:flutter_lints\/flutter\.yaml/);
  assert.match(androidManifest, /android:label="쉬운 지하철"/);
  assert.match(androidManifest, /android:allowBackup="false"/);
  assert.match(androidManifest, /android:fullBackupContent="false"/);
  assert.match(androidManifest, /<uses-permission android:name="android\.permission\.INTERNET"\/>/);
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
  assert.match(main, /AnonymousAuthSession/);
  assert.match(main, /FavoriteStationApiRepository/);
  assert.match(main, /NotificationSettingsApiRepository/);
  assert.match(main, /OnboardingScreen/);
  assert.match(main, /initialOnboardingState/);
  assert.match(main, /initialMobilityType: onboardingResult\?\.profile\.mobilityType/);
  assert.match(main, /initialMobilityType: initialMobilityType/);
  assert.match(main, /_OnboardingPreferenceScope/);
  assert.match(main, /mediaQuery\.textScaler\.clamp\(minScaleFactor: 1\.18\)/);
  assert.match(main, /highContrast:[\s\S]*preferences\.highContrastEnabled \|\| mediaQuery\.highContrast/);
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
  assert.match(onboarding, /큰 글씨/);
  assert.match(onboarding, /고대비/);
  assert.match(onboarding, /단순 보기/);
  assert.match(onboarding, /onTap: \(\) => onChanged\(!value\)/);
  assert.match(routeSearch, /final String initialMobilityType/);
  assert.match(routeSearch, /final bool simpleViewEnabled/);
  assert.match(routeSearch, /_resolveInitialMobilityType/);
  assert.match(routeSearch, /_selectedMobilityType = widget\.initialMobilityType/);
  assert.match(routeSearch, /_RouteMobilityTypeSummary\([\s\S]*mobilityType: _selectedMobilityType[\s\S]*onChangeRequested: _showMobilityTypePicker/);
  assert.match(routeSearch, /routeSimpleMobilityTypeButton/);
  assert.match(routeSearch, /routeMobilityOption-\$\{option\.mobilityType\}/);
  assert.match(widgetTest, /첫 실행 앱은 온보딩을 완료한 뒤 홈으로 이동한다/);
  assert.match(widgetTest, /온보딩 이동 조건은 경로 검색 기본값으로 이어진다/);
  assert.match(widgetTest, /온보딩 보기 설정은 완료 뒤 홈 UI에 적용된다/);
  assert.match(widgetTest, /MediaQuery\.textScalerOf/);
  assert.match(onboardingTest, /온보딩은 이동 조건과 보기 설정을 선택한 뒤 완료 결과를 반환한다/);
  assert.match(onboardingTest, /hasTapAction: true/);
  assert.match(authHeaders, /abstract class AuthorizationHeaderProvider/);
  assert.match(authHeaders, /class BasicAuthorizationHeaderProvider implements AuthorizationHeaderProvider/);
  assert.match(authHeaders, /authorizationHeader/);
  assert.match(authHeaders, /invalidateAuthorization/);
  assert.match(anonymousAuth, /class AnonymousAuthApiRepository implements AnonymousAuthRepository/);
  assert.match(anonymousAuth, /class SecureAnonymousAuthCredentialStore/);
  assert.match(anonymousAuth, /FlutterSecureStorage/);
  assert.match(anonymousAuth, /readCredentials/);
  assert.match(anonymousAuth, /saveCredentials/);
  assert.match(anonymousAuth, /clearCredentials/);
  assert.match(anonymousAuth, /canReuseStoredCredentials/);
  assert.match(anonymousAuth, /POST|postUrl/);
  assert.match(anonymousAuth, /\/api\/v1\/auth\/anonymous/);
  assert.match(anonymousAuth, /class AnonymousAuthSession implements AuthorizationHeaderProvider/);
  assert.match(anonymousAuth, /_credentials/);
  assert.match(anonymousAuth, /_loadOrIssueCredentials/);
  assert.match(anonymousAuth, /invalidateAuthorization/);
  assert.doesNotMatch(
    anonymousAuth,
    /Future<void>\s+invalidateAuthorization\(\)\s+async\s+\{[^}]*_issuingCredentials\s*=/,
  );
  assert.match(anonymousAuth, /_isAllowedAnonymousAuthBaseUri/);
  assert.match(anonymousAuth, /_isIpv4LoopbackLiteral/);
  assert.match(anonymousAuth, /allowAndroidEmulatorHttp = kDebugMode/);
  assert.match(anonymousAuth, /allowAndroidEmulatorHttp && host == '10\.0\.2\.2'/);
  assert.match(anonymousAuth, /10\.0\.2\.2/);
  assert.match(anonymousAuthTest, /저장된 인증 정보를 먼저 사용한다/);
  assert.match(anonymousAuthTest, /재시작 후 재사용한다/);
  assert.match(anonymousAuthTest, /인증 실패 후 저장된 인증 정보를 지우고 다시 발급한다/);
  assert.match(anonymousAuthTest, /동시 인증 무효화 후 하나의 새 인증 정보를 공유한다/);
  assert.match(anonymousAuthTest, /원격 HTTP 주소에서 저장된 Basic 인증 정보를 재사용하지 않는다/);
  assert.ok(existsSync(path.join(root, "apps/mobile/lib/station_search.dart")));
  assert.match(stationSearch, /typedef FavoriteStationAuthProvider = AuthorizationHeaderProvider/);
  assert.match(stationSearch, /final double\? latitude/);
  assert.match(stationSearch, /final double\? longitude/);
  assert.match(stationSearch, /_optionalDouble\(json, 'latitude'\)/);
  assert.match(stationSearch, /_optionalDouble\(json, 'longitude'\)/);
  assert.match(stationSearch, /_httpClient\s*\.\s*getUrl\(uri\)\s*\.\s*timeout\(_stationSearchTimeout\)/);
  assert.match(stationSearch, /request\.close\(\)\.timeout\(_stationSearchTimeout\)/);
  assert.match(stationSearch, /HttpStatus\.unauthorized/);
  assert.match(stationSearch, /invalidateAuthorization\(\)/);
  assert.match(stationSearch, /package:flutter\/foundation\.dart/);
  assert.match(stationSearch, /const configuredBaseUrl = String\.fromEnvironment\('EASYSUBWAY_API_BASE_URL'\)/);
  assert.match(stationSearch, /isReleaseMode: kReleaseMode/);
  assert.match(stationSearch, /Uri stationApiBaseUriForEnvironment\(/);
  assert.match(stationSearch, /Release API base URL must be configured\./);
  assert.match(stationSearch, /Release API base URL must use HTTPS\./);
  assert.match(stationSearch, /baseUri\.host\.isEmpty/);
  assert.match(stationSearch, /Release API base URL must include a host\./);
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
  assert.match(mapAdapterTest, /지도 제공자는 네이버를 기본값으로 두고 카카오를 대체 후보로 둔다/);
  assert.match(mapAdapterTest, /지도 어댑터는 좌표가 있는 역 출구 시설만 쉬운 이름의 마커로 만든다/);
  assert.match(facilityReport, /Future<FacilityReportResult> getReport\(String reportId\)/);
  assert.match(facilityReport, /\/api\/v1\/reports\/\$\{Uri\.encodeComponent\(trimmedReportId\)\}/);
  assert.match(facilityReport, /refreshCurrentReport/);
  assert.match(facilityReport, /처리 상태 확인 중/);
  assert.match(facilityReport, /접수번호/);
  assert.match(facilityReport, /facilityReportRefreshButton/);
  assert.match(facilityReportTest, /접수번호로 처리 상태를 조회한다/);
  assert.match(facilityReportTest, /접수 후 처리 상태를 다시 확인한다/);
  assert.match(widgetTest, /신고 접수번호 report-1, 현재 상태 반영됨/);
  assert.match(notificationSettings, /class NotificationSettingsApiRepository/);
  assert.match(notificationSettings, /\/api\/v1\/me\/notification-settings/);
  assert.match(notificationSettings, /AuthorizationHeaderProvider/);
  assert.match(notificationSettings, /HttpStatus\.unauthorized/);
  assert.match(notificationSettings, /class NotificationSettingsController extends ChangeNotifier/);
  assert.match(notificationSettings, /class NotificationSettingsScreen extends StatefulWidget/);
  assert.match(notificationSettings, /역 시설 알림/);
  assert.match(notificationSettings, /경로 시설 알림/);
  assert.match(notificationSettings, /신고 처리 알림/);
  assert.match(notificationSettings, /정보 갱신 알림/);
  assert.match(notificationSettingsTest, /인증 실패 시 인증을 지우고 한 번 재시도한다/);
  assert.match(notificationSettingsTest, /알림 설정 컨트롤러는 조회와 저장 상태를 구분한다/);
  assert.doesNotMatch(main, /빠른 길보다, 갈 수 있는 길을 먼저 안내합니다|고령자, 임산부, 장애인도 편하게 이동할 수 있도록|현장에서 발견한 불편 정보를 신고하고 검수할 수 있게/);
  assert.match(widgetTest, /EasySubwayApp/);
  assert.match(widgetTest, /홈 화면은 핵심 행동과 보조 행동을 나누어 보여준다/);
  assert.match(widgetTest, /홈 즐겨찾기는 하나의 진입점에서 탭 목록을 바로 보여준다/);
  assert.match(widgetTest, /알림 설정 화면은 현재 설정을 불러오고 바꾼 값을 저장한다/);
  assert.match(widgetTest, /bySemanticsLabel/);
  assert.match(widgetTest, /greaterThanOrEqualTo\(60\)/);
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
  assertPrivacyCollectedDataType(privacyManifest, "NSPrivacyCollectedDataTypeUserID");
  assert.match(project, /PrivacyInfo\.xcprivacy \*\/ = \{isa = PBXFileReference;[\s\S]*?path = PrivacyInfo\.xcprivacy;/);
  assert.match(project, /PrivacyInfo\.xcprivacy in Resources/);
});

test("iOS 위치 권한은 앱 사용 중 목적만 설명한다", () => {
  const infoPlist = read("apps/mobile/ios/Runner/Info.plist");

  assert.match(infoPlist, /<key>NSLocationWhenInUseUsageDescription<\/key>/);
  assert.match(infoPlist, /앱을 사용하는 동안 가까운 역을 찾고 시설 신고 위치를 확인하는 데 사용합니다\./);
  assert.doesNotMatch(infoPlist, /NSLocationAlways/);
  assert.doesNotMatch(infoPlist, /UIBackgroundModes/);
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
    "android.permission.POST_NOTIFICATIONS",
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
