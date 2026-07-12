import assert from "node:assert/strict";
import { access, mkdtemp, readFile, rm, stat } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import * as fareProbe from "./probe-seoul-fare-api.mjs";

const FARE_KEY = "DATA_GO_KR_SERVICE_KEY_VALUE";
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

const scheduleRows = {
  서울역: [{ lineNm: "4호선", stnNm: "서울역", stnCd: "0150", trainno: "SYNTHETIC-1" }],
  시청: [{ lineNm: "1호선", stnNm: "시청", stnCd: "0151", trainno: "SYNTHETIC-2" }],
  상록수: [{ lineNm: "4호선", stnNm: "상록수", stnCd: "9001", trainno: "SYNTHETIC-3" }],
  사당: [{ lineNm: "4호선", stnNm: "사당", stnCd: "9002", trainno: "SYNTHETIC-4" }],
};

const directionalFares = {
  "상록수→사당": [101, 102, 103, 104, 105, 106],
  "사당→상록수": [201, 202, 203, 204, 205, 206],
};

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

function createFetch({
  rows = scheduleRows,
  fareResponse,
  onCall = () => {},
} = {}) {
  return async (input) => {
    const url = new URL(input);
    if (url.pathname === "/B553766/schedule/getTrainSch") {
      const stationName = url.searchParams.get("stnNm");
      onCall(`schedule:${stationName}`, url);
      return Response.json({
        response: {
          header: { resultCode: "00" },
          body: { totalCount: rows[stationName].length, items: { item: rows[stationName] } },
        },
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

test("HTTPS schedule stnCd canary로 양방향 공식 OD 증거만 기록한다", async () => {
  await withOutput(async (outputPath) => {
    const calls = [];
    const evidence = await probe({
      outputPath,
      fetchImpl: createFetch({
        onCall: (kind, url) => {
          assert.equal(url.protocol, "https:");
          calls.push(kind);
        },
      }),
    });

    assert.deepEqual(calls, [
      "schedule:서울역",
      "schedule:시청",
      "schedule:상록수",
      "schedule:사당",
      "fare:상록수→사당",
      "fare:사당→상록수",
    ]);
    assert.equal(evidence.artifactKind, "official-od-fare-probe-evidence");
    assert.equal(evidence.mappingField, "stnCd");
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
    assert.doesNotMatch(JSON.stringify(stored), new RegExp(`${FARE_KEY}|serviceKey|https?://`));
  });
});

test("한 역·노선에서 schedule stnCd가 둘이면 target 호출 전에 실패한다", async () => {
  await withOutput(async (outputPath) => {
    const rows = structuredClone(scheduleRows);
    rows.서울역.push({ ...rows.서울역[0], stnCd: "9999" });
    const calls = [];

    await assert.rejects(
      () => probe({ outputPath, fetchImpl: createFetch({ rows, onCall: (kind) => calls.push(kind) }) }),
      /schedule station code is absent or ambiguous/,
    );
    assert.deepEqual(calls, ["schedule:서울역"]);
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

test("계속되는 5xx는 두 번에서 중단하고 output을 만들지 않는다", async () => {
  await withOutput(async (outputPath) => {
    let fareAttempts = 0;
    const fetchImpl = createFetch({
      fareResponse: () => {
        fareAttempts += 1;
        return new Response("temporary", { status: 503 });
      },
    });
    await assert.rejects(() => probe({ outputPath, fetchImpl }), /fare API HTTP 503/);
    assert.equal(fareAttempts, 2);
    await assert.rejects(access(outputPath));
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

test("계속되는 transport failure는 두 번에서 중단하고 output을 만들지 않는다", async () => {
  await withOutput(async (outputPath) => {
    let fareAttempts = 0;
    const fetchImpl = createFetch({
      fareResponse: () => {
        fareAttempts += 1;
        throw new Error("socket closed");
      },
    });
    await assert.rejects(() => probe({ outputPath, fetchImpl }), /socket closed/);
    assert.equal(fareAttempts, 2);
    await assert.rejects(access(outputPath));
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
      throw new Error(`request failed ${url} ${FARE_KEY}`);
    };
    const error = await probe({ outputPath, fetchImpl: secretErrorFetch }).catch((caught) => caught);
    assert.equal(error instanceof Error, true);
    assert.doesNotMatch(error.message, new RegExp(`${FARE_KEY}|https?://|serviceKey=`));
    await assert.rejects(access(outputPath));
  });
});
