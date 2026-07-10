import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import {
  buildAccessibilitySnapshot,
  collectSeoulAccessibility,
  normalizeAccessibilityRows,
} from "./collect-seoul-accessibility-evidence.mjs";

const execFileAsync = promisify(execFile);
const collectorPath = fileURLToPath(new URL("./collect-seoul-accessibility-evidence.mjs", import.meta.url));

test("collector rejects non-HTTPS endpoints", async () => {
  await assert.rejects(
    collectSeoulAccessibility({ endpoint: "http://apis.data.go.kr", serviceKey: "secret" }),
    /HTTPS endpoint is required/,
  );
});

test("collector redacts request details from network failures", async () => {
  await assert.rejects(
    collectSeoulAccessibility({
      endpoint: "https://apis.data.go.kr/example",
      serviceKey: "secret",
      fetchImpl: async (url) => {
        throw new Error(String(url));
      },
    }),
    (error) => {
      assert.match(error.message, /Seoul accessibility API request failed/);
      assert.doesNotMatch(error.message, /secret|https?:\/\//);
      return true;
    },
  );
});

test("collector keeps only station, location and operation evidence", () => {
  const snapshot = normalizeAccessibilityRows([
    { stnNm: "사당", oprYn: "Y", instlPstn: "대합실-승강장" },
  ]);
  assert.deepEqual(snapshot, [
    { stationName: "사당", operational: true, pathDescription: "대합실-승강장" },
  ]);
  assert.doesNotMatch(JSON.stringify(snapshot), /serviceKey/);
});

test("normalizer accepts the current official operation and location fields", () => {
  assert.deepEqual(
    normalizeAccessibilityRows([{ stnNm: "상록수", oprtngSitu: "M", dtlPstn: "1번 출구-대합실" }]),
    [{ stationName: "상록수", operational: true, pathDescription: "1번 출구-대합실" }],
  );
});

test("snapshot contains sanitized evidence for both pilot stations", () => {
  const snapshot = buildAccessibilitySnapshot(
    [
      { stationName: "사당", operational: true, pathDescription: "대합실-승강장" },
      { stationName: "상록수", operational: false, pathDescription: "1번 출구-대합실" },
    ],
    "2026-07-10T00:00:00.000Z",
  );

  assert.deepEqual(snapshot, {
    sourceId: "seoul-metro-accessibility",
    retrievedAt: "2026-07-10T00:00:00.000Z",
    stations: [
      {
        stationName: "상록수",
        facilities: [{ operational: false, pathDescription: "1번 출구-대합실" }],
      },
      {
        stationName: "사당",
        facilities: [{ operational: true, pathDescription: "대합실-승강장" }],
      },
    ],
  });
  assert.doesNotMatch(JSON.stringify(snapshot), /serviceKey|https?:\/\//);
});

test("snapshot rejects missing pilot station evidence", () => {
  assert.throws(
    () =>
      buildAccessibilitySnapshot(
        [{ stationName: "사당", operational: true, pathDescription: "대합실-승강장" }],
        "2026-07-10T00:00:00.000Z",
      ),
    /accessibility evidence missing for 상록수/,
  );
});

test("CLI requires the service key before collection", async () => {
  await assert.rejects(
    execFileAsync(
      process.execPath,
      [collectorPath, "--output", "unused.json"],
      { env: {} },
    ),
    /DATA_GO_KR_SERVICE_KEY env is required/,
  );
});

test("official endpoints remain pending candidates until admission evidence exists", async () => {
  const candidatesDocument = JSON.parse(
    await readFile(new URL("./source-candidates.json", import.meta.url), "utf8"),
  );
  const ids = ["seoul-metro-accessibility", "seoul-metro-facility-location"];
  const candidates = ids.map((id) => candidatesDocument.candidates.find((candidate) => candidate.id === id));
  assert.deepEqual(
    candidates.map((candidate) => ({
      id: candidate?.id,
      domain: candidate?.domain,
      requestUrl: candidate?.requestUrl,
      admissionStatus: candidate?.admissionStatus,
      retrievedAt: candidate?.evidence?.retrievedAt,
      usePermissionRange: candidate?.evidence?.usePermissionRange,
    })),
    [
      {
        id: "seoul-metro-accessibility",
        domain: "accessibility_facilities",
        requestUrl: "https://apis.data.go.kr/B553766/wksn/getWksnElvtr",
        admissionStatus: "evidence_recorded_admin_review_required",
        retrievedAt: "2026-07-10",
        usePermissionRange: "이용허락범위 제한 없음",
      },
      {
        id: "seoul-metro-facility-location",
        domain: "accessibility_facilities",
        requestUrl: "https://apis.data.go.kr/B553766/facility/getFcElvtr",
        admissionStatus: "evidence_recorded_admin_review_required",
        retrievedAt: "2026-07-10",
        usePermissionRange: "이용허락범위 제한 없음",
      },
    ],
  );

  const inventory = JSON.parse(await readFile(new URL("./source-inventory.json", import.meta.url), "utf8"));
  assert.deepEqual(
    inventory.sources.filter(({ id }) => ids.includes(id)),
    [],
  );
  assert.match(await readFile(new URL("../../.env.example", import.meta.url), "utf8"), /^DATA_GO_KR_SERVICE_KEY=$/m);
});
