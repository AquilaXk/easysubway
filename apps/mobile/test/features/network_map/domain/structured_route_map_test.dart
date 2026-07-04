import 'dart:ui' show Offset;

import 'package:easysubway_mobile/features/network_map/domain/structured_route_map.dart';
import 'package:flutter_test/flutter_test.dart';

StructuredRouteMapStationInput station({
  required String stationId,
  required String lineId,
  int sequence = 0,
  Offset position = Offset.zero,
  List<Offset> labelPolygon = const [],
}) {
  return StructuredRouteMapStationInput(
    stationId: stationId,
    lineId: lineId,
    sequence: sequence,
    position: position,
    labelPolygon: labelPolygon,
  );
}

StructuredRouteMapEdgeInput edge(String lineId, String from, String to) {
  return StructuredRouteMapEdgeInput(lineId: lineId, fromKey: from, toKey: to);
}

void main() {
  group('buildStructuredRouteMap line geometry (topology)', () {
    test('각 RIDE 엣지를 인접 두 역 세그먼트로 만든다', () {
      final map = buildStructuredRouteMap(
        stations: [
          station(stationId: 's1', lineId: 'L1', position: const Offset(0, 0)),
          station(
            stationId: 's2',
            lineId: 'L1',
            position: const Offset(10, 0),
          ),
          station(
            stationId: 's3',
            lineId: 'L1',
            position: const Offset(20, 0),
          ),
        ],
        edges: [edge('L1', 's1:L1', 's2:L1'), edge('L1', 's2:L1', 's3:L1')],
      );
      expect(map.lines, hasLength(1));
      final segments = map.lines.single.polylines;
      expect(segments, <List<Offset>>[
        [const Offset(0, 0), const Offset(10, 0)],
        [const Offset(10, 0), const Offset(20, 0)],
      ]);
    });

    test('무방향 중복 엣지(A-B, B-A)는 한 번만 그린다', () {
      final map = buildStructuredRouteMap(
        stations: [
          station(stationId: 's1', lineId: 'L1', position: const Offset(0, 0)),
          station(
            stationId: 's2',
            lineId: 'L1',
            position: const Offset(10, 0),
          ),
        ],
        edges: [edge('L1', 's1:L1', 's2:L1'), edge('L1', 's2:L1', 's1:L1')],
      );
      expect(map.lines.single.polylines, hasLength(1));
    });

    test('분기(한 역에서 여러 인접)는 여러 세그먼트로 자연 표현된다', () {
      // s2에서 s1, s3, s4로 분기 → 세그먼트 3개(부채꼴 아님, 각자 짧은 인접).
      final map = buildStructuredRouteMap(
        stations: [
          station(stationId: 's1', lineId: 'L1', position: const Offset(0, 0)),
          station(
            stationId: 's2',
            lineId: 'L1',
            position: const Offset(10, 0),
          ),
          station(
            stationId: 's3',
            lineId: 'L1',
            position: const Offset(20, 5),
          ),
          station(
            stationId: 's4',
            lineId: 'L1',
            position: const Offset(20, -5),
          ),
        ],
        edges: [
          edge('L1', 's1:L1', 's2:L1'),
          edge('L1', 's2:L1', 's3:L1'),
          edge('L1', 's2:L1', 's4:L1'),
        ],
      );
      expect(map.lines.single.polylines, hasLength(3));
    });

    test('phantom(노선 median 대비 매우 긴) 세그먼트를 제외한다', () {
      // 길이 10짜리 인접 6개 + 먼 역으로 튀는 phantom 1개.
      final stations = [
        for (var i = 0; i <= 6; i++)
          station(
            stationId: 's$i',
            lineId: 'L1',
            position: Offset(i * 10, 0),
          ),
        station(stationId: 'far', lineId: 'L1', position: const Offset(1000, 0)),
      ];
      final edges = [
        for (var i = 0; i < 6; i++) edge('L1', 's$i:L1', 's${i + 1}:L1'),
        edge('L1', 's6:L1', 'far:L1'),
      ];
      final map = buildStructuredRouteMap(stations: stations, edges: edges);
      expect(map.lines.single.polylines, hasLength(6));
    });

    test('세그먼트가 균일하게 길면(GTX-A류) 보존한다', () {
      // 모두 길이 300 → median 300, threshold 1200, 아무것도 안 잘림.
      final stations = [
        for (var i = 0; i <= 5; i++)
          station(
            stationId: 'g$i',
            lineId: 'GTX',
            position: Offset(i * 300, 0),
          ),
      ];
      final edges = [
        for (var i = 0; i < 5; i++) edge('GTX', 'g$i:GTX', 'g${i + 1}:GTX'),
      ];
      final map = buildStructuredRouteMap(stations: stations, edges: edges);
      expect(map.lines.single.polylines, hasLength(5));
    });

    test('좌표를 못 찾는 엣지는 건너뛴다', () {
      final map = buildStructuredRouteMap(
        stations: [
          station(stationId: 's1', lineId: 'L1', position: const Offset(0, 0)),
        ],
        edges: [edge('L1', 's1:L1', 'missing:L1')],
      );
      expect(map.lines, isEmpty);
    });
  });

  group('buildStructuredRouteMap nodes/transfers/labels', () {
    test('여러 노선에 속한 역을 환승 그룹으로 묶고 중심 좌표를 구한다', () {
      final map = buildStructuredRouteMap(
        stations: [
          station(stationId: 's1', lineId: 'L1', position: Offset.zero),
          station(
            stationId: 's1',
            lineId: 'L2',
            position: const Offset(10, 20),
          ),
          station(
            stationId: 's2',
            lineId: 'L1',
            position: const Offset(100, 100),
          ),
        ],
        edges: const [],
      );
      expect(map.transferGroups, hasLength(1));
      final group = map.transferGroups.single;
      expect(group.stationId, 's1');
      expect(group.lineIds, <String>['L1', 'L2']);
      expect(group.centroid, const Offset(5, 10));
    });

    test('환승역은 transfer, 단일 노선역은 regular class + LOD', () {
      final map = buildStructuredRouteMap(
        stations: [
          station(stationId: 's1', lineId: 'L1'),
          station(stationId: 's1', lineId: 'L2'),
          station(stationId: 's2', lineId: 'L1'),
        ],
        edges: const [],
      );
      final transfer = map.stations.firstWhere((s) => s.stationId == 's1');
      final regular = map.stations.firstWhere((s) => s.stationId == 's2');
      expect(transfer.labelClass, RouteMapLabelClass.transfer);
      expect(regular.labelClass, RouteMapLabelClass.regular);
      expect(transfer.minLabelZoomBucket, 1);
      expect(regular.minLabelZoomBucket, 2);
    });

    test('LOD: transfer/major는 zoom1, regular는 zoom2', () {
      expect(minLabelZoomBucketFor(RouteMapLabelClass.transfer), 1);
      expect(minLabelZoomBucketFor(RouteMapLabelClass.major), 1);
      expect(minLabelZoomBucketFor(RouteMapLabelClass.regular), 2);
    });

    test('빈 입력은 빈 구조', () {
      expect(
        buildStructuredRouteMap(stations: const [], edges: const []).isEmpty,
        isTrue,
      );
    });
  });
}
