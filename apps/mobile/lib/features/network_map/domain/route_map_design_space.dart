import 'dart:ui' show Offset;

import 'structured_route_map.dart';

// 노선도 design space (#1789 정적 스케일 렌더, 스펙 S1).
//
// 모든 글리프·라벨·선 폭을 design px 단일 좌표계에 고정하고, 줌은 그림 전체의
// 스케일(camera.scale / k*)로만 처리한다. 아래 상수는 공식 노선도 실측 비율
// (선8·도트10·캡슐19 → 선 4px 환산 체계)을 잇는 **캘리브레이션 상수**다 —
// 실기기 QA(중간 줌에서 환승역명 가독)에 따라 조정될 수 있다.

/// 인접 역 간 중앙값 간격을 이 design px로 정규화한다.
const double kRouteMapDesignStationSpacingPx = 48.0;
const double kRouteMapDesignLineWidthPx = 4.0;
const double kRouteMapDesignStationRadiusPx = 3.0;
const double kRouteMapDesignLabelFontPx = 13.0;
const double kRouteMapDesignBadgeFontPx = 11.0;
const double kRouteMapDesignBadgeRadiusPx = 9.0;
const double kRouteMapDesignLabelGapPx = 4.0;

/// SVG 바탕층(#2068) 환승 캡슐의 design px 반폭. basemap 모드에서는 구조화 캡슐
/// 대신 오너 SVG 캡슐이 화면에 그려지고 실측 반폭이 훨씬 크므로, 라벨 장애물·
/// 환승 라벨 anchorPadding을 이 값으로 부풀려 라벨이 캡슐을 침범하지 않게 한다.
/// 수도권 실데이터 fixture(routeMapDesignSpaceFor)로 실측한 designScale=1.3729673
/// 기준(이전 추정 1.19는 nearest-neighbor 근사 오차): shell stroke-width 40 local
/// / 2 × 0.455(레이어 스케일) × 1.373 ≈ 12.5 design px. 외곽 스트로크 절반과 여유를
/// 더해 13.0으로 상향한다 — 11.0에서는 실기기 확인 결과 약수·옥수·청구 라벨이
/// 캡슐 끝에 닿아 보였다(여유 ~1.6px 불충분). (부산·대구는 designScale이 작아
/// 실측 반폭이 더 작다 — 과대 시 라벨이 조금 더 밀릴 뿐 겹침 방향으로는 안전).
const double kRouteMapBasemapTransferCapsuleHalfWidthPx = 13.0;

/// 노선 뱃지 반복 간격(design px). 일반 탐색 줌(라벨≈design 크기 그대로 보이는
/// scale≈k*)에서 짧은 화면축(~360dp)에 최소 1개 걸리도록 잡는다(스펙 S4).
const double kRouteMapDesignBadgeIntervalPx = 340.0;

/// 최대 확대에서 역명이 도달할 화면 px (스펙 S2: ~22–24px 기준의 상한).
const double kRouteMapMaxLabelScreenPx = 26.0;

class RouteMapDesignSpace {
  const RouteMapDesignSpace({required this.designScale});

  /// k*: source 단위 → design px 배율.
  final double designScale;

  Offset toDesign(Offset source) => source * designScale;

  /// 라벨 폰트가 [kRouteMapMaxLabelScreenPx]에 닿는 camera scale (스펙 S2).
  double get maxCameraScale =>
      designScale * (kRouteMapMaxLabelScreenPx / kRouteMapDesignLabelFontPx);
}

/// 지역 기하에서 design space를 1회 산출한다. 인접 정점 간 거리의 중앙값이
/// [kRouteMapDesignStationSpacingPx]가 되도록 k*를 정한다. line geometry의
/// 정점은 역 위치이므로(#1638 track 렌더) "인접 역 간격"의 대리값으로 쓴다.
RouteMapDesignSpace routeMapDesignSpaceFor(StructuredRouteMap map) {
  final distances = <double>[];
  for (final line in map.lines) {
    for (final polyline in line.polylines) {
      for (var i = 1; i < polyline.length; i += 1) {
        final d = (polyline[i] - polyline[i - 1]).distance;
        if (d > 0) {
          distances.add(d);
        }
      }
    }
  }
  if (distances.isEmpty) {
    return const RouteMapDesignSpace(designScale: 1.0);
  }
  distances.sort();
  final median = distances[distances.length ~/ 2];
  return RouteMapDesignSpace(
    designScale: kRouteMapDesignStationSpacingPx / median,
  );
}
