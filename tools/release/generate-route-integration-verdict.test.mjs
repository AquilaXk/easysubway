import assert from "node:assert/strict";
import test from "node:test";

import {
  ROUTE_INTEGRATION_SCENARIOS,
  ROUTE_SEARCH_CATALOG_ID,
  buildRouteIntegrationVerdict,
} from "./generate-route-integration-verdict.mjs";

const CANONICAL_IDENTITY = {
  gitSha: "26d1461210a36d9d969e5a18d5f13725519abdcd",
  appVersionName: "1.0.4",
  versionCode: "10005",
  aabSha256: "87df6fd89fd8490a8af0d754e48a17288b880f3e918bde87729b79fee88435cc",
  aabPayloadSha256: "e2b9753619285e685a713e101b996129781f9067de5bc6a90a125c5c9de95758",
  backendImageDigest: null,
  backendArtifactSha256: "74a3e35762d1973c0b05a0c0bd6f0fc6aa2a4657ef23cde359cf100e0830f631",
  dataPackManifestSha256: "2ee9f38f3e748d7bbc6d9eba124b34e6b5c8ad539338a6cdeee7a472515456e5",
  dataPackArtifactSha256: "7bb4bb68f0642e45377d98b083e93cd8c1c92aaa58dd353f32189e3f325a1562",
  routeContractVersion: "route-map-contract-v1",
  realtimeContractVersion: "seoul-topis-schema-v1",
};

function rcManifest(identity = CANONICAL_IDENTITY) {
  return { rcIdentity: { ...identity }, releaseCandidateIdentity: { ...identity } };
}

function plannerEvidence(overrides = {}) {
  return {
    sourceIssue: 2098,
    provenance: "final-candidate",
    testRunUrl: "https://example.invalid/run/planner",
    releaseCandidateIdentity: { ...CANONICAL_IDENTITY },
    plannerIdentity: {
      canonicalPackSha256: CANONICAL_IDENTITY.dataPackArtifactSha256,
      timetableSnapshotSha256: "a".repeat(64),
      canonicalStationSetSha256: "d".repeat(64),
      sourceLineageSha256: "e".repeat(64),
    },
    checks: { unknownPatternDefaultedToLocal: false },
    integrationScenarios: {
      E2: "PASS",
      E3: "PASS",
      E4: "PASS",
      E5: "PASS",
      E6: "PASS",
      E9: "PASS",
    },
    canaryResult: {
      plan: {
        itineraries: [
          {
            steps: [
              { stepType: "entry", serviceClass: null, servicePattern: null },
              { stepType: "ride", serviceClass: "SUBWAY", servicePattern: "LOCAL" },
              { stepType: "ride", serviceClass: "ITX_CHEONGCHUN", servicePattern: "EXPRESS" },
              { stepType: "exit", serviceClass: null, servicePattern: null },
            ],
          },
        ],
      },
    },
    ...overrides,
  };
}

function mobileEvidence(overrides = {}) {
  return {
    sourceIssue: 2099,
    provenance: "manual-observation",
    releaseCandidateIdentity: { ...CANONICAL_IDENTITY },
    integrationScenarios: { E7: "PASS", E8: "PASS", E9: "PASS" },
    ...overrides,
  };
}

function routeMapEvidence(overrides = {}) {
  return {
    sourceIssue: 2068,
    provenance: "final-candidate",
    releaseCandidateIdentity: { ...CANONICAL_IDENTITY },
    integrationScenarios: { E1: "PASS" },
    ...overrides,
  };
}

function goInputs(overrides = {}) {
  return {
    rcManifest: rcManifest(),
    plannerEvidence: plannerEvidence(),
    mobileEvidence: mobileEvidence(),
    routeMapEvidence: routeMapEvidence(),
    generatedAt: "2026-07-17T15:00:00.000Z",
    ...overrides,
  };
}

test("완전히 일치하는 same-RC 증거 조합은 GO로 판정하고 E1~E9를 모두 PASS로 채운다", () => {
  const verdict = buildRouteIntegrationVerdict(goInputs());

  assert.equal(verdict.schemaVersion, 1);
  assert.equal(verdict.releaseGate, "route-integration-verdict");
  assert.equal(verdict.issue, 1414);
  assert.equal(verdict.apiContract.catalogId, ROUTE_SEARCH_CATALOG_ID);
  assert.equal(verdict.decision, "GO");
  assert.equal(verdict.blockers.length, 0);
  assert.equal(verdict.scenarioMatrix.length, ROUTE_INTEGRATION_SCENARIOS.length);
  assert.ok(verdict.scenarioMatrix.every((scenario) => scenario.result === "PASS"));
  assert.ok(verdict.noGoConditions.every((condition) => !condition.triggered && !condition.unresolved));
  assert.equal(verdict.artifactIdentityLinkage.timetableSnapshotSha256, "a".repeat(64));
  assert.match(verdict.verdictDigestSha256, /^[0-9a-f]{64}$/);
  // 각 시나리오는 실존 producer issue와 test에 연결된다.
  for (const scenario of verdict.scenarioMatrix) {
    assert.match(scenario.producerIssueUrl, /github\.com\/.+\/issues\/\d+$/);
    assert.ok(scenario.evidenceTests.length > 0);
  }
});

test("backendArtifactSha256/backendImageDigest가 모두 null이면 anchor 미완성으로 NO_GO한다", () => {
  const verdict = buildRouteIntegrationVerdict(goInputs({
    rcManifest: rcManifest({ ...CANONICAL_IDENTITY, backendArtifactSha256: null, backendImageDigest: null }),
  }));

  assert.equal(verdict.decision, "NO_GO");
  const mixed = verdict.noGoConditions.find((condition) => condition.id === "mixed_rc_or_artifact_identity");
  assert.equal(mixed.triggered, true);
  assert.ok(mixed.reasons.some((reason) => reason.includes("backendArtifactSha256|backendImageDigest")));
});

test("aabSha256/aabPayloadSha256이 없으면 mobile bundle anchor 미완성으로 NO_GO한다", () => {
  const verdict = buildRouteIntegrationVerdict(goInputs({
    rcManifest: rcManifest({ ...CANONICAL_IDENTITY, aabSha256: null, aabPayloadSha256: null }),
  }));

  assert.equal(verdict.decision, "NO_GO");
  const mixed = verdict.noGoConditions.find((condition) => condition.id === "mixed_rc_or_artifact_identity");
  assert.equal(mixed.triggered, true);
  assert.ok(mixed.reasons.some((reason) => reason.includes("aabSha256")));
});

test("서로 다른 aabSha256의 mobile evidence는 mixed identity로 NO_GO한다(같은 버전·다른 재빌드 구분)", () => {
  const verdict = buildRouteIntegrationVerdict(goInputs({
    mobileEvidence: mobileEvidence({
      releaseCandidateIdentity: { ...CANONICAL_IDENTITY, aabSha256: "f".repeat(64) },
    }),
  }));

  assert.equal(verdict.decision, "NO_GO");
  const mixed = verdict.noGoConditions.find((condition) => condition.id === "mixed_rc_or_artifact_identity");
  assert.equal(mixed.triggered, true);
});

test("backendImageDigest만 있어도(backendArtifactSha256 null) anchor는 충족된다", () => {
  const verdict = buildRouteIntegrationVerdict(goInputs({
    rcManifest: rcManifest({ ...CANONICAL_IDENTITY, backendArtifactSha256: null, backendImageDigest: "sha256:" + "1".repeat(64) }),
    plannerEvidence: plannerEvidence({
      releaseCandidateIdentity: { ...CANONICAL_IDENTITY, backendArtifactSha256: null, backendImageDigest: "sha256:" + "1".repeat(64) },
    }),
    mobileEvidence: mobileEvidence({
      releaseCandidateIdentity: { ...CANONICAL_IDENTITY, backendArtifactSha256: null, backendImageDigest: "sha256:" + "1".repeat(64) },
    }),
    routeMapEvidence: routeMapEvidence({
      releaseCandidateIdentity: { ...CANONICAL_IDENTITY, backendArtifactSha256: null, backendImageDigest: "sha256:" + "1".repeat(64) },
    }),
  }));

  const mixed = verdict.noGoConditions.find((condition) => condition.id === "mixed_rc_or_artifact_identity");
  assert.equal(mixed.triggered, false);
});

test("서로 다른 RC identity 증거를 조합하면 mixed identity로 NO_GO한다", () => {
  const verdict = buildRouteIntegrationVerdict(goInputs({
    plannerEvidence: plannerEvidence({
      releaseCandidateIdentity: { ...CANONICAL_IDENTITY, gitSha: "deadbeef".repeat(5) },
      plannerIdentity: {
        canonicalPackSha256: CANONICAL_IDENTITY.dataPackArtifactSha256,
        timetableSnapshotSha256: "a".repeat(64),
      },
    }),
  }));

  assert.equal(verdict.decision, "NO_GO");
  const mixed = verdict.noGoConditions.find((condition) => condition.id === "mixed_rc_or_artifact_identity");
  assert.equal(mixed.triggered, true);
  const plannerScenario = verdict.scenarioMatrix.find((scenario) => scenario.id === "E2");
  assert.equal(plannerScenario.result, "FAIL");
});

test("planner artifact identity(canonicalPackSha256) 불일치는 mixed identity로 NO_GO한다", () => {
  const verdict = buildRouteIntegrationVerdict(goInputs({
    plannerEvidence: plannerEvidence({
      plannerIdentity: {
        canonicalPackSha256: "f".repeat(64),
        timetableSnapshotSha256: "a".repeat(64),
      },
    }),
  }));

  assert.equal(verdict.decision, "NO_GO");
  const mixed = verdict.noGoConditions.find((condition) => condition.id === "mixed_rc_or_artifact_identity");
  assert.equal(mixed.triggered, true);
});

test("입력 누락은 PASS로 기본하지 않고 scenario PENDING·NO_GO로 fail closed한다", () => {
  const verdict = buildRouteIntegrationVerdict(goInputs({
    plannerEvidence: null,
    mobileEvidence: null,
    routeMapEvidence: null,
  }));

  assert.equal(verdict.decision, "NO_GO");
  assert.ok(verdict.scenarioMatrix.every((scenario) => scenario.result !== "PASS"));
  const e2 = verdict.scenarioMatrix.find((scenario) => scenario.id === "E2");
  assert.equal(e2.result, "PENDING");
});

test("fixture-only 증거는 fixture_only_evidence로 NO_GO한다", () => {
  const verdict = buildRouteIntegrationVerdict(goInputs({
    plannerEvidence: plannerEvidence({ provenance: "fixture" }),
  }));

  assert.equal(verdict.decision, "NO_GO");
  const fixture = verdict.noGoConditions.find((condition) => condition.id === "fixture_only_evidence");
  assert.equal(fixture.triggered, true);
});

test("RIDE leg가 serviceClass/servicePattern 없이 성공 응답되면 NO_GO한다", () => {
  const verdict = buildRouteIntegrationVerdict(goInputs({
    plannerEvidence: plannerEvidence({
      canaryResult: {
        plan: {
          itineraries: [{
            steps: [
              { stepType: "ride", serviceClass: "SUBWAY", servicePattern: null },
              { stepType: "ride", serviceClass: "ITX_CHEONGCHUN", servicePattern: "EXPRESS" },
            ],
          }],
        },
      },
    }),
  }));

  assert.equal(verdict.decision, "NO_GO");
  const rideMeta = verdict.noGoConditions.find((condition) => condition.id === "ride_leg_missing_service_metadata");
  assert.equal(rideMeta.triggered, true);
  const e3 = verdict.scenarioMatrix.find((scenario) => scenario.id === "E3");
  assert.equal(e3.result, "FAIL");
});

test("planner canary에 ITX_CHEONGCHUN EXPRESS ride가 없으면 E9를 FAIL로 낮춘다", () => {
  const verdict = buildRouteIntegrationVerdict(goInputs({
    plannerEvidence: plannerEvidence({
      canaryResult: {
        plan: {
          itineraries: [{
            steps: [
              { stepType: "ride", serviceClass: "SUBWAY", servicePattern: "LOCAL" },
            ],
          }],
        },
      },
    }),
  }));

  const e9 = verdict.scenarioMatrix.find((scenario) => scenario.id === "E9");
  assert.equal(e9.result, "FAIL");
  const itx = verdict.noGoConditions.find((condition) => condition.id === "itx_shown_as_generic_or_local_badged");
  assert.equal(itx.triggered, true);
  assert.equal(verdict.decision, "NO_GO");
});

test("scenario attestation FAIL은 연결된 NO_GO 조건을 발동한다", () => {
  const verdict = buildRouteIntegrationVerdict(goInputs({
    routeMapEvidence: routeMapEvidence({ integrationScenarios: { E1: "FAIL" } }),
  }));

  const e1 = verdict.scenarioMatrix.find((scenario) => scenario.id === "E1");
  assert.equal(e1.result, "FAIL");
  const control = verdict.noGoConditions.find(
    (condition) => condition.id === "route_map_local_express_control_present",
  );
  assert.equal(control.triggered, true);
  assert.equal(verdict.decision, "NO_GO");
});

test("seed의 unknown pattern을 LOCAL로 default하면 NO_GO한다", () => {
  const verdict = buildRouteIntegrationVerdict(goInputs({
    plannerEvidence: plannerEvidence({ checks: { unknownPatternDefaultedToLocal: true } }),
  }));

  const seed = verdict.noGoConditions.find((condition) => condition.id === "unknown_pattern_defaulted_to_local");
  assert.equal(seed.triggered, true);
  assert.equal(verdict.decision, "NO_GO");
});

test("rcManifest 없이는 판정하지 않는다", () => {
  assert.throws(() => buildRouteIntegrationVerdict({}), /rcManifest is required/);
});

test("planner canary가 ITX EXPRESS ride를 가져도 mobile evidence가 E9를 FAIL로 attest하면 덮어쓴다", () => {
  const verdict = buildRouteIntegrationVerdict(goInputs({
    mobileEvidence: mobileEvidence({ integrationScenarios: { E7: "PASS", E8: "PASS", E9: "FAIL" } }),
  }));

  const e9 = verdict.scenarioMatrix.find((scenario) => scenario.id === "E9");
  assert.equal(e9.result, "FAIL");
  assert.ok(e9.reasons.some((reason) => reason.includes("mobile evidence attests E9")));
  assert.equal(verdict.decision, "NO_GO");
});

test("mobile evidence가 없으면 planner만으로 E9가 fail-open PASS하지 않고 PENDING으로 낮아진다", () => {
  const verdict = buildRouteIntegrationVerdict(goInputs({ mobileEvidence: null }));

  const e9 = verdict.scenarioMatrix.find((scenario) => scenario.id === "E9");
  assert.equal(e9.result, "PENDING");
  assert.equal(verdict.decision, "NO_GO");
});

test("mobile evidence가 E9를 attest하지 않으면(E7/E8만) fail-open PASS하지 않고 PENDING으로 낮아진다", () => {
  const verdict = buildRouteIntegrationVerdict(goInputs({
    mobileEvidence: mobileEvidence({ integrationScenarios: { E7: "PASS", E8: "PASS" } }),
  }));

  const e9 = verdict.scenarioMatrix.find((scenario) => scenario.id === "E9");
  assert.equal(e9.result, "PENDING");
  assert.ok(e9.reasons.some((reason) => reason.includes("does not explicitly attest E9 as PASS")));
  assert.equal(verdict.decision, "NO_GO");
});

test("mobile evidence의 identity가 RC와 다르면 E9 PASS attestation을 신뢰하지 않고 PENDING으로 낮아진다", () => {
  const verdict = buildRouteIntegrationVerdict(goInputs({
    mobileEvidence: mobileEvidence({ releaseCandidateIdentity: { ...CANONICAL_IDENTITY, gitSha: "0".repeat(40) } }),
  }));

  // E9의 owner는 planner라 mismatch된 mobile evidence 자체가 E9 base 판정을 FAIL로 만들지는
  // 않는다 — 대신 fail-open override가 mismatch된 mobile의 E9 PASS를 신뢰하지 않고 PENDING으로
  // 낮춘다.
  const e9 = verdict.scenarioMatrix.find((scenario) => scenario.id === "E9");
  assert.equal(e9.result, "PENDING");
  // mobile evidence 자체의 identity mismatch는 별도로 mixed identity NO_GO도 발동시킨다.
  assert.equal(
    verdict.noGoConditions.find((condition) => condition.id === "mixed_rc_or_artifact_identity").triggered,
    true,
  );
  assert.equal(verdict.decision, "NO_GO");
});
