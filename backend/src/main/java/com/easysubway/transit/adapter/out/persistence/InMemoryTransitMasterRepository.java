package com.easysubway.transit.adapter.out.persistence;

import com.easysubway.transit.application.port.out.LoadTransitMasterPort;
import com.easysubway.transit.application.port.out.SaveAccessibilityFacilityStatusPort;
import com.easysubway.transit.application.port.out.SaveRouteEdgePort;
import com.easysubway.transit.application.port.out.SaveRouteNodePort;
import com.easysubway.transit.application.port.out.SaveStationLayoutSourcePort;
import com.easysubway.transit.application.port.out.SaveSimplifiedStationLayoutStatusPort;
import com.easysubway.transit.domain.AccessibilityFacility;
import com.easysubway.transit.domain.AccessibilityFacilityStatus;
import com.easysubway.transit.domain.AccessibilityFacilityType;
import com.easysubway.transit.domain.DataConfidenceLevel;
import com.easysubway.transit.domain.DataQualityLevel;
import com.easysubway.transit.domain.DataSourceType;
import com.easysubway.transit.domain.RouteEdge;
import com.easysubway.transit.domain.RouteEdgeType;
import com.easysubway.transit.domain.RouteNode;
import com.easysubway.transit.domain.RouteNodeType;
import com.easysubway.transit.domain.Station;
import com.easysubway.transit.domain.StationExit;
import com.easysubway.transit.domain.StationLayoutSource;
import com.easysubway.transit.domain.StationLayoutSourceType;
import com.easysubway.transit.domain.StationLine;
import com.easysubway.transit.domain.SimplifiedStationLayout;
import com.easysubway.transit.domain.SimplifiedStationLayoutConfidence;
import com.easysubway.transit.domain.SimplifiedStationLayoutStatus;
import com.easysubway.transit.domain.SubwayLine;
import com.easysubway.transit.domain.TransitOperator;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Repository;

@Repository
@Profile("!prod & !staging & !release & !prod-like")
public class InMemoryTransitMasterRepository implements
	LoadTransitMasterPort,
	SaveAccessibilityFacilityStatusPort,
	SaveStationLayoutSourcePort,
	SaveSimplifiedStationLayoutStatusPort,
	SaveRouteNodePort,
	SaveRouteEdgePort {

	private static final List<TransitOperator> OPERATORS = List.of(
		new TransitOperator(
			"seoul-metro",
			"서울교통공사",
			"수도권",
			"https://www.seoulmetro.co.kr",
			"https://www.seoulmetro.co.kr/kr/customerMain.do",
			DataSourceType.OFFICIAL_FILE,
			true
		),
		new TransitOperator(
			"korail",
			"한국철도공사",
			"수도권",
			"https://www.letskorail.com",
			"https://info.korail.com",
			DataSourceType.OFFICIAL_FILE,
			true
		)
	);

	private static final List<SubwayLine> LINES = List.of(
		new SubwayLine("seoul-4", "seoul-metro", "수도권 4호선", "#00A5DE", "수도권", "4", true),
		new SubwayLine("suin-bundang", "korail", "수인분당선", "#F5A200", "수도권", "K1", true)
	);

	private static final List<Station> STATIONS = List.of(
		new Station(
			"station-sangnoksu",
			"상록수",
			"Sangnoksu",
			"수도권",
			new BigDecimal("37.302795"),
			new BigDecimal("126.866489"),
			DataQualityLevel.LEVEL_1,
			DataSourceType.OFFICIAL_FILE,
			LocalDate.of(2026, 6, 12),
			true
		),
		new Station(
			"station-sadang",
			"사당",
			"Sadang",
			"수도권",
			new BigDecimal("37.476530"),
			new BigDecimal("126.981685"),
			DataQualityLevel.LEVEL_1,
			DataSourceType.OFFICIAL_FILE,
			LocalDate.of(2026, 6, 12),
			true
		),
		// ITX-청춘(경춘선) pilot 정차역 14곳 — Route V2 capacity evidence(#2095)가 검증하는
		// pilot scope. id·이름·정차 순서는 tools/datapack/sources/itx-cheongchun-source-timetable-20260715152903681.json
		// (stationRosters, providerStationId·providerStationName·canonicalStationId·corridorSequence,
		// 원출처 data.go.kr 열린데이터광장 KRIC API — 같은 소스의
		// korail-itx-cheongchun-station-sequence-20260713.json officialSourceUrl 참고)에서
		// 그대로 가져왔고, production 격리 클론의 실제 transit_stop_times/transit_trips
		// (service_class='ITX_CHEONGCHUN') stop_sequence 순서와 대조해 일치를 확인했다
		// (#2095). nameEn은 국립국어원 로마자 표기법(코레일 역명판 표기와 동일) 표준 변환이다.
		// region은 행정구역 기준(가평까지 경기도=수도권, 강촌부터 강원도=강원권)이며 정밀
		// 좌표가 아니므로 창작이 아니다.
		//
		// 위도·경도는 이 datapack 소스에 없고, capacity 스크립트가 검증하는 Route V2 search
		// 경로(RouteV2Planner)는 LoadTransitMasterPort/Station 좌표를 전혀 참조하지 않는다
		// (loadActiveStation()은 존재·active 여부만 확인) — 그래서 여기서는 확정 좌표를
		// 만들어내는 대신 명백히 미확정임을 알 수 있는 자리표시자 0,0을 쓴다. null을 쓰면
		// TransitMasterService의 "인근 역 검색"(distanceMeters())이 실제로 이 14역에 대해
		// NullPointerException을 낸다 — 0,0은 한국에서 수백만 km 떨어져 있어 그 기능이
		// 정상 동작하는 한 이 14역이 우연히 "인근"으로 뜰 일이 없다. 실좌표 반입은 #2098
		// real data-pack adapter 범위다.
		itxCheongchunPilotStation("station-8aa315864466", "용산", "Yongsan"),
		itxCheongchunPilotStation("station-c0679b9a6cf8", "옥수", "Oksu"),
		itxCheongchunPilotStation("station-e5cf592cf355", "왕십리", "Wangsimni"),
		itxCheongchunPilotStation("station-b819702fa7d9", "청량리", "Cheongnyangni"),
		itxCheongchunPilotStation("station-83bcb1eae340", "상봉", "Sangbong"),
		itxCheongchunPilotStation("station-b52ac4dfe64e", "퇴계원", "Toegyewon"),
		itxCheongchunPilotStation("station-2ccf5647f7f7", "사릉", "Sareung"),
		itxCheongchunPilotStation("station-f3d9c93ba7d6", "평내호평", "Pyeongnae-Hopyeong"),
		itxCheongchunPilotStation("station-661ff65ea040", "마석", "Maseok"),
		itxCheongchunPilotStation("station-6c1f50a5aa3b", "청평", "Cheongpyeong"),
		itxCheongchunPilotStation("station-4f6045ff9103", "가평", "Gapyeong"),
		itxCheongchunPilotStation("station-30ba86472e55", "강촌", "Gangchon", "강원권"),
		itxCheongchunPilotStation("station-d5e344125b52", "남춘천", "Namchuncheon", "강원권"),
		itxCheongchunPilotStation("station-dd14cfb89cbc", "춘천", "Chuncheon", "강원권")
	);

	private static Station itxCheongchunPilotStation(String id, String nameKo, String nameEn) {
		return itxCheongchunPilotStation(id, nameKo, nameEn, "수도권");
	}

	private static Station itxCheongchunPilotStation(String id, String nameKo, String nameEn, String region) {
		return new Station(
			id,
			nameKo,
			nameEn,
			region,
			BigDecimal.ZERO,
			BigDecimal.ZERO,
			DataQualityLevel.LEVEL_1,
			DataSourceType.OFFICIAL_FILE,
			LocalDate.of(2026, 7, 15),
			true
		);
	}

	private static final List<StationLine> STATION_LINES = List.of(
		new StationLine("station-sangnoksu", "seoul-4", "448", 48, "당고개 방면 / 오이도 방면"),
		new StationLine("station-sadang", "seoul-4", "433", 33, "당고개 방면 / 오이도 방면")
	);

	private static final List<StationExit> STATION_EXITS = List.of(
		new StationExit(
			"exit-sangnoksu-1",
			"station-sangnoksu",
			"1",
			"1번 출구",
			new BigDecimal("37.302421"),
			new BigDecimal("126.866221"),
			true,
			false,
			DataConfidenceLevel.HIGH,
			DataSourceType.OFFICIAL_FILE
		),
		new StationExit(
			"exit-sangnoksu-2",
			"station-sangnoksu",
			"2",
			"2번 출구",
			new BigDecimal("37.303041"),
			new BigDecimal("126.866768"),
			false,
			true,
			DataConfidenceLevel.MEDIUM,
			DataSourceType.OFFICIAL_FILE
		),
		new StationExit(
			"exit-sadang-2",
			"station-sadang",
			"2",
			"2번 출구",
			new BigDecimal("37.476208"),
			new BigDecimal("126.982157"),
			true,
			false,
			DataConfidenceLevel.HIGH,
			DataSourceType.OFFICIAL_FILE
		)
	);

	private static final List<StationLayoutSource> STATION_LAYOUT_SOURCES = List.of(
		// 저작권 리스크가 있는 원본 도면은 저장하지 않고, 구조도 단순화에 사용한 출처 메타데이터만 보관한다.
		new StationLayoutSource(
			"layout-source-sangnoksu-station-map",
			"station-sangnoksu",
			StationLayoutSourceType.OPERATOR_DIAGRAM,
			"상록수역 역사 안내도",
			"https://www.seoulmetro.co.kr",
			"운영기관 안내도 확인용",
			false,
			true,
			LocalDate.of(2026, 6, 12),
			LocalDate.of(2026, 6, 12)
		)
	);

	private static final List<SimplifiedStationLayout> SIMPLIFIED_STATION_LAYOUTS = List.of(
		new SimplifiedStationLayout(
			"layout-sangnoksu-draft",
			"station-sangnoksu",
			1,
			SimplifiedStationLayoutStatus.DRAFT,
			List.of("layout-source-sangnoksu-station-map"),
			SimplifiedStationLayoutConfidence.OFFICIAL_DIAGRAM_REFERENCED,
			"B1",
			"{\"nodes\":[],\"edges\":[]}",
			null,
			"admin-user",
			null,
			null,
			LocalDate.of(2026, 6, 12)
		)
	);

	private static final List<RouteNode> ROUTE_NODES = List.of(
		new RouteNode(
			"node-sangnoksu-elevator-1",
			"station-sangnoksu",
			RouteNodeType.ELEVATOR,
			"1번 출구 엘리베이터",
			"B1",
			new BigDecimal("37.302421"),
			new BigDecimal("126.866221"),
			"facility-sangnoksu-elevator-1",
			"layout-sangnoksu-draft",
			120,
			240,
			"엘리베이터",
			"휠체어 이동 가능"
		),
		new RouteNode(
			"node-sangnoksu-faregate",
			"station-sangnoksu",
			RouteNodeType.FAREGATE,
			"개찰구",
			"B1",
			null,
			null,
			null,
			"layout-sangnoksu-draft",
			260,
			240,
			"개찰구",
			null
		)
	);

	private static final List<RouteEdge> ROUTE_EDGES = List.of(
		new RouteEdge(
			"edge-sangnoksu-elevator-to-faregate",
			"station-sangnoksu",
			"node-sangnoksu-elevator-1",
			"node-sangnoksu-faregate",
			RouteEdgeType.WALK,
			28,
			75,
			false,
			true,
			false,
			1,
			2,
			92,
			true
		)
	);

	private final Map<String, AccessibilityFacility> accessibilityFacilities = new LinkedHashMap<>();
	private final Map<String, StationLayoutSource> stationLayoutSources = new LinkedHashMap<>();
	private final Map<String, SimplifiedStationLayout> simplifiedStationLayouts = new LinkedHashMap<>();
	private final Map<String, RouteNode> routeNodes = new LinkedHashMap<>();
	private final Map<String, RouteEdge> routeEdges = new LinkedHashMap<>();

	public InMemoryTransitMasterRepository() {
		seedAccessibilityFacilities();
		seedStationLayoutSources();
		seedSimplifiedStationLayouts();
		seedRouteNodes();
		seedRouteEdges();
	}

	@Override
	public List<TransitOperator> loadOperators() {
		return OPERATORS;
	}

	@Override
	public List<SubwayLine> loadLines() {
		return LINES;
	}

	@Override
	public List<Station> loadStations() {
		return STATIONS;
	}

	@Override
	public List<StationLine> loadStationLines() {
		return STATION_LINES;
	}

	@Override
	public List<StationExit> loadStationExits() {
		return STATION_EXITS;
	}

	@Override
	public List<AccessibilityFacility> loadAccessibilityFacilities() {
		return List.copyOf(accessibilityFacilities.values());
	}

	@Override
	public List<StationLayoutSource> loadStationLayoutSources() {
		return List.copyOf(stationLayoutSources.values());
	}

	@Override
	public List<SimplifiedStationLayout> loadSimplifiedStationLayouts() {
		return List.copyOf(simplifiedStationLayouts.values());
	}

	@Override
	public List<RouteNode> loadRouteNodes() {
		return List.copyOf(routeNodes.values());
	}

	@Override
	public List<RouteEdge> loadRouteEdges() {
		return List.copyOf(routeEdges.values());
	}

	@Override
	public void saveFacilityStatus(String facilityId, AccessibilityFacilityStatus status, LocalDate updatedAt) {
		AccessibilityFacility facility = accessibilityFacilities.get(facilityId);
		if (facility == null) {
			// 신고 생성 단계에서 시설 존재 여부를 확인하므로 저장 어댑터는 알 수 없는 식별자를 무시한다.
			return;
		}

		accessibilityFacilities.put(facilityId, new AccessibilityFacility(
			facility.id(),
			facility.stationId(),
			facility.exitId(),
			facility.type(),
			facility.name(),
			facility.floorFrom(),
			facility.floorTo(),
			facility.latitude(),
			facility.longitude(),
			facility.description(),
			status,
			facility.dataConfidence(),
			facility.dataSourceType(),
			updatedAt
		));
	}

	@Override
	public void saveAccessibilityFacility(AccessibilityFacility facility) {
		accessibilityFacilities.put(facility.id(), facility);
	}

	@Override
	public void saveStationLayoutSource(StationLayoutSource source) {
		stationLayoutSources.put(source.id(), source);
	}

	@Override
	public void saveSimplifiedStationLayoutStatus(
		String layoutId,
		SimplifiedStationLayoutStatus status,
		String reviewedBy,
		LocalDate updatedAt
	) {
		SimplifiedStationLayout layout = simplifiedStationLayouts.get(layoutId);
		if (layout == null) {
			return;
		}

		simplifiedStationLayouts.put(layoutId, new SimplifiedStationLayout(
			layout.id(),
			layout.stationId(),
			layout.version() + 1,
			status,
			layout.sourceIds(),
			layout.confidenceLevel(),
			layout.baseFloor(),
			layout.layoutJson(),
			layout.renderedPreviewUrl(),
			layout.createdBy(),
			reviewedBy,
			status == SimplifiedStationLayoutStatus.PUBLISHED ? updatedAt : layout.publishedAt(),
			updatedAt
		));
	}

	@Override
	public void saveRouteNode(RouteNode routeNode) {
		routeNodes.put(routeNode.id(), routeNode);
	}

	@Override
	public void saveRouteEdge(RouteEdge routeEdge) {
		routeEdges.put(routeEdge.id(), routeEdge);
	}

	private void seedAccessibilityFacilities() {
		saveSeedFacility(new AccessibilityFacility(
			"facility-sangnoksu-elevator-1",
			"station-sangnoksu",
			"exit-sangnoksu-1",
			AccessibilityFacilityType.ELEVATOR,
			"1번 출구 엘리베이터",
			"지상",
			"대합실",
			new BigDecimal("37.302421"),
			new BigDecimal("126.866221"),
			"1번 출구와 대합실을 연결합니다.",
			AccessibilityFacilityStatus.NORMAL,
			DataConfidenceLevel.HIGH,
			DataSourceType.OFFICIAL_FILE,
			LocalDate.of(2026, 6, 12)
		));
		saveSeedFacility(new AccessibilityFacility(
			"facility-sangnoksu-escalator-1",
			"station-sangnoksu",
			"exit-sangnoksu-1",
			AccessibilityFacilityType.ESCALATOR,
			"1번 출구 에스컬레이터",
			"지상",
			"대합실",
			new BigDecimal("37.302444"),
			new BigDecimal("126.866250"),
			"1번 출구 방향 상행 에스컬레이터입니다.",
			AccessibilityFacilityStatus.NORMAL,
			DataConfidenceLevel.MEDIUM,
			DataSourceType.OFFICIAL_FILE,
			LocalDate.of(2026, 6, 12)
		));
		saveSeedFacility(new AccessibilityFacility(
			"facility-sangnoksu-accessible-toilet",
			"station-sangnoksu",
			null,
			AccessibilityFacilityType.ACCESSIBLE_TOILET,
			"장애인 화장실",
			"대합실",
			"대합실",
			new BigDecimal("37.302820"),
			new BigDecimal("126.866401"),
			"개찰구 안쪽 대합실에 있습니다.",
			AccessibilityFacilityStatus.UNKNOWN,
			DataConfidenceLevel.NEEDS_VERIFICATION,
			DataSourceType.OFFICIAL_FILE,
			LocalDate.of(2026, 6, 12)
		));
	}

	private void saveSeedFacility(AccessibilityFacility facility) {
		accessibilityFacilities.put(facility.id(), facility);
	}

	private void seedSimplifiedStationLayouts() {
		SIMPLIFIED_STATION_LAYOUTS.forEach(layout -> simplifiedStationLayouts.put(layout.id(), layout));
	}

	private void seedStationLayoutSources() {
		STATION_LAYOUT_SOURCES.forEach(source -> stationLayoutSources.put(source.id(), source));
	}

	private void seedRouteNodes() {
		ROUTE_NODES.forEach(routeNode -> routeNodes.put(routeNode.id(), routeNode));
	}

	private void seedRouteEdges() {
		ROUTE_EDGES.forEach(routeEdge -> routeEdges.put(routeEdge.id(), routeEdge));
	}
}
