import 'package:easysubway_mobile/features/routes/data/local_route_repository.dart';
import 'package:easysubway_mobile/features/routes/domain/route_result.dart';
import 'package:easysubway_mobile/features/routes/domain/route_step.dart';
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
    test(
      '규칙1: 같은 노선·패턴·연결 노드여도 경계 마커가 두 승차를 갈라 놓는다',
      () {
        // first의 마지막 ride와 second의 첫 ride가 collapse 병합 조건(같은 lineId,
        // 같은 servicePattern, 연결 노드)을 모두 만족하도록 구성한다.
        final first = _found(
          steps: [
            _ride(sequence: 1, fromNodeId: 'a', toNodeId: 'b'),
          ],
          totalCost: 100,
        );
        final second = _found(
          steps: [
            _ride(sequence: 1, fromNodeId: 'b', toNodeId: 'c'),
          ],
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
      },
    );

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
      expect(
        merged.warnings.map((warning) => warning.code).toList(),
        ['W1', 'W2', 'W3'],
      );
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
        steps: [
          _ride(sequence: 1, fromNodeId: 'c', toNodeId: 'd'),
        ],
        totalCost: 100,
      );

      final merged = mergeWaypointRouteResults(first, second);

      final sequences = merged.steps.map((step) => step.sequence).toList();
      expect(sequences, [
        for (var i = 1; i <= merged.steps.length; i += 1) i,
      ]);
    });
  });
}
