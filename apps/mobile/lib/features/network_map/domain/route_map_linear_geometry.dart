import 'dart:ui' show Offset;

// 노선도 line path 선형 파라미터 → 좌표 매퍼 (#1649 실시간 열차 overlay 기반).
//
// #1636 structured-route-map-contract의 linearParameter/realtimeOverlayHook 계약을
// 구현한다: "열차 overlay는 line path 선형 파라미터만으로 좌표 계산 가능 — 렌더러는
// line geometry와 t만으로 노선도 좌표를 계산한다."
//
// 순수 기하다. 열차 상태 해석(도착/출발=역 node 고정, 진입=구간 보간)과 provider
// join은 상위 layer가 하고, 여기서는 polyline + t → Offset만 계산한다.

/// polyline을 누적 거리로 파라미터화해 정규화 t(0..1) 위치의 좌표를 준다.
class RouteMapLinearGeometry {
  RouteMapLinearGeometry(List<Offset> polyline)
    : _polyline = List<Offset>.unmodifiable(polyline),
      _cumulative = _cumulativeDistances(polyline);

  final List<Offset> _polyline;
  final List<double> _cumulative;

  /// polyline 전체 길이(누적 거리).
  double get length => _cumulative.isEmpty ? 0 : _cumulative.last;

  int get vertexCount => _polyline.length;

  /// 정규화 t(0..1) 위치의 좌표. 범위 밖 t는 [0,1]로 clamp한다.
  /// 빈 polyline은 Offset.zero, 길이 0(같은 점들)은 첫 정점을 준다.
  Offset pointAtT(double t) {
    if (_polyline.isEmpty) {
      return Offset.zero;
    }
    // 단일 정점·길이 0·비유한(NaN/Infinity geometry)은 첫 정점으로 안전 강등.
    if (_polyline.length == 1 || length == 0 || !length.isFinite) {
      return _polyline.first;
    }
    final clamped = t.isNaN ? 0.0 : t.clamp(0.0, 1.0);
    final target = clamped * length;
    // _cumulative는 단조 비감소 → 이진 탐색으로 target 이상 첫 정점을 찾는다.
    var lo = 1;
    var hi = _cumulative.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_cumulative[mid] >= target) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    final segmentStart = _cumulative[lo - 1];
    final segmentLength = _cumulative[lo] - segmentStart;
    final fraction =
        segmentLength == 0 ? 0.0 : (target - segmentStart) / segmentLength;
    return Offset.lerp(_polyline[lo - 1], _polyline[lo], fraction)!;
  }

  /// 정점 index의 t값(누적 거리 / 전체). 역이 polyline 정점에 해당하므로,
  /// 역별 t는 이 값으로 얻는다.
  double tAtVertex(int index) {
    if (_cumulative.isEmpty || length == 0 || !length.isFinite) {
      return 0;
    }
    final clampedIndex = index.clamp(0, _cumulative.length - 1);
    return _cumulative[clampedIndex] / length;
  }

  /// 정점 [a]→[b] 사이 [fraction](0..1) 위치의 좌표.
  /// 열차 '진입' 상태를 이전 역→현재 역 구간의 보간점에 배치할 때 쓴다.
  Offset pointBetweenVertices(int a, int b, double fraction) {
    final clampedFraction = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    final tA = tAtVertex(a);
    final tB = tAtVertex(b);
    return pointAtT(tA + (tB - tA) * clampedFraction);
  }

  static List<double> _cumulativeDistances(List<Offset> polyline) {
    if (polyline.isEmpty) {
      return const [];
    }
    final cumulative = <double>[0];
    for (var index = 1; index < polyline.length; index += 1) {
      cumulative.add(
        cumulative[index - 1] + (polyline[index] - polyline[index - 1]).distance,
      );
    }
    return cumulative;
  }
}
