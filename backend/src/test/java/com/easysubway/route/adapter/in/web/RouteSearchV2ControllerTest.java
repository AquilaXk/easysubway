package com.easysubway.route.adapter.in.web;

import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.easysubway.profile.domain.MobilityType;
import com.easysubway.route.application.port.in.RouteSearchUseCase;
import com.easysubway.route.domain.RouteSearchResult;
import com.easysubway.route.domain.RouteSearchStatus;
import com.easysubway.route.domain.RouteStep;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest(properties = {
	"easysubway.admin.username=admin-user",
	"easysubway.admin.password=admin-test-password"
})
@AutoConfigureMockMvc
@DisplayName("공개 경로 검색 V2 API")
class RouteSearchV2ControllerTest {

	@Autowired
	private MockMvc mockMvc;

	@MockitoBean
	private RouteSearchUseCase routeSearchUseCase;

	@Test
	@DisplayName("모바일 V2 계약으로 itinerary와 leg 단위 ETA 필드를 반환한다")
	void routeSearchV2ReturnsItineraryContract() throws Exception {
		when(routeSearchUseCase.searchRoute(argThat(command ->
			"station-sangnoksu".equals(command.originStationId())
				&& "station-sadang".equals(command.destinationStationId())
				&& command.mobilityType() == MobilityType.STROLLER
		))).thenReturn(foundRouteSearch());

		mockMvc.perform(post("/api/v2/routes/search")
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
					{
					  "originStationId": "station-sangnoksu",
					  "destinationStationId": "station-sadang",
					  "departureTime": "2026-06-30T09:15:00+09:00",
					  "mobilityType": "STROLLER",
					  "constraintMode": "STRICT_STEP_FREE",
					  "useRealtime": true,
					  "maxTransfers": 3,
					  "alternativeCount": 3
					}
					"""))
			.andExpect(status().isOk())
			.andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
			.andExpect(jsonPath("$.success").value(true))
			.andExpect(jsonPath("$.data.contractVersion").value("ROUTE_SEARCH_V2"))
			.andExpect(jsonPath("$.data.originStationId").value("station-sangnoksu"))
			.andExpect(jsonPath("$.data.destinationStationId").value("station-sadang"))
			.andExpect(jsonPath("$.data.departureTime").value("2026-06-30T09:15:00+09:00"))
			.andExpect(jsonPath("$.data.constraintMode").value("STRICT_STEP_FREE"))
			.andExpect(jsonPath("$.data.useRealtime").value(true))
			.andExpect(jsonPath("$.data.maxTransfers").value(3))
			.andExpect(jsonPath("$.data.alternativeCount").value(3))
			.andExpect(jsonPath("$.data.statuses[0]").value("FOUND"))
			.andExpect(jsonPath("$.data.statuses[1]").value("BLOCKED_ACCESSIBILITY"))
			.andExpect(jsonPath("$.data.statuses[2]").value("NO_TIMETABLE_SERVICE"))
			.andExpect(jsonPath("$.data.statuses[3]").value("REALTIME_UNAVAILABLE_PLANNED_USED"))
			.andExpect(jsonPath("$.data.statuses[4]").value("UNSUPPORTED_REGION"))
			.andExpect(jsonPath("$.data.statuses[5]").value("ROUTE_GRAPH_UNKNOWN"))
			.andExpect(jsonPath("$.data.itineraries[0].itineraryId").value("route-search-1-primary"))
			.andExpect(jsonPath("$.data.itineraries[0].status").value("FOUND"))
			.andExpect(jsonPath("$.data.itineraries[0].plannedArrivalTime").value("2026-06-30T09:22:00+09:00"))
			.andExpect(jsonPath("$.data.itineraries[0].realtimeArrivalTime").doesNotExist())
			.andExpect(jsonPath("$.data.itineraries[0].etaSource").value("STATIC_BACKEND_V1"))
			.andExpect(jsonPath("$.data.itineraries[0].etaConfidence").value("LOW"))
			.andExpect(jsonPath("$.data.itineraries[0].durationSeconds").value(420))
			.andExpect(jsonPath("$.data.itineraries[0].transferCount").value(0))
			.andExpect(jsonPath("$.data.itineraries[0].walkingDistanceMeters").value(180))
			.andExpect(jsonPath("$.data.itineraries[0].accessibilityRisk.level").value("REVIEW_REQUIRED"))
			.andExpect(jsonPath("$.data.itineraries[0].legs[0].legType").value("ACCESS"))
			.andExpect(jsonPath("$.data.itineraries[0].legs[0].plannedDepartureTime").value("2026-06-30T09:15:00+09:00"))
			.andExpect(jsonPath("$.data.itineraries[0].legs[0].plannedArrivalTime").value("2026-06-30T09:22:00+09:00"))
			.andExpect(jsonPath("$.data.itineraries[0].legs[0].waitTimeSeconds").value(0))
			.andExpect(jsonPath("$.data.itineraries[0].legs[0].slackSeconds").value(0))
			.andExpect(jsonPath("$.data.itineraries[0].legs[0].etaSource").value("STATIC_BACKEND_V1"))
			.andExpect(jsonPath("$.data.itineraries[0].commercialEtaEligible").value(false));
	}

	private RouteSearchResult foundRouteSearch() {
		return new RouteSearchResult(
			"route-search-1",
			"station-sangnoksu",
			"상록수",
			"station-sadang",
			"사당",
			MobilityType.STROLLER,
			RouteSearchStatus.FOUND,
			"line-4",
			"수도권 4호선",
			18,
			List.of(new RouteStep(
				1,
				"entry",
				"상록수역 진입",
				"엘리베이터를 이용해 승강장으로 이동",
				"line-4",
				"수도권 4호선",
				"station-sangnoksu",
				"station-sangnoksu",
				7,
				180,
				false,
				"VERIFIED",
				false,
				"STATIC_BACKEND_V1",
				"STATIC_BACKEND_V1",
				"LEGACY_STATIC"
			)),
			List.of(),
			List.of(),
			LocalDateTime.of(2026, 6, 30, 9, 0)
		);
	}
}
