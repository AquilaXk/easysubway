import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { collectBusanTimetable } from "./collect-busan-timetable.mjs";

const topology = JSON.parse(await readFile(
  new URL("./sources/busan-transportation-route-topology-20260720.json", import.meta.url),
  "utf8",
));

function response(item) {
  return new Response(`<?xml version="1.0" encoding="UTF-8"?><response>
    <header><resultCode>00</resultCode><resultMsg>정상</resultMsg></header>
    <body><item>${item}</item></body></response>`, {
    headers: { "content-type": "application/xml" },
  });
}

test("부산 timetable collector는 114개 역과 3개 요일을 bounded fan-out한다", async () => {
  const requested = [];
  const secret = "never-print-service-key";
  const snapshot = await collectBusanTimetable({
    serviceKey: secret,
    stationScopes: topology.scope,
    now: new Date("2026-07-20T09:00:00.000Z"),
    fetchImpl: async (url) => {
      const request = new URL(url);
      requested.push(request);
      const station = topology.scope.find(({ stationCode }) => stationCode === request.searchParams.get("scode"));
      const line = ({
        "line-ab1a041f6266": "1",
        "line-eb7b47920390": "2",
        "line-d74614a04530": "3",
        "line-d812a5bc1e5f": "4",
      })[station.lineId];
      const day = request.searchParams.get("day");
      return response([
        `<sname>${station.stationName}</sname>`,
        `<engname>Station ${station.stationCode}</engname>`,
        `<trainno>${line}${day}01</trainno>`,
        "<hour>05</hour><time>01</time>",
        `<day>${day}</day><updown>${Number(station.stationCode) % 2}</updown>`,
        `<endcode>${station.stationCode}</endcode><scode>${station.stationCode}</scode><line>${line}</line>`,
      ].join(""));
    },
  });

  assert.equal(requested.length, 342);
  assert.equal(snapshot.requestCount, 342);
  assert.equal(snapshot.stationCount, 114);
  assert.equal(snapshot.rowCount, 342);
  assert.deepEqual(snapshot.dayTypes, ["1", "2", "3"]);
  assert.deepEqual(snapshot.lineIds, topology.lineIds);
  assert.deepEqual([...requested[0].searchParams], [
    ["serviceKey", secret], ["act", "xml"], ["scode", topology.scope[0].stationCode], ["day", "1"], ["enum", "999"],
  ]);
  assert.equal(snapshot.credentialRedacted, true);
  assert.match(snapshot.rowsSha256, /^[a-f0-9]{64}$/);
  assert.match(snapshot.rawSha256, /^[a-f0-9]{64}$/);
  assert.doesNotMatch(JSON.stringify(snapshot), new RegExp(secret));
});
