import 'dart:ui';

import 'package:easysubway_mobile/network_map.dart';
import 'package:flutter_test/flutter_test.dart';

// GPS/인플레이스 검색으로 역을 focus하면 카메라가 그 역으로 pan만 하고 확대는
// 되지 않던 버그(#2062)의 회귀 방지. 역 focus는 지역 초기 화면(축소 하한,
// #1789)보다 항상 눈에 띄게 확대돼 역이 식별 가능해야 한다.
//
// 초기 화면 카메라와 focus 카메라를 같은 지역 bounds·viewport로 만들어
// focus scale이 초기 scale보다 확실히 큰지(확대) 검증한다.
void main() {
  // 실기기 세로 해상도(SM A175N). 세로로 긴 viewport에서 수도권처럼 가로로 넓은
  // 지역은 초기 contain-fit이 가로에 걸려, 절대 픽셀 하한 기반 focus bounds가
  // 초기 화면보다 오히려 넓어져 확대가 사라지던 것이 원래 증상이다.
  const viewport = Size(1080, 2340);

  // 대표 지역 초기 화면 bounds(_readableBoundsFor 산출값 규격): 수도권처럼 가로로
  // 넓고 viewport보다 훨씬 작은 지역부터, 세로로 긴 소규모 지역까지.
  const initialBoundsByRegion = <String, Rect>{
    // 수도권 도심 확대(38%) 규격: 가로 넓음. 원 버그가 가장 크게 났던 케이스.
    '수도권(도심 확대)': Rect.fromLTWH(600, 500, 777, 568),
    // 대구권 도심 확대(38%): 준-정사각.
    '대구권(도심 확대)': Rect.fromLTWH(200, 200, 901, 408),
    // 부산권 도심 확대(38%): 대형.
    '부산권(도심 확대)': Rect.fromLTWH(100, 100, 1440, 899),
    // 광주권 전체 조망(소규모): 가로로 매우 넓음.
    '광주권(전체 조망)': Rect.fromLTWH(0, 0, 2205, 560),
  };

  const fullBounds = Rect.fromLTWH(0, 0, 4000, 4000);

  group('역 focus는 초기 화면보다 확대된다 (#2062)', () {
    initialBoundsByRegion.forEach((label, initialBounds) {
      test('$label: focus scale > 초기 scale (pan만 하지 않고 확대)', () {
        final initialCamera = networkMapInitialCameraForRegion(
          regionBounds: initialBounds,
          fullBounds: fullBounds,
          viewport: viewport,
        );
        // focus 대상 역은 초기 화면 중심에 둔다(순수 확대 비교; pan 영향 배제).
        final focusCamera = networkMapStationFocusCameraForRegion(
          initialBounds: initialBounds,
          stationCenter: initialBounds.center,
          fullBounds: fullBounds,
          viewport: viewport,
        );

        expect(
          focusCamera.scale,
          greaterThan(initialCamera.scale),
          reason: '$label focus는 확대(scale↑)돼야 하는데 pan만 됨',
        );
        // 역이 식별 가능한 수준까지 확실히 확대돼야 한다(미세 확대는 실기기에서
        // 체감되지 않는다). 최소 1.5배 이상 확대.
        expect(
          focusCamera.scale / initialCamera.scale,
          greaterThanOrEqualTo(1.5),
          reason: '$label focus 확대율이 너무 작아 역 식별이 어려움',
        );
      });
    });

    test('LOD baseline(initialScale)은 focus 후에도 초기 화면 값을 유지한다', () {
      const initialBounds = Rect.fromLTWH(600, 500, 777, 568);
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
        initialScaleOverride: initialCamera.initialScale,
      );
      // 역 focus 후에도 LOD 기준은 지역 초기 화면 baseline을 유지한다(#1764 A).
      expect(focusCamera.initialScale, initialCamera.initialScale);
      // 실제 표시 scale은 baseline보다 확대돼 있어야 한다.
      expect(focusCamera.scale, greaterThan(focusCamera.initialScale!));
    });
  });
}
