import assert from "node:assert/strict";
import { execFile, execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { existsSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";
import { inflateSync } from "node:zlib";

const root = process.cwd();
const execFileAsync = promisify(execFile);
const validDataPackPublicKeyModulus =
  "itNBIH_FyHbqONXe_z8LNzWes4rh3veI4_8RY76rb7onamA-WDoJlvFyvBG-ihBOl7LtgW1rV54hCLHz95VFLmm028-tll9ThDzSs3Bu9ychED-m0vny16tK8ZgB6gf7sJkjGBJn8MLDaiVWoVvD5TEjv433f_vMFIljdNUKZC2Xf0qHYlYv18dAwbJHKeOsmJkky13HNVn40HuEn5FWEJvFI5qqVgpJ-k1V3ip39ga2-Ek5SOVHAL6U44ypjSXUjo7NCKVpuQRwN7hAnvlYutXDdrEQ6Oa3iUtbQJIgkl-ZmTwNkYHCEIhd_ZLB9n_EEHdvyJAmUKCtAKLX5FOa9w";
const validPlayAppSigningFingerprint =
  "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99";

function read(relativePath) {
  return readFileSync(path.join(root, relativePath), "utf8");
}

function mobileProductionDartFiles() {
  return execFileSync("git", ["ls-files", "apps/mobile/lib"], {
    cwd: root,
    encoding: "utf8",
  }).trim().split("\n").filter((file) => file.endsWith(".dart") && !file.endsWith(".g.dart"));
}

function readJson(relativePath) {
  return JSON.parse(read(relativePath));
}

test("route ETA accuracy evaluator report contract is machine-readable", async () => {
  const outputDir = await mkdtemp(path.join(tmpdir(), "route-accuracy-"));
  const output = path.join(outputDir, "route-accuracy-report.json");
  await execFileAsync(process.execPath, [
    "tools/routes/evaluate-eta-accuracy.mjs",
    "--dataset",
    "tools/routes/golden-od",
    "--output",
    output,
  ], { cwd: root });

  const report = JSON.parse(readFileSync(output, "utf8"));
  assert.equal(report.schemaVersion, 1);
  assert.equal(report.sampleSize, 100);
  assert.equal(report.metrics.sampleSize, 100);
  assert.equal(report.coverage.singleRide, true);
  assert.equal(report.coverage.oneTransfer, true);
  assert.equal(report.coverage.twoTransfer, true);
  assert.equal(report.coverage.express, true);
  assert.equal(report.coverage.outOfStationTransfer, true);
  assert.equal(report.coverage.strictStepFree, true);
  assert.equal(report.coverage.realtimeSupported, true);
  assert.equal(report.coverage.realtimeUnsupported, true);
  assert.deepEqual(report.failures, []);
});

test("route commercialization release gate blocks unsupported commercial route claims", () => {
  const gatePath = "apps/mobile/release/route-commercialization-gate.json";
  assert.equal(existsSync(path.join(root, gatePath)), true, "route commercialization gate must exist");

  const gate = readJson(gatePath);
  const readme = read("README.md");
  const prTemplate = read(".github/pull_request_template.md");

  assert.equal(gate.schemaVersion, 1);
  assert.equal(gate.applicationId, "easysubway");
  assert.equal(gate.androidApplicationId, "com.easysubway.app");
  assert.equal(gate.releaseGate, "route-commercialization");
  assert.equal(gate.issue, 1210);
  assert.equal(gate.releaseBlockerPolicy, true);
  assert.equal(gate.storeReadyStatus, "blocked_route_commercialization_evidence_missing");
  assert.equal(gate.routeEtaAccuracy.singleRideP50ErrorSecondsMax, 60);
  assert.equal(gate.routeEtaAccuracy.singleRideP90ErrorSecondsMax, 180);
  assert.equal(gate.routeEtaAccuracy.transferP50ErrorSecondsMax, 120);
  assert.equal(gate.routeEtaAccuracy.transferP90ErrorSecondsMax, 300);
  assert.equal(gate.routeEtaAccuracy.sampleSizeMin, 100);
  assert.equal(gate.realtimeCoverage.supportedStationLinePairsMin, 100);
  assert.equal(gate.realtimeCoverage.providerFreshnessSecondsMax, 90);
  assert.equal(gate.realtimeCoverage.staleFallbackRequired, true);
  assert.equal(gate.accessibility.strictStepFreeKnownStairFalsePositiveAllowed, 0);
  assert.equal(gate.accessibility.generatedConnectorAsVerifiedAllowed, false);
  assert.equal(gate.accessibility.unknownAccessibilityMustBeLabeled, true);
  assert.equal(gate.routing.multiTransferSupported, true);
  assert.equal(gate.routing.outOfStationTransferSupported, true);
  assert.equal(gate.routing.alternativeItinerariesMin, 2);
  assert.equal(gate.etaSourceIntegrity.realtimeEtaWithoutFreshProviderAllowed, false);
  assert.equal(gate.etaSourceIntegrity.staleRealtimeUsedAsFreshAllowed, false);
  assert.equal(gate.etaSourceIntegrity.staticLocalMustBeLabeled, true);
  assert.equal(gate.etaSourceIntegrity.plannedOnlyMustBeLabeled, true);
  assert.equal(gate.routeQuality.wrongTransferCountAllowed, 0);
  assert.equal(gate.routeQuality.wrongLineSequenceAllowed, 0);
  assert.equal(gate.routeQuality.routeNotFoundRateMax, 0.02);
  assert.equal(gate.evidence.routeAccuracyReportRequired, true);
  assert.equal(gate.evidence.providerCoverageReportRequired, true);
  assert.equal(gate.evidence.accessibilityRegressionReportRequired, true);
  assert.deepEqual(gate.requiredReports, {
    accuracy: "artifacts/route-accuracy-report.json",
    accessibility: "artifacts/route-accessibility-regression-report.json",
    coverage: "artifacts/realtime-provider-coverage-report.json",
    contract: "artifacts/route-v2-contract-report.json",
  });
  assert.deepEqual(gate.outOfStationTransferReleaseBlockers, ["D-2", "D-3", "H-1"]);

  assert.match(readme, /Route commercialization gate/);
  assert.match(readme, /apps\/mobile\/release\/route-commercialization-gate\.json/);
  assert.match(prTemplate, /Route commercialization gate impact/);
  assert.match(prTemplate, /route-commercialization-gate\.json/);
});

function currentMobileVersionCode() {
  const match = read("apps/mobile/pubspec.yaml").match(/^version:\s*[^+\s]+[+](\d+)\s*$/m);
  assert.ok(match, "mobile pubspec must contain versionName+versionCode");
  return Number.parseInt(match[1], 10);
}

function currentMobileVersion() {
  const match = read("apps/mobile/pubspec.yaml").match(/^version:\s*(\d+)\.(\d+)\.(\d+)[+](\d+)\s*$/m);
  assert.ok(match, "mobile pubspec must contain semver versionName and numeric versionCode");
  const [, major, minor, patch, code] = match;
  return {
    major: Number.parseInt(major, 10),
    minor: Number.parseInt(minor, 10),
    patch: Number.parseInt(patch, 10),
    code: Number.parseInt(code, 10),
  };
}

test("Android versionCode는 표시 버전과 분리된 단조 증가 빌드 번호다", () => {
  const mobileVersion = currentMobileVersion();
  assert.ok(mobileVersion.code > 0, "Android versionCode must be positive");
  assert.match(read("README.md"), /표시 버전은 SemVer/);
  assert.match(read("README.md"), /빌드 번호는 스토어 업로드마다 단조 증가/);
});

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
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
  }).trim().split("\n").filter((file) => file && existsSync(path.join(root, file)));
}

function assertActionsEnvSecretPolicy(file, source) {
  const secretAccess = /secrets(?:\.([A-Z0-9_]+)|\[['"]([A-Z0-9_]+)['"]\])/g;
  const disallowedVarsAccess = /vars(?:\.EASYSUBWAY_[A-Z0-9_]+|\[['"]EASYSUBWAY_[A-Z0-9_]+['"]\])/;
  const allowedExtraSecrets = file === ".github/workflows/release-artifacts.yml"
    ? new Set([
        "EASYSUBWAY_ANDROID_UPLOAD_KEYSTORE_BASE64",
        "EASYSUBWAY_ANDROID_STORE_PASSWORD",
        "EASYSUBWAY_ANDROID_KEY_ALIAS",
        "EASYSUBWAY_ANDROID_KEY_PASSWORD",
      ])
    : new Set();

  for (const match of source.matchAll(secretAccess)) {
    const secretName = match[1] ?? match[2];
    if (
      secretName.startsWith("EASYSUBWAY_") &&
      secretName !== "EASYSUBWAY_ENV" &&
      !allowedExtraSecrets.has(secretName)
    ) {
      assert.fail(`${file} must use only secrets.EASYSUBWAY_ENV or approved Android upload key secrets`);
    }
  }
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

function collectStatusValues(value, values = []) {
  if (Array.isArray(value)) {
    for (const item of value) {
      collectStatusValues(item, values);
    }
    return values;
  }

  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) {
      if (key === "status" && typeof child === "string") {
        values.push(child);
      }
      collectStatusValues(child, values);
    }
  }

  return values;
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
  const releaseGateJob = jobBlock(workflow, "release-gate-consistency", "repository-contracts");

  assert.match(workflow, /workflow_dispatch:/);
  assert.match(workflow, /name: Changes/);
  assert.match(workflow, /name: Repository CI/);
  assert.match(workflow, /name: Backend CI/);
  assert.match(workflow, /name: Mobile App CI/);
  assert.match(workflow, /name: Android CI/);
  assert.match(releaseGateJob, /name: Release Gate Consistency/);
  assert.doesNotMatch(releaseGateJob, /name: iOS CI/);
  assert.doesNotMatch(releaseGateJob, /runs-on: macos-latest/);
  assert.match(workflow, /Repository CI \/ Run contract tests/);
  assert.match(workflow, /Repository CI \/ Set up Chrome for route map tests/);
  assert.match(workflow, /CHROME_PATH: \$\{\{ steps\.setup-chrome\.outputs\.chrome-path \}\}/);
  assert.match(workflow, /ROUTE_MAP_CHROME_NO_SANDBOX: "1"/);
  assert.match(workflow, /Repository CI \/ Run route map tool tests/);
  assert.match(releaseGateJob, /Release Gate Consistency \/ Run release gate contract tests/);
  assert.match(releaseGateJob, /node --test tools\/ci\/repository-contract\.test\.mjs/);
  assert.doesNotMatch(releaseGateJob, /--test-name-pattern/);
  assert.match(workflow, /Backend CI \/ Detect backend scaffold/);
  assert.match(workflow, /Mobile App CI \/ Run Flutter analyzer and tests/);
  assert.match(workflow, /Mobile App CI \/ Run mobile contracts/);
  assert.match(workflow, /Android CI \/ Build Flutter Android debug APK/);
  assert.doesNotMatch(releaseGateJob, /iOS CI \/ Build Flutter iOS simulator app/);
});

test("필수 지속적 통합 작업은 변경 없는 영역도 성공 상태로 종료한다", () => {
  const workflow = read(".github/workflows/ci.yml");
  const androidJob = jobBlock(workflow, "android", "notify-slack-ci-failure");

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
  assert.match(workflow, /workflow_run:[\s\S]*workflows:\s*\n\s*-\s*CI[\s\S]*types:\s*\n\s*-\s*completed/);
  assert.match(workflow, /workflow_run:[\s\S]*branches:\s*\n\s*-\s*main/);
  assert.match(workflow, /workflow_dispatch:/);
  assert.match(workflow, /permissions:[\s\S]*actions:\s*read[\s\S]*contents:\s*read/);
  assert.doesNotMatch(workflow, /\nconcurrency:\s*\n\s*group: cd-production-deploy/);
  assert.match(workflow, /runs-on:[\s\S]*-\s*self-hosted[\s\S]*-\s*easysubway-production/);
  assert.match(workflow, /name: CD Deploy/);
  const deployJob = workflow.match(/\n  deploy:[\s\S]*$/)?.[0] ?? "";
  assert.doesNotMatch(deployJob, /environment:\s*production/, "automatic server CD must not wait for production environment review");
  assert.match(deployJob, /\n    concurrency:\s*\n\s*group: cd-production-deploy\s*\n\s*cancel-in-progress: false/);
  assert.match(workflow, /secrets\.EASYSUBWAY_ENV/);
  assert.match(workflow, /CD Deploy \/ Validate manual dispatch CI/);
  assert.match(workflow, /manual deployment requires a successful CI workflow/);
  assert.match(workflow, /CD Deploy \/ Restore GitHub Actions dotenv secret/);
  assert.match(workflow, /CD Deploy \/ Restore GitHub Actions dotenv secret[\s\S]*?env:\s*\n\s*EASYSUBWAY_ENV_SECRET: \$\{\{ secrets\.EASYSUBWAY_ENV \}\}/);
  assert.match(workflow, /printf '%s' "\$\{EASYSUBWAY_ENV_SECRET\}" > "\$\{env_file\}"/);
  assert.doesNotMatch(workflow, /printf '%s\\n' "\$\{EASYSUBWAY_ENV_SECRET\}"/);
  assert.match(workflow, /CD Deploy \/ Validate deployment dotenv contract/);
  assert.match(workflow, /CD Plan \/ Detect deployment changes/);
  assert.match(workflow, /bash tools\/ci\/detect-changed-paths\.sh changed-files\.txt/);
  assert.match(workflow, /deploy_target_relevant: \$\{\{ steps\.changes\.outputs\.deploy \}\}/);
  assert.match(workflow, /if: \$\{\{ needs\.plan\.outputs\.deploy_target_relevant == 'true' \}\}/);
  assert.match(workflow, /CD Deploy \/ Prepare split deployment env files/);
  assert.match(workflow, /tools\/deploy\/prepare-deployment-env\.sh/);
  assert.match(workflow, /tools\/deploy\/compose-server-env\.allowlist/);
  assert.match(workflow, /tools\/deploy\/backend-app-env\.allowlist/);
  assert.match(workflow, /CD Deploy \/ Validate Docker Compose deployment config/);
  assert.match(workflow, /docker compose --env-file "\$\{PREPARED_ENV_DIR\}\/compose\.env" -f infra\/docker-compose\.yml config --quiet/);
  assert.match(workflow, /CD Deploy \/ Build backend bootJar/);
  assert.match(workflow, /sha256sum backend\.jar > backend\.jar\.sha256/);
  assert.match(workflow, /CD Deploy \/ Run local deployment/);
  assert.match(workflow, /install -m 700 -d "\$\{incoming\}"/);
  assert.match(workflow, /bash "\$\{incoming\}\/deploy-backend\.sh"/);
  assert.doesNotMatch(workflow, /DEPLOY_HOST: \$\{\{ secrets\.DEPLOY_HOST \}\}/);
  assert.doesNotMatch(workflow, /DEPLOY_USER: \$\{\{ secrets\.DEPLOY_USER \}\}/);
  assert.doesNotMatch(workflow, /DEPLOY_SSH_PRIVATE_KEY: \$\{\{ secrets\.DEPLOY_SSH_PRIVATE_KEY \}\}/);
  assert.match(workflow, /DEPLOY_ROOT="\$\{DEPLOY_ROOT:-\/opt\/easysubway\}"/);
  assert.match(workflow, /DEPLOY_COMPOSE_PROJECT="\$\{DEPLOY_COMPOSE_PROJECT:-easysubway\}"/);
  assert.doesNotMatch(workflow, /missing_ssh_credentials/);
  assert.doesNotMatch(workflow, /\bssh\b|\bscp\b/);
  assert.match(workflow, /invalid_deploy_root/);
  assert.match(workflow, /invalid_compose_project/);
  assert.match(workflow, /remote deployment:[\s\S]*not_started/);
  assert.match(workflow, /deploy-backend\.sh/);
  assert.doesNotMatch(workflow, /runs-on: ubuntu-latest\s*\n\s*env:\s*\n\s*EASYSUBWAY_ENV_SECRET/);
  assert.doesNotMatch(workflow, /secrets\.EASYSUBWAY_(DATASOURCE|REDIS|TRUSTED_PROXY|POSTGRES)/);
});

test("풀 리퀘스트 템플릿은 리뷰와 배포 확인 게이트를 포함한다", () => {
  const template = read(".github/pull_request_template.md");

  assert.match(template, /## 관련 이슈/);
  assert.match(template, /## 검증/);
  assert.match(template, /실행한 명령과 결과/);
  assert.match(template, /리뷰어가 먼저 봐야 할 지점/);
  assert.match(template, /## Version impact/);
  assert.match(template, /mobile patch/);
  assert.match(template, /backend identity/);
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
  assert.match(envExample, /^EASYSUBWAY_POSTGRES_PORT=15432$/m);
  assert.match(envExample, /^EASYSUBWAY_DATASOURCE_URL=jdbc:postgresql:\/\/localhost:15432\/easysubway$/m);
  assert.match(envExample, /^EASYSUBWAY_DATASOURCE_USERNAME=easysubway$/m);
  assert.match(envExample, /^EASYSUBWAY_DATASOURCE_PASSWORD=easysubway_local$/m);
  assert.match(envExample, /^EASYSUBWAY_DATA_PACK_BASE_URL=http:\/\/localhost:9000\/easysubway-datapacks$/m);
  assert.match(envExample, /^EASYSUBWAY_REPORT_API_BASE_URL=http:\/\/localhost:8080$/m);
  assert.match(envExample, /^EASYSUBWAY_REPORT_RECEIPT_PEPPER=$/m);
  assert.match(envExample, /^EASYSUBWAY_REPORT_UPLOAD_BUCKET=easysubway-report-uploads$/m);
  assert.match(envExample, /^EASYSUBWAY_REPORT_UPLOAD_MAX_BYTES=921600$/m);
  assert.match(envExample, /^EASYSUBWAY_REPORT_UPLOAD_URL_TTL_SECONDS=900$/m);
  assert.match(envExample, /^EASYSUBWAY_REPORT_UPLOAD_INTENT_SIGNING_KEY=$/m);
  assert.match(envExample, /^EASYSUBWAY_REPORT_ABUSE_STORE_MODE=local$/m);
  assert.match(envExample, /^EASYSUBWAY_OBJECT_STORAGE_ENDPOINT=http:\/\/localhost:9000$/m);
  assert.match(envExample, /^EASYSUBWAY_REPORT_OBJECT_STORAGE_INTERNAL_ENDPOINT=http:\/\/localhost:9000$/m);
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
  assert.match(envExample, /^EASYSUBWAY_ADMIN_REVISION=local$/m);
  assert.match(envExample, /^EASYSUBWAY_ADMIN_MASTER_DATA_VERSION=unknown$/m);
  assert.match(envExample, /^EASYSUBWAY_ADMIN_BASIC_AUTH_ENABLED=false$/m);
  assert.match(envExample, /^EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_OWNER=$/m);
  assert.match(envExample, /^EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_EXPIRES_AT=$/m);
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

  assert.match(readme, /애플리케이션 환경값을 개별 환경변수로 여러 개 만들지 않고, 로컬 `\.env` 파일 전체를 `EASYSUBWAY_ENV` secret 하나/);
  assert.match(readme, /애플리케이션 환경값용 GitHub Actions secret 이름은 반드시 `EASYSUBWAY_ENV`만 사용합니다/);
  assert.match(readme, /scripts\/github\/sync-actions-env-secret\.sh \.env/);
  assert.match(readme, /secrets\.EASYSUBWAY_ENV/);
  assert.match(readme, /CD workflow는 `EASYSUBWAY_ENV` repository secret이 있으면 배포 dotenv 계약을 검증하고 Compose env와 backend env로 분리/);
  assert.match(readme, /GitHub `production` environment approval을 기다리지 않습니다/);
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

test("GitHub Actions Slack 알림은 채널별 webhook secret으로 필터링한다", () => {
  const removedWorkflowPath = ".github/workflows/slack-notifications.yml";
  const ciWorkflow = read(".github/workflows/ci.yml");
  const cdWorkflow = read(".github/workflows/cd.yml");
  const releaseArtifactsWorkflow = read(".github/workflows/release-artifacts.yml");
  const dataPackReleaseWorkflow = read(".github/workflows/datapack-release.yml");
  const sonarCloudWorkflow = read(".github/workflows/sonarcloud.yml");
  const storeDistributionWorkflow = read(".github/workflows/store-distribution-evidence.yml");
  const inlineSlackWorkflows = [
    ciWorkflow,
    cdWorkflow,
    releaseArtifactsWorkflow,
    dataPackReleaseWorkflow,
    sonarCloudWorkflow,
    storeDistributionWorkflow,
  ].join("\n---\n");
  const readme = read("README.md");
  const envExample = read(".env.example");

  assert.ok(!existsSync(path.join(root, removedWorkflowPath)), "Slack notification workflow must not create standalone skipped runs");
  assert.equal((inlineSlackWorkflows.match(/uses: slackapi\/slack-github-action@45a88b9581bfab2566dc881e2cd66d334e621e2c/g) ?? []).length, 6);
  assert.equal((inlineSlackWorkflows.match(/webhook-type: incoming-webhook/g) ?? []).length, 6);
  assert.doesNotMatch(inlineSlackWorkflows, /uses: slackapi\/slack-github-action@v3\.0\.3/);
  const slackPayloads = inlineSlackWorkflows.match(/payload: \|\n(?: {10,}.+\n?)*/g) ?? [];
  assert.equal(slackPayloads.length, 6);
  for (const payload of slackPayloads) {
    assert.doesNotMatch(payload, /^\s+(channel|username|icon_emoji|icon_url):/m);
  }
  assert.doesNotMatch(inlineSlackWorkflows, /webhook:\s*\$\{\{ secrets\.EASYSUBWAY_ENV \}\}/);
  assert.equal((inlineSlackWorkflows.match(/SLACK_CI_WEBHOOK_URL: \$\{\{ secrets\.SLACK_CI_WEBHOOK_URL \}\}/g) ?? []).length, 1);
  assert.equal((inlineSlackWorkflows.match(/SLACK_RELEASE_WEBHOOK_URL: \$\{\{ secrets\.SLACK_RELEASE_WEBHOOK_URL \}\}/g) ?? []).length, 4);
  assert.equal((inlineSlackWorkflows.match(/SLACK_SECURITY_WEBHOOK_URL: \$\{\{ secrets\.SLACK_SECURITY_WEBHOOK_URL \}\}/g) ?? []).length, 1);
  assert.match(ciWorkflow, /notify-slack-ci-failure:[\s\S]*needs:\s*\n\s*-\s*changes[\s\S]*github\.event_name == 'push'[\s\S]*github\.ref == 'refs\/heads\/main'[\s\S]*contains\(needs\.\*\.result, 'failure'\)/);
  assert.match(cdWorkflow, /notify-slack-cd-result:[\s\S]*needs:\s*\n\s*-\s*plan\n\s*-\s*deploy[\s\S]*SLACK_RELEASE_WEBHOOK_URL/);
  assert.match(releaseArtifactsWorkflow, /notify-slack-release-result:[\s\S]*github\.event_name != 'pull_request'[\s\S]*SLACK_RELEASE_WEBHOOK_URL/);
  assert.match(dataPackReleaseWorkflow, /notify-slack-datapack-result:[\s\S]*SLACK_RELEASE_WEBHOOK_URL/);
  assert.match(storeDistributionWorkflow, /notify-slack-store-result:[\s\S]*SLACK_RELEASE_WEBHOOK_URL/);
  assert.match(sonarCloudWorkflow, /notify-slack-security-failure:[\s\S]*github\.event_name == 'push'[\s\S]*SLACK_SECURITY_WEBHOOK_URL/);

  assert.match(readme, /Slack webhook secret은 애플리케이션 런타임 dotenv인 `EASYSUBWAY_ENV`에 섞지 않습니다/);
  assert.match(readme, /SLACK_CI_WEBHOOK_URL/);
  assert.match(readme, /SLACK_RELEASE_WEBHOOK_URL/);
  assert.match(readme, /SLACK_SECURITY_WEBHOOK_URL/);
  assert.match(readme, /원본 workflow 내부 notify job/);
  assert.match(envExample, /^SLACK_CI_WEBHOOK_URL=$/m);
  assert.match(envExample, /^SLACK_RELEASE_WEBHOOK_URL=$/m);
  assert.match(envExample, /^SLACK_SECURITY_WEBHOOK_URL=$/m);
});

test("CD dotenv 검증은 운영 fallback env 계약을 반영한다", async () => {
  const dir = await mkdtemp(path.join(tmpdir(), "easysubway-cd-env-"));
  const envFile = path.join(dir, "deploy.env");
  const deploymentEnvLines = [
    "EASYSUBWAY_POSTGRES_DB=easysubway",
    "EASYSUBWAY_POSTGRES_USER=easysubway",
    "EASYSUBWAY_POSTGRES_PASSWORD=secret",
    "EASYSUBWAY_POSTGRES_PORT=15432",
    "EASYSUBWAY_DATASOURCE_URL=jdbc:postgresql://db:5432/easysubway",
    "EASYSUBWAY_DATASOURCE_USERNAME=easysubway",
    "EASYSUBWAY_DATASOURCE_PASSWORD=secret",
    "EASYSUBWAY_DATA_PACK_BASE_URL=https://cdn.example.com/easysubway-datapacks",
    "EASYSUBWAY_REPORT_API_BASE_URL=https://api.example.com",
    "EASYSUBWAY_REPORT_RECEIPT_TOKEN_PEPPER=legacy-pepper-with-enough-entropy",
    "EASYSUBWAY_REPORT_UPLOAD_BUCKET=easysubway-report-uploads",
    "EASYSUBWAY_REPORT_UPLOAD_MAX_BYTES=921600",
    "EASYSUBWAY_REPORT_UPLOAD_URL_TTL_SECONDS=900",
    "EASYSUBWAY_REPORT_UPLOAD_PUBLIC_BASE_URL=https://uploads.example.com",
    "EASYSUBWAY_OBJECT_STORAGE_ENDPOINT=https://object-storage.example.com",
    "EASYSUBWAY_REPORT_OBJECT_STORAGE_INTERNAL_ENDPOINT=http://object-storage:9000",
    "EASYSUBWAY_OBJECT_STORAGE_ACCESS_KEY=access-key",
    "EASYSUBWAY_OBJECT_STORAGE_SECRET_KEY=secret-key",
    "EASYSUBWAY_DATAPACK_BUCKET=easysubway-datapacks",
    "EASYSUBWAY_DATAPACK_SIGNING_PRIVATE_KEY_PEM=private-key-pem",
    "EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_PEM=public-key-pem",
    "EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_N=public-key-modulus",
    "EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_E=AQAB",
    "EASYSUBWAY_DATAPACK_SIGNING_KEY_ID=production-v1",
    "EASYSUBWAY_DATAPACK_CHANNEL=production",
    "EASYSUBWAY_TRUSTED_PROXY_CIDRS=",
    "EASYSUBWAY_PUSH_EXTERNAL_ENABLED=false",
    "EASYSUBWAY_ENABLE_PUSH_NOTIFICATIONS=false",
    "EASYSUBWAY_ADMIN_USERNAME=admin",
    "EASYSUBWAY_ADMIN_PASSWORD=secret",
    "EASYSUBWAY_ADMIN_REVISION=main-20260627",
    "EASYSUBWAY_ADMIN_MASTER_DATA_VERSION=datapack-20260627",
    "EASYSUBWAY_ADMIN_CUTOVER_ENFORCED=false",
    "EASYSUBWAY_ADMIN_PLATFORM_FLAGS_RBAC_ENFORCEMENT=false",
    "EASYSUBWAY_ADMIN_PLATFORM_FLAGS_AUDIT_ENFORCEMENT=false",
    "EASYSUBWAY_ADMIN_PLATFORM_FLAGS_LEGACY_ENV_ADMIN_FALLBACK=true",
    "EASYSUBWAY_ADMIN_PLATFORM_FLAGS_BREAK_GLASS_BOOTSTRAP=true",
    "EASYSUBWAY_PRIVACY_POLICY_URL=https://example.com/privacy",
    "EASYSUBWAY_SUPPORT_EMAIL=support@example.com",
    "EASYSUBWAY_SECURITY_EMAIL=security@example.com",
    "EASYSUBWAY_DATA_DELETION_EMAIL=privacy@example.com",
    "EASYSUBWAY_ANDROID_KEYSTORE_PATH=",
    "EASYSUBWAY_ANDROID_STORE_PASSWORD=",
    "EASYSUBWAY_ANDROID_KEY_ALIAS=",
    "EASYSUBWAY_ANDROID_KEY_PASSWORD=",
    "EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME=com.easysubway.app",
    "EASYSUBWAY_GOOGLE_PLAY_APP_SIGNING_SHA256=AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA",
    "EASYSUBWAY_PLAY_APP_SIGNING_KEY_SHA256=AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA",
    "EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE=0",
    "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64=base64-json",
    "",
  ];
  await writeFile(envFile, deploymentEnvLines.join("\n"));

  const validator = read("tools/ci/validate-deployment-env.sh");
  assert.match(validator, /EASYSUBWAY_REPORT_ABUSE_STORE_MODE/);
  assert.match(validator, /EASYSUBWAY_ADMIN_REVISION/);
  assert.match(validator, /EASYSUBWAY_ADMIN_MASTER_DATA_VERSION/);
  assert.match(validator, /EASYSUBWAY_ADMIN_BASIC_AUTH_ENABLED/);
  assert.match(validator, /EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_OWNER/);
  assert.match(validator, /EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_EXPIRES_AT/);
  assert.match(validator, /EASYSUBWAY_ADMIN_CUTOVER_ENFORCED/);
  assert.match(validator, /SLACK_CI_WEBHOOK_URL\|SLACK_RELEASE_WEBHOOK_URL\|SLACK_SECURITY_WEBHOOK_URL/);
  await execFileAsync("tools/ci/validate-deployment-env.sh", [envFile], { cwd: root });

  await writeFile(envFile, [
    ...deploymentEnvLines,
    "EASYSUBWAY_ADMIN_BASIC_AUTH_ENABLED=true",
    "",
  ].join("\n"));
  await assert.rejects(
    execFileAsync("tools/ci/validate-deployment-env.sh", [envFile], { cwd: root }),
    /EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_OWNER[\s\S]*EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_EXPIRES_AT/
  );

  await writeFile(envFile, [
    ...deploymentEnvLines,
    'EASYSUBWAY_ADMIN_BASIC_AUTH_ENABLED="true"',
    "",
  ].join("\n"));
  await assert.rejects(
    execFileAsync("tools/ci/validate-deployment-env.sh", [envFile], { cwd: root }),
    /EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_OWNER[\s\S]*EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_EXPIRES_AT/
  );

  await writeFile(envFile, [
    ...deploymentEnvLines,
    "EASYSUBWAY_ADMIN_BASIC_AUTH_ENABLED=TRUE",
    "",
  ].join("\n"));
  await assert.rejects(
    execFileAsync("tools/ci/validate-deployment-env.sh", [envFile], { cwd: root }),
    /EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_OWNER[\s\S]*EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_EXPIRES_AT/
  );

  await writeFile(envFile, [
    ...deploymentEnvLines,
    "EASYSUBWAY_ADMIN_BASIC_AUTH_ENABLED=maybe",
    "",
  ].join("\n"));
  await assert.rejects(
    execFileAsync("tools/ci/validate-deployment-env.sh", [envFile], { cwd: root }),
    /EASYSUBWAY_ADMIN_BASIC_AUTH_ENABLED/
  );

  await writeFile(envFile, [
    ...deploymentEnvLines,
    "EASYSUBWAY_ADMIN_BASIC_AUTH_ENABLED=true",
    "EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_OWNER=   ",
    "EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_EXPIRES_AT=   ",
    "",
  ].join("\n"));
  await assert.rejects(
    execFileAsync("tools/ci/validate-deployment-env.sh", [envFile], { cwd: root }),
    /EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_OWNER[\s\S]*EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_EXPIRES_AT/
  );

  await writeFile(envFile, [
    ...deploymentEnvLines,
    "EASYSUBWAY_ADMIN_BASIC_AUTH_ENABLED=true",
    'EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_OWNER=""',
    'EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_EXPIRES_AT=""',
    "",
  ].join("\n"));
  await assert.rejects(
    execFileAsync("tools/ci/validate-deployment-env.sh", [envFile], { cwd: root }),
    /EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_OWNER[\s\S]*EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_EXPIRES_AT/
  );

  await writeFile(envFile, [
    ...deploymentEnvLines,
    "EASYSUBWAY_ADMIN_BASIC_AUTH_ENABLED=true",
    "EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_OWNER=ops-team",
    "",
  ].join("\n"));
  await assert.rejects(
    execFileAsync("tools/ci/validate-deployment-env.sh", [envFile], { cwd: root }),
    /EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_EXPIRES_AT/
  );

  await writeFile(envFile, [
    ...deploymentEnvLines,
    "EASYSUBWAY_ADMIN_CUTOVER_ENFORCED=true",
    "",
  ].join("\n"));
  await assert.rejects(
    execFileAsync("tools/ci/validate-deployment-env.sh", [envFile], { cwd: root }),
    /EASYSUBWAY_ADMIN_PLATFORM_FLAGS_RBAC_ENFORCEMENT[\s\S]*EASYSUBWAY_ADMIN_PLATFORM_FLAGS_AUDIT_ENFORCEMENT[\s\S]*EASYSUBWAY_ADMIN_PLATFORM_FLAGS_LEGACY_ENV_ADMIN_FALLBACK[\s\S]*EASYSUBWAY_ADMIN_PLATFORM_FLAGS_BREAK_GLASS_BOOTSTRAP/
  );

  await writeFile(envFile, [
    ...deploymentEnvLines.map((line) => {
      if (line === "EASYSUBWAY_ADMIN_CUTOVER_ENFORCED=false") return "EASYSUBWAY_ADMIN_CUTOVER_ENFORCED=true";
      if (line === "EASYSUBWAY_ADMIN_PLATFORM_FLAGS_RBAC_ENFORCEMENT=false") return "EASYSUBWAY_ADMIN_PLATFORM_FLAGS_RBAC_ENFORCEMENT=true";
      if (line === "EASYSUBWAY_ADMIN_PLATFORM_FLAGS_AUDIT_ENFORCEMENT=false") return "EASYSUBWAY_ADMIN_PLATFORM_FLAGS_AUDIT_ENFORCEMENT=true";
      if (line === "EASYSUBWAY_ADMIN_PLATFORM_FLAGS_LEGACY_ENV_ADMIN_FALLBACK=true") return "EASYSUBWAY_ADMIN_PLATFORM_FLAGS_LEGACY_ENV_ADMIN_FALLBACK=false";
      if (line === "EASYSUBWAY_ADMIN_PLATFORM_FLAGS_BREAK_GLASS_BOOTSTRAP=true") return "EASYSUBWAY_ADMIN_PLATFORM_FLAGS_BREAK_GLASS_BOOTSTRAP=false";
      return line;
    }),
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

test("프로덕션 모바일 UI 위젯명은 prototype 명칭을 쓰지 않는다", () => {
  const mobileFiles = execFileSync("git", ["ls-files", "apps/mobile/lib/*.dart"], {
    cwd: root,
    encoding: "utf8",
  }).trim().split("\n").filter(Boolean);

  for (const file of mobileFiles) {
    assert.doesNotMatch(read(file), /Prototype/, `${file} still has prototype UI naming`);
  }
});

test("모바일 production 사용자 문구는 점수와 기본정보 같은 내부 용어를 쓰지 않는다", () => {
  const forbiddenCopyPatterns = [
    ["기본정보", /['"`][^'"`\n]*기본\s*정보[^'"`\n]*['"`]/u],
    ["기본정보", /['"`][^'"`\n]*기본정보[^'"`\n]*['"`]/u],
    ["정보만", /['"`][^'"`\n]*정보만[^'"`\n]*['"`]/u],
    ["상세정보", /['"`][^'"`\n]*상세\s*정보[^'"`\n]*['"`]/u],
    ["상세정보", /['"`][^'"`\n]*상세정보[^'"`\n]*['"`]/u],
    ["정보 신뢰도", /['"`][^'"`\n]*정보\s*신뢰도[^'"`\n]*['"`]/u],
    ["이동 점수", /['"`][^'"`\n]*이동\s*점수[^'"`\n]*['"`]/u],
    ["이동 편의도", /['"`][^'"`\n]*이동\s*편의도[^'"`\n]*['"`]/u],
    ["이동 구조", /['"`][^'"`\n]*이동\s*구조[^'"`\n]*['"`]/u],
    ["살펴볼 시설 없음", /['"`][^'"`\n]*살펴볼\s*시설\s*없음[^'"`\n]*['"`]/u],
    ["다시 볼 시설 없음", /['"`][^'"`\n]*다시\s*볼\s*시설\s*없음[^'"`\n]*['"`]/u],
    ["환승 없음", /['"`][^'"`\n]*환승\s*없음[^'"`\n]*['"`]/u],
    ["삭제할 항목 없음", /['"`][^'"`\n]*삭제할\s*항목\s*없음[^'"`\n]*['"`]/u],
    ["계단 없음 확인", /['"`][^'"`\n]*계단\s*없음\s*확인[^'"`\n]*['"`]/u],
    ["새 알림 없음", /['"`][^'"`\n]*새\s*알림\s*없음[^'"`\n]*['"`]/u],
    ["현재 이용할 수 없음", /['"`][^'"`\n]*현재\s*이용할\s*수\s*없음[^'"`\n]*['"`]/u],
    ["점수", /['"`][^'"`\n]*점수[^'"`\n]*['"`]/u],
    ["숫자 점수", /['"`][^'"`\n]*\d+\s*점[^'"`\n]*['"`]/u],
    ["데이터팩", /['"`][^'"`\n]*데이터팩[^'"`\n]*['"`]/u],
    ["공공 API", /['"`][^'"`\n]*공공\s*API[^'"`\n]*['"`]/u],
    ["관리자 검수", /['"`][^'"`\n]*관리자\s*검수[^'"`\n]*['"`]/u],
    ["현장 검증", /['"`][^'"`\n]*현장\s*검증[^'"`\n]*['"`]/u],
    ["출처", /['"`][^'"`\n]*출처[^'"`\n]*['"`]/u],
    ["상태 제보", /['"`][^'"`\n]*상태\s*제보[^'"`\n]*['"`]/u],
    ["시설 상태 제보", /['"`][^'"`\n]*시설\s*상태\s*제보[^'"`\n]*['"`]/u],
    ["가기 전 확인", /['"`][^'"`\n]*가기\s*전\s*확인[^'"`\n]*['"`]/u],
    ["이동 전 확인", /['"`][^'"`\n]*이동\s*전\s*확인[^'"`\n]*['"`]/u],
    ["확인 필요", /['"`][^'"`\n]*확인\s*필요[^'"`\n]*['"`]/u],
    ["추정", /['"`][^'"`\n]*추정[^'"`\n]*['"`]/u],
    ["측정값", /['"`][^'"`\n]*측정값[^'"`\n]*['"`]/u],
    ["기준점", /['"`][^'"`\n]*기준점[^'"`\n]*['"`]/u],
    ["제보 처리", /['"`][^'"`\n]*제보\s*처리[^'"`\n]*['"`]/u],
    ["처리 절차", /['"`][^'"`\n]*처리\s*절차[^'"`\n]*['"`]/u],
    ["처리 결과", /['"`][^'"`\n]*처리\s*결과[^'"`\n]*['"`]/u],
    ["처리 상태", /['"`][^'"`\n]*처리\s*상태[^'"`\n]*['"`]/u],
    ["처리 상황", /['"`][^'"`\n]*처리\s*상황[^'"`\n]*['"`]/u],
    ["처리하지 못했어요", /['"`][^'"`\n]*처리하지\s*못했어요[^'"`\n]*['"`]/u],
    ["처리 완료", /['"`][^'"`\n]*처리\s*완료[^'"`\n]*['"`]/u],
    ["개인을 알 수 없게 처리", /['"`][^'"`\n]*개인을\s*알\s*수\s*없게\s*처리[^'"`\n]*['"`]/u],
    ["임시 설정", /['"`][^'"`\n]*임시\s*설정[^'"`\n]*['"`]/u],
    ["제보 연결 정보", /['"`][^'"`\n]*제보\s*연결\s*정보[^'"`\n]*['"`]/u],
    ["경로 의견 연결 정보", /['"`][^'"`\n]*경로\s*의견\s*연결\s*정보[^'"`\n]*['"`]/u],
    ["개인정보 제거", /['"`][^'"`\n]*개인정보\s*제거[^'"`\n]*['"`]/u],
    ["답변 안내에 따라 처리", /['"`][^'"`\n]*답변\s*안내에\s*따라\s*처리[^'"`\n]*['"`]/u],
  ];

  const mobileFiles = mobileProductionDartFiles();
  assert.ok(mobileFiles.length > 0, "mobile production Dart files not found");
  for (const file of mobileFiles) {
    const source = read(file);
    for (const [label, pattern] of forbiddenCopyPatterns) {
      assert.doesNotMatch(source, pattern, `${file} still exposes unfriendly copy: ${label}`);
    }
  }
});

test("노선도 탭 화면은 자체 하단 NavigationBar를 만들지 않는다", () => {
  const networkMap = read("apps/mobile/lib/network_map.dart");

  assert.doesNotMatch(
    networkMap,
    /bottomNavigationBar:\s*widget\.bottomNavigationBar\s*\?\?\s*NavigationBar\(/,
    "NetworkMapScreen must receive the shell NavigationBar instead of creating its own",
  );
});

test("모바일 홈 shell과 주요 상태 UI 회귀 테스트는 유지된다", () => {
  const main = read("apps/mobile/lib/main.dart");
  const widgetTest = read("apps/mobile/test/widget_test.dart");

  assert.match(main, /selectedIndex:\s*_selectedTabIndex/);
  assert.doesNotMatch(main, /selectedIndex:\s*[0-9]/);
  assert.match(widgetTest, /홈 노선도 탭은 같은 shell 안에서 선택 상태를 바꾼다/);
  assert.match(widgetTest, /홈 하단 탭은 길찾기 즐겨찾기 더보기를 같은 shell에서 전환한다/);
  assert.match(widgetTest, /홈 하단 루트 탭에서 시스템 뒤로가기는 홈으로 돌아온다/);
  assert.match(widgetTest, /홈은 시설 알림과 최근 경로 로드 실패를 화면에 보여준다/);
  assert.match(widgetTest, /노선도 로드 실패는 재시도와 역 검색 대안을 보여준다/);
  assert.match(main, /homeFacilityAlertLoadingState/);
  assert.match(main, /homeFacilityAlertErrorState/);
  assert.match(main, /homeFacilityAlertEmptyState/);
  assert.match(main, /homeRecentRouteLoadingState/);
  assert.match(main, /homeRecentRouteErrorState/);
  assert.match(main, /homeRecentRouteEmptyState/);
});

test("모바일 역 검색 결과 큰 글자 문구 회귀 테스트는 유지된다", () => {
  const stationSearch = read("apps/mobile/lib/station_search.dart");
  const widgetTest = read("apps/mobile/test/widget_test.dart");
  const resultTileMatch = stationSearch.match(
    /class _StationSearchResultTile[\s\S]*?class _StationRoleActionBar/,
  );
  const largeTextTestMatch = widgetTest.match(
    /testWidgets\('역 검색 결과 핵심 문구는 큰 글자에서 한 줄 말줄임으로 고정하지 않는다'[\s\S]*?\n  testWidgets\('/,
  );

  assert.ok(resultTileMatch, "_StationSearchResultTile block not found");
  const resultTile = resultTileMatch[0];
  assert.match(resultTile, /StationLineBadges\([\s\S]*maxBadgeCount:\s*2/);
  assert.match(
    resultTile,
    /Text\(\s*stationName[\s\S]*Text\(\s*result\.distanceLabel\.isEmpty[\s\S]*Text\(\s*result\.dataQualityLabel/,
  );
  assert.doesNotMatch(resultTile, /maxLines:\s*1/);
  assert.doesNotMatch(resultTile, /overflow:\s*TextOverflow\.ellipsis/);
  assert.ok(largeTextTestMatch, "station search large text widget test block not found");
  const largeTextTest = largeTextTestMatch[0];
  assert.match(largeTextTest, /TextScaler\.linear\(2\.0\)/);
  assert.match(largeTextTest, /김포공항국제선환승센터/);
  assert.match(largeTextTest, /수도권 9호선 급행/);
  assert.match(largeTextTest, /공항철도 직통 일반 공용/);
  assert.match(largeTextTest, /일부 정보는 확인 중이에요/);
  assert.match(largeTextTest, /expect\(widget\.maxLines, isNot\(1\)\)/);
  assert.match(largeTextTest, /expect\(widget\.overflow, isNot\(TextOverflow\.ellipsis\)\)/);
});

test("모바일 경로 결과 단계별 뒤로가기 회귀 테스트는 유지된다", () => {
  const routeSearch = read("apps/mobile/lib/route_search.dart");
  const widgetTest = read("apps/mobile/test/widget_test.dart");
  const routeBackTestPattern = new RegExp([
    "testWidgets\\('경로 결과 단계는 시스템 뒤로가기를 화면 내 뒤로가기와 맞춘다'",
    "routeStartGuidanceButton",
    "routeOpenInternalRouteButton",
    "routeOpenFeedbackButton",
    "routeFeedbackHelpfulButton",
  ].join("[\\s\\S]*"));

  assert.match(widgetTest, routeBackTestPattern);
  assert.match(routeSearch, /return PopScope\(/);
  assert.match(routeSearch, /_RouteWorkflowView\.detail\s*=>\s*_RouteWorkflowView\.list/);
  assert.match(routeSearch, /_RouteWorkflowView\.guidance\s*=>\s*_RouteWorkflowView\.detail/);
  assert.match(routeSearch, /_RouteWorkflowView\.internalRoute\s*=>\s*_RouteWorkflowView\.guidance/);
  assert.match(routeSearch, /_RouteWorkflowView\.feedback\s*=>\s*_RouteWorkflowView\.detail/);
});

test("모바일 설정 저장 실패와 시설 제보 위치 실패 회귀 테스트는 유지된다", () => {
  const main = read("apps/mobile/lib/main.dart");
  const facilityReport = read("apps/mobile/lib/facility_report.dart");
  const widgetTest = read("apps/mobile/test/widget_test.dart");
  const settingsFailurePattern = new RegExp([
    "testWidgets\\('설정 화면 보기 옵션 마지막 queued 저장 실패는 마지막 변경만 되돌린다'",
    "latestSave\\.completeError",
    "설정을 저장하지 못했어요\\. 이전 값으로 되돌렸어요\\.",
    "고대비, 꺼짐",
  ].join("[\\s\\S]*"));
  const facilityNoLocationPattern = new RegExp([
    "testWidgets\\('시설 신고 화면은 GPS가 꺼져 있으면 위치 없이 제보를 선택할 수 있다'",
    "facilityReportSubmitWithoutLocationButton",
    "위치 없이 제보합니다",
    "현재 위치 없이 제보하면 담당자가 위치를 따로 파악해야 할 수 있어요",
    "latitude, isNull",
    "longitude, isNull",
  ].join("[\\s\\S]*"));

  assert.match(main, /_updateViewPreferences/);
  assert.match(main, /_viewPreferences\s*=\s*previous/);
  assert.match(main, /설정을 저장하지 못했어요\. 이전 값으로 되돌렸어요\./);
  assert.match(widgetTest, settingsFailurePattern);
  assert.match(facilityReport, /facilityReportSubmitWithoutLocationButton/);
  assert.match(facilityReport, /facilityReportOpenLocationSettingsButton/);
  assert.match(facilityReport, /facilityReportRetryLocationButton/);
  assert.match(facilityReport, /현재 위치 없이 제보하면 담당자가 위치를 따로 파악해야 할 수 있어요/);
  assert.match(widgetTest, facilityNoLocationPattern);
  assert.match(widgetTest, /시설 신고 화면은 GPS가 꺼져 있으면 위치 설정으로 이동할 수 있다/);
});

test("모바일 오프라인 안내는 저장된 안내 상태를 쉬운 문구로 보여준다", () => {
  const main = read("apps/mobile/lib/main.dart");
  const widgetTest = read("apps/mobile/test/widget_test.dart");
  const offlineScreenMatch = main.match(/class OfflineDataScreen[\s\S]*?class _SupportSectionTitle/);
  const offlineWidgetTestPattern = new RegExp([
    "testWidgets\\('오프라인 데이터 안내는 저장 범위와 품질 제한을 보여준다'",
    "offlineDataSettingsButton",
    "저장된 안내 상태",
    "수도권 역과 노선",
    "마지막 갱신",
    "앱 설치 때 함께 받은 안내",
    "안내 범위",
    "실시간 시설 상태와 제보 전송은 인터넷 연결이 필요해요",
  ].join("[\\s\\S]*"));

  assert.ok(offlineScreenMatch, "OfflineDataScreen block not found");
  const offlineScreen = offlineScreenMatch[0];
  assert.match(main, /offlineDataSettingsButton/);
  assert.match(main, /title:\s*'인터넷 없이 이용'/);
  assert.match(offlineScreen, /저장된 안내 상태/);
  assert.doesNotMatch(offlineScreen, /저장된 데이터 상태/);
  assert.match(offlineScreen, /지역[\s\S]*수도권 역과 노선/);
  assert.match(offlineScreen, /마지막 갱신[\s\S]*앱 설치 때 함께 받은 안내/);
  assert.match(offlineScreen, /안내 범위[\s\S]*주요 역·노선 안내를 먼저 보여줘요/);
  assert.match(offlineScreen, /인터넷 연결 필요[\s\S]*시설 제보[\s\S]*연결 필요/);
  assert.match(widgetTest, offlineWidgetTestPattern);
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

test("release dart-define guard는 demo home data flag를 차단한다", async () => {
  await execFileAsync("bash", ["-n", "tools/mobile/validate-release-dart-defines.sh"], { cwd: root });
  await execFileAsync("tools/mobile/validate-release-dart-defines.sh", [
    "--dart-define=EASYSUBWAY_ENABLE_PUSH_NOTIFICATIONS=false",
  ], { cwd: root });
  await assert.rejects(
    execFileAsync("tools/mobile/validate-release-dart-defines.sh", [
      "--dart-define=EASYSUBWAY_DEMO_HOME_DATA=true",
    ], { cwd: root }),
    /EASYSUBWAY_DEMO_HOME_DATA is not allowed in release/,
  );
});

test("mobile datapack asset audit는 fixture provenance와 최소 row를 검사한다", async () => {
  const auditor = read("tools/ci/audit-mobile-datapack-assets.mjs");
  assert.match(auditor, /artifactKind/);
  assert.match(auditor, /fixture/);
  assert.match(auditor, /sourceInventory/);
  assert.match(auditor, /review-required/);
  assert.match(auditor, /station_exits/);
  assert.match(auditor, /facilities/);
  assert.match(auditor, /data_quality_records/);
  await execFileAsync(process.execPath, [
    "tools/ci/audit-mobile-datapack-assets.mjs",
    "--index",
    "apps/mobile/assets/datapacks/index.json",
    "--root",
    "apps/mobile",
  ], { cwd: root });
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
	  assert.match(workflow, /Android Release Artifact \/ Set up Node[\s\S]*actions\/setup-node@48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e[\s\S]*node-version: "24"[\s\S]*Android Release Artifact \/ Audit bundled datapacks/);
	  assert.match(workflow, /node tools\/ci\/audit-mobile-datapack-assets\.mjs --index apps\/mobile\/assets\/datapacks\/index\.json --root apps\/mobile/);
	  assert.match(workflow, /tools\/mobile\/validate-release-dart-defines\.sh/);
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
	  assert.doesNotMatch(workflow, /--dart-define=EASYSUBWAY_DEMO_HOME_DATA=true/);
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
  const androidRcEvidencePath = "apps/mobile/release/android-rc-store-evidence.json";
  const androidRcEvidence = readJson(androidRcEvidencePath);
  const playProductionAccessPath = "apps/mobile/release/play-production-access-gate.json";
  const playProductionAccessGate = readJson(playProductionAccessPath);
  const playStoreSubmissionContentPath = "apps/mobile/release/play-store-submission-content.json";
  const playStoreSubmissionContent = readJson(playStoreSubmissionContentPath);
  const playGeneratedApkDeviceMatrixPath = "apps/mobile/release/play-generated-apk-device-matrix-gate.json";
  const playGeneratedApkDeviceMatrixGate = readJson(playGeneratedApkDeviceMatrixPath);
  const postLaunchOperationsReviewPath = "apps/mobile/release/post-launch-operations-review-gate.json";
  const postLaunchOperationsReviewGate = readJson(postLaunchOperationsReviewPath);
  const supportIncidentResponsePath = "apps/mobile/release/support-incident-response-gate.json";
  const supportIncidentResponseGate = readJson(supportIncidentResponsePath);
  const abusePenetrationRehearsalPath = "apps/mobile/release/abuse-penetration-rehearsal-gate.json";
  const abusePenetrationRehearsalGate = readJson(abusePenetrationRehearsalPath);
  const releaseGovernanceGate = readJson("apps/mobile/release/release-governance-gate.json");
  const rcEvidenceManifestContractPath = "apps/mobile/release/rc-evidence-manifest-contract.json";
  const rcEvidenceManifestContract = readJson(rcEvidenceManifestContractPath);
  const workflow = read(".github/workflows/release-artifacts.yml");
  const readme = read("README.md");

  assert.equal(gate.schemaVersion, 1);
  assert.equal(gate.applicationId, "easysubway");
  assert.equal(gate.androidApplicationId, "com.easysubway.app");
  assert.equal(gate.releaseGate, "mobile-signed-release-artifacts");
  assert.equal(gate.storeReadyStatus, "blocked_external_distribution_evidence_missing");
  assert.equal(gate.androidRcEvidenceManifest, androidRcEvidencePath);
  assert.equal(gate.rcEvidenceManifestContract, rcEvidenceManifestContractPath);
  assert.equal(gate.androidPageSize16kbGate, "apps/mobile/release/android-16kb-page-size-gate.json");
  assert.equal(gate.playProductionAccessGate, playProductionAccessPath);
  assert.equal(gate.playGeneratedApkDeviceMatrixGate, playGeneratedApkDeviceMatrixPath);
  assert.equal(gate.postLaunchOperationsReviewGate, postLaunchOperationsReviewPath);
  assert.equal(gate.supportIncidentResponseGate, supportIncidentResponsePath);
  assert.equal(gate.abusePenetrationRehearsalGate, abusePenetrationRehearsalPath);

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
  assert.ok(gate.artifacts.android.storeReadyRequires.includes("Play-generated APK or Play-installed build smoke evidence"));
  assert.ok(gate.artifacts.android.storeReadyRequires.includes("Android 16 KB page-size AAB and runtime smoke evidence"));
  assert.equal(gate.artifacts.android.productionRcArtifactStoreReadyCandidate, true);
  assert.equal(gate.artifacts.android.productionRcSigningKeyType, "production-upload-key");
  assert.ok(gate.artifacts.android.productionRcRequiredMetadata.includes("uploadKeySha256Fingerprint"));
  assert.ok(gate.artifacts.android.productionRcRequiredMetadata.includes("appSigningKeySha256Fingerprint"));
  assert.ok(gate.artifacts.android.productionRcRequiredMetadata.includes("versionCodeMonotonicPolicy"));
  assert.ok(gate.artifacts.android.storeReadyRequires.includes("Play production access or closed test requirement satisfaction evidence"));
  assert.ok(gate.artifacts.android.storeReadyRequires.includes("Play-generated APK device compatibility matrix evidence"));
  assert.ok(gate.artifacts.android.storeReadyRequires.includes("Post-launch 2h/24h/7d/30d operations review evidence"));
  assert.ok(
    gate.artifacts.android.storeReadyRequires.includes(
      "Support, data correction, incident notice, emergency datapack response evidence",
    ),
  );
  assert.ok(gate.artifacts.android.storeReadyRequires.includes("Abuse-case and penetration rehearsal evidence"));
  assert.equal(playProductionAccessGate.releaseGate, "play-production-access-closed-test");
  assert.equal(playProductionAccessGate.issue, 1016);
  assert.equal(playProductionAccessGate.parentEvidenceManifest, androidRcEvidencePath);
  assert.equal(playProductionAccessGate.status, "BLOCKED_EXTERNAL");
  assert.equal(playProductionAccessGate.latestApiAccessCheck.qaEvidenceDateKst, "2026-06-29");
  assert.equal(playProductionAccessGate.latestApiAccessCheck.result, "PASS");
  assert.equal(playProductionAccessGate.latestApiAccessCheck.packageName, "com.easysubway.app");
  assert.equal(playProductionAccessGate.latestApiAccessCheck.latestVersionCodeEnv, 10001);
  assert.equal(playProductionAccessGate.latestApiAccessCheck.editInsertReady, true);
  assert.equal(playProductionAccessGate.latestApiAccessCheck.tracksListReady, true);
  assert.deepEqual(playProductionAccessGate.latestApiAccessCheck.tracks, [
    "alpha",
    "beta",
    "internal",
    "production",
  ]);
  assert.equal(playProductionAccessGate.latestApiAccessCheck.tracksMaxVersionCode, 10001);
  assert.equal(playProductionAccessGate.latestApiAccessCheck.latestVersionCodeCoversTrackMax, true);
  assert.equal(playProductionAccessGate.latestApiAccessCheck.editValidateReady, true);
  assert.equal(playProductionAccessGate.latestApiAccessCheck.editDeleteReady, true);
  assert.equal(playProductionAccessGate.latestApiAccessCheck.uploadAttempted, false);
  assert.equal(playProductionAccessGate.latestApiAccessCheck.storeSubmitAttempted, false);
  assert.equal(playProductionAccessGate.latestApiAccessCheck.secretValuesPrinted, false);
  assert.match(
    playProductionAccessGate.latestApiAccessCheck.localOnlyEvidence,
    /\.codex\/evidence\/release\/play-production-access\/1016-api-recheck-20260629\//,
  );
  assert.equal(playProductionAccessGate.officialPolicy.closedTestMinimumOptedInTesters, 12);
  assert.equal(playProductionAccessGate.officialPolicy.closedTestContinuousOptInDays, 14);
  assert.match(playProductionAccessGate.officialPolicy.source, /^https:\/\/support\.google\.com\/googleplay\/android-developer\/answer\/14151465/);
  assert.ok(playProductionAccessGate.requiredConsoleEvidence.every((item) => item.releaseBlocker === true));
  assert.ok(playProductionAccessGate.requiredConsoleEvidence.map((item) => item.id).includes("play_production_access_status"));
  assert.ok(playProductionAccessGate.requiredConsoleEvidence.map((item) => item.id).includes("play_closed_test_requirement"));
  assert.ok(playProductionAccessGate.requiredConsoleEvidence.map((item) => item.id).includes("play_app_signing_enrollment"));
  assert.ok(playProductionAccessGate.requiredConsoleEvidence.map((item) => item.id).includes("play_version_code_monotonicity"));
  assert.ok(
    playProductionAccessGate.requiredConsoleEvidence
      .find((item) => item.id === "play_production_access_status")
      .evidence.includes("android-publisher-api-edit-track-list-summary"),
  );
  assert.ok(
    playProductionAccessGate.requiredConsoleEvidence
      .find((item) => item.id === "play_version_code_monotonicity")
      .evidence.includes("android-publisher-api-track-versioncode-summary"),
  );
  assert.equal(playProductionAccessGate.goNoGoRules.missingPlayAppSigningEnrollment, "BLOCKED_EXTERNAL");
  assert.equal(playProductionAccessGate.goNoGoRules.versionCodeNotGreaterThanLatestPlayArtifact, "BLOCKED_EXTERNAL");
  assert.equal(playProductionAccessGate.goNoGoRules.failedRcVersionCodeReuse, "BLOCKED_TECHNICAL");
  assert.match(playProductionAccessGate.evidencePolicy.localOnlyEvidenceRoot, /\.codex\/evidence\/release\/play-production-access/);
  assert.equal(playStoreSubmissionContent.releaseGate, "play-store-submission-content");
  assert.equal(playStoreSubmissionContent.issue, 1018);
  assert.equal(playStoreSubmissionContent.androidRcEvidenceManifest, androidRcEvidencePath);
  assert.equal(playStoreSubmissionContent.storePrivacyInventory, "apps/mobile/release/store-privacy-inventory.json");
  assert.equal(playStoreSubmissionContent.appContentDeclarations.ads, false);
  assert.equal(playStoreSubmissionContent.appContentDeclarations.publicUserSignIn, false);
  assert.equal(playStoreSubmissionContent.appContentDeclarations.accountCreation, false);
  assert.equal(playStoreSubmissionContent.appContentDeclarations.backgroundLocation, false);
  assert.equal(playStoreSubmissionContent.dataSafetyDeclarations.tracking, false);
  assert.equal(playStoreSubmissionContent.dataSafetyDeclarations.sharesDataWithThirdParties, false);
  assert.equal(playStoreSubmissionContent.dataSafetyDeclarations.dataEncryptedInTransit, true);
  assert.equal(playStoreSubmissionContent.dataSafetyDeclarations.dataDeletionRequestSupported, true);
  assert.ok(playStoreSubmissionContent.dataSafetyDeclarations.requiredCollectedDataTypes.includes("Location"));
  assert.ok(playStoreSubmissionContent.dataSafetyDeclarations.requiredCollectedDataTypes.includes("Photos and videos"));
  assert.match(playStoreSubmissionContent.koreanListing.fullDescriptionKo, /데이터 기준일|공식 출처|현장 상황|실시간/);
  for (const claim of playStoreSubmissionContent.prohibitedClaims) {
    assert.doesNotMatch(playStoreSubmissionContent.koreanListing.fullDescriptionKo, new RegExp(claim));
    assert.doesNotMatch(playStoreSubmissionContent.koreanListing.shortDescription, new RegExp(claim));
  }
  assert.equal(playGeneratedApkDeviceMatrixGate.releaseGate, "play-generated-apk-device-matrix");
  assert.equal(playGeneratedApkDeviceMatrixGate.issue, 1016);
  assert.equal(playGeneratedApkDeviceMatrixGate.androidRcEvidenceManifest, androidRcEvidencePath);
  assert.ok(playGeneratedApkDeviceMatrixGate.acceptedArtifactSources.includes("internal-app-sharing"));
  assert.ok(playGeneratedApkDeviceMatrixGate.acceptedArtifactSources.includes("play-installed-build"));
  assert.ok(playGeneratedApkDeviceMatrixGate.requiredArtifactEvidence.includes("play-generated-split-apk-install-log"));
  assert.ok(playGeneratedApkDeviceMatrixGate.requiredArtifactEvidence.includes("install-provenance-record"));
  assert.ok(playGeneratedApkDeviceMatrixGate.requiredArtifactEvidence.includes("foreground-app-launch-smoke-record"));
  assert.ok(playGeneratedApkDeviceMatrixGate.requiredArtifactEvidence.includes("latest-play-uploaded-versioncode-record"));
  assert.ok(playGeneratedApkDeviceMatrixGate.requiredArtifactEvidence.includes("play-generated-artifact-identity-match-record"));
  assert.ok(playGeneratedApkDeviceMatrixGate.requiredArtifactEvidence.includes("pre-launch-report-crash-anr-policy-warning-summary"));
  assert.ok(playGeneratedApkDeviceMatrixGate.requiredArtifactEvidence.includes("device-specific-manifest-dump"));
  assert.ok(playGeneratedApkDeviceMatrixGate.requiredArtifactEvidence.includes("native-library-delivery-and-16kb-page-size-record"));
  assert.ok(playGeneratedApkDeviceMatrixGate.requiredArtifactIdentityFields.includes("appSigningKeySha256Fingerprint"));
  assert.ok(playGeneratedApkDeviceMatrixGate.requiredArtifactIdentityFields.includes("dataPackManifestSha256"));
  assert.match(playGeneratedApkDeviceMatrixGate.identityMatchPolicy, /RC evidence manifest/);
  assert.match(playGeneratedApkDeviceMatrixGate.installProvenancePolicy.playGeneratedApkShellInstallKo, /Play-installed build smoke를 대체하지 않는다/);
  assert.ok(playGeneratedApkDeviceMatrixGate.installProvenancePolicy.playInstalledBuildRequires.includes("installerPackageName=com.android.vending"));
  assert.ok(playGeneratedApkDeviceMatrixGate.installProvenancePolicy.playInstalledBuildRequires.includes("foregroundPackage=com.easysubway.app"));
  assert.ok(playGeneratedApkDeviceMatrixGate.installProvenancePolicy.forbiddenSmokeSubstitutes.includes("initiatingPackageName=com.android.shell"));
  assert.ok(playGeneratedApkDeviceMatrixGate.installProvenancePolicy.forbiddenSmokeSubstitutes.includes("package stopped=true or notLaunched=true"));
  assert.match(playGeneratedApkDeviceMatrixGate.versionCodePolicy, /최신 artifact보다 커야/);
  assert.ok(playGeneratedApkDeviceMatrixGate.deviceMatrix.every((item) => item.releaseBlocker === true));
  assert.ok(playGeneratedApkDeviceMatrixGate.deviceMatrix.map((item) => item.id).includes("android_16_16kb_page_size"));
  assert.equal(playGeneratedApkDeviceMatrixGate.goNoGoRules.localAabOnly, "BLOCKED_EXTERNAL");
  assert.equal(playGeneratedApkDeviceMatrixGate.goNoGoRules.artifactIdentityMismatch, "BLOCKED_TECHNICAL");
  assert.equal(playGeneratedApkDeviceMatrixGate.goNoGoRules.appSigningCertificateMismatch, "BLOCKED_TECHNICAL");
  assert.equal(playGeneratedApkDeviceMatrixGate.goNoGoRules.versionCodeNotGreaterThanLatestPlayArtifact, "BLOCKED_EXTERNAL");
  assert.equal(playGeneratedApkDeviceMatrixGate.goNoGoRules.missingPlayInstallerProvenance, "BLOCKED_EXTERNAL");
  assert.equal(playGeneratedApkDeviceMatrixGate.goNoGoRules.shellInstalledArtifactUsedAsPlayInstalledSmoke, "BLOCKED_EXTERNAL");
  assert.equal(postLaunchOperationsReviewGate.releaseGate, "post-launch-operations-review");
  assert.equal(postLaunchOperationsReviewGate.issue, 1019);
  assert.equal(postLaunchOperationsReviewGate.status, "BLOCKED_EXTERNAL");
  assert.equal(postLaunchOperationsReviewGate.androidRcEvidenceManifest, androidRcEvidencePath);
  assert.equal(postLaunchOperationsReviewGate.operationsEvidenceManifest, "apps/mobile/release/operations-release-evidence.json");
  assert.equal(postLaunchOperationsReviewGate.supportIncidentResponseGate, supportIncidentResponsePath);
  assert.match(postLaunchOperationsReviewGate.evidenceRoot, /\.codex\/evidence\/release\/post-launch-operations-review\/<rc-or-run>/);
  assert.equal(postLaunchOperationsReviewGate.latestQaEvidenceSummary.qaEvidenceDateKst, "2026-06-28");
  assert.equal(postLaunchOperationsReviewGate.latestQaEvidenceSummary.alertRouteDryRun.result, "PASS");
  assert.equal(postLaunchOperationsReviewGate.latestQaEvidenceSummary.alertRouteDryRun.channel, "Slack Incoming Webhook");
  assert.match(
    postLaunchOperationsReviewGate.latestQaEvidenceSummary.alertRouteDryRun.publicEvidenceSummary,
    /HTTP 200 \/ ok/,
  );
  assert.equal(
    postLaunchOperationsReviewGate.latestQaEvidenceSummary.supportMailboxRouting.result,
    "RESOLVED_BY_QA_MANUAL_EVIDENCE",
  );
  assert.deepEqual(postLaunchOperationsReviewGate.latestQaEvidenceSummary.supportMailboxRouting.addresses, [
    "support@aquilaxk.site",
    "security@aquilaxk.site",
    "privacy@aquilaxk.site",
  ]);
  assert.deepEqual(postLaunchOperationsReviewGate.latestQaEvidenceSummary.remainingExternalBlockers, [
    "play-review-status-summary",
    "crash-anr-vitals-summary",
    "support-ticket-summary-after-public-release",
    "post-launch-review-window-evidence-after-public-release",
  ]);
  assert.deepEqual(
    postLaunchOperationsReviewGate.reviewWindows.map((window) => window.id),
    ["first_2h", "first_24h", "day_7", "day_30"],
  );
  for (const window of postLaunchOperationsReviewGate.reviewWindows) {
    assert.ok(window.ownerKo.length > 0, `${window.id} must define owner`);
    assert.ok(window.requiredSignals.length > 0, `${window.id} must define monitoring signals`);
    assert.ok(window.decisionKo.length > 0, `${window.id} must define decision rule`);
  }
  assert.deepEqual(
    postLaunchOperationsReviewGate.killSwitchAndRollbackOwners.map((owner) => owner.domain).sort(),
    ["backend", "datapack", "realtime"],
  );
  assert.ok(postLaunchOperationsReviewGate.fixedReleaseProcedure.requiredSteps.includes("local-emulator-regression-evidence"));
  assert.equal(postLaunchOperationsReviewGate.stagedRolloutPolicy.initialProductionRelease, "not-available-for-first-public-release");
  assert.ok(postLaunchOperationsReviewGate.stagedRolloutPolicy.secondAndLaterUpdates.includes("halt-rollout-on-p0-or-policy-warning"));
  assert.ok(postLaunchOperationsReviewGate.dryRunRequiredEvidence.includes("alert-route-dry-run-log"));
  assert.deepEqual(postLaunchOperationsReviewGate.releaseEvidenceSummaryPolicy.githubSummaryFields, [
    "reviewWindowId",
    "artifactIdentity",
    "signalSnapshot",
    "owner",
    "decision",
    "goNoGoResult",
    "redactionNotes",
    "localEvidencePath",
  ]);
  for (const evidenceId of postLaunchOperationsReviewGate.dryRunRequiredEvidence) {
    assert.ok(
      postLaunchOperationsReviewGate.releaseEvidenceSummaryPolicy.requiredEvidenceSet.includes(evidenceId),
      `${evidenceId} must be included in post-launch GitHub summary evidence`,
    );
  }
  for (const evidenceId of postLaunchOperationsReviewGate.fixedReleaseProcedure.requiredSteps) {
    assert.ok(
      postLaunchOperationsReviewGate.releaseEvidenceSummaryPolicy.requiredEvidenceSet.includes(evidenceId),
      `${evidenceId} must be included in post-launch GitHub summary evidence`,
    );
  }
  for (const evidenceId of postLaunchOperationsReviewGate.reviewWindows.flatMap((window) => window.requiredSignals)) {
    assert.ok(
      postLaunchOperationsReviewGate.releaseEvidenceSummaryPolicy.requiredEvidenceSet.includes(evidenceId),
      `${evidenceId} must be included in post-launch GitHub summary evidence`,
    );
  }
  for (const evidenceId of postLaunchOperationsReviewGate.killSwitchAndRollbackOwners.flatMap((owner) => owner.evidence)) {
    assert.ok(
      postLaunchOperationsReviewGate.releaseEvidenceSummaryPolicy.requiredEvidenceSet.includes(evidenceId),
      `${evidenceId} must be included in post-launch GitHub summary evidence`,
    );
  }
  assert.ok(
    postLaunchOperationsReviewGate.releaseEvidenceSummaryPolicy.requiredEvidenceSet.includes(
      "crash-anr-vitals-summary",
    ),
  );
  assert.ok(
    postLaunchOperationsReviewGate.releaseEvidenceSummaryPolicy.requiredEvidenceSet.includes(
      "fixed-release-owner-acknowledgement",
    ),
  );
  for (const forbiddenValue of [
    "Play Console account data",
    "support mailbox personal data",
    "device identifiers",
    "provider credential or quota token",
  ]) {
    assert.ok(
      postLaunchOperationsReviewGate.releaseEvidenceSummaryPolicy.forbiddenInGithubSummary.includes(forbiddenValue),
      `${forbiddenValue} must be forbidden in post-launch GitHub summary`,
    );
  }
  assert.equal(supportIncidentResponseGate.releaseGate, "support-incident-response");
  assert.equal(supportIncidentResponseGate.issue, 1019);
  assert.equal(supportIncidentResponseGate.status, "BLOCKED_EXTERNAL");
  assert.equal(supportIncidentResponseGate.androidRcEvidenceManifest, androidRcEvidencePath);
  assert.equal(supportIncidentResponseGate.postLaunchOperationsReviewGate, postLaunchOperationsReviewPath);
  assert.match(supportIncidentResponseGate.evidenceRoot, /\.codex\/evidence\/release\/support-incident-response\/<rc-or-run>/);
  assert.equal(supportIncidentResponseGate.latestQaEvidenceSummary.publicContactDomain, "aquilaxk.site");
  assert.equal(
    supportIncidentResponseGate.latestQaEvidenceSummary.mailboxRouting.result,
    "RESOLVED_BY_QA_MANUAL_EVIDENCE",
  );
  assert.deepEqual(supportIncidentResponseGate.latestQaEvidenceSummary.mailboxRouting.addresses, [
    "support@aquilaxk.site",
    "security@aquilaxk.site",
    "privacy@aquilaxk.site",
  ]);
  assert.ok(supportIncidentResponseGate.latestQaEvidenceSummary.mailboxRouting.dnsEvidence.includes("MX records present"));
  assert.match(
    supportIncidentResponseGate.latestQaEvidenceSummary.mailboxRouting.redactionPolicy,
    /raw report receipt token/,
  );
  assert.match(
    supportIncidentResponseGate.latestQaEvidenceSummary.mailboxRouting.redactionPolicy,
    /operator private contact/,
  );
  assert.match(
    supportIncidentResponseGate.latestQaEvidenceSummary.mailboxRouting.redactionPolicy,
    /provider credential or quota token/,
  );
  assert.match(
    supportIncidentResponseGate.latestQaEvidenceSummary.mailboxRouting.redactionPolicy,
    /photo metadata/,
  );
  assert.deepEqual(supportIncidentResponseGate.latestQaEvidenceSummary.remainingSupportReadiness, [
    "data-error-triage-dry-run",
    "emergency-datapack-release-rollback-runbook-match",
    "incident-notice-copy-review",
    "local-emulator-help-screen-screenshot-or-ui-tree",
    "operator-contact-route-evidence",
  ]);
  assert.deepEqual(
    supportIncidentResponseGate.supportChannels.map((channel) => channel.id).sort(),
    ["faq_and_status_notice", "security_privacy_deletion", "support_email"],
  );
  assert.deepEqual(
    supportIncidentResponseGate.intakeCategories.map((category) => category.id).sort(),
    ["p0_safety_data_error", "p1_accessibility_blocker", "p2_support_question"],
  );
  assert.equal(supportIncidentResponseGate.dataCorrectionFlow.slaTargets.p0SafetyErrorTriage, "PT2H");
  assert.equal(supportIncidentResponseGate.dataCorrectionFlow.slaTargets.dataCorrectionApproval, "P1D");
  assert.equal(supportIncidentResponseGate.dataCorrectionFlow.slaTargets.emergencyOverridePublish, "PT4H");
  assert.equal(supportIncidentResponseGate.dataCorrectionFlow.slaTargets.emergencyDatapackRelease, "P1D");
  assert.ok(supportIncidentResponseGate.operatorContactRoutes.map((route) => route.id).includes("seoul_metro_or_city_provider"));
  assert.ok(supportIncidentResponseGate.incidentNoticeTemplates.map((notice) => notice.id).includes("data_error_notice"));
  assert.ok(supportIncidentResponseGate.retentionDuplicateOverridePolicy.requiredEvidence.includes("override-rollback-sample"));
  assert.ok(supportIncidentResponseGate.dryRunRequiredEvidence.includes("data-error-triage-dry-run"));
  assert.ok(supportIncidentResponseGate.dryRunRequiredEvidence.includes("local-emulator-help-screen-screenshot-or-ui-tree"));
  assert.deepEqual(supportIncidentResponseGate.supportEvidenceSummaryPolicy.githubSummaryFields, [
    "channelId",
    "redactedReceiptReference",
    "receivedAt",
    "owner",
    "result",
    "redactionNotes",
    "localEvidencePath",
  ]);
  for (const evidenceId of supportIncidentResponseGate.supportChannels.flatMap((channel) => channel.requiredEvidence)) {
    assert.ok(
      supportIncidentResponseGate.supportEvidenceSummaryPolicy.requiredEvidenceSet.includes(evidenceId),
      `${evidenceId} must be included in support GitHub summary evidence`,
    );
  }
  for (const evidenceId of supportIncidentResponseGate.dryRunRequiredEvidence) {
    assert.ok(
      supportIncidentResponseGate.supportEvidenceSummaryPolicy.requiredEvidenceSet.includes(evidenceId),
      `${evidenceId} must be included in support GitHub summary evidence`,
    );
  }
  for (const evidenceId of supportIncidentResponseGate.operatorContactRoutes.flatMap((route) => route.requiredEvidence)) {
    assert.ok(
      supportIncidentResponseGate.supportEvidenceSummaryPolicy.requiredEvidenceSet.includes(evidenceId),
      `${evidenceId} must be included in support GitHub summary evidence`,
    );
  }
  for (const evidenceId of supportIncidentResponseGate.retentionDuplicateOverridePolicy.requiredEvidence) {
    assert.ok(
      supportIncidentResponseGate.supportEvidenceSummaryPolicy.requiredEvidenceSet.includes(evidenceId),
      `${evidenceId} must be included in support GitHub summary evidence`,
    );
  }
  for (const evidenceId of supportIncidentResponseGate.dataCorrectionFlow.requiredSteps) {
    assert.ok(
      supportIncidentResponseGate.supportEvidenceSummaryPolicy.requiredEvidenceSet.includes(evidenceId),
      `${evidenceId} must be included in support GitHub summary evidence`,
    );
  }
  assert.ok(
    supportIncidentResponseGate.supportEvidenceSummaryPolicy.requiredEvidenceSet.includes(
      "support-mailbox-receive-test",
    ),
  );
  assert.ok(
    supportIncidentResponseGate.supportEvidenceSummaryPolicy.requiredEvidenceSet.includes(
      "data-error-triage-dry-run",
    ),
  );
  for (const forbiddenValue of [
    "support mailbox personal data",
    "raw report receipt token",
    "operator private contact",
    "provider credential or quota token",
    "photo metadata",
  ]) {
    assert.ok(
      supportIncidentResponseGate.supportEvidenceSummaryPolicy.forbiddenInGithubSummary.includes(forbiddenValue),
      `${forbiddenValue} must be forbidden in support GitHub summary`,
    );
  }
  assert.equal(abusePenetrationRehearsalGate.releaseGate, "abuse-penetration-rehearsal");
  assert.equal(abusePenetrationRehearsalGate.issue, 1022);
  assert.equal(abusePenetrationRehearsalGate.status, "BLOCKED_EXTERNAL");
  assert.equal(abusePenetrationRehearsalGate.androidRcEvidenceManifest, androidRcEvidencePath);
  assert.equal(abusePenetrationRehearsalGate.securityPrivacyEvidenceManifest, "apps/mobile/release/security-privacy-release-evidence.json");
  assert.match(abusePenetrationRehearsalGate.evidenceRoot, /\.codex\/evidence\/security\/abuse-penetration-rehearsal\/<rc-or-run>/);
  assert.equal(abusePenetrationRehearsalGate.latestQaEvidenceStatus.qaEvidenceDateKst, "2026-06-28");
  assert.equal(abusePenetrationRehearsalGate.latestQaEvidenceStatus.playAndStorePreflight.androidPlayInternalTrack, "READY");
  assert.equal(
    abusePenetrationRehearsalGate.latestQaEvidenceStatus.playAndStorePreflight.googlePlayApi,
    "READY_EDIT_TRACK_VALIDATE",
  );
  assert.equal(abusePenetrationRehearsalGate.latestQaEvidenceStatus.playAndStorePreflight.uploadedInternalVersionCode, 10001);
  assert.equal(abusePenetrationRehearsalGate.latestQaEvidenceStatus.playAndStorePreflight.latestVersionCodeEnv, 10001);
  assert.deepEqual(abusePenetrationRehearsalGate.latestQaEvidenceStatus.resolvedEvidence, [
    "android-play-internal-track-env-preflight",
    "datapack-object-storage-publish-env-preflight",
    "google-play-api-edit-track-validate",
    "play-internal-upload-version-code-10001",
    "store-distribution-evidence-success",
    "production-datapack-release-publish-success",
    "android-aab-release-artifact-secret-scan-output",
    "release-aab-internal-endpoint-scan-output",
    "backend-image-env-redaction-summary",
    "backend-abuse-security-selected-tests",
    "trusted-proxy-negative-test-output",
  ]);
  assert.deepEqual(abusePenetrationRehearsalGate.latestQaEvidenceStatus.remainingExternalBlockers, [
    "play-generated-apk-download-id-summary",
    "play-installed-build-smoke",
    "play-pre-launch-report-crash-anr-policy-summary",
    "network-trace-redaction-summary-from-play-installed-build",
    "deployed-public-https-backend-report-admin-base-url-evidence",
    "deployed-admin-operator-auth-session-csrf-summary",
    "deployed-signed-url-boundary-summary",
    "object-storage-lifecycle-retention-delete-summary",
    "deployed-distributed-or-multi-node-rate-limit-rehearsal",
  ]);
  assert.match(abusePenetrationRehearsalGate.latestQaEvidenceStatus.notClosingReasonKo, /#1022/);
  assert.equal(abusePenetrationRehearsalGate.latestQaEvidenceStatus.redactionPolicy.secretValuesPrinted, false);
  assert.ok(
    abusePenetrationRehearsalGate.latestQaEvidenceStatus.redactionPolicy.forbiddenInGitHubEvidence.includes(
      "raw signed URL",
    ),
  );
  assert.deepEqual(abusePenetrationRehearsalGate.buildIdentityPolicy.requiredIssueLinks, ["#1015", "#1016", "#1020"]);
  assert.deepEqual(abusePenetrationRehearsalGate.buildIdentityPolicy.acceptedArtifactSources, [
    "rc-aab",
    "play-generated-apk",
    "play-installed-build",
    "backend-release-image",
  ]);
  assert.deepEqual(abusePenetrationRehearsalGate.buildIdentityPolicy.requiredIdentityFields, [
    "gitSha",
    "versionCode",
    "androidApplicationId",
    "dataPackManifestSha256",
  ]);
  assert.deepEqual(abusePenetrationRehearsalGate.buildIdentityPolicy.requiredIdentityAnyOf, [
    ["aabSha256", "generatedApkSha256"],
    ["backendImageDigest", "backendArtifactSha256"],
  ]);
  assert.equal(abusePenetrationRehearsalGate.buildIdentityPolicy.mismatchDisposition, "NO_GO");
  assert.ok(abusePenetrationRehearsalGate.artifactSecretAndEndpointScan.forbiddenFindings.includes("provider secret"));
  assert.ok(abusePenetrationRehearsalGate.artifactSecretAndEndpointScan.forbiddenFindings.includes("receipt token"));
  assert.deepEqual(
    abusePenetrationRehearsalGate.abuseScenarios.map((scenario) => scenario.id).sort(),
    [
      "admin_operator_auth_session_csrf",
      "distributed_rate_limit_abuse",
      "provider_and_release_secret_exposure",
      "receipt_token_replay_and_status_abuse",
      "report_photo_upload_abuse",
      "signed_url_lifecycle_abuse",
    ],
  );
  const rehearsalMatrices = abusePenetrationRehearsalGate.rehearsalMatrices;
  assert.deepEqual(Object.keys(rehearsalMatrices).sort(), [
    "adminOperatorSecurity",
    "distributedRateLimitAbuse",
    "objectStorageLifecycle",
    "providerReleaseSecretExposure",
    "receiptTokenAbuse",
    "reportUploadLifecycle",
    "signedUploadUrlBoundary",
  ]);
  assert.deepEqual(
    [...new Set(Object.values(rehearsalMatrices).map((matrix) => matrix.scenarioId))].sort(),
    abusePenetrationRehearsalGate.abuseScenarios.map((scenario) => scenario.id).sort(),
    "every #1022 abuse scenario must have per-case rehearsal matrix coverage",
  );
  const abuseScenarioIds = new Set(abusePenetrationRehearsalGate.abuseScenarios.map((scenario) => scenario.id));
  const requiredMatrixCases = {
    receiptTokenAbuse: [
      "brute_force_guessing",
      "replay_after_status_lookup",
      "cross_report_enumeration",
      "confirm_endpoint_abuse",
      "url_header_log_redaction",
    ],
    signedUploadUrlBoundary: [
      "method_mismatch",
      "content_type_mismatch",
      "size_limit_exceeded",
      "ttl_expired",
      "object_key_prefix_traversal",
      "signed_url_reuse",
    ],
    reportUploadLifecycle: [
      "upload_intent_abuse",
      "duplicate_claim",
      "submit_without_valid_claim",
      "status_lookup_without_valid_receipt",
      "confirm_without_valid_receipt",
      "orphan_cleanup_after_failed_claim",
      "malicious_photo_upload",
    ],
    adminOperatorSecurity: [
      "login_failure_lockout",
      "logout_session_invalidation",
      "session_expiry",
      "csrf_missing_mutation",
      "role_denied_personal_data",
      "role_denied_photo_read",
      "tenant_authorization_bypass",
      "break_glass_audit_redaction",
    ],
    objectStorageLifecycle: [
      "orphan_object_cleanup",
      "retention_policy_record",
      "delete_after_report_deletion",
      "signed_url_expiry_enforced",
      "storage_audit_redaction",
    ],
    distributedRateLimitAbuse: [
      "multi_node_upload_intent_flooding",
      "claim_submit_status_confirm_flooding",
      "trusted_proxy_spoofing",
      "abuse_store_mode_record",
      "single_instance_exception_link",
    ],
    providerReleaseSecretExposure: [
      "tracked_secret_search",
      "android_artifact_secret_scan",
      "backend_image_env_redaction",
      "release_endpoint_allowlist_diff",
      "pr_evidence_redaction",
    ],
  };
  for (const [matrixId, requiredCases] of Object.entries(requiredMatrixCases)) {
    const matrix = rehearsalMatrices[matrixId];
    assert.ok(abuseScenarioIds.has(matrix.scenarioId), `${matrixId} must reference an existing #1022 scenario`);
    assert.deepEqual(matrix.requiredCases, requiredCases, `${matrixId} must require all #1022 abuse cases`);
    for (const field of ["caseId", "expectedStatus", "observedStatus", "redactionResult", "localEvidencePath"]) {
      assert.ok(matrix.summaryFields.includes(field), `${matrixId} must include PR summary field ${field}`);
    }
    assert.ok(Array.isArray(matrix.requiredEvidence), `${matrixId} must define evidence`);
    assert.ok(matrix.requiredEvidence.length > 0, `${matrixId} must require evidence`);
    assert.ok(Array.isArray(matrix.forbiddenSummaryValues), `${matrixId} must forbid sensitive summary values`);
    assert.ok(matrix.forbiddenSummaryValues.length > 0, `${matrixId} must have forbidden summary values`);
  }
  for (const scenario of abusePenetrationRehearsalGate.abuseScenarios) {
    const matrixEvidence = new Set(
      Object.values(rehearsalMatrices)
        .filter((matrix) => matrix.scenarioId === scenario.id)
        .flatMap((matrix) => matrix.requiredEvidence),
    );
    for (const evidenceId of scenario.requiredEvidence) {
      assert.ok(
        matrixEvidence.has(evidenceId),
        `${scenario.id} rehearsal matrices must include scenario evidence ${evidenceId}`,
      );
    }
  }
  assert.ok(
    rehearsalMatrices.receiptTokenAbuse.forbiddenSummaryValues.includes("raw receipt token"),
    "receipt token rehearsal summary must not expose raw tokens",
  );
  assert.ok(
    rehearsalMatrices.signedUploadUrlBoundary.forbiddenSummaryValues.includes("raw signed URL"),
    "signed URL rehearsal summary must not expose raw URLs",
  );
  assert.ok(
    rehearsalMatrices.adminOperatorSecurity.forbiddenSummaryValues.includes("session cookie"),
    "admin/operator rehearsal summary must not expose session cookies",
  );
  assert.ok(
    rehearsalMatrices.objectStorageLifecycle.requiredEvidence.includes("object-retention-delete-policy-summary"),
    "storage lifecycle rehearsal must require retention/delete evidence",
  );
  assert.equal(abusePenetrationRehearsalGate.manualRehearsalPolicy.localAndroidEmulatorRequiredForMobileEvidence, true);
  assert.deepEqual(abusePenetrationRehearsalGate.manualRehearsalPolicy.githubSummaryFields, [
    "scenarioId",
    "artifactIdentity",
    "commandOrManualCheck",
    "findingCounts",
    "result",
    "redactionNotes",
    "localEvidencePath",
  ]);
  assert.equal(abusePenetrationRehearsalGate.manualRehearsalPolicy.perCaseSummaryRequired, true);
  assert.deepEqual(abusePenetrationRehearsalGate.manualRehearsalPolicy.minimumSummaryFields, [
    "caseId",
    "expectedStatus",
    "observedStatus",
    "redactionResult",
    "localEvidencePath",
  ]);
  assert.ok(abusePenetrationRehearsalGate.manualRehearsalPolicy.forbiddenInEvidence.includes("raw receipt token"));
  assert.ok(abusePenetrationRehearsalGate.manualRehearsalPolicy.forbiddenInEvidence.includes("raw signed URL"));
  assert.equal(abusePenetrationRehearsalGate.findingPolicy.criticalHighAllowed, 0);
  assert.equal(abusePenetrationRehearsalGate.findingPolicy.waiverIssue, 1020);
  assert.deepEqual(
    abusePenetrationRehearsalGate.findingPolicy.waiverRequiredFields,
    releaseGovernanceGate.waiverSchema.requiredFields,
  );
  assert.equal(androidRcEvidence.releaseGate, "android-rc-store-evidence");
  assert.equal(androidRcEvidence.releaseBlockerPolicy, true);
  assert.ok(androidRcEvidence.requiredEvidence.signingAndIdentity.includes("rc-evidence-manifest"));
  assert.equal(androidRcEvidence.scope.platform.android, "RELEASE_REQUIRED");
  assert.equal(androidRcEvidence.scope.platform.ios, "DEFERRED_OUT_OF_SCOPE");
  assert.deepEqual(androidRcEvidence.scope.distributionFlow, [
    "internal-test",
    "closed-test",
    "production-access",
    "rc-freeze",
    "go-no-go",
    "production-submission",
    "post-release-monitoring",
  ]);
  assert.ok(androidRcEvidence.requiredEvidence.signingAndIdentity.includes("play-app-signing-enrollment"));
  assert.ok(androidRcEvidence.requiredEvidence.signingAndIdentity.includes("latest-play-uploaded-versioncode-comparison"));
  assert.ok(androidRcEvidence.requiredEvidence.signingAndIdentity.includes("failed-rc-versioncode-reuse-policy"));
  assert.ok(androidRcEvidence.requiredEvidence.aabInspection.includes("bundletool-manifest-dump"));
  assert.ok(androidRcEvidence.requiredEvidence.pageSize16kb.includes("android-16kb-page-size-gate-manifest"));
  assert.ok(androidRcEvidence.requiredEvidence.pageSize16kb.includes("bundletool-config-dump"));
  assert.ok(androidRcEvidence.requiredEvidence.pageSize16kb.includes("adb-getconf-page-size-16384"));
  assert.ok(androidRcEvidence.requiredEvidence.pageSize16kb.includes("android-15-or-16-page-size-smoke"));
  assert.ok(androidRcEvidence.requiredEvidence.playGeneratedArtifact.includes("play-generated-apk-or-installed-build-smoke"));
  assert.ok(androidRcEvidence.requiredEvidence.playGeneratedArtifact.includes("play-generated-apk-device-matrix-gate-manifest"));
  assert.ok(androidRcEvidence.requiredEvidence.playGeneratedArtifact.includes("play-app-signing-certificate-record"));
  assert.ok(androidRcEvidence.requiredEvidence.playGeneratedArtifact.includes("play-generated-artifact-identity-match-record"));
  assert.ok(androidRcEvidence.requiredEvidence.playGeneratedArtifact.includes("rc-versioncode-greater-than-latest-play-artifact-record"));
  assert.ok(androidRcEvidence.requiredEvidence.playGeneratedArtifact.includes("split-apk-manifest-permission-network-config-record"));
  assert.ok(androidRcEvidence.requiredEvidence.playGeneratedArtifact.includes("device-matrix-smoke-summary"));
  assert.ok(androidRcEvidence.requiredEvidence.androidAccessibilityQa.includes("talkback-rc-build-notes"));
  assert.ok(androidRcEvidence.requiredEvidence.playConsoleSubmission.includes("play-production-access-gate-manifest"));
  assert.ok(androidRcEvidence.requiredEvidence.playConsoleSubmission.includes("closed-test-12-testers-14-days-continuous-opt-in-record"));
  assert.ok(androidRcEvidence.requiredEvidence.playConsoleSubmission.includes("production-access-application-response-record"));
  assert.ok(androidRcEvidence.requiredEvidence.playConsoleSubmission.includes("play-store-submission-content-manifest"));
  assert.ok(androidRcEvidence.requiredEvidence.playConsoleSubmission.includes("data-safety-answer-contract"));
  assert.ok(androidRcEvidence.requiredEvidence.playConsoleSubmission.includes("korean-store-listing-contract"));
  assert.ok(androidRcEvidence.requiredEvidence.playConsoleSubmission.includes("store-graphic-screenshot-asset-record"));
  assert.ok(androidRcEvidence.requiredEvidence.playConsoleSubmission.includes("data-safety-binary-network-trace-match"));
  assert.ok(androidRcEvidence.requiredEvidence.preReviewPreLaunch.includes("abuse-penetration-rehearsal-gate-manifest"));
  assert.ok(androidRcEvidence.requiredEvidence.preReviewPreLaunch.includes("android-aab-or-play-apk-secret-scan-output"));
  assert.ok(androidRcEvidence.requiredEvidence.preReviewPreLaunch.includes("report-photo-receipt-signed-url-abuse-summary"));
  assert.ok(androidRcEvidence.requiredEvidence.preReviewPreLaunch.includes("admin-operator-session-csrf-rate-limit-abuse-summary"));
  assert.ok(androidRcEvidence.requiredEvidence.preReviewPreLaunch.includes("critical-high-finding-zero-or-waiver-record"));
  assert.ok(androidRcEvidence.requiredEvidence.preReviewPreLaunch.includes("pre-launch-report-crash-0"));
  assert.ok(androidRcEvidence.requiredEvidence.preReviewPreLaunch.includes("pre-launch-report-anr-0"));
  assert.ok(androidRcEvidence.requiredEvidence.preReviewPreLaunch.includes("pre-launch-report-policy-warning-0-or-triaged"));
  assert.ok(androidRcEvidence.requiredEvidence.postReleaseReadiness.includes("post-launch-operations-review-gate-manifest"));
  assert.ok(androidRcEvidence.requiredEvidence.postReleaseReadiness.includes("support-incident-response-gate-manifest"));
  assert.ok(androidRcEvidence.requiredEvidence.postReleaseReadiness.includes("first-2h-monitoring-owner-schedule"));
  assert.ok(androidRcEvidence.requiredEvidence.postReleaseReadiness.includes("24h-7d-30d-review-owner-schedule"));
  assert.ok(androidRcEvidence.requiredEvidence.postReleaseReadiness.includes("backend-datapack-realtime-kill-switch-rollback-owner-record"));
  assert.ok(androidRcEvidence.requiredEvidence.postReleaseReadiness.includes("fixed-release-submission-procedure-record"));
  assert.ok(androidRcEvidence.requiredEvidence.postReleaseReadiness.includes("second-update-staged-rollout-halt-rollback-procedure"));
  assert.ok(androidRcEvidence.requiredEvidence.postReleaseReadiness.includes("support-faq-and-incident-notice-copy-review"));
  assert.ok(androidRcEvidence.requiredEvidence.postReleaseReadiness.includes("data-error-triage-dry-run"));
  assert.ok(androidRcEvidence.requiredEvidence.postReleaseReadiness.includes("operator-contact-route-record"));
  assert.ok(androidRcEvidence.requiredEvidence.postReleaseReadiness.includes("emergency-datapack-release-rollback-runbook-match"));
  assert.ok(androidRcEvidence.requiredEvidence.postReleaseReadiness.includes("retention-duplicate-override-recovery-policy"));
  assert.ok(androidRcEvidence.evidencePolicy.localOnlyEvidenceRoot.startsWith(".codex/evidence/"));
  assert.equal(rcEvidenceManifestContract.releaseGate, "rc-evidence-manifest");
  assert.equal(rcEvidenceManifestContract.issue, 1020);
  assert.deepEqual(rcEvidenceManifestContract.parentIssues, [1014, 1020]);
  assert.deepEqual(rcEvidenceManifestContract.linkedEvidenceIssues, [547, 571, 1015, 1016, 1017, 1018, 1019, 1021, 1022]);
  assert.equal(rcEvidenceManifestContract.androidRcEvidenceManifest, androidRcEvidencePath);
  assert.equal(rcEvidenceManifestContract.signedReleaseArtifactGate, gatePath);
  assert.equal(rcEvidenceManifestContract.releaseGovernanceGate, "apps/mobile/release/release-governance-gate.json");
  assert.equal(rcEvidenceManifestContract.generator, "tools/release/generate-rc-evidence-manifest.mjs");
  for (const field of [
    "gitSha",
    "appVersionName",
    "versionCode",
    "aabSha256",
    "dataPackManifestSha256",
    "releaseSequence",
    "routeContractVersion",
    "realtimeContractVersion",
  ]) {
    assert.ok(rcEvidenceManifestContract.requiredRcIdentityFields.includes(field), `${field} must be required`);
  }
  assert.deepEqual(rcEvidenceManifestContract.backendIdentityFieldsAnyOf, ["backendImageDigest", "backendArtifactSha256"]);
  for (const field of ["device", "androidVersion", "testedAt", "evidencePaths", "expiresWhen"]) {
    assert.ok(rcEvidenceManifestContract.requiredEvidenceEntryFields.includes(field), `${field} must be required`);
  }
  assert.deepEqual(
    rcEvidenceManifestContract.requiredEvidenceEntries.map(({ id, sourceIssue }) => ({ id, sourceIssue })),
    [
      { id: "rc_device_qa", sourceIssue: 571 },
      { id: "production_datapack", sourceIssue: 547 },
      { id: "signed_rc_store_submission", sourceIssue: 1015 },
      { id: "play_generated_install", sourceIssue: 1016 },
      { id: "store_privacy_submission", sourceIssue: 1018 },
      { id: "backend_operations", sourceIssue: 1017 },
      { id: "post_launch_operations", sourceIssue: 1019 },
      { id: "android_release_quality", sourceIssue: 1021 },
      { id: "abuse_penetration_rehearsal", sourceIssue: 1022 },
    ],
  );
  assert.equal(rcEvidenceManifestContract.readinessPolicy.openAndroidP0BlocksGo, true);
  assert.equal(rcEvidenceManifestContract.readinessPolicy.identityMismatchBlocksGo, true);
  assert.equal(rcEvidenceManifestContract.evidencePolicy.androidDeviceEvidence, "local_android_emulator_only_for_codex_pr_evidence");

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
  assert.match(workflow, /toolchainPolicy=apps\/mobile\/release\/signed-release-artifact-gate\.json/);
  assert.match(workflow, /android_rc_signing_mode:/);
  assert.match(workflow, /production-upload-key/);
  assert.match(workflow, /android-production-rc/);
  assert.match(workflow, /android-production-rc-release:/);
  assert.match(workflow, /name: Android Production RC Artifact/);
  assert.match(workflow, /if: \$\{\{ github\.event_name == 'workflow_dispatch' && github\.ref == 'refs\/heads\/main' && inputs\.android_rc_signing_mode == 'production-upload-key' \}\}/);
  assert.match(workflow, /environment:\s*\n\s*name: android-production-rc/);
  assert.match(workflow, /EASYSUBWAY_ANDROID_UPLOAD_KEYSTORE_BASE64: \$\{\{ secrets\.EASYSUBWAY_ANDROID_UPLOAD_KEYSTORE_BASE64 \}\}/);
  assert.match(workflow, /EASYSUBWAY_ANDROID_UPLOAD_KEY_SHA256/);
  assert.match(workflow, /EASYSUBWAY_PLAY_APP_SIGNING_KEY_SHA256/);
  assert.match(workflow, /--require-android-rc-production/);
  assert.match(workflow, /base64 --decode > "\$\{EASYSUBWAY_ANDROID_KEYSTORE_PATH\}"/);
  assert.match(workflow, /rm -f "\$\{RUNNER_TEMP\}\/easysubway-ci-release\.jks" "\$\{RUNNER_TEMP\}\/easysubway-upload-key\.jks" "\$\{RUNNER_TEMP\}\/easysubway-release\.env"/);
  assert.match(workflow, /gitSha=\$\{GITHUB_SHA\}/);
  assert.match(workflow, /storeReadyCandidate=true/);
  assert.match(workflow, /signingKeyType=production-upload-key/);
  assert.match(workflow, /uploadKeySha256Fingerprint=\$\{EASYSUBWAY_ANDROID_UPLOAD_KEY_SHA256\}/);
  assert.match(workflow, /appSigningKeySha256Fingerprint=\$\{EASYSUBWAY_PLAY_APP_SIGNING_KEY_SHA256\}/);
  assert.match(workflow, /versionName=\$\{version_name\}/);
  assert.match(workflow, /versionCode=\$\{version_code\}/);
  assert.match(workflow, /packageId=com\.easysubway\.app/);
  assert.match(workflow, /aabSha256=\$\{aab_sha256\}/);
  assert.match(workflow, /dataPackManifestSha256=\$\{data_pack_manifest_sha256\}/);
  assert.match(workflow, /routeContractVersion=route-map-contract-v1/);
  assert.match(workflow, /realtimeContractVersion=seoul-topis-schema-v1/);
  assert.match(workflow, /mappingRetentionDays=90/);
  assert.match(workflow, /versionCodeMonotonicPolicy=must_be_greater_than_latest_play_uploaded_artifact/);
  assert.match(workflow, /failedRcVersionCodeReusePolicy=forbidden_without_1020_waiver/);
  for (const key of gate.artifacts.android.productionRcRequiredMetadata) {
    assert.match(workflow, new RegExp(`${key}=`), `${key} must be emitted in production RC metadata`);
  }
  assert.match(workflow, /store_ready=false/);
  assert.match(workflow, /signing_key_type=temporary-self-signed/);
  assert.match(workflow, /play_submission_evidence=blocked_missing_internal_track_or_prelaunch_report/);
  assert.match(workflow, /cp release\/android-16kb-page-size-gate\.json release-artifacts\/android\/android-16kb-page-size-gate\.json/);
  assert.match(workflow, /cp release\/play-production-access-gate\.json release-artifacts\/android\/play-production-access-gate\.json/);
  assert.match(workflow, /cp release\/play-store-submission-content\.json release-artifacts\/android\/play-store-submission-content\.json/);
  assert.match(workflow, /cp release\/play-generated-apk-device-matrix-gate\.json release-artifacts\/android\/play-generated-apk-device-matrix-gate\.json/);
  assert.match(workflow, /cp release\/post-launch-operations-review-gate\.json release-artifacts\/android\/post-launch-operations-review-gate\.json/);
  assert.match(workflow, /cp release\/support-incident-response-gate\.json release-artifacts\/android\/support-incident-response-gate\.json/);
  assert.match(workflow, /cp release\/abuse-penetration-rehearsal-gate\.json release-artifacts\/android\/abuse-penetration-rehearsal-gate\.json/);
  assert.match(workflow, /cp release\/rc-evidence-manifest-contract\.json release-artifacts\/android\/rc-evidence-manifest-contract\.json/);
  assert.match(workflow, /rc-evidence-manifest:/);
  assert.match(workflow, /name: RC Evidence Manifest/);
  assert.match(workflow, /uses: actions\/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093/);
  assert.match(workflow, /name: easysubway-android-release-\$\{\{ github\.sha \}\}/);
  assert.match(workflow, /name: easysubway-android-production-rc-\$\{\{ github\.sha \}\}/);
  assert.match(workflow, /name: easysubway-backend-release-\$\{\{ github\.sha \}\}/);
  assert.match(workflow, /node tools\/release\/generate-rc-evidence-manifest\.mjs "\$\{generator_args\[@\]\}"/);
  assert.match(workflow, /--output release-artifacts\/rc\/rc-evidence-manifest\.json/);
  assert.match(workflow, /--gate-status productionDatapack=BLOCKED_EXTERNAL/);
  assert.match(workflow, /--backend-image-inspect release-artifacts\/downloaded\/backend\/image-inspect\.json/);
  assert.match(workflow, /--gate-status backendOperations=BLOCKED_EXTERNAL/);
  assert.match(workflow, /--gate-status postLaunchOperations=BLOCKED_EXTERNAL/);
  assert.match(workflow, /--evidence-root "\.codex\/evidence\/release\/rc-evidence-manifest\/\$\{GITHUB_SHA\}\/"/);
  assert.match(workflow, /android_artifact_source="none"/);
  assert.match(workflow, /android_artifact_source="easysubway-android-production-rc-\$\{GITHUB_SHA\}"/);
  assert.match(workflow, /android_artifact_source="easysubway-android-release-\$\{GITHUB_SHA\}"/);
  assert.match(workflow, /android_artifact_source=\$\{android_artifact_source\}/);
  assert.match(workflow, /cp \.\.\/\.\.\/tools\/mobile\/check-android-aab-16kb-page-size\.sh release-artifacts\/android\/check-android-aab-16kb-page-size\.sh/);
  assert.match(workflow, /cp \.\.\/\.\.\/tools\/mobile\/check-elf-load-alignment\.mjs release-artifacts\/android\/check-elf-load-alignment\.mjs/);
  assert.match(workflow, /page_size_16kb_evidence=blocked_until_tools_mobile_check_android_aab_16kb_page_size_passes_and_runtime_PAGE_SIZE_16384_smoke_passes/);
  assert.match(workflow, /play_production_access_evidence=blocked_until_play_production_access_gate_console_summary_is_satisfied/);
  assert.match(workflow, /play_app_content_data_safety_listing_evidence=blocked_until_play_store_submission_content_console_summary_is_satisfied/);
  assert.match(workflow, /play_generated_apk_device_matrix_evidence=blocked_until_play_generated_apk_device_matrix_gate_is_satisfied/);
  assert.match(workflow, /post_launch_operations_review_evidence=blocked_until_post_launch_operations_review_gate_is_satisfied/);
  assert.match(workflow, /support_incident_response_evidence=blocked_until_support_incident_response_gate_is_satisfied/);
  assert.match(workflow, /abuse_penetration_rehearsal_evidence=blocked_until_abuse_penetration_rehearsal_gate_is_satisfied/);
  assert.match(workflow, /rc_evidence_manifest=easysubway-rc-evidence-manifest-\$\{GITHUB_SHA\}/);
  assert.match(workflow, /name: easysubway-rc-evidence-manifest-\$\{\{ github\.sha \}\}/);
  assert.match(workflow, /cp release\/signed-release-artifact-gate\.json release-artifacts\/android\/signed-release-artifact-gate\.json/);
  assert.doesNotMatch(workflow, /signing_key_type=no-codesign/);
  assert.doesNotMatch(workflow, /echo "\$\{EASYSUBWAY_ANDROID_STORE_PASSWORD\}"/);
  assert.doesNotMatch(workflow, /echo "\$\{EASYSUBWAY_ANDROID_KEY_PASSWORD\}"/);
  assert.doesNotMatch(workflow, /echo "\$\{EASYSUBWAY_ANDROID_UPLOAD_KEYSTORE_BASE64\}"/);
  assert.doesNotMatch(workflow, /testflight_evidence=blocked_missing_testflight_or_signed_device_install/);
  assert.doesNotMatch(workflow, /cp release\/signed-release-artifact-gate\.json release-artifacts\/ios\/signed-release-artifact-gate\.json/);

  assert.match(readme, /signed release artifact gate/);
  assert.match(readme, /Android-first 배포 파이프라인은 Android AAB와 backend image만 생성/);
  assert.match(readme, /Android 15 \(API 35\)/);
  assert.match(readme, /Xcode 26/);
  assert.match(readme, /TestFlight/);
  assert.match(readme, /dSYM 90일 보관 workflow/);
  assert.match(readme, /Play internal track/);
  assert.match(readme, /production upload key/);
  assert.match(readme, /android-production-rc/);
  assert.match(readme, /versionCode/);
  assert.match(readme, /Android 16 KB page-size gate/);
  assert.match(readme, /Google Play production access/);
  assert.match(readme, /12명 이상/);
  assert.match(readme, /14일 연속 opt-in/);
  assert.match(readme, /Google Play App Content, Data Safety, 한국어 listing gate/);
  assert.match(readme, /store-privacy-inventory\.json/);
  assert.match(readme, /휠체어 경로 보장/);
  assert.match(readme, /Play-generated APK와 device compatibility matrix gate/);
  assert.match(readme, /로컬 AAB만으로는 Go evidence가 될 수 없고/);
  assert.match(readme, /generatedApks 다운로드 APK를 adb\/shell로 설치한 증거는 artifact identity와 manifest 확인에만 쓰고/);
  assert.match(readme, /Play-installed build smoke는 `installerPackageName=com\.android\.vending`/);
  assert.match(readme, /16 KB page-size/);
  assert.match(readme, /Android 출시 후 2시간\/24시간\/7일\/30일 운영 검토/);
  assert.match(readme, /post-launch-operations-review-gate\.json/);
  assert.match(readme, /로컬 Android emulator/);
  assert.match(readme, /사용자 지원, 데이터 오류, 장애 대응 gate/);
  assert.match(readme, /support-incident-response-gate\.json/);
  assert.match(readme, /emergency datapack release\/rollback/);
  assert.match(readme, /Abuse-case와 penetration rehearsal gate/);
  assert.match(readme, /abuse-penetration-rehearsal-gate\.json/);
  assert.match(readme, /critical\/high finding/);
  assert.match(readme, /RC evidence manifest/);
  assert.match(readme, /generate-rc-evidence-manifest\.mjs/);
  assert.match(readme, /#547\/#571\/#1015\/#1016\/#1017\/#1018\/#1019\/#1021\/#1022 evidence entry/);
  assert.match(readme, /로컬 Android emulator 기준/);
});

test("RC evidence manifest generator는 RC identity와 No-Go blocker를 생성한다", async () => {
  const tempDir = await mkdtemp(path.join(tmpdir(), "easysubway-rc-manifest-"));
  const aabPath = path.join(tempDir, "app-release.aab");
  const backendInspectPath = path.join(tempDir, "image-inspect.json");
  const outputPath = path.join(tempDir, "rc-evidence-manifest.json");
  const appVersion = read("apps/mobile/pubspec.yaml").match(/^version:\s*([^+\s]+)\+([0-9]+)\s*$/m);
  assert.ok(appVersion, "mobile pubspec must contain versionName+versionCode");

  await writeFile(aabPath, "fake-aab");
  await writeFile(
    backendInspectPath,
    JSON.stringify([{ RepoDigests: ["ghcr.io/aquilaxk/easysubway-backend@sha256:abcdef"] }]),
  );

  await execFileAsync(process.execPath, [
    "tools/release/generate-rc-evidence-manifest.mjs",
    "--repo-root",
    ".",
    "--app-root",
    "apps/mobile",
    "--git-sha",
    "0123456789abcdef0123456789abcdef01234567",
    "--aab",
    aabPath,
    "--backend-image-inspect",
    backendInspectPath,
    "--data-pack-manifest",
    "apps/mobile/assets/datapacks/metro_map_pack/manifest.json",
    "--output",
    outputPath,
    "--tested-at",
    "2026-06-26T00:00:00.000Z",
    "--device",
    "local_android_emulator",
    "--android-version",
    "Android 16 API 36",
    "--gate-status",
    "androidRcEvidence=BLOCKED_EXTERNAL",
  ], { cwd: root });

  const manifest = JSON.parse(readFileSync(outputPath, "utf8"));
  assert.equal(manifest.releaseGate, "rc-evidence-manifest");
  assert.equal(manifest.issue, 1020);
  assert.equal(manifest.gitSha, "0123456789abcdef0123456789abcdef01234567");
  assert.equal(manifest.appVersionName, appVersion[1]);
  assert.equal(manifest.versionCode, appVersion[2]);
  assert.match(manifest.aabSha256, /^[a-f0-9]{64}$/);
  assert.equal(manifest.backendImageDigest, "sha256:abcdef");
  assert.equal(manifest.backendArtifactSha256, null);
  assert.match(manifest.dataPackManifestSha256, /^[a-f0-9]{64}$/);
  assert.equal(manifest.routeContractVersion, "route-map-contract-v1");
  assert.equal(manifest.realtimeContractVersion, "seoul-topis-schema-v1");
  assert.equal(manifest.readiness.status, "NO_GO");
  assert.ok(manifest.readiness.blockers.map((blocker) => blocker.id).includes("gate_androidrcevidence_blocked_external"));
  assert.deepEqual(
    manifest.evidenceEntries.map(({ id, sourceIssue }) => ({ id, sourceIssue })),
    [
      { id: "rc_device_qa", sourceIssue: 571 },
      { id: "production_datapack", sourceIssue: 547 },
      { id: "signed_rc_store_submission", sourceIssue: 1015 },
      { id: "play_generated_install", sourceIssue: 1016 },
      { id: "store_privacy_submission", sourceIssue: 1018 },
      { id: "backend_operations", sourceIssue: 1017 },
      { id: "post_launch_operations", sourceIssue: 1019 },
      { id: "android_release_quality", sourceIssue: 1021 },
      { id: "abuse_penetration_rehearsal", sourceIssue: 1022 },
    ],
  );
  assert.ok(manifest.evidenceEntries.every((entry) => entry.device === "local_android_emulator"));
  assert.ok(manifest.evidenceEntries.every((entry) => entry.androidVersion === "Android 16 API 36"));
  assert.ok(manifest.evidenceEntries.every((entry) => entry.testedAt === "2026-06-26T00:00:00.000Z"));
  assert.ok(manifest.evidenceEntries.every((entry) => entry.expiresWhen === "2026-07-10T00:00:00.000Z"));

  const localImageInspectPath = path.join(tempDir, "local-image-inspect.json");
  const localImageManifestPath = path.join(tempDir, "local-image-rc-evidence-manifest.json");
  await writeFile(
    localImageInspectPath,
    JSON.stringify([{ RepoDigests: [], Id: "sha256:2076c88dbc6590b239f6762e9c209d7ae189f2bc53725ca94d42c81c5d8e4521" }]),
  );
  await execFileAsync(process.execPath, [
    "tools/release/generate-rc-evidence-manifest.mjs",
    "--repo-root",
    ".",
    "--app-root",
    "apps/mobile",
    "--git-sha",
    "0123456789abcdef0123456789abcdef01234567",
    "--aab",
    aabPath,
    "--backend-image-inspect",
    localImageInspectPath,
    "--data-pack-manifest",
    "apps/mobile/assets/datapacks/metro_map_pack/manifest.json",
    "--output",
    localImageManifestPath,
    "--tested-at",
    "2026-06-26T00:00:00.000Z",
  ], { cwd: root });
  const localImageManifest = JSON.parse(readFileSync(localImageManifestPath, "utf8"));
  assert.equal(
    localImageManifest.backendImageDigest,
    "sha256:2076c88dbc6590b239f6762e9c209d7ae189f2bc53725ca94d42c81c5d8e4521",
  );
  assert.equal(localImageManifest.backendArtifactSha256, null);
  assert.ok(
    !localImageManifest.readiness.blockers.map((blocker) => blocker.id).includes("missing_backend_identity"),
  );

  const metadataOnlyInspectPath = path.join(tempDir, "metadata-only-image-inspect.json");
  const metadataOnlyManifestPath = path.join(tempDir, "metadata-only-rc-evidence-manifest.json");
  const metadataOnlyInspect = JSON.stringify([{ RepoDigests: [], Size: 367184804 }]);
  const metadataOnlyInspectSha256 = createHash("sha256").update(metadataOnlyInspect).digest("hex");
  await writeFile(metadataOnlyInspectPath, metadataOnlyInspect);
  await execFileAsync(process.execPath, [
    "tools/release/generate-rc-evidence-manifest.mjs",
    "--repo-root",
    ".",
    "--app-root",
    "apps/mobile",
    "--git-sha",
    "0123456789abcdef0123456789abcdef01234567",
    "--aab",
    aabPath,
    "--backend-image-inspect",
    metadataOnlyInspectPath,
    "--data-pack-manifest",
    "apps/mobile/assets/datapacks/metro_map_pack/manifest.json",
    "--output",
    metadataOnlyManifestPath,
    "--tested-at",
    "2026-06-26T00:00:00.000Z",
  ], { cwd: root });
  const metadataOnlyManifest = JSON.parse(readFileSync(metadataOnlyManifestPath, "utf8"));
  assert.equal(metadataOnlyManifest.backendImageDigest, null);
  assert.equal(metadataOnlyManifest.backendArtifactSha256, metadataOnlyInspectSha256);
  assert.ok(
    !metadataOnlyManifest.readiness.blockers.map((blocker) => blocker.id).includes("missing_backend_identity"),
  );

  await assert.rejects(
    execFileAsync(process.execPath, [
      "tools/release/generate-rc-evidence-manifest.mjs",
      "--repo-root",
      ".",
      "--app-root",
      "apps/mobile",
      "--git-sha",
      "0123456789abcdef0123456789abcdef01234567",
      "--aab",
      aabPath,
      "--backend-image-inspect",
      backendInspectPath,
      "--data-pack-manifest",
      "apps/mobile/assets/datapacks/metro_map_pack/manifest.json",
      "--output",
      path.join(tempDir, "mismatch.json"),
      "--expect",
      "gitSha=ffffffffffffffffffffffffffffffffffffffff",
      "--fail-on-blocked",
      "true",
    ], { cwd: root }),
    /mismatch_gitSha/,
  );
});

test("Android 16 KB page-size gate는 AAB alignment와 16384 runtime smoke 계약을 고정한다", () => {
  const gatePath = "apps/mobile/release/android-16kb-page-size-gate.json";
  assert.equal(existsSync(path.join(root, gatePath)), true, "Android 16 KB page-size gate must exist");

  const gate = readJson(gatePath);
  const aabScript = read("tools/mobile/check-android-aab-16kb-page-size.sh");
  const elfScript = read("tools/mobile/check-elf-load-alignment.mjs");
  const runtimeScript = read("tools/mobile/run-android-16kb-page-size-smoke.sh");
  const androidRcEvidence = readJson("apps/mobile/release/android-rc-store-evidence.json");

  assert.equal(gate.schemaVersion, 1);
  assert.equal(gate.applicationId, "easysubway");
  assert.equal(gate.androidApplicationId, "com.easysubway.app");
  assert.equal(gate.releaseGate, "android-16kb-page-size");
  assert.equal(gate.issue, 1015);
  assert.equal(gate.releaseBlockerPolicy, true);
  assert.equal(gate.scope.platform.android, "RELEASE_REQUIRED");
  assert.equal(gate.scope.platform.ios, "DEFERRED_OUT_OF_SCOPE");
  assert.equal(gate.scope.artifact, "android-aab");
  assert.equal(gate.scope.minimumPageSizeBytes, 16384);
  assert.equal(gate.aabInspection.script, "tools/mobile/check-android-aab-16kb-page-size.sh");
  assert.equal(gate.runtimeSmoke.script, "tools/mobile/run-android-16kb-page-size-smoke.sh");
  assert.equal(gate.runtimeSmoke.requiredDevice, "local_android_emulator_with_getconf_PAGE_SIZE_16384");
  assert.ok(gate.aabInspection.requiredEvidence.includes("bundletool-config-dump"));
  assert.ok(gate.aabInspection.requiredTools.includes("node"));
  assert.ok(gate.aabInspection.requiredEvidence.includes("native-library-load-segment-alignment"));
  assert.ok(gate.runtimeSmoke.requiredEvidence.includes("adb-getconf-page-size-16384"));
  assert.ok(gate.runtimeSmoke.requiredEvidence.includes("sqlite-gzip-datapack-smoke"));
  assert.ok(androidRcEvidence.requiredEvidence.pageSize16kb.includes("android-16kb-page-size-gate-manifest"));

  assert.match(aabScript, /"\$BUNDLETOOL" dump config --bundle="\$AAB"/);
  assert.match(aabScript, /PAGE_ALIGNMENT_16K/);
  assert.match(aabScript, /missing_PAGE_ALIGNMENT_16K_native_library_alignment/);
  assert.match(aabScript, /zipinfo -1 "\$AAB"/);
  assert.match(aabScript, /MIN_ALIGN=16384/);
  assert.match(aabScript, /node "\$SCRIPT_DIR\/check-elf-load-alignment\.mjs" --min-align "\$MIN_ALIGN"/);
  assert.match(aabScript, /native-alignment-summary\.tsv/);
  assert.match(elfScript, /readBigUInt64LE/);
  assert.match(elfScript, /u32\(base\) === 1/);
  assert.match(elfScript, /align < minAlign/);

  assert.match(runtimeScript, /EXPECTED_PAGE_SIZE=16384/);
  assert.match(runtimeScript, /ro\.kernel\.qemu/);
  assert.match(runtimeScript, /getconf PAGE_SIZE/);
  assert.match(runtimeScript, /"\$page_size" != "\$EXPECTED_PAGE_SIZE"/);
  assert.match(runtimeScript, /pm path "\$PACKAGE"/);
  assert.match(runtimeScript, /android\.intent\.action\.MAIN/);
  assert.match(runtimeScript, /android\.intent\.category\.LAUNCHER/);
  assert.match(runtimeScript, /am start -n "\$launch_activity"/);
  assert.match(runtimeScript, /current-focus\.txt/);
  assert.match(runtimeScript, /screencap -p/);
  assert.match(runtimeScript, /uiautomator dump/);
  assert.match(runtimeScript, /FATAL EXCEPTION\| \[EF\] AndroidRuntime:\|Fatal signal\|Abort message\|tombstoned/);
  assert.match(runtimeScript, /crash-excerpt\.txt/);
  assert.match(runtimeScript, /foreground_package_verified=true/);
  assert.match(runtimeScript, /logcat_no_crash=true/);
  assert.match(runtimeScript, /logcat\.txt/);
  assert.match(runtimeScript, /summary\.txt/);
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
    "DENOMINATOR_LOCKED",
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
  assert.deepEqual(gate.requiredRcEvidenceBackendIdentityFieldsAnyOf, ["backendImageDigest", "backendArtifactSha256"]);

  assert.equal(gate.releaseReadiness.openAndroidP0BlocksGo, true);
  assert.equal(gate.releaseReadiness.iosBlocksAndroidRelease, false);
  assert.ok(gate.releaseReadiness.p0EscalationRules.includes("measured_performance_budget_failure"));
  assert.ok(gate.releaseReadiness.p0EscalationRules.includes("play_prelaunch_crash"));
  assert.equal(gate.latestOperationsEvidenceStatus.issue, 1019);
  assert.equal(gate.latestOperationsEvidenceStatus.supportMailboxRouting, "RESOLVED_BY_QA_MANUAL_EVIDENCE");
  assert.equal(gate.latestOperationsEvidenceStatus.alertRouteDryRun, "PASS");
  assert.deepEqual(gate.latestOperationsEvidenceStatus.remainingBlockers, [
    "play-review-status-summary",
    "crash-anr-vitals-summary",
    "post-launch-review-window-evidence-after-public-release",
    "support-incident-response-dry-run-evidence",
  ]);
  assert.equal(gate.latestGoNoGoStatus.qaEvidenceDateKst, "2026-06-29");
  assert.equal(gate.latestGoNoGoStatus.reviewedMainMergeSha, "a1a6da80b3433c26ae2f5a45b02de86c8f37ce82");
  assert.equal(gate.latestGoNoGoStatus.currentDecision, "NO_GO");
  assert.equal(gate.latestGoNoGoStatus.decisionOwner, "release-owner");
  assert.deepEqual(gate.latestGoNoGoStatus.blockingOpenIssues, [571, 1016, 1018, 1019, 1021, 1022]);
  assert.deepEqual(gate.latestGoNoGoStatus.recentlyResolvedEvidence, [
    "production-datapack-release-publish-success",
    "store-distribution-evidence-success",
    "play-internal-upload-version-code-10001",
    "android-publisher-api-access-ready",
    "server-minimized-android-release-scope-fixed",
    "android-quality-local-emulator-real-device-smoke-summary",
    "abuse-rehearsal-local-and-store-preflight-summary",
    "operations-alert-and-mailbox-routing-summary",
  ]);
  assert.deepEqual(gate.latestGoNoGoStatus.remainingP0Blockers, [
    "play-installed-build-provenance",
    "play-pre-launch-crash-anr-policy-summary",
    "play-console-data-safety-listing-screenshot-final-preview",
    "android-vitals-crash-anr-summary",
    "support-incident-response-dry-run-evidence",
    "post-launch-review-window-evidence-after-public-release",
    "play-installed-android-quality-performance-recovery-evidence",
    "production-like-abuse-rehearsal-evidence",
    "play-installed-server-minimized-final-acceptance-evidence",
  ]);
  assert.deepEqual(gate.latestGoNoGoStatus.remainingApprovalPrerequisites, [
    "release-owner-final-go-approval",
  ]);
  assert.equal(gate.latestGoNoGoStatus.externalEffectGate.googlePlayProductionSubmitAllowed, false);
  assert.equal(gate.latestGoNoGoStatus.externalEffectGate.publicReleaseAllowed, false);
  assert.equal(
    gate.latestGoNoGoStatus.externalEffectGate.reasonKo,
    "open Android P0 blocker가 남아 있고 Play-installed, Play Console, Android vitals, production-like rehearsal 증거가 아직 동결되지 않았다.",
  );
  assert.equal(
    gate.latestGoNoGoStatus.notClosingReasonKo,
    "#1020은 latest evidence status를 동결했지만, open release blocker와 final GO approval이 남아 있어 NO-GO 상태로 open 유지한다.",
  );
  assert.ok(gate.gates.some((item) => item.issue === 1021 && item.id === "G7_ANDROID_QUALITY"));
  assert.ok(gate.gates.some((item) => item.issue === 1018 && item.id === "G9_GOOGLE_PLAY"));
  assert.deepEqual(
    gate.gates.find((item) => item.issue === 1015),
    {
      id: "G3_ANDROID_16KB_PAGE_SIZE",
      issue: 1015,
      priority: "P0",
      status: "IN_PROGRESS",
      owner: "android-build",
      nextAction: "16 KB page-size AAB alignment와 Android 15/16 runtime smoke evidence 수집",
      evidenceReference: "apps/mobile/release/android-16kb-page-size-gate.json",
    },
  );
  assert.equal(
    gate.gates.find((item) => item.id === "G6_SECURITY_PRIVACY")?.status,
    readJson("apps/mobile/release/abuse-penetration-rehearsal-gate.json").status,
  );
  assert.deepEqual(
    gate.childIssueLinks,
    [547, 571, 1014, 1015, 1016, 1017, 1018, 1019, 1020, 1021, 1022],
  );
  for (const item of gate.gates.filter((gateItem) => gateItem.priority.startsWith("P0"))) {
    assert.ok(item.owner, `${item.id} must define owner`);
    assert.ok(item.nextAction, `${item.id} must define next action`);
    assert.ok(item.evidenceReference, `${item.id} must define evidence reference`);
  }
  assert.deepEqual(gate.waiverSchema.requiredFields, [
    "owner",
    "untilDate",
    "reason",
    "risk",
    "mitigation",
    "followUpIssue",
  ]);
  assert.ok(gate.waiverSchema.nonWaivableP0Blockers.includes("play_prelaunch_crash"));
  assert.ok(gate.requiredChecks.includes("CI / Repository CI"));
  assert.ok(gate.requiredChecks.includes("CI / Release Gate Consistency"));
  assert.ok(gate.releaseImpactPaths.includes("apps/mobile/release/**"));
  const allowedStatuses = new Set(gate.gateStatusEnum);
  for (const releaseFile of execFileSync("git", ["ls-files", "apps/mobile/release/*.json"], {
    cwd: root,
    encoding: "utf8",
  }).trim().split("\n").filter(Boolean)) {
    for (const status of collectStatusValues(readJson(releaseFile))) {
      assert.ok(allowedStatuses.has(status), `${releaseFile} uses unsupported status ${status}`);
    }
  }
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
  assert.deepEqual(privacyInventory.googlePlayDataSafetyRequiredFields, [
    "collected",
    "collectionType",
    "optional",
    "required",
    "purpose",
    "linkedToUser",
    "encryptedInTransit",
    "deletionSupported",
  ]);
  assert.equal(privacyInventory.crashAnrProviderDecision.separateCrashProvider, false);
  assert.ok(privacyInventory.crashAnrProviderDecision.sourceOfTruth.includes("Android vitals"));
  assert.ok(privacyInventory.crashAnrProviderDecision.sourceOfTruth.includes("Google Play pre-launch report"));
  assert.ok(privacyInventory.crashAnrProviderDecision.requiredEvidence.includes("no-crash-sdk-dependency-scan"));
  assert.ok(privacyInventory.crashAnrProviderDecision.requiredEvidence.includes("android-vitals-or-play-pre-launch-report-export"));

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
  assert.match(readme, /https:\/\/easysubway-api\.aquilaxk\.site\/easysubway\/privacy/);
  assert.match(readme, /EasySubway does not sell personal or sensitive user data\./);
  assert.match(readme, /support@aquilaxk\.site/);
  assert.match(readme, /security@aquilaxk\.site/);
  assert.match(readme, /privacy@aquilaxk\.site/);
  assert.doesNotMatch(readme, /easysubway\.local|@easysubway\.local/);

  const dir = await mkdtemp(path.join(tmpdir(), "easysubway-store-privacy-env-"));
  const validEnv = path.join(dir, "valid.env");
  await writeFile(validEnv, [
    "EASYSUBWAY_PRIVACY_POLICY_URL=https://easysubway-api.aquilaxk.site/easysubway/privacy",
    "EASYSUBWAY_SUPPORT_EMAIL=support@aquilaxk.site",
    "EASYSUBWAY_SECURITY_EMAIL=security@aquilaxk.site",
    "EASYSUBWAY_DATA_DELETION_EMAIL=privacy@aquilaxk.site",
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
  assert.match(githubEnvOutput, /^EASYSUBWAY_PRIVACY_POLICY_URL=https:\/\/easysubway-api\.aquilaxk\.site\/easysubway\/privacy$/m);
  assert.match(githubEnvOutput, /^EASYSUBWAY_SUPPORT_EMAIL=support@aquilaxk\.site$/m);
  assert.match(githubEnvOutput, /^EASYSUBWAY_SECURITY_EMAIL=security@aquilaxk\.site$/m);
  assert.match(githubEnvOutput, /^EASYSUBWAY_DATA_DELETION_EMAIL=privacy@aquilaxk\.site$/m);

  const rcEnv = path.join(dir, "android-rc.env");
  await writeFile(rcEnv, [
    "EASYSUBWAY_PRIVACY_POLICY_URL=https://easysubway-api.aquilaxk.site/easysubway/privacy",
    "EASYSUBWAY_SUPPORT_EMAIL=support@aquilaxk.site",
    "EASYSUBWAY_SECURITY_EMAIL=security@aquilaxk.site",
    "EASYSUBWAY_DATA_DELETION_EMAIL=privacy@aquilaxk.site",
    "EASYSUBWAY_DATA_PACK_BASE_URL=https://datapack.aquilaxk.site/datapacks/",
    `EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_N=${validDataPackPublicKeyModulus}`,
    "EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_E=AQAB",
    "EASYSUBWAY_DATAPACK_SIGNING_KEY_ID=production-v1",
    "EASYSUBWAY_DATAPACK_CHANNEL=production",
    `EASYSUBWAY_PLAY_APP_SIGNING_KEY_SHA256=${validPlayAppSigningFingerprint}`,
    "",
  ].join("\n"));
  const rcGithubEnv = path.join(dir, "android-rc-github.env");
  await execFileAsync(
    process.execPath,
    [
      "tools/ci/validate-store-privacy-env.mjs",
      "--env-file",
      rcEnv,
      "--github-env",
      rcGithubEnv,
      "--require-android-rc-production",
    ],
    {
      cwd: root,
    },
  );
  const rcGithubEnvOutput = readFileSync(rcGithubEnv, "utf8");
  assert.match(rcGithubEnvOutput, /^EASYSUBWAY_DATA_PACK_BASE_URL=https:\/\/datapack\.aquilaxk\.site\/datapacks\/$/m);
  assert.match(rcGithubEnvOutput, /^EASYSUBWAY_DATAPACK_SIGNING_KEY_ID=production-v1$/m);
  assert.match(rcGithubEnvOutput, /^EASYSUBWAY_DATAPACK_CHANNEL=production$/m);
  assert.match(
    rcGithubEnvOutput,
    new RegExp(`^EASYSUBWAY_PLAY_APP_SIGNING_KEY_SHA256=${escapeRegExp(validPlayAppSigningFingerprint)}$`, "m"),
  );

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

  const invalidRcEnv = path.join(dir, "invalid-android-rc.env");
  await writeFile(invalidRcEnv, [
    "EASYSUBWAY_PRIVACY_POLICY_URL=https://easysubway-api.aquilaxk.site/easysubway/privacy",
    "EASYSUBWAY_SUPPORT_EMAIL=support@aquilaxk.site",
    "EASYSUBWAY_SECURITY_EMAIL=security@aquilaxk.site",
    "EASYSUBWAY_DATA_DELETION_EMAIL=privacy@aquilaxk.site",
    "EASYSUBWAY_DATA_PACK_BASE_URL=http://localhost/datapacks/",
    `EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_N=${validDataPackPublicKeyModulus}`,
    "EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_E=AQAB",
    "EASYSUBWAY_DATAPACK_SIGNING_KEY_ID=production-v1",
    "EASYSUBWAY_DATAPACK_CHANNEL=staging",
    `EASYSUBWAY_PLAY_APP_SIGNING_KEY_SHA256=${validPlayAppSigningFingerprint}`,
    "",
  ].join("\n"));
  await assert.rejects(
    execFileAsync(process.execPath, [
      "tools/ci/validate-store-privacy-env.mjs",
      "--env-file",
      invalidRcEnv,
      "--require-android-rc-production",
    ], {
      cwd: root,
    }),
    /EASYSUBWAY_DATA_PACK_BASE_URL must be a valid HTTPS URL|EASYSUBWAY_DATAPACK_CHANNEL must be production/,
  );

  const invalidRcKeyEnv = path.join(dir, "invalid-android-rc-key.env");
  await writeFile(invalidRcKeyEnv, [
    "EASYSUBWAY_PRIVACY_POLICY_URL=https://easysubway-api.aquilaxk.site/easysubway/privacy",
    "EASYSUBWAY_SUPPORT_EMAIL=support@aquilaxk.site",
    "EASYSUBWAY_SECURITY_EMAIL=security@aquilaxk.site",
    "EASYSUBWAY_DATA_DELETION_EMAIL=privacy@aquilaxk.site",
    "EASYSUBWAY_DATA_PACK_BASE_URL=https://datapack.aquilaxk.site/datapacks/",
    "EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_N=public-key-modulus",
    "EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_E=AQAB",
    "EASYSUBWAY_DATAPACK_SIGNING_KEY_ID=production-v1",
    "EASYSUBWAY_DATAPACK_CHANNEL=production",
    "EASYSUBWAY_PLAY_APP_SIGNING_KEY_SHA256=AA:BB:CC",
    "",
  ].join("\n"));
  await assert.rejects(
    execFileAsync(process.execPath, [
      "tools/ci/validate-store-privacy-env.mjs",
      "--env-file",
      invalidRcKeyEnv,
      "--require-android-rc-production",
    ], {
      cwd: root,
    }),
    /EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_N must be a base64url RSA modulus of at least 2048 bits/,
  );

  const invalidRcFingerprintEnv = path.join(dir, "invalid-android-rc-fingerprint.env");
  await writeFile(invalidRcFingerprintEnv, [
    "EASYSUBWAY_PRIVACY_POLICY_URL=https://easysubway-api.aquilaxk.site/easysubway/privacy",
    "EASYSUBWAY_SUPPORT_EMAIL=support@aquilaxk.site",
    "EASYSUBWAY_SECURITY_EMAIL=security@aquilaxk.site",
    "EASYSUBWAY_DATA_DELETION_EMAIL=privacy@aquilaxk.site",
    "EASYSUBWAY_DATA_PACK_BASE_URL=https://datapack.aquilaxk.site/datapacks/",
    `EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_N=${validDataPackPublicKeyModulus}`,
    "EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_E=AQAB",
    "EASYSUBWAY_DATAPACK_SIGNING_KEY_ID=production-v1",
    "EASYSUBWAY_DATAPACK_CHANNEL=production",
    "EASYSUBWAY_PLAY_APP_SIGNING_KEY_SHA256=AA:BB:CC",
    "",
  ].join("\n"));
  await assert.rejects(
    execFileAsync(process.execPath, [
      "tools/ci/validate-store-privacy-env.mjs",
      "--env-file",
      invalidRcFingerprintEnv,
      "--require-android-rc-production",
    ], {
      cwd: root,
    }),
    /EASYSUBWAY_PLAY_APP_SIGNING_KEY_SHA256 must be a full SHA-256 fingerprint/,
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
  const operationsEvidencePath = "apps/mobile/release/operations-release-evidence.json";
  const operationsEvidence = readJson(operationsEvidencePath);
  const backupRestoreGate = readJson("apps/mobile/release/backup-restore-rehearsal-gate.json");
  const readme = read("README.md");
  const datapackWorkflow = read(".github/workflows/datapack-release.yml");
  const releaseArtifactsWorkflow = read(".github/workflows/release-artifacts.yml");
  const applicationProd = read("backend/src/main/resources/application-prod.yml");
  const securityConfig = read("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java");

  assert.equal(gate.schemaVersion, 1);
  assert.equal(gate.applicationId, "easysubway");
  assert.equal(gate.releaseGate, "operations-observability");
  assert.equal(gate.releaseBlockerPolicy, true);
  assert.equal(gate.releaseEvidenceManifest, operationsEvidencePath);
  assert.equal(gate.signalEvidencePolicy.allowedResolutionKinds.includes("dashboard-url"), true);
  assert.equal(gate.signalEvidencePolicy.allowedResolutionKinds.includes("alert-route"), true);
  assert.equal(gate.signalEvidencePolicy.allowedResolutionKinds.includes("runbook"), true);
  assert.equal(gate.signalEvidencePolicy.allowedResolutionKinds.includes("external-blocker-record"), true);
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
  assert.match(readme, /operations-release-evidence\.json/);
  assert.match(readme, /backend control-plane/);
  assert.match(readme, /public API surface/);
  assert.match(readme, /single-instance/);
  assert.match(readme, /backend_health_readiness_storage_datapack_report/);
  assert.match(readme, /realtime_provider_success_stale_timeout_latency_eta_error/);
  assert.match(readme, /receipt token|upload URL|photo metadata/i);
  assert.equal(operationsEvidence.schemaVersion, 1);
  assert.equal(operationsEvidence.applicationId, "easysubway");
  assert.equal(operationsEvidence.releaseGate, "operations-release-evidence");
  assert.equal(operationsEvidence.releaseBlockerPolicy, true);
  assert.match(operationsEvidence.evidenceRoot, /^\.codex\/evidence\/operations-release\/<rc-or-run>$/);
  assert.ok(operationsEvidence.deploymentWorkflow.requiredEvidence.includes("cd-workflow-run-url"));
  assert.ok(operationsEvidence.deploymentWorkflow.requiredEvidence.includes("backend-release-artifact-sha"));
  assert.ok(operationsEvidence.deploymentWorkflow.requiredEvidence.includes("readiness-check-result"));
  assert.ok(operationsEvidence.deploymentWorkflow.requiredEvidence.includes("rollback-drill-result"));
  assert.equal(operationsEvidence.migrationPolicy.strategy, "expand-contract-or-backup-before-migration");
  assert.equal(operationsEvidence.migrationPolicy.blockedIfMissingBackupBeforeMigration, true);
  assert.ok(operationsEvidence.restoreRehearsal.requiredChecks.includes("postgresql-restore-rehearsal"));
  assert.ok(operationsEvidence.restoreRehearsal.requiredChecks.includes("facility-report-photo-restore-check"));
  assert.equal(operationsEvidence.backendControlPlane.issue, 1017);
  assert.equal(
    operationsEvidence.backendControlPlane.latestQaEvidenceStatus.qaEvidenceDateKst,
    "2026-06-28",
  );
  assert.equal(
    operationsEvidence.backendControlPlane.latestQaEvidenceStatus.githubEnvironmentProtection
      .productionRequiredReviewer,
    "PASS_REQUIRED_REVIEWER_CONFIGURED",
  );
  assert.equal(
    operationsEvidence.backendControlPlane.latestQaEvidenceStatus.githubEnvironmentProtection
      .productionEnvironmentSecret,
    "PASS_ENV_SCOPED_EASYSUBWAY_ENV_PRESENT",
  );
  assert.equal(
    operationsEvidence.backendControlPlane.latestQaEvidenceStatus.githubEnvironmentProtection
      .repositoryWideProductionSecretsOnly,
    "RESOLVED_BY_ENV_SCOPED_SECRET",
  );
  assert.equal(
    operationsEvidence.backendControlPlane.latestQaEvidenceStatus.prodLikeLocalValidation
      .deploymentEnvValidation,
    "PASS_VALIDATE_DEPLOYMENT_ENV",
  );
  assert.equal(
    operationsEvidence.backendControlPlane.latestQaEvidenceStatus.prodLikeLocalValidation
      .secretValueCapturedInEvidence,
    false,
  );
  assert.deepEqual(
    operationsEvidence.backendControlPlane.latestQaEvidenceStatus.resolvedEvidence,
    [
      "github-production-environment-required-reviewer-summary",
      "production-secret-scope-review",
      "prod-like-env-validation-output",
      "backend-gradle-check-output",
    ],
  );
  assert.deepEqual(
    operationsEvidence.backendControlPlane.latestQaEvidenceStatus.remainingBlockers,
    [
      "production-or-prod-like-deploy-readiness-summary",
      "backend-release-artifact-sha",
      "deployment-target-sha",
      "backend-rollback-drill-result",
      "migration-diff-summary",
      "postgresql-restore-rehearsal-result",
      "facility-report-photo-object-restore-result",
      "datapack-source-inventory-validation",
      "datapack-release-manifest-restore",
      "backend-public-api-surface-inventory",
      "default-deny-public-chain-test-output",
      "security-matcher-contract-test-output",
      "admin-auth-transition-decision-record",
      "admin-basic-auth-prod-disabled-test-output",
      "admin-operator-lockout-test-output",
      "break-glass-rotation-drill-record",
      "break-glass-use-immediate-rotation-record",
      "admin-credential-rotation-cadence-record",
      "operator-tenant-scope-decision-record",
      "operator-global-audit-sample",
      "trusted-proxy-negative-test-output",
      "multi-instance-rate-limit-test-output-or-single-instance-exception",
      "abuse-store-mode-release-blocker-record",
      "staging-prod-environment-separation-summary",
      "admin-operator-page-smoke-output",
      "admin-page-accessibility-smoke-output",
      "admin-role-matrix-test-output",
      "admin-mutating-action-audit-sample",
      "privacy-read-audit-sample",
      "report-photo-read-audit-sample",
      "break-glass-use-audit-sample",
    ],
  );
  assert.match(operationsEvidence.backendControlPlane.latestQaEvidenceStatus.notClosingReasonKo, /#1017/);
  assert.ok(
    operationsEvidence.backendControlPlane.latestQaEvidenceStatus.redactionPolicy.forbiddenInGitHubEvidence.includes(
      "raw environment secret",
    ),
  );
  assert.equal(operationsEvidence.backendControlPlane.publicApiSurface.inventoryRequired, true);
  assert.equal(operationsEvidence.backendControlPlane.publicApiSurface.defaultDenyRequired, true);
  assert.equal(
    operationsEvidence.backendControlPlane.publicApiSurface.newApiOrAdminEndpointWithoutMatcherBlocksRelease,
    true,
  );
  assert.equal(operationsEvidence.backendControlPlane.publicApiSurface.securityMatcherComparisonRequired, true);
  assert.deepEqual(
    operationsEvidence.backendControlPlane.publicApiSurface.allowedPublicEndpoints,
    [
      "/api/health",
      "/actuator/health",
      "/actuator/health/liveness",
      "/actuator/health/readiness",
      "/actuator/prometheus",
      "/api/v1/report-uploads",
      "/api/v1/report-uploads/{uploadId}",
      "/api/v1/reports",
      "/api/v1/reports/{reportId}",
      "/api/v1/reports/{reportId}/confirm",
      "/api/v1/realtime/arrivals",
      "/api/v1/realtime/train-positions",
    ],
  );
  assert.deepEqual(
    operationsEvidence.backendControlPlane.publicApiSurface.allowedPublicSecurityMatchers,
    [
      "/api/v1/report-uploads",
      "/api/v1/report-uploads/*",
      "/api/v1/reports",
      "/api/v1/reports/*",
      "/api/v1/reports/*/confirm",
      "/api/health",
      "/actuator/health",
      "/actuator/health/liveness",
      "/actuator/health/readiness",
      "/actuator/prometheus",
      "/api/v1/realtime/**",
    ],
  );
  const publicApiMatcherScope = securityConfig.match(
    /reportSecurityFilterChain[\s\S]*?publicSecurityFilterChain[\s\S]*?\.anyRequest\(\)\.denyAll\(\)/,
  );
  assert.ok(publicApiMatcherScope, "public API security matcher scope must be readable");
  const publicApiMatchers = Array.from(publicApiMatcherScope[0].matchAll(/"([^"]+)"/g), (match) => match[1]).filter(
    (matcher) => matcher.startsWith("/api/") || matcher.startsWith("/actuator/"),
  );
  assert.deepEqual(
    publicApiMatchers,
    operationsEvidence.backendControlPlane.publicApiSurface.allowedPublicSecurityMatchers,
  );
  assert.ok(
    operationsEvidence.backendControlPlane.publicApiSurface.requiredEvidence.includes(
      "security-matcher-contract-test-output",
    ),
  );
  assert.equal(operationsEvidence.backendControlPlane.adminAuthTransition.basicAuthDefaultInProd, "disabled");
  assert.equal(operationsEvidence.backendControlPlane.adminAuthTransition.oidcMfaSsoDeferredExceptionRequired, true);
  assert.deepEqual(
    operationsEvidence.backendControlPlane.adminAuthTransition.temporaryExceptionRequiredFields,
    ["owner", "untilDate", "risk", "mitigation", "followUpIssue"],
  );
  assert.ok(
    operationsEvidence.backendControlPlane.adminAuthTransition.requiredEvidence.includes(
      "break-glass-rotation-drill-record",
    ),
  );
  assert.ok(
    operationsEvidence.backendControlPlane.adminAuthTransition.requiredEvidence.includes(
      "break-glass-use-immediate-rotation-record",
    ),
  );
  assert.ok(
    operationsEvidence.backendControlPlane.adminAuthTransition.requiredEvidence.includes(
      "admin-credential-rotation-cadence-record",
    ),
  );
  assert.equal(operationsEvidence.backendControlPlane.operatorTenantScope.temporaryScope, "operator-global");
  assert.equal(operationsEvidence.backendControlPlane.operatorTenantScope.releaseExceptionRequired, true);
  assert.deepEqual(
    operationsEvidence.backendControlPlane.operatorTenantScope.requiredDecisionFields,
    ["owner", "untilDate", "risk", "mitigation", "followUpIssue"],
  );
  assert.ok(
    operationsEvidence.backendControlPlane.operatorTenantScope.requiredEvidence.includes(
      "operator-tenant-scope-decision-record",
    ),
  );
  assert.ok(
    operationsEvidence.backendControlPlane.operatorTenantScope.requiredEvidence.includes("operator-global-audit-sample"),
  );
  assert.ok(
    operationsEvidence.backendControlPlane.operatorTenantScope.requiredEvidence.includes(
      "trusted-proxy-negative-test-output",
    ),
  );
  assert.match(operationsEvidence.backendControlPlane.operatorTenantScope.blockedWhenKo, /operator-global/);
  assert.equal(operationsEvidence.backendControlPlane.abuseControlReleaseException.distributedStorePreferred, true);
  assert.ok(
    operationsEvidence.backendControlPlane.abuseControlReleaseException.singleInstanceExceptionRequiredFields.includes(
      "backendReplicaCountOneEvidence",
    ),
  );
  assert.ok(
    operationsEvidence.backendControlPlane.abuseControlReleaseException.singleInstanceExceptionRequiredFields.includes(
      "distributedLimiterFollowUpIssue",
    ),
  );
  assert.ok(
    operationsEvidence.backendControlPlane.abuseControlReleaseException.requiredEvidence.includes(
      "trusted-proxy-negative-test-output",
    ),
  );
  assert.equal(
    operationsEvidence.backendControlPlane.environmentProtection.productionRequiredReviewerRequired,
    true,
  );
  assert.equal(
    operationsEvidence.backendControlPlane.environmentProtection.repositoryWideProductionSecretsOnlyBlocksRelease,
    true,
  );
  assert.ok(
    operationsEvidence.backendControlPlane.environmentProtection.requiredEvidence.includes(
      "github-production-environment-required-reviewer-summary",
    ),
  );
  assert.deepEqual(operationsEvidence.backendControlPlane.adminPageSmoke.requiredPages, [
    "dashboard",
    "stations",
    "facilities",
    "layout-editor",
    "reports",
    "quality",
    "field-verifications",
    "collections",
    "batches",
    "codes",
    "incidents",
    "route-searches",
    "route-feedback",
    "push",
    "usage",
    "system",
    "audits",
    "privacy-audits",
  ]);
  assert.ok(operationsEvidence.backendControlPlane.adminPageSmoke.requiredChecks.includes("login-required"));
  assert.ok(operationsEvidence.backendControlPlane.adminPageSmoke.requiredChecks.includes("role-denied"));
  assert.ok(operationsEvidence.backendControlPlane.adminPageSmoke.requiredChecks.includes("keyboard-navigation"));
  assert.ok(operationsEvidence.backendControlPlane.adminPageSmoke.requiredChecks.includes("skip-link"));
  assert.ok(operationsEvidence.backendControlPlane.adminPageSmoke.requiredChecks.includes("focus-visible"));
  assert.ok(operationsEvidence.backendControlPlane.adminPageSmoke.requiredChecks.includes("csrf-token"));
  assert.ok(operationsEvidence.backendControlPlane.adminPageSmoke.requiredChecks.includes("error-flash"));
  assert.ok(operationsEvidence.backendControlPlane.adminPageSmoke.requiredChecks.includes("environment-badge"));
  assert.ok(
    operationsEvidence.backendControlPlane.adminPageSmoke.requiredChecks.includes("revision-master-data-version"),
  );
  assert.ok(
    operationsEvidence.backendControlPlane.adminPageSmoke.requiredEvidence.includes(
      "admin-operator-page-smoke-output",
    ),
  );
  assert.ok(
    operationsEvidence.backendControlPlane.adminPageSmoke.requiredEvidence.includes(
      "admin-page-accessibility-smoke-output",
    ),
  );
  assert.ok(
    operationsEvidence.backendControlPlane.adminPageSmoke.requiredEvidence.includes(
      "admin-role-matrix-test-output",
    ),
  );
  assert.ok(operationsEvidence.backendControlPlane.auditRedaction.requiredEvidence.includes("privacy-read-audit-sample"));
  assert.ok(
    operationsEvidence.backendControlPlane.auditRedaction.requiredEvidence.includes("break-glass-use-audit-sample"),
  );
  assert.ok(operationsEvidence.backendControlPlane.auditRedaction.forbiddenInEvidence.includes("signed URL"));
  assert.ok(operationsEvidence.backendControlPlane.auditRedaction.forbiddenInEvidence.includes("raw request body"));
  assert.ok(operationsEvidence.observability.requiredResolutionKinds.includes("dashboard-url"));
  assert.ok(operationsEvidence.observability.requiredResolutionKinds.includes("alert-route"));
  assert.ok(operationsEvidence.observability.requiredResolutionKinds.includes("runbook"));
  assert.ok(operationsEvidence.observability.allowedFallbackKinds.includes("external-blocker-record"));
  assert.equal(backupRestoreGate.rcEvidenceManifest, operationsEvidencePath);

  assert.match(applicationProd, /management:[\s\S]*health:[\s\S]*readiness:[\s\S]*productionReadiness/);
  assert.match(datapackWorkflow, /Data Pack Release \/ Write observability metadata/);
  assert.match(datapackWorkflow, /datapack-observability\.txt/);
  assert.match(datapackWorkflow, /pack_version=/);
  assert.match(datapackWorkflow, /manifest\.activePack/);
  assert.match(datapackWorkflow, /\$\{activePack\.id\}@\$\{activePack\.version\}/);
  assert.match(datapackWorkflow, /source_updated_at=/);
  assert.match(datapackWorkflow, /publish_result=/);
  assert.match(datapackWorkflow, /remote_publish_ready=/);
  assert.match(datapackWorkflow, /EASYSUBWAY_DATAPACK_REMOTE_PUBLISH_RESULT=success/);
  assert.match(datapackWorkflow, /EASYSUBWAY_DATAPACK_REMOTE_PUBLISH_RESULT=blocked-strict-coverage/);
  assert.match(datapackWorkflow, /remotePublishEnabled !== "false" && remotePublishReady !== "true"/);
  assert.match(datapackWorkflow, /publishResult = remotePublishResult \|\| "failed"/);
  assert.match(datapackWorkflow, /remote_publish_enabled=\$\{remotePublishEnabled \|\| "unknown"\}/);
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
  assert.equal(gate.releaseBlockerScope.androidGooglePlayV1Required, true);
  assert.equal(gate.releaseBlockerScope.iosDeferredOutOfScope, true);
  assert.equal(gate.releaseBlockerScope.iosEvidenceRetainedForHistory, true);
  assert.match(gate.releaseBlockerScope.completionRuleKo, /Android Google Play v1 release evidence만/);
  assert.doesNotMatch(
    JSON.stringify(gate),
    /com\.easysubway\.mobile/,
    "server minimized QA gate must not reference the retired Android package",
  );
  assert.equal(gate.platformCompletionRule.androidRequired, true);
  assert.equal(gate.platformCompletionRule.iosRequired, false);
  assert.equal(gate.platformCompletionRule.singlePlatformEvidenceIsInsufficient, false);
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
  const prepareIndex = workflow.indexOf("Data Pack Release / Prepare release fixture");
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
  assert.match(workflow, /EASYSUBWAY_DATAPACK_IMPORTED_FIXTURE=\$\{\{ runner\.temp \}\}\/easysubway-production-source-fixture\.json/);
  assert.match(workflow, /EASYSUBWAY_DATAPACK_PRODUCTION_REVIEWED_FIXTURE=\$\{\{ runner\.temp \}\}\/easysubway-reviewed-production-source-fixture\.json/);
  assert.match(workflow, /EASYSUBWAY_DATAPACK_PRODUCTION_GATE_OUTPUT=\$\{\{ runner\.temp \}\}\/easysubway-production-gate/);
  assert.match(workflow, /EASYSUBWAY_DATAPACK_PRODUCTION_GATE_REPORT=\$\{\{ runner\.temp \}\}\/easysubway-production-gate-validation\.log/);
  assert.match(workflow, /EASYSUBWAY_ROUTE_MAP_AUDIT_REPORT=\$\{\{ runner\.temp \}\}\/easysubway-datapack-stage\/route-map-audit\.json/);
  assert.match(workflow, /Data Pack Release \/ Prepare release fixture/);
  assert.match(workflow, /id: release-fixture/);
  assert.match(workflow, /tools\/datapack\/import-official-sources\.mjs/);
  assert.match(workflow, /--input tools\/datapack\/inputs\/capital-pilot-production-source-input\.json/);
  assert.match(workflow, /build_fixture="\$\{EASYSUBWAY_DATAPACK_REVIEWED_FIXTURE\}"/);
  assert.match(workflow, /const spec=JSON\.parse\(fs\.readFileSync\(process\.env\.EASYSUBWAY_DATAPACK_BUILD_SPEC_PATH/);
  assert.match(workflow, /process\.stdout\.write\(spec\.fixturePath\)/);
  assert.match(workflow, /remote_publish_ready=true/);
  assert.match(workflow, /remote_publish_ready=\$\{remote_publish_ready\}/);
  assert.match(workflow, /verified \(ENTRY\|EXIT\|TRANSFER\) coverage gap/);
  assert.match(workflow, /blocked-strict-coverage/);
  assert.match(workflow, /EASYSUBWAY_DATAPACK_BUILD_FIXTURE=\$\{build_fixture\}/);
  assert.match(workflow, /tools\/datapack\/apply-admin-review-overrides\.mjs/);
  assert.match(workflow, /Data Pack Release \/ Audit route map coordinate coverage/);
  assert.match(workflow, /node tools\/route-map\/audit-route-map\.mjs/);
  assert.match(workflow, /--fixture "\$\{EASYSUBWAY_DATAPACK_BUILD_FIXTURE\}"/);
  assert.match(workflow, /--reviewed-ambiguities tools\/route-map\/fixtures\/reviewed-ambiguities\.json/);
  assert.match(workflow, /--fail-on BLOCKER,HIGH/);
  assert.match(workflow, /test -s "\$\{EASYSUBWAY_ROUTE_MAP_AUDIT_REPORT\}"/);
  assert.match(workflow, /node tools\/datapack\/validate-source-inventory\.mjs/);
  assert.match(workflow, /tools\/datapack\/build-datapack\.mjs[\s\S]*?--fixture "\$\{EASYSUBWAY_DATAPACK_BUILD_FIXTURE\}"/);
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
  assert.doesNotMatch(workflow, /--allow-invalid-disabled/);
  assert.match(workflow, /id: remote-publish-env/);
  assert.match(workflow, /steps\.remote-publish-env\.outputs\.enabled == 'true'/);
  assert.match(workflow, /steps\.release-fixture\.outputs\.remote_publish_ready == 'true'/);
  assert.match(workflow, /github\.ref == 'refs\/heads\/main'/);
  assert.match(workflow, /--require-production/);
  assert.match(workflow, /Data Pack Release \/ Upload staged data packs[\s\S]*?if: \$\{\{ always\(\) \}\}/);
  assert.match(workflow, /\$\{EASYSUBWAY_DATAPACK_STAGE\}\/catalog\/current\.json/);
  assert.match(workflow, /publish-plan\.json/);
  assert.doesNotMatch(workflow, /\$\{EASYSUBWAY_DATAPACK_STAGE\}\/current\.json/);
  assert.ok(restoreSecretIndex >= 0, "workflow must restore dotenv secret before production data pack build");
  assert.ok(remoteEnvIndex > restoreSecretIndex, "workflow must validate remote publish env after secret restore");
  assert.ok(prepareIndex > remoteEnvIndex, "workflow must prepare the release fixture after remote publish mode is known");
  assert.ok(routeMapAuditIndex > prepareIndex, "workflow must audit reviewed route map coordinates after release fixture preparation");
  assert.ok(buildIndex > routeMapAuditIndex, "workflow must build data packs after route map coordinate audit");
  assert.ok(validateIndex >= 0, "workflow must validate generated data packs");
  assert.ok(packIndex > validateIndex, "workflow must stage pack files after validation");
  assert.ok(verifyIndex > packIndex, "workflow must verify staged pack checksums before manifest staging");
  assert.ok(manifestIndex > verifyIndex, "workflow must stage manifest after pack checksum verification");
  assert.ok(preflightIndex > manifestIndex, "workflow must create publish preflight plan after manifest staging");
  assert.ok(executorDryRunIndex > preflightIndex, "workflow must validate publish executor after plan creation");
  assert.ok(remotePublishIndex > executorDryRunIndex, "workflow must publish remotely after dry-run validation");
  const requireProductionIndex = workflow.indexOf("--require-production", remotePublishIndex);
  const publishObjectStorageIndex = workflow.indexOf("publish-object-storage.mjs", remotePublishIndex);
  assert.notStrictEqual(
    requireProductionIndex,
    -1,
    "workflow must enable --require-production in the remote publish block",
  );
  assert.ok(
    requireProductionIndex < publishObjectStorageIndex,
    "workflow must reject fixture packs before remote publish",
  );
  assert.ok(artifactIndex > remotePublishIndex, "workflow must keep artifact upload after remote publish attempt");
  assert.match(workflow, /name: easysubway-datapacks-\$\{\{ github\.sha \}\}/);
  assert.match(workflow, /path: \$\{\{ runner\.temp \}\}\/easysubway-datapack-stage/);
});

test("데이터팩 release workflow는 production publish hard gate를 강제한다", () => {
  const workflow = read(".github/workflows/datapack-release.yml");
  const releaseEvidenceBundleSchema = readJson("tools/datapack/schema/release-evidence-bundle.schema.json");

  assert.match(workflow, /mode:[\s\S]*options:[\s\S]*- exploratory[\s\S]*- release-candidate[\s\S]*- production-publish/);
  assert.match(workflow, /buildSpecPath:[\s\S]*required: true/);
  assert.match(workflow, /allowGaps:[\s\S]*default: false/);
  assert.match(workflow, /targetChannel:[\s\S]*options:[\s\S]*- dev[\s\S]*- staging[\s\S]*- production/);
  assert.match(workflow, /releaseRequestId:/);
  assert.match(workflow, /releaseRequestPath:/);
  assert.match(workflow, /production-datapack/);
  assert.match(workflow, /Data Pack Release \/ Validate release mode inputs/);
  assert.match(workflow, /release-candidate\|production-publish/);
  assert.match(workflow, /release mode cannot use --allow-gaps/);
  assert.match(workflow, /release mode cannot use fixture input/);
  assert.match(workflow, /release request approver must differ from requester/);
  assert.match(workflow, /manifest channel must match targetChannel/);
  assert.match(workflow, /Data Pack Release \/ Validate release evidence bundle/);
  assert.match(workflow, /tools\/datapack\/validate-release-evidence-bundle\.mjs/);
  assert.match(workflow, /--build-spec "\$\{EASYSUBWAY_DATAPACK_BUILD_SPEC_PATH\}"/);
  assert.match(workflow, /const buildSpec = JSON\.parse\(fs\.readFileSync\(buildSpecPath, "utf8"\)\)/);
  assert.match(workflow, /sourceSnapshotSetHash: releaseHash\("sourceSnapshotSetHash"\)/);
  assert.match(workflow, /approvedOverrideSetHash: releaseHash\("approvedOverrideSetHash"\)/);
  assert.match(workflow, /throw new Error\(`buildSpec\.\$\{field\} must be sha256`\)/);
  assert.match(workflow, /--require-pass/);
  assert.match(workflow, /--verify-only/);
  const nodeTerminatorIndents = workflow
    .split("\n")
    .filter((line) => /^\s*NODE$/.test(line))
    .map((line) => line.match(/^\s*/)[0].length);
  assert.deepEqual(
    nodeTerminatorIndents,
    [10, 10, 10],
    "workflow heredoc terminators must start at shell column 1 after YAML indentation is stripped",
  );

  for (const field of [
    "releaseRequestId",
    "supportedDenominatorSha256",
    "coverageStatus",
    "strictRouteRegressionSha256",
    "androidEvidenceSha256",
    "strictRouteRegressionStatus",
  ]) {
    assert.ok(releaseEvidenceBundleSchema.required.includes(field), `${field} must be required`);
  }
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
  assert.ok(
    existsSync(path.join(root, "tools/ci/check-google-play-api-access.mjs")),
    "Google Play API access checker must exist",
  );

  const workflow = read(".github/workflows/store-distribution-evidence.yml");
  const preflight = read("tools/ci/check-store-distribution-evidence-env.mjs");
  const playApiAccess = read("tools/ci/check-google-play-api-access.mjs");

  assert.match(workflow, /^name: Store Distribution Evidence$/m);
  assert.match(workflow, /workflow_dispatch:/);
  assertActionsEnvSecretPolicy(".github/workflows/store-distribution-evidence.yml", workflow);
  assert.match(workflow, /EASYSUBWAY_ENV_SECRET: \$\{\{ secrets\.EASYSUBWAY_ENV \}\}/);
  assert.match(workflow, /printf '%s' "\$\{EASYSUBWAY_ENV_SECRET\}" > "\$\{env_file\}"/);
  assert.doesNotMatch(workflow, /printf '%s\\n' "\$\{EASYSUBWAY_ENV_SECRET\}"/);
  assert.match(workflow, /node tools\/ci\/check-store-distribution-evidence-env\.mjs/);
  assert.match(workflow, /--env-file "\$\{EASYSUBWAY_ENV_FILE\}"/);
  assert.match(workflow, /--mobile-pubspec apps\/mobile\/pubspec\.yaml/);
  assert.match(workflow, /--github-output "\$\{GITHUB_OUTPUT\}"/);
  assert.match(workflow, /--report "\$\{RUNNER_TEMP\}\/store-distribution-evidence-preflight\.txt"/);
  assert.match(workflow, /node tools\/ci\/check-google-play-api-access\.mjs/);
  assert.match(workflow, /--report "\$\{RUNNER_TEMP\}\/google-play-api-access\.txt"/);
  assert.match(workflow, /node tools\/datapack\/export-publish-env\.mjs/);
  assert.doesNotMatch(workflow, /--allow-invalid-disabled/);
  assert.match(workflow, /store-distribution-evidence-preflight-\$\{\{ github\.sha \}\}/);
  assert.match(workflow, /\$\{\{ runner\.temp \}\}\/google-play-api-access\.txt/);

  assert.match(preflight, /EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON/);
  assert.match(preflight, /EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME/);
  assert.match(preflight, /EASYSUBWAY_GOOGLE_PLAY_APP_SIGNING_SHA256/);
  assert.match(preflight, /EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE/);
  assert.match(preflight, /sha256_fingerprint/);
  assert.match(preflight, /nonnegative_integer/);
  assert.match(preflight, /must_be_less_than_mobile_version_code/);
  assert.match(preflight, /EASYSUBWAY_APP_STORE_CONNECT_KEY_ID/);
  assert.match(preflight, /EASYSUBWAY_APP_STORE_CONNECT_ISSUER_ID/);
  assert.match(preflight, /EASYSUBWAY_APP_STORE_CONNECT_PRIVATE_KEY_PEM/);
  assert.match(preflight, /EASYSUBWAY_APP_STORE_APPLE_ID/);
  assert.match(preflight, /DEFERRED_OUT_OF_SCOPE/);
  assert.match(preflight, /releaseBlocker: false/);
  assert.match(preflight, /EASYSUBWAY_DATAPACK_REMOTE_PUBLISH_ENABLED/);
  assert.match(preflight, /EASYSUBWAY_OBJECT_STORAGE_PREAUTH_BASE_URL/);
  assert.doesNotMatch(preflight, /console\.log\(.*env\[/, "preflight must not print secret values");

  assert.match(playApiAccess, /https:\/\/www\.googleapis\.com\/auth\/androidpublisher/);
  assert.match(playApiAccess, /\/applications\/\$\{encodePath\(packageName\)\}\/edits/);
  assert.match(playApiAccess, /\/tracks/);
  assert.match(playApiAccess, /:validate/);
  assert.match(playApiAccess, /method: "DELETE"/);
  assert.doesNotMatch(playApiAccess, /client_email=.*\$\{/, "API access report must not print service account email");
});

test("스토어 배포 증거 preflight는 iOS 누락을 Android 출시 blocker로 보지 않는다", async () => {
  const dir = await mkdtemp(path.join(tmpdir(), "easysubway-store-env-android-only-"));
  const envFile = path.join(dir, "deploy.env");
  const outputFile = path.join(dir, "github-output.txt");
  const reportFile = path.join(dir, "report.txt");
  await writeFile(
    envFile,
    [
      "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64=base64-json",
      "EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME=com.easysubway.app",
      "EASYSUBWAY_GOOGLE_PLAY_APP_SIGNING_SHA256=AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA",
      "EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE=0",
      "EASYSUBWAY_DATAPACK_REMOTE_PUBLISH_ENABLED=true",
      "EASYSUBWAY_DATA_PACK_BASE_URL=https://cdn.example.com/easysubway-datapacks",
      "EASYSUBWAY_OBJECT_STORAGE_PREAUTH_BASE_URL=https://objectstorage.example.com/p/token/n/ns/b/bucket/o/",
      "",
    ].join("\n"),
  );

  await execFileAsync(
    process.execPath,
    [
      "tools/ci/check-store-distribution-evidence-env.mjs",
      "--env-file",
      envFile,
      "--mobile-pubspec",
      "apps/mobile/pubspec.yaml",
      "--github-output",
      outputFile,
      "--report",
      reportFile,
    ],
    { cwd: root },
  );

  const output = readFileSync(outputFile, "utf8");
  const report = readFileSync(reportFile, "utf8");
  assert.match(output, /^android_play_internal_track_ready=true$/m);
  assert.match(output, /^ios_testflight_ready=false$/m);
  assert.match(output, /^datapack_object_storage_publish_ready=true$/m);
  assert.match(report, /^ios_testflight.release_blocker=false$/m);
  assert.match(report, /^ios_testflight.status=DEFERRED_OUT_OF_SCOPE$/m);
});

test("스토어 배포 증거 preflight는 legacy S3와 PAR 데이터팩 publish env를 모두 허용한다", async () => {
  const commonEnvLines = [
    "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64=base64-json",
    "EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME=com.easysubway.app",
    "EASYSUBWAY_GOOGLE_PLAY_APP_SIGNING_SHA256=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE=0",
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
        "--mobile-pubspec",
        "apps/mobile/pubspec.yaml",
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

test("스토어 배포 증거 preflight는 Play App Signing 지문과 versionCode 증가를 요구한다", async () => {
  const dir = await mkdtemp(path.join(tmpdir(), "easysubway-store-env-play-identity-"));
  const envFile = path.join(dir, "deploy.env");
  const outputFile = path.join(dir, "github-output.txt");
  const reportFile = path.join(dir, "report.txt");
  const mobileVersionCode = currentMobileVersionCode();
  await writeFile(
    envFile,
    [
      "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64=base64-json",
      "EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME=com.easysubway.app",
      "EASYSUBWAY_GOOGLE_PLAY_APP_SIGNING_SHA256=not-a-fingerprint",
      `EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE=${mobileVersionCode}`,
      "EASYSUBWAY_DATAPACK_REMOTE_PUBLISH_ENABLED=true",
      "EASYSUBWAY_DATA_PACK_BASE_URL=https://cdn.example.com/easysubway-datapacks",
      "EASYSUBWAY_OBJECT_STORAGE_PREAUTH_BASE_URL=https://objectstorage.example.com/p/token/n/ns/b/bucket/o/",
      "",
    ].join("\n"),
  );

  await assert.rejects(
    execFileAsync(
      process.execPath,
      [
        "tools/ci/check-store-distribution-evidence-env.mjs",
        "--env-file",
        envFile,
        "--mobile-pubspec",
        "apps/mobile/pubspec.yaml",
        "--github-output",
        outputFile,
        "--report",
        reportFile,
      ],
      { cwd: root },
    ),
  );

  const report = readFileSync(reportFile, "utf8");
  assert.match(report, /^android_play_internal_track\.ready=false$/m);
  assert.match(report, /EASYSUBWAY_GOOGLE_PLAY_APP_SIGNING_SHA256:sha256_fingerprint/);
  assert.match(
    report,
    new RegExp(`EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE:must_be_less_than_mobile_version_code_${mobileVersionCode}`),
  );
});

test("스토어 배포 증거 preflight는 큰 Play versionCode가 비교를 우회하지 못하게 한다", async () => {
  const dir = await mkdtemp(path.join(tmpdir(), "easysubway-store-env-play-versioncode-"));
  const envFile = path.join(dir, "deploy.env");
  const outputFile = path.join(dir, "github-output.txt");
  const reportFile = path.join(dir, "report.txt");
  const mobileVersionCode = currentMobileVersionCode();
  await writeFile(
    envFile,
    [
      "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64=base64-json",
      "EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME=com.easysubway.app",
      `EASYSUBWAY_GOOGLE_PLAY_APP_SIGNING_SHA256=${validPlayAppSigningFingerprint}`,
      "EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE=900719925474099312345",
      "EASYSUBWAY_DATAPACK_REMOTE_PUBLISH_ENABLED=true",
      "EASYSUBWAY_DATA_PACK_BASE_URL=https://cdn.example.com/easysubway-datapacks",
      "EASYSUBWAY_OBJECT_STORAGE_PREAUTH_BASE_URL=https://objectstorage.example.com/p/token/n/ns/b/bucket/o/",
      "",
    ].join("\n"),
  );

  await assert.rejects(
    execFileAsync(
      process.execPath,
      [
        "tools/ci/check-store-distribution-evidence-env.mjs",
        "--env-file",
        envFile,
        "--mobile-pubspec",
        "apps/mobile/pubspec.yaml",
        "--github-output",
        outputFile,
        "--report",
        reportFile,
      ],
      { cwd: root },
    ),
  );

  assert.match(
    readFileSync(reportFile, "utf8"),
    new RegExp(`EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE:must_be_less_than_mobile_version_code_${mobileVersionCode}`),
  );
});

test("데이터팩 도구는 앱 manifest 계약과 SQLite 검증 계약을 고정한다", () => {
  const fixture = JSON.parse(read("tools/datapack/fixtures/catalog-fixture.json"));
  const candidateBuildSpec = JSON.parse(read("tools/datapack/fixtures/candidate-build-spec.json"));
  const releaseRequestSchema = readJson("tools/datapack/schema/release-request.schema.json");
  const releaseCallbackSchema = readJson("tools/datapack/schema/release-callback.schema.json");
  const releaseEvidenceBundleSchema = readJson("tools/datapack/schema/release-evidence-bundle.schema.json");
  const schema = read("tools/datapack/schema/catalog-schema.sql");
  const builder = read("tools/datapack/build-datapack.mjs");
  const validator = read("tools/datapack/validate-datapack.mjs");

  assert.equal(fixture.manifest.ttlSeconds, 3600);
  assert.deepEqual(fixture.manifest.activePack, { id: "capital", version: "1" });
  assert.ok(fixture.packs.some((pack) => pack.id === "capital" && pack.version === "1"));
  assert.equal(candidateBuildSpec.artifactKind, "datapack-candidate-build-spec");
  assert.equal(candidateBuildSpec.schemaVersion, 1);
  assert.equal(candidateBuildSpec.candidateId, "capital-pilot-candidate-fixture");
  assert.equal(candidateBuildSpec.productionScopeId, "capital_pilot_android_v1");
  assert.equal(candidateBuildSpec.fixturePath, "tools/datapack/fixtures/catalog-fixture.json");
  assert.ok(Array.isArray(candidateBuildSpec.sourceSnapshotIds) && candidateBuildSpec.sourceSnapshotIds.length > 0);
  for (const field of [
    "sourceSnapshotSetHash",
    "approvedAliasLedgerHash",
    "facilityEvidenceLedgerHash",
    "routeEvidenceLedgerHash",
    "approvedOverrideSetHash",
    "sourceInventorySha256",
  ]) {
    assert.match(candidateBuildSpec[field], /^[a-f0-9]{64}$/);
  }
  assert.match(candidateBuildSpec.builderGitSha, /^[a-f0-9]{7,40}$/i);
  assert.equal(candidateBuildSpec.builderVersion, "build-datapack.mjs@1");
  assert.equal(releaseRequestSchema.properties.artifactKind.const, "datapack-release-request");
  assert.deepEqual(releaseRequestSchema.required, [
    "schemaVersion",
    "artifactKind",
    "candidateId",
    "scopeId",
    "buildSpecSha256",
    "sourceSnapshotSetHash",
    "approvedLedgerHash",
    "requestedBy",
    "approvedBy",
    "approvalId",
    "targetChannel",
  ]);
  assert.equal(releaseCallbackSchema.properties.artifactKind.const, "datapack-release-callback");
  assert.deepEqual(releaseCallbackSchema.required, [
    "schemaVersion",
    "artifactKind",
    "releaseRequestId",
    "workflowRunUrl",
    "manifestSha256",
    "sqliteSha256",
    "gzipSha256",
    "evidenceBundleSha256",
    "validatorStatus",
    "routeRegressionStatus",
    "publishStatus",
    "callbackVerifier",
  ]);
  assert.equal(releaseEvidenceBundleSchema.title, "EasySubway data pack release evidence bundle");
  assert.equal(releaseEvidenceBundleSchema.properties.artifactKind.const, "datapack-release-evidence-bundle");
  assert.deepEqual(releaseEvidenceBundleSchema.required, [
    "schemaVersion",
    "artifactKind",
    "candidateId",
    "scopeId",
    "releaseRequestId",
    "builderGitSha",
    "buildSpecSha256",
    "supportedDenominatorSha256",
    "sourceSnapshotSetHash",
    "approvedAliasLedgerHash",
    "facilityEvidenceLedgerHash",
    "routeEvidenceLedgerHash",
    "approvedOverrideSetHash",
    "normalizedSourceInventorySha256",
    "sqliteSha256",
    "gzipSha256",
    "manifestSha256",
    "coverageSummarySha256",
    "strictRouteRegressionSha256",
    "androidEvidenceSha256",
    "validatorStatus",
    "coverageStatus",
    "strictRouteRegressionStatus",
    "manifestSignatureStatus",
    "androidEvidenceStatus",
    "createdAt",
    "workflowRunUrl",
  ]);
  assert.match(schema, /CREATE TABLE catalog_metadata/);
  assert.match(schema, /PRAGMA user_version = 9/);
  assert.match(schema, /CREATE TABLE stations/);
  assert.match(schema, /CREATE TABLE station_facility_evidence/);
  assert.match(schema, /CREATE TABLE service_calendars/);
  assert.match(schema, /CREATE TABLE transit_trips/);
  assert.match(schema, /CREATE TABLE transit_stop_times/);
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
  assert.match(builder, /--build-spec/);
  assert.match(builder, /datapack-candidate-build-spec/);
  assert.match(builder, /candidateBuild/);
  assert.match(builder, /"transit_stop_times"/);
  assert.match(validator, /PRAGMA quick_check/);
  assert.match(validator, /PRAGMA foreign_key_check/);
  assert.match(validator, /PRAGMA user_version/);
  assert.match(validator, /minimumTableRows/);
  assert.match(validator, /sourceInventory/);
  assert.match(validator, /validateNetworkEdgeStationLineEndpoints/);
  assert.match(validator, /validateProductionNetworkEdgeProvenance/);
  assert.match(validator, /datapack_verified_edge_coverage/);
  assert.match(validator, /validateRepresentativeRouteRegressions/);
  assert.match(validator, /validateTransitSchedule/);
  assert.match(validator, /transit_stop_times must be monotonic/);
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
    [
      "station_line_membership",
      "route_graph_topology",
      "accessibility_facilities",
      "realtime_arrivals",
      "route_map_positions",
      "demand_reference",
    ],
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
    "seoulmetro-cyberstation-route-map",
    "seoulmetro-station-line-info",
  ]);

  for (const source of inventory.sources) {
    assert.equal(typeof source.requiredForProductionPack, "boolean", `${source.id} must declare production required flag`);
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
      /^https:\/\/(?:data\.seoul\.go\.kr\/dataList\/OA-[0-9]+\/[FS]\/1\/datasetView\.do|www\.data\.go\.kr\/data\/[0-9]+\/(?:openapi|fileData)\.do|www\.seoulmetro\.co\.kr\/kr\/cyberStation\.do)$/,
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
    assert.ok(source.capabilities && typeof source.capabilities === "object", `${source.id} must declare source capabilities`);
    assert.deepEqual(
      Object.keys(source.capabilities).sort((left, right) => left.localeCompare(right)),
      ["facility", "realtime", "schedule"],
      `${source.id} must declare schedule, realtime, and facility capabilities`,
    );

    for (const capabilityName of ["schedule", "realtime", "facility"]) {
      const capability = source.capabilities[capabilityName];
      assert.ok(capability && typeof capability === "object", `${source.id}.${capabilityName} capability must be an object`);
      assert.ok(
        ["SUPPORTED", "CANDIDATE", "UNSUPPORTED"].includes(capability.status),
        `${source.id}.${capabilityName} capability status must be explicit`,
      );
      assert.equal(
        typeof capability.productionUseAllowed,
        "boolean",
        `${source.id}.${capabilityName} productionUseAllowed must be boolean`,
      );
      assert.ok(capability.coverageStatus, `${source.id}.${capabilityName} coverageStatus must be explicit`);
      assert.ok(capability.updateFrequency, `${source.id}.${capabilityName} updateFrequency must be explicit`);
      assert.ok(capability.unsupportedNotes, `${source.id}.${capabilityName} unsupportedNotes must explain support boundary`);
    }

    const realtime = source.capabilities.realtime;
    assert.equal(typeof realtime.liveEtaEligible, "boolean", `${source.id}.realtime.liveEtaEligible must be boolean`);
    assert.ok(realtime.rateLimitStatus, `${source.id}.realtime.rateLimitStatus must be explicit`);
    if (realtime.liveEtaEligible) {
      assert.equal(realtime.productionUseAllowed, true, `${source.id}.realtime live ETA must be approved for production use`);
      assert.equal(
        realtime.rateLimitStatus,
        "COMPATIBLE",
        `${source.id}.realtime live ETA requires compatible provider terms and rate limits`,
      );
    }
  }

  assert.ok(
    inventory.sources.some((source) => source.capabilities.schedule.status !== "UNSUPPORTED"),
    "source inventory must include at least one schedule source or candidate",
  );
  assert.ok(
    inventory.sources.some((source) => source.capabilities.realtime.status !== "UNSUPPORTED"),
    "source inventory must include at least one realtime source or candidate",
  );
  assert.ok(
    inventory.sources.some((source) => source.capabilities.facility.status !== "UNSUPPORTED"),
    "source inventory must include at least one facility source or candidate",
  );

  const realtimeArrivalSource = inventory.sources.find((source) => source.id === "seoul-realtime-arrival-station-info");
  assert.equal(realtimeArrivalSource.capabilities.realtime.status, "CANDIDATE");
  assert.equal(realtimeArrivalSource.capabilities.realtime.liveEtaEligible, false);
  assert.equal(realtimeArrivalSource.capabilities.realtime.rateLimitStatus, "BLOCKED_PENDING_PROVIDER_TERMS_OR_QUOTA");
});

test("Android v1 production 데이터팩 scope는 수도권 pilot 승인 기준을 고정한다", () => {
  const scope = readJson("apps/mobile/release/production-datapack-scope.json");
  const productionInput = readJson("tools/datapack/inputs/capital-pilot-production-source-input.json");
  const inventory = readJson("tools/datapack/source-inventory.json");
  const inventorySources = new Map(inventory.sources.map((source) => [source.id, source]));

  assert.equal(scope.schemaVersion, 1);
  assert.equal(scope.applicationId, "easysubway");
  assert.equal(scope.androidApplicationId, "com.easysubway.app");
  assert.equal(scope.releaseGate, "production-datapack-scope");
  assert.equal(scope.issue, 547);
  assert.equal(scope.status, "DENOMINATOR_LOCKED");
  assert.equal(scope.statusDetail, "SUPPORTED_STATION_LINE_OPERATOR_DENOMINATOR_LOCKED");
  assert.equal(scope.decision.approvalState, "qa-approved");
  assert.equal(scope.supportScope.id, "capital_pilot_android_v1");
  assert.deepEqual(scope.supportScope.regionIds, ["capital"]);
  assert.equal(scope.supportScope.supportedClaimKo, "상록수·사당 검증 pilot");
  assert.deepEqual(scope.supportScope.includedOperatorIds, ["seoul-metro"]);
  assert.deepEqual(scope.supportScope.includedLineIds, ["seoul-4"]);
  assert.deepEqual(scope.supportScope.includedStationIds, ["station-sangnoksu", "station-sadang"]);
  assert.deepEqual(scope.supportScope.requiredFacilityTypes, ["ELEVATOR", "ESCALATOR", "WHEELCHAIR_LIFT"]);
  assert.deepEqual(scope.supportScope.facilityCoverageDenominator, {
    kind: "station_line_x_required_facility_type",
    expectedRows: 6,
  });
  assert.deepEqual(productionInput.supportedV1Scope.includedOperatorIds, scope.supportScope.includedOperatorIds);
  assert.deepEqual(productionInput.supportedV1Scope.includedLineIds, scope.supportScope.includedLineIds);
  assert.deepEqual(productionInput.supportedV1Scope.includedStationIds, scope.supportScope.includedStationIds);
  assert.deepEqual(productionInput.supportedV1Scope.requiredFacilityTypes, scope.supportScope.requiredFacilityTypes);
  assert.deepEqual(
    productionInput.supportedV1Scope.facilityCoverageDenominator,
    scope.supportScope.facilityCoverageDenominator,
  );
  assert.deepEqual(scope.supportScope.unsupportedRegionPolicy.requiredAppStatus, [
    "UNSUPPORTED_REGION",
    "다시 확인",
  ]);

  assert.deepEqual(scope.productionSourceSet.requiredSourceIds.sort(), [
    "kric-station-elevator",
    "kric-station-elevator-movement",
    "kric-station-escalator",
    "kric-wheelchair-lift-location",
    "kric-wheelchair-lift-movement",
    "molit-urban-rail-full-route",
    "seoulmetro-station-line-info",
  ]);
  assert.ok(scope.productionSourceSet.excludedFromV1SupportClaims.includes("seoul-realtime-arrival-station-info"));
  assert.ok(scope.productionSourceSet.optionalAccessibilitySourceIds.includes("kric-disabled-toilet"));
  assert.deepEqual(scope.productionSourceSet.optionalAccessibilitySourceIds.sort(), [
    "kric-braille-displays",
    "kric-disabled-toilet",
    "kric-elevator-car-number",
    "kric-metropolitan-rail-station-info",
    "kric-platform-train-distance",
    "kric-safety-platform",
  ]);
  assert.deepEqual(scope.productionSourceSet.excludedFromV1SupportClaims.sort(), [
    "busan-transportation-urban-rail-station-info",
    "molit-tago-subway-info",
    "seoul-realtime-arrival-station-info",
    "seoul-subway-hourly-boarding",
  ]);

  const requiredSourceIds = new Set(scope.productionSourceSet.requiredSourceIds);
  const optionalSourceIds = new Set(scope.productionSourceSet.optionalAccessibilitySourceIds);
  const excludedSourceIds = new Set(scope.productionSourceSet.excludedFromV1SupportClaims);
  assert.equal(requiredSourceIds.size, scope.productionSourceSet.requiredSourceIds.length);
  assert.equal(optionalSourceIds.size, scope.productionSourceSet.optionalAccessibilitySourceIds.length);
  assert.equal(excludedSourceIds.size, scope.productionSourceSet.excludedFromV1SupportClaims.length);
  assert.deepEqual([...requiredSourceIds].filter((sourceId) => optionalSourceIds.has(sourceId)), []);
  assert.deepEqual([...requiredSourceIds].filter((sourceId) => excludedSourceIds.has(sourceId)), []);
  assert.deepEqual([...optionalSourceIds].filter((sourceId) => excludedSourceIds.has(sourceId)), []);

  for (const sourceId of [
    ...scope.productionSourceSet.requiredSourceIds,
    ...scope.productionSourceSet.optionalAccessibilitySourceIds,
    ...scope.productionSourceSet.excludedFromV1SupportClaims,
  ]) {
    const source = inventorySources.get(sourceId);
    assert.ok(source, `${sourceId} must exist in source inventory`);
  }
  for (const sourceId of scope.productionSourceSet.requiredSourceIds) {
    const source = inventorySources.get(sourceId);
    assert.equal(source.requiredForProductionPack, true, `${sourceId} must be production eligible`);
    assert.equal(source.license.redistributionAllowed, true, `${sourceId} must allow redistribution`);
    assert.ok(source.coverageScope.regionIds.includes("capital"), `${sourceId} must cover capital`);
  }
  for (const sourceId of scope.productionSourceSet.optionalAccessibilitySourceIds) {
    const source = inventorySources.get(sourceId);
    assert.equal(source.requiredForProductionPack, false, `${sourceId} must stay optional for Android v1 claim`);
  }
  for (const sourceId of scope.productionSourceSet.excludedFromV1SupportClaims) {
    const source = inventorySources.get(sourceId);
    assert.equal(source.requiredForProductionPack, false, `${sourceId} must not be required for Android v1 claim`);
  }
  for (const source of inventory.sources) {
    if (source.requiredForProductionPack) {
      assert.ok(requiredSourceIds.has(source.id), `${source.id} required flag must match production scope`);
    }
  }

  assert.equal(scope.productionPromotionCriteria.artifactKind, "production");
  assert.equal(scope.productionPromotionCriteria.releaseModeAllowGaps, false);
  assert.equal(scope.productionPromotionCriteria.p0CoverageGapPolicy, "fail-release");
  assert.equal(scope.productionPromotionCriteria.minimumProductionCoverageValuesMustBePositive, true);
  assert.equal(scope.productionPromotionCriteria.coverageEvidenceRequired, true);
  assert.equal(scope.productionPromotionCriteria.manifest.manifestVersion, 2);
  assert.equal(scope.productionPromotionCriteria.manifest.channel, "production");
  assert.equal(scope.productionPromotionCriteria.manifest.releaseSequenceMustIncrease, true);
  assert.equal(scope.productionPromotionCriteria.manifest.publishedAtExpiresAtRequired, true);
  assert.equal(scope.productionPromotionCriteria.manifest.publicHttpsPackUrlRequired, true);
  assert.equal(scope.productionPromotionCriteria.manifest.localPlaceholderHostForbidden, true);
  assert.equal(scope.productionPromotionCriteria.manifest.rsaSignatureRequired, true);
  assert.equal(scope.productionPromotionCriteria.manifest.privateKeyForbiddenInRepoArtifacts, true);
  assert.equal(scope.productionPromotionCriteria.strictMobilityProfile.staleUnknownGeneratedConnectorCannotProduceFound, true);
  assert.ok(scope.productionPromotionCriteria.androidEvidenceRequired.includes("published-manifest-install"));
  assert.ok(scope.productionPromotionCriteria.androidEvidenceRequired.includes("rollback-manifest-recovery"));
  assert.ok(
    scope.productionPromotionCriteria.androidEvidenceRequired.includes(
      "corrupt-expired-channel-mismatch-unsigned-manifest-rejection",
    ),
  );
  assert.ok(scope.productionPromotionCriteria.androidEvidenceRequired.includes("offline-existing-pack-retained"));
  assert.ok(scope.productionPromotionForbiddenWhen.includes("pack or source url uses localhost, .localhost, .local domains, or .local hosts"));
  assert.equal(scope.evidencePolicy.githubSummaryOnly, true);
  assert.ok(scope.linkedReleaseBlockers.includes(571));
  assert.ok(scope.linkedReleaseBlockers.includes(1020));
});

test("official source importer는 production placeholder evidence hash를 거부한다", async () => {
  const outputDir = await mkdtemp(path.join(tmpdir(), "easysubway-production-placeholder-evidence-"));
  const input = readJson("tools/datapack/inputs/capital-pilot-production-source-input.json");
  const inputPath = path.join(outputDir, "input.json");
  const outputPath = path.join(outputDir, "output.json");

  input.facilityRows[0].evidenceHash = "1".repeat(64);

  await writeFile(inputPath, `${JSON.stringify(input, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(
      process.execPath,
      [
        "tools/datapack/import-official-sources.mjs",
        "--inventory",
        "tools/datapack/source-inventory.json",
        "--input",
        inputPath,
        "--output",
        outputPath,
      ],
      { cwd: root },
    ),
    /facilityRows\.evidenceHash is placeholder evidence: facility-sangnoksu-elevator-kric-1/,
  );
});

test("official source importer는 production facility source snapshot id 누락을 거부한다", async () => {
  const outputDir = await mkdtemp(path.join(tmpdir(), "easysubway-production-source-snapshot-"));
  const input = readJson("tools/datapack/inputs/capital-pilot-production-source-input.json");
  const inputPath = path.join(outputDir, "input.json");
  const outputPath = path.join(outputDir, "output.json");

  for (const row of input.facilityRows) {
    row.evidenceHash = createHash("sha256").update(`evidence:${row.id}`).digest("hex");
    row.providerRecordHash = createHash("sha256").update(`provider:${row.id}`).digest("hex");
  }
  delete input.facilityRows[0].sourceSnapshotId;

  await writeFile(inputPath, `${JSON.stringify(input, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(
      process.execPath,
      [
        "tools/datapack/import-official-sources.mjs",
        "--inventory",
        "tools/datapack/source-inventory.json",
        "--input",
        inputPath,
        "--output",
        outputPath,
      ],
      { cwd: root },
    ),
    /facilityRows\.sourceSnapshotId must be a non-empty string/,
  );
});

test("official source importer는 production facility provider record hash 누락을 거부한다", async () => {
  const outputDir = await mkdtemp(path.join(tmpdir(), "easysubway-production-provider-record-"));
  const input = readJson("tools/datapack/inputs/capital-pilot-production-source-input.json");
  const inputPath = path.join(outputDir, "input.json");
  const outputPath = path.join(outputDir, "output.json");

  for (const row of input.facilityRows) {
    row.sourceSnapshotId = `${row.sourceId}-snapshot-20260622`;
    row.evidenceHash = createHash("sha256").update(`evidence:${row.id}`).digest("hex");
  }
  delete input.facilityRows[0].providerRecordHash;

  await writeFile(inputPath, `${JSON.stringify(input, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(
      process.execPath,
      [
        "tools/datapack/import-official-sources.mjs",
        "--inventory",
        "tools/datapack/source-inventory.json",
        "--input",
        inputPath,
        "--output",
        outputPath,
      ],
      { cwd: root },
    ),
    /facilityRows\.providerRecordHash must be a non-empty string/,
  );
});

test("official source importer는 production route edge 검증 기본값 누락을 거부한다", async () => {
  const cases = [
    ["provenanceKind", /routeEdges\.provenanceKind must be a non-empty string/],
    ["verificationStatus", /routeEdges\.verificationStatus must be a non-empty string/],
    ["accessibilityStatus", /routeEdges\.accessibilityStatus must be a non-empty string/],
    ["reliabilityScore", /routeEdges\.reliabilityScore must be an integer/],
  ];

  for (const [field, expected] of cases) {
    const outputDir = await mkdtemp(path.join(tmpdir(), `easysubway-production-route-${field}-`));
    const input = readJson("tools/datapack/inputs/capital-pilot-production-source-input.json");
    const inputPath = path.join(outputDir, "input.json");
    const outputPath = path.join(outputDir, "output.json");
    delete input.routeEdges[0][field];

    await writeFile(inputPath, `${JSON.stringify(input, null, 2)}\n`);
    await assert.rejects(
      execFileAsync(
        process.execPath,
        [
          "tools/datapack/import-official-sources.mjs",
          "--inventory",
          "tools/datapack/source-inventory.json",
          "--input",
          inputPath,
          "--output",
          outputPath,
        ],
        { cwd: root },
      ),
      expected,
    );
  }
});

test("official source importer는 production route edge verifiedAt alias를 유지한다", async () => {
  const outputDir = await mkdtemp(path.join(tmpdir(), "easysubway-production-route-verified-at-alias-"));
  const input = readJson("tools/datapack/inputs/capital-pilot-production-source-input.json");
  const inputPath = path.join(outputDir, "input.json");
  const outputPath = path.join(outputDir, "output.json");
  const verifiedAt = "2026-06-21T01:02:03.000Z";

  delete input.routeEdges[0].lastVerifiedAt;
  input.routeEdges[0].verifiedAt = verifiedAt;

  await writeFile(inputPath, `${JSON.stringify(input, null, 2)}\n`);
  await execFileAsync(
    process.execPath,
    [
      "tools/datapack/import-official-sources.mjs",
      "--inventory",
      "tools/datapack/source-inventory.json",
      "--input",
      inputPath,
      "--output",
      outputPath,
    ],
    { cwd: root },
  );

  const fixture = JSON.parse(readFileSync(outputPath, "utf8"));
  assert.equal(fixture.packs[0].networkEdges[0].lastVerifiedAt, verifiedAt);
});

test("official source importer는 fixture route edge 검증 timestamp 누락을 거부한다", async () => {
  const outputDir = await mkdtemp(path.join(tmpdir(), "easysubway-fixture-route-timestamp-"));
  const input = readJson("tools/datapack/inputs/capital-pilot-production-source-input.json");
  const inputPath = path.join(outputDir, "input.json");
  const outputPath = path.join(outputDir, "output.json");

  input.pack.artifactKind = "fixture";
  delete input.routeEdges[0].lastVerifiedAt;
  delete input.routeEdges[0].verifiedAt;

  await writeFile(inputPath, `${JSON.stringify(input, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(
      process.execPath,
      [
        "tools/datapack/import-official-sources.mjs",
        "--inventory",
        "tools/datapack/source-inventory.json",
        "--input",
        inputPath,
        "--output",
        outputPath,
      ],
      { cwd: root },
    ),
    /routeEdges\.lastVerifiedAt must be a non-empty string/,
  );
});

test("official source importer는 production facility 검증 기본값 누락을 거부한다", async () => {
  const cases = [
    ["providerFacilityRef", /facilityRows\.providerFacilityRef must be a non-empty string/],
    ["provenanceKind", /facilityRows\.provenanceKind must be a non-empty string/],
    ["statusMeaning", /facilityRows\.statusMeaning must be a non-empty string/],
    ["operationalStatus", /facilityRows\.operationalStatus must be a non-empty string/],
    ["installationStatus", /facilityRows\.installationStatus must be a non-empty string/],
    ["verifiedAt", /facilityRows\.verifiedAt must be a non-empty string/],
    ["retrievedAt", /facilityRows\.retrievedAt must be a non-empty string/],
    ["confidence", /facilityRows\.confidence must be an integer/],
  ];

  for (const [field, expected] of cases) {
    const outputDir = await mkdtemp(path.join(tmpdir(), `easysubway-production-facility-${field}-`));
    const input = readJson("tools/datapack/inputs/capital-pilot-production-source-input.json");
    const inputPath = path.join(outputDir, "input.json");
    const outputPath = path.join(outputDir, "output.json");
    delete input.facilityRows[0][field];

    await writeFile(inputPath, `${JSON.stringify(input, null, 2)}\n`);
    await assert.rejects(
      execFileAsync(
        process.execPath,
        [
          "tools/datapack/import-official-sources.mjs",
          "--inventory",
          "tools/datapack/source-inventory.json",
          "--input",
          inputPath,
          "--output",
          outputPath,
        ],
        { cwd: root },
      ),
      expected,
    );
  }
});

test("official source importer는 production facility confidence 범위를 검증한다", async () => {
  for (const confidence of [-1, 101]) {
    const outputDir = await mkdtemp(path.join(tmpdir(), `easysubway-production-facility-confidence-${confidence}-`));
    const input = readJson("tools/datapack/inputs/capital-pilot-production-source-input.json");
    const inputPath = path.join(outputDir, "input.json");
    const outputPath = path.join(outputDir, "output.json");
    input.facilityRows[0].confidence = confidence;

    await writeFile(inputPath, `${JSON.stringify(input, null, 2)}\n`);
    await assert.rejects(
      execFileAsync(
        process.execPath,
        [
          "tools/datapack/import-official-sources.mjs",
          "--inventory",
          "tools/datapack/source-inventory.json",
          "--input",
          inputPath,
          "--output",
          outputPath,
        ],
        { cwd: root },
      ),
      /facilityRows\.confidence must be between 0 and 100/,
    );
  }
});

test("production row provenance는 snapshot/provider/evidence hash gate를 유지한다", () => {
  const input = readJson("tools/datapack/inputs/capital-pilot-production-source-input.json");
  const schema = read("tools/datapack/schema/catalog-schema.sql");
  const builder = read("tools/datapack/build-datapack.mjs");
  const validator = read("tools/datapack/validate-datapack.mjs");
  const mobileTables = read("apps/mobile/lib/core/database/catalog/catalog_tables.dart");
  const mobileDatabase = read("apps/mobile/lib/core/database/catalog/catalog_database.dart");
  const schedulePostgresMigration = read("backend/src/main/resources/db/migration/postgresql/V29__canonical_transit_schedule.sql");
  const scheduleH2Migration = read("backend/src/main/resources/db/migration/h2/V29__canonical_transit_schedule.sql");

  for (const row of input.facilityRows) {
    assert.match(row.sourceSnapshotId, /^[a-z0-9-]+-snapshot-\d{8}$/);
    assert.match(row.providerRecordHash, /^[0-9a-f]{64}$/);
    assert.match(row.evidenceHash, /^[0-9a-f]{64}$/);
    assert.doesNotMatch(row.providerRecordHash, /^([0-9a-f])\1{63}$/);
    assert.doesNotMatch(row.evidenceHash, /^([0-9a-f])\1{63}$/);
  }
  for (const row of input.routeEdges) {
    assert.match(row.sourceSnapshotId, /^[a-z0-9-]+-snapshot-\d{8}$/);
    assert.match(row.providerRecordHash, /^[0-9a-f]{64}$/);
    assert.match(row.evidenceHash, /^[0-9a-f]{64}$/);
    assert.doesNotMatch(row.providerRecordHash, /^([0-9a-f])\1{63}$/);
    assert.doesNotMatch(row.evidenceHash, /^([0-9a-f])\1{63}$/);
  }
  for (const row of input.movementPathCandidates) {
    assert.match(row.sourceSnapshotId, /^[a-z0-9-]+-snapshot-\d{8}$/);
    assert.match(row.providerRecordHash, /^[0-9a-f]{64}$/);
    assert.match(row.evidenceHash, /^[0-9a-f]{64}$/);
    assert.doesNotMatch(row.providerRecordHash, /^([0-9a-f])\1{63}$/);
    assert.doesNotMatch(row.evidenceHash, /^([0-9a-f])\1{63}$/);
  }

  assert.match(schema, /CREATE TABLE network_edges \([\s\S]+source_snapshot_id TEXT NOT NULL DEFAULT ''[\s\S]+provider_record_hash TEXT NOT NULL DEFAULT ''/);
  assert.match(schema, /CREATE TABLE facilities \([\s\S]+source_snapshot_id TEXT NOT NULL DEFAULT ''[\s\S]+provider_record_hash TEXT NOT NULL DEFAULT ''/);
  assert.match(schema, /CREATE TABLE station_facility_evidence \([\s\S]+provider_record_hash TEXT NOT NULL[\s\S]+strict_route_eligible INTEGER NOT NULL DEFAULT 0/);
  assert.match(schema, /CREATE TABLE transit_stop_times \([\s\S]+arrival_seconds INTEGER NOT NULL[\s\S]+departure_seconds INTEGER NOT NULL/);
  assert.match(schema, /CREATE TABLE internal_route_edges \([\s\S]+source_snapshot_id TEXT NOT NULL DEFAULT ''[\s\S]+provider_record_hash TEXT NOT NULL DEFAULT ''/);
  assert.match(builder, /"station_facility_evidence"/);
  assert.match(builder, /"transit_stop_times"/);
  assert.match(builder, /"source_snapshot_id"/);
  assert.match(builder, /"provider_record_hash"/);
  assert.match(validator, /validateProductionStationFacilityEvidence/);
  assert.match(validator, /validateTransitSchedule/);
  assert.match(validator, /"source_snapshot_id"/);
  assert.match(validator, /"provider_record_hash"/);
  assert.match(mobileTables, /class TransitStopTimes extends Table/);
  assert.match(mobileDatabase, /int get schemaVersion => 9/);
  assert.match(mobileDatabase, /_createTransitScheduleIndexes/);
  assert.match(schedulePostgresMigration, /CREATE TABLE IF NOT EXISTS transit_stop_times/);
  assert.match(scheduleH2Migration, /CREATE TABLE IF NOT EXISTS transit_stop_times/);
  assert.match(validator, /validateProductionInternalRouteEdgeProvenance/);
  assert.match(validator, /validateNetworkEdgeBaseProvenance/);
  assert.match(validator, /is placeholder evidence/);
  assert.match(mobileTables, /class StationFacilityEvidence extends Table/);
  assert.match(mobileTables, /sourceSnapshotId[\s\S]+source_snapshot_id/);
  assert.match(mobileTables, /providerRecordHash[\s\S]+provider_record_hash/);
  assert.match(mobileDatabase, /int get schemaVersion => 9/);
  assert.match(mobileDatabase, /StationFacilityEvidence/);
  assert.match(mobileDatabase, /_addSourceEvidenceProvenanceColumns/);
});

test("strict route coverage는 UNKNOWN edge와 unpromoted movement candidate를 제외한다", async () => {
  const validator = read("tools/datapack/validate-datapack.mjs");
  const importer = read("tools/datapack/import-official-sources.mjs");
  const input = readJson("tools/datapack/inputs/capital-pilot-production-source-input.json");
  const outputDir = await mkdtemp(path.join(tmpdir(), "easysubway-strict-route-coverage-"));
  const importedFixturePath = path.join(outputDir, "capital-pilot-production.json");

  assert.doesNotMatch(validator, /\["AVAILABLE", "UNKNOWN"\]\.includes\(String\(edge\.accessibility_status/);
  assert.match(validator, /String\(edge\.accessibility_status \?\? ""\)\.toUpperCase\(\) === "AVAILABLE"/);
  assert.match(validator, /function isAccessibilityProvenanceCandidate/);
  assert.match(validator, /\["AVAILABLE", "UNKNOWN"\]\.includes\(accessibilityStatus\)/);
  assert.match(validator, /unverifiedAccessibilityCoverageEdges/);

  for (const candidate of input.movementPathCandidates) {
    assert.match(candidate.evidenceHash, /^[0-9a-f]{64}$/);
  }
  assert.match(importer, /reviewStatus: "PENDING_ADMIN_REVIEW"/);
  assert.doesNotMatch(importer, /APPROVED_FOR_GRAPH/);

  await execFileAsync(
    process.execPath,
    [
      "tools/datapack/import-official-sources.mjs",
      "--inventory",
      "tools/datapack/source-inventory.json",
      "--input",
      "tools/datapack/inputs/capital-pilot-production-source-input.json",
      "--output",
      importedFixturePath,
    ],
    { cwd: root },
  );
  const importedPack = JSON.parse(readFileSync(importedFixturePath, "utf8")).packs[0];
  assert.deepEqual(
    importedPack.movementPathCandidates.map((candidate) => ({
      id: candidate.id,
      reviewStatus: candidate.reviewStatus,
    })),
    input.movementPathCandidates.map((candidate) => ({
      id: candidate.id,
      reviewStatus: "PENDING_ADMIN_REVIEW",
    })),
  );
  assert.equal(importedPack.networkEdges.some((edge) => edge.edgeType === "MOVEMENT"), false);
  assert.equal(importedPack.stationFacilityEvidence.length, input.supportedV1Scope.facilityCoverageDenominator.expectedRows);
});

test("official source importer는 locked production denominator 밖 station을 거부한다", async () => {
  const outputDir = await mkdtemp(path.join(tmpdir(), "easysubway-production-denominator-"));
  const input = readJson("tools/datapack/inputs/capital-pilot-production-source-input.json");
  const inputPath = path.join(outputDir, "input.json");
  const outputPath = path.join(outputDir, "output.json");

  input.stationMappings.push({
    sourceId: "molit-urban-rail-full-route",
    sourceStationCode: "MOLIT-SEOUL-4-999",
    lineId: "seoul-4",
    stationId: "station-extra",
    stationLineId: "station-extra:seoul-4",
    mappingStatus: "active",
  });
  input.stationLineRows.push({
    ...input.stationLineRows[0],
    sourceStationCode: "MOLIT-SEOUL-4-999",
    stationNameKo: "추가",
    stationNameEn: "Extra",
    normalizedName: "추가",
    stationCode: "999",
    lineSequence: 99,
  });
  for (const [sourceId, type] of [
    ["kric-station-elevator", "ELEVATOR"],
    ["kric-station-escalator", "ESCALATOR"],
    ["kric-wheelchair-lift-location", "WHEELCHAIR_LIFT"],
  ]) {
    input.facilityRows.push({
      ...input.facilityRows[0],
      sourceId,
      id: `facility-extra-${type.toLowerCase()}`,
      station: {
        sourceId: "molit-urban-rail-full-route",
        sourceStationCode: "MOLIT-SEOUL-4-999",
        lineId: "seoul-4",
      },
      type,
      name: `추가 ${type}`,
      providerFacilityRef: `extra-${type}`,
    });
  }

  await writeFile(inputPath, `${JSON.stringify(input, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(
      process.execPath,
      [
        "tools/datapack/import-official-sources.mjs",
        "--inventory",
        "tools/datapack/source-inventory.json",
        "--input",
        inputPath,
        "--output",
        outputPath,
      ],
      { cwd: root },
    ),
    /production scope station outside supportedV1Scope\.includedStationIds: station-extra/,
  );
});

test("official source importer는 locked production operator 밖 line metadata를 거부한다", async () => {
  const outputDir = await mkdtemp(path.join(tmpdir(), "easysubway-production-operator-"));
  const input = readJson("tools/datapack/inputs/capital-pilot-production-source-input.json");
  const inputPath = path.join(outputDir, "input.json");
  const outputPath = path.join(outputDir, "output.json");

  input.operators.push({
    id: "other-operator",
    nameKo: "다른 운영사",
    nameEn: "Other Operator",
  });
  input.lines[0].operatorId = "other-operator";

  await writeFile(inputPath, `${JSON.stringify(input, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(
      process.execPath,
      [
        "tools/datapack/import-official-sources.mjs",
        "--inventory",
        "tools/datapack/source-inventory.json",
        "--input",
        inputPath,
        "--output",
        outputPath,
      ],
      { cwd: root },
    ),
    /production scope operator outside supportedV1Scope\.includedOperatorIds: other-operator/,
  );
});

test("official source importer는 locked production operator metadata 누락을 거부한다", async () => {
  const outputDir = await mkdtemp(path.join(tmpdir(), "easysubway-production-operator-metadata-"));
  const input = readJson("tools/datapack/inputs/capital-pilot-production-source-input.json");
  const inputPath = path.join(outputDir, "input.json");
  const outputPath = path.join(outputDir, "output.json");

  input.operators = [];

  await writeFile(inputPath, `${JSON.stringify(input, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(
      process.execPath,
      [
        "tools/datapack/import-official-sources.mjs",
        "--inventory",
        "tools/datapack/source-inventory.json",
        "--input",
        inputPath,
        "--output",
        outputPath,
      ],
      { cwd: root },
    ),
    /supportedV1Scope\.includedOperatorIds missing production operator metadata: seoul-metro/,
  );
});

test("official source importer는 locked production denominator 밖 route endpoint를 거부한다", async () => {
  const outputDir = await mkdtemp(path.join(tmpdir(), "easysubway-production-route-endpoint-"));
  const input = readJson("tools/datapack/inputs/capital-pilot-production-source-input.json");
  const inputPath = path.join(outputDir, "input.json");
  const outputPath = path.join(outputDir, "output.json");

  input.stationMappings.push({
    sourceId: "seoulmetro-station-line-info",
    sourceStationCode: "999",
    lineId: "seoul-4",
    stationId: "station-extra",
    stationLineId: "station-extra:seoul-4",
    mappingStatus: "active",
  });
  input.routeEdges.push({
    ...input.routeEdges[0],
    id: "edge-extra-route-endpoint",
    from: {
      sourceId: "seoulmetro-station-line-info",
      sourceStationCode: "448",
      lineId: "seoul-4",
    },
    to: {
      sourceId: "seoulmetro-station-line-info",
      sourceStationCode: "999",
      lineId: "seoul-4",
    },
  });

  await writeFile(inputPath, `${JSON.stringify(input, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(
      process.execPath,
      [
        "tools/datapack/import-official-sources.mjs",
        "--inventory",
        "tools/datapack/source-inventory.json",
        "--input",
        inputPath,
        "--output",
        outputPath,
      ],
      { cwd: root },
    ),
    /production scope station outside supportedV1Scope\.includedStationIds: station-extra/,
  );
});

test("official source importer는 locked production denominator 밖 pass-through station을 거부한다", async () => {
  const outputDir = await mkdtemp(path.join(tmpdir(), "easysubway-production-pass-through-station-"));
  const input = readJson("tools/datapack/inputs/capital-pilot-production-source-input.json");
  const inputPath = path.join(outputDir, "input.json");
  const outputPath = path.join(outputDir, "output.json");

  input.stationMappings.push({
    sourceId: "molit-urban-rail-full-route",
    sourceStationCode: "MOLIT-SEOUL-4-999",
    lineId: "seoul-4",
    stationId: "station-extra",
    stationLineId: "station-extra:seoul-4",
    mappingStatus: "renamed",
    previousNames: ["추가역"],
  });
  input.stationExits = [
    {
      id: "exit-extra",
      stationId: "station-extra",
      exitNumber: "1",
      description: "scope 밖 station exit",
    },
  ];
  input.stationAccessibilitySummaries = [
    {
      stationId: "station-extra",
      summary: "scope 밖 station 접근성 요약",
    },
  ];

  await writeFile(inputPath, `${JSON.stringify(input, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(
      process.execPath,
      [
        "tools/datapack/import-official-sources.mjs",
        "--inventory",
        "tools/datapack/source-inventory.json",
        "--input",
        inputPath,
        "--output",
        outputPath,
      ],
      { cwd: root },
    ),
    /production scope station outside supportedV1Scope\.includedStationIds: station-extra/,
  );
});

test("official source importer는 locked production line denominator의 metadata-only 확장을 거부한다", async () => {
  const outputDir = await mkdtemp(path.join(tmpdir(), "easysubway-production-line-metadata-"));
  const input = readJson("tools/datapack/inputs/capital-pilot-production-source-input.json");
  const inputPath = path.join(outputDir, "input.json");
  const outputPath = path.join(outputDir, "output.json");

  input.supportedV1Scope.includedLineIds.push("seoul-5");
  input.lines.push({
    id: "seoul-5",
    operatorId: "seoul-metro",
    nameKo: "수도권 5호선",
    nameEn: "Seoul Subway Line 5",
    color: "#996CAC",
  });

  await writeFile(inputPath, `${JSON.stringify(input, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(
      process.execPath,
      [
        "tools/datapack/import-official-sources.mjs",
        "--inventory",
        "tools/datapack/source-inventory.json",
        "--input",
        inputPath,
        "--output",
        outputPath,
      ],
      { cwd: root },
    ),
    /supportedV1Scope\.includedLineIds missing production station row: seoul-5/,
  );
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
    assert.ok(candidate.capabilities && typeof candidate.capabilities === "object");
    assert.deepEqual(Object.keys(candidate.capabilities).sort((left, right) => left.localeCompare(right)), [
      "facility",
      "realtime",
      "schedule",
    ]);
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
    assert.ok(candidate.capabilities && typeof candidate.capabilities === "object");
    assert.deepEqual(Object.keys(candidate.capabilities).sort((left, right) => left.localeCompare(right)), [
      "facility",
      "realtime",
      "schedule",
    ]);
    assert.equal(candidate.capabilities.realtime.status, "CANDIDATE");
    assert.equal(candidate.capabilities.realtime.productionUseAllowed, false);
    assert.equal(candidate.capabilities.realtime.liveEtaEligible, false);
    assert.equal(candidate.capabilities.realtime.rateLimitStatus, "BLOCKED_PENDING_PROVIDER_TERMS_OR_QUOTA");
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
    assert.match(source, /productionMinimumTableRowNames = \[[\s\S]+"station_facility_evidence"[\s\S]+\]/);
    assert.match(
      source,
      /production minimumTableRows must define positive stations, station_lines, network_edges, facilities, and station_facility_evidence/,
    );
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
  assert.match(
    compose,
    /image: imresamu\/postgis:16-3\.5@sha256:92031b614897082103c00729ea26e62f118ecb59b71e27b5c3ac3a8dc13bff23/,
  );
  assert.doesNotMatch(postgresBlock, /profiles:/);
  assert.match(compose, /POSTGRES_DB: \$\{EASYSUBWAY_POSTGRES_DB:-easysubway\}/);
  assert.match(compose, /POSTGRES_USER: \$\{EASYSUBWAY_POSTGRES_USER:-easysubway\}/);
  assert.match(compose, /POSTGRES_PASSWORD: \$\{EASYSUBWAY_POSTGRES_PASSWORD:-easysubway_local\}/);
  assert.match(compose, /"\$\{EASYSUBWAY_POSTGRES_PORT:-15432\}:5432"/);
  assert.match(compose, /pg_isready -U \$\$\{POSTGRES_USER\} -d \$\$\{POSTGRES_DB\}/);
  assert.match(compose, /postgres-data:\/var\/lib\/postgresql\/data/);

  assert.match(compose, /object-storage:\n/);
  assert.match(compose, /image: minio\/minio:/);
  assert.match(compose, /image: minio\/minio:RELEASE\.2025-06-13T11-33-47Z/);
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
  assert.match(backupScript, /COMPOSE_PROJECT="\$\{EASYSUBWAY_COMPOSE_PROJECT:-\}"/);
  assert.match(backupScript, /compose_args\+=\(--project-name "\$\{COMPOSE_PROJECT\}"\)/);
  assert.match(backupScript, /compose_args\+=\(--env-file "\$\{ENV_FILE\}" -f "\$\{COMPOSE_FILE\}"\)/);
  assert.match(backupScript, /docker compose "\$\{compose_args\[@\]\}" exec -T postgres sh -lc/);
  assert.match(backupScript, /pg_dump --format=custom --no-owner --no-privileges -U "\$POSTGRES_USER" "\$POSTGRES_DB"/);
  assert.match(backupScript, /> "\$\{temp_file\}"/);
  assert.match(backupScript, /test -s "\$\{temp_file\}"/);
  assert.match(backupScript, /docker compose "\$\{compose_args\[@\]\}" exec -T postgres sh -lc 'pg_restore --list >\/dev\/null' < "\$\{temp_file\}"/);
  assert.doesNotMatch(backupScript, /pg_restore --list -/);
  assert.match(backupScript, /mv "\$\{temp_file\}" "\$\{backup_file\}"/);
  assert.match(backupScript, /sha256sum "\$\{backup_file\}" > "\$\{backup_file\}\.sha256"/);
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

test("eGovFrame control-plane 선택 적용 gate는 허용 영역과 no-go 경계를 고정한다", () => {
  const gate = readJson("backend/quality/egovframe-control-plane-gate.json");
  const build = read("backend/build.gradle");
  const lockfile = read("backend/gradle.lockfile");
  const readme = read("README.md");

  assert.equal(gate.schemaVersion, 1);
  assert.equal(gate.gateId, "egovframe-control-plane-adoption");
  assert.equal(gate.framework.egovFrame, "5.0.0");
  assert.match(gate.framework.springBoot, /^3\.5\./);
  assert.deepEqual(gate.allowedProductionSurface, [
    "backend_admin_operator_pages",
    "data_collection_batch_control_plane",
    "operations_logging_properties_ids",
  ]);
  assert.deepEqual(gate.noGoSurface, [
    "flutter_mobile_runtime",
    "ordinary_mobile_api",
    "realtime_hot_path",
    "token_or_crypto_security_boundary",
    "domain_application_public_json_contracts",
  ]);
  assert.equal(gate.pocDecision.egovframeBatCore.status, "deferred_until_dependency_convergence_and_local_mirror");
  assert.equal(gate.pocDecision.egovframeBatCore.currentImplementation, "spring_batch_control_plane_job");
  assert.equal(gate.pocDecision.fdlLogging.status, "classpath_verified_control_plane_only");
  assert.equal(gate.pocDecision.fdlProperty.status, "not_enabled_for_production");
  assert.equal(gate.pocDecision.fdlIdgnr.status, "not_enabled_for_production");
  assert.equal(gate.pocDecision.pslDataaccess.status, "forbidden_until_poc_passes");
  assert.equal(gate.pocDecision.fdlAccess.status, "forbidden_until_poc_passes");
  assert.equal(gate.pocDecision.fdlExcel.status, "forbidden_until_poc_passes");

  assert.match(build, /implementation 'org\.egovframe\.rte:egovframe-rte-ptl-mvc'/);
  assert.match(build, /implementation 'org\.springframework\.boot:spring-boot-starter-batch'/);
  assert.doesNotMatch(build, /egovframe-rte-bat-core/);
  assert.doesNotMatch(build, /egovframe-rte-fdl-property/);
  assert.doesNotMatch(build, /egovframe-rte-fdl-idgnr/);
  assert.doesNotMatch(build, /egovframe-rte-psl-dataaccess/);
  assert.doesNotMatch(build, /egovframe-boot-starter-(access|crypto|security)/);
  assert.doesNotMatch(build, /egovframe-rte-fdl-excel/);
  assert.match(lockfile, /^org\.egovframe\.rte:egovframe-rte-fdl-logging:5\.0\.0=/m);

  assert.match(readme, /eGovFrame은 backend control-plane에만 선택 적용한다/);
  assert.match(readme, /Flutter mobile runtime, ordinary mobile API, realtime hot path, token\/crypto boundary/);
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
	assert.match(messages, /^validation\.field-verification\.status\.required=현장 확인 상태를 선택해야 합니다\.$/m);
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
  const jdbcTransitMasterOverride = read(
    "backend/src/main/java/com/easysubway/transit/adapter/out/persistence/JdbcTransitMasterOverrideRepository.java",
  );
  const applicationYml = read("backend/src/main/resources/application.yml");
  const applicationProdYml = read("backend/src/main/resources/application-prod.yml");

  assert.ok(files.length >= 1, "InMemory repository files must be discovered");
  for (const file of files) {
    const source = read(file);
    assert.match(source, /import org\.springframework\.context\.annotation\.Profile;/, `${file} must import Profile`);
    if (file.endsWith("InMemoryRouteSearchRepository.java")) {
      assert.match(
        source,
        /@Repository\s+@Profile\("!prod & !staging & !release & !prod-like"\)/,
        `${file} must be disabled on prod-like profiles`,
      );
    } else {
      assert.match(source, /@Repository\s+@Profile\("!prod & !staging & !release & !prod-like"\)/, `${file} must be disabled on prod profile`);
    }
  }
  assert.match(applicationYml, /group:\s*\n\s*staging:\s*prod\s*\n\s*release:\s*prod\s*\n\s*prod-like:\s*prod/);
  assert.match(readinessConfiguration, /@Profile\("prod \| staging \| release \| prod-like"\)/);
  assert.match(readinessConfiguration, /HealthIndicator/);
  assert.match(readinessConfiguration, /Status\.DOWN/);
  assert.match(readinessConfiguration, /productionReadinessHealthIndicator/);
  assert.doesNotMatch(readinessConfiguration, /BeanFactoryPostProcessor/);
  assert.doesNotMatch(readinessConfiguration, /BeanCreationException/);
  assert.doesNotMatch(readinessConfiguration, /운영 영속 저장소 구현이 필요합니다\./);
  assert.doesNotMatch(unavailableTransitMaster, /@Repository/);
  assert.doesNotMatch(unavailableTransitMaster, /@Profile\("prod \| staging \| release \| prod-like"\)/);
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
  assert.match(jdbcTransitMasterOverride, /@Repository\s+@Profile\("prod \| staging \| release \| prod-like"\)/);
  assert.match(jdbcTransitMasterOverride, /extends UnavailableTransitMasterRepository/);
  assert.match(jdbcTransitMasterOverride, /implements[\s\S]*RollbackTransitMasterOverridePort/);
  assert.match(jdbcTransitMasterOverride, /transit_master_overrides/);
  assert.match(jdbcTransitMasterOverride, /transit_master_override_audits/);
  assert.match(jdbcTransitMasterOverride, /MasterDataCapabilityStatus\.UP[\s\S]*true,[\s\S]*true/);
  assert.match(jdbcTransitMasterOverride, /MasterDataCapabilityStatus\.READ_ONLY[\s\S]*true,[\s\S]*false/);
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

test("관리자 플랫폼 전환 계약은 shadow rollout과 legacy fallback 제거 조건을 고정한다", () => {
  const applicationYml = read("backend/src/main/resources/application.yml");
  const applicationProdYml = read("backend/src/main/resources/application-prod.yml");
  const transitionProperties = read(
    "backend/src/main/java/com/easysubway/admin/transition/AdminPlatformTransitionProperties.java",
  );
  const transitionConfiguration = read(
    "backend/src/main/java/com/easysubway/admin/transition/AdminPlatformTransitionConfiguration.java",
  );
  const transitionTest = read(
    "backend/src/test/java/com/easysubway/admin/transition/AdminPlatformTransitionPropertiesTest.java",
  );
  const security = read("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java");
  const securityTest = read("backend/src/test/java/com/easysubway/common/security/SecurityConfigTest.java");
  const postgresAdminMigrations = [
    "backend/src/main/resources/db/migration/postgresql/V10__admin_rbac_menu.sql",
    "backend/src/main/resources/db/migration/postgresql/V11__admin_audit_events.sql",
    "backend/src/main/resources/db/migration/postgresql/V12__admin_batch_operation_permission.sql",
    "backend/src/main/resources/db/migration/postgresql/V13__admin_common_code_incident.sql",
    "backend/src/main/resources/db/migration/postgresql/V15__admin_report_photo_read_permission.sql",
  ].map(read).join("\n");
  const h2AdminMigrations = [
    "backend/src/main/resources/db/migration/h2/V10__admin_rbac_menu.sql",
    "backend/src/main/resources/db/migration/h2/V11__admin_audit_events.sql",
    "backend/src/main/resources/db/migration/h2/V12__admin_batch_operation_permission.sql",
    "backend/src/main/resources/db/migration/h2/V13__admin_common_code_incident.sql",
    "backend/src/main/resources/db/migration/h2/V15__admin_report_photo_read_permission.sql",
  ].map(read).join("\n");

  assert.match(applicationYml, /platform-transition:\s*\n\s*stage: \$\{EASYSUBWAY_ADMIN_PLATFORM_TRANSITION_STAGE:shadow\}/);
  assert.match(applicationYml, /identity-store: \$\{EASYSUBWAY_ADMIN_IDENTITY_STORE_ENABLED:true\}/);
  assert.match(applicationYml, /rbac-shadow: \$\{EASYSUBWAY_ADMIN_RBAC_SHADOW_ENABLED:true\}/);
  assert.match(applicationYml, /rbac-enforcement: \$\{EASYSUBWAY_ADMIN_RBAC_ENFORCEMENT_ENABLED:false\}/);
  assert.match(applicationYml, /audit-shadow: \$\{EASYSUBWAY_ADMIN_AUDIT_SHADOW_ENABLED:true\}/);
  assert.match(applicationYml, /audit-enforcement: \$\{EASYSUBWAY_ADMIN_AUDIT_ENFORCEMENT_ENABLED:false\}/);
  assert.match(applicationYml, /legacy-env-admin-fallback: \$\{EASYSUBWAY_ADMIN_LEGACY_ENV_FALLBACK_ENABLED:true\}/);
  assert.match(applicationYml, /break-glass-bootstrap: \$\{EASYSUBWAY_ADMIN_BREAK_GLASS_BOOTSTRAP_ENABLED:true\}/);
  assert.match(applicationYml, /role-seed-required: \$\{EASYSUBWAY_ADMIN_ROLE_SEED_REQUIRED:true\}/);
  assert.match(applicationYml, /admin_rbac_shadow_denial_total/);
  assert.match(applicationYml, /admin_audit_shadow_missing_total/);
  assert.match(applicationYml, /all production admins have admin_users rows with role seed/);
  assert.match(applicationYml, /break-glass bootstrap account was rotated after first use/);
  assert.match(applicationYml, /restore EASYSUBWAY_ADMIN_USERNAME and EASYSUBWAY_ADMIN_PASSWORD/);
  assert.match(applicationYml, /CREDENTIAL_ROTATION_REQUIRED/);
  assert.match(applicationYml, /admin_role_permissions first/);
  assert.match(applicationYml, /persistent admin_users seed is verified/);
  assert.match(applicationYml, /disable rbac-enforcement and audit-enforcement/);
  assert.match(applicationYml, /RBAC shadow denials are untriaged/);
  assert.match(applicationYml, /role or account seed is missing in prod/);
  assert.match(applicationProdYml, /blocker-mode: \$\{EASYSUBWAY_ADMIN_PLATFORM_RELEASE_BLOCKER_MODE:fail\}/);

  assert.match(transitionConfiguration, /@EnableConfigurationProperties\(AdminPlatformTransitionProperties\.class\)/);
  assert.match(transitionProperties, /@ConfigurationProperties\(prefix = "easysubway\.admin\.platform-transition"\)/);
  assert.match(transitionProperties, /enum Stage[\s\S]*SHADOW,[\s\S]*ENFORCE,[\s\S]*LEGACY_DISABLED/);
  assert.match(transitionProperties, /enum BlockerMode[\s\S]*WARN,[\s\S]*FAIL/);
  assert.match(transitionProperties, /new Flags\(null, null, null, null, null, null, null, null\)/);
  assert.match(transitionProperties, /record LegacyEnvAdminFallback/);
  assert.match(transitionProperties, /record BreakGlass/);
  assert.match(transitionProperties, /record Seed/);
  assert.match(transitionProperties, /record Rollback/);
  assert.match(transitionProperties, /record ReleaseGate/);
  assert.match(transitionTest, /defaultsKeepShadowModeAndLegacyFallback/);
  assert.match(transitionTest, /transitionStageAndEnforcementFlagsCanBeOverridden/);

  assert.match(security, /validateProdAdminCredentials/);
  assert.match(security, /validateBreakGlassCredentials/);
  assert.match(security, /disableStaleBootstrapIdentities/);
  assert.match(securityTest, /prodProfileFailsWhenAdminCredentialsAreMissing/);
  assert.match(securityTest, /removedBootstrapIdentitiesAreDisabledOnStartup/);
  assert.match(securityTest, /breakGlassAuthRecordsReasonAndRequiresCredentialRotation/);

  for (const permission of [
    "admin.view",
    "admin.report.review",
    "admin.report.photo.read",
    "admin.master.edit",
    "admin.field.operate",
    "admin.data.operate",
    "admin.security.audit",
    "admin.security.admin",
    "admin.audit.read",
    "admin.privacy-log.read",
    "admin.batch.retry",
    "admin.operations.manage",
  ]) {
    assert.match(postgresAdminMigrations, new RegExp(escapeRegExp(permission)));
    assert.match(h2AdminMigrations, new RegExp(escapeRegExp(permission)));
  }
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
	assert.match(
		quality,
		/LEVEL_1\("정보 확인 중", "일부 정보는 확인 중이에요", DataQualitySeverity\.NEEDS_BASE_DATA, 40, "일부 정보는 확인 중이에요"\)/,
	);
	assert.match(
		quality,
		/LEVEL_2\("시설 정보 있음", "시설 정보를 함께 볼 수 있어요", DataQualitySeverity\.NEEDS_ROUTE_VERIFICATION, 60, "쉬운 길 확인이 더 필요해요"\)/,
	);
	assert.match(
		quality,
		/LEVEL_3\("쉬운 길 안내 가능", "쉬운 길 안내를 볼 수 있어요", DataQualitySeverity\.NEEDS_LIVE_STATUS, 80, "고장·공사 소식 확인이 필요해요"\)/,
	);
	assert.match(
		quality,
		/LEVEL_4\("고장·공사 반영", "고장·공사 소식이 반영됐어요", DataQualitySeverity\.VERIFIED, 100, ""\)/,
	);
  assert.match(quality, /searchSortPriority\(\)/);
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
  assert.match(workflow, /EASYSUBWAY_DATAPACK_IMPORTED_FIXTURE=/);
  assert.match(workflow, /EASYSUBWAY_DATAPACK_PRODUCTION_REVIEWED_FIXTURE=/);
  assert.match(workflow, /EASYSUBWAY_DATAPACK_BUILD_FIXTURE/);
  assert.match(workflow, /tools\/datapack\/import-official-sources\.mjs/);
  assert.match(workflow, /tools\/datapack\/inputs\/capital-pilot-production-source-input\.json/);
  assert.match(workflow, /tools\/datapack\/apply-admin-review-overrides\.mjs/);
  assert.match(workflow, /--fixture tools\/datapack\/fixtures\/catalog-fixture\.json/);
  assert.match(workflow, /--fixture "\$\{EASYSUBWAY_DATAPACK_IMPORTED_FIXTURE\}"/);
  assert.match(workflow, /--overrides tools\/datapack\/fixtures\/admin-review-overrides\.json/);
  assert.match(workflow, /--fixture "\$\{EASYSUBWAY_DATAPACK_BUILD_FIXTURE\}"/);
  assert.doesNotMatch(workflow, /transit_master_overrides/);
  assert.match(script, /datapack-manual-override-ledger/);
  assert.match(script, /manual_overrides/);
  assert.match(script, /facilityStatusUpdates/);
  assert.match(script, /facilityStatusUpdates\.facilityId was not found in fixture/);
  assert.match(script, /adminReviewOverrideCount/);
  assert.match(datapackTest, /승인된 관리자 검수 결과는 다음 data pack fixture 시설 상태에 반영된다/);
  assert.match(datapackTest, /legacy transit_master_overrides 입력을 거부한다/);
});

test("관리자 v3 공통 shell은 접근성 chrome과 inline style 제한을 유지한다", () => {
  const shellFragment = read("backend/src/main/resources/templates/admin/fragments/shell.html");
  const formErrorsFragment = read("backend/src/main/resources/templates/admin/fragments/form-errors.html");
  const paginationFragment = read("backend/src/main/resources/templates/admin/fragments/pagination.html");
  const errorTemplate = read("backend/src/main/resources/templates/admin/error.html");
  const adminCss = read("backend/src/main/resources/static/css/admin-v3.css");
  const navigationAdvice = read("backend/src/main/java/com/easysubway/admin/navigation/AdminNavigationAdvice.java");
  const envExample = read(".env.example");
  const backendEnvAllowlist = read("tools/deploy/backend-app-env.allowlist");
  const deployBackendScript = read("tools/deploy/deploy-backend.sh");
  const adminTemplateFiles = execFileSync("git", [
    "ls-files",
    "backend/src/main/resources/templates/admin/*.html",
    "backend/src/main/resources/templates/admin/**/*.html",
  ], {
    cwd: root,
    encoding: "utf8",
  }).trim().split("\n").filter(Boolean);

  assert.match(shellFragment, /th:fragment="sidebar\(active\)"/);
  assert.match(shellFragment, /th:fragment="skipLink"/);
  assert.match(shellFragment, /th:fragment="topbar"/);
  assert.match(shellFragment, /class="skip-link" href="#admin-content"/);
  assert.match(shellFragment, /th:fragment="contentStart"/);
  assert.match(shellFragment, /id="admin-content"/);
  assert.match(shellFragment, /admin-env-badge/);
  assert.match(shellFragment, /revision/);
  assert.match(shellFragment, /master data/);
  assert.match(shellFragment, /th:action="@\{\/admin\/logout\}"/);
  assert.match(shellFragment, /aria-label="관리자 로그아웃"/);
  assert.match(shellFragment, /th:fragment="flash"/);
  assert.match(shellFragment, /<output[\s\S]*th:fragment="flash"/);
  assert.doesNotMatch(shellFragment, /role="status"/);
  assert.match(shellFragment, /th:fragment="status\(text, tone\)"/);
  assert.match(errorTemplate, /role="alert"/);
  assert.match(errorTemplate, /aria-labelledby="admin-error-title"/);
  assert.match(errorTemplate, /id="admin-error-title"/);
  assert.match(formErrorsFragment, /role="alert"/);
  assert.match(formErrorsFragment, /aria-labelledby="form-error-summary-title"/);
  assert.match(formErrorsFragment, /id="form-error-summary-title"/);
  assert.match(paginationFragment, /aria-current=\$\{pageLink\.current \? 'page' : null\}/);
  assert.match(adminCss, /\.admin-v3 a:focus-visible/);
  assert.match(adminCss, /outline: 3px solid #ffbf47/);
  assert.match(adminCss, /\.admin-topbar-row/);
  assert.match(adminCss, /\.admin-main[\s\S]*min-width: 0[\s\S]*overflow-x: auto/);
  assert.match(adminCss, /\.admin-sidebar[\s\S]*overflow-y: auto/);
  assert.match(adminCss, /\.admin-v3 table[\s\S]*min-width: 620px/);
  assert.match(adminCss, /\.admin-v3 section,[\s\S]*\.admin-card[\s\S]*overflow-x: auto/);
  assert.match(navigationAdvice, /@ModelAttribute\("adminShell"\)/);
  assert.match(navigationAdvice, /return "PRODUCTION"/);
  assert.match(navigationAdvice, /return "STAGING"/);
  assert.match(navigationAdvice, /environment\.getProperty\("easysubway\.admin\.revision", "local"\)/);
  assert.match(navigationAdvice, /environment\.getProperty\("easysubway\.admin\.master-data-version", "unknown"\)/);
  assert.match(envExample, /EASYSUBWAY_ADMIN_REVISION=local/);
  assert.match(envExample, /EASYSUBWAY_ADMIN_MASTER_DATA_VERSION=unknown/);
  assert.match(backendEnvAllowlist, /^EASYSUBWAY_ADMIN_REVISION$/m);
  assert.match(backendEnvAllowlist, /^EASYSUBWAY_ADMIN_MASTER_DATA_VERSION$/m);
  assert.match(deployBackendScript, /ensure_backend_env_value EASYSUBWAY_ADMIN_REVISION "\$\{DEPLOY_SHA\}"/);
  assert.match(deployBackendScript, /ensure_backend_env_value EASYSUBWAY_ADMIN_MASTER_DATA_VERSION "\$\{DEPLOY_SHA\}"/);

  const adminPageFiles = adminTemplateFiles.filter((file) =>
    !file.includes("/fragments/") && !file.endsWith("/login.html")
  );

  for (const file of adminPageFiles) {
    const source = read(file);
    assert.match(source, /class="admin-shell"/, `${file} must use the shared admin shell`);
    assert.match(source, /<main class="admin-main">/, `${file} must keep the topbar and page content in main`);
    assert.match(source, /admin\/fragments\/shell :: skipLink/, `${file} must render skip link before the shell`);
    assert.match(source, /admin\/fragments\/shell :: topbar/, `${file} must render the common topbar`);
    assert.match(source, /admin\/fragments\/shell :: contentStart/, `${file} must render a skip-link target after topbar`);
    assert.ok(
      source.indexOf("admin/fragments/shell :: skipLink") < source.indexOf("class=\"admin-shell\""),
      `${file} must place the skip link before sidebar navigation`,
    );
    assert.ok(
      source.indexOf("admin/fragments/shell :: topbar") < source.indexOf("admin/fragments/shell :: contentStart"),
      `${file} must place the skip-link target after topbar`,
    );
  }

  const inlineStyleFiles = adminTemplateFiles
    .filter((file) => /<style\b/.test(read(file)))
    .sort();
  assert.deepEqual(inlineStyleFiles, [
    "backend/src/main/resources/templates/admin/collections/list.html",
    "backend/src/main/resources/templates/admin/facilities/list.html",
    "backend/src/main/resources/templates/admin/notifications/push.html",
    "backend/src/main/resources/templates/admin/quality/dashboard.html",
    "backend/src/main/resources/templates/admin/reports/detail.html",
    "backend/src/main/resources/templates/admin/reports/list.html",
    "backend/src/main/resources/templates/admin/routes/feedback.html",
    "backend/src/main/resources/templates/admin/routes/searches.html",
    "backend/src/main/resources/templates/admin/stations/layouts.html",
    "backend/src/main/resources/templates/admin/usage/activity.html",
  ]);
});

test("관리자 E2E와 query budget 회귀 gate는 CI에서 직접 검증된다", () => {
  const e2eTest = read("backend/src/test/java/com/easysubway/admin/adapter/in/web/AdminE2EFlowTest.java");
  const accessibilityTest = read(
    "backend/src/test/java/com/easysubway/admin/adapter/in/web/AdminAccessibilitySmokeTest.java",
  );
  const securityConfig = read("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java");
  const adminPageRequest = read("backend/src/main/java/com/easysubway/common/web/pagination/AdminPageRequest.java");
  const reportPageRequest = read("backend/src/main/java/com/easysubway/report/application/port/in/FacilityReportPageRequest.java");
  const paginationTest = read("backend/src/test/java/com/easysubway/common/web/pagination/EgovPaginationViewTest.java");
  const readOnlyAdminTest = read(
    "backend/src/test/java/com/easysubway/transit/adapter/in/web/TransitReadOnlyAdminPageModelTest.java",
  );
  const listControllers = [
    "backend/src/main/java/com/easysubway/admin/audit/adapter/in/web/AdminAuditPageController.java",
    "backend/src/main/java/com/easysubway/admin/batch/adapter/in/web/AdminBatchPageController.java",
    "backend/src/main/java/com/easysubway/admin/operations/adapter/in/web/AdminOperationsPageController.java",
    "backend/src/main/java/com/easysubway/collection/adapter/in/web/DataCollectionAdminPageController.java",
    "backend/src/main/java/com/easysubway/report/adapter/in/web/FacilityReportAdminPageController.java",
  ];
  const jdbcRepositories = [
    "backend/src/main/java/com/easysubway/admin/audit/adapter/out/persistence/JdbcAdminAuditEventRepository.java",
    "backend/src/main/java/com/easysubway/admin/operations/adapter/out/persistence/JdbcAdminIncidentRepository.java",
    "backend/src/main/java/com/easysubway/collection/adapter/out/persistence/JdbcDataCollectionRunRepository.java",
    "backend/src/main/java/com/easysubway/report/adapter/out/persistence/JdbcFacilityReportRepository.java",
  ];

  assert.match(e2eTest, /class AdminE2EFlowTest/);
  assert.match(e2eTest, /formLogin\("\/admin\/login"\)/);
  assert.match(e2eTest, /post\("\/console\/admin\/logout"\)/);
  assert.match(e2eTest, /contextPath\("\/console"\)/);
  assert.match(e2eTest, /redirectedUrl\("\/console\/admin\/login\?logout"\)/);
  assert.match(e2eTest, /adminLoginLockoutAndLogoutFlow/);
  assert.match(e2eTest, /adminCoreOperationFlow/);
  assert.match(e2eTest, /adminErrorShellCoversForbiddenConflictAndValidation/);
  assert.match(e2eTest, /\/admin\/reports\/\{reportId\}\/page\/review/);
  assert.match(e2eTest, /\/admin\/facilities\/facility-sangnoksu-elevator-1\/page\/status/);
  assert.match(e2eTest, /\/admin\/batches\/transit-master-collection\/runs\/admin-e2e-failed-run\/retry/);
  assert.match(e2eTest, /\/admin\/audits\/privacy\/page/);
  assert.match(e2eTest, /role=\\"alert\\"/);
  assert.match(accessibilityTest, /class AdminAccessibilitySmokeTest/);
  assert.match(accessibilityTest, /adminPagesKeepAccessibleShell/);
  assert.match(accessibilityTest, /adminErrorAndValidationPagesExposeAlertSemantics/);
  assert.match(accessibilityTest, /href=\\"#admin-content\\"/);
  assert.match(accessibilityTest, /aria-label=\\"관리자 로그아웃\\"/);
  assert.match(accessibilityTest, /aria-labelledby=\\"form-error-summary-title\\"/);
  assert.match(securityConfig, /logoutUrl\("\/admin\/logout"\)/);
  assert.match(securityConfig, /request\.getContextPath\(\) \+ "\/admin\/login\?logout"/);
  assert.match(readOnlyAdminTest, /masterDataWritable/);
  assert.match(readOnlyAdminTest, /운영 마스터 데이터가 읽기 전용입니다\./);
  assert.match(adminPageRequest, /MAX_SIZE = 50/);
  assert.match(adminPageRequest, /limitForHasNext\(\)/);
  assert.match(reportPageRequest, /MAX_SIZE = 50/);
  assert.match(reportPageRequest, /limitForHasNext\(\)/);
  assert.match(paginationTest, /adminPageRequestCapsSizeAndOffset/);

  for (const file of listControllers) {
    const source = read(file);
    assert.match(source, /EgovPaginationView/, `${file} must render paginated admin lists`);
    assert.match(source, /(AdminPageRequest|FacilityReportPageRequest)\.of\(page, size\)/, `${file} must cap page size`);
    assert.doesNotMatch(source, /listRecent\(\s*\)|loadRecentRuns\(\s*\)|loadReportSummaries\(\s*status\s*\)/, `${file} must not call unbounded list loaders`);
  }

  for (const file of jdbcRepositories) {
    const source = read(file);
    assert.match(source, /LIMIT \?/, `${file} must keep SQL limit placeholders`);
    assert.match(source, /OFFSET \?/, `${file} must keep SQL offset placeholders`);
  }
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
  const adminPaginationFragment = read("backend/src/main/resources/templates/admin/fragments/pagination.html");
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
  assert.match(jdbcRepository, /@Profile\("prod \| staging \| release \| prod-like"\)/);
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
  assert.match(abuseControl, /easysubway\.report\.abuse-control\.store-mode/);
  assert.match(abuseControl, /maxCounterKeys/);
  assert.match(abuseControl, /usesReleaseBlockingLocalStore/);
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
  assert.match(prodConfig, /EASYSUBWAY_REPORT_ABUSE_STORE_MODE:local/);
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
  assert.doesNotMatch(adminReportDetailTemplate, /photoObjectKey|objectKey/);
  assert.match(adminReportDetailTemplate, /\/admin\/reports\/\{reportId\}\/photo\/thumbnail/);
  assert.match(adminReportListTemplate, /최근 24시간 신고/);
  assert.match(adminReportListTemplate, /신고 처리 시간/);
  assert.match(adminReportListTemplate, /처리 완료 신고 없음/);
  assert.match(adminReportListTemplate, /신고 목록 페이지/);
  assert.match(adminPaginationFragment, /page\.hasNext/);
  assert.match(security, /@Order\(1\)[\s\S]*?securityMatcher\("\/admin\/\*\*"\)/);
  assert.match(security, /securityMatcher\("\/admin\/\*\*"\)/);
  assert.match(security, /anyRequest\(\)\.hasAuthority\(AdminPermission\.ADMIN_VIEW\.authority\(\)\)/);
  assert.match(security, /adminSecurityFilterChain\([\s\S]*HttpSecurity http,[\s\S]*AdminOperatorAuditFilter auditFilter,[\s\S]*basicAuthEnabled/);
  assert.match(security, /adminSecurityFilterChain[\s\S]*addFilterAfter\(auditFilter, BasicAuthenticationFilter\.class\)/);
  assert.match(security, /@Order\(2\)[\s\S]*?securityMatcher\("\/operator\/\*\*"\)/);
  assert.match(security, /securityMatcher\("\/operator\/\*\*"\)/);
  assert.match(security, /anyRequest\(\)\.hasRole\("OPERATOR_ADMIN"\)/);
  assert.match(security, /operatorSecurityFilterChain\([\s\S]*HttpSecurity http,[\s\S]*AdminOperatorAuditFilter auditFilter,[\s\S]*basicAuthEnabled/);
  assert.match(security, /operatorSecurityFilterChain[\s\S]*addFilterAfter\(auditFilter, BasicAuthenticationFilter\.class\)/);
  assert.match(security, /@Order\(3\)[\s\S]*?reportSecurityFilterChain/);
  assert.doesNotMatch(security, /"\/api\/v1\/me"/);
  assert.match(security, /"\/api\/v1\/reports\/\*"/);
  assert.match(security, /"\/api\/v1\/reports\/\*\/confirm"/);
  assert.match(security, /@Order\(4\)[\s\S]*?publicSecurityFilterChain/);
  assert.match(
    security,
    /requestMatchers\([\s\S]*"\/api\/health"[\s\S]*"\/actuator\/health"[\s\S]*"\/actuator\/health\/liveness"[\s\S]*"\/actuator\/health\/readiness"[\s\S]*"\/actuator\/prometheus"[\s\S]*\)\.permitAll\(\)/,
  );
  assert.match(security, /@Order\(4\)[\s\S]*?anyRequest\(\)\.denyAll\(\)/);
  assert.match(security, /easysubway\.operator\.username/);
  assert.match(security, /easysubway\.operator\.password/);
  assert.match(security, /AdminIdentityRepository/);
  assert.match(security, /AdminIdentityUserDetailsService/);
  assert.match(security, /upsertBootstrap/);
  assert.match(security, /AdminIdentityRole\.OPERATOR_ADMIN/);
  assert.match(security, /easysubway\.admin\.break-glass\.username/);
  assert.match(security, /easysubway\.admin\.break-glass\.password/);
  assert.match(security, /easysubway\.admin\.break-glass\.reason/);
  assert.match(security, /AdminIdentityAuthMethod\.BREAK_GLASS/);
  assert.match(security, /validateOperatorCredentials/);
  assert.match(security, /validateBreakGlassCredentials/);
  assert.match(security, /validateDistinctAdminLoginIds/);
  assert.doesNotMatch(security, /publicSecurityFilterChain[\s\S]*?anyRequest\(\)\.permitAll\(\)/);
  assert.match(security, /httpBasic/);
  assert.match(security, /PasswordEncoder/);
  assert.match(security, /passwordEncoder\.encode\(adminPassword\)/);
  assert.match(security, /passwordEncoder\.encode\(operatorPassword\)/);
  assert.match(security, /AdminOperatorAuditFilter adminOperatorAuditFilter\(AdminAuditEventRepository auditEventRepository\)/);
  assert.match(security, /return new AdminOperatorAuditFilter\(auditEventRepository\)/);
  assert.match(adminOperatorAuditFilter, /extends OncePerRequestFilter/);
  assert.match(adminOperatorAuditFilter, /MUTATING_METHODS = Set\.of\("POST", "PUT", "PATCH", "DELETE"\)/);
  assert.match(adminOperatorAuditFilter, /path\.startsWith\("\/admin\/"\) \|\| path\.startsWith\("\/operator\/"\)/);
  assert.match(
    adminOperatorAuditFilter,
    /admin_operator_state_change_audit method=\{\} path=\{\} principal=\{\} roles=\{\} tenant=\{\} status=\{\} outcome=\{\} correlation_id=\{\}/,
  );
  assert.match(adminOperatorAuditFilter, /ROLE_OPERATOR_ADMIN/);
  assert.match(adminOperatorAuditFilter, /X-Correlation-Id/);
  assert.match(adminOperatorAuditFilter, /SUCCESS/);
  assert.match(adminOperatorAuditFilter, /FAILURE/);
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
  assert.match(reportController, /activeProfiles\.contains\("prod"\)[\s\S]*activeProfiles\.contains\("staging"\)[\s\S]*activeProfiles\.contains\("release"\)[\s\S]*activeProfiles\.contains\("prod-like"\)/);
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
  assert.match(uploadUrlSigner, /@Profile\("prod \| staging \| release \| prod-like"\)[\s\S]*ObjectStorageFacilityReportUploadUrlSigner/);
  assert.match(uploadUrlSigner, /AWS4-HMAC-SHA256/);
  assert.match(uploadUrlSigner, /X-Amz-Credential/);
  assert.match(uploadUrlSigner, /X-Amz-SignedHeaders/);
  assert.match(objectStorage, /@Profile\("prod \| staging \| release \| prod-like"\)/);
  assert.match(objectStorage, /implements[\s\S]*StoreFacilityReportPhotoPort,[\s\S]*LoadFacilityReportPhotoPort,[\s\S]*DeleteFacilityReportPhotoPort,[\s\S]*StoreFacilityReportUploadedPhotoPort/);
  assert.match(objectStorage, /HttpRequest signedRequest\(String method, String objectKey, String contentType, byte\[] body\)/);
  assert.match(applicationProd, /receipt-token-pepper: \$\{EASYSUBWAY_REPORT_RECEIPT_PEPPER:\$\{EASYSUBWAY_REPORT_RECEIPT_TOKEN_PEPPER:\}\}/);
  assert.match(applicationProd, /intent-signing-key: \$\{EASYSUBWAY_REPORT_UPLOAD_INTENT_SIGNING_KEY:\$\{EASYSUBWAY_REPORT_RECEIPT_PEPPER:\$\{EASYSUBWAY_REPORT_RECEIPT_TOKEN_PEPPER:\}\}\}/);
  assert.match(applicationProd, /object-storage-endpoint: \$\{EASYSUBWAY_REPORT_OBJECT_STORAGE_INTERNAL_ENDPOINT:\}/);
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
  assert.match(jdbcRepository, /@Profile\("prod \| staging \| release \| prod-like"\)/);
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
  assert.match(jdbcRepository, /@Profile\("prod \| staging \| release \| prod-like"\)/);
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
  assert.match(jdbcRepository, /@Profile\("prod \| staging \| release \| prod-like"\)/);
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
  assert.match(jdbcRepository, /@Profile\("prod \| staging \| release \| prod-like"\)/);
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
  assert.match(jdbcRepository, /@Profile\("prod \| staging \| release \| prod-like"\)/);
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
  assert.match(jdbcRepository, /@Profile\("prod \| staging \| release \| prod-like"\)/);
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
  const collectionRunStepsPostgresSchema = read(
    "backend/src/main/resources/db/migration/postgresql/V8__data_collection_run_steps.sql",
  );
  const run = read("backend/src/main/java/com/easysubway/collection/domain/DataCollectionRun.java");
  const runStep = read("backend/src/main/java/com/easysubway/collection/domain/DataCollectionRunStep.java");
  const stepStatus = read("backend/src/main/java/com/easysubway/collection/domain/DataCollectionStepStatus.java");
  const source = read("backend/src/main/java/com/easysubway/collection/domain/DataCollectionSource.java");
  const status = read("backend/src/main/java/com/easysubway/collection/domain/DataCollectionStatus.java");
  const invalidCollection = read("backend/src/main/java/com/easysubway/collection/domain/InvalidDataCollectionException.java");
  const useCase = read("backend/src/main/java/com/easysubway/collection/application/port/in/DataCollectionUseCase.java");
  const command = read("backend/src/main/java/com/easysubway/collection/application/port/in/RunDataCollectionCommand.java");
  const loadRunPort = read("backend/src/main/java/com/easysubway/collection/application/port/out/LoadDataCollectionRunPort.java");
  const saveRunPort = read("backend/src/main/java/com/easysubway/collection/application/port/out/SaveDataCollectionRunPort.java");
  const fetchSourcePort = read(
    "backend/src/main/java/com/easysubway/collection/application/port/out/FetchTransitMasterCollectionSourcePort.java",
  );
  const sourceSnapshot = read(
    "backend/src/main/java/com/easysubway/collection/application/port/out/TransitMasterCollectionSnapshot.java",
  );
  const service = read("backend/src/main/java/com/easysubway/collection/application/service/DataCollectionService.java");
  const recorder = read("backend/src/main/java/com/easysubway/collection/application/service/DataCollectionRunRecorder.java");
  const sourceAdapter = read(
    "backend/src/main/java/com/easysubway/collection/adapter/out/source/LoadedTransitMasterCollectionSourceAdapter.java",
  );
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
  assert.match(collectionRunStepsPostgresSchema, /CREATE TABLE IF NOT EXISTS data_collection_run_steps/);
  assert.match(collectionRunStepsPostgresSchema, /step_name VARCHAR\(40\) NOT NULL/);
  assert.match(collectionRunStepsPostgresSchema, /artifact_reference VARCHAR\(1000\)/);
  assert.match(collectionRunStepsPostgresSchema, /checksum VARCHAR\(64\)/);
  assert.match(batchPostgresSchema, /ALTER TABLE data_collection_runs[\s\S]*ADD COLUMN IF NOT EXISTS retryable BOOLEAN NOT NULL DEFAULT FALSE/);
  assert.match(batchPostgresSchema, /ALTER TABLE data_collection_runs[\s\S]*ADD COLUMN IF NOT EXISTS operator_action VARCHAR\(500\) NOT NULL DEFAULT/);
  assert.match(batchPostgresSchema, /CREATE INDEX IF NOT EXISTS idx_data_collection_runs_started_at/);
  assert.match(run, /record DataCollectionRun/);
  assert.match(run, /requestedBy/);
  assert.match(run, /collectedCount/);
  assert.match(run, /retryable/);
  assert.match(run, /operatorAction/);
  assert.match(run, /List<DataCollectionRunStep> steps/);
  assert.match(run, /status == DataCollectionStatus\.COMPLETED[\s\S]*completedAt == null/);
  assert.match(run, /status == DataCollectionStatus\.FAILED[\s\S]*failureMessage/);
  assert.match(run, /status != DataCollectionStatus\.FAILED && retryable/);
  assert.match(runStep, /record DataCollectionRunStep/);
  assert.match(runStep, /inputSource/);
  assert.match(runStep, /artifactReference/);
  assert.match(runStep, /checksum/);
  assert.match(runStep, /recordCount/);
  assert.match(stepStatus, /COMPLETED/);
  assert.match(stepStatus, /FAILED/);
  assert.match(stepStatus, /SKIPPED/);
  assert.match(stepStatus, /MANUAL_REQUIRED/);
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
  assert.match(fetchSourcePort, /interface FetchTransitMasterCollectionSourcePort/);
  assert.match(fetchSourcePort, /TransitMasterCollectionSnapshot fetch\(\)/);
  assert.match(sourceSnapshot, /record TransitMasterCollectionSnapshot/);
  assert.match(sourceSnapshot, /inputSource/);
  assert.match(sourceSnapshot, /artifactReference/);
  assert.match(sourceSnapshot, /checksum/);
  assert.match(service, /implements DataCollectionUseCase/);
  assert.match(service, /JobLauncher/);
  assert.match(service, /transitMasterCollectionJob/);
  assert.match(service, /InvalidDataCollectionException\("데이터 수집 배치를 실행하지 못했습니다\.", exception\)/);
  assert.match(service, /loadRun\(runId\)/);
  assert.match(service, /loadLatestCompletedRun\(source\)/);
  assert.match(recorder, /FetchTransitMasterCollectionSourcePort/);
  assert.match(recorder, /recordTransitMasterRun/);
  assert.match(recorder, /"FETCH"/);
  assert.match(recorder, /"ARCHIVE"/);
  assert.match(recorder, /"VALIDATE"/);
  assert.match(recorder, /"PARSE"/);
  assert.match(recorder, /"DIFF"/);
  assert.match(recorder, /"STAGE"/);
  assert.match(recorder, /MANUAL_REQUIRED/);
  assert.match(recorder, /catch \(RuntimeException exception\)/);
  assert.match(recorder, /DataCollectionStatus\.FAILED/);
  assert.match(recorder, /COMPLETED_OPERATOR_ACTION/);
  assert.match(recorder, /FAILED_OPERATOR_ACTION/);
  assert.match(sourceAdapter, /implements FetchTransitMasterCollectionSourcePort/);
  assert.match(sourceAdapter, /LoadTransitMasterPort/);
  assert.match(sourceAdapter, /checksumPayload/);
  assert.match(sourceAdapter, /appendRecords/);
  assert.match(sourceAdapter, /\.sorted\(\)/);
  assert.match(sourceAdapter, /MessageDigest\.getInstance\("SHA-256"\)/);
  assert.match(repository, /implements[\s\S]*LoadDataCollectionRunPort[\s\S]*SaveDataCollectionRunPort/);
  assert.match(repository, /@Profile\("!prod & !staging & !release & !prod-like"\)/);
  assert.match(repository, /loadRun\(String runId\)/);
  assert.match(repository, /loadLatestCompletedRun\(DataCollectionSource source\)/);
  assert.match(jdbcRepository, /@Profile\("prod \| staging \| release \| prod-like"\)/);
  assert.match(jdbcRepository, /implements[\s\S]*LoadDataCollectionRunPort[\s\S]*SaveDataCollectionRunPort/);
  assert.match(jdbcRepository, /JdbcTemplate/);
  assert.match(jdbcRepository, /INSERT INTO data_collection_runs/);
  assert.match(jdbcRepository, /INSERT INTO data_collection_run_steps/);
  assert.match(jdbcRepository, /DELETE FROM data_collection_run_steps WHERE run_id = \?/);
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
  assert.match(controller, /DataCollectionRunStepResponse/);
  assert.match(adminController, /retryableLabel/);
  assert.match(adminController, /DataCollectionRunStepRow/);
  assert.match(adminTemplate, />재시도</);
  assert.match(adminTemplate, />단계</);
  assert.match(adminTemplate, />다음 행동</);
  assert.match(batchConfig, /new JobBuilder\(JOB_NAME, jobRepository\)/);
  assert.match(batchConfig, /STEP_NAME = "recordTransitMasterCollectionStep"/);
  assert.match(batchConfig, /new StepBuilder\(STEP_NAME, jobRepository\)/);
  assert.doesNotMatch(batchConfig, /markerStep/);
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
  assert.match(inMemoryHistoryRepository, /@Repository\s+@Profile\("!prod & !staging & !release & !prod-like"\)/);
  assert.match(inMemoryHistoryRepository, /implements FieldVerificationChangeHistoryRepository/);
  assert.match(jdbcHistoryRepository, /@Repository\s+@Profile\("prod \| staging \| release \| prod-like"\)/);
  assert.match(jdbcHistoryRepository, /JdbcTemplate/);
  assert.match(jdbcHistoryRepository, /INSERT INTO field_verification_change_history/);
  assert.match(jdbcHistoryRepository, /ORDER BY changed_at DESC, history_id ASC/);
  assert.match(service, /SANGNOKSU_STATION_ID = "station-sangnoksu"/);
  assert.doesNotMatch(service, /historiesByStationId/);
  assert.match(service, /FieldVerificationChangeHistoryRepository/);
  assert.match(service, /field-verification-sangnoksu-2026-06/);
  assert.match(service, /SADANG_STATION_ID = "station-sadang"/);
  assert.match(service, /field-verification-sadang-2026-06/);
	assert.match(service, /주요 환승역 현장 확인 확대 기준선/);
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
  assert.match(inMemorySessionRepository, /@Repository\s+@Profile\("!prod & !staging & !release & !prod-like"\)/);
  assert.match(inMemorySessionRepository, /implements FieldVerificationSessionRepository/);
  assert.match(inMemorySessionRepository, /LinkedHashMap/);
  assert.match(jdbcSessionRepository, /@Repository\s+@Profile\("prod \| staging \| release \| prod-like"\)/);
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
  const operatorAssembler = read("backend/src/main/java/com/easysubway/operator/adapter/in/web/OperatorAccessibilityReportAssembler.java");
  const mobileStationSearch = read("apps/mobile/lib/station_search.dart");
  const mobileRouteRepository = read("apps/mobile/lib/features/routes/data/local_route_repository.dart");
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
  assert.match(service, /level\.accessibilityScore\(\)/);
  assert.match(service, /level\.scoreReason\(\)/);
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
  assert.match(adminController, /level\.label\(\)/);
  assert.match(adminController, /level\.description\(\)/);
  assert.match(operatorAssembler, /level\.label\(\)/);
  assert.match(operatorAssembler, /level\.description\(\)/);
  assert.doesNotMatch(adminController, /case LEVEL_4 -> "제보 필요"/);
  assert.doesNotMatch(operatorAssembler, /case LEVEL_4 -> "제보 필요"/);
  assert.doesNotMatch(adminController, /listReports\(null\)/);
  assert.match(adminController, /isVerifiedReportStatus/);
  assert.match(adminTemplate, /지역별 데이터 품질/);
  assert.match(adminTemplate, /갱신 지연 시설/);
  assert.match(adminTemplate, /시설 상태 갱신 지연/);
	assert.match(adminTemplate, /사용자 제보 확인률/);
	assert.match(adminTemplate, /제보 확인률/);
  assert.match(adminTemplate, /역별 접근성 점수/);
  assert.match(adminTemplate, /접근성 점수/);
  assert.match(adminTemplate, /접근성 개선 우선순위/);
	assert.match(adminTemplate, /우선순위/);
  assert.match(adminTemplate, /반복 고장 신고 시설/);
  assert.match(adminTemplate, /고장 신고 수/);
	assert.match(adminTemplate, /정보 확인 중/);
	assert.match(adminTemplate, /고장·공사 반영/);
  assert.match(mobileStationSearch, /'LEVEL_1' => '일부 정보는 확인 중이에요'/);
  assert.match(mobileStationSearch, /'LEVEL_2' => '시설 정보를 함께 볼 수 있어요'/);
  assert.match(mobileStationSearch, /'LEVEL_3' => '쉬운 길 안내를 볼 수 있어요'/);
  assert.match(mobileStationSearch, /'LEVEL_4' => '고장·공사 소식이 반영됐어요'/);
  assert.match(mobileRouteRepository, /'LEVEL_1' => 40/);
  assert.match(mobileRouteRepository, /'LEVEL_2' => 60/);
  assert.match(mobileRouteRepository, /'LEVEL_3' => 80/);
  assert.match(mobileRouteRepository, /'LEVEL_4' => 100/);
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
  assert.match(repository, /@Profile\("prod \| staging \| release \| prod-like"\)/);
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
  assert.match(repository, /@Profile\("prod \| staging \| release \| prod-like"\)/);
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
  assert.match(repository, /@Profile\("!prod & !staging & !release & !prod-like"\)/);
  assert.match(jdbcRepository, /@Profile\("prod \| staging \| release \| prod-like"\)/);
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
  assert.match(onboardingAppFlowTest, /첫 실행 앱은 온보딩 알림 권한 실패 도움말을 안내한다/);
  assert.match(onboardingAppFlowTest, /첫 실행 앱은 알림 설정이 꺼진 구성에서 온보딩 알림 권한을 요청하지 않는다/);
  assert.match(onboardingAppFlowTest, /첫 실행 앱은 알림 권한 제공자가 직접 주입되면 온보딩 알림 권한을 요청한다/);
  assert.match(onboardingAppFlowTest, /앱은 저장된 온보딩 설정으로 홈을 바로 보여준다/);
  assert.match(onboardingAppFlowTest, /앱은 온보딩 저장소를 읽지 못하면 다시 설정을 고르게 한다/);
  assert.match(stationSearch, /stationSearchFailureNextAction/);
  assert.match(stationSearch, /역명으로 검색하면 현재 위치를 쓰지 않아도 계속 이용할 수 있습니다\./);
  assert.match(widgetTest, /역명으로 검색하면 현재 위치를 쓰지 않아도 계속 이용할 수 있습니다\./);
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
  assert.match(widgetTest, /상록수역, 수도권 4호선, 경의중앙선, 수도권, 일부 정보는 확인 중이에요/);
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
  assert.match(widgetTest, /상록수역 자세한 안내[\s\S]*지도 위치/);
  assert.match(widgetTest, /1번 출구, 엘리베이터 연결, 계단 없는 이동 가능[\s\S]*지도 위치/);
  assert.match(facilityReport, /Future<FacilityReportResult> getReport\(String reportId\)/);
  assert.match(facilityReport, /\/api\/v1\/reports\/\$\{Uri\.encodeComponent\(trimmedReportId\)\}/);
  assert.match(facilityReport, /refreshCurrentReport/);
  assert.match(facilityReport, /제보 진행 상황 확인 중/);
  assert.match(facilityReport, /제보 번호/);
  assert.match(facilityReport, /facilityReportRefreshButton/);
  assert.match(facilityReport, /facilityReportFailureNextAction/);
  assert.match(facilityReport, /내용을 확인한 뒤 네트워크 상태를 보고 다시 보내 주세요\./);
  assert.match(facilityReportTest, /접수번호로 제보 진행 상황을 조회한다/);
  assert.match(facilityReportTest, /접수 후 제보 진행 상황을 다시 확인한다/);
  assert.match(widgetTest, /제보 번호 ES-1001, 현재 상태 반영됨/);
  assert.match(widgetTest, /시설 신고 실패는 도움말을 쉬운 문구로 안내한다/);
  assert.match(notificationSettings, /class NotificationSettingsApiRepository/);
  assert.match(notificationSettings, /\/api\/v1\/me\/notification-settings/);
  assert.match(notificationSettings, /AuthorizationHeaderProvider/);
  assert.match(notificationSettings, /HttpStatus\.unauthorized/);
  assert.match(notificationSettings, /class NotificationSettingsController extends ChangeNotifier/);
  assert.match(notificationSettings, /class NotificationSettingsScreen extends StatefulWidget/);
  assert.match(notificationSettings, /역 시설 알림/);
  assert.match(notificationSettings, /경로 시설 알림/);
  assert.match(notificationSettings, /제보 진행 알림/);
  assert.match(notificationSettings, /최신 안내 알림/);
  assert.match(notificationSettings, /즐겨찾는 역과 경로의 시설 변경/);
  assert.match(notificationSettings, /알림 설정에서 언제든 끌 수 있습니다/);
  assert.match(notificationSettings, /notificationRegistrationFailureNextAction/);
  assert.match(notificationSettings, /휴대전화 알림 설정과 인터넷 연결을 확인한 뒤 다시 시도해 주세요\./);
  assert.match(notificationSettingsTest, /인증 실패 시 인증을 지우고 한 번 재시도한다/);
  assert.match(notificationSettingsTest, /알림 설정 컨트롤러는 조회와 저장 상태를 구분한다/);
  assert.match(widgetTest, /알림 설정 화면은 기기 알림 실패 도움말을 안내한다/);
  assert.match(read("apps/mobile/lib/onboarding.dart"), /onboardingNotificationFailureNextAction/);
  assert.match(read("apps/mobile/lib/onboarding.dart"), /나중에 알림 설정에서 다시 켤 수 있습니다\./);
  assert.match(read("apps/mobile/test/onboarding_test.dart"), /온보딩은 알림 권한 요청 실패 도움말을 안내한다/);
  assert.match(onboardingAppFlowTest, /첫 실행 앱은 온보딩 알림 권한 실패 도움말을 안내한다/);
  assert.doesNotMatch(widgetTest, /첫 실행 앱은 온보딩 알림 권한 실패 도움말을 안내한다/);
  assert.match(stationSearch, /가까운 역 찾기와 시설 제보 위치 확인에만 현재 위치를 사용합니다/);
  assert.match(stationSearch, /위치 사용을 허용하지 않아도 역명 검색, 즐겨찾기, 엘리베이터와 시설 안내는 계속 사용할 수 있습니다/);
  assert.doesNotMatch(stationSearch, /상태 신고/);
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
  assert.match(widgetTest, /도움말은 이동 전 살펴보기 안내를 함께 보여준다/);
  assert.match(widgetTest, /도움말은 보안과 개인정보 문의 경로를 안내한다/);
  assert.match(main, /보안 문의 안내/);
  assert.match(main, /앱 보안이나 개인정보가 걱정되면 문의로 알려주세요\./);
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
  assert.match(routeSearch, /다른 방법 \$_routeSearchFailureNextAction/);
  assert.match(routeSearch, /routeBlockedNextActionNotice/);
  assert.doesNotMatch(
    routeSearch,
    /label: '다음 행동, \$_routeSearchFailureNextAction'[\s\S]{0,120}child: const SizedBox\.shrink\(\)/,
  );
  assert.match(widgetTest, /경로 검색 실패는 도움말을 쉬운 문구로 안내한다/);
  assert.match(widgetTest, /안내 불가 이유[\s\S]*도움말/);
  assert.match(routeSearch, /routeFeedbackFailureNextAction/);
  assert.match(routeSearch, /잠시 후 다시 보내거나 경로 조건을 바꿔 다시 찾아보세요\./);
  assert.match(widgetTest, /경로 피드백 실패는 도움말을 쉬운 문구로 안내한다/);
  assert.match(routeSearch, /favoriteRouteSaveFailureNextAction/);
  assert.match(routeSearch, /네트워크 상태를 확인한 뒤 자주 쓰는 경로 저장을 다시 눌러 주세요\./);
  assert.match(routeSearch, /favoriteRouteLoadFailureNextAction/);
  assert.match(routeSearch, /네트워크 상태를 확인한 뒤 다시 불러와 주세요\./);
  assert.match(widgetTest, /즐겨찾기 경로 저장 실패는 도움말을 쉬운 문구로 안내한다/);
  assert.match(widgetTest, /즐겨찾기 경로 목록 실패는 도움말을 쉬운 문구로 안내한다/);
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
  assert.match(main, /이동 전 살펴보기/);
  assert.match(main, /현재 위치는 가까운 역 찾기와 시설 제보 위치 확인에만 사용됩니다/);
  assert.match(main, /경로와 시설 정보는 이동을 돕는 참고 정보입니다/);
  assert.match(main, /현장 안내, 역무원 안내, 운영기관 공지를 먼저 확인해 주세요/);
  assert.match(main, /실시간 상태나 무조건 안전한 경로를 보장하지 않습니다/);
  assert.match(main, /내 정보 삭제 요청 시 즐겨찾기, 이동 조건, 제보 접수 기록, 제보 내용·사진·위치와 경로 피드백을 삭제하거나 누구의 정보인지 알 수 없게 바꿉니다/);
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
    /userDataDeletionErrorMessage = '정보 삭제를 완료하지 못했어요\. 잠시 후 다시 시도해 주세요\.'/,
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

test("Android 출시 UX 접근성 성능 gate는 local emulator evidence와 P0 blocker 기준을 고정한다", () => {
  const gate = readJson("apps/mobile/release/android-release-quality-gate.json");
  const androidRcEvidence = readJson("apps/mobile/release/android-rc-store-evidence.json");
  const governance = readJson("apps/mobile/release/release-governance-gate.json");
  const readme = read("README.md");
  const smokeScript = read("tools/mobile/run-android-release-quality-emulator-smoke.sh");

  assert.equal(gate.schemaVersion, 1);
  assert.equal(gate.applicationId, "easysubway");
  assert.equal(gate.androidApplicationId, "com.easysubway.app");
  assert.equal(gate.releaseGate, "android-release-ux-accessibility-performance");
  assert.equal(gate.issue, 1021);
  assert.equal(gate.releaseBlockerPolicy, true);
  assert.equal(gate.scope.platform.android, "RELEASE_REQUIRED");
  assert.equal(gate.scope.platform.ios, "DEFERRED_OUT_OF_SCOPE");
  assert.deepEqual(gate.routeSafetyStatusEnum, ["FOUND", "BLOCKED", "UNKNOWN", "UNSUPPORTED", "ERROR"]);
  assert.equal(gate.routeSafetyContract, "#571");
  assert.deepEqual(gate.buildIdentityPolicy.requiredIssueLinks, ["#1015", "#1016", "#1020"]);
  assert.deepEqual(gate.buildIdentityPolicy.acceptedBuildSources, [
    "rc-aab",
    "play-generated-apk",
    "play-installed-build",
  ]);
  assert.deepEqual(gate.buildIdentityPolicy.requiredIdentityFields, [
    "gitSha",
    "versionCode",
    "aabSha256",
    "dataPackManifestSha256",
    "androidApplicationId",
  ]);
  assert.equal(gate.buildIdentityPolicy.mismatchDisposition, "NO_GO");
  assert.equal(gate.playConsoleEvidencePolicy.requiredBeforeGo, true);
  assert.deepEqual(gate.playConsoleEvidencePolicy.requiredSummaryFields, [
    "playPreLaunchReportResult",
    "playPreLaunchCrashCount",
    "playPreLaunchAnrCount",
    "playPolicyWarningStatus",
    "androidVitalsCrashAnrSummary",
    "triageDisposition",
    "capturedAtUtc",
  ]);
  assert.equal(gate.playConsoleEvidencePolicy.goNoGoRules.missingConsoleSummary, "BLOCKED_EXTERNAL");
  assert.equal(gate.playConsoleEvidencePolicy.goNoGoRules.preLaunchCrashOrAnr, "BLOCKED_TECHNICAL");
  assert.equal(gate.playConsoleEvidencePolicy.goNoGoRules.untriagedPolicyWarning, "BLOCKED_TECHNICAL");
  assert.match(gate.playConsoleEvidencePolicy.summaryRequiredKo, /Play Console pre-launch report/);
  assert.match(gate.playConsoleEvidencePolicy.summaryRequiredKo, /Android vitals/);
  assert.equal(gate.deviceEvidencePolicy.codexQaDevice, "local_android_emulator_only");
  assert.equal(gate.deviceEvidencePolicy.physicalDeviceEvidence, "not_used_for_codex_pr_evidence");
  assert.equal(gate.deviceEvidencePolicy.releaseRcEvidence, "play_installed_or_exact_rc_required_before_go");
  assert.deepEqual(gate.deviceEvidencePolicy.requiredDeviceDiscoveryCommands, [
    "flutter emulators",
    "emulator -list-avds",
    "ANDROID_HOME or ANDROID_SDK_ROOT emulator path check",
    "flutter devices",
    "adb devices",
  ]);
  assert.equal(gate.deviceEvidencePolicy.emptyAdbDevicesDisposition, "INSUFFICIENT_EVIDENCE");
  assert.equal(gate.evidencePolicy.localOnlyEvidenceRoot, ".codex/evidence/release/android-quality/<rc-or-run>/");
  assert.equal(gate.latestQaEvidenceStatus.qaEvidenceDateKst, "2026-06-29");
  assert.equal(gate.latestQaEvidenceStatus.localEvidenceStatus.local16KbEmulatorSmoke, "PASS");
  assert.equal(gate.latestQaEvidenceStatus.localEvidenceStatus.talkBackRouteMapUiTree, "PASS_UI_TREE_ONLY");
  assert.equal(gate.latestQaEvidenceStatus.localEvidenceStatus.playInstalledBuildProvenance, "BLOCKED_EXTERNAL");
  assert.equal(gate.latestQaEvidenceStatus.localEvidenceStatus.playConsolePreLaunchAndVitals, "BLOCKED_EXTERNAL");
  assert.deepEqual(gate.latestQaEvidenceStatus.resolvedEvidence, [
    "android-quality-gate-contract",
    "emulator-discovery-command-policy",
    "local-16kb-runtime-home-station-search-smoke",
    "font-scale-150-home-smoke",
    "font-scale-200-home-smoke",
    "route-map-initial-bounds-visual-smoke",
    "talkback-route-map-ui-tree-accessibility-service",
    "location-permission-denied-recovery",
    "my-reports-backend-failure-recovery",
    "real-device-home-smoke",
    "release-logcat-privacy-marker-scan",
  ]);
  assert.deepEqual(gate.latestQaEvidenceStatus.remainingExternalBlockers, [
    "play-installed-build-provenance",
    "play-generated-apk-download-id-summary",
    "talkback-manual-reading-order-notes",
    "play-pre-launch-crash-anr-policy-summary",
    "android-vitals-crash-anr-summary",
    "play-installed-network-logcat-privacy-summary",
    "play-installed-route-map-performance-budget",
    "play-installed-font-scale-150-200-compact-screen-screenshots",
    "upload-failure-recovery-on-rc-or-play-installed-build",
  ]);
  assert.match(gate.latestQaEvidenceStatus.notClosingReasonKo, /#1021/);
  assert.equal(gate.latestQaEvidenceStatus.redactionPolicy.secretValuesPrinted, false);
  assert.ok(
    gate.latestQaEvidenceStatus.redactionPolicy.forbiddenInGitHubEvidence.includes(
      "network trace with device identifiers",
    ),
  );
  assert.match(
    gate.deviceEvidencePolicy.requiredDeviceDiscoveryCommands.join("\n"),
    /ANDROID_HOME|ANDROID_SDK_ROOT/,
  );
  assert.deepEqual(gate.manualEvidenceSummaryPolicy.commonRequiredFields, [
    "checkId",
    "buildIdentity",
    "evidencePaths",
    "result",
    "blockerDisposition",
  ]);
  assert.deepEqual(gate.manualEvidenceSummaryPolicy.requiredResultValues, [
    "PASS",
    "FAIL",
    "BLOCKED_EXTERNAL",
    "NOT_APPLICABLE_WITH_REASON",
  ]);
  for (const field of [
    "checkId",
    "buildIdentity",
    "buildSource",
    "deviceId",
    "androidApi",
    "fontScale",
    "viewport",
    "evidencePaths",
    "uiTreePath",
    "screenshotOrRecordingPath",
    "logcatSummaryPath",
    "talkbackNotesPath",
    "playConsoleSummaryPath",
    "result",
    "blockerDisposition",
  ]) {
    assert.ok(
      gate.manualEvidenceSummaryPolicy.allowedFields.includes(field),
      `manual evidence summary must allow ${field}`,
    );
  }
  assert.deepEqual(gate.manualEvidenceSummaryPolicy.forbiddenSummaryValues, [
    "TBD",
    "TODO",
    "unknown",
    "not checked",
    "not captured",
  ]);

  const requiredChecks = new Map(gate.requiredChecks.map((check) => [check.id, check]));
  for (const id of [
    "route_safety_status_copy",
    "talkback_primary_journey",
    "font_scale_150_200_small_screen",
    "high_contrast_state_visibility",
    "location_permission_denied_recovery",
    "network_server_upload_error_recovery",
    "route_map_fallback_zoom_help",
    "route_map_performance_budget",
    "scope_source_realtime_support_ui",
    "crash_anr_privacy_safe_reporting",
  ]) {
    assert.ok(requiredChecks.has(id), `${id} must be tracked`);
    assert.equal(requiredChecks.get(id).releaseBlocker, true, `${id} must block release`);
  }
  assert.deepEqual(requiredChecks.get("route_map_performance_budget").budgets, {
    maxJankyPercent: 5,
    maxP95FrameMs: 32,
    maxP99FrameMs: 48,
    maxCameraLatencyP95Ms: 120,
    maxTotalPssKb: 250000,
  });
  assert.deepEqual(requiredChecks.get("route_map_performance_budget").measurementSource.releaseOrPlayInstalled, [
    "gfxinfo-framestats",
    "meminfo",
    "screen-recording-or-screenshot-sequence",
  ]);
  assert.ok(
    requiredChecks
      .get("route_map_performance_budget")
      .measurementSource.matchedProfileInstrumentation.includes("tools/mobile/run-route-map-android-evidence.sh"),
  );
  assert.ok(
    requiredChecks
      .get("route_map_performance_budget")
      .evidence.includes("play-installed-route-map-gfxinfo-framestats-summary"),
  );
  assert.ok(
    requiredChecks
      .get("route_map_performance_budget")
      .evidence.includes("matched-profile-route-map-camera-latency-summary"),
  );
  assert.ok(
    requiredChecks.get("talkback_primary_journey").evidence.includes("talkback-reading-order-notes"),
    "TalkBack check must require actual reading-order notes instead of only UI tree evidence",
  );
  assert.ok(
    requiredChecks.get("crash_anr_privacy_safe_reporting").evidence.includes("play-console-pre-launch-report-summary"),
    "crash/ANR check must require Play Console pre-launch summary evidence",
  );
  assert.ok(
    requiredChecks.get("crash_anr_privacy_safe_reporting").evidence.includes("android-vitals-summary"),
    "crash/ANR check must require Android vitals summary evidence",
  );

  const evidenceSet = new Map(gate.requiredEvidenceSet.map((item) => [item.id, item]));
  for (const id of [
    "home_support_scope",
    "station_search",
    "station_detail_facility_status",
    "route_result_found_unknown_unavailable",
    "route_map_fallback",
    "facility_report_recovery",
    "help_privacy_data_deletion",
    "data_baseline_source_realtime_scope",
  ]) {
    const item = evidenceSet.get(id);
    assert.ok(item, `${id} must be required Android QA evidence`);
    assert.ok(item.evidence.includes("screenshot"), `${id} must require screenshot evidence`);
    assert.ok(item.evidence.includes("ui-tree"), `${id} must require UI tree evidence`);
    assert.equal(typeof item.provesKo, "string", `${id} must explain what evidence proves`);
  }
  assert.ok(evidenceSet.get("route_map_fallback").evidence.includes("performance-summary"));
  assert.ok(evidenceSet.get("facility_report_recovery").evidence.includes("logcat-summary"));

  const checkEvidenceMatrix = new Map(gate.checkEvidenceMatrix.map((item) => [item.checkId, item]));
  assert.deepEqual([...checkEvidenceMatrix.keys()].sort(), [...requiredChecks.keys()].sort());
  const requiredEvidenceIds = new Set(evidenceSet.keys());
  for (const [checkId, matrix] of checkEvidenceMatrix) {
    assert.ok(requiredChecks.has(checkId), `${checkId} matrix must reference a required check`);
    assert.ok(Array.isArray(matrix.requiredEvidenceIds), `${checkId} matrix must list evidence IDs`);
    assert.ok(matrix.requiredEvidenceIds.length > 0, `${checkId} matrix must require evidence IDs`);
    assert.equal(
      new Set(matrix.requiredEvidenceIds).size,
      matrix.requiredEvidenceIds.length,
      `${checkId} matrix must not duplicate evidence IDs`,
    );
    for (const evidenceId of matrix.requiredEvidenceIds) {
      assert.ok(requiredEvidenceIds.has(evidenceId), `${checkId} matrix references unknown evidence ID: ${evidenceId}`);
    }
    for (const field of [
      "checkId",
      "buildIdentity",
      "evidencePaths",
      "result",
      "blockerDisposition",
    ]) {
      assert.ok(matrix.requiredSummaryFields.includes(field), `${checkId} matrix must require summary field ${field}`);
    }
    for (const field of matrix.requiredSummaryFields) {
      assert.ok(
        gate.manualEvidenceSummaryPolicy.allowedFields.includes(field),
        `${checkId} matrix summary field must be in allowed vocabulary: ${field}`,
      );
    }
  }
  assert.ok(
    checkEvidenceMatrix.get("font_scale_150_200_small_screen").requiredSummaryFields.includes("fontScale"),
    "font scale check must record the Android font scale",
  );
  assert.ok(
    checkEvidenceMatrix.get("font_scale_150_200_small_screen").requiredSummaryFields.includes("viewport"),
    "font scale check must record the viewport",
  );
  assert.ok(
    checkEvidenceMatrix.get("talkback_primary_journey").requiredSummaryFields.includes("talkbackNotesPath"),
    "TalkBack check must record the actual reading-order notes path",
  );
  assert.ok(
    checkEvidenceMatrix.get("route_map_performance_budget").requiredSummaryFields.includes("buildSource"),
    "performance check must record RC or Play-installed build source",
  );
  assert.ok(
    checkEvidenceMatrix.get("crash_anr_privacy_safe_reporting").requiredSummaryFields.includes("logcatSummaryPath"),
    "crash/ANR privacy check must record logcat or crash summary path",
  );
  assert.ok(
    checkEvidenceMatrix.get("crash_anr_privacy_safe_reporting").requiredSummaryFields.includes("playConsoleSummaryPath"),
    "crash/ANR privacy check must record Play Console or Android vitals summary path",
  );

  assert.ok(androidRcEvidence.requiredEvidence.androidAccessibilityQa.includes("android-release-quality-gate-manifest"));
  assert.ok(androidRcEvidence.requiredEvidence.androidAccessibilityQa.includes("local-emulator-ui-tree-screenshots"));
  assert.ok(androidRcEvidence.requiredEvidence.androidAccessibilityQa.includes("route-map-performance-summary"));
  assert.ok(governance.childIssueLinks.includes(1021));
  assert.match(readme, /Android 출시 UX·접근성·성능 gate/);
  assert.match(readme, /local Android emulator evidence/);
  assert.match(smokeScript, /ro\.kernel\.qemu/);
  assert.match(smokeScript, /--expected-font-scale/);
  assert.match(smokeScript, /MIN_ANDROID_API=35/);
  assert.match(smokeScript, /MAX_COMPACT_WIDTH_DP=599/);
  assert.match(smokeScript, /width_dp=\$\(\(width_px \* 160 \/ density_dpi\)\)/);
  assert.match(smokeScript, /"\$width_px" -ge "\$height_px"/);
  assert.match(smokeScript, /viewport_orientation=portrait/);
  assert.match(smokeScript, /dumpsys input/);
  assert.match(smokeScript, /orientation=\\\(\[0-3\]\\\)/);
  assert.match(smokeScript, /screen_rotation_source=/);
  assert.match(smokeScript, /screen_rotation=/);
  assert.match(smokeScript, /"\$screen_rotation" != "0"/);
  assert.match(smokeScript, /wm_size_raw=/);
  assert.match(smokeScript, /Override size:/);
  assert.match(smokeScript, /wm_size_source="override"/);
  assert.match(smokeScript, /pm path "\$PACKAGE"/);
  assert.match(smokeScript, /android\.intent\.action\.MAIN/);
  assert.match(smokeScript, /android\.intent\.category\.LAUNCHER/);
  assert.match(smokeScript, /-p "\$PACKAGE"/);
  assert.match(smokeScript, /am start -n "\$launch_activity"/);
  assert.match(smokeScript, /current-focus\.txt/);
  assert.match(smokeScript, /font_scale/);
  assert.match(smokeScript, /uiautomator dump/);
  assert.match(smokeScript, /dumpsys gfxinfo/);
});

test("모바일 스토어 심사 정보 기준선은 제출 전 필수 항목을 고정한다", () => {
  const readinessPath = "apps/mobile/release/store-submission-readiness.json";
  assert.ok(existsSync(path.join(root, readinessPath)));

  const readiness = readJson(readinessPath);
  const androidRcEvidence = readJson("apps/mobile/release/android-rc-store-evidence.json");
  const playStoreContent = readJson("apps/mobile/release/play-store-submission-content.json");
  const storePrivacyInventory = readJson("apps/mobile/release/store-privacy-inventory.json");

  assert.equal(readiness.schemaVersion, 1);
  assert.equal(readiness.applicationId, "easysubway");
  assert.equal(readiness.androidApplicationId, "com.easysubway.app");
  assert.equal(readiness.releaseGate, "store-submission-readiness");
  assert.equal(readiness.androidRcEvidenceManifest, "apps/mobile/release/android-rc-store-evidence.json");
  assert.equal(readiness.appNameKo, "쉬운 지하철");
  assert.equal(readiness.appNameEn, "easysubway");
  assert.ok(readiness.appNameKo.length <= readiness.appNameLengthLimits.googlePlay);
  assert.match(readiness.policyRefreshKo, /제출 직전|최신/);
  assert.doesNotMatch(JSON.stringify(readiness), /\b(TBD|TODO)\b|\.{3}/i);
  assert.ok(Array.isArray(readiness.items));
  assert.equal(readiness.latestEvidenceStatus.issue, 1018);
  assert.equal(readiness.latestEvidenceStatus.privacyPolicyUrl, "PASS_PUBLIC_HTTPS");
  assert.equal(readiness.latestEvidenceStatus.publicContactMailboxes, "RESOLVED_BY_QA_MANUAL_EVIDENCE");
  assert.deepEqual(readiness.latestEvidenceStatus.remainingGooglePlayBlockers, [
    "play-console-data-safety-preview",
    "play-console-main-listing-preview",
    "play-pre-launch-report-or-android-vitals-export",
    "play-upload-or-play-installed-required-screenshot-set",
  ]);
  assert.match(readiness.latestEvidenceStatus.notClosingReasonKo, /#1018은 open 유지/);

  const items = new Map(readiness.items.map((item) => [item.id, item]));
  const requiredIds = [
    "play_data_safety",
    "play_privacy_policy_url",
    "play_app_access",
    "play_production_access_closed_test",
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

  assert.equal(playStoreContent.latestQaEvidenceSummary.qaEvidenceDateKst, "2026-06-28");
  assert.equal(playStoreContent.latestQaEvidenceSummary.privacyPolicyUrl.result, "PASS_PUBLIC_HTTPS");
  assert.equal(
    playStoreContent.latestQaEvidenceSummary.privacyPolicyUrl.url,
    "https://easysubway-api.aquilaxk.site/easysubway/privacy",
  );
  assert.deepEqual(playStoreContent.latestQaEvidenceSummary.privacyPolicyUrl.requiredIn, [
    "Play Console",
    "app help",
    "README.md or public policy page",
  ]);
  assert.equal(
    playStoreContent.latestQaEvidenceSummary.publicContactMailboxes.result,
    "RESOLVED_BY_QA_MANUAL_EVIDENCE",
  );
  assert.equal(playStoreContent.latestQaEvidenceSummary.publicContactMailboxes.domain, "aquilaxk.site");
  assert.deepEqual(playStoreContent.latestQaEvidenceSummary.publicContactMailboxes.addresses, [
    "support@aquilaxk.site",
    "security@aquilaxk.site",
    "privacy@aquilaxk.site",
  ]);
  assert.match(playStoreContent.latestQaEvidenceSummary.publicContactMailboxes.redactionPolicy, /raw report receipt token/);
  assert.match(playStoreContent.latestQaEvidenceSummary.publicContactMailboxes.redactionPolicy, /operator private contact/);
  assert.match(playStoreContent.latestQaEvidenceSummary.publicContactMailboxes.redactionPolicy, /provider credential or quota token/);
  assert.match(playStoreContent.latestQaEvidenceSummary.publicContactMailboxes.redactionPolicy, /photo metadata/);
  assert.deepEqual(playStoreContent.latestQaEvidenceSummary.remainingExternalBlockers, [
    "play-console-data-safety-preview",
    "play-console-main-listing-preview",
    "play-pre-launch-report-or-android-vitals-export",
    "play-upload-or-play-installed-required-screenshot-set",
  ]);
  assert.deepEqual(playStoreContent.latestQaEvidenceSummary.remainingEvidenceBeforeFinalGo, [
    "network-trace-match-summary",
    "crash-anr-privacy-summary",
    "store-screenshot-summary",
    "privacy-url-same-url-summary",
  ]);

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
  assert.ok(items.get("play_data_safety").linkedArtifacts.includes("apps/mobile/release/play-store-submission-content.json"));
  assert.match(items.get("play_data_safety").readyWhenKo, /collected|collection type|optional\/required|linked to user|deletion support/i);
  assert.match(items.get("play_privacy_policy_url").configurationSources.join("\n"), /EASYSUBWAY_PRIVACY_POLICY_URL/);
  assert.match(items.get("play_privacy_policy_url").readyWhenKo, /public HTTPS|인증 없이|수집 항목|삭제|제3자 공유 없음|tracking 없음/);
  assert.match(items.get("play_app_access").readyWhenKo, /로그인 없음|제한 접근|심사 계정/);
  assert.ok(items.get("play_production_access_closed_test").linkedArtifacts.includes("apps/mobile/release/play-production-access-gate.json"));
  assert.match(items.get("play_production_access_closed_test").readyWhenKo, /12명 이상|14일 연속|production access/);
  assert.match(items.get("play_content_rating").readyWhenKo, /등급/);
  assert.match(items.get("play_target_audience").readyWhenKo, /전체 사용자|어린이 대상 아님/);
  assert.match(items.get("play_app_category").readyWhenKo, /대중교통|접근성|지하철|경로 안내/);
  assert.match(items.get("play_store_contact").readyWhenKo, /공개 연락처 이메일|고객지원 메일|같은 운영 수신함/);
  assert.match(items.get("play_permissions_declaration").readyWhenKo, /위치|권한/);
  assert.ok(items.get("play_listing_assets_truthfulness").linkedArtifacts.includes("apps/mobile/release/play-store-submission-content.json"));
  assert.match(items.get("play_listing_assets_truthfulness").readyWhenKo, /고정 스크린샷 세트/);
  const playListingAssetsTruthfulnessReadyWhenKo = items.get("play_listing_assets_truthfulness").readyWhenKo;
  assert.match(playListingAssetsTruthfulnessReadyWhenKo, /7인치\/10인치 태블릿/);
  assert.match(playListingAssetsTruthfulnessReadyWhenKo, /Chromebook/);
  assert.match(playListingAssetsTruthfulnessReadyWhenKo, /Android XR/);
  assert.ok(items.get("play_listing_assets_truthfulness").evidence.includes("large-screen-screenshot-review"));
  assert.match(items.get("play_account_data_deletion").configurationSources.join("\n"), /EASYSUBWAY_DATA_DELETION_EMAIL/);
  assert.ok(androidRcEvidence.requiredEvidence.playConsoleSubmission.includes("app-content-declarations"));
  assert.ok(androidRcEvidence.requiredEvidence.playConsoleSubmission.includes("store-listing-scope-copy-review"));
  assert.ok(androidRcEvidence.requiredEvidence.playConsoleSubmission.includes("large-screen-store-screenshot-asset-record"));
  assert.deepEqual(playStoreContent.requiredScreenshotSet.map((item) => item.id), [
    "home_support_scope",
    "station_search",
    "station_detail_facility_status",
    "route_result_found_and_unknown_or_needs_confirmation",
    "facility_report_form",
    "report_receipt_status",
    "help_privacy_data_deletion",
    "data_baseline_source_realtime_scope",
  ]);
  assert.deepEqual(playStoreContent.largeScreenScreenshotTargets.map((item) => item.id), [
    "seven_inch_tablet_landscape",
    "ten_inch_tablet_landscape",
    "chromebook_16_9",
    "android_xr_16_9",
  ]);
  const largeScreenTargets = new Map(playStoreContent.largeScreenScreenshotTargets.map((item) => [item.id, item]));
  for (const target of largeScreenTargets.values()) {
    assert.ok(target.requiredScreenshotIds.includes("home_support_scope"), `${target.id} must include home evidence`);
    assert.ok(target.requiredScreenshotIds.includes("station_search"), `${target.id} must include station search evidence`);
    assert.ok(
      target.requiredScreenshotIds.includes("station_detail_facility_status"),
      `${target.id} must include station detail evidence`,
    );
    assert.ok(target.requiredEvidenceFields.includes("sourceGitSha"), `${target.id} must record source git SHA`);
    assert.ok(target.requiredEvidenceFields.includes("sourceBuildType"), `${target.id} must record source build type`);
    assert.ok(target.requiredEvidenceFields.includes("viewport"), `${target.id} must record viewport`);
    assert.ok(target.requiredEvidenceFields.includes("seedData"), `${target.id} must record seed data`);
    assert.ok(target.requiredEvidenceFields.includes("uiTreePath"), `${target.id} must record UI tree evidence`);
    assert.ok(target.requiredEvidenceFields.includes("largeTextScaleResult"), `${target.id} must record large text evidence`);
    assert.ok(target.requiredEvidenceFields.includes("highContrastResult"), `${target.id} must record high contrast evidence`);
    assert.ok(target.requiredEvidenceFields.includes("accessibilityGuidelineResult"), `${target.id} must record accessibility guideline evidence`);
    assert.ok(target.requiredEvidenceFields.includes("result"), `${target.id} must record result`);
  }
  assert.ok(largeScreenTargets.get("chromebook_16_9").requiredScreenshotIds.includes("help_privacy_data_deletion"));
  assert.ok(largeScreenTargets.get("chromebook_16_9").requiredEvidenceFields.includes("keyboardMouseSmokeResult"));
  assert.ok(largeScreenTargets.get("android_xr_16_9").requiredScreenshotIds.includes("help_privacy_data_deletion"));
  assert.match(largeScreenTargets.get("android_xr_16_9").scopeNoteKo, /XR 전용 spatial UI 지원으로 표현하지 않는다/);
  assert.deepEqual(playStoreContent.dataSafetyDeclarations.requiredFieldsPerDataType, [
    "collected",
    "collectionType",
    "optional",
    "required",
    "purpose",
    "linkedToUser",
    "encryptedInTransit",
    "deletionSupported",
  ]);
  const inventoryDataTypesById = new Map(storePrivacyInventory.dataTypes.map((item) => [item.id, item]));
  const expectedPlayDataTypes = [
    ...new Set(storePrivacyInventory.dataTypes.map((item) => item.googlePlayDataSafety.dataType)),
  ].sort();
  const expectedInventoryIdsByDataType = new Map();
  for (const item of storePrivacyInventory.dataTypes) {
    const dataType = item.googlePlayDataSafety.dataType;
    const existingIds = expectedInventoryIdsByDataType.get(dataType) ?? [];
    expectedInventoryIdsByDataType.set(dataType, [...existingIds, item.id]);
  }
  assert.deepEqual(playStoreContent.dataSafetyDeclarations.requiredCollectedDataTypes.toSorted(), expectedPlayDataTypes);
  const dataSafetyAnswerMatrix = new Map(
    playStoreContent.dataSafetyDeclarations.answerMatrix.map((item) => [item.dataType, item]),
  );
  assert.deepEqual([...dataSafetyAnswerMatrix.keys()].sort(), expectedPlayDataTypes);
  for (const dataType of expectedPlayDataTypes) {
    const matrix = dataSafetyAnswerMatrix.get(dataType);
    assert.ok(Array.isArray(matrix.inventoryDataIds), `${dataType} matrix must list inventory IDs`);
    assert.ok(matrix.inventoryDataIds.length > 0, `${dataType} matrix must include at least one inventory ID`);
    assert.equal(
      new Set(matrix.inventoryDataIds).size,
      matrix.inventoryDataIds.length,
      `${dataType} matrix must not duplicate inventory IDs`,
    );
    assert.deepEqual(
      matrix.inventoryDataIds.toSorted(),
      expectedInventoryIdsByDataType.get(dataType).toSorted(),
      `${dataType} matrix must cover every inventory ID for the Play data type`,
    );
    assert.deepEqual(
      matrix.requiredConsoleFields,
      playStoreContent.dataSafetyDeclarations.requiredFieldsPerDataType,
      `${dataType} matrix must require every Play Console field`,
    );
    assert.ok(
      matrix.evidenceSummaryFields.includes("consolePreviewEvidence"),
      `${dataType} matrix must require Console preview evidence`,
    );
    assert.ok(
      matrix.evidenceSummaryFields.includes("networkTraceMatchResult"),
      `${dataType} matrix must require network trace matching result`,
    );
    assert.ok(
      matrix.evidenceSummaryFields.includes("localEvidencePath"),
      `${dataType} matrix must require local-only evidence path`,
    );
    for (const inventoryId of matrix.inventoryDataIds) {
      const inventoryItem = inventoryDataTypesById.get(inventoryId);
      assert.ok(inventoryItem, `${dataType} matrix references unknown inventory item: ${inventoryId}`);
      assert.equal(
        inventoryItem.googlePlayDataSafety.dataType,
        dataType,
        `${inventoryId} must map back to the same Play data type`,
      );
    }
    const matrixItems = matrix.inventoryDataIds.map((id) => inventoryDataTypesById.get(id));
    assert.equal(
      matrix.containsCollectedData,
      matrixItems.some((item) => item.googlePlayDataSafety.collected),
      `${dataType} matrix collected flag must match inventory`,
    );
    assert.equal(
      matrix.containsRequiredData,
      matrixItems.some((item) => item.googlePlayDataSafety.required),
      `${dataType} matrix required flag must match inventory`,
    );
    assert.equal(
      matrix.containsOptionalData,
      matrixItems.some((item) => item.googlePlayDataSafety.optional),
      `${dataType} matrix optional flag must match inventory`,
    );
  }
  assert.equal(dataSafetyAnswerMatrix.get("Diagnostics").containsLocalOnlyDiagnostics, true);
  assert.equal(playStoreContent.privacyPolicyRequirements.urlMustBePublicHttps, true);
  assert.equal(playStoreContent.privacyPolicyRequirements.urlMustBeUnauthenticated, true);
  assert.deepEqual(playStoreContent.privacyPolicyRequirements.sameUrlRequiredIn, [
    "Play Console",
    "app help",
    "README.md or public policy page",
  ]);
  assert.ok(playStoreContent.privacyPolicyRequirements.requiredContentKo.includes("제3자 공유 없음"));
  assert.ok(playStoreContent.privacyPolicyRequirements.requiredContentKo.includes("tracking 없음"));
  assert.equal(playStoreContent.storeMetadataRequirements.publicContactEmailMustMatchAppSupportEmail, true);
  assert.ok(playStoreContent.storeMetadataRequirements.requiredTagsKo.includes("대중교통"));
  assert.ok(playStoreContent.storeMetadataRequirements.requiredTagsKo.includes("접근성"));
  assert.ok(playStoreContent.storeMetadataRequirements.reviewerNotesMustIncludeKo.includes("로그인 없음"));
  assert.ok(playStoreContent.storeMetadataRequirements.reviewerNotesMustIncludeKo.includes("위치 권한은 선택적 사용"));
  assert.equal(playStoreContent.crashAnrProviderDecision.separateCrashProvider, false);
  assert.ok(playStoreContent.crashAnrProviderDecision.sourceOfTruth.includes("Android vitals"));
  assert.ok(playStoreContent.crashAnrProviderDecision.sourceOfTruth.includes("Google Play pre-launch report"));
  assert.equal(playStoreContent.crashAnrProviderDecision.dependencyEvidenceRequired, "no-crash-sdk-dependency-scan");
  assert.deepEqual(Object.keys(playStoreContent.evidenceSummarySchemas).sort(), [
    "crashAnrPrivacySummary",
    "dataSafetyConsoleSummary",
    "mailboxReceiptSummary",
    "networkTraceMatchSummary",
    "privacyPolicyUrlSummary",
    "storeScreenshotSummary",
  ]);
  for (const [schemaId, schema] of Object.entries(playStoreContent.evidenceSummarySchemas)) {
    assert.ok(Array.isArray(schema.requiredFields), `${schemaId} must define required fields`);
    assert.ok(schema.requiredFields.includes("localEvidencePath"), `${schemaId} must require local evidence path`);
    assert.ok(schema.requiredFields.includes("result"), `${schemaId} must require an explicit result`);
  }
  assert.ok(
    playStoreContent.evidenceSummarySchemas.dataSafetyConsoleSummary.requiredFields.includes("consolePreviewEvidence"),
  );
  assert.ok(
    playStoreContent.evidenceSummarySchemas.dataSafetyConsoleSummary.requiredFields.includes("networkTraceMatchResult"),
  );
  assert.ok(
    playStoreContent.evidenceSummarySchemas.privacyPolicyUrlSummary.requiredFields.includes("sameUrlResult"),
  );
  assert.ok(
    playStoreContent.evidenceSummarySchemas.mailboxReceiptSummary.requiredFields.includes("redactionResult"),
  );
  assert.ok(
    playStoreContent.evidenceSummarySchemas.storeScreenshotSummary.requiredFields.includes("forbiddenClaimsAbsent"),
  );
  assert.ok(playStoreContent.evidenceSummarySchemas.storeScreenshotSummary.requiredFields.includes("sourceGitSha"));
  assert.ok(playStoreContent.evidenceSummarySchemas.storeScreenshotSummary.requiredFields.includes("targetDeviceClass"));
  assert.ok(playStoreContent.evidenceSummarySchemas.storeScreenshotSummary.requiredFields.includes("viewport"));
  assert.ok(playStoreContent.evidenceSummarySchemas.storeScreenshotSummary.requiredFields.includes("seedData"));
  assert.ok(playStoreContent.evidenceSummarySchemas.storeScreenshotSummary.requiredFields.includes("uiTreePath"));
  assert.equal(
    playStoreContent.assetEvidence.tabletScreenshots,
    "required_large_screen_screenshots_matching_largeScreenScreenshotTargets",
  );
  assert.equal(
    playStoreContent.assetEvidence.chromebookScreenshots,
    "required_16_9_app_screenshots_matching_largeScreenScreenshotTargets",
  );
  assert.equal(
    playStoreContent.assetEvidence.androidXrScreenshots,
    "required_16_9_app_screenshots_without_xr_specific_ui_claim",
  );
  assert.ok(
    playStoreContent.evidenceSummarySchemas.crashAnrPrivacySummary.requiredFields.includes("forbiddenPayloadAbsent"),
  );
  assert.ok(
    playStoreContent.evidenceSummarySchemas.networkTraceMatchSummary.requiredFields.includes("undeclaredDataTransferCount"),
  );
  assert.deepEqual(playStoreContent.forbiddenEvidenceSummaryValues, [
    "TBD",
    "TODO",
    "unknown",
    "not checked",
    "not captured",
  ]);
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
  const adminOperatorAuditFilter = read("backend/src/main/java/com/easysubway/common/security/AdminOperatorAuditFilter.java");
  const adminOperatorLockoutProvider = read(
    "backend/src/main/java/com/easysubway/common/security/AdminOperatorLockoutAuthenticationProvider.java",
  );
  const adminIdentityPostgresSchema = read("backend/src/main/resources/db/migration/postgresql/V9__admin_identity.sql");
  const adminRbacPostgresSchema = [
    read("backend/src/main/resources/db/migration/postgresql/V10__admin_rbac_menu.sql"),
    read("backend/src/main/resources/db/migration/postgresql/V11__admin_audit_events.sql"),
    read("backend/src/main/resources/db/migration/postgresql/V12__admin_batch_operation_permission.sql"),
    read("backend/src/main/resources/db/migration/postgresql/V13__admin_common_code_incident.sql"),
    read("backend/src/main/resources/db/migration/postgresql/V15__admin_report_photo_read_permission.sql"),
    read("backend/src/main/resources/db/migration/postgresql/V22__datapack_admin_permissions.sql"),
  ].join("\n");
  const adminRbacH2Schema = [
    read("backend/src/main/resources/db/migration/h2/V10__admin_rbac_menu.sql"),
    read("backend/src/main/resources/db/migration/h2/V11__admin_audit_events.sql"),
    read("backend/src/main/resources/db/migration/h2/V12__admin_batch_operation_permission.sql"),
    read("backend/src/main/resources/db/migration/h2/V13__admin_common_code_incident.sql"),
    read("backend/src/main/resources/db/migration/h2/V15__admin_report_photo_read_permission.sql"),
    read("backend/src/main/resources/db/migration/h2/V22__datapack_admin_permissions.sql"),
  ].join("\n");
  const adminProgramRegistry = read("backend/src/main/java/com/easysubway/admin/navigation/AdminProgram.java");
  const adminPermission = read("backend/src/main/java/com/easysubway/admin/authorization/AdminPermission.java");
  const adminRbacRole = read("backend/src/main/java/com/easysubway/admin/authorization/AdminRbacRole.java");
  const inMemoryAdminRbacAuthorityRepository = read(
    "backend/src/main/java/com/easysubway/admin/authorization/adapter/out/persistence/InMemoryAdminRbacAuthorityRepository.java",
  );
  const jdbcAdminRbacAuthorityRepository = read(
    "backend/src/main/java/com/easysubway/admin/authorization/adapter/out/persistence/JdbcAdminRbacAuthorityRepository.java",
  );
  const adminIdentityUserDetailsService = read(
    "backend/src/main/java/com/easysubway/admin/identity/application/service/AdminIdentityUserDetailsService.java",
  );
  const jdbcAdminIdentityRepository = read(
    "backend/src/main/java/com/easysubway/admin/identity/adapter/out/persistence/JdbcAdminIdentityRepository.java",
  );
  const facilityReportAbuseControl = read(
    "backend/src/main/java/com/easysubway/report/adapter/in/web/FacilityReportAbuseControl.java",
  );
  const facilityReportPhotoProcessor = read(
    "backend/src/main/java/com/easysubway/report/application/service/FacilityReportPhotoProcessor.java",
  );
  const userDataDeletionService = read(
    "backend/src/main/java/com/easysubway/user/application/service/UserDataDeletionService.java",
  );
  const userDataDeletionTest = read(
    "backend/src/test/java/com/easysubway/user/application/service/UserDataDeletionServiceTest.java",
  );
  const prodConfig = read("backend/src/main/resources/application-prod.yml");
  const backendAppEnvAllowlist = read("tools/deploy/backend-app-env.allowlist");
  const securityPrivacyEvidence = readJson("apps/mobile/release/security-privacy-release-evidence.json");
  const abusePenetrationRehearsalGate = readJson("apps/mobile/release/abuse-penetration-rehearsal-gate.json");

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
    "datapack_signing_key_lifecycle",
    "mobile_test_credentials_absent",
    "mobile_release_artifact_secret_trace_scan",
    "mobile_error_stacktrace_sanitized",
    "backend_admin_auth_required",
    "backend_admin_basic_auth_transition_gate",
    "backend_role_authorization",
    "backend_report_photo_upload_limits",
    "backend_report_photo_malicious_upload_defense",
    "backend_report_abuse_control_release_gate",
    "backend_error_response_sanitized",
    "backend_api_traffic_monitoring",
    "backend_sensitive_log_minimization",
    "user_data_deletion_retention_e2e",
    "repository_secrets_not_tracked",
    "repository_provider_storage_exposure_guard",
    "repository_dependency_review",
    "repository_abuse_penetration_rehearsal",
    "repository_codex_security_scan_before_release",
    "cross_store_privacy_security_consistency",
  ];
  assert.deepEqual([...items.keys()].sort(), requiredIds.toSorted());

  const areas = new Set(gate.items.map((item) => item.area));
  assert.deepEqual([...areas].sort(), ["backend", "cross-store", "mobile", "repository", "user-data"]);

  for (const id of requiredIds) {
    const item = items.get(id);
    assert.match(item.area, /^(mobile|backend|repository|cross-store|user-data)$/);
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
  const datapackSigningGate = items.get("datapack_signing_key_lifecycle");
  assert.match(datapackSigningGate.readyWhenKo, /public keyring|rotation|revocation|rollback/i);
  assert.ok(datapackSigningGate.evidence.includes("manifest-signature-test-vector"));
  assert.ok(datapackSigningGate.evidence.includes("key-rotation-revocation-record"));
  assert.ok(datapackSigningGate.linkedArtifacts.includes("apps/mobile/release/security-privacy-release-evidence.json"));
  const releaseArtifactScanGate = items.get("mobile_release_artifact_secret_trace_scan");
  assert.match(releaseArtifactScanGate.readyWhenKo, /provider key|signing private key|upload URL|receipt token|placeholder endpoint/i);
  assert.ok(releaseArtifactScanGate.evidence.includes("release-artifact-secret-scan-output"));
  assert.ok(releaseArtifactScanGate.evidence.includes("release-network-trace-review"));
  assert.ok(releaseArtifactScanGate.linkedArtifacts.includes(".github/workflows/release-artifacts.yml"));
  assert.ok(releaseArtifactScanGate.linkedArtifacts.includes("apps/mobile/release/security-privacy-release-evidence.json"));
  const abuseRehearsalItem = items.get("repository_abuse_penetration_rehearsal");
  assert.match(abuseRehearsalItem.readyWhenKo, /Android AAB|Play-generated APK|receipt|signed URL|CSRF|distributed rate limit|#1020/i);
  assert.ok(abuseRehearsalItem.evidence.includes("abuse-penetration-rehearsal-gate-manifest"));
  assert.ok(abuseRehearsalItem.evidence.includes("critical-high-finding-zero-or-waiver"));
  assert.ok(abuseRehearsalItem.linkedArtifacts.includes("apps/mobile/release/abuse-penetration-rehearsal-gate.json"));
  assert.equal(securityPrivacyEvidence.abusePenetrationRehearsalGate, "apps/mobile/release/abuse-penetration-rehearsal-gate.json");
  assert.equal(securityPrivacyEvidence.abusePenetrationRehearsal.criticalHighAllowed, 0);
  assert.ok(securityPrivacyEvidence.abusePenetrationRehearsal.requiredScenarios.includes("receipt_token_replay_and_status_abuse"));
  assert.ok(securityPrivacyEvidence.abusePenetrationRehearsal.requiredScenarios.includes("distributed_rate_limit_abuse"));
  assert.equal(abusePenetrationRehearsalGate.findingPolicy.criticalHighAllowed, 0);
  assert.equal(abusePenetrationRehearsalGate.findingPolicy.waiverIssue, 1020);
  assert.match(commonExceptionHandler, /messages\.message\("common\.error\.invalid-parameter"\)/);
  assert.match(messages, /^common\.error\.invalid-parameter=요청 값을 확인해야 합니다\.$/m);
  assert.doesNotMatch(commonExceptionHandler, /StackTrace|printStackTrace|getStackTrace/);
  assert.match(securityConfig, /securityMatcher\("\/admin\/\*\*"\)/);
  assert.match(securityConfig, /hasAuthority\(AdminPermission\.ADMIN_VIEW\.authority\(\)\)/);
  assert.match(securityConfig, /hasAuthority\(AdminPermission\.REPORT_REVIEW\.authority\(\)\)/);
  assert.match(securityConfig, /hasAuthority\(AdminPermission\.REPORT_PHOTO_READ\.authority\(\)\)/);
  assert.match(securityConfig, /hasAuthority\(AdminPermission\.DATA_OPERATE\.authority\(\)\)/);
  assert.match(securityConfig, /"\/admin\/notifications\/\*\*"/);
  assert.match(securityConfig, /hasRole\("OPERATOR_ADMIN"\)/);
  assert.match(securityConfig, /validateProdAdminCredentials/);
  assert.match(securityConfig, /validateProdBasicAuthPolicy/);
  assert.match(securityConfig, /easysubway\.admin\.basic-auth\.enabled/);
  assert.match(securityConfig, /easysubway\.admin\.basic-auth\.exception-owner/);
  assert.match(securityConfig, /easysubway\.admin\.basic-auth\.exception-expires-at/);
  assert.match(securityConfig, /AdminIdentityRepository/);
  assert.match(securityConfig, /upsertBootstrap/);
  assert.match(securityConfig, /easysubway\.admin\.break-glass\.username/);
  assert.match(securityConfig, /easysubway\.admin\.break-glass\.password/);
  assert.match(securityConfig, /easysubway\.admin\.break-glass\.reason/);
  assert.match(prodConfig, /EASYSUBWAY_ADMIN_BASIC_AUTH_ENABLED:false/);
  assert.match(prodConfig, /EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_OWNER/);
  assert.match(prodConfig, /EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_EXPIRES_AT/);
  assert.match(prodConfig, /EASYSUBWAY_ADMIN_BREAK_GLASS_USERNAME/);
  assert.match(prodConfig, /EASYSUBWAY_ADMIN_BREAK_GLASS_PASSWORD/);
  assert.match(prodConfig, /EASYSUBWAY_ADMIN_BREAK_GLASS_REASON/);
  assert.match(prodConfig, /EASYSUBWAY_OPERATOR_USERNAME/);
  assert.match(prodConfig, /EASYSUBWAY_OPERATOR_PASSWORD/);
  assert.match(adminOperatorAuditFilter, /tenant=\{\}/);
  assert.match(adminOperatorAuditFilter, /outcome=\{\}/);
  assert.match(adminOperatorAuditFilter, /correlation_id=\{\}/);
  assert.doesNotMatch(adminOperatorAuditFilter, /getQueryString|getParameter|getParameterMap|getInputStream|getReader/);
  const adminBasicAuthGate = items.get("backend_admin_basic_auth_transition_gate");
  assert.match(adminBasicAuthGate.readyWhenKo, /lockout|OIDC|MFA|SSO/i);
  assert.match(adminBasicAuthGate.readyWhenKo, /Basic auth/);
  assert.match(adminBasicAuthGate.readyWhenKo, /owner|만료일/);
  assert.ok(adminBasicAuthGate.evidence.includes("admin-auth-transition-decision-record"));
  assert.ok(adminBasicAuthGate.evidence.includes("basic-auth-prod-disable-test"));
  assert.ok(adminBasicAuthGate.evidence.includes("basic-auth-exception-expiry-record"));
  assert.ok(adminBasicAuthGate.evidence.includes("admin-basic-auth-lockout-tests"));
  assert.ok(adminBasicAuthGate.linkedArtifacts.includes("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java"));
  assert.ok(adminBasicAuthGate.linkedArtifacts.includes("backend/src/main/java/com/easysubway/common/security/AdminOperatorLockoutAuthenticationProvider.java"));
  assert.ok(adminBasicAuthGate.linkedArtifacts.includes("backend/src/test/java/com/easysubway/common/security/AdminOperatorLockoutAuthenticationProviderTest.java"));
  assert.ok(adminBasicAuthGate.linkedArtifacts.includes(".github/pull_request_template.md"));
  assert.match(adminOperatorLockoutProvider, /LockedException/);
  assert.match(adminOperatorLockoutProvider, /BadCredentialsException/);
  assert.match(adminOperatorLockoutProvider, /AdminIdentityRepository/);
  assert.match(adminOperatorLockoutProvider, /recordLoginAudit/);
  assert.match(adminOperatorLockoutProvider, /recordLoginSuccess/);
  assert.match(adminOperatorLockoutProvider, /lockedAt/);
  assert.match(adminIdentityPostgresSchema, /CREATE TABLE admin_users/);
  assert.match(adminIdentityPostgresSchema, /login_id VARCHAR\(120\) NOT NULL PRIMARY KEY/);
  assert.match(adminIdentityPostgresSchema, /password_hash VARCHAR\(255\) NOT NULL/);
  assert.match(adminIdentityPostgresSchema, /auth_method VARCHAR\(40\) NOT NULL/);
  assert.match(adminIdentityPostgresSchema, /auth_method IN \('LOCAL', 'BREAK_GLASS'\)/);
  assert.match(adminIdentityPostgresSchema, /role IN \('ADMIN', 'OPERATOR_ADMIN'\)/);
  assert.match(adminIdentityPostgresSchema, /status IN \('ACTIVE', 'DISABLED', 'LOCKED', 'PASSWORD_EXPIRED', 'CREDENTIAL_ROTATION_REQUIRED'\)/);
  assert.match(adminIdentityPostgresSchema, /failed_login_count INTEGER NOT NULL DEFAULT 0/);
  assert.match(adminIdentityPostgresSchema, /failed_login_count >= 0/);
  assert.match(adminIdentityPostgresSchema, /locked_until TIMESTAMP/);
  assert.match(adminIdentityPostgresSchema, /credential_rotation_required BOOLEAN NOT NULL DEFAULT FALSE/);
  assert.match(adminIdentityPostgresSchema, /CREATE TABLE admin_login_audits/);
  assert.match(adminIdentityPostgresSchema, /outcome IN \('FAILED', 'LOCKED', 'DISABLED', 'PASSWORD_EXPIRED', 'CREDENTIAL_ROTATION_REQUIRED', 'SUCCESS'\)/);
  assert.match(adminIdentityPostgresSchema, /idx_admin_login_audits_login_occurred_at/);
  const adminRbacRoleCodes = [...adminRbacRole.matchAll(/^\s*([A-Z_]+)\(/gm)].map((match) => match[1]);
  const adminPermissionCodes = [...adminPermission.matchAll(/^\s*[A-Z_]+\("([^"]+)"\)/gm)].map((match) => match[1]);
  const adminRbacRoleConstraint = `role_code IN (${adminRbacRoleCodes.map((role) => `'${role}'`).join(", ")})`;
  const adminRbacPermissionConstraint =
    `permission_code IN (${adminPermissionCodes.map((permission) => `'${permission}'`).join(", ")})`;
  assert.deepEqual(adminRbacRoleCodes, [
    "ADMIN_VIEWER",
    "REPORT_REVIEWER",
    "MASTER_EDITOR",
    "FIELD_OPERATOR",
    "DATA_OPERATOR",
    "SECURITY_ADMIN",
    "SUPER_ADMIN",
  ]);
  assert.deepEqual(adminPermissionCodes, [
    "admin.view",
    "admin.report.review",
    "admin.report.photo.read",
    "admin.master.edit",
    "admin.field.operate",
    "admin.data.operate",
    "admin.security.audit",
    "admin.security.admin",
    "admin.audit.read",
    "admin.privacy-log.read",
    "admin.batch.retry",
    "admin.operations.manage",
    "admin.datapack.read",
    "admin.datapack.source.run",
    "admin.datapack.alias.review",
    "admin.datapack.quarantine.review",
    "admin.datapack.evidence.review",
    "admin.datapack.override.request",
    "admin.datapack.override.approve",
    "admin.datapack.candidate.build",
    "admin.datapack.staging.promote",
    "admin.datapack.production.approve",
    "admin.datapack.rollback",
    "admin.datapack.audit.read",
  ]);
  for (const adminRbacSchema of [adminRbacPostgresSchema, adminRbacH2Schema]) {
    const compactAdminRbacSchema = adminRbacSchema.replace(/\s+/g, "");
    assert.match(adminRbacSchema, /CREATE TABLE admin_role_permissions/);
    assert.match(adminRbacSchema, /CREATE TABLE admin_user_roles/);
    assert.match(adminRbacSchema, /CREATE TABLE admin_menu_items/);
    assert.match(adminRbacSchema, /CREATE TABLE admin_audit_events/);
    assert.match(adminRbacSchema, /event_type IN \('LOGIN', 'LOGIN_FAILURE', 'LOGOUT', 'ADMIN_ACTION', 'PRIVACY_READ', 'SYSTEM_CHANGE', 'BATCH_OPERATION', 'COMMON_CODE_CHANGE', 'INCIDENT_CHANGE', 'MASTER_DATA_CHANGE'\)/);
    assert.match(adminRbacSchema, /outcome IN \('SUCCESS', 'FAILURE'\)/);
    assert.match(adminRbacSchema, /idx_admin_audit_events_type_occurred_at/);
    assert.match(adminRbacSchema, /CREATE TABLE admin_common_code_groups/);
    assert.match(adminRbacSchema, /CREATE TABLE admin_common_codes/);
    assert.match(adminRbacSchema, /CREATE TABLE admin_incidents/);
    assert.match(adminRbacSchema, /REPORT_REJECTION_REASON/);
    assert.match(adminRbacSchema, /BATCH_FAILURE_CATEGORY/);
    assert.match(adminRbacSchema, /INCIDENT_STATUS/);
    assert.ok(compactAdminRbacSchema.includes(adminRbacRoleConstraint.replace(/\s+/g, "")));
    assert.ok(compactAdminRbacSchema.includes(adminRbacPermissionConstraint.replace(/\s+/g, "")));
    assert.match(adminRbacSchema, /login_id = LOWER\(TRIM\(login_id\)\)/);
    assert.match(adminRbacSchema, /FOREIGN KEY \(parent_program_code\) REFERENCES admin_menu_items\(program_code\)/);
    assert.doesNotMatch(adminRbacSchema, /\b(url|handler|controller|method)_/i);
  }
  assert.match(adminProgramRegistry, /enum AdminProgram/);
  assert.match(adminProgramRegistry, /\/admin\/reports\/page/);
  assert.match(adminProgramRegistry, /AdminPermission\.REPORT_REVIEW/);
  assert.match(adminProgramRegistry, /\/admin\/batches\/page/);
  assert.match(adminProgramRegistry, /AdminPermission\.DATA_OPERATE/);
  assert.match(adminProgramRegistry, /\/admin\/codes\/page/);
  assert.match(adminProgramRegistry, /\/admin\/incidents\/page/);
  assert.match(adminProgramRegistry, /AdminPermission\.OPERATIONS_MANAGE/);
  assert.match(inMemoryAdminRbacAuthorityRepository, /AdminPermission\.values\(\)/);
  assert.match(inMemoryAdminRbacAuthorityRepository, /VALID_AUTHORITIES\.containsAll/);
  assert.match(jdbcAdminRbacAuthorityRepository, /JOIN admin_role_permissions/);
  assert.match(jdbcAdminRbacAuthorityRepository, /FROM admin_user_roles/);
  assert.match(adminIdentityUserDetailsService, /fallbackUserDetailsService/);
  assert.match(adminIdentityUserDetailsService, /credentialsExpired/);
  assert.match(adminIdentityUserDetailsService, /AdminAuthorization\.authoritiesFor/);
  assert.match(jdbcAdminIdentityRepository, /@Profile\("prod \| staging \| release \| prod-like"\)/);
  assert.match(jdbcAdminIdentityRepository, /INSERT INTO admin_users/);
  assert.match(jdbcAdminIdentityRepository, /INSERT INTO admin_login_audits/);
  const abuseControlGate = items.get("backend_report_abuse_control_release_gate");
  assert.match(abuseControlGate.readyWhenKo, /local store|release blocker|분산/);
  assert.ok(abuseControlGate.evidence.includes("facility-report-abuse-control-tests"));
  assert.ok(abuseControlGate.evidence.includes("abuse-store-mode-release-blocker-record"));
  assert.ok(abuseControlGate.evidence.includes("deployment-env-contract"));
  assert.match(facilityReportAbuseControl, /easysubway\.report\.abuse-control\.store-mode/);
  assert.match(facilityReportAbuseControl, /usesReleaseBlockingLocalStore/);
  assert.match(prodConfig, /EASYSUBWAY_REPORT_ABUSE_STORE_MODE:local/);
  assert.match(backendAppEnvAllowlist, /^EASYSUBWAY_REPORT_ABUSE_STORE_MODE$/m);
  assert.match(facilityReportPhotoProcessor, /MAX_PHOTO_BYTES = 900 \* 1024/);
  assert.match(facilityReportPhotoProcessor, /MAX_PHOTO_WIDTH = 4_096/);
  assert.match(facilityReportPhotoProcessor, /MAX_PHOTO_PIXELS = 12_000_000/);
  assert.match(facilityReportPhotoProcessor, /ALLOWED_PHOTO_CONTENT_TYPES/);
  assert.match(facilityReportPhotoProcessor, /"image\/webp"/);
  assert.match(facilityReportPhotoProcessor, /Base64\.getDecoder\(\)\.decode/);
  assert.match(facilityReportPhotoProcessor, /requireSupportedMagic/);
  assert.match(facilityReportPhotoProcessor, /readDimensions/);
  assert.match(facilityReportPhotoProcessor, /ImageIO\.read/);
  const maliciousUploadGate = items.get("backend_report_photo_malicious_upload_defense");
  assert.match(maliciousUploadGate.readyWhenKo, /MIME|extension|magic bytes|checksum|image decode|thumbnail|orphan cleanup/i);
  assert.ok(maliciousUploadGate.evidence.includes("malicious-photo-upload-tests"));
  assert.ok(maliciousUploadGate.evidence.includes("orphan-cleanup-failure-path-test"));
  assert.ok(maliciousUploadGate.linkedArtifacts.includes("backend/src/test/java/com/easysubway/report/application/service/FacilityReportPhotoProcessorTest.java"));
  assert.ok(maliciousUploadGate.linkedArtifacts.includes("backend/src/test/java/com/easysubway/report/application/service/FacilityReportServiceTest.java"));
  const deletionGate = items.get("user_data_deletion_retention_e2e");
  assert.match(deletionGate.readyWhenKo, /local data|report link|photo object|notification|favorite|search|profile/i);
  assert.ok(deletionGate.evidence.includes("backend-user-data-deletion-service-test"));
  assert.ok(deletionGate.evidence.includes("mobile-user-data-deletion-local-test"));
  assert.ok(deletionGate.evidence.includes("android-emulator-deletion-ui-evidence"));
  assert.ok(deletionGate.linkedArtifacts.includes("apps/mobile/test/user_data_deletion_test.dart"));
  assert.match(userDataDeletionService, /deleteUserFavoriteStationPort\.deleteFavoriteStationsByUserId\(normalizedUserId\)/);
  assert.match(userDataDeletionService, /deleteUserNotificationPreferencePort\.deleteNotificationSettings\(normalizedUserId\)/);
  assert.match(userDataDeletionService, /deleteUserMobilityProfilePort\.deleteMobilityProfile\(normalizedUserId\)/);
  assert.match(userDataDeletionService, /anonymizeUserFacilityReportPort\.anonymizeFacilityReportsByUserId\(normalizedUserId\)/);
  assert.match(userDataDeletionTest, /favoriteFacilities\.requestedUserId/);
  assert.match(userDataDeletionTest, /notificationPreferences\.settingsRequestedUserId/);
  assert.match(userDataDeletionTest, /mobilityProfile\.requestedUserId/);
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
  assert.match(items.get("cross_store_privacy_security_consistency").readyWhenKo, /network trace|Data safety|App Privacy|PrivacyInfo/i);
  assert.equal(securityPrivacyEvidence.releaseBlockerPolicy, true);
  assert.ok(securityPrivacyEvidence.sensitiveEvidenceLocalOnlyPath.startsWith(".codex/evidence/"));
  assert.deepEqual(
    securityPrivacyEvidence.releaseArtifactSecretScan.forbiddenClasses.toSorted(),
    ["local-placeholder-endpoint", "provider-key", "receipt-token", "signing-private-key", "upload-url"].toSorted(),
  );
  assert.equal(securityPrivacyEvidence.crashAnrPrivacyEvidence.separateCrashProvider, false);
  assert.ok(securityPrivacyEvidence.crashAnrPrivacyEvidence.sourceOfTruth.includes("Android vitals"));
  assert.ok(securityPrivacyEvidence.crashAnrPrivacyEvidence.sourceOfTruth.includes("Google Play pre-launch report"));
  assert.ok(securityPrivacyEvidence.crashAnrPrivacyEvidence.requiredEvidence.includes("no-crash-sdk-dependency-scan"));
  assert.ok(securityPrivacyEvidence.crashAnrPrivacyEvidence.requiredEvidence.includes("android-vitals-or-play-pre-launch-report-export"));
  assert.ok(securityPrivacyEvidence.crashAnrPrivacyEvidence.forbiddenPayload.includes("precise coordinates"));
  assert.ok(securityPrivacyEvidence.crashAnrPrivacyEvidence.forbiddenPayload.includes("facility report photo"));
  assert.ok(securityPrivacyEvidence.crashAnrPrivacyEvidence.forbiddenPayload.includes("receipt token"));
  assert.ok(securityPrivacyEvidence.userDataDeletionE2E.targets.includes("report photo object 삭제"));
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
  assert.deepEqual(inventory.googlePlayDataSafetyRequiredFields, [
    "collected",
    "collectionType",
    "optional",
    "required",
    "purpose",
    "linkedToUser",
    "encryptedInTransit",
    "deletionSupported",
  ]);
  assert.equal(inventory.crashAnrProviderDecision.separateCrashProvider, false);
  assert.ok(inventory.crashAnrProviderDecision.sourceOfTruth.includes("Android vitals"));
  assert.ok(inventory.crashAnrProviderDecision.sourceOfTruth.includes("Google Play pre-launch report"));
  assert.ok(inventory.crashAnrProviderDecision.requiredEvidence.includes("android-vitals-or-play-pre-launch-report-export"));
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
    assert.equal(typeof item.googlePlayDataSafety.collected, "boolean", `${id} must declare Play collection`);
    assert.equal(
      item.googlePlayDataSafety.collected,
      item.implementationStatus !== "local-only",
      `${id} Play collection must match release collection status`,
    );
    assert.equal(typeof item.googlePlayDataSafety.collectionType, "string", `${id} must declare Play collection type`);
    assert.ok(item.googlePlayDataSafety.collectionType.length > 0, `${id} collection type must not be empty`);
    assert.equal(typeof item.googlePlayDataSafety.purpose, "string", `${id} must declare Play purpose`);
    assert.equal(typeof item.googlePlayDataSafety.linkedToUser, "boolean", `${id} must declare Play linked-to-user value`);
    if (item.googlePlayDataSafety.collected) {
      assert.equal(item.googlePlayDataSafety.linkedToUser, true, `${id} collected Play data must be linked to user`);
    }
    assert.equal(
      item.googlePlayDataSafety.encryptedInTransit,
      true,
      `${id} must require encrypted transport`,
    );
    assert.equal(typeof item.googlePlayDataSafety.optional, "boolean", `${id} must declare optional value`);
    assert.equal(typeof item.googlePlayDataSafety.required, "boolean", `${id} must declare required value`);
    if (item.googlePlayDataSafety.collected) {
      assert.equal(
        item.googlePlayDataSafety.required,
        !item.googlePlayDataSafety.optional,
        `${id} Play required value must be the inverse of optional`,
      );
    } else {
      assert.equal(item.googlePlayDataSafety.required, false, `${id} not-collected Play data must not be required`);
    }
    assert.equal(item.googlePlayDataSafety.deletionSupported, true, `${id} must declare data deletion support`);
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
  assert.equal(items.get("precise_location").googlePlayDataSafety.optional, true);
  assert.equal(items.get("precise_location").googlePlayDataSafety.collectionType, "user-triggered");
  assert.equal(items.get("facility_report_photo").googlePlayDataSafety.optional, true);
  assert.equal(items.get("facility_report_photo").googlePlayDataSafety.collectionType, "user-triggered");
  assert.equal(items.get("facility_report_location").googlePlayDataSafety.optional, true);
  assert.equal(items.get("facility_report_location").googlePlayDataSafety.collectionType, "user-triggered");
  assert.equal(items.get("diagnostics_crash_logs").googlePlayDataSafety.dataType, "Diagnostics");
  assert.equal(items.get("diagnostics_crash_logs").googlePlayDataSafety.collected, false);
  assert.equal(items.get("diagnostics_crash_logs").googlePlayDataSafety.collectionType, "local-only-diagnostic-event");
  assert.equal(items.get("diagnostics_crash_logs").googlePlayDataSafety.linkedToUser, false);
  assert.equal(items.get("diagnostics_performance_logs").googlePlayDataSafety.collected, true);
  assert.equal(items.get("diagnostics_performance_logs").googlePlayDataSafety.collectionType, "diagnostic-event");
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
