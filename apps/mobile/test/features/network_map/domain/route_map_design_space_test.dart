import 'dart:ui';

import 'package:easysubway_mobile/features/network_map/domain/route_map_design_space.dart';
import 'package:easysubway_mobile/features/network_map/domain/structured_route_map.dart';
import 'package:flutter_test/flutter_test.dart';

StructuredRouteMap _mapWithSpacing(double spacing) {
  return StructuredRouteMap(
    lines: [
      RouteMapLineGeometry(
        lineId: 'L1',
        polylines: [
          [for (var i = 0; i < 5; i += 1) Offset(i * spacing, 0)],
        ],
      ),
    ],
    stations: const [],
    transferGroups: const [],
  );
}

void main() {
  test('k*는 인접 정점 중앙값 간격을 기준 역 간격으로 정규화한다', () {
    final design = routeMapDesignSpaceFor(_mapWithSpacing(24));
    // 24 source → kRouteMapDesignStationSpacingPx(48) 이 되도록 k*=2.
    expect(design.designScale, closeTo(48 / 24, 1e-9));
    expect(design.toDesign(const Offset(24, 0)).dx, closeTo(48, 1e-9));
  });

  test('간격이 제각각이면 중앙값을 쓴다', () {
    final map = StructuredRouteMap(
      lines: [
        RouteMapLineGeometry(
          lineId: 'L1',
          polylines: [
            const [Offset(0, 0), Offset(10, 0), Offset(30, 0), Offset(130, 0)],
          ],
        ),
      ],
      stations: const [],
      transferGroups: const [],
    );
    // 간격 10, 20, 100 → 중앙값 20.
    final design = routeMapDesignSpaceFor(map);
    expect(design.designScale, closeTo(48 / 20, 1e-9));
  });

  test('빈 지도는 배율 1 (0 나눗셈 방지)', () {
    final design = routeMapDesignSpaceFor(
      const StructuredRouteMap(lines: [], stations: [], transferGroups: []),
    );
    expect(design.designScale, 1.0);
  });

  test('maxCameraScale은 라벨이 최대 화면 px에 닿는 지점', () {
    final design = routeMapDesignSpaceFor(_mapWithSpacing(24)); // k*=2
    // 라벨 design 13px × (scale/k*) = 26px → scale = 2 × k*.
    expect(
      design.maxCameraScale,
      closeTo(
        design.designScale *
            (kRouteMapMaxLabelScreenPx / kRouteMapDesignLabelFontPx),
        1e-9,
      ),
    );
  });
}
