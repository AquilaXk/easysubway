import assert from "node:assert/strict";
import test from "node:test";
import { filterLcov } from "./filter-mobile-lcov.mjs";

test("filter-mobile-lcov는 생성 Dart 파일을 제거하고 일반 소스는 유지한다", () => {
  const input = [
    "SF:lib/features/home/home_page.dart",
    "DA:1,1",
    "end_of_record",
    "SF:lib/features/home/home_page.g.dart",
    "DA:1,1",
    "end_of_record",
    "SF:lib/models/station.freezed.dart",
    "DA:2,0",
    "end_of_record",
    "SF:lib/generated/assets.dart",
    "DA:3,1",
    "end_of_record",
    "",
  ].join("\n");

  const result = filterLcov(input);

  assert.equal(result.keptFiles, 1);
  assert.equal(result.removedFiles, 3);
  assert.match(result.content, /SF:lib\/features\/home\/home_page\.dart/);
  assert.doesNotMatch(result.content, /\.g\.dart/);
  assert.doesNotMatch(result.content, /\.freezed\.dart/);
  assert.doesNotMatch(result.content, /lib\/generated\//);
});
