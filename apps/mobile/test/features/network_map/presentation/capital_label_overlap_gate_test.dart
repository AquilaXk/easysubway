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

// [1단계 baseline — 재간격(respace) datapack 반영 커밋(Task 7)에서 0으로 강등.
//  스펙 R3의 "수도권 잔여 겹침 0" 계약의 실데이터 판정이 이 테스트다.]
const int kCapitalUnresolvedBaseline = 64; // 2026-07-06 실측(재간격 전)

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
          '재간격(Task 7) 후 0이 되어야 한다',
    );
  });
}
