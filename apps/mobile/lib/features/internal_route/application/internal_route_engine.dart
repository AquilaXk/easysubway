import '../../routes/domain/route_request.dart';
import '../../routes/domain/route_result.dart';

class InternalRouteNode {
  const InternalRouteNode({
    required this.id,
    required this.stationId,
    required this.name,
  });

  final String id;
  final String stationId;
  final String name;
}

class InternalRouteEdge {
  const InternalRouteEdge({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    this.edgeType = 'WALK',
    required this.distanceMeters,
    required this.estimatedSeconds,
    required this.guidance,
    this.includesStairs = false,
    this.requiresElevator = false,
    this.requiresEscalator = false,
    this.slopeLevel = 1,
    this.widthLevel = 2,
    this.reliabilityScore = 100,
    this.isFacilityAvailable = true,
    this.accessibilityStatus = 'AVAILABLE',
  });

  final String id;
  final String fromNodeId;
  final String toNodeId;
  final String edgeType;
  final int distanceMeters;
  final int estimatedSeconds;
  final String guidance;
  final bool includesStairs;
  final bool requiresElevator;
  final bool requiresEscalator;
  final int slopeLevel;
  final int widthLevel;
  final int reliabilityScore;
  final bool isFacilityAvailable;
  final String accessibilityStatus;
}

class InternalRouteGraph {
  InternalRouteGraph({
    required List<InternalRouteNode> nodes,
    required List<InternalRouteEdge> edges,
  }) : nodes = List.unmodifiable(nodes),
       edges = List.unmodifiable(edges);

  final List<InternalRouteNode> nodes;
  final List<InternalRouteEdge> edges;

  Iterable<InternalRouteEdge> edgesFrom(String nodeId) {
    return edges.where((edge) => edge.fromNodeId == nodeId);
  }
}

class LocalInternalRouteEngine {
  const LocalInternalRouteEngine({required this.graph});

  final InternalRouteGraph graph;

  LocalInternalRouteResult search(InternalRouteSearchRequest request) {
    final blockedReasonCodes = <String>{};
    final path = _findLowestTimePath(
      request.fromNodeId,
      request.toNodeId,
      request.mobilityType,
      blockedReasonCodes,
    );
    if (path == null) {
      return LocalInternalRouteResult.blocked(
        blockedReasonCodes.isEmpty
            ? const ['STAIR_ONLY_ACCESS']
            : blockedReasonCodes.toList(growable: false),
      );
    }

    final warningCodes = <String>{};
    var totalDistance = 0;
    var totalSeconds = 0;
    var includesStairs = false;

    for (final edge in path) {
      totalDistance += edge.distanceMeters;
      totalSeconds += edge.estimatedSeconds;
      includesStairs = includesStairs || edge.includesStairs;
      if (edge.reliabilityScore < 80) {
        warningCodes.add('LOW_DATA_CONFIDENCE');
      }
    }

    return LocalInternalRouteResult(
      status: RouteStatus.found,
      totalDistanceMeters: totalDistance,
      totalEstimatedSeconds: totalSeconds,
      edgeIds: path.map((edge) => edge.id).toList(growable: false),
      warningCodes: warningCodes.toList(growable: false),
      blockedReasonCodes: const [],
      includesStairs: includesStairs,
    );
  }

  List<InternalRouteEdge>? _findLowestTimePath(
    String originNodeId,
    String destinationNodeId,
    MobilityType mobilityType,
    Set<String> blockedReasonCodes,
  ) {
    final costs = <String, int>{originNodeId: 0};
    final previousNode = <String, String>{};
    final previousEdge = <String, InternalRouteEdge>{};
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
        if (_isBlocked(edge, mobilityType, blockedReasonCodes)) {
          continue;
        }
        final nextCost = costs[current]! + edge.estimatedSeconds;
        if (nextCost < (costs[edge.toNodeId] ?? 1 << 62)) {
          costs[edge.toNodeId] = nextCost;
          previousNode[edge.toNodeId] = current;
          previousEdge[edge.toNodeId] = edge;
        }
      }
    }

    final reversed = <InternalRouteEdge>[];
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

  bool _isBlocked(
    InternalRouteEdge edge,
    MobilityType mobilityType,
    Set<String> blockedReasonCodes,
  ) {
    final accessibilityStatus = edge.accessibilityStatus.toUpperCase();
    if (edge.includesStairs && mobilityType.blocksStairOnlyAccess) {
      blockedReasonCodes.add('STAIR_ONLY_ACCESS');
      return true;
    }
    if (!edge.isFacilityAvailable || accessibilityStatus == 'UNAVAILABLE') {
      blockedReasonCodes.add('FACILITY_UNAVAILABLE');
      return true;
    }
    if (accessibilityStatus == 'UNKNOWN' &&
        mobilityType.blocksStairOnlyAccess) {
      blockedReasonCodes.add('ACCESSIBILITY_STATE_UNKNOWN');
      return true;
    }
    return false;
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
