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

function jobBlock(workflow, startJob, nextJob) {
  const pattern = new RegExp(`  ${startJob}:[\\s\\S]*?\\n  ${nextJob}:`);
  const match = workflow.match(pattern);
  assert.ok(match, `${startJob} job block not found`);
  return match[0];
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
  assert.match(envExample, /^EASYSUBWAY_REDIS_PORT=6379$/m);
  assert.doesNotMatch(envExample, /prod|production|secret|token|key/i);
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
  const useCase = read("backend/src/main/java/com/easysubway/auth/application/port/in/AnonymousAuthUseCase.java");
  const registerPort = read("backend/src/main/java/com/easysubway/auth/application/port/out/RegisterAnonymousUserPort.java");
  const service = read("backend/src/main/java/com/easysubway/auth/application/service/AnonymousAuthService.java");
  const registry = read("backend/src/main/java/com/easysubway/auth/adapter/out/security/SpringSecurityAnonymousUserRegistry.java");
  const rateLimiter = read("backend/src/main/java/com/easysubway/auth/adapter/in/web/AnonymousAuthRateLimiter.java");
  const controller = read("backend/src/main/java/com/easysubway/auth/adapter/in/web/AnonymousAuthController.java");
  const security = read("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java");
  const userDetailsManager = read("backend/src/main/java/com/easysubway/common/security/ConcurrentUserDetailsManager.java");

  assert.match(credentials, /record AnonymousUserCredentials/);
  assert.match(credentials, /userId/);
  assert.match(credentials, /password/);
  assert.match(credentials, /createdAt/);
  assert.match(authenticatedUser, /record AuthenticatedUser/);
  assert.match(authenticatedUser, /authType/);
  assert.match(authenticatedUser, /anonymous/);
  assert.match(invalidAuth, /extends InvalidRequestException/);
  assert.match(useCase, /interface AnonymousAuthUseCase/);
  assert.match(useCase, /issueAnonymousUser/);
  assert.match(useCase, /currentUser/);
  assert.match(registerPort, /interface RegisterAnonymousUserPort/);
  assert.match(registerPort, /existsByUserId/);
  assert.match(registerPort, /isAnonymousUser/);
  assert.match(registerPort, /registerAnonymousUser/);
  assert.match(service, /implements AnonymousAuthUseCase/);
  assert.match(service, /RegisterAnonymousUserPort/);
  assert.match(registry, /implements RegisterAnonymousUserPort/);
  assert.match(registry, /UserDetailsManager/);
  assert.match(registry, /PasswordEncoder/);
  assert.match(registry, /MAX_ANONYMOUS_USERS/);
  assert.match(registry, /deleteUser/);
  assert.match(userDetailsManager, /implements UserDetailsManager, UserDetailsPasswordService/);
  assert.match(userDetailsManager, /ConcurrentHashMap/);
  assert.doesNotMatch(security, /InMemoryUserDetailsManager/);
  assert.match(rateLimiter, /class AnonymousAuthRateLimiter/);
  assert.match(rateLimiter, /MAX_ISSUE_REQUESTS_PER_CLIENT/);
  assert.match(controller, /@PostMapping\("\/api\/v1\/auth\/anonymous"\)/);
  assert.match(controller, /AnonymousAuthRateLimiter/);
  assert.match(controller, /HttpStatus\.TOO_MANY_REQUESTS/);
  assert.match(controller, /@GetMapping\("\/api\/v1\/me"\)/);
  assert.match(controller, /Principal principal/);
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
  const transitRepository = read(
    "backend/src/main/java/com/easysubway/transit/adapter/out/persistence/InMemoryTransitMasterRepository.java",
  );
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
  assert.match(repository, /implements LoadFacilityReportPort, SaveFacilityReportPort/);
  assert.match(repository, /List<FacilityReport> loadReports\(\)/);
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

test("백엔드 즐겨찾기 역은 헥사고날 API 경계를 따른다", () => {
  const favorite = read("backend/src/main/java/com/easysubway/favorite/domain/FavoriteStation.java");
  const favoriteDetails = read("backend/src/main/java/com/easysubway/favorite/domain/FavoriteStationWithDetails.java");
  const invalidFavorite = read("backend/src/main/java/com/easysubway/favorite/domain/InvalidFavoriteStationException.java");
  const useCase = read("backend/src/main/java/com/easysubway/favorite/application/port/in/FavoriteStationUseCase.java");
  const listCommand = read("backend/src/main/java/com/easysubway/favorite/application/port/in/ListFavoriteStationsCommand.java");
  const saveCommand = read("backend/src/main/java/com/easysubway/favorite/application/port/in/SaveFavoriteStationCommand.java");
  const removeCommand = read("backend/src/main/java/com/easysubway/favorite/application/port/in/RemoveFavoriteStationCommand.java");
  const loadPort = read("backend/src/main/java/com/easysubway/favorite/application/port/out/LoadFavoriteStationPort.java");
  const savePort = read("backend/src/main/java/com/easysubway/favorite/application/port/out/SaveFavoriteStationPort.java");
  const deletePort = read("backend/src/main/java/com/easysubway/favorite/application/port/out/DeleteFavoriteStationPort.java");
  const service = read("backend/src/main/java/com/easysubway/favorite/application/service/FavoriteStationService.java");
  const repository = read("backend/src/main/java/com/easysubway/favorite/adapter/out/persistence/InMemoryFavoriteStationRepository.java");
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
  assert.match(savePort, /interface SaveFavoriteStationPort/);
  assert.match(deletePort, /interface DeleteFavoriteStationPort/);
  assert.match(service, /implements FavoriteStationUseCase/);
  assert.match(service, /LoadTransitMasterPort/);
  assert.match(service, /StationNotFoundException/);
  assert.match(repository, /implements[\s\S]*LoadFavoriteStationPort[\s\S]*SaveFavoriteStationPort[\s\S]*DeleteFavoriteStationPort/);
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
  const savePort = read("backend/src/main/java/com/easysubway/favorite/application/port/out/SaveFavoriteFacilityPort.java");
  const deletePort = read("backend/src/main/java/com/easysubway/favorite/application/port/out/DeleteFavoriteFacilityPort.java");
  const service = read("backend/src/main/java/com/easysubway/favorite/application/service/FavoriteFacilityService.java");
  const repository = read("backend/src/main/java/com/easysubway/favorite/adapter/out/persistence/InMemoryFavoriteFacilityRepository.java");
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
  assert.match(savePort, /interface SaveFavoriteFacilityPort/);
  assert.match(deletePort, /interface DeleteFavoriteFacilityPort/);
  assert.match(service, /implements FavoriteFacilityUseCase/);
  assert.match(service, /LoadTransitMasterPort/);
  assert.match(service, /loadAccessibilityFacilities/);
  assert.match(service, /FavoriteFacilityNotFoundException/);
  assert.match(repository, /implements[\s\S]*LoadFavoriteFacilityPort[\s\S]*SaveFavoriteFacilityPort[\s\S]*DeleteFavoriteFacilityPort/);
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
  const savePort = read("backend/src/main/java/com/easysubway/favorite/application/port/out/SaveFavoriteRoutePort.java");
  const deletePort = read("backend/src/main/java/com/easysubway/favorite/application/port/out/DeleteFavoriteRoutePort.java");
  const service = read("backend/src/main/java/com/easysubway/favorite/application/service/FavoriteRouteService.java");
  const repository = read("backend/src/main/java/com/easysubway/favorite/adapter/out/persistence/InMemoryFavoriteRouteRepository.java");
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
  assert.match(savePort, /interface SaveFavoriteRoutePort/);
  assert.match(deletePort, /interface DeleteFavoriteRoutePort/);
  assert.match(service, /implements FavoriteRouteUseCase/);
  assert.match(service, /LoadRouteSearchPort/);
  assert.match(service, /RouteSearchNotFoundException/);
  assert.match(repository, /implements[\s\S]*LoadFavoriteRoutePort[\s\S]*SaveFavoriteRoutePort[\s\S]*DeleteFavoriteRoutePort/);
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
  const type = read("backend/src/main/java/com/easysubway/notification/domain/PushNotificationType.java");
  const status = read("backend/src/main/java/com/easysubway/notification/domain/PushNotificationStatus.java");
  const invalidPush = read("backend/src/main/java/com/easysubway/notification/domain/InvalidPushNotificationException.java");
  const useCase = read("backend/src/main/java/com/easysubway/notification/application/port/in/PushNotificationDispatchUseCase.java");
  const command = read("backend/src/main/java/com/easysubway/notification/application/port/in/DispatchPushNotificationCommand.java");
  const loadOutboxPort = read("backend/src/main/java/com/easysubway/notification/application/port/out/LoadPushNotificationOutboxPort.java");
  const saveOutboxPort = read("backend/src/main/java/com/easysubway/notification/application/port/out/SavePushNotificationOutboxPort.java");
  const service = read("backend/src/main/java/com/easysubway/notification/application/service/PushNotificationDispatchService.java");
  const repository = read("backend/src/main/java/com/easysubway/notification/adapter/out/persistence/InMemoryPushNotificationOutboxRepository.java");
  const controller = read("backend/src/main/java/com/easysubway/notification/adapter/in/web/PushNotificationController.java");
  const security = read("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java");

  assert.match(notification, /record PushNotification/);
  assert.match(notification, /deviceToken/);
  assert.match(notification, /PushNotificationStatus/);
  assert.match(result, /record PushNotificationDispatchResult/);
  assert.match(type, /FAVORITE_STATION_FACILITY/);
  assert.match(type, /FAVORITE_ROUTE_FACILITY/);
  assert.match(type, /REPORT_STATUS/);
  assert.match(type, /DATA_QUALITY/);
  assert.match(status, /PENDING/);
  assert.match(invalidPush, /extends InvalidRequestException/);
  assert.match(useCase, /interface PushNotificationDispatchUseCase/);
  assert.match(useCase, /dispatch/);
  assert.match(command, /record DispatchPushNotificationCommand/);
  assert.match(loadOutboxPort, /interface LoadPushNotificationOutboxPort/);
  assert.match(saveOutboxPort, /interface SavePushNotificationOutboxPort/);
  assert.match(service, /implements PushNotificationDispatchUseCase/);
  assert.match(service, /LoadNotificationPreferencePort/);
  assert.match(service, /SavePushNotificationOutboxPort/);
  assert.match(repository, /implements[\s\S]*LoadPushNotificationOutboxPort[\s\S]*SavePushNotificationOutboxPort/);
  assert.match(controller, /@PostMapping\("\/admin\/notifications\/push"\)/);
  assert.match(controller, /PushNotificationDispatchUseCase/);
  assert.doesNotMatch(controller, /deviceToken/);
  assert.match(security, /securityMatcher\("\/admin\/\*\*"\)/);
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
  assert.match(repository, /loadRun\(String runId\)/);
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
  const security = read("backend/src/main/java/com/easysubway/common/security/SecurityConfig.java");

  assert.match(summary, /record DataQualitySummary/);
  assert.match(summary, /stationQualityCounts/);
  assert.match(summary, /exitConfidenceCounts/);
  assert.match(summary, /facilityConfidenceCounts/);
  assert.match(summary, /needsVerificationFacilityCount/);
  assert.match(useCase, /interface DataQualityUseCase/);
  assert.match(useCase, /summarizeDataQuality/);
  assert.match(service, /implements DataQualityUseCase/);
  assert.match(service, /LoadTransitMasterPort/);
  assert.match(service, /DataConfidenceLevel\.NEEDS_VERIFICATION/);
  assert.match(service, /AccessibilityFacilityStatus\.UNKNOWN/);
  assert.match(controller, /@GetMapping\("\/admin\/data-quality\/summary"\)/);
  assert.match(controller, /DataQualityUseCase/);
  assert.match(security, /securityMatcher\("\/admin\/\*\*"\)/);
});

test("백엔드 경로 검색은 헥사고날 API 경계를 따른다", () => {
  const result = read("backend/src/main/java/com/easysubway/route/domain/RouteSearchResult.java");
  const status = read("backend/src/main/java/com/easysubway/route/domain/RouteSearchStatus.java");
  const warning = read("backend/src/main/java/com/easysubway/route/domain/RouteWarning.java");
  const warningCode = read("backend/src/main/java/com/easysubway/route/domain/RouteWarningCode.java");
  const profileWeight = read("backend/src/main/java/com/easysubway/route/domain/RouteProfileWeight.java");
  const step = read("backend/src/main/java/com/easysubway/route/domain/RouteStep.java");
  const invalidSearch = read("backend/src/main/java/com/easysubway/route/domain/InvalidRouteSearchException.java");
  const routeNotFound = read("backend/src/main/java/com/easysubway/route/domain/RouteNotFoundException.java");
  const searchNotFound = read("backend/src/main/java/com/easysubway/route/domain/RouteSearchNotFoundException.java");
  const useCase = read("backend/src/main/java/com/easysubway/route/application/port/in/RouteSearchUseCase.java");
  const command = read("backend/src/main/java/com/easysubway/route/application/port/in/SearchRouteCommand.java");
  const loadPort = read("backend/src/main/java/com/easysubway/route/application/port/out/LoadRouteSearchPort.java");
  const savePort = read("backend/src/main/java/com/easysubway/route/application/port/out/SaveRouteSearchPort.java");
  const service = read("backend/src/main/java/com/easysubway/route/application/service/RouteSearchService.java");
  const repository = read("backend/src/main/java/com/easysubway/route/adapter/out/persistence/InMemoryRouteSearchRepository.java");
  const controller = read("backend/src/main/java/com/easysubway/route/adapter/in/web/RouteSearchController.java");

  assert.match(result, /record RouteSearchResult/);
  assert.match(result, /mobilityType/);
  assert.match(result, /blockedReasons/);
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
  assert.match(command, /record SearchRouteCommand/);
  assert.match(loadPort, /interface LoadRouteSearchPort/);
  assert.match(savePort, /interface SaveRouteSearchPort/);
  assert.match(service, /implements RouteSearchUseCase/);
  assert.match(service, /LoadTransitMasterPort/);
  assert.match(service, /RouteProfileWeight\.from/);
  assert.match(service, /RouteSearchStatus\.BLOCKED/);
  assert.match(service, /hasStairOnlyAccess/);
  assert.match(service, /routeScore/);
  assert.match(repository, /implements LoadRouteSearchPort, SaveRouteSearchPort/);
  assert.match(controller, /@PostMapping\("\/api\/v1\/routes\/search"\)/);
  assert.match(controller, /@GetMapping\("\/api\/v1\/routes\/\{routeSearchId\}"\)/);
});

test("모바일 스캐폴드는 Flutter Android와 iOS 앱 구조를 가진다", () => {
  const pubspec = read("apps/mobile/pubspec.yaml");
  const analysisOptions = read("apps/mobile/analysis_options.yaml");
  const androidManifest = read("apps/mobile/android/app/src/main/AndroidManifest.xml");
  const iosInfoPlist = read("apps/mobile/ios/Runner/Info.plist");
  const main = read("apps/mobile/lib/main.dart");
  const authHeaders = read("apps/mobile/lib/auth_headers.dart");
  const anonymousAuth = read("apps/mobile/lib/anonymous_auth.dart");
  const anonymousAuthTest = read("apps/mobile/test/anonymous_auth_test.dart");
  const onboarding = read("apps/mobile/lib/onboarding.dart");
  const onboardingTest = read("apps/mobile/test/onboarding_test.dart");
  const routeSearch = read("apps/mobile/lib/route_search.dart");
  const stationSearch = read("apps/mobile/lib/station_search.dart");
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
  assert.match(iosInfoPlist, /CFBundleDisplayName[\s\S]*?<string>쉬운 지하철<\/string>/);
  assert.match(main, /class EasySubwayApp extends StatelessWidget/);
  assert.match(main, /역 찾기/);
  assert.match(main, /역 검색/);
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
  assert.match(main, /if \(!simpleViewEnabled\)/);
  assert.match(main, /semanticLabel: '시설 정보, 엘리베이터와 경사로'/);
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
  assert.match(routeSearch, /_resolveInitialMobilityType/);
  assert.match(routeSearch, /_selectedMobilityType = widget\.initialMobilityType/);
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
  assert.match(stationSearch, /_httpClient\s*\.\s*getUrl\(uri\)\s*\.\s*timeout\(_stationSearchTimeout\)/);
  assert.match(stationSearch, /request\.close\(\)\.timeout\(_stationSearchTimeout\)/);
  assert.match(stationSearch, /HttpStatus\.unauthorized/);
  assert.match(stationSearch, /invalidateAuthorization\(\)/);
  assert.match(read("apps/mobile/test/station_search_test.dart"), /인증 실패 시 인증을 지우고 한 번 재시도한다/);
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
  assert.match(widgetTest, /홈 화면은 핵심 행동만 간결하게 보여준다/);
  assert.match(widgetTest, /알림 설정 화면은 현재 설정을 불러오고 바꾼 값을 저장한다/);
  assert.match(widgetTest, /bySemanticsLabel/);
  assert.match(widgetTest, /greaterThanOrEqualTo\(60\)/);
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
