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
