import assert from "node:assert/strict";
import test from "node:test";

import { parseMolitSvgProviderIdentity } from "./molit-svg-provider-identity.mjs";

test("MOLIT SVG 식별자에서 KRIC 권역·노선·운영기관 코드를 정확히 복원한다", () => {
  assert.deepEqual(
    parseMolitSvgProviderIdentity("subway_a02_l01", "BS(부산교통공사)"),
    {
      mreaWideCd: "02",
      lnCd: "1",
      railOprIsttCd: "BS",
      operatorName: "부산교통공사",
    },
  );
  assert.deepEqual(
    parseMolitSvgProviderIdentity("subway_a01_lA1", "AR(공항철도주식회사)"),
    {
      mreaWideCd: "01",
      lnCd: "A1",
      railOprIsttCd: "AR",
      operatorName: "공항철도주식회사",
    },
  );
  assert.deepEqual(
    parseMolitSvgProviderIdentity("subway_a01_lUI", "UI(우이신설경전철주식회사)"),
    {
      mreaWideCd: "01",
      lnCd: "UI",
      railOprIsttCd: "UI",
      operatorName: "우이신설경전철주식회사",
    },
  );
});

test("KRIC provider 형식이 아닌 노선도 행은 provider identity로 승격하지 않는다", () => {
  assert.equal(parseMolitSvgProviderIdentity("area01", "서울교통공사"), null);
  assert.equal(parseMolitSvgProviderIdentity("subway_a1_l01", "S1(서울교통공사)"), null);
  assert.equal(parseMolitSvgProviderIdentity("subway_a01_l01", "서울교통공사"), null);
});
