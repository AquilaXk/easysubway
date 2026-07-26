import 'dart:math' as math;
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

// #2068 SVG 충실도(2026-07-26): basemap 전용 라벨 배치 상수 2종을 제거했다 —
// kRouteMapBasemapLabelGapPx(라벨 gap 사다리 시작값)·kRouteMapBasemapLineHalfWidthPx
// (선 장애물 반폭). 오너 결정("글자도 복붙")으로 바탕층 모드에서 앱이 역명을
// 그리지 않게 되면서 이 값들을 쓰던 라벨 솔버의 basemap 분기가 사라져 참조가
// 0이 됐다. public const는 analyzer가 미사용 경고를 내지 않으므로 명시적으로
// 걷어낸다. 나머지 basemap 상수(환승 캡슐 3종·역 노드 반경)는 팬 메뉴 앵커
// (fanMenuAnchorNodeHeight)가 계속 쓰므로 남긴다.

/// SVG 바탕층(#2068) 환승 캡슐의 design px 반폭. basemap 모드에서는 구조화 캡슐
/// 대신 오너 SVG 캡슐이 화면에 그려지고 실측 반폭이 훨씬 크므로, 라벨 장애물·
/// 환승 라벨 anchorPadding을 이 값으로 부풀려 라벨이 캡슐을 침범하지 않게 한다.
/// 수도권 실데이터 fixture(routeMapDesignSpaceFor)로 실측한 designScale=1.3729673
/// 기준(이전 추정 1.19는 nearest-neighbor 근사 오차): shell stroke-width 40 local
/// / 2 × 0.455(레이어 스케일) × 1.373 ≈ 12.5 design px. 외곽 스트로크 절반과 여유를
/// 더해 13.0으로 상향한다 — 11.0에서는 실기기 확인 결과 약수·옥수·청구 라벨이
/// 캡슐 끝에 닿아 보였다(여유 ~1.6px 불충분). (부산·대구는 designScale이 작아
/// 실측 반폭이 더 작다 — 과대 시 라벨이 조금 더 밀릴 뿐 겹침 방향으로는 안전).
/// #2068 수도권 노드 간격 최소 기준 패스(2026-07-18) 후 재실측: 중앙값 간격이
/// 48px로 정규화되며 designScale=1.340070912085764로 소폭 하향(≈-2.4%) — 위
/// 12.5 design px 추정도 12.2로 낮아지지만 13.0 여유폭 안에 그대로 들어와
/// 상수 조정은 불필요하다(아래 파생값들도 동일 논리로 안전).
const double kRouteMapBasemapTransferCapsuleHalfWidthPx = 13.0;

/// basemap 캡슐 장축(멤버 수) 반폭 기여분(design px) — SVG data-slot-size=3u=
/// 24 local × 0.455(레이어 스케일) × designScale 1.373 ≈ 15 design px 슬롯 간격의
/// 절반. 멤버(배지)가 하나 늘 때마다 캡슐 장축 반폭이 이만큼 는다. 종로3가(3개
/// 노선 환승) 실기기 재확인(2026-07-16): member bbox가 route_map_positions
/// 수렴 파이프라인으로 눌려(스프레드 14.4) 고정 반폭 13 inflate로는 기하상
/// 3.8px 여유가 있었는데도 화면에서 라벨이 캡슐에 닿아 보였다 — 멤버 수 기반
/// 하한이 없어 3-슬롯 캡슐의 실제 장축을 과소평가했기 때문이다.
const double kRouteMapBasemapTransferSlotHalfWidthPx = 7.5;

/// basemap 캡슐 장축 반폭의 멤버 수 무관 기저값(design px) — SVG 배지 반경
/// r=12 local × 0.455 × designScale 1.373 ≈ 7.5 design px에 캡슐 외곽 스트로크·
/// 여유를 더한 값. [kRouteMapBasemapTransferSlotHalfWidthPx]와 함께
/// `(memberCount-1) × slot + base` 로 멤버 수 기반 반폭 하한을 이룬다.
const double kRouteMapBasemapTransferCapsuleBaseHalfWidthPx = 9.0;

/// basemap 캡슐 **장축** 반폭(design px). 위 세 상수를
/// `(memberCount-1) × slot + base` 로 조합한 멤버 수 기반 하한이며, 고정 반폭
/// [kRouteMapBasemapTransferCapsuleHalfWidthPx]와의 max를 취한다.
///
/// 이 값은 **장축** 하한이다. 라벨 솔버는 방향 정보가 없어 균등 inflate로 쓰지만
/// (과대는 라벨이 조금 더 밀릴 뿐 안전 방향), 노드의 **세로 크기**를 구할 때는
/// 캡슐 장축이 실제로 세로일 때만 쓰고 아니면 두께
/// ([kRouteMapBasemapTransferCapsuleHalfWidthPx])를 써야 한다 — 가로 캡슐에 이
/// 값을 세로로 적용하면 세로 크기를 크게 과대평가한다.
///
/// 라벨 장애물(`routeMapTransferObstacleRects`)과 팬 메뉴 앵커
/// (`fanMenuAnchorNodeHeight`)가 같은 캡슐 모델을 소비하도록 단일 출처로 둔다.
double routeMapBasemapTransferCapsuleHalfWidthFor(int memberCount) => math.max(
  kRouteMapBasemapTransferCapsuleHalfWidthPx,
  (memberCount - 1) * kRouteMapBasemapTransferSlotHalfWidthPx +
      kRouteMapBasemapTransferCapsuleBaseHalfWidthPx,
);

/// SVG 바탕층(#2068) 일반(비환승) 역 심벌의 design px 외곽 반경. basemap 모드에서
/// 이웃 라벨이 남의 역 노드를 덮지 않도록 장애물로 시드하고, 자기 라벨의
/// anchorPadding 하한으로도 쓴다(자기 노드와 자기 라벨이 최소 gap에서 충돌 방지).
/// 수도권 SVG station-symbols-layer 원 실측: 지배 r=5.8 local·stroke-width 1.5
/// (원 353개), 그 외 r=6/sw2·r=6.5/sw3. 외곽 반경 = (r + stroke/2) × 0.455 ×
/// 1.373 → r5.8≈4.09·r6≈4.37·r6.5≈5.00 design px. 지배 케이스+여유를 덮는 4.5로
/// 잡는다(과대 시 라벨이 조금 더 밀릴 뿐 겹침 방향으로는 안전).
const double kRouteMapBasemapStationNodeRadiusPx = 4.5;

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
