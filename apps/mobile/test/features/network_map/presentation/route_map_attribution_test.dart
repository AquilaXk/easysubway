// 광주 노선도 attribution 계약 전환 회귀(#1951 → #2011).
//
// [연혁] 광주 노선도는 CC BY-SA 2.0 KR(kiwitree) 원본이라 화면 좌하단에 attribution을
// 배선했다(#1951). [2026-07-12 #2011/#1951] 오너 자작 광주 도식(easy-subway-gwangju-v1)
// 반입으로 배포 렌더링이 CC-BY-SA SVG 파생이 아니게 되어 attribution을 자작 기준으로
// 전환했다 — 제거가 아니라 계약 전환이다(manifest license.attributionRequired=false).
// 이제 광주는 수도권·부산·대구·대전과 동일하게 화면 attribution을 표시하지 않는다.
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

/// network_map.dart의 private `_mapManifestAssetPath`와 동일한 값을 가져야 한다
/// (재시도 회귀 테스트에서 manifest asset 로드를 mock으로 가로채기 위한 키).
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
  testWidgets(
    '광주 노선도는 자작 전환으로 attribution을 표시하지 않는다(#2011 계약 전환)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NetworkMapScreen(
            repository: _FakeNetworkMapRepository(selectedRegion: '광주'),
            routeDraftController: RouteDraftController(),
            onOpenStationSearch: (_) {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pumpAndSettle();

      // 오너 자작 도식으로 전환돼 CC-BY-SA(kiwitree) attribution 체인이 배포
      // 렌더링에 부착되지 않는다 — 수도권 등과 동일하게 미표시.
      expect(find.byType(StructuredRouteMapView), findsOneWidget);
      final painter = _findRouteMapPainter(tester);
      expect(painter.attributionText, isNull);
    },
  );

  test('manifest 파싱: 자작 전환 후 어떤 권역도 attribution을 요구하지 않는다(#2011)', () {
    // parseNetworkMapAttributionByRegion은 license.attributionRequired=true인
    // 권역만 담는다. 4권역+수도권 모두 self-drawn(attributionRequired=false)이므로
    // 결과는 비어 있어야 한다(계약 전환 결과의 정본 검증).
    final byRegion = parseNetworkMapAttributionByRegion(
      _manifestWithGwangjuAttributionRequired(false),
    );
    expect(byRegion.containsKey('광주'), isFalse);

    // 역으로, 광주 license.attributionRequired를 true로 되돌리면 파서는 kiwitree
    // 배선을 다시 만든다 — 계약 배선 자체(파싱 로직)는 회귀 없이 보존됨을 확인한다.
    final restored = parseNetworkMapAttributionByRegion(
      _manifestWithGwangjuAttributionRequired(true),
    );
    expect(restored['광주'], contains('kiwitree'));
  });

  testWidgets('수도권 노선도는 attribution을 표시하지 않는다(#1951)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: _FakeNetworkMapRepository(selectedRegion: '수도권'),
          routeDraftController: RouteDraftController(),
          onOpenStationSearch: (_) {},
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
    'manifest 로드가 1차 실패해도 캐시가 비워져 재마운트 시 재시도한다(#1951 회귀, #2011 자작 재작성)',
    (tester) async {
      // [연혁] 이 회귀 테스트는 원래 광주 CC-BY-SA attribution 표시(kiwitree)를
      // 성공 관측 수단으로 삼았으나, #2011 자작 전환으로 광주를 포함한 모든 권역이
      // attributionRequired=false가 되어 성공/실패와 무관하게 attributionText가 항상
      // null이다. 따라서 관측 수단을 attribution 표시 대신 manifest 로드 시도 횟수
      // (manifestLoadAttempts)로 재작성한다 — 자작 manifest 상태와 무관하게 성립한다.
      //
      // 가드하는 회귀: _loadNetworkMapAttributionTextByRegion의
      // `_sharedAttributionTextByRegionFuture ??=` 캐시가 실패한 Future를 그대로
      // 붙들면 1차 실패가 영구 미표기로 고정된다. 캐시 무효화는 _loadAttributionText의
      // catch 블록(`_sharedAttributionTextByRegionFuture = null`)이 담당하므로, 그
      // 무효화가 사라지면(=재시도 안 됨) manifestLoadAttempts가 2에 도달하지 못한다.
      final manifestBytes = await rootBundle.load(_mapManifestAssetPath);
      // rootBundle은 loadString(cache:true)을 프로세스 생애주기 동안 캐시한다. 앞선
      // 테스트가 이미 이 키를 성공 로드해 rootBundle 자체의 _stringCache에 남아
      // 있으므로, induced failure를 실제로 겪으려면 그 캐시를 먼저 비운다.
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
          return null; // 1차 로드 실패를 유도한다.
        }
        return manifestBytes; // 2차부터는 실제 번들 바이트로 성공 로드.
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
            onOpenStationSearch: (_) {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pumpAndSettle();

      // 1차 시도는 실패했어야 한다. 실패는 reportMobileError를 거쳐
      // FlutterError.reportError로 전파되므로 takeException으로 소비해 의도된
      // 예외임을 확인한다. 자작 전환 후 attribution은 성공/실패 무관하게 null이므로
      // 표시 여부가 아니라 시도 횟수와 예외로 실패를 관측한다.
      expect(find.byType(StructuredRouteMapView), findsOneWidget);
      expect(_findRouteMapPainter(tester).attributionText, isNull);
      expect(manifestLoadAttempts, 1);
      expect(tester.takeException(), isNotNull);

      // 재마운트 시 _sharedAttributionTextByRegionFuture는 catch에서 비워졌으므로
      // _loadNetworkMapAttributionTextByRegion이 재시도된다. rootBundle
      // (cache:true)이 실패 Future를 자체 _stringCache에 캐시하므로 하위 레이어도
      // evict해야 실제 새 로드가 일어난다.
      rootBundle.evict(_mapManifestAssetPath);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: NetworkMapScreen(
            repository: _FakeNetworkMapRepository(selectedRegion: '광주'),
            routeDraftController: RouteDraftController(),
            onOpenStationSearch: (_) {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pumpAndSettle();

      // 재시도가 실제로 일어나 2차 로드가 성공했다: 시도 횟수가 2에 도달하고,
      // 2차에는 예외가 남지 않는다(성공 파싱). 캐시 무효화가 없었다면 실패 Future가
      // 붙들려 재시도가 일어나지 않고 attempts는 1에 머문다.
      expect(find.byType(StructuredRouteMapView), findsOneWidget);
      expect(_findRouteMapPainter(tester).attributionText, isNull);
      expect(manifestLoadAttempts, 2);
      expect(tester.takeException(), isNull);
    },
  );
}

/// #2011 계약 전환 테스트용 최소 manifest JSON. 광주 한 권역만 담고
/// license.attributionRequired를 인자로 토글해 parseNetworkMapAttributionByRegion의
/// 계약 배선(attributionRequired=true → kiwitree 표기 생성)이 회귀 없이 보존됨을
/// 확인한다. 실제 번들 manifest의 광주 license는 self-drawn(=false)이다.
String _manifestWithGwangjuAttributionRequired(bool attributionRequired) {
  final license = attributionRequired
      ? <String, Object?>{
          'name': 'Creative Commons Attribution-ShareAlike 2.0 Korea',
          'spdx': 'CC-BY-SA-2.0-KR',
          'authors': ['kiwitree', 'grafiker'],
          'attributionRequired': true,
        }
      : <String, Object?>{
          'name': '오너 자작 노선도(self-drawn)',
          'spdx': 'LicenseRef-Self-Drawn',
          'authors': ['오너'],
          'attributionRequired': false,
        };
  return jsonEncode(<String, Object?>{
    'maps': [
      <String, Object?>{'app_region': '광주', 'license': license},
    ],
  });
}
