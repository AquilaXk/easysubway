#!/usr/bin/env node

// #1018 마지막 DoD의 #2056 fragment. Play Data Safety 폼 target(answerMatrix), 공개된
// 개인정보 처리방침, runtime 수집 inventory 세 원본 사이의 machine-auditable 일치 판정을
// 같은 candidate-context(#2056) RC identity에 결속해 emit한다. 개인정보 처리방침 산문이나
// 폼 답변을 재작성하지 않고, 이미 tracked된 세 원본의 내부 모순 0과 정책 경계 문구 anchor
// 존재만 정적으로 검증한다. 불일치가 하나라도 있으면 fail-closed로 BLOCKED를 산출한다.

import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { runCandidateContextEvidenceCli } from "./lib/candidate-context-evidence-cli.mjs";

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
  // reviewedFormSha256/reviewedFormCommit은 Play Console Data Safety 폼과 현행 tracked
  // play-store-submission-content.json을 전수 대조 재검증한 시점의 파일 원문에 결속된
  // 고정값이다(git show fa82ce6e:apps/mobile/release/play-store-submission-content.json
  // | shasum -a 256). 2026-07-20 재검증(오너 위임 하에 Console 5단계 전체를 현행 tracked
  // 폼과 대조): Console에 노출되는 답변과 현행 tracked 내용이 완전 일치, Console 답변 변경
  // 0건·미저장 변경 0건이라 '저장' 비활성 — Console 재제출 이벤트는 불가·불필요였다.
  // 2026-07-18 검토(7ca86806) 이후의 tracked 변경(2026-07-19 train_search 참조 추가,
  // 2026-07-20 PR #2366 집계 플래그 5건 명시)은 전부 Console 폼에 노출되지 않는 tracked
  // 전용 변경(집계 플래그·inventory 참조 id·dataRetention 목록)이라, 노출 답변 무변경이
  // 확인된 이상 sha만 현행 revision(fa82ce6e)으로 재고정한다. 재검증 상세 로그는 local-only
  // evidence(.codex/evidence/release/privacy-consistency/1018-console-reverify-20260720/).
  // 이후 파일이 다시 바뀌면 현재 tracked sha256이 이 값과 달라지고
  // evaluatePlayConsoleProvenanceConsistency가 그 차이를 STALE로 fail-closed 판정한다 —
  // Console이 실제로 검토한 적 없는 내용을 검토된 것처럼 위조하지 않는다.
  playConsoleDataSafetyForm: {
    inventorySource: INVENTORY_FILE,
    formSource: PLAY_FORM_FILE,
    reviewedFormCommit: "fa82ce6e",
    reviewedFormSha256: "9ac24f19d8ab31389e75767050cf596f07142b541a53bb98ce8c1cf8ae9ad837",
    reverifiedAt: "2026-07-20",
    recordedResult: "REVERIFIED_CONSOLE_MATCHES_TRACKED_NO_RESUBMISSION_REQUIRED",
    // 이력: 최초 재제출·검토는 2026-07-18(7ca86806). 이후 tracked 전용 변경만 있었고
    // Console 노출 답변은 그대로여서 2026-07-20 재검증으로 sha만 현행 revision에 재고정했다.
    priorResubmittedAt: "2026-07-18",
    priorReviewedFormCommit: "7ca86806",
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
          // raw 필드가 backendStoredFields에 있으면 backendNeverPersistedOrLogged가 같은
          // 필드를 "저장 안 함"으로 선언해도 실제 저장 목록과 모순이다 — hash 필드 존재만
          // 보고 통과시키지 않는다.
          && !stored.includes("rawIntegrityToken")
          && !stored.includes("rawClientNonce")
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
      const neverPersisted = routeV2Integrity?.backendNeverPersistedOrLogged ?? [];
      return Boolean(
        routeV2Integrity?.googlePlayProcessing?.sharedOnward === false
          && routeV2Integrity?.googleProcessingMayBeLinkedToSignedInAccountOrDevice === true
          // Google Integrity payload·verdict 자체를 backend가 저장·로그하지 않는다는
          // 선언이 없으면, sharedOnward=false만으로는 이 boundary가 실제로 성립하지 않는다.
          && neverPersisted.includes("integrityPayloadOrVerdict"),
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
// inventory 항목들의 실제 googlePlayDataSafety 값과 일치하는지 각각 검증한다. 필드가
// 아예 없거나 boolean이 아니면(예: 문자열 "true") malformed/불완전한 Console 선언으로
// fail-closed 처리한다 — Boolean(...) truthy 변환이나 undefined 기본값에 기대지 않는다.
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
    const value = entry[field];
    if (typeof value !== "boolean") {
      contradictions.push({
        dataType: entry.dataType,
        code: "aggregate_flag_missing_or_not_boolean",
        detail: `${field}=${JSON.stringify(value ?? null)}`,
      });
      continue;
    }
    if (value !== expected) contradictions.push({ dataType: entry.dataType, code });
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

  // entry별 세 판정(참조 조회·집계 플래그·보조 필드)의 모순을 한 번에 모은다. push()를
  // 연쇄 호출하는 대신 flatMap으로 배열을 구성해 같은 entry 순서·같은 판정 순서를 유지한다.
  const entryContradictions = matrix.flatMap((entry) => {
    for (const id of entry.inventoryDataIds ?? []) referencedIds.add(id);
    const { referenced, contradictions } = resolveMatrixEntryReferences(entry, items);
    return [
      ...contradictions,
      ...checkMatrixEntryAggregateFlags(entry, referenced),
      ...checkMatrixEntrySupplementalFields(entry, referenced, requiredConsoleFields),
    ];
  });

  const { uncovered: uncoveredCollected, contradictions: coverageContradictions } =
    findUncoveredCollectedData(inventory, referencedIds);
  const contradictions = [...entryContradictions, ...coverageContradictions];

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

// HTML 주석(<!-- ... -->) 안에만 남은 문구는 실제 사용자에게 렌더링되지 않으므로 anchor
// 검사 대상에서 제외한다. 완전한 HTML 파서는 만들지 않고 주석 블록만 제거하는 최소
// 정규식을 쓴다(각 anchor는 순수 텍스트 리터럴이라 이 정도로 충분하다).
function stripHtmlComments(html) {
  return html.replace(/<!--[\s\S]*?-->/g, "");
}

// runtime inventory가 선언하는 핵심 경계가 실제로 성립하고, 그 경계를 알리는 정책 문구
// anchor가 공개 정책 원본(주석 제외 렌더링 텍스트)에 모두 존재하는지 검증한다.
function evaluatePolicyBoundaryConsistency(inventory, privacyPolicyHtml) {
  const items = new Map((inventory.dataTypes ?? []).map((item) => [item.id, item]));
  const context = buildPolicyBoundaryContext(inventory, items);
  const renderedPolicyText = stripHtmlComments(privacyPolicyHtml);
  const boundaries = POLICY_BOUNDARIES.map((boundary) => {
    const inventoryFactHolds = boundary.inventoryFact(context);
    const missingAnchors = boundary.anchors.filter((anchor) => !renderedPolicyText.includes(anchor));
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

// Console이 실제로 검토·재제출한 폼 원문 sha256(reviewedFormSha256)과 현재 tracked
// play-store-submission-content.json의 sha256이 같은지 검증한다. 다르면(예: 검토 이후
// commit이 폼을 바꿨는데 재제출·재검토가 없었으면) 그 provenance는 최신 상태를 대변하지
// 않으므로 STALE로 fail-closed 처리한다 — 검토된 적 없는 내용을 검토된 것처럼 위조하지
// 않는다.
function evaluatePlayConsoleProvenanceConsistency(currentFormSha256, reviewedFormSha256) {
  const matchesReviewedRevision = /^[0-9a-f]{64}$/.test(reviewedFormSha256 ?? "")
    && currentFormSha256 === reviewedFormSha256;
  return {
    reviewedFormSha256: reviewedFormSha256 ?? null,
    currentFormSha256,
    matchesReviewedRevision,
    consistent: matchesReviewedRevision,
  };
}

export function buildPrivacyConsistencyEvidence({
  candidate,
  repoRoot = process.cwd(),
  generatedAt = new Date().toISOString(),
  provenance = "final-candidate",
  // 프로덕션/CLI 경로는 항상 기본값(2026-07-20 재검증 시점의 현행 revision fa82ce6e에
  // 고정된 hash)을 쓴다. 이 파라미터는 evaluatePlayConsoleProvenanceConsistency 로직을
  // git 이력에 결합하지 않고 독립적으로 단위 테스트하기 위한 테스트 전용 override다.
  reviewedPlayFormSha256 = BOUND_EVIDENCE_REFERENCES.playConsoleDataSafetyForm.reviewedFormSha256,
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
        playConsoleProvenanceCurrent: "BLOCKED",
      },
    };
  }

  const inventory = JSON.parse(inventoryInput.text);
  const playForm = JSON.parse(playFormInput.text);
  const answerMatrixConsistency = evaluateAnswerMatrixConsistency(inventory, playForm);
  const policyBoundaryConsistency = evaluatePolicyBoundaryConsistency(inventory, policyInput.text);
  const playConsoleProvenanceConsistency = evaluatePlayConsoleProvenanceConsistency(
    playFormInput.sha256,
    reviewedPlayFormSha256,
  );
  const consistent = answerMatrixConsistency.consistent
    && policyBoundaryConsistency.consistent
    && playConsoleProvenanceConsistency.consistent;

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
    playConsoleProvenanceConsistency,
    checks: {
      inventoryFormConsistent: answerMatrixConsistency.consistent ? "SATISFIED" : "FAILED",
      inventoryPolicyConsistent: policyBoundaryConsistency.consistent ? "SATISFIED" : "FAILED",
      playConsoleProvenanceCurrent: playConsoleProvenanceConsistency.consistent ? "SATISFIED" : "STALE",
    },
  };
}

runCandidateContextEvidenceCli(import.meta.url, buildPrivacyConsistencyEvidence);
