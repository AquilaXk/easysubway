// 구조화 노선도 도메인 모델과 파생 로직 (#1641 Stage 1: data layer).
//
// route_map_positions에서 앱으로 올라온 필드를 native canvas 렌더러(#1641
// Stage 2)가 바로 소비할 구조로 파생한다. 렌더링은 이 모듈에 없다 — 순수
// 파생만 한다. label_polygon 파싱은 network_map.dart의 기존 _parseLabelPolygon
// 을 재사용하므로(호출부에서 List<Offset>로 전달) 여기서 다시 파싱하지 않는다.
//
// #1636 structured-route-map-contract의 layer/LOD 규칙을 따른다:
// - line_geometry: 노선 track polyline (gap에서 끊는다)
// - transfer_groups: 같은 station_id에 여러 line_id → 중심 좌표
// - station_labels priority: 환승 > 주요 > 일반 (별도 검수값 없으면 일반)
// - LOD: zoom0 lines only, zoom1 환승/주요 라벨, zoom2 전체 역 라벨
import 'dart:ui' show Offset;

/// 라벨 우선순위 class (#1636 station_labels.priority).
///
/// [major]는 #1636 majorRule("별도 검수된 주요 거점")을 위한 예약 값이다.
/// 현재 데이터팩에는 검수 컬럼이 없어 빌더는 transfer/regular만 산출하지만,
/// 계약과 LOD 매핑을 위해 값과 zoom bucket을 유지한다.
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

/// 한 노선의 track geometry. 데이터 hole(인접 세그먼트가 이어지지 않는 지점)에서
/// 끊어 여러 sub-polyline으로 둔다 — 끊긴 두 역을 직선으로 잇는 phantom edge를
/// 만들지 않기 위함이다.
class RouteMapLineGeometry {
  const RouteMapLineGeometry({required this.lineId, required this.polylines});

  final String lineId;

  /// sequence 순서의 정점 목록들. 각 원소가 연속된 sub-polyline.
  final List<List<Offset>> polylines;
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
  final Offset position;
  final List<Offset> labelPolygon;
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
  final Offset centroid;
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

/// 빌더 입력: route_map_positions 한 행에 대응하는 값(역 노드·라벨·환승용).
/// [labelPolygon]은 호출부에서 기존 _parseLabelPolygon으로 미리 파싱해 전달한다.
/// line geometry는 이 입력이 아니라 [RouteMapLineTrackInput]에서 온다(#1638).
class StructuredRouteMapStationInput {
  const StructuredRouteMapStationInput({
    required this.stationId,
    required this.lineId,
    required this.sequence,
    required this.position,
    required this.labelPolygon,
  });

  final String stationId;
  final String lineId;
  final int sequence;
  final Offset position;
  final List<Offset> labelPolygon;
}

/// 한 노선의 track 입력: pack route_map_line_tracks의 path 문자열들(#1638).
/// line geometry의 source — 역별 down_path 조립을 대체한다.
class RouteMapLineTrackInput {
  const RouteMapLineTrackInput({required this.lineId, required this.paths});

  final String lineId;
  final List<String> paths;
}

/// "M x y L x y ..." 형태의 절대 좌표 path를 정점 목록으로 파싱한다.
/// 데이터팩(enrich-capital-route-map-layer.mjs)은 절대 M/L 세그먼트만 방출하므로
/// 명령 문자는 무시하고 숫자 쌍만 읽는다. (H/V/상대 명령은 대상 아님.)
List<Offset> parseRouteMapPolyline(String path) {
  if (path.trim().isEmpty) {
    return const [];
  }
  final numbers = RegExp(r'-?\d+(?:\.\d+)?')
      .allMatches(path)
      .map((match) => double.parse(match.group(0)!))
      .toList();
  final points = <Offset>[];
  for (var index = 0; index + 1 < numbers.length; index += 2) {
    points.add(Offset(numbers[index], numbers[index + 1]));
  }
  return points;
}

/// route_map 입력에서 구조화 노선도를 파생한다. line geometry는 [lineTracks]의
/// track path에서, 역 노드·환승·라벨은 [inputs]에서 온다(#1638 track 직접 렌더).
StructuredRouteMap buildStructuredRouteMap(
  Iterable<StructuredRouteMapStationInput> inputs, {
  required List<RouteMapLineTrackInput> lineTracks,
}) {
  final inputList = inputs.toList(growable: false);

  // 물리 역(station_id)이 속한 line 집합 → 환승 판정.
  final lineIdsByStation = <String, Set<String>>{};
  // 환승 중심 계산용: 환승역 후보만 좌표를 모은다.
  final positionsByStation = <String, List<Offset>>{};
  final lineIdsWithStations = <String>{};
  for (final input in inputList) {
    lineIdsByStation
        .putIfAbsent(input.stationId, () => <String>{})
        .add(input.lineId);
    positionsByStation
        .putIfAbsent(input.stationId, () => <Offset>[])
        .add(input.position);
    lineIdsWithStations.add(input.lineId);
  }

  // line geometry: 노선별 실제 track polyline을 저장된 path 그대로 파싱한다.
  // 조각(끊긴 track)은 phantom 직선 없이 분리 유지, 정점 2개 미만은 버린다.
  final pathsByLine = <String, List<String>>{
    for (final track in lineTracks) track.lineId: track.paths,
  };
  final lineIds = <String>{...lineIdsWithStations, ...pathsByLine.keys}.toList()
    ..sort();
  final lines = <RouteMapLineGeometry>[
    for (final lineId in lineIds)
      RouteMapLineGeometry(
        lineId: lineId,
        polylines: [
          for (final path in pathsByLine[lineId] ?? const <String>[])
            parseRouteMapPolyline(path),
        ].where((points) => points.length >= 2).toList(growable: false),
      ),
  ];

  // 구조화 역 노드 + 라벨 class.
  final stations = <RouteMapStructuredStation>[];
  for (final input in inputList) {
    final isTransfer = (lineIdsByStation[input.stationId]?.length ?? 0) > 1;
    stations.add(
      RouteMapStructuredStation(
        stationId: input.stationId,
        lineId: input.lineId,
        sequence: input.sequence,
        position: input.position,
        labelPolygon: input.labelPolygon,
        labelClass: isTransfer
            ? RouteMapLabelClass.transfer
            : RouteMapLabelClass.regular,
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

Offset _centroid(List<Offset> points) {
  if (points.isEmpty) {
    return Offset.zero;
  }
  var sumX = 0.0;
  var sumY = 0.0;
  for (final point in points) {
    sumX += point.dx;
    sumY += point.dy;
  }
  return Offset(sumX / points.length, sumY / points.length);
}
