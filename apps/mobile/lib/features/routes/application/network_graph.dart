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
      edges = List.unmodifiable(edges),
      _edgesByFromNodeId = _indexEdgesByFromNodeId(edges);

  final List<RouteNode> nodes;
  final List<RouteEdge> edges;
  final Map<String, List<RouteEdge>> _edgesByFromNodeId;

  Iterable<RouteEdge> edgesFrom(String nodeId) {
    return _edgesByFromNodeId[nodeId] ?? const [];
  }
}

Map<String, List<RouteEdge>> _indexEdgesByFromNodeId(List<RouteEdge> edges) {
  final indexed = <String, List<RouteEdge>>{};
  for (final edge in edges) {
    indexed.putIfAbsent(edge.fromNodeId, () => <RouteEdge>[]).add(edge);
  }
  return {
    for (final entry in indexed.entries)
      entry.key: List.unmodifiable(entry.value),
  };
}
