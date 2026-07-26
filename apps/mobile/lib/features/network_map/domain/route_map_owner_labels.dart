// 오너 SVG 라벨 실측 앵커 sidecar 모델(#2068 6차).
//
// tools/route-map/compile-basemap-vec.mjs의 extractOwnerLabels가 5권역 SVG의
// <text data-label-role="ordinary|transfer|terminal">에서 뽑은 실측 위치·
// text-anchor·font-size를 담은 sidecar
// (assets/datapacks/metro_map_pack/basemap/labels.json)를 파싱한다. 순수
// 파싱만 담당 — asset 로드(rootBundle)는 network_map.dart가 한다(#1951
// attribution 로더와 같은 관례).
//
// 좌표계: sidecar의 x/y는 SVG viewBox 좌표(=route_map_positions와 같은 source
// 좌표계, RouteMapBasemapPainter가 그대로 재생하는 좌표)다. 호출부가
// design.toDesign()으로 design px로 변환한다(기존 station.position과 동일 경로).
import 'dart:convert' show jsonDecode;
import 'dart:ui' show Offset;

/// SVG `text-anchor` 값. `middle`/`end` 외 전부 `start`로 정규화한다.
enum RouteMapOwnerLabelAnchor { start, middle, end }

/// 오너 SVG 다줄(2단) 라벨의 한 줄(#2068 다줄 라벨 렌더) — compile-basemap-vec.mjs
/// extractOwnerLabelLineLocalPositions가 뽑은 실측 줄 텍스트·앵커 좌표.
/// [position]은 부모 [RouteMapOwnerLabelEntry.position]과 같은 viewBox(source)
/// 좌표계·같은 text-anchor 의미(줄마다 독립 적용 — SVG 텍스트 청크 규칙, tspan이
/// 자기 x를 선언하면 그 지점이 그 줄의 앵커)를 공유한다.
class RouteMapOwnerLabelLine {
  const RouteMapOwnerLabelLine({required this.text, required this.position});

  final String text;

  /// viewBox(source) 좌표.
  final Offset position;
}

/// 오너가 SVG에서 손배치한 역명 라벨 1건.
class RouteMapOwnerLabelEntry {
  const RouteMapOwnerLabelEntry({
    required this.station,
    required this.role,
    required this.position,
    required this.anchor,
    required this.fontSizePx,
    this.hasLineTerminalBadge = false,
    this.lines = const [],
  });

  /// SVG 라벨의 렌더 텍스트 내용(=역명, nameKo와 정확 일치 매칭 키).
  final String station;

  /// `ordinary`/`transfer`/`terminal` — 중복 역명 해소 우선순위에만 쓴다.
  final String role;

  /// viewBox(source) 좌표(첫 줄 앵커 — 단일 줄 라벨과 동일 의미, 매칭·후보
  /// 거리 게이트는 이 대표점을 계속 쓴다).
  final Offset position;
  final RouteMapOwnerLabelAnchor anchor;

  /// viewBox(source) 단위 로컬 font-size — design px 변환은 호출부가 한다.
  final double fontSizePx;

  /// #2068 광주 2차: 이 역이 오너 SVG에 종점 호선 마크(line-terminal-badge,
  /// 노선 끝단 원+숫자 마감)를 갖고 있으면 true — compile-basemap-vec.mjs가
  /// region 내 `data-role="line-terminal-badge"` 존재를 감지해 terminal role
  /// 엔트리에만 표시한다. 앱 솔버가 basemap 노선 뱃지 pill과 중복 그리지
  /// 않도록 route_map_label_layout.dart가 이 플래그로 억제한다.
  final bool hasLineTerminalBadge;

  /// #2068 다줄 라벨 렌더: 오너 SVG가 이 라벨을 2줄 이상으로 줄바꿈했으면 그
  /// 줄 구성(비어 있으면 단일 줄 — 기존 station 텍스트·position 그대로 렌더).
  /// 비어 있지 않을 때만 렌더러가 다줄 경로를 탄다.
  final List<RouteMapOwnerLabelLine> lines;
}

RouteMapOwnerLabelAnchor _parseRouteMapOwnerLabelAnchor(Object? value) =>
    switch (value) {
      'middle' => RouteMapOwnerLabelAnchor.middle,
      'end' => RouteMapOwnerLabelAnchor.end,
      _ => RouteMapOwnerLabelAnchor.start,
    };

/// `lines` sidecar 필드 파싱(#2068 다줄 라벨 렌더) — 형식이 어긋난 항목은
/// 건너뛴다(단일 줄 폴백과 같은 안전 방향: 결과가 비면 호출부가 단일 줄로 렌더).
List<RouteMapOwnerLabelLine> _parseRouteMapOwnerLabelLines(Object? raw) {
  if (raw is! List) return const [];
  final lines = <RouteMapOwnerLabelLine>[];
  for (final rawLine in raw) {
    if (rawLine is! Map) continue;
    final text = rawLine['text'];
    final x = rawLine['x'];
    final y = rawLine['y'];
    if (text is! String || text.isEmpty || x is! num || y is! num) continue;
    lines.add(
      RouteMapOwnerLabelLine(
        text: text,
        position: Offset(x.toDouble(), y.toDouble()),
      ),
    );
  }
  return lines;
}

/// sidecar 전체 JSON에서 [regionId](예: `seoul`)의 라벨을 station명 키 맵으로
/// 파싱한다. 형식이 어긋나거나 regionId가 없으면 빈 맵(호출부가 안전 폴백).
///
/// 동명이역(#2068 실측: seoul 신촌·양평, busan 좌천·동래 — 서로 다른 물리역이
/// 같은 렌더 텍스트를 공유)은 **한 이름 아래 모든 라벨을 위치로 구분해 리스트로
/// 보존한다**. 이전엔 role 우선순위로 하나만 남겨(6차 한계) 라벨 하나가 통째로
/// 소실됐다 — 소비처(geometry bounds 확장·초기 카메라 가독 배율)가 엔트리를
/// 빠짐없이 훑도록 전부 넘긴다.
/// 리스트 안 순서는 sidecar 등장 순(=station→role 정렬)으로 결정적이다.
Map<String, List<RouteMapOwnerLabelEntry>> parseRouteMapOwnerLabelsForRegion(
  String sidecarJson,
  String regionId,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(sidecarJson);
  } on FormatException {
    return const {};
  }
  if (decoded is! Map || decoded['regions'] is! Map) {
    return const {};
  }
  return _buildOwnerLabelMap((decoded['regions'] as Map)[regionId]);
}

/// 이미 디코드된 region 엔트리 리스트(Object?)를 station명 키 맵으로 만든다.
/// 형식이 어긋나면 빈 맵. [parseRouteMapOwnerLabelsForRegion]과
/// [routeMapOwnerLabelsByRegionFrom]이 공유해 sidecar를 1회만 decode하도록 한다.
Map<String, List<RouteMapOwnerLabelEntry>> _buildOwnerLabelMap(
  Object? regionEntries,
) {
  if (regionEntries is! List) {
    return const {};
  }
  final result = <String, List<RouteMapOwnerLabelEntry>>{};
  for (final raw in regionEntries) {
    if (raw is! Map) continue;
    final station = raw['station'];
    final x = raw['x'];
    final y = raw['y'];
    final fontSizePx = raw['fontSizePx'];
    if (station is! String ||
        station.isEmpty ||
        x is! num ||
        y is! num ||
        fontSizePx is! num) {
      continue;
    }
    final role = raw['role'] is String ? raw['role'] as String : 'ordinary';
    final entry = RouteMapOwnerLabelEntry(
      station: station,
      role: role,
      position: Offset(x.toDouble(), y.toDouble()),
      anchor: _parseRouteMapOwnerLabelAnchor(raw['anchor']),
      fontSizePx: fontSizePx.toDouble(),
      hasLineTerminalBadge: raw['hasLineTerminalBadge'] == true,
      lines: _parseRouteMapOwnerLabelLines(raw['lines']),
    );
    result.putIfAbsent(station, () => []).add(entry);
  }
  return result;
}

/// sidecar 전체 JSON을 region별로 한 번에 파싱한다(로더가 1회 호출해 캐시).
/// sidecar는 여기서 1회만 decode하고 그 결과를 모든 region이 공유한다.
Map<String, Map<String, List<RouteMapOwnerLabelEntry>>>
routeMapOwnerLabelsByRegionFrom(String sidecarJson) {
  final Object? decoded;
  try {
    decoded = jsonDecode(sidecarJson);
  } on FormatException {
    return const {};
  }
  if (decoded is! Map || decoded['regions'] is! Map) {
    return const {};
  }
  final regions = decoded['regions'] as Map;
  return {
    for (final key in regions.keys)
      if (key is String) key: _buildOwnerLabelMap(regions[key]),
  };
}

/// basemap 모드 sidecar asset 경로. metro_map_pack/basemap/는 pubspec.yaml에
/// 디렉터리째 등록돼 있어 별도 자산 선언이 필요 없다.
const String kRouteMapOwnerLabelsAssetPath =
    'assets/datapacks/metro_map_pack/basemap/labels.json';

/// 오너 SVG service-tag(KTX·SRT·AIR 표장) 1건의 장애물 사각형(#2068 마감
/// 라운드 item 3). compile-basemap-vec.mjs의 extractServiceTagObstacles가
/// 표장 도형(중첩 transform·scale 전부 합성) 외접 바운딩박스를 실측해 낸다.
/// 좌표계는 [RouteMapOwnerLabelEntry.position]과 같은 viewBox(source) 단위 —
/// 호출부가 design.toDesign()으로 변환한다.
class RouteMapServiceTagObstacle {
  const RouteMapServiceTagObstacle({
    required this.station,
    required this.center,
    required this.halfWidth,
    required this.halfHeight,
  });

  /// SVG data-station 원문(참고용 — 매칭에는 쓰지 않는다. 장애물은 위치
  /// 기반으로만 회피하면 충분하고, 이름 매칭은 오배치 위험만 늘린다).
  final String station;

  /// viewBox(source) 좌표.
  final Offset center;
  final double halfWidth;
  final double halfHeight;
}

/// sidecar의 `serviceTagObstacles[regionId]`를 파싱한다. 필드가 없거나
/// 형식이 어긋나면 빈 리스트(호출부가 안전 폴백 — 장애물 없이 기존 동작).
List<RouteMapServiceTagObstacle> parseRouteMapServiceTagObstaclesForRegion(
  String sidecarJson,
  String regionId,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(sidecarJson);
  } on FormatException {
    return const [];
  }
  if (decoded is! Map || decoded['serviceTagObstacles'] is! Map) {
    return const [];
  }
  final regionEntries = (decoded['serviceTagObstacles'] as Map)[regionId];
  if (regionEntries is! List) {
    return const [];
  }
  final result = <RouteMapServiceTagObstacle>[];
  for (final raw in regionEntries) {
    if (raw is! Map) continue;
    final station = raw['station'];
    final x = raw['x'];
    final y = raw['y'];
    final halfWidth = raw['halfWidth'];
    final halfHeight = raw['halfHeight'];
    if (station is! String ||
        x is! num ||
        y is! num ||
        halfWidth is! num ||
        halfHeight is! num) {
      continue;
    }
    result.add(
      RouteMapServiceTagObstacle(
        station: station,
        center: Offset(x.toDouble(), y.toDouble()),
        halfWidth: halfWidth.toDouble(),
        halfHeight: halfHeight.toDouble(),
      ),
    );
  }
  return result;
}
