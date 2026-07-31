import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";
import {
  entriesForTarget,
  entryForSourceIssue,
  validateLedger,
} from "./issue-migration-ledger.mjs";

const REVIEWED_SOURCE_ISSUE_NUMBERS = [
  571, 1016, 1019, 1020, 1021, 1022, 1393, 1414, 1918, 2050, 2055, 2058,
  2065, 2095, 2126, 2138, 2268, 2406, 2523, 2524, 2525, 2526, 2533, 2535,
  2536, 2537, 2538, 2539, 2540, 2541, 2542, 2543, 2544, 2545, 2547, 2548,
  2586, 2591, 2596, 2600, 2605, 2607, 2608, 2610, 2611, 2612, 2613, 2617,
  2619, 2620, 2621, 2622, 2623, 2624, 2625, 2626, 2627, 2628, 2629, 2630,
  2667, 2674, 2675, 2676, 2677, 2678, 2679, 2680, 2684, 2690, 2691,
];
const DATA_APPROVAL_URL = "https://github.com/AquilaXk/easysubway/issues/2705#issuecomment-5134093671";
const BACKEND_APPROVAL_URL = "https://github.com/AquilaXk/easysubway/issues/2714#issuecomment-5138826003";
const BACKEND_APPROVED = new Set([2095, 2544, 2545, 2622, 2623, 2624, 2625, 2626, 2675, 2676, 2677]);
const BACKEND_TRANSFERS = new Map([
  [2095, ["https://github.com/AquilaXk/easysubway-backend/issues/3", "2026-07-31T04:02:01Z"]],
  [2544, ["https://github.com/AquilaXk/easysubway-backend/issues/4", "2026-07-31T04:04:02Z"]],
]);
const DATA_TRANSFERS = new Map([
  [2138, ["https://github.com/AquilaXk/easysubway-data/issues/3", "2026-07-30T18:59:46Z"]],
  [2523, ["https://github.com/AquilaXk/easysubway-data/issues/4", "2026-07-30T19:23:33Z"]],
  [2533, ["https://github.com/AquilaXk/easysubway-data/issues/5", "2026-07-30T19:39:57Z"]],
  [2607, ["https://github.com/AquilaXk/easysubway-data/issues/6", "2026-07-30T19:41:26Z"]],
  [2608, ["https://github.com/AquilaXk/easysubway-data/issues/7", "2026-07-30T19:43:04Z"]],
  [2610, ["https://github.com/AquilaXk/easysubway-data/issues/8", "2026-07-30T19:45:12Z"]],
  [2611, ["https://github.com/AquilaXk/easysubway-data/issues/9", "2026-07-30T19:46:15Z"]],
  [2684, ["https://github.com/AquilaXk/easysubway-data/issues/10", "2026-07-30T19:47:10Z"]],
]);

function ledgerFixture() {
  return JSON.parse(readFileSync("release/migrations/repository-split-issues.json", "utf8"));
}

test("reviewed source issue ledger는 data transfer와 backend Task8 approval state를 만족한다", () => {
  const ledger = ledgerFixture();

  assert.equal(ledger.issues.length, 71);
  assert.deepEqual(validateLedger(ledger, { openIssueNumbers: REVIEWED_SOURCE_ISSUE_NUMBERS }), []);
  for (const entry of ledger.issues) {
    const transfer = DATA_TRANSFERS.get(entry.sourceIssue) ?? BACKEND_TRANSFERS.get(entry.sourceIssue);
    assert.equal(entry.executionApproval, DATA_TRANSFERS.has(entry.sourceIssue) ? DATA_APPROVAL_URL
      : BACKEND_APPROVED.has(entry.sourceIssue) ? BACKEND_APPROVAL_URL : null);
    assert.equal(entry.targetUrl, transfer?.[0] ?? null);
    assert.equal(entry.transferredAt, transfer?.[1] ?? null);
  }
});

test("target과 source issue 조회는 direct target과 split child를 모두 반환한다", () => {
  const ledger = ledgerFixture();

  assert.equal(entryForSourceIssue(ledger, 2605).disposition, "SPLIT_CHILDREN");
  assert.deepEqual(
    entriesForTarget(ledger, "AquilaXk/easysubway-data").map(({ sourceIssue }) => sourceIssue),
    [2138, 2523, 2533, 2605, 2607, 2608, 2610, 2611, 2684],
  );
});

test("source issue 중복은 분류 ledger를 무효화한다", () => {
  const ledger = ledgerFixture();
  ledger.issues.push(structuredClone(ledger.issues[0]));

  assert.deepEqual(validateLedger(ledger), ["issues: sourceIssue 571 중복"]);
});

test("open fixture와 frozen reviewed mapping 밖의 source issue는 ledger를 무효화한다", () => {
  const ledger = ledgerFixture();
  ledger.issues[0].sourceIssue = 9999;

  assert.deepEqual(validateLedger(ledger, { openIssueNumbers: REVIEWED_SOURCE_ISSUE_NUMBERS }), [
    "issues[0].sourceUrl: sourceIssue와 URL 번호 불일치",
    "issues[0]: frozen reviewed mapping에 없는 sourceIssue",
    "issues: frozen reviewed mapping 누락 (571)",
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

  assert.deepEqual(validateLedger(ledger), [
    "issues[0].disposition: 지원하지 않는 disposition",
    "issues[0].disposition: frozen reviewed mapping과 불일치",
  ]);
});

test("TRANSFER는 hub를 target으로 지정할 수 없다", () => {
  const ledger = ledgerFixture();
  const entry = ledger.issues.find(({ disposition }) => disposition === "TRANSFER");
  entry.targetRepository = "AquilaXk/easysubway";

  assert.deepEqual(validateLedger(ledger), [
    "issues[0].targetRepository: TRANSFER는 approved non-hub target이 필요함",
    "issues[0].targetRepository: frozen reviewed mapping과 불일치",
  ]);
});

test("TRANSFER는 null target을 허용하지 않는다", () => {
  const ledger = ledgerFixture();
  ledger.issues[0].targetRepository = null;

  assert.deepEqual(validateLedger(ledger), [
    "issues[0].targetRepository: TRANSFER는 approved non-hub target이 필요함",
    "issues[0].targetRepository: frozen reviewed mapping과 불일치",
  ]);
});

test("KEEP_HUB는 hub만 target으로 지정할 수 있다", () => {
  const ledger = ledgerFixture();
  const entry = ledger.issues.find(({ disposition }) => disposition === "KEEP_HUB");
  entry.targetRepository = "AquilaXk/easysubway-mobile";

  assert.deepEqual(validateLedger(ledger), [
    "issues[2].targetRepository: KEEP_HUB target은 sourceRepository여야 함",
    "issues[2].targetRepository: frozen reviewed mapping과 불일치",
  ]);
});

test("reason과 source issue URL 번호는 ledger entry와 일치해야 한다", () => {
  const ledger = ledgerFixture();
  delete ledger.issues[0].reason;
  ledger.issues[1].sourceUrl = "https://github.com/AquilaXk/easysubway/issues/9999";

  assert.deepEqual(validateLedger(ledger), [
    "issues[0].reason: reason이 필요함",
    "issues[1].sourceUrl: sourceIssue와 URL 번호 불일치",
  ]);
});

test("허용된 다섯 repository 밖의 target은 거부한다", () => {
  const ledger = ledgerFixture();
  ledger.issues[0].targetRepository = "AquilaXk/other";

  assert.deepEqual(validateLedger(ledger), [
    "issues[0].targetRepository: 허용되지 않은 repository",
    "issues[0].targetRepository: TRANSFER는 approved non-hub target이 필요함",
    "issues[0].targetRepository: frozen reviewed mapping과 불일치",
  ]);
});

test("TRANSFER는 approved와 transferred execution state를 차례로 허용한다", () => {
  const ledger = ledgerFixture();
  const entry = ledger.issues[0];
  for (const otherEntry of ledger.issues.slice(1)) {
    otherEntry.executionApproval = null;
    otherEntry.targetUrl = null;
    otherEntry.transferredAt = null;
  }
  entry.executionApproval = "https://github.com/AquilaXk/easysubway/issues/2691#issuecomment-1";

  assert.deepEqual(validateLedger(ledger), []);
  assert.deepEqual(validateLedger(ledger, { requirePending: true }), [
    "issues[0].execution: requirePending에서는 PENDING만 허용",
  ]);

  entry.targetUrl = "https://github.com/AquilaXk/easysubway-mobile/issues/1";
  entry.transferredAt = "2026-07-30T00:00:00.000Z";

  assert.deepEqual(validateLedger(ledger), []);
  entry.transferredAt = "2026-07-30T00:00:00Z";
  assert.deepEqual(validateLedger(ledger), []);
});

test("TRANSFER execution state는 approval·target URL·timestamp의 순서를 강제한다", () => {
  const ledger = ledgerFixture();
  const entry = ledger.issues[0];
  entry.targetUrl = "https://github.com/AquilaXk/easysubway-mobile/issues/1";

  assert.deepEqual(validateLedger(ledger), [
    "issues[0].execution: 허용되지 않은 TRANSFER execution state",
  ]);
});

test("KEEP_HUB와 SPLIT_CHILDREN은 PENDING execution state만 허용한다", () => {
  const ledger = ledgerFixture();
  ledger.issues[2].executionApproval = "https://github.com/AquilaXk/easysubway/issues/2691#issuecomment-1";
  ledger.issues.find(({ sourceIssue }) => sourceIssue === 2605).targetUrl = "https://github.com/AquilaXk/easysubway-data/issues/1";

  assert.deepEqual(validateLedger(ledger), [
    "issues[2].execution: KEEP_HUB은 PENDING만 허용",
    "issues[40].execution: SPLIT_CHILDREN은 PENDING만 허용",
  ]);
});

test("schema는 TRANSFER의 세 execution state를 표현하고 불완전한 조합을 거부한다", () => {
  const schema = JSON.parse(readFileSync("contracts/repository-split-issues.schema.json", "utf8"));
  const approved = ledgerFixture();
  approved.issues[0].executionApproval = "https://github.com/AquilaXk/easysubway/issues/2691#issuecomment-1";
  const transferred = structuredClone(approved);
  transferred.issues[0].targetUrl = "https://github.com/AquilaXk/easysubway-mobile/issues/1";
  transferred.issues[0].transferredAt = "2026-07-30T00:00:00.000Z";
  const incomplete = structuredClone(approved);
  incomplete.issues[0].transferredAt = "2026-07-30T00:00:00.000Z";

  assert.deepEqual(validateSchema(schema, approved).errors, []);
  assert.deepEqual(validateSchema(schema, transferred).errors, []);
  assert.ok(validateSchema(schema, incomplete).errors.some((error) => error.includes("oneOf")));
});
