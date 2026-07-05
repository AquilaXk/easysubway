import 'package:easysubway_mobile/features/network_map/presentation/route_map_transfer_marker.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('routeMapTransferMarker', () {
    test('노선 2개는 세로로 쌓인 도트와 이를 감싸는 캡슐을 만든다', () {
      final marker = routeMapTransferMarker(
        center: const Offset(100, 100),
        colors: const [Color(0xFF0052A4), Color(0xFF00A84D)],
        dotRadius: 3,
        dotGap: 2,
        padding: 2,
      );

      // 도트는 center 기준 세로 대칭. spacing(center-to-center)=2*3+2=8.
      expect(marker.dots, hasLength(2));
      expect(marker.dots[0].center, const Offset(100, 96));
      expect(marker.dots[1].center, const Offset(100, 104));
      expect(marker.dots[0].color, const Color(0xFF0052A4));
      expect(marker.dots[1].color, const Color(0xFF00A84D));

      // 캡슐: width=2*(3+2)=10, height=span(8)+2*3+2*2=18, 중심=center.
      expect(marker.capsule.width, 10);
      expect(marker.capsule.height, 18);
      expect(marker.capsule.center, const Offset(100, 100));
      // 스타디움(pill): corner radius = 가로 반폭.
      expect(marker.capsule.tlRadiusX, 5);
      expect(marker.capsule.blRadiusY, 5);
    });

    test('노선 1개는 도트 1개와 원형(정사각 캡슐)을 만든다', () {
      final marker = routeMapTransferMarker(
        center: const Offset(100, 100),
        colors: const [Color(0xFF0052A4)],
        dotRadius: 3,
        dotGap: 2,
        padding: 2,
      );

      expect(marker.dots, hasLength(1));
      expect(marker.dots[0].center, const Offset(100, 100));
      expect(marker.capsule.width, 10);
      expect(marker.capsule.height, 10);
      expect(marker.capsule.tlRadiusX, 5);
    });

    test('노선 3개는 균등 간격으로 배치되고 순서를 보존한다', () {
      final marker = routeMapTransferMarker(
        center: const Offset(0, 0),
        colors: const [Color(0xFF111111), Color(0xFF222222), Color(0xFF333333)],
        dotRadius: 3,
        dotGap: 2,
        padding: 2,
      );

      // span=(3-1)*8=16 → 도트 y: -8, 0, 8.
      expect(marker.dots.map((d) => d.center.dy), [-8, 0, 8]);
      expect(marker.dots.map((d) => d.color), const [
        Color(0xFF111111),
        Color(0xFF222222),
        Color(0xFF333333),
      ]);
      expect(marker.capsule.height, 16 + 6 + 4);
    });

    test('색이 없으면 도트 없이 빈 마커를 반환한다', () {
      final marker = routeMapTransferMarker(
        center: const Offset(5, 5),
        colors: const [],
        dotRadius: 3,
        dotGap: 2,
        padding: 2,
      );
      expect(marker.dots, isEmpty);
      expect(marker.capsule.width, 0);
      expect(marker.capsule.height, 0);
    });
  });
}
