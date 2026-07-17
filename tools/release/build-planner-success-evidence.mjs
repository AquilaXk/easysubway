#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const API_CATALOG_ID = "internal:POST:/api/v2/routes/search:com.easysubway.route.adapter.in.web.RouteSearchController#searchRouteV2";
const SHA256 = /^[0-9a-f]{64}$/;

export function buildPlannerSuccessEvidence({ candidate, canary, generatedAt = new Date().toISOString() }) {
  const identity = candidate?.releaseCandidateIdentity;
  if (candidate?.phase !== "CANDIDATE" || candidate?.issue !== 2056 || !identity) {
    throw new Error("planner evidence requires the #2056 CANDIDATE context");
  }
  validateCanary(canary);
  const signedRcBound = SHA256.test(identity.aabSha256 ?? "")
    && SHA256.test(identity.aabPayloadSha256 ?? "")
    && (SHA256.test(identity.backendArtifactSha256 ?? "") || SHA256.test(identity.backendImageDigest ?? ""));
  const topologyBound = SHA256.test(identity.dataPackArtifactSha256 ?? "")
    && canary.plan.plannerIdentity.canonicalPackSha256 === identity.dataPackArtifactSha256;
  const canarySha256 = sha256(Buffer.from(JSON.stringify(canary)));
  return {
    schemaVersion: 1,
    artifactKind: "route-v2-planner-success-evidence",
    sourceIssue: 2098,
    consumerIssue: 2056,
    generatedAt,
    status: signedRcBound && topologyBound
      ? "SATISFIED"
      : signedRcBound ? "BLOCKED_CANDIDATE_TOPOLOGY_IDENTITY" : "BLOCKED_SIGNED_RC_IDENTITY",
    releaseCandidateIdentity: identity,
    apiContract: { catalogId: API_CATALOG_ID, contractVersion: "ROUTE_SEARCH_V2" },
    plannerIdentity: canary.plan.plannerIdentity,
    timetableArtifactId: canary.plan.timetableArtifactId,
    canaryResultSha256: canarySha256,
    canaryResult: canary,
    checks: {
      deterministicRepresentativeRanking: "SATISFIED",
      officialFare: "SATISFIED",
      exactPlannedTimes: "SATISFIED",
      typedRideMetadata: "SATISFIED",
      topologyTimetableLinkage: "SATISFIED",
      candidateTopologyIdentity: topologyBound ? "SATISFIED" : "BLOCKED",
      signedReleaseCandidate: signedRcBound ? "SATISFIED" : "BLOCKED",
    },
  };
}

function validateCanary(canary) {
  const plan = canary?.plan;
  const itineraries = plan?.itineraries;
  if (canary?.schemaVersion !== 1
    || canary.artifactKind !== "route-v2-planner-canary-result"
    || canary.sourceIssue !== 2098
    || canary.transportScope !== "SUBWAY_AND_ITX_CHEONGCHUN"
    || plan?.source !== "TIMETABLE_RAPTOR"
    || !plan.statuses?.includes("FOUND")
    || typeof plan.timetableArtifactId !== "string"
    || !Array.isArray(itineraries)
    || itineraries.length < 1
    || itineraries.length > 2) {
    throw new Error("planner canary result contract is invalid");
  }
  for (const value of Object.values(plan.plannerIdentity ?? {})) {
    if (typeof value !== "string" || value.length === 0) {
      throw new Error("planner topology/timetable identity is incomplete");
    }
  }
  const objectiveTags = new Set(itineraries.flatMap(({ objectiveTags }) => objectiveTags ?? []));
  if (!objectiveTags.has("FASTEST") || !objectiveTags.has("FEWEST_TRANSFERS")) {
    throw new Error("planner objective representatives are incomplete");
  }
  const rideClasses = new Set();
  for (const itinerary of itineraries) {
    const fare = itinerary.officialFare;
    if (!Number.isInteger(fare?.adultFareWon) || fare.adultFareWon <= 0
      || fare.currency !== "KRW"
      || fare.policy !== "SUM_OF_OFFICIAL_RIDE_OD_FARES"
      || !fare.sourceIds?.length
      || !fare.sourceSnapshotIds?.length) {
      throw new Error("planner official fare is incomplete");
    }
    for (const step of itinerary.steps ?? []) {
      if (!validTimestamp(step.plannedDepartureTime) || !validTimestamp(step.plannedArrivalTime)) {
        throw new Error("planner exact planned times are incomplete");
      }
      if (step.stepType !== "ride") continue;
      if (typeof step.tripId !== "string" || step.tripId.length === 0
        || !["SUBWAY", "ITX_CHEONGCHUN"].includes(step.serviceClass)
        || !["LOCAL", "EXPRESS"].includes(step.servicePattern)
        || (step.serviceClass === "ITX_CHEONGCHUN" && !step.trainNo)) {
        throw new Error("planner typed RIDE metadata is incomplete");
      }
      rideClasses.add(step.serviceClass);
    }
  }
  if (!rideClasses.has("SUBWAY") || !rideClasses.has("ITX_CHEONGCHUN")) {
    throw new Error("planner canary must cover SUBWAY and ITX_CHEONGCHUN");
  }
}

function validTimestamp(value) {
  return typeof value === "string" && Number.isFinite(Date.parse(value));
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function argument(name) {
  const index = process.argv.indexOf(`--${name}`);
  return index < 0 ? null : process.argv[index + 1];
}

const entry = process.argv[1] ? path.resolve(process.argv[1]) : null;
if (entry === fileURLToPath(import.meta.url)) {
  const candidatePath = argument("candidate-context");
  const canaryPath = argument("canary-result");
  const outputPath = argument("output");
  if (!candidatePath || !canaryPath || !outputPath) {
    throw new Error("--candidate-context, --canary-result and --output are required");
  }
  const evidence = buildPlannerSuccessEvidence({
    candidate: JSON.parse(readFileSync(candidatePath, "utf8")),
    canary: JSON.parse(readFileSync(canaryPath, "utf8")),
  });
  writeFileSync(outputPath, `${JSON.stringify(evidence, null, 2)}\n`);
}
