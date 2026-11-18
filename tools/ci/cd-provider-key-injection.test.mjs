import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const cd = readFileSync(new URL("../../.github/workflows/cd.yml", import.meta.url), "utf8");

test("cd.yml이 TAGO 키 주입과 awk drop 규칙을 유지한다 (회귀 방지)", () => {
  assert.match(
    cd,
    /drop\["EASYSUBWAY_TAGO_TRAIN_SERVICE_KEY"\]\s*=\s*1/,
    "awk drop 목록에 EASYSUBWAY_TAGO_TRAIN_SERVICE_KEY가 있어야 한다",
  );
  assert.match(
    cd,
    /printf 'EASYSUBWAY_TAGO_TRAIN_SERVICE_KEY=%s\\n' "\$\{DATA_GO_KR_SERVICE_KEY_SECRET\}" >> "\$\{env_file\}"/,
    "DATA_GO_KR_SERVICE_KEY_SECRET으로 EASYSUBWAY_TAGO_TRAIN_SERVICE_KEY를 주입해야 한다",
  );
});

test("cd.yml이 엘리베이터 가동 수집 키를 awk drop 목록에 포함한다", () => {
  assert.match(
    cd,
    /drop\["EASYSUBWAY_SEOUL_METRO_ELEVATOR_SERVICE_KEY"\]\s*=\s*1/,
    "awk drop 목록에 EASYSUBWAY_SEOUL_METRO_ELEVATOR_SERVICE_KEY가 있어야 한다",
  );
});

test("cd.yml이 DATA_GO_KR_SERVICE_KEY_SECRET 블록 안에서 엘리베이터 가동 수집 키를 주입한다", () => {
  const start = cd.indexOf('if [[ -n "${DATA_GO_KR_SERVICE_KEY_SECRET}" ]]; then');
  assert.ok(start !== -1, "DATA_GO_KR_SERVICE_KEY_SECRET 검사 블록 시작이 있어야 한다");
  const nextSection = cd.indexOf("EASYSUBWAY_TRAIN_SEARCH_RATE_LIMIT_PER_DAY=64", start);
  assert.ok(nextSection !== -1, "DATA_GO_KR_SERVICE_KEY_SECRET 블록 이후 섹션이 있어야 한다");
  const blockContent = cd.slice(start, nextSection);

  assert.match(
    blockContent,
    /printf 'EASYSUBWAY_TAGO_TRAIN_SERVICE_KEY=%s\\n' "\$\{DATA_GO_KR_SERVICE_KEY_SECRET\}" >> "\$\{env_file\}"/,
    "DATA_GO_KR_SERVICE_KEY_SECRET 블록 안에 EASYSUBWAY_TAGO_TRAIN_SERVICE_KEY 주입이 있어야 한다",
  );
  assert.match(
    blockContent,
    /printf 'EASYSUBWAY_SEOUL_METRO_ELEVATOR_SERVICE_KEY=%s\\n' "\$\{DATA_GO_KR_SERVICE_KEY_SECRET\}" >> "\$\{env_file\}"/,
    "DATA_GO_KR_SERVICE_KEY_SECRET 블록 안에 EASYSUBWAY_SEOUL_METRO_ELEVATOR_SERVICE_KEY 주입이 있어야 한다",
  );
});
