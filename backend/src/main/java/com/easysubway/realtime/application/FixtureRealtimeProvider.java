package com.easysubway.realtime.application;

import com.easysubway.realtime.domain.RealtimeArrival;
import com.easysubway.realtime.domain.RealtimeTrainPosition;
import java.util.List;

final class FixtureRealtimeProvider implements RealtimeProvider {

	private static final String PROVIDER_RECEIVED_AT = "2026-06-26T08:00:00Z";

	@Override
	public List<RealtimeArrival> arrivals(RealtimeQuery query) {
		return List.of(new RealtimeArrival(
			"4",
			"상록수",
			"당고개",
			"상행",
			"4123",
			180,
			"3분 후",
			"전역 출발",
			PROVIDER_RECEIVED_AT
		));
	}

	@Override
	public List<RealtimeTrainPosition> trainPositions(RealtimeQuery query) {
		return List.of(new RealtimeTrainPosition(
			"4",
			"상록수",
			"4123",
			"운행중",
			"상행",
			"당고개",
			PROVIDER_RECEIVED_AT
		));
	}
}
