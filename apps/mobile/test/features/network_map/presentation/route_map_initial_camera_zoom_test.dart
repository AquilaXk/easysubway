import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:math' as math;

import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_design_space.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_owner_labels.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';
import 'package:easysubway_mobile/features/route_draft/application/route_draft_controller.dart';
import 'package:easysubway_mobile/network_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

// #2068 트랙 QA 후속: 노선도 초기 카메라를 "전체-fit 과축소"에서 "노선도 콘텐츠
// 중앙을 글자가 읽히는 배율로 확대"로 바꾼 계약의 회귀 가드.
//
// [오너 결정] "글자가 읽힐 정도로 중앙을 확대" + "노선도 기준으로 중앙을 의미함".
//
// [가독 기준의 근거] basemap 모드에서 화면에 실제로 그려지는 역명은 오너 라벨
// (sidecar labels.json)이다. 라벨은 design px(`entry.fontSizePx × designScale`)로
// 그려지고 캔버스는 `camera.scale / designScale`로 스케일되므로 designScale이
// 약분되어 **화면 글자 크기 = entry.fontSizePx(source 단위) × camera.scale**이다.
// 목표 화면 글자 크기는 리포 내 기존 캘리브레이션 상수
// [kRouteMapDesignLabelFontPx](13.0 design px — design space가 "일반 탐색 줌"
// 에서 역명이 갖는 크기로 정한 값, route_map_design_space.dart)를 재사용한다.
//
// [권역 중앙값의 모집단] sidecar에는 그 권역 데이터에 없는 라벨(광주 2호선
// 미개통 구간: 글자 14 vs 운영 1호선 60)이 섞여 있어, 전 엔트리 중앙값을 쓰면
// 실제 역 라벨 기준으로 5배 넘게 과확대된다. 그래서 이 권역 route_map_positions
// 에 실제로 있는 역명과 매칭되는 엔트리만 모집단으로 쓴다.
//
// 이 테스트는 합성 fixture가 아니라 실 datapack(capital.sqlite.gz)의 권역 데이터
// + 실 sidecar 콘텐츠로 NetworkMapScreen을 끝까지 마운트해 실행 중인 위젯의
// 카메라를 직접 실측한다(route_map_gwangju_owner_label_geometry_test와 동일
// 인프라 — sidecar는 rootBundle.load() 바이트로 읽어 직접 디코드한 뒤
// primeNetworkMapOwnerLabelsCacheForTest로 프로덕션 공유 캐시에 주입한다).

class _RegionFixture {
  const _RegionFixture({required this.data, required this.stationNames});

  final NetworkMapData data;
  final Set<String> stationNames;
}

/// 저장형 region('수도권' 등, route_map_positions.region 표기) → sidecar asset id.
const _regionsUnderTest = <String, String>{
  '수도권': 'seoul',
  '부산권': 'busan',
  '대구권': 'daegu',
  '대전권': 'daejeon',
  '광주권': 'gwangju',
};

_RegionFixture _loadRegionFixture(String storedRegion) {
  final gzBytes = File('assets/datapacks/capital.sqlite.gz').readAsBytesSync();
  final dir = Directory.systemTemp.createTempSync('initial-camera-zoom-');
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
        [storedRegion],
      );
      if (stationRows.isEmpty) {
        fail('$storedRegion 실데이터가 capital.sqlite.gz에 없다 — fixture 쿼리 확인');
      }
      final trackRows = db.select(
        'SELECT line_id, path FROM route_map_line_tracks '
        'WHERE region = ? ORDER BY line_id, track_index',
        [storedRegion],
      );
      final lineRows = db.select('SELECT id, name_ko, color FROM lines');

      final stations = <NetworkMapStation>[
        for (final row in stationRows)
          NetworkMapStation(
            id: row['station_id'] as String,
            nameKo: row['name_ko'] as String,
            nameEn: row['name_en'] as String? ?? '',
            region: storedRegion,
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
              sourceId: 'initial-camera-zoom-test',
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
              region: storedRegion,
            ),
      ];
      final pathsByLine = <String, List<String>>{};
      for (final row in trackRows) {
        pathsByLine
            .putIfAbsent(row['line_id'] as String, () => [])
            .add(row['path'] as String);
      }
      return _RegionFixture(
        data: NetworkMapData(
          regions: [NetworkMapRegion(name: storedRegion)],
          selectedRegion: storedRegion,
          lines: lines,
          stations: stations,
          edges: const [],
          positionSources: const [
            NetworkMapPositionSource(
              id: 'initial-camera-zoom-test',
              name: '초기 카메라 확대 회귀 테스트 fixture',
              licenseStatus: 'fixture-only',
            ),
          ],
          stationLineMemberships: [
            for (final s in stations)
              NetworkMapStationLineMembership(
                stationId: s.id,
                lineId: s.lineId,
              ),
          ],
          lineTracks: [
            for (final entry in pathsByLine.entries)
              NetworkMapLineTrack(lineId: entry.key, paths: entry.value),
          ],
        ),
        stationNames: {for (final s in stations) s.nameKo},
      );
    } finally {
      db.close();
    }
  } finally {
    dir.deleteSync(recursive: true);
  }
}

class _FakeRegionRepository implements NetworkMapRepository {
  _FakeRegionRepository(this.data);

  final NetworkMapData data;

  @override
  Future<NetworkMapData> getNetworkMap({String? region, String? lineId}) =>
      Future.value(data);
}

class _StubViewportRepository implements NetworkMapViewportRepository {
  _StubViewportRepository(this.stored);

  final Rect? stored;
  final saved = <String, Rect>{};

  @override
  Future<String?> loadSelectedRegion() async => null;

  @override
  Future<void> saveSelectedRegion(String region) async {}

  @override
  Future<Rect?> loadViewport(String region) async => stored;

  @override
  Future<void> saveViewport({
    required String region,
    required Rect viewport,
  }) async {
    saved[region] = viewport;
  }
}

/// sidecar 바이트를 rootBundle.load()로 읽어 직접 디코드한다(loadString은 50KB
/// 초과 자산을 compute() 워커 아이솔레이트로 넘기는데 이 실행 샌드박스에서
/// 그 spawn이 멈춘다 — 테스트 환경 한계, 프로덕션 코드는 그대로 둔다).
Future<String> _loadSidecarJson() async {
  final data = await rootBundle.load(kRouteMapOwnerLabelsAssetPath);
  return utf8.decode(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

/// 이 권역 데이터에 실제로 있는 역과 매칭되는 오너 라벨 font-size의 중앙값
/// (source 단위). 프로덕션 기준과 독립적으로 테스트가 직접 산출한다.
///
/// `fontSizePx > 0` 필터는 프로덕션 [networkMapReadableInitialMapScale]과 **같은
/// 모집단**을 쓰기 위한 것이다. 현재 sidecar에는 0 이하 값이 없어 결과가 같지만,
/// 재컴파일로 `fontSizePx: 0` 엔트리가 하나라도 들어오면 두 중앙값이 갈려 이
/// 파일의 핵심 가드가 프로덕션 버그 없이 red가 되거나 실제 회귀를 통과시킨다.
double _matchedOwnerFontSizeMedian(
  Map<String, List<RouteMapOwnerLabelEntry>> ownerLabels,
  Set<String> stationNames,
) {
  final sizes = <double>[
    for (final entry in ownerLabels.entries)
      if (stationNames.contains(entry.key))
        for (final label in entry.value)
          if (label.fontSizePx > 0) label.fontSizePx,
  ]..sort();
  expect(sizes, isNotEmpty, reason: '매칭되는 오너 라벨이 없다 — fixture/sidecar 확인');
  return sizes[sizes.length ~/ 2];
}

/// 실기기(세로 폰) 크기로 테스트 서피스를 맞춘다. 기본 800×600은 폰보다 훨씬
/// 가로가 넓어 소규모 권역이 이미 가독 배율에 들어가버려 대비 케이스가 사라진다.
void _usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(411, 914);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _screen(
  _RegionFixture fixture, {
  Rect? storedViewport,
  String? focusStationRequestId,
}) {
  return MaterialApp(
    home: NetworkMapScreen(
      repository: _FakeRegionRepository(fixture.data),
      routeDraftController: RouteDraftController(),
      onOpenStationSearch: (_, _) {},
      focusStationRequestId: focusStationRequestId,
      viewportRepository: storedViewport == null
          ? null
          : _StubViewportRepository(storedViewport),
    ),
  );
}

MapCameraState _readCamera(WidgetTester tester) {
  expect(find.byType(RouteMapBasemapView), findsOneWidget);
  return tester
      .widget<RouteMapBasemapView>(find.byType(RouteMapBasemapView))
      .camera;
}

Future<void> _primeSidecar() async {
  primeNetworkMapOwnerLabelsCacheForTest(
    routeMapOwnerLabelsByRegionFrom(await _loadSidecarJson()),
  );
}

Future<MapCameraState> _mountAndReadCamera(
  WidgetTester tester,
  _RegionFixture fixture, {
  Rect? storedViewport,
}) async {
  _usePhoneSurface(tester);
  await _primeSidecar();
  await tester.pumpWidget(_screen(fixture, storedViewport: storedViewport));
  await tester.pumpAndSettle();
  return _readCamera(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(resetNetworkMapOwnerLabelsCacheForTest);

  group('저장 viewport 없음: 초기 카메라는 콘텐츠 중앙을 가독 배율로 연다 (#2068 QA)', () {
    _regionsUnderTest.forEach((storedRegion, assetId) {
      testWidgets('$storedRegion: 중심=콘텐츠 중앙, 배율×라벨 중앙값 ≥ 가독 기준', (
        tester,
      ) async {
        final fixture = _loadRegionFixture(storedRegion);
        final sidecarJson = await _loadSidecarJson();
        final ownerLabels =
            routeMapOwnerLabelsByRegionFrom(sidecarJson)[assetId] ?? const {};
        final medianFontPx = _matchedOwnerFontSizeMedian(
          ownerLabels,
          fixture.stationNames,
        );

        final camera = await _mountAndReadCamera(tester, fixture);

        // ① 중심 = 노선도 콘텐츠 bounding box 중앙. geometry는 콘텐츠 extents에
        //    대칭 54px 여백을 더한 것이라 sourceBounds.center가 곧 콘텐츠 중앙이다
        //    (viewBox 캔버스 중앙·헤더·여백이 아님).
        expect(
          camera.center.dx,
          closeTo(camera.sourceBounds.center.dx, 0.5),
          reason:
              '$storedRegion 초기 카메라 중심 x=${camera.center.dx}가 '
              '콘텐츠 중앙 ${camera.sourceBounds.center.dx}과 다르다',
        );
        expect(
          camera.center.dy,
          closeTo(camera.sourceBounds.center.dy, 0.5),
          reason:
              '$storedRegion 초기 카메라 중심 y=${camera.center.dy}가 '
              '콘텐츠 중앙 ${camera.sourceBounds.center.dy}과 다르다',
        );

        // ② 배율: 오너 라벨 중앙값의 화면 글자 크기가 가독 기준 이상.
        //    화면 글자 크기 = fontSizePx(source) × camera.scale (파일 상단 근거).
        expect(
          medianFontPx * camera.scale,
          greaterThanOrEqualTo(kRouteMapDesignLabelFontPx - 0.001),
          reason:
              '$storedRegion 초기 화면 라벨이 '
              '${(medianFontPx * camera.scale).toStringAsFixed(2)}px로 '
              '가독 기준 $kRouteMapDesignLabelFontPx px 미만이다 '
              '(scale=${camera.scale}, 라벨 중앙값=$medianFontPx)',
        );
      });
    });
  });

  group('대비 케이스: 소형(대전·광주) vs 초대형(부산·수도권)', () {
    // 소규모 지역(#1764 E, 역 수 ≤ 40)은 초기 bounds 기준선이 지도 전체라
    // 기준선 contain-fit을 카메라 자신의 값으로 재현할 수 있다. 그 위에서
    // `max(contain-fit, 가독 배율)` 규칙이 실제로 적용됐는지 **분기까지 포함해**
    // 고정한다.
    //
    // 처음에는 "대전은 전체 조망이 유지된다"를 `scale × width ≤ viewportWidth`로
    // 직접 단언했는데, 이는 **viewport 형태 의존**이라 환경에 따라 깨진다. 지도
    // 캔버스 높이는 상단바·하단 배너의 텍스트 높이에 좌우되고 그 텍스트 높이는
    // 실행 환경 폰트에 따라 달라진다(로컬 macOS vs Linux CI). 캔버스가 짧아지면
    // contain-fit이 세로에 걸려 작아지고, 그러면 대전도 가독 미달이 되어 규칙상
    // **정당하게** 확대된다(CI 실측: scale × width = 545.0 > viewportWidth 411).
    // 즉 프로덕션이 아니라 테스트의 기대가 과하게 좁았다. 그래서 "어느 분기가
    // 선택돼야 하는가"를 카메라의 실제 viewport에서 판정해 검증한다.
    testWidgets('대전권(소규모): max(contain-fit, 가독 배율) 규칙이 그대로 적용된다', (
      tester,
    ) async {
      final fixture = _loadRegionFixture('대전권');
      final ownerLabels =
          routeMapOwnerLabelsByRegionFrom(
            await _loadSidecarJson(),
          )['daejeon'] ??
          const {};
      final medianFontPx = _matchedOwnerFontSizeMedian(
        ownerLabels,
        fixture.stationNames,
      );
      final camera = await _mountAndReadCamera(tester, fixture);

      final containFit = math.min(
        camera.viewportSize.width / camera.sourceBounds.width,
        camera.viewportSize.height / camera.sourceBounds.height,
      );
      final readable = kRouteMapDesignLabelFontPx / medianFontPx;
      final diagnostics =
          'W=${camera.sourceBounds.width} H=${camera.sourceBounds.height} '
          'viewport=${camera.viewportSize} 라벨중앙값=$medianFontPx '
          'containFit=$containFit readable=$readable scale=${camera.scale}';

      if (readable <= containFit) {
        // 실기기급 세로 폰(411×768 캔버스) 실측이 이 분기다: containFit 0.2470 ·
        // readable 0.2407 → 이미 13.3px이라 확대 없음(동작 불변, 전체 조망 유지).
        expect(
          camera.scale,
          closeTo(containFit, 1e-6),
          reason: '대전권이 이미 가독 배율인데 불필요하게 확대됐다 — $diagnostics',
        );
        expect(
          camera.scale * camera.sourceBounds.width,
          lessThanOrEqualTo(camera.viewportSize.width + 0.5),
          reason: '대전권 전체 조망이 깨졌다 — $diagnostics',
        );
      } else {
        // 캔버스가 짧아 contain-fit에서 라벨이 13px에 못 미치는 환경: 규칙대로
        // 가독 배율까지 올라가야 한다(과확대도, 미확대도 아님).
        expect(
          camera.scale,
          closeTo(readable, 1e-6),
          reason: '대전권이 가독 미달인데 가독 배율로 올라가지 않았다 — $diagnostics',
        );
      }

      // 분기와 무관한 공통 계약: 축소되지 않고, 라벨은 가독 기준 이상이다.
      expect(
        camera.scale,
        greaterThanOrEqualTo(containFit - 1e-6),
        reason: '대전권 초기 배율이 기존 contain-fit보다 축소됐다 — $diagnostics',
      );
      expect(
        medianFontPx * camera.scale,
        greaterThanOrEqualTo(kRouteMapDesignLabelFontPx - 0.001),
        reason: '대전권 초기 화면 라벨이 가독 기준 미만이다 — $diagnostics',
      );
    });

    for (final storedRegion in const ['광주권', '부산권', '수도권']) {
      testWidgets('$storedRegion은 전체-fit보다 확대된 상태로 연다', (tester) async {
        final fixture = _loadRegionFixture(storedRegion);
        final camera = await _mountAndReadCamera(tester, fixture);

        final wholeMapFit =
            camera.viewportSize.width / camera.sourceBounds.width;
        expect(
          camera.scale,
          greaterThan(wholeMapFit),
          reason:
              '$storedRegion 초기 배율 ${camera.scale}가 전체-fit $wholeMapFit '
              '이하다 — 과축소가 그대로다',
        );
      });
    }
  });

  group('역 focus 카메라는 확대된 초기 배율 위에서 다시 확대된다 (#2062 · 프로덕션 배선)', () {
    // seam이 아니라 프로덕션 배선(focusStationRequestId → _searchFanMenuStationId
    // → _NetworkMapCanvas.focusedStationId → _stationFocusBoundsFor)을 그대로
    // 태운다. network_map.dart의 focus 분기가 초기 카메라 bounds 대신 geometry의
    // 원 initialBounds를 다시 넘기면 이 테스트가 red가 된다(수도권 실측: 비율이
    // 2.38 → 0.86으로 뒤집혀 focus가 오히려 축소된다).
    testWidgets('수도권: focus scale / 초기 scale == 1/0.42 (≈2.38)', (
      tester,
    ) async {
      _usePhoneSurface(tester);
      await _primeSidecar();
      final fixture = _loadRegionFixture('수도권');

      await tester.pumpWidget(_screen(fixture));
      await tester.pumpAndSettle();
      final initialCamera = _readCamera(tester);

      // 화면 중앙에 가까운 역을 골라 focus 시 경계 클램프 영향을 줄인다.
      final target = fixture.data.stations.reduce((a, b) {
        double d(NetworkMapStation s) =>
            ((s.position.x - initialCamera.center.dx).abs() +
            (s.position.y - initialCamera.center.dy).abs());
        return d(a) <= d(b) ? a : b;
      });

      await tester.pumpWidget(
        _screen(fixture, focusStationRequestId: target.id),
      );
      await tester.pumpAndSettle();
      final focusCamera = _readCamera(tester);

      expect(
        focusCamera.scale / initialCamera.scale,
        closeTo(1 / 0.42, 0.02),
        reason:
            'focus scale=${focusCamera.scale} / 초기 scale=${initialCamera.scale} '
            '= ${focusCamera.scale / initialCamera.scale} — focus가 초기 화면 '
            'bounds를 공유하지 않으면 이 비율이 무너진다(축소 회귀)',
      );
      // LOD baseline(initialScale)은 지역 초기 카메라 값을 그대로 상속한다.
      expect(focusCamera.initialScale, closeTo(initialCamera.scale, 1e-6));
    });
  });

  group('cold-open: sidecar가 이미 캐시돼 있으면 첫 프레임부터 가독 카메라 (#2068 QA)', () {
    testWidgets('수도권: 캔버스 첫 build에서 과축소 카메라를 거치지 않는다', (tester) async {
      _usePhoneSurface(tester);
      await _primeSidecar();
      final fixture = _loadRegionFixture('수도권');
      final ownerLabels =
          routeMapOwnerLabelsByRegionFrom(await _loadSidecarJson())['seoul'] ??
          const {};
      final medianFontPx = _matchedOwnerFontSizeMedian(
        ownerLabels,
        fixture.stationNames,
      );

      await tester.pumpWidget(_screen(fixture));
      // 캔버스가 처음 등장하는 프레임을 잡는다(pumpAndSettle 금지 — 중간 프레임을
      // 삼켜 줌 팝을 못 본다).
      for (var i = 0; i < 30; i += 1) {
        if (tester.any(find.byType(RouteMapBasemapView))) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 16));
      }
      final firstFrameCamera = _readCamera(tester);

      expect(
        medianFontPx * firstFrameCamera.scale,
        greaterThanOrEqualTo(kRouteMapDesignLabelFontPx - 0.001),
        reason:
            '첫 프레임 라벨이 '
            '${(medianFontPx * firstFrameCamera.scale).toStringAsFixed(2)}px로 '
            '과축소다 — sidecar 로드 후 확대로 튀는 줌 팝이 보인다',
      );

      // 이후 프레임에서 카메라가 다시 바뀌지 않는다(= 팝이 없다).
      await tester.pumpAndSettle();
      expect(_readCamera(tester).scale, closeTo(firstFrameCamera.scale, 1e-9));
    });
  });

  group('networkMapReadableInitialMapScale 모집단 규칙', () {
    RouteMapOwnerLabelEntry entry(String station, double fontSizePx) =>
        RouteMapOwnerLabelEntry(
          station: station,
          role: 'ordinary',
          position: Offset.zero,
          anchor: RouteMapOwnerLabelAnchor.start,
          fontSizePx: fontSizePx,
        );

    test('권역 데이터에 없는 라벨(미개통 구간)은 중앙값 모집단에서 빠진다', () {
      // 운영 라벨 3건(60) + 미개통 라벨 5건(14): 전 엔트리 중앙값은 14라
      // 기준 13px 기준 scale 0.93(≈5배 과확대), 매칭 한정 중앙값 60이면 0.217.
      final ownerLabels = <String, List<RouteMapOwnerLabelEntry>>{
        for (final name in ['가', '나', '다']) name: [entry(name, 60)],
        for (final name in ['A', 'B', 'C', 'D', 'E']) name: [entry(name, 14)],
      };
      expect(
        networkMapReadableInitialMapScale(
          ownerLabelsByStationName: ownerLabels,
          stationNames: const {'가', '나', '다'},
        ),
        closeTo(kRouteMapDesignLabelFontPx / 60, 1e-9),
      );
    });

    test('매칭이 하나도 없으면 전 엔트리 중앙값으로 폴백한다(렌더의 폴백 라벨 크기와 같은 모집단)', () {
      expect(
        networkMapReadableInitialMapScale(
          ownerLabelsByStationName: {
            'A': [entry('A', 20)],
          },
          stationNames: const {'없는역'},
        ),
        closeTo(kRouteMapDesignLabelFontPx / 20, 1e-9),
      );
    });

    test('sidecar가 비면 null — 호출부는 기존 contain-fit을 쓴다', () {
      expect(
        networkMapReadableInitialMapScale(
          ownerLabelsByStationName: const {},
          stationNames: const {'가'},
        ),
        isNull,
      );
    });
  });

  group('networkMapInitialCameraBounds 하한·상한', () {
    const fullBounds = Rect.fromLTWH(0, 0, 4000, 3000);
    const regionInitialBounds = Rect.fromLTWH(1000, 800, 1500, 1200);
    const viewport = Size(411, 830);

    double fitOf(Rect bounds) => [
      viewport.width / bounds.width,
      viewport.height / bounds.height,
    ].reduce((a, b) => a < b ? a : b);

    test('가독 배율이 contain-fit보다 작으면 배율이 그대로다(축소되는 권역 없음)', () {
      final containFit = fitOf(regionInitialBounds);
      final bounds = networkMapInitialCameraBounds(
        fullBounds: fullBounds,
        regionInitialBounds: regionInitialBounds,
        viewport: viewport,
        readableScale: containFit / 2,
      );
      expect(fitOf(bounds), closeTo(containFit, 1e-9));
      // 배율은 그대로여도 중심은 콘텐츠 중앙으로 옮긴다(오너 결정).
      expect(bounds.center, fullBounds.center);
    });

    test('readableScale이 null이면(=sidecar 없음) contain-fit 배율 유지', () {
      final bounds = networkMapInitialCameraBounds(
        fullBounds: fullBounds,
        regionInitialBounds: regionInitialBounds,
        viewport: viewport,
        readableScale: null,
      );
      expect(fitOf(bounds), closeTo(fitOf(regionInitialBounds), 1e-9));
    });

    test('가독 배율이 상한(_maxMapScale)을 넘어도 상한을 넘겨 확대하지 않는다', () {
      final bounds = networkMapInitialCameraBounds(
        fullBounds: fullBounds,
        regionInitialBounds: regionInitialBounds,
        viewport: viewport,
        readableScale: 1000,
      );
      // lib의 _maxMapScale(4.8)과 같은 값 — 상수가 바뀌면 함께 갱신해야 한다.
      expect(fitOf(bounds), closeTo(4.8, 1e-9));
    });
  });

  group('초기 확대와 역 focus 카메라(#2062)의 정합', () {
    const fullBounds = Rect.fromLTWH(0, 0, 4000, 3000);
    const regionInitialBounds = Rect.fromLTWH(1000, 800, 1500, 1200);
    const viewport = Size(411, 830);

    test('확대된 초기 bounds를 focus가 공유하면 focus는 여전히 확대된다', () {
      // 초기 화면이 가독 배율로 확대된 뒤에도 focus가 그보다 더 확대돼야 한다.
      // geometry의 원 initialBounds를 focus가 쓰면 여기서 비율이 1 미만이 된다.
      final initialBounds = networkMapInitialCameraBounds(
        fullBounds: fullBounds,
        regionInitialBounds: regionInitialBounds,
        viewport: viewport,
        readableScale: 0.9,
      );
      final initialCamera = networkMapInitialCameraForRegion(
        regionBounds: initialBounds,
        fullBounds: fullBounds,
        viewport: viewport,
      );
      final focusCamera = networkMapStationFocusCameraForRegion(
        initialBounds: initialBounds,
        stationCenter: initialBounds.center,
        fullBounds: fullBounds,
        viewport: viewport,
      );
      expect(
        focusCamera.scale / initialCamera.scale,
        greaterThanOrEqualTo(1.5),
        reason:
            'focus scale=${focusCamera.scale}가 초기 scale='
            '${initialCamera.scale} 대비 충분히 확대되지 않았다',
      );
    });
  });

  group('저장 viewport가 있으면 복원 동작이 그대로다', () {
    testWidgets('대전권: 저장된 viewport의 중심·contain-fit 배율로 복원된다', (tester) async {
      final fixture = _loadRegionFixture('대전권');
      final sidecarJson = await _loadSidecarJson();
      final ownerLabels =
          routeMapOwnerLabelsByRegionFrom(sidecarJson)['daejeon'] ?? const {};
      // 카메라 좌표계(geometry origin을 뺀 0-기준 공간)의 지도 전체 bounds.
      final geometryBounds = networkMapGeometrySourceBoundsFor(
        fixture.data.stations,
        ownerLabelSourceRects: networkMapOwnerLabelSourceRects(
          ownerLabels: ownerLabels.values.expand((entries) => entries),
        ),
      );
      final fullBounds = Rect.fromLTWH(
        0,
        0,
        geometryBounds.width,
        geometryBounds.height,
      );

      // 지도 안쪽에 충분히 들어간 사각형(클램프가 중심을 밀지 않도록).
      final stored = Rect.fromCenter(
        center: fullBounds.center.translate(
          fullBounds.width * 0.1,
          fullBounds.height * 0.1,
        ),
        width: fullBounds.width * 0.3,
        height: fullBounds.height * 0.3,
      );

      final camera = await _mountAndReadCamera(
        tester,
        fixture,
        storedViewport: stored,
      );

      expect(camera.center.dx, closeTo(stored.center.dx, 0.5));
      expect(camera.center.dy, closeTo(stored.center.dy, 0.5));
      final expectedScale = [
        camera.viewportSize.width / stored.width,
        camera.viewportSize.height / stored.height,
      ].reduce((a, b) => a < b ? a : b);
      expect(
        camera.scale,
        closeTo(expectedScale, 0.001),
        reason: '저장 viewport 복원 배율이 contain-fit이 아니다(초기 확대가 복원 경로를 침범)',
      );
    });
  });
}
