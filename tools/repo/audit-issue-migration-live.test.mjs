import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  auditMigrationState,
  collectLiveState,
  execGh,
  parseArguments,
  recordedLocations,
} from "./audit-issue-migration-live.mjs";

const LEDGER_PATH = "release/migrations/repository-split-issues.json";
const AMENDMENTS_PATH = "release/migrations/repository-split-issues-amendments.json";

function migrationRecords() {
  return {
    ledger: JSON.parse(readFileSync(LEDGER_PATH, "utf8")),
    amendments: JSON.parse(readFileSync(AMENDMENTS_PATH, "utf8")),
  };
}

/** 기록과 완전히 일치하는 live 실측 상태. drift 테스트는 이 값을 국소 변형한다. */
function liveStateMatchingRecords({ ledger, amendments }) {
  const { records } = recordedLocations({ ledger, amendments });
  const redirects = {};
  const openIssueNumbers = [];
  for (const [sourceIssue, record] of records) {
    redirects[sourceIssue] = record.expectedUrl;
    if (record.hubOwned) openIssueNumbers.push(sourceIssue);
  }
  return { openIssueNumbers, redirects };
}

/** `gh api` 실패는 stderr로만 원인이 구분되므로 execFile 실패 객체 형태를 그대로 흉내낸다. */
function ghFailure(stderr) {
  const error = new Error(`Command failed: gh api\n${stderr}`);
  error.code = 1;
  error.stderr = stderr;
  return error;
}

test("gh 실행은 bounded timeout과 SIGTERM을 고정하고 실행 실패를 그대로 전파한다", async () => {
  let invocation;
  const execute = async (...args) => {
    invocation = args;
    return { stdout: "ok\n" };
  };

  assert.equal(await execGh(["version"], execute), "ok\n");
  assert.deepEqual(invocation, [
    "gh",
    ["version"],
    {
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
      timeout: 30_000,
      killSignal: "SIGTERM",
    },
  ]);

  const timeout = Object.assign(new Error("Command failed: gh version"), {
    killed: true,
    signal: "SIGTERM",
  });
  await assert.rejects(() => execGh(["version"], async () => { throw timeout; }), (error) => error === timeout);
});

function fakeGh({ openNumbers, redirectFor }) {
  const calls = [];
  const execGh = async (args) => {
    calls.push(args);
    if (args[0] === "issue" && args[1] === "list") {
      return JSON.stringify(openNumbers.map((number) => ({ number })));
    }
    if (args[0] === "api") {
      const redirect = redirectFor(Number(args[1].split("/").at(-1)));
      if (redirect instanceof Error) throw redirect;
      if (redirect === null) throw ghFailure("gh: Not Found (HTTP 404)\n");
      return `${redirect}\n`;
    }
    throw new Error(`unexpected gh invocation: ${args.join(" ")}`);
  };
  return { calls, execGh };
}

test("인자 파서는 ledger와 amendments 경로를 각각 한 번만 받는다", () => {
  assert.deepEqual(
    parseArguments(["--ledger", LEDGER_PATH, "--amendments", AMENDMENTS_PATH]),
    { ledgerPath: LEDGER_PATH, amendmentsPath: AMENDMENTS_PATH },
  );
  for (const argv of [
    [],
    ["--ledger", LEDGER_PATH],
    ["--amendments", AMENDMENTS_PATH],
    ["--ledger", LEDGER_PATH, "--ledger", LEDGER_PATH, "--amendments", AMENDMENTS_PATH],
    ["--ledger", "--amendments", AMENDMENTS_PATH],
    ["--unexpected", "value"],
  ]) {
    assert.throws(() => parseArguments(argv));
  }
});

test("기록과 일치하는 실측 상태는 finding이 없다", () => {
  const { ledger, amendments } = migrationRecords();

  assert.deepEqual(auditMigrationState({ ledger, amendments, live: liveStateMatchingRecords({ ledger, amendments }) }), []);
});

test("기록된 이전 대상과 실측 redirect 불일치를 보고한다", () => {
  const { ledger, amendments } = migrationRecords();
  const live = liveStateMatchingRecords({ ledger, amendments });
  live.redirects[2667] = "https://github.com/AquilaXk/easysubway-mobile/issues/99";

  assert.deepEqual(auditMigrationState({ ledger, amendments, live }), [
    "#2667: 기록된 이전 대상 https://github.com/AquilaXk/easysubway-backend/issues/19와 실측 https://github.com/AquilaXk/easysubway-mobile/issues/99 불일치",
  ]);
});

test("PENDING 기록인데 이미 이전된 이슈를 미기록 이전으로 보고한다", () => {
  const { ledger, amendments } = migrationRecords();
  const live = liveStateMatchingRecords({ ledger, amendments });
  const entry = ledger.issues.find(({ sourceIssue }) => sourceIssue === 2667);
  entry.executionApproval = null;
  entry.targetUrl = null;
  entry.transferredAt = null;

  assert.deepEqual(auditMigrationState({ ledger, amendments, live }), [
    "#2667: 미기록 이전 감지 — 실측 https://github.com/AquilaXk/easysubway-backend/issues/19, 기록은 PENDING",
  ]);
});

test("hub 소유 기록인데 실측 위치가 hub 밖이면 보고한다", () => {
  const { ledger, amendments } = migrationRecords();
  const live = liveStateMatchingRecords({ ledger, amendments });
  live.redirects[2605] = "https://github.com/AquilaXk/easysubway-mobile/issues/5";
  live.redirects[2727] = "https://github.com/AquilaXk/easysubway-platform/issues/7";

  assert.deepEqual(auditMigrationState({ ledger, amendments, live }), [
    "#2605: hub 소유 기록인데 실측 위치는 https://github.com/AquilaXk/easysubway-mobile/issues/5",
    "#2727: hub 소유 기록인데 실측 위치는 https://github.com/AquilaXk/easysubway-platform/issues/7",
  ]);
});

test("TRANSFER 기록이 hub open 목록에 남아 있으면 보고한다", () => {
  const { ledger, amendments } = migrationRecords();
  const live = liveStateMatchingRecords({ ledger, amendments });
  live.openIssueNumbers.push(2667, 2700);

  assert.deepEqual(auditMigrationState({ ledger, amendments, live }), [
    "#2667: TRANSFER 기록인데 hub open 목록에 남아 있음",
    "#2700: TRANSFER 기록인데 hub open 목록에 남아 있음",
  ]);
});

test("분류 기록이 없는 hub open 이슈를 보고한다", () => {
  const { ledger, amendments } = migrationRecords();
  const live = liveStateMatchingRecords({ ledger, amendments });
  live.openIssueNumbers.push(9999, 9998);

  assert.deepEqual(auditMigrationState({ ledger, amendments, live }), [
    "#9998: hub open인데 분류 기록 없음",
    "#9999: hub open인데 분류 기록 없음",
  ]);
});

test("redirect 실측값이 없으면 보고한다", () => {
  const { ledger, amendments } = migrationRecords();
  const live = liveStateMatchingRecords({ ledger, amendments });
  delete live.redirects[1019];

  assert.deepEqual(auditMigrationState({ ledger, amendments, live }), ["#1019: hub redirect 실측값 없음"]);
});

test("snapshot과 amendments 중복 기록을 보고한다", () => {
  const { ledger, amendments } = migrationRecords();
  const live = liveStateMatchingRecords({ ledger, amendments });
  amendments.amendments.push({
    sourceIssue: 1019,
    title: "[Chore] 출시 후 운영·지원 대응 증거 완성",
    disposition: "KEEP_HUB",
    targetRepository: "AquilaXk/easysubway",
    targetUrl: null,
    transferredAt: null,
    reason: "중복 기록",
    classifiedAt: "2026-08-01T16:59:35Z",
  });

  assert.deepEqual(auditMigrationState({ ledger, amendments, live }), ["#1019: snapshot과 amendments에 중복 기록됨"]);
});

test("live 실측 입력이 불량이면 audit을 진행하지 않는다", () => {
  const { ledger, amendments } = migrationRecords();

  assert.deepEqual(auditMigrationState({ ledger, amendments, live: {} }), ["live.openIssueNumbers: 배열 필요"]);
  assert.deepEqual(
    auditMigrationState({ ledger, amendments, live: { openIssueNumbers: [], redirects: [] } }),
    ["live.redirects: 객체 필요"],
  );
});

function collectFixture() {
  return {
    ledger: {
      issues: [
        { sourceIssue: 11, disposition: "KEEP_HUB", targetUrl: null },
        { sourceIssue: 12, disposition: "TRANSFER", targetUrl: "https://github.com/AquilaXk/easysubway-mobile/issues/9" },
      ],
    },
    amendments: { amendments: [{ sourceIssue: 13, disposition: "KEEP_HUB", targetUrl: null }] },
  };
}

test("live 수집은 읽기 전용 gh 호출만 사용하고 404 redirect를 생략한다", async () => {
  const { ledger, amendments } = collectFixture();
  const fake = fakeGh({
    openNumbers: [11, 13],
    redirectFor: (number) => (number === 13 ? null : `https://github.com/AquilaXk/easysubway/issues/${number}`),
  });

  const live = await collectLiveState({ ledger, amendments, execGh: fake.execGh });

  assert.deepEqual(live, {
    openIssueNumbers: [11, 13],
    redirects: {
      11: "https://github.com/AquilaXk/easysubway/issues/11",
      12: "https://github.com/AquilaXk/easysubway/issues/12",
    },
  });
  assert.deepEqual(fake.calls[0], [
    "issue", "list", "--repo", "AquilaXk/easysubway", "--state", "open", "--limit", "1000", "--json", "number",
  ]);
  assert.deepEqual(fake.calls.slice(1).map((args) => args[1]), [
    "repos/AquilaXk/easysubway/issues/11",
    "repos/AquilaXk/easysubway/issues/12",
    "repos/AquilaXk/easysubway/issues/13",
  ]);
  assert.ok(fake.calls.every((args) => !args.includes("-X") && !args.includes("--method") && !args.includes("transfer")));
  assert.deepEqual(auditMigrationState({ ledger, amendments, live }), [
    "#12: 기록된 이전 대상 https://github.com/AquilaXk/easysubway-mobile/issues/9와 실측 https://github.com/AquilaXk/easysubway/issues/12 불일치",
    "#13: hub redirect 실측값 없음",
  ]);
});

test("404 아닌 gh 실패와 issue URL 아닌 응답은 실측값 부재로 흡수하지 않는다", async () => {
  const failures = [
    [ghFailure("gh: API rate limit exceeded (HTTP 403)\n"), /#12 redirect 실측 실패: gh: API rate limit exceeded \(HTTP 403\)/],
    [ghFailure("error connecting to api.github.com\n"), /#12 redirect 실측 실패: error connecting to api\.github\.com/],
    [ghFailure(""), /#12 redirect 실측 실패: Command failed: gh api/],
  ];

  for (const [failure, expected] of failures) {
    const { ledger, amendments } = collectFixture();
    const fake = fakeGh({
      openNumbers: [11, 13],
      redirectFor: (number) => (number === 12 ? failure : `https://github.com/AquilaXk/easysubway/issues/${number}`),
    });
    await assert.rejects(() => collectLiveState({ ledger, amendments, execGh: fake.execGh }), expected);
  }

  const { ledger, amendments } = collectFixture();
  const malformed = fakeGh({
    openNumbers: [11, 13],
    redirectFor: (number) => (number === 12 ? "null" : `https://github.com/AquilaXk/easysubway/issues/${number}`),
  });
  await assert.rejects(
    () => collectLiveState({ ledger, amendments, execGh: malformed.execGh }),
    /#12 redirect 응답이 issue URL이 아니다: "null"/,
  );
});

test("hub open 목록이 잘리면 fail closed한다", async () => {
  const ledger = { issues: [{ sourceIssue: 11, disposition: "KEEP_HUB", targetUrl: null }] };
  const amendments = { amendments: [] };
  const fake = fakeGh({
    openNumbers: Array.from({ length: 1000 }, (_, index) => index + 1),
    redirectFor: (number) => `https://github.com/AquilaXk/easysubway/issues/${number}`,
  });

  await assert.rejects(
    () => collectLiveState({ ledger, amendments, execGh: fake.execGh }),
    /hub open issue list is truncated/,
  );
});
