import 'package:easysubway_mobile/network_map.dart';
import 'package:flutter_test/flutter_test.dart';

// #1764 E: 소규모 지역(역 수 임계 이하)은 초기 화면을 전체 조망으로, 대형 지역은
// 도심 확대로 연다. 판정은 networkMapUsesWholeRegionInitialView 단일 소스를 쓴다.
// (LOD zoom bucket 산정은 #1789 정적 스케일 렌더 전환에서 폐지됐고, 초기 조망
// 판정만 역 수 임계로 남았다 — 구 route_map_initial_bucket_test에서 이관.)
void main() {
  group('소규모 지역 초기 전체 조망 (#1764 E)', () {
    test('광주·대전은 전체 조망, 부산·대구·수도권은 도심 확대', () {
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
}
