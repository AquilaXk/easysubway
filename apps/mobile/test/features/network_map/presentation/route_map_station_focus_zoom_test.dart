import 'dart:ui';

import 'package:easysubway_mobile/network_map.dart';
import 'package:flutter_test/flutter_test.dart';

// GPS/인플레이스 검색으로 역을 focus하면 카메라가 그 역으로 pan만 하고 확대는
// 되지 않던 버그(#2062)의 회귀 방지. 역 focus는 지역 초기 화면(축소 하한,
// #1789)보다 항상 눈에 띄게 확대돼 역이 식별 가능해야 한다.
//
// 초기 화면 카메라와 focus 카메라를 같은 지역 bounds·viewport로 만들어
// focus scale이 초기 scale보다 확실히 큰지(확대) 검증한다.

// lib의 _maxMapScale(private)과 같은 값. 상한 saturation 케이스를 검증하는
// 테스트 전용 사본이며, lib 쪽 상수가 바뀌면 이 값도 함께 갱신해야 한다.
const _maxMapScaleForTest = 4.8;

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

    test('초소형 지역(초기 scale이 _maxMapScale 근접)은 확대율이 2.38배보다 줄어든다 '
        '(상한 saturation, pan-only 퇴행은 아님)', () {
      // 초기 화면 bounds가 매우 작아 초기 scale 자체가 4.8/0.42≈2.02를
      // 넘는 경우: focus scale은 4.8에서 saturate돼 확대율이 기본
      // 2.38배보다 작아진다. 이 케이스는 여전히 확대(ratio>1)는 되지만
      // 그 폭이 줄어드는 정직한 상한 상호작용을 고정한다(성능을 부풀리지
      // 않음).
      const initialBounds = Rect.fromLTWH(1500, 1500, 400, 300);
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

      expect(initialCamera.scale, closeTo(2.7, 1e-9));
      expect(focusCamera.scale, closeTo(_maxMapScaleForTest, 1e-9));
      expect(
        focusCamera.scale / initialCamera.scale,
        closeTo(1.7777777777777777, 1e-9),
        reason: '_maxMapScale saturation으로 확대율이 2.38배 미만으로 줄어야 함',
      );
    });

    test('극소형 지역(초기 화면 자체가 이미 _maxMapScale)은 focus가 순수 pan이 된다 '
        '(둘 다 같은 상한 공유 — pan-only 이지만 초기보다 축소되지는 않음)', () {
      // 초기 화면 bounds가 극단적으로 작아 초기 camera 자체가 이미 상한에서
      // 시작하는 경우: focus bounds를 아무리 좁혀도 같은 상한에 막혀 focus
      // scale == 초기 scale이 된다(ratio 1.0). 이 상태를 "확대"로 잘못
      // 주장하지 않고, 실제 동작(순수 pan, 축소로의 퇴행은 아님) 그대로
      // 고정한다.
      const initialBounds = Rect.fromLTWH(1500, 1500, 100, 50);
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

      expect(initialCamera.scale, closeTo(_maxMapScaleForTest, 1e-9));
      expect(
        focusCamera.scale,
        closeTo(initialCamera.scale, 1e-9),
        reason: '초기 scale이 이미 상한이면 focus도 같은 상한이라 순수 pan(ratio 1.0)',
      );
      // 최소한 초기 scale 아래로 축소되지는 않는다.
      expect(focusCamera.scale, greaterThanOrEqualTo(initialCamera.scale));
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
