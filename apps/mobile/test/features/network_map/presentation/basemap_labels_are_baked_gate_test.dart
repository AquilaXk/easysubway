import 'package:easysubway_mobile/features/network_map/domain/route_map_design_space.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_label_layout.dart';
import 'package:easysubway_mobile/features/network_map/presentation/structured_route_map_painter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/capital_route_map_fixture.dart';

// #2068 SVG 충실도 — 바탕층 모드에서 앱은 역명 글자를 그리지 않는다(오너 결정
// 2026-07-26, "글자도 복붙").
//
// 오너 SVG의 역명 라벨은 이제 .vec 바탕층에 그대로 구워진다
// (tools/route-map/compile-basemap-vec.mjs의 MAP_BODY_LAYER_IDS). 앱이 같은
// 글자를 다시 배치·렌더하면 이중 렌더이자 오배치의 원인이 된다 — 벡스코류
// 오배치의 근본 해소가 "앱이 아예 안 그리는 것"이다. 이 게이트는 바탕층 모드
// 그림(ui.Picture) 녹화 입력에 라벨·뱃지가 하나도 없음을 고정한다.
//
// 대체된 게이트(#2068 2026-07-26):
//   capital_basemap_label_overlap_gate_test.dart  — 삭제
//   regional_basemap_label_overlap_gate_test.dart — 삭제
// 두 게이트는 "앱 솔버가 배치한 라벨끼리 겹치지 않는가"를 쟀는데, 바탕층 모드에서
// 솔버가 라벨을 배치하지 않으므로 측정 대상이 사라졌다. 화면 라벨의 정합은
// tools/route-map/basemap-svg-fidelity-gate.test.mjs(SVG↔산출물 전수 대조)가
// 대신 지킨다. 유지되는 게이트: owner_label_match_rate_gate_test.dart
// (labels.json ↔ 카탈로그 매칭 — 탭 히트·TalkBack·초기 카메라 가독 배율용).
void main() {
  test('바탕층 모드(drawStationSymbols=false)는 라벨·뱃지를 하나도 그리지 않는다', () {
    final fixture = loadCapitalRouteMapFixture();
    final map = fixture.map;
    final design = routeMapDesignSpaceFor(map);

    Size measureLabel(
      String text, {
      required bool bold,
      required double fontSize,
    }) => measureRouteMapLabel(
      text,
      bold: bold,
      fontSize: fontSize,
      basemap: true,
    );
    Size measureBadge(String text, {required double fontSize}) =>
        measureRouteMapBadge(text, fontSize: fontSize, basemap: true);

    // 솔버 자체는 살아 있다(구조화 노선도 모드 전용) — 바탕층 모드에서만 쓰지
    // 않는다. 여기서는 "솔버를 돌리면 라벨이 나온다"를 먼저 확인해, 아래
    // 바탕층 그림이 비어 있는 것이 입력 부재가 아니라 의도된 비활성임을 보인다.
    final solved = solveRouteMapLabelLayout(
      map: map,
      design: design,
      labelTextByStationId: fixture.labelTextByStationId,
      badgeLabelByLineId: fixture.badgeLabelByLineId,
      measureLabel: measureLabel,
      measureBadge: measureBadge,
    );
    expect(solved.labels, isNotEmpty);

    // 바탕층 모드 렌더러가 소비하는 레이아웃은 비어 있어야 한다.
    expect(kRouteMapBasemapEmptyLabelLayout.labels, isEmpty);
    expect(kRouteMapBasemapEmptyLabelLayout.badges, isEmpty);
    expect(kRouteMapBasemapEmptyLabelLayout.unresolvedOverlapCount, 0);
  });
}
