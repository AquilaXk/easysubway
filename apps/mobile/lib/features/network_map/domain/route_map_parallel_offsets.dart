// 평행선 렌더 오프셋 (#1792 G4): 여러 노선이 같은 좌표를 지나는 공유 corridor
// 에서 track이 완전히 겹쳐 한 노선만 보이는 문제를, 각 노선을 corridor 진행
// 방향에 수직으로 조금씩 밀어 나란히 그리게 한다(서해선·경의중앙 일산~능곡 등).
//
// 이 모듈은 순수 계산만 한다 — 각 정점에 적용할 **단위 법선 × 노선 rank(중앙
// 기준 부호)** 벡터를 돌려주고, 렌더러가 뷰포트 px 간격을 곱해 적용한다(확대율과
// 무관하게 일정 간격). 데이터(track 좌표)는 건드리지 않는다.
import 'dart:ui' show Offset;

import 'structured_route_map.dart';

/// 각 노선 polyline 정점에 적용할 평행 오프셋 방향 벡터를 계산한다.
/// 반환: lineId → (polyline별) → (정점별) Offset(= 단위 법선 × rank 배수).
///
/// 공유 정점이 **연속 2개 이상**(진짜 평행 corridor)일 때만 오프셋한다. 환승역
/// centroid 스냅으로 교차 노선이 한 점만 공유하는 경우는 오프셋하지 않아 교차점
/// kink를 막고, 분기/단독 정점은 0이라 corridor 끝(역)에서 자연 수렴한다.
Map<String, List<List<Offset>>> routeMapParallelLineOffsets(
  List<RouteMapLineGeometry> lines,
) {
  // 정점 좌표 키 → 그 점을 지나는 노선 집합.
  final linesByPoint = <String, Set<String>>{};
  for (final line in lines) {
    for (final polyline in line.polylines) {
      for (final point in polyline) {
        linesByPoint
            .putIfAbsent(_pointKey(point), () => <String>{})
            .add(line.lineId);
      }
    }
  }

  final result = <String, List<List<Offset>>>{};
  for (final line in lines) {
    final perPolyline = <List<Offset>>[];
    for (final polyline in line.polylines) {
      // 각 정점이 다른 노선과 공유되는지 미리 계산(런 판정용).
      final shared = [
        for (final point in polyline)
          (linesByPoint[_pointKey(point)]?.length ?? 0) > 1,
      ];
      final offsets = <Offset>[];
      for (var i = 0; i < polyline.length; i += 1) {
        final hasSharedNeighbor =
            (i > 0 && shared[i - 1]) ||
            (i + 1 < polyline.length && shared[i + 1]);
        if (!shared[i] || !hasSharedNeighbor) {
          offsets.add(Offset.zero);
          continue;
        }
        // 공유 노선을 정렬해 결정적 rank → 중앙 기준 부호 배수(대칭 배치).
        final members = linesByPoint[_pointKey(polyline[i])]!.toList()..sort();
        final mult = members.indexOf(line.lineId) - (members.length - 1) / 2;
        offsets.add(_unitNormal(polyline, i) * mult);
      }
      perPolyline.add(offsets);
    }
    result[line.lineId] = perPolyline;
  }
  return result;
}

/// 공유 판정용 정점 키. 정수 좌표계라 반올림해 미세 오차를 흡수한다.
String _pointKey(Offset p) => '${p.dx.round()},${p.dy.round()}';

/// polyline 정점 i에서 진행 방향에 수직인 단위 법선. 인접 정점으로 접선을
/// 추정한다(끝점은 한쪽 세그먼트). 접선 길이 0이면 Offset.zero.
Offset _unitNormal(List<Offset> polyline, int i) {
  if (polyline.length < 2) {
    return Offset.zero;
  }
  final Offset tangent;
  if (i == 0) {
    tangent = polyline[1] - polyline[0];
  } else if (i == polyline.length - 1) {
    tangent = polyline[i] - polyline[i - 1];
  } else {
    tangent = polyline[i + 1] - polyline[i - 1];
  }
  final length = tangent.distance;
  if (length == 0) {
    return Offset.zero;
  }
  final unit = tangent / length;
  return Offset(-unit.dy, unit.dx);
}
