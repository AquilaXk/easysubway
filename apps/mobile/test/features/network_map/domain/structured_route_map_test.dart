import 'package:easysubway_mobile/features/network_map/domain/structured_route_map.dart';
import 'package:flutter_test/flutter_test.dart';

StructuredRouteMapStationInput input({
  required String stationId,
  required String lineId,
  required int sequence,
  Offset position = Offset.zero,
  List<Offset> labelPolygon = const [],
  String downPath = '',
}) {
  return StructuredRouteMapStationInput(
    stationId: stationId,
    lineId: lineId,
    sequence: sequence,
    position: position,
    labelPolygon: labelPolygon,
    downPath: downPath,
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
    test('track polyline을 sequence 순서로 잇고 공유 정점을 중복 제거한다', () {
      final map = buildStructuredRouteMap([
        input(
          stationId: 's2',
          lineId: 'L1',
          sequence: 2,
          downPath: 'M 10 10 L 20 20',
        ),
        input(
          stationId: 's1',
          lineId: 'L1',
          sequence: 1,
          downPath: '', // 시점 역은 들어오는 세그먼트 없음
        ),
        input(
          stationId: 's3',
          lineId: 'L1',
          sequence: 3,
          downPath: 'M 20 20 L 30 30',
        ),
      ]);

      expect(map.lines, hasLength(1));
      expect(map.lines.single.polylines, hasLength(1));
      expect(map.lines.single.polylines.single, <Offset>[
        const Offset(10, 10),
        const Offset(20, 20),
        const Offset(30, 30),
      ]);
    });

    test('이어지지 않는 세그먼트(데이터 hole)에서 polyline을 끊는다', () {
      final map = buildStructuredRouteMap([
        input(stationId: 's1', lineId: 'L1', sequence: 1, downPath: ''),
        input(
          stationId: 's2',
          lineId: 'L1',
          sequence: 2,
          downPath: 'M 0 0 L 10 10',
        ),
        // s3 세그먼트가 (10,10)에서 이어지지 않고 (30,30)에서 시작 → 끊는다.
        input(
          stationId: 's3',
          lineId: 'L1',
          sequence: 3,
          downPath: 'M 30 30 L 40 40',
        ),
      ]);

      expect(map.lines.single.polylines, <List<Offset>>[
        [const Offset(0, 0), const Offset(10, 10)],
        [const Offset(30, 30), const Offset(40, 40)],
      ]);
    });

    test('sequence 동률이면 station_id로 결정적으로 정렬한다', () {
      final ordered = buildStructuredRouteMap([
        input(
          stationId: 'sb',
          lineId: 'L1',
          sequence: 1,
          downPath: 'M 5 5 L 6 6',
        ),
        input(
          stationId: 'sa',
          lineId: 'L1',
          sequence: 1,
          downPath: 'M 0 0 L 5 5',
        ),
      ]);
      // sa(먼저) → sb: (0,0)-(5,5)-(6,6) 하나로 이어진다.
      expect(ordered.lines.single.polylines.single, <Offset>[
        const Offset(0, 0),
        const Offset(5, 5),
        const Offset(6, 6),
      ]);
    });

    test('여러 노선에 속한 역을 환승 그룹으로 묶고 중심 좌표를 구한다', () {
      final map = buildStructuredRouteMap([
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
      ]);

      expect(map.transferGroups, hasLength(1));
      final group = map.transferGroups.single;
      expect(group.stationId, 's1');
      expect(group.lineIds, <String>['L1', 'L2']);
      expect(group.centroid, const Offset(5, 10));
    });

    test('환승역은 transfer, 단일 노선역은 regular class', () {
      final map = buildStructuredRouteMap([
        input(stationId: 's1', lineId: 'L1', sequence: 1),
        input(stationId: 's1', lineId: 'L2', sequence: 1),
        input(stationId: 's2', lineId: 'L1', sequence: 2),
      ]);

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
      expect(buildStructuredRouteMap(const []).isEmpty, isTrue);
    });
  });
}
