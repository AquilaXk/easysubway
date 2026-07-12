import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, rm, writeFile } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import test from "node:test";
import { buildAbusePenetrationSummaryV2Schema, deriveSummaryCatalog } from "./abuse-penetration-summary-schema.mjs";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";

const execFileAsync = promisify(execFile);
const root = path.resolve(import.meta.dirname, "../..");
const gate = JSON.parse(readFileSync(path.join(root, "apps/mobile/release/abuse-penetration-rehearsal-gate.json"), "utf8"));

const schemaV2EvidencePath = ".codex/evidence/security/abuse-penetration-rehearsal/run/redacted.json";
const schemaV2Identity = Object.freeze({
  gitSha: "a".repeat(40), versionCode: 10001, androidApplicationId: "com.easysubway.app",
  dataPackManifestSha256: "b".repeat(64), aabSha256: "c".repeat(64),
  generatedApkSha256: "d".repeat(64), backendImageDigest: `sha256:${"e".repeat(64)}`,
  backendArtifactSha256: "f".repeat(64),
});
function schemaV2Evidence(evidenceId) {
  return { evidenceId, result: "PASS", localEvidencePath: schemaV2EvidencePath };
}
function schemaV2Blocked(gateValue = gate, status = "BLOCKED_EXTERNAL") {
  return { schemaVersion: 2, releaseGate: gateValue.releaseGate, issue: gateValue.issue, status,
    rawInvocationStored: false, redactionPolicyId: "summary-v2-no-sensitive-values" };
}
function schemaV2Pass(gateValue = gate, withDisposition = true) {
  const evidenceIds = Array.from(new Set(Object.values(gateValue.rehearsalMatrices)
    .flatMap((matrix) => matrix.requiredEvidence))).sort();
  const summary = Object.assign(schemaV2Blocked(gateValue, "PASS"), {
    artifactIdentity: structuredClone(schemaV2Identity), evidence: evidenceIds.map(schemaV2Evidence),
    productionLikeEvidence: gateValue.productionLikeEvidencePolicy.requiredForClosing.map(schemaV2Evidence),
    matrices: Object.entries(gateValue.rehearsalMatrices).map(([matrixId, matrix]) => ({
      matrixId, result: "PASS", findingCounts: { critical: 0, high: 0, medium: 0, low: 0 },
      cases: matrix.requiredCases.map((caseId) => ({
        procedureId: `${matrixId}.${caseId}`, targetAlias: `target.${matrixId}`,
        expectedStatus: matrix.expectedStatusByCase[caseId][0], observedStatus: matrix.expectedStatusByCase[caseId][0],
        redactionResult: "PASS", localEvidencePath: schemaV2EvidencePath,
      })),
    })),
  });
  if (withDisposition) {
    summary.matrices[0].findingCounts.medium = 1;
    summary.matrices[0].mediumFindingDisposition = {
      ownerAlias: `owner.${summary.matrices[0].matrixId}`,
      fixPlanEvidencePath: ".codex/evidence/security/abuse-penetration-rehearsal/run/fix-plan.json",
    };
  }
  return summary;
}
function schemaV2Nodes(summary) {
  return {
    root: summary, artifactIdentity: summary.artifactIdentity, evidence: summary.evidence[0],
    matrix: summary.matrices[0], findingCounts: summary.matrices[0].findingCounts,
    mediumFindingDisposition: summary.matrices[0].mediumFindingDisposition,
    case: summary.matrices[0].cases[0],
  };
}
function schemaV2Validate(summary, gateValue = gate) {
  return validateSchema(buildAbusePenetrationSummaryV2Schema(gateValue), summary);
}
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
      requiredEvidence: structuredClone(matrix.requiredEvidence),
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

function freshSummary() {
  return structuredClone(validSummary());
}

test("A RED direct schema rejects every missing required and extra field", () => {
  const requiredByKind = {
    root: ["schemaVersion", "releaseGate", "issue", "status", "rawInvocationStored", "redactionPolicyId"],
    artifactIdentity: ["gitSha", "versionCode", "androidApplicationId", "dataPackManifestSha256"],
    evidence: ["evidenceId", "result", "localEvidencePath"], matrix: ["matrixId", "result", "findingCounts", "cases"],
    findingCounts: ["critical", "high", "medium", "low"],
    mediumFindingDisposition: ["ownerAlias", "fixPlanEvidencePath"],
    case: ["procedureId", "targetAlias", "expectedStatus", "observedStatus", "redactionResult", "localEvidencePath"],
  };
  for (const [kind, fields] of Object.entries(requiredByKind)) {
    for (const field of fields) {
      const summary = schemaV2Pass(); delete schemaV2Nodes(summary)[kind][field];
      assert.equal(schemaV2Validate(summary).ok, false, `${kind}.${field} missing`);
    }
    const summary = schemaV2Pass(); schemaV2Nodes(summary)[kind].unexpectedField = 1;
    assert.equal(schemaV2Validate(summary).ok, false, `${kind} extra`);
  }
});

test("A RED direct schema rejects every wrong declared type", () => {
  const wrong = { string: 1, integer: "1", boolean: "false", object: [], array: {} };
  for (const [kind, fields] of Object.entries(gate.summaryContract.fieldTypes)) {
    for (const [field, type] of Object.entries(fields)) {
      const summary = schemaV2Pass();
      schemaV2Nodes(summary)[kind][field] = structuredClone(wrong[type]);
      assert.equal(schemaV2Validate(summary).ok, false, `${kind}.${field}:${type}`);
    }
  }
});

test("A RED direct schema enforces every enum const count and relative path", () => {
  const mutations = [
    (s) => { s.schemaVersion = 3; }, (s) => { s.releaseGate = "other"; }, (s) => { s.issue = -1; },
    (s) => { s.status = "UNKNOWN"; }, (s) => { s.rawInvocationStored = true; },
    (s) => { s.redactionPolicyId = "unknown-policy"; }, (s) => { s.evidence[0].evidenceId = "unknown-evidence"; },
    (s) => { s.evidence[0].result = "UNKNOWN"; }, (s) => { s.productionLikeEvidence[0].evidenceId = "unknown-evidence"; },
    (s) => { s.matrices[0].matrixId = "unknownMatrix"; }, (s) => { s.matrices[0].result = "UNKNOWN"; },
    (s) => { s.matrices[0].cases[0].procedureId = "unknown.procedure"; },
    (s) => { s.matrices[0].cases[0].targetAlias = "target.unknown"; },
    (s) => { s.matrices[0].cases[0].redactionResult = "UNKNOWN"; },
    (s) => { s.matrices[0].findingCounts.high = -1; }, (s) => { s.matrices[0].findingCounts.high = 0.5; },
    (s) => { s.matrices[0].findingCounts.high = "0"; },
  ];
  for (const mutate of mutations) { const summary = schemaV2Pass(); mutate(summary); assert.equal(schemaV2Validate(summary).ok, false); }
  const badPaths = ["/absolute", "../parent", "scheme:path", "with?query", "with#fragment", "with space"];
  for (const value of badPaths) { const summary = schemaV2Pass(); summary.evidence[0].localEvidencePath = value; assert.equal(schemaV2Validate(summary).ok, false); }
  const allowed = new Set(["$id", "additionalProperties", "const", "enum", "items", "minimum", "pattern", "properties", "required", "type"]);
  const visit = (schema) => {
    for (const key of Object.keys(schema)) assert.equal(allowed.has(key), true, key);
    for (const child of Object.values(schema.properties ?? {})) visit(child);
    if (schema.items) visit(schema.items);
  };
  visit(buildAbusePenetrationSummaryV2Schema(gate));
});

test("A RED direct schema enforces deterministic identity patterns", () => {
  assert.equal(schemaV2Validate(schemaV2Pass()).ok, true);
  const fields = ["gitSha", "androidApplicationId", "dataPackManifestSha256", "aabSha256", "generatedApkSha256", "backendImageDigest", "backendArtifactSha256"];
  const invalid = {
    gitSha: "a".repeat(39), androidApplicationId: "com.example.app", dataPackManifestSha256: "b".repeat(63),
    aabSha256: "c".repeat(63), generatedApkSha256: "d".repeat(65),
    backendImageDigest: `sha256:${"g".repeat(64)}`, backendArtifactSha256: "f".repeat(63),
  };
  for (const field of fields) {
    const summary = schemaV2Pass(); summary.artifactIdentity[field] = invalid[field];
    assert.equal(schemaV2Validate(summary).ok, false, field);
  }
});

async function assertSensitiveValueRejected(value) {
  const summary = freshSummary();
  summary.matrices[0].redactionNotes = value;
  await assert.rejects(
    validateSummary(summary),
    /raw sensitive evidence material/,
  );
}

async function assertWrongTypeRejected(mutate) {
  const summary = freshSummary();
  mutate(summary);
  await assert.rejects(
    validateSummary(summary),
    /must be (?:a string|an integer|a non-negative integer|an object|an array)/,
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
  const missingProductionEvidence = freshSummary();
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
  const forbiddenClosureEvidence = freshSummary();
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

test("abuse penetration summary validator rejects standalone authority and path address forms", async () => {
  const ipv4 = [["19", "2"], ["0"], ["2"], ["4", "2"]].map((parts) => parts.join("")).join(".");
  const ipv6 = [["20", "01"], ":", ["db", "8"], "::", ["4", "2"]].flat().join("");
  const alternate = ["0x", "c0", "00", "02", "2a"].join("");
  for (const value of [
    [ipv4, ":", ["8", "443"].join("")].join(""),
    [ipv4, "/evidence"].join(""),
    [alternate, ":", ["8", "443"].join(""), "/evidence"].join(""),
    ["[", ipv6, "]:", ["4", "43"].join(""), "/evidence"].join(""),
  ]) {
    await assertSensitiveValueRejected(value);
  }
});

test("abuse penetration summary validator rejects an address after version-like prose prefixes", async () => {
  const ipv4 = [["19", "2"], ["0"], ["2"], ["4", "2"]].map((parts) => parts.join("")).join(".");
  for (const prefix of ["version ", "release ", "build "]) {
    await assertSensitiveValueRejected(`${prefix}${ipv4}`);
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
    const summary = freshSummary();
    mutate(summary);
    await assert.rejects(validateSummary(summary), /unsupported field/);
  }
});

test("abuse penetration summary validator rejects wrong types across root and nested containers", async () => {
  const isolatedFirst = freshSummary();
  const isolatedSecond = freshSummary();
  isolatedFirst.matrices[0].requiredEvidence[0] = 1;
  assert.equal(typeof isolatedSecond.matrices[0].requiredEvidence[0], "string");

  const mutations = [
    (summary) => { summary.schemaVersion = "1"; },
    (summary) => { summary.releaseGate = 1; },
    (summary) => { summary.issue = "1022"; },
    (summary) => { summary.status = 1; },
    (summary) => { summary.artifactIdentity = []; },
    (summary) => { summary.productionLikeEvidence = {}; },
    (summary) => { summary.matrices = {}; },
    (summary) => { summary.artifactIdentity.versionCode = "10001"; },
    (summary) => { summary.artifactIdentity.gitSha = 1; },
    (summary) => { summary.productionLikeEvidence[0].evidenceId = 1; },
    (summary) => { summary.productionLikeEvidence[0].result = 1; },
    (summary) => { summary.productionLikeEvidence[0].localEvidencePath = 1; },
    (summary) => { summary.productionLikeEvidence[0] = "invalid"; },
    (summary) => { summary.matrices[0].matrixId = 1; },
    (summary) => { summary.matrices[0].scenarioId = 1; },
    (summary) => { summary.matrices[0].commandOrManualCheck = 1; },
    (summary) => { summary.matrices[0].result = 1; },
    (summary) => { summary.matrices[0].redactionNotes = 1; },
    (summary) => { summary.matrices[0].localEvidencePath = 1; },
    (summary) => { summary.matrices[0].artifactIdentity = []; },
    (summary) => { summary.matrices[0].findingCounts = []; },
    (summary) => { summary.matrices[0].requiredEvidence = {}; },
    (summary) => { summary.matrices[0].cases = {}; },
    (summary) => { summary.matrices[0] = "invalid"; },
    (summary) => { summary.matrices[0].findingCounts.critical = "0"; },
    (summary) => { summary.matrices[0].findingCounts.low = -1; },
    (summary) => {
      summary.matrices[0].mediumFindingDisposition = { owner: 1, fixPlan: "tracked follow-up" };
    },
    (summary) => {
      summary.matrices[0].mediumFindingDisposition = { owner: "security-owner", fixPlan: 1 };
    },
    (summary) => { summary.matrices[0].requiredEvidence[0] = 1; },
    (summary) => { summary.matrices[0].cases[0] = "invalid"; },
  ];
  for (const mutate of mutations) await assertWrongTypeRejected(mutate);
});

test("abuse penetration summary validator enforces every gate-declared case field type", async () => {
  const integerFields = new Set(["expectedStatus", "observedStatus", "sizeBytes", "ttlSeconds"]);
  const fields = new Set(Object.values(gate.rehearsalMatrices).flatMap((matrix) => matrix.summaryFields));
  for (const field of fields) {
    const [matrixId] = Object.entries(gate.rehearsalMatrices).find(([, matrix]) => matrix.summaryFields.includes(field));
    const summary = freshSummary();
    const matrix = summary.matrices.find((item) => item.matrixId === matrixId);
    matrix.cases[0][field] = integerFields.has(field) ? "1" : 1;
    await assert.rejects(
      validateSummary(summary),
      /must be (?:a string|an integer)/,
    );
  }
});

test("abuse penetration summary validator rejects a numeric alternate host in an allowed endpoint field", async () => {
  const summary = freshSummary();
  const matrix = summary.matrices.find((item) => item.matrixId === "adCounterInflation");
  matrix.cases[0].endpoint = Number(["322", "122", "602", "6"].join(""));
  await assert.rejects(validateSummary(summary), /endpoint must be a string/);
});

test("abuse penetration summary validator rejects extra and duplicate evidence, matrix, and case IDs", async () => {
  const extraEvidence = freshSummary();
  extraEvidence.productionLikeEvidence.push({
    evidenceId: "unexpected-evidence",
    result: "PASS",
    localEvidencePath: ".codex/evidence/security/abuse-penetration-rehearsal/rc/redacted-summary.json",
  });
  await assert.rejects(validateSummary(extraEvidence), /unexpected evidenceId/);

  const duplicateEvidence = freshSummary();
  duplicateEvidence.productionLikeEvidence.push(structuredClone(duplicateEvidence.productionLikeEvidence[0]));
  await assert.rejects(validateSummary(duplicateEvidence), /duplicate evidenceId/);

  const extraMatrix = freshSummary();
  extraMatrix.matrices.push({ ...structuredClone(extraMatrix.matrices[0]), matrixId: "unexpectedMatrix" });
  await assert.rejects(validateSummary(extraMatrix), /unexpected matrixId/);

  const duplicateMatrix = freshSummary();
  duplicateMatrix.matrices.push(structuredClone(duplicateMatrix.matrices[0]));
  await assert.rejects(validateSummary(duplicateMatrix), /duplicate matrixId/);

  const extraCase = freshSummary();
  extraCase.matrices[0].cases.push({ ...structuredClone(extraCase.matrices[0].cases[0]), caseId: "unexpected_case" });
  await assert.rejects(validateSummary(extraCase), /unexpected caseId/);

  const duplicateCase = freshSummary();
  duplicateCase.matrices[0].cases.push(structuredClone(duplicateCase.matrices[0].cases[0]));
  await assert.rejects(validateSummary(duplicateCase), /duplicate caseId/);
});

test("abuse penetration summary validator accepts safe endpoint, evidence, prose, command, and version controls", async () => {
  const semver = ["release v", ["1", "2", "3", "4"].join(".")].join("");
  for (const value of [
    "easysubway-api.aquilaxk.site",
    "/api/v1/reports",
    "image/jpeg",
    ".codex/evidence/security/abuse-penetration-rehearsal/rc/redacted-summary.json",
    "sensitive values removed",
    "curl --fail",
    semver,
    ["not", "::", "an", "::", "address"].join(""),
  ]) {
    const summary = freshSummary();
    summary.matrices[0].redactionNotes = value;
    await validateSummary(summary);
  }
});

test("abuse penetration summary validator rejects missing cases, raw sensitive markers, and high findings", async () => {
  const missingCase = freshSummary();
  missingCase.matrices[0].cases.pop();
  await assert.rejects(
    withSummary(missingCase, (summaryPath) =>
      execFileAsync(process.execPath, ["tools/security/validate-abuse-penetration-summary.mjs", "--summary", summaryPath], {
        cwd: root,
      }),
    ),
    /cases\./,
  );

  const leaked = freshSummary();
  leaked.matrices[0].redactionNotes = "raw signed URL leaked";
  await assert.rejects(
    withSummary(leaked, (summaryPath) =>
      execFileAsync(process.execPath, ["tools/security/validate-abuse-penetration-summary.mjs", "--summary", summaryPath], {
        cwd: root,
      }),
    ),
    /forbidden sensitive evidence marker/,
  );

  const highFinding = freshSummary();
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

  const stringCount = freshSummary();
  stringCount.matrices[0].findingCounts.critical = "0";
  await assert.rejects(
    withSummary(stringCount, (summaryPath) =>
      execFileAsync(process.execPath, ["tools/security/validate-abuse-penetration-summary.mjs", "--summary", summaryPath], {
        cwd: root,
      }),
    ),
    /non-negative integer/,
  );

  const mixedIdentity = freshSummary();
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
  const statusMismatch = freshSummary();
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

  const redactionFailure = freshSummary();
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

  const untrustedStatusPair = freshSummary();
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
  const wrongEdgeStatus = freshSummary();
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
    const missingCase = freshSummary();
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
