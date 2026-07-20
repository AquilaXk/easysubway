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
// 함께 요구한다. anchor는 산문 전체를 동결하지 않는 최소 리터럴만 쓴다.
const POLICY_BOUNDARIES = [
  {
    id: "gateway_shared_memory_non_persistence",
    descriptionKo:
      "Nginx IP·Authorization shared-memory rate-limit 처리와 DB·access log 비저장 경계",
    inventoryFact(inventory, items) {
      const gateway = items.get("route_v2_gateway_abuse_rate_limit_state");
      const keys = inventory.routeV2GatewayRateLimit?.keys ?? [];
      return Boolean(
        gateway
          && gateway.googlePlayDataSafety?.deletionSupported === false
          && gateway.googlePlayDataSafety?.processedEphemerally === false
          && keys.length > 0
          && keys.every((key) => key.persistedToDatabase === false && key.includedInAccessLog === false),
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
    inventoryFact(_inventory, items) {
      const integrity = items.get("route_v2_itx_integrity");
      const stored = integrity?.backendStoredFields ?? [];
      const neverPersisted = integrity?.backendNeverPersistedOrLogged ?? [];
      return Boolean(
        integrity
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
    inventoryFact(_inventory, items) {
      const location = items.get("precise_location");
      const exception = location?.userInitiatedSharingException;
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
    inventoryFact(_inventory, items) {
      const integrity = items.get("route_v2_itx_integrity");
      return Boolean(
        integrity?.googlePlayProcessing?.sharedOnward === false
          && integrity?.googleProcessingMayBeLinkedToSignedInAccountOrDevice === true,
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

// answerMatrix(폼 target)의 각 dataType 집계 선언이 그것이 참조하는 inventory 수집 항목의
// 실제 값과 모순되지 않는지 검증한다. inventory의 어떤 collected 항목도 폼 matrix에서
// 누락되지 않았는지(coverage)도 확인한다. 반환하는 contradictions가 비어야 일치다.
function evaluateAnswerMatrixConsistency(inventory, playForm) {
  const items = new Map((inventory.dataTypes ?? []).map((item) => [item.id, item]));
  const matrix = playForm.dataSafetyDeclarations?.answerMatrix ?? [];
  const requiredConsoleFields = inventory.googlePlayDataSafetyRequiredFields ?? [];
  const contradictions = [];
  const referencedIds = new Set();

  for (const entry of matrix) {
    const referenced = [];
    for (const id of entry.inventoryDataIds ?? []) {
      referencedIds.add(id);
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

    const some = (predicate) => referenced.some((item) => predicate(item.googlePlayDataSafety ?? {}));
    const expectCollected = some((safety) => safety.collected === true);
    const expectRequired = some((safety) => safety.required === true);
    const expectOptional = some((safety) => safety.optional === true);
    const expectDeletionUnsupported = some((safety) => safety.deletionSupported === false);

    if (Boolean(entry.containsCollectedData) !== expectCollected) {
      contradictions.push({ dataType: entry.dataType, code: "collected_flag_mismatch" });
    }
    if (Boolean(entry.containsRequiredData) !== expectRequired) {
      contradictions.push({ dataType: entry.dataType, code: "required_flag_mismatch" });
    }
    if (Boolean(entry.containsOptionalData) !== expectOptional) {
      contradictions.push({ dataType: entry.dataType, code: "optional_flag_mismatch" });
    }
    if (Boolean(entry.containsDeletionUnsupportedData) !== expectDeletionUnsupported) {
      contradictions.push({ dataType: entry.dataType, code: "deletion_unsupported_flag_mismatch" });
    }
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
  }

  // Coverage: inventory에서 실제 수집(collected=true)하는 항목은 모두 폼 matrix가 참조해야 한다.
  const uncoveredCollected = [];
  for (const item of inventory.dataTypes ?? []) {
    if (item.googlePlayDataSafety?.collected === true && !referencedIds.has(item.id)) {
      uncoveredCollected.push(item.id);
      contradictions.push({ dataType: item.googlePlayDataSafety?.dataType, code: "uncovered_collected_data", detail: item.id });
    }
  }

  return {
    checkedDataTypes: matrix.length,
    uncoveredCollected,
    contradictions,
    consistent: contradictions.length === 0,
  };
}

// runtime inventory가 선언하는 핵심 경계가 실제로 성립하고, 그 경계를 알리는 정책 문구
// anchor가 공개 정책 원본에 모두 존재하는지 검증한다.
function evaluatePolicyBoundaryConsistency(inventory, privacyPolicyHtml) {
  const items = new Map((inventory.dataTypes ?? []).map((item) => [item.id, item]));
  const boundaries = POLICY_BOUNDARIES.map((boundary) => {
    const inventoryFactHolds = boundary.inventoryFact(inventory, items);
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
