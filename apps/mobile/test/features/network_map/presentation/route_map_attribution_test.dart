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
  testWidgets(
    '광주 노선도는 자작 전환으로 attribution을 표시하지 않는다(#2011 계약 전환)',
    (tester) async {
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
