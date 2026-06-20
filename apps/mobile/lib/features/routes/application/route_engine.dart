import '../domain/route_request.dart';
import '../domain/route_result.dart';
import '../domain/route_step.dart';
import '../domain/route_weight.dart';
import 'accessibility_cost_calculator.dart';
import 'network_graph.dart';

class LocalRouteEngine {
  LocalRouteEngine({
    required this.graph,
    this.costCalculator = const AccessibilityCostCalculator(),
  });

  final NetworkGraph graph;
  final AccessibilityCostCalculator costCalculator;

  LocalRouteResult search(RouteRequest request) {
    final blockedReasonCodes = <String>{};
    final path = _findLowestCostPath(
      request.originStationId,
      request.destinationStationId,
      request.mobilityType,
      blockedReasonCodes,
    );
    if (path == null) {
      return LocalRouteResult.blocked(
        blockedReasonCodes.isEmpty
            ? const ['STAIR_ONLY_ACCESS']
            : blockedReasonCodes.toList(growable: false),
      );
    }

    final weight = RouteWeight.from(request.mobilityType);
    final warnings = <String, RouteWarning>{};
    var totalCost = weight.baseAccessCost;
    final steps = <RouteStep>[];

    for (final edge in path) {
      final accessCost = costCalculator.costFor(edge, request.mobilityType);
      totalCost += accessCost.cost;
      for (final code in accessCost.warningCodes) {
        warnings[code] = RouteWarning(
          code: code,
          message: _warningMessage(code),
        );
      }
      steps.add(
        RouteStep(
          sequence: steps.length + 1,
          edgeId: edge.id,
          fromNodeId: edge.fromNodeId,
          toNodeId: edge.toNodeId,
          type: _stepType(edge.type),
          cost: accessCost.cost,
          durationSeconds: edge.baseCost,
          lineId: edge.lineId,
          transferStationId: edge.transferStationId,
          includesStairs: edge.includesStairs,
        ),
      );
    }

    return LocalRouteResult(
      status: RouteStatus.found,
      totalCost: totalCost,
      steps: List.unmodifiable(steps),
      warnings: List.unmodifiable(warnings.values),
      blockedReasonCodes: const [],
    );
  }

  List<RouteEdge>? _findLowestCostPath(
    String originNodeId,
    String destinationNodeId,
    MobilityType mobilityType,
    Set<String> blockedReasonCodes,
  ) {
    final costs = <String, int>{originNodeId: 0};
    final previousNode = <String, String>{};
    final previousEdge = <String, RouteEdge>{};
    final visited = <String>{};

    while (true) {
      final current = _lowestUnvisitedNode(costs, visited);
      if (current == null) {
        return null;
      }
      if (current == destinationNodeId) {
        break;
      }
      visited.add(current);

      for (final edge in graph.edgesFrom(current)) {
        if (edge.type == RouteEdgeType.entry && current != originNodeId) {
          continue;
        }
        if (edge.type == RouteEdgeType.exit &&
            edge.toNodeId != destinationNodeId) {
          continue;
        }
        final edgeCost = costCalculator.costFor(edge, mobilityType);
        if (edgeCost.isBlocked) {
          blockedReasonCodes.addAll(edgeCost.warningCodes);
          continue;
        }
        final nextCost = costs[current]! + edgeCost.cost;
        if (nextCost < (costs[edge.toNodeId] ?? 1 << 62)) {
          costs[edge.toNodeId] = nextCost;
          previousNode[edge.toNodeId] = current;
          previousEdge[edge.toNodeId] = edge;
        }
      }
    }

    final reversed = <RouteEdge>[];
    var nodeId = destinationNodeId;
    while (nodeId != originNodeId) {
      final edge = previousEdge[nodeId];
      final prev = previousNode[nodeId];
      if (edge == null || prev == null) {
        return null;
      }
      reversed.add(edge);
      nodeId = prev;
    }

    return reversed.reversed.toList(growable: false);
  }

  String? _lowestUnvisitedNode(Map<String, int> costs, Set<String> visited) {
    String? selected;
    var selectedCost = 1 << 62;
    for (final entry in costs.entries) {
      if (visited.contains(entry.key)) {
        continue;
      }
      if (entry.value < selectedCost) {
        selected = entry.key;
        selectedCost = entry.value;
      }
    }
    return selected;
  }

  RouteStepType _stepType(RouteEdgeType edgeType) {
    return switch (edgeType) {
      RouteEdgeType.ride => RouteStepType.ride,
      RouteEdgeType.transfer => RouteStepType.transfer,
      RouteEdgeType.entry => RouteStepType.entry,
      RouteEdgeType.exit => RouteStepType.exit,
    };
  }

  String _warningMessage(String code) {
    return switch (code) {
      'LOW_DATA_CONFIDENCE' => '일부 시설 정보는 확인이 필요합니다.',
      'STALE_ACCESSIBILITY_DATA' => '접근성 시설 정보가 최근 확인되지 않았습니다.',
      'STAIR_ONLY_ACCESS' => '계단 포함 구간이 있습니다.',
      _ => '이동 전 현장 안내를 확인해 주세요.',
    };
  }
}
