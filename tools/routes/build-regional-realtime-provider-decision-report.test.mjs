import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { buildRegionalRealtimeProviderDecisionReport } from "./build-regional-realtime-provider-decision-report.mjs";

const targets = {
  targetVersion: "2026-07-13",
  activeLineScopes: [
    { regionId: "capital", operatorId: "seoul-metro", lineId: "seoul-2" },
    { regionId: "busan", operatorId: "busan-transportation", lineId: "busan-1" },
    { regionId: "daejeon", operatorId: "daejeon-transportation", lineId: "daejeon-1" },
  ],
};

const officialSources = [
  {
    id: "public-api-audit",
    url: "https://www.data.go.kr/data/15000522/openapi.do",
    decision: "SCHEDULE_ONLY_NOT_REALTIME",
  },
];

function contract(decisions = [
  decision("busan", "busan-transportation", "busan-1"),
  decision("daejeon", "daejeon-transportation", "daejeon-1"),
]) {
  return {
    schemaVersion: 1,
    artifactKind: "regional-realtime-provider-decisions",
    issue: 1621,
    targetVersion: "2026-07-13",
    verifiedAt: "2026-07-13T17:50:29.249Z",
    scope: { excludedRegionIds: ["capital"] },
    officialSources,
    publicApiAudit: {
      targetCount: 2,
      credentialSafeCallCount: 2,
      uniqueQueryCount: 2,
      supportedCount: 0,
      explicitNoDataCount: 1,
      falsePositiveClassifiedCount: 1,
      boundedRetryCount: 1,
      searchPlanSha256: "a".repeat(64),
    },
    decisions,
  };
}

function decision(regionId, operatorId, lineId) {
  return {
    regionId,
    operatorId,
    lineId,
    state: "EXPLICITLY_UNSUPPORTED_WITH_EVIDENCE",
    fallback: "UNSUPPORTED_REGION",
    routeFallbackCapability: "PLANNED",
    userMessageKo: "이 지역은 실시간 도착 정보를 아직 제공하지 않아요.",
    evidenceRefs: ["public-api-audit"],
  };
}

function supportedDecision(regionId, operatorId, lineId) {
  return {
    regionId,
    operatorId,
    lineId,
    state: "SUPPORTED",
    fallback: "NONE",
    routeFallbackCapability: "PLANNED",
    providerId: "approved-provider",
    userMessageKo: "실시간 도착 정보를 제공해요.",
    evidenceRefs: ["public-api-audit"],
  };
}

test("비서울 active line 전체를 terminal state로 완결하고 실시간 claim은 열지 않는다", () => {
  const report = buildRegionalRealtimeProviderDecisionReport({ targets, contract: contract() });

  assert.equal(report.artifactKind, "regional-realtime-provider-decision-report");
  assert.deepEqual(report.scope, {
    excludedRegionIds: ["capital"],
    regionIds: ["busan", "daejeon"],
    activeLineOperatorScopeCount: 2,
  });
  assert.deepEqual(report.coverageResolution, {
    requirementCount: 2,
    supportedCount: 0,
    explicitlyUnsupportedCount: 2,
    missingCount: 0,
    supportedRatio: 0,
    terminalResolutionRatio: 1,
  });
  assert.equal(report.resolutionGate.allRequirementsResolved, true);
  assert.equal(report.claimGate.nationwideRealtimeSupportAllowed, false);
  assert.deepEqual(report.decisionEvidence.map(({ routeFallbackCapability }) => routeFallbackCapability), [
    "PLANNED",
    "PLANNED",
  ]);
});

test("target 누락·알 수 없는 evidence·내부 gate 문구를 거부한다", () => {
  assert.throws(
    () => buildRegionalRealtimeProviderDecisionReport({ targets, contract: contract([decision("busan", "busan-transportation", "busan-1")]) }),
    /missing regional realtime decision/,
  );
  assert.throws(
    () => buildRegionalRealtimeProviderDecisionReport({
      targets,
      contract: contract([
        { ...decision("busan", "busan-transportation", "busan-1"), evidenceRefs: ["missing"] },
        decision("daejeon", "daejeon-transportation", "daejeon-1"),
      ]),
    }),
    /unknown evidence ref/,
  );
  assert.throws(
    () => buildRegionalRealtimeProviderDecisionReport({
      targets,
      contract: contract([
        { ...decision("busan", "busan-transportation", "busan-1"), userMessageKo: "provider gate 미통과" },
        decision("daejeon", "daejeon-transportation", "daejeon-1"),
      ]),
    }),
    /internal release vocabulary/,
  );
});

test("SUPPORTED 결정은 providerId와 fallback NONE 계약을 지킨다", () => {
  const supported = supportedDecision("busan", "busan-transportation", "busan-1");
  const supportedContract = contract([
    supported,
    decision("daejeon", "daejeon-transportation", "daejeon-1"),
  ]);
  supportedContract.publicApiAudit = {
    ...supportedContract.publicApiAudit,
    supportedCount: 1,
    explicitNoDataCount: 0,
  };

  const report = buildRegionalRealtimeProviderDecisionReport({ targets, contract: supportedContract });
  assert.equal(report.coverageResolution.supportedCount, 1);
  assert.equal(report.coverageResolution.explicitlyUnsupportedCount, 1);
  assert.equal(report.resolutionGate.allRequirementsResolved, true);
  assert.equal(report.claimGate.nationwideRealtimeSupportAllowed, false);

  const { providerId: _providerId, ...missingProvider } = supported;
  assert.throws(
    () => buildRegionalRealtimeProviderDecisionReport({
      targets,
      contract: { ...supportedContract, decisions: [missingProvider, supportedContract.decisions[1]] },
    }),
    /providerId is required/,
  );
  assert.throws(
    () => buildRegionalRealtimeProviderDecisionReport({
      targets,
      contract: {
        ...supportedContract,
        decisions: [{ ...supported, fallback: "UNSUPPORTED_REGION" }, supportedContract.decisions[1]],
      },
    }),
    /supported fallback must be NONE/,
  );
});

test("public API 감사의 uniqueQueryCount는 음이 아닌 정수다", () => {
  const invalidContract = contract();
  invalidContract.publicApiAudit.uniqueQueryCount = -1;

  assert.throws(
    () => buildRegionalRealtimeProviderDecisionReport({ targets, contract: invalidContract }),
    /publicApiAudit.uniqueQueryCount must be a non-negative integer/,
  );
});

test("tracked 전국 target과 권역 decision report가 동일하게 재생성된다", async () => {
  const trackedTargets = JSON.parse(await readFile("tools/datapack/nationwide-coverage-targets.json", "utf8"));
  const trackedContract = JSON.parse(await readFile("tools/realtime/regional-realtime-provider-decisions.json", "utf8"));
  const trackedReport = JSON.parse(await readFile("tools/realtime/regional-realtime-provider-decision-report.json", "utf8"));

  assert.deepEqual(
    buildRegionalRealtimeProviderDecisionReport({ targets: trackedTargets, contract: trackedContract }),
    trackedReport,
  );
});
