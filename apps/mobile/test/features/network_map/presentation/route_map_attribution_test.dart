// 광주 노선도 CC BY-SA 2.0 KR attribution 배선 회귀(#1951).
//
// StructuredRouteMapPainter는 화면 좌하단에 attributionText를 직접
// Canvas.drawPicture로 그리므로 find.text()로는 찾을 수 없다(#283-347행,
// structured_route_map_painter.dart 참고). 대신 CustomPaint의 painter를
// StructuredRouteMapPainter로 캐스팅해 attributionText 필드를 직접
// assert한다 — 이 방식이 렌더 방식과 가장 정합적이고 신뢰성 있는 검증이다.
import 'dart:convert';

import 'package:easysubway_mobile/features/network_map/presentation/structured_route_map_painter.dart';
import 'package:easysubway_mobile/features/route_draft/application/route_draft_controller.dart';
import 'package:easysubway_mobile/network_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// #1951 datapack manifest asset의 실제 번들 키. lib/network_map.dart의
/// `_mapManifestAssetPath`(private)와 동일한 값을 가져야 한다.
const _mapManifestAssetPath = 'assets/datapacks/metro_map_pack/manifest.json';

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

  testWidgets(
    'manifest 로드가 1차 실패해도 캐시가 비워져 재마운트 시 재시도해 attribution을 표시한다(#1951)',
    (tester) async {
      // 원래 핸들러(flutter_test가 등록한, 디스크에서 실제 번들 asset을
      // 읽어오는 핸들러)로 manifest 원본 바이트를 미리 읽어 둔 뒤, 그
      // 핸들러를 우리 mock으로 교체한다 — manifest 키에 한해 최초 1회만
      // null(=로드 실패)을 반환하고, 이후 호출은 미리 읽어 둔 원본 바이트를
      // 그대로 반환해 실제 로드 성공을 재현한다.
      final manifestBytes = await rootBundle.load(_mapManifestAssetPath);
      // rootBundle은 loadString(cache:true, 이번 수정의 기본값)을 프로세스
      // 생애주기 동안 캐시한다. 이전 테스트(#1951 광주 attribution 테스트)가
      // 이미 이 키를 성공적으로 로드해 rootBundle 자체의 _stringCache에
      // 남아 있으므로, 이 테스트가 induced failure를 실제로 겪으려면 그
      // 캐시를 먼저 비워야 한다.
      rootBundle.evict(_mapManifestAssetPath);
      addTearDown(() => rootBundle.evict(_mapManifestAssetPath));

      final binaryMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var manifestLoadAttempts = 0;
      binaryMessenger.setMockMessageHandler('flutter/assets', (
        ByteData? message,
      ) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        if (key != _mapManifestAssetPath) {
          return null;
        }
        manifestLoadAttempts += 1;
        if (manifestLoadAttempts == 1) {
          return null;
        }
        return manifestBytes;
      });
      addTearDown(
        () => binaryMessenger.setMockMessageHandler('flutter/assets', null),
      );

      resetNetworkMapAttributionCacheForTest();
      addTearDown(resetNetworkMapAttributionCacheForTest);

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

      // 1차 시도는 실패했어야 하므로 attribution은 아직 표시되지 않는다.
      // 실패는 reportMobileError를 거쳐 FlutterError.reportError로 전파되므로
      // (테스트 바인딩이 기본으로 실패 처리하지 않도록) takeException으로
      // 소비해 의도된 예외임을 확인한다.
      expect(find.byType(StructuredRouteMapView), findsOneWidget);
      expect(_findRouteMapPainter(tester).attributionText, isNull);
      expect(manifestLoadAttempts, 1);
      expect(tester.takeException(), isNotNull);

      // 재마운트하면 _sharedAttributionTextByRegionFuture는 비워져 있었으므로
      // _loadNetworkMapAttributionTextByRegion 자체는 재시도된다. 다만
      // rootBundle.loadString(cache:true, 이번 수정의 기본값)이 실패한
      // Future 자체를 자체 _stringCache에 영구 캐시하므로, 그 하위 레이어의
      // 재시도가 실제로 새 로드를 하려면 여기서도 다시 evict가 필요하다.
      rootBundle.evict(_mapManifestAssetPath);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
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
      expect(manifestLoadAttempts, 2);
    },
  );
}
