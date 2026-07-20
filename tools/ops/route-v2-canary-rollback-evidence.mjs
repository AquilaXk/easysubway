#!/usr/bin/env node
// Signed-RC synthetic canary + ingress-close rollback dry-run evidence helpers
// (issue #2095). This module owns the *pure* decision logic that the bash runner
// tools/ops/verify-production-route-v2-canary-rollback.sh delegates to:
//
//   - resolving the checked-in RC candidate identity (backend SHA, Mobile
//     versionName/versionCode, timetable snapshot identity) so canary and
//     rollback always target the SAME candidate,
//   - asserting a caller-provided candidate matches that identity (fail-closed),
//   - validating the explicit owner approval reference,
//   - scoring the synthetic canary against the limit/latency/error/cache-safety
//     budget, and
//   - assembling the canary/rollback timeline evidence with per-stage timestamps.
//
// Nothing here opens ingress, mutates production, or performs network I/O — the
// bash runner is the only place that touches the live edge, and only after this
// module's gates pass. Keeping the logic here makes every gate unit-testable
// without a production runner.
import { readFile } from "node:fs/promises";

export const CANARY_TIMELINE_STAGES = [
  "candidate_verified",
  "prior_approved_state_recorded",
  "canary_started",
  "canary_completed",
  "budget_evaluated",
  "rollback_dry_run_started",
  "ingress_closed",
  "ingress_restored",
  "rollback_verified",
  "evidence_emitted",
];

// The rollback dry-run ALWAYS physically closes the host Route V2 ingress — on a
// clean canary this is a real close/verify/restore rehearsal (not a no-op), and on
// a budget breach it is the permanent rollback. Only the restore step is
// conditional: a clean canary restores ingress to the state it started in
// (ingress_restored), while a breach leaves it closed (the prior approved posture)
// and never restores.
export const OPTIONAL_TIMELINE_STAGES = new Set(["ingress_restored"]);

const APPROVAL_REFERENCE_PATTERN =
  /^https:\/\/github\.com\/AquilaXk\/easysubway\/(?:issues|pull|actions\/runs)\/[0-9]+(?:#[A-Za-z0-9_-]+)?$/;

export function validateApprovalReference(reference) {
  if (typeof reference !== "string" || !APPROVAL_REFERENCE_PATTERN.test(reference)) {
    throw new Error(
      "production canary requires an explicit owner approval reference (AquilaXk/easysubway issue, pull, or actions/runs URL)",
    );
  }
  return reference;
}

function requireString(value, label) {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${label} is missing or empty`);
  }
  return value;
}

// --- Signed-RC canary integrity token pool (input contract for #1016) ---
//
// A real production backend container always runs the `prod` Spring profile,
// which wires GooglePlayIntegrityDecoder — NOT the synthetic
// CapacityEvidencePlayIntegrityDecoder the isolated capacity-evidence clone uses.
// This runner therefore MUST NOT locally synthesize an attestation (e.g. an
// HMAC-signed nonce): production's real decoder would reject it and every
// session request would fail, always reading as a budget breach. Adding a
// synthetic decoder to the `prod` profile to make this canary pass is explicitly
// OUT OF SCOPE and rejected on security grounds — it would be a permanent
// authentication bypass shipped in the production artifact.
//
// The runner's input contract is: #1016's provisioning pipeline mints a POOL of
// already-minted, currently-valid, single-use signed-RC Play Integrity
// token/nonce pairs IMMEDIATELY BEFORE each approved workflow run, and delivers
// them ONCE to that run via a host-local file
// (${DEPLOY_ROOT}/shared/route-v2-canary-integrity-tokens.json) that the runner
// moves into its own work directory and deletes from that shared location —
// NEVER via the deployed compose.env, which is a durable, deploy-time artifact:
// RouteV2SessionService rejects a Play Integrity verdict whose request
// timestamp is more than 2 minutes old and rejects a replayed nonce, so a pool
// sitting in compose.env since the last deploy (which could be hours or days
// old, and could be reused across multiple runs) would always fail decode on a
// perfectly healthy candidate. The payload also carries the Mobile candidate
// identity that #1016 actually built and signed to mint these tokens — binding
// the attestation to a REAL provisioning event instead of trusting whatever
// pubspec.yaml happens to say in the reviewed-main checkout, which could
// disagree with a different Play-recognized build using the same package and
// certificate:
//
//   {
//     "mintedAt": "<ISO-8601 instant, must be within CANARY_POOL_MAX_AGE_MS of use>",
//     "mobileVersionName": "<Mobile candidate versionName #1016 signed>",
//     "mobileVersionCode": <Mobile candidate versionCode #1016 signed>,
//     "pairs": [{ "integrityToken": "<opaque Play Integrity token>", "clientNonce": "<nonce>" }, ...]
//   }
//
// If this payload is absent, stale, malformed, or short of the pairs a run
// needs, the runner fails closed with "blocked on #1016" before sending a
// single request — exactly like the (now-superseded) compose.env-key gate it
// replaces.
//
// The age bound is STRICTLY LESS than RouteV2SessionService's 2-minute Play
// Integrity verdict acceptance window, not equal to or looser than it: a pool
// that passes this gate still has to survive Gate 4's live Postgres query and
// candidate assertion, then the canary loop's own multiple sequential
// requests, before its LAST pair is actually sent. A 5-minute (or even a
// 2-minute) bound would let a 2-5 minute old pool through the gate only to be
// rejected by the backend on every request — misread as a genuine budget
// breach and closing a perfectly healthy candidate's ingress. 60 seconds
// leaves a full minute of margin for that gate-to-last-request latency plus
// clock skew between the host that minted the pool and this runner.
const CANARY_POOL_MAX_AGE_MS = 60 * 1000;
const CLIENT_NONCE_PATTERN = /^[A-Za-z0-9_-]{22}$/;

export function parseCanaryIntegrityTokens(rawJson, requiredCount, options = {}) {
  if (!Number.isInteger(requiredCount) || requiredCount <= 0) {
    throw new Error("requiredCount must be a positive integer");
  }
  const now = options.now ?? Date.now();
  let parsed;
  try {
    parsed = JSON.parse(rawJson);
  } catch {
    throw new Error("signed-RC canary integrity token payload is not valid JSON");
  }

  const mintedAtMs = Date.parse(parsed?.mintedAt);
  if (!Number.isFinite(mintedAtMs)) {
    throw new Error("signed-RC canary integrity token payload is missing a valid mintedAt timestamp");
  }
  const ageMs = now - mintedAtMs;
  if (ageMs < 0 || ageMs > CANARY_POOL_MAX_AGE_MS) {
    throw new Error(
      `signed-RC canary integrity token payload must be minted within ${CANARY_POOL_MAX_AGE_MS / 1000} second(s) of use`,
    );
  }

  const mobileVersionName = requireString(parsed?.mobileVersionName, "token payload mobileVersionName");
  const mobileVersionCode = parsed?.mobileVersionCode;
  if (!Number.isInteger(mobileVersionCode) || mobileVersionCode <= 0) {
    throw new Error("token payload mobileVersionCode is invalid");
  }

  const pairs = parsed?.pairs;
  if (!Array.isArray(pairs) || pairs.length < requiredCount) {
    throw new Error(
      `signed-RC canary integrity token payload must supply at least ${requiredCount} pair(s)`,
    );
  }
  // clientNonce format and pool-wide uniqueness are validated against the SAME
  // rules the backend itself enforces (RouteV2SessionService requires exactly
  // 22 base64url characters decoding to 16 bytes, and rejects a replayed
  // nonce) — over the FULL pool, not just the pairs this run will consume, so
  // a provisioning bug is caught here instead of surfacing as a false budget
  // breach after live canary traffic against an otherwise-healthy candidate.
  const seenNonces = new Set();
  const validatedPairs = pairs.map((pair, index) => {
    const integrityToken = requireString(pair?.integrityToken, `integrity token pair[${index}].integrityToken`);
    const clientNonce = pair?.clientNonce;
    if (typeof clientNonce !== "string" || !CLIENT_NONCE_PATTERN.test(clientNonce)) {
      throw new Error(`integrity token pair[${index}].clientNonce must be a 22-character base64url value`);
    }
    let decodedLength;
    try {
      decodedLength = Buffer.from(clientNonce, "base64url").length;
    } catch {
      decodedLength = -1;
    }
    if (decodedLength !== 16) {
      throw new Error(`integrity token pair[${index}].clientNonce must decode to exactly 16 bytes`);
    }
    if (seenNonces.has(clientNonce)) {
      throw new Error(`integrity token pair[${index}].clientNonce is duplicated within the pool`);
    }
    seenNonces.add(clientNonce);
    return { integrityToken, clientNonce };
  });

  return {
    mintedAt: parsed.mintedAt,
    mobileVersionName,
    mobileVersionCode,
    pairs: validatedPairs.slice(0, requiredCount),
  };
}

// Resolve the single RC candidate identity from the checked-in release evidence
// and timetable snapshot evidence. Reading these at runtime (rather than pinning
// constants) keeps the canary tied to whatever candidate the RC bump last recorded.
export function resolveExpectedCandidate(operationsEvidence, timetableEvidence) {
  const readiness =
    operationsEvidence?.backendControlPlane?.publicApiSurface?.routeV2Readiness;
  const candidate = readiness?.realisticLoadEvidence?.candidate;
  if (!candidate) {
    throw new Error("operations release evidence is missing the RC candidate identity");
  }
  const versionCode = candidate.versionCode;
  if (!Number.isInteger(versionCode) || versionCode <= 0) {
    throw new Error("RC candidate versionCode is invalid");
  }

  const timetableSnapshotId = requireString(timetableEvidence?.snapshotId, "timetable snapshotId");
  const timetableSnapshotSha256 = requireString(
    timetableEvidence?.snapshotSha256,
    "timetable snapshotSha256",
  );
  const timetableFreshUntil = requireString(timetableEvidence?.freshUntil, "timetable freshUntil");

  // The timetable evidence FILE this helper was handed must be the SAME
  // snapshot operations-release-evidence.json's own timetableSnapshotCache
  // record declares as current — otherwise this helper could silently mix two
  // different release evidences into one candidate identity (e.g. certify a
  // production timetable the RC manifest never actually approved, or reject a
  // production timetable that matches the manifest just because a stale file
  // was passed in). Note: this only rejects a MISMATCH between the two
  // evidences; it does not correct either one — reconciling which value is
  // authoritative is a separate, follow-up binding change.
  const boundSnapshot = readiness?.timetableSnapshotCache?.currentImplementation;
  const boundFreshUntilMs = Date.parse(boundSnapshot?.freshUntil);
  const timetableFreshUntilMs = Date.parse(timetableFreshUntil);
  const timetableEvidenceMatchesBoundSnapshot =
    boundSnapshot?.snapshotSha256 === timetableSnapshotSha256 &&
    Number.isFinite(boundFreshUntilMs) &&
    Number.isFinite(timetableFreshUntilMs) &&
    boundFreshUntilMs === timetableFreshUntilMs;
  if (!timetableEvidenceMatchesBoundSnapshot) {
    throw new Error(
      "operations-release-evidence.json timetableSnapshotCache does not match the timetable evidence file; refusing to resolve a candidate from mismatched release evidence",
    );
  }

  return {
    backendDeploySha: requireString(candidate.candidateGitSha, "candidate backend SHA"),
    mobileVersionName: requireString(candidate.versionName, "candidate versionName"),
    mobileVersionCode: versionCode,
    timetableSnapshotId,
    timetableSnapshotSha256,
    timetableFreshUntil,
  };
}

// Fail-closed identity match: the canary/rollback candidate the caller supplies
// (from the deployed runner state + workflow inputs) must equal the checked-in RC
// candidate on every field, or the run is rejected before any traffic is sent.
export function assertCandidateMatch(provided, expected) {
  const strictFields = [
    "backendDeploySha",
    "mobileVersionName",
    "mobileVersionCode",
    "timetableSnapshotId",
    "timetableSnapshotSha256",
  ];
  const mismatches = strictFields.filter((field) => provided?.[field] !== expected?.[field]);

  // timetableFreshUntil represents a single INSTANT, not a display string: the
  // live production DB query renders it in UTC ("...Z"), while the checked-in RC
  // evidence keeps its original zone offset (e.g. "+09:00"). A byte-for-byte
  // string compare would reject the SAME instant on every run, so this field is
  // compared as parsed epoch milliseconds instead of literal text.
  const providedFreshUntilMs = Date.parse(provided?.timetableFreshUntil);
  const expectedFreshUntilMs = Date.parse(expected?.timetableFreshUntil);
  const freshUntilMatches =
    Number.isFinite(providedFreshUntilMs) &&
    Number.isFinite(expectedFreshUntilMs) &&
    providedFreshUntilMs === expectedFreshUntilMs;
  if (!freshUntilMatches) {
    mismatches.push("timetableFreshUntil");
  }

  if (mismatches.length > 0) {
    throw new Error(
      `canary and rollback must use the same candidate identity; mismatched fields: ${mismatches.join(", ")}`,
    );
  }
  return true;
}

function normalizeSample(sample, index) {
  const profile = requireString(sample?.profile, `sample[${index}] profile`);
  const status = sample?.status;
  // 0 is the bash runner's transport-failure sentinel (curl's own "000" for a
  // DNS/TLS/connect/timeout that never reached the server) — accepted here so a
  // network blip becomes a scored breach sample instead of an unhandled
  // exception that would abort budget evaluation entirely.
  if (!Number.isInteger(status) || status < 0 || (status > 0 && status < 100) || status > 599) {
    throw new Error(`sample[${index}] status is invalid`);
  }
  const latencyMs = sample?.latencyMs;
  if (!Number.isFinite(latencyMs) || latencyMs < 0) {
    throw new Error(`sample[${index}] latencyMs is invalid`);
  }
  const cacheControl = typeof sample?.cacheControl === "string" ? sample.cacheControl : "";
  // Only route-search samples carry this field; every other sample defaults to
  // "matched" (not applicable) so it never contributes a false breach.
  const plannerIdentityMatch = sample?.plannerIdentityMatch !== false;
  return { profile, status, latencyMs, cacheControl, plannerIdentityMatch };
}

function percentile(sortedLatencies, ratio) {
  if (sortedLatencies.length === 0) return 0;
  const rank = Math.max(0, Math.ceil(sortedLatencies.length * ratio) - 1);
  return sortedLatencies[rank];
}

// Score the synthetic canary against the pre-launch budget. A breach in ANY
// dimension (a normal-profile request that did not succeed, latency, error,
// missing rate-limit engagement, or a cache-safety violation) flags the run so the
// caller executes the ingress-close rollback. Requiring every "normal" sample to be
// an exact HTTP 200 (burst's 429 is scored separately via limitEngaged) closes a
// vacuous-pass gap: without it, a canary whose normal requests are ALL rejected
// (e.g. every attestation is denied) could still read as "within budget" as long as
// one burst request got rate-limited.
export function evaluateCanaryBudgets(samples, budgets) {
  if (!Array.isArray(samples) || samples.length === 0) {
    throw new Error("canary produced no samples");
  }
  const normalized = samples.map((sample, index) => normalizeSample(sample, index));
  const p95MaxMs = budgets?.p95MaxMs;
  const p99MaxMs = budgets?.p99MaxMs;
  const maxUnexpectedErrors = budgets?.maxUnexpectedErrors ?? 0;
  const requireNoStore = budgets?.requireNoStore !== false;
  const requireLimitEngaged = budgets?.requireLimitEngaged !== false;
  if (!Number.isInteger(p95MaxMs) || !Number.isInteger(p99MaxMs) || p95MaxMs <= 0 || p99MaxMs <= 0) {
    throw new Error("canary latency budget is invalid");
  }

  const normalSamples = normalized.filter((sample) => sample.profile === "normal");
  if (normalSamples.length === 0) {
    throw new Error("canary requires at least one normal-profile sample");
  }
  const failedNormalSamples = normalSamples.filter((sample) => sample.status !== 200).length;

  const latencies = normalized.map((sample) => sample.latencyMs).sort((a, b) => a - b);
  const p95 = percentile(latencies, 0.95);
  const p99 = percentile(latencies, 0.99);
  const unexpectedErrors = normalized.filter(
    (sample) => sample.status >= 500 && sample.status !== 503,
  ).length;
  const limitEngaged = normalized.some((sample) => sample.status === 429);
  const cacheSafetyViolations = requireNoStore
    ? normalized.filter(
        (sample) => !/^private,\s*no-store$/i.test(sample.cacheControl.trim()),
      ).length
    : 0;
  // A 200 response with the WRONG timetable identity is a distinct failure mode
  // from a bad status code (e.g. a route search hitting a stale/drifted active
  // snapshot behind an otherwise-healthy session endpoint) — scored separately so
  // it cannot be masked by an unrelated status-code-only budget check.
  const plannerIdentityMismatches = normalized.filter(
    (sample) => sample.plannerIdentityMatch === false,
  ).length;
  // A burst-profile sample may only legitimately be 200 (accepted before the
  // limiter engaged) or 429 (rejected by the limiter) — anything else (403 from
  // a rejected attestation, another 4xx, a 5xx, or the "0" transport-failure
  // sentinel) is a breach on its own. Without this, repeated invalid-attestation
  // responses in the burst batch could pass unnoticed as long as ONE burst
  // request happened to also return 429 and every normal sample was fine.
  const invalidBurstSamples = normalized.filter(
    (sample) => sample.profile === "burst" && sample.status !== 200 && sample.status !== 429,
  ).length;

  const breaches = [];
  if (failedNormalSamples > 0) {
    breaches.push(`${failedNormalSamples} normal-profile sample(s) did not return exact HTTP 200`);
  }
  if (invalidBurstSamples > 0) {
    breaches.push(`${invalidBurstSamples} burst-profile sample(s) returned neither 200 nor 429`);
  }
  if (p95 > p95MaxMs) breaches.push(`p95 latency ${p95}ms exceeds ${p95MaxMs}ms`);
  if (p99 > p99MaxMs) breaches.push(`p99 latency ${p99}ms exceeds ${p99MaxMs}ms`);
  if (unexpectedErrors > maxUnexpectedErrors) {
    breaches.push(`unexpected error count ${unexpectedErrors} exceeds ${maxUnexpectedErrors}`);
  }
  if (requireLimitEngaged && !limitEngaged) {
    breaches.push("rate limiter never engaged (no 429 observed)");
  }
  if (cacheSafetyViolations > 0) {
    breaches.push(`${cacheSafetyViolations} response(s) missing Cache-Control: private, no-store`);
  }
  if (plannerIdentityMismatches > 0) {
    breaches.push(`${plannerIdentityMismatches} response(s) had a route search planner identity mismatch`);
  }

  return {
    withinBudget: breaches.length === 0,
    breaches,
    summary: {
      sampleCount: normalized.length,
      normalSampleCount: normalSamples.length,
      failedNormalSampleCount: failedNormalSamples,
      invalidBurstSampleCount: invalidBurstSamples,
      p95LatencyMs: p95,
      p99LatencyMs: p99,
      unexpectedErrorCount: unexpectedErrors,
      limitEngaged,
      cacheSafetyViolationCount: cacheSafetyViolations,
      plannerIdentityMismatchCount: plannerIdentityMismatches,
    },
  };
}

function assertMonotonic(timeline) {
  let previous = -Infinity;
  for (const entry of timeline) {
    const at = Date.parse(entry.at);
    if (!Number.isFinite(at)) {
      throw new Error(`timeline stage ${entry.stage} has an invalid timestamp`);
    }
    if (at < previous) {
      throw new Error(`timeline stage ${entry.stage} is out of chronological order`);
    }
    previous = at;
  }
}

// Assemble the canary/rollback dry-run evidence. `stages` maps each timeline stage
// name to an ISO-8601 timestamp. `ingress_closed` is ALWAYS required — the
// rollback dry-run always physically closes the host Route V2 ingress, whether the
// canary was healthy (rehearsal) or breached its budget (permanent rollback).
// `ingress_restored` is present only on the healthy/rehearsal path, where ingress
// is reopened after the close is verified; a budget breach never restores it.
export function buildCanaryRollbackEvidence({
  candidate,
  publicBaseUrl,
  approvalReference,
  ingressWasOpen,
  budget,
  budgetResult,
  restoredAfterRehearsal,
  priorApprovedState,
  stages,
}) {
  validateApprovalReference(approvalReference);
  if (!candidate) throw new Error("evidence requires the resolved candidate identity");
  if (!budgetResult) throw new Error("evidence requires the budget evaluation result");
  requireString(publicBaseUrl, "publicBaseUrl");
  if (!priorApprovedState) throw new Error("evidence requires the prior approved state");

  const restored = restoredAfterRehearsal === true;
  if (budgetResult.withinBudget !== restored) {
    throw new Error(
      "a healthy canary must restore ingress after the rehearsal, and a budget breach must not restore it",
    );
  }

  const timeline = [];
  for (const stage of CANARY_TIMELINE_STAGES) {
    const at = stages?.[stage];
    if (at === undefined) {
      if (OPTIONAL_TIMELINE_STAGES.has(stage)) continue;
      throw new Error(`timeline is missing required stage: ${stage}`);
    }
    timeline.push({ stage, at });
  }
  // ingress_closed is a REQUIRED stage (not in OPTIONAL_TIMELINE_STAGES), so the
  // loop above already rejects a missing timestamp with "timeline is missing
  // required stage: ingress_closed". Only ingress_restored's presence needs to be
  // tied to `restored` here, since it is the one truly conditional stage.
  if (restored && stages?.ingress_restored === undefined) {
    throw new Error("rehearsal restored ingress but the ingress_restored stage timestamp is missing");
  }
  if (!restored && stages?.ingress_restored !== undefined) {
    throw new Error("ingress_restored recorded but the rehearsal did not restore ingress");
  }
  assertMonotonic(timeline);

  return {
    schemaVersion: 1,
    gate: "route-v2-canary-rollback-dry-run",
    issue: 2095,
    generatedAt: new Date().toISOString(),
    approvalReference,
    publicBaseUrl,
    sameCandidateIdentity: candidate,
    priorApprovedState,
    canary: {
      ingressWasOpen: ingressWasOpen === true,
      budget,
      withinBudget: budgetResult.withinBudget,
      breaches: budgetResult.breaches,
      summary: budgetResult.summary,
    },
    rollbackDryRun: {
      trigger: budgetResult.withinBudget ? "rehearsal" : "budget-breach",
      ingressClosed: true,
      restoredAfterRehearsal: restored,
    },
    timeline,
  };
}

async function readJson(path) {
  return JSON.parse(await readFile(path, "utf8"));
}

// Reads the raw token pool from STDIN rather than an argv string — the CLI's
// own argv is visible to any same-UID process on the self-hosted runner host
// via /proc/<pid>/cmdline for the lifetime of this short-lived process, which
// would otherwise expose not-yet-consumed signed-RC tokens.
async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString("utf8");
}

async function main(argv) {
  const [subcommand, ...rest] = argv;
  switch (subcommand) {
    case "validate-approval": {
      validateApprovalReference(rest[0]);
      return;
    }
    case "expected-candidate": {
      const [operationsPath, timetablePath] = rest;
      const [operations, timetable] = await Promise.all([
        readJson(operationsPath),
        readJson(timetablePath),
      ]);
      process.stdout.write(`${JSON.stringify(resolveExpectedCandidate(operations, timetable))}\n`);
      return;
    }
    case "assert-candidate": {
      const [expectedJson, providedJson] = rest;
      assertCandidateMatch(JSON.parse(providedJson), JSON.parse(expectedJson));
      return;
    }
    case "parse-integrity-tokens": {
      const [requiredCountArg] = rest;
      const rawJson = await readStdin();
      const tokens = parseCanaryIntegrityTokens(rawJson, Number(requiredCountArg));
      process.stdout.write(`${JSON.stringify(tokens)}\n`);
      return;
    }
    case "evaluate-budgets": {
      const [samplesPath, budgetsJson] = rest;
      const samples = await readJson(samplesPath);
      const result = evaluateCanaryBudgets(samples, JSON.parse(budgetsJson));
      process.stdout.write(`${JSON.stringify(result)}\n`);
      if (!result.withinBudget) process.exitCode = 1;
      return;
    }
    case "build-evidence": {
      const [inputPath] = rest;
      const input = await readJson(inputPath);
      process.stdout.write(`${JSON.stringify(buildCanaryRollbackEvidence(input), null, 2)}\n`);
      return;
    }
    default:
      throw new Error(`unknown subcommand: ${subcommand ?? "(none)"}`);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error.message);
    process.exitCode = 2;
  });
}
