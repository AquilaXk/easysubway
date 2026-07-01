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

class RouteRequest {
  const RouteRequest({
    required this.originStationId,
    required this.destinationStationId,
    required this.mobilityType,
    this.constraintMode,
    this.searchMode = RouteSearchMode.stationToStation,
  });

  final String originStationId;
  final String destinationStationId;
  final MobilityType mobilityType;
  final ConstraintMode? constraintMode;
  final RouteSearchMode searchMode;

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
