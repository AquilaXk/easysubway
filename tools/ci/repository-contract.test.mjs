import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, writeFile } from "node:fs/promises";
import { existsSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";

const root = process.cwd();
const execFileAsync = promisify(execFile);

function read(relativePath) {
  return readFileSync(path.join(root, relativePath), "utf8");
}

test("gitignore keeps local agent docs and non-README markdown out of git", () => {
  const gitignore = read(".gitignore");

  assert.match(gitignore, /^\*\.md$/m);
  assert.match(gitignore, /^!\/README\.md$/m);
  assert.match(gitignore, /^!\/\.github\/pull_request_template\.md$/m);
  assert.match(gitignore, /^AGENTS\.md$/m);
  assert.match(gitignore, /^docs\/$/m);
  assert.match(gitignore, /^\.codex\/$/m);
});

test("ci enforces README-only markdown and local agent file policy", () => {
  const workflow = read(".github/workflows/ci.yml");

  assert.match(workflow, /git ls-files '\*\.md' ':!:README\.md' ':!:\.github\/pull_request_template\.md'/);
  assert.match(workflow, /Unexpected tracked Markdown file/);
  assert.match(workflow, /git ls-files AGENTS\.md CLAUDE\.md GEMINI\.md CURSOR\.md COPILOT\.md docs \.codex/);
  assert.match(workflow, /Unexpected tracked local agent file/);
});

test("ci job and step names identify failure areas clearly", () => {
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
  assert.match(workflow, /Android CI \/ Build Flutter Android debug APK/);
  assert.match(workflow, /iOS CI \/ Build Flutter iOS simulator app/);
});

test("pull request template is tracked with review and CD gates", () => {
  const template = read(".github/pull_request_template.md");

  assert.match(template, /## 관련 이슈/);
  assert.match(template, /## 검증/);
  assert.match(template, /실행한 명령과 결과/);
  assert.match(template, /리뷰어가 먼저 봐야 할 지점/);
  assert.match(template, /CodeRabbit 리뷰를 확인했다/);
  assert.match(template, /Codex CLI code review 결과를 확인했다/);
  assert.match(template, /CD 상태를 확인했다/);
});

test("issue templates collect developer-style context without agent narration", () => {
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

test("coderabbit is configured for Korean repository reviews", () => {
  const config = read(".coderabbit.yaml");

  assert.match(config, /language: "ko-KR"/);
  assert.match(config, /path: "backend\/\*\*"/);
  assert.match(config, /path: "apps\/mobile\/lib\/\*\*"/);
  assert.match(config, /path: "\.github\/workflows\/\*\*"/);
  assert.match(config, /auto_review:/);
});

test("env example provides non-secret local data infrastructure defaults", () => {
  const envExample = read(".env.example");

  assert.match(envExample, /^EASYSUBWAY_POSTGRES_DB=easysubway$/m);
  assert.match(envExample, /^EASYSUBWAY_POSTGRES_USER=easysubway$/m);
  assert.match(envExample, /^EASYSUBWAY_POSTGRES_PASSWORD=easysubway_local$/m);
  assert.match(envExample, /^EASYSUBWAY_POSTGRES_PORT=5432$/m);
  assert.match(envExample, /^EASYSUBWAY_REDIS_PORT=6379$/m);
  assert.doesNotMatch(envExample, /prod|production|secret|token|key/i);
});

test("docker compose defines local PostGIS and Redis services", () => {
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

test("repository ci validates docker compose configuration", () => {
  const workflow = read(".github/workflows/ci.yml");

  assert.match(workflow, /Repository CI \/ Validate Docker Compose config/);
  assert.match(workflow, /docker compose --env-file \.env\.example -f infra\/docker-compose\.yml config --quiet/);
});

test("backend scaffold is an eGovFrame 5.0 Spring Boot Java 21 hexagonal project", () => {
  const build = read("backend/build.gradle");
  const wrapper = read("backend/gradle/wrapper/gradle-wrapper.properties");
  const application = read("backend/src/main/java/com/easysubway/EasySubwayBackendApplication.java");
  const domain = read("backend/src/main/java/com/easysubway/health/domain/HealthStatus.java");
  const port = read("backend/src/main/java/com/easysubway/health/application/port/in/CheckHealthUseCase.java");
  const service = read("backend/src/main/java/com/easysubway/health/application/service/HealthCheckService.java");
  const controller = read("backend/src/main/java/com/easysubway/health/adapter/in/web/HealthCheckController.java");
  const apiResponse = read("backend/src/main/java/com/easysubway/common/web/ApiResponse.java");
  const properties = read("backend/src/main/resources/application.properties");

  assert.ok(existsSync(path.join(root, "backend/gradlew")));
  assert.ok(existsSync(path.join(root, "backend/gradle/wrapper/gradle-wrapper.jar")));
  assert.match(wrapper, /gradle-8\.14\.5-bin\.zip/);

  assert.match(build, /id 'org\.springframework\.boot' version '3\.5\.6'/);
  assert.match(build, /languageVersion = JavaLanguageVersion\.of\(21\)/);
  assert.match(build, /https:\/\/maven\.egovframe\.go\.kr\/maven/);
  assert.match(build, /mavenBom 'org\.egovframe\.boot:egovframe-boot-starter-parent:5\.0\.0'/);
  assert.match(build, /implementation 'org\.egovframe\.rte:egovframe-rte-ptl-mvc'/);
  assert.match(build, /implementation 'org\.springframework\.boot:spring-boot-starter-web'/);
  assert.match(build, /implementation 'org\.springframework\.boot:spring-boot-starter-actuator'/);
  assert.match(build, /testImplementation 'org\.springframework\.boot:spring-boot-starter-test'/);

  assert.match(application, /@SpringBootApplication/);
  assert.match(domain, /record HealthStatus/);
  assert.match(port, /interface CheckHealthUseCase/);
  assert.match(service, /implements CheckHealthUseCase/);
  assert.match(service, /easysubway-backend/);
  assert.match(controller, /@GetMapping\("\/api\/health"\)/);
  assert.match(controller, /CheckHealthUseCase/);
  assert.match(apiResponse, /record ApiResponse/);
  assert.match(properties, /spring\.application\.name=easysubway-backend/);
  assert.match(properties, /management\.endpoints\.web\.exposure\.include=health,info/);
});

test("backend transit master follows hexagonal API boundaries", () => {
  const operator = read("backend/src/main/java/com/easysubway/transit/domain/TransitOperator.java");
  const line = read("backend/src/main/java/com/easysubway/transit/domain/SubwayLine.java");
  const station = read("backend/src/main/java/com/easysubway/transit/domain/Station.java");
  const stationExit = read("backend/src/main/java/com/easysubway/transit/domain/StationExit.java");
  const facility = read("backend/src/main/java/com/easysubway/transit/domain/AccessibilityFacility.java");
  const quality = read("backend/src/main/java/com/easysubway/transit/domain/DataQualityLevel.java");
  const confidence = read("backend/src/main/java/com/easysubway/transit/domain/DataConfidenceLevel.java");
  const facilityType = read("backend/src/main/java/com/easysubway/transit/domain/AccessibilityFacilityType.java");
  const facilityStatus = read("backend/src/main/java/com/easysubway/transit/domain/AccessibilityFacilityStatus.java");
  const source = read("backend/src/main/java/com/easysubway/transit/domain/DataSourceType.java");
  const useCase = read("backend/src/main/java/com/easysubway/transit/application/port/in/TransitMasterQueryUseCase.java");
  const outboundPort = read("backend/src/main/java/com/easysubway/transit/application/port/out/LoadTransitMasterPort.java");
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
  assert.match(source, /OFFICIAL_FILE/);
  assert.match(useCase, /interface TransitMasterQueryUseCase/);
  assert.match(useCase, /listStationExits/);
  assert.match(useCase, /listStationFacilities/);
  assert.match(outboundPort, /interface LoadTransitMasterPort/);
  assert.match(outboundPort, /loadStationExits/);
  assert.match(outboundPort, /loadAccessibilityFacilities/);
  assert.match(service, /implements TransitMasterQueryUseCase/);
  assert.match(repository, /implements LoadTransitMasterPort/);
  assert.match(controller, /@GetMapping\("\/api\/v1\/operators"\)/);
  assert.match(controller, /@GetMapping\("\/api\/v1\/lines"\)/);
  assert.match(controller, /@GetMapping\("\/api\/v1\/stations"\)/);
  assert.match(controller, /@GetMapping\("\/api\/v1\/stations\/\{stationId\}"\)/);
  assert.match(controller, /@GetMapping\("\/api\/v1\/stations\/\{stationId\}\/exits"\)/);
  assert.match(controller, /@GetMapping\("\/api\/v1\/stations\/\{stationId\}\/facilities"\)/);
  assert.match(exceptionHandler, /@ExceptionHandler\(HttpMessageNotReadableException\.class\)/);
  assert.match(exceptionHandler, /@ExceptionHandler\(InvalidRequestException\.class\)/);
  assert.match(exceptionHandler, /@ExceptionHandler\(ResourceNotFoundException\.class\)/);
});

test("backend facility reports follow hexagonal API boundaries", () => {
  const report = read("backend/src/main/java/com/easysubway/report/domain/FacilityReport.java");
  const reportType = read("backend/src/main/java/com/easysubway/report/domain/FacilityReportType.java");
  const reportStatus = read("backend/src/main/java/com/easysubway/report/domain/FacilityReportStatus.java");
  const invalidReport = read("backend/src/main/java/com/easysubway/report/domain/InvalidFacilityReportException.java");
  const useCase = read("backend/src/main/java/com/easysubway/report/application/port/in/FacilityReportUseCase.java");
  const command = read("backend/src/main/java/com/easysubway/report/application/port/in/CreateFacilityReportCommand.java");
  const loadPort = read("backend/src/main/java/com/easysubway/report/application/port/out/LoadFacilityReportPort.java");
  const savePort = read("backend/src/main/java/com/easysubway/report/application/port/out/SaveFacilityReportPort.java");
  const service = read("backend/src/main/java/com/easysubway/report/application/service/FacilityReportService.java");
  const repository = read("backend/src/main/java/com/easysubway/report/adapter/out/persistence/InMemoryFacilityReportRepository.java");
  const controller = read("backend/src/main/java/com/easysubway/report/adapter/in/web/FacilityReportController.java");

  assert.match(report, /record FacilityReport/);
  assert.match(report, /reviewedAt/);
  assert.match(reportType, /BROKEN/);
  assert.match(reportType, /LOCATION_WRONG/);
  assert.match(reportStatus, /SUBMITTED/);
  assert.match(reportStatus, /RESOLVED/);
  assert.match(invalidReport, /extends InvalidRequestException/);
  assert.match(useCase, /interface FacilityReportUseCase/);
  assert.match(useCase, /createReport/);
  assert.match(useCase, /getReport/);
  assert.match(command, /record CreateFacilityReportCommand/);
  assert.match(loadPort, /interface LoadFacilityReportPort/);
  assert.match(savePort, /interface SaveFacilityReportPort/);
  assert.match(service, /implements FacilityReportUseCase/);
  assert.match(service, /LoadTransitMasterPort/);
  assert.match(service, /FacilityReportStatus\.SUBMITTED/);
  assert.match(repository, /implements LoadFacilityReportPort, SaveFacilityReportPort/);
  assert.match(controller, /@PostMapping\("\/api\/v1\/reports"\)/);
  assert.match(controller, /@GetMapping\("\/api\/v1\/reports\/\{reportId\}"\)/);
  assert.match(controller, /@ResponseStatus\(HttpStatus\.CREATED\)/);
});

test("backend mobility profiles follow hexagonal API boundaries", () => {
  const profile = read("backend/src/main/java/com/easysubway/profile/domain/MobilityProfile.java");
  const mobilityType = read("backend/src/main/java/com/easysubway/profile/domain/MobilityType.java");
  const invalidProfile = read("backend/src/main/java/com/easysubway/profile/domain/InvalidMobilityProfileException.java");
  const useCase = read("backend/src/main/java/com/easysubway/profile/application/port/in/MobilityProfileUseCase.java");
  const command = read("backend/src/main/java/com/easysubway/profile/application/port/in/SaveMobilityProfileCommand.java");
  const loadPort = read("backend/src/main/java/com/easysubway/profile/application/port/out/LoadMobilityProfilePort.java");
  const savePort = read("backend/src/main/java/com/easysubway/profile/application/port/out/SaveMobilityProfilePort.java");
  const service = read("backend/src/main/java/com/easysubway/profile/application/service/MobilityProfileService.java");
  const repository = read("backend/src/main/java/com/easysubway/profile/adapter/out/persistence/InMemoryMobilityProfileRepository.java");
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
  assert.match(repository, /implements LoadMobilityProfilePort, SaveMobilityProfilePort/);
  assert.match(controller, /@GetMapping\("\/api\/v1\/me\/mobility-profile"\)/);
  assert.match(controller, /@PutMapping\("\/api\/v1\/me\/mobility-profile"\)/);
});

test("mobile scaffold is a Flutter Android and iOS app", () => {
  const pubspec = read("apps/mobile/pubspec.yaml");
  const analysisOptions = read("apps/mobile/analysis_options.yaml");
  const androidManifest = read("apps/mobile/android/app/src/main/AndroidManifest.xml");
  const iosInfoPlist = read("apps/mobile/ios/Runner/Info.plist");
  const main = read("apps/mobile/lib/main.dart");
  const widgetTest = read("apps/mobile/test/widget_test.dart");

  assert.ok(existsSync(path.join(root, "apps/mobile/android")));
  assert.ok(existsSync(path.join(root, "apps/mobile/ios")));
  assert.ok(existsSync(path.join(root, "apps/mobile/pubspec.lock")));

  assert.match(pubspec, /^name: easysubway_mobile$/m);
  assert.match(pubspec, /sdk: \^3\./);
  assert.match(pubspec, /flutter_lints:/);
  assert.match(pubspec, /uses-material-design: true/);
  assert.match(analysisOptions, /package:flutter_lints\/flutter\.yaml/);
  assert.match(androidManifest, /android:label="쉬운 지하철"/);
  assert.match(iosInfoPlist, /CFBundleDisplayName[\s\S]*?<string>쉬운 지하철<\/string>/);
  assert.match(main, /class EasySubwayApp extends StatelessWidget/);
  assert.match(main, /역 찾기/);
  assert.match(main, /역 검색/);
  assert.match(main, /이동 조건/);
  assert.match(main, /semanticLabel: '시설 정보, 엘리베이터와 경사로'/);
  assert.ok(existsSync(path.join(root, "apps/mobile/lib/station_search.dart")));
  assert.doesNotMatch(main, /빠른 길보다, 갈 수 있는 길을 먼저 안내합니다|고령자, 임산부, 장애인도 편하게 이동할 수 있도록|현장에서 발견한 불편 정보를 신고하고 검수할 수 있게/);
  assert.match(widgetTest, /EasySubwayApp/);
  assert.match(widgetTest, /renders concise home screen actions/);
  assert.match(widgetTest, /bySemanticsLabel/);
  assert.match(widgetTest, /greaterThanOrEqualTo\(60\)/);
});

test("path classifier treats README as docs-only", async () => {
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

test("path classifier maps repository, backend, mobile, Android, and iOS changes", async () => {
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

test("path classifier tests are stable when GITHUB_OUTPUT is inherited from CI", async () => {
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
