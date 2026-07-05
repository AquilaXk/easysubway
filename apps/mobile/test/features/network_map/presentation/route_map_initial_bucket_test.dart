import 'dart:ui';

import 'package:easysubway_mobile/features/network_map/presentation/structured_route_map_painter.dart';
import 'package:easysubway_mobile/network_map.dart';
import 'package:flutter_test/flutter_test.dart';

// #1789 LOD: 초기 화면 카메라는 지역 크기와 무관하게 bucket 0(선 실루엣만)이어야
// 한다 — 고정 크기 노드·환승 캡슐·역명이 촘촘한 노선을 덮지 않도록. 확대할수록
// 캡슐·뱃지(1.5배, bucket 1) → 역 노드·역명(3배, bucket 2)이 단계적으로 나타난다.
// 대표 지역(초소형~초대형)에서 초기 bucket=0과 전이 배율을 핀.
void main() {
  const viewport = Size(1080, 2000);

  // 대표 지역 bounds: 광주(초소형·세로 긴 1호선)~수도권(초대형 격자).
  const regions = <String, Rect>{
    '광주(초소형)': Rect.fromLTWH(0, 0, 300, 1500),
    '대전(소형)': Rect.fromLTWH(0, 0, 900, 700),
    '부산(중형)': Rect.fromLTWH(0, 0, 2000, 1600),
    '수도권(초대형)': Rect.fromLTWH(0, 0, 4000, 4400),
  };

  group('초기 카메라 bucket=0 보장 (지역별)', () {
    regions.forEach((label, bounds) {
      test('$label 초기 화면은 bucket 0 (선만)', () {
        final camera = networkMapInitialCameraForRegion(
          regionBounds: bounds,
          fullBounds: bounds,
          viewport: viewport,
        );
        // 초기 카메라는 scale == initialScale (배율 1.0)이라 항상 bucket 0.
        expect(camera.initialScale, isNotNull);
        expect(camera.scale, camera.initialScale);
        expect(routeMapZoomBucket(camera), 0, reason: '$label 초기 bucket');
      });

      test('$label 확대하면 bucket 1(1.5배)→2(3배)로 전이', () {
        final base = networkMapInitialCameraForRegion(
          regionBounds: bounds,
          fullBounds: bounds,
          viewport: viewport,
        );
        // 초기 대비 1.5배 확대 → bucket 1(환승 캡슐·뱃지).
        final mid = base.copyWith(scale: base.scale * 1.5);
        expect(routeMapZoomBucket(mid), 1, reason: '$label 중간 bucket');
        // 초기 대비 3배 확대 → bucket 2(전체 역 라벨·노드).
        final zoomedIn = base.copyWith(scale: base.scale * 3.0);
        expect(routeMapZoomBucket(zoomedIn), 2, reason: '$label 확대 bucket');
      });
    });
  });
}
