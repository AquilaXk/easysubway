import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

const workflowUrl = new URL("../../.github/workflows/automerge-queue.yml", import.meta.url);
const coordinator = readFileSync(workflowUrl, "utf8");
const reviewJqDefs = coordinator.match(/review_jq_defs="\$\(cat <<'JQ'\n([\s\S]*?)\n {10}JQ\n {10}\)"/)?.[1] ?? "";
const reviewGateBody =
  coordinator.match(
    /review_gate="?\$\(jq -r(?: --arg \S+ "\$\{[^}]+\}"| --argjson \S+ "\$\{[^}]+\}")* "\$\{review_jq_defs\}"'([\s\S]*?)' <<<"\$\{reviews\}"\)"?/,
  )?.[1] ?? "";
const expression = reviewJqDefs && reviewGateBody ? `${reviewJqDefs}\n${reviewGateBody}` : "";

const PREV_HEAD = "1111111111111111111111111111111111111111";
const HEAD = "2222222222222222222222222222222222222222";
const OTHER_SHA = "3333333333333333333333333333333333333333";
const MAIN_SHA = "5555555555555555555555555555555555555555";

const CLAUDE = { login: "claude[bot]", id: 209825114, type: "Bot" };
const CODERABBIT = { login: "coderabbitai[bot]", id: 136622811, type: "Bot" };
const ACTIONS_BOT = { login: "github-actions[bot]", id: 41898282, type: "Bot" };
const OWNER = { login: "AquilaXk", id: 1, type: "User" };
const MEMBER = { login: "reviewer", id: 2, type: "User" };
const COLLABORATOR = { login: "collab-dev", id: 3, type: "User" };
const OUTSIDER = { login: "external-user", id: 99, type: "User" };

const review = (id, { state, user, association, commitId = HEAD, body = "" }) => ({
  id,
  state,
  commit_id: commitId,
  submitted_at: `2026-10-31T00:00:${String(id).padStart(2, "0")}Z`,
  author_association: association,
  user,
  body,
});

const claudeReview = (id, overrides = {}) =>
  review(id, { state: "COMMENTED", user: CLAUDE, association: "NONE", ...overrides });
const ownerReview = (id, state, body = "", commitId = HEAD) =>
  review(id, { state, user: OWNER, association: "OWNER", commitId, body });
const memberReview = (id, state, body = "", commitId = HEAD) =>
  review(id, { state, user: MEMBER, association: "MEMBER", commitId, body });
const collaboratorReview = (id, state, body = "", commitId = HEAD) =>
  review(id, { state, user: COLLABORATOR, association: "COLLABORATOR", commitId, body });

const interrogateBody = (sha = HEAD, actOn = 0, prose = "## Synthesized Review\n\nNo blocking findings.") =>
  `${prose}\n\n<!-- pstack-interrogate head=${sha} act-on=${actOn} -->`;

const authComment = (sha = HEAD, user = ACTIONS_BOT, id = 900) => ({
  id,
  user,
  body: `<!-- Automerge frozen discovery authorization: ${sha} -->`,
});

const baseUpdateComment = (sha = HEAD, user = ACTIONS_BOT, id = 901) => ({
  id,
  user,
  body: `<!-- Automerge base update requested: ${sha} -->`,
});

const reviewGate = (pages, { head = HEAD, commitShas = [PREV_HEAD, HEAD], comments = [authComment(HEAD)] } = {}) =>
  execFileSync(
    "jq",
    [
      "-r",
      "--arg",
      "head",
      head,
      "--argjson",
      "commit_shas",
      JSON.stringify(commitShas),
      "--argjson",
      "comments",
      JSON.stringify(comments),
      expression,
    ],
    {
      input: JSON.stringify(pages),
      encoding: "utf8",
    },
  ).trim();

const AQUILA_FALLBACK_BODY =
  "**Actionable comments posted: 1**\n<!-- Review source: Aquila fallback; canonical visible structure: summary -->";
const AQUILA_UNIVERSAL_BODY =
  "**Actionable comments posted: 0**\n<!-- Review source: Aquila Universal Review; engine: aquila-review -->";
const CODEX_FALLBACK_BODY =
  "**Actionable comments posted: 2**\n<!-- Review source: Codex CLI fallback; canonical visible structure: summary -->";

function extractCoordinateScript(workflowText) {
  const coordinateStart = workflowText.indexOf("\n  coordinate:\n");
  assert.notEqual(coordinateStart, -1, "coordinate job이 존재해야 한다");
  const coordinateBlock = workflowText.slice(coordinateStart);
  const runMatch = coordinateBlock.match(/\n {8}run: \|\n((?: {10}[^\n]*\n|\n)+)/);
  assert.ok(runMatch, "coordinate job의 inline bash run 블록이 필요하다");
  return runMatch[1].replace(/^ {10}/gm, "");
}

function runCoordinatorWithFakeGh(scenario) {
  const script = extractCoordinateScript(coordinator);
  const root = mkdtempSync(join(tmpdir(), "automerge-queue-test-"));
  const binDir = join(root, "bin");
  const statePath = join(root, "scenario.json");
  const callsPath = join(root, "calls.jsonl");
  const eventPath = join(root, "event.json");
  mkdirSync(binDir);
  writeFileSync(statePath, JSON.stringify(scenario));
  writeFileSync(callsPath, "");
  writeFileSync(eventPath, JSON.stringify(scenario.eventPayload ?? {}));

  const fakeGh = `#!${process.execPath}
import { execFileSync } from "node:child_process";
import { appendFileSync, readFileSync, writeFileSync } from "node:fs";

const args = process.argv.slice(2);
const scenarioPath = process.env.FAKE_GH_SCENARIO;
const scenario = JSON.parse(readFileSync(scenarioPath, "utf8"));
appendFileSync(
  process.env.FAKE_GH_CALLS,
  JSON.stringify({ args, token: process.env.GH_TOKEN ?? "" }) + "\\n",
);

function emit(payload) {
  const text = typeof payload === "string" ? payload : JSON.stringify(payload);
  const jqIndex = args.indexOf("--jq");
  if (jqIndex !== -1 && args[jqIndex + 1]) {
    const filtered = execFileSync("jq", ["-r", args[jqIndex + 1]], {
      input: text,
      encoding: "utf8",
    });
    process.stdout.write(filtered);
    return;
  }
  process.stdout.write(text + "\\n");
}

if (args[0] === "api") {
  if (args.includes("graphql")) {
    emit({
      data: {
        repository: {
          pullRequest: {
            reviewThreads: {
              nodes: (scenario.threads ?? []).map((isResolved) => ({ isResolved })),
              pageInfo: { hasNextPage: Boolean(scenario.threadsHasNextPage), endCursor: null },
            },
          },
        },
      },
    });
    process.exit(0);
  }
  if (args.includes("rate_limit")) {
    const rem = scenario.budget ?? 4500;
    emit({ resources: { core: { remaining: rem }, graphql: { remaining: rem } } });
    process.exit(0);
  }
  const methodIdx = args.indexOf("--method");
  const method = methodIdx !== -1 ? args[methodIdx + 1] : "GET";
  const endpoint = args.find((arg) => arg.startsWith("repos/")) ?? "";
  if (endpoint.endsWith("/rules/branches/main")) {
    if (scenario.rulesetError) {
      process.stderr.write("HTTP 500 ruleset unavailable\\n");
      process.exit(1);
    }
    emit(scenario.rules ?? [
      {
        type: "required_status_checks",
        parameters: { required_status_checks: [{ context: "Repository CI", integration_id: 15368 }] },
      },
    ]);
    process.exit(0);
  }
  if (endpoint.includes("/collaborators/") && endpoint.endsWith("/permission")) {
    emit({ permission: scenario.permission ?? "write" });
    process.exit(0);
  }
  if (method === "POST" && endpoint.endsWith("/comments")) {
    const bodyArg = args.find((a) => a.startsWith("body=")) ?? "body=";
    const created = { id: 5001, body: bodyArg.slice(5), user: ${JSON.stringify(ACTIONS_BOT)} };
    scenario.comments = [...(scenario.comments ?? []), created];
    writeFileSync(scenarioPath, JSON.stringify(scenario));
    emit(created);
    process.exit(0);
  }
  if (method === "PATCH" && endpoint.includes("/issues/comments/")) {
    const id = Number(endpoint.split("/").pop());
    const bodyArg = args.find((a) => a.startsWith("body=")) ?? "body=";
    const patched = { id, body: bodyArg.slice(5), user: ${JSON.stringify(ACTIONS_BOT)} };
    scenario.comments = (scenario.comments ?? []).map((c) => (c.id === id ? patched : c));
    writeFileSync(scenarioPath, JSON.stringify(scenario));
    emit(patched);
    process.exit(0);
  }
  if (method === "PUT" && endpoint.endsWith("/update-branch")) {
    emit({ message: "Updating pull request branch." });
    process.exit(0);
  }
  if (endpoint.includes("/pulls/") && endpoint.includes("/reviews")) {
    const page = endpoint.includes("page=") ? Number(new URLSearchParams(endpoint.split("?")[1]).get("page")) : 1;
    emit(page === 1 ? (scenario.reviews ?? []) : []);
    process.exit(0);
  }
  if (endpoint.includes("/pulls/") && endpoint.includes("/commits")) {
    const page = endpoint.includes("page=") ? Number(new URLSearchParams(endpoint.split("?")[1]).get("page")) : 1;
    const commits = page === 1
      ? (scenario.commits ?? [
          { sha: "${PREV_HEAD}", commit: { committer: { date: "2026-10-31T00:00:00Z" } } },
          { sha: scenario.head ?? "${HEAD}", commit: { committer: { date: "2026-10-31T00:00:05Z" } } },
        ])
      : [];
    emit(commits);
    process.exit(0);
  }
  if (endpoint.includes("/issues/") && endpoint.includes("/comments")) {
    const page = endpoint.includes("page=") ? Number(new URLSearchParams(endpoint.split("?")[1]).get("page")) : 1;
    const defaultComments = scenario.comments ?? [{ id: 900, user: ${JSON.stringify(ACTIONS_BOT)}, body: "<!-- Automerge frozen discovery authorization: " + (scenario.head ?? "${HEAD}") + " -->" }];
    emit(page === 1 ? defaultComments : []);
    process.exit(0);
  }
  if (endpoint.includes("/issues/") && endpoint.includes("/events")) {
    const page = endpoint.includes("page=") ? Number(new URLSearchParams(endpoint.split("?")[1]).get("page")) : 1;
    emit(page === 1 ? (scenario.events ?? []) : []);
    process.exit(0);
  }
  if (endpoint.includes("/check-runs")) {
    const page = endpoint.includes("page=") ? Number(new URLSearchParams(endpoint.split("?")[1]).get("page")) : 1;
    emit({ check_runs: page === 1 ? (scenario.checkRuns ?? []) : [] });
    process.exit(0);
  }
  if (endpoint.includes("/statuses")) {
    const page = endpoint.includes("page=") ? Number(new URLSearchParams(endpoint.split("?")[1]).get("page")) : 1;
    emit(page === 1 ? (scenario.statuses ?? []) : []);
    process.exit(0);
  }
  if (endpoint.includes("/compare/")) {
    emit({ status: scenario.compareStatus ?? "ahead" });
    process.exit(0);
  }
  if (endpoint.includes("/commits/")) {
    emit(scenario.headCommit ?? { sha: scenario.head ?? "${HEAD}", parents: [{ sha: "${PREV_HEAD}" }, { sha: "${MAIN_SHA}" }] });
    process.exit(0);
  }
  process.stderr.write("unexpected api endpoint: " + endpoint + "\\n");
  process.exit(2);
}

if (args[0] === "pr" && args[1] === "list") {
  emit(scenario.prList ?? [{ number: 42, createdAt: "2026-10-31T00:00:00Z", isDraft: false }]);
  process.exit(0);
}

if (args[0] === "pr" && args[1] === "view") {
  emit({
    number: 42,
    createdAt: "2026-10-31T00:00:00Z",
    isDraft: false,
    state: "OPEN",
    baseRefName: "main",
    headRefOid: scenario.head ?? "${HEAD}",
    mergeStateStatus: scenario.mergeState ?? "CLEAN",
    labels: scenario.labels ?? [{ name: "automerge" }],
  });
  process.exit(0);
}

if (args[0] === "pr" && args[1] === "edit") {
  if (args.includes("--remove-label")) {
    scenario.labels = [];
    writeFileSync(scenarioPath, JSON.stringify(scenario));
  }
  process.exit(0);
}

if (args[0] === "pr" && (args[1] === "merge" || args[1] === "comment")) {
  process.exit(scenario.mergeExit ?? 0);
}

process.stderr.write("unexpected gh command: " + args.join(" ") + "\\n");
process.exit(2);
`;

  const ghPath = join(binDir, "gh");
  writeFileSync(ghPath, fakeGh);
  chmodSync(ghPath, 0o755);

  try {
    const result = spawnSync("bash", ["-c", script], {
      cwd: root,
      encoding: "utf8",
      env: {
        ...process.env,
        PATH: `${binDir}:${process.env.PATH}`,
        FAKE_GH_SCENARIO: statePath,
        FAKE_GH_CALLS: callsPath,
        GITHUB_REPOSITORY: "AquilaXk/easysubway",
        GITHUB_EVENT_NAME: scenario.eventName ?? "workflow_dispatch",
        GITHUB_EVENT_PATH: eventPath,
        GITHUB_SERVER_URL: "https://github.com",
        GITHUB_RUN_ID: "9001",
        GH_TOKEN: "ghs_workflow_token",
        MERGE_GH_TOKEN: scenario.hasAutomergePat === false ? "ghs_workflow_token" : "ghp_automerge_pat",
        HAS_AUTOMERGE_PAT: scenario.hasAutomergePat === false ? "false" : "true",
      },
    });
    const calls = readFileSync(callsPath, "utf8")
      .split("\n")
      .filter(Boolean)
      .map((line) => JSON.parse(line));
    return { status: result.status, stdout: result.stdout, stderr: result.stderr, calls };
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test("automerge workflow는 F1 트리거·queue-probe·최소 권한·토큰 분리·inline review_gate 계약을 유지한다", () => {
  assert.ok(expression, "workflow 안에 inline review_gate jq 식이 있어야 한다");
  assert.doesNotMatch(expression, /claude/i);
  assert.doesNotMatch(coordinator, /Aquila Universal Review|Aquila fallback|aquila-review|Codex CLI fallback/);
  assert.doesNotMatch(coordinator, /--auto\b/, "hub는 native auto-merge 미활성 저장소이므로 --auto를 쓰지 않는다");
  assert.match(coordinator, /\npermissions: \{\}\n/);
  assert.match(coordinator, /pull_request_target:\n {4}types: \[labeled, unlabeled\]/);
  assert.match(coordinator, /workflow_run:\n {4}workflows: \[CI\]\n {4}types: \[completed\]/);
  assert.match(coordinator, /schedule:\n {4}- cron: '\*\/15 \* \* \* \*'/);
  assert.match(coordinator, /push:\n {4}branches: \[main\]/);
  assert.match(coordinator, /pull_request_review:\n {4}types: \[submitted\]/);
  assert.match(coordinator, /workflow_dispatch:/);
  assert.match(coordinator, /\n {2}queue-probe:\n[\s\S]*?\n {2}coordinate:\n/);
  assert.match(
    coordinator,
    /permissions:\n {6}checks: read\n {6}contents: write\n {6}pull-requests: write\n {6}statuses: read/,
  );
  assert.match(coordinator, /GH_TOKEN: \$\{\{ github\.token \}\}/);
  assert.match(
    coordinator,
    /MERGE_GH_TOKEN: \$\{\{ secrets\.AUTOMERGE_PAT != '' && secrets\.AUTOMERGE_PAT \|\| github\.token \}\}/,
  );
  assert.match(coordinator, /HAS_AUTOMERGE_PAT: \$\{\{ secrets\.AUTOMERGE_PAT != '' \}\}/);
});

test("pstack-interrogate act-on=0 exact-head Review는 신뢰된 사람 COMMENTED일 때만 통과한다", () => {
  assert.equal(reviewGate([[ownerReview(1, "COMMENTED", interrogateBody(HEAD, 0))]]), "true");
  assert.equal(reviewGate([[memberReview(1, "COMMENTED", interrogateBody(HEAD, 0))]]), "true");
  assert.equal(reviewGate([[collaboratorReview(1, "COMMENTED", interrogateBody(HEAD, 0))]]), "true");

  const bodyWithCodeExample = [
    `Inline \`<!-- pstack-interrogate head=${PREV_HEAD} act-on=2 -->\` example.`,
    "```html",
    `<!-- pstack-interrogate head=${HEAD} act-on=1 -->`,
    "```",
    interrogateBody(HEAD, 0),
  ].join("\n");
  assert.equal(reviewGate([[ownerReview(1, "COMMENTED", bodyWithCodeExample)]]), "true");
  assert.equal(
    reviewGate([[ownerReview(1, "COMMENTED", `\`\`\`\n<!-- pstack-interrogate head=${HEAD} act-on=0 -->\n\`\`\``)]]),
    "false",
  );

  assert.equal(
    reviewGate([[review(1, { state: "COMMENTED", user: OUTSIDER, association: "NONE", body: interrogateBody(HEAD, 0) })]]),
    "false",
  );
  assert.equal(
    reviewGate([[review(1, { state: "COMMENTED", user: OUTSIDER, association: "CONTRIBUTOR", body: interrogateBody(HEAD, 0) })]]),
    "false",
  );
  assert.equal(reviewGate([[ownerReview(1, "DISMISSED", interrogateBody(HEAD, 0))]]), "false");
});

test("pstack-interrogate act-on>0·중복·head 불일치·레거시 마커·claude[bot] Review는 거부한다", () => {
  for (const bad of [
    interrogateBody(HEAD, 1),
    interrogateBody(HEAD, 2),
    interrogateBody(HEAD, "01"),
    `<!-- pstack-interrogate head=${HEAD} act-on=0 extra=1 -->`,
    `<!-- pstack-interrogate head=${HEAD} act-on=1 -->\n<!-- pstack-interrogate head=${HEAD} act-on=0 -->`,
    `<!-- pstack-interrogate head=${HEAD} act-on=0 -->\n<!-- pstack-interrogate head=${HEAD} act-on=0 -->`,
    AQUILA_UNIVERSAL_BODY,
    AQUILA_FALLBACK_BODY,
    CODEX_FALLBACK_BODY,
    "",
    "LGTM",
  ]) {
    assert.equal(reviewGate([[ownerReview(1, "COMMENTED", bad)]]), "false", bad);
  }
  assert.equal(reviewGate([[ownerReview(1, "COMMENTED", null)]]), "false");
  assert.equal(reviewGate([[claudeReview(1)]]), "false");
  assert.equal(reviewGate([[claudeReview(1, { state: "APPROVED" })]]), "false");
  assert.equal(reviewGate([[ownerReview(1, "COMMENTED", interrogateBody(PREV_HEAD, 0), HEAD)]]), "false");
  assert.equal(reviewGate([[ownerReview(1, "COMMENTED", interrogateBody(HEAD, 0), PREV_HEAD)]]), "false");
  assert.equal(reviewGate([[ownerReview(1, "COMMENTED", interrogateBody(PREV_HEAD, 0), PREV_HEAD)]]), "false");
  assert.equal(
    reviewGate([[ownerReview(1, "COMMENTED", interrogateBody(OTHER_SHA, 0), OTHER_SHA)]], {
      head: OTHER_SHA,
      commitShas: [PREV_HEAD, HEAD],
      comments: [authComment(OTHER_SHA)],
    }),
    "false",
  );
});

test("CodeRabbit frozen discovery·현재 head APPROVED·CHANGES_REQUESTED·ACT_ON 순서 계약을 유지한다", () => {
  const coderabbit = (id, { user = CODERABBIT, commitId = PREV_HEAD } = {}) =>
    review(id, { state: "COMMENTED", user, association: "NONE", commitId, body: "Walkthrough" });

  assert.equal(reviewGate([[coderabbit(1)]], { comments: [authComment(HEAD)] }), "true");
  assert.equal(reviewGate([[coderabbit(1)]], { comments: [] }), "false");
  assert.equal(reviewGate([[coderabbit(1)]], { comments: [authComment(PREV_HEAD)] }), "false");
  assert.equal(reviewGate([[coderabbit(1)]], { comments: [authComment(HEAD), authComment(PREV_HEAD, ACTIONS_BOT, 901)] }), "false");
  assert.equal(reviewGate([[coderabbit(1, { commitId: OTHER_SHA })]], { comments: [authComment(HEAD)] }), "false");
  assert.equal(reviewGate([[coderabbit(1, { user: { ...CODERABBIT, id: 999 } })]], { comments: [authComment(HEAD)] }), "false");

  assert.equal(reviewGate([[memberReview(1, "APPROVED", "", HEAD)]]), "true");
  assert.equal(reviewGate([[memberReview(1, "APPROVED", "", PREV_HEAD)]]), "false");

  assert.equal(
    reviewGate([[ownerReview(1, "COMMENTED", interrogateBody(HEAD, 0)), memberReview(2, "CHANGES_REQUESTED")]]),
    "false",
  );
  assert.equal(
    reviewGate([[
      ownerReview(1, "COMMENTED", interrogateBody(HEAD, 0)),
      ownerReview(2, "COMMENTED", interrogateBody(HEAD, 1)),
    ]]),
    "false",
    "후속 act-on>0은 앞선 act-on=0을 덮어써야 한다",
  );
  assert.equal(
    reviewGate([[
      memberReview(1, "CHANGES_REQUESTED", "fix", HEAD),
      memberReview(2, "CHANGES_REQUESTED", "older cr", PREV_HEAD),
      memberReview(3, "APPROVED", "", PREV_HEAD),
      ownerReview(4, "COMMENTED", interrogateBody(HEAD, 0)),
    ]]),
    "false",
    "더 최신 커밋에 남긴 CHANGES_REQUESTED는 이전 커밋 APPROVED로 해제되지 않는다",
  );
  assert.equal(
    reviewGate([[
      memberReview(1, "CHANGES_REQUESTED", "pre-rebase cr", OTHER_SHA),
      memberReview(2, "COMMENTED", interrogateBody(OTHER_SHA, 0), OTHER_SHA),
      ownerReview(3, "COMMENTED", interrogateBody(HEAD, 0)),
    ]]),
    "true",
    "rebase 이전 PR 밖 커밋의 CHANGES_REQUESTED는 같은 리뷰어의 pstack act-on=0으로 해제된다",
  );
  assert.equal(
    reviewGate([[
      ownerReview(1, "COMMENTED", interrogateBody(HEAD, 0)),
      memberReview(2, "CHANGES_REQUESTED"),
      memberReview(3, "DISMISSED"),
    ]]),
    "true",
  );
  assert.equal(
    reviewGate([[
      ownerReview(1, "COMMENTED", interrogateBody(HEAD, 0)),
      memberReview(2, "CHANGES_REQUESTED", "fix", PREV_HEAD),
      memberReview(3, "APPROVED", "", PREV_HEAD),
    ]]),
    "true",
  );
});

test("F1 ruleset 조회 실패·빈 ruleset은 하드코딩 폴백 없이 fail-closed 종료한다", () => {
  const apiFailure = runCoordinatorWithFakeGh({
    rulesetError: true,
    reviews: [ownerReview(1, "COMMENTED", interrogateBody(HEAD, 0))],
  });
  assert.notEqual(apiFailure.status, 0);
  assert.equal(apiFailure.calls.some((call) => call.args[0] === "pr" && call.args[1] === "merge"), false);

  const emptyRuleset = runCoordinatorWithFakeGh({
    rules: [],
    reviews: [ownerReview(1, "COMMENTED", interrogateBody(HEAD, 0))],
  });
  assert.notEqual(emptyRuleset.status, 0);
  assert.equal(emptyRuleset.calls.some((call) => call.args[0] === "pr" && call.args[1] === "merge"), false);
});

test("F1 모든 필수 체크가 현재 head에서 success일 때만 MERGE_GH_TOKEN으로 직접 병합하고 BEHIND/label 동작을 지킨다", () => {
  const rules = [
    {
      type: "required_status_checks",
      parameters: {
        required_status_checks: [
          { context: "Repository CI", integration_id: 15368 },
          { context: "External Status", integration_id: null },
        ],
      },
    },
  ];
  const validReviews = [ownerReview(1, "COMMENTED", interrogateBody(HEAD, 0))];

  for (const badScenario of [
    { checkRuns: [], statuses: [] },
    {
      checkRuns: [{ id: 10, name: "Repository CI", status: "in_progress", conclusion: null, started_at: "2026-10-31T00:01:00Z", app: { id: 15368 } }],
      statuses: [{ id: 20, context: "External Status", state: "success", updated_at: "2026-10-31T00:01:00Z" }],
    },
    {
      checkRuns: [{ id: 10, name: "Repository CI", status: "completed", conclusion: "success", started_at: "2026-10-31T00:01:00Z", app: { id: 999 } }],
      statuses: [
        { id: 19, context: "Repository CI", state: "success", updated_at: "2026-10-31T00:01:00Z" },
        { id: 20, context: "External Status", state: "success", updated_at: "2026-10-31T00:01:00Z" },
      ],
    },
  ]) {
    const res = runCoordinatorWithFakeGh({ rules, reviews: validReviews, ...badScenario });
    assert.equal(res.status, 0, res.stderr);
    assert.equal(res.calls.some((call) => call.args[0] === "pr" && call.args[1] === "merge"), false);
  }

  const allGreen = runCoordinatorWithFakeGh({
    rules,
    reviews: validReviews,
    threads: [true, true],
    checkRuns: [
      { id: 10, name: "Repository CI", status: "completed", conclusion: "failure", started_at: "2026-10-31T00:01:00Z", app: { id: 15368 } },
      { id: 11, name: "Repository CI", status: "completed", conclusion: "success", started_at: "2026-10-31T00:02:00Z", app: { id: 15368 } },
    ],
    statuses: [
      { id: 20, context: "External Status", state: "pending", updated_at: "2026-10-31T00:01:00Z" },
      { id: 21, context: "External Status", state: "success", updated_at: "2026-10-31T00:02:00Z" },
    ],
  });
  assert.equal(allGreen.status, 0, allGreen.stderr);
  const mergeCalls = allGreen.calls.filter((call) => call.args[0] === "pr" && call.args[1] === "merge");
  assert.equal(mergeCalls.length, 1);
  assert.equal(mergeCalls[0].token, "ghp_automerge_pat");
  assert.equal(mergeCalls[0].args.includes("--auto"), false);
  assert.ok(mergeCalls[0].args.includes("--squash"));
  assert.ok(mergeCalls[0].args.includes("--match-head-commit"));
  assert.ok(mergeCalls[0].args.includes(HEAD));

  const behindPstack = runCoordinatorWithFakeGh({
    mergeState: "BEHIND",
    reviews: validReviews,
    checkRuns: [{ id: 11, name: "Repository CI", status: "completed", conclusion: "success", started_at: "2026-10-31T00:02:00Z", app: { id: 15368 } }],
  });
  assert.equal(behindPstack.status, 0, behindPstack.stderr);
  assert.equal(
    behindPstack.calls.some((call) => call.args.some((a) => a.endsWith("/update-branch"))),
    false,
    "pstack-interrogate 전용 BEHIND PR은 update-branch를 호출하지 않고 라벨을 해제해야 한다",
  );
  assert.equal(
    behindPstack.calls.some((call) => call.args[0] === "pr" && call.args[1] === "edit" && call.args.includes("--remove-label")),
    true,
  );

  const behindCodeRabbit = runCoordinatorWithFakeGh({
    mergeState: "BEHIND",
    reviews: [review(1, { state: "COMMENTED", user: CODERABBIT, association: "NONE", commitId: PREV_HEAD, body: "Walkthrough" })],
    comments: [authComment(HEAD)],
    checkRuns: [{ id: 11, name: "Repository CI", status: "completed", conclusion: "success", started_at: "2026-10-31T00:02:00Z", app: { id: 15368 } }],
  });
  assert.equal(behindCodeRabbit.status, 0, behindCodeRabbit.stderr);
  assert.equal(
    behindCodeRabbit.calls.some((call) => call.token === "ghp_automerge_pat" && call.args.some((a) => a.endsWith("/update-branch"))),
    true,
  );
  assert.equal(
    behindCodeRabbit.calls.some((call) => call.token === "ghs_workflow_token" && call.args.some((a) => a.includes(baseUpdateComment(HEAD).body))),
    true,
  );
});

const validateJqAsBindings = (program) => {
  const openToClose = new Map();
  const closeToOpen = new Map();
  const stack = [];
  const chars = [...program];
  const masked = [];
  for (let index = 0; index < chars.length; index += 1) {
    const ch = chars[index];
    if (ch === '"') {
      masked.push(" ");
      index += 1;
      while (index < chars.length && chars[index] !== '"') {
        if (chars[index] === "\\" && index + 1 < chars.length) {
          masked.push(" ", " ");
          index += 2;
          continue;
        }
        masked.push(" ");
        index += 1;
      }
      if (index >= chars.length) return { ok: false, reason: "unterminated string literal" };
      masked.push(" ");
      continue;
    }
    if (ch === "#") {
      while (index < chars.length && chars[index] !== "\n") {
        masked.push(" ");
        index += 1;
      }
      if (index < chars.length) masked.push("\n");
      continue;
    }
    if (ch === "(") stack.push(index);
    else if (ch === ")") {
      const open = stack.pop();
      if (open === undefined) return { ok: false, reason: `unmatched ')' at offset ${index}` };
      openToClose.set(open, index);
      closeToOpen.set(index, open);
    }
    masked.push(ch);
  }
  if (stack.length > 0) return { ok: false, reason: `unclosed '(' at offset ${stack.at(-1)}` };

  const text = masked.join("");
  const prevNonSpace = (from) => {
    let cursor = from;
    while (cursor >= 0 && /\s/.test(text[cursor])) cursor -= 1;
    return cursor;
  };
  const nextNonSpace = (from) => {
    let cursor = from;
    while (cursor < text.length && /\s/.test(text[cursor])) cursor += 1;
    return cursor;
  };

  let nonReduceCount = 0;
  let reduceCount = 0;
  for (const match of text.matchAll(/\bas\s+\$([A-Za-z_][A-Za-z0-9_]*)/g)) {
    const asIndex = match.index;
    const varName = match[1];
    const afterVar = nextNonSpace(asIndex + match[0].length);
    if (text[afterVar] === "(") {
      const enclosingOpen =
        [...openToClose.entries()]
          .filter(([open, close]) => open < asIndex && close > asIndex)
          .map(([open]) => open)
          .at(-1) ?? -1;
      if (!/\b(?:reduce|foreach)\b/.test(text.slice(enclosingOpen + 1, asIndex))) {
        return { ok: false, reason: `as $${varName} followed by '(' without reduce/foreach` };
      }
      reduceCount += 1;
      continue;
    }
    if (text[afterVar] !== "|") return { ok: false, reason: `as $${varName} must be followed by '|'` };
    const lhsClose = prevNonSpace(asIndex - 1);
    if (text[lhsClose] !== ")") return { ok: false, reason: `as $${varName} LHS must be enclosed in (...)` };
    const lhsOpen = closeToOpen.get(lhsClose);
    if (lhsOpen === undefined || text.slice(lhsOpen + 1, lhsClose).trim() === "") {
      return { ok: false, reason: `as $${varName} has empty LHS (...)` };
    }
    const outerOpen = prevNonSpace(lhsOpen - 1);
    if (text[outerOpen] !== "(") return { ok: false, reason: `as $${varName} must have outer '(' immediately before LHS` };
    const outerClose = openToClose.get(outerOpen);
    if (outerClose === undefined || outerClose <= afterVar || text.slice(afterVar + 1, outerClose).trim() === "") {
      return { ok: false, reason: `as $${varName} outer (...) must enclose a non-empty RHS body` };
    }
    nonReduceCount += 1;
  }
  return { ok: true, nonReduceCount, reduceCount };
};

test("워크플로의 모든 비-reduce jq as 바인딩이 ((<lhs>) as $<var> | <body>) 형식을 지키고 jq 컴파일을 통과한다", () => {
  assert.equal(validateJqAsBindings("((.[0]) as $x | $x)").ok, true);
  assert.equal(validateJqAsBindings("reduce .[] as $x ({}; .)").ok, true);
  for (const broken of [
    ".[0] as $x | $x",
    "($files | flatten) as $changed | ($changed | length == 1)",
    "((.[0]) as $x) | $x",
  ]) {
    assert.equal(validateJqAsBindings(broken).ok, false, broken);
  }

  const commentStripped = coordinator.replace(/^[ \t]*#.*$/gm, "");
  const totalWorkflowAsBindings = [...commentStripped.matchAll(/\bas\s+\\?\$[A-Za-z_][A-Za-z0-9_]*/g)].length;
  assert.ok(totalWorkflowAsBindings >= 15, "workflow must contain jq as bindings");

  let checkedNonReduce = 0;
  let checkedReduce = 0;
  const defsValidation = validateJqAsBindings(reviewJqDefs);
  assert.equal(defsValidation.ok, true, defsValidation.reason);
  checkedNonReduce += defsValidation.nonReduceCount;
  checkedReduce += defsValidation.reduceCount;

  const joinedWorkflow = coordinator.replace(/\\\n[ \t]*/g, " ");
  for (const match of joinedWorkflow.matchAll(
    /(?:--jq\s+|_query=|\bjq\b(?:[^\n']|'[^'\n]*')*?\s+)("\$\{review_jq_defs\}")?'([^']*)'/g,
  )) {
    const usesDefs = Boolean(match[1]);
    const program = match[2];
    const validation = validateJqAsBindings(program);
    assert.equal(validation.ok, true, `${validation.reason}:\n${program}`);
    checkedNonReduce += validation.nonReduceCount;
    checkedReduce += validation.reduceCount;

    const fullProgram = usesDefs ? `${reviewJqDefs}\n${program}` : program;
    const args = [...match[0].matchAll(/--(?:arg(?:json)?|slurpfile)\s+([A-Za-z_][A-Za-z0-9_]*)/g)].map((m) => m[1]);
    const compiled = spawnSync(
      "jq",
      ["-n", ...args.flatMap((name) => ["--arg", name, ""]), `if false then (${fullProgram}) else true end`],
      { encoding: "utf8" },
    );
    assert.equal(compiled.status, 0, `jq compile failed: ${compiled.stderr}\n${program}`);
  }
  assert.equal(checkedNonReduce + checkedReduce, totalWorkflowAsBindings);
});

test("모든 PR 템플릿이 pstack interrogate 마커 Review를 안내하고 Repository CI가 게이트 테스트를 실행한다", () => {
  for (const relativePath of [
    "../../.github/PULL_REQUEST_TEMPLATE/full.md",
    "../../.github/PULL_REQUEST_TEMPLATE/short.md",
    "../../.github/pull_request_template.md",
  ]) {
    const content = readFileSync(new URL(relativePath, import.meta.url), "utf8");
    assert.doesNotMatch(content, /aquila-review|Aquila 마커|Codex|폴백 리뷰/i);
    assert.match(content, /<!-- pstack-interrogate head=<40자 sha> act-on=0 -->/);
  }

  const ci = readFileSync(new URL("../../.github/workflows/ci.yml", import.meta.url), "utf8");
  const run = ci.match(/- name: Repository CI \/ Run contract tests\n(?: {8}[^\n]*\n)*? {8}run: ([^\n]+)\n/)?.[1];
  assert.ok(run);
  const files = run.split(/\s+/);
  assert.equal(files.slice(0, 2).join(" "), "node --test");
  assert.ok(files.includes("tools/ci/automerge-queue.test.mjs"));
});
