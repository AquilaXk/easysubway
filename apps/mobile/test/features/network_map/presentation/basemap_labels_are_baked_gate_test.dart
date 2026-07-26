import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
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
// 오배치의 근본 해소가 "앱이 아예 안 그리는 것"이다.
//
// 이 게이트는 **분기가 되돌려지면 red가 되도록** 두 겹으로 못 박는다:
//   (1) 프로덕션이 실제로 쓰는 순수 함수 [routeMapPictureLabelLayout]을 양쪽
//       분기(basemap true/false)로 직접 호출해 결과를 비교한다. 삼항을 뒤집으면
//       basemap=true가 라벨을 내놓아 red.
//   (2) [debugRouteMapLabelSolverInvocationCount]로 솔버 호출 자체를 센다.
//       "빈 레이아웃"이 입력 부재(라벨 텍스트 없음)가 아니라 **의도된 비활성**
//       임을 보이기 위해 대조군(basemap=false / drawStationSymbols=true)에서는
//       솔버가 실제로 돌아 라벨이 나옴을 함께 단언한다.
// 위젯 경로([StructuredRouteMapView])까지 pump해, 순수 함수만 고치고 위젯
// 배선을 되돌리는 회귀도 잡는다.
//
// 대체된 게이트(#2068 2026-07-26):
//   capital_basemap_label_overlap_gate_test.dart  — 삭제
//   regional_basemap_label_overlap_gate_test.dart — 삭제
// 두 게이트는 "앱 솔버가 배치한 라벨끼리 겹치지 않는가"를 쟀는데, 바탕층 모드에서
// 솔버가 라벨을 배치하지 않으므로 측정 대상이 사라졌다. 화면 라벨의 정합은
// tools/route-map/basemap-svg-fidelity-gate.test.mjs(SVG↔산출물 전수 대조)가
// 대신 지킨다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixture = loadCapitalRouteMapFixture();
  final map = fixture.map;
  final design = routeMapDesignSpaceFor(map);

  Size measureLabel(
    String text, {
    required bool bold,
    required double fontSize,
  }) => measureRouteMapLabel(text, bold: bold, fontSize: fontSize);
  Size measureBadge(String text, {required double fontSize}) =>
      measureRouteMapBadge(text, fontSize: fontSize);

  RouteMapStaticLabelLayout layoutFor({required bool basemap}) =>
      routeMapPictureLabelLayout(
        basemap: basemap,
        map: map,
        design: design,
        labelTextByStationId: fixture.labelTextByStationId,
        badgeLabelByLineId: fixture.badgeLabelByLineId,
        measureLabel: measureLabel,
        measureBadge: measureBadge,
      );

  test('바탕층 분기는 솔버를 호출하지 않고 빈 레이아웃을 돌려준다', () {
    final beforeBasemap = debugRouteMapLabelSolverInvocationCount;
    final basemapLayout = layoutFor(basemap: true);
    expect(
      debugRouteMapLabelSolverInvocationCount,
      beforeBasemap,
      reason: '바탕층 모드에서 라벨 솔버가 돌았다 — 라벨 미렌더 결정이 되돌려졌다',
    );
    expect(basemapLayout.labels, isEmpty);
    expect(basemapLayout.badges, isEmpty);
    expect(basemapLayout.unresolvedOverlapCount, 0);
    expect(identical(basemapLayout, kRouteMapBasemapEmptyLabelLayout), isTrue);

    // 대조군: 구조화 노선도 모드는 같은 입력으로 솔버가 실제로 돌아 라벨이
    // 나온다 — 위 빈 레이아웃이 "입력 부재"가 아님을 보인다.
    final beforeStructured = debugRouteMapLabelSolverInvocationCount;
    final structuredLayout = layoutFor(basemap: false);
    expect(debugRouteMapLabelSolverInvocationCount, beforeStructured + 1);
    expect(structuredLayout.labels, isNotEmpty);
    expect(structuredLayout.badges, isNotEmpty);
  });

  testWidgets(
    'StructuredRouteMapView(drawStationSymbols:false)는 라벨 솔버를 돌리지 않는다',
    (tester) async {
      const camera = MapCameraState(
        sourceBounds: Rect.fromLTWH(0, 0, 4000, 4000),
        viewportSize: Size(400, 800),
        center: Offset(2000, 2000),
        scale: 1,
        minScale: 0.2,
        maxScale: 8,
        revision: 1,
        initialScale: 1,
      );

      Future<void> pump({required bool drawStationSymbols}) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: StructuredRouteMapView(
              // 키를 바꿔 매번 새 State(=cold 진입과 같은 picture 구축)로 돈다.
              key: ValueKey(drawStationSymbols),
              map: map,
              camera: camera,
              lineColors: const {},
              labelTextByStationId: fixture.labelTextByStationId,
              lineBadgeLabelByLineId: fixture.badgeLabelByLineId,
              drawLines: false,
              drawStationSymbols: drawStationSymbols,
            ),
          ),
        );
        await tester.pump(); // post-frame picture build.
      }

      final beforeBasemap = debugRouteMapLabelSolverInvocationCount;
      await pump(drawStationSymbols: false);
      expect(
        debugRouteMapLabelSolverInvocationCount,
        beforeBasemap,
        reason:
            '바탕층 모드 위젯이 라벨 솔버를 돌렸다 — _ensurePicture 배선이 '
            'routeMapPictureLabelLayout(basemap: !drawStationSymbols)에서 벗어났다',
      );
      // picture는 정상 구축돼야 한다(라벨만 비고 렌더 자체는 살아 있다).
      expect(find.byType(CustomPaint), findsOneWidget);

      final beforeStructured = debugRouteMapLabelSolverInvocationCount;
      await pump(drawStationSymbols: true);
      expect(
        debugRouteMapLabelSolverInvocationCount,
        greaterThan(beforeStructured),
        reason: '구조화 노선도 모드는 솔버를 돌려야 한다 — 비활성이 모드에 조건적임을 확인',
      );
    },
  );
}
