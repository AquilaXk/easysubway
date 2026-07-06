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
  });
}
