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

    test('거의 닫힌 순환 track은 시작점을 이어붙여 폐합한다 (#2068)', () {
      // 시작-끝 간격(38.2)이 자기 bbox 대각선(813.8)의 0.25 미만 → 폐합 대상
      // (수도권 2호선 track0 실측 비율 0.047 재현).
      final map = buildStructuredRouteMap(
        const [],
        lineTracks: const [
          RouteMapLineTrackInput(
            lineId: 'loop-line',
            paths: [
              'M 1061.05 830.001 L 700 500 L 700 1100 L 1099.267 830.003',
            ],
          ),
        ],
      );
      final poly = map.lines.single.polylines.single;
      expect(poly.length, 5); // 원 4정점 + 폐합점.
      expect(poly.last, poly.first);
      expect(poly.first, const Offset(1061.05, 830.001));
    });

    test('시작-끝이 이미 같은 폐곡선은 그대로 둔다 (중복 폐합 방지)', () {
      final map = buildStructuredRouteMap(
        const [],
        lineTracks: const [
          RouteMapLineTrackInput(
            lineId: 'closed-line',
            paths: ['M 0 0 L 10 0 L 10 10 L 0 0'],
          ),
        ],
      );
      expect(map.lines.single.polylines.single, hasLength(4));
    });

    test('열린 선형(비순환) track은 폐합하지 않는다 — 시작-끝 간격이 규모에 비례', () {
      // 수도권 6호선 실측 비율(0.918)류: 시작-끝 간격이 bbox 대각선의 상당
      // 비율 — 순환 폐합 후보가 아니다.
      final map = buildStructuredRouteMap(
        const [],
        lineTracks: const [
          RouteMapLineTrackInput(
            lineId: 'linear-line',
            paths: ['M 0 0 L 50 50 L 100 0'],
          ),
        ],
      );
      expect(map.lines.single.polylines.single, hasLength(3));
    });

    test('역이 있어도 track이 없는 노선은 빈 polylines', () {
      final map = buildStructuredRouteMap([
        input(stationId: 's1', lineId: 'line-a', sequence: 1),
      ], lineTracks: const []);

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
      ], lineTracks: const []);

      expect(map.transferGroups, hasLength(1));
      final group = map.transferGroups.single;
      expect(group.stationId, 's1');
      expect(group.lineIds, <String>['L1', 'L2']);
      expect(group.centroid, const Offset(5, 10));
    });

    test('환승 그룹은 lineIds 순서와 정렬된 멤버 좌표를 노출한다', () {
      final map = buildStructuredRouteMap([
        input(
          stationId: 's1',
          lineId: 'line-b',
          sequence: 1,
          position: const Offset(10, 0),
        ),
        input(
          stationId: 's1',
          lineId: 'line-a',
          sequence: 1,
          position: Offset.zero,
        ),
      ], lineTracks: const []);
      final group = map.transferGroups.single;
      expect(group.lineIds, ['line-a', 'line-b']);
      expect(group.memberPositions, const [Offset(0, 0), Offset(10, 0)]);
      expect(group.centroid, const Offset(5, 0));
    });

    test('환승역은 transfer, 단일 노선 중간역은 regular, 종점은 major', () {
      final map = buildStructuredRouteMap([
        input(stationId: 's1', lineId: 'L1', sequence: 1),
        input(stationId: 's1', lineId: 'L2', sequence: 1),
        input(stationId: 's2', lineId: 'L1', sequence: 2), // 단일·중간
        input(stationId: 's3', lineId: 'L1', sequence: 3), // 단일·종점
      ], lineTracks: const []);

      final transfer = map.stations.firstWhere((s) => s.stationId == 's1');
      final regular = map.stations.firstWhere((s) => s.stationId == 's2');
      final terminal = map.stations.firstWhere((s) => s.stationId == 's3');
      // s1은 L1 종점(seq 최소)이지만 환승이라 transfer가 우선한다.
      expect(transfer.labelClass, RouteMapLabelClass.transfer);
      expect(regular.labelClass, RouteMapLabelClass.regular);
      expect(terminal.labelClass, RouteMapLabelClass.major);
    });

    test('노선 양 종점은 major(자동), 환승은 transfer 우선', () {
      final map = buildStructuredRouteMap([
        input(stationId: 'a', lineId: 'L1', sequence: 5), // 최소 seq=종점
        input(stationId: 'b', lineId: 'L1', sequence: 7),
        input(stationId: 'c', lineId: 'L1', sequence: 9), // 최대 seq=종점
      ], lineTracks: const []);
      RouteMapLabelClass cls(String id) =>
          map.stations.firstWhere((s) => s.stationId == id).labelClass;
      expect(cls('a'), RouteMapLabelClass.major);
      expect(cls('b'), RouteMapLabelClass.regular);
      expect(cls('c'), RouteMapLabelClass.major);
    });

    test('거점 allowlist(majorStationIds) 역은 major, 단 환승이면 transfer 우선', () {
      final map = buildStructuredRouteMap(
        [
          input(stationId: 'start', lineId: 'L1', sequence: 1),
          input(stationId: 'hub', lineId: 'L1', sequence: 2), // 중간·거점
          input(stationId: 'end', lineId: 'L1', sequence: 3),
          input(stationId: 'x', lineId: 'L1', sequence: 4),
          input(stationId: 'x', lineId: 'L2', sequence: 1), // 환승·거점
        ],
        lineTracks: const [],
        majorStationIds: const {'hub', 'x'},
      );
      RouteMapLabelClass cls(String id) =>
          map.stations.firstWhere((s) => s.stationId == id).labelClass;
      // 중간역이지만 allowlist라 major.
      expect(cls('hub'), RouteMapLabelClass.major);
      // allowlist이자 환승이면 transfer가 우선(major 아님).
      expect(cls('x'), RouteMapLabelClass.transfer);
    });

    test('순환선(양 극점 인접)은 종점 major를 만들지 않는다', () {
      // seq 1..4 루프: 극점 s1(seq1)·s4(seq4)이 노선 span 대비 가깝다(루프 닫힘).
      final map = buildStructuredRouteMap([
        input(
          stationId: 's1',
          lineId: 'loop',
          sequence: 1,
          position: Offset(100, 100),
        ),
        input(
          stationId: 's2',
          lineId: 'loop',
          sequence: 2,
          position: Offset(300, 100),
        ),
        input(
          stationId: 's3',
          lineId: 'loop',
          sequence: 3,
          position: Offset(300, 300),
        ),
        input(
          stationId: 's4',
          lineId: 'loop',
          sequence: 4,
          position: Offset(106, 106),
        ),
      ], lineTracks: const []);
      for (final station in map.stations) {
        expect(
          station.labelClass,
          RouteMapLabelClass.regular,
          reason: '${station.stationId}: 순환선은 종점 major 없음',
        );
      }
    });

    test('sequence 동률 종점(분기)은 극값 역을 모두 major로 포함', () {
      final map = buildStructuredRouteMap([
        input(
          stationId: 'trunk',
          lineId: 'L',
          sequence: 1,
          position: Offset(0, 0),
        ),
        input(
          stationId: 'mid',
          lineId: 'L',
          sequence: 2,
          position: Offset(200, 0),
        ),
        input(
          stationId: 'branchA',
          lineId: 'L',
          sequence: 3,
          position: Offset(400, 0),
        ),
        input(
          stationId: 'branchB',
          lineId: 'L',
          sequence: 3,
          position: Offset(400, 200),
        ),
      ], lineTracks: const []);
      RouteMapLabelClass cls(String id) =>
          map.stations.firstWhere((s) => s.stationId == id).labelClass;
      expect(cls('trunk'), RouteMapLabelClass.major); // seq 최소 극값
      expect(cls('branchA'), RouteMapLabelClass.major); // seq 최대 극값
      expect(cls('branchB'), RouteMapLabelClass.major); // 동률 극값도 포함
      expect(cls('mid'), RouteMapLabelClass.regular);
    });

    test('빈 입력은 빈 구조', () {
      expect(
        buildStructuredRouteMap(const [], lineTracks: const []).isEmpty,
        isTrue,
      );
    });
  });

  group('종착역 파생 (#1789 볼드 스타일)', () {
    RouteMapStructuredStation station(
      String id,
      String lineId,
      int seq,
      Offset pos,
    ) => RouteMapStructuredStation(
      stationId: id,
      lineId: lineId,
      sequence: seq,
      position: pos,
      labelPolygon: const [],
      labelClass: RouteMapLabelClass.regular,
    );

    test('노선별 sequence 양 끝 역이 종착', () {
      final map = StructuredRouteMap(
        lines: const [],
        stations: [
          station('a', 'L1', 1, const Offset(0, 0)),
          station('b', 'L1', 2, const Offset(10, 0)),
          station('c', 'L1', 3, const Offset(20, 0)),
        ],
        transferGroups: const [],
      );
      expect(routeMapTerminusStationIds(map), {'a', 'c'});
    });

    test('순환선(시·종점 좌표 동일)은 종착 없음', () {
      final map = StructuredRouteMap(
        lines: const [],
        stations: [
          station('a', 'L2', 1, const Offset(0, 0)),
          station('b', 'L2', 2, const Offset(10, 0)),
          station('a2', 'L2', 3, const Offset(0, 0)),
        ],
        transferGroups: const [],
      );
      expect(routeMapTerminusStationIds(map), isEmpty);
    });
  });
}
