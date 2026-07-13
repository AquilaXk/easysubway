package com.easysubway.realtime.domain;

import java.time.Instant;

public record RealtimeArrivalObservation(
	String providerId,
	String stationId,
	String lineId,
	String providerLineId,
	String providerStationId,
	String trainNo,
	Instant providerObservedAt,
	Instant backendReceivedAt,
	Integer rawEtaSeconds,
	Integer adjustedEtaSeconds,
	String rawDirection,
	String rawDestination,
	Instant retainedUntil
) {
}
