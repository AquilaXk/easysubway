import assert from "node:assert/strict";
import test from "node:test";
import { buildGeoTransform, splitHighDegreeNodes } from "./export-loom-geojson.mjs";

const BBOX = { minX: 100, maxX: 5600, minY: 190, maxY: 6200 };

test("buildGeoTransform 왕복 항등: design → geo → design ≤ 0.05px", () => {
  const { toGeo, toDesign } = buildGeoTransform(BBOX);
  let maxRt = 0;
  for (let x = BBOX.minX; x <= BBOX.maxX; x += 550) {
    for (let y = BBOX.minY; y <= BBOX.maxY; y += 600) {
      const [lon, lat] = toGeo(x, y);
      const b = toDesign(lon, lat);
      maxRt = Math.max(maxRt, Math.hypot(b.x - x, b.y - y));
    }
  }
  assert.ok(maxRt <= 0.05, `maxRoundTrip=${maxRt}`);
});

test("buildGeoTransform은 축정렬을 보존한다(수평 design → 등위도, 수직 → 등경도)", () => {
  const { toGeo } = buildGeoTransform(BBOX);
  // 같은 y(수평선) → 같은 위도
  assert.equal(toGeo(200, 1000)[1], toGeo(5000, 1000)[1]);
  // 같은 x(수직선) → 같은 경도
  assert.equal(toGeo(1500, 300)[0], toGeo(1500, 6000)[0]);
});

test("buildGeoTransform은 45° design 벡터를 webmerc 45°로 보낸다(octi 8선형 정합)", () => {
  const { toDesign, toGeo } = buildGeoTransform(BBOX);
  // design 대각(dx=dy) → geo로 → 되돌린 design 벡터도 dx≈dy (부호/크기 보존)
  const a = { x: 1000, y: 1000 };
  const b = { x: 1500, y: 1500 };
  const ga = toGeo(a.x, a.y);
  const gb = toGeo(b.x, b.y);
  const da = toDesign(ga[0], ga[1]);
  const dbp = toDesign(gb[0], gb[1]);
  const dx = dbp.x - da.x;
  const dy = dbp.y - da.y;
  assert.ok(Math.abs(Math.abs(dx) - Math.abs(dy)) < 0.05, `dx=${dx} dy=${dy}`);
});

test("splitHighDegreeNodes는 차수>8 노드를 분할해 모든 차수를 8 이하로 만든다", () => {
  const nodeCoord = new Map();
  nodeCoord.set("hub", { x: 0, y: 0, name: "허브" });
  const edgeList = [];
  for (let i = 0; i < 9; i += 1) {
    const leaf = `leaf${i}`;
    nodeCoord.set(leaf, { x: i + 1, y: i + 1, name: `L${i}` });
    edgeList.push({ from: "hub", to: leaf, lines: new Set([`line-${i}`]) });
  }
  const split = splitHighDegreeNodes(nodeCoord, edgeList);
  assert.equal(split.length, 1);
  assert.equal(split[0].id, "hub");
  // 분할 노드 hub#2 생성, station_label 매핑(원 id 접두) 보존
  assert.ok(nodeCoord.has("hub#2"));
  assert.equal(nodeCoord.get("hub#2").name, "허브");
  // 재계산 차수 전부 ≤ 8
  const deg = new Map();
  for (const e of edgeList) {
    deg.set(e.from, (deg.get(e.from) ?? 0) + 1);
    deg.set(e.to, (deg.get(e.to) ?? 0) + 1);
  }
  for (const d of deg.values()) assert.ok(d <= 8, `degree ${d} > 8`);
});

test("splitHighDegreeNodes는 차수 ≤8이면 아무것도 하지 않는다", () => {
  const nodeCoord = new Map([["a", { x: 0, y: 0 }], ["b", { x: 1, y: 1 }]]);
  const edgeList = [{ from: "a", to: "b", lines: new Set(["l1"]) }];
  assert.deepEqual(splitHighDegreeNodes(nodeCoord, edgeList), []);
  assert.equal(edgeList.length, 1);
});
