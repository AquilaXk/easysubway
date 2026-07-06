// 환승역 마커 기하(캡슐 + 노선별 색 도트)의 순수 계산 (#1792 G3).
//
// 기존 환승 마커는 흰 원 + 짙은 테두리 하나였다 — 어느 노선이 만나는지 색으로
// 드러나지 않았다. 상용 노선도처럼 물리 역당 캡슐(pill) 하나를 그리고 그 안에
// 노선 수만큼 색 도트를 세로로 쌓아 환승 노선을 색으로 표현한다.
//
// 렌더링은 이 모듈에 없다 — painter가 [RouteMapTransferMarker]를 소비해 그린다.
// 좌표·크기 계산만 순수 함수로 두어 지오메트리를 기계 판정할 수 있게 한다.
import 'dart:ui' show Color, Offset, RRect, Radius, Rect;

// 환승 캡슐 실측 비율 상수(선8·도트10·캡슐짧은축19·간격13 → 선 4px 환산, #1792 G3).
// painter와 라벨 솔버(장애물 rect)가 같은 값을 소비해 기하 정합을 보장한다.
const double kRouteMapTransferDotRadiusPx = 2.5;
const double kRouteMapTransferDotGapPx = 1.5;
const double kRouteMapTransferDotPaddingPx = 1.5;

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

/// 환승 그룹 중심 [center]에 노선 수([colors])만큼 색 도트를 쌓은 마커 기하를
/// 만든다. 도트는 center 기준 대칭으로 균등 배치하고, 캡슐은 도트 전체를
/// [padding]만큼 여백을 두고 감싼다(짧은축 반폭 = corner radius).
///
/// [horizontalDots]가 true면 도트를 가로로 쌓고 캡슐을 가로 스타디움으로 만든다
/// (국소 corridor가 수평인 환승의 자연스러운 배치). false(기본)면 기존 세로 스택
/// 동작을 그대로 유지한다.
///
/// - 도트 center-to-center 간격 = 2*[dotRadius] + [dotGap].
/// - 노선 1개면 정사각 캡슐(원형 pill), 0개면 빈 마커.
RouteMapTransferMarker routeMapTransferMarker({
  required Offset center,
  required List<Color> colors,
  required double dotRadius,
  required double dotGap,
  required double padding,
  bool horizontalDots = false,
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
  final thickness = 2 * (dotRadius + padding);

  if (horizontalDots) {
    final firstDx = center.dx - span / 2;
    final dots = <RouteMapTransferDot>[
      for (var index = 0; index < colors.length; index += 1)
        RouteMapTransferDot(
          center: Offset(firstDx + index * spacing, center.dy),
          color: colors[index],
        ),
    ];
    final width = span + thickness;
    final height = thickness;
    return RouteMapTransferMarker(
      capsule: RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: width, height: height),
        Radius.circular(height / 2),
      ),
      dots: dots,
    );
  }

  final firstDy = center.dy - span / 2;
  final dots = <RouteMapTransferDot>[
    for (var index = 0; index < colors.length; index += 1)
      RouteMapTransferDot(
        center: Offset(center.dx, firstDy + index * spacing),
        color: colors[index],
      ),
  ];

  final width = thickness;
  final height = span + thickness;
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

/// 환승 그룹 하나를 이격(designSpread, design px)에 따라 그린다:
/// - 스택(사실상 한 점): centroid에 표준 폭 캡슐 + 세로 도트.
/// - 스팬(소이격 평행 노선): 멤버를 캡슐이 걸침 — 긴축 상한 spanMax+표준폭.
/// - 강등 스택(스팬 상한 초과~분리 하한): 이격을 무시하고 centroid 고정 크기 —
///   캡슐이 이격에 비례해 커지던 "초거대 원/타원"을 제거한다(#1789 캡슐 통일).
/// - 분리(대이격): 동명이역 오병합·좌표 검수 대상은 별개 마커가 정직한 표현.
/// 임계는 전부 design px 기준이며 캘리브레이션 값이다(실기기 QA로 튜닝 가능).
///
/// [horizontalDots]는 스택·강등 스택 모드의 도트/캡슐을 가로로 눕힌다(국소
/// corridor가 수평인 환승용). 스팬 모드 캡슐은 멤버 좌표 spread를 그대로 따르므로
/// 영향받지 않는다.
List<RouteMapTransferMarker> routeMapTransferMarkers({
  required List<Offset> memberCenters,
  required List<Color> colors,
  required double designSpread,
  required double dotRadius,
  required double dotGap,
  required double padding,
  bool horizontalDots = false,
  double stackedMaxDesignSpread = 8,
  double spanMaxDesignSpread = 16,
  double separateMinDesignSpread = 28,
}) {
  if (memberCenters.isEmpty || memberCenters.length != colors.length) {
    return const [];
  }
  if (designSpread <= stackedMaxDesignSpread ||
      (designSpread > spanMaxDesignSpread &&
          designSpread <= separateMinDesignSpread)) {
    return [
      routeMapTransferMarker(
        center: _meanOffset(memberCenters),
        colors: colors,
        dotRadius: dotRadius,
        dotGap: dotGap,
        padding: padding,
        horizontalDots: horizontalDots,
      ),
    ];
  }
  if (designSpread <= spanMaxDesignSpread) {
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
        horizontalDots: horizontalDots,
      ),
  ];
}
