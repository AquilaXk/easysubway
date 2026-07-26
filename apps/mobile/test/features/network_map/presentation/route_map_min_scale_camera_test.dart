import 'dart:math' as math;

import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';
import 'package:easysubway_mobile/features/route_draft/application/route_draft_controller.dart';
import 'package:easysubway_mobile/network_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 축소 하한이 **카메라에 실제로 걸리는지**(#2600).
//
// [이 파일이 red가 되어야 하는 두 축]
//   (값) [_RegionFixture.expectedFloor]는 표를 참조하지 않는 **리터럴**이다.
//        kRouteMapMinScaleByRegion의 부산을 0.05로 되돌리면 조회 그룹과 위젯
//        그룹이 함께 red다(표 사본 비교 하나에만 의존하지 않는다).
//   (배선) '프로덕션 배선' 그룹은 NetworkMapScreen을 끝까지 마운트해 **커밋된**
//        카메라를 읽는다. network_map.dart의 build가 `_cameraForBounds`에
//        `minScale:`을 안 넘기면 폴백 하한(0.08)으로 조용히 되돌아가는데, 그때
//        red다. 핀치 테스트는 `_updateCameraForGesture`(startCamera.minScale로
//        clamp)까지 실제 포인터로 태운다.
//
// 표 자체(값·정규화·폴백)는 route_map_min_scale_test.dart가 본다.
//
// 아래 unit 그룹의 권역 수치는 오너 기기(SM-A175N) 실측이다(2026-07-27):
// 지도 뷰포트 384.0 × 602.4 logical, 노선망 잉크 bbox와 초기 가독 배율은 표 참고.

class _RegionFixture {
  const _RegionFixture({
    required this.region,
    required this.expectedFloor,
    required this.ink,
    required this.readableInitialScale,
  });

  /// 저장형 권역명(앱이 실제로 다루는 형태).
  final String region;

  /// 이 권역의 오너 지정 하한 — **표에서 읽지 않은 리터럴**. 표가 바뀌면 red.
  final double expectedFloor;

  /// _MapGeometry.fromStations가 만든 노선망 잉크 bbox(카메라 sourceBounds).
  final Size ink;

  /// sidecar 라벨 기준 초기 가독 배율(기기 로그 실측).
  final double readableInitialScale;

  Rect get fullBounds => Rect.fromLTWH(0, 0, ink.width, ink.height);
}

const _viewport = Size(384.0, 602.4);

const _fixtures = <_RegionFixture>[
  _RegionFixture(
    region: '수도권',
    expectedFloor: 0.2261,
    ink: Size(3556.2, 2692.2),
    readableInitialScale: 0.8403,
  ),
  _RegionFixture(
    region: '부산권',
    expectedFloor: 0.1128,
    ink: Size(10266.1, 4789.3),
    readableInitialScale: 0.2661,
  ),
  _RegionFixture(
    region: '대구권',
    expectedFloor: 0.2216,
    ink: Size(4329.5, 2187.2),
    readableInitialScale: 0.3824,
  ),
  _RegionFixture(
    region: '대전권',
    expectedFloor: 0.3119,
    ink: Size(1425.4, 1537.4),
    readableInitialScale: 0.3824,
  ),
  _RegionFixture(
    region: '광주권',
    expectedFloor: 0.2399,
    ink: Size(1664.0, 1442.2),
    readableInitialScale: 0.3824,
  ),
];

/// 하한 배율로 연 카메라. 기대값이 아니라 **리터럴 하한**을 입력으로 쓴다.
MapCameraState _cameraAtFloor(_RegionFixture fixture) {
  return networkMapInitialCameraForRegion(
    // 노선망 전체를 담으려는 요청 = 가장 축소된 카메라 요청.
    regionBounds: fixture.fullBounds,
    fullBounds: fixture.fullBounds,
    viewport: _viewport,
    minScale: fixture.expectedFloor,
  );
}

double _containFit(MapCameraState camera) => math.min(
  camera.viewportSize.width / camera.sourceBounds.width,
  camera.viewportSize.height / camera.sourceBounds.height,
);

// ---------------------------------------------------------------------------
// 프로덕션 배선 테스트용 합성 fixture.
//
// 실 datapack이 아니라 합성 데이터를 쓰는 이유: 배선이 소비하는 입력은
// `data.selectedRegion` 문자열 하나뿐이고(하한 조회 → _cameraForBounds), 나머지는
// 카메라가 스스로 계산한 값에서 검증할 수 있다. 합성 데이터로 노선망 크기를
// 직접 정해 "초기 배율 > 하한"과 "초기 배율 < 하한" 두 상황을 모두 만든다.
// ---------------------------------------------------------------------------

const _syntheticLineId = 'line-route-map-min-scale';
const _syntheticSourceId = 'route-map-min-scale-test';

NetworkMapData _syntheticData({
  required String storedRegion,
  required double span,
}) {
  final stations = <NetworkMapStation>[
    for (var i = 0; i < 6; i += 1)
      NetworkMapStation(
        id: 'station-min-scale-$i',
        nameKo: '하한$i',
        nameEn: 'Floor$i',
        region: storedRegion,
        lineId: _syntheticLineId,
        stationCode: 'F$i',
        sequence: i,
        position: NetworkMapPosition(
          x: (span * i / 5).round(),
          y: (span * 0.2 * (i % 2)).round(),
          labelDx: 0,
          labelDy: 0,
          labelPolygon: '',
          upPath: '',
          downPath: '',
          sourceId: _syntheticSourceId,
        ),
      ),
  ];
  return NetworkMapData(
    regions: [NetworkMapRegion(name: storedRegion)],
    selectedRegion: storedRegion,
    lines: [
      NetworkMapLine(
        id: _syntheticLineId,
        name: '하한선',
        color: '#000000',
        region: storedRegion,
      ),
    ],
    stations: stations,
    edges: const [],
    positionSources: const [
      NetworkMapPositionSource(
        id: _syntheticSourceId,
        name: '축소 하한 배선 테스트 fixture',
        licenseStatus: 'fixture-only',
      ),
    ],
    stationLineMemberships: [
      for (final station in stations)
        NetworkMapStationLineMembership(
          stationId: station.id,
          lineId: _syntheticLineId,
        ),
    ],
    lineTracks: const [],
  );
}

class _FakeNetworkMapRepository implements NetworkMapRepository {
  _FakeNetworkMapRepository(this.data);

  final NetworkMapData data;

  @override
  Future<NetworkMapData> getNetworkMap({String? region, String? lineId}) =>
      Future.value(data);
}

Widget _screen(NetworkMapData data, {String? focusStationRequestId}) {
  return MaterialApp(
    home: NetworkMapScreen(
      repository: _FakeNetworkMapRepository(data),
      routeDraftController: RouteDraftController(),
      onOpenStationSearch: (_, _) {},
      focusStationRequestId: focusStationRequestId,
    ),
  );
}

/// 실기기(세로 폰) 크기로 테스트 서피스를 맞춘다.
void _usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(411, 914);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

MapCameraState _readCamera(WidgetTester tester) {
  expect(find.byType(RouteMapBasemapView), findsOneWidget);
  return tester
      .widget<RouteMapBasemapView>(find.byType(RouteMapBasemapView))
      .camera;
}

Future<MapCameraState> _mountAndReadCamera(
  WidgetTester tester,
  NetworkMapData data,
) async {
  _usePhoneSurface(tester);
  // 오너 라벨 sidecar 캐시를 비운 채로 시드해 비동기 로드를 막는다 —
  // readableScale == null(= sidecar 미로드) 프레임을 결정적으로 재현한다.
  primeNetworkMapOwnerLabelsCacheForTest(const {});
  await tester.pumpWidget(_screen(data));
  await tester.pumpAndSettle();
  return _readCamera(tester);
}

void main() {
  tearDown(resetNetworkMapOwnerLabelsCacheForTest);

  group('(1) 하한 조회값이 오너 지정 리터럴과 같다', () {
    for (final fixture in _fixtures) {
      test('${fixture.region}: 하한 = ${fixture.expectedFloor}', () {
        // 저장형 그대로 넘겨도(정규화가 조회 함수 안에 있으므로) 지정값이 나온다.
        expect(
          networkMapMinimumScaleForRegion(fixture.region),
          fixture.expectedFloor,
        );
        expect(_cameraAtFloor(fixture).minScale, fixture.expectedFloor);
      });
    }

    test('모든 권역 하한이 종전 0.08보다 위다', () {
      // 실측 최악 구간(0.16)까지 올라갔는지는 여기서 보지 않는다 — 부산은 실제로
      // 그 아래이며, 그 간극은 route_map_min_scale.dart 상단에 #2600 후속으로
      // 명시돼 있다.
      for (final fixture in _fixtures) {
        expect(fixture.expectedFloor, greaterThan(0.08));
      }
    });
  });

  group('(2) 저장된 viewport 복원', () {
    for (final fixture in _fixtures) {
      test('${fixture.region}: 하한보다 축소된 저장 viewport는 하한으로 승격된다', () {
        // 저장 당시 노선망보다 4배 넓게 보고 있던 viewport(하한 도입 전 상태).
        final storedViewport = Rect.fromCenter(
          center: fixture.fullBounds.center,
          width: fixture.ink.width * 4,
          height: fixture.ink.height * 4,
        );
        final restored = networkMapInitialCameraForRegion(
          regionBounds: storedViewport,
          fullBounds: fixture.fullBounds,
          viewport: _viewport,
          minScale: fixture.expectedFloor,
        );
        expect(restored.scale, fixture.expectedFloor);
        expect(restored.scale, greaterThanOrEqualTo(restored.minScale));
      });
    }

    test('하한보다 확대된 저장 viewport는 그대로 복원된다(불필요한 승격 없음)', () {
      final fixture = _fixtures.first;
      final storedViewport = Rect.fromCenter(
        center: fixture.fullBounds.center,
        width: 600,
        height: 900,
      );
      final restored = networkMapInitialCameraForRegion(
        regionBounds: storedViewport,
        fullBounds: fixture.fullBounds,
        viewport: _viewport,
        minScale: fixture.expectedFloor,
      );
      expect(restored.scale, greaterThan(fixture.expectedFloor));
    });
  });

  group('(3) 기존 카메라 계약', () {
    for (final fixture in _fixtures) {
      test('${fixture.region}: fixture 전제 — 초기 가독 배율 > 하한', () {
        // 카메라를 만들지 않고 실측 상수 두 개만 비교한다. sidecar가 붙은 정상
        // 상태에서 하한이 첫 화면을 밀어올리지 않는다는 **전제**를 고정하는 것이
        // 목적이며, 실제 첫 화면이 안 변하는지는 (5)·(6) 위젯 그룹이 마운트해서
        // 본다.
        expect(
          fixture.readableInitialScale,
          greaterThan(fixture.expectedFloor),
          reason: '${fixture.region}: 하한이 초기 가독 배율보다 크다',
        );
      });

      test('${fixture.region}: 역 focus는 하한 적용 후에도 초기 화면보다 확대된다(#2062)', () {
        final initialBounds = Rect.fromCenter(
          center: fixture.fullBounds.center,
          width: fixture.ink.width * 0.38,
          height: fixture.ink.height * 0.38,
        );
        final initialCamera = networkMapInitialCameraForRegion(
          regionBounds: initialBounds,
          fullBounds: fixture.fullBounds,
          viewport: _viewport,
          minScale: fixture.expectedFloor,
        );
        final focusCamera = networkMapStationFocusCameraForRegion(
          initialBounds: initialBounds,
          stationCenter: initialBounds.center,
          fullBounds: fixture.fullBounds,
          viewport: _viewport,
          minScale: fixture.expectedFloor,
        );
        expect(focusCamera.scale, greaterThan(initialCamera.scale));
        expect(focusCamera.scale / initialCamera.scale, greaterThan(1.5));
      });
    }

    test('하한 배율에서는 렌더러 overscan 여유가 0이 된다(계약 명시)', () {
      // overscan은 scale/3.25로 넓히되 minScale에서 멈춘다. 하한에 붙어 있는
      // 카메라는 더 넓힐 곳이 없어 렌더러 카메라 == 시야 카메라가 된다. 이번
      // 변경으로 하한이 0.08 → 0.11~0.31로 올라가 "최대 축소 상태"가 사용자가
      // 상시 머무는 지점이 되므로, 그 지점에서 팬 중 여유가 사라지는 것이
      // 의도된 계약임을 못 박는다.
      for (final fixture in _fixtures) {
        final visual = _cameraAtFloor(fixture);
        expect(visual.scale, fixture.expectedFloor);
        final renderer = networkMapOverscannedRendererCamera(visual);
        expect(
          renderer.scale,
          fixture.expectedFloor,
          reason: '${fixture.region}: 하한에서 overscan이 하한 아래로 내려갔다',
        );
        expect(
          renderer.visibleSourceRect,
          visual.visibleSourceRect,
          reason: '${fixture.region}: 하한에서는 여유가 없어 두 카메라가 같아야 한다',
        );
      }
    });

    test('하한보다 위에서는 overscan이 실제로 넓어지고 시야를 덮는다', () {
      // 항진명제가 되지 않도록 하한보다 확대된 카메라로 확인한다.
      for (final fixture in _fixtures) {
        final visual = _cameraAtFloor(
          fixture,
        ).copyWith(scale: fixture.expectedFloor * 2);
        final renderer = networkMapOverscannedRendererCamera(visual);
        expect(
          renderer.scale,
          lessThan(visual.scale),
          reason: '${fixture.region}: overscan이 넓어지지 않았다',
        );
        expect(
          renderer.scale,
          greaterThanOrEqualTo(fixture.expectedFloor),
          reason: '${fixture.region}: overscan이 하한 아래로 내려갔다',
        );
        expect(
          networkMapRendererCameraCoversVisual(
            rendererCamera: renderer,
            visualCamera: visual,
          ),
          isTrue,
          reason: '${fixture.region}: overscan이 시야를 못 덮는다',
        );
      }
    });
  });

  group('(4) 하한 배율의 팬 경계', () {
    for (final fixture in _fixtures) {
      test('${fixture.region}: 하한에서 팬해도 노선망 밖으로 새지 않는다', () {
        final camera = _cameraAtFloor(fixture);
        // 사방으로 크게 팬을 시도해도 clamped가 잡아준다.
        const margin = 220.0;
        for (final push in <Offset>[
          Offset(-fixture.ink.width, -fixture.ink.height),
          Offset(fixture.ink.width, fixture.ink.height),
          Offset(fixture.ink.width, -fixture.ink.height),
        ]) {
          final panned = camera
              .copyWith(center: camera.center + push)
              .clamped(viewportMargin: margin);
          final visible = panned.visibleSourceRect;
          final allowed = fixture.fullBounds.inflate(margin / panned.scale);
          expect(visible.left, greaterThanOrEqualTo(allowed.left - 1e-6));
          expect(visible.top, greaterThanOrEqualTo(allowed.top - 1e-6));
          expect(visible.right, lessThanOrEqualTo(allowed.right + 1e-6));
          expect(visible.bottom, lessThanOrEqualTo(allowed.bottom + 1e-6));
        }
      });
    }
  });

  group('(5) 프로덕션 배선: 마운트된 캔버스가 권역 하한을 싣는다', () {
    // 노선망이 작아 초기 contain-fit이 하한보다 훨씬 크다 → 하한이 캡되지 않고
    // 그대로 카메라에 실린다.
    const smallSpan = 300.0;

    for (final fixture in _fixtures) {
      testWidgets(
        '${fixture.region}: 커밋된 카메라 minScale = ${fixture.expectedFloor}',
        (tester) async {
          final camera = await _mountAndReadCamera(
            tester,
            _syntheticData(storedRegion: fixture.region, span: smallSpan),
          );
          expect(
            _containFit(camera),
            greaterThan(fixture.expectedFloor),
            reason: '${fixture.region}: fixture 전제가 깨졌다(초기 배율이 하한보다 낮다)',
          );
          expect(
            camera.minScale,
            closeTo(fixture.expectedFloor, 1e-9),
            reason:
                '${fixture.region}: 커밋된 카메라 하한이 ${camera.minScale} — '
                'build가 minScale을 안 넘겨 폴백(0.08)으로 되돌아갔거나 표가 바뀌었다',
          );
        },
      );
    }

    testWidgets('역 focus 카메라도 같은 하한을 싣는다', (tester) async {
      final fixture = _fixtures[1]; // 부산권
      final data = _syntheticData(
        storedRegion: fixture.region,
        span: smallSpan,
      );
      _usePhoneSurface(tester);
      primeNetworkMapOwnerLabelsCacheForTest(const {});
      await tester.pumpWidget(_screen(data));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _screen(data, focusStationRequestId: data.stations[2].id),
      );
      await tester.pumpAndSettle();

      expect(
        _readCamera(tester).minScale,
        closeTo(fixture.expectedFloor, 1e-9),
        reason: 'focus 분기가 minScale을 안 넘기면 폴백(0.08)으로 되돌아간다',
      );
    });

    testWidgets('핀치 줌아웃이 권역 하한에서 멈춘다(실제 제스처 경로)', (tester) async {
      final fixture = _fixtures[1]; // 부산권
      final camera = await _mountAndReadCamera(
        tester,
        _syntheticData(storedRegion: fixture.region, span: smallSpan),
      );
      expect(
        camera.scale,
        greaterThan(fixture.expectedFloor),
        reason: '축소 여지가 없으면 이 테스트가 아무것도 검증하지 못한다',
      );

      final center = tester.getCenter(
        find.byKey(const Key('networkMapSurface')),
      );
      final left = await tester.startGesture(center - const Offset(120, 0));
      final right = await tester.startGesture(center + const Offset(120, 0));
      // 두 손가락 간격을 240 → 12로 좁힌다(비율 0.05) — 어떤 권역 하한보다도 훨씬
      // 아래로 내려가는 축소 요청이다.
      for (var step = 0; step < 6; step += 1) {
        await left.moveBy(const Offset(19, 0));
        await right.moveBy(const Offset(-19, 0));
        await tester.pump();
      }
      await left.up();
      await right.up();
      await tester.pumpAndSettle();

      expect(
        _readCamera(tester).scale,
        closeTo(fixture.expectedFloor, 1e-6),
        reason: '핀치 줌아웃이 하한에서 멈추지 않았다',
      );
    });
  });

  group('(6) sidecar 미로드 프레임: 하한이 첫 화면을 밀어올리지 않는다', () {
    // 오너 라벨 sidecar가 아직(또는 끝내) 안 붙으면 초기 카메라는 기존
    // contain-fit이고, 그 배율이 하한보다 낮은 권역이 있다(실측 부산 0.0984 <
    // 0.1128). 하한을 그대로 물리면 첫 화면이 강제로 확대돼 "소규모 권역 전체
    // 조망"(#1764 E)과 "focus = 초기 배율 × 1/0.42"(#2062)가 함께 깨진다.
    // 그래서 하한은 초기 화면 배율로 캡한다 — 축소만 막고 확대는 하지 않는다.
    const hugeSpan = 40000.0;

    for (final fixture in _fixtures) {
      testWidgets('${fixture.region}: 초기 배율이 하한보다 낮으면 그 배율을 유지한다', (
        tester,
      ) async {
        final camera = await _mountAndReadCamera(
          tester,
          _syntheticData(storedRegion: fixture.region, span: hugeSpan),
        );
        final fit = _containFit(camera);
        expect(
          fit,
          lessThan(fixture.expectedFloor),
          reason: '${fixture.region}: fixture 전제가 깨졌다(초기 배율이 하한보다 높다)',
        );
        expect(
          camera.scale,
          closeTo(fit, 1e-9),
          reason:
              '${fixture.region}: 첫 화면이 ${camera.scale}로 밀려 올라갔다 '
              '(전체 조망 $fit) — 하한이 초기 배율로 캡되지 않았다',
        );
        expect(
          camera.minScale,
          closeTo(fit, 1e-9),
          reason: '${fixture.region}: 카메라 하한이 초기 배율보다 커서 축소 제스처가 확대로 뒤집힌다',
        );
      });
    }
  });
}
