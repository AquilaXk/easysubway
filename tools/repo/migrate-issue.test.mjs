import assert from "node:assert/strict";
import test from "node:test";
import {
  executeIssueTransfer,
  parseArguments,
  preflightIssueTransfer,
  verifyTransferredIssue,
} from "./migrate-issue.mjs";

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

function metadata({ url = SOURCE_URL, number = SOURCE_ISSUE, title, state = "OPEN", labels = ["release-blocker"], milestone = "P0", commentCount = 1 } = {}) {
  return { url, number, title: title ?? transferEntry().title, state, labels: { totalCount: labels.length, nodes: labels.map((name) => ({ name })) }, milestone: milestone === null ? null : { title: milestone }, comments: { totalCount: commentCount } };
}

function fakeGh({ source = metadata(), target = metadata({ url: TARGET_URL, number: 7 }), targetExists = true, linkedPullRequests = [] } = {}) {
  const calls = [];
  let transferred = false;
  const execGh = async (args) => {
    calls.push(args);
    if (args[0] === "repo" && args[1] === "view") {
      if (!targetExists) throw new Error("target repository not found");
      return JSON.stringify({ nameWithOwner: TARGET_REPOSITORY });
    }
    if (args[0] === "pr" && args[1] === "list") return JSON.stringify(linkedPullRequests);
    if (args[0] === "label" && args[1] === "list") return JSON.stringify(target.labels.nodes);
    if (args[0] === "issue" && args[1] === "transfer") {
      transferred = true;
      return "";
    }
    if (args[0] === "api" && args.includes("--method")) {
      if (!transferred) throw new Error("redirect requested before transfer");
      return `HTTP/2.0 301 Moved Permanently\nlocation: ${TARGET_URL}\n`;
    }
    if (args[0] === "api" && args[1] === "graphql") {
      const issue = args.includes(`name=${TARGET_REPOSITORY.split("/")[1]}`) ? target : source;
      return JSON.stringify({ data: { repository: { issue } } });
    }
    if (args[0] === "api" && args[1].endsWith("/milestones?state=all&per_page=100")) {
      return JSON.stringify(target.milestone === null ? [] : [target.milestone]);
    }
    throw new Error(`unexpected gh invocation: ${args.join(" ")}`);
  };
  return { calls, execGh };
}

function transferCalls(calls) {
  return calls.filter((args) => args[0] === "issue" && args[1] === "transfer");
}

test("argument parser accepts exactly one source issue and one mode", () => {
  assert.deepEqual(
    parseArguments(["--ledger", "ledger.json", "--source-issue", "2684", "--dry-run"]),
    { ledgerPath: "ledger.json", sourceIssue: 2684, mode: "dry-run" },
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
    ["open linked pull request", transferEntry(), { linkedPullRequests: [{ number: 9 }] }],
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
