enum RouteEdgeType { ride, transfer, entry, exit }

class RouteNode {
  const RouteNode({
    required this.id,
    required this.stationId,
    required this.lineId,
  });

  final String id;
  final String stationId;
  final String lineId;
}

class RouteEdge {
  const RouteEdge({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.type,
    required this.baseCost,
    this.lineId = '',
    this.transferStationId = '',
    this.includesStairs = false,
    this.reliabilityScore = 100,
    this.isDataStale = false,
    this.isAvailable = true,
  });

  final String id;
  final String fromNodeId;
  final String toNodeId;
  final RouteEdgeType type;
  final int baseCost;
  final String lineId;
  final String transferStationId;
  final bool includesStairs;
  final int reliabilityScore;
  final bool isDataStale;
  final bool isAvailable;
}

class NetworkGraph {
  NetworkGraph({required List<RouteNode> nodes, required List<RouteEdge> edges})
    : nodes = List.unmodifiable(nodes),
      edges = List.unmodifiable(edges);

  final List<RouteNode> nodes;
  final List<RouteEdge> edges;

  Iterable<RouteEdge> edgesFrom(String nodeId) {
    return edges.where((edge) => edge.fromNodeId == nodeId);
  }
}
