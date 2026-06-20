enum RouteStepType { ride, transfer, entry, exit, internal }

class RouteStep {
  const RouteStep({
    required this.sequence,
    required this.edgeId,
    required this.fromNodeId,
    required this.toNodeId,
    required this.type,
    required this.cost,
    required this.durationSeconds,
    this.distanceMeters = 0,
    this.lineId = '',
    this.transferStationId = '',
    this.includesStairs = false,
  });

  final int sequence;
  final String edgeId;
  final String fromNodeId;
  final String toNodeId;
  final RouteStepType type;
  final int cost;
  final int durationSeconds;
  final int distanceMeters;
  final String lineId;
  final String transferStationId;
  final bool includesStairs;
}
