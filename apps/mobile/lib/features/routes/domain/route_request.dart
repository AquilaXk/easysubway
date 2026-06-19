enum MobilityType {
  senior,
  stroller,
  wheelchair,
  pregnant,
  temporaryInjury,
  luggage;

  bool get blocksStairOnlyAccess => this == MobilityType.wheelchair;
}

class RouteRequest {
  const RouteRequest({
    required this.originStationId,
    required this.destinationStationId,
    required this.mobilityType,
  });

  final String originStationId;
  final String destinationStationId;
  final MobilityType mobilityType;
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
