import assert from "node:assert/strict";
import test from "node:test";

import { validateMolitProviderIdentities } from "./build-molit-nationwide-fixture.mjs";

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
