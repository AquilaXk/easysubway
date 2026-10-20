import assert from "node:assert/strict";
import test from "node:test";

import { codepointCompare } from "./codepoint-compare.mjs";

// 기본 Array.prototype.sort()는 UTF-16 code unit 순서다. 명시 비교자로 바꿔도 결정적 산출물의 순서가 같아야 한다.
const SAMPLES = ["b", "a", "B", "A", "10", "9", "가", "나", "각", "힣", "ㄱ", "😀", "～", "퟿", "", "", "ab", "a\u0000b"];

test("codepointCompare returns the ordering of the default code unit sort", () => {
  assert.deepEqual([...SAMPLES].sort(codepointCompare), [...SAMPLES].sort());
});

test("codepointCompare orders Hangul syllables by code unit, independent of locale collation", () => {
  assert.deepEqual(["힣", "나", "가", "각"].sort(codepointCompare), ["가", "각", "나", "힣"]);
});

test("codepointCompare orders a surrogate pair by its high surrogate, not by code point", () => {
  // U+1F600(😀)은 code point로는 U+FF5E보다 크지만 UTF-16 code unit으로는 \uD83D < ～이다.
  assert.equal(codepointCompare("\u{1F600}", "～"), -1);
  assert.deepEqual(["～", "\u{1F600}"].sort(codepointCompare), ["\u{1F600}", "～"]);
});

test("codepointCompare is a three-way comparator", () => {
  assert.equal(codepointCompare("a", "b"), -1);
  assert.equal(codepointCompare("b", "a"), 1);
  assert.equal(codepointCompare("a", "a"), 0);
});
