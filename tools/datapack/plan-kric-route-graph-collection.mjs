#!/usr/bin/env node
import { readFile } from "node:fs/promises";

const DEFAULT_CANDIDATE_IDS = ["kric-subway-route-info", "kric-station-info"];
const DEFAULT_CANDIDATES_PATH = "tools/datapack/source-candidates.json";

function buildKricRouteGraphCollectionPlan(candidatesDocument, candidateIds = DEFAULT_CANDIDATE_IDS) {
  const candidates = candidatesDocument.candidates ?? [];
  const requests = candidateIds.map((candidateId, index) => {
    const candidate = candidates.find((entry) => entry.id === candidateId);
    if (!candidate) {
      throw new Error(`unknown KRIC route graph candidate: ${candidateId}`);
    }
    return planRequest(candidate, index + 1);
  });
  return {
    artifactKind: "kric-route-graph-membership-collection-plan",
    serviceKeyEnv: "KRIC_SERVICE_KEY",
    sourcePurpose: "route_graph_station_membership",
    totalRequestCount: requests.length,
    requests,
    productionUseAllowed: false,
  };
}

function planRequest(candidate, priority) {
  requireCandidateState(candidate);
  const evidence = candidate.evidence ?? {};
  const validatedLiveSampleFormat = candidate.sampleEvidenceStatus === "validated_live_sample"
    ? requiredLiveSampleFormat(evidence.liveSampleFormat, candidate.id)
    : null;
  const plannedSampleFormat = validatedLiveSampleFormat ?? "json";
  const documentedSampleUrl = requiredText(evidence.sampleUrl, `${candidate.id}.evidence.sampleUrl`);
  assertRedactedServiceKey(documentedSampleUrl, candidate.id);
  const sampleUrl = forceFormat(documentedSampleUrl, plannedSampleFormat);
  if (!(evidence.formats ?? []).some((format) => String(format).toLowerCase() === plannedSampleFormat)) {
    throw new Error(`${candidate.id} must support ${plannedSampleFormat.toUpperCase()} sample collection`);
  }
  return {
    priority,
    candidateId: candidate.id,
    endpoint: requiredText(evidence.endpoint, `${candidate.id}.evidence.endpoint`),
    url: sampleUrl,
    expectedFields: [...(evidence.outputFields ?? [])].sort((left, right) => left.localeCompare(right)),
    evidenceOutput: `.codex/evidence/kric/${candidate.id}.sample.json`,
    rawArchiveOutput: `.codex/evidence/kric/${candidate.id}.raw.json`,
    sampleEvidenceStatus: candidate.sampleEvidenceStatus,
    plannedSampleFormat,
    validatedLiveSampleFormat,
    sampleAcquisitionRequired: candidate.sampleEvidenceStatus === "sample_url_documented_key_required",
    remainingAdmissionBlockers: [...(evidence.missingEvidence ?? [])],
    productionUseAllowed: false,
    automaticRouteGraphEdgeAllowed: false,
    capabilities: {
      schedule: false,
      realtime: false,
      facility: false,
    },
  };
}

function requiredLiveSampleFormat(value, candidateId) {
  const format = requiredText(value, `${candidateId}.evidence.liveSampleFormat`).toLowerCase();
  if (!["json", "xml"].includes(format)) {
    throw new Error(`${candidateId}.evidence.liveSampleFormat must be JSON or XML`);
  }
  return format;
}

function requireCandidateState(candidate) {
  if (!candidate.id.startsWith("kric-")) {
    throw new Error(`candidate is not KRIC: ${candidate.id}`);
  }
  if (candidate.admissionStatus !== "evidence_recorded_admin_review_required") {
    throw new Error(`${candidate.id} admissionStatus must require admin review before production use`);
  }
  if (!["sample_url_documented_key_required", "validated_live_sample"].includes(candidate.sampleEvidenceStatus)) {
    throw new Error(`${candidate.id} sampleEvidenceStatus must be pending or validated live sample evidence`);
  }
  if (candidate.automaticRouteGraphEdgeAllowed !== false) {
    throw new Error(`${candidate.id} automatic route graph edge must stay disabled`);
  }
  if (candidate.productionUseAllowed === true) {
    throw new Error(`${candidate.id} production use must stay disabled`);
  }
  for (const capability of ["schedule", "realtime", "facility"]) {
    if (candidate.capabilities?.[capability]?.productionUseAllowed !== false) {
      throw new Error(`${candidate.id} production capability must stay disabled: ${capability}`);
    }
  }
}

function forceFormat(sampleUrl, format) {
  const url = new URL(sampleUrl);
  for (const name of [...url.searchParams.keys()]) {
    if (["servicekey", "format"].includes(name.toLowerCase())) {
      url.searchParams.delete(name);
    }
  }
  url.searchParams.set("serviceKey", "[서비스키값]");
  url.searchParams.set("format", format);
  return url.toString().replace("serviceKey=%5B%EC%84%9C%EB%B9%84%EC%8A%A4%ED%82%A4%EA%B0%92%5D", "serviceKey=[서비스키값]");
}

function assertRedactedServiceKey(sampleUrl, candidateId) {
  const serviceKeys = [...new URL(sampleUrl).searchParams.entries()]
    .filter(([name]) => name.toLowerCase() === "servicekey")
    .map(([, value]) => value);
  if (serviceKeys.length !== 1 || serviceKeys[0] !== "[서비스키값]") {
    throw new Error(`${candidateId} sampleUrl must keep exactly one redacted serviceKey`);
  }
}

function requiredText(value, label) {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${label} is required`);
  }
  return value;
}

function cliOptions(argv) {
  const options = { candidates: DEFAULT_CANDIDATES_PATH, candidate: DEFAULT_CANDIDATE_IDS.join(",") };
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (!flag?.startsWith("--") || !value || value.startsWith("--")) {
      throw new Error(`${flag ?? "argument"} requires a value`);
    }
    options[flag.slice(2)] = value;
  }
  return options;
}

async function run(argv) {
  const options = cliOptions(argv);
  const candidates = JSON.parse(await readFile(options.candidates, "utf8"));
  const candidateIds = options.candidate.split(",").map((value) => value.trim()).filter(Boolean);
  return buildKricRouteGraphCollectionPlan(candidates, candidateIds);
}

run(process.argv.slice(2))
  .then((plan) => console.log(JSON.stringify(plan, null, 2)))
  .catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
