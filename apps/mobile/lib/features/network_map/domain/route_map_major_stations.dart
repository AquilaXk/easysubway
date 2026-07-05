// 노선도 major(주요역) allowlist — 비환승 거점 (#1764 C).
//
// major class는 데이터팩에 굽지 않고 앱 buildStructuredRouteMap이 런타임에
// 산출한다(스키마·팩 무변경, 사용자 결정 2026-07-05): ① 각 노선 양 종점(빌더가
// line별 sequence min/max로 자동), ② 이 지역별 비환승 거점 allowlist. 환승역은
// transfer로 우선 처리되므로 여기엔 비환승 거점만 둔다.
//
// 정본은 tools/route-map/major-stations.json 이며, 이 상수와의 정합·역명 존재·
// 비환승 여부는 route-map-major-stations 계약 테스트가 검증한다(드리프트 방지).
const Map<String, Set<String>> routeMapMajorLandmarkStationNamesByRegion =
    <String, Set<String>>{
      '수도권': {'성수'},
      '부산권': {'해운대', '부산대'},
      '대구권': {'중앙로'},
      '대전권': {'시청', '정부청사'},
      '광주권': {'금남로4가', '상무'},
    };
