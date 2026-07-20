import assert from "node:assert/strict";
import test from "node:test";

import { collectGwangjuTimetable } from "./collect-gwangju-timetable.mjs";

function xmlResponse({ resultCode = "00", rows = sampleRows(), totalCount = rows.length } = {}) {
  const items = rows.map((row) => `<item>${Object.entries(row)
    .map(([field, value]) => `<${field}>${value}</${field}>`).join("")}</item>`).join("");
  return new Response(`<?xml version="1.0" encoding="UTF-8"?><response>
    <header><resultCode>${resultCode}</resultCode><resultMsg>정상</resultMsg></header>
    <body><items>${items}</items><numOfRows>${rows.length}</numOfRows><pageNo>1</pageNo>
    <totalCount>${totalCount}</totalCount></body></response>`, {
    headers: { "content-type": "application/xml;charset=UTF-8" },
  });
}

function sampleRows() {
  const common = { day: "평일", updateDt: "2025-08-01", subwayLine: "1호선" };
  return [
    { ...common, endCord: "100", direction: "상행", time: "05:30", subwayCord: "101", endName: "녹동역", subwayName: "평동역" },
    { ...common, endCord: "119", direction: "하행", time: "05:32", subwayCord: "101", endName: "평동역", subwayName: "녹동역" },
  ];
}

test("광주 timetable collector는 공식 XML을 redacted deterministic snapshot으로 만든다", async () => {
  const secret = "never-print-gwangju-key";
  let requested;
  const snapshot = await collectGwangjuTimetable({
    serviceKey: secret,
    now: new Date("2026-07-20T13:00:00.000Z"),
    fetchImpl: async (url) => {
      requested = new URL(url);
      return xmlResponse();
    },
  });

  assert.equal(requested.origin + requested.pathname, "https://apis.data.go.kr/B551232/grtcTimetable/timetable");
  assert.deepEqual([...requested.searchParams], [
    ["serviceKey", secret], ["pageNo", "1"], ["numOfRows", "9999"],
  ]);
  assert.equal(snapshot.artifactKind, "gwangju-timetable-snapshot");
  assert.equal(snapshot.sourceId, "gwangju-transportation-timetable");
  assert.equal(snapshot.providerResultCode, "00");
  assert.equal(snapshot.schemaStatus, "EXPECTED");
  assert.equal(snapshot.rowCount, 2);
  assert.deepEqual(snapshot.outputFields, [
    "day", "endCord", "direction", "time", "subwayCord", "updateDt", "subwayLine", "endName", "subwayName",
  ]);
  assert.deepEqual(snapshot.dayTypes, ["평일"]);
  assert.deepEqual(snapshot.directions, ["상행", "하행"]);
  assert.match(snapshot.rawSha256, /^[a-f0-9]{64}$/);
  assert.match(snapshot.rowsSha256, /^[a-f0-9]{64}$/);
  assert.equal(snapshot.credentialRedacted, true);
  assert.doesNotMatch(JSON.stringify(snapshot), new RegExp(secret));
});

test("광주 timetable collector는 provider·pagination·row schema 오류를 fail closed한다", async () => {
  await assert.rejects(collectGwangjuTimetable({
    serviceKey: "key",
    fetchImpl: async () => xmlResponse({ resultCode: "20" }),
  }), /provider resultCode 20/);
  await assert.rejects(collectGwangjuTimetable({
    serviceKey: "key",
    fetchImpl: async () => xmlResponse({ totalCount: 3 }),
  }), /truncated items; items=2; totalCount=3/);
  await assert.rejects(collectGwangjuTimetable({
    serviceKey: "key",
    fetchImpl: async () => xmlResponse({ rows: [{ ...sampleRows()[0], time: "not-a-time" }] }),
  }), /item\[0\] values=time/);
});

test("광주 timetable collector는 credential과 provider body 없이 transport code만 진단한다", async () => {
  const transport = Object.assign(new Error("secret-bearing provider body"), { code: "ENOTFOUND" });
  await assert.rejects(collectGwangjuTimetable({
    serviceKey: "never-print-gwangju-key",
    sleepImpl: async () => {},
    fetchImpl: async () => { throw transport; },
  }), (error) => {
    assert.match(error.message, /transport failure; code=ENOTFOUND/);
    assert.doesNotMatch(error.message, /never-print|secret-bearing/);
    return true;
  });
});
