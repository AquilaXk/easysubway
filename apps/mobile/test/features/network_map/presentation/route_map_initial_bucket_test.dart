import 'dart:ui';

import 'package:easysubway_mobile/features/network_map/presentation/structured_route_map_painter.dart';
import 'package:easysubway_mobile/network_map.dart';
import 'package:flutter_test/flutter_test.dart';

// #1764 A: 초기 화면 카메라는 지역 크기와 무관하게 bucket 1 이어야 한다(역 노드·
// 환승/주요 라벨·노선 뱃지가 보이는 상태로 시작). 절대 scale 3분할이던 구현은
// 실사용 초기 구간이 전부 bucket 0에 묻혔다(#1764 문제 진단). initialScale 상대
// 배율 기준으로 바뀌었으므로, 대표 지역(초소형~초대형)에서 초기 bucket=1을 핀.
void main() {
  const viewport = Size(1080, 2000);

  // 대표 지역 bounds: 광주(초소형·세로 긴 1호선)~수도권(초대형 격자).
  const regions = <String, Rect>{
    '광주(초소형)': Rect.fromLTWH(0, 0, 300, 1500),
    '대전(소형)': Rect.fromLTWH(0, 0, 900, 700),
    '부산(중형)': Rect.fromLTWH(0, 0, 2000, 1600),
    '수도권(초대형)': Rect.fromLTWH(0, 0, 4000, 4400),
  };

  group('초기 카메라 bucket=1 보장 (지역별)', () {
    regions.forEach((label, bounds) {
      test('$label 초기 화면은 bucket 1', () {
        final camera = networkMapInitialCameraForRegion(
          regionBounds: bounds,
          fullBounds: bounds,
          viewport: viewport,
        );
        // 초기 카메라는 scale == initialScale (배율 1.0)이라 항상 bucket 1.
        expect(camera.initialScale, isNotNull);
        expect(camera.scale, camera.initialScale);
        expect(routeMapZoomBucket(camera), 1, reason: '$label 초기 bucket');
      });

      test('$label 초기 대비 축소/확대하면 bucket 0/2로 전이', () {
        final base = networkMapInitialCameraForRegion(
          regionBounds: bounds,
          fullBounds: bounds,
          viewport: viewport,
        );
        // 초기 대비 0.5배 축소 → bucket 0(선 실루엣).
        final zoomedOut = base.copyWith(scale: base.scale * 0.5);
        expect(routeMapZoomBucket(zoomedOut), 0, reason: '$label 축소 bucket');
        // 초기 대비 2배 확대 → bucket 2(전체 역 라벨).
        final zoomedIn = base.copyWith(scale: base.scale * 2.0);
        expect(routeMapZoomBucket(zoomedIn), 2, reason: '$label 확대 bucket');
      });
    });
  });
}
