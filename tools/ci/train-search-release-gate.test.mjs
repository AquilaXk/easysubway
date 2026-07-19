import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  normalizeProviderTrainType,
  validateBackendSearchEnvelope,
  validateProviderEnvelope,
} from "../test/train-search-live-smoke.mjs";

const read = (file) => readFileSync(file, "utf8");
const readJson = (file) => JSON.parse(read(file));

const supportedTrainTypes = [
  "KTX",
  "KTX_SANCHEON",
  "SRT",
  "ITX_MAUM",
  "ITX_SAEMAEUL",
  "SAEMAEUL",
  "MUGUNGHWA",
  "NURIRO",
];

test("TAGO resultCode·body schema와 공식 열차종을 strict하게 검증한다", () => {
  const payload = {
    response: {
      header: { resultCode: "00" },
      body: {
        items: { item: [{ vehiclekndid: "00", vehiclekndnm: "KTX" }] },
        pageNo: 1,
        numOfRows: 100,
        totalCount: 1,
      },
    },
  };

  assert.deepEqual(validateProviderEnvelope(payload, {
    operation: "GetVhcleKndList",
    paginated: true,
    pageNo: 1,
    pageSize: 100,
  }), payload.response.body);
  assert.equal(normalizeProviderTrainType("KTX-산천"), "KTX_SANCHEON");
  assert.equal(normalizeProviderTrainType("KTX-산천(A-type)"), "KTX_SANCHEON");
  assert.equal(normalizeProviderTrainType("KTX-산천(B-type)"), "KTX_SANCHEON");
  assert.equal(normalizeProviderTrainType("ITX-마음"), "ITX_MAUM");
  assert.equal(normalizeProviderTrainType("ITX-청춘"), "ITX_CHEONGCHUN");
  assert.throws(
    () => validateProviderEnvelope({ response: { header: { resultCode: "03" } } }, {
      operation: "GetVhcleKndList",
      paginated: false,
    }),
    /provider resultCode was not 00/,
  );
});

test("backend 서울→대전 KTX 응답은 운임·시간·ITX 0건을 증명한다", () => {
  const evidence = validateBackendSearchEnvelope({
    success: true,
    data: {
      observedAt: "2026-07-19T06:00:00Z",
      outbound: [{
        trainNumber: "101",
        trainType: "KTX",
        departureStationId: "NAT010000",
        departureStationName: "서울",
        departureAt: "2026-07-20T09:00:00+09:00",
        arrivalStationId: "NAT011668",
        arrivalStationName: "대전",
        arrivalAt: "2026-07-20T10:02:00+09:00",
        durationMinutes: 62,
        adultFareWon: 23700,
      }],
      inbound: [],
    },
  }, {
    departureStationId: "NAT010000",
    arrivalStationId: "NAT011668",
    trainType: "KTX",
  });

  assert.equal(evidence.rowCount, 1);
  assert.equal(evidence.fareRowCount, 1);
  assert.equal(evidence.itxCheongchunRowCount, 0);
});

test("capacity runner는 repeated·unique·3-node·quota 경계를 고정한다", () => {
  const k6 = read("tools/test/train-search-capacity.k6.js");
  const runner = read("tools/test/run-train-search-capacity.sh");

  assert.match(k6, /TRAIN_SEARCH_WORKLOAD/);
  assert.match(k6, /repeated/);
  assert.match(k6, /unique/);
  assert.match(k6, /http_req_duration/);
  assert.match(k6, /http_req_failed/);
  assert.match(k6, /new Counter\("train_search_5xx"\)/);
  assert.match(k6, /fiveXxCount = data\.metrics\.train_search_5xx/);
  assert.doesNotMatch(k6, /http_req_failed\?\.values\?\.passes/);
  assert.match(k6, /requestCount > 0/);
  assert.match(runner, /--nodes 3/);
  assert.match(runner, /--max-duration-seconds/);
  assert.match(runner, /providerCallCount/);
  assert.match(runner, /quotaVerdict/);
  assert.match(runner, /validate-train-search-capacity\.mjs/);
  assert.doesNotMatch(runner, /source .*\.env|curl|jq|sed|awk|grep/);
});

test("#2094 release artifact는 동일 candidate와 모든 완료 증거를 요구한다", () => {
  const gate = readJson("apps/mobile/release/train-search-itx-exclusion-gate.json");
  const runtime = gate.issue2094RuntimeEvidence;

  assert.equal(gate.runtimeImplementationStatus, "SATISFIED_BY_2094");
  assert.equal(gate.issue2094RoadmapRequiredForThisGate, true);
  assert.match(runtime.candidateGitSha, /^[0-9a-f]{40}$/);
  assert.equal(runtime.backend.deployedGitSha, runtime.candidateGitSha);
  assert.equal(runtime.android.artifactGitSha, runtime.candidateGitSha);
  assert.equal(runtime.provider.httpSuccess, true);
  assert.equal(runtime.provider.resultCode, "00");
  assert.equal(runtime.provider.schemaStatus, "EXPECTED");
  assert.deepEqual(runtime.provider.operations, [
    "GetCtyCodeList",
    "GetCtyAcctoTrainSttnList",
    "GetVhcleKndList",
    "GetStrtpntAlocFndTrainInfo",
  ]);
  assert.deepEqual(runtime.provider.supportedTrainTypes, supportedTrainTypes);
  assert.equal(runtime.backend.seoulDaejeonKtxFareRows > 0, true);
  assert.equal(runtime.backend.itxCheongchunRows, 0);
  assert.equal(runtime.capacity.repeated.status, "PASS");
  assert.equal(runtime.capacity.unique.status, "PASS");
  assert.equal(runtime.capacity.threeNodeSingleFlight.status, "PASS");
  assert.equal(runtime.capacity.threeNodeSingleFlight.providerCallCount, 1);
  assert.equal(runtime.capacity.quotaVerdict, "PASS");
  assert.equal(runtime.android.menuToResultPassed, true);
  assert.equal(runtime.android.roundTripPassed, true);
  assert.equal(runtime.android.stateMatrixPassed, true);
  assert.equal(runtime.android.offlineUnavailablePassed, true);
  assert.equal(runtime.android.subwayRegressionPassed, true);
  assert.match(runtime.android.screenshotSha256, /^[0-9a-f]{64}$/);
  assert.match(runtime.android.semanticsSha256, /^[0-9a-f]{64}$/);
  assert.equal(runtime.review.actionableFindingsOpen, 0);
  assert.equal(runtime.requiredCi.status, "PASS");
});
