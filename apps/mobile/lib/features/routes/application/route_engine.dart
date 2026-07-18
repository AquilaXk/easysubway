import 'package:collection/collection.dart';

import '../../../route_hedge_labels.dart';
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
    this.edgeResolver,
  }) : accessGraphRouter = AccessGraphRouter(
         graph: graph,
         costCalculator: costCalculator,
         edgeResolver: edgeResolver,
       ),
       routeAssembler = RouteAssembler(costCalculator: costCalculator);

  final NetworkGraph graph;
  final AccessibilityCostCalculator costCalculator;
  final RouteEdge Function(RouteEdge edge)? edgeResolver;
  final AccessGraphRouter accessGraphRouter;
  final RouteAssembler routeAssembler;

  LocalRouteResult search(RouteRequest request) {
    final pathResult = accessGraphRouter.findPath(
      originNodeId: request.originStationId,
      destinationNodeId: request.destinationStationId,
      mobilityType: request.mobilityType,
      constraintMode: request.effectiveConstraintMode,
      searchMode: request.searchMode,
      objective: request.objective,
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
    this.edgeResolver,
  });

  final NetworkGraph graph;
  final AccessibilityCostCalculator costCalculator;
  final RouteEdge Function(RouteEdge edge)? edgeResolver;

  AccessPathResult findPath({
    required String originNodeId,
    required String destinationNodeId,
    required MobilityType mobilityType,
    required ConstraintMode constraintMode,
    RouteSearchMode searchMode = RouteSearchMode.stationToStation,
    RouteObjective objective = RouteObjective.fastest,
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
      RouteTraversalPolicy(searchMode),
      blockedReasonCodes,
      objective,
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
    // 실측된 비가용(이용 어려움·보수중)은 '확인 불가'가 아니라 차단 사유다.
    if (reasonCodes.contains('FACILITY_UNAVAILABLE') ||
        reasonCodes.contains('FACILITY_UNDER_MAINTENANCE')) {
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

  /// fewestTransfers 목표에서 환승 edge마다 얹는 큰 사전식(lexicographic) 페널티.
  /// 어떤 대안 경로의 총 일반화 비용보다도 크게 잡아, 탐색이 환승 수를 1차로
  /// 최소화하고 동률에서만 일반화 비용(대체로 소요시간)으로 tie-break하게 한다.
  /// 이 페널티는 경로 선택에만 쓰이고 결과에 보고되는 비용에는 반영되지 않는다.
  static const int _fewestTransfersEdgePenalty = 100000000;

  List<RouteEdge>? _findLowestCostPath(
    String originNodeId,
    String destinationNodeId,
    MobilityType mobilityType,
    ConstraintMode constraintMode,
    RouteTraversalPolicy traversalPolicy,
    Set<String> blockedReasonCodes,
    RouteObjective objective,
  ) {
    final bestCostByNode = <String, int>{originNodeId: 0};
    final previousNode = <String, String>{};
    final previousEdge = <String, RouteEdge>{};
    var sequence = 0;
    final candidates =
        PriorityQueue<_RouteCandidate>((a, b) {
          final costComparison = a.cost.compareTo(b.cost);
          if (costComparison != 0) {
            return costComparison;
          }
          return a.sequence.compareTo(b.sequence);
        })..add(
          _RouteCandidate(nodeId: originNodeId, cost: 0, sequence: sequence++),
        );

    while (candidates.isNotEmpty) {
      final candidate = candidates.removeFirst();
      if (candidate.cost != bestCostByNode[candidate.nodeId]) {
        continue;
      }
      if (candidate.nodeId == destinationNodeId) {
        break;
      }

      for (final storedEdge in graph.edgesFrom(candidate.nodeId)) {
        final edge = edgeResolver?.call(storedEdge) ?? storedEdge;
        if (!traversalPolicy.canTraverse(
          edge,
          currentNodeId: candidate.nodeId,
          originNodeId: originNodeId,
          destinationNodeId: destinationNodeId,
        )) {
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
        var stepCost = edgeCost.cost;
        if (objective == RouteObjective.fewestTransfers &&
            isRouteTransferEdgeType(edge.type)) {
          stepCost += _fewestTransfersEdgePenalty;
        }
        final nextCost = candidate.cost + stepCost;
        if (nextCost < (bestCostByNode[edge.toNodeId] ?? 1 << 62)) {
          bestCostByNode[edge.toNodeId] = nextCost;
          previousNode[edge.toNodeId] = candidate.nodeId;
          previousEdge[edge.toNodeId] = edge;
          candidates.add(
            _RouteCandidate(
              nodeId: edge.toNodeId,
              cost: nextCost,
              sequence: sequence++,
            ),
          );
        }
      }
    }

    if (!bestCostByNode.containsKey(destinationNodeId)) {
      return null;
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
}

class _RouteCandidate {
  const _RouteCandidate({
    required this.nodeId,
    required this.cost,
    required this.sequence,
  });

  final String nodeId;
  final int cost;
  final int sequence;
}

class RouteTraversalPolicy {
  const RouteTraversalPolicy(this.searchMode);

  final RouteSearchMode searchMode;

  bool canTraverse(
    RouteEdge edge, {
    required String currentNodeId,
    required String originNodeId,
    required String destinationNodeId,
  }) {
    if (searchMode == RouteSearchMode.debugAllEdges ||
        searchMode == RouteSearchMode.stationInternal) {
      return true;
    }
    if (edge.type == RouteEdgeType.entry) {
      return currentNodeId == originNodeId;
    }
    if (edge.type == RouteEdgeType.exit) {
      return edge.toNodeId == destinationNodeId;
    }
    if (edge.type == RouteEdgeType.outOfStationTransfer) {
      return searchMode ==
          RouteSearchMode.stationToStationWithOutOfStationTransfers;
    }
    return true;
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
      searchMode: RouteSearchMode.stationInternal,
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
          servicePattern: edge.servicePattern,
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
      // 불확실성 헤지는 앱 공통 사전 한 벌로 통일한다(#1577). 연결 미확인의
      // '현장 안내를 먼저 봐 주세요' 둘째 문장은 결과 하단 각주와 중복이라 뺀다.
      'STAIR_ONLY_ACCESS_UNKNOWN' => routeHedgeStepFreeUnknown,
      'GENERATED_CONNECTOR_UNVERIFIED' => routeHedgeConnectivityUnknown,
      'BLOCKED_UNVERIFIED_EDGE' => '검증되지 않은 경로는 안내하지 않아요.',
      'BLOCKED_MISSING_EVIDENCE_HASH' => '검증 근거가 없는 경로는 안내하지 않아요.',
      'BLOCKED_PLACEHOLDER_EVIDENCE_HASH' => '임시 근거만 있는 경로는 안내하지 않아요.',
      'BLOCKED_UNSUPPORTED_SCOPE' => '지원 범위 밖 경로는 안내하지 않아요.',
      'STRICT_EVIDENCE_UNSUPPORTED' => '검증 근거가 부족해 계단 없는 경로로 안내하지 않아요.',
      'DURATION_UNKNOWN' => routeDurationUnknown,
      'ACCESSIBILITY_STATE_UNKNOWN' => routeHedgeAccessibilityUnknown,
      'FACILITY_UNDER_MAINTENANCE' => routeFacilityUnderMaintenance,
      'FACILITY_UNAVAILABLE' => routeFacilityUnavailable,
      'ROUTE_GRAPH_UNKNOWN' => routeHedgeConnectivityUnknown,
      _ => '이동 전 현장 안내를 확인해 주세요.',
    };
  }
}

List<String> _routeEvidenceSources(RouteEdge edge) {
  return [
    'edge:${edge.id}',
    if (edge.isGeneratedConnector) 'GENERATED_CONNECTOR',
    if (edge.lineId.isNotEmpty) 'line:${edge.lineId}',
    if (edge.safetyEvidence.sourceId.isNotEmpty)
      'source:${edge.safetyEvidence.sourceId}',
    if (edge.safetyEvidence.sourceSnapshotId.isNotEmpty)
      'snapshot:${edge.safetyEvidence.sourceSnapshotId}',
  ];
}
