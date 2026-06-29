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
    this.stairAccessState = 'unknown',
    this.evidenceSources = const [],
    this.timeSource = 'UNKNOWN',
    this.distanceSource = 'UNKNOWN',
    this.confidenceLabel = '정보가 부족해요',
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
  final String stairAccessState;
  final List<String> evidenceSources;
  final String timeSource;
  final String distanceSource;
  final String confidenceLabel;
}
