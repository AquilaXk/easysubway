import 'dart:ui';

import 'package:easysubway_mobile/features/network_map/domain/route_map_design_space.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_label_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/capital_route_map_fixture.dart';

// 결정적 보수 측정: 한글 전각 폭 ≈ 폰트 px/자. 실기기 TextPainter 실측(비전각
// 혼재)보다 넓게 잡는다 — 이 근사로 겹침이 없으면 실기기에서도 없다.
Size _measureLabel(String text, {required bool bold}) => Size(
  text.length * kRouteMapDesignLabelFontPx,
  kRouteMapDesignLabelFontPx + 4,
);
Size _measureBadge(String text) => Size(
  text.length * kRouteMapDesignBadgeFontPx + 12,
  kRouteMapDesignBadgeFontPx + 7,
);

// 재간격 + 부역명 축약 + gap 확장 반영(2026-07-06 실측): 64→2. 잔여 1쌍은
// 임진강/운천(경의중앙 최북단, 둘 다 짧은 평역명·지리적 근접)으로 라벨 배치로는
// 분리 불가한 기약 케이스 — 도심 겹침은 0이다(스펙 R3). baseline은 악화 금지.
const int kCapitalUnresolvedBaseline = 2;

// 2026-07-06 실기기 클러터 게이트 — 라벨-라벨 외 라벨-선 겹침도 측정해 "게이트=
// 실기기 체감" 정합. baseline은 현재 실측값(악화 금지).
const int kCapitalLabelLineOverlapBaseline = 17;
// 노선번호 색 원은 간선 위에 얹히는 게 서울메트로 룩의 의도라 뱃지-선 겹침은 측정
// 하지 않는다(#1789). 대신 뱃지가 역명을 가리지 않는 것(뱃지-라벨 겹침 0)이 핵심
// 제약 — 뱃지 pass가 라벨과 겹치는 후보를 생략한다.
const int kCapitalBadgeLabelOverlapBaseline = 0;

void main() {
  test('수도권 실데이터: 전 라벨 표시 + 겹침 악화 금지 게이트', () {
    final fixture = loadCapitalRouteMapFixture();
    final layout = solveRouteMapLabelLayout(
      map: fixture.map,
      design: routeMapDesignSpaceFor(fixture.map),
      labelTextByStationId: fixture.labelTextByStationId,
      badgeLabelByLineId: fixture.badgeLabelByLineId,
      measureLabel: _measureLabel,
      measureBadge: _measureBadge,
    );
    // 숨김 금지: 환승은 그룹당 1, 나머지는 역·노선당 1 — 계약상 전 역이 라벨을 가진다.
    expect(layout.labels.length, greaterThan(600));
    expect(
      layout.unresolvedOverlapCount,
      lessThanOrEqualTo(kCapitalUnresolvedBaseline),
      reason:
          '실측 unresolved=${layout.unresolvedOverlapCount} — baseline 갱신 금지, '
          '재간격+축약+gap 확장으로 2 이하를 유지해야 한다',
    );
    // 라벨-라벨 겹침 쌍은 기약 1쌍(임진강/운천) 이하 — 도심 포함 그 외 전부 0.
    final labelRects = layout.labels.map((l) => l.rect).toList();
    var overlapPairs = 0;
    for (var i = 0; i < labelRects.length; i += 1) {
      for (var j = i + 1; j < labelRects.length; j += 1) {
        if (labelRects[i].overlaps(labelRects[j])) overlapPairs += 1;
      }
    }
    expect(overlapPairs, lessThanOrEqualTo(1), reason: '라벨 겹침 쌍 $overlapPairs');

    // 라벨-선·뱃지 겹침(실기기 클러터) 악화 금지.
    final design = routeMapDesignSpaceFor(fixture.map);
    final labelLine = routeMapLabelLineOverlapCount(
      layout,
      fixture.map,
      design,
    );
    final badge = routeMapBadgeOverlapCounts(layout, fixture.map, design);
    expect(
      labelLine,
      lessThanOrEqualTo(kCapitalLabelLineOverlapBaseline),
      reason:
          '라벨-선 겹침 $labelLine — baseline $kCapitalLabelLineOverlapBaseline 악화 금지',
    );
    // 노선번호 원이 역명을 가리지 않는다(핵심 제약) — 간선 위 배치는 의도.
    expect(
      badge.label,
      lessThanOrEqualTo(kCapitalBadgeLabelOverlapBaseline),
      reason: '뱃지-라벨 겹침 ${badge.label} — 역명 판독 우선(0 유지, 겹치는 후보는 생략)',
    );
  });
}
