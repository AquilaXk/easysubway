enum RouteStepType {
  ride,
  transfer,
  inStationTransfer,
  outOfStationTransfer,
  entry,
  exit,
  walkway,
  elevator,
  ramp,
  stair,
  escalator,
  facilityConnector,
  internal,
  waypoint,
}

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
    this.servicePattern = '',
    this.transferStationId = '',
    this.includesStairs = false,
    this.stairAccessState = 'unknown',
    this.evidenceSources = const [],
    this.timeSource = 'UNKNOWN',
    this.distanceSource = 'UNKNOWN',
    this.confidenceLabel = '',
    this.accessibilityVerified = false,
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
  final String servicePattern;
  final String transferStationId;
  final bool includesStairs;
  final String stairAccessState;
  final List<String> evidenceSources;
  final String timeSource;
  final String distanceSource;
  final String confidenceLabel;

  /// 이 구간의 접근성이 실제로 검증된 근거를 갖는지(#2590). 표시 계층의
  /// `requiresAccessibilityCheck`가 이 값에서 파생되므로 근거를 아는 곳,
  /// 즉 그래프 edge를 손에 쥔 라우터에서만 채운다. 기본값은 fail closed다.
  final bool accessibilityVerified;
}
