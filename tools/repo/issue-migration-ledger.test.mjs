import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  entriesForTarget,
  entryForSourceIssue,
  validateLedger,
} from "./issue-migration-ledger.mjs";

const OPEN_ISSUE_NUMBERS = [
  571, 1016, 1019, 1020, 1021, 1022, 1393, 1414, 1918, 2050, 2055, 2058,
  2065, 2095, 2126, 2138, 2268, 2406, 2523, 2524, 2525, 2526, 2533, 2535,
  2536, 2537, 2538, 2539, 2540, 2541, 2542, 2543, 2544, 2545, 2547, 2548,
  2586, 2591, 2596, 2600, 2605, 2607, 2608, 2610, 2611, 2612, 2613, 2617,
  2619, 2620, 2621, 2622, 2623, 2624, 2625, 2626, 2627, 2628, 2629, 2630,
  2667, 2674, 2675, 2676, 2677, 2678, 2679, 2680, 2684, 2690, 2691,
];

function ledgerFixture() {
  return JSON.parse(readFileSync("release/migrations/repository-split-issues.json", "utf8"));
}

test("71개 open issue ledger는 inventory와 execution guard를 모두 만족한다", () => {
  const ledger = ledgerFixture();

  assert.equal(ledger.issues.length, 71);
  assert.deepEqual(validateLedger(ledger, { openIssueNumbers: OPEN_ISSUE_NUMBERS }), []);
  assert.ok(ledger.issues.every((entry) => entry.executionApproval === null));
  assert.ok(ledger.issues.every((entry) => entry.targetUrl === null));
  assert.ok(ledger.issues.every((entry) => entry.transferredAt === null));
});

test("target과 source issue 조회는 실제 ledger entry를 반환한다", () => {
  const ledger = ledgerFixture();

  assert.equal(entryForSourceIssue(ledger, 2605).disposition, "SPLIT_CHILDREN");
  assert.deepEqual(
    entriesForTarget(ledger, "AquilaXk/easysubway-data").map(({ sourceIssue }) => sourceIssue),
    [2138, 2523, 2533, 2607, 2608, 2610, 2611, 2684],
  );
});

test("source issue 중복은 분류 ledger를 무효화한다", () => {
  const ledger = ledgerFixture();
  ledger.issues.push(structuredClone(ledger.issues[0]));

  assert.deepEqual(validateLedger(ledger), ["issues: sourceIssue 571 중복"]);
});

test("open fixture에 없는 source issue는 ledger를 무효화한다", () => {
  const ledger = ledgerFixture();
  ledger.issues[0].sourceIssue = 9999;

  assert.deepEqual(validateLedger(ledger, { openIssueNumbers: OPEN_ISSUE_NUMBERS }), [
    "issues: open issue inventory 불일치 (누락: 571; 초과: 9999)",
  ]);
});

test("inventory count는 unique source issue 수와 같아야 한다", () => {
  const ledger = ledgerFixture();
  ledger.inventory.openIssueCount = 70;

  assert.deepEqual(validateLedger(ledger), ["inventory.openIssueCount: issues unique sourceIssue 수와 불일치"]);
});

test("지원하지 않는 disposition은 거부한다", () => {
  const ledger = ledgerFixture();
  ledger.issues[0].disposition = "ARCHIVE";

  assert.deepEqual(validateLedger(ledger), ["issues[0].disposition: 지원하지 않는 disposition"]);
});

test("TRANSFER는 hub를 target으로 지정할 수 없다", () => {
  const ledger = ledgerFixture();
  const entry = ledger.issues.find(({ disposition }) => disposition === "TRANSFER");
  entry.targetRepository = "AquilaXk/easysubway";

  assert.deepEqual(validateLedger(ledger), ["issues[0].targetRepository: TRANSFER는 hub target을 허용하지 않음"]);
});

test("KEEP_HUB는 hub만 target으로 지정할 수 있다", () => {
  const ledger = ledgerFixture();
  const entry = ledger.issues.find(({ disposition }) => disposition === "KEEP_HUB");
  entry.targetRepository = "AquilaXk/easysubway-mobile";

  assert.deepEqual(validateLedger(ledger), ["issues[2].targetRepository: KEEP_HUB target은 sourceRepository여야 함"]);
});

test("reason과 GitHub issue URL은 실행 전에도 유효해야 한다", () => {
  const ledger = ledgerFixture();
  delete ledger.issues[0].reason;
  ledger.issues[1].sourceUrl = "github.com/AquilaXk/easysubway/issues/1016";

  assert.deepEqual(validateLedger(ledger), [
    "issues[0].reason: reason이 필요함",
    "issues[1].sourceUrl: source issue GitHub URL 불량",
  ]);
});

test("허용된 다섯 repository 밖의 target은 거부한다", () => {
  const ledger = ledgerFixture();
  ledger.issues[0].targetRepository = "AquilaXk/other";

  assert.deepEqual(validateLedger(ledger), ["issues[0].targetRepository: 허용되지 않은 repository"]);
});

test("execution approval과 transfer 결과는 비어 있어야 한다", () => {
  const ledger = ledgerFixture();
  ledger.issues[0].executionApproval = "approved";
  ledger.issues[1].transferredAt = "2026-07-30T00:00:00.000Z";

  assert.deepEqual(validateLedger(ledger), [
    "issues[0].executionApproval: baseline에서는 null이어야 함",
    "issues[1].transferredAt: targetUrl 없이 transferredAt을 지정할 수 없음",
    "issues[1].transferredAt: baseline에서는 null이어야 함",
  ]);
});
