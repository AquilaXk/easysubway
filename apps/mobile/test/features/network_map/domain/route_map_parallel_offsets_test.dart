import 'package:easysubway_mobile/features/network_map/domain/route_map_parallel_offsets.dart';
import 'package:easysubway_mobile/features/network_map/domain/structured_route_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('routeMapParallelLineOffsets', () {
    test('두 노선이 같은 수평 corridor를 공유하면 반대 수직 방향으로 갈린다', () {
      final offsets = routeMapParallelLineOffsets(const [
        RouteMapLineGeometry(
          lineId: 'A',
          polylines: [
            [Offset(0, 0), Offset(10, 0), Offset(20, 0)],
          ],
        ),
        RouteMapLineGeometry(
          lineId: 'B',
          polylines: [
            [Offset(0, 0), Offset(10, 0), Offset(20, 0)],
          ],
        ),
      ]);

      // 수평 corridor(tangent=(1,0)) → normal=(0,1). rank 정렬(A,B) → mult -0.5,+0.5.
      expect(offsets['A']!.first, const [
        Offset(0, -0.5),
        Offset(0, -0.5),
        Offset(0, -0.5),
      ]);
      expect(offsets['B']!.first, const [
        Offset(0, 0.5),
        Offset(0, 0.5),
        Offset(0, 0.5),
      ]);
    });

    test('공유하지 않는 노선은 모든 정점이 0 오프셋', () {
      final offsets = routeMapParallelLineOffsets(const [
        RouteMapLineGeometry(
          lineId: 'A',
          polylines: [
            [Offset(0, 0), Offset(10, 0)],
          ],
        ),
        RouteMapLineGeometry(
          lineId: 'B',
          polylines: [
            [Offset(0, 50), Offset(10, 50)],
          ],
        ),
      ]);

      expect(offsets['A']!.first, const [Offset.zero, Offset.zero]);
      expect(offsets['B']!.first, const [Offset.zero, Offset.zero]);
    });

    test('세 노선이 수직 corridor를 공유하면 -1/0/+1로 벌어진다', () {
      final offsets = routeMapParallelLineOffsets(const [
        RouteMapLineGeometry(
          lineId: 'A',
          polylines: [
            [Offset(5, 0), Offset(5, 10)],
          ],
        ),
        RouteMapLineGeometry(
          lineId: 'B',
          polylines: [
            [Offset(5, 0), Offset(5, 10)],
          ],
        ),
        RouteMapLineGeometry(
          lineId: 'C',
          polylines: [
            [Offset(5, 0), Offset(5, 10)],
          ],
        ),
      ]);

      // 수직 corridor(tangent=(0,1)) → normal=(-1,0). mult A=-1,B=0,C=+1.
      expect(offsets['A']!.first, const [Offset(1, 0), Offset(1, 0)]);
      expect(offsets['B']!.first, const [Offset.zero, Offset.zero]);
      expect(offsets['C']!.first, const [Offset(-1, 0), Offset(-1, 0)]);
    });

    test('공유 구간만 오프셋되고 단독 구간은 0 (분기에서 수렴)', () {
      // A: 공유 corridor(0,0)-(10,0) 뒤 단독으로 (20,0) 진행.
      // B: 공유 corridor(0,0)-(10,0) 뒤 단독으로 (10,10) 분기.
      final offsets = routeMapParallelLineOffsets(const [
        RouteMapLineGeometry(
          lineId: 'A',
          polylines: [
            [Offset(0, 0), Offset(10, 0), Offset(20, 0)],
          ],
        ),
        RouteMapLineGeometry(
          lineId: 'B',
          polylines: [
            [Offset(0, 0), Offset(10, 0), Offset(10, 10)],
          ],
        ),
      ]);

      // (0,0)·(10,0)은 공유 → 오프셋, 단독 정점 (20,0)/(10,10)은 0.
      expect(offsets['A']!.first[0], isNot(Offset.zero));
      expect(offsets['A']!.first[1], isNot(Offset.zero));
      expect(offsets['A']!.first[2], Offset.zero);
      expect(offsets['B']!.first[0], isNot(Offset.zero));
      expect(offsets['B']!.first[1], isNot(Offset.zero));
      expect(offsets['B']!.first[2], Offset.zero);
    });

    test('한 정점만 공유(교차)는 오프셋하지 않는다 — 평행 런 ≥2만', () {
      // 환승역 centroid 스냅으로 두 노선이 (10,10) 한 점만 공유하고 좌우로 갈림.
      // 단일 교차점을 오프셋하면 track에 kink가 생기므로 오프셋 0이어야 한다.
      final offsets = routeMapParallelLineOffsets(const [
        RouteMapLineGeometry(
          lineId: 'A',
          polylines: [
            [Offset(0, 10), Offset(10, 10), Offset(20, 10)],
          ],
        ),
        RouteMapLineGeometry(
          lineId: 'B',
          polylines: [
            [Offset(10, 0), Offset(10, 10), Offset(10, 20)],
          ],
        ),
      ]);

      expect(offsets['A']!.first, const [
        Offset.zero,
        Offset.zero,
        Offset.zero,
      ]);
      expect(offsets['B']!.first, const [
        Offset.zero,
        Offset.zero,
        Offset.zero,
      ]);
    });
  });
}
