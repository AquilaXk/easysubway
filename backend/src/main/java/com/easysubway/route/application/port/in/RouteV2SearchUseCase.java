package com.easysubway.route.application.port.in;

import com.easysubway.profile.domain.MobilityType;
import com.easysubway.route.domain.ConstraintMode;
import com.easysubway.route.domain.RouteSearchResult;
import java.time.OffsetDateTime;
import java.util.List;

public interface RouteV2SearchUseCase {

	RouteV2Plan search(SearchRouteV2Command command);

	record SearchRouteV2Command(
		String originStationId,
		String destinationStationId,
		OffsetDateTime departureTime,
		MobilityType mobilityType,
		ConstraintMode constraintMode,
		boolean useRealtime,
		int maxTransfers,
		int alternativeCount
	) {
	}

	record RouteV2Plan(
		List<RouteSearchResult> itineraries,
		List<String> statuses,
		String plannerAdr
	) {
	}
}
