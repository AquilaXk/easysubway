package com.easysubway.route.application.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.easysubway.profile.domain.MobilityType;
import com.easysubway.route.adapter.out.persistence.InMemoryRouteSearchRepository;
import com.easysubway.route.application.port.in.SearchRouteCommand;
import com.easysubway.route.domain.RouteNotFoundException;
import com.easysubway.route.domain.RouteSearchNotFoundException;
import com.easysubway.route.domain.RouteSearchStatus;
import com.easysubway.route.domain.RouteWarningCode;
import com.easysubway.transit.adapter.out.persistence.InMemoryTransitMasterRepository;
import com.easysubway.transit.application.port.out.LoadTransitMasterPort;
import com.easysubway.transit.domain.AccessibilityFacility;
import com.easysubway.transit.domain.DataConfidenceLevel;
import com.easysubway.transit.domain.DataQualityLevel;
import com.easysubway.transit.domain.DataSourceType;
import com.easysubway.transit.domain.Station;
import com.easysubway.transit.domain.StationExit;
import com.easysubway.transit.domain.StationLine;
import com.easysubway.transit.domain.StationNotFoundException;
import com.easysubway.transit.domain.SubwayLine;
import com.easysubway.transit.domain.TransitOperator;
import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

@DisplayName("경로 검색 서비스")
class RouteSearchServiceTest {

	private static final Clock CLOCK = Clock.fixed(Instant.parse("2026-06-13T09:00:00Z"), ZoneId.of("Asia/Seoul"));

	private final InMemoryRouteSearchRepository routeSearchRepository = new InMemoryRouteSearchRepository();
	private final RouteSearchService service = new RouteSearchService(
		routeSearchRepository,
		routeSearchRepository,
		new InMemoryTransitMasterRepository(),
		CLOCK
	);

	@Test
	@DisplayName("유모차 이동 유형은 같은 노선 직접 경로와 접근성 경고를 반환한다")
	void searchRouteReturnsDirectLineRecommendationForStroller() {
		var result = service.searchRoute(new SearchRouteCommand(
			"station-sangnoksu",
			"station-sadang",
			MobilityType.STROLLER
		));

		assertThat(result.routeSearchId()).startsWith("route-");
		assertThat(result.status()).isEqualTo(RouteSearchStatus.FOUND);
		assertThat(result.mobilityType()).isEqualTo(MobilityType.STROLLER);
		assertThat(result.originStationName()).isEqualTo("상록수");
		assertThat(result.destinationStationName()).isEqualTo("사당");
		assertThat(result.lineName()).isEqualTo("수도권 4호선");
		assertThat(result.score()).isGreaterThan(0);
		assertThat(result.steps())
			.extracting("title")
			.containsExactly(
				"상록수역에서 4호선 승강장으로 이동",
				"수도권 4호선으로 사당역까지 이동",
				"사당역에서 출구 접근성 정보를 확인"
			);
		assertThat(result.warnings())
			.extracting("code")
			.contains(RouteWarningCode.LOW_DATA_CONFIDENCE);
	}

	@Test
	@DisplayName("생성된 경로 검색 결과는 식별자로 다시 조회할 수 있다")
	void getRouteSearchReturnsStoredResult() {
		var created = service.searchRoute(new SearchRouteCommand(
			"station-sangnoksu",
			"station-sadang",
			MobilityType.SENIOR
		));

		var loaded = service.getRouteSearch(created.routeSearchId());

		assertThat(loaded).isEqualTo(created);
	}

	@Test
	@DisplayName("휠체어 이동 유형은 계단만 있는 역 접근 경로를 차단한다")
	void wheelchairRouteBlocksStairOnlyStationAccess() {
		var repository = new InMemoryRouteSearchRepository();
		var stairOnlyService = new RouteSearchService(
			repository,
			repository,
			new StairOnlyTransitMasterPort(),
			CLOCK
		);

		var result = stairOnlyService.searchRoute(new SearchRouteCommand(
			"station-a",
			"station-b",
			MobilityType.WHEELCHAIR
		));

		assertThat(result.status()).isEqualTo(RouteSearchStatus.BLOCKED);
		assertThat(result.steps()).isEmpty();
		assertThat(result.blockedReasons())
			.containsExactly("계단 없는 역 접근 경로를 확인할 수 없습니다.");
	}

	@Test
	@DisplayName("경로 검색은 존재하는 역과 공통 노선을 요구한다")
	void searchRouteRequiresExistingStationsAndSharedLine() {
		assertThatThrownBy(() -> service.searchRoute(new SearchRouteCommand(
			"missing",
			"station-sadang",
			MobilityType.SENIOR
		)))
			.isInstanceOf(StationNotFoundException.class)
			.hasMessage("역 정보를 찾을 수 없습니다.");

		var repository = new InMemoryRouteSearchRepository();
		var disconnectedService = new RouteSearchService(
			repository,
			repository,
			new DisconnectedTransitMasterPort(),
			CLOCK
		);

		assertThatThrownBy(() -> disconnectedService.searchRoute(new SearchRouteCommand(
			"station-a",
			"station-b",
			MobilityType.SENIOR
		)))
			.isInstanceOf(RouteNotFoundException.class)
			.hasMessage("연결 가능한 경로를 찾을 수 없습니다.");
	}

	@Test
	@DisplayName("알 수 없는 경로 검색 식별자는 조회할 수 없다")
	void getRouteSearchRequiresKnownRouteSearchId() {
		assertThatThrownBy(() -> service.getRouteSearch("route-missing"))
			.isInstanceOf(RouteSearchNotFoundException.class)
			.hasMessage("경로 검색 결과를 찾을 수 없습니다.");
	}

	private static class StairOnlyTransitMasterPort implements LoadTransitMasterPort {

		@Override
		public List<TransitOperator> loadOperators() {
			return List.of(operator());
		}

		@Override
		public List<SubwayLine> loadLines() {
			return List.of(line("line-a"));
		}

		@Override
		public List<Station> loadStations() {
			return List.of(station("station-a", "출발역"), station("station-b", "도착역"));
		}

		@Override
		public List<StationLine> loadStationLines() {
			return List.of(
				new StationLine("station-a", "line-a", "101", 1, "상행 / 하행"),
				new StationLine("station-b", "line-a", "102", 2, "상행 / 하행")
			);
		}

		@Override
		public List<StationExit> loadStationExits() {
			return List.of(
				new StationExit("exit-a-1", "station-a", "1", "1번 출구", BigDecimal.ONE, BigDecimal.ONE, false, true, DataConfidenceLevel.HIGH),
				new StationExit("exit-b-1", "station-b", "1", "1번 출구", BigDecimal.ONE, BigDecimal.ONE, false, true, DataConfidenceLevel.HIGH)
			);
		}

		@Override
		public List<AccessibilityFacility> loadAccessibilityFacilities() {
			return List.of();
		}
	}

	private static class DisconnectedTransitMasterPort extends StairOnlyTransitMasterPort {

		@Override
		public List<SubwayLine> loadLines() {
			return List.of(line("line-a"), line("line-b"));
		}

		@Override
		public List<StationLine> loadStationLines() {
			return List.of(
				new StationLine("station-a", "line-a", "101", 1, "상행 / 하행"),
				new StationLine("station-b", "line-b", "202", 2, "상행 / 하행")
			);
		}
	}

	private static TransitOperator operator() {
		return new TransitOperator(
			"operator-a",
			"운영사",
			"수도권",
			"https://example.com",
			"https://example.com/contact",
			DataSourceType.OFFICIAL_FILE,
			true
		);
	}

	private static SubwayLine line(String id) {
		return new SubwayLine(id, "operator-a", "테스트 노선", "#0052A4", "수도권", "T", true);
	}

	private static Station station(String id, String name) {
		return new Station(
			id,
			name,
			name,
			"수도권",
			BigDecimal.ONE,
			BigDecimal.ONE,
			DataQualityLevel.LEVEL_1,
			LocalDate.of(2026, 6, 13),
			true
		);
	}
}
