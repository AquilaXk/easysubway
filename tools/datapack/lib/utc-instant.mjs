export function requiredUtcInstant(value, label) {
  if (typeof value !== "string" || !value.endsWith("Z")) {
    throw new Error(`${label} must be an RFC 3339 UTC timestamp`);
  }
  const millis = Date.parse(value);
  if (!Number.isFinite(millis)) {
    throw new Error(`${label} must be an RFC 3339 UTC timestamp`);
  }
  return millis;
}
