// 환승역 마커 기하(캡슐 + 노선별 색 도트)의 순수 계산 (#1792 G3).
//
// 기존 환승 마커는 흰 원 + 짙은 테두리 하나였다 — 어느 노선이 만나는지 색으로
// 드러나지 않았다. 상용 노선도처럼 물리 역당 캡슐(pill) 하나를 그리고 그 안에
// 노선 수만큼 색 도트를 세로로 쌓아 환승 노선을 색으로 표현한다.
//
// 렌더링은 이 모듈에 없다 — painter가 [RouteMapTransferMarker]를 소비해 그린다.
// 좌표·크기 계산만 순수 함수로 두어 지오메트리를 기계 판정할 수 있게 한다.
import 'dart:ui' show Color, Offset, RRect, Radius, Rect;

/// 환승 마커의 색 도트 한 개 (노선별).
class RouteMapTransferDot {
  const RouteMapTransferDot({required this.center, required this.color});

  final Offset center;
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is RouteMapTransferDot &&
      other.center == center &&
      other.color == color;

  @override
  int get hashCode => Object.hash(center, color);
}

/// 환승역 마커 기하: 노선별 색 도트와 이를 감싸는 캡슐(pill).
class RouteMapTransferMarker {
  const RouteMapTransferMarker({required this.capsule, required this.dots});

  /// 도트를 감싸는 스타디움 모양 배경(가로 반폭 = corner radius).
  final RRect capsule;

  /// 노선 순서를 보존한 색 도트 목록.
  final List<RouteMapTransferDot> dots;
}

/// 환승 그룹 중심 [center]에 노선 수([colors])만큼 색 도트를 세로로 쌓은
/// 마커 기하를 만든다. 도트는 center 기준 세로 대칭으로 균등 배치하고, 캡슐은
/// 도트 전체를 [padding]만큼 여백을 두고 감싼다(가로 반폭 = corner radius).
///
/// - 도트 center-to-center 간격 = 2*[dotRadius] + [dotGap].
/// - 노선 1개면 정사각 캡슐(원형 pill), 0개면 빈 마커.
RouteMapTransferMarker routeMapTransferMarker({
  required Offset center,
  required List<Color> colors,
  required double dotRadius,
  required double dotGap,
  required double padding,
}) {
  if (colors.isEmpty) {
    return RouteMapTransferMarker(
      capsule: RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 0, height: 0),
        Radius.zero,
      ),
      dots: const [],
    );
  }

  final spacing = 2 * dotRadius + dotGap;
  final span = (colors.length - 1) * spacing;
  final firstDy = center.dy - span / 2;

  final dots = <RouteMapTransferDot>[
    for (var index = 0; index < colors.length; index += 1)
      RouteMapTransferDot(
        center: Offset(center.dx, firstDy + index * spacing),
        color: colors[index],
      ),
  ];

  final width = 2 * (dotRadius + padding);
  final height = span + 2 * (dotRadius + padding);
  return RouteMapTransferMarker(
    capsule: RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: width, height: height),
      Radius.circular(width / 2),
    ),
    dots: dots,
  );
}

/// 점 집합의 최대 쌍거리. 0·1개면 0.
double offsetsMaxPairwiseDistance(List<Offset> points) {
  var max = 0.0;
  for (var i = 0; i < points.length; i += 1) {
    for (var j = i + 1; j < points.length; j += 1) {
      final d = (points[i] - points[j]).distance;
      if (d > max) {
        max = d;
      }
    }
  }
  return max;
}

Offset _meanOffset(List<Offset> points) {
  var sum = Offset.zero;
  for (final point in points) {
    sum += point;
  }
  return points.isEmpty ? Offset.zero : sum / points.length.toDouble();
}

/// 환승 그룹 하나를 이격(sourceSpread, source 좌표계 기준)에 따라 3모드로 그린다:
/// 스택(사실상 한 점) / 스팬(평행 노선들을 캡슐이 걸침, 공식 노선도 문법) /
/// 분리(대이격 — 동명이역 오병합·검수 대상은 별개 마커가 정직한 표현).
/// [memberCenters]는 viewport 좌표이고 [colors]와 같은 순서다.
List<RouteMapTransferMarker> routeMapTransferMarkers({
  required List<Offset> memberCenters,
  required List<Color> colors,
  required double sourceSpread,
  required double dotRadius,
  required double dotGap,
  required double padding,
  double stackedMaxSourceSpread = 8,
  double spanMaxSourceSpread = 60,
}) {
  if (memberCenters.isEmpty || memberCenters.length != colors.length) {
    return const [];
  }
  if (sourceSpread <= stackedMaxSourceSpread) {
    return [
      routeMapTransferMarker(
        center: _meanOffset(memberCenters),
        colors: colors,
        dotRadius: dotRadius,
        dotGap: dotGap,
        padding: padding,
      ),
    ];
  }
  if (sourceSpread <= spanMaxSourceSpread) {
    var bounds = Rect.fromCenter(
      center: memberCenters.first,
      width: 0,
      height: 0,
    );
    for (final center in memberCenters.skip(1)) {
      bounds = bounds.expandToInclude(
        Rect.fromCenter(center: center, width: 0, height: 0),
      );
    }
    final inflated = bounds.inflate(dotRadius + padding);
    final radius = inflated.shortestSide / 2;
    return [
      RouteMapTransferMarker(
        capsule: RRect.fromRectAndRadius(inflated, Radius.circular(radius)),
        dots: [
          for (var i = 0; i < memberCenters.length; i += 1)
            RouteMapTransferDot(center: memberCenters[i], color: colors[i]),
        ],
      ),
    ];
  }
  return [
    for (var i = 0; i < memberCenters.length; i += 1)
      routeMapTransferMarker(
        center: memberCenters[i],
        colors: [colors[i]],
        dotRadius: dotRadius,
        dotGap: dotGap,
        padding: padding,
      ),
  ];
}
