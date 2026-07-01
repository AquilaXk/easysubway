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
  }) : accessGraphRouter = AccessGraphRouter(
         graph: graph,
         costCalculator: costCalculator,
       ),
       routeAssembler = RouteAssembler(costCalculator: costCalculator);

  final NetworkGraph graph;
  final AccessibilityCostCalculator costCalculator;
  final AccessGraphRouter accessGraphRouter;
  final RouteAssembler routeAssembler;

  LocalRouteResult search(RouteRequest request) {
    final pathResult = accessGraphRouter.findPath(
      originNodeId: request.originStationId,
      destinationNodeId: request.destinationStationId,
      mobilityType: request.mobilityType,
      constraintMode: request.effectiveConstraintMode,
    );
    final path = pathResult.path;
    if (path == null) {
      if (pathResult.noPathReason != AccessNoPathReason.blocked) {
        return LocalRouteResult.unknown(pathResult.reasonCodes);
      }
      return LocalRouteResult.blocked(pathResult.reasonCodes);
    }

    final weight = RouteWeight.from(request.mobilityType);
    final assembled = routeAssembler.assemble(
      path,
      request.mobilityType,
      constraintMode: request.effectiveConstraintMode,
    );

    return LocalRouteResult(
      status: RouteStatus.found,
      totalCost: weight.baseAccessCost + assembled.totalCost,
      steps: assembled.steps,
      warnings: assembled.warnings,
      blockedReasonCodes: const [],
    );
  }
}

enum AccessNoPathReason { blocked, unknown, unsupported, noData }

class AccessPathResult {
  const AccessPathResult._({
    required this.path,
    required this.noPathReason,
    required this.reasonCodes,
  });

  factory AccessPathResult.found(AccessPath path) {
    return AccessPathResult._(
      path: path,
      noPathReason: null,
      reasonCodes: const [],
    );
  }

  factory AccessPathResult.noPath({
    required AccessNoPathReason reason,
    required List<String> reasonCodes,
  }) {
    return AccessPathResult._(
      path: null,
      noPathReason: reason,
      reasonCodes: List.unmodifiable(reasonCodes),
    );
  }

  final AccessPath? path;
  final AccessNoPathReason? noPathReason;
  final List<String> reasonCodes;
}

class AccessPath {
  const AccessPath({required this.edges});

  final List<RouteEdge> edges;

  int get entrySeconds => _secondsForTypes({RouteEdgeType.entry});

  int get transferSeconds => _secondsForTypes({
    RouteEdgeType.inStationTransfer,
    RouteEdgeType.outOfStationTransfer,
  });

  int get egressSeconds => _secondsForTypes({RouteEdgeType.exit});

  List<String> get edgeIds =>
      edges.map((edge) => edge.id).toList(growable: false);

  List<String> get evidenceSources =>
      edges.expand(_routeEvidenceSources).toSet().toList(growable: false);

  int _secondsForTypes(Set<RouteEdgeType> types) {
    return edges
        .where((edge) => types.contains(edge.type))
        .fold(0, (total, edge) => total + edge.durationSeconds);
  }
}

class AccessGraphRouter {
  const AccessGraphRouter({
    required this.graph,
    this.costCalculator = const AccessibilityCostCalculator(),
  });

  final NetworkGraph graph;
  final AccessibilityCostCalculator costCalculator;

  AccessPathResult findPath({
    required String originNodeId,
    required String destinationNodeId,
    required MobilityType mobilityType,
    required ConstraintMode constraintMode,
  }) {
    if (graph.nodes.isEmpty || graph.edges.isEmpty) {
      return AccessPathResult.noPath(
        reason: AccessNoPathReason.noData,
        reasonCodes: const ['NO_DATA'],
      );
    }

    final blockedReasonCodes = <String>{};
    final edges = _findLowestCostPath(
      originNodeId,
      destinationNodeId,
      mobilityType,
      constraintMode,
      blockedReasonCodes,
    );
    if (edges != null) {
      return AccessPathResult.found(
        AccessPath(edges: List.unmodifiable(edges)),
      );
    }

    final reasonCodes = blockedReasonCodes.isEmpty
        ? const ['ROUTE_GRAPH_UNKNOWN']
        : blockedReasonCodes.toList(growable: false);
    return AccessPathResult.noPath(
      reason: _noPathReason(reasonCodes),
      reasonCodes: reasonCodes,
    );
  }

  bool _hasUnknownRouteReason(List<String> reasonCodes) {
    if (reasonCodes.contains('FACILITY_UNAVAILABLE')) {
      return false;
    }
    const unknownCodes = {
      'ACCESSIBILITY_STATE_UNKNOWN',
      'STAIR_ONLY_ACCESS_UNKNOWN',
      'GENERATED_CONNECTOR_UNVERIFIED',
      'STALE_ACCESSIBILITY_DATA',
      'BLOCKED_UNVERIFIED_EDGE',
      'BLOCKED_MISSING_EVIDENCE_HASH',
      'BLOCKED_PLACEHOLDER_EVIDENCE_HASH',
      'BLOCKED_UNSUPPORTED_SCOPE',
      'STRICT_EVIDENCE_UNSUPPORTED',
      'ROUTE_GRAPH_UNKNOWN',
    };
    return reasonCodes.isNotEmpty &&
        reasonCodes.any((code) => unknownCodes.contains(code));
  }

  AccessNoPathReason _noPathReason(List<String> reasonCodes) {
    if (reasonCodes.contains('NO_DATA')) {
      return AccessNoPathReason.noData;
    }
    if (reasonCodes.contains('BLOCKED_UNSUPPORTED_SCOPE') ||
        reasonCodes.contains('STRICT_EVIDENCE_UNSUPPORTED')) {
      return AccessNoPathReason.unsupported;
    }
    if (_hasUnknownRouteReason(reasonCodes)) {
      return AccessNoPathReason.unknown;
    }
    return AccessNoPathReason.blocked;
  }

  List<RouteEdge>? _findLowestCostPath(
    String originNodeId,
    String destinationNodeId,
    MobilityType mobilityType,
    ConstraintMode constraintMode,
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
        final edgeCost = costCalculator.costFor(
          edge,
          mobilityType,
          constraintMode: constraintMode,
        );
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
}

class StationPathwayRouter {
  const StationPathwayRouter({required this.accessGraphRouter});

  final AccessGraphRouter accessGraphRouter;

  AccessPathResult findPathway({
    required String stationId,
    required String fromNodeId,
    required String toNodeId,
    required MobilityType mobilityType,
    required ConstraintMode constraintMode,
  }) {
    return accessGraphRouter.findPath(
      originNodeId: fromNodeId,
      destinationNodeId: toNodeId,
      mobilityType: mobilityType,
      constraintMode: constraintMode,
    );
  }
}

class TransferAccess {
  const TransferAccess({
    required this.path,
    required this.transferReadyAtSeconds,
    required this.slackSeconds,
    required this.isFeasible,
  });

  final AccessPath path;
  final int transferReadyAtSeconds;
  final int slackSeconds;
  final bool isFeasible;
}

class TransferAccessResolver {
  const TransferAccessResolver();

  TransferAccess resolve({
    required AccessPath path,
    required int alightAtSeconds,
    required int nextDepartureSeconds,
  }) {
    final transferReadyAtSeconds = alightAtSeconds + path.transferSeconds;
    return TransferAccess(
      path: path,
      transferReadyAtSeconds: transferReadyAtSeconds,
      slackSeconds: nextDepartureSeconds - transferReadyAtSeconds,
      isFeasible: nextDepartureSeconds >= transferReadyAtSeconds,
    );
  }
}

class AssembledRoute {
  const AssembledRoute({
    required this.totalCost,
    required this.steps,
    required this.warnings,
  });

  final int totalCost;
  final List<RouteStep> steps;
  final List<RouteWarning> warnings;
}

class RouteAssembler {
  const RouteAssembler({
    this.costCalculator = const AccessibilityCostCalculator(),
  });

  final AccessibilityCostCalculator costCalculator;

  AssembledRoute assemble(
    AccessPath path,
    MobilityType mobilityType, {
    required ConstraintMode constraintMode,
  }) {
    final warnings = <String, RouteWarning>{};
    var totalCost = 0;
    final steps = <RouteStep>[];
    for (final edge in path.edges) {
      final accessCost = costCalculator.costFor(
        edge,
        mobilityType,
        constraintMode: constraintMode,
      );
      totalCost += accessCost.cost;
      if (edge.type == RouteEdgeType.outOfStationTransfer) {
        warnings['FARE_EXIT_REENTRY_REQUIRED'] = const RouteWarning(
          code: 'FARE_EXIT_REENTRY_REQUIRED',
          message: '역 밖 환승은 요금구역을 나가 다시 들어갈 수 있어요.',
        );
      }
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
          durationSeconds: edge.durationSeconds,
          distanceMeters: edge.distanceMeters,
          lineId: edge.lineId,
          transferStationId: _transferStationId(edge),
          includesStairs: edge.includesStairs,
          stairAccessState: edge.stairAccessState.name,
          evidenceSources: _routeEvidenceSources(edge),
          timeSource: edge.durationSeconds > 0 ? 'STATIC_ESTIMATE' : 'UNKNOWN',
          distanceSource: edge.distanceMeters > 0 ? 'MEASURED' : 'UNKNOWN',
          confidenceLabel: _confidenceLabel(edge),
        ),
      );
    }

    return AssembledRoute(
      totalCost: totalCost,
      steps: List.unmodifiable(steps),
      warnings: List.unmodifiable(warnings.values),
    );
  }

  RouteStepType _stepType(RouteEdgeType edgeType) {
    return switch (edgeType) {
      RouteEdgeType.ride => RouteStepType.ride,
      RouteEdgeType.inStationTransfer => RouteStepType.inStationTransfer,
      RouteEdgeType.outOfStationTransfer => RouteStepType.outOfStationTransfer,
      RouteEdgeType.entry => RouteStepType.entry,
      RouteEdgeType.exit => RouteStepType.exit,
      RouteEdgeType.walkway => RouteStepType.walkway,
      RouteEdgeType.elevator => RouteStepType.elevator,
      RouteEdgeType.ramp => RouteStepType.ramp,
      RouteEdgeType.stair => RouteStepType.stair,
      RouteEdgeType.escalator => RouteStepType.escalator,
      RouteEdgeType.facilityConnector => RouteStepType.facilityConnector,
    };
  }

  String _transferStationId(RouteEdge edge) {
    if (edge.transferStationId.isNotEmpty) {
      return edge.transferStationId;
    }
    if (!isRouteTransferEdgeType(edge.type)) {
      return '';
    }
    if (edge.fromNodeId == edge.toNodeId) {
      return '';
    }
    final fromStationId = _stationIdFromNode(edge.fromNodeId);
    final toStationId = _stationIdFromNode(edge.toNodeId);
    if (fromStationId.isEmpty || fromStationId != toStationId) {
      return '';
    }
    final fromLineId = _lineIdFromNode(edge.fromNodeId);
    final toLineId = _lineIdFromNode(edge.toNodeId);
    if (fromLineId.isEmpty || toLineId.isEmpty || fromLineId == toLineId) {
      return '';
    }
    return fromStationId;
  }

  String _stationIdFromNode(String nodeId) {
    return nodeId.split(':').first;
  }

  String _lineIdFromNode(String nodeId) {
    final parts = nodeId.split(':');
    return parts.length >= 2 ? parts[1] : '';
  }

  String _confidenceLabel(RouteEdge edge) {
    if (edge.isGeneratedConnector ||
        edge.durationSeconds <= 0 ||
        edge.isDataStale ||
        edge.accessibilityState == RouteAccessibilityState.unknown ||
        edge.stairAccessState == RouteStairAccessState.unknown) {
      return '안내를 준비 중이에요';
    }
    if (edge.reliabilityScore >= 80) {
      return '확인된 정보예요';
    }
    if (edge.reliabilityScore >= 60) {
      return '일부 확인된 정보예요';
    }
    return '안내를 준비 중이에요';
  }

  String _warningMessage(String code) {
    return switch (code) {
      'LOW_DATA_CONFIDENCE' => '일부 시설 안내를 준비 중이에요.',
      'STALE_ACCESSIBILITY_DATA' => '시설 상태 안내가 오래됐을 수 있어요.',
      'STAIR_ONLY_ACCESS' => '계단 포함 구간이 있습니다.',
      'STAIR_ONLY_ACCESS_UNKNOWN' => '계단 없는 길인지 아직 알 수 없어요.',
      'GENERATED_CONNECTOR_UNVERIFIED' =>
        '연결 위치를 아직 정확히 확인하지 못했어요. 현장 안내를 먼저 봐 주세요.',
      'BLOCKED_UNVERIFIED_EDGE' => '검증되지 않은 경로는 안내하지 않아요.',
      'BLOCKED_MISSING_EVIDENCE_HASH' => '검증 근거가 없는 경로는 안내하지 않아요.',
      'BLOCKED_PLACEHOLDER_EVIDENCE_HASH' => '임시 근거만 있는 경로는 안내하지 않아요.',
      'BLOCKED_UNSUPPORTED_SCOPE' => '지원 범위 밖 경로는 안내하지 않아요.',
      'STRICT_EVIDENCE_UNSUPPORTED' => '검증 근거가 부족해 계단 없는 경로로 안내하지 않아요.',
      'DURATION_UNKNOWN' => '소요 시간을 확인하고 있어요.',
      'ACCESSIBILITY_STATE_UNKNOWN' => '엘리베이터와 통로 상태를 아직 알 수 없어요.',
      'ROUTE_GRAPH_UNKNOWN' => '길이 이어지는지 아직 확인하지 못했어요.',
      _ => '이동 전 현장 안내를 확인해 주세요.',
    };
  }
}

List<String> _routeEvidenceSources(RouteEdge edge) {
  return [
    'edge:${edge.id}',
    if (edge.isGeneratedConnector) 'GENERATED_CONNECTOR',
    if (edge.lineId.isNotEmpty) 'line:${edge.lineId}',
  ];
}
