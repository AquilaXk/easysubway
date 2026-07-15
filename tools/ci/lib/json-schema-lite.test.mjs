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
});
