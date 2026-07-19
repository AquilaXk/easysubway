export function parseMolitSvgProviderIdentity(svgFileName, providerLabel) {
  const fileMatch = /^subway_a(\d{2})_l([A-Za-z0-9]+)$/.exec(svgFileName);
  const providerMatch = /^([A-Z0-9]+)\(([^()]+)\)$/.exec(providerLabel);
  if (!fileMatch || !providerMatch) return null;

  const rawLineCode = fileMatch[2];
  return {
    mreaWideCd: fileMatch[1],
    lnCd: /^\d+$/.test(rawLineCode) ? String(Number(rawLineCode)) : rawLineCode.toUpperCase(),
    railOprIsttCd: providerMatch[1],
    operatorName: providerMatch[2].trim(),
  };
}
