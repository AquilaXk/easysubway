import assert from "node:assert/strict";
import test from "node:test";

import {
  validateKricProviderCodeCatalogIdentity,
  validateMolitProviderIdentities,
} from "./build-molit-nationwide-fixture.mjs";

test("MOLIT provider identity가 coverage scope와 매칭되지 않으면 거부한다", () => {
  assert.throws(() => validateMolitProviderIdentities([{
    providerIdentity: {
      mreaWideCd: "01",
      lnCd: "4",
      railOprIsttCd: "S1",
      operatorName: "서울교통공사",
    },
    lineName: "4호선",
  }], []), /MOLIT provider scope is unmatched/);
});

test("MOLIT provider identity는 canonical alias scope를 검증하고 코드 불일치를 거부한다", () => {
  const row = {
    providerIdentity: {
      mreaWideCd: "01",
      lnCd: "K4",
      railOprIsttCd: "KR",
      operatorName: "한국철도공사",
    },
    lineName: "경의·중앙선",
  };
  const scope = {
    regionId: "capital",
    operatorId: "korail",
    lineId: "line-6e39be0cb6e2",
    mreaWideCd: "01",
    lnCd: "K4",
    railOprIsttCd: "KR",
  };
  assert.doesNotThrow(() => validateMolitProviderIdentities([row], [scope]));
  assert.throws(() => validateMolitProviderIdentities([{
    ...row,
    providerIdentity: { ...row.providerIdentity, lnCd: "K1" },
  }], [scope]), /MOLIT\/KRIC provider code mismatch/);
});

test("KRIC provider code catalog identity는 고정 source ID와 SHA-256만 허용한다", () => {
  assert.doesNotThrow(() => validateKricProviderCodeCatalogIdentity({
    sourceId: "kric-provider-code-catalog-20260228",
    sourceSha256: "ef1f8b094e32e81c7390e8566984293dcefcc85e7fadacfe4433e77ddcc61272",
  }));
  assert.throws(() => validateKricProviderCodeCatalogIdentity({
    sourceId: "unexpected",
    sourceSha256: "a".repeat(64),
  }), /sourceId is invalid/);
  assert.throws(() => validateKricProviderCodeCatalogIdentity({
    sourceId: "kric-provider-code-catalog-20260228",
    sourceSha256: "a".repeat(64),
  }), /sourceSha256 does not match/);
  assert.throws(() => validateKricProviderCodeCatalogIdentity({
    sourceId: "kric-provider-code-catalog-20260228",
    sourceSha256: "not-a-sha",
  }), /sourceSha256 is invalid/);
});
