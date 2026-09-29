import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const cd = readFileSync(new URL("../../.github/workflows/cd.yml", import.meta.url), "utf8");

test("배포 env는 공공 API 자체 호출 한도를 주입하지 않는다", () => {
  assert.equal(/CALL_LIMIT_PER_/.test(cd), false);
  assert.match(cd, /EASYSUBWAY_TRAIN_SEARCH_RATE_LIMIT_PER_DAY=64/);
});
