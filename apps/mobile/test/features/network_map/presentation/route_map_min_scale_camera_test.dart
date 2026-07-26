import 'dart:ui';

import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_min_scale.dart';
import 'package:easysubway_mobile/network_map.dart';
import 'package:flutter_test/flutter_test.dart';

// 축소 하한이 **카메라에 실제로 걸리는지**(#2600).
//
// 표 자체는 route_map_min_scale_test.dart가 본다. 여기서는 그 값이
//   (1) 제스처 줌아웃을 막고,
//   (2) 저장된 viewport를 복원할 때 하한으로 승격되고,
//   (3) 초기 화면(가독 배율)·역 focus 확대 불변식(#2062)을 깨지 않고,
//   (4) 하한 배율에서 팬 경계 clamp가 노선망 밖으로 나가지 않는지
// 를 프로덕션과 같은 헬퍼로 확인한다.
//
// 권역 수치는 오너 기기(SM-A175N) 실측이다(2026-07-27):
// 지도 뷰포트 384.0 × 602.4 logical, 노선망 잉크 bbox와 초기 가독 배율은 아래 표.

class _RegionFixture {
  const _RegionFixture({
    required this.region,
    required this.ink,
    required this.readableInitialScale,
  });

  final String region;

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
    ink: Size(3556.2, 2692.2),
    readableInitialScale: 0.8403,
  ),
  _RegionFixture(
    region: '부산권',
    ink: Size(10266.1, 4789.3),
    readableInitialScale: 0.2661,
  ),
  _RegionFixture(
    region: '대구권',
    ink: Size(4329.5, 2187.2),
    readableInitialScale: 0.3824,
  ),
  _RegionFixture(
    region: '대전권',
    ink: Size(1425.4, 1537.4),
    readableInitialScale: 0.3824,
  ),
  _RegionFixture(
    region: '광주권',
    ink: Size(1664.0, 1442.2),
    readableInitialScale: 0.3824,
  ),
];

MapCameraState _cameraAtFloor(_RegionFixture fixture) {
  final floor = networkMapMinimumScaleForRegion(fixture.region);
  return networkMapInitialCameraForRegion(
    // 노선망 전체를 담으려는 요청 = 가장 축소된 카메라 요청.
    regionBounds: fixture.fullBounds,
    fullBounds: fixture.fullBounds,
    viewport: _viewport,
    minScale: floor,
  );
}

void main() {
  group('(1) 제스처 줌아웃이 하한에서 멈춘다', () {
    for (final fixture in _fixtures) {
      test('${fixture.region}: 계속 축소해도 하한 아래로 안 내려간다', () {
        final floor = networkMapMinimumScaleForRegion(fixture.region);
        var camera = _cameraAtFloor(fixture);
        expect(camera.minScale, floor);

        // 핀치 줌아웃을 여러 번 겹쳐도(프로덕션 제스처와 같은 clamp 경로).
        for (var pinch = 0; pinch < 8; pinch += 1) {
          camera = camera.zoomBy(
            0.5,
            focalPoint: _viewport.center(Offset.zero),
          );
        }
        expect(
          camera.scale,
          floor,
          reason: '${fixture.region}: 하한 아래로 축소가 열려 있다',
        );
      });
    }

    test('종전 하한(0.08)이라면 같은 제스처가 렉 구간까지 내려간다(대조군)', () {
      final legacy = networkMapInitialCameraForRegion(
        regionBounds: _fixtures.first.fullBounds,
        fullBounds: _fixtures.first.fullBounds,
        viewport: _viewport,
      );
      var camera = legacy;
      for (var pinch = 0; pinch < 8; pinch += 1) {
        camera = camera.zoomBy(0.5, focalPoint: _viewport.center(Offset.zero));
      }
      // 실측 최악 구간(0.16, 팬 jank 7.4%)보다 아래까지 내려간다.
      expect(camera.scale, lessThan(0.16));
    });
  });

  group('(2) 저장된 viewport 복원', () {
    for (final fixture in _fixtures) {
      test('${fixture.region}: 하한보다 축소된 저장 viewport는 하한으로 승격된다', () {
        final floor = networkMapMinimumScaleForRegion(fixture.region);
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
          minScale: floor,
        );
        expect(restored.scale, floor);
        expect(restored.scale, greaterThanOrEqualTo(restored.minScale));
      });
    }

    test('하한보다 확대된 저장 viewport는 그대로 복원된다(불필요한 승격 없음)', () {
      final fixture = _fixtures.first;
      final floor = networkMapMinimumScaleForRegion(fixture.region);
      final storedViewport = Rect.fromCenter(
        center: fixture.fullBounds.center,
        width: 600,
        height: 900,
      );
      final restored = networkMapInitialCameraForRegion(
        regionBounds: storedViewport,
        fullBounds: fixture.fullBounds,
        viewport: _viewport,
        minScale: floor,
      );
      expect(restored.scale, greaterThan(floor));
    });
  });

  group('(3) 기존 카메라 계약', () {
    for (final fixture in _fixtures) {
      test('${fixture.region}: 초기 가독 배율이 하한보다 커서 첫 화면이 안 변한다', () {
        // 하한이 초기 배율보다 커지면 앱을 열자마자 더 확대된 화면이 뜬다 —
        // 이번 변경은 축소 여지만 줄이고 첫 화면은 건드리지 않는다.
        expect(
          fixture.readableInitialScale,
          greaterThan(networkMapMinimumScaleForRegion(fixture.region)),
          reason: '${fixture.region}: 하한이 초기 화면을 밀어올린다',
        );
      });

      test('${fixture.region}: 역 focus는 하한 적용 후에도 초기 화면보다 확대된다(#2062)', () {
        final floor = networkMapMinimumScaleForRegion(fixture.region);
        final initialBounds = Rect.fromCenter(
          center: fixture.fullBounds.center,
          width: fixture.ink.width * 0.38,
          height: fixture.ink.height * 0.38,
        );
        final initialCamera = networkMapInitialCameraForRegion(
          regionBounds: initialBounds,
          fullBounds: fixture.fullBounds,
          viewport: _viewport,
          minScale: floor,
        );
        final focusCamera = networkMapStationFocusCameraForRegion(
          initialBounds: initialBounds,
          stationCenter: initialBounds.center,
          fullBounds: fixture.fullBounds,
          viewport: _viewport,
          minScale: floor,
        );
        expect(focusCamera.scale, greaterThan(initialCamera.scale));
        expect(focusCamera.scale / initialCamera.scale, greaterThan(1.5));
      });
    }

    test('렌더러 overscan 카메라가 하한 아래로 내려가지 않고 시야를 계속 덮는다', () {
      // overscan은 scale/3.25로 넓히되 minScale에서 멈춘다 — 하한이 올라가면
      // 덜 넓어지므로, 시야를 여전히 덮는지 확인한다.
      for (final fixture in _fixtures) {
        final floor = networkMapMinimumScaleForRegion(fixture.region);
        final visual = _cameraAtFloor(fixture);
        final renderer = networkMapOverscannedRendererCamera(visual);
        expect(renderer.scale, greaterThanOrEqualTo(floor));
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

  group('(5) 권역 전환', () {
    test('권역마다 서로 다른 하한이 카메라에 실린다', () {
      final byRegion = <String, double>{
        for (final fixture in _fixtures)
          fixture.region: _cameraAtFloor(fixture).minScale,
      };
      expect(byRegion, {
        '수도권': kRouteMapMinScaleByRegion['수도권'],
        '부산권': kRouteMapMinScaleByRegion['부산'],
        '대구권': kRouteMapMinScaleByRegion['대구'],
        '대전권': kRouteMapMinScaleByRegion['대전'],
        '광주권': kRouteMapMinScaleByRegion['광주'],
      });
    });
  });
}
