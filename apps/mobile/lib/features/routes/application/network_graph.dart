enum RouteEdgeType { ride, transfer, entry, exit }

enum RouteAccessibilityState { available, unavailable, unknown }

enum RouteStairAccessState { stepFree, stairOnly, unknown }

class RouteEdgeSafetyEvidence {
  const RouteEdgeSafetyEvidence({
    required this.sourceId,
    required this.sourceSnapshotId,
    required this.providerRecordHash,
    required this.provenanceKind,
    required this.verificationStatus,
    required this.evidenceHash,
    required this.evidenceHashValid,
    required this.isPlaceholderEvidence,
    required this.lastVerifiedAt,
    required this.isStale,
    required this.isGeneratedConnector,
    required this.strictRouteEligible,
    required this.blockerReasons,
  });

  const RouteEdgeSafetyEvidence.verified()
    : sourceId = '',
      sourceSnapshotId = '',
      providerRecordHash = '',
      provenanceKind = 'OFFICIAL_SOURCE',
      verificationStatus = 'VERIFIED',
      evidenceHash = '',
      evidenceHashValid = true,
      isPlaceholderEvidence = false,
      lastVerifiedAt = null,
      isStale = false,
      isGeneratedConnector = false,
      strictRouteEligible = true,
      blockerReasons = const [];

  final String sourceId;
  final String sourceSnapshotId;
  final String providerRecordHash;
  final String provenanceKind;
  final String verificationStatus;
  final String evidenceHash;
  final bool evidenceHashValid;
  final bool isPlaceholderEvidence;
  final DateTime? lastVerifiedAt;
  final bool isStale;
  final bool isGeneratedConnector;
  final bool strictRouteEligible;
  final List<String> blockerReasons;
}

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
    int? durationSeconds,
    this.distanceMeters = 0,
    this.lineId = '',
    this.transferStationId = '',
    bool? includesStairs,
    RouteStairAccessState? stairAccessState,
    this.reliabilityScore = 100,
    this.isDataStale = false,
    this.isGeneratedConnector = false,
    this.safetyEvidence = const RouteEdgeSafetyEvidence.verified(),
    RouteAccessibilityState accessibilityState =
        RouteAccessibilityState.available,
    bool? isAvailable,
  }) : durationSeconds = durationSeconds ?? baseCost,
       stairAccessState =
           stairAccessState ??
           (includesStairs == true
               ? RouteStairAccessState.stairOnly
               : type == RouteEdgeType.ride
               ? RouteStairAccessState.stepFree
               : RouteStairAccessState.unknown),
       includesStairs = stairAccessState == null
           ? includesStairs ?? false
           : stairAccessState == RouteStairAccessState.stairOnly,
       accessibilityState = isAvailable == null
           ? accessibilityState
           : isAvailable
           ? RouteAccessibilityState.available
           : RouteAccessibilityState.unavailable;

  final String id;
  final String fromNodeId;
  final String toNodeId;
  final RouteEdgeType type;

  /// route contract: baseCost seconds
  ///
  /// `baseCost` is the routing weight in seconds before profile penalties.
  /// `durationSeconds` may stay 0 when source data has no reliable duration,
  /// but route ordering still needs a positive fallback weight.
  final int baseCost;
  final int durationSeconds;
  final int distanceMeters;
  final String lineId;
  final String transferStationId;
  final bool includesStairs;
  final RouteStairAccessState stairAccessState;

  /// route contract: reliability thresholds
  ///
  /// 100 means verified or default confidence, values below 80 trigger a
  /// low-confidence penalty, and UNKNOWN source accessibility data is capped
  /// by the repository before it reaches the route engine.
  final int reliabilityScore;
  final bool isDataStale;
  final bool isGeneratedConnector;
  final RouteEdgeSafetyEvidence safetyEvidence;
  final RouteAccessibilityState accessibilityState;

  bool get isAvailable =>
      accessibilityState == RouteAccessibilityState.available;
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

  /// route contract: generated connector ratio
  ///
  /// Generated entry, exit, and transfer connector edges are source gaps, not
  /// verified step-free coverage. Report their share separately from
  /// accessibility availability metrics.
  double get generatedConnectorEdgeRatio {
    if (edges.isEmpty) {
      return 0;
    }
    final generatedCount = edges
        .where((edge) => edge.isGeneratedConnector)
        .length;
    return generatedCount / edges.length;
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
