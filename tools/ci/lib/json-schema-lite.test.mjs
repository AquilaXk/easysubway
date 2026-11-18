import test from "node:test";
import assert from "node:assert/strict";
import { validateSchema } from "./json-schema-lite.mjs";

test("required 필드 누락을 잡는다", () => {
  const schema = {
    type: "object",
    required: ["schemaVersion"],
    properties: { schemaVersion: { type: "integer" } },
  };

  const result = validateSchema(schema, {});

  assert.equal(result.ok, false);
  assert.match(result.errors[0], /schemaVersion/);
});

test("타입·enum·pattern·배열 items·additionalProperties를 검증한다", () => {
  const schema = {
    type: "object",
    required: ["id", "sha256", "packs"],
    additionalProperties: false,
    properties: {
      id: { type: "string", enum: ["core", "capital"] },
      sha256: { type: "string", pattern: "^[0-9a-f]{64}$" },
      packs: { type: "array", items: { type: "object" }, minItems: 1 },
    },
  };

  assert.equal(validateSchema(schema, { id: "core", sha256: "a".repeat(64), packs: [{}] }).ok, true);
  assert.equal(validateSchema(schema, { id: "seoul", sha256: "x", packs: [] }).ok, false);
  assert.equal(
    validateSchema(schema, { id: "core", sha256: "a".repeat(64), packs: [{}], extra: 1 }).ok,
    false,
  );
});

test("uniqueItems는 scalar와 객체의 중복을 거부한다", () => {
  const schema = { type: "array", uniqueItems: true };

  assert.equal(validateSchema(schema, ["a", "b"]).ok, true);
  assert.equal(validateSchema(schema, ["a", "a"]).ok, false);
  assert.equal(validateSchema(schema, [{ id: 1 }, { id: 1 }]).ok, false);
});

test("minLength는 Unicode code point 기준으로 문자열 길이를 검증한다", () => {
  const schema = { type: "string", minLength: 1 };

  assert.equal(validateSchema(schema, "a").ok, true);
  assert.equal(validateSchema(schema, "😀").ok, true);
  assert.equal(validateSchema(schema, "").ok, false);
  assert.throws(() => validateSchema({ type: "string", minLength: -1 }, "a"), /0 이상의 정수/);
  assert.throws(() => validateSchema({ type: "array", minLength: 1 }, []), /type: string/);
});

test("minimum과 maximum은 유한한 inclusive numeric bound를 검증한다", () => {
  const schema = { type: "integer", minimum: 1, maximum: 3 };

  assert.equal(validateSchema(schema, 1).ok, true);
  assert.equal(validateSchema(schema, 3).ok, true);
  assert.equal(validateSchema(schema, 0).ok, false);
  assert.equal(validateSchema(schema, 4).ok, false);
  assert.throws(() => validateSchema({ type: "integer", maximum: "3" }, 2), /유한한 숫자/);
  assert.throws(() => validateSchema({ type: "number", minimum: Number.NaN }, 2), /유한한 숫자/);
  assert.throws(() => validateSchema({ type: "number", maximum: Number.POSITIVE_INFINITY }, 2), /유한한 숫자/);
  assert.throws(() => validateSchema({ type: "integer", minimum: 4, maximum: 3 }, 3), /minimum.*maximum/);
});

test("중첩 객체 오류 경로를 점 표기로 보고한다", () => {
  const schema = {
    type: "object",
    properties: {
      packs: { type: "array", items: { type: "object", required: ["asset"] } },
    },
  };

  const result = validateSchema(schema, { packs: [{}] });

  assert.equal(result.ok, false);
  assert.match(result.errors[0], /packs\.0\.asset/);
});

test("type 배열은 명시한 scalar union만 허용한다", () => {
  const schema = { type: ["integer", "string", "null"] };

  assert.equal(validateSchema(schema, 1000).ok, true);
  assert.equal(validateSchema(schema, "unlimited").ok, true);
  assert.equal(validateSchema(schema, null).ok, true);
  assert.equal(validateSchema(schema, {}).ok, false);
  assert.equal(validateSchema(schema, []).ok, false);
});

test("객체·배열 전용 키워드는 type 누락 시 스키마 작성 오류로 실패한다", () => {
  assert.throws(
    () => validateSchema({ properties: { id: { type: "string" } } }, { id: "core" }),
    /type: object/,
  );
  assert.throws(
    () => validateSchema({ items: { type: "string" } }, ["core"]),
    /type: array/,
  );
});

test("date·date-time·uri format은 달력과 URL 구조까지 검증한다", () => {
  const schema = {
    type: "object",
    properties: {
      policyVersion: { type: "string", format: "date" },
      reviewedAt: { type: "string", format: "date-time" },
      termsUrl: { type: "string", format: "uri", pattern: "^https://" },
    },
  };

  assert.equal(validateSchema(schema, {
    policyVersion: "2026-07-15",
    reviewedAt: "2026-07-15T09:00:00.123456+09:00",
    termsUrl: "https://example.invalid/terms",
  }).ok, true);
  assert.equal(validateSchema(schema, {
    policyVersion: "2026-02-31",
    reviewedAt: "2026-07-15T00:00:00Z",
    termsUrl: "https://example.invalid/terms",
  }).ok, false);
  assert.equal(validateSchema(schema, {
    policyVersion: "2026-07-15",
    reviewedAt: "2026-07-15T25:00:00Z",
    termsUrl: "https://example.invalid/terms",
  }).ok, false);
  assert.equal(validateSchema(schema, {
    policyVersion: "2026-07-15",
    reviewedAt: "2026-07-15T00:00:00Z",
    termsUrl: "https://",
  }).ok, false);
  assert.equal(validateSchema({ type: "string", format: "uri" }, "urn:example:source").ok, true);
  for (const malformed of [
    "https://example.invalid/has space",
    "https://example.invalid/%zz",
    String.raw`https:\example.invalid/path`,
  ]) {
    assert.equal(validateSchema({ type: "string", format: "uri" }, malformed).ok, false, malformed);
  }
});

test("allOf는 모든 하위 스키마 조건을 동시에 검증한다", () => {
  const schema = {
    type: "object",
    allOf: [
      { type: "object", required: ["id"] },
      { type: "object", properties: { id: { type: "string" } } },
      { type: "object", properties: { score: { type: "integer", minimum: 0 } } },
    ],
  };

  assert.equal(validateSchema(schema, { id: "alpha", score: 10 }).ok, true);
  assert.equal(validateSchema(schema, { id: "alpha", score: -1 }).ok, false);
  assert.equal(validateSchema(schema, { score: 10 }).ok, false);
});

test("if/then/else는 조건부 스키마 분기를 검증한다", () => {
  const schema = {
    type: "object",
    if: {
      type: "object",
      required: ["role"],
      properties: { role: { const: "admin" } },
    },
    then: {
      type: "object",
      required: ["adminToken"],
      properties: { adminToken: { type: "string", minLength: 8 } },
    },
    else: {
      type: "object",
      not: {
        type: "object",
        required: ["adminToken"],
      },
    },
  };

  assert.equal(validateSchema(schema, { role: "admin", adminToken: "secret123" }).ok, true);
  assert.equal(validateSchema(schema, { role: "admin", adminToken: "short" }).ok, false);
  assert.equal(validateSchema(schema, { role: "admin" }).ok, false);
  assert.equal(validateSchema(schema, { role: "user" }).ok, true);
  assert.equal(validateSchema(schema, { role: "user", adminToken: "secret123" }).ok, false);
});

test("maxDepth(기본 64)를 초과한 깊은 중첩은 RangeError 없이 구조화된 오류로 fail-closed 한다", () => {
  const recursiveSchema = { type: "object", properties: {} };
  recursiveSchema.properties.next = recursiveSchema;

  function makeNested(depth) {
    let node = { leaf: true };
    for (let i = 0; i < depth; i += 1) {
      node = { next: node };
    }
    return node;
  }

  // depth 64(루트 + 64단계 중첩)까지는 통과
  const validAtLimit = validateSchema(recursiveSchema, makeNested(64));
  assert.equal(validAtLimit.ok, true);

  // depth 65부터는 스택 오버플로 없이 구조화된 오류 반환
  const exceeded = validateSchema(recursiveSchema, makeNested(65));
  assert.equal(exceeded.ok, false);
  assert.match(exceeded.errors[0], /^\$(\.next){65}:.*깊이/);

  // 매우 깊은 중첩(5000단계)도 RangeError 없이 즉시 차단
  const extreme = validateSchema(recursiveSchema, makeNested(5000));
  assert.equal(extreme.ok, false);
  assert.match(extreme.errors[0], /깊이/);

  // not/if/oneOf 분기 내부에서 깊이 초과 시에도 fail-open 없이 실패해야 함
  const notSchema = { type: "object", not: recursiveSchema };
  assert.equal(validateSchema(notSchema, makeNested(70)).ok, false);

  const ifElseSchema = {
    type: "object",
    if: recursiveSchema,
    then: { type: "object" },
    else: { type: "object" },
  };
  assert.equal(validateSchema(ifElseSchema, makeNested(70)).ok, false);

  const oneOfSchema = {
    type: "object",
    oneOf: [
      recursiveSchema,
      { type: "object", properties: { impossible: { const: "never" } }, required: ["impossible"] },
    ],
  };
  assert.equal(validateSchema(oneOfSchema, makeNested(70)).ok, false);
});

test("minLength와 maxLength는 surrogate pair와 lone surrogate를 code point 기준으로 검증한다", () => {
  const schema = { type: "string", minLength: 2, maxLength: 3 };

  assert.equal(validateSchema(schema, "😀").ok, false);
  assert.equal(validateSchema(schema, "😀a").ok, true);
  assert.equal(validateSchema(schema, "😀👍🇰").ok, true);
  assert.equal(validateSchema(schema, "😀👍a!").ok, false);
  // lone surrogate(UTF-16 1단위)도 [...str].length와 동일하게 1 code point로 계산
  assert.equal(validateSchema(schema, "\uD800a").ok, true);
  assert.equal(validateSchema(schema, "\uD800\uDC00").ok, false); // valid surrogate pair = 1 code point

  assert.throws(() => validateSchema({ type: "string", maxLength: -1 }, "a"), /0 이상의 정수/);
  assert.throws(() => validateSchema({ type: "array", maxLength: 2 }, []), /type: string/);
  assert.throws(() => validateSchema({ type: "string", minLength: 4, maxLength: 3 }, "abcd"), /minLength.*maxLength/);
});

test("pattern 정규식 캐시는 상한(4096) 초과 시에도 안정적으로 검증 결과를 유지한다", () => {
  for (let i = 0; i < 4500; i += 1) {
    const schema = { type: "string", pattern: `^token-${i}$` };
    assert.equal(validateSchema(schema, `token-${i}`).ok, true);
    assert.equal(validateSchema(schema, `wrong-${i}`).ok, false);
  }
  const repeated = { type: "string", pattern: "^[0-9a-f]{8}$" };
  for (let i = 0; i < 1000; i += 1) {
    assert.equal(validateSchema(repeated, "deadbeef").ok, true);
    assert.equal(validateSchema(repeated, "xyz").ok, false);
  }
});

test("uniqueItems는 대용량 배열(10000건), 키 순서 다른 객체, null/undefined, 깊이 초과를 O(N)으로 처리한다", () => {
  const schema = { type: "array", uniqueItems: true };

  // 키 순서가 달라도 동일 객체로 판정
  assert.equal(validateSchema(schema, [{ a: 1, b: 2 }, { b: 2, a: 1 }]).ok, false);
  // 타입 구분(null, undefined, "null", "1", 1, true, "true")
  assert.equal(validateSchema(schema, [null, undefined, "null", "1", 1, true, "true"]).ok, true);
  assert.equal(validateSchema(schema, [undefined, undefined]).ok, false);

  // 대용량 배열(10,000건) 검증이 빠르게 완료되는지 확인
  const largeUnique = Array.from({ length: 10000 }, (_, i) => ({ id: i, tags: ["a", String(i)] }));
  const start = performance.now();
  assert.equal(validateSchema(schema, largeUnique).ok, true);
  const largeDuplicate = [...largeUnique, { tags: ["a", "9999"], id: 9999 }];
  assert.equal(validateSchema(schema, largeDuplicate).ok, false);
  const elapsedMs = performance.now() - start;
  assert.ok(elapsedMs < 2000, `uniqueItems took too long: ${elapsedMs}ms`);

  // uniqueItems 배열 내부의 깊이 초과 객체도 fail-closed
  let deep = 1;
  for (let i = 0; i < 70; i += 1) {
    deep = { x: deep };
  }
  const deepResult = validateSchema(schema, [deep]);
  assert.equal(deepResult.ok, false);
  assert.match(deepResult.errors[0], /깊이/);
});
