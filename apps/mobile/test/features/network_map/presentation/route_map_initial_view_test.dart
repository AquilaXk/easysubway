import 'dart:ui';

import 'package:easysubway_mobile/network_map.dart';
import 'package:flutter_test/flutter_test.dart';

// #1764 E: 소규모 지역(역 수 임계 이하)은 초기 bounds 기준선을 지역 전체로,
// 대형 지역은 38% 도심 확대로 잡는다. 판정은 networkMapUsesWholeRegionInitialView
// 단일 소스를 쓴다. (LOD zoom bucket 산정은 #1789 정적 스케일 렌더 전환에서
// 폐지됐고, 기준선 판정만 역 수 임계로 남았다 — 구 route_map_initial_bucket_test
// 에서 이관.)
//
// [#2068 트랙 QA 후속 · 계약 범위 축소] 이 판정과 아래 contain-fit 성질은 이제
// 초기 카메라의 **기준선(하한 배율)** 만 정한다. 최종 초기 카메라는
// networkMapInitialCameraBounds가 "기준선 contain-fit"과 "오너 라벨 가독 배율"
// 중 큰 쪽으로 정하므로, 소규모 지역이라고 반드시 전체 조망으로 열리지는 않는다
// (실측: 대전은 유지, 광주는 1.20배 확대). 실제 초기 카메라 계약은
// route_map_initial_camera_zoom_test가 실데이터로 가드한다.
void main() {
  group('소규모 지역 초기 bounds 기준선 (#1764 E)', () {
    test('광주·대전은 지역 전체 기준선, 부산·대구·수도권은 38% 도심 확대 기준선', () {
      expect(networkMapUsesWholeRegionInitialView(20), isTrue, reason: '광주');
      expect(networkMapUsesWholeRegionInitialView(22), isTrue, reason: '대전');
      expect(networkMapUsesWholeRegionInitialView(101), isFalse, reason: '대구');
      expect(networkMapUsesWholeRegionInitialView(158), isFalse, reason: '부산');
      expect(networkMapUsesWholeRegionInitialView(796), isFalse, reason: '수도권');
    });

    test('임계 40 경계', () {
      expect(networkMapUsesWholeRegionInitialView(40), isTrue);
      expect(networkMapUsesWholeRegionInitialView(41), isFalse);
    });
  });

  group(
    'networkMapInitialCameraForRegion(contain-fit 헬퍼)은 scale == initialScale',
    () {
      const viewport = Size(1080, 2000);
      // 대표 지역 bounds: 광주(초소형·세로 긴 1호선)~수도권(초대형 격자).
      const regions = <String, Rect>{
        '광주(초소형)': Rect.fromLTWH(0, 0, 300, 1500),
        '대전(소형)': Rect.fromLTWH(0, 0, 900, 700),
        '부산(중형)': Rect.fromLTWH(0, 0, 2000, 1600),
        '수도권(초대형)': Rect.fromLTWH(0, 0, 4000, 4400),
      };

      regions.forEach((label, bounds) {
        test('$label 주어진 bounds를 담는 배율이 LOD baseline이 된다', () {
          final camera = networkMapInitialCameraForRegion(
            regionBounds: bounds,
            fullBounds: bounds,
            viewport: viewport,
          );
          // 정적 스케일 렌더: 이 헬퍼가 만든 카메라는 넘긴 bounds가 그대로 담긴
          // contain-fit이고 그 배율이 LOD baseline(initialScale)이 된다.
          // #1789 전환 후 bucket 무관. (프로덕션 초기 카메라는 이 헬퍼에
          // networkMapInitialCameraBounds가 만든 bounds를 넘긴다 — 파일 상단 메모.)
          expect(camera.initialScale, isNotNull);
          expect(camera.initialScale, greaterThan(0));
          expect(camera.scale, camera.initialScale);
        });
      });
    },
  );
}
