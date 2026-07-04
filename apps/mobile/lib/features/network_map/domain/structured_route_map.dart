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

/// 빌더 입력: route_map_positions 한 행(역-노선)의 표시 값.
/// [labelPolygon]은 호출부에서 기존 _parseLabelPolygon으로 미리 파싱해 전달한다.
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

  String get key => '$stationId:$lineId';
}

/// 역 좌표에서 구조화 노선도를 파생한다.
///
/// line geometry는 각 노선의 역을 좌표 거리 기반 최근접 인접으로 잇는다.
/// line_sequence/RIDE의 번호 기반 인접(지선/분기에서 먼 역을 잇는 부채꼴)을
/// 신뢰하지 않고, 정확한 좌표만으로 실제 인접을 재구성한다.
StructuredRouteMap buildStructuredRouteMap({
  required Iterable<StructuredRouteMapStationInput> stations,
}) {
  final stationList = stations.toList(growable: false);

  final lineIdsByStation = <String, Set<String>>{};
  final positionsByStation = <String, List<Offset>>{};
  final stationsByLine = <String, List<StructuredRouteMapStationInput>>{};
  for (final station in stationList) {
    lineIdsByStation
        .putIfAbsent(station.stationId, () => <String>{})
        .add(station.lineId);
    positionsByStation
        .putIfAbsent(station.stationId, () => <Offset>[])
        .add(station.position);
    stationsByLine.putIfAbsent(station.lineId, () => []).add(station);
  }

  final lines = <RouteMapLineGeometry>[];
  final orderedLineIds = stationsByLine.keys.toList()..sort();
  for (final lineId in orderedLineIds) {
    lines.add(
      RouteMapLineGeometry(
        lineId: lineId,
        polylines: _filterPhantomSegments(
          _minimumSpanningTreeSegments(stationsByLine[lineId]!),
        ),
      ),
    );
  }

  // 구조화 역 노드 + 라벨 class.
  final structuredStations = <RouteMapStructuredStation>[];
  for (final station in stationList) {
    final isTransfer =
        (lineIdsByStation[station.stationId]?.length ?? 0) > 1;
    structuredStations.add(
      RouteMapStructuredStation(
        stationId: station.stationId,
        lineId: station.lineId,
        sequence: station.sequence,
        position: station.position,
        labelPolygon: station.labelPolygon,
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
    stations: structuredStations,
    transferGroups: transferGroups,
  );
}

/// 노선의 역들을 좌표 기반 최소 신장 트리(MST, euclidean)로 잇는다. 번호
/// (line_sequence)의 잘못된 인접을 신뢰하지 않고 정확한 좌표만으로 topology를
/// 재구성한다. 트리라 각 역이 필요한 만큼만 연결돼 skip/부채꼴이 없으며, 선형
/// 노선은 체인, 분기 노선은 트리로 자연스럽게 표현된다. (Prim O(n^2).)
/// 순환선은 트리라 한 구간이 열리지만 시각적 영향은 미미하다. octilinear 등
/// 상용 도식화의 입력 topology를 만드는 정석 단계이기도 하다.
List<List<Offset>> _minimumSpanningTreeSegments(
  List<StructuredRouteMapStationInput> stations,
) {
  final positions = stations.map((s) => s.position).toList(growable: false);
  final count = positions.length;
  if (count < 2) {
    return const [];
  }
  final inTree = List<bool>.filled(count, false);
  final bestDistance = List<double>.filled(count, double.infinity);
  final bestFrom = List<int>.filled(count, -1);
  bestDistance[0] = 0;
  final segments = <List<Offset>>[];
  for (var added = 0; added < count; added += 1) {
    var u = -1;
    var best = double.infinity;
    for (var v = 0; v < count; v += 1) {
      if (!inTree[v] && bestDistance[v] < best) {
        best = bestDistance[v];
        u = v;
      }
    }
    if (u < 0) {
      break;
    }
    inTree[u] = true;
    if (bestFrom[u] >= 0) {
      segments.add(<Offset>[positions[bestFrom[u]], positions[u]]);
    }
    for (var v = 0; v < count; v += 1) {
      if (inTree[v]) {
        continue;
      }
      final distance = (positions[v] - positions[u]).distanceSquared;
      if (distance < bestDistance[v]) {
        bestDistance[v] = distance;
        bestFrom[v] = u;
      }
    }
  }
  return segments;
}

/// 데이터에 실제 인접 topology가 없어 RIDE 엣지가 line_sequence 기반이면,
/// 지선/분기에서 먼 두 역을 잇는 phantom 세그먼트(부채꼴)가 섞인다. 노선별
/// 세그먼트 길이의 median 대비 [thresholdFactor]배를 넘는 세그먼트를 제외한다.
/// GTX-A처럼 역간격이 균일하게 넓은 노선은 median 자체가 커서 보존된다.
List<List<Offset>> _filterPhantomSegments(
  List<List<Offset>> segments, {
  double thresholdFactor = 4.0,
}) {
  if (segments.length < 5) {
    return segments;
  }
  final lengths = segments.map((s) => (s[1] - s[0]).distance).toList()..sort();
  final median = lengths[lengths.length ~/ 2];
  if (median <= 0) {
    return segments;
  }
  final threshold = median * thresholdFactor;
  return segments
      .where((s) => (s[1] - s[0]).distance <= threshold)
      .toList(growable: false);
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
