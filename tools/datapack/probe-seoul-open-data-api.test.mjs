import assert from "node:assert/strict";
import test from "node:test";

import { probeSeoulOpenDataApi } from "./probe-seoul-open-data-api.mjs";

test("서울시 path-key API probe는 key를 URL에만 넣고 sanitized schema evidence를 만든다", async () => {
  const secret = "never-print-seoul-key";
  let requestedUrl;
  const evidence = await probeSeoulOpenDataApi({
    sourceId: "seoul-topis-realtime-station-arrival",
    serviceKey: secret,
    fetchImpl: async (url) => {
      requestedUrl = url;
      return new Response(JSON.stringify({
        errorMessage: { status: 200, code: "INFO-000" },
        realtimeArrivalList: [{ statnId: "1004000432", statnNm: "사당" }],
      }), { status: 200, headers: { "content-type": "application/json" } });
    },
  });

  assert.match(requestedUrl.pathname, new RegExp(`/${secret}/json/realtimeStationArrival/0/5/`));
  assert.equal(evidence.providerResultCode, "INFO-000");
  assert.equal(evidence.rowCount, 1);
  assert.equal(evidence.credentialRedacted, true);
  assert.doesNotMatch(JSON.stringify(evidence), new RegExp(secret));
});

test("서울시 path-key API probe는 retryable 응답 뒤 bounded backoff를 적용한다", async () => {
  const delays = [];
  let attempts = 0;
  const evidence = await probeSeoulOpenDataApi({
    sourceId: "seoul-topis-realtime-station-arrival",
    serviceKey: "key",
    sleepImpl: async (milliseconds) => delays.push(milliseconds),
    fetchImpl: async () => {
      attempts += 1;
      if (attempts === 1) return new Response("", { status: 429 });
      return new Response(JSON.stringify({
        errorMessage: { status: 200, code: "INFO-000" },
        realtimeArrivalList: [{ statnId: "1004000432", statnNm: "사당" }],
      }), { status: 200, headers: { "content-type": "application/json" } });
    },
  });

  assert.equal(attempts, 2);
  assert.deepEqual(delays, [500]);
  assert.equal(evidence.rowCount, 1);
});

test("서울시 path-key API probe는 HTTP와 schema 및 transport 오류를 fail closed한다", async (t) => {
  const base = { sourceId: "seoul-topis-realtime-station-arrival", serviceKey: "key" };

  await t.test("HTTP failure", async () => {
    await assert.rejects(probeSeoulOpenDataApi({
      ...base,
      fetchImpl: async () => new Response("", { status: 404 }),
    }), /Seoul open data API HTTP 404/);
  });

  await t.test("content-type mismatch", async () => {
    await assert.rejects(probeSeoulOpenDataApi({
      ...base,
      fetchImpl: async () => new Response("not json", {
        status: 200,
        headers: { "content-type": "text/plain" },
      }),
    }), /schema mismatch: content-type text\/plain/);
  });

  await t.test("required row field missing", async () => {
    await assert.rejects(probeSeoulOpenDataApi({
      ...base,
      fetchImpl: async () => new Response(JSON.stringify({
        errorMessage: { status: 200, code: "INFO-000" },
        realtimeArrivalList: [{ statnId: "1004000432" }],
      }), { status: 200, headers: { "content-type": "application/json" } }),
    }), /schema mismatch: item\[0\] fields missing=statnNm/);
  });

  await t.test("transport failure after bounded retry", async () => {
    const delays = [];
    let attempts = 0;
    await assert.rejects(probeSeoulOpenDataApi({
      ...base,
      sleepImpl: async (milliseconds) => delays.push(milliseconds),
      fetchImpl: async () => {
        attempts += 1;
        throw new Error("network details must stay in cause");
      },
    }), /Seoul open data API transport failure/);
    assert.equal(attempts, 2);
    assert.deepEqual(delays, [500]);
  });
});

test("서울시 path-key API probe는 Sheet envelope와 provider/schema 오류를 fail closed한다", async (t) => {
  let requestedUrl;
  const sheet = await probeSeoulOpenDataApi({
    sourceId: "seoulmetro-station-line-info",
    serviceKey: "key",
    fetchImpl: async (url) => {
      requestedUrl = url;
      return new Response(JSON.stringify({
        SearchSTNBySubwayLineInfo: {
          list_total_count: 1,
          RESULT: { CODE: "INFO-000", MESSAGE: "정상 처리되었습니다" },
          row: [{
            LINE_NUM: "04호선", STATION_CD: "0432", STATION_NM: "사당", STATION_NM_ENG: "Sadang",
            FR_CODE: "432", STATION_NM_CHN: "舍堂", STATION_NM_JPN: "サダン",
          }],
        },
      }), { status: 200, headers: { "content-type": "application/json" } });
    },
  });
  assert.equal(sheet.rowCount, 1);
  assert.deepEqual(sheet.outputFields, [
    "STATION_CD", "STATION_NM", "STATION_NM_ENG", "LINE_NUM", "FR_CODE", "STATION_NM_CHN", "STATION_NM_JPN",
  ]);
  assert.match(decodeURI(requestedUrl.pathname), /\/1\/5\/\/\/4호선$/);

  await t.test("provider failure", async () => {
    await assert.rejects(probeSeoulOpenDataApi({
      sourceId: "seoul-topis-realtime-train-position",
      serviceKey: "key",
      fetchImpl: async () => new Response(JSON.stringify({
        errorMessage: { status: 500, code: "ERROR-500" },
      }), { status: 200, headers: { "content-type": "application/json" } }),
    }), /provider resultCode ERROR-500/);
  });

  await t.test("empty rows", async () => {
    await assert.rejects(probeSeoulOpenDataApi({
      sourceId: "seoul-topis-realtime-train-position",
      serviceKey: "key",
      fetchImpl: async () => new Response(JSON.stringify({
        errorMessage: { status: 200, code: "INFO-000" },
        realtimePositionList: [],
      }), { status: 200, headers: { "content-type": "application/json" } }),
    }), /returned zero rows/);
  });

  await t.test("Sheet top-level provider failure", async () => {
    await assert.rejects(probeSeoulOpenDataApi({
      sourceId: "seoulmetro-station-line-info",
      serviceKey: "key",
      fetchImpl: async () => new Response(JSON.stringify({
        RESULT: { CODE: "INFO-200", MESSAGE: "해당하는 데이터가 없습니다" },
      }), { status: 200, headers: { "content-type": "application/json" } }),
    }), /provider resultCode INFO-200/);
  });
});
