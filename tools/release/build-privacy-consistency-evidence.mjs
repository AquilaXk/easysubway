#!/usr/bin/env node

// #1018 마지막 DoD의 #2056 fragment. Play Data Safety 폼 target(answerMatrix), 공개된
// 개인정보 처리방침, runtime 수집 inventory 세 원본 사이의 machine-auditable 일치 판정을
// 같은 candidate-context(#2056) RC identity에 결속해 emit한다. 개인정보 처리방침 산문이나
// 폼 답변을 재작성하지 않고, 이미 tracked된 세 원본의 내부 모순 0과 정책 경계 문구 anchor
// 존재만 정적으로 검증한다. 불일치가 하나라도 있으면 fail-closed로 BLOCKED를 산출한다.

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const INVENTORY_FILE = "apps/mobile/release/store-privacy-inventory.json";
const PLAY_FORM_FILE = "apps/mobile/release/play-store-submission-content.json";
const PRIVACY_POLICY_FILE = "backend/src/main/resources/templates/legal/privacy.html";

// 이미 확보된 외부 검증 사실의 provenance 참조다. 이 값들은 기계적으로 재현할 수 없는
// 외부 검증(공개 URL 200 응답, runtime denylist audit, Play Console 폼 재제출)이 어디에
// 기록됐는지 가리키는 인용이며, 아래 status 판정에는 사용하지 않는다. status는 오직 세
// tracked 원본의 정적 일치 검증 결과로만 결정한다(외부 사실을 status로 위조하지 않는다).
const BOUND_EVIDENCE_REFERENCES = {
  publishedPolicy: {
    url: "https://easysubway-api.aquilaxk.site/easysubway/privacy",
    effectiveDate: "2026-07-16",
    trackedSource: PRIVACY_POLICY_FILE,
    trackedSourceIssue: 2225,
    trackedSourceCommit: "4b35c23c",
    recordedResult: "PASS_PUBLIC_HTTPS_UNAUTHENTICATED",
    verificationCommentUrl:
      "https://github.com/AquilaXk/easysubway/issues/1018#issuecomment-5018187764",
  },
  runtimeDenylistAudit: {
    scopes: ["database", "application-log", "proxy-log", "metric", "analytics"],
    recordedViolationCount: 0,
    capacityRunUrl: "https://github.com/AquilaXk/easysubway/actions/runs/29712689840",
    verificationCommentUrl:
      "https://github.com/AquilaXk/easysubway/issues/1018#issuecomment-5018496643",
  },
  playConsoleDataSafetyForm: {
    inventorySource: INVENTORY_FILE,
    formSource: PLAY_FORM_FILE,
    resubmittedAt: "2026-07-18",
    recordedResult: "RESUBMITTED_AND_REVIEWED_FROM_TRACKED_INVENTORY",
  },
};

// 정책 원본에 존재해야 하는 핵심 경계 서술의 최소 anchor. 각 boundary는 (1) inventory가
// 실제로 그 경계를 선언하는지와 (2) 정책 원본에 그 경계를 알리는 문구 anchor가 있는지를
// 함께 요구한다. anchor는 산문 전체를 동결하지 않는 최소 리터럴만 쓴다. inventoryFact는
// evaluatePolicyBoundaryConsistency가 한 번만 조회해 넘기는 공유 context를 받아, 같은
// inventory 항목을 여러 boundary가 각자 다시 조회하는 중복을 없앤다.
const POLICY_BOUNDARIES = [
  {
    id: "gateway_shared_memory_non_persistence",
    descriptionKo:
      "Nginx IP·Authorization shared-memory rate-limit 처리와 DB·access log 비저장 경계",
    inventoryFact({ gateway, gatewayKeys }) {
      return Boolean(
        gateway
          && gateway.googlePlayDataSafety?.deletionSupported === false
          && gateway.googlePlayDataSafety?.processedEphemerally === false
          && gatewayKeys.length > 0
          && gatewayKeys.every((key) => key.persistedToDatabase === false && key.includedInAccessLog === false),
      );
    },
    anchors: [
      "$binary_remote_addr",
      "$http_authorization",
      "shared memory",
      "DB나 access log에는 저장하지 않습니다",
    ],
  },
  {
    id: "route_v2_raw_hash_boundary",
    descriptionKo:
      "선택형 ITX-청춘 Route V2 raw token·nonce 미저장과 SHA-256·논리 만료·5분 purge 물리 파기 경계",
    inventoryFact({ routeV2Integrity }) {
      const stored = routeV2Integrity?.backendStoredFields ?? [];
      const neverPersisted = routeV2Integrity?.backendNeverPersistedOrLogged ?? [];
      return Boolean(
        routeV2Integrity
          && stored.includes("tokenSha256")
          && stored.includes("nonceSha256")
          && neverPersisted.includes("rawIntegrityToken")
          && neverPersisted.includes("rawClientNonce"),
      );
    },
    anchors: [
      "raw integrityToken을 저장하지 않고",
      "nonce SHA-256",
      "purge로 물리 삭제",
    ],
  },
  {
    id: "external_map_user_initiated",
    descriptionKo:
      "외부 지도 도보 길안내는 사용자가 직접 누를 때만 좌표를 전달하고 서버에 저장하지 않는 user-initiated 예외 경계",
    inventoryFact({ preciseLocation }) {
      const exception = preciseLocation?.userInitiatedSharingException;
      return Boolean(
        exception?.applies === true
          && exception?.consoleThirdPartySharingDeclared === false,
      );
    },
    anchors: [
      "출구 도보 길안내를 명시적으로 누른 경우에만",
      "쉬운 지하철 서버에는 저장하지 않습니다",
    ],
  },
  {
    id: "play_integrity_boundary",
    descriptionKo:
      "Google Play Integrity 처리 정보는 Google 고정 정책을 따르고 backend가 raw token·verdict를 저장·로그하지 않는 경계",
    inventoryFact({ routeV2Integrity }) {
      return Boolean(
        routeV2Integrity?.googlePlayProcessing?.sharedOnward === false
          && routeV2Integrity?.googleProcessingMayBeLinkedToSignedInAccountOrDevice === true,
      );
    },
    anchors: [
      "Integrity payload·verdict를 DB에 저장하거나 로그에 남기지 않으며",
      "Google Play Integrity decode API",
    ],
  },
];

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function readInput(repoRoot, relativePath) {
  const absolute = path.join(repoRoot, relativePath);
  if (!existsSync(absolute)) return { present: false, path: relativePath, text: null, sha256: null };
  const bytes = readFileSync(absolute);
  return { present: true, path: relativePath, text: bytes.toString("utf8"), sha256: sha256(bytes) };
}

// entry.inventoryDataIds가 가리키는 inventory 항목을 조회해 (1) 참조된 항목 목록과
// (2) 조회 자체에서 나온 모순(존재하지 않는 id, dataType 불일치)을 반환한다.
function resolveMatrixEntryReferences(entry, items) {
  const referenced = [];
  const contradictions = [];
  for (const id of entry.inventoryDataIds ?? []) {
    const item = items.get(id);
    if (!item) {
      contradictions.push({ dataType: entry.dataType, code: "missing_inventory_data_id", detail: id });
      continue;
    }
    referenced.push(item);
    if (item.googlePlayDataSafety?.dataType !== entry.dataType) {
      contradictions.push({
        dataType: entry.dataType,
        code: "inventory_data_type_mismatch",
        detail: `${id}=${item.googlePlayDataSafety?.dataType}`,
      });
    }
  }
  return { referenced, contradictions };
}

// entry의 boolean 집계 플래그(collected/required/optional/deletion-unsupported)가 참조된
// inventory 항목들의 실제 googlePlayDataSafety 값과 일치하는지 각각 검증한다.
function checkMatrixEntryAggregateFlags(entry, referenced) {
  const some = (predicate) => referenced.some((item) => predicate(item.googlePlayDataSafety ?? {}));
  const flagChecks = [
    ["containsCollectedData", "collected_flag_mismatch", some((safety) => safety.collected === true)],
    ["containsRequiredData", "required_flag_mismatch", some((safety) => safety.required === true)],
    ["containsOptionalData", "optional_flag_mismatch", some((safety) => safety.optional === true)],
    [
      "containsDeletionUnsupportedData",
      "deletion_unsupported_flag_mismatch",
      some((safety) => safety.deletionSupported === false),
    ],
  ];
  const contradictions = [];
  for (const [field, code, expected] of flagChecks) {
    if (Boolean(entry[field]) !== expected) contradictions.push({ dataType: entry.dataType, code });
  }
  return contradictions;
}

// containsLocalOnlyDiagnostics와 requiredConsoleFields는 boolean 집계와 형태가 달라
// (선언적일 때만 검사, 배열 비교) 별도 helper로 분리한다.
function checkMatrixEntrySupplementalFields(entry, referenced, requiredConsoleFields) {
  const contradictions = [];
  if (entry.containsLocalOnlyDiagnostics !== undefined) {
    const expectLocalOnly = referenced.some(
      (item) => (item.googlePlayDataSafety?.collectionType ?? "").includes("local-only"),
    );
    if (Boolean(entry.containsLocalOnlyDiagnostics) !== expectLocalOnly) {
      contradictions.push({ dataType: entry.dataType, code: "local_only_diagnostics_flag_mismatch" });
    }
  }
  if (JSON.stringify(entry.requiredConsoleFields ?? []) !== JSON.stringify(requiredConsoleFields)) {
    contradictions.push({ dataType: entry.dataType, code: "required_console_fields_mismatch" });
  }
  return contradictions;
}

// inventory에서 실제 수집(collected=true)하는 항목이 모두 폼 matrix에서 참조됐는지
// (coverage) 확인한다. 누락된 id는 uncovered로, 그 자체도 모순으로 기록한다.
function findUncoveredCollectedData(inventory, referencedIds) {
  const uncovered = [];
  const contradictions = [];
  for (const item of inventory.dataTypes ?? []) {
    if (item.googlePlayDataSafety?.collected === true && !referencedIds.has(item.id)) {
      uncovered.push(item.id);
      contradictions.push({
        dataType: item.googlePlayDataSafety?.dataType,
        code: "uncovered_collected_data",
        detail: item.id,
      });
    }
  }
  return { uncovered, contradictions };
}

// answerMatrix(폼 target)의 각 dataType 집계 선언이 그것이 참조하는 inventory 수집 항목의
// 실제 값과 모순되지 않는지 검증한다. inventory의 어떤 collected 항목도 폼 matrix에서
// 누락되지 않았는지(coverage)도 확인한다. 반환하는 contradictions가 비어야 일치다.
function evaluateAnswerMatrixConsistency(inventory, playForm) {
  const items = new Map((inventory.dataTypes ?? []).map((item) => [item.id, item]));
  const matrix = playForm.dataSafetyDeclarations?.answerMatrix ?? [];
  const requiredConsoleFields = inventory.googlePlayDataSafetyRequiredFields ?? [];
  const referencedIds = new Set();
  const contradictions = [];

  for (const entry of matrix) {
    for (const id of entry.inventoryDataIds ?? []) referencedIds.add(id);
    const { referenced, contradictions: referenceContradictions } = resolveMatrixEntryReferences(entry, items);
    contradictions.push(...referenceContradictions);
    contradictions.push(...checkMatrixEntryAggregateFlags(entry, referenced));
    contradictions.push(...checkMatrixEntrySupplementalFields(entry, referenced, requiredConsoleFields));
  }

  const { uncovered: uncoveredCollected, contradictions: coverageContradictions } =
    findUncoveredCollectedData(inventory, referencedIds);
  contradictions.push(...coverageContradictions);

  return {
    checkedDataTypes: matrix.length,
    uncoveredCollected,
    contradictions,
    consistent: contradictions.length === 0,
  };
}

// 여러 boundary가 공통으로 참조하는 inventory 항목을 한 번만 조회해 각 boundary의
// inventoryFact에 공유 context로 넘긴다(같은 항목을 boundary마다 다시 조회하는 중복 제거).
function buildPolicyBoundaryContext(inventory, items) {
  return {
    gateway: items.get("route_v2_gateway_abuse_rate_limit_state"),
    gatewayKeys: inventory.routeV2GatewayRateLimit?.keys ?? [],
    routeV2Integrity: items.get("route_v2_itx_integrity"),
    preciseLocation: items.get("precise_location"),
  };
}

// runtime inventory가 선언하는 핵심 경계가 실제로 성립하고, 그 경계를 알리는 정책 문구
// anchor가 공개 정책 원본에 모두 존재하는지 검증한다.
function evaluatePolicyBoundaryConsistency(inventory, privacyPolicyHtml) {
  const items = new Map((inventory.dataTypes ?? []).map((item) => [item.id, item]));
  const context = buildPolicyBoundaryContext(inventory, items);
  const boundaries = POLICY_BOUNDARIES.map((boundary) => {
    const inventoryFactHolds = boundary.inventoryFact(context);
    const missingAnchors = boundary.anchors.filter((anchor) => !privacyPolicyHtml.includes(anchor));
    return {
      id: boundary.id,
      descriptionKo: boundary.descriptionKo,
      inventoryFactHolds,
      anchors: boundary.anchors,
      missingAnchors,
      consistent: inventoryFactHolds && missingAnchors.length === 0,
    };
  });
  return {
    boundaries,
    consistent: boundaries.every((boundary) => boundary.consistent),
  };
}

export function buildPrivacyConsistencyEvidence({
  candidate,
  repoRoot = process.cwd(),
  generatedAt = new Date().toISOString(),
  provenance = "final-candidate",
}) {
  const identity = candidate?.releaseCandidateIdentity;
  if (candidate?.phase !== "CANDIDATE" || candidate?.issue !== 2056 || !identity) {
    throw new Error("privacy consistency evidence requires the #2056 CANDIDATE context");
  }

  const inventoryInput = readInput(repoRoot, INVENTORY_FILE);
  const playFormInput = readInput(repoRoot, PLAY_FORM_FILE);
  const policyInput = readInput(repoRoot, PRIVACY_POLICY_FILE);
  const inputs = {
    inventory: { path: inventoryInput.path, sha256: inventoryInput.sha256 },
    playForm: { path: playFormInput.path, sha256: playFormInput.sha256 },
    privacyPolicy: { path: policyInput.path, sha256: policyInput.sha256 },
  };
  const missingInputs = [inventoryInput, playFormInput, policyInput]
    .filter((input) => !input.present)
    .map((input) => input.path);

  if (missingInputs.length > 0) {
    return {
      schemaVersion: 1,
      artifactKind: "store-privacy-consistency-evidence",
      sourceIssue: 1018,
      consumerIssue: 2056,
      generatedAt,
      provenance,
      status: "BLOCKED_PRIVACY_CONSISTENCY_INPUTS",
      releaseCandidateIdentity: identity,
      inputs,
      missingInputs,
      boundEvidenceReferences: BOUND_EVIDENCE_REFERENCES,
      checks: {
        inventoryFormConsistent: "BLOCKED",
        inventoryPolicyConsistent: "BLOCKED",
      },
    };
  }

  const inventory = JSON.parse(inventoryInput.text);
  const playForm = JSON.parse(playFormInput.text);
  const answerMatrixConsistency = evaluateAnswerMatrixConsistency(inventory, playForm);
  const policyBoundaryConsistency = evaluatePolicyBoundaryConsistency(inventory, policyInput.text);
  const consistent = answerMatrixConsistency.consistent && policyBoundaryConsistency.consistent;

  return {
    schemaVersion: 1,
    artifactKind: "store-privacy-consistency-evidence",
    sourceIssue: 1018,
    consumerIssue: 2056,
    generatedAt,
    provenance,
    status: consistent ? "SATISFIED" : "BLOCKED_PRIVACY_CONSISTENCY",
    releaseCandidateIdentity: identity,
    inputs,
    boundEvidenceReferences: BOUND_EVIDENCE_REFERENCES,
    answerMatrixConsistency,
    policyBoundaryConsistency,
    checks: {
      inventoryFormConsistent: answerMatrixConsistency.consistent ? "SATISFIED" : "FAILED",
      inventoryPolicyConsistent: policyBoundaryConsistency.consistent ? "SATISFIED" : "FAILED",
    },
  };
}

function argument(name) {
  const index = process.argv.indexOf(`--${name}`);
  return index < 0 ? null : process.argv[index + 1];
}

const entry = process.argv[1] ? path.resolve(process.argv[1]) : null;
if (entry === fileURLToPath(import.meta.url)) {
  const candidatePath = argument("candidate-context");
  const outputPath = argument("output");
  if (!candidatePath || !outputPath) {
    throw new Error("--candidate-context and --output are required");
  }
  const repoRoot = argument("repo-root") ? path.resolve(argument("repo-root")) : process.cwd();
  const provenance = argument("provenance") ?? "final-candidate";
  const evidence = buildPrivacyConsistencyEvidence({
    candidate: JSON.parse(readFileSync(candidatePath, "utf8")),
    repoRoot,
    provenance,
  });
  mkdirSync(path.dirname(outputPath), { recursive: true });
  writeFileSync(outputPath, `${JSON.stringify(evidence, null, 2)}\n`);
}
