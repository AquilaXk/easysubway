function isDigits(value) {
  return value.length > 0 && [...value].every((character) => character >= "0" && character <= "9");
}

function isIdentifier(value, rejectNumericLeadingZero) {
  return value.length > 0
    && [...value].every((character) => (
      (character >= "0" && character <= "9")
      || (character >= "A" && character <= "Z")
      || (character >= "a" && character <= "z")
      || character === "-"
    ))
    && (!rejectNumericLeadingZero || !isDigits(value) || value === "0" || value[0] !== "0");
}

export function isSemVer(value) {
  if (typeof value !== "string" || value.length === 0 || value.length > 255) return false;
  const buildParts = value.split("+");
  if (buildParts.length > 2) return false;
  const [version, build] = buildParts;
  if (build !== undefined && !build.split(".").every((identifier) => isIdentifier(identifier, false))) return false;

  const prereleaseSeparator = version.indexOf("-");
  const core = prereleaseSeparator === -1 ? version : version.slice(0, prereleaseSeparator);
  const prerelease = prereleaseSeparator === -1 ? undefined : version.slice(prereleaseSeparator + 1);
  if (prerelease !== undefined && !prerelease.split(".").every((identifier) => isIdentifier(identifier, true))) return false;
  const coreIdentifiers = core.split(".");
  return coreIdentifiers.length === 3
    && coreIdentifiers.every((identifier) => isDigits(identifier) && (identifier === "0" || identifier[0] !== "0"));
}
