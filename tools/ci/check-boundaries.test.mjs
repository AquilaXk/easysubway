import test from "node:test";
import assert from "node:assert/strict";
import { findViolations } from "./check-boundaries.mjs";

test("금지 패턴이 있는 파일을 위반으로 보고한다", () => {
  const violations = findViolations(
    [{ from: "fixtures-root/a", pattern: "apps/mobile", reason: "테스트" }],
    { root: "tools/ci/fixtures/boundary-check", allowlist: [] },
  );

  assert.equal(violations.length, 1);
  assert.match(violations[0].file, /bad\.txt$/);
});

test("allowlist 항목은 만료일이 지나면 위반으로 되돌린다", () => {
  const violations = findViolations(
    [{ from: "fixtures-root/a", pattern: "apps/mobile", reason: "테스트" }],
    {
      root: "tools/ci/fixtures/boundary-check",
      allowlist: [{ file: "fixtures-root/a/bad.txt", reason: "이관 중", expires: "2000-01-01" }],
    },
  );

  assert.equal(violations.length, 1);
  assert.match(violations[0].why, /만료/);
});

test("allowlist 항목은 만료일을 파싱할 수 없으면 위반으로 되돌린다", () => {
  const violations = findViolations(
    [{ from: "fixtures-root/a", pattern: "apps/mobile", reason: "테스트" }],
    {
      root: "tools/ci/fixtures/boundary-check",
      allowlist: [{ file: "fixtures-root/a/bad.txt", reason: "이관 중", expires: "not-a-date" }],
    },
  );

  assert.equal(violations.length, 1);
  assert.match(violations[0].why, /만료일 불량/);
});
