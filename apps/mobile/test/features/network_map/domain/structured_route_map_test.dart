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

void main() {
  group('buildStructuredRouteMap line geometry (좌표 MST)', () {
    test('선형 노선은 MST 체인으로 인접 세그먼트를 만든다', () {
      final map = buildStructuredRouteMap(
        stations: [
          for (var i = 0; i < 4; i += 1)
            station(
              stationId: 's$i',
              lineId: 'L1',
              position: Offset(i * 10.0, 0),
            ),
        ],
      );
      // 4역 체인 → 세그먼트 3개, 각 인접(길이 10).
      final segments = map.lines.single.polylines;
      expect(segments, hasLength(3));
      for (final segment in segments) {
        expect((segment[1] - segment[0]).distance, closeTo(10, 1e-9));
      }
    });

    test('분기 노선은 MST 트리로 표현된다(먼 역 직접 연결 없음)', () {
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
      );
      // 4역 트리 = 세그먼트 3개. 모든 세그먼트가 짧은 인접(부채꼴 없음).
      expect(map.lines.single.polylines, hasLength(3));
      for (final segment in map.lines.single.polylines) {
        expect((segment[1] - segment[0]).distance, lessThan(30));
      }
    });

    test('번호 순서가 물리 위치와 어긋나도 좌표로 올바르게 잇는다', () {
      // sequence는 뒤죽박죽이지만 좌표는 일렬 → MST가 좌표대로 체인.
      final map = buildStructuredRouteMap(
        stations: [
          station(
            stationId: 'a',
            lineId: 'L1',
            sequence: 99,
            position: const Offset(0, 0),
          ),
          station(
            stationId: 'b',
            lineId: 'L1',
            sequence: 1,
            position: const Offset(10, 0),
          ),
          station(
            stationId: 'c',
            lineId: 'L1',
            sequence: 50,
            position: const Offset(20, 0),
          ),
        ],
      );
      expect(map.lines.single.polylines, hasLength(2));
      for (final segment in map.lines.single.polylines) {
        expect((segment[1] - segment[0]).distance, closeTo(10, 1e-9));
      }
    });

    test('phantom(노선 median 대비 매우 긴) 세그먼트를 제외한다', () {
      // 촘촘한 역들 + 멀리 떨어진 outlier 1개. MST는 outlier를 마지막에 긴
      // 엣지로 붙이는데, phantom 필터가 그 긴 엣지를 제거한다.
      final map = buildStructuredRouteMap(
        stations: [
          for (var i = 0; i <= 6; i += 1)
            station(
              stationId: 's$i',
              lineId: 'L1',
              position: Offset(i * 10.0, 0),
            ),
          station(
            stationId: 'far',
            lineId: 'L1',
            position: const Offset(2000, 0),
          ),
        ],
      );
      // 촘촘한 7역 체인(6 세그먼트)은 남고 far로 가는 긴 엣지는 제외.
      expect(map.lines.single.polylines, hasLength(6));
    });

    test('세그먼트가 균일하게 길면(GTX-A류) 보존한다', () {
      final map = buildStructuredRouteMap(
        stations: [
          for (var i = 0; i <= 5; i += 1)
            station(
              stationId: 'g$i',
              lineId: 'GTX',
              position: Offset(i * 300.0, 0),
            ),
        ],
      );
      expect(map.lines.single.polylines, hasLength(5));
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
      expect(buildStructuredRouteMap(stations: const []).isEmpty, isTrue);
    });
  });
}
