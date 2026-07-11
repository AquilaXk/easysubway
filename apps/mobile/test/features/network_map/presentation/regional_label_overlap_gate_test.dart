import 'dart:ui';

import 'package:easysubway_mobile/features/network_map/domain/route_map_design_space.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_label_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/capital_route_map_fixture.dart';

// 비수도권 4권역(부산·대구·대전·광주) 라벨 겹침 기계 게이트 (#1952 작업 1).
// 수도권 게이트(capital_label_overlap_gate_test.dart)와 동일 측정 방식·동일 보수
// 근사(한글 전각 폭 ≈ 폰트 px/자)를 재사용해 "게이트=실기기 체감" 정합을 권역
// 확장한다. 팩(assets/datapacks/capital.sqlite.gz)의 route_map_positions에는
// 수도권 외 4권역이 이미 수록돼 있어(부산권 158·대구권 101·대전권 22·광주권 20
// positions) 동일 fixture 로더를 region 인자만 바꿔 재사용한다.
//
// 2026-07-11 #1952 신 정본(오너 8선형 도식) 실측 baseline: 4권역 전부 라벨-라벨,
// 라벨-선, 뱃지-선, 뱃지-라벨, unresolved 모두 0. 저사양 권역이라 도심 밀집이
// 수도권보다 낮아 겹침이 원천 발생하지 않는다. baseline은 하드 0 — 후속 버전
// 교체에서 겹침이 생기면 즉시 실패해 회귀를 잡는다.
Size _measureLabel(String text, {required bool bold}) => Size(
  text.length * kRouteMapDesignLabelFontPx,
  kRouteMapDesignLabelFontPx + 4,
);
Size _measureBadge(String text) => Size(
  text.length * kRouteMapDesignBadgeFontPx + 12,
  kRouteMapDesignBadgeFontPx + 7,
);

void main() {
  // 저장 region 명은 route_map_positions.region 값(권역 접미사 포함)과 일치해야
  // 한다. 프로덕션 _networkMapRegions() SELECT DISTINCT region 결과와 동일.
  const regions = <String>['부산권', '대구권', '대전권', '광주권'];

  for (final region in regions) {
    test('$region 실데이터: 전 라벨 표시 + 겹침 0 게이트', () {
      final fixture = loadCapitalRouteMapFixture(region: region);
      final design = routeMapDesignSpaceFor(fixture.map);
      final layout = solveRouteMapLabelLayout(
        map: fixture.map,
        design: design,
        labelTextByStationId: fixture.labelTextByStationId,
        badgeLabelByLineId: fixture.badgeLabelByLineId,
        measureLabel: _measureLabel,
        measureBadge: _measureBadge,
      );

      // 숨김 금지: 권역 전 역이 라벨을 가진다(환승은 그룹당 1로 접힘).
      expect(
        layout.labels.length,
        greaterThan(0),
        reason: '$region 라벨이 하나도 없다 — fixture 로드/region 명 확인',
      );

      // 라벨-라벨 겹침 0.
      final labelRects = layout.labels.map((l) => l.rect).toList();
      var overlapPairs = 0;
      for (var i = 0; i < labelRects.length; i += 1) {
        for (var j = i + 1; j < labelRects.length; j += 1) {
          if (labelRects[i].overlaps(labelRects[j])) overlapPairs += 1;
        }
      }
      expect(overlapPairs, 0, reason: '$region 라벨 겹침 쌍 $overlapPairs');

      // unresolved(최소 겹침 fallback으로 강제 배치된 겹침) 0.
      expect(
        layout.unresolvedOverlapCount,
        0,
        reason: '$region unresolved=${layout.unresolvedOverlapCount}',
      );

      // 라벨-선·뱃지 겹침(실기기 클러터) 0.
      final labelLine = routeMapLabelLineOverlapCount(layout, fixture.map, design);
      final badge = routeMapBadgeOverlapCounts(layout, fixture.map, design);
      expect(labelLine, 0, reason: '$region 라벨-선 겹침 $labelLine');
      expect(badge.line, 0, reason: '$region 뱃지-선 겹침 ${badge.line}');
      expect(badge.label, 0, reason: '$region 뱃지-라벨 겹침 ${badge.label}');
    });
  }
}
