import { codepointCompare } from "../../lib/codepoint-compare.mjs";

export const DEFAULT_MAX_DEPTH = 64;
const MAX_PATTERN_CACHE_ENTRIES = 4096;
const PATTERN_CACHE = new Map();

const SUPPORTED = new Set([
  "$id",
  "$schema",
  "additionalProperties",
  "const",
  "description",
  "enum",
  "format",
  "items",
  "maxItems",
  "maxLength",
  "maximum",
  "minItems",
  "minLength",
  "minimum",
  "not",
  "oneOf",
  "pattern",
  "properties",
  "required",
  "title",
  "type",
  "uniqueItems",
  "allOf",
  "if",
  "then",
  "else",
]);

class MaxDepthExceededError extends Error {
  constructor(path, maxDepth) {
    super(`${path}: 최대 검증 깊이(${maxDepth}) 초과`);
    this.path = path;
  }
}

export function validateSchema(schema, value, options = {}) {
  const maxDepth = options?.maxDepth ?? DEFAULT_MAX_DEPTH;
  if (!Number.isInteger(maxDepth) || maxDepth < 0) {
    throw new Error("json-schema-lite: maxDepth는 0 이상의 정수여야 합니다");
  }
  const errors = [];
  try {
    walk(schema, value, "$", errors, 0, maxDepth);
  } catch (error) {
    if (error instanceof MaxDepthExceededError) {
      errors.push(error.message);
      return { ok: false, errors };
    }
    throw error;
  }
  return { ok: errors.length === 0, errors };
}

function walk(schema, value, path, errors, depth, maxDepth) {
  if (depth > maxDepth) {
    throw new MaxDepthExceededError(path, maxDepth);
  }
  assertSupported(schema, path);
  validateAllOf(schema, value, path, errors, depth, maxDepth);
  validateOneOf(schema, value, path, errors, depth, maxDepth);
  validateNot(schema, value, path, errors, depth, maxDepth);
  validateIfThenElse(schema, value, path, errors, depth, maxDepth);
  if (validateScalar(schema, value, path, errors)) return;
  validateObject(schema, value, path, errors, depth, maxDepth);
  validateArray(schema, value, path, errors, depth, maxDepth);
}

function validateAllOf(schema, value, path, errors, depth, maxDepth) {
  if (schema.allOf === undefined) return;
  if (!Array.isArray(schema.allOf) || schema.allOf.length === 0) {
    throw new Error(`json-schema-lite: allOf는 비어 있지 않은 배열이어야 합니다 (${path})`);
  }
  for (const branch of schema.allOf) {
    walk(branch, value, path, errors, depth + 1, maxDepth);
  }
}

function validateIfThenElse(schema, value, path, errors, depth, maxDepth) {
  if (schema.if === undefined) return;
  const ifErrors = [];
  walk(schema.if, value, path, ifErrors, depth + 1, maxDepth);
  if (ifErrors.length === 0) {
    if (schema.then !== undefined) {
      walk(schema.then, value, path, errors, depth + 1, maxDepth);
    }
  } else if (schema.else !== undefined) {
    walk(schema.else, value, path, errors, depth + 1, maxDepth);
  }
}

function validateNot(schema, value, path, errors, depth, maxDepth) {
  if (schema.not === undefined) return;
  const candidateErrors = [];
  walk(schema.not, value, path, candidateErrors, depth + 1, maxDepth);
  if (candidateErrors.length === 0) errors.push(`${path}: not 분기와 일치하면 안 됨`);
}

function validateOneOf(schema, value, path, errors, depth, maxDepth) {
  if (schema.oneOf === undefined) return;
  if (!Array.isArray(schema.oneOf) || schema.oneOf.length === 0) {
    throw new Error(`json-schema-lite: oneOf는 비어 있지 않은 배열이어야 합니다 (${path})`);
  }
  const matches = schema.oneOf.filter((candidate) => {
    const candidateErrors = [];
    walk(candidate, value, path, candidateErrors, depth + 1, maxDepth);
    return candidateErrors.length === 0;
  }).length;
  if (matches !== 1) errors.push(`${path}: oneOf 분기 정확히 하나와 일치해야 함`);
}

function assertSupported(schema, path) {
  for (const key of Object.keys(schema)) {
    if (!SUPPORTED.has(key)) throw new Error(`json-schema-lite: 미지원 키워드 '${key}' (${path})`);
  }
}

function validateScalar(schema, value, path, errors) {
  validateStringLengthKeywords(schema, path);
  validateNumericBoundsKeywords(schema, path);
  if (schema.const !== undefined && value !== schema.const) {
    errors.push(`${path}: const ${JSON.stringify(schema.const)} 불일치`);
    return true;
  }
  if (schema.enum && !schema.enum.includes(value)) {
    errors.push(`${path}: enum ${JSON.stringify(schema.enum)} 밖의 값`);
    return true;
  }
  if (schema.type && !matchesType(schema.type, value)) {
    errors.push(`${path}: type ${schema.type} 불일치`);
    return true;
  }
  validateString(schema, value, path, errors);
  if (typeof value === "number" && schema.minimum !== undefined && value < schema.minimum) {
    errors.push(`${path}: minimum ${schema.minimum} 미만`);
  }
  if (typeof value === "number" && schema.maximum !== undefined && value > schema.maximum) {
    errors.push(`${path}: maximum ${schema.maximum} 초과`);
  }
  return false;
}

function validateNumericBoundsKeywords(schema, path) {
  for (const keyword of ["minimum", "maximum"]) {
    if (schema[keyword] !== undefined
      && (typeof schema[keyword] !== "number" || !Number.isFinite(schema[keyword]))) {
      throw new Error(`json-schema-lite: ${keyword}은 유한한 숫자여야 합니다 (${path})`);
    }
  }
  if (schema.minimum !== undefined && schema.maximum !== undefined && schema.minimum > schema.maximum) {
    throw new Error(`json-schema-lite: minimum은 maximum 이하여야 합니다 (${path})`);
  }
}

function validateStringLengthKeywords(schema, path) {
  for (const keyword of ["minLength", "maxLength"]) {
    if (schema[keyword] === undefined) continue;
    if (schema.type !== "string") {
      throw new Error(`json-schema-lite: ${keyword} 사용 시 type: string 명시 필요 (${path})`);
    }
    if (!Number.isInteger(schema[keyword]) || schema[keyword] < 0) {
      throw new Error(`json-schema-lite: ${keyword}는 0 이상의 정수여야 합니다 (${path})`);
    }
  }
  if (schema.minLength !== undefined && schema.maxLength !== undefined && schema.minLength > schema.maxLength) {
    throw new Error(`json-schema-lite: minLength는 maxLength 이하여야 합니다 (${path})`);
  }
}

function countCodePointsUpTo(value, limit) {
  let count = 0;
  const length = value.length;
  for (let index = 0; index < length && count < limit; ) {
    const code = value.codePointAt(index);
    count += 1;
    index += code > 0xffff ? 2 : 1;
  }
  return count;
}

function getCompiledPattern(pattern) {
  let compiled = PATTERN_CACHE.get(pattern);
  if (compiled !== undefined) {
    PATTERN_CACHE.delete(pattern);
    PATTERN_CACHE.set(pattern, compiled);
    return compiled;
  }
  compiled = new RegExp(pattern);
  if (PATTERN_CACHE.size >= MAX_PATTERN_CACHE_ENTRIES) {
    const oldestKey = PATTERN_CACHE.keys().next().value;
    PATTERN_CACHE.delete(oldestKey);
  }
  PATTERN_CACHE.set(pattern, compiled);
  return compiled;
}

function validateString(schema, value, path, errors) {
  if (schema.type !== "string") return;
  if (schema.pattern && !getCompiledPattern(schema.pattern).test(value)) {
    errors.push(`${path}: pattern ${schema.pattern} 불일치`);
  }
  if (schema.minLength !== undefined || schema.maxLength !== undefined) {
    const upperLimit = schema.maxLength !== undefined ? schema.maxLength + 1 : schema.minLength;
    const codePoints = countCodePointsUpTo(value, upperLimit);
    if (schema.minLength !== undefined && codePoints < schema.minLength) {
      errors.push(`${path}: minLength ${schema.minLength} 미만`);
    }
    if (schema.maxLength !== undefined && codePoints > schema.maxLength) {
      errors.push(`${path}: maxLength ${schema.maxLength} 초과`);
    }
  }
  if (schema.format && !matchesFormat(schema.format, value)) {
    errors.push(`${path}: format ${schema.format} 불일치`);
  }
}

function matchesFormat(format, value) {
  if (format === "date") {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
    const date = new Date(`${value}T00:00:00.000Z`);
    return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
  }
  if (format === "date-time") {
    const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-]\d{2}:\d{2})$/.exec(value);
    if (!match) return false;
    const [year, month, day, hour, minute, second] = match.slice(1, 7).map(Number);
    const offset = match[7];
    const maxDay = [31, isLeapYear(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];
    if (month < 1 || month > 12 || day < 1 || day > maxDay
      || hour > 23 || minute > 59 || second > 59) return false;
    if (offset !== "Z") {
      const [offsetHour, offsetMinute] = offset.slice(1).split(":").map(Number);
      if (offsetHour > 23 || offsetMinute > 59) return false;
    }
    return true;
  }
  if (format === "uri") {
    if (!isRawUri(value)) return false;
    try {
      const parsed = new URL(value);
      return parsed.protocol !== "";
    } catch {
      return false;
    }
  }
  throw new Error(`json-schema-lite: 미지원 format '${format}'`);
}

function isRawUri(value) {
  return /^[A-Za-z0-9:/?#\[\]@!$&'()*+,;=._~%\-]+$/.test(value)
    && !/%(?![0-9A-Fa-f]{2})/.test(value);
}

function isLeapYear(year) {
  return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
}

function validateObject(schema, value, path, errors, depth, maxDepth) {
  if (schema.type !== "object") {
    if (schema.properties || schema.required) {
      throw new Error(`json-schema-lite: properties/required 사용 시 type: object 명시 필요 (${path})`);
    }
    return;
  }
  if (value === null || typeof value !== "object" || Array.isArray(value)) return;
  for (const req of schema.required ?? []) {
    if (!(req in value)) errors.push(`${dot(path, req)}: 필수 필드 누락`);
  }
  for (const [key, child] of Object.entries(value)) {
    const propSchema = schema.properties?.[key];
    if (propSchema) walk(propSchema, child, dot(path, key), errors, depth + 1, maxDepth);
    else if (schema.additionalProperties === false) errors.push(`${dot(path, key)}: 허용되지 않은 필드`);
  }
}

function canonicalizeValue(value, depth, maxDepth, path) {
  if (depth > maxDepth) {
    throw new MaxDepthExceededError(path, maxDepth);
  }
  if (value === null) return "l";
  switch (typeof value) {
    case "undefined":
      return "u";
    case "boolean":
      return value ? "t" : "f";
    case "number":
      if (Number.isNaN(value)) return "n:NaN";
      return Object.is(value, -0) ? "n:-0" : `n:${value}`;
    case "string":
      return `s:${JSON.stringify(value)}`;
    case "bigint":
      return `bi:${value.toString()}`;
    case "symbol":
      return `sym:${String(value)}`;
    case "function":
      return `fn:${value.name}`;
    default:
      break;
  }
  if (Array.isArray(value)) {
    const parts = new Array(value.length);
    for (let i = 0; i < value.length; i += 1) {
      parts[i] = i in value
        ? canonicalizeValue(value[i], depth + 1, maxDepth, dot(path, String(i)))
        : "hole";
    }
    return `[${parts.join(",")}]`;
  }
  if (value instanceof Date) {
    return `D:${value.getTime()}`;
  }
  if (value instanceof RegExp) {
    return `R:${value.source}/${value.flags}`;
  }
  const keys = Object.keys(value).sort(codepointCompare);
  const entries = new Array(keys.length);
  for (let i = 0; i < keys.length; i += 1) {
    const key = keys[i];
    entries[i] = `${JSON.stringify(key)}:${canonicalizeValue(value[key], depth + 1, maxDepth, dot(path, key))}`;
  }
  return `{${entries.join(",")}}`;
}

function hasDuplicateItems(items, depth, maxDepth, path) {
  const seen = new Set();
  for (let i = 0; i < items.length; i += 1) {
    const serialized = canonicalizeValue(items[i], depth + 1, maxDepth, dot(path, String(i)));
    if (seen.has(serialized)) {
      return true;
    }
    seen.add(serialized);
  }
  return false;
}

function validateArray(schema, value, path, errors, depth, maxDepth) {
  if (schema.type !== "array") {
    if (schema.items || schema.minItems !== undefined || schema.maxItems !== undefined || schema.uniqueItems !== undefined) {
      throw new Error(`json-schema-lite: items/minItems/maxItems/uniqueItems 사용 시 type: array 명시 필요 (${path})`);
    }
    return;
  }
  if (!Array.isArray(value)) return;
  if (schema.minItems !== undefined && value.length < schema.minItems) {
    errors.push(`${path}: minItems ${schema.minItems} 미만`);
  }
  if (schema.maxItems !== undefined && value.length > schema.maxItems) {
    errors.push(`${path}: maxItems ${schema.maxItems} 초과`);
  }
  if (schema.uniqueItems !== undefined && typeof schema.uniqueItems !== "boolean") {
    throw new Error(`json-schema-lite: uniqueItems는 boolean이어야 합니다 (${path})`);
  }
  if (schema.uniqueItems === true && hasDuplicateItems(value, depth, maxDepth, path)) {
    errors.push(`${path}: uniqueItems 중복`);
  }
  if (schema.items) {
    for (let i = 0; i < value.length; i += 1) {
      walk(schema.items, value[i], dot(path, String(i)), errors, depth + 1, maxDepth);
    }
  }
}

function matchesType(type, value) {
  if (Array.isArray(type)) {
    if (type.length === 0) throw new Error("json-schema-lite: type 배열은 비어 있을 수 없습니다");
    return type.some((candidate) => matchesType(candidate, value));
  }
  switch (type) {
    case "object":
      return value !== null && typeof value === "object" && !Array.isArray(value);
    case "array":
      return Array.isArray(value);
    case "string":
      return typeof value === "string";
    case "integer":
      return Number.isInteger(value);
    case "number":
      return typeof value === "number" && Number.isFinite(value);
    case "boolean":
      return typeof value === "boolean";
    case "null":
      return value === null;
    default:
      throw new Error(`json-schema-lite: 미지원 type '${type}'`);
  }
}

function dot(path, key) {
  return `${path}.${key}`;
}
