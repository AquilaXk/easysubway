import 'package:easysubway_mobile/features/network_map/domain/route_map_min_scale.dart';
import 'package:easysubway_mobile/network_map.dart';
import 'package:flutter_test/flutter_test.dart';

// 노선도 축소 하한 표(#2600).
//
// [무엇을 고정하나] 하한은 오너가 기기에서 권역마다 직접 맞춰 실측한 값이다.
// 표가 조용히 비거나 값이 렉 구간으로 내려가면 사용자가 다시 프레임이 무너지는
// 배율까지 축소할 수 있게 된다. 종전 하한은 권역 무관 0.08이라 전 권역이
// 실측 최악 구간(0.16, 팬 jank 7.4%·스와이프 19.4%)보다 아래로 열려 있었다.
//
// 프로덕션 카메라가 이 표를 실제로 소비하는지는
// route_map_min_scale_camera_test.dart가 본다.

/// lib의 `_maxMapScale`(private)과 같은 값. 상한 cap 검증용 사본이며 lib 쪽
/// 상수가 바뀌면 함께 갱신해야 한다.
const double _maxScale = 4.8;

void main() {
  // 오너 지정값(2026-07-27 실기기 실측). 코드와 PR 근거가 어긋난 채 병합되지
  // 않도록 표를 그대로 고정한다.
  const designated = <String, double>{
    '부산': 0.1128,
    '대구': 0.2216,
    '수도권': 0.2261,
    '광주': 0.2399,
    '대전': 0.3119,
  };

  test('5권역 하한이 오너 지정 실측값 그대로다', () {
    expect(kRouteMapMinScaleByRegion, designated);
  });

  designated.forEach((region, scale) {
    test('$region 하한 조회 = $scale', () {
      expect(routeMapMinimumScale(region: region, maxScale: _maxScale), scale);
    });
  });

  test('종전 하한(0.08)보다 모든 권역이 위다 — 축소 여지를 실제로 줄인다', () {
    for (final entry in kRouteMapMinScaleByRegion.entries) {
      expect(
        entry.value,
        greaterThan(0.08),
        reason: '${entry.key}: 하한이 종전과 같거나 낮아 효과가 없다',
      );
    }
  });

  test('표에 없는 권역은 성능 쪽으로 안전한 기본값을 쓴다(하한 누락 금지)', () {
    expect(
      routeMapMinimumScale(region: '없는권역', maxScale: _maxScale),
      kRouteMapDefaultMinScale,
    );
    expect(kRouteMapDefaultMinScale, greaterThan(0.08));
  });

  test('하한은 확대 상한을 넘지 않는다(minScale > maxScale인 카메라 방지)', () {
    expect(routeMapMinimumScale(region: '대전', maxScale: 0.1), 0.1);
  });

  group('프로덕션 조회 경로', () {
    test('저장형 권역명(광주권)과 표시형(광주)이 같은 하한을 준다', () {
      const pairs = <String, String>{
        '부산권': '부산',
        '대구권': '대구',
        '대전권': '대전',
        '광주권': '광주',
        '수도권': '수도권',
      };
      pairs.forEach((stored, display) {
        expect(
          networkMapMinimumScaleForRegion(stored),
          designated[display],
          reason: '$stored → $display 정규화 실패 시 하한이 기본값으로 새어 나간다',
        );
      });
    });
  });
}
