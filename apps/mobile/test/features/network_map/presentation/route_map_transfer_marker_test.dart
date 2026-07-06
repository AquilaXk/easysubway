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

    test('horizontalDots=true는 도트를 가로로 쌓고 가로 캡슐을 만든다', () {
      const dotRadius = 3.0;
      const dotGap = 2.0;
      const padding = 2.0;
      final marker = routeMapTransferMarker(
        center: const Offset(100, 100),
        colors: const [Color(0xFF0052A4), Color(0xFF00A84D)],
        dotRadius: dotRadius,
        dotGap: dotGap,
        padding: padding,
        horizontalDots: true,
      );

      // 두 도트는 같은 dy, dx는 center-to-center = 2*dotRadius+dotGap 만큼 벌어짐.
      expect(marker.dots, hasLength(2));
      expect(marker.dots[0].center.dy, marker.dots[1].center.dy);
      expect(
        marker.dots[1].center.dx - marker.dots[0].center.dx,
        2 * dotRadius + dotGap,
      );

      // 캡슐: 가로가 세로보다 길고, 세로(짧은축) = 2*(dotRadius+padding).
      expect(marker.capsule.width, greaterThan(marker.capsule.height));
      expect(marker.capsule.height, 2 * (dotRadius + padding));
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

  group('모드 임계 (design px, #1789 캡슐 통일)', () {
    const dot = kRouteMapTransferDotRadiusPx;
    const gap = kRouteMapTransferDotGapPx;
    const pad = kRouteMapTransferDotPaddingPx;
    const standardWidth = 2 * (dot + pad); // 8.0 — 모든 비스팬 캡슐의 폭 계약

    List<RouteMapTransferMarker> markersFor(double spread) =>
        routeMapTransferMarkers(
          memberCenters: [Offset.zero, Offset(spread, 0)],
          colors: const [Color(0xFF111111), Color(0xFF222222)],
          designSpread: spread,
          dotRadius: dot,
          dotGap: gap,
          padding: pad,
        );

    test('스팬 상한(16) 초과 이격은 centroid 고정 크기 스택으로 강등', () {
      final markers = markersFor(20.0); // 16 < 20 <= 28
      expect(markers.length, 1);
      final capsule = markers.single.capsule.outerRect;
      expect(capsule.width, standardWidth); // 표준 폭 — 이격과 무관
      expect(capsule.center.dx, 10.0); // 멤버 평균
      expect(capsule.center.dy, 0.0);
    });

    test('스팬 캡슐 긴축은 상한 내(≤ spanMax + 표준 폭)', () {
      final markers = markersFor(15.0); // 8 < 15 <= 16 → 스팬 유지
      final capsule = markers.single.capsule.outerRect;
      expect(capsule.width, lessThanOrEqualTo(16.0 + standardWidth));
      expect(capsule.height, standardWidth); // 수평 스팬의 짧은축 = 표준 폭
    });

    test('분리 모드는 separateMin(28) 초과에서만', () {
      expect(markersFor(28.0).length, 1); // 강등 스택
      expect(markersFor(28.1).length, 2); // 분리 (오병합 의심 — 정직 표현)
    });

    test('강등 스택 캡슐도 도트는 노선 수만큼 세로 스택', () {
      final markers = markersFor(20.0);
      expect(markers.single.dots.length, 2);
      expect(
        markers.single.dots[0].center.dx,
        markers.single.dots[1].center.dx,
      );
    });
  });

  test('offsetsMaxPairwiseDistance', () {
    expect(offsetsMaxPairwiseDistance(const []), 0);
    expect(offsetsMaxPairwiseDistance(const [Offset(1, 1)]), 0);
    expect(
      offsetsMaxPairwiseDistance(const [
        Offset(0, 0),
        Offset(3, 4),
        Offset(1, 0),
      ]),
      5,
    );
  });

  group('routeMapTransferRings (서울메트로 흰 원)', () {
    test('수렴 멤버는 centroid 흰 원 1개, 연결선 없음', () {
      final m = routeMapTransferRings(
        members: const [Offset(100, 100), Offset(100, 100)],
      );
      expect(m.rings, hasLength(1));
      expect(m.rings.single.center, const Offset(100, 100));
      expect(m.connectors, isEmpty);
    });

    test('소분산(< 2*radius) 멤버도 centroid 원 1개', () {
      final m = routeMapTransferRings(
        members: const [Offset(100, 100), Offset(104, 100)],
        radius: 6,
      );
      expect(m.rings, hasLength(1));
      expect(m.rings.single.center, const Offset(102, 100));
      expect(m.connectors, isEmpty);
    });

    test('대분산(>= 2*radius) 멤버는 멤버별 원 + centroid 연결선', () {
      final m = routeMapTransferRings(
        members: const [Offset(0, 0), Offset(100, 0)],
        radius: 6,
      );
      expect(m.rings, hasLength(2));
      expect(
        m.rings.map((r) => r.center),
        containsAll(const [Offset(0, 0), Offset(100, 0)]),
      );
      expect(m.connectors, hasLength(2));
      // 각 연결선의 끝점은 centroid.
      for (final c in m.connectors) {
        expect(c.last, const Offset(50, 0));
      }
    });

    test('멤버 0개는 빈 마커', () {
      final m = routeMapTransferRings(members: const []);
      expect(m.rings, isEmpty);
      expect(m.connectors, isEmpty);
    });
  });
}
