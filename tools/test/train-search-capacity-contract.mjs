export function validateSearchPayload(payload, parameters, workload) {
  if (payload?.success !== true
    || !Array.isArray(payload?.data?.outbound)
    || !Array.isArray(payload.data.inbound)) return false;
  const rows = [...payload.data.outbound, ...payload.data.inbound];
  const rowsMatchRequest = rows.every((row) => (
    row?.departureStationId === parameters.departureStationId
    && row?.arrivalStationId === parameters.arrivalStationId
    && typeof row?.departureAt === "string"
    && row.departureAt.slice(0, 10) === parameters.departureDate
    && row?.trainType === parameters.trainType
    && row.trainType !== "ITX_CHEONGCHUN"
  ));
  const repeatedHasFareRows = workload !== "repeated" || (
    rows.length > 0
    && rows.every((row) => Number.isInteger(row?.adultFareWon) && row.adultFareWon > 0)
  );
  return rowsMatchRequest && repeatedHasFareRows;
}
