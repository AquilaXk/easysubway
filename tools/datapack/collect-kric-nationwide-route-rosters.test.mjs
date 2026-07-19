import assert from "node:assert/strict";
import test from "node:test";

import { collectKricNationwideRouteRosters } from "./collect-kric-nationwide-route-rosters.mjs";

const targets = {
  targetVersion: "2026-07-13",
  activeLineScopes: [
    { regionId: "capital", operatorId: "seoul-metro", lineId: "line-4" },
    { regionId: "capital", operatorId: "korail", lineId: "line-4" },
    { regionId: "busan", operatorId: "busan-transportation", lineId: "busan-1" },
  ],
};
const fixture = {
  providerLineScopes: [
    { regionId: "capital", operatorId: "seoul-metro", lineId: "line-4", mreaWideCd: "01", lnCd: "4", railOprIsttCd: "S1" },
    { regionId: "capital", operatorId: "korail", lineId: "line-4", mreaWideCd: "01", lnCd: "4", railOprIsttCd: "KR" },
    { regionId: "busan", operatorId: "busan-transportation", lineId: "busan-1", mreaWideCd: "02", lnCd: "1", railOprIsttCd: "BS" },
  ],
};

test("전국 KRIC roster 수집은 shared line 요청을 합치고 모든 operator row를 검증한다", async () => {
  const requests = [];
  const result = await collectKricNationwideRouteRosters({
    targets,
    fixture,
    serviceKey: "secret",
    now: new Date("2026-07-19T00:00:00.000Z"),
    collectImpl: async ({ mreaWideCd, lnCd, serviceKey }) => {
      requests.push(`${mreaWideCd}:${lnCd}:${serviceKey}`);
      const operators = mreaWideCd === "01" ? ["S1", "KR"] : ["BS"];
      return {
        schemaVersion: 1,
        artifactKind: "kric-route-roster",
        mreaWideCd,
        lnCd,
        resultCode: "00",
        stations: operators.map((railOprIsttCd, index) => ({
          railOprIsttCd,
          lnCd,
          mreaWideCd,
          stinCd: `${index + 1}`,
          stinNm: `역${index + 1}`,
          stinConsOrdr: index + 1,
        })),
      };
    },
  });

  assert.equal(result.providerScopeCount, 3);
  assert.equal(result.requestCount, 2);
  assert.deepEqual(requests.sort(), ["01:4:secret", "02:1:secret"]);
  assert.equal(result.capturedAt, "2026-07-19T00:00:00.000Z");
});

test("전국 KRIC roster 수집은 target mapping이나 provider operator row 누락을 거부한다", async () => {
  await assert.rejects(collectKricNationwideRouteRosters({
    targets,
    fixture: { providerLineScopes: fixture.providerLineScopes.slice(1) },
    serviceKey: "secret",
    collectImpl: async () => assert.fail("must not collect"),
  }), /provider scope set/);

  await assert.rejects(collectKricNationwideRouteRosters({
    targets,
    fixture,
    serviceKey: "secret",
    collectImpl: async ({ mreaWideCd, lnCd }) => ({
      schemaVersion: 1,
      artifactKind: "kric-route-roster",
      mreaWideCd,
      lnCd,
      resultCode: "00",
      stations: [{ railOprIsttCd: "S1", lnCd, mreaWideCd, stinCd: "1", stinNm: "역", stinConsOrdr: 1 }],
    }),
  }), /provider operator row is missing/);
});

test("전국 KRIC roster 수집은 target과 fixture의 중복 provider scope를 거부한다", async () => {
  await assert.rejects(collectKricNationwideRouteRosters({
    targets: { ...targets, activeLineScopes: [...targets.activeLineScopes, targets.activeLineScopes[0]] },
    fixture,
    serviceKey: "secret",
    collectImpl: async () => assert.fail("must not collect"),
  }), /duplicate target active line scope/);

  await assert.rejects(collectKricNationwideRouteRosters({
    targets,
    fixture: { providerLineScopes: [...fixture.providerLineScopes, fixture.providerLineScopes[0]] },
    serviceKey: "secret",
    collectImpl: async () => assert.fail("must not collect"),
  }), /duplicate fixture provider scope/);
});

test("전국 KRIC roster 수집은 targetVersion을 provider 호출 전에 검증한다", async () => {
  await assert.rejects(collectKricNationwideRouteRosters({
    targets: { ...targets, targetVersion: "" },
    fixture,
    serviceKey: "secret",
    collectImpl: async () => assert.fail("must not collect"),
  }), /targets.targetVersion is required/);
});

test("전국 KRIC roster 수집은 각 provider roster schema 오류를 거부한다", async (context) => {
  const validRoster = ({ mreaWideCd, lnCd }) => ({
    schemaVersion: 1,
    artifactKind: "kric-route-roster",
    mreaWideCd,
    lnCd,
    resultCode: "00",
    stations: ["S1", "KR", "BS"].map((railOprIsttCd, index) => ({
      railOprIsttCd,
      lnCd,
      mreaWideCd,
      stinCd: `${index + 1}`,
      stinNm: `역${index + 1}`,
      stinConsOrdr: index + 1,
    })),
  });
  for (const [label, mutate] of [
    ["artifactKind", (roster) => { roster.artifactKind = "wrong"; }],
    ["resultCode", (roster) => { roster.resultCode = "30"; }],
    ["stations", (roster) => { roster.stations = null; }],
  ]) {
    await context.test(label, async () => {
      await assert.rejects(collectKricNationwideRouteRosters({
        targets,
        fixture,
        serviceKey: "secret",
        collectImpl: async (request) => {
          const roster = validRoster(request);
          mutate(roster);
          return roster;
        },
      }), /nationwide roster schema is invalid/);
    });
  }
});
