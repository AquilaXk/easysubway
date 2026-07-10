import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { access, mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import {
  buildAccessibilitySnapshot,
  collectSeoulAccessibility,
  normalizeAccessibilityRows,
  writeSeoulAccessibilityEvidence,
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

test("collector rejects HTTP 403 before reading the response body", async () => {
  let bodyRead = false;
  await assert.rejects(
    collectSeoulAccessibility({
      endpoint: "https://apis.data.go.kr/example",
      serviceKey: "secret",
      fetchImpl: async () => ({
        ok: false,
        status: 403,
        json: async () => {
          bodyRead = true;
          throw new Error("serviceKey=secret raw body");
        },
      }),
    }),
    /Seoul accessibility API HTTP 403/,
  );
  assert.equal(bodyRead, false);
});

test("collector redacts raw body and request details from invalid JSON", async () => {
  await assert.rejects(
    collectSeoulAccessibility({
      endpoint: "https://apis.data.go.kr/example",
      serviceKey: "secret",
      fetchImpl: async () => ({
        ok: true,
        json: async () => {
          throw new Error("raw body https://apis.data.go.kr/example?serviceKey=secret");
        },
      }),
    }),
    (error) => {
      assert.equal(error.message, "Seoul accessibility API response invalid");
      assert.doesNotMatch(error.message, /raw body|secret|https?:\/\//);
      return true;
    },
  );
});

test("collector rejects API-level error envelopes without exposing the provider message", async () => {
  await assert.rejects(
    collectSeoulAccessibility({
      endpoint: "https://apis.data.go.kr/example",
      serviceKey: "secret",
      fetchImpl: async () => ({
        ok: true,
        json: async () => ({
          response: {
            header: { resultCode: "99", resultMsg: "serviceKey=secret raw provider message" },
            body: {
              items: {
                item: [{ stnNm: "사당", oprYn: "Y", instlPstn: "대합실-승강장" }],
              },
            },
          },
        }),
      }),
    }),
    (error) => {
      assert.equal(error.message, "Seoul accessibility API response invalid");
      assert.doesNotMatch(error.message, /secret|provider message/);
      return true;
    },
  );
});

test("collector rejects malformed items with a fixed credential-free error", async () => {
  await assert.rejects(
    collectSeoulAccessibility({
      endpoint: "https://apis.data.go.kr/example",
      serviceKey: "secret",
      fetchImpl: async () => ({
        ok: true,
        json: async () => ({
          response: {
            header: { resultCode: "00" },
            body: { items: { item: { reflected: "serviceKey=secret" } } },
          },
        }),
      }),
    }),
    (error) => {
      assert.equal(error.message, "Seoul accessibility API response invalid");
      assert.doesNotMatch(error.message, /secret|rows\.map/);
      return true;
    },
  );
});

test("collector accepts only the documented success schema", async () => {
  const rows = await collectSeoulAccessibility({
    endpoint: "https://apis.data.go.kr/example",
    serviceKey: "secret",
    fetchImpl: async () => ({
      ok: true,
      json: async () => ({
        response: {
          header: { resultCode: "00" },
          body: {
            items: {
              item: [
                { stnNm: "상록수", oprYn: "Y", instlPstn: "1번 출구-대합실" },
                { stnNm: "사당", oprYn: "Y", instlPstn: "대합실-승강장" },
              ],
            },
          },
        },
      }),
    }),
  });

  assert.deepEqual(rows, [
    { stationName: "상록수", operational: true, pathDescription: "1번 출구-대합실" },
    { stationName: "사당", operational: true, pathDescription: "대합실-승강장" },
  ]);
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

test("normalizer rejects undocumented operation codes", () => {
  assert.throws(
    () => normalizeAccessibilityRows([{ stnNm: "상록수", oprtngSitu: "M", dtlPstn: "1번 출구-대합실" }]),
    /Seoul accessibility API response invalid/,
  );
});

test("normalizer rejects malformed and incomplete evidence rows", () => {
  const valid = { stnNm: "사당", oprYn: "Y", instlPstn: "대합실-승강장" };
  for (const row of [
    null,
    { ...valid, stnNm: undefined },
    { ...valid, stnNm: 123 },
    { ...valid, instlPstn: undefined },
    { ...valid, instlPstn: 123 },
    { ...valid, oprYn: undefined },
    { ...valid, oprYn: 123 },
  ]) {
    assert.throws(() => normalizeAccessibilityRows([row]), /Seoul accessibility API response invalid/);
  }
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

test("snapshot rejects pilot facilities without a boolean status and path", () => {
  const validSadang = { stationName: "사당", operational: true, pathDescription: "대합실-승강장" };
  for (const sangnoksu of [
    { stationName: "상록수", pathDescription: "1번 출구-대합실" },
    { stationName: "상록수", operational: "Y", pathDescription: "1번 출구-대합실" },
    { stationName: "상록수", operational: true },
    { stationName: "상록수", operational: true, pathDescription: 123 },
  ]) {
    assert.throws(
      () => buildAccessibilitySnapshot([sangnoksu, validSadang], "2026-07-10T00:00:00.000Z"),
      /Seoul accessibility API response invalid/,
    );
  }
});

test("invalid provider evidence never reaches the output write", async () => {
  const outputDir = await mkdtemp(join(tmpdir(), "easysubway-accessibility-"));
  const valid = { stnNm: "사당", oprYn: "Y", instlPstn: "대합실-승강장" };
  const jsonResponse = (item, resultCode = "00") => async () => ({
    ok: true,
    json: async () => ({ response: { header: { resultCode }, body: { items: { item } } } }),
  });
  const cases = [
    async () => ({ ok: false, status: 403 }),
    async () => ({
      ok: true,
      json: async () => {
        throw new Error("raw serviceKey=secret");
      },
    }),
    jsonResponse([valid], "99"),
    jsonResponse({ reflected: "serviceKey=secret" }),
    ...[
      null,
      { ...valid, stnNm: undefined },
      { ...valid, stnNm: 123 },
      { ...valid, instlPstn: undefined },
      { ...valid, instlPstn: 123 },
      { ...valid, oprYn: undefined },
      { ...valid, oprYn: 123 },
      { ...valid, oprYn: "M" },
    ].map((row) => jsonResponse([row])),
  ];

  try {
    for (const [index, fetchImpl] of cases.entries()) {
      const output = join(outputDir, `${index}.json`);
      await assert.rejects(
        writeSeoulAccessibilityEvidence({
          endpoint: "https://apis.data.go.kr/example",
          serviceKey: "secret",
          output,
          fetchImpl,
          retrievedAt: "2026-07-10T00:00:00.000Z",
        }),
      );
      await assert.rejects(access(output), (error) => error.code === "ENOENT");
    }
  } finally {
    await rm(outputDir, { recursive: true, force: true });
  }
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
