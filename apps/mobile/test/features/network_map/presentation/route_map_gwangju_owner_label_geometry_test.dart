import 'dart:convert' show utf8;
import 'dart:io';

import 'package:easysubway_mobile/features/network_map/domain/route_map_design_space.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_owner_labels.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';
import 'package:easysubway_mobile/features/route_draft/application/route_draft_controller.dart';
import 'package:easysubway_mobile/network_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

// #2068 실기기 반려 재발 방지(2026-07-16 좌우 라벨 잘림 재보고).
//
// [연혁] 최초 수정(geometry bounds에 오너 라벨 rect union, d10090a0)이 실기기에서
// 효과가 없었다 — 실측: 초기 카메라 sourceBounds.width가 여전히 라벨 미포함 좁은
// 값을 썼다. 원인은 kRouteMapBasemapRegionToId 조회가 data.selectedRegion을
// 정규화 없이 그대로 썼기 때문이다: NetworkMapData.selectedRegion은
// drift_station_repository._storedNetworkMapRegion이 만든 저장형('광주권' 등
// 접미 포함, route_map_positions.region과 동일 표기)인데
// kRouteMapBasemapRegionToId의 키는 짧은 표시명('광주')이라 조회가 항상
// null이었다 — basemapAssetId가 null → ownerEntries가 항상 null → 오너 라벨
// rect가 geometry bounds에 절대 반영되지 않았다(로드 타이밍·designScale과
// 무관하게 애초에 라벨 목록 자체가 비어 있었음).
//
// 수정: _geometryFor·_buildStructuredRouteMapCanvas 양쪽 조회를
// kRouteMapBasemapRegionToId[_displayRegionName(selectedRegion)]로 정규화.
//
// 이 테스트는 실제 capital.sqlite.gz의 광주권(route_map_positions.region=
// '광주권') 실데이터로 NetworkMapScreen을 프로덕션과 동일한 저장형 region으로
// 끝까지 마운트하고, 실제 labels.json sidecar 콘텐츠(파싱 결과)를 프로덕션과
// 동일한 오너 라벨 캐시 슬롯에 주입해, 초기 카메라의 source bounds가 오너 라벨
// extents를 실제로 포함하는지 가드한다(합성 fixture가 아니라 실 station 데이터 +
// 실 sidecar 콘텐츠로 region 키·geometry 캐시 무효화·designScale 산출 세 후보를
// 한 번에 실측 가드).
//
// [테스트 인프라 메모] sidecar 콘텐츠는 rootBundle.load()(바이트)로 읽어 이
// 테스트가 직접 utf8.decode한다 — rootBundle.loadString()이 아니다. Flutter의
// loadString은 50KB 이상 자산을 메인 아이솔레이트 잼을 피하려고 compute()(워커
// 아이솔레이트)로 디코드하는데, 이 sidecar가 170KB대라 그 경로를 타고, 이 실행
// 샌드박스에서는 그 isolate spawn이 응답 없이 멈춘다(실기기·CI에는 없는 테스트
// 환경 한계 — 프로덕션 코드가 loadString을 쓰는 것 자체는 정상이며 바꾸지
// 않는다). 파싱된 결과는 network_map.dart의
// primeNetworkMapOwnerLabelsCacheForTest로 프로덕션이 쓰는 것과 동일한 공유
// 캐시 슬롯에 주입해, 마운트된 위젯의 _loadOwnerLabels()가 실제 loadString 호출
// 없이 이 값을 즉시 받는다 — region 키 정규화 로직 자체는 실제 코드 경로 그대로
// 실행된다.
class _GwangjuFixture {
  const _GwangjuFixture({required this.data, required this.designScale});

  final NetworkMapData data;
  final double designScale;
}

const _gwangjuStoredRegion = '광주권'; // route_map_positions 저장형.

_GwangjuFixture _loadGwangjuFixture() {
  final gzBytes = File('assets/datapacks/capital.sqlite.gz').readAsBytesSync();
  final dir = Directory.systemTemp.createTempSync(
    'gwangju-owner-label-geometry-',
  );
  try {
    final sqliteFile = File('${dir.path}/pack.sqlite')
      ..writeAsBytesSync(gzip.decode(gzBytes));
    final db = sqlite3.open(sqliteFile.path);
    try {
      final stationRows = db.select(
        '''
        SELECT p.station_id, p.line_id, p.x, p.y, p.label_polygon,
               sl.line_sequence, s.name_ko, s.name_en
        FROM route_map_positions p
        JOIN station_lines sl
          ON sl.station_id = p.station_id AND sl.line_id = p.line_id
        JOIN stations s ON s.id = p.station_id
        WHERE p.region = ?
        ORDER BY p.line_id, sl.line_sequence, p.station_id
        ''',
        [_gwangjuStoredRegion],
      );
      if (stationRows.isEmpty) {
        fail('광주권 실데이터가 capital.sqlite.gz에 없다 — fixture 쿼리 확인');
      }
      final trackRows = db.select(
        'SELECT line_id, path FROM route_map_line_tracks '
        'WHERE region = ? ORDER BY line_id, track_index',
        [_gwangjuStoredRegion],
      );
      final lineRows = db.select('SELECT id, name_ko, color FROM lines');

      final stations = <NetworkMapStation>[
        for (final row in stationRows)
          NetworkMapStation(
            id: row['station_id'] as String,
            nameKo: row['name_ko'] as String,
            nameEn: row['name_en'] as String? ?? '',
            region: _gwangjuStoredRegion,
            lineId: row['line_id'] as String,
            stationCode: row['station_id'] as String,
            sequence: row['line_sequence'] as int,
            position: NetworkMapPosition(
              x: (row['x'] as num).toInt(),
              y: (row['y'] as num).toInt(),
              labelDx: 0,
              labelDy: 0,
              labelPolygon: row['label_polygon'] as String? ?? '',
              upPath: '',
              downPath: '',
              sourceId: 'gwangju-owner-label-geometry-test',
            ),
          ),
      ];
      final lineIdsInFixture = {for (final s in stations) s.lineId};
      final lines = <NetworkMapLine>[
        for (final row in lineRows)
          if (lineIdsInFixture.contains(row['id'] as String))
            NetworkMapLine(
              id: row['id'] as String,
              name: row['name_ko'] as String,
              color: (row['color'] as String?) ?? '#000000',
              region: _gwangjuStoredRegion,
            ),
      ];
      final pathsByLine = <String, List<String>>{};
      for (final row in trackRows) {
        pathsByLine
            .putIfAbsent(row['line_id'] as String, () => [])
            .add(row['path'] as String);
      }
      final data = NetworkMapData(
        regions: [const NetworkMapRegion(name: _gwangjuStoredRegion)],
        selectedRegion: _gwangjuStoredRegion,
        lines: lines,
        stations: stations,
        edges: const [],
        positionSources: const [
          NetworkMapPositionSource(
            id: 'gwangju-owner-label-geometry-test',
            name: '광주 오너 라벨 geometry 회귀 테스트 fixture',
            licenseStatus: 'fixture-only',
          ),
        ],
        stationLineMemberships: [
          for (final s in stations)
            NetworkMapStationLineMembership(stationId: s.id, lineId: s.lineId),
        ],
        lineTracks: [
          for (final entry in pathsByLine.entries)
            NetworkMapLineTrack(lineId: entry.key, paths: entry.value),
        ],
      );
      final designScale = routeMapDesignSpaceFor(
        data.toStructuredRouteMap(),
      ).designScale;
      return _GwangjuFixture(data: data, designScale: designScale);
    } finally {
      db.close();
    }
  } finally {
    dir.deleteSync(recursive: true);
  }
}

class _FakeGwangjuRepository implements NetworkMapRepository {
  _FakeGwangjuRepository(this.data);

  final NetworkMapData data;

  @override
  Future<NetworkMapData> getNetworkMap({String? region, String? lineId}) =>
      Future.value(data);
}

/// 실 sidecar 바이트를 rootBundle.load()(바이트, compute() 미경유)로 읽어 이
/// 테스트가 직접 디코드한다 — 파일 상단 [테스트 인프라 메모] 참고.
Future<String> _loadSidecarJsonBytesDecoded() async {
  final data = await rootBundle.load(kRouteMapOwnerLabelsAssetPath);
  return utf8.decode(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(resetNetworkMapOwnerLabelsCacheForTest);

  testWidgets('#2068 광주 실데이터(저장형 region=광주권): 오너 라벨 sidecar가 초기 카메라 '
      'bounds에 반영된다(region 키 정규화 회귀 가드)', (tester) async {
    final fixture = _loadGwangjuFixture();

    // ground truth: 실 sidecar 콘텐츠를 gwangju 오너 라벨 엔트리로 파싱해 기대
    // rect를 독립 산출한다(프로덕션 코드 경로와 별도).
    final sidecarJson = await _loadSidecarJsonBytesDecoded();
    final byRegion = routeMapOwnerLabelsByRegionFrom(sidecarJson);
    final ownerLabels = byRegion['gwangju'] ?? const {};
    expect(ownerLabels, isNotEmpty, reason: 'gwangju sidecar 엔트리가 없다');

    final expectedOwnerRects = networkMapOwnerLabelSourceRects(
      ownerLabels: ownerLabels.values.expand((entries) => entries),
    );

    // 프로덕션 _MapGeometry.fromStations와 동일 계산(테스트 노출 함수)으로
    // "라벨 미포함" vs "라벨 포함" 두 기대 bounds를 미리 구해둔다.
    final boundsWithoutLabels = networkMapGeometrySourceBoundsFor(
      fixture.data.stations,
    );
    final boundsWithLabels = networkMapGeometrySourceBoundsFor(
      fixture.data.stations,
      ownerLabelSourceRects: expectedOwnerRects,
    );
    expect(
      boundsWithLabels.width,
      greaterThan(boundsWithoutLabels.width),
      reason: '오너 라벨이 station 기반 bounds보다 넓어야 회귀 재현 의미가 있다',
    );

    // 프로덕션이 쓰는 것과 동일한 공유 캐시 슬롯에 파싱 결과를 주입한다 — 마운트된
    // 위젯의 _loadOwnerLabels()가 실제 rootBundle.loadString 호출 없이 이 값을
    // 즉시 받는다(테스트 인프라 메모 참고). region 키 정규화(_displayRegionName)
    // 로직 자체는 실제 프로덕션 코드 경로 그대로 실행된다.
    primeNetworkMapOwnerLabelsCacheForTest(byRegion);

    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: _FakeGwangjuRepository(fixture.data),
          routeDraftController: RouteDraftController(),
          onOpenStationSearch: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RouteMapBasemapView), findsOneWidget);
    final camera = tester
        .widget<RouteMapBasemapView>(find.byType(RouteMapBasemapView))
        .camera;

    // 회귀 가드 1: 실행 중인 위젯의 초기 카메라 sourceBounds(=fullBounds=
    // geometry 전체)가 station-only bounds보다 넓다 — sidecar가 실제로
    // geometry에 반영됐다는 직접 증거. region 키 정규화가 빠지면
    // basemapAssetId가 항상 null이 되어 이 값이 boundsWithoutLabels와
    // 같아져 실패한다.
    expect(
      camera.sourceBounds.width,
      greaterThan(boundsWithoutLabels.width),
      reason:
          '카메라 sourceBounds.width=${camera.sourceBounds.width}가 '
          'station-only width=${boundsWithoutLabels.width}보다 넓지 않다 — '
          '오너 라벨이 geometry에 반영되지 않았다(region 키 불일치 재발?)',
    );

    // 회귀 가드 2: 프로덕션 계산과 독립 산출한 "라벨 포함" 기대 bounds와
    // 실제 카메라 bounds가 일치한다(동일 입력·동일 알고리즘이므로 엄격 일치).
    expect(camera.sourceBounds.width, closeTo(boundsWithLabels.width, 0.5));
    expect(camera.sourceBounds.height, closeTo(boundsWithLabels.height, 0.5));

    // 회귀 가드 3(초기 카메라 scale ≤ 폭fit-라벨포함): 초기 카메라가 라벨을
    // 포함한 source 폭 전체를 뷰포트 안에 담아야 한다 — contain-fit이므로
    // scale × sourceBounds.width가 뷰포트 폭을 넘지 않는다(라벨이 화면 밖으로
    // 잘리지 않음을 뜻하는 직접 조건).
    final viewportWidth = camera.viewportSize.width;
    expect(
      camera.scale * camera.sourceBounds.width,
      lessThanOrEqualTo(viewportWidth + 0.5),
      reason:
          'scale=${camera.scale} × sourceBounds.width=${camera.sourceBounds.width} '
          '가 viewportWidth=$viewportWidth를 넘는다 — 라벨이 화면 밖으로 잘린다',
    );
  });
}
