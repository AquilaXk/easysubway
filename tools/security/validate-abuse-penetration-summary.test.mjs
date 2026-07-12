import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdir, rm, writeFile } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import test from "node:test";

const execFileAsync = promisify(execFile);
const root = path.resolve(import.meta.dirname, "../..");
const gate = JSON.parse(readFileSync(path.join(root, "apps/mobile/release/abuse-penetration-rehearsal-gate.json"), "utf8"));
const artifactIdentity = {
  gitSha: "abcdef1234567890",
  versionCode: 10001,
  androidApplicationId: "com.easysubway.app",
  dataPackManifestSha256: "a".repeat(64),
  aabSha256: "b".repeat(64),
  backendArtifactSha256: "c".repeat(64),
};

function caseValue(field, matrix, caseId) {
  if (field === "expectedStatus" || field === "observedStatus") return matrix.expectedStatusByCase[caseId][0];
  return {
    apiStep: "submit",
    artifactType: "android-aab",
    auditRedactionResult: "PASS",
    bucketOrPolicyAlias: "report-photo-release",
    cleanupResult: "PASS",
    commandOrManualCheck: "redacted local rehearsal",
    contentType: "image/jpeg",
    deleteOrCleanupResult: "PASS",
    endpoint: "/api/v1/reports",
    localEvidencePath: ".codex/evidence/security/abuse-penetration-rehearsal/rc/redacted-summary.json",
    method: "PUT",
    nodeOrStoreMode: "multi-node",
    redactionResult: "PASS",
    retentionRule: "30d",
    role: "REPORT_REVIEWER",
    scanTarget: "release artifact",
    sizeBytes: 1024,
    tenantScope: "operator-global",
    ttlSeconds: 60,
  }[field] ?? "PASS";
}

function validSummary() {
  return {
    schemaVersion: 1,
    releaseGate: gate.releaseGate,
    issue: gate.issue,
    status: "PASS",
    artifactIdentity: { ...artifactIdentity },
    productionLikeEvidence: gate.productionLikeEvidencePolicy.requiredForClosing.map((evidenceId) => ({
      evidenceId,
      result: "PASS",
      localEvidencePath: ".codex/evidence/security/abuse-penetration-rehearsal/rc/redacted-summary.json",
    })),
    matrices: Object.entries(gate.rehearsalMatrices).map(([matrixId, matrix]) => ({
      matrixId,
      scenarioId: matrix.scenarioId,
      artifactIdentity: { ...artifactIdentity },
      commandOrManualCheck: "redacted local rehearsal",
      findingCounts: { critical: 0, high: 0, medium: 0, low: 0 },
      result: "PASS",
      redactionNotes: "sensitive values removed",
      localEvidencePath: ".codex/evidence/security/abuse-penetration-rehearsal/rc/redacted-summary.json",
      requiredEvidence: matrix.requiredEvidence,
      cases: matrix.requiredCases.map((caseId) => {
        const item = { caseId };
        for (const field of matrix.summaryFields) item[field] = field === "caseId" ? caseId : caseValue(field, matrix, caseId);
        return item;
      }),
    })),
  };
}

async function withSummary(summary, fn) {
  const dir = path.join(tmpdir(), `abuse-summary-${Date.now()}-${Math.random().toString(16).slice(2)}`);
  await rm(dir, { recursive: true, force: true });
  await mkdir(dir, { recursive: true });
  const summaryPath = path.join(dir, "summary.json");
  await writeFile(summaryPath, `${JSON.stringify(summary, null, 2)}\n`);
  return fn(summaryPath);
}

function validateSummary(summary) {
  return withSummary(summary, (summaryPath) =>
    execFileAsync(process.execPath, [
      "tools/security/validate-abuse-penetration-summary.mjs",
      "--summary",
      summaryPath,
      "--require-pass",
    ], { cwd: root }),
  );
}

async function assertSensitiveValueRejected(value) {
  const summary = validSummary();
  summary.matrices[0].redactionNotes = value;
  await assert.rejects(
    validateSummary(summary),
    /raw sensitive evidence material/,
  );
}

test("abuse penetration summary validator accepts a complete redacted matrix summary", async () => {
  await withSummary(validSummary(), (summaryPath) =>
    execFileAsync(process.execPath, [
      "tools/security/validate-abuse-penetration-summary.mjs",
      "--summary",
      summaryPath,
      "--require-pass",
    ], { cwd: root }),
  );
});

test("abuse penetration summary validator rejects pass without production-like closure evidence", async () => {
  const missingProductionEvidence = validSummary();
  missingProductionEvidence.productionLikeEvidence.pop();
  await assert.rejects(
    withSummary(missingProductionEvidence, (summaryPath) =>
      execFileAsync(process.execPath, [
        "tools/security/validate-abuse-penetration-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root }),
    ),
    /productionLikeEvidence missing/,
  );
});

test("abuse penetration summary validator rejects forbidden closure evidence markers", async () => {
  const forbiddenClosureEvidence = validSummary();
  forbiddenClosureEvidence.productionLikeEvidence[0].localEvidencePath = "preflight env check only";
  await assert.rejects(
    withSummary(forbiddenClosureEvidence, (summaryPath) =>
      execFileAsync(process.execPath, [
        "tools/security/validate-abuse-penetration-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root }),
    ),
    /forbidden sensitive evidence marker/,
  );
});

test("abuse penetration summary validator rejects a runtime-constructed IPv4 CIDR value", async () => {
  const syntheticReservedCidr = [
    ["19", "2"],
    ["0"],
    ["2"],
    ["4", "2"],
  ].map((parts) => parts.join("")).join(".") + `/${["2", "4"].join("")}`;
  await assertSensitiveValueRejected(syntheticReservedCidr);
});

test("abuse penetration summary validator rejects a runtime-constructed raw User-Agent value", async () => {
  const syntheticRawUserAgent = [
    ["Moz", "illa"].join(""),
    "/",
    ["5", "0"].join("."),
    " (",
    ["syn", "thetic"].join(""),
    ")",
  ].join("");
  await assertSensitiveValueRejected(syntheticRawUserAgent);
});

test("abuse penetration summary validator rejects runtime-constructed compressed IPv6 CIDR", async () => {
  const syntheticIpv6 = [["20", "01"], ":", ["db", "8"], "::", ["4", "2"]].flat().join("");
  await assertSensitiveValueRejected([syntheticIpv6, "/", ["6", "4"].join("")].join(""));
});

test("abuse penetration summary validator rejects a runtime-constructed bracketed IPv6 URL", async () => {
  const syntheticIpv6 = [["20", "01"], ":", ["db", "8"], "::", ["4", "2"]].flat().join("");
  await assertSensitiveValueRejected(["https://[", syntheticIpv6, "]/evidence"].join(""));
});

test("abuse penetration summary validator rejects runtime-constructed alternate numeric IPv4 hosts", async () => {
  for (const value of [
    ["https://", ["0x", "c0", "00", "02", "2a"].join(""), "/evidence"].join(""),
    ["322", "122", "602", "6"].join(""),
    ["1", "27"].join(""),
  ]) {
    await assertSensitiveValueRejected(value);
  }
});

test("abuse penetration summary validator rejects product-independent raw User-Agent values", async () => {
  for (const value of [
    [["Da", "rt"].join(""), "/", ["3", "8"].join("."), " (", ["dart", ":io"].join(""), ")"].join(""),
    [["cu", "rl"].join(""), "/", ["8", "1"].join(".")].join(""),
    [["ok", "http"].join(""), "/", ["4", "12"].join(".")].join(""),
  ]) {
    await assertSensitiveValueRejected(value);
  }
});

test("abuse penetration summary validator rejects a CamelCase UserAgent identifier", async () => {
  await assertSensitiveValueRejected(["client", "User", "Agent"].join(""));
});

test("abuse penetration summary validator rejects unknown keys including numeric values", async () => {
  const mutations = [
    (summary) => { summary.unexpectedCount = 1; },
    (summary) => { summary.artifactIdentity.unexpectedCount = 1; },
    (summary) => { summary.productionLikeEvidence[0].unexpectedCount = 1; },
    (summary) => { summary.matrices[0].unexpectedCount = 1; },
    (summary) => { summary.matrices[0].findingCounts.unexpectedCount = 1; },
    (summary) => {
      summary.matrices[0].mediumFindingDisposition = {
        owner: "security-owner",
        fixPlan: "tracked follow-up",
        unexpectedCount: 1,
      };
    },
    (summary) => { summary.matrices[0].cases[0].unexpectedCount = 1; },
  ];
  for (const mutate of mutations) {
    const summary = validSummary();
    mutate(summary);
    await assert.rejects(validateSummary(summary), /unsupported field/);
  }
});

test("abuse penetration summary validator rejects extra and duplicate evidence, matrix, and case IDs", async () => {
  const extraEvidence = validSummary();
  extraEvidence.productionLikeEvidence.push({
    evidenceId: "unexpected-evidence",
    result: "PASS",
    localEvidencePath: ".codex/evidence/security/abuse-penetration-rehearsal/rc/redacted-summary.json",
  });
  await assert.rejects(validateSummary(extraEvidence), /unexpected evidenceId/);

  const duplicateEvidence = validSummary();
  duplicateEvidence.productionLikeEvidence.push(structuredClone(duplicateEvidence.productionLikeEvidence[0]));
  await assert.rejects(validateSummary(duplicateEvidence), /duplicate evidenceId/);

  const extraMatrix = validSummary();
  extraMatrix.matrices.push({ ...structuredClone(extraMatrix.matrices[0]), matrixId: "unexpectedMatrix" });
  await assert.rejects(validateSummary(extraMatrix), /unexpected matrixId/);

  const duplicateMatrix = validSummary();
  duplicateMatrix.matrices.push(structuredClone(duplicateMatrix.matrices[0]));
  await assert.rejects(validateSummary(duplicateMatrix), /duplicate matrixId/);

  const extraCase = validSummary();
  extraCase.matrices[0].cases.push({ ...structuredClone(extraCase.matrices[0].cases[0]), caseId: "unexpected_case" });
  await assert.rejects(validateSummary(extraCase), /unexpected caseId/);

  const duplicateCase = validSummary();
  duplicateCase.matrices[0].cases.push(structuredClone(duplicateCase.matrices[0].cases[0]));
  await assert.rejects(validateSummary(duplicateCase), /duplicate caseId/);
});

test("abuse penetration summary validator accepts safe endpoint, evidence, prose, command, and version controls", async () => {
  const dottedVersion = ["release version ", ["1", "2", "3", "4"].join(".")].join("");
  for (const value of [
    "easysubway-api.aquilaxk.site",
    "/api/v1/reports",
    "image/jpeg",
    ".codex/evidence/security/abuse-penetration-rehearsal/rc/redacted-summary.json",
    "sensitive values removed",
    "curl --fail",
    dottedVersion,
    ["not", "::", "an", "::", "address"].join(""),
  ]) {
    const summary = validSummary();
    summary.matrices[0].redactionNotes = value;
    await validateSummary(summary);
  }
});

test("abuse penetration summary validator rejects missing cases, raw sensitive markers, and high findings", async () => {
  const missingCase = validSummary();
  missingCase.matrices[0].cases.pop();
  await assert.rejects(
    withSummary(missingCase, (summaryPath) =>
      execFileAsync(process.execPath, ["tools/security/validate-abuse-penetration-summary.mjs", "--summary", summaryPath], {
        cwd: root,
      }),
    ),
    /cases\./,
  );

  const leaked = validSummary();
  leaked.matrices[0].redactionNotes = "raw signed URL leaked";
  await assert.rejects(
    withSummary(leaked, (summaryPath) =>
      execFileAsync(process.execPath, ["tools/security/validate-abuse-penetration-summary.mjs", "--summary", summaryPath], {
        cwd: root,
      }),
    ),
    /forbidden sensitive evidence marker/,
  );

  const highFinding = validSummary();
  highFinding.matrices[0].findingCounts.high = 1;
  await assert.rejects(
    withSummary(highFinding, (summaryPath) =>
      execFileAsync(process.execPath, [
        "tools/security/validate-abuse-penetration-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root }),
    ),
    /critical\/high findings/,
  );

  const stringCount = validSummary();
  stringCount.matrices[0].findingCounts.critical = "0";
  await assert.rejects(
    withSummary(stringCount, (summaryPath) =>
      execFileAsync(process.execPath, ["tools/security/validate-abuse-penetration-summary.mjs", "--summary", summaryPath], {
        cwd: root,
      }),
    ),
    /non-negative integers/,
  );

  const mixedIdentity = validSummary();
  mixedIdentity.matrices[0].artifactIdentity.versionCode = 10002;
  await assert.rejects(
    withSummary(mixedIdentity, (summaryPath) =>
      execFileAsync(process.execPath, ["tools/security/validate-abuse-penetration-summary.mjs", "--summary", summaryPath], {
        cwd: root,
      }),
    ),
    /artifactIdentity must match/,
  );
});

test("abuse penetration summary validator rejects case-level failed rehearsal evidence", async () => {
  const statusMismatch = validSummary();
  statusMismatch.matrices[0].cases[0].observedStatus = 200;
  await assert.rejects(
    withSummary(statusMismatch, (summaryPath) =>
      execFileAsync(process.execPath, [
        "tools/security/validate-abuse-penetration-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root }),
    ),
    /observedStatus must match expectedStatus/,
  );

  const redactionFailure = validSummary();
  redactionFailure.matrices[0].cases[0].redactionResult = "FAIL";
  await assert.rejects(
    withSummary(redactionFailure, (summaryPath) =>
      execFileAsync(process.execPath, [
        "tools/security/validate-abuse-penetration-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root }),
    ),
    /redactionResult must be PASS/,
  );

  const untrustedStatusPair = validSummary();
  untrustedStatusPair.matrices[0].cases[0].expectedStatus = 500;
  untrustedStatusPair.matrices[0].cases[0].observedStatus = 500;
  await assert.rejects(
    withSummary(untrustedStatusPair, (summaryPath) =>
      execFileAsync(process.execPath, [
        "tools/security/validate-abuse-penetration-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root }),
    ),
    /expectedStatus must match release gate/,
  );
});

test("ad counter rehearsal은 edge 429와 direct-origin denial을 정확히 요구한다", async () => {
  const wrongEdgeStatus = validSummary();
  const adMatrix = wrongEdgeStatus.matrices.find((matrix) => matrix.matrixId === "adCounterInflation");
  const edgeCase = adMatrix.cases.find((item) => item.caseId === "edge_ip_rate_limit");
  edgeCase.expectedStatus = 204;
  edgeCase.observedStatus = 204;
  await assert.rejects(
    withSummary(wrongEdgeStatus, (summaryPath) =>
      execFileAsync(process.execPath, [
        "tools/security/validate-abuse-penetration-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root }),
    ),
    /expectedStatus must match release gate/,
  );

  for (const caseId of [
    "direct_origin_bypass",
    "wrong_host_origin_rejected",
    "wrong_sni_origin_rejected",
    "missing_or_untrusted_client_auth_rejected",
    "cloudflare_ipv4_live_oci_set_equality",
  ]) {
    const missingCase = validSummary();
    const originMatrix = missingCase.matrices.find((matrix) => matrix.matrixId === "adCounterInflation");
    originMatrix.cases = originMatrix.cases.filter((item) => item.caseId !== caseId);
    await assert.rejects(
      withSummary(missingCase, (summaryPath) =>
        execFileAsync(process.execPath, [
          "tools/security/validate-abuse-penetration-summary.mjs",
          "--summary",
          summaryPath,
          "--require-pass",
        ], { cwd: root }),
      ),
      new RegExp(`cases\\.${caseId}`),
    );
  }
});
