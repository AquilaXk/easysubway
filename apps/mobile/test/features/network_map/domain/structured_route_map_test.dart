import 'package:easysubway_mobile/features/network_map/domain/structured_route_map.dart';
import 'package:flutter_test/flutter_test.dart';

StructuredRouteMapStationInput input({
  required String stationId,
  required String lineId,
  required int sequence,
  double x = 0,
  double y = 0,
  String upPath = '',
  String downPath = '',
  String labelPolygon = '',
}) {
  return StructuredRouteMapStationInput(
    stationId: stationId,
    lineId: lineId,
    sequence: sequence,
    x: x,
    y: y,
    upPath: upPath,
    downPath: downPath,
    labelPolygon: labelPolygon,
  );
}

void main() {
  group('parseRouteMapPath', () {
    test('절대 M/L 명령을 점 목록으로 파싱한다', () {
      expect(parseRouteMapPath('M 1623 1238 L 1744 1359'), <RouteMapPoint>[
        const RouteMapPoint(1623, 1238),
        const RouteMapPoint(1744, 1359),
      ]);
    });

    test('빈 문자열은 빈 목록', () {
      expect(parseRouteMapPath(''), isEmpty);
      expect(parseRouteMapPath('   '), isEmpty);
    });

    test('명령 문자를 건너뛰고 쉼표 구분도 처리한다', () {
      expect(parseRouteMapPath('M1,2 L3,4'), <RouteMapPoint>[
        const RouteMapPoint(1, 2),
        const RouteMapPoint(3, 4),
      ]);
    });

    test('짝이 맞지 않는 마지막 숫자는 버린다', () {
      expect(parseRouteMapPath('M 1 2 L 3'), <RouteMapPoint>[
        const RouteMapPoint(1, 2),
      ]);
    });
  });

  group('parseRouteMapLabelPolygon', () {
    test('JSON 폴리곤을 점 목록으로 파싱한다', () {
      const source = '[{"x":1741,"y":1348},{"x":1779,"y":1370}]';
      expect(parseRouteMapLabelPolygon(source), <RouteMapPoint>[
        const RouteMapPoint(1741, 1348),
        const RouteMapPoint(1779, 1370),
      ]);
    });

    test('빈/잘못된 입력은 빈 목록', () {
      expect(parseRouteMapLabelPolygon(''), isEmpty);
      expect(parseRouteMapLabelPolygon('not json'), isEmpty);
      expect(parseRouteMapLabelPolygon('{"x":1}'), isEmpty);
    });
  });

  group('buildStructuredRouteMap', () {
    test('노선 polyline을 sequence 순서로 잇고 공유 정점을 중복 제거한다', () {
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
          downPath: 'M 0 0 L 10 10',
        ),
      ]);

      expect(map.lines, hasLength(1));
      // sequence 1,2 순서로 세그먼트 연결: (0,0)-(10,10)-(20,20), 공유점 (10,10) 1회.
      expect(map.lines.single.downPolyline, <RouteMapPoint>[
        const RouteMapPoint(0, 0),
        const RouteMapPoint(10, 10),
        const RouteMapPoint(20, 20),
      ]);
    });

    test('여러 노선에 속한 역을 환승 그룹으로 묶고 중심 좌표를 구한다', () {
      final map = buildStructuredRouteMap([
        input(stationId: 's1', lineId: 'L1', sequence: 1, x: 0, y: 0),
        input(stationId: 's1', lineId: 'L2', sequence: 5, x: 10, y: 20),
        input(stationId: 's2', lineId: 'L1', sequence: 2, x: 100, y: 100),
      ]);

      expect(map.transferGroups, hasLength(1));
      final group = map.transferGroups.single;
      expect(group.stationId, 's1');
      expect(group.lineIds, <String>['L1', 'L2']);
      expect(group.centroid, const RouteMapPoint(5, 10));
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
    });

    test('LOD: transfer/major는 zoom1, regular는 zoom2에서 라벨 노출', () {
      expect(minLabelZoomBucketFor(RouteMapLabelClass.transfer), 1);
      expect(minLabelZoomBucketFor(RouteMapLabelClass.major), 1);
      expect(minLabelZoomBucketFor(RouteMapLabelClass.regular), 2);
    });

    test('빈 입력은 빈 구조', () {
      final map = buildStructuredRouteMap(const []);
      expect(map.isEmpty, isTrue);
    });
  });
}
