import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  addProviderStation,
  normalizeProviderTrainType,
  providerJourney,
  validateBackendSearchEnvelope,
  validateDeploymentRun,
  validateProviderEnvelope,
} from "../test/train-search-live-smoke.mjs";
import {
  buildBackendObservation,
  validateBackendObservationArtifact,
} from "../test/collect-train-search-backend-observation.mjs";

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
    departureDate: "2026-07-20",
  });

  assert.equal(evidence.rowCount, 1);
  assert.equal(evidence.fareRowCount, 1);
  assert.equal(evidence.itxCheongchunRowCount, 0);
  assert.throws(
    () => validateBackendSearchEnvelope({
      success: true,
      data: {
        observedAt: "2026-07-19T06:00:00Z",
        outbound: [{
          trainNumber: "101",
          trainType: "KTX",
          departureStationId: "NAT010000",
          departureStationName: "서울",
          departureAt: "2026-07-22T09:00:00+09:00",
          arrivalStationId: "NAT011668",
          arrivalStationName: "대전",
          arrivalAt: "2026-07-22T10:02:00+09:00",
          durationMinutes: 62,
          adultFareWon: 23700,
        }],
        inbound: [],
      },
    }, {
      departureStationId: "NAT010000",
      arrivalStationId: "NAT011668",
      trainType: "KTX",
      departureDate: "2026-07-20",
    }),
    /backend outbound row did not match the requested leg/,
  );
  for (const data of [
    {
      observedAt: "2026-07-19",
      outbound: [],
      inbound: [],
    },
    {
      observedAt: "2026-07-19T06:00:00Z",
      outbound: [],
      inbound: [{
        trainNumber: "102",
        trainType: "KTX",
        departureStationId: "NAT011668",
        departureStationName: "대전",
        departureAt: "2026-07-20T11:00:00+09:00",
        arrivalStationId: "NAT010000",
        arrivalStationName: "서울",
        arrivalAt: "2026-07-20T12:02:00+09:00",
        durationMinutes: 62,
        adultFareWon: 23700,
      }],
    },
  ]) {
    assert.throws(
      () => validateBackendSearchEnvelope({ success: true, data }, {
        departureStationId: "NAT010000",
        arrivalStationId: "NAT011668",
        trainType: "KTX",
        departureDate: "2026-07-20",
      }),
      /backend train search result schema was invalid/,
    );
  }
});

test("TAGO station catalog는 동일 ID의 상이한 이름을 거부한다", () => {
  const stations = new Map();
  addProviderStation(stations, "NAT010000", "서울");
  assert.throws(
    () => addProviderStation(stations, "NAT010000", "서울역"),
    /station ID conflict/,
  );
});

test("TAGO 운임 행은 요청한 서울→대전 OD와 날짜가 정확히 일치해야 한다", () => {
  const row = {
    trainno: "101",
    traingradename: "KTX",
    depplandtime: "20260720090000",
    arrplandtime: "20260720100200",
    depplacename: "서울",
    arrplacename: "대전",
    adultcharge: "23700",
  };
  assert.equal(providerJourney(row, 0, {
    departureStationId: "NAT010000",
    departureStationName: "서울",
    arrivalStationId: "NAT011668",
    arrivalStationName: "대전",
    departureDate: "2026-07-20",
  }).adultFareWon, 23700);
  assert.throws(
    () => providerJourney({ ...row, arrplacename: "동대구" }, 0, {
      departureStationId: "NAT010000",
      departureStationName: "서울",
      arrivalStationId: "NAT011668",
      arrivalStationName: "대전",
      departureDate: "2026-07-20",
    }),
    /provider journey OD or date mismatch/,
  );
  assert.throws(
    () => providerJourney({ ...row, depplandtime: "20260721090000", arrplandtime: "20260721100200" }, 0, {
      departureStationId: "NAT010000",
      departureStationName: "서울",
      arrivalStationId: "NAT011668",
      arrivalStationName: "대전",
      departureDate: "2026-07-20",
    }),
    /provider journey OD or date mismatch/,
  );
});

test("배포 workflow run은 성공한 CD SHA와 필수 job을 독립 검증한다", () => {
  const deploymentRunUrl = "https://github.com/AquilaXk/easysubway/actions/runs/29677130333";
  const candidateGitSha = "d36bc00467ab69732f49e1f56a343bb2da1e73ce";
  const run = {
    id: 29677130333,
    name: "CD",
    head_sha: candidateGitSha,
    status: "completed",
    conclusion: "success",
    html_url: deploymentRunUrl,
    repository: { full_name: "AquilaXk/easysubway" },
  };
  const jobs = { jobs: [
    { name: "CD Deploy", conclusion: "success" },
    { name: "Post-deploy smoke", conclusion: "success" },
    { name: "CD Record deployment", conclusion: "success" },
  ] };
  assert.equal(validateDeploymentRun(run, jobs, { candidateGitSha, deploymentRunUrl }).deployedGitSha,
    candidateGitSha);
  assert.throws(
    () => validateDeploymentRun({ ...run, head_sha: "a".repeat(40) }, jobs, {
      candidateGitSha,
      deploymentRunUrl,
    }),
    /deployment workflow run did not match/,
  );
  assert.throws(
    () => validateDeploymentRun(run, { jobs: jobs.jobs.slice(0, 1) }, {
      candidateGitSha,
      deploymentRunUrl,
    }),
    /deployment workflow jobs were incomplete/,
  );
});

test("backend test XML에서 3-node provider 1회와 quota fail-closed를 계산한다", () => {
  const suite = (name, tests) => [
    '<?xml version="1.0" encoding="UTF-8"?>',
    `<testsuite name="${name}" tests="${tests.length}" skipped="0" failures="0" errors="0">`,
    ...tests.map((testName) => `<testcase name="${testName}()" classname="${name}" time="0.1"/>`),
    "</testsuite>",
  ].join("\n");
  const observation = buildBackendObservation([
    {
      path: "TEST-com.easysubway.train.application.TrainSearchServiceTest.xml",
      content: suite("com.easysubway.train.application.TrainSearchServiceTest", [
        "threeNodesShareOneProviderCallThroughTheDatabaseLease",
      ]),
    },
    {
      path: "TEST-com.easysubway.train.adapter.out.persistence.JdbcTrainSearchCacheTest.xml",
      content: suite("com.easysubway.train.adapter.out.persistence.JdbcTrainSearchCacheTest", [
        "enforcesSharedMinuteAndDayQuotaPerProvider",
      ]),
    },
    {
      path: "TEST-com.easysubway.train.adapter.out.http.SharedTrainSearchProviderCallBudgetTest.xml",
      content: suite("com.easysubway.train.adapter.out.http.SharedTrainSearchProviderCallBudgetTest", [
        "quotaRejectionFailsClosedAsUnavailable",
        "quotaPersistenceFailureFailsClosedAsUnavailable",
        "quotaTransactionBoundaryFailureFailsClosedAsUnavailable",
      ]),
    },
  ]);
  assert.equal(observation.status, "PASS");
  assert.equal(observation.nodeCount, 3);
  assert.equal(observation.providerCallCount, 1);
  assert.equal(observation.quotaVerdict, "PASS");
  assert.throws(
    () => buildBackendObservation([{
      path: "TEST-broken.xml",
      content: '<testsuite name="broken" tests="1" skipped="0" failures="1" errors="0"/>',
    }]),
    /backend observation test suite failed/,
  );
});

test("capacity runner는 repeated·unique·3-node·quota 경계를 고정한다", () => {
  const k6 = read("tools/test/train-search-capacity.k6.js");
  const runner = read("tools/test/run-train-search-capacity.sh");

  assert.match(k6, /TRAIN_SEARCH_WORKLOAD/);
  assert.match(k6, /repeated/);
  assert.match(k6, /unique/);
  assert.match(k6, /iterationInTest/);
  assert.doesNotMatch(k6, /__ITER/);
  assert.match(k6, /http_req_duration/);
  assert.match(k6, /http_req_failed/);
  assert.match(k6, /new Counter\("train_search_5xx"\)/);
  assert.match(k6, /new Counter\("train_search_4xx"\)/);
  assert.match(k6, /new Counter\("train_search_429"\)/);
  assert.match(k6, /dropped_iterations/);
  assert.match(k6, /expectedRequestCount/);
  assert.match(k6, /fiveXxCount = data\.metrics\.train_search_5xx/);
  assert.match(k6, /timeUnit: "2s"/);
  assert.doesNotMatch(k6, /http_req_failed\?\.values\?\.passes/);
  assert.match(k6, /requestCount >= expectedRequestCount/);
  assert.match(runner, /--nodes 3/);
  assert.match(runner, /--max-duration-seconds/);
  assert.match(runner, /collect-train-search-backend-observation\.mjs/);
  assert.doesNotMatch(runner, /--provider-call-count|--quota-verdict/);
  assert.doesNotMatch(k6, /TRAIN_SEARCH_PROVIDER_CALL_COUNT|TRAIN_SEARCH_QUOTA_VERDICT/);
  assert.match(runner, /validate-train-search-capacity\.mjs/);
  assert.doesNotMatch(runner, /source .*\.env|curl|jq|sed|awk|grep/);
  for (const baseUrl of ["https://localhost", "https://127.0.0.1", "https://10.0.0.1"]) {
    const result = spawnSync("bash", [
      "tools/test/run-train-search-capacity.sh",
      "--base-url",
      baseUrl,
    ], { encoding: "utf8" });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /public EasySubway production HTTPS origin/);
  }
});

test("#2094 release artifact는 동일 candidate와 모든 완료 증거를 요구한다", () => {
  const gate = readJson("apps/mobile/release/train-search-itx-exclusion-gate.json");
  const runtime = gate.issue2094RuntimeEvidence;

  assert.equal(gate.runtimeImplementationStatus, "SATISFIED_BY_2094");
  assert.equal(gate.issue2094RoadmapRequiredForThisGate, true);
  assert.match(runtime.candidateGitSha, /^[0-9a-f]{40}$/);
  assert.equal(runtime.backend.deployedGitSha, runtime.candidateGitSha);
  assert.equal(runtime.backend.deployment.deployedGitSha, runtime.candidateGitSha);
  assert.equal(runtime.backend.deployment.conclusion, "success");
  assert.deepEqual(runtime.backend.deployment.requiredJobs, [
    "CD Deploy",
    "Post-deploy smoke",
    "CD Record deployment",
  ]);
  assert.equal(runtime.android.artifactGitSha, runtime.candidateGitSha);
  assert.equal(runtime.provider.httpSuccess, true);
  assert.equal(runtime.provider.resultCode, "00");
  assert.equal(runtime.provider.schemaStatus, "EXPECTED");
  assert.equal(runtime.provider.stationConflictCount, 0);
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
  for (const workload of [runtime.capacity.repeated, runtime.capacity.unique]) {
    assert.equal(workload.failureRate, 0);
    assert.equal(workload.fiveXxCount, 0);
    assert.equal(workload.fourXxCount, 0);
    assert.equal(workload.rateLimitedCount, 0);
    assert.equal(workload.droppedIterationCount, 0);
    assert.equal(workload.requestCount >= workload.expectedRequestCount, true);
  }
  assert.equal(runtime.capacity.executor.k6Version, "1.5.0");
  assert.match(runtime.capacity.executor.imageDigest, /^sha256:[0-9a-f]{64}$/);
  validateBackendObservationArtifact(runtime.capacity.backendObservation);
  assert.equal(runtime.android.menuToResultPassed, true);
  assert.equal(runtime.android.roundTripPassed, true);
  assert.equal(runtime.android.stateMatrixPassed, true);
  assert.equal(runtime.android.offlineUnavailablePassed, true);
  assert.equal(runtime.android.subwayRegressionPassed, true);
  assert.equal(runtime.android.networkBoundary, "OCI_STAGING_CONNECT_PROXY");
  assert.match(runtime.android.candidateApkSha256, /^[0-9a-f]{64}$/);
  assert.match(runtime.android.integrationTestSourceSha256, /^[0-9a-f]{64}$/);
  assert.match(runtime.android.screenshotSha256, /^[0-9a-f]{64}$/);
  assert.match(runtime.android.semanticsSha256, /^[0-9a-f]{64}$/);
  assert.equal(runtime.review.actionableFindingsOpen, 0);
  assert.equal(runtime.requiredCi.status, "PASS");
});
