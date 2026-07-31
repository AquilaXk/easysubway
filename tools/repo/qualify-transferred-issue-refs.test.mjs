import assert from "node:assert/strict";
import test from "node:test";
import { parseArguments, qualifyIssueReferences, runNormalization } from "./qualify-transferred-issue-refs.mjs";

const ledger = {
  issues: [
    { sourceIssue: 10, disposition: "TRANSFER", targetRepository: "AquilaXk/easysubway-mobile", targetUrl: "https://github.com/AquilaXk/easysubway-mobile/issues/2" },
    { sourceIssue: 11, disposition: "KEEP_HUB", targetRepository: "AquilaXk/easysubway", targetUrl: null },
    { sourceIssue: 12, disposition: "TRANSFER", targetRepository: "AquilaXk/easysubway-data", targetUrl: "https://github.com/AquilaXk/easysubway-data/issues/4" },
    { sourceIssue: 13, disposition: "TRANSFER", targetRepository: "AquilaXk/easysubway-backend", targetUrl: "https://github.com/AquilaXk/easysubway-backend/issues/7" },
    { sourceIssue: 14, disposition: "TRANSFER", targetRepository: "AquilaXk/easysubway-mobile", targetUrl: null },
  ],
};

test("qualifyIssueReferences는 completed map의 bare ref만 repository-qualified로 바꾼다", () => {
  const text = "internal #10, hub #11, data #12, backend #13, existing AquilaXk/easysubway#11";

  assert.equal(
    qualifyIssueReferences({ text, ledger }),
    "internal AquilaXk/easysubway-mobile#2, hub AquilaXk/easysubway#11, data AquilaXk/easysubway-data#4, backend AquilaXk/easysubway-backend#7, existing AquilaXk/easysubway#11",
  );
});

test("qualifyIssueReferences는 fenced/inline code와 URL의 #N을 byte-for-byte 보존한다", () => {
  const text = [
    "normal #10",
    "`inline #11`",
    "``inline with ` tick #12``",
    "https://example.test/issues/#12",
    "```text",
    "fenced #13",
    "```",
  ].join("\n");

  assert.equal(
    qualifyIssueReferences({ text, ledger }),
    [
      "normal AquilaXk/easysubway-mobile#2",
      "`inline #11`",
      "``inline with ` tick #12``",
      "https://example.test/issues/#12",
      "```text",
      "fenced #13",
      "```",
    ].join("\n"),
  );
});

test("qualifyIssueReferences는 closing fence의 trailing text를 code block 종료로 처리하지 않는다", () => {
  const text = [
    "```text",
    "first code #10",
    "``` trailing text",
    "second code #11",
    "```",
    "outside #12",
  ].join("\n");

  assert.equal(
    qualifyIssueReferences({ text, ledger }),
    [
      "```text",
      "first code #10",
      "``` trailing text",
      "second code #11",
      "```",
      "outside AquilaXk/easysubway-data#4",
    ].join("\n"),
  );
});

test("qualifyIssueReferences는 multiline inline code span을 byte-for-byte 보존한다", () => {
  const text = [
    "before #10",
    "`inline",
    "code #11`",
    "after #12",
  ].join("\n");

  assert.equal(
    qualifyIssueReferences({ text, ledger }),
    [
      "before AquilaXk/easysubway-mobile#2",
      "`inline",
      "code #11`",
      "after AquilaXk/easysubway-data#4",
    ].join("\n"),
  );
});

test("qualifyIssueReferences는 ledger 밖 bare ref를 fail-closed한다", () => {
  assert.throws(
    () => qualifyIssueReferences({ text: "unknown #99", ledger }),
    /unresolved bare issue reference #99/,
  );
});

test("qualifyIssueReferences는 unrelated incomplete transfer를 무시하지만 그 ref는 fail-closed한다", () => {
  assert.equal(qualifyIssueReferences({ text: "completed #10", ledger }), "completed AquilaXk/easysubway-mobile#2");
  assert.throws(() => qualifyIssueReferences({ text: "incomplete #14", ledger }), /unresolved bare issue reference #14/);
});

test("qualifyIssueReferences는 SPLIT_CHILDREN hub parent reference를 hub-qualified로 바꾼다", () => {
  const splitChildrenLedger = {
    issues: [
      { sourceIssue: 2605, disposition: "SPLIT_CHILDREN", targetRepository: null, childRepositories: ["AquilaXk/easysubway-data", "AquilaXk/easysubway-mobile"] },
    ],
  };

  assert.equal(
    qualifyIssueReferences({ text: "retained parent #2605", ledger: splitChildrenLedger }),
    "retained parent AquilaXk/easysubway#2605",
  );
});

test("runNormalization dry-run은 body와 모든 comment 제안만 만들고 write하지 않는다", async () => {
  const fake = fakeGh({ body: "body #10 and #11", comments: [{ id: 1, body: "comment #12" }, { id: 2, body: "already AquilaXk/easysubway#11" }] });

  const result = await runNormalization({
    arguments_: { sourceIssue: 10, mode: "dry-run", confirmations: {} },
    ledger,
    execGh: fake.exec,
  });

  assert.deepEqual(result, {
    sourceIssue: 10,
    targetUrl: "https://github.com/AquilaXk/easysubway-mobile/issues/2",
    referenceMap: {
      10: "AquilaXk/easysubway-mobile#2",
      11: "AquilaXk/easysubway#11",
      12: "AquilaXk/easysubway-data#4",
      13: "AquilaXk/easysubway-backend#7",
    },
    changes: [
      { kind: "body", id: null, before: "body #10 and #11", after: "body AquilaXk/easysubway-mobile#2 and AquilaXk/easysubway#11" },
      { kind: "comment", id: 1, before: "comment #12", after: "comment AquilaXk/easysubway-data#4" },
    ],
  });
  assert.equal(fake.calls.some((args) => args.includes("PATCH")), false);
});

test("runNormalization execute는 GitHub의 conditional PATCH 부재로 write 전에 fail-closed한다", async () => {
  const fake = fakeGh({ body: "body #10", comments: [{ id: 1, body: "comment #13" }] });

  await assert.rejects(
    () => runNormalization({
      arguments_: { sourceIssue: 10, mode: "execute", confirmations: { source: "AquilaXk/easysubway#10", target: "AquilaXk/easysubway-mobile#3" } },
      ledger,
      execGh: fake.exec,
    }),
    /target confirmation does not match/,
  );

  await assert.rejects(
    () => runNormalization({
      arguments_: { sourceIssue: 10, mode: "execute", confirmations: { source: "AquilaXk/easysubway#10", target: "AquilaXk/easysubway-mobile#2" } }, ledger, execGh: fake.exec,
    }), /conditional write/,
  );
  assert.equal(fake.calls.length, 0);
});

test("runNormalization은 mobile target 외 과거 transfer를 거부한다", async () => {
  await assert.rejects(
    () => runNormalization({
      arguments_: { sourceIssue: 12, mode: "dry-run", confirmations: {} },
      ledger,
      execGh: fakeGh({ body: "#10", comments: [] }).exec,
    }),
    /target repository must be easysubway-mobile/,
  );
});

test("parseArguments는 execute의 exact confirmations를 요구한다", () => {
  assert.deepEqual(
    parseArguments(["--ledger", "ledger.json", "--source-issue", "10", "--dry-run"]),
    { ledgerPath: "ledger.json", sourceIssue: 10, mode: "dry-run", confirmations: {} },
  );
  assert.throws(
    () => parseArguments(["--ledger", "ledger.json", "--source-issue", "10", "--execute", "--confirm-source", "AquilaXk/easysubway#10"]),
    /both confirmations/,
  );
});

function fakeGh({ body, comments }) {
  const state = { body, comments: structuredClone(comments).map((comment) => ({ ...comment, issue_url: "https://api.github.com/repos/AquilaXk/easysubway-mobile/issues/2" })), calls: [] };
  return {
    get body() { return state.body; },
    get comments() { return state.comments; },
    get calls() { return state.calls; },
    async exec(args) {
      state.calls.push(args);
      const endpoint = args.find((argument) => argument.startsWith("repos/"));
      if (args.includes("PATCH")) {
        const value = args.find((argument) => argument.startsWith("body="));
        const nextBody = value?.slice("body=".length);
        if (endpoint.endsWith("/issues/2")) state.body = nextBody;
        else {
          const id = Number(endpoint.match(/comments\/(\d+)$/)?.[1]);
          state.comments.find((comment) => comment.id === id).body = nextBody;
        }
        return "";
      }
      if (endpoint.endsWith("/issues/2")) return JSON.stringify({ body: state.body });
      if (endpoint.includes("/comments?")) return JSON.stringify([state.comments]);
      const commentId = Number(endpoint.match(/comments\/(\d+)$/)?.[1]);
      if (Number.isInteger(commentId)) return JSON.stringify(state.comments.find((comment) => comment.id === commentId));
      throw new Error(`unexpected gh call: ${args.join(" ")}`);
    },
  };
}
