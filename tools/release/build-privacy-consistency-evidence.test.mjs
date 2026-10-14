import assert from "node:assert/strict";
import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import {
  buildPrivacyConsistencyEvidence,
  stripHtmlComments,
} from "./build-privacy-consistency-evidence.mjs";

test("stripHtmlComments는 중첩·분할된 HTML 주석과 닫히지 않은 주석 꼬리까지 반복 제거해 <!-- 잔재를 남기지 않는다", () => {
  assert.equal(
    stripHtmlComments("공개 문구 <!-- 내부 메모 --> 끝"),
    "공개 문구  끝",
  );
  assert.equal(
    stripHtmlComments("앞 <!<!-- inner -->-- 숨겨진 문구 --> 뒤"),
    "앞  뒤",
  );
  assert.equal(
    stripHtmlComments("앞 <!<!--- a --->-<!-- b -->- 숨겨진 문구 --> 뒤"),
    "앞  뒤",
  );
  assert.equal(
    stripHtmlComments("앞 <!<!-- inner -->-- 닫히지 않은 주석 꼬리"),
    "앞 ",
  );
});

test("buildPrivacyConsistencyEvidence는 중첩 HTML 주석 안에만 남은 anchor를 렌더링된 본문으로 오인하지 않는다", async () => {
  const repoRoot = await mkdtemp(path.join(tmpdir(), "easysubway-privacy-nested-comment-"));
  await mkdir(path.join(repoRoot, "apps/mobile/release"), { recursive: true });
  await mkdir(path.join(repoRoot, "backend/src/main/resources/templates/legal"), { recursive: true });

  const inventory = {
    googlePlayDataSafetyRequiredFields: ["collected"],
    routeV2GatewayRateLimit: {
      keys: [{ persistedToDatabase: false, includedInAccessLog: false }],
    },
    embeddedMapPreview: {
      provider: "kakao-map",
      loadTrigger: "station_exit_section_visible",
      currentLocationShared: false,
      serverStored: false,
      tracking: false,
      googlePlayLocationClassification: { included: false },
    },
    dataTypes: [
      {
        id: "route_v2_gateway_abuse_rate_limit_state",
        googlePlayDataSafety: {
          dataType: "app_activity",
          collected: false,
          required: false,
          optional: false,
          deletionSupported: false,
          processedEphemerally: false,
        },
      },
      {
        id: "route_v2_itx_integrity",
        backendStoredFields: ["tokenSha256", "nonceSha256"],
        backendNeverPersistedOrLogged: [
          "rawIntegrityToken",
          "rawClientNonce",
          "integrityPayloadOrVerdict",
        ],
        googlePlayProcessing: { sharedOnward: false },
        googleProcessingMayBeLinkedToSignedInAccountOrDevice: true,
        googlePlayDataSafety: {
          dataType: "device_id",
          collected: false,
          required: false,
          optional: false,
          deletionSupported: false,
        },
      },
      {
        id: "precise_location",
        userInitiatedSharingException: {
          applies: true,
          consoleThirdPartySharingDeclared: false,
        },
        googlePlayDataSafety: {
          dataType: "precise_location",
          collected: false,
          required: false,
          optional: false,
          deletionSupported: false,
        },
      },
    ],
  };

  const playForm = {
    dataSafetyDeclarations: {
      answerMatrix: [],
    },
  };

  // $binary_remote_addr가 중첩 주석(<!<!-- inner -->-- ... -->) 내부에만 존재할 때
  // 단일 패스 치환은 바깥 주석을 남겨 anchor가 본문에 존재하는 것처럼 통과시키는 결함이 있었다.
  const policyHtml = [
    "<p>$http_authorization shared memory DB나 access log에는 저장하지 않습니다</p>",
    "<!<!-- inner -->-- $binary_remote_addr -->",
    "<p>raw integrityToken을 저장하지 않고 nonce SHA-256 purge로 물리 삭제</p>",
    "<p>출구 정보가 표시되면 카카오맵 미리보기를 자동으로 불러오며 공개 역·출구 좌표와 지도 화면 범위를 카카오에 전달하지만 현재 위치는 사용하지 않습니다 출구 도보 길안내를 명시적으로 누르면 쉬운 지하철 서버에 저장하지 않습니다</p>",
    "<p>Integrity payload·verdict를 DB에 저장하거나 로그에 남기지 않으며 Google Play Integrity decode API</p>",
  ].join("\n");

  await writeFile(
    path.join(repoRoot, "apps/mobile/release/store-privacy-inventory.json"),
    `${JSON.stringify(inventory, null, 2)}\n`,
  );
  await writeFile(
    path.join(repoRoot, "apps/mobile/release/play-store-submission-content.json"),
    `${JSON.stringify(playForm, null, 2)}\n`,
  );
  await writeFile(
    path.join(repoRoot, "backend/src/main/resources/templates/legal/privacy.html"),
    policyHtml,
  );

  const evidence = buildPrivacyConsistencyEvidence({
    candidate: {
      phase: "CANDIDATE",
      issue: 2056,
      releaseCandidateIdentity: {
        gitSha: "a".repeat(40),
        appVersionName: "1.0.4",
        versionCode: "10005",
      },
    },
    repoRoot,
    generatedAt: "2026-10-14T00:00:00.000Z",
  });

  const gatewayBoundary = evidence.policyBoundaryConsistency.boundaries.find(
    (item) => item.id === "gateway_shared_memory_non_persistence",
  );
  assert.ok(gatewayBoundary);
  assert.deepEqual(gatewayBoundary.missingAnchors, ["$binary_remote_addr"]);
  assert.equal(gatewayBoundary.consistent, false);
  assert.equal(evidence.policyBoundaryConsistency.consistent, false);
  assert.equal(evidence.status, "BLOCKED_PRIVACY_CONSISTENCY");
});
