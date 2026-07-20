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
import 'dart:math' as math;
import 'dart:ui' show Offset;

/// 라벨 우선순위·볼드 class (#1636 station_labels.priority).
///
/// [major](주요역)는 [buildStructuredRouteMap]이 런타임 산출한다(#1764 C):
/// 각 노선 양 종점(sequence min/max)이거나 비환승 거점 allowlist
/// (route_map_major_stations)에 속하는 역. 환승역은 [transfer]로 우선 처리된다.
/// LOD zoom bucket 매핑은 #1789 정적 스케일 렌더 전환에서 폐지됐다(로드 시 1회
/// 정적 배치·전부 표시) — 이 enum은 배치 우선순위와 볼드 판정에만 쓰인다.
enum RouteMapLabelClass { transfer, major, regular }

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
}

/// 환승 그룹 (#1636 transfer_groups): 같은 물리 역의 노선 묶음.
class RouteMapTransferGroup {
  const RouteMapTransferGroup({
    required this.stationId,
    required this.lineIds,
    required this.centroid,
    required this.memberPositions,
  });

  final String stationId;

  /// 이 역이 속한 line_id 목록 (정렬됨, 2개 이상).
  final List<String> lineIds;

  /// 표시 좌표: 해당 station_id route_map_positions의 중심값.
  final Offset centroid;

  /// [lineIds]와 같은 순서의 노선별 노드 좌표. 비수렴 기하에서 캡슐이
  /// 멤버들을 걸치도록 렌더러가 소비한다.
  final List<Offset> memberPositions;
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

/// 순환선의 폐합 엣지 판정 임계값. 시작-끝 간격이 폴리라인 자체 bbox 대각선의
/// 이 비율 미만이면 "거의 닫힌 고리"로 보고 [_closeNearLoopPolyline]이 닫는다.
/// [_routeMapTerminalStationIds]의 순환 판정(loopSpanRatio)과 같은 크기.
const double _kLoopClosureSpanRatio = 0.25;

/// route_map_line_tracks의 path 조립 과정에서 순환(loop) track의 마지막 폐합
/// 세그먼트가 드롭된 경우를 보정한다(#2068 실기기 반려 3차: 시청 라벨이 2호선
/// 순환 폐합 구간 "빈 공간"에 배치돼 화면에선 선 위로 보임). 데이터팩 전 권역
/// 실측(2026-07-16): 50개 track 중 시작-끝 간격/자기 bbox 대각선 비율이 0.25
/// 미만인 경우는 2건뿐 — 수도권 2호선 track0(간격 38.2/대각 813.8=0.047, 시청↔
/// 을지로입구 사이 약 1역 간격 누락)과 수도권 공항 track1(간격 0.35/대각 26.7=
/// 0.013, 사실상 부동소수 오차). 그 외 노선(6호선 등, 응암루프처럼 부분 순환을
/// 포함해도 전체 track은 선형이라 비율이 0.7~1.0)은 영향 없다 — 진짜 열린
/// 노선은 시작-끝 간격이 자기 규모에 비례해 크다.
List<Offset> _closeNearLoopPolyline(List<Offset> points) {
  if (points.length < 3) {
    return points;
  }
  final first = points.first;
  final last = points.last;
  if (first == last) {
    return points;
  }
  var minX = first.dx, maxX = first.dx, minY = first.dy, maxY = first.dy;
  for (final p in points) {
    minX = math.min(minX, p.dx);
    maxX = math.max(maxX, p.dx);
    minY = math.min(minY, p.dy);
    maxY = math.max(maxY, p.dy);
  }
  final span = (Offset(maxX, maxY) - Offset(minX, minY)).distance;
  if (span <= 0) {
    return points;
  }
  final gap = (last - first).distance;
  if (gap > 0 && gap < span * _kLoopClosureSpanRatio) {
    return [...points, first];
  }
  return points;
}

/// "M x y L x y ..." 형태의 절대 좌표 path를 정점 목록으로 파싱한다.
/// 데이터팩(enrich-capital-route-map-layer.mjs)은 절대 M/L 세그먼트만 방출하므로
/// 명령 문자는 무시하고 숫자 쌍만 읽는다. (H/V/상대 명령은 대상 아님.)
List<Offset> parseRouteMapPolyline(String path) {
  if (path.trim().isEmpty) {
    return const [];
  }
  final numbers = RegExp(
    r'-?\d+(?:\.\d+)?',
  ).allMatches(path).map((match) => double.parse(match.group(0)!)).toList();
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
  Set<String> majorStationIds = const <String>{},
}) {
  final inputList = inputs.toList(growable: false);

  // 물리 역(station_id)이 속한 line 집합 → 환승 판정.
  final lineIdsByStation = <String, Set<String>>{};
  // 환승 중심·멤버 좌표 계산용: stationId → lineId → position.
  final positionByStationLine = <String, Map<String, Offset>>{};
  final lineIdsWithStations = <String>{};
  // 노선별 입력(양 종점 자동 산출용, #1764 C major).
  final inputsByLine = <String, List<StructuredRouteMapStationInput>>{};
  for (final input in inputList) {
    lineIdsByStation
        .putIfAbsent(input.stationId, () => <String>{})
        .add(input.lineId);
    positionByStationLine.putIfAbsent(
      input.stationId,
      () => <String, Offset>{},
    )[input.lineId] = input.position;
    lineIdsWithStations.add(input.lineId);
    inputsByLine
        .putIfAbsent(input.lineId, () => <StructuredRouteMapStationInput>[])
        .add(input);
  }

  // 각 노선 양 종점 station_id 집합(자동 major 후보).
  final terminalStationIds = _routeMapTerminalStationIds(inputsByLine);

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
            _closeNearLoopPolyline(parseRouteMapPolyline(path)),
        ].where((points) => points.length >= 2).toList(growable: false),
      ),
  ];

  // 구조화 역 노드 + 라벨 class.
  final stations = <RouteMapStructuredStation>[];
  for (final input in inputList) {
    final isTransfer = (lineIdsByStation[input.stationId]?.length ?? 0) > 1;
    // 환승이 아니면서 노선 종점이거나 거점 allowlist에 속하면 major(#1764 C).
    final isMajor =
        !isTransfer &&
        (terminalStationIds.contains(input.stationId) ||
            majorStationIds.contains(input.stationId));
    stations.add(
      RouteMapStructuredStation(
        stationId: input.stationId,
        lineId: input.lineId,
        sequence: input.sequence,
        position: input.position,
        labelPolygon: input.labelPolygon,
        labelClass: isTransfer
            ? RouteMapLabelClass.transfer
            : isMajor
            ? RouteMapLabelClass.major
            : RouteMapLabelClass.regular,
      ),
    );
  }

  // 환승 그룹: 2개 이상 노선에 속한 역, 중심 좌표.
  final transferGroups = <RouteMapTransferGroup>[];
  final transferStationIds =
      lineIdsByStation.entries
          .where((entry) => entry.value.length > 1)
          .map((entry) => entry.key)
          .toList()
        ..sort();
  for (final stationId in transferStationIds) {
    final lineIds = lineIdsByStation[stationId]!.toList()..sort();
    final byLine = positionByStationLine[stationId]!;
    final memberPositions = [for (final lineId in lineIds) byLine[lineId]!];
    transferGroups.add(
      RouteMapTransferGroup(
        stationId: stationId,
        lineIds: lineIds,
        centroid: _centroid(memberPositions),
        memberPositions: memberPositions,
      ),
    );
  }

  return StructuredRouteMap(
    lines: lines,
    stations: stations,
    transferGroups: transferGroups,
  );
}

/// 각 노선의 양 종점 station_id(자동 major 후보, #1764 C). 규칙:
/// - sequence 극값(최소·최대) 역을 종점으로 본다. 동률(분기/지선 종점)이면 그
///   극값 역을 모두 포함한다(첫 역만 취하지 않는다).
/// - 순환선(수도권 2호선 등)은 양 극점이 노선 전체 span 대비 가까워 종점이 없다.
///   이때는 내부 루프 역이 종점으로 오판돼 major가 되지 않도록 제외한다.
Set<String> _routeMapTerminalStationIds(
  Map<String, List<StructuredRouteMapStationInput>> inputsByLine,
) {
  const loopSpanRatio = 0.25;
  final terminals = <String>{};
  for (final inputs in inputsByLine.values) {
    if (inputs.length < 2) {
      continue;
    }
    var minSeq = inputs.first.sequence;
    var maxSeq = inputs.first.sequence;
    for (final input in inputs) {
      if (input.sequence < minSeq) minSeq = input.sequence;
      if (input.sequence > maxSeq) maxSeq = input.sequence;
    }
    if (minSeq == maxSeq) {
      continue;
    }
    final minStations = inputs.where((i) => i.sequence == minSeq).toList();
    final maxStations = inputs.where((i) => i.sequence == maxSeq).toList();
    final span = _routeMapLineSpan(inputs);
    final endpointGap =
        (minStations.first.position - maxStations.first.position).distance;
    if (span > 0 && endpointGap < span * loopSpanRatio) {
      // 순환선: 종점 강조 대상 아님.
      continue;
    }
    for (final input in minStations) {
      terminals.add(input.stationId);
    }
    for (final input in maxStations) {
      terminals.add(input.stationId);
    }
  }
  return terminals;
}

/// 노선 역 좌표 bbox 대각 길이(순환선 판정용 노선 규모).
double _routeMapLineSpan(List<StructuredRouteMapStationInput> inputs) {
  var minX = inputs.first.position.dx;
  var maxX = minX;
  var minY = inputs.first.position.dy;
  var maxY = minY;
  for (final input in inputs) {
    final point = input.position;
    if (point.dx < minX) minX = point.dx;
    if (point.dx > maxX) maxX = point.dx;
    if (point.dy < minY) minY = point.dy;
    if (point.dy > maxY) maxY = point.dy;
  }
  return (Offset(maxX, maxY) - Offset(minX, minY)).distance;
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

/// 노선별 종착역(sequence 최소/최대) station_id 집합 (#1789 볼드 스타일).
/// 시·종점 좌표가 같은 순환선은 종착 개념이 없어 제외한다.
Set<String> routeMapTerminusStationIds(StructuredRouteMap map) {
  final byLine = <String, List<RouteMapStructuredStation>>{};
  for (final station in map.stations) {
    (byLine[station.lineId] ??= []).add(station);
  }
  final ids = <String>{};
  for (final stations in byLine.values) {
    if (stations.length < 2) {
      continue;
    }
    stations.sort((a, b) => a.sequence.compareTo(b.sequence));
    final first = stations.first;
    final last = stations.last;
    if (first.position == last.position) {
      continue; // 순환선.
    }
    ids
      ..add(first.stationId)
      ..add(last.stationId);
  }
  return ids;
}
