const DAY_MS = 24 * 60 * 60 * 1000;

export function deriveFreshness({
  policy,
  sourceClassId,
  basisAt,
  providerValidUntil,
  storedExpiresAt,
  evaluationAt,
}) {
  const sourceClass = policy?.sourceClasses?.find((entry) => entry.id === sourceClassId);
  if (!sourceClass || !basisAt) {
    throw new Error("SOURCE_FRESHNESS_POLICY_MISSING");
  }

  const evaluatedMillis = requiredInstant(evaluationAt, "evaluationAt");
  const basisMillis = requiredInstant(basisAt, "basisAt");
  const clockSkewMillis = requiredNonNegativeInteger(
    sourceClass.clockSkewSeconds ?? policy.clockSkewSeconds ?? 0,
    "clockSkewSeconds",
  ) * 1_000;
  if (basisMillis > evaluatedMillis + clockSkewMillis) {
    throw new Error("SOURCE_FRESHNESS_DERIVATION_MISMATCH: basisAt exceeds clock skew");
  }

  const cadence = sourceClass.reverificationCadence ?? sourceClass.maximumReverificationCadence;
  let derivedMillis = addCadence(basisMillis, cadence);
  if (providerValidUntil != null) {
    derivedMillis = Math.min(derivedMillis, requiredInstant(providerValidUntil, "providerValidUntil"));
  }
  const storedMillis = requiredInstant(storedExpiresAt, "storedExpiresAt");
  if (storedMillis !== derivedMillis) {
    throw new Error("SOURCE_FRESHNESS_DERIVATION_MISMATCH");
  }

  const stale = evaluatedMillis >= derivedMillis;
  return {
    status: stale ? "STALE" : "FRESH",
    freshnessExpiresAt: new Date(derivedMillis).toISOString(),
    reasonCodes: stale ? ["SOURCE_SNAPSHOT_EXPIRED"] : [],
  };
}

export function decideScheduledRun({
  materialChange,
  approvalValid,
  strictValidationPassed,
  publishRequired,
  publishAttempted,
  remoteValidationPassed,
}) {
  if (!strictValidationPassed) return decision("FAILED", false);
  if (materialChange && !approvalValid) return decision("CHANGE_BLOCKED", false);
  if (publishRequired && !publishAttempted) return decision("PUBLISH_REQUIRED", approvalValid);
  if (publishAttempted) {
    if (!approvalValid) return decision("FAILED", false);
    return remoteValidationPassed
      ? decision("PUBLISHED_AND_VERIFIED", true)
      : decision("FAILED", true);
  }
  return decision("NO_CHANGE_VALID", false);
}

function addCadence(basisMillis, cadence) {
  if (typeof cadence !== "string") {
    throw new Error("SOURCE_FRESHNESS_POLICY_MISSING: cadence");
  }
  const days = /^P([1-9][0-9]*)D$/.exec(cadence);
  if (days) return basisMillis + Number(days[1]) * DAY_MS;
  const years = /^P([1-9][0-9]*)Y$/.exec(cadence);
  if (years) {
    const value = new Date(basisMillis);
    value.setUTCFullYear(value.getUTCFullYear() + Number(years[1]));
    return value.getTime();
  }
  const seconds = /^PT([1-9][0-9]*)S$/.exec(cadence);
  if (seconds) return basisMillis + Number(seconds[1]) * 1_000;
  throw new Error(`SOURCE_FRESHNESS_POLICY_MISSING: unsupported cadence ${cadence}`);
}

function requiredInstant(value, label) {
  if (typeof value !== "string" || !value.endsWith("Z")) {
    throw new Error(`${label} must be an RFC 3339 UTC timestamp`);
  }
  const millis = Date.parse(value);
  if (!Number.isFinite(millis)) {
    throw new Error(`${label} must be an RFC 3339 UTC timestamp`);
  }
  return millis;
}

function requiredNonNegativeInteger(value, label) {
  if (!Number.isInteger(value) || value < 0) {
    throw new Error(`${label} must be a non-negative integer`);
  }
  return value;
}

function decision(outcome, productionWriteAllowed) {
  return { outcome, productionWriteAllowed };
}
