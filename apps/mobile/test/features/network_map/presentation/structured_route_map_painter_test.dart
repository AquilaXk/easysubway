import 'dart:ui' as ui;

import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/domain/structured_route_map.dart';
import 'package:easysubway_mobile/features/network_map/presentation/structured_route_map_painter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

MapCameraState camera({double scale = 1.0}) {
  return MapCameraState(
    sourceBounds: const Rect.fromLTWH(0, 0, 1000, 1000),
    viewportSize: const Size(400, 400),
    center: const Offset(500, 500),
    scale: scale,
    minScale: 0.5,
    maxScale: 3.5,
    revision: 1,
  );
}

StructuredRouteMap sampleMap() {
  return StructuredRouteMap(
    lines: [
      const RouteMapLineGeometry(
        lineId: 'L1',
        polylines: [
          [Offset(480, 480), Offset(520, 520)],
        ],
      ),
    ],
    stations: [
      const RouteMapStructuredStation(
        stationId: 'transfer',
        lineId: 'L1',
        sequence: 1,
        position: Offset(500, 500),
        labelPolygon: [],
        labelClass: RouteMapLabelClass.transfer,
      ),
      const RouteMapStructuredStation(
        stationId: 'regular',
        lineId: 'L1',
        sequence: 2,
        position: Offset(510, 510),
        labelPolygon: [],
        labelClass: RouteMapLabelClass.regular,
      ),
    ],
    transferGroups: const [
      RouteMapTransferGroup(
        stationId: 'transfer',
        lineIds: ['L1', 'L2'],
        centroid: Offset(500, 500),
      ),
    ],
  );
}

void main() {
  group('routeMapZoomBucket', () {
    test('최소 확대는 bucket 0, 중간은 1, 최대는 2', () {
      expect(routeMapZoomBucket(camera(scale: 0.5)), 0);
      expect(routeMapZoomBucket(camera(scale: 2.0)), 1);
      expect(routeMapZoomBucket(camera(scale: 3.5)), 2);
    });

    test('scale 범위가 0이면 2', () {
      final flat = MapCameraState(
        sourceBounds: const Rect.fromLTWH(0, 0, 10, 10),
        viewportSize: const Size(10, 10),
        center: const Offset(5, 5),
        scale: 1.0,
        minScale: 1.0,
        maxScale: 1.0,
        revision: 0,
      );
      expect(routeMapZoomBucket(flat), 2);
    });
  });

  group('routeMapPolylineIntersectsRect', () {
    const rect = Rect.fromLTWH(0, 0, 100, 100);
    test('교차/포함하면 true', () {
      expect(
        routeMapPolylineIntersectsRect(
          const [Offset(50, 50), Offset(60, 60)],
          rect,
        ),
        isTrue,
      );
      expect(
        routeMapPolylineIntersectsRect(
          const [Offset(-50, -50), Offset(150, 150)],
          rect,
        ),
        isTrue,
      );
    });

    test('완전히 밖이면 false', () {
      expect(
        routeMapPolylineIntersectsRect(
          const [Offset(200, 200), Offset(300, 300)],
          rect,
        ),
        isFalse,
      );
    });

    test('빈 polyline은 false', () {
      expect(routeMapPolylineIntersectsRect(const [], rect), isFalse);
    });
  });

  group('routeMapLineColors', () {
    test('hex를 파싱하고 잘못된 값은 fallback', () {
      final colors = routeMapLineColors({'L1': '#0052A4', 'L2': 'garbage'});
      expect(colors['L1'], const Color(0xFF0052A4));
      expect(colors['L2'], const Color(0xFF006D77));
    });
  });

  group('StructuredRouteMapPainter.shouldRepaint', () {
    StructuredRouteMapPainter painterWith({
      required StructuredRouteMap map,
      required MapCameraState cam,
    }) {
      return StructuredRouteMapPainter(
        map: map,
        camera: cam,
        lineColors: const {'L1': Color(0xFF0052A4)},
      );
    }

    test('revision이 바뀌면 repaint', () {
      final map = sampleMap();
      final a = painterWith(map: map, cam: camera());
      final b = painterWith(
        map: map,
        cam: MapCameraState(
          sourceBounds: const Rect.fromLTWH(0, 0, 1000, 1000),
          viewportSize: const Size(400, 400),
          center: const Offset(500, 500),
          scale: 1.0,
          minScale: 0.5,
          maxScale: 3.5,
          revision: 2,
        ),
      );
      expect(b.shouldRepaint(a), isTrue);
    });

    test('동일 map·revision·내용 동일 lineColors면 repaint 안 함', () {
      // painterWith가 매번 새 lineColors 맵 리터럴을 만들지만 내용이 같으면
      // mapEquals로 repaint하지 않는다(참조 비교로 매 프레임 repaint 방지).
      final map = sampleMap();
      final cam = camera();
      final a = painterWith(map: map, cam: cam);
      final b = painterWith(map: map, cam: cam);
      expect(b.shouldRepaint(a), isFalse);
    });

    test('lineColors 내용이 바뀌면 repaint', () {
      final map = sampleMap();
      final cam = camera();
      final a = StructuredRouteMapPainter(
        map: map,
        camera: cam,
        lineColors: const {'L1': Color(0xFF0052A4)},
      );
      final b = StructuredRouteMapPainter(
        map: map,
        camera: cam,
        lineColors: const {'L1': Color(0xFFEE0000)},
      );
      expect(b.shouldRepaint(a), isTrue);
    });
  });

  testWidgets('StructuredRouteMapView는 WebView 없이 CustomPaint로 그린다', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StructuredRouteMapView(
          map: sampleMap(),
          camera: camera(scale: 3.5),
          lineColors: routeMapLineColors(const {'L1': '#0052A4'}),
        ),
      ),
    );
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('paint는 예외 없이 그린다 (culling·LOD 경로 포함)', () {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final painter = StructuredRouteMapPainter(
      map: sampleMap(),
      camera: camera(scale: 0.5), // bucket 0 → 환승역 점만
      lineColors: routeMapLineColors(const {'L1': '#0052A4'}),
    );
    painter.paint(canvas, const Size(400, 400));
    final picture = recorder.endRecording();
    expect(picture, isNotNull);
    picture.dispose();
  });

  test('최대 확대에서 선·일반역·환승마커 경로를 예외 없이 그린다', () {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final painter = StructuredRouteMapPainter(
      map: sampleMap(),
      camera: camera(scale: 3.5), // bucket 2 → 전체 역 + 환승 그룹 마커
      lineColors: routeMapLineColors(const {'L1': '#0052A4'}),
    );
    painter.paint(canvas, const Size(400, 400));
    final picture = recorder.endRecording();
    expect(picture, isNotNull);
    picture.dispose();
  });

  testWidgets('라벨·attribution을 예외 없이 그린다 (bucket 2)', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StructuredRouteMapView(
          map: sampleMap(),
          camera: camera(scale: 3.5),
          lineColors: routeMapLineColors(const {'L1': '#0052A4'}),
          labelTextByStationId: const {
            'transfer': '환승역',
            'regular': '일반역',
          },
          attributionText: '© 광주교통공사',
        ),
      ),
    );
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('major 역 라벨은 bucket 1(중간 확대)에서 예외 없이 그려진다', (tester) async {
    final map = StructuredRouteMap(
      lines: const [],
      stations: const [
        RouteMapStructuredStation(
          stationId: 'major',
          lineId: 'L1',
          sequence: 1,
          position: Offset(500, 500),
          labelPolygon: [],
          labelClass: RouteMapLabelClass.major,
        ),
      ],
      transferGroups: const [],
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StructuredRouteMapView(
          map: map,
          camera: camera(scale: 2.0), // bucket 1
          lineColors: const {},
          labelTextByStationId: const {'major': '주요역'},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  test('shouldRepaint은 라벨 텍스트·attribution 변화를 감지한다', () {
    final map = sampleMap();
    final cam = camera(scale: 3.5);
    final base = StructuredRouteMapPainter(
      map: map,
      camera: cam,
      lineColors: const {'L1': Color(0xFF0052A4)},
      labelTextByStationId: const {'transfer': '환승역'},
      attributionText: '© A',
    );
    final differentLabel = StructuredRouteMapPainter(
      map: map,
      camera: cam,
      lineColors: const {'L1': Color(0xFF0052A4)},
      labelTextByStationId: const {'transfer': '다른역'},
      attributionText: '© A',
    );
    final differentAttribution = StructuredRouteMapPainter(
      map: map,
      camera: cam,
      lineColors: const {'L1': Color(0xFF0052A4)},
      labelTextByStationId: const {'transfer': '환승역'},
      attributionText: '© B',
    );
    expect(differentLabel.shouldRepaint(base), isTrue);
    expect(differentAttribution.shouldRepaint(base), isTrue);
  });
}
