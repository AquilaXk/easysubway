import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:easysubway_mobile/features/network_map/domain/route_map_design_space.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_owner_labels.dart';
import 'package:easysubway_mobile/features/network_map/domain/structured_route_map.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_label_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/capital_route_map_fixture.dart';

// #2068 실기기 반려 7차(최종): basemap 라벨 배치를 오너 SVG 라벨 실측 앵커
// (assets/datapacks/metro_map_pack/basemap/labels.json, tools/route-map/
// compile-basemap-vec.mjs의 extractOwnerLabels가 생성) 우선으로 전환한 뒤의
// 클러터 게이트. 3~5차의 자동 솔버는 밀집부(시청 등)에서 선을 가로지르는
// 근본 한계가 있었다 — 오너가 SVG에서 손으로 피해 그린 실제 좌표를 그대로
// 쓰면 그 한계를 구조적으로 우회한다. 실기기 재검증(도심 밀집부 전부 클린)
// 후 7차에서 동명이역 위치 게이트 + 이름 정규화를 추가했다.
//
// 판정 근거(수도권 실데이터 fixture 실측, 2026-07-16):
// - 매치율 651/654(99.5%, 중점(·)↔마침표(.) 정규화 포함) — station 원본
//   nameKo 정확 일치(정규화 후). 미매치 3건(도라산: SVG 라벨 자체 부재,
//   총신대입구(이수): SVG 괄호부기 vs DB 미부기, 하남검단산역: SVG "역" 접미
//   없음 vs DB 있음)은 표기 구조 차라 추가 정규화는 과매칭 위험(지시 2 — 하지
//   않음). 미매치는 기존 4차 자동 솔버로 폴백해 라벨을 숨기지 않는다.
// - **동명이역(신촌·양평 각 2곳) 위치 게이트 해소 확인**: 7차 전엔 두 물리역이
//   같은 sidecar 앵커를 공유해 "신촌×신촌"·"양평×양평" 겹침 쌍이 발생했다.
//   위치 게이트(kRouteMapOwnerLabelMaxAnchorDistancePx=185 design px)+최근접
//   우선 해소 후: 신촌은 2호선(거리 34.5)이 오너 앵커를 쓰고 경의중앙선(거리
//   107.2)은 폴백(자기 실제 위치 인근 배치), 양평은 수인분당선(거리 40.2)이
//   오너 앵커를 쓰고 경의중앙선(거리 1880.9 — 실제로 아예 다른 지역)은 폴백—
//   두 쌍 다 사라짐(실측정 기준 확인).
// - 라벨-라벨 겹침 쌍은 실측정(TextPainter) 기준 여전히 15쌍(근사 측정
//   기준 17쌍, 이 파일 게이트 기준) — **구성이 바뀌었다**: 동명이역 2쌍
//   해소, 대신 정규화로 새로 매치된 "4.19민주묘지"·"시청.용인대"가 인접
//   라벨(솔밭공원·명지대)과 새로 겹쳐 순증감 0. baseline 수치 자체는
//   불변이나 원인이 달라졌음을 기록한다(임의로 0으로 주장하지 않는다).
// - 라벨-노드/캡슐/밴드는 하드 게이트로 두지 않는다(오너 SVG 실제 렌더가
//   아니라 구조화 오버레이의 근사 장애물 모델과 비교하는 값이라 노이즈가
//   섞인다 — 예: 시청 2-멤버 캡슐 half-width 16.5는 실측 캡슐보다 보수적으로
//   크다). 실측치만 기록해 회귀를 감시한다.
//
// 이름 매칭은 중점(·)↔마침표(.) 정규화만 적용한다(#2068 7차 지시 2 — 다른
// 정규화는 과매칭 위험이라 하지 않는다, route_map_label_layout.dart의
// _normalizeOwnerLabelNameKey와 동일 규칙을 이 파일 매치율 계산에도 미러링).
String _normalizeNameForMatchRate(String name) => name.replaceAll('·', '.');
Size _measureLabel(String text, {required bool bold}) => Size(
  text.length * kRouteMapDesignLabelFontPx,
  kRouteMapDesignLabelFontPx + 4,
);
Size _measureBadge(String text) => Size(
  text.length * kRouteMapDesignBadgeFontPx + 12,
  kRouteMapDesignBadgeFontPx + 7,
);

// 실측 달성값 고정(악화 금지, 이 파일의 근사 측정 기준 — 실측정 TextPainter
// 기준은 15).
const int kCapitalBasemapLabelLabelPairBaseline = 17;

bool _rectOverlaps(Rect a, Rect b) {
  final o = a.intersect(b);
  return o.width > 0 && o.height > 0;
}

void main() {
  test('수도권 basemap: 오너 라벨 매치율 ≥98% · 전 라벨 표시 · 라벨-라벨 겹침 ≤17쌍 (#2068 7차)', () {
    final fixture = loadCapitalRouteMapFixture();
    final design = routeMapDesignSpaceFor(fixture.map);
    final sidecarJson = File(
      'assets/datapacks/metro_map_pack/basemap/labels.json',
    ).readAsStringSync();
    final ownerLabels = parseRouteMapOwnerLabelsForRegion(sidecarJson, 'seoul');
    final normalizedOwnerLabelNames = ownerLabels.keys
        .map(_normalizeNameForMatchRate)
        .toSet();
    // 전 후보(환승 그룹 + 비환승 역) 대비 매치율(정규화 후 — 위치 게이트·
    // 최근접 우선은 매치율이 아니라 "어느 물리역이 쓰는지"만 바꾸므로 여기
    // 매치율 계산에는 영향 없다).
    final candidateNames = <String>{
      for (final group in fixture.map.transferGroups)
        ?fixture.stationNameByStationId[group.stationId],
      for (final station in fixture.map.stations)
        if (station.labelClass != RouteMapLabelClass.transfer)
          ?fixture.stationNameByStationId[station.stationId],
    };
    final matchedCount = candidateNames
        .where(
          (name) => normalizedOwnerLabelNames.contains(
            _normalizeNameForMatchRate(name),
          ),
        )
        .length;
    expect(
      matchedCount / candidateNames.length,
      greaterThanOrEqualTo(0.98),
      reason:
          '오너 라벨 매치율 $matchedCount/${candidateNames.length} — '
          '98% 미만이면 sidecar·nameKo 정합이 깨진 것',
    );

    final layout = solveRouteMapLabelLayout(
      map: fixture.map,
      design: design,
      labelTextByStationId: fixture.labelTextByStationId,
      badgeLabelByLineId: fixture.badgeLabelByLineId,
      measureLabel: _measureLabel,
      measureBadge: _measureBadge,
      basemap: true,
      ownerLabelsByStationName: ownerLabels,
      stationNameByStationId: fixture.stationNameByStationId,
    );

    // 전 역 표시(숨김 금지 계약) — 미매치도 폴백 경로로 라벨을 낸다.
    expect(layout.labels.length, greaterThan(600));

    // 라벨-라벨 겹침 쌍 — 실측치로 고정(악화 금지). 0 미도달 원인은 파일
    // 상단 주석 참고.
    var pairs = 0;
    for (var i = 0; i < layout.labels.length; i += 1) {
      for (var j = i + 1; j < layout.labels.length; j += 1) {
        if (layout.labels[i].rect.overlaps(layout.labels[j].rect)) {
          pairs += 1;
        }
      }
    }
    expect(
      pairs,
      lessThanOrEqualTo(kCapitalBasemapLabelLabelPairBaseline),
      reason:
          '라벨-라벨 겹침 쌍 $pairs — baseline '
          '$kCapitalBasemapLabelLabelPairBaseline 악화 금지',
    );

    // 이하 참고 보고(하드 게이트 아님) — 구조화 오버레이 근사 장애물 모델
    // 기준. 회귀 감시용으로 print만 한다(assert 없음).
    final nodeRects = [
      for (final s in fixture.map.stations)
        if (s.labelClass != RouteMapLabelClass.transfer)
          Rect.fromCenter(
            center: design.toDesign(s.position),
            width: kRouteMapBasemapStationNodeRadiusPx * 2,
            height: kRouteMapBasemapStationNodeRadiusPx * 2,
          ),
    ];
    final capsules = routeMapTransferObstacleRects(
      fixture.map,
      design,
      basemap: true,
    );
    var labelNode = 0, labelCapsule = 0, labelBand = 0;
    for (final l in layout.labels) {
      if (nodeRects.any((n) => _rectOverlaps(l.rect, n))) labelNode += 1;
      if (capsules.any((c) => _rectOverlaps(l.rect, c))) labelCapsule += 1;
      if (_bandHit(
        l.rect,
        fixture.map,
        design,
        kRouteMapBasemapLineHalfWidthPx,
      )) {
        labelBand += 1;
      }
    }
    final labelLine = routeMapLabelLineOverlapCount(
      layout,
      fixture.map,
      design,
    );
    // ignore: avoid_print
    print(
      '[참고] labelNode=$labelNode labelCapsule=$labelCapsule '
      'labelBand=$labelBand labelLine=$labelLine '
      'unresolved(오너 겹침 감사)=${layout.unresolvedOverlapCount}',
    );
  });
}

bool _bandHit(
  Rect r,
  StructuredRouteMap map,
  RouteMapDesignSpace d,
  double half,
) {
  for (final line in map.lines) {
    for (final poly in line.polylines) {
      for (var i = 1; i < poly.length; i += 1) {
        if (_segRectDist(d.toDesign(poly[i - 1]), d.toDesign(poly[i]), r) <=
            half) {
          return true;
        }
      }
    }
  }
  return false;
}

double _segRectDist(Offset a, Offset b, Rect r) {
  bool seg(Offset p1, Offset p2, Offset p3, Offset p4) {
    double cross(Offset o, Offset x, Offset y) =>
        (x.dx - o.dx) * (y.dy - o.dy) - (x.dy - o.dy) * (y.dx - o.dx);
    final d1 = cross(p3, p4, p1), d2 = cross(p3, p4, p2);
    final d3 = cross(p1, p2, p3), d4 = cross(p1, p2, p4);
    return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0));
  }

  final tl = r.topLeft, tr = r.topRight, br = r.bottomRight, bl = r.bottomLeft;
  final edges = [
    [tl, tr],
    [tr, br],
    [br, bl],
    [bl, tl],
  ];
  if (r.contains(a) || r.contains(b)) return 0;
  for (final e in edges) {
    if (seg(a, b, e[0], e[1])) return 0;
  }
  double pointSeg(Offset p, Offset s, Offset t) {
    final st = t - s;
    final len2 = st.distanceSquared;
    final u = len2 == 0
        ? 0.0
        : (((p - s).dx * st.dx + (p - s).dy * st.dy) / len2).clamp(0.0, 1.0);
    return (p - (s + st * u)).distance;
  }

  var best = double.infinity;
  for (final e in edges) {
    best = math.min(best, pointSeg(a, e[0], e[1]));
    best = math.min(best, pointSeg(b, e[0], e[1]));
    best = math.min(best, pointSeg(e[0], a, b));
    best = math.min(best, pointSeg(e[1], a, b));
  }
  return best;
}
