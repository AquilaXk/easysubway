import 'package:easysubway_mobile/features/network_map/domain/structured_route_map.dart';
import 'package:flutter_test/flutter_test.dart';

StructuredRouteMapStationInput input({
  required String stationId,
  required String lineId,
  required int sequence,
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
  group('parseRouteMapPolyline', () {
    test('절대 M/L 명령을 정점 목록으로 파싱한다', () {
      expect(parseRouteMapPolyline('M 1623 1238 L 1744 1359'), <Offset>[
        const Offset(1623, 1238),
        const Offset(1744, 1359),
      ]);
    });

    test('빈 문자열은 빈 목록', () {
      expect(parseRouteMapPolyline(''), isEmpty);
      expect(parseRouteMapPolyline('   '), isEmpty);
    });

    test('명령 문자에 붙어 있어도 숫자만 추출한다', () {
      expect(parseRouteMapPolyline('M1,2 L3,4'), <Offset>[
        const Offset(1, 2),
        const Offset(3, 4),
      ]);
    });

    test('짝이 맞지 않는 마지막 숫자는 버린다', () {
      expect(parseRouteMapPolyline('M 1 2 L 3'), <Offset>[const Offset(1, 2)]);
    });
  });

  group('buildStructuredRouteMap', () {
    test('line geometry는 역 down_path가 아니라 line track에서 온다', () {
      final map = buildStructuredRouteMap(
        [input(stationId: 's1', lineId: 'line-a', sequence: 1)],
        lineTracks: const [
          RouteMapLineTrackInput(
            lineId: 'line-a',
            // 조각 2개는 phantom 직선 없이 분리 유지.
            paths: ['M 0 0 L 10 0 L 10 10', 'M 20 0 L 30 0'],
          ),
        ],
      );

      final geometry = map.lines.single;
      expect(geometry.lineId, 'line-a');
      expect(geometry.polylines, hasLength(2));
      expect(geometry.polylines.first, const <Offset>[
        Offset(0, 0),
        Offset(10, 0),
        Offset(10, 10),
      ]);
      expect(geometry.polylines[1], const <Offset>[
        Offset(20, 0),
        Offset(30, 0),
      ]);
    });

    test('정점이 2개 미만인 track 조각은 버린다', () {
      final map = buildStructuredRouteMap(
        [input(stationId: 's1', lineId: 'line-a', sequence: 1)],
        lineTracks: const [
          RouteMapLineTrackInput(
            lineId: 'line-a',
            paths: ['M 0 0', 'M 0 0 L 10 0'], // 첫 조각은 정점 1개 → 제외
          ),
        ],
      );

      expect(map.lines.single.polylines, hasLength(1));
    });

    test('역이 있어도 track이 없는 노선은 빈 polylines', () {
      final map = buildStructuredRouteMap(
        [input(stationId: 's1', lineId: 'line-a', sequence: 1)],
        lineTracks: const [],
      );

      expect(map.lines.single.lineId, 'line-a');
      expect(map.lines.single.polylines, isEmpty);
    });

    test('track만 있고 역이 없는 노선도 그린다', () {
      final map = buildStructuredRouteMap(
        const [],
        lineTracks: const [
          RouteMapLineTrackInput(lineId: 'line-b', paths: ['M 0 0 L 1 0']),
        ],
      );

      expect(map.lines.single.lineId, 'line-b');
      expect(map.lines.single.polylines, hasLength(1));
    });

    test('여러 노선에 속한 역을 환승 그룹으로 묶고 중심 좌표를 구한다', () {
      final map = buildStructuredRouteMap(
        [
          input(
            stationId: 's1',
            lineId: 'L1',
            sequence: 1,
            position: Offset.zero,
          ),
          input(
            stationId: 's1',
            lineId: 'L2',
            sequence: 5,
            position: const Offset(10, 20),
          ),
          input(
            stationId: 's2',
            lineId: 'L1',
            sequence: 2,
            position: const Offset(100, 100),
          ),
        ],
        lineTracks: const [],
      );

      expect(map.transferGroups, hasLength(1));
      final group = map.transferGroups.single;
      expect(group.stationId, 's1');
      expect(group.lineIds, <String>['L1', 'L2']);
      expect(group.centroid, const Offset(5, 10));
    });

    test('환승역은 transfer, 단일 노선역은 regular class', () {
      final map = buildStructuredRouteMap(
        [
          input(stationId: 's1', lineId: 'L1', sequence: 1),
          input(stationId: 's1', lineId: 'L2', sequence: 1),
          input(stationId: 's2', lineId: 'L1', sequence: 2),
        ],
        lineTracks: const [],
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
        buildStructuredRouteMap(const [], lineTracks: const []).isEmpty,
        isTrue,
      );
    });
  });
}
