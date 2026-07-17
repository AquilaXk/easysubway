enum MobilityType {
  senior,
  stroller,
  wheelchair,
  pregnant,
  temporaryInjury,
  luggage;

  ConstraintMode get defaultConstraintMode => this == MobilityType.wheelchair
      ? ConstraintMode.strictStepFree
      : ConstraintMode.preferStepFree;

  bool blocksStairOnlyAccess(ConstraintMode? mode) =>
      (mode ?? defaultConstraintMode) == ConstraintMode.strictStepFree;
}

enum ConstraintMode { strictStepFree, preferStepFree, allowWithWarnings }

enum RouteSearchMode {
  stationToStation,
  stationToStationWithOutOfStationTransfers,
  stationInternal,
  debugAllEdges,
}

/// 로컬 탐색 최적화 목표. fastest는 기존 일반화 비용 최소화(기본), fewestTransfers는
/// 환승 수를 우선 최소화하고 동률이면 일반화 비용이 낮은(대체로 소요시간이 짧은)
/// 경로를 고른다.
enum RouteObjective { fastest, fewestTransfers }

class RouteRequest {
  const RouteRequest({
    required this.originStationId,
    required this.destinationStationId,
    required this.mobilityType,
    this.constraintMode,
    this.searchMode = RouteSearchMode.stationToStation,
    this.objective = RouteObjective.fastest,
  });

  final String originStationId;
  final String destinationStationId;
  final MobilityType mobilityType;
  final ConstraintMode? constraintMode;
  final RouteSearchMode searchMode;
  final RouteObjective objective;

  ConstraintMode get effectiveConstraintMode =>
      constraintMode ?? mobilityType.defaultConstraintMode;

  bool get blocksStairOnlyAccess =>
      mobilityType.blocksStairOnlyAccess(effectiveConstraintMode);
}

class InternalRouteSearchRequest {
  const InternalRouteSearchRequest({
    required this.stationId,
    required this.fromNodeId,
    required this.toNodeId,
    required this.mobilityType,
  });

  final String stationId;
  final String fromNodeId;
  final String toNodeId;
  final MobilityType mobilityType;
}
