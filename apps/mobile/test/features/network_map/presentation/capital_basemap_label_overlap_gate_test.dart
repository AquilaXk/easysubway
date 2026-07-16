import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:easysubway_mobile/features/network_map/domain/route_map_design_space.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_owner_labels.dart';
import 'package:easysubway_mobile/features/network_map/domain/structured_route_map.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_label_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/capital_route_map_fixture.dart';

// #2068 실기기 반려 10차(최종): basemap 라벨을 오너 SVG font-size로 그리되
// 앱 기본(13 design px) 이하로 클램프한다. 9차는 오너 크기를 그대로 써
// 비수도권(부산·대구·대전, 오너 폰트 <13)의 pairs를 0으로 만들었지만, 수도권
// (오너 ordinary 16.48·transfer 17.85, 13보다 큼)에서 인접 라벨 겹침이
// 15→32쌍(REAL측정)으로 늘었다 — SVG는 Pretendard, 앱은 fontFamily 미지정
// (시스템 기본) 폰트라 동일 point size에서도 한글 자폭이 달라 SVG에서 안
// 겹치던 배치가 앱 렌더에서 겹친 것으로 추정(Pretendard 번들은 후속 과제,
// 이번엔 폰트 자산을 추가하지 않는다). 10차는
// `min(13, entry.fontSizePx×designScale)`로 클램프해(_clampOwnerFontSizeDesign,
// route_map_label_layout.dart) 수도권을 6~8차에서 이미 검증된 13px 렌더로
// 복귀시킨다 — 작은 글자는 오너가 비워둔 영역의 부분집합이라 겹침을 만들지
// 않는다(수학적으로 안전한 방향). 비수도권은 오너 폰트가 이미 13 미만이라
// 클램프가 발동하지 않아 9차 효과(pairs 0)를 그대로 유지한다
// (regional_basemap_label_overlap_gate_test.dart로 확인).
//
// 판정 근거(수도권 실데이터 fixture 실측, 2026-07-16):
// - 매치율 651/654(99.5%, 중점(·)↔마침표(.) 정규화 포함) — 10차는 매칭
//   로직을 건드리지 않았다.
// - 라벨-라벨 겹침 쌍: 9차 실측정 32/근사 44 → 10차 클램프 후 **실측정 15/
//   근사 17**로 복귀 — 7차(6~8차 13px 렌더) baseline과 정확히 일치한다(클램프
//   가 수도권 전체를 13px 렌더로 되돌렸으므로 당연한 결과).
// - 라벨-노드/캡슐/밴드는 하드 게이트로 두지 않는다(오너 SVG 실제 렌더가
//   아니라 구조화 오버레이의 근사 장애물 모델과 비교하는 값이라 노이즈가
//   섞인다). 실측치만 기록해 회귀를 감시한다.
//
// 이름 매칭은 중점(·)↔마침표(.) 정규화만 적용한다(#2068 7차 지시 2 — 다른
// 정규화는 과매칭 위험이라 하지 않는다, route_map_label_layout.dart의
// _normalizeOwnerLabelNameKey와 동일 규칙을 이 파일 매치율 계산에도 미러링).
String _normalizeNameForMatchRate(String name) => name.replaceAll('·', '.');
// #2068 9차: fontSize는 라벨마다 다르다(오너 매치=오너 크기, 폴백/뱃지=권역
// 중앙값) — 고정 상수 대신 솔버가 넘긴 값을 그대로 실측에 쓴다. 10차부터
// 수도권은 클램프로 사실상 13(솔버가 넘기는 값)이 된다.
Size _measureLabel(
  String text, {
  required bool bold,
  required double fontSize,
}) => Size(text.length * fontSize, fontSize + 4);
Size _measureBadge(String text, {required double fontSize}) =>
    Size(text.length * fontSize + 12, fontSize + 7);

// 실측 달성값 고정(악화 금지, 이 파일의 근사 측정 기준 — 실측정 TextPainter
// 기준은 15). 10차 클램프로 7차 baseline과 동일하게 복귀했다.
const int kCapitalBasemapLabelLabelPairBaseline = 17;

bool _rectOverlaps(Rect a, Rect b) {
  final o = a.intersect(b);
  return o.width > 0 && o.height > 0;
}

void main() {
  test('수도권 basemap: 오너 라벨 매치율 ≥98% · 전 라벨 표시 · 라벨-라벨 겹침 ≤17쌍 (#2068 10차)', () {
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
