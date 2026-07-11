// 광주 노선도 CC BY-SA 2.0 KR attribution 배선 회귀(#1951).
//
// StructuredRouteMapPainter는 화면 좌하단에 attributionText를 직접
// Canvas.drawPicture로 그리므로 find.text()로는 찾을 수 없다(#283-347행,
// structured_route_map_painter.dart 참고). 대신 CustomPaint의 painter를
// StructuredRouteMapPainter로 캐스팅해 attributionText 필드를 직접
// assert한다 — 이 방식이 렌더 방식과 가장 정합적이고 신뢰성 있는 검증이다.
import 'package:easysubway_mobile/features/network_map/presentation/structured_route_map_painter.dart';
import 'package:easysubway_mobile/features/route_draft/application/route_draft_controller.dart';
import 'package:easysubway_mobile/network_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeNetworkMapRepository implements NetworkMapRepository {
  _FakeNetworkMapRepository({required this.selectedRegion});

  final String selectedRegion;

  @override
  Future<NetworkMapData> getNetworkMap({String? region, String? lineId}) async {
    return NetworkMapData(
      regions: [NetworkMapRegion(name: selectedRegion)],
      selectedRegion: selectedRegion,
      lines: [
        NetworkMapLine(
          id: 'line-1',
          name: '$selectedRegion 1호선',
          color: '#00A0E0',
          region: selectedRegion,
        ),
      ],
      stations: [
        NetworkMapStation(
          id: 'station-a',
          nameKo: '가역',
          nameEn: 'Ga',
          region: selectedRegion,
          lineId: 'line-1',
          stationCode: '101',
          sequence: 1,
          position: const NetworkMapPosition(
            x: 0,
            y: 0,
            labelDx: 0,
            labelDy: 0,
            upPath: '',
            downPath: '',
            sourceId: 'fixture-route-map-attribution-test',
          ),
        ),
        NetworkMapStation(
          id: 'station-b',
          nameKo: '나역',
          nameEn: 'Na',
          region: selectedRegion,
          lineId: 'line-1',
          stationCode: '102',
          sequence: 2,
          position: const NetworkMapPosition(
            x: 100,
            y: 0,
            labelDx: 0,
            labelDy: 0,
            upPath: '',
            downPath: 'M 0 0 L 100 0',
            sourceId: 'fixture-route-map-attribution-test',
          ),
        ),
      ],
      edges: const [],
      positionSources: const [
        NetworkMapPositionSource(
          id: 'fixture-route-map-attribution-test',
          name: 'attribution 테스트 fixture 좌표',
          licenseStatus: 'fixture-only',
        ),
      ],
      stationLineMemberships: const [
        NetworkMapStationLineMembership(
          stationId: 'station-a',
          lineId: 'line-1',
        ),
        NetworkMapStationLineMembership(
          stationId: 'station-b',
          lineId: 'line-1',
        ),
      ],
    );
  }
}

StructuredRouteMapPainter _findRouteMapPainter(WidgetTester tester) {
  final customPaintFinder = find.descendant(
    of: find.byType(StructuredRouteMapView),
    matching: find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is StructuredRouteMapPainter,
    ),
  );
  final painter = tester.widget<CustomPaint>(customPaintFinder).painter;
  return painter as StructuredRouteMapPainter;
}

void main() {
  testWidgets('광주 노선도는 CC BY-SA attribution을 화면에 배선한다(#1951)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: _FakeNetworkMapRepository(selectedRegion: '광주'),
          routeDraftController: RouteDraftController(),
          onOpenStationSearch: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(Duration.zero);
    await tester.pumpAndSettle();

    expect(find.byType(StructuredRouteMapView), findsOneWidget);
    final painter = _findRouteMapPainter(tester);
    expect(painter.attributionText, isNotNull);
    expect(painter.attributionText, contains('kiwitree'));
    expect(painter.attributionText, contains('CC BY SA'));
  });

  testWidgets('수도권 노선도는 attribution을 표시하지 않는다(#1951)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: _FakeNetworkMapRepository(selectedRegion: '수도권'),
          routeDraftController: RouteDraftController(),
          onOpenStationSearch: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(Duration.zero);
    await tester.pumpAndSettle();

    expect(find.byType(StructuredRouteMapView), findsOneWidget);
    final painter = _findRouteMapPainter(tester);
    expect(painter.attributionText, isNull);
  });
}
