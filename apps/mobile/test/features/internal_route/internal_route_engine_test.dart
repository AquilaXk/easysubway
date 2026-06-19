import 'package:easysubway_mobile/features/internal_route/application/internal_route_engine.dart';
import 'package:easysubway_mobile/features/routes/domain/route_request.dart';
import 'package:easysubway_mobile/features/routes/domain/route_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalInternalRouteEngine', () {
    test('역 내부 이동 경로를 거리, 시간, 접근성 속성과 함께 계산한다', () {
      final engine = LocalInternalRouteEngine(graph: _internalFixtureGraph());

      final result = engine.search(
        const InternalRouteSearchRequest(
          stationId: 'station-sangnoksu',
          fromNodeId: 'node-sangnoksu-elevator',
          toNodeId: 'node-sangnoksu-platform',
          mobilityType: MobilityType.wheelchair,
        ),
      );

      expect(result.status, RouteStatus.found);
      expect(result.edgeIds, [
        'edge-elevator-to-faregate',
        'edge-faregate-to-platform',
      ]);
      expect(result.totalDistanceMeters, 64);
      expect(result.totalEstimatedSeconds, 150);
      expect(result.includesStairs, isFalse);
      expect(result.blockedReasonCodes, isEmpty);
      expect(result.warningCodes, isEmpty);
    });

    test('엘리베이터 고장으로 계단만 남은 내부 이동은 차단한다', () {
      final engine = LocalInternalRouteEngine(graph: _blockedInternalGraph());

      final result = engine.search(
        const InternalRouteSearchRequest(
          stationId: 'station-sangnoksu',
          fromNodeId: 'node-sangnoksu-entrance',
          toNodeId: 'node-sangnoksu-platform',
          mobilityType: MobilityType.wheelchair,
        ),
      );

      expect(result.status, RouteStatus.blocked);
      expect(result.edgeIds, isEmpty);
      expect(result.totalDistanceMeters, 0);
      expect(result.totalEstimatedSeconds, 0);
      expect(result.includesStairs, isFalse);
      expect(result.blockedReasonCodes, ['STAIR_ONLY_ACCESS']);
    });
  });
}

InternalRouteGraph _internalFixtureGraph() {
  return InternalRouteGraph(
    nodes: const [
      InternalRouteNode(
        id: 'node-sangnoksu-elevator',
        stationId: 'station-sangnoksu',
        name: '1번 출구 엘리베이터',
      ),
      InternalRouteNode(
        id: 'node-sangnoksu-faregate',
        stationId: 'station-sangnoksu',
        name: '개찰구',
      ),
      InternalRouteNode(
        id: 'node-sangnoksu-platform',
        stationId: 'station-sangnoksu',
        name: '4호선 승강장',
      ),
    ],
    edges: const [
      InternalRouteEdge(
        id: 'edge-elevator-to-faregate',
        fromNodeId: 'node-sangnoksu-elevator',
        toNodeId: 'node-sangnoksu-faregate',
        distanceMeters: 28,
        estimatedSeconds: 75,
        requiresElevator: true,
        guidance: '엘리베이터에서 개찰구까지 이동합니다.',
      ),
      InternalRouteEdge(
        id: 'edge-faregate-to-platform',
        fromNodeId: 'node-sangnoksu-faregate',
        toNodeId: 'node-sangnoksu-platform',
        distanceMeters: 36,
        estimatedSeconds: 75,
        guidance: '넓은 통로를 따라 승강장으로 이동합니다.',
      ),
    ],
  );
}

InternalRouteGraph _blockedInternalGraph() {
  return InternalRouteGraph(
    nodes: const [
      InternalRouteNode(
        id: 'node-sangnoksu-entrance',
        stationId: 'station-sangnoksu',
        name: '계단 출입구',
      ),
      InternalRouteNode(
        id: 'node-sangnoksu-platform',
        stationId: 'station-sangnoksu',
        name: '4호선 승강장',
      ),
    ],
    edges: const [
      InternalRouteEdge(
        id: 'edge-stairs-to-platform',
        fromNodeId: 'node-sangnoksu-entrance',
        toNodeId: 'node-sangnoksu-platform',
        distanceMeters: 42,
        estimatedSeconds: 120,
        includesStairs: true,
        isFacilityAvailable: false,
        guidance: '계단만 있는 출입구입니다.',
      ),
    ],
  );
}
