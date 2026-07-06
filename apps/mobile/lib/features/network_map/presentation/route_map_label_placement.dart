import 'dart:ui' show Offset, Rect, Size;

// 구조화 노선도 라벨 배치 (#1641 Stage 3).
//
// 상용 앱(Mapbox GL) 방식: 우선순위(환승 > 주요 > 일반) 정렬 후, variable
// anchor로 후보 위치를 시도하며 이미 배치된 라벨과 겹치지 않는 첫 위치에 둔다.
// 모든 후보가 겹치면 그 라벨은 숨긴다. 충돌 검사는 화면(viewport) 픽셀 공간에서
// 한다 — 라벨 크기가 화면 px이고 겹침은 시각적이기 때문이다.
//
// 이 모듈은 순수 기하 로직만 담는다. 텍스트 실측(TextPainter)과 카메라 투영은
// 호출부(painter)가 하고, 실측된 [RouteMapLabelCandidate]를 넘긴다.

/// 라벨 박스를 anchor(역 점) 기준 어느 방향에 둘지. 대각 4방향 포함(8-position).
enum RouteMapLabelAnchor {
  right,
  left,
  above,
  below,
  aboveRight,
  belowRight,
  aboveLeft,
  belowLeft,
}

const double _kDiagonalGapFactor = 0.707; // 1/√2: 대각은 두 축에 나눠 띄운다.

/// 기본 anchor 시도 순서: 오른쪽 우선, 이어서 왼쪽/위/아래.
const List<RouteMapLabelAnchor> kDefaultRouteMapLabelAnchors = [
  RouteMapLabelAnchor.right,
  RouteMapLabelAnchor.left,
  RouteMapLabelAnchor.above,
  RouteMapLabelAnchor.below,
];

/// 라벨을 **지도 bbox 중심** 기준 바깥쪽으로 향하게 하는 8-position 시도 순서
/// (#1789 정적 배치, 스펙 S3). 뷰포트가 아니라 지도 좌표에만 의존하므로 팬·줌과
/// 무관하게 결정적이다 — 팬 중 라벨이 좌우로 점프하던 원인을 제거한다.
/// 순서: 지배축 바깥 → 바깥 대각 → 보조축 바깥 → 지배축×보조축 안쪽 대각 →
/// 보조축 안쪽 → 안쪽 대각들 → 지배축 안쪽.
List<RouteMapLabelAnchor> routeMapMapOutwardAnchorOrder(
  Offset anchorPoint,
  Offset mapCenter,
) {
  final dx = anchorPoint.dx - mapCenter.dx;
  final dy = anchorPoint.dy - mapCenter.dy;
  final h = dx >= 0 ? RouteMapLabelAnchor.right : RouteMapLabelAnchor.left;
  final hOpp = dx >= 0 ? RouteMapLabelAnchor.left : RouteMapLabelAnchor.right;
  final v = dy >= 0 ? RouteMapLabelAnchor.below : RouteMapLabelAnchor.above;
  final vOpp = dy >= 0 ? RouteMapLabelAnchor.above : RouteMapLabelAnchor.below;
  RouteMapLabelAnchor diag(RouteMapLabelAnchor hh, RouteMapLabelAnchor vv) {
    if (hh == RouteMapLabelAnchor.right) {
      return vv == RouteMapLabelAnchor.above
          ? RouteMapLabelAnchor.aboveRight
          : RouteMapLabelAnchor.belowRight;
    }
    return vv == RouteMapLabelAnchor.above
        ? RouteMapLabelAnchor.aboveLeft
        : RouteMapLabelAnchor.belowLeft;
  }

  final horizontalDominant = dx.abs() >= dy.abs();
  final dom = horizontalDominant ? h : v;
  final sec = horizontalDominant ? v : h;
  final domOpp = horizontalDominant ? hOpp : vOpp;
  final secOpp = horizontalDominant ? vOpp : hOpp;
  return [
    dom,
    diag(h, v),
    sec,
    horizontalDominant ? diag(h, vOpp) : diag(hOpp, v),
    secOpp,
    horizontalDominant ? diag(hOpp, v) : diag(h, vOpp),
    diag(hOpp, vOpp),
    domOpp,
  ];
}

/// 배치 후보 라벨 (viewport 공간).
class RouteMapLabelCandidate {
  const RouteMapLabelCandidate({
    required this.id,
    required this.anchor,
    required this.size,
    required this.priority,
    this.anchorPadding = 0,
  });

  /// 안정 정렬용 식별자 (보통 stationId:lineId).
  final String id;

  /// 역 점의 viewport 좌표.
  final Offset anchor;

  /// 실측된 라벨 크기 (viewport px).
  final Size size;

  /// 낮을수록 우선(0=환승, 1=주요, 2=일반). 우선순위 높은 라벨이 자리를 먼저 차지.
  final int priority;

  /// 역 마커 반지름 등, 라벨을 anchor에서 추가로 띄울 여백 px. gap에 더해진다.
  /// (환승 마커처럼 큰 글리프 위에 라벨이 겹치지 않게 한다.)
  final double anchorPadding;
}

/// 배치된 라벨과 최종 사각형.
class PlacedRouteMapLabel {
  const PlacedRouteMapLabel({
    required this.candidate,
    required this.rect,
    required this.anchor,
  });

  final RouteMapLabelCandidate candidate;
  final Rect rect;
  final RouteMapLabelAnchor anchor;
}

/// anchor 점 기준으로 [size] 라벨 박스를 [placement] 방향에 [gap]만큼 띄워 만든다.
Rect routeMapLabelRect(
  Offset anchorPoint,
  Size size,
  RouteMapLabelAnchor placement,
  double gap,
) {
  switch (placement) {
    case RouteMapLabelAnchor.right:
      return Rect.fromLTWH(
        anchorPoint.dx + gap,
        anchorPoint.dy - size.height / 2,
        size.width,
        size.height,
      );
    case RouteMapLabelAnchor.left:
      return Rect.fromLTWH(
        anchorPoint.dx - gap - size.width,
        anchorPoint.dy - size.height / 2,
        size.width,
        size.height,
      );
    case RouteMapLabelAnchor.above:
      return Rect.fromLTWH(
        anchorPoint.dx - size.width / 2,
        anchorPoint.dy - gap - size.height,
        size.width,
        size.height,
      );
    case RouteMapLabelAnchor.below:
      return Rect.fromLTWH(
        anchorPoint.dx - size.width / 2,
        anchorPoint.dy + gap,
        size.width,
        size.height,
      );
    case RouteMapLabelAnchor.aboveRight:
      return Rect.fromLTWH(
        anchorPoint.dx + gap * _kDiagonalGapFactor,
        anchorPoint.dy - gap * _kDiagonalGapFactor - size.height,
        size.width,
        size.height,
      );
    case RouteMapLabelAnchor.belowRight:
      return Rect.fromLTWH(
        anchorPoint.dx + gap * _kDiagonalGapFactor,
        anchorPoint.dy + gap * _kDiagonalGapFactor,
        size.width,
        size.height,
      );
    case RouteMapLabelAnchor.aboveLeft:
      return Rect.fromLTWH(
        anchorPoint.dx - gap * _kDiagonalGapFactor - size.width,
        anchorPoint.dy - gap * _kDiagonalGapFactor - size.height,
        size.width,
        size.height,
      );
    case RouteMapLabelAnchor.belowLeft:
      return Rect.fromLTWH(
        anchorPoint.dx - gap * _kDiagonalGapFactor - size.width,
        anchorPoint.dy + gap * _kDiagonalGapFactor,
        size.width,
        size.height,
      );
  }
}

/// 우선순위 정렬 후 greedy collision으로 겹치지 않는 라벨만 배치한다.
///
/// - [candidates]: 실측된 후보들.
/// - [anchors]: variable anchor 시도 순서.
/// - [gap]: 역 점과 라벨 사이 간격 px.
/// - [viewportBounds]: 주면 이 영역과 겹치지 않는 후보 위치는 건너뛴다(화면 밖).
List<PlacedRouteMapLabel> placeRouteMapLabels(
  List<RouteMapLabelCandidate> candidates, {
  List<RouteMapLabelAnchor> anchors = kDefaultRouteMapLabelAnchors,
  double gap = 4.0,
  Rect? viewportBounds,
}) {
  final sorted = [...candidates]
    ..sort((a, b) {
      final byPriority = a.priority.compareTo(b.priority);
      return byPriority != 0 ? byPriority : a.id.compareTo(b.id);
    });
  final placed = <PlacedRouteMapLabel>[];
  final placedRects = <Rect>[];
  for (final candidate in sorted) {
    for (final anchor in anchors) {
      final rect = routeMapLabelRect(
        candidate.anchor,
        candidate.size,
        anchor,
        gap + candidate.anchorPadding,
      );
      if (viewportBounds != null && !viewportBounds.overlaps(rect)) {
        continue;
      }
      final collides = placedRects.any((other) => other.overlaps(rect));
      if (!collides) {
        placed.add(
          PlacedRouteMapLabel(candidate: candidate, rect: rect, anchor: anchor),
        );
        placedRects.add(rect);
        break;
      }
    }
  }
  return placed;
}
