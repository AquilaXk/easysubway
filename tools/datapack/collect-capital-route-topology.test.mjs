import assert from "node:assert/strict";
import test from "node:test";

import {
  LINE_SOURCES,
  mergeOfficialDistanceEvidence,
  parseLineSource,
  resolveDataGoDownloadUrl,
} from "./collect-capital-route-topology.mjs";

test("data.go.kr 상세 페이지는 단일 canonical FILE download만 허용한다", () => {
  const detail = "https://www.data.go.kr/data/15122916/fileData.do";
  const resolved = resolveDataGoDownloadUrl(`
    <a href="/cmm/cmm/fileDownload.do?atchFileId=FILE_000000003700001&amp;fileDetailSn=1&amp;insertDataPrcus=N">CSV</a>
  `, detail);
  assert.equal(
    resolved,
    "https://www.data.go.kr/cmm/cmm/fileDownload.do?atchFileId=FILE_000000003700001&fileDetailSn=1&insertDataPrcus=N",
  );
  assert.throws(() => resolveDataGoDownloadUrl("<html>none</html>", detail), /exactly one/);
  assert.throws(
    () => resolveDataGoDownloadUrl(`
      /cmm/cmm/fileDownload.do?atchFileId=FILE_000000003700001&amp;fileDetailSn=1
      /cmm/cmm/fileDownload.do?atchFileId=FILE_000000003700002&amp;fileDetailSn=1
    `, detail),
    /exactly one/,
  );
  assert.throws(
    () => resolveDataGoDownloadUrl(
      "https://evil.example/cmm/cmm/fileDownload.do?atchFileId=FILE_000000003700001&fileDetailSn=1",
      detail,
    ),
    /canonical data.go.kr/,
  );
});

test("상충하는 official 거리는 선택하지 않고 conflict evidence를 보존한다", () => {
  assert.deepEqual(
    mergeOfficialDistanceEvidence({ distanceMeters: 1700 }, 2100),
    { distanceMeters: 0, distanceConflictMeters: [1700, 2100] },
  );
  assert.deepEqual(
    mergeOfficialDistanceEvidence({ distanceMeters: 0, distanceConflictMeters: [1700, 2100] }, 1700),
    { distanceMeters: 0, distanceConflictMeters: [1700, 2100] },
  );
  assert.deepEqual(mergeOfficialDistanceEvidence({ distanceMeters: 0 }, 600), { distanceMeters: 600 });
});

test("서해선 official file이 다른 노선을 함께 반환해도 서해선 branch만 수용한다", () => {
  const source = LINE_SOURCES.find(({ slug }) => slug === "seohae");
  const korailBytes = Buffer.from([
    "철도운영기관명,선명,역명,역간거리(km)",
    "코레일,1호선(경부선),가능,1.0",
    "코레일,1호선(경부선),의정부,1.4",
    "코레일,서해선,일산,1.9",
    "코레일,서해선,풍산,1.7",
    "코레일,서해선,백마,1.6",
  ].join("\n"));
  const molitBytes = Buffer.from([
    "권역,권역명,철도운영기관명,노선명,순번,역명",
    "1,수도권,서해철도,서해선,10,소사",
    "1,수도권,서해철도,서해선,11,소새울",
  ].join("\n"));

  const result = parseLineSource(source, korailBytes, {
    capturedAt: new Date("2026-08-09T12:04:20.479Z"),
    secondaryBytes: molitBytes,
  });

  assert.deepEqual(result.branchNames, ["서해선"]);
  assert.equal(result.scope.some(({ stationName }) => stationName === "가능"), false);
  assert.equal(result.scope.some(({ stationName }) => stationName === "일산"), true);
});
