import assert from "node:assert/strict";
import { access, mkdtemp, readFile, rm, stat } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import * as fareProbe from "./probe-seoul-fare-api.mjs";

const FARE_KEY = "DATA_GO_KR_SERVICE_KEY_VALUE";
const SEOUL_KEY = "SEOUL_OPENAPI_KEY_VALUE";
const requiredFareFields = [
  "childCardFare",
  "childCashFare",
  "gnrlCardFare",
  "gnrlCashFare",
  "yungCardFare",
  "yungCashFare",
];

const officialSample = {
  dptreStnCd: "0150",
  dptreStnNm: "서울역",
  arvlStnCd: "0151",
  arvlStnNm: "시청",
  gnrlCardFare: 1550,
  gnrlCashFare: 1650,
  yungCardFare: 900,
  yungCashFare: 1650,
  childCardFare: 550,
  childCashFare: 550,
};

const catalogRows = {
  서울역: { LINE_NUM: "04호선", STATION_NM: "서울역", FR_CODE: "0150", STATION_CD: "426" },
  시청: { LINE_NUM: "01호선", STATION_NM: "시청", FR_CODE: "0151", STATION_CD: "132" },
  상록수: { LINE_NUM: "04호선", STATION_NM: "상록수", FR_CODE: "9001", STATION_CD: "8001" },
  사당: { LINE_NUM: "04호선", STATION_NM: "사당", FR_CODE: "9002", STATION_CD: "8002" },
};

const directionalFares = {
  "상록수→사당": [101, 102, 103, 104, 105, 106],
  "사당→상록수": [201, 202, 203, 204, 205, 206],
};

function catalogXml(row) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<SearchSTNBySubwayLineInfo>
  <list_total_count>1</list_total_count>
  <RESULT><CODE>INFO-000</CODE><MESSAGE>정상 처리되었습니다</MESSAGE></RESULT>
  <row>
    <LINE_NUM>${row.LINE_NUM}</LINE_NUM>
    <STATION_NM>${row.STATION_NM}</STATION_NM>
    <FR_CODE>${row.FR_CODE}</FR_CODE>
    <STATION_CD>${row.STATION_CD}</STATION_CD>
  </row>
</SearchSTNBySubwayLineInfo>`;
}

function farePayload(url, { omitField, extra = true } = {}) {
  const originName = url.searchParams.get("dptreStnNm");
  const destinationName = url.searchParams.get("arvlStnNm");
  const values = directionalFares[`${originName}→${destinationName}`];
  const item = {
    dptreStnCd: url.searchParams.get("dptreStnCd"),
    dptreStnNm: originName,
    arvlStnCd: url.searchParams.get("arvlStnCd"),
    arvlStnNm: destinationName,
    gnrlCardFare: values[0],
    gnrlCashFare: values[1],
    yungCardFare: values[2],
    yungCashFare: values[3],
    childCardFare: values[4],
    childCashFare: values[5],
    ...(extra ? { providerNotice: "documented-extra" } : {}),
  };
  delete item[omitField];
  return { response: { header: { resultCode: "00" }, body: { totalCount: 1, items: { item: [item] } } } };
}

function stationNameFromCatalogUrl(url) {
  const decodedPath = decodeURIComponent(url.pathname);
  return Object.keys(catalogRows).find((stationName) => decodedPath.includes(`/${stationName}/`));
}

function createFetch({
  rows = catalogRows,
  fareResponse,
  onCall = () => {},
} = {}) {
  return async (input) => {
    const url = new URL(input);
    if (url.hostname === "openapi.seoul.go.kr") {
      const stationName = stationNameFromCatalogUrl(url);
      onCall(`catalog:${stationName}`, url);
      return new Response(catalogXml(rows[stationName]), {
        status: 200,
        headers: { "content-type": "application/xml" },
      });
    }
    const direction = `${url.searchParams.get("dptreStnNm")}→${url.searchParams.get("arvlStnNm")}`;
    onCall(`fare:${direction}`, url);
    if (fareResponse) return fareResponse({ direction, url });
    return Response.json(farePayload(url));
  };
}

async function withOutput(run) {
  const directory = await mkdtemp(path.join(os.tmpdir(), "official-od-fare-test-"));
  const outputPath = path.join(directory, "evidence.json");
  try {
    return await run(outputPath);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

async function probe({ fetchImpl, outputPath }) {
  return fareProbe.probeOfficialOdFares({
    fareServiceKey: FARE_KEY,
    seoulOpenApiKey: SEOUL_KEY,
    outputPath,
    fetchImpl,
    retryDelayMs: 0,
    timeoutMs: 100,
  });
}

test("서울역-시청 공식 요금 응답 계약을 검증한다", () => {
  assert.doesNotThrow(() => fareProbe.validateFareSample({ ...officialSample, providerNotice: "extra" }));
  assert.throws(
    () => fareProbe.validateFareSample({ ...officialSample, yungCashFare: "1650" }),
    /yungCashFare/,
  );
  const { childCashFare: _, ...missingFare } = officialSample;
  assert.throws(() => fareProbe.validateFareSample(missingFare), /childCashFare/);
});

test("유일하게 동치인 FR_CODE로 양방향 공식 OD 증거만 기록한다", async () => {
  await withOutput(async (outputPath) => {
    const calls = [];
    const evidence = await probe({
      outputPath,
      fetchImpl: createFetch({ onCall: (kind) => calls.push(kind) }),
    });

    assert.deepEqual(calls, [
      "catalog:서울역",
      "catalog:시청",
      "catalog:상록수",
      "catalog:사당",
      "fare:상록수→사당",
      "fare:사당→상록수",
    ]);
    assert.equal(evidence.artifactKind, "official-od-fare-probe-evidence");
    assert.equal(evidence.selectedFareCodeField, "FR_CODE");
    assert.deepEqual(evidence.providerMappings.map(({ stationId, lineId, fareStationCode }) => ({
      stationId,
      lineId,
      fareStationCode,
    })), [
      { stationId: "station-sangnoksu", lineId: "seoul-4", fareStationCode: "9001" },
      { stationId: "station-sadang", lineId: "seoul-4", fareStationCode: "9002" },
    ]);
    assert.deepEqual(evidence.quotes.map(({ originStationId, destinationStationId }) =>
      `${originStationId}→${destinationStationId}`), [
      "station-sangnoksu→station-sadang",
      "station-sadang→station-sangnoksu",
    ]);
    assert.deepEqual(Object.keys(evidence.quotes[0].fares).sort(), requiredFareFields);
    assert.equal(JSON.stringify(evidence).includes("providerNotice"), false);
    assert.deepEqual(evidence.attemptCounts, { "station-sangnoksu→station-sadang": 1, "station-sadang→station-sangnoksu": 1 });

    const stored = JSON.parse(await readFile(outputPath, "utf8"));
    assert.deepEqual(stored, evidence);
    assert.equal((await stat(outputPath)).mode & 0o777, 0o600);
    assert.doesNotMatch(JSON.stringify(stored), new RegExp(`${FARE_KEY}|${SEOUL_KEY}|serviceKey|https?://`));
  });
});

test("두 catalog code가 모두 canary와 같으면 target 호출 전에 실패한다", async () => {
  await withOutput(async (outputPath) => {
    const rows = structuredClone(catalogRows);
    rows.서울역.STATION_CD = "0150";
    rows.시청.STATION_CD = "0151";
    const calls = [];

    await assert.rejects(
      () => probe({ outputPath, fetchImpl: createFetch({ rows, onCall: (kind) => calls.push(kind) }) }),
      /unique fare code field equivalence failed/,
    );
    assert.deepEqual(calls, ["catalog:서울역", "catalog:시청"]);
    await assert.rejects(access(outputPath));
  });
});

test("429와 5xx는 방향별 최대 두 번만 재시도하고 attempt count를 기록한다", async () => {
  await withOutput(async (outputPath) => {
    const attempts = new Map();
    const fetchImpl = createFetch({
      fareResponse: ({ direction, url }) => {
        const count = (attempts.get(direction) ?? 0) + 1;
        attempts.set(direction, count);
        if (count === 1) return new Response("temporary", { status: direction.startsWith("상록수") ? 429 : 503 });
        return Response.json(farePayload(url));
      },
    });

    const evidence = await probe({ outputPath, fetchImpl });
    assert.deepEqual(evidence.attemptCounts, { "station-sangnoksu→station-sadang": 2, "station-sadang→station-sangnoksu": 2 });
    assert.deepEqual(Object.fromEntries(attempts), { "상록수→사당": 2, "사당→상록수": 2 });
  });
});

test("transport failure는 한 번만 재시도한다", async () => {
  await withOutput(async (outputPath) => {
    let forwardAttempts = 0;
    const fetchImpl = createFetch({
      fareResponse: ({ direction, url }) => {
        if (direction === "상록수→사당" && ++forwardAttempts === 1) throw new Error("socket closed");
        return Response.json(farePayload(url));
      },
    });
    const evidence = await probe({ outputPath, fetchImpl });
    assert.equal(evidence.attemptCounts["station-sangnoksu→station-sadang"], 2);
    assert.equal(forwardAttempts, 2);
  });
});

test("429가 아닌 4xx는 재시도하지 않고 output을 만들지 않는다", async () => {
  await withOutput(async (outputPath) => {
    let fareAttempts = 0;
    const fetchImpl = createFetch({
      fareResponse: () => {
        fareAttempts += 1;
        return new Response("bad request", { status: 400 });
      },
    });
    await assert.rejects(() => probe({ outputPath, fetchImpl }), /fare API HTTP 400/);
    assert.equal(fareAttempts, 1);
    await assert.rejects(access(outputPath));
  });
});

test("필수 요금 필드 누락과 credential-bearing 오류를 fail closed하고 redaction한다", async () => {
  await withOutput(async (outputPath) => {
    const missingFieldFetch = createFetch({
      fareResponse: ({ url }) => Response.json(farePayload(url, { omitField: "childCashFare" })),
    });
    await assert.rejects(() => probe({ outputPath, fetchImpl: missingFieldFetch }), /childCashFare/);
    await assert.rejects(access(outputPath));

    const secretErrorFetch = async (input) => {
      const url = String(input);
      throw new Error(`request failed ${url} ${FARE_KEY} ${SEOUL_KEY}`);
    };
    const error = await probe({ outputPath, fetchImpl: secretErrorFetch }).catch((caught) => caught);
    assert.equal(error instanceof Error, true);
    assert.doesNotMatch(error.message, new RegExp(`${FARE_KEY}|${SEOUL_KEY}|https?://|serviceKey=`));
  });
});
