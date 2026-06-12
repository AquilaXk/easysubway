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

test("backend scaffold is a Spring Boot 3.5 Java 21 Gradle project", () => {
  const build = read("backend/build.gradle");
  const wrapper = read("backend/gradle/wrapper/gradle-wrapper.properties");
  const application = read("backend/src/main/java/com/easysubway/EasySubwayBackendApplication.java");
  const controller = read("backend/src/main/java/com/easysubway/api/health/HealthCheckController.java");
  const properties = read("backend/src/main/resources/application.properties");

  assert.ok(existsSync(path.join(root, "backend/gradlew")));
  assert.ok(existsSync(path.join(root, "backend/gradle/wrapper/gradle-wrapper.jar")));
  assert.match(wrapper, /gradle-8\.14\.5-bin\.zip/);

  assert.match(build, /id 'org\.springframework\.boot' version '3\.5\.\d+'/);
  assert.match(build, /languageVersion = JavaLanguageVersion\.of\(21\)/);
  assert.match(build, /implementation 'org\.springframework\.boot:spring-boot-starter-web'/);
  assert.match(build, /implementation 'org\.springframework\.boot:spring-boot-starter-actuator'/);
  assert.match(build, /testImplementation 'org\.springframework\.boot:spring-boot-starter-test'/);

  assert.match(application, /@SpringBootApplication/);
  assert.match(controller, /@GetMapping\("\/api\/health"\)/);
  assert.match(controller, /easysubway-backend/);
  assert.match(properties, /spring\.application\.name=easysubway-backend/);
  assert.match(properties, /management\.endpoints\.web\.exposure\.include=health,info/);
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
  assert.equal(mobile.android, "false");
  assert.equal(mobile.ios, "false");

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
