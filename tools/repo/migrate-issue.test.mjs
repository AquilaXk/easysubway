import assert from "node:assert/strict";
import test from "node:test";
import {
  executeIssueTransfer,
  parseArguments,
  preflightIssueTransfer,
  runMigration,
  validateMigrationLedger,
  verifyTransferredIssue,
} from "./migrate-issue.mjs";
import { readFileSync } from "node:fs";

const SOURCE_REPOSITORY = "AquilaXk/easysubway";
const TARGET_REPOSITORY = "AquilaXk/easysubway-data";
const SOURCE_ISSUE = 2684;
const SOURCE_URL = `https://github.com/${SOURCE_REPOSITORY}/issues/${SOURCE_ISSUE}`;
const TARGET_URL = `https://github.com/${TARGET_REPOSITORY}/issues/7`;

function transferEntry(overrides = {}) {
  return {
    sourceIssue: SOURCE_ISSUE,
    sourceUrl: SOURCE_URL,
    title: "[Release Blocker][P0][Data] KRIC FACILITY 전체 station-line source admission",
    disposition: "TRANSFER",
    targetRepository: TARGET_REPOSITORY,
    executionApproval: "https://github.com/AquilaXk/easysubway/issues/2691#issuecomment-1",
    targetUrl: null,
    transferredAt: null,
    ...overrides,
  };
}

function metadata({ url = SOURCE_URL, number = SOURCE_ISSUE, title, state = "OPEN", labels = ["release-blocker"], milestone = "P0", commentCount = 1, closingPullRequests = [] } = {}) {
  const repo = url.split("/issues/")[0].replace("https://github.com/", "");
  const connection = (nodes) => ({ totalCount: nodes.length, nodes });
  return { id: `I_${number}`, url, number, title: title ?? transferEntry().title, state, repository: { nameWithOwner: repo }, labels: connection(labels.map((name) => ({ name }))), milestone: milestone === null ? null : { title: milestone, dueOn: null }, comments: { totalCount: commentCount }, assignees: connection([]), projectItems: connection([]), parent: null, subIssues: connection([]), blocking: connection([]), blockedBy: connection([]), closedByPullRequestsReferences: connection(closingPullRequests) };
}

function fakeGh({ source = metadata(), target = metadata({ url: TARGET_URL, number: 7 }), targetExists = true, unassignableLogin, malformedAssigneeResponse } = {}) {
  const calls = [];
  let transferred = false;
  const execGh = async (args) => {
    calls.push(args);
    if (args[0] === "repo" && args[1] === "view") {
      if (!targetExists) throw new Error("target repository not found");
      return JSON.stringify({ nameWithOwner: TARGET_REPOSITORY });
    }
    if (args[0] === "issue" && args[1] === "transfer") {
      transferred = true;
      return "";
    }
    if (args[0] === "api" && args.at(-1).includes("/assignees/")) {
      if (args.at(-1).endsWith(`/${encodeURIComponent(unassignableLogin)}`)) throw new Error("not assignable");
      if (malformedAssigneeResponse !== undefined) return malformedAssigneeResponse;
      return "";
    }
    if (args[0] === "api" && args.includes("--paginate")) {
      return JSON.stringify([args.at(-1).includes("labels") ? target.labels.nodes : (target.milestone === null ? [] : [{ title: target.milestone.title, due_on: target.milestone.dueOn }])]);
    }
    if (args[0] === "api" && args.at(-1) === `/repos/${SOURCE_REPOSITORY}/issues/${SOURCE_ISSUE}`) {
      if (!transferred) throw new Error("redirect requested before transfer");
      return JSON.stringify({ html_url: TARGET_URL, number: 7, repository_url: `https://api.github.com/repos/${TARGET_REPOSITORY}` });
    }
    if (args[0] === "api" && args[1] === "graphql") {
      const issue = args.includes(`name=${TARGET_REPOSITORY.split("/")[1]}`) ? target : source;
      return JSON.stringify({ data: { repository: { issue } } });
    }
    throw new Error(`unexpected gh invocation: ${args.join(" ")}`);
  };
  return { calls, execGh };
}

function migrationContract() {
  return {
    ledger: JSON.parse(readFileSync("release/migrations/repository-split-issues.json", "utf8")),
    schema: JSON.parse(readFileSync("contracts/repository-split-issues.schema.json", "utf8")),
  };
}

function transferCalls(calls) {
  return calls.filter((args) => args[0] === "issue" && args[1] === "transfer");
}

test("argument parser accepts exactly one source issue and one mode", () => {
  assert.deepEqual(
    parseArguments(["--ledger", "ledger.json", "--source-issue", "2684", "--dry-run"]),
    { ledgerPath: "ledger.json", sourceIssue: 2684, mode: "dry-run", confirmations: { source: undefined, target: undefined } },
  );
  assert.throws(
    () => parseArguments(["--ledger", "ledger.json", "--source-issue", "2684", "--source-issue", "2685", "--dry-run"]),
    /exactly one --source-issue/,
  );
});

test("preflight fails closed before transfer for unsafe ledger and GitHub metadata", async (t) => {
  const cases = [
    ["non-TRANSFER disposition", transferEntry({ disposition: "KEEP_HUB" })],
    ["missing execution approval", transferEntry({ executionApproval: null })],
    ["unapproved target", transferEntry({ targetRepository: "AquilaXk/other" })],
    ["missing target repository", transferEntry(), { targetExists: false }],
    ["stale source title", transferEntry(), { source: metadata({ title: "changed" }) }],
    ["closed source issue", transferEntry(), { source: metadata({ state: "CLOSED" }) }],
    ["open linked pull request", transferEntry(), { source: metadata({ closingPullRequests: [{ id: "PR_9", number: 9, url: "https://github.com/AquilaXk/easysubway/pull/9", state: "OPEN", repository: { nameWithOwner: SOURCE_REPOSITORY } }] }) }],
    ["label mismatch", transferEntry(), { target: metadata({ labels: ["different"] }) }],
    ["milestone mismatch", transferEntry(), { target: metadata({ milestone: "P1" }) }],
  ];

  for (const [name, entry, options] of cases) {
    await t.test(name, async () => {
      const fake = fakeGh(options);
      await assert.rejects(() => preflightIssueTransfer({ entry, execGh: fake.execGh }));
      assert.deepEqual(transferCalls(fake.calls), []);
    });
  }
});

test("dry-run preflight returns redacted metadata and never transfers", async () => {
  const fake = fakeGh();

  const report = await preflightIssueTransfer({ entry: transferEntry(), execGh: fake.execGh });

  assert.deepEqual(report, {
    source: { number: SOURCE_ISSUE, url: SOURCE_URL, title: transferEntry().title, state: "OPEN", labelCount: 1, milestone: "P0", commentCount: 1 },
    target: { repository: TARGET_REPOSITORY, exists: true, labelCount: 1, milestone: "P0" },
  });
  assert.deepEqual(transferCalls(fake.calls), []);
  assert.ok(fake.calls.every((args) => !args.some((value) => value.includes("body"))));
});

test("migration validates whole-ledger schema and semantics before any GitHub call", async (t) => {
  const cases = [
    ["schemaVersion", (ledger) => { ledger.schemaVersion = 2; }],
    ["classificationState", (ledger) => { ledger.issues[0].classificationState = "PENDING"; }],
    ["required metadata", (ledger) => { delete ledger.issues[0].reason; }],
    ["semantic mapping", (ledger) => { ledger.issues[0].targetRepository = "AquilaXk/easysubway-backend"; }],
  ];

  for (const [name, mutate] of cases) await t.test(name, async () => {
    const { ledger, schema } = migrationContract();
    mutate(ledger);
    const fake = fakeGh();
    assert.ok(validateMigrationLedger({ ledger, schema }).length > 0);
    await assert.rejects(() => runMigration({
      arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY } },
      ledger,
      schema,
      execGh: fake.execGh,
    }), /ledger validation failed/);
    assert.deepEqual(fake.calls, []);
  });
});

test("preflight verifies every source assignee can be assigned in the target before transfer", async () => {
  const source = metadata();
  source.assignees = { totalCount: 2, nodes: [{ id: "U_1", login: "space user" }, { id: "U_2", login: "owner" }] };
  const fake = fakeGh({ source });

  await preflightIssueTransfer({ entry: transferEntry(), execGh: fake.execGh });

  assert.ok(fake.calls.some((args) => args.at(-1) === "repos/AquilaXk/easysubway-data/assignees/space%20user"));
  assert.ok(fake.calls.some((args) => args.at(-1) === "repos/AquilaXk/easysubway-data/assignees/owner"));
});

test("preflight rejects unassignable or malformed target assignee responses before transfer", async (t) => {
  const source = metadata();
  source.assignees = { totalCount: 1, nodes: [{ id: "U_1", login: "owner" }] };
  for (const options of [{ unassignableLogin: "owner" }, { malformedAssigneeResponse: "{}" }]) await t.test(JSON.stringify(options), async () => {
    const fake = fakeGh({ source, ...options });
    await assert.rejects(() => preflightIssueTransfer({ entry: transferEntry(), execGh: fake.execGh }));
    assert.deepEqual(transferCalls(fake.calls), []);
  });
});

test("execution requires exact source and target confirmations before transfer", async () => {
  const fake = fakeGh();
  const entry = transferEntry();

  await assert.rejects(
    () => executeIssueTransfer({ entry, confirmations: { source: "AquilaXk/easysubway#1", target: TARGET_REPOSITORY }, execGh: fake.execGh }),
    /source confirmation/,
  );
  await assert.rejects(
    () => executeIssueTransfer({ entry, confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: "AquilaXk/other" }, execGh: fake.execGh }),
    /target confirmation/,
  );
  assert.deepEqual(transferCalls(fake.calls), []);
});

test("execution transfers one approved issue and verifies redirected metadata", async () => {
  const fake = fakeGh();
  const entry = transferEntry();
  const transferResult = await executeIssueTransfer({
    entry,
    confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY },
    execGh: fake.execGh,
  });

  const verified = await verifyTransferredIssue({ entry, transferResult, execGh: fake.execGh });

  assert.deepEqual(transferCalls(fake.calls), [["issue", "transfer", String(SOURCE_ISSUE), TARGET_REPOSITORY, "--repo", SOURCE_REPOSITORY]]);
  assert.deepEqual(verified, {
    sourceUrl: SOURCE_URL,
    targetUrl: TARGET_URL,
    number: 7,
    title: entry.title,
    state: "OPEN",
    labelCount: 1,
    milestone: "P0",
    commentCount: 1,
  });
  assert.equal(Object.hasOwn(verified, "body"), false);
  assert.equal(Object.hasOwn(verified, "comments"), false);
});

test("post-transfer verification rejects metadata that does not identify the redirected issue", async () => {
  const fake = fakeGh({ target: metadata({ url: TARGET_URL, number: 8 }) });
  const entry = transferEntry();
  const transferResult = await executeIssueTransfer({
    entry,
    confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY },
    execGh: fake.execGh,
  });

  await assert.rejects(
    () => verifyTransferredIssue({ entry, transferResult, execGh: fake.execGh }),
    /redirect target metadata is stale/,
  );
});

test("unsafe entries and incomplete connections never transfer", async (t) => {
  const cases = [
    transferEntry(),
  ];
  for (const [index, entry] of cases.entries()) await t.test(String(index), async () => {
    const source = { ...metadata(), labels: { totalCount: 2, nodes: [{ name: "release-blocker" }] } };
    const fake = fakeGh({ source });
    await assert.rejects(() => preflightIssueTransfer({ entry, execGh: fake.execGh }));
    assert.deepEqual(transferCalls(fake.calls), []);
  });
});

test("execute rejects malformed approval and completed transfer state before transfer", async (t) => {
  const cases = [
    transferEntry({ executionApproval: "bad" }),
    transferEntry({ targetUrl: TARGET_URL, transferredAt: "2026-07-30T00:00:00.000Z" }),
  ];
  for (const entry of cases) await t.test(entry.executionApproval, async () => {
    const fake = fakeGh();
    await assert.rejects(() => executeIssueTransfer({
      entry,
      confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY },
      execGh: fake.execGh,
    }));
    assert.deepEqual(transferCalls(fake.calls), []);
  });
});

test("parser rejects duplicate and missing singleton values", () => {
  for (const flag of ["--ledger", "--source-issue", "--confirm-source", "--confirm-target"]) {
    const base = ["--ledger", "l", "--source-issue", "1", "--execute", "--confirm-source", "AquilaXk/easysubway#1", "--confirm-target", "AquilaXk/easysubway-data"];
    assert.throws(() => parseArguments([...base, flag, "x"]));
    const index = base.indexOf(flag);
    assert.throws(() => parseArguments([...base.slice(0, index), ...base.slice(index + 1)]));
  }
  assert.throws(() => parseArguments(["--ledger", "l", "--source-issue", "1", "--execute", "--confirm-source", "AquilaXk/easysubway#1", "--confirm-target"]));
  assert.throws(() => parseArguments(["--ledger", "--source-issue", "1", "--execute", "--confirm-source", "AquilaXk/easysubway#1", "--confirm-target", "AquilaXk/easysubway-data"]));
});

test("target milestone due-date mismatch rejects before transfer", async () => {
  const fake = fakeGh({ target: metadata({ milestone: "P0" }) });
  fake.execGh = fake.execGh;
  const original = fake.execGh;
  const execGh = async (args) => args[0] === "api" && args.includes("--paginate") && args.at(-1).includes("milestones")
    ? JSON.stringify([[{ title: "P0", due_on: "2026-08-01T00:00:00Z" }]]) : original(args);
  await assert.rejects(() => preflightIssueTransfer({ entry: transferEntry(), execGh }));
  assert.deepEqual(transferCalls(fake.calls), []);
});

test("post-transfer relation snapshots reject every changed relation after one transfer", async (t) => {
  const relation = { id: "I_9", number: 9, url: "https://github.com/AquilaXk/easysubway/issues/9", repository: { nameWithOwner: SOURCE_REPOSITORY } };
  const cases = [
    ["assignee", { assignees: { totalCount: 1, nodes: [{ id: "U_1", login: "owner" }] } }],
    ["project", { projectItems: { totalCount: 1, nodes: [{ id: "PVTITEM_1", project: { id: "PVT_1", number: 1, title: "P", url: "https://github.com/orgs/AquilaXk/projects/1" } }] } }],
    ["parent", { parent: relation }],
    ["sub issue", { subIssues: { totalCount: 1, nodes: [relation] } }],
    ["blocking", { blocking: { totalCount: 1, nodes: [relation] } }],
    ["blocked by", { blockedBy: { totalCount: 1, nodes: [relation] } }],
    ["closing PR", { closedByPullRequestsReferences: { totalCount: 1, nodes: [{ ...relation, id: "PR_9", state: "CLOSED" }] } }],
  ];
  for (const [name, changed] of cases) await t.test(name, async () => {
    const fake = fakeGh({ target: { ...metadata({ url: TARGET_URL, number: 7 }), ...changed } });
    const entry = transferEntry();
    const transferResult = await executeIssueTransfer({ entry, confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, execGh: fake.execGh });
    await assert.rejects(() => verifyTransferredIssue({ entry, transferResult, execGh: fake.execGh }));
    assert.equal(transferCalls(fake.calls).length, 1);
  });
});
