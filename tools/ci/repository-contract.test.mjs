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
