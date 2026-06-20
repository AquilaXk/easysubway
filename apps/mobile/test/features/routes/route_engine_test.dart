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

    test('낮은 신뢰도와 오래된 데이터는 경고 코드와 비용에 반영한다', () {
      final engine = LocalRouteEngine(graph: _lowQualityFixtureGraph());

      final result = engine.search(
        const RouteRequest(
          originStationId: 'station-sangnoksu',
          destinationStationId: 'station-sadang',
          mobilityType: MobilityType.stroller,
        ),
      );

      expect(result.status, RouteStatus.found);
      expect(result.warningCodes, [
        'LOW_DATA_CONFIDENCE',
        'STALE_ACCESSIBILITY_DATA',
      ]);
      expect(result.totalCost, 674);
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
  });
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
        type: RouteEdgeType.transfer,
        baseCost: 140,
        transferStationId: 'station-sadang',
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
      ),
      RouteEdge(
        id: 'exit-cityhall-step-free',
        fromNodeId: 'station-cityhall:seoul-2',
        toNodeId: 'station-cityhall',
        type: RouteEdgeType.exit,
        baseCost: 90,
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
