import 'dart:ui' as ui;

import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_design_space.dart';
import 'package:easysubway_mobile/features/network_map/domain/structured_route_map.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_label_layout.dart';
import 'package:easysubway_mobile/features/network_map/presentation/structured_route_map_painter.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// #1970 회귀 방지: 캔버스(picture 재생)와 오버레이(히트 rect·팝오버·draft 핀)가
// 모든 카메라 상태에서 동일한 화면 좌표를 쓰는지 검증한다.
//
// - 캔버스 기준 좌표: painter의 실제 재생 변환(`designToViewport`)으로 얻는다.
//   즉 "캔버스가 실제로 그 픽셀에 노드를 그린다"를 painter 단일 수식으로 표현.
// - 오버레이 기준 좌표: 히트 rect 중심/팝오버 앵커/핀 앵커가 실제로 쓰는 값인
//   `camera.sourceToViewportPoint(station.position - origin)`.
//   (network_map.dart의 `geometry.x/y` = `station.position - origin`을
//    `camera.sourceToViewportPoint`에 넣는 것과 동일 수식)
//
// origin이 (0,0)이 아니어야 버그가 재현된다.

/// 모든 역을 [base] 부근에 두어 비영점 origin이 되도록 구성한 맵.
StructuredRouteMap _mapAround(Offset base) {
  final positions = [
    base,
    base + const Offset(24, 0),
    base + const Offset(48, 0),
  ];
  return StructuredRouteMap(
    lines: [
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

ui.Picture _picture(StructuredRouteMap map, RouteMapDesignSpace design) {
  final layout = solveRouteMapLabelLayout(
    map: map,
    design: design,
    labelTextByStationId: const {},
    badgeLabelByLineId: const {},
    measureLabel: (text, {required bool bold}) => const Size(10, 13),
    measureBadge: (text) => const Size(10, 18),
  );
  return recordRouteMapPicture(
    map: map,
    design: design,
    layout: layout,
    lineColors: const {},
    lineOffsets: const {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 비영점 origin: 모든 역이 (1000,700) 부근 → origin≈(946,646) 유형.
  final base = const Offset(1000, 700);
  // 콘텐츠 bounds 기반 origin(network_map.dart _MapGeometry: minXY - 54)을 모사.
  // 이 값은 오버레이의 geometry.x/y = position - origin과 동일 벡터다.
  final origin = base - const Offset(54, 54);

  final cameras = <String, MapCameraState>{
    '기본(초기)': MapCameraState(
      sourceBounds: const Rect.fromLTWH(0, 0, 200, 200),
      viewportSize: const Size(400, 800),
      center: const Offset(100, 100),
      scale: 3,
      minScale: 1,
      maxScale: 20,
      revision: 0,
      initialScale: 3,
    ),
    '팬 후 center 이동': MapCameraState(
      sourceBounds: const Rect.fromLTWH(0, 0, 200, 200),
      viewportSize: const Size(400, 800),
      center: const Offset(137, 62),
      scale: 3,
      minScale: 1,
      maxScale: 20,
      revision: 1,
      initialScale: 3,
    ),
    '줌 후 scale 변경': MapCameraState(
      sourceBounds: const Rect.fromLTWH(0, 0, 200, 200),
      viewportSize: const Size(400, 800),
      center: const Offset(100, 100),
      scale: 7.5,
      minScale: 1,
      maxScale: 20,
      revision: 2,
      initialScale: 3,
    ),
    'initialViewport 복원(비영점 origin center)': MapCameraState(
      sourceBounds: const Rect.fromLTWH(0, 0, 200, 200),
      viewportSize: const Size(400, 800),
      center: const Offset(54, 54),
      scale: 4.25,
      minScale: 1,
      maxScale: 20,
      revision: 3,
      initialScale: 4.25,
    ),
  };

  final map = _mapAround(base);
  final design = routeMapDesignSpaceFor(map);
  final picture = _picture(map, design);

  tearDownAll(picture.dispose);

  for (final entry in cameras.entries) {
    test('캔버스 노드 == 오버레이 앵커: ${entry.key}', () {
      final camera = entry.value;
      // sourceOrigin을 geometry origin으로 넘긴 painter가 실제 렌더 상태.
      final painter = StructuredRouteMapPainter(
        picture: picture,
        designScale: design.designScale,
        camera: camera,
        sourceOrigin: origin,
      );

      for (final station in map.stations) {
        // 캔버스: painter 재생 변환으로 얻은 노드 화면 좌표.
        final canvasPoint = painter.designToViewport(
          design.toDesign(station.position),
        );
        // 오버레이: 히트 rect 중심/팝오버/핀이 실제로 쓰는 값.
        final overlayPoint = camera.sourceToViewportPoint(
          station.position - origin,
        );
        expect(
          (canvasPoint - overlayPoint).distance,
          lessThan(1e-6),
          reason:
              '${entry.key} / ${station.stationId}: '
              'canvas=$canvasPoint overlay=$overlayPoint '
              'delta=${canvasPoint - overlayPoint}',
        );
      }
    });
  }
}
