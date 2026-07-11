import 'package:easysubway_mobile/features/routes/data/local_route_repository.dart';
import 'package:easysubway_mobile/features/routes/domain/route_result.dart';
import 'package:easysubway_mobile/features/routes/domain/route_step.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:flutter_test/flutter_test.dart';

RouteStep _ride({
  required int sequence,
  required String fromNodeId,
  required String toNodeId,
  String lineId = 'line-2',
  String servicePattern = 'inner',
  int cost = 100,
}) {
  return RouteStep(
    sequence: sequence,
    edgeId: 'edge-$fromNodeId-$toNodeId',
    fromNodeId: fromNodeId,
    toNodeId: toNodeId,
    type: RouteStepType.ride,
    cost: cost,
    durationSeconds: 60,
    lineId: lineId,
    servicePattern: servicePattern,
  );
}

RouteStep _exit({
  required int sequence,
  required String fromNodeId,
  required String toNodeId,
  int durationSeconds = 120,
  int cost = 50,
}) {
  return RouteStep(
    sequence: sequence,
    edgeId: 'edge-$fromNodeId-$toNodeId',
    fromNodeId: fromNodeId,
    toNodeId: toNodeId,
    type: RouteStepType.exit,
    cost: cost,
    durationSeconds: durationSeconds,
  );
}

RouteStep _entry({
  required int sequence,
  required String fromNodeId,
  required String toNodeId,
  int durationSeconds = 60,
  int cost = 50,
}) {
  return RouteStep(
    sequence: sequence,
    edgeId: 'edge-$fromNodeId-$toNodeId',
    fromNodeId: fromNodeId,
    toNodeId: toNodeId,
    type: RouteStepType.entry,
    cost: cost,
    durationSeconds: durationSeconds,
  );
}

LocalRouteResult _found({
  required List<RouteStep> steps,
  required int totalCost,
  List<RouteWarning> warnings = const [],
  List<String> blockedReasonCodes = const [],
}) {
  return LocalRouteResult(
    status: RouteStatus.found,
    totalCost: totalCost,
    steps: steps,
    warnings: warnings,
    blockedReasonCodes: blockedReasonCodes,
  );
}

void main() {
  group('mergeWaypointRouteResults', () {
    test('규칙1: 같은 노선·패턴·연결 노드여도 경계 마커가 두 승차를 갈라 놓는다', () {
      // first의 마지막 ride와 second의 첫 ride가 collapse 병합 조건(같은 lineId,
      // 같은 servicePattern, 연결 노드)을 모두 만족하도록 구성한다.
      final first = _found(
        steps: [_ride(sequence: 1, fromNodeId: 'a', toNodeId: 'b')],
        totalCost: 100,
      );
      final second = _found(
        steps: [_ride(sequence: 1, fromNodeId: 'b', toNodeId: 'c')],
        totalCost: 100,
      );

      final merged = mergeWaypointRouteResults(first, second);

      final waypointSteps = merged.steps
          .where((step) => step.type == RouteStepType.waypoint)
          .toList();
      expect(waypointSteps.length, 1);

      final markerIndex = merged.steps.indexWhere(
        (step) => step.type == RouteStepType.waypoint,
      );
      expect(markerIndex, greaterThan(0));
      expect(markerIndex, lessThan(merged.steps.length - 1));
      // 마커 앞뒤로 승차가 각각 남아 있어(2개) 하나로 병합되지 않는다.
      expect(merged.steps[markerIndex - 1].type, RouteStepType.ride);
      expect(merged.steps[markerIndex + 1].type, RouteStepType.ride);
      final rideCount = merged.steps
          .where((step) => step.type == RouteStepType.ride)
          .length;
      expect(rideCount, 2);
    });

    test('규칙1b: 경계에서 도착 하차 동선(exit)과 출발 진입 동선(entry)을 제거한다 (#1948)', () {
      final first = _found(
        steps: [
          _ride(sequence: 1, fromNodeId: 'a', toNodeId: 'b'),
          _exit(
            sequence: 2,
            fromNodeId: 'b',
            toNodeId: 'b',
            durationSeconds: 120,
          ),
        ],
        totalCost: 150,
      );
      final second = _found(
        steps: [
          _entry(
            sequence: 1,
            fromNodeId: 'c',
            toNodeId: 'c',
            durationSeconds: 60,
          ),
          _ride(sequence: 2, fromNodeId: 'c', toNodeId: 'd'),
        ],
        totalCost: 150,
      );

      final merged = mergeWaypointRouteResults(first, second);

      // 경계 접근 동선(exit/entry)은 제거된다.
      expect(
        merged.steps.any((step) => step.type == RouteStepType.exit),
        isFalse,
      );
      expect(
        merged.steps.any((step) => step.type == RouteStepType.entry),
        isFalse,
      );

      // ride 2개 + waypoint 마커 1개 = 3스텝.
      expect(merged.steps.length, 3);
      final markerIndex = merged.steps.indexWhere(
        (step) => step.type == RouteStepType.waypoint,
      );
      expect(markerIndex, 1);
      expect(merged.steps[markerIndex - 1].type, RouteStepType.ride);
      expect(merged.steps[markerIndex + 1].type, RouteStepType.ride);

      // 마커는 trim 후 first 마지막 toNodeId('b')를 가리킨다.
      final marker = merged.steps[markerIndex];
      expect(marker.fromNodeId, 'b');
      expect(marker.toNodeId, 'b');

      // 총 소요시간은 ride 2개 합(60+60)만 남고 접근 180초는 빠진다.
      final totalDuration = merged.steps.fold<int>(
        0,
        (sum, step) => sum + step.durationSeconds,
      );
      expect(totalDuration, 120);
    });

    test('규칙2: found+found는 found & 비용 합산', () {
      final first = _found(
        steps: [_ride(sequence: 1, fromNodeId: 'a', toNodeId: 'b')],
        totalCost: 100,
      );
      final second = _found(
        steps: [_ride(sequence: 1, fromNodeId: 'b', toNodeId: 'c')],
        totalCost: 250,
      );

      final merged = mergeWaypointRouteResults(first, second);

      expect(merged.status, RouteStatus.found);
      expect(merged.totalCost, 350);
    });

    test('규칙2: 한쪽 blocked면 전체 blocked', () {
      final found = _found(
        steps: [_ride(sequence: 1, fromNodeId: 'a', toNodeId: 'b')],
        totalCost: 100,
      );
      final blocked = LocalRouteResult.blocked(const ['NO_ELEVATOR']);

      expect(
        mergeWaypointRouteResults(found, blocked).status,
        RouteStatus.blocked,
      );
      expect(
        mergeWaypointRouteResults(blocked, found).status,
        RouteStatus.blocked,
      );
    });

    test('규칙2: 한쪽 unknown + 다른쪽 found면 전체 unknown', () {
      final found = _found(
        steps: [_ride(sequence: 1, fromNodeId: 'a', toNodeId: 'b')],
        totalCost: 100,
      );
      final unknown = LocalRouteResult.unknown(const ['ROUTE_GRAPH_UNKNOWN']);

      expect(
        mergeWaypointRouteResults(found, unknown).status,
        RouteStatus.unknown,
      );
      expect(
        mergeWaypointRouteResults(unknown, found).status,
        RouteStatus.unknown,
      );
    });

    test('규칙2: blockedReasonCodes와 warnings는 순서보존 dedup', () {
      final first = _found(
        steps: [_ride(sequence: 1, fromNodeId: 'a', toNodeId: 'b')],
        totalCost: 100,
        blockedReasonCodes: const ['X', 'Y'],
        warnings: const [
          RouteWarning(code: 'W1', message: '하나'),
          RouteWarning(code: 'W2', message: '둘'),
        ],
      );
      final second = _found(
        steps: [_ride(sequence: 1, fromNodeId: 'b', toNodeId: 'c')],
        totalCost: 100,
        blockedReasonCodes: const ['Y', 'Z'],
        warnings: const [
          RouteWarning(code: 'W2', message: '둘'),
          RouteWarning(code: 'W3', message: '셋'),
        ],
      );

      final merged = mergeWaypointRouteResults(first, second);

      expect(merged.blockedReasonCodes, ['X', 'Y', 'Z']);
      expect(merged.warnings.map((warning) => warning.code).toList(), [
        'W1',
        'W2',
        'W3',
      ]);
    });

    test('규칙3: found+found 병합 결과 sequence는 1..N 연속', () {
      final first = _found(
        steps: [
          _ride(sequence: 1, fromNodeId: 'a', toNodeId: 'b'),
          _ride(sequence: 2, fromNodeId: 'b', toNodeId: 'c'),
        ],
        totalCost: 200,
      );
      final second = _found(
        steps: [_ride(sequence: 1, fromNodeId: 'c', toNodeId: 'd')],
        totalCost: 100,
      );

      final merged = mergeWaypointRouteResults(first, second);

      final sequences = merged.steps.map((step) => step.sequence).toList();
      expect(sequences, [for (var i = 1; i <= merged.steps.length; i += 1) i]);
    });
  });

  group('경유 합성 요약 정합 가드 (#1948)', () {
    // mergeWaypointRouteResults가 삽입하는 경계 마커(RouteStepType.waypoint,
    // cost=0/durationSeconds=0/distanceMeters=0/lineId='')가 화면 요약
    // 계산(RouteSearchResult.estimatedDurationSeconds / transferCount)을
    // 왜곡하지 않는지 검증하는 가드. 여기서는 마커가 _toSteps를 거쳐 변환된
    // 뒤의 형태(stepType='waypoint', lineId='', lineName='',
    // estimatedMinutes=0)를 RouteSearchStep으로 직접 구성해 검증한다.
    test('총 소요시간 불변 가드: waypoint 마커는 시간 합산에 영향을 주지 않는다', () {
      // 구간1: ride 10분 + ride 5분 = 15분, 구간2: ride 8분 = 8분.
      // total은 두 구간 값의 합(15 + 8 = 23분)이어야 하며, 마커의 0분이 더해져도
      // 총합이 변하지 않아야 한다.
      final firstLegSteps = [
        _rideStep(sequence: 1, estimatedMinutes: 10),
        _rideStep(sequence: 2, estimatedMinutes: 5),
      ];
      final waypointMarker = _rideStep(
        sequence: 3,
        stepType: 'waypoint',
        lineId: '',
        lineName: '',
        estimatedMinutes: 0,
      );
      final secondLegSteps = [_rideStep(sequence: 4, estimatedMinutes: 8)];

      final withMarker = _result(
        steps: [...firstLegSteps, waypointMarker, ...secondLegSteps],
      );
      final withoutMarker = _result(
        steps: [...firstLegSteps, ...secondLegSteps],
      );

      // total은 두 구간 값의 합: (10 + 5 + 8) * 60초.
      expect(withMarker.estimatedDurationSeconds, (10 + 5 + 8) * 60);
      // 마커 포함 여부와 무관하게 총합이 동일해야 한다(마커의 0이 왜곡을 만들지 않음).
      expect(
        withMarker.estimatedDurationSeconds,
        withoutMarker.estimatedDurationSeconds,
      );
    });

    test('환승 수 가드: 경유 전후 같은 노선이면 환승이 0이다', () {
      // 구간1 line-2 ride 1개(환승 없음) + waypoint 마커 + 구간2 line-2 ride 1개.
      // waypoint는 환승 타입이 아니고, lineId/lineName이 비어 있어 폴백 lineId
      // 변화 카운트에서도 continue로 스킵되므로 환승 수는 0이어야 한다.
      final steps = [
        _rideStep(sequence: 1, lineId: 'line-2', lineName: '2호선'),
        _rideStep(
          sequence: 2,
          stepType: 'waypoint',
          lineId: '',
          lineName: '',
          estimatedMinutes: 0,
        ),
        _rideStep(sequence: 3, lineId: 'line-2', lineName: '2호선'),
      ];

      final result = _result(steps: steps);

      // total은 두 구간 값의 합: 0(구간1) + 0(구간2) = 0.
      expect(result.transferCount, 0);
    });

    test('환승 수 가드: 경유 전후 다른 노선이면 명시적 환승 스텝만 카운트된다', () {
      // 구간1: line-2 ride + transfer 1개, waypoint 마커,
      // 구간2: line-9 ride + transfer 1개.
      // _isRouteTransferStepType 우선 경로가 사용되어 명시적 transfer 스텝만
      // 카운트되고 waypoint는 포함되지 않아야 한다.
      final steps = [
        _rideStep(sequence: 1, lineId: 'line-2', lineName: '2호선'),
        _rideStep(
          sequence: 2,
          stepType: 'transfer',
          lineId: 'line-2',
          lineName: '2호선',
        ),
        _rideStep(
          sequence: 3,
          stepType: 'waypoint',
          lineId: '',
          lineName: '',
          estimatedMinutes: 0,
        ),
        _rideStep(sequence: 4, lineId: 'line-9', lineName: '9호선'),
        _rideStep(
          sequence: 5,
          stepType: 'transfer',
          lineId: 'line-9',
          lineName: '9호선',
        ),
      ];

      final result = _result(steps: steps);

      // total은 두 구간 값의 합: 1(구간1 transfer) + 1(구간2 transfer) = 2.
      expect(result.transferCount, 2);
    });
  });
}

RouteSearchStep _rideStep({
  required int sequence,
  String stepType = 'ride',
  String lineId = 'line-2',
  String lineName = '2호선',
  int estimatedMinutes = 5,
}) {
  return RouteSearchStep(
    sequence: sequence,
    stepType: stepType,
    title: 'step-$sequence',
    description: 'step-$sequence',
    lineId: lineId,
    lineName: lineName,
    fromStationId: 'station-from-$sequence',
    toStationId: 'station-to-$sequence',
    estimatedMinutes: estimatedMinutes,
    distanceMeters: 0,
    includesStairs: false,
    requiresAccessibilityCheck: false,
  );
}

RouteSearchResult _result({required List<RouteSearchStep> steps}) {
  return RouteSearchResult(
    routeSearchId: 'route-1',
    originStationId: 'origin',
    originStationName: '출발역',
    destinationStationId: 'destination',
    destinationStationName: '도착역',
    mobilityType: 'GENERAL',
    status: 'FOUND',
    lineId: '',
    lineName: '',
    score: 0,
    steps: steps,
    warnings: const [],
    blockedReasons: const [],
    createdAt: '',
  );
}
