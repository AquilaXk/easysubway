import assert from "node:assert/strict";
import { test } from "node:test";
import {
  assertCompleteCollection,
  buildCollectionContext,
  credentialFreeRawArchiveRows,
  fetchWithRetry,
  summarizeCollectionFailures,
  successfulKricRows,
} from "./collect-kric-line4-timetables.mjs";
import { normalizeKricSubwayTimetable } from "./normalize-kric-timetable.mjs";
import { reconstructTransitTrips } from "./reconstruct-transit-trips.mjs";

const ROSTER = {
  lnCd: "4",
  stations: [
    { stinConsOrdr: 28, stinCd: "433", railOprIsttCd: "S1", stinNm: "사당" },
    { stinConsOrdr: 29, stinCd: "434", railOprIsttCd: "S1", stinNm: "남태령" },
    { stinConsOrdr: 43, stinCd: "448", railOprIsttCd: "KR", stinNm: "상록수" },
  ],
};

test("buildCollectionContext는 로스터로 재구성 코어 context를 만든다", () => {
  const ctx = buildCollectionContext(ROSTER, "seoul-4");
  assert.equal(ctx.stationIdByProviderStation["S1|4|433"], "station-seoul-4-433");
  assert.equal(ctx.stationIdByProviderStation["KR|4|448"], "station-seoul-4-448");
  assert.equal(ctx.lineIdByProviderLine["S1|4"], "seoul-4");
  assert.equal(ctx.lineIdByProviderLine["KR|4"], "seoul-4");
  assert.equal(ctx.lineSequenceByStationLine["station-seoul-4-433|seoul-4"], 28);
  assert.equal(ctx.routeIdByLineDirection["seoul-4|up"], "route-seoul-4-up");
  assert.equal(ctx.serviceIdByDayCd["8"], "weekday-kric");
});

test("KRIC 응답→context→normalizer→코어가 직결(같은 trnNo)을 온전한 trip으로 잇는다", () => {
  const ctx = buildCollectionContext(ROSTER, "seoul-4");
  // 같은 trnNo가 사당(S1 조회)·상록수(KR 조회) 응답에 각각 등장(직결)
  const sadangRows = [{ railOprIsttCd: "S1", trnNo: "4719", dayCd: "8", stinCd: "433", lnCd: "4", arvTm: "084830", dptTm: "084900" }];
  const sangnoksuRows = [{ railOprIsttCd: "KR", trnNo: "4719", dayCd: "8", stinCd: "448", lnCd: "4", arvTm: "092930", dptTm: "093000" }];
  const rows = [
    ...normalizeKricSubwayTimetable(sadangRows, ctx),
    ...normalizeKricSubwayTimetable(sangnoksuRows, ctx),
  ];
  const { transitTrips, transitStopTimes } = reconstructTransitTrips(rows, ctx);
  assert.equal(transitTrips.length, 1);
  assert.equal(transitStopTimes.length, 2); // 사당 + 상록수 한 trip으로 연결
  assert.equal(transitTrips[0].serviceId, "weekday-kric");
});

test("KRIC raw archive는 문서화된 provider 필드만 보존한다", () => {
  const rows = credentialFreeRawArchiveRows([
    {
      railOprIsttCd: "S1",
      trnNo: "4719",
      dayCd: "8",
      dayNm: "평일",
      stinCd: "433",
      lnCd: "4",
      arvTm: "084830",
      dptTm: "084900",
      exptCd: "0",
      serviceKey: "must-not-be-archived",
      undocumented: "must-not-be-archived",
    },
  ]);

  assert.deepEqual(rows, [
    {
      railOprIsttCd: "S1",
      trnNo: "4719",
      dayCd: "8",
      dayNm: "평일",
      stinCd: "433",
      lnCd: "4",
      arvTm: "084830",
      dptTm: "084900",
      exptCd: "0",
    },
  ]);
});

test("KRIC provider 오류 응답은 빈 성공 데이터로 취급하지 않는다", () => {
  assert.throws(
    () => successfulKricRows({ header: { resultCode: "30", resultMsg: "등록되지 않은 서비스키입니다." } }),
    /resultCode=30/,
  );
});

test("KRIC 요청 실패가 하나라도 있으면 수집 완료로 처리하지 않는다", () => {
  assert.throws(() => assertCompleteCollection(1, 153), /KRIC collection incomplete: 1\/153 requests failed/);
  assert.doesNotThrow(() => assertCompleteCollection(0, 153));
});

test("KRIC 실패 진단은 sanitized 원인별 개수와 요청 표본만 요약한다", () => {
  assert.deepEqual(
    summarizeCollectionFailures([
      { requestKey: "S1:4:433:7:express", error: "KRIC provider failure: resultCode=20, resultMsg=NO DATA" },
      { requestKey: "S1:4:433:7:local", error: "KRIC provider failure: resultCode=20, resultMsg=NO DATA" },
      { requestKey: "KR:4:448:8:local", error: "KRIC provider failure: resultCode=30, resultMsg=[KEY]" },
      { requestKey: "KR:4:448:9:local", resultCode: "00", rows: 1 },
    ]),
    {
      failedRequestCount: 3,
      failures: [
        {
          error: "KRIC provider failure: resultCode=20, resultMsg=NO DATA",
          count: 2,
          sampleRequestKeys: ["S1:4:433:7:express", "S1:4:433:7:local"],
        },
        {
          error: "KRIC provider failure: resultCode=30, resultMsg=[KEY]",
          count: 1,
          sampleRequestKeys: ["KR:4:448:8:local"],
        },
      ],
    },
  );
});

test("KRIC 수집 요청은 timeout 뒤 bounded retry로 중단한다", async () => {
  let attempts = 0;
  const stalledFetch = (_url, { signal }) => {
    attempts += 1;
    return new Promise((resolve, reject) => {
      signal.addEventListener("abort", () => reject(signal.reason), { once: true });
    });
  };

  await assert.rejects(
    fetchWithRetry("https://openapi.kric.go.kr/test", 2, stalledFetch, 1, 0),
    /timeout|aborted/i,
  );
  assert.equal(attempts, 2);
});
