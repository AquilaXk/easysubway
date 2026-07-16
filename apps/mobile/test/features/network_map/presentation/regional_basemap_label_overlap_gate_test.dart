import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:easysubway_mobile/features/network_map/domain/route_map_design_space.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_owner_labels.dart';
import 'package:easysubway_mobile/features/network_map/domain/structured_route_map.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_label_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/capital_route_map_fixture.dart';

// #2068 실기기 반려 10차(최종): 비수도권(부산·대구·대전) basemap 라벨 게이트.
// capital_basemap_label_overlap_gate_test.dart와 같은 골격을 3권역에 확장한다.
//
// 9차: 라벨을 오너 SVG font-size 그대로 렌더(entry.fontSizePx × designScale
// — 부산 ordinary ≈4.87·대구 ≈7.23·대전 ≈5.7~6.2 design px)하고 8차의 앵커
// 오프셋 확대(fontRatio)를 제거했다 — pairs가 3권역 전부 0으로 떨어졌다(부산
// 24→0·대구 6→0·대전 1→0).
//
// 10차: 수도권(오너 폰트가 앱 기본 13보다 큼)의 회귀(pairs 15→32)를 잡기
// 위해 오너 font-size를 `min(13, 오너값)`으로 클램프했다
// (_clampOwnerFontSizeDesign, route_map_label_layout.dart). 비수도권은 오너
// 폰트가 이미 13 미만이라 클램프가 발동하지 않는다 — **9차 결과가 그대로
// 유지된다**(클램프 전/후 동일값, 아래 baseline 불변):
//   부산: pairs **0**(불변), unresolved 56(REAL)/70(근사) 불변,
//         labelLine 20(REAL)/41(근사) 불변, labelBand 70(REAL)/87(근사) 불변
//   대구: pairs **0**(불변), unresolved 17 불변,
//         labelLine 5(REAL)/11(근사) 불변, labelBand 17(REAL)/18(근사) 불변
//   대전: pairs **0**(불변), unresolved 1 불변,
//         labelLine 0(REAL)/1(근사) 불변, labelBand 1(REAL)/2(근사) 불변
// labelLine·labelBand는 완전히 0은 아니다 — 구조화 오버레이의 근사 장애물
// 모델(실제 SVG 렌더가 아님, capital 게이트 주석과 동일 사유)과 비교하는
// 값이라 노이즈가 남는다.
// #2068 9~10차: fontSize는 라벨마다 다르다(오너 매치=클램프된 오너 크기,
// 폴백/뱃지=권역 중앙값) — 고정 상수 대신 솔버가 넘긴 값을 그대로 실측에 쓴다.
Size _measureLabel(
  String text, {
  required bool bold,
  required double fontSize,
}) => Size(text.length * fontSize, fontSize + 4);
Size _measureBadge(String text, {required double fontSize}) =>
    Size(text.length * fontSize + 12, fontSize + 7);

bool _rectOverlaps(Rect a, Rect b) {
  final o = a.intersect(b);
  return o.width > 0 && o.height > 0;
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

bool _bandHit(Rect r, StructuredRouteMap map, RouteMapDesignSpace d) {
  for (final line in map.lines) {
    for (final poly in line.polylines) {
      for (var i = 1; i < poly.length; i += 1) {
        if (_segRectDist(d.toDesign(poly[i - 1]), d.toDesign(poly[i]), r) <=
            kRouteMapBasemapLineHalfWidthPx) {
          return true;
        }
      }
    }
  }
  return false;
}

void main() {
  final sidecarJson = File(
    'assets/datapacks/metro_map_pack/basemap/labels.json',
  ).readAsStringSync();

  // (dbRegion, sidecarId, 매치율 하한, 라벨-라벨 겹침 쌍 baseline).
  const cases = <(String, String, double, int)>[
    ('부산권', 'busan', 0.90, 0),
    ('대구권', 'daegu', 0.90, 0),
    ('대전권', 'daejeon', 0.70, 0),
  ];

  for (final (dbRegion, sidecarId, matchRateFloor, pairBaseline) in cases) {
    test(
      '$dbRegion basemap: 오너 라벨 매치율 · 전 라벨 표시 · 라벨-라벨 겹침 ≤$pairBaseline쌍 (#2068 10차)',
      () {
        final fixture = loadCapitalRouteMapFixture(region: dbRegion);
        final design = routeMapDesignSpaceFor(fixture.map);
        final ownerLabels = parseRouteMapOwnerLabelsForRegion(
          sidecarJson,
          sidecarId,
        );

        final candidateNames = <String>{
          for (final group in fixture.map.transferGroups)
            ?fixture.stationNameByStationId[group.stationId],
          for (final station in fixture.map.stations)
            if (station.labelClass != RouteMapLabelClass.transfer)
              ?fixture.stationNameByStationId[station.stationId],
        };
        final matchedCount = candidateNames
            .where(ownerLabels.containsKey)
            .length;
        expect(
          matchedCount / candidateNames.length,
          greaterThanOrEqualTo(matchRateFloor),
          reason:
              '$dbRegion 오너 라벨 매치율 $matchedCount/${candidateNames.length} — '
              '하한 $matchRateFloor 미만이면 sidecar·nameKo 정합이 깨진 것',
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

        // 숨김 금지: 전 역이 라벨을 가진다(미매치는 폴백 솔버 경로).
        expect(layout.labels.length, greaterThan(0));

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
          lessThanOrEqualTo(pairBaseline),
          reason: '$dbRegion 라벨-라벨 겹침 쌍 $pairs — baseline $pairBaseline 악화 금지',
        );

        // 참고 보고(하드 게이트 아님) — 구조화 오버레이 근사 장애물 모델 기준.
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
          if (_bandHit(l.rect, fixture.map, design)) labelBand += 1;
        }
        final labelLine = routeMapLabelLineOverlapCount(
          layout,
          fixture.map,
          design,
        );
        // ignore: avoid_print
        print(
          '[$dbRegion 참고] labelNode=$labelNode labelCapsule=$labelCapsule '
          'labelBand=$labelBand labelLine=$labelLine '
          'unresolved(오너 겹침 감사)=${layout.unresolvedOverlapCount}',
        );
      },
    );
  }
}
