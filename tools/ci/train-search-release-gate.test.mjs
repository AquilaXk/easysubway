import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import * as trainSearchLiveSmoke from "../test/train-search-live-smoke.mjs";

import {
  addProviderStation,
  collectBackendEvidence,
  collectProviderEvidence,
  normalizeProviderTrainType,
  providerJourney,
  validateBackendSearchEnvelope,
  validateBackendObservationTime,
  validateCurrentProductionDeployment,
  validateDeploymentRun,
  validateKtxProviderJourneys,
  validateProviderEnvelope,
} from "../test/train-search-live-smoke.mjs";
import {
  buildBackendObservation,
  validateBackendObservationArtifact,
} from "../test/collect-train-search-backend-observation.mjs";

const read = (file) => readFileSync(file, "utf8");
const readJson = (file) => JSON.parse(read(file));
const sha256 = (value) => createHash("sha256").update(value).digest("hex");

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
  for (const invalidCount of [null, "", false]) {
    assert.throws(
      () => validateProviderEnvelope({
        response: {
          header: { resultCode: "00" },
          body: { items: { item: [] }, pageNo: 1, numOfRows: 100, totalCount: invalidCount },
        },
      }, { operation: "GetVhcleKndList", paginated: true, pageNo: 1, pageSize: 100 }),
      /was not an integer/,
    );
  }
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
          trainNumber: "ITX-1",
          trainType: "ITX_CHEONGCHUN",
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
    }),
    /backend train search returned ITX_CHEONGCHUN rows/,
  );
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

test("backend live evidence는 API observedAt을 보존하고 stale 응답을 거부한다", () => {
  assert.deepEqual(
    validateBackendObservationTime(
      "2026-07-19T06:00:00Z",
      "2026-07-19",
      new Date("2026-07-19T06:04:00Z"),
    ),
    {
      observedAt: "2026-07-19T06:00:00Z",
      collectedAt: "2026-07-19T06:04:00.000Z",
    },
  );
  assert.throws(
    () => validateBackendObservationTime(
      "2026-07-19T06:00:00Z",
      "2026-07-19",
      new Date("2026-07-19T06:11:00Z"),
    ),
    /backend observation was stale/,
  );
  assert.throws(
    () => validateBackendObservationTime(
      "2026-07-19T06:00:00Z",
      "2026-07-20",
      new Date("2026-07-19T06:04:00Z"),
      "2026-07-19T06:01:00Z",
    ),
    /predated the candidate deployment/,
  );
});

test("backend freshness 시각은 search 응답을 수집한 뒤 결정한다", () => {
  const source = read("tools/test/train-search-live-smoke.mjs");
  const backendSource = source.slice(
    source.indexOf("export async function collectBackendEvidence"),
    source.indexOf("export function validateKtxProviderJourneys"),
  );
  assert.doesNotMatch(backendSource, /now = new Date\(\)/);
  assert.ok(
    source.indexOf("const collectedAt = now === undefined ? new Date() : now;")
      > source.indexOf("validateBackendSearchEnvelope(await responseJson(first"),
  );
  assert.match(source, /validateBackendObservationTime\([\s\S]*?collectedAt,/);
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
  for (const invalidFare of [null, "", false, true]) {
    assert.throws(
      () => providerJourney({ ...row, adultcharge: invalidFare }, 0, {
        departureStationId: "NAT010000",
        departureStationName: "서울",
        arrivalStationId: "NAT011668",
        arrivalStationName: "대전",
        departureDate: "2026-07-20",
      }),
      /was not an integer/,
    );
  }
  for (const invalidTime of ["20260720250000", "20260230090000"]) {
    assert.throws(
      () => providerJourney({
        trainno: "101",
        traingradename: "KTX",
        depplandtime: invalidTime,
        arrplandtime: "20260721100000",
        depplacename: "서울",
        arrplacename: "대전",
        adultcharge: 23700,
      }, 0, {
        departureStationId: "NAT010000",
        departureStationName: "서울",
        arrivalStationId: "NAT011668",
        arrivalStationName: "대전",
        departureDate: "2026-07-20",
      }),
      /time was invalid/,
    );
  }
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

test("TAGO KTX grade 응답은 모든 행이 KTX여야 한다", () => {
  assert.doesNotThrow(() => validateKtxProviderJourneys([{ trainType: "KTX" }]));
  assert.throws(
    () => validateKtxProviderJourneys([{ trainType: "KTX" }, { trainType: "SRT" }]),
    /non-KTX row/,
  );
});

test("TAGO exclusion 증거는 ITX_CHEONGCHUN grade를 직접 조회한다", async () => {
  const scheduleGradeCodes = [];
  const grades = [
    ["00", "KTX"],
    ["10", "KTX-산천"],
    ["17", "SRT"],
    ["18", "ITX-마음"],
    ["01", "ITX-새마을"],
    ["05", "새마을호"],
    ["06", "무궁화호"],
    ["08", "누리로"],
    ["09", "ITX-청춘"],
  ].map(([vehiclekndid, vehiclekndnm]) => ({ vehiclekndid, vehiclekndnm }));
  const fetchImpl = async (input) => {
    const url = new URL(input);
    const operation = url.pathname.split("/").at(-1);
    let rows;
    if (operation === "GetVhcleKndList") rows = grades;
    else if (operation === "GetCtyCodeList") rows = [{ citycode: "11", cityname: "전국" }];
    else if (operation === "GetCtyAcctoTrainSttnList") {
      rows = [
        { nodeid: "NAT010000", nodename: "서울" },
        { nodeid: "NAT011668", nodename: "대전" },
      ];
    } else if (operation === "GetStrtpntAlocFndTrainInfo") {
      const gradeCode = url.searchParams.get("trainGradeCode");
      scheduleGradeCodes.push(gradeCode);
      rows = gradeCode === "00" ? [{
        trainno: "101",
        traingradename: "KTX",
        depplandtime: "20260815090000",
        arrplandtime: "20260815100200",
        depplacename: "서울",
        arrplacename: "대전",
        adultcharge: "23700",
      }] : [];
    } else {
      throw new Error(`unexpected operation: ${operation}`);
    }
    const paginated = operation === "GetCtyAcctoTrainSttnList"
      || operation === "GetStrtpntAlocFndTrainInfo";
    return new Response(JSON.stringify({
      response: {
        header: { resultCode: "00" },
        body: {
          items: { item: rows },
          ...(paginated ? {
            pageNo: Number(url.searchParams.get("pageNo")),
            numOfRows: Number(url.searchParams.get("numOfRows")),
            totalCount: rows.length,
          } : {}),
        },
      },
    }), { status: 200 });
  };

  const evidence = await collectProviderEvidence({
    serviceKey: "test-key",
    departureDate: "2026-08-15",
    departureStationId: "NAT010000",
    arrivalStationId: "NAT011668",
    fetchImpl,
    now: new Date("2026-07-19T12:00:00Z"),
  });

  assert.deepEqual(scheduleGradeCodes.sort(), ["00", "09"]);
  assert.deepEqual(evidence.queriedTrainGradeCodes, {
    KTX: ["00"],
    ITX_CHEONGCHUN: ["09"],
  });
  assert.equal(evidence.itxCheongchunRowCount, 0);
  assert.equal(evidence.fareRowCount, 1);
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

test("필수 CI workflow run은 candidate SHA와 required job 성공에 결속된다", () => {
  const validateRequiredCiRun = trainSearchLiveSmoke.validateRequiredCiRun;
  assert.equal(typeof validateRequiredCiRun, "function");
  const candidateGitSha = "d36bc00467ab69732f49e1f56a343bb2da1e73ce";
  const ciRunUrl = "https://github.com/AquilaXk/easysubway/actions/runs/29677947876";
  const run = {
    id: 29677947876,
    name: "CI",
    head_sha: candidateGitSha,
    status: "completed",
    conclusion: "success",
    event: "push",
    html_url: ciRunUrl,
    repository: { full_name: "AquilaXk/easysubway" },
  };
  const requiredJobs = [
    "Repository CI",
    "Android CI",
    "Release Gate Consistency",
    "Mobile App CI",
    "Backend CI",
    "Admin QA Gates",
  ];
  const jobs = { jobs: requiredJobs.map((name) => ({ name, conclusion: "success" })) };

  assert.deepEqual(validateRequiredCiRun(run, jobs, { candidateGitSha, ciRunUrl }), {
    runId: 29677947876,
    runUrl: ciRunUrl,
    workflowName: "CI",
    candidateGitSha,
    conclusion: "success",
    requiredJobs,
  });
  assert.throws(
    () => validateRequiredCiRun({ ...run, head_sha: "a".repeat(40) }, jobs, { candidateGitSha, ciRunUrl }),
    /CI workflow run did not match the candidate/,
  );
  assert.throws(
    () => validateRequiredCiRun(run, { jobs: jobs.jobs.slice(1) }, { candidateGitSha, ciRunUrl }),
    /CI workflow jobs were incomplete/,
  );
});

test("backend live evidence는 최신 production environment deployment를 candidate에 바인딩한다", () => {
  const candidateGitSha = "d36bc00467ab69732f49e1f56a343bb2da1e73ce";
  const deployments = [{
    id: 123,
    sha: candidateGitSha,
    ref: "main",
    environment: "production",
    created_at: "2026-07-19T06:53:34Z",
  }];
  const statuses = [{
    id: 456,
    state: "success",
    environment_url: "https://easysubway-api.aquilaxk.site",
    created_at: "2026-07-19T07:00:00Z",
  }];
  assert.deepEqual(validateCurrentProductionDeployment(deployments, statuses, candidateGitSha), {
    deploymentId: 123,
    statusId: 456,
    sha: candidateGitSha,
    createdAt: "2026-07-19T06:53:34Z",
    succeededAt: "2026-07-19T07:00:00Z",
  });
  assert.throws(
    () => validateCurrentProductionDeployment(deployments, statuses, "b".repeat(40)),
    /current production deployment did not match/,
  );
});

test("backend test XML에서 3-node provider 1회와 quota fail-closed를 계산한다", () => {
  const suite = (name, tests) => [
    '<?xml version="1.0" encoding="UTF-8"?>',
    `<testsuite name="${name}" tests="${tests.length}" skipped="0" failures="0" errors="0">`,
    ...tests.map((testName) => `<testcase name="${testName}()" classname="${name}" time="0.1"/>`),
    "</testsuite>",
  ].join("\n");
  const metadata = {
    candidateGitSha: "a".repeat(40),
    runtimeSourceGitSha: "a".repeat(40),
    runtimeSourceMatchesCandidate: true,
    apiOrigin: "https://easysubway-api.aquilaxk.site",
    collectedAt: "2026-07-19T12:00:00.000Z",
  };
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
        "concurrentLeaseAttemptsHaveExactlyOneOwner",
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
  ], metadata);
  assert.equal(observation.status, "PASS");
  assert.equal(observation.threeNodeSingleProviderCallVerifiedByTest, true);
  assert.equal(observation.quotaFailClosedVerifiedByTests, true);
  assert.equal("nodeCount" in observation, false);
  assert.equal("providerCallCount" in observation, false);
  assert.equal("quotaVerdict" in observation, false);
  assert.ok(observation.requiredTests.includes(
    "com.easysubway.train.adapter.out.persistence.JdbcTrainSearchCacheTest#concurrentLeaseAttemptsHaveExactlyOneOwner",
  ));
  assert.throws(
    () => buildBackendObservation([{
      path: "TEST-broken.xml",
      content: '<testsuite name="broken" tests="1" skipped="0" failures="1" errors="0"/>',
    }], metadata),
    /backend observation test suite failed/,
  );
});

test("live evidence는 EasySubway production API origin만 허용한다", async () => {
  const android = read("apps/mobile/integration_test/train_search_release_evidence_test.dart");
  assert.match(android, /Uri _requireProductionBaseUri\(\)/);
  assert.equal((android.match(/_requireProductionBaseUri\(\)/g) ?? []).length, 3);
  await assert.rejects(
    collectBackendEvidence({
      baseUrl: "https://api.example.com/",
      candidateGitSha: "a".repeat(40),
      deploymentRunUrl: "https://github.com/AquilaXk/easysubway/actions/runs/1",
      departureDate: "2026-07-20",
      fetchImpl: async () => { throw new Error("fetch must not run"); },
    }),
    /EasySubway production HTTPS origin/,
  );
});

test("존재하지 않는 달력 날짜는 external fetch 전에 거부한다", async () => {
  let fetchCalls = 0;
  await assert.rejects(
    collectBackendEvidence({
      baseUrl: "https://easysubway-api.aquilaxk.site/",
      candidateGitSha: "a".repeat(40),
      deploymentRunUrl: "https://github.com/AquilaXk/easysubway/actions/runs/1",
      departureDate: "2026-02-30",
      fetchImpl: async () => {
        fetchCalls += 1;
        throw new Error("fetch must not run");
      },
    }),
    /--date must be YYYY-MM-DD/,
  );
  assert.equal(fetchCalls, 0);

  const cli = spawnSync(process.execPath, [
    "tools/test/train-search-live-smoke.mjs",
    "--validate-date", "2026-02-30",
  ], { encoding: "utf8" });
  assert.notEqual(cli.status, 0);
  assert.match(cli.stderr, /--date must be YYYY-MM-DD/);
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
  assert.match(k6, /const ARRIVAL_INTERVAL_SECONDS = 2;/);
  assert.match(
    k6,
    /expectedRequestCount = Math\.floor\(\(rate \* durationSeconds\) \/ ARRIVAL_INTERVAL_SECONDS\)/,
  );
  assert.match(k6, /timeUnit: `\$\{ARRIVAL_INTERVAL_SECONDS\}s`/);
  assert.doesNotMatch(k6, /http_req_failed\?\.values\?\.passes/);
  assert.match(k6, /requestCount >= expectedRequestCount/);
  assert.match(k6, /Array\.isArray\(payload\.data\.inbound\)/);
  assert.match(k6, /TRAIN_SEARCH_SUMMARY_PATH is required/);
  assert.match(k6, /TRAIN_SEARCH_CANDIDATE_SHA must be a full lowercase Git SHA/);
  assert.match(k6, /candidateGitSha,/);
  assert.match(k6, /apiOrigin,/);
  assert.match(k6, /departureStationId,/);
  assert.match(k6, /arrivalStationId,/);
  assert.match(k6, /departureDate,/);
  assert.match(k6, /collectedAt: new Date\(\)\.toISOString\(\)/);
  assert.match(runner, /--nodes 3/);
  assert.match(runner, /--max-duration-seconds/);
  assert.match(runner, /collect-train-search-backend-observation\.mjs/);
  assert.doesNotMatch(runner, /--provider-call-count|--quota-verdict/);
  assert.doesNotMatch(k6, /TRAIN_SEARCH_PROVIDER_CALL_COUNT|TRAIN_SEARCH_QUOTA_VERDICT/);
  const serviceTest = read("backend/src/test/java/com/easysubway/train/application/TrainSearchServiceTest.java");
  assert.match(serviceTest, /Executors\.newFixedThreadPool\(2\)/);
  assert.match(serviceTest, /Executors\.newFixedThreadPool\(3\)/);
  assert.match(serviceTest, /pool\.shutdownNow\(\)/);
  assert.match(runner, /validate-train-search-capacity\.mjs/);
  assert.match(runner, /--preflight-output-dir/);
  assert.match(runner, /--candidate-sha/);
  assert.match(runner, /--deployment-run-url/);
  assert.match(runner, /--ci-run-url/);
  assert.match(runner, /--departure-id "\$\{departure_id\}"/);
  assert.match(runner, /--arrival-id "\$\{arrival_id\}"/);
  assert.match(runner, /--date "\$\{departure_date\}"/);
  assert.ok(runner.indexOf("--validate-date") < runner.indexOf("--mode backend"));
  assert.match(runner, /train-search-live-smoke\.mjs/);
  assert.match(runner, /candidate-binding\.json/);
  const collector = read("tools/test/collect-train-search-backend-observation.mjs");
  assert.match(collector, /git", \["diff", "--quiet", candidateGitSha/);
  assert.doesNotMatch(runner, /source .*\.env|curl|jq|sed|awk|grep/);
  const unsafeEvidence = spawnSync(process.execPath, [
    "tools/test/validate-train-search-capacity.mjs",
    "--candidate-sha",
    "a".repeat(40),
    "--api-origin",
    "https://easysubway-api.aquilaxk.site",
    "--departure-id",
    "NAT010000",
    "--arrival-id",
    "NAT011668",
    "--date",
    "2026-07-20",
    "/etc/repeated.json",
    "/etc/unique.json",
    "/etc/backend-observation.json",
    "/etc/candidate-binding.json",
  ], { encoding: "utf8" });
  assert.notEqual(unsafeEvidence.status, 0);
  assert.match(unsafeEvidence.stderr, /outside the allowed roots/);
  const unsafeOutput = spawnSync("bash", [
    "tools/test/run-train-search-capacity.sh",
    "--base-url", "https://easysubway-api.aquilaxk.site",
    "--departure-id", "NAT010000",
    "--arrival-id", "NAT011668",
    "--date", "2026-08-10",
    "--output-dir", "/etc/easysubway-capacity",
    "--nodes", "3",
    "--candidate-sha", "a".repeat(40),
    "--deployment-run-url", "https://github.com/AquilaXk/easysubway/actions/runs/1",
    "--ci-run-url", "https://github.com/AquilaXk/easysubway/actions/runs/2",
  ], { encoding: "utf8" });
  assert.notEqual(unsafeOutput.status, 0);
  assert.match(unsafeOutput.stderr, /outside the allowed roots/);
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

test("capacity validator는 OD·날짜와 required CI를 fail-closed로 검증한다", () => {
  const runtime = readJson("apps/mobile/release/train-search-itx-exclusion-gate.json").issue2094RuntimeEvidence;
  const directory = mkdtempSync(path.join(tmpdir(), "train-capacity-validator-"));
  const candidateGitSha = runtime.candidateGitSha;
  const args = [
    "tools/test/validate-train-search-capacity.mjs",
    "--candidate-sha", candidateGitSha,
    "--api-origin", "https://easysubway-api.aquilaxk.site",
    "--departure-id", "NAT010000",
    "--arrival-id", "NAT011668",
    "--date", "2026-07-20",
    path.join(directory, "repeated.json"),
    path.join(directory, "unique.json"),
    path.join(directory, "backend-observation.json"),
    path.join(directory, "candidate-binding.json"),
  ];
  const write = (name, value) => writeFileSync(path.join(directory, name), `${JSON.stringify(value)}\n`);
  try {
    write("repeated.json", runtime.capacity.repeated);
    write("unique.json", runtime.capacity.unique);
    write("backend-observation.json", runtime.capacity.backendObservation);
    write("candidate-binding.json", runtime.capacity.candidateBinding);
    assert.equal(spawnSync(process.execPath, args, { encoding: "utf8" }).status, 0);

    write("repeated.json", { ...runtime.capacity.repeated, departureStationId: "NAT999999" });
    const wrongOd = spawnSync(process.execPath, args, { encoding: "utf8" });
    assert.notEqual(wrongOd.status, 0);
    assert.match(wrongOd.stderr, /repeated summary failed its evidence contract/);

    write("repeated.json", runtime.capacity.repeated);
    const binding = structuredClone(runtime.capacity.candidateBinding);
    delete binding.backend.requiredCi;
    delete binding.evidenceSha256;
    const unsigned = binding;
    binding.evidenceSha256 = sha256(JSON.stringify(unsigned));
    write("candidate-binding.json", binding);
    const missingCi = spawnSync(process.execPath, args, { encoding: "utf8" });
    assert.notEqual(missingCi.status, 0);
    assert.match(missingCi.stderr, /candidate deployment binding failed its evidence contract/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("#2094 release artifact는 동일 candidate와 모든 완료 증거를 요구한다", () => {
  const gate = readJson("apps/mobile/release/train-search-itx-exclusion-gate.json");
  const runtime = gate.issue2094RuntimeEvidence;
  const { liveEvidenceSha256, ...unsignedRuntime } = runtime;

  assert.equal(gate.runtimeImplementationStatus, "SATISFIED_BY_2094");
  assert.equal(liveEvidenceSha256, sha256(JSON.stringify(unsignedRuntime)));
  assert.equal(gate.issue2094RoadmapRequiredForThisGate, true);
  assert.match(runtime.candidateGitSha, /^[0-9a-f]{40}$/);
  assert.equal(runtime.backend.deployedGitSha, runtime.candidateGitSha);
  assert.equal(runtime.backend.apiOrigin, "https://easysubway-api.aquilaxk.site");
  assert.equal(runtime.backend.deployment.deployedGitSha, runtime.candidateGitSha);
  assert.equal(runtime.backend.deployment.conclusion, "success");
  assert.equal(runtime.backend.currentDeployment.sha, runtime.candidateGitSha);
  assert.equal(Number.isSafeInteger(runtime.backend.currentDeployment.deploymentId), true);
  assert.equal(Number.isSafeInteger(runtime.backend.currentDeployment.statusId), true);
  assert.match(runtime.backend.currentDeployment.createdAt, /^\d{4}-\d{2}-\d{2}T/);
  assert.match(runtime.backend.currentDeployment.succeededAt, /^\d{4}-\d{2}-\d{2}T/);
  assert.equal(
    Date.parse(runtime.backend.observedAt) >= Date.parse(runtime.backend.currentDeployment.succeededAt),
    true,
  );
  assert.deepEqual(runtime.backend.deployment.requiredJobs, [
    "CD Deploy",
    "Post-deploy smoke",
    "CD Record deployment",
  ]);
  assert.equal(runtime.android.artifactGitSha, runtime.candidateGitSha);
  assert.equal(runtime.android.apiOrigin, "https://easysubway-api.aquilaxk.site");
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
  assert.deepEqual(runtime.provider.queriedTrainGradeCodes, {
    KTX: ["00"],
    ITX_CHEONGCHUN: ["09"],
  });
  assert.equal(runtime.backend.seoulDaejeonKtxFareRows > 0, true);
  assert.equal(runtime.backend.itxCheongchunRows, 0);
  assert.equal(runtime.capacity.repeated.status, "PASS");
  assert.equal(runtime.capacity.unique.status, "PASS");
  for (const workload of [runtime.capacity.repeated, runtime.capacity.unique]) {
    assert.equal(workload.candidateGitSha, runtime.candidateGitSha);
    assert.equal(workload.apiOrigin, runtime.backend.apiOrigin);
    assert.equal(workload.departureStationId, "NAT010000");
    assert.equal(workload.arrivalStationId, "NAT011668");
    assert.equal(workload.departureDate, "2026-07-20");
    assert.match(workload.collectedAt, /^\d{4}-\d{2}-\d{2}T/);
    assert.equal(workload.failureRate, 0);
    assert.equal(workload.fiveXxCount, 0);
    assert.equal(workload.fourXxCount, 0);
    assert.equal(workload.rateLimitedCount, 0);
    assert.equal(workload.droppedIterationCount, 0);
    assert.equal(workload.requestCount >= workload.expectedRequestCount, true);
  }
  assert.equal(runtime.capacity.executor.hostClass, "LOCAL_MACOS_ARM64");
  assert.equal(runtime.capacity.executor.k6Version, "1.5.0");
  assert.match(runtime.capacity.executor.binarySha256, /^[0-9a-f]{64}$/);
  validateBackendObservationArtifact(runtime.capacity.backendObservation);
  assert.equal(runtime.capacity.backendObservation.candidateGitSha, runtime.candidateGitSha);
  assert.equal(runtime.capacity.backendObservation.runtimeSourceGitSha, runtime.candidateGitSha);
  assert.equal(runtime.capacity.backendObservation.runtimeSourceMatchesCandidate, true);
  assert.equal(runtime.capacity.backendObservation.apiOrigin, runtime.backend.apiOrigin);
  assert.match(runtime.capacity.backendObservation.collectedAt, /^\d{4}-\d{2}-\d{2}T/);
  assert.equal(runtime.capacity.candidateBinding.candidateGitSha, runtime.candidateGitSha);
  assert.equal(runtime.capacity.candidateBinding.backend.deployedGitSha, runtime.candidateGitSha);
  assert.deepEqual(runtime.capacity.candidateBinding.backend.requiredCi, runtime.requiredCi);
  assert.equal(runtime.capacity.candidateBinding.backend.currentDeployment.sha, runtime.candidateGitSha);
  assert.equal(runtime.capacity.candidateBinding.backend.origin, runtime.backend.apiOrigin);
  const { evidenceSha256: bindingSha256, ...unsignedBinding } = runtime.capacity.candidateBinding;
  assert.equal(bindingSha256, sha256(JSON.stringify(unsignedBinding)));
  assert.equal(runtime.backend.sourceObjectSha256, bindingSha256);
  assert.equal(
    Date.parse(runtime.capacity.candidateBinding.backend.observedAt)
      >= Date.parse(runtime.capacity.candidateBinding.backend.currentDeployment.succeededAt),
    true,
  );
  assert.equal(runtime.android.menuToResultPassed, true);
  assert.equal(runtime.android.roundTripPassed, true);
  assert.equal(runtime.android.stateMatrixPassed, true);
  assert.equal(runtime.android.offlineUnavailablePassed, true);
  assert.equal(runtime.android.subwayRegressionPassed, true);
  assert.equal(runtime.android.networkBoundary, "OCI_STAGING_CONNECT_PROXY");
  assert.match(runtime.android.candidateApkSha256, /^[0-9a-f]{64}$/);
  assert.match(runtime.android.integrationTestSourceSha256, /^[0-9a-f]{64}$/);
  assert.equal(
    runtime.android.integrationTestSourceSha256,
    sha256(read("apps/mobile/integration_test/train_search_release_evidence_test.dart")),
  );
  assert.match(runtime.android.screenshotSha256, /^[0-9a-f]{64}$/);
  assert.match(runtime.android.semanticsSha256, /^[0-9a-f]{64}$/);
  assert.equal(runtime.review.actionableFindingsOpen, 0);
  assert.equal(runtime.review.candidatePullRequest, 2291);
  assert.equal(runtime.review.candidateMergeGitSha, runtime.candidateGitSha);
  assert.match(runtime.review.reviewedHeadGitSha, /^[0-9a-f]{40}$/);
  assert.equal(
    runtime.review.reviewUrl,
    "https://github.com/AquilaXk/easysubway/pull/2291#pullrequestreview-4730310729",
  );
  assert.equal(runtime.requiredCi.candidateGitSha, runtime.candidateGitSha);
  assert.deepEqual(runtime.backend.requiredCi, runtime.requiredCi);
  assert.equal(runtime.requiredCi.workflowName, "CI");
  assert.equal(runtime.requiredCi.conclusion, "success");
  assert.deepEqual(runtime.requiredCi.requiredJobs, [
    "Repository CI",
    "Android CI",
    "Release Gate Consistency",
    "Mobile App CI",
    "Backend CI",
    "Admin QA Gates",
  ]);
});
