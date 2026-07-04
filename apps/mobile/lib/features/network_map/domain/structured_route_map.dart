// 구조화 노선도 도메인 모델과 파생 로직 (#1641 Stage 1: data layer).
//
// route_map_positions에서 앱으로 올라온 원시 필드(x/y, up_path/down_path,
// label_polygon)를 native canvas 렌더러(#1641 Stage 2)가 바로 소비할 수 있는
// 구조로 파생한다. 렌더링은 이 모듈에 없다 — 순수 파싱·파생만 한다.
//
// #1636 structured-route-map-contract의 layer/LOD 규칙을 따른다:
// - line_geometry: up_path/down_path polyline
// - transfer_groups: 같은 station_id에 여러 line_id → 중심 좌표
// - station_labels priority: 환승 > 주요 > 일반 (별도 검수값 없으면 일반)
// - LOD: zoom0 lines only, zoom1 환승/주요 라벨, zoom2 전체 역 라벨
import 'dart:convert';

/// 노선도 원본 좌표계의 2D 점.
class RouteMapPoint {
  const RouteMapPoint(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is RouteMapPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'RouteMapPoint($x, $y)';
}

/// 라벨 우선순위 class (#1636 station_labels.priority).
enum RouteMapLabelClass { transfer, major, regular }

/// 라벨 class → 최초 표시 zoom bucket (#1636 LOD).
/// 0 = lines only(라벨 없음), 1 = 환승/주요 라벨, 2 = 전체 역 라벨.
int minLabelZoomBucketFor(RouteMapLabelClass labelClass) {
  switch (labelClass) {
    case RouteMapLabelClass.transfer:
    case RouteMapLabelClass.major:
      return 1;
    case RouteMapLabelClass.regular:
      return 2;
  }
}

/// 한 노선의 방향별 polyline geometry.
class RouteMapLineGeometry {
  const RouteMapLineGeometry({
    required this.lineId,
    required this.upPolyline,
    required this.downPolyline,
  });

  final String lineId;

  /// 상행(up) 방향 정점 목록, station sequence 순서.
  final List<RouteMapPoint> upPolyline;

  /// 하행(down) 방향 정점 목록, station sequence 순서.
  final List<RouteMapPoint> downPolyline;
}

/// 구조화된 역 노드 (렌더러가 point/label layer로 소비).
class RouteMapStructuredStation {
  const RouteMapStructuredStation({
    required this.stationId,
    required this.lineId,
    required this.sequence,
    required this.position,
    required this.labelPolygon,
    required this.labelClass,
  });

  final String stationId;
  final String lineId;
  final int sequence;
  final RouteMapPoint position;
  final List<RouteMapPoint> labelPolygon;
  final RouteMapLabelClass labelClass;

  int get minLabelZoomBucket => minLabelZoomBucketFor(labelClass);
}

/// 환승 그룹 (#1636 transfer_groups): 같은 물리 역의 노선 묶음.
class RouteMapTransferGroup {
  const RouteMapTransferGroup({
    required this.stationId,
    required this.lineIds,
    required this.centroid,
  });

  final String stationId;

  /// 이 역이 속한 line_id 목록 (정렬됨, 2개 이상).
  final List<String> lineIds;

  /// 표시 좌표: 해당 station_id route_map_positions의 중심값.
  final RouteMapPoint centroid;
}

/// 구조화 노선도 집합 (렌더러 입력).
class StructuredRouteMap {
  const StructuredRouteMap({
    required this.lines,
    required this.stations,
    required this.transferGroups,
  });

  final List<RouteMapLineGeometry> lines;
  final List<RouteMapStructuredStation> stations;
  final List<RouteMapTransferGroup> transferGroups;

  bool get isEmpty =>
      lines.isEmpty && stations.isEmpty && transferGroups.isEmpty;
}

/// 빌더 입력: route_map_positions 한 행에 대응하는 원시 값.
class StructuredRouteMapStationInput {
  const StructuredRouteMapStationInput({
    required this.stationId,
    required this.lineId,
    required this.sequence,
    required this.x,
    required this.y,
    required this.upPath,
    required this.downPath,
    required this.labelPolygon,
  });

  final String stationId;
  final String lineId;
  final int sequence;
  final double x;
  final double y;
  final String upPath;
  final String downPath;
  final String labelPolygon;
}

/// "M x y L x y ..." 형태의 절대 좌표 path 문자열을 점 목록으로 파싱한다.
/// 명령 문자(M/L 등)는 건너뛰고 숫자 쌍만 읽는다. 잘못된 입력은 건너뛴다.
List<RouteMapPoint> parseRouteMapPath(String path) {
  if (path.trim().isEmpty) {
    return const [];
  }
  // 명령 문자(M/L 등)나 쉼표에 붙어 있어도 숫자만 추출한다.
  final numbers = RegExp(r'-?\d+(?:\.\d+)?')
      .allMatches(path)
      .map((match) => double.parse(match.group(0)!))
      .toList();
  final points = <RouteMapPoint>[];
  for (var index = 0; index + 1 < numbers.length; index += 2) {
    points.add(RouteMapPoint(numbers[index], numbers[index + 1]));
  }
  return points;
}

/// label_polygon JSON('[{"x":..,"y":..}]')을 점 목록으로 파싱한다.
List<RouteMapPoint> parseRouteMapLabelPolygon(String source) {
  if (source.trim().isEmpty) {
    return const [];
  }
  Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    return const [];
  }
  if (decoded is! List) {
    return const [];
  }
  final points = <RouteMapPoint>[];
  for (final entry in decoded) {
    if (entry is Map) {
      final x = (entry['x'] as num?)?.toDouble();
      final y = (entry['y'] as num?)?.toDouble();
      if (x != null && y != null) {
        points.add(RouteMapPoint(x, y));
      }
    }
  }
  return points;
}

/// 원시 route_map_positions 입력에서 구조화 노선도를 파생한다.
StructuredRouteMap buildStructuredRouteMap(
  Iterable<StructuredRouteMapStationInput> inputs,
) {
  final inputList = inputs.toList(growable: false);

  // 물리 역(station_id)이 속한 line 집합 → 환승 판정.
  final lineIdsByStation = <String, Set<String>>{};
  final positionsByStation = <String, List<RouteMapPoint>>{};
  for (final input in inputList) {
    lineIdsByStation
        .putIfAbsent(input.stationId, () => <String>{})
        .add(input.lineId);
    positionsByStation
        .putIfAbsent(input.stationId, () => <RouteMapPoint>[])
        .add(RouteMapPoint(input.x, input.y));
  }

  // 노선별 방향 polyline: sequence 순서로 세그먼트를 이어 붙인다.
  final byLine = <String, List<StructuredRouteMapStationInput>>{};
  for (final input in inputList) {
    byLine.putIfAbsent(input.lineId, () => []).add(input);
  }
  final lines = <RouteMapLineGeometry>[];
  final orderedLineIds = byLine.keys.toList()..sort();
  for (final lineId in orderedLineIds) {
    final stations = byLine[lineId]!
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    lines.add(
      RouteMapLineGeometry(
        lineId: lineId,
        upPolyline: _joinSegments(stations.map((s) => s.upPath)),
        downPolyline: _joinSegments(stations.map((s) => s.downPath)),
      ),
    );
  }

  // 구조화 역 노드 + 라벨 class.
  final stations = <RouteMapStructuredStation>[];
  for (final input in inputList) {
    final isTransfer = (lineIdsByStation[input.stationId]?.length ?? 0) > 1;
    stations.add(
      RouteMapStructuredStation(
        stationId: input.stationId,
        lineId: input.lineId,
        sequence: input.sequence,
        position: RouteMapPoint(input.x, input.y),
        labelPolygon: parseRouteMapLabelPolygon(input.labelPolygon),
        labelClass:
            isTransfer ? RouteMapLabelClass.transfer : RouteMapLabelClass.regular,
      ),
    );
  }

  // 환승 그룹: 2개 이상 노선에 속한 역, 중심 좌표.
  final transferGroups = <RouteMapTransferGroup>[];
  final transferStationIds = lineIdsByStation.entries
      .where((entry) => entry.value.length > 1)
      .map((entry) => entry.key)
      .toList()
    ..sort();
  for (final stationId in transferStationIds) {
    transferGroups.add(
      RouteMapTransferGroup(
        stationId: stationId,
        lineIds: lineIdsByStation[stationId]!.toList()..sort(),
        centroid: _centroid(positionsByStation[stationId]!),
      ),
    );
  }

  return StructuredRouteMap(
    lines: lines,
    stations: stations,
    transferGroups: transferGroups,
  );
}

/// 세그먼트 path 목록을 하나의 polyline으로 잇는다. 인접 세그먼트의 공유 정점은
/// 중복 제거한다(세그먼트 i의 끝점 == 세그먼트 i+1의 시작점).
List<RouteMapPoint> _joinSegments(Iterable<String> paths) {
  final polyline = <RouteMapPoint>[];
  for (final path in paths) {
    for (final point in parseRouteMapPath(path)) {
      if (polyline.isEmpty || polyline.last != point) {
        polyline.add(point);
      }
    }
  }
  return polyline;
}

RouteMapPoint _centroid(List<RouteMapPoint> points) {
  if (points.isEmpty) {
    return const RouteMapPoint(0, 0);
  }
  var sumX = 0.0;
  var sumY = 0.0;
  for (final point in points) {
    sumX += point.x;
    sumY += point.y;
  }
  return RouteMapPoint(sumX / points.length, sumY / points.length);
}
