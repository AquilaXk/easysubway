import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";
import {
  entriesForTarget,
  entryForSourceIssue,
  validateAmendments,
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
const MOBILE_APPROVAL_URL = "https://github.com/AquilaXk/easysubway/issues/2718#issuecomment-5139602699";
const BACKEND_APPROVED = new Set([
  2095, 2524, 2535, 2536, 2537, 2538, 2544, 2545, 2622, 2623, 2624, 2625, 2626, 2667, 2675, 2676, 2677,
]);
const BACKEND_TRANSFERS = new Map([
  [2095, ["https://github.com/AquilaXk/easysubway-backend/issues/3", "2026-07-31T04:02:01Z"]],
  [2524, ["https://github.com/AquilaXk/easysubway-backend/issues/25", "2026-08-01T16:08:53Z"]],
  [2535, ["https://github.com/AquilaXk/easysubway-backend/issues/21", "2026-08-01T16:08:34Z"]],
  [2536, ["https://github.com/AquilaXk/easysubway-backend/issues/22", "2026-08-01T16:08:44Z"]],
  [2537, ["https://github.com/AquilaXk/easysubway-backend/issues/23", "2026-08-01T16:08:43Z"]],
  [2538, ["https://github.com/AquilaXk/easysubway-backend/issues/24", "2026-08-01T16:08:45Z"]],
  [2544, ["https://github.com/AquilaXk/easysubway-backend/issues/4", "2026-07-31T04:04:02Z"]],
  [2545, ["https://github.com/AquilaXk/easysubway-backend/issues/5", "2026-07-31T04:17:59Z"]],
  [2622, ["https://github.com/AquilaXk/easysubway-backend/issues/6", "2026-07-31T04:18:15Z"]],
  [2623, ["https://github.com/AquilaXk/easysubway-backend/issues/7", "2026-07-31T04:18:28Z"]],
  [2624, ["https://github.com/AquilaXk/easysubway-backend/issues/8", "2026-07-31T04:18:49Z"]],
  [2625, ["https://github.com/AquilaXk/easysubway-backend/issues/9", "2026-07-31T04:19:05Z"]],
  [2626, ["https://github.com/AquilaXk/easysubway-backend/issues/10", "2026-07-31T04:19:21Z"]],
  [2667, ["https://github.com/AquilaXk/easysubway-backend/issues/19", "2026-08-01T11:09:21Z"]],
  [2675, ["https://github.com/AquilaXk/easysubway-backend/issues/11", "2026-07-31T04:19:40Z"]],
  [2676, ["https://github.com/AquilaXk/easysubway-backend/issues/12", "2026-07-31T04:19:48Z"]],
  [2677, ["https://github.com/AquilaXk/easysubway-backend/issues/13", "2026-07-31T04:20:00Z"]],
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
const MOBILE_TRANSFERS = new Map([
  [571, ["https://github.com/AquilaXk/easysubway-mobile/issues/7", "2026-07-31T07:00:04Z"]],
  [1016, ["https://github.com/AquilaXk/easysubway-mobile/issues/8", "2026-07-31T12:30:31Z"]],
  [1021, ["https://github.com/AquilaXk/easysubway-mobile/issues/9", "2026-07-31T12:33:02Z"]],
  [1918, ["https://github.com/AquilaXk/easysubway-mobile/issues/10", "2026-07-31T12:34:27Z"]],
  [2055, ["https://github.com/AquilaXk/easysubway-mobile/issues/11", "2026-07-31T12:35:23Z"]],
  [2525, ["https://github.com/AquilaXk/easysubway-mobile/issues/13", "2026-07-31T12:37:22Z"]],
  [2539, ["https://github.com/AquilaXk/easysubway-mobile/issues/18", "2026-07-31T12:45:46Z"]],
  [2540, ["https://github.com/AquilaXk/easysubway-mobile/issues/19", "2026-07-31T12:46:01Z"]],
  [2541, ["https://github.com/AquilaXk/easysubway-mobile/issues/20", "2026-07-31T12:49:24Z"]],
  [2542, ["https://github.com/AquilaXk/easysubway-mobile/issues/21", "2026-07-31T12:49:42Z"]],
  [2543, ["https://github.com/AquilaXk/easysubway-mobile/issues/22", "2026-07-31T12:49:57Z"]],
  [2547, ["https://github.com/AquilaXk/easysubway-mobile/issues/23", "2026-07-31T12:50:12Z"]],
  [2586, ["https://github.com/AquilaXk/easysubway-mobile/issues/24", "2026-07-31T12:51:14Z"]],
  [2591, ["https://github.com/AquilaXk/easysubway-mobile/issues/25", "2026-07-31T12:51:35Z"]],
  [2596, ["https://github.com/AquilaXk/easysubway-mobile/issues/26", "2026-07-31T12:52:04Z"]],
  [2600, ["https://github.com/AquilaXk/easysubway-mobile/issues/27", "2026-07-31T12:54:23Z"]],
  [2612, ["https://github.com/AquilaXk/easysubway-mobile/issues/28", "2026-07-31T12:54:52Z"]],
  [2613, ["https://github.com/AquilaXk/easysubway-mobile/issues/29", "2026-07-31T12:55:36Z"]],
  [2617, ["https://github.com/AquilaXk/easysubway-mobile/issues/30", "2026-07-31T12:55:54Z"]],
  [2619, ["https://github.com/AquilaXk/easysubway-mobile/issues/31", "2026-07-31T12:56:09Z"]],
  [2620, ["https://github.com/AquilaXk/easysubway-mobile/issues/32", "2026-07-31T12:56:26Z"]],
  [2621, ["https://github.com/AquilaXk/easysubway-mobile/issues/33", "2026-07-31T12:56:52Z"]],
  [2628, ["https://github.com/AquilaXk/easysubway-mobile/issues/34", "2026-07-31T12:57:08Z"]],
  [2629, ["https://github.com/AquilaXk/easysubway-mobile/issues/35", "2026-07-31T12:57:23Z"]],
  [2630, ["https://github.com/AquilaXk/easysubway-mobile/issues/36", "2026-07-31T12:57:40Z"]],
  [2678, ["https://github.com/AquilaXk/easysubway-mobile/issues/37", "2026-07-31T12:58:00Z"]],
  [2679, ["https://github.com/AquilaXk/easysubway-mobile/issues/38", "2026-07-31T12:58:23Z"]],
  [2680, ["https://github.com/AquilaXk/easysubway-mobile/issues/39", "2026-07-31T12:58:39Z"]],
]);

function ledgerFixture() {
  return JSON.parse(readFileSync("release/migrations/repository-split-issues.json", "utf8"));
}

function amendmentsFixture() {
  return JSON.parse(readFileSync("release/migrations/repository-split-issues-amendments.json", "utf8"));
}

function amendmentsSchema() {
  return JSON.parse(readFileSync("contracts/repository-split-issue-amendments.schema.json", "utf8"));
}

test("reviewed source issue ledger는 component transfer approval state를 만족한다", () => {
  const ledger = ledgerFixture();

  assert.equal(ledger.issues.length, 71);
  assert.deepEqual(validateLedger(ledger, { openIssueNumbers: REVIEWED_SOURCE_ISSUE_NUMBERS }), []);
  for (const entry of ledger.issues) {
    const transfer = DATA_TRANSFERS.get(entry.sourceIssue) ?? BACKEND_TRANSFERS.get(entry.sourceIssue) ?? MOBILE_TRANSFERS.get(entry.sourceIssue);
    assert.equal(entry.executionApproval, DATA_TRANSFERS.has(entry.sourceIssue) ? DATA_APPROVAL_URL
      : BACKEND_APPROVED.has(entry.sourceIssue) ? BACKEND_APPROVAL_URL
        : entry.targetRepository === "AquilaXk/easysubway-mobile" ? MOBILE_APPROVAL_URL : null);
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
  assert.deepEqual(
    entriesForTarget(ledger, "AquilaXk/easysubway-backend").map(({ sourceIssue }) => sourceIssue),
    [
      2095, 2524, 2535, 2536, 2537, 2538, 2544, 2545, 2548, 2622,
      2623, 2624, 2625, 2626, 2627, 2667, 2674, 2675, 2676, 2677,
    ],
  );
  assert.deepEqual(
    entriesForTarget(ledger, "AquilaXk/easysubway-mobile").map(({ sourceIssue }) => sourceIssue),
    [
      571, 1016, 1021, 1918, 2055, 2525, 2539, 2540, 2541, 2542, 2543, 2547, 2548, 2586, 2591, 2596,
      2600, 2605, 2612, 2613, 2617, 2619, 2620, 2621, 2627, 2628, 2629, 2630, 2674, 2678, 2679, 2680,
    ],
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
  ledger.issues[0].executionApproval = null;
  ledger.issues[0].targetUrl = null;
  ledger.issues[0].transferredAt = null;
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
  entry.targetUrl = null;
  entry.transferredAt = null;

  assert.deepEqual(validateLedger(ledger), [
    "issues[0].targetRepository: TRANSFER는 approved non-hub target이 필요함",
    "issues[0].targetRepository: frozen reviewed mapping과 불일치",
  ]);
});

test("TRANSFER는 null target을 허용하지 않는다", () => {
  const ledger = ledgerFixture();
  ledger.issues[0].targetRepository = null;
  ledger.issues[0].targetUrl = null;
  ledger.issues[0].transferredAt = null;

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
  ledger.issues[0].targetUrl = null;
  ledger.issues[0].transferredAt = null;

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
  entry.targetUrl = null;
  entry.transferredAt = null;
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
  entry.transferredAt = null;

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

test("SPLIT_CHILDREN는 childRepositories와 일치하는 child issue URL을 기록한다", () => {
  const ledger = ledgerFixture();
  const schema = JSON.parse(readFileSync("contracts/repository-split-issues.schema.json", "utf8"));

  assert.deepEqual(entryForSourceIssue(ledger, 2605).childIssueUrls, {
    "AquilaXk/easysubway-data": "https://github.com/AquilaXk/easysubway-data/issues/21",
    "AquilaXk/easysubway-mobile": "https://github.com/AquilaXk/easysubway-mobile/issues/5",
  });
  assert.deepEqual(validateSchema(schema, ledger).errors, []);
  assert.deepEqual(validateLedger(ledger), []);
});

test("SPLIT_CHILDREN는 backend와 mobile child 조합도 기록한다", () => {
  const ledger = ledgerFixture();
  const schema = JSON.parse(readFileSync("contracts/repository-split-issues.schema.json", "utf8"));

  for (const [sourceIssue, backendIssue, mobileIssue] of [[2548, 31, 47], [2627, 32, 48], [2674, 33, 49]]) {
    const entry = entryForSourceIssue(ledger, sourceIssue);
    assert.equal(entry.disposition, "SPLIT_CHILDREN");
    assert.equal(entry.targetRepository, null);
    assert.deepEqual(entry.childRepositories, ["AquilaXk/easysubway-backend", "AquilaXk/easysubway-mobile"]);
    assert.deepEqual(entry.childIssueUrls, {
      "AquilaXk/easysubway-backend": `https://github.com/AquilaXk/easysubway-backend/issues/${backendIssue}`,
      "AquilaXk/easysubway-mobile": `https://github.com/AquilaXk/easysubway-mobile/issues/${mobileIssue}`,
    });
  }
  assert.deepEqual(validateSchema(schema, ledger).errors, []);
  assert.deepEqual(validateLedger(ledger), []);
});

test("SPLIT_CHILDREN는 frozen mapping 밖의 child repository 조합을 거부한다", () => {
  const ledger = ledgerFixture();
  const schema = JSON.parse(readFileSync("contracts/repository-split-issues.schema.json", "utf8"));
  const entry = entryForSourceIssue(ledger, 2548);
  entry.childRepositories = ["AquilaXk/easysubway-data", "AquilaXk/easysubway-mobile"];
  entry.childIssueUrls = {
    "AquilaXk/easysubway-data": "https://github.com/AquilaXk/easysubway-data/issues/21",
    "AquilaXk/easysubway-mobile": "https://github.com/AquilaXk/easysubway-mobile/issues/47",
  };

  assert.deepEqual(validateLedger(ledger), [
    "issues[35].childRepositories: frozen reviewed mapping의 child repository가 정확히 필요함",
  ]);
  assert.deepEqual(validateSchema(schema, ledger).errors, []);
});

test("SPLIT_CHILDREN는 비어 있지 않은 childIssueUrls를 반드시 기록한다", () => {
  const ledger = ledgerFixture();
  const schema = JSON.parse(readFileSync("contracts/repository-split-issues.schema.json", "utf8"));
  delete entryForSourceIssue(ledger, 2605).childIssueUrls;

  assert.deepEqual(validateLedger(ledger), ["issues[40].childIssueUrls: child repository별 child issue URL이 필요함"]);
  assert.ok(validateSchema(schema, ledger).errors.some((error) => error.includes("$.issues.40: not 분기")));
});

test("childIssueUrls는 SPLIT_CHILDREN의 정확한 repository key와 중복 없는 positive issue URL만 허용한다", () => {
  const invalidChildIssueUrls = [
    [
      "missing key",
      (entry) => delete entry.childIssueUrls["AquilaXk/easysubway-mobile"],
      ["issues[40].childIssueUrls: childRepositories key와 정확히 일치해야 함"],
    ],
    [
      "extra key",
      (entry) => { entry.childIssueUrls["AquilaXk/easysubway-platform"] = "https://github.com/AquilaXk/easysubway-platform/issues/1"; },
      ["issues[40].childIssueUrls: childRepositories key와 정확히 일치해야 함"],
    ],
    [
      "duplicate URL",
      (entry) => { entry.childIssueUrls["AquilaXk/easysubway-mobile"] = "https://github.com/AquilaXk/easysubway-data/issues/21"; },
      [
        "issues[40].childIssueUrls: child issue URL 중복",
        "issues[40].childIssueUrls.AquilaXk/easysubway-mobile: repository와 URL repository 불일치",
      ],
    ],
    [
      "wrong repository",
      (entry) => { entry.childIssueUrls["AquilaXk/easysubway-mobile"] = "https://github.com/AquilaXk/easysubway-data/issues/5"; },
      ["issues[40].childIssueUrls.AquilaXk/easysubway-mobile: repository와 URL repository 불일치"],
    ],
    [
      "non-positive issue number",
      (entry) => { entry.childIssueUrls["AquilaXk/easysubway-data"] = "https://github.com/AquilaXk/easysubway-data/issues/0"; },
      ["issues[40].childIssueUrls.AquilaXk/easysubway-data: positive GitHub issue URL 불량"],
    ],
    [
      "leading-zero issue number",
      (entry) => { entry.childIssueUrls["AquilaXk/easysubway-data"] = "https://github.com/AquilaXk/easysubway-data/issues/01"; },
      ["issues[40].childIssueUrls.AquilaXk/easysubway-data: positive GitHub issue URL 불량"],
    ],
  ];

  const schema = JSON.parse(readFileSync("contracts/repository-split-issues.schema.json", "utf8"));
  for (const [, mutate, errors] of invalidChildIssueUrls) {
    const ledger = ledgerFixture();
    mutate(entryForSourceIssue(ledger, 2605));
    assert.deepEqual(validateLedger(ledger), errors);
    assert.ok(validateSchema(schema, ledger).errors.some(
      (error) => error.includes("$.issues.40.childIssueUrls: oneOf 분기 정확히 하나와 일치해야 함"),
    ));
  }
});

test("childIssueUrls는 SPLIT_CHILDREN에서만 허용한다", () => {
  const ledger = ledgerFixture();
  const schema = JSON.parse(readFileSync("contracts/repository-split-issues.schema.json", "utf8"));
  ledger.issues[0].childIssueUrls = {
    "AquilaXk/easysubway-data": "https://github.com/AquilaXk/easysubway-data/issues/1",
    "AquilaXk/easysubway-mobile": "https://github.com/AquilaXk/easysubway-mobile/issues/1",
  };

  assert.deepEqual(validateLedger(ledger), ["issues[0].childIssueUrls: SPLIT_CHILDREN에서만 허용됨"]);
  assert.ok(validateSchema(schema, ledger).errors.some((error) => error.includes("$.issues.0: not 분기")));
});

test("childIssueUrls가 있으면 malformed childRepositories도 결정적 오류로 거부한다", () => {
  const childRepositoriesValues = [
    ["missing", (entry) => delete entry.childRepositories],
    ["null", (entry) => { entry.childRepositories = null; }],
    ["string", (entry) => { entry.childRepositories = "AquilaXk/easysubway-data"; }],
    ["duplicate", (entry) => { entry.childRepositories = ["AquilaXk/easysubway-data", "AquilaXk/easysubway-data"]; }],
  ];

  for (const [, mutate] of childRepositoriesValues) {
    const ledger = ledgerFixture();
    mutate(entryForSourceIssue(ledger, 2605));
    assert.doesNotThrow(() => validateLedger(ledger));
    assert.deepEqual(validateLedger(ledger), [
      "issues[40].childRepositories: frozen reviewed mapping의 child repository가 정확히 필요함",
      "issues[40].childIssueUrls: childRepositories key와 정확히 일치해야 함",
    ]);
  }
});

test("post-snapshot amendments는 snapshot 밖 hub issue의 분류를 기록한다", () => {
  const ledger = ledgerFixture();
  const amendments = amendmentsFixture();

  assert.deepEqual(validateSchema(amendmentsSchema(), amendments).errors, []);
  assert.deepEqual(validateAmendments(amendments, { ledger }), []);
  assert.deepEqual(amendments.amendments.map(({ sourceIssue }) => sourceIssue), [
    1685, 2649, 2700, 2705, 2710, 2712, 2714, 2720, 2727, 2728, 2729,
    2731, 2732, 2734, 2739, 2740, 2741, 2742, 2743, 2747, 2748, 2764,
    2765, 2766, 2767, 2768, 2776,
  ]);
  assert.deepEqual(
    amendments.amendments.filter(({ disposition }) => disposition === "TRANSFER"),
    [{
      sourceIssue: 2700,
      title: "[Architecture][Mobile] datapack lock과 verified AAB staging 도입",
      disposition: "TRANSFER",
      targetRepository: "AquilaXk/easysubway-mobile",
      targetUrl: "https://github.com/AquilaXk/easysubway-mobile/issues/45",
      transferredAt: "2026-08-01T16:08:48Z",
      reason: "mobile datapack lock과 AAB staging 산출물 단독 소유",
      classifiedAt: "2026-08-01T16:59:35Z",
    }],
  );
});

test("amendments는 snapshot ledger sourceIssue와 겹치면 무효화한다", () => {
  const ledger = ledgerFixture();
  const amendments = amendmentsFixture();
  amendments.amendments[1].sourceIssue = 2691;

  assert.deepEqual(validateAmendments(amendments, { ledger }), ["amendments[1].sourceIssue: snapshot ledger와 중복"]);
});

test("amendments 안의 sourceIssue 중복은 무효화한다", () => {
  const ledger = ledgerFixture();
  const amendments = amendmentsFixture();
  const duplicate = structuredClone(amendments.amendments[1]);
  amendments.amendments.push(duplicate);

  assert.deepEqual(validateAmendments(amendments, { ledger }), [`amendments: sourceIssue ${duplicate.sourceIssue} 중복`]);
});

test("amendments TRANSFER는 targetRepository와 일치하는 실행 필드를 요구한다", () => {
  const ledger = ledgerFixture();
  const transferIndex = amendmentsFixture().amendments.findIndex(({ sourceIssue }) => sourceIssue === 2700);
  const executionError = `amendments[${transferIndex}].execution: TRANSFER는 targetRepository와 일치하는 targetUrl과 transferredAt이 필요함`;
  const mismatchedRepository = amendmentsFixture();
  mismatchedRepository.amendments[transferIndex].targetUrl = "https://github.com/AquilaXk/easysubway-backend/issues/45";

  // 스키마는 승인된 4개 target repository URL을 모두 허용하므로 target↔URL 결속은 semantic 검증이 잡는다.
  assert.deepEqual(validateSchema(amendmentsSchema(), mismatchedRepository).errors, []);
  assert.deepEqual(validateAmendments(mismatchedRepository, { ledger }), [executionError]);

  for (const mutate of [
    (entry) => { entry.targetUrl = null; },
    (entry) => { entry.transferredAt = null; },
    (entry) => { entry.transferredAt = "2026-08-32T16:08:48Z"; },
  ]) {
    const amendments = amendmentsFixture();
    mutate(amendments.amendments[transferIndex]);
    assert.deepEqual(validateAmendments(amendments, { ledger }), [executionError]);
    assert.ok(validateSchema(amendmentsSchema(), amendments).errors.some(
      (error) => error.includes(`$.amendments.${transferIndex}: oneOf 분기 정확히 하나와 일치해야 함`),
    ));
  }
});

test("amendments KEEP_HUB는 hub target과 null 실행 필드만 허용한다", () => {
  const ledger = ledgerFixture();
  const withTargetUrl = amendmentsFixture();
  withTargetUrl.amendments[1].targetUrl = "https://github.com/AquilaXk/easysubway-mobile/issues/45";
  const withTargetRepository = amendmentsFixture();
  withTargetRepository.amendments[1].targetRepository = "AquilaXk/easysubway-mobile";

  assert.deepEqual(validateAmendments(withTargetUrl, { ledger }), [
    "amendments[1].execution: KEEP_HUB은 targetUrl과 transferredAt이 null이어야 함",
  ]);
  assert.ok(validateSchema(amendmentsSchema(), withTargetUrl).errors.some(
    (error) => error.includes("$.amendments.1: oneOf 분기 정확히 하나와 일치해야 함"),
  ));
  assert.deepEqual(validateAmendments(withTargetRepository, { ledger }), [
    "amendments[1].targetRepository: KEEP_HUB target은 sourceRepository여야 함",
  ]);
});

test("amendments는 SPLIT_CHILDREN과 필수 서술 누락을 fail closed한다", () => {
  const ledger = ledgerFixture();
  const amendments = amendmentsFixture();
  amendments.amendments[1].disposition = "SPLIT_CHILDREN";
  amendments.amendments[2].reason = "  ";
  amendments.amendments[3].classifiedAt = "2026-08-01T16:59:35";
  amendments.amendments[4].title = "";

  assert.deepEqual(validateAmendments(amendments, { ledger }), [
    "amendments[1].disposition: amendments는 KEEP_HUB과 TRANSFER만 지원함",
    "amendments[2].reason: reason이 필요함",
    "amendments[3].classifiedAt: UTC 시각이 필요함",
    "amendments[4].title: title이 필요함",
  ]);
});

test("amendments 검증은 snapshot ledger 없이 통과하지 않는다", () => {
  const amendments = amendmentsFixture();

  assert.deepEqual(validateAmendments(amendments), ["amendments: 중복 판정에 snapshot ledger issues가 필요함"]);
  assert.deepEqual(validateAmendments({}, { ledger: ledgerFixture() }), ["amendments: 배열 필요"]);
});

test("schema는 TRANSFER의 세 execution state를 표현하고 불완전한 조합을 거부한다", () => {
  const schema = JSON.parse(readFileSync("contracts/repository-split-issues.schema.json", "utf8"));
  const approved = ledgerFixture();
  approved.issues[0].executionApproval = "https://github.com/AquilaXk/easysubway/issues/2691#issuecomment-1";
  approved.issues[0].targetUrl = null;
  approved.issues[0].transferredAt = null;
  const transferred = structuredClone(approved);
  transferred.issues[0].targetUrl = "https://github.com/AquilaXk/easysubway-mobile/issues/1";
  transferred.issues[0].transferredAt = "2026-07-30T00:00:00.000Z";
  const incomplete = structuredClone(approved);
  incomplete.issues[0].transferredAt = "2026-07-30T00:00:00.000Z";

  assert.deepEqual(validateSchema(schema, approved).errors, []);
  assert.deepEqual(validateSchema(schema, transferred).errors, []);
  assert.ok(validateSchema(schema, incomplete).errors.some((error) => error.includes("oneOf")));
});
