import 'dart:math' as math;
import 'dart:ui' show Color, Offset, Rect, Size;

import '../domain/route_map_design_space.dart';
import '../domain/route_map_owner_labels.dart';
import '../domain/route_map_parallel_offsets.dart';
import '../domain/structured_route_map.dart';
import 'route_map_label_placement.dart';
import 'route_map_transfer_marker.dart';

// 정적 라벨 레이아웃 솔버 (#1789 스펙 S3·S4).
//
// 지역 로드 시 1회, design space에서 라벨·뱃지 자리를 확정한다. 이후 팬·줌은
// 그림 전체 스케일이라 재배치가 없다 — "설계 스케일에서 충돌 없으면 모든
// 줌에서 충돌 없음"(균등 스케일 불변성). 카카오지하철 문법대로 전부 표시:
// 어떤 라벨도 숨기지 않으며, 물리적으로 불가피한 겹침만 최소화 배치 후
// unresolvedOverlapCount로 집계해 감사·튜닝 대상으로 남긴다.

/// 배치된 역명 라벨 (design space px). [bold]는 환승 또는 종착.
class RouteMapStaticLabel {
  const RouteMapStaticLabel({
    required this.id,
    required this.text,
    required this.rect,
    required this.bold,
  });

  /// `transfer:<stationId>` 또는 `<stationId>:<lineId>`.
  final String id;
  final String text;
  final Rect rect; // design space px
  final bool bold;
}

/// 배치된 노선 뱃지 pill (design space px).
class RouteMapStaticBadge {
  const RouteMapStaticBadge({
    required this.lineId,
    required this.label,
    required this.rect,
  });

  final String lineId;
  final String label;
  final Rect rect; // design space px
}

/// 정적 레이아웃 결과. [unresolvedOverlapCount]는 최소 겹침 fallback으로 강제
/// 배치된(=겹침을 못 피한) 라벨 수 — 데이터 품질 감사·튜닝용.
class RouteMapStaticLabelLayout {
  const RouteMapStaticLabelLayout({
    required this.labels,
    required this.badges,
    required this.unresolvedOverlapCount,
  });

  final List<RouteMapStaticLabel> labels;
  final List<RouteMapStaticBadge> badges;
  final int unresolvedOverlapCount;
}

/// 우선순위: 뱃지 -1 > 환승 0 > 주요 1 > 일반 2 (기존 규칙 유지).
int _priorityFor(RouteMapLabelClass labelClass) {
  switch (labelClass) {
    case RouteMapLabelClass.transfer:
      return 0;
    case RouteMapLabelClass.major:
      return 1;
    case RouteMapLabelClass.regular:
      return 2;
  }
}

class _Candidate {
  _Candidate({
    required this.id,
    required this.text,
    required this.anchor,
    required this.size,
    required this.priority,
    required this.anchorPadding,
    required this.bold,
    this.badgeLineId,
  });
  final String id;
  final String text;
  final Offset anchor;
  final Size size;
  final int priority;
  final double anchorPadding;
  final bool bold;
  final String? badgeLineId; // null이면 역 라벨.
}

/// basemap 캡슐 반폭(design px) — SVG 캡슐 장축이 멤버(배지) 수에 비례해 는다.
/// route_map_positions의 환승 멤버 좌표 수렴 파이프라인 때문에 member bbox가
/// 실제 SVG 캡슐 장축을 반영하지 못해(예: 종로3가 3-노선 환승이 스프레드
/// 14.4로 눌림) 고정 반폭만으로는 과소평가한다 — 멤버 수 기반 하한을 둔다.
/// 방향 정보가 없어 균등 inflate(과대는 라벨이 조금 더 밀릴 뿐 안전 방향).
double _basemapCapsuleHalfWidthFor(int memberCount) => math.max(
  kRouteMapBasemapTransferCapsuleHalfWidthPx,
  (memberCount - 1) * kRouteMapBasemapTransferSlotHalfWidthPx +
      kRouteMapBasemapTransferCapsuleBaseHalfWidthPx,
);

/// 오너 SVG 앵커 [anchorDesign](design px)에 [anchor] 의미(start=좌측·middle=
/// 수평중앙·end=우측, 전부 baseline)대로 앱 실측 [size] 텍스트를 배치한다
/// (#2068 6차). baseline 근사: SVG는 y가 baseline이므로
/// `rect.top = anchorY − 0.8×appFontPx` — 앱 폰트([appFontPx], design px)가
/// 오너 SVG font-size(design 환산 ≈16.5~17.8px)보다 작아 오너가 비워둔
/// 영역 안에 들어간다.
Rect _ownerLabelRect(
  Offset anchorDesign,
  Size size,
  RouteMapOwnerLabelAnchor anchor,
  double appFontPx,
) {
  final top = anchorDesign.dy - 0.8 * appFontPx;
  switch (anchor) {
    case RouteMapOwnerLabelAnchor.middle:
      return Rect.fromLTWH(
        anchorDesign.dx - size.width / 2,
        top,
        size.width,
        size.height,
      );
    case RouteMapOwnerLabelAnchor.end:
      return Rect.fromLTWH(
        anchorDesign.dx - size.width,
        top,
        size.width,
        size.height,
      );
    case RouteMapOwnerLabelAnchor.start:
      return Rect.fromLTWH(anchorDesign.dx, top, size.width, size.height);
  }
}

/// 오너 라벨 매칭 위치 게이트(design px, #2068 7차) — 동명이역(신촌·양평 등)이
/// 같은 sidecar 앵커를 두고 경쟁할 때, station.position(또는 환승 centroid)이
/// 오너 앵커에서 이 거리보다 멀면 애초에 후보에서 제외해 기존 솔버로 폴백시킨다.
///
/// 실측 근거(수도권 실데이터, 2026-07-16 — 동명이역 2건을 정상 매치 후보에서
/// 제외하고 나머지 648개 매치의 station↔오너 앵커 거리):
/// min=2.3, p50=27.1, p90=52.4, p95=67.9, p99=96.0, **실측 최댓값=122.7**
/// (정왕 환승 그룹 — 라벨이 station point에서 멀리 떨어진 정당한 배치).
/// 122.7 × 1.5(여유) ≈ 184.1 → 185.0으로 올림. 이 값은 정상 매치(정왕 등)를
/// 전부 통과시키면서, 양평의 오배치(경의중앙선 양평역, 거리 1880.9 — 실제로는
/// 수인분당선 양평역의 라벨을 공유해 발생)는 배제한다. 신촌(거리 107.2 —
/// 정상 매치 최댓값 122.7보다 작아 이 게이트만으로는 못 거름)은 아래
/// [_resolveOwnerLabelsByCandidateKey]의 "이름별 최근접 1개만 채택" 규칙이
/// 별도로 해소한다(거리 게이트와 최근접 우선은 서로 다른 안전장치).
const double kRouteMapOwnerLabelMaxAnchorDistancePx = 185.0;

/// SVG·DB 표기 차 정규화(#2068 7차 지시 2) — 중점(·)을 마침표(.)로 통일해
/// "4·19민주묘지"/DB "4.19민주묘지", "전대·에버랜드"/DB "전대.에버랜드" 2건을
/// 회수한다. **다른 정규화는 과매칭 위험이 있어 추가하지 않는다**(공백·괄호·
/// "역" 접미 등은 그대로 둔다 — 시청·용인대·총신대입구(이수)·하남검단산 등은
/// 여전히 미매치로 남아 솔버 폴백).
String _normalizeOwnerLabelNameKey(String name) => name.replaceAll('·', '.');

/// basemap 모드에서 candidate id(`transfer:<stationId>` 또는
/// `<stationId>:<lineId>`) → 채택된 오너 라벨을 사전 해소한다(#2068 7차).
/// 1) 이름 정규화(중점/마침표) 후 station 원본명으로 오너 라벨을 찾는다.
/// 2) 같은 정규화 이름을 가진 후보(동명이역)가 여럿이면, 오너 앵커에서 가장
///    가까운 후보 1개만 채택한다 — 나머지는 결과 맵에 없어(null) 기존 솔버로
///    폴백한다(신촌·양평 케이스 해소).
/// 3) 채택된 후보도 [kRouteMapOwnerLabelMaxAnchorDistancePx] 위치 게이트를
///    통과해야 한다(양평의 원거리 오배치 등 병리적 케이스 방어).
Map<String, RouteMapOwnerLabelEntry> _resolveOwnerLabelsByCandidateKey({
  required StructuredRouteMap map,
  required RouteMapDesignSpace design,
  required Map<String, RouteMapOwnerLabelEntry> ownerLabelsByStationName,
  required Map<String, String> stationNameByStationId,
}) {
  if (ownerLabelsByStationName.isEmpty || stationNameByStationId.isEmpty) {
    return const {};
  }
  final normalizedOwnerLabels = <String, RouteMapOwnerLabelEntry>{};
  for (final entry in ownerLabelsByStationName.entries) {
    normalizedOwnerLabels[_normalizeOwnerLabelNameKey(entry.key)] = entry.value;
  }
  // 정규화 이름 → 후보(candidateKey, design 좌표) 목록.
  final candidatesByName = <String, List<(String key, Offset anchor)>>{};
  for (final group in map.transferGroups) {
    final rawName = stationNameByStationId[group.stationId];
    if (rawName == null) continue;
    candidatesByName
        .putIfAbsent(_normalizeOwnerLabelNameKey(rawName), () => [])
        .add(('transfer:${group.stationId}', design.toDesign(group.centroid)));
  }
  for (final station in map.stations) {
    if (station.labelClass == RouteMapLabelClass.transfer) continue;
    final rawName = stationNameByStationId[station.stationId];
    if (rawName == null) continue;
    candidatesByName
        .putIfAbsent(_normalizeOwnerLabelNameKey(rawName), () => [])
        .add((
          '${station.stationId}:${station.lineId}',
          design.toDesign(station.position),
        ));
  }

  final resolved = <String, RouteMapOwnerLabelEntry>{};
  for (final labelEntry in normalizedOwnerLabels.entries) {
    final candidates = candidatesByName[labelEntry.key];
    if (candidates == null || candidates.isEmpty) {
      continue;
    }
    final anchorDesign = design.toDesign(labelEntry.value.position);
    String? bestKey;
    var bestDistance = double.infinity;
    for (final (key, stationAnchor) in candidates) {
      final distance = (stationAnchor - anchorDesign).distance;
      if (distance > kRouteMapOwnerLabelMaxAnchorDistancePx) {
        continue;
      }
      if (distance < bestDistance) {
        bestDistance = distance;
        bestKey = key;
      }
    }
    if (bestKey != null) {
      resolved[bestKey] = labelEntry.value;
    }
  }
  return resolved;
}

/// 환승 캡슐의 design space 외접 Rect — 라벨 배치의 선점 장애물(#1789).
/// painter와 같은 [routeMapTransferMarkers] 호출로 기하 정합을 보장한다
/// (색은 캡슐 기하에 영향이 없어 placeholder를 넘긴다).
List<Rect> routeMapTransferObstacleRects(
  StructuredRouteMap map,
  RouteMapDesignSpace design, {
  bool basemap = false,
}) {
  final rects = <Rect>[];
  for (final group in map.transferGroups) {
    final centers = [for (final p in group.memberPositions) design.toDesign(p)];
    if (basemap) {
      // basemap 모드의 화면 캡슐은 오너 SVG 것(구조화 캡슐 아님)이라 실측 반폭이
      // 크다. SVG 캡슐은 멤버 배지 중심을 잇는 직선 스타디움이므로, 멤버 design
      // 좌표 bounding box를 실측 반폭만큼 부풀린 rect가 실기 캡슐에 더 가깝다.
      if (centers.isEmpty) {
        continue;
      }
      var bounds = Rect.fromCenter(center: centers.first, width: 0, height: 0);
      for (final center in centers.skip(1)) {
        bounds = bounds.expandToInclude(
          Rect.fromCenter(center: center, width: 0, height: 0),
        );
      }
      rects.add(bounds.inflate(_basemapCapsuleHalfWidthFor(centers.length)));
      continue;
    }
    final markers = routeMapTransferMarkers(
      memberCenters: centers,
      colors: List<Color>.filled(centers.length, const Color(0xFF000000)),
      designSpread:
          offsetsMaxPairwiseDistance(group.memberPositions) *
          design.designScale,
      dotRadius: kRouteMapTransferDotRadiusPx,
      dotGap: kRouteMapTransferDotGapPx,
      padding: kRouteMapTransferDotPaddingPx,
    );
    for (final marker in markers) {
      rects.add(marker.capsule.outerRect);
    }
  }
  return rects;
}

RouteMapStaticLabelLayout solveRouteMapLabelLayout({
  required StructuredRouteMap map,
  required RouteMapDesignSpace design,
  required Map<String, String> labelTextByStationId,
  required Map<String, String> badgeLabelByLineId,
  required Size Function(String text, {required bool bold}) measureLabel,
  required Size Function(String text) measureBadge,
  bool basemap = false,
  // basemap 6차(#2068): 오너가 SVG에서 손배치한 라벨 앵커. station 원본 이름
  // (축약 전 nameKo) 기준 정확 일치로 조회한다 — labelTextByStationId는 화면
  // 표시용 축약(괄호 부역명 제거) 텍스트라 매칭 키로 못 쓴다. 둘 다 기본값이
  // 빈 맵이라 기존 호출부는 동작 불변(옵트인).
  Map<String, RouteMapOwnerLabelEntry> ownerLabelsByStationName = const {},
  Map<String, String> stationNameByStationId = const {},
}) {
  final terminusIds = routeMapTerminusStationIds(map);
  final candidates = <_Candidate>[];
  // basemap 모드 오너 라벨 고정 배치(#2068 6~7차) — 검색(gap 사다리)을 거치지
  // 않고 SVG 실측 앵커에 즉시 확정한다. 미매치(원본명 없음·sidecar 미보유·
  // 이름 정규화 후에도 미매치·위치 게이트 밖·동명이역 중 비최근접)는
  // candidates에 담겨 기존 4차 자동 솔버 경로로 폴백한다.
  final ownerFixedLabels = <RouteMapStaticLabel>[];
  // candidate id → 채택된 오너 라벨(동명이역 최근접 해소·위치 게이트 적용 후).
  final resolvedOwnerLabels = basemap
      ? _resolveOwnerLabelsByCandidateKey(
          map: map,
          design: design,
          ownerLabelsByStationName: ownerLabelsByStationName,
          stationNameByStationId: stationNameByStationId,
        )
      : const <String, RouteMapOwnerLabelEntry>{};

  // 1) 노선 뱃지: 끝점 + arc length 반복 (스펙 S4 — 노선 중간 확대에도 식별).
  for (final line in map.lines) {
    final label = badgeLabelByLineId[line.lineId];
    if (label == null || label.isEmpty) {
      continue;
    }
    final size = measureBadge(label);
    var emitted = 0;
    void emit(Offset source) {
      candidates.add(
        _Candidate(
          id: 'badge:${line.lineId}:${emitted++}',
          text: label,
          anchor: design.toDesign(source),
          size: size,
          priority: -1,
          anchorPadding: kRouteMapDesignBadgeRadiusPx,
          bold: false,
          badgeLineId: line.lineId,
        ),
      );
    }

    // 노선 뱃지는 **종점에만** 둔다(공식 노선도 관례). 선 따라 반복하면 역명을
    // 덮어 가독을 해친다 — 중간 구간은 선 색으로 노선을 식별한다(#1789 튜닝).
    //
    // anchor = 실제 양 극점(모든 조각 끝점 중 상호 최원 쌍). 다중 조각 노선에서
    // first/last가 중앙 조각 경계로 잡혀 뱃지가 도심을 덮던 문제를 고친다(#1789).
    final endpoints = <Offset>[];
    for (final polyline in line.polylines) {
      if (polyline.isEmpty) {
        continue;
      }
      endpoints.add(polyline.first);
      if (polyline.length > 1) {
        endpoints.add(polyline.last);
      }
    }
    Offset? a;
    Offset? b;
    var maxD = -1.0;
    for (var i = 0; i < endpoints.length; i += 1) {
      for (var j = i + 1; j < endpoints.length; j += 1) {
        final d = (endpoints[i] - endpoints[j]).distanceSquared;
        if (d > maxD) {
          maxD = d;
          a = endpoints[i];
          b = endpoints[j];
        }
      }
    }
    if (a != null) {
      emit(a);
    }
    if (b != null && b != a) {
      emit(b); // 순환선(양 극점 근접)은 a==b → 한 번만.
    }
  }

  // 2) 환승 라벨(그룹당 1) + 역 라벨(환승 멤버 제외).
  for (final group in map.transferGroups) {
    final text = labelTextByStationId[group.stationId];
    if (text == null || text.isEmpty) {
      continue;
    }
    final size = measureLabel(text, bold: true);
    if (basemap) {
      final entry = resolvedOwnerLabels['transfer:${group.stationId}'];
      if (entry != null) {
        ownerFixedLabels.add(
          RouteMapStaticLabel(
            id: 'transfer:${group.stationId}',
            text: text,
            rect: _ownerLabelRect(
              design.toDesign(entry.position),
              size,
              entry.anchor,
              kRouteMapDesignLabelFontPx,
            ),
            bold: true,
          ),
        );
        continue;
      }
    }
    candidates.add(
      _Candidate(
        id: 'transfer:${group.stationId}',
        text: text,
        anchor: design.toDesign(group.centroid),
        size: size,
        priority: _priorityFor(RouteMapLabelClass.transfer),
        // 캡슐이 걸치는 폭까지 띄운다: 캡슐 짧은축 절반 + 멤버 이격 절반.
        // basemap 모드는 SVG 캡슐 실측 반폭(멤버 수 기반, 장애물 rect와 동일
        // 공식)이 더 크므로 그 값으로 상향한다 — routeMapTransferObstacleRects와
        // 반폭 산정을 일치시켜 라벨이 자기 그룹 캡슐과 최소 gap에서 충돌하지
        // 않게 한다. (이 경로는 오너 라벨 미매치 폴백 — #2068 6차.)
        anchorPadding:
            (basemap
                ? _basemapCapsuleHalfWidthFor(group.memberPositions.length)
                : kRouteMapDesignBadgeRadiusPx) +
            _memberSpread(group.memberPositions) * design.designScale / 2,
        bold: true,
      ),
    );
  }
  for (final station in map.stations) {
    if (station.labelClass == RouteMapLabelClass.transfer) {
      continue;
    }
    final text = labelTextByStationId[station.stationId];
    if (text == null || text.isEmpty) {
      continue;
    }
    final bold = terminusIds.contains(station.stationId);
    final size = measureLabel(text, bold: bold);
    if (basemap) {
      final entry =
          resolvedOwnerLabels['${station.stationId}:${station.lineId}'];
      if (entry != null) {
        ownerFixedLabels.add(
          RouteMapStaticLabel(
            id: '${station.stationId}:${station.lineId}',
            text: text,
            rect: _ownerLabelRect(
              design.toDesign(entry.position),
              size,
              entry.anchor,
              kRouteMapDesignLabelFontPx,
            ),
            bold: bold,
          ),
        );
        continue;
      }
    }
    candidates.add(
      _Candidate(
        id: '${station.stationId}:${station.lineId}',
        text: text,
        anchor: design.toDesign(station.position),
        size: size,
        priority: _priorityFor(station.labelClass),
        // basemap 모드는 자기 노드 심벌(장애물로 시드됨)이 실측 반경만큼 크므로
        // anchorPadding 하한을 그 반경으로 올려 자기 라벨이 자기 노드와 최소
        // gap에서 충돌하지 않게 한다. 기본 모드는 기존 3.0 유지. (이 경로는
        // 오너 라벨 미매치 폴백 — #2068 6차.)
        anchorPadding: basemap
            ? math.max(
                kRouteMapDesignStationRadiusPx,
                kRouteMapBasemapStationNodeRadiusPx,
              )
            : kRouteMapDesignStationRadiusPx,
        bold: bold,
      ),
    );
  }

  // 3) greedy 배치: 우선순위→id 정렬, 지도 중심 기준 outward 8방향 × gap 2단.
  //    전부 충돌이면 최소 겹침 면적 위치에 강제 배치(숨김 금지).
  candidates.sort((a, b) {
    final byPriority = a.priority.compareTo(b.priority);
    return byPriority != 0 ? byPriority : a.id.compareTo(b.id);
  });
  final mapCenter = _designBoundsCenter(map, design);
  // basemap 모드는 실측 선 반폭으로 선을 마킹해 라벨이 노선 밴드 위에 올라앉지
  // 않게 한다(#2068 실기기 반려). 기본 모드는 중심선만(halfWidth 0) 유지.
  // corridor(다중 노선 공유 구간)는 painter와 같은 routeMapParallelLineOffsets로
  // 정점을 오프셋한 뒤 마킹해, 화면에 나란히 펼쳐 그려지는 실제 폭(중심선 ±
  // (n-1) 라인폭)이 밴드에 반영되게 한다(basemap 한정 — 기본 모드는 오프셋 없이
  // 중심선 그대로).
  final lineGrid = _RouteMapLineGrid.build(
    map,
    design,
    halfWidth: basemap ? kRouteMapBasemapLineHalfWidthPx : 0,
    lineOffsets: basemap ? routeMapParallelLineOffsets(map.lines) : null,
  );
  // 환승 캡슐은 라벨보다 먼저 자리를 선점한 장애물이다 — 라벨이 캡슐을 덮지
  // 않도록 시드한다(출력에는 포함되지 않음). basemap·기본 모드 공통 — 3~4차
  // 장애물 모델은 뱃지 배치·폴백 검색 경로에 그대로 유효하다(#2068 6차에서도
  // 제거하지 않는다).
  final transferObstacles = routeMapTransferObstacleRects(
    map,
    design,
    basemap: basemap,
  );
  // basemap 모드: 일반(비환승) 역 노드 심벌도 장애물로 시드한다 — 이웃 라벨이
  // 남의 노드 원을 덮던 실기기 반려(#2068)를 막는다. 각 노드 design 좌표 중심에
  // 실측 노드 반경 정사각 rect를 놓는다(환승 멤버는 캡슐 장애물이 이미 덮는다).
  final nodeObstacles = <Rect>[
    if (basemap)
      for (final station in map.stations)
        if (station.labelClass != RouteMapLabelClass.transfer)
          Rect.fromCenter(
            center: design.toDesign(station.position),
            width: kRouteMapBasemapStationNodeRadiusPx * 2,
            height: kRouteMapBasemapStationNodeRadiusPx * 2,
          ),
  ];
  // basemap 모드: 오너 고정 라벨도 뱃지·폴백 검색보다 먼저 자리를 선점한
  // 장애물이다(#2068 6차 지시 2) — 뱃지가 오너 라벨을 덮지 않게 한다.
  final placedRects = <Rect>[
    ...transferObstacles,
    ...nodeObstacles,
    for (final label in ownerFixedLabels) label.rect,
  ];
  final labels = <RouteMapStaticLabel>[...ownerFixedLabels];
  final badges = <RouteMapStaticBadge>[];
  var unresolved = 0;
  for (final candidate in candidates) {
    final order = routeMapMapOutwardAnchorOrder(candidate.anchor, mapCenter);
    // 라벨-라벨 겹침 0(하드 계약)을 먼저 만족한 뒤, 그중 선 겹침이 최소인 위치를
    // 고른다 — 라벨이 선을 안 덮도록(사실상 선에 수직인 바깥쪽으로 밀려난다).
    Rect? perfect; // 라벨 0 & 선 0.
    Rect? bestClear; // 라벨 0, 선 최소.
    var bestClearLine = double.infinity;
    Rect? bestFallback; // 라벨 겹침 최소(전부 충돌 시).
    var bestFallbackLabel = double.infinity;
    // basemap 모드는 gap 사다리 시작값을 kRouteMapBasemapLabelGapPx(6.0)로
    // 상향한다 — 기하상 여유가 sliver 수준(예: 종로3가 3.8px)이면 실기기에서
    // 라벨-캡슐 접촉으로 보이던 문제 대응(2026-07-16). 기본 모드는
    // kRouteMapDesignLabelGapPx(4.0) 그대로 — 게이트 baseline 불변.
    final baseGap = basemap
        ? kRouteMapBasemapLabelGapPx
        : kRouteMapDesignLabelGapPx;
    for (final gap in [
      baseGap,
      baseGap + 6,
      baseGap + 12,
      baseGap + 18,
      baseGap + 24,
      baseGap + 30,
      baseGap + 36,
      // basemap 모드는 넓은 라벨이 밀집 교차부에서 선 밴드를 못 피하는 경우가
      // 있어 더 먼 gap 단을 추가로 시도한다(선에서 더 멀리 밀어낸다). 기본
      // 모드는 기존 사다리를 유지해 게이트 baseline을 흔들지 않는다(#2068).
      if (basemap) ...[baseGap + 44, baseGap + 52, baseGap + 60],
    ]) {
      for (final anchor in order) {
        final rect = routeMapLabelRect(
          candidate.anchor,
          candidate.size,
          anchor,
          gap + candidate.anchorPadding,
        );
        var labelOverlap = 0.0;
        for (final other in placedRects) {
          final overlap = rect.intersect(other);
          if (overlap.width > 0 && overlap.height > 0) {
            labelOverlap += overlap.width * overlap.height;
          }
        }
        if (labelOverlap == 0) {
          final lineOverlap = lineGrid.overlapArea(rect);
          if (lineOverlap == 0) {
            perfect = rect;
            break;
          }
          if (lineOverlap < bestClearLine) {
            bestClearLine = lineOverlap;
            bestClear = rect;
          }
        }
        if (labelOverlap < bestFallbackLabel) {
          bestFallbackLabel = labelOverlap;
          bestFallback = rect;
        }
      }
      if (perfect != null) {
        break;
      }
    }
    final rect = perfect ?? bestClear ?? bestFallback!;
    if (perfect == null && bestClear == null) {
      unresolved += 1; // 라벨-라벨 겹침을 못 피한 경우만 집계.
    }
    placedRects.add(rect);
    if (candidate.badgeLineId != null) {
      badges.add(
        RouteMapStaticBadge(
          lineId: candidate.badgeLineId!,
          label: candidate.text,
          rect: rect,
        ),
      );
    } else {
      labels.add(
        RouteMapStaticLabel(
          id: candidate.id,
          text: candidate.text,
          rect: rect,
          bold: candidate.bold,
        ),
      );
    }
  }
  // 오너 고정 라벨은 검색으로 회피하지 않으므로(오너 배치를 그대로 신뢰),
  // 다른 장애물(캡슐·노드) 또는 서로와 겹치면 "검색으로 못 피한 겹침"과
  // 동치로 unresolved에 더한다 — 실측 감사용(#2068 6차, 게이트가 하드
  // 실패시키지 않고 실측치로 보고).
  if (ownerFixedLabels.isNotEmpty) {
    final staticObstacles = <Rect>[...transferObstacles, ...nodeObstacles];
    for (var i = 0; i < ownerFixedLabels.length; i += 1) {
      final rect = ownerFixedLabels[i].rect;
      var overlapped = staticObstacles.any((o) => rect.overlaps(o));
      if (!overlapped) {
        for (var j = 0; j < ownerFixedLabels.length; j += 1) {
          if (i == j) continue;
          if (rect.overlaps(ownerFixedLabels[j].rect)) {
            overlapped = true;
            break;
          }
        }
      }
      if (overlapped) {
        unresolved += 1;
      }
    }
  }
  return RouteMapStaticLabelLayout(
    labels: labels,
    badges: badges,
    unresolvedOverlapCount: unresolved,
  );
}

/// 세그먼트 a→b가 rect를 관통하나 — 끝점 내부 or 4변 교차(정확 판정).
bool _segmentHitsRect(Offset a, Offset b, Rect r) {
  if (r.contains(a) || r.contains(b)) return true;
  bool segCross(Offset p1, Offset p2, Offset p3, Offset p4) {
    double cross(Offset o, Offset x, Offset y) =>
        (x.dx - o.dx) * (y.dy - o.dy) - (x.dy - o.dy) * (y.dx - o.dx);
    final d1 = cross(p3, p4, p1), d2 = cross(p3, p4, p2);
    final d3 = cross(p1, p2, p3), d4 = cross(p1, p2, p4);
    return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0));
  }

  final tl = r.topLeft, tr = r.topRight, br = r.bottomRight, bl = r.bottomLeft;
  return segCross(a, b, tl, tr) ||
      segCross(a, b, tr, br) ||
      segCross(a, b, br, bl) ||
      segCross(a, b, bl, tl);
}

/// 라벨 rect를 노선 track이 관통하는 라벨 수(#1789 실기기 클러터 게이트) — 선을
/// 덮는 라벨은 게이트에 없던 실기기 겹침의 주원인이다.
int routeMapLabelLineOverlapCount(
  RouteMapStaticLabelLayout layout,
  StructuredRouteMap map,
  RouteMapDesignSpace design,
) {
  final segs = <(Offset, Offset)>[];
  for (final line in map.lines) {
    for (final poly in line.polylines) {
      for (var i = 1; i < poly.length; i += 1) {
        segs.add((design.toDesign(poly[i - 1]), design.toDesign(poly[i])));
      }
    }
  }
  var count = 0;
  for (final label in layout.labels) {
    for (final s in segs) {
      if (_segmentHitsRect(s.$1, s.$2, label.rect)) {
        count += 1;
        break;
      }
    }
  }
  return count;
}

/// 뱃지가 노선 track / 역명 라벨을 덮는 수(#1789).
({int line, int label}) routeMapBadgeOverlapCounts(
  RouteMapStaticLabelLayout layout,
  StructuredRouteMap map,
  RouteMapDesignSpace design,
) {
  final segs = <(Offset, Offset)>[];
  for (final line in map.lines) {
    for (final poly in line.polylines) {
      for (var i = 1; i < poly.length; i += 1) {
        segs.add((design.toDesign(poly[i - 1]), design.toDesign(poly[i])));
      }
    }
  }
  var line = 0, lbl = 0;
  for (final b in layout.badges) {
    if (segs.any((s) => _segmentHitsRect(s.$1, s.$2, b.rect))) line += 1;
    if (layout.labels.any((l) => l.rect.overlaps(b.rect))) lbl += 1;
  }
  return (line: line, label: lbl);
}

double _memberSpread(List<Offset> positions) {
  var maxDistance = 0.0;
  for (var i = 0; i < positions.length; i += 1) {
    for (var j = i + 1; j < positions.length; j += 1) {
      maxDistance = math.max(
        maxDistance,
        (positions[i] - positions[j]).distance,
      );
    }
  }
  return maxDistance;
}

Offset _designBoundsCenter(StructuredRouteMap map, RouteMapDesignSpace design) {
  double? minX, minY, maxX, maxY;
  void visit(Offset p) {
    minX = math.min(minX ?? p.dx, p.dx);
    maxX = math.max(maxX ?? p.dx, p.dx);
    minY = math.min(minY ?? p.dy, p.dy);
    maxY = math.max(maxY ?? p.dy, p.dy);
  }

  for (final line in map.lines) {
    for (final polyline in line.polylines) {
      polyline.forEach(visit);
    }
  }
  for (final station in map.stations) {
    visit(station.position);
  }
  if (minX == null) {
    return Offset.zero;
  }
  return design.toDesign(Offset((minX! + maxX!) / 2, (minY! + maxY!) / 2));
}

/// 선을 장애물 셀로 마킹한 그리드 — 라벨이 선을 덮는지 판정한다(#1789 라벨-선 회피).
/// design space에서 각 선분을 반셀 간격으로 샘플해 점유 셀을 Set에 담고, 라벨 rect가
/// 덮는 점유 셀 면적을 스코어로 돌려준다. 로드 시 1회라 비용은 무방하다.
class _RouteMapLineGrid {
  _RouteMapLineGrid._(this._occupied, this._cell);

  final Set<int> _occupied;
  final double _cell;

  /// [halfWidth]>0이면(basemap 모드) 중심선만이 아니라 실측 선 반폭 원판을
  /// 샘플마다 마킹해 실제 선 폭을 장애물로 덮는다(#2068 — 라벨이 선 밴드 위에
  /// 올라앉지 않게). 폴리라인 **내부 정점**에는 반폭×2 원판을 추가 마킹해 SVG
  /// 라운드 코너 벌지를 보수적으로 덮는다. [halfWidth]==0(기본 모드)이면 기존
  /// 동작(중심선 단일 셀)을 그대로 유지한다 — 게이트 baseline 불변.
  ///
  /// [lineOffsets]는 painter가 렌더에 쓰는 것과 같은
  /// [routeMapParallelLineOffsets] 결과(basemap 한정)다. 다중 노선이 같은
  /// 좌표를 공유하는 corridor(서해선·경의중앙 일산~능곡 등)는 화면에 나란히
  /// 펼쳐 그려지므로, 정점을 그 오프셋만큼 이동한 뒤 마킹해야 corridor의 실제
  /// 폭(중심선 ± (n-1) 라인폭)이 밴드에 반영된다. null이면(기본 모드) 오프셋
  /// 없이 원좌표를 그대로 마킹한다.
  static _RouteMapLineGrid build(
    StructuredRouteMap map,
    RouteMapDesignSpace design, {
    double cell = kRouteMapDesignLineWidthPx,
    double halfWidth = 0,
    Map<String, List<List<Offset>>>? lineOffsets,
  }) {
    final occupied = <int>{};
    void markCell(Offset p) {
      occupied.add(_key((p.dx / cell).floor(), (p.dy / cell).floor()));
    }

    void markDisk(Offset center, double radius) {
      final x0 = ((center.dx - radius) / cell).floor();
      final x1 = ((center.dx + radius) / cell).ceil();
      final y0 = ((center.dy - radius) / cell).floor();
      final y1 = ((center.dy + radius) / cell).ceil();
      final r2 = radius * radius;
      for (var gy = y0; gy <= y1; gy += 1) {
        for (var gx = x0; gx <= x1; gx += 1) {
          final cx = (gx + 0.5) * cell;
          final cy = (gy + 0.5) * cell;
          final ddx = cx - center.dx;
          final ddy = cy - center.dy;
          if (ddx * ddx + ddy * ddy <= r2) {
            occupied.add(_key(gx, gy));
          }
        }
      }
    }

    void mark(Offset a, Offset b) {
      final steps = ((b - a).distance / (cell / 2)).ceil();
      for (var i = 0; i <= steps; i += 1) {
        final t = steps == 0 ? 0.0 : i / steps;
        final p = Offset.lerp(a, b, t)!;
        if (halfWidth > 0) {
          markDisk(p, halfWidth);
        } else {
          markCell(p);
        }
      }
    }

    for (final line in map.lines) {
      final offsetsByPolyline = lineOffsets?[line.lineId];
      for (var p = 0; p < line.polylines.length; p += 1) {
        final poly = line.polylines[p];
        final vertexOffsets =
            offsetsByPolyline != null && p < offsetsByPolyline.length
            ? offsetsByPolyline[p]
            : null;
        // painter(recordRouteMapPicture)와 같은 식: design 좌표 + 단위 법선 ×
        // rank × kRouteMapDesignLineWidthPx. vertexOffsets가 없으면(기본 모드)
        // design.toDesign 그대로.
        Offset vertexAt(int i) {
          var point = design.toDesign(poly[i]);
          if (vertexOffsets != null && i < vertexOffsets.length) {
            point += vertexOffsets[i] * kRouteMapDesignLineWidthPx;
          }
          return point;
        }

        for (var i = 1; i < poly.length; i += 1) {
          mark(vertexAt(i - 1), vertexAt(i));
        }
        // 내부 정점(코너)에 여유 원판 — SVG 라운드 코너 arc가 직선 폴리라인
        // 바깥으로 부푸는 벌지를 보수적으로 덮는다(basemap 전용).
        if (halfWidth > 0) {
          for (var i = 1; i < poly.length - 1; i += 1) {
            markDisk(vertexAt(i), halfWidth * 2);
          }
        }
      }
    }
    return _RouteMapLineGrid._(occupied, cell);
  }

  // 20비트씩 pack (음수는 하위 20비트 마스크 — mark/query 일관 사용이라 정합).
  static int _key(int x, int y) => (x & 0xFFFFF) | ((y & 0xFFFFF) << 20);

  /// [rect]가 덮는 선-점유 셀의 면적(design px²). 없으면 0.
  double overlapArea(Rect rect) {
    final x0 = (rect.left / _cell).floor();
    final x1 = (rect.right / _cell).ceil();
    final y0 = (rect.top / _cell).floor();
    final y1 = (rect.bottom / _cell).ceil();
    var count = 0;
    for (var y = y0; y < y1; y += 1) {
      for (var x = x0; x < x1; x += 1) {
        if (_occupied.contains(_key(x, y))) {
          count += 1;
        }
      }
    }
    return count * _cell * _cell;
  }
}
