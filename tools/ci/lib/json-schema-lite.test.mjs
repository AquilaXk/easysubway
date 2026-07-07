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
