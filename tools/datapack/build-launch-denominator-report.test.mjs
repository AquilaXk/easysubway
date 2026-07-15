import assert from "node:assert/strict";
import test from "node:test";
import {
  buildLaunchDenominatorReport,
  canonicalScopeHash,
} from "./build-launch-denominator-report.mjs";

const scope = {
  verifiedAccessibilityScope: {
    id: "capital-pilot-accessibility-v1",
    requiredRowIds: [
      "station-sangnoksu|seoul-4|ELEVATOR",
      "station-sangnoksu|seoul-4|ESCALATOR",
      "station-sangnoksu|seoul-4|WHEELCHAIR_LIFT",
      "station-sadang|seoul-4|ELEVATOR",
      "station-sadang|seoul-4|ESCALATOR",
      "station-sadang|seoul-4|WHEELCHAIR_LIFT",
    ],
  },
  routingLaunchScope: {
    id: "capital-routing-launch-v1",
    regionIds: ["capital"],
    operatorIds: ["seoul-metro", "korail"],
    lineIds: ["seoul-4", "line-54a7b980b7c3"],
    serviceIds: ["SUBWAY", "ITX_CHEONGCHUN"],
    candidateStationIds: ["station-a", "station-b", "station-c"],
    requiredBaseEdgeIds: ["edge-a-b", "edge-b-c"],
    requiredTransferEdgeIds: ["transfer-b"],
  },
  nationwideRoadmapScope: {
    id: "nationwide-roadmap-v1",
    launchRequiredCount: 270,
  },
  identityMatrix: {
    requiredSharedFields: [
      "canonicalStationVersion",
      "corridorId",
      "serviceId",
      "lineageId",
      "schemaVersion",
    ],
    differentArtifactHashesAllowed: true,
  },
};

function passingEvidence({ nationwideMissing = 270 } = {}) {
  const identity = {
    canonicalStationVersion: "station-catalog-v18",
    corridorId: "capital-gyeongchun-v1",
    serviceId: "ITX_CHEONGCHUN",
    lineageId: "launch-lineage-v1",
    schemaVersion: 1,
  };
  return {
    pilot: { coveredRowIds: [...scope.verifiedAccessibilityScope.requiredRowIds] },
    routing: {
      admittedStationIds: ["station-a", "station-b", "station-c"],
      materializedStationIds: ["station-a", "station-b", "station-c"],
      baseEdgeIds: [...scope.routingLaunchScope.requiredBaseEdgeIds],
      transferEdgeIds: [...scope.routingLaunchScope.requiredTransferEdgeIds],
      serviceIds: [...scope.routingLaunchScope.serviceIds],
    },
    source: {
      status: "ADMITTED",
      freshness: "FRESH",
      routingScopeHash: canonicalScopeHash(scope.routingLaunchScope),
      artifactHash: "a".repeat(64),
      identity: { ...identity },
    },
    server: {
      status: "ACTIVE",
      routingReady: true,
      artifactHash: "b".repeat(64),
      identity: { ...identity },
    },
    mobile: {
      status: "READY",
      topologyReady: true,
      artifactHash: "c".repeat(64),
      identity: { ...identity },
    },
    safety: {
      signatureValid: true,
      rollbackVerified: true,
      freshness: "FRESH",
      lineage: "VERIFIED",
    },
    claims: {
      accessibilityScopeId: scope.verifiedAccessibilityScope.id,
      routingScopeId: scope.routingLaunchScope.id,
      serviceIds: [...scope.routingLaunchScope.serviceIds],
    },
    forbiddenEvidence: [],
    nationwide: { missingCount: nationwideMissing },
  };
}

function withGap(mutator) {
  const evidence = passingEvidence();
  mutator(evidence);
  return evidence;
}

test("nationwide 0% does not block a fully satisfied v1 scope", () => {
  const report = buildLaunchDenominatorReport(scope, passingEvidence({ nationwideMissing: 270 }));
  assert.equal(report.decision, "GO");
  assert.equal(report.nationwideBlocksV1, false);
  assert.deepEqual(report.blockers, []);
});

test("pilot row and each routing exact-set gap block launch", async (context) => {
  const gaps = [
    ["pilot row", (evidence) => evidence.pilot.coveredRowIds.pop(), "PILOT_ROW_GAP"],
    ["admitted station", (evidence) => evidence.routing.admittedStationIds.pop(), "ROUTING_STATION_ID_GAP"],
    ["materialized station", (evidence) => evidence.routing.materializedStationIds.pop(), "ROUTING_STATION_ID_GAP"],
    ["base edge", (evidence) => evidence.routing.baseEdgeIds.pop(), "ROUTING_BASE_EDGE_ID_GAP"],
    ["transfer edge", (evidence) => evidence.routing.transferEdgeIds.pop(), "ROUTING_TRANSFER_EDGE_ID_GAP"],
  ];
  for (const [name, mutate, blocker] of gaps) {
    await context.test(name, () => {
      const report = buildLaunchDenominatorReport(scope, withGap(mutate));
      assert.equal(report.decision, "NO_GO");
      assert.ok(report.blockers.includes(blocker));
    });
  }
});

test("source admission, freshness, and routing scope hash fail closed", async (context) => {
  const gaps = [
    ["missing source", (evidence) => { evidence.source.status = "MISSING"; }, "SOURCE_NOT_ADMITTED"],
    ["stale source", (evidence) => { evidence.source.freshness = "STALE"; }, "SOURCE_STALE"],
    ["scope hash mismatch", (evidence) => { evidence.source.routingScopeHash = "d".repeat(64); }, "ROUTING_SCOPE_HASH_MISMATCH"],
  ];
  for (const [name, mutate, blocker] of gaps) {
    await context.test(name, () => {
      const report = buildLaunchDenominatorReport(scope, withGap(mutate));
      assert.equal(report.decision, "NO_GO");
      assert.ok(report.blockers.includes(blocker));
    });
  }
});

test("out-of-scope service and fixture or legacy evidence block launch", async (context) => {
  await context.test("out-of-scope service", () => {
    const report = buildLaunchDenominatorReport(scope, withGap((evidence) => {
      evidence.routing.serviceIds.push("KTX");
    }));
    assert.equal(report.decision, "NO_GO");
    assert.ok(report.blockers.includes("ROUTING_SERVICE_SCOPE_MISMATCH"));
  });
  for (const evidenceClass of ["FIXTURE", "LEGACY", "OTHER_SERVICE"]) {
    await context.test(evidenceClass, () => {
      const report = buildLaunchDenominatorReport(scope, withGap((evidence) => {
        evidence.forbiddenEvidence.push({ evidenceClass });
      }));
      assert.equal(report.decision, "NO_GO");
      assert.ok(report.blockers.includes("FORBIDDEN_EVIDENCE_CLASS"));
    });
  }
});

test("server, mobile, shared identity, and common safety evidence fail closed", async (context) => {
  const gaps = [
    ["inactive server", (evidence) => { evidence.server.status = "INACTIVE"; }, "SERVER_NOT_ACTIVE"],
    ["server routing", (evidence) => { evidence.server.routingReady = false; }, "SERVER_ROUTING_NOT_READY"],
    ["mobile status", (evidence) => { evidence.mobile.status = "MISSING"; }, "MOBILE_NOT_READY"],
    ["mobile topology", (evidence) => { evidence.mobile.topologyReady = false; }, "MOBILE_TOPOLOGY_NOT_READY"],
    ["identity", (evidence) => { evidence.mobile.identity.lineageId = "other-lineage"; }, "IDENTITY_FIELD_MISMATCH:lineageId"],
    ["signature", (evidence) => { evidence.safety.signatureValid = false; }, "SIGNATURE_INVALID"],
    ["rollback", (evidence) => { evidence.safety.rollbackVerified = false; }, "ROLLBACK_UNVERIFIED"],
    ["freshness", (evidence) => { evidence.safety.freshness = "STALE"; }, "EVIDENCE_STALE"],
    ["lineage", (evidence) => { evidence.safety.lineage = "MISMATCH"; }, "LINEAGE_UNVERIFIED"],
    ["claim", (evidence) => { evidence.claims.routingScopeId = "other-scope"; }, "CLAIM_SCOPE_MISMATCH"],
  ];
  for (const [name, mutate, blocker] of gaps) {
    await context.test(name, () => {
      const report = buildLaunchDenominatorReport(scope, withGap(mutate));
      assert.equal(report.decision, "NO_GO");
      assert.ok(report.blockers.includes(blocker));
    });
  }
});

test("different source, server, and mobile artifact hashes are allowed when shared identity matches", () => {
  const report = buildLaunchDenominatorReport(scope, passingEvidence());
  assert.equal(report.decision, "GO");
  assert.equal(report.identityLinkage.compatible, true);
  assert.deepEqual(report.identityLinkage.artifactHashes, {
    source: "a".repeat(64),
    server: "b".repeat(64),
    mobile: "c".repeat(64),
  });
});

test("nationwide progress does not change the routing launch scope hash", () => {
  const before = structuredClone(scope);
  const after = structuredClone(scope);
  before.nationwideRoadmapScope.missingCount = 270;
  after.nationwideRoadmapScope.missingCount = 0;
  assert.equal(
    canonicalScopeHash(before.routingLaunchScope),
    canonicalScopeHash(after.routingLaunchScope),
  );
});
