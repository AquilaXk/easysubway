import assert from "node:assert/strict";
import test from "node:test";
import { computeSpanOracle, parseReviewedCsv } from "./oracle-metrics.mjs";

test("computeSpanOracle는 멤버수별 스팬 p90(nearest-rank)을 낸다", () => {
  const groups = [
    { memberCount: 2, span: 10 }, { memberCount: 2, span: 12 },
    { memberCount: 2, span: 13 }, { memberCount: 2, span: 40 },
    { memberCount: 3, span: 29 },
  ];
  const o = computeSpanOracle(groups);
  // 2선 4개 정렬 [10,12,13,40], p90 nearest-rank = ceil(0.9*4)=4번째 = 40? → 도트피치 오라클은
  // 이상치(오병합 잔재) 제외 위해 p90. 4개 중 p90=40. 단일 3선=29.
  assert.equal(o["2"], 40);
  assert.equal(o["3"], 29);
});

test("parseReviewedCsv는 역명·노선·좌표 행을 파싱한다(헤더 스킵)", () => {
  const csv = "station,line,x,y\n서울역,1호선,100,200\n서울역,4호선,110,205\n";
  const rows = parseReviewedCsv(csv);
  assert.deepEqual(rows, [
    { stationName: "서울역", lineId: "1호선", x: 100, y: 200 },
    { stationName: "서울역", lineId: "4호선", x: 110, y: 205 },
  ]);
});
