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
