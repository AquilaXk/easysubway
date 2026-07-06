import 'dart:ui' as ui;

import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_design_space.dart';
import 'package:easysubway_mobile/features/network_map/domain/structured_route_map.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_label_layout.dart';
import 'package:easysubway_mobile/features/network_map/presentation/structured_route_map_painter.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

StructuredRouteMap _map() {
  const positions = [Offset(0, 0), Offset(24, 0), Offset(48, 0)];
  return StructuredRouteMap(
    lines: const [
      RouteMapLineGeometry(lineId: 'L1', polylines: [positions]),
    ],
    stations: [
      for (var i = 0; i < 3; i += 1)
        RouteMapStructuredStation(
          stationId: 's$i',
          lineId: 'L1',
          sequence: i,
          position: positions[i],
          labelPolygon: const [],
          labelClass: RouteMapLabelClass.regular,
        ),
    ],
    transferGroups: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recordRouteMapPicture는 유효한 Picture를 만든다', () {
    final map = _map();
    final design = routeMapDesignSpaceFor(map);
    final layout = solveRouteMapLabelLayout(
      map: map,
      design: design,
      labelTextByStationId: const {'s0': '가역', 's1': '나역', 's2': '다역'},
      badgeLabelByLineId: const {'L1': '1'},
      measureLabel: (text, {required bool bold}) => Size(text.length * 13.0, 13),
      measureBadge: (text) => Size(text.length * 11.0 + 10, 18),
    );
    final picture = recordRouteMapPicture(
      map: map,
      design: design,
      layout: layout,
      lineColors: const {'L1': Color(0xFF00A0E0)},
      lineOffsets: const {},
    );
    expect(picture, isA<ui.Picture>());
    picture.dispose();
  });

  test('painter는 카메라 revision 변경 시에만 repaint', () {
    final map = _map();
    final design = routeMapDesignSpaceFor(map);
    final layout = solveRouteMapLabelLayout(
      map: map,
      design: design,
      labelTextByStationId: const {},
      badgeLabelByLineId: const {},
      measureLabel: (text, {required bool bold}) => const Size(10, 13),
      measureBadge: (text) => const Size(10, 18),
    );
    final picture = recordRouteMapPicture(
      map: map,
      design: design,
      layout: layout,
      lineColors: const {},
      lineOffsets: const {},
    );
    MapCameraState camera({int revision = 1}) => MapCameraState(
      sourceBounds: const Rect.fromLTWH(0, 0, 48, 48),
      viewportSize: const Size(400, 800),
      center: const Offset(24, 24),
      scale: 8,
      minScale: 8,
      maxScale: 20,
      revision: revision,
      initialScale: 8,
    );
    final a = StructuredRouteMapPainter(
      picture: picture,
      designScale: design.designScale,
      camera: camera(),
    );
    final same = StructuredRouteMapPainter(
      picture: picture,
      designScale: design.designScale,
      camera: camera(),
    );
    final moved = StructuredRouteMapPainter(
      picture: picture,
      designScale: design.designScale,
      camera: camera(revision: 2),
    );
    expect(a.shouldRepaint(same), isFalse);
    expect(moved.shouldRepaint(a), isTrue);
    picture.dispose();
  });

  test('routeMapStationLabel은 괄호 부역명을 축약한다', () {
    expect(routeMapStationLabel('굴봉산(제이드가든)'), '굴봉산');
    expect(routeMapStationLabel('신금호'), '신금호');
    // 맨 앞이 '('이면 축약할 역명이 없으므로 원문 유지.
    expect(routeMapStationLabel('(임시)역'), '(임시)역');
  });
}
