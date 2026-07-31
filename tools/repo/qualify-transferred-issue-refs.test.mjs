import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import test from "node:test";
import { promisify } from "node:util";
import { parseArguments, qualifyIssueReferences, runNormalization } from "./qualify-transferred-issue-refs.mjs";

const ledger = {
  issues: [
    { sourceIssue: 10, disposition: "TRANSFER", targetRepository: "AquilaXk/easysubway-mobile", targetUrl: "https://github.com/AquilaXk/easysubway-mobile/issues/2", transferredAt: "2026-07-31T09:00:00Z" },
    { sourceIssue: 11, disposition: "KEEP_HUB", targetRepository: "AquilaXk/easysubway", targetUrl: null },
    { sourceIssue: 12, disposition: "TRANSFER", targetRepository: "AquilaXk/easysubway-data", targetUrl: "https://github.com/AquilaXk/easysubway-data/issues/4" },
    { sourceIssue: 13, disposition: "TRANSFER", targetRepository: "AquilaXk/easysubway-backend", targetUrl: "https://github.com/AquilaXk/easysubway-backend/issues/7" },
    { sourceIssue: 14, disposition: "TRANSFER", targetRepository: "AquilaXk/easysubway-mobile", targetUrl: null },
  ],
};
const ambiguous = (reference) => ({ reference, reason: "bare reference is ambiguous after issue transfer" });
const execFileAsync = promisify(execFile);

test("qualifyIssueReferences는 ledger-matching bare ref만 ambiguity로 보고한다", () => {
  assert.deepEqual(
    qualifyIssueReferences({ text: "internal #10, hub #11, data #12, backend #13, existing AquilaXk/easysubway#11", ledger }),
    [ambiguous(10), ambiguous(11), ambiguous(12), ambiguous(13)],
  );
  assert.deepEqual(
    qualifyIssueReferences({
      text: "retained parent #2605",
      ledger: { issues: [{ sourceIssue: 2605, disposition: "SPLIT_CHILDREN", targetRepository: null, childRepositories: ["AquilaXk/easysubway-data", "AquilaXk/easysubway-mobile"] }] },
    }),
    [ambiguous(2605)],
  );
});

test("qualifyIssueReferences는 fenced/inline code와 URL의 #N을 무시한다", () => {
  const text = [
    "normal #10", "`inline #11`", "``inline with ` tick #12``", "https://example.test/issues/#12", "```text", "fenced #13", "```",
  ].join("\n");
  assert.deepEqual(qualifyIssueReferences({ text, ledger }), [ambiguous(10)]);
});

test("qualifyIssueReferences는 closing fence의 trailing text를 code block 종료로 처리하지 않는다", () => {
  const text = ["```text", "first code #10", "``` trailing text", "second code #11", "```", "outside #12"].join("\n");
  assert.deepEqual(qualifyIssueReferences({ text, ledger }), [ambiguous(12)]);
});

test("qualifyIssueReferences는 multiline inline code span을 무시한다", () => {
  const text = ["before #10", "`inline", "code #11`", "after #12"].join("\n");
  assert.deepEqual(qualifyIssueReferences({ text, ledger }), [ambiguous(10), ambiguous(12)]);
});

test("qualifyIssueReferences는 더 긴 backtick run 내부를 inline closing fence로 처리하지 않는다", () => {
  assert.deepEqual(qualifyIssueReferences({ text: "``code ``` #10``", ledger }), []);
});

test("qualifyIssueReferences는 Markdown link 뒤 참조와 backslash escape를 구분한다", () => {
  assert.deepEqual(qualifyIssueReferences({ text: "[docs](https://example.test)#10 \\`live #11\\` literal \\#12", ledger }), [ambiguous(10), ambiguous(11)]);
  assert.deepEqual(qualifyIssueReferences({ text: "[docs](<https://example.test> \"title #11\")#10", ledger }), [ambiguous(10)]);
  assert.deepEqual(qualifyIssueReferences({ text: "[docs](https://example.test \"title ) #10\") outside #11", ledger }), [ambiguous(11)]);
  assert.deepEqual(qualifyIssueReferences({ text: "[docs](https://example.test/a_(b)#10) outside #11", ledger }), [ambiguous(11)]);
  assert.deepEqual(qualifyIssueReferences({ text: "[docs](https://example.test/a_\\)#10) outside #11", ledger }), [ambiguous(11)]);
});

test("qualifyIssueReferences는 ledger 밖 또는 미완료 transfer bare ref를 fail-closed한다", () => {
  assert.throws(() => qualifyIssueReferences({ text: "unknown #99", ledger }), /unresolved bare issue reference #99/);
  assert.throws(() => qualifyIssueReferences({ text: "incomplete #14", ledger }), /unresolved bare issue reference #14/);
});

test("qualifyIssueReferences는 fenced/inline 미종결과 indented code를 fail-closed한다", () => {
  for (const [text, message] of [
    ["```\n#10", /unterminated fenced/],
    ["`#10", /unterminated inline/],
    ["    #10", /indented code/],
    ["\t#10", /indented code/],
  ]) assert.throws(() => qualifyIssueReferences({ text, ledger }), message);
});

test("runNormalization dry-run은 변경 제안 없이 surface별 ambiguous ref만 보고한다", async () => {
  const fake = fakeGh({ body: "body #10 and #11", comments: [
    { id: 1, body: "comment #12", created_at: "2026-07-31T08:00:00Z", updated_at: "2026-07-31T08:00:00Z" },
    { id: 2, body: "already AquilaXk/easysubway#11", created_at: "2026-07-31T08:00:00Z", updated_at: "2026-07-31T08:00:00Z" },
    { id: 3, body: "target-local #99", created_at: "2026-07-31T10:00:00Z", updated_at: "2026-07-31T10:00:00Z" },
  ] });
  const result = await runNormalization({ arguments_: { sourceIssue: 10, mode: "dry-run", confirmations: {} }, ledger, execGh: fake.exec });
  assert.deepEqual(result, {
    sourceIssue: 10,
    targetUrl: "https://github.com/AquilaXk/easysubway-mobile/issues/2",
    referenceMap: { 10: "AquilaXk/easysubway-mobile#2", 11: "AquilaXk/easysubway#11", 12: "AquilaXk/easysubway-data#4", 13: "AquilaXk/easysubway-backend#7" },
    changes: [],
    unresolved: [
      { surface: { kind: "body", id: null }, ...ambiguous(10) },
      { surface: { kind: "body", id: null }, ...ambiguous(11) },
      { surface: { kind: "comment", id: 1 }, ...ambiguous(12) },
    ],
  });
  assert.equal(fake.calls.some((args) => args.includes("PATCH")), false);
});

test("runNormalization은 noncanonical transfer timestamp를 read 전에 거부한다", async () => {
  const invalidLedger = structuredClone(ledger);
  invalidLedger.issues[0].transferredAt = "2026-07-31";
  const fake = fakeGh({ body: "#10", comments: [] });
  await assert.rejects(() => runNormalization({ arguments_: { sourceIssue: 10, mode: "dry-run", confirmations: {} }, ledger: invalidLedger, execGh: fake.exec }), /transfer timestamp is invalid/);
  assert.equal(fake.calls.length, 0);
  const invalidCommentFake = fakeGh({ body: "#10", comments: [{ id: 1, body: "#10", created_at: 0, updated_at: "2026-07-31T08:00:00Z" }] });
  await assert.rejects(() => runNormalization({ arguments_: { sourceIssue: 10, mode: "dry-run", confirmations: {} }, ledger, execGh: invalidCommentFake.exec }), /issue comments are invalid/);
  const fractionalLedger = structuredClone(ledger);
  fractionalLedger.issues[0].transferredAt = "2026-07-31T09:00:00.1234Z";
  const fractionalCommentFake = fakeGh({ body: "", comments: [
    { id: 1, body: "#10", created_at: "2026-07-31T09:00:00.1233Z", updated_at: "2026-07-31T09:00:00.1233Z" },
    { id: 2, body: "#99", created_at: "2026-07-31T09:00:00.1235Z", updated_at: "2026-07-31T09:00:00.1235Z" },
  ] });
  assert.equal((await runNormalization({ arguments_: { sourceIssue: 10, mode: "dry-run", confirmations: {} }, ledger: fractionalLedger, execGh: fractionalCommentFake.exec })).unresolved.length, 1);
});

test("runNormalization execute는 source ledger 부재와 conditional PATCH 부재 모두 read/write 전에 fail-closed한다", async () => {
  const fake = fakeGh({ body: "body #10", comments: [{ id: 1, body: "comment #13" }] });
  await assert.rejects(
    () => runNormalization({ arguments_: { sourceIssue: 10, mode: "execute", confirmations: { source: "AquilaXk/easysubway#9", target: "AquilaXk/easysubway-mobile#2" } }, ledger, execGh: fake.exec }),
    /source confirmation does not match/,
  );
  await assert.rejects(
    () => runNormalization({ arguments_: { sourceIssue: 10, mode: "execute", confirmations: { source: "AquilaXk/easysubway#10", target: "AquilaXk/easysubway-mobile#3" } }, ledger, execGh: fake.exec }),
    /target confirmation does not match/,
  );
  await assert.rejects(
    () => runNormalization({ arguments_: { sourceIssue: 99, mode: "execute", confirmations: {} }, ledger, execGh: fake.exec }),
    /source issue #99 is not present in the ledger/,
  );
  await assert.rejects(
    () => runNormalization({ arguments_: { sourceIssue: 10, mode: "execute", confirmations: { source: "AquilaXk/easysubway#10", target: "AquilaXk/easysubway-mobile#2" } }, ledger, execGh: fake.exec }),
    /conditional write/,
  );
  assert.equal(fake.calls.length, 0);
});

test("runNormalization은 mobile target 외 과거 transfer를 거부한다", async () => {
  await assert.rejects(
    () => runNormalization({ arguments_: { sourceIssue: 12, mode: "dry-run", confirmations: {} }, ledger, execGh: fakeGh({ body: "#10", comments: [] }).exec }),
    /target repository must be easysubway-mobile/,
  );
});

test("parseArguments는 invalid input을 table-driven으로 거부한다", () => {
  assert.deepEqual(parseArguments(["--ledger", "ledger.json", "--source-issue", "10", "--dry-run"]), { ledgerPath: "ledger.json", sourceIssue: 10, mode: "dry-run", confirmations: {} });
  for (const [argv, message] of [
    [["--ledger", "ledger.json", "--source-issue", "0", "--dry-run"], /required/],
    [["--ledger", "--source-issue", "10", "--dry-run"], /exactly once/],
    [["--ledger", "--", "--source-issue", "10", "--dry-run"], /exactly once/],
    [["--ledger", "ledger.json", "--source-issue", "not-a-number", "--dry-run"], /required/],
    [["--ledger", "ledger.json", "--source-issue", "10", "--execute"], /both confirmations/],
    [["--ledger", "ledger.json", "--ledger", "again", "--source-issue", "10", "--dry-run"], /exactly once/],
    [["--ledger", "ledger.json", "--source-issue", "10", "--dry-run", "--execute"], /exactly one/],
    [["--ledger", "ledger.json", "--source-issue", "10", "--dry-run", "--unknown"], /unsupported/],
  ]) assert.throws(() => parseArguments(argv), message);
});

test("CLI direct invocation은 main을 시작한다", async () => {
  await assert.rejects(
    () => execFileAsync(process.execPath, ["tools/repo/qualify-transferred-issue-refs.mjs"], { cwd: process.cwd() }),
    (error) => /issue reference normalization was not executed: ledger, source issue, and execution mode are required/.test(error.stderr),
  );
});

function fakeGh({ body, comments }) {
  const state = { body, comments: structuredClone(comments).map((comment) => ({ ...comment, issue_url: "https://api.github.com/repos/AquilaXk/easysubway-mobile/issues/2" })), calls: [] };
  return {
    get calls() { return state.calls; },
    async exec(args) {
      state.calls.push(args);
      const endpoint = args.find((argument) => argument.startsWith("repos/"));
      if (endpoint.endsWith("/issues/2")) return JSON.stringify({ body: state.body });
      if (endpoint.includes("/comments?")) return JSON.stringify([state.comments]);
      throw new Error(`unexpected gh call: ${args.join(" ")}`);
    },
  };
}
