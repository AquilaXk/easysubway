import 'package:easysubway_mobile/features/routes/application/network_graph.dart';
import 'package:easysubway_mobile/features/routes/application/route_engine.dart';
import 'package:easysubway_mobile/features/routes/domain/route_request.dart';
import 'package:easysubway_mobile/features/routes/domain/route_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalRouteEngine', () {
    test('상록수에서 사당까지 직통 경로를 서버 fixture와 같은 도메인 결과로 계산한다', () {
      final engine = LocalRouteEngine(graph: _capitalFixtureGraph());

      final result = engine.search(
        const RouteRequest(
          originStationId: 'station-sangnoksu',
          destinationStationId: 'station-sadang',
          mobilityType: MobilityType.wheelchair,
        ),
      );

      expect(result.status, RouteStatus.found);
      expect(result.lineIds, ['seoul-4']);
      expect(result.transferStationIds, isEmpty);
      expect(result.edgeIds, [
        'entry-sangnoksu-step-free',
        'ride-sangnoksu-sadang-line4',
        'exit-sadang-step-free',
      ]);
      expect(result.totalCost, 594);
      expect(result.includesStairs, isFalse);
      expect(result.blockedReasonCodes, isEmpty);
      expect(result.warningCodes, isEmpty);
    });

    test('1회 환승 경로는 사용 노선과 환승역, 환승 패널티를 결과에 포함한다', () {
      final engine = LocalRouteEngine(graph: _capitalFixtureGraph());

      final result = engine.search(
        const RouteRequest(
          originStationId: 'station-sangnoksu',
          destinationStationId: 'station-cityhall',
          mobilityType: MobilityType.senior,
        ),
      );

      expect(result.status, RouteStatus.found);
      expect(result.lineIds, ['seoul-4', 'seoul-2']);
      expect(result.transferStationIds, ['station-sadang']);
      expect(result.edgeIds, [
        'entry-sangnoksu-step-free',
        'ride-sangnoksu-sadang-line4',
        'transfer-sadang-line4-line2',
        'ride-sadang-cityhall-line2',
        'exit-cityhall-step-free',
      ]);
      expect(result.totalCost, 1290);
      expect(result.includesStairs, isFalse);
    });

    test('access graph contract는 진입, 환승, 진출 시간을 분리한다', () {
      final router = AccessGraphRouter(graph: _capitalFixtureGraph());

      final result = router.findPath(
        originNodeId: 'station-sangnoksu',
        destinationNodeId: 'station-cityhall',
        mobilityType: MobilityType.senior,
        constraintMode: ConstraintMode.preferStepFree,
      );
      final path = result.path!;
      final transfer = const TransferAccessResolver().resolve(
        path: path,
        alightAtSeconds: 600,
        nextDepartureSeconds: 780,
      );

      expect(path.edgeIds, [
        'entry-sangnoksu-step-free',
        'ride-sangnoksu-sadang-line4',
        'transfer-sadang-line4-line2',
        'ride-sadang-cityhall-line2',
        'exit-cityhall-step-free',
      ]);
      expect(path.entrySeconds, 90);
      expect(path.transferSeconds, 140);
      expect(path.egressSeconds, 90);
      expect(
        path.evidenceSources,
        contains('edge:transfer-sadang-line4-line2'),
      );
      expect(transfer.transferReadyAtSeconds, 740);
      expect(transfer.slackSeconds, 40);
      expect(transfer.isFeasible, isTrue);
    });

    test('access graph no-path reason은 차단, 미확인, 데이터 없음으로 분리된다', () {
      final blocked = AccessGraphRouter(graph: _stairOnlyFixtureGraph())
          .findPath(
            originNodeId: 'station-sangnoksu',
            destinationNodeId: 'station-sadang',
            mobilityType: MobilityType.wheelchair,
            constraintMode: ConstraintMode.strictStepFree,
          );
      final unknown =
          AccessGraphRouter(graph: _generatedConnectorFixtureGraph()).findPath(
            originNodeId: 'station-a',
            destinationNodeId: 'station-b',
            mobilityType: MobilityType.stroller,
            constraintMode: ConstraintMode.strictStepFree,
          );
      final noData =
          AccessGraphRouter(
            graph: NetworkGraph(nodes: const [], edges: const []),
          ).findPath(
            originNodeId: 'station-a',
            destinationNodeId: 'station-b',
            mobilityType: MobilityType.stroller,
            constraintMode: ConstraintMode.strictStepFree,
          );

      expect(blocked.noPathReason, AccessNoPathReason.blocked);
      expect(blocked.reasonCodes, ['STAIR_ONLY_ACCESS']);
      expect(unknown.noPathReason, AccessNoPathReason.unknown);
      expect(unknown.reasonCodes, ['GENERATED_CONNECTOR_UNVERIFIED']);
      expect(noData.noPathReason, AccessNoPathReason.noData);
      expect(noData.reasonCodes, ['NO_DATA']);
    });

    test('2회 환승 경로는 catalog transfer edge에서 환승역 순서를 보존한다', () {
      final engine = LocalRouteEngine(graph: _twoTransferCatalogFixtureGraph());

      final result = engine.search(
        const RouteRequest(
          originStationId: 'station-a',
          destinationStationId: 'station-d',
          mobilityType: MobilityType.senior,
        ),
      );

      expect(result.status, RouteStatus.found);
      expect(result.lineIds, ['line-1', 'line-2', 'line-3']);
      expect(result.transferStationIds, ['station-b', 'station-c']);
      expect(result.edgeIds, [
        'entry-a-line-1',
        'ride-a-b-line-1',
        'transfer-b-line-1-line-2',
        'ride-b-c-line-2',
        'transfer-c-line-2-line-3',
        'ride-c-d-line-3',
        'exit-d-line-3',
      ]);
    });

    test('같은 노선 또는 다른 역 transfer edge는 환승역으로 보존하지 않는다', () {
      final sameLineResult =
          LocalRouteEngine(
            graph: _sameLineTransferCatalogFixtureGraph(),
          ).search(
            const RouteRequest(
              originStationId: 'station-a',
              destinationStationId: 'station-b',
              mobilityType: MobilityType.senior,
            ),
          );
      final crossStationResult =
          LocalRouteEngine(
            graph: _crossStationTransferCatalogFixtureGraph(),
          ).search(
            const RouteRequest(
              originStationId: 'station-a',
              destinationStationId: 'station-c',
              mobilityType: MobilityType.senior,
            ),
          );

      expect(sameLineResult.status, RouteStatus.found);
      expect(sameLineResult.transferStationIds, isEmpty);
      expect(crossStationResult.status, RouteStatus.found);
      expect(crossStationResult.transferStationIds, isEmpty);
    });

    test('역외 환승 모드는 검증된 역외 환승 edge를 허용한다', () {
      final result =
          LocalRouteEngine(graph: _outOfStationTransferFixtureGraph()).search(
            const RouteRequest(
              originStationId: 'station-a',
              destinationStationId: 'station-d',
              mobilityType: MobilityType.senior,
              searchMode:
                  RouteSearchMode.stationToStationWithOutOfStationTransfers,
            ),
          );

      expect(result.status, RouteStatus.found);
      expect(result.edgeIds, [
        'entry-a-line-1',
        'ride-a-b-line-1',
        'out-transfer-b-c',
        'ride-c-d-line-2',
        'exit-d-line-2',
      ]);
    });

    test('기본 역간 탐색은 역외 환승 edge를 쓰지 않는다', () {
      final result =
          LocalRouteEngine(graph: _outOfStationTransferFixtureGraph()).search(
            const RouteRequest(
              originStationId: 'station-a',
              destinationStationId: 'station-d',
              mobilityType: MobilityType.senior,
            ),
          );

      expect(result.status, RouteStatus.unknown);
      expect(result.edgeIds, isEmpty);
    });

    test('역외 환승 모드도 임의 중간 exit와 entry 우회는 거부한다', () {
      final result = LocalRouteEngine(graph: _midRouteExitEntryFixtureGraph())
          .search(
            const RouteRequest(
              originStationId: 'station-a',
              destinationStationId: 'station-d',
              mobilityType: MobilityType.senior,
              searchMode:
                  RouteSearchMode.stationToStationWithOutOfStationTransfers,
            ),
          );

      expect(result.status, RouteStatus.unknown);
      expect(result.edgeIds, isEmpty);
    });

    test('strict 역외 환승 모드는 generated 역외 환승 connector를 검증된 edge로 쓰지 않는다', () {
      final result =
          LocalRouteEngine(
            graph: _generatedOutOfStationTransferFixtureGraph(),
          ).search(
            const RouteRequest(
              originStationId: 'station-a',
              destinationStationId: 'station-d',
              mobilityType: MobilityType.wheelchair,
              searchMode:
                  RouteSearchMode.stationToStationWithOutOfStationTransfers,
            ),
          );

      expect(result.status, RouteStatus.unknown);
      expect(result.edgeIds, isEmpty);
      expect(result.blockedReasonCodes, ['GENERATED_CONNECTOR_UNVERIFIED']);
    });

    test('휠체어 조건은 계단만 있는 경로를 비용 증가가 아니라 차단으로 처리한다', () {
      final engine = LocalRouteEngine(graph: _stairOnlyFixtureGraph());

      final result = engine.search(
        const RouteRequest(
          originStationId: 'station-sangnoksu',
          destinationStationId: 'station-sadang',
          mobilityType: MobilityType.wheelchair,
        ),
      );

      expect(result.status, RouteStatus.blocked);
      expect(result.edgeIds, isEmpty);
      expect(result.totalCost, 0);
      expect(result.includesStairs, isFalse);
      expect(result.blockedReasonCodes, ['STAIR_ONLY_ACCESS']);
      expect(result.warningCodes, isEmpty);
    });

    test('일시적 부상 strict 조건은 계단만 있는 경로를 차단한다', () {
      final engine = LocalRouteEngine(graph: _stairOnlyFixtureGraph());

      final result = engine.search(
        const RouteRequest(
          originStationId: 'station-sangnoksu',
          destinationStationId: 'station-sadang',
          mobilityType: MobilityType.temporaryInjury,
          constraintMode: ConstraintMode.strictStepFree,
        ),
      );

      expect(result.status, RouteStatus.blocked);
      expect(result.blockedReasonCodes, ['STAIR_ONLY_ACCESS']);
    });

    test('휠체어 prefer 조건은 계단 포함 경로 비용을 경고와 함께 유지한다', () {
      final engine = LocalRouteEngine(graph: _stairOnlyFixtureGraph());

      final result = engine.search(
        const RouteRequest(
          originStationId: 'station-sangnoksu',
          destinationStationId: 'station-sadang',
          mobilityType: MobilityType.wheelchair,
          constraintMode: ConstraintMode.preferStepFree,
        ),
      );

      expect(result.status, RouteStatus.found);
      expect(result.totalCost, 749);
      expect(result.steps.map((step) => step.cost), [160, 420, 145]);
      expect(result.warningCodes, ['STAIR_ONLY_ACCESS']);
    });

    test('휠체어 조건은 미확인 접근성 edge를 안전한 경로로 사용하지 않는다', () {
      final engine = LocalRouteEngine(
        graph: _unknownAccessibilityFixtureGraph(),
      );

      final result = engine.search(
        const RouteRequest(
          originStationId: 'station-sangnoksu',
          destinationStationId: 'station-sadang',
          mobilityType: MobilityType.wheelchair,
        ),
      );

      expect(result.status, RouteStatus.unknown);
      expect(result.edgeIds, isEmpty);
      expect(result.blockedReasonCodes, ['ACCESSIBILITY_STATE_UNKNOWN']);
      expect(result.warningCodes, isEmpty);
    });

    test('휠체어 조건은 계단 여부 미확인 edge를 안전한 경로로 사용하지 않는다', () {
      final engine = LocalRouteEngine(graph: _unknownStairAccessFixtureGraph());

      final result = engine.search(
        const RouteRequest(
          originStationId: 'station-sangnoksu',
          destinationStationId: 'station-sadang',
          mobilityType: MobilityType.wheelchair,
        ),
      );

      expect(result.status, RouteStatus.unknown);
      expect(result.edgeIds, isEmpty);
      expect(result.includesStairs, isFalse);
      expect(result.blockedReasonCodes, ['STAIR_ONLY_ACCESS_UNKNOWN']);
      expect(result.warningCodes, isEmpty);
    });

    test('휠체어 조건은 미확인 사유가 확정 차단 사유와 섞여도 UNKNOWN으로 남긴다', () {
      final engine = LocalRouteEngine(
        graph: _mixedUnknownAndBlockedFixtureGraph(),
      );

      final result = engine.search(
        const RouteRequest(
          originStationId: 'station-a',
          destinationStationId: 'station-b',
          mobilityType: MobilityType.wheelchair,
        ),
      );

      expect(result.status, RouteStatus.unknown);
      expect(result.edgeIds, isEmpty);
      expect(result.blockedReasonCodes, [
        'ACCESSIBILITY_STATE_UNKNOWN',
        'STAIR_ONLY_ACCESS',
      ]);
      expect(result.warningCodes, isEmpty);
    });

    test('휠체어 조건은 계단 상태가 없는 기본 edge를 안전한 경로로 사용하지 않는다', () {
      final engine = LocalRouteEngine(graph: _missingStairAccessFixtureGraph());

      final result = engine.search(
        const RouteRequest(
          originStationId: 'station-sangnoksu',
          destinationStationId: 'station-sadang',
          mobilityType: MobilityType.wheelchair,
        ),
      );

      expect(result.status, RouteStatus.unknown);
      expect(result.edgeIds, isEmpty);
      expect(result.includesStairs, isFalse);
      expect(result.blockedReasonCodes, ['STAIR_ONLY_ACCESS_UNKNOWN']);
      expect(result.warningCodes, isEmpty);
    });

    test('휠체어 조건은 tri-state 계단 전용 값을 legacy flag보다 우선한다', () {
      final engine = LocalRouteEngine(
        graph: _conflictingStairAccessFixtureGraph(),
      );

      final result = engine.search(
        const RouteRequest(
          originStationId: 'station-sangnoksu',
          destinationStationId: 'station-sadang',
          mobilityType: MobilityType.wheelchair,
        ),
      );

      expect(result.status, RouteStatus.blocked);
      expect(result.edgeIds, isEmpty);
      expect(result.includesStairs, isFalse);
      expect(result.blockedReasonCodes, ['STAIR_ONLY_ACCESS']);
      expect(result.warningCodes, isEmpty);
    });

    test('일반 조건의 오래된 데이터는 경고 코드와 비용에 반영한다', () {
      final engine = LocalRouteEngine(graph: _lowQualityFixtureGraph());

      final result = engine.search(
        const RouteRequest(
          originStationId: 'station-sangnoksu',
          destinationStationId: 'station-sadang',
          mobilityType: MobilityType.senior,
        ),
      );

      expect(result.status, RouteStatus.found);
      expect(result.warningCodes, [
        'LOW_DATA_CONFIDENCE',
        'STALE_ACCESSIBILITY_DATA',
      ]);
      expect(result.totalCost, 666);
      expect(result.includesStairs, isFalse);
    });

    test('10000 node 그래프는 fromNode index로 필요한 edge만 조회한다', () {
      final graph = _largeLinearGraph(10000);
      final engine = LocalRouteEngine(graph: graph);

      final result = engine.search(
        const RouteRequest(
          originStationId: 'station-0',
          destinationStationId: 'station-9999',
          mobilityType: MobilityType.wheelchair,
        ),
      );

      expect(graph.edgesFrom('station-5000').map((edge) => edge.id), [
        'edge-5000-5001',
      ]);
      expect(graph.edgesFrom('station-9999'), isEmpty);
      expect(result.status, RouteStatus.found);
      expect(result.edgeIds.length, 9999);
    });

    test('개선된 후보가 있는 경로는 반복 실행해도 같은 최저 비용 경로를 반환한다', () {
      final engine = LocalRouteEngine(graph: _improvedCandidateFixtureGraph());

      final results = List.generate(
        5,
        (_) => engine.search(
          const RouteRequest(
            originStationId: 'station-a',
            destinationStationId: 'station-d',
            mobilityType: MobilityType.senior,
          ),
        ),
      );

      for (final result in results) {
        expect(result.status, RouteStatus.found);
        expect(result.edgeIds, [
          'entry-a-line-1',
          'ride-a-b-line-1',
          'ride-b-d-line-1',
          'exit-d-line-1',
        ]);
        expect(result.totalCost, 398);
        expect(result.blockedReasonCodes, isEmpty);
      }
    });

    test('generated connector edge 비율을 일반 접근성 edge와 별도로 계산한다', () {
      final graph = NetworkGraph(
        nodes: const [
          RouteNode(
            id: 'station-a:line-1',
            stationId: 'station-a',
            lineId: 'line-1',
          ),
          RouteNode(
            id: 'station-b:line-1',
            stationId: 'station-b',
            lineId: 'line-1',
          ),
        ],
        edges: const [
          RouteEdge(
            id: 'entry-a-generated',
            fromNodeId: 'station-a',
            toNodeId: 'station-a:line-1',
            type: RouteEdgeType.entry,
            baseCost: 90,
            stairAccessState: RouteStairAccessState.unknown,
            isGeneratedConnector: true,
          ),
          RouteEdge(
            id: 'ride-a-b',
            fromNodeId: 'station-a:line-1',
            toNodeId: 'station-b:line-1',
            type: RouteEdgeType.ride,
            baseCost: 180,
            lineId: 'line-1',
          ),
        ],
      );

      expect(graph.generatedConnectorEdgeRatio, 0.5);
    });

    test('휠체어 경로는 generated connector edge가 stepFree여도 FOUND가 되지 않는다', () {
      final engine = LocalRouteEngine(
        graph: NetworkGraph(
          nodes: const [
            RouteNode(
              id: 'station-a:line-1',
              stationId: 'station-a',
              lineId: 'line-1',
            ),
            RouteNode(
              id: 'station-b:line-1',
              stationId: 'station-b',
              lineId: 'line-1',
            ),
          ],
          edges: const [
            RouteEdge(
              id: 'entry-a-generated',
              fromNodeId: 'station-a',
              toNodeId: 'station-a:line-1',
              type: RouteEdgeType.entry,
              baseCost: 90,
              stairAccessState: RouteStairAccessState.stepFree,
              isGeneratedConnector: true,
            ),
            RouteEdge(
              id: 'ride-a-b',
              fromNodeId: 'station-a:line-1',
              toNodeId: 'station-b:line-1',
              type: RouteEdgeType.ride,
              baseCost: 180,
              lineId: 'line-1',
            ),
            RouteEdge(
              id: 'exit-b-step-free',
              fromNodeId: 'station-b:line-1',
              toNodeId: 'station-b',
              type: RouteEdgeType.exit,
              baseCost: 60,
              stairAccessState: RouteStairAccessState.stepFree,
            ),
          ],
        ),
      );

      final result = engine.search(
        const RouteRequest(
          originStationId: 'station-a',
          destinationStationId: 'station-b',
          mobilityType: MobilityType.wheelchair,
        ),
      );

      expect(result.status, RouteStatus.unknown);
      expect(result.blockedReasonCodes, ['GENERATED_CONNECTOR_UNVERIFIED']);
    });

    test('유모차 strict 경로는 미확인, 생성, 오래된 edge를 FOUND로 사용하지 않는다', () {
      final unknownResult =
          LocalRouteEngine(graph: _unknownAccessibilityFixtureGraph()).search(
            const RouteRequest(
              originStationId: 'station-sangnoksu',
              destinationStationId: 'station-sadang',
              mobilityType: MobilityType.stroller,
              constraintMode: ConstraintMode.strictStepFree,
            ),
          );
      final staleResult = LocalRouteEngine(graph: _lowQualityFixtureGraph())
          .search(
            const RouteRequest(
              originStationId: 'station-sangnoksu',
              destinationStationId: 'station-sadang',
              mobilityType: MobilityType.stroller,
              constraintMode: ConstraintMode.strictStepFree,
            ),
          );
      final generatedResult =
          LocalRouteEngine(graph: _generatedConnectorFixtureGraph()).search(
            const RouteRequest(
              originStationId: 'station-a',
              destinationStationId: 'station-b',
              mobilityType: MobilityType.stroller,
              constraintMode: ConstraintMode.strictStepFree,
            ),
          );

      expect(unknownResult.status, RouteStatus.unknown);
      expect(unknownResult.blockedReasonCodes, ['ACCESSIBILITY_STATE_UNKNOWN']);
      expect(staleResult.status, RouteStatus.unknown);
      expect(staleResult.blockedReasonCodes, ['STALE_ACCESSIBILITY_DATA']);
      expect(generatedResult.status, RouteStatus.unknown);
      expect(generatedResult.blockedReasonCodes, [
        'GENERATED_CONNECTOR_UNVERIFIED',
      ]);
    });
  });
}

NetworkGraph _improvedCandidateFixtureGraph() {
  return NetworkGraph(
    nodes: const [
      RouteNode(
        id: 'station-a:line-1',
        stationId: 'station-a',
        lineId: 'line-1',
      ),
      RouteNode(
        id: 'station-b:line-1',
        stationId: 'station-b',
        lineId: 'line-1',
      ),
      RouteNode(
        id: 'station-d:line-1',
        stationId: 'station-d',
        lineId: 'line-1',
      ),
    ],
    edges: const [
      RouteEdge(
        id: 'entry-a-line-1',
        fromNodeId: 'station-a',
        toNodeId: 'station-a:line-1',
        type: RouteEdgeType.entry,
        baseCost: 90,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
      RouteEdge(
        id: 'ride-a-d-expensive-line-1',
        fromNodeId: 'station-a:line-1',
        toNodeId: 'station-d:line-1',
        type: RouteEdgeType.ride,
        baseCost: 500,
        lineId: 'line-1',
      ),
      RouteEdge(
        id: 'ride-a-b-line-1',
        fromNodeId: 'station-a:line-1',
        toNodeId: 'station-b:line-1',
        type: RouteEdgeType.ride,
        baseCost: 100,
        lineId: 'line-1',
      ),
      RouteEdge(
        id: 'ride-b-d-line-1',
        fromNodeId: 'station-b:line-1',
        toNodeId: 'station-d:line-1',
        type: RouteEdgeType.ride,
        baseCost: 100,
        lineId: 'line-1',
      ),
      RouteEdge(
        id: 'exit-d-line-1',
        fromNodeId: 'station-d:line-1',
        toNodeId: 'station-d',
        type: RouteEdgeType.exit,
        baseCost: 90,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
    ],
  );
}

NetworkGraph _generatedConnectorFixtureGraph() {
  return NetworkGraph(
    nodes: const [
      RouteNode(
        id: 'station-a:line-1',
        stationId: 'station-a',
        lineId: 'line-1',
      ),
      RouteNode(
        id: 'station-b:line-1',
        stationId: 'station-b',
        lineId: 'line-1',
      ),
    ],
    edges: const [
      RouteEdge(
        id: 'entry-a-generated',
        fromNodeId: 'station-a',
        toNodeId: 'station-a:line-1',
        type: RouteEdgeType.entry,
        baseCost: 90,
        stairAccessState: RouteStairAccessState.stepFree,
        isGeneratedConnector: true,
      ),
      RouteEdge(
        id: 'ride-a-b',
        fromNodeId: 'station-a:line-1',
        toNodeId: 'station-b:line-1',
        type: RouteEdgeType.ride,
        baseCost: 180,
        lineId: 'line-1',
      ),
      RouteEdge(
        id: 'exit-b-step-free',
        fromNodeId: 'station-b:line-1',
        toNodeId: 'station-b',
        type: RouteEdgeType.exit,
        baseCost: 60,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
    ],
  );
}

NetworkGraph _capitalFixtureGraph() {
  return NetworkGraph(
    nodes: const [
      RouteNode(
        id: 'station-sangnoksu:seoul-4',
        stationId: 'station-sangnoksu',
        lineId: 'seoul-4',
      ),
      RouteNode(
        id: 'station-sadang:seoul-4',
        stationId: 'station-sadang',
        lineId: 'seoul-4',
      ),
      RouteNode(
        id: 'station-sadang:seoul-2',
        stationId: 'station-sadang',
        lineId: 'seoul-2',
      ),
      RouteNode(
        id: 'station-cityhall:seoul-2',
        stationId: 'station-cityhall',
        lineId: 'seoul-2',
      ),
    ],
    edges: const [
      RouteEdge(
        id: 'entry-sangnoksu-step-free',
        fromNodeId: 'station-sangnoksu',
        toNodeId: 'station-sangnoksu:seoul-4',
        type: RouteEdgeType.entry,
        baseCost: 90,
        includesStairs: false,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
      RouteEdge(
        id: 'ride-sangnoksu-sadang-line4',
        fromNodeId: 'station-sangnoksu:seoul-4',
        toNodeId: 'station-sadang:seoul-4',
        type: RouteEdgeType.ride,
        baseCost: 420,
        lineId: 'seoul-4',
      ),
      RouteEdge(
        id: 'transfer-sadang-line4-line2',
        fromNodeId: 'station-sadang:seoul-4',
        toNodeId: 'station-sadang:seoul-2',
        type: RouteEdgeType.inStationTransfer,
        baseCost: 140,
        transferStationId: 'station-sadang',
        stairAccessState: RouteStairAccessState.stepFree,
      ),
      RouteEdge(
        id: 'ride-sadang-cityhall-line2',
        fromNodeId: 'station-sadang:seoul-2',
        toNodeId: 'station-cityhall:seoul-2',
        type: RouteEdgeType.ride,
        baseCost: 520,
        lineId: 'seoul-2',
      ),
      RouteEdge(
        id: 'exit-sadang-step-free',
        fromNodeId: 'station-sadang:seoul-4',
        toNodeId: 'station-sadang',
        type: RouteEdgeType.exit,
        baseCost: 60,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
      RouteEdge(
        id: 'exit-cityhall-step-free',
        fromNodeId: 'station-cityhall:seoul-2',
        toNodeId: 'station-cityhall',
        type: RouteEdgeType.exit,
        baseCost: 90,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
    ],
  );
}

NetworkGraph _sameLineTransferCatalogFixtureGraph() {
  return NetworkGraph(
    nodes: const [
      RouteNode(
        id: 'station-a:line-1:LOCAL',
        stationId: 'station-a',
        lineId: 'line-1',
      ),
      RouteNode(
        id: 'station-a:line-1:EXPRESS',
        stationId: 'station-a',
        lineId: 'line-1',
      ),
      RouteNode(
        id: 'station-b:line-1:EXPRESS',
        stationId: 'station-b',
        lineId: 'line-1',
      ),
    ],
    edges: const [
      RouteEdge(
        id: 'entry-a-line-1-local',
        fromNodeId: 'station-a',
        toNodeId: 'station-a:line-1:LOCAL',
        type: RouteEdgeType.entry,
        baseCost: 90,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
      RouteEdge(
        id: 'transfer-a-local-express',
        fromNodeId: 'station-a:line-1:LOCAL',
        toNodeId: 'station-a:line-1:EXPRESS',
        type: RouteEdgeType.inStationTransfer,
        baseCost: 80,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
      RouteEdge(
        id: 'ride-a-b-line-1-express',
        fromNodeId: 'station-a:line-1:EXPRESS',
        toNodeId: 'station-b:line-1:EXPRESS',
        type: RouteEdgeType.ride,
        baseCost: 180,
        lineId: 'line-1',
      ),
      RouteEdge(
        id: 'exit-b-line-1-express',
        fromNodeId: 'station-b:line-1:EXPRESS',
        toNodeId: 'station-b',
        type: RouteEdgeType.exit,
        baseCost: 90,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
    ],
  );
}

NetworkGraph _crossStationTransferCatalogFixtureGraph() {
  return NetworkGraph(
    nodes: const [
      RouteNode(
        id: 'station-a:line-1',
        stationId: 'station-a',
        lineId: 'line-1',
      ),
      RouteNode(
        id: 'station-b:line-2',
        stationId: 'station-b',
        lineId: 'line-2',
      ),
      RouteNode(
        id: 'station-c:line-2',
        stationId: 'station-c',
        lineId: 'line-2',
      ),
    ],
    edges: const [
      RouteEdge(
        id: 'entry-a-line-1',
        fromNodeId: 'station-a',
        toNodeId: 'station-a:line-1',
        type: RouteEdgeType.entry,
        baseCost: 90,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
      RouteEdge(
        id: 'transfer-a-b-cross-station',
        fromNodeId: 'station-a:line-1',
        toNodeId: 'station-b:line-2',
        type: RouteEdgeType.inStationTransfer,
        baseCost: 240,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
      RouteEdge(
        id: 'ride-b-c-line-2',
        fromNodeId: 'station-b:line-2',
        toNodeId: 'station-c:line-2',
        type: RouteEdgeType.ride,
        baseCost: 180,
        lineId: 'line-2',
      ),
      RouteEdge(
        id: 'exit-c-line-2',
        fromNodeId: 'station-c:line-2',
        toNodeId: 'station-c',
        type: RouteEdgeType.exit,
        baseCost: 90,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
    ],
  );
}

NetworkGraph _outOfStationTransferFixtureGraph({
  bool generatedOutOfStationTransfer = false,
}) {
  return NetworkGraph(
    nodes: const [
      RouteNode(
        id: 'station-a:line-1',
        stationId: 'station-a',
        lineId: 'line-1',
      ),
      RouteNode(
        id: 'station-b:line-1',
        stationId: 'station-b',
        lineId: 'line-1',
      ),
      RouteNode(
        id: 'station-c:line-2',
        stationId: 'station-c',
        lineId: 'line-2',
      ),
      RouteNode(
        id: 'station-d:line-2',
        stationId: 'station-d',
        lineId: 'line-2',
      ),
    ],
    edges: [
      const RouteEdge(
        id: 'entry-a-line-1',
        fromNodeId: 'station-a',
        toNodeId: 'station-a:line-1',
        type: RouteEdgeType.entry,
        baseCost: 90,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
      const RouteEdge(
        id: 'ride-a-b-line-1',
        fromNodeId: 'station-a:line-1',
        toNodeId: 'station-b:line-1',
        type: RouteEdgeType.ride,
        baseCost: 180,
        lineId: 'line-1',
      ),
      RouteEdge(
        id: 'out-transfer-b-c',
        fromNodeId: 'station-b:line-1',
        toNodeId: 'station-c:line-2',
        type: RouteEdgeType.outOfStationTransfer,
        baseCost: 240,
        stairAccessState: RouteStairAccessState.stepFree,
        isGeneratedConnector: generatedOutOfStationTransfer,
      ),
      const RouteEdge(
        id: 'ride-c-d-line-2',
        fromNodeId: 'station-c:line-2',
        toNodeId: 'station-d:line-2',
        type: RouteEdgeType.ride,
        baseCost: 180,
        lineId: 'line-2',
      ),
      const RouteEdge(
        id: 'exit-d-line-2',
        fromNodeId: 'station-d:line-2',
        toNodeId: 'station-d',
        type: RouteEdgeType.exit,
        baseCost: 90,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
    ],
  );
}

NetworkGraph _generatedOutOfStationTransferFixtureGraph() {
  return _outOfStationTransferFixtureGraph(generatedOutOfStationTransfer: true);
}

NetworkGraph _midRouteExitEntryFixtureGraph() {
  return NetworkGraph(
    nodes: const [
      RouteNode(
        id: 'station-a:line-1',
        stationId: 'station-a',
        lineId: 'line-1',
      ),
      RouteNode(
        id: 'station-b:line-1',
        stationId: 'station-b',
        lineId: 'line-1',
      ),
      RouteNode(
        id: 'station-b:line-2',
        stationId: 'station-b',
        lineId: 'line-2',
      ),
      RouteNode(
        id: 'station-d:line-2',
        stationId: 'station-d',
        lineId: 'line-2',
      ),
    ],
    edges: const [
      RouteEdge(
        id: 'entry-a-line-1',
        fromNodeId: 'station-a',
        toNodeId: 'station-a:line-1',
        type: RouteEdgeType.entry,
        baseCost: 90,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
      RouteEdge(
        id: 'ride-a-b-line-1',
        fromNodeId: 'station-a:line-1',
        toNodeId: 'station-b:line-1',
        type: RouteEdgeType.ride,
        baseCost: 180,
        lineId: 'line-1',
      ),
      RouteEdge(
        id: 'exit-b-line-1',
        fromNodeId: 'station-b:line-1',
        toNodeId: 'station-b',
        type: RouteEdgeType.exit,
        baseCost: 60,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
      RouteEdge(
        id: 'entry-b-line-2',
        fromNodeId: 'station-b',
        toNodeId: 'station-b:line-2',
        type: RouteEdgeType.entry,
        baseCost: 90,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
      RouteEdge(
        id: 'ride-b-d-line-2',
        fromNodeId: 'station-b:line-2',
        toNodeId: 'station-d:line-2',
        type: RouteEdgeType.ride,
        baseCost: 180,
        lineId: 'line-2',
      ),
      RouteEdge(
        id: 'exit-d-line-2',
        fromNodeId: 'station-d:line-2',
        toNodeId: 'station-d',
        type: RouteEdgeType.exit,
        baseCost: 90,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
    ],
  );
}

NetworkGraph _twoTransferCatalogFixtureGraph() {
  return NetworkGraph(
    nodes: const [
      RouteNode(
        id: 'station-a:line-1',
        stationId: 'station-a',
        lineId: 'line-1',
      ),
      RouteNode(
        id: 'station-b:line-1',
        stationId: 'station-b',
        lineId: 'line-1',
      ),
      RouteNode(
        id: 'station-b:line-2',
        stationId: 'station-b',
        lineId: 'line-2',
      ),
      RouteNode(
        id: 'station-c:line-2',
        stationId: 'station-c',
        lineId: 'line-2',
      ),
      RouteNode(
        id: 'station-c:line-3',
        stationId: 'station-c',
        lineId: 'line-3',
      ),
      RouteNode(
        id: 'station-d:line-3',
        stationId: 'station-d',
        lineId: 'line-3',
      ),
    ],
    edges: const [
      RouteEdge(
        id: 'entry-a-line-1',
        fromNodeId: 'station-a',
        toNodeId: 'station-a:line-1',
        type: RouteEdgeType.entry,
        baseCost: 90,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
      RouteEdge(
        id: 'ride-a-b-line-1',
        fromNodeId: 'station-a:line-1',
        toNodeId: 'station-b:line-1',
        type: RouteEdgeType.ride,
        baseCost: 180,
        lineId: 'line-1',
      ),
      RouteEdge(
        id: 'transfer-b-line-1-line-2',
        fromNodeId: 'station-b:line-1',
        toNodeId: 'station-b:line-2',
        type: RouteEdgeType.inStationTransfer,
        baseCost: 140,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
      RouteEdge(
        id: 'ride-b-c-line-2',
        fromNodeId: 'station-b:line-2',
        toNodeId: 'station-c:line-2',
        type: RouteEdgeType.ride,
        baseCost: 210,
        lineId: 'line-2',
      ),
      RouteEdge(
        id: 'transfer-c-line-2-line-3',
        fromNodeId: 'station-c:line-2',
        toNodeId: 'station-c:line-3',
        type: RouteEdgeType.inStationTransfer,
        baseCost: 140,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
      RouteEdge(
        id: 'ride-c-d-line-3',
        fromNodeId: 'station-c:line-3',
        toNodeId: 'station-d:line-3',
        type: RouteEdgeType.ride,
        baseCost: 240,
        lineId: 'line-3',
      ),
      RouteEdge(
        id: 'exit-d-line-3',
        fromNodeId: 'station-d:line-3',
        toNodeId: 'station-d',
        type: RouteEdgeType.exit,
        baseCost: 90,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
    ],
  );
}

NetworkGraph _stairOnlyFixtureGraph() {
  return NetworkGraph(
    nodes: const [
      RouteNode(
        id: 'station-sangnoksu:seoul-4',
        stationId: 'station-sangnoksu',
        lineId: 'seoul-4',
      ),
      RouteNode(
        id: 'station-sadang:seoul-4',
        stationId: 'station-sadang',
        lineId: 'seoul-4',
      ),
    ],
    edges: const [
      RouteEdge(
        id: 'entry-sangnoksu-stairs',
        fromNodeId: 'station-sangnoksu',
        toNodeId: 'station-sangnoksu:seoul-4',
        type: RouteEdgeType.entry,
        baseCost: 60,
        includesStairs: true,
      ),
      RouteEdge(
        id: 'ride-sangnoksu-sadang-line4',
        fromNodeId: 'station-sangnoksu:seoul-4',
        toNodeId: 'station-sadang:seoul-4',
        type: RouteEdgeType.ride,
        baseCost: 420,
        lineId: 'seoul-4',
      ),
      RouteEdge(
        id: 'exit-sadang-stairs',
        fromNodeId: 'station-sadang:seoul-4',
        toNodeId: 'station-sadang',
        type: RouteEdgeType.exit,
        baseCost: 45,
        includesStairs: true,
      ),
    ],
  );
}

NetworkGraph _unknownAccessibilityFixtureGraph() {
  return NetworkGraph(
    nodes: const [
      RouteNode(
        id: 'station-sangnoksu:seoul-4',
        stationId: 'station-sangnoksu',
        lineId: 'seoul-4',
      ),
      RouteNode(
        id: 'station-sadang:seoul-4',
        stationId: 'station-sadang',
        lineId: 'seoul-4',
      ),
    ],
    edges: const [
      RouteEdge(
        id: 'entry-sangnoksu-unknown-elevator',
        fromNodeId: 'station-sangnoksu',
        toNodeId: 'station-sangnoksu:seoul-4',
        type: RouteEdgeType.entry,
        baseCost: 90,
        accessibilityState: RouteAccessibilityState.unknown,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
      RouteEdge(
        id: 'ride-sangnoksu-sadang-line4',
        fromNodeId: 'station-sangnoksu:seoul-4',
        toNodeId: 'station-sadang:seoul-4',
        type: RouteEdgeType.ride,
        baseCost: 420,
        lineId: 'seoul-4',
      ),
      RouteEdge(
        id: 'exit-sadang-step-free',
        fromNodeId: 'station-sadang:seoul-4',
        toNodeId: 'station-sadang',
        type: RouteEdgeType.exit,
        baseCost: 60,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
    ],
  );
}

NetworkGraph _unknownStairAccessFixtureGraph() {
  return NetworkGraph(
    nodes: const [
      RouteNode(
        id: 'station-sangnoksu:seoul-4',
        stationId: 'station-sangnoksu',
        lineId: 'seoul-4',
      ),
      RouteNode(
        id: 'station-sadang:seoul-4',
        stationId: 'station-sadang',
        lineId: 'seoul-4',
      ),
    ],
    edges: const [
      RouteEdge(
        id: 'entry-sangnoksu-stair-state-unknown',
        fromNodeId: 'station-sangnoksu',
        toNodeId: 'station-sangnoksu:seoul-4',
        type: RouteEdgeType.entry,
        baseCost: 90,
        stairAccessState: RouteStairAccessState.unknown,
      ),
      RouteEdge(
        id: 'ride-sangnoksu-sadang-line4',
        fromNodeId: 'station-sangnoksu:seoul-4',
        toNodeId: 'station-sadang:seoul-4',
        type: RouteEdgeType.ride,
        baseCost: 420,
        lineId: 'seoul-4',
      ),
      RouteEdge(
        id: 'exit-sadang-step-free',
        fromNodeId: 'station-sadang:seoul-4',
        toNodeId: 'station-sadang',
        type: RouteEdgeType.exit,
        baseCost: 60,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
    ],
  );
}

NetworkGraph _mixedUnknownAndBlockedFixtureGraph() {
  return NetworkGraph(
    nodes: const [
      RouteNode(id: 'station-a', stationId: 'station-a', lineId: 'line-1'),
      RouteNode(id: 'station-b', stationId: 'station-b', lineId: 'line-1'),
    ],
    edges: const [
      RouteEdge(
        id: 'ride-a-b-unknown-accessibility',
        fromNodeId: 'station-a',
        toNodeId: 'station-b',
        type: RouteEdgeType.ride,
        baseCost: 180,
        lineId: 'line-1',
        accessibilityState: RouteAccessibilityState.unknown,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
      RouteEdge(
        id: 'ride-a-b-stair-only',
        fromNodeId: 'station-a',
        toNodeId: 'station-b',
        type: RouteEdgeType.ride,
        baseCost: 180,
        lineId: 'line-1',
        stairAccessState: RouteStairAccessState.stairOnly,
      ),
    ],
  );
}

NetworkGraph _conflictingStairAccessFixtureGraph() {
  return NetworkGraph(
    nodes: const [
      RouteNode(
        id: 'station-sangnoksu:seoul-4',
        stationId: 'station-sangnoksu',
        lineId: 'seoul-4',
      ),
      RouteNode(
        id: 'station-sadang:seoul-4',
        stationId: 'station-sadang',
        lineId: 'seoul-4',
      ),
    ],
    edges: const [
      RouteEdge(
        id: 'entry-sangnoksu-stair-state-conflict',
        fromNodeId: 'station-sangnoksu',
        toNodeId: 'station-sangnoksu:seoul-4',
        type: RouteEdgeType.entry,
        baseCost: 90,
        includesStairs: false,
        stairAccessState: RouteStairAccessState.stairOnly,
      ),
      RouteEdge(
        id: 'ride-sangnoksu-sadang-line4',
        fromNodeId: 'station-sangnoksu:seoul-4',
        toNodeId: 'station-sadang:seoul-4',
        type: RouteEdgeType.ride,
        baseCost: 420,
        lineId: 'seoul-4',
      ),
      RouteEdge(
        id: 'exit-sadang-step-free',
        fromNodeId: 'station-sadang:seoul-4',
        toNodeId: 'station-sadang',
        type: RouteEdgeType.exit,
        baseCost: 60,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
    ],
  );
}

NetworkGraph _missingStairAccessFixtureGraph() {
  return NetworkGraph(
    nodes: const [
      RouteNode(
        id: 'station-sangnoksu:seoul-4',
        stationId: 'station-sangnoksu',
        lineId: 'seoul-4',
      ),
      RouteNode(
        id: 'station-sadang:seoul-4',
        stationId: 'station-sadang',
        lineId: 'seoul-4',
      ),
    ],
    edges: const [
      RouteEdge(
        id: 'entry-sangnoksu-stair-state-missing',
        fromNodeId: 'station-sangnoksu',
        toNodeId: 'station-sangnoksu:seoul-4',
        type: RouteEdgeType.entry,
        baseCost: 90,
      ),
      RouteEdge(
        id: 'ride-sangnoksu-sadang-line4',
        fromNodeId: 'station-sangnoksu:seoul-4',
        toNodeId: 'station-sadang:seoul-4',
        type: RouteEdgeType.ride,
        baseCost: 420,
        lineId: 'seoul-4',
        stairAccessState: RouteStairAccessState.stepFree,
      ),
      RouteEdge(
        id: 'exit-sadang-step-free',
        fromNodeId: 'station-sadang:seoul-4',
        toNodeId: 'station-sadang',
        type: RouteEdgeType.exit,
        baseCost: 60,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
    ],
  );
}

NetworkGraph _lowQualityFixtureGraph() {
  return NetworkGraph(
    nodes: const [
      RouteNode(
        id: 'station-sangnoksu:seoul-4',
        stationId: 'station-sangnoksu',
        lineId: 'seoul-4',
      ),
      RouteNode(
        id: 'station-sadang:seoul-4',
        stationId: 'station-sadang',
        lineId: 'seoul-4',
      ),
    ],
    edges: const [
      RouteEdge(
        id: 'entry-sangnoksu-low-confidence',
        fromNodeId: 'station-sangnoksu',
        toNodeId: 'station-sangnoksu:seoul-4',
        type: RouteEdgeType.entry,
        baseCost: 90,
        reliabilityScore: 62,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
      RouteEdge(
        id: 'ride-sangnoksu-sadang-line4',
        fromNodeId: 'station-sangnoksu:seoul-4',
        toNodeId: 'station-sadang:seoul-4',
        type: RouteEdgeType.ride,
        baseCost: 420,
        lineId: 'seoul-4',
      ),
      RouteEdge(
        id: 'exit-sadang-stale-data',
        fromNodeId: 'station-sadang:seoul-4',
        toNodeId: 'station-sadang',
        type: RouteEdgeType.exit,
        baseCost: 90,
        isDataStale: true,
        stairAccessState: RouteStairAccessState.stepFree,
      ),
    ],
  );
}

NetworkGraph _largeLinearGraph(int nodeCount) {
  return NetworkGraph(
    nodes: [
      for (var index = 0; index < nodeCount; index++)
        RouteNode(
          id: 'station-$index',
          stationId: 'station-$index',
          lineId: 'line-large',
        ),
    ],
    edges: [
      for (var index = 0; index < nodeCount - 1; index++)
        RouteEdge(
          id: 'edge-$index-${index + 1}',
          fromNodeId: 'station-$index',
          toNodeId: 'station-${index + 1}',
          type: RouteEdgeType.ride,
          baseCost: 30,
          lineId: 'line-large',
        ),
    ],
  );
}
