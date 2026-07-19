import 'train_search_scope_policy.dart';

class TrainStation {
  const TrainStation({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is TrainStation && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

class TrainJourney {
  const TrainJourney({
    required this.trainNumber,
    required this.trainType,
    required this.departureStationId,
    required this.departureStationName,
    required this.departureAt,
    required this.arrivalStationId,
    required this.arrivalStationName,
    required this.arrivalAt,
    required this.durationMinutes,
    required this.adultFareWon,
  });

  final String trainNumber;
  final TrainSearchTrainType trainType;
  final String departureStationId;
  final String departureStationName;
  final DateTime departureAt;
  final String arrivalStationId;
  final String arrivalStationName;
  final DateTime arrivalAt;
  final int durationMinutes;
  final int adultFareWon;
}

class TrainSearchCriteria {
  const TrainSearchCriteria({
    required this.departure,
    required this.arrival,
    required this.departureDate,
    this.returnDate,
    this.trainType,
  });

  final TrainStation departure;
  final TrainStation arrival;
  final DateTime departureDate;
  final DateTime? returnDate;
  final TrainSearchTrainType? trainType;

  bool get isRoundTrip => returnDate != null;
}

class TrainSearchResult {
  const TrainSearchResult({
    required this.observedAt,
    required this.outbound,
    required this.inbound,
  });

  final DateTime observedAt;
  final List<TrainJourney> outbound;
  final List<TrainJourney> inbound;
}

enum TrainSearchFailureKind {
  invalidArgument,
  unsupportedTrainType,
  rateLimited,
  providerError,
  noValidRows,
  unavailable,
  network,
  invalidResponse,
}

class TrainSearchException implements Exception {
  const TrainSearchException(this.kind, this.message);

  final TrainSearchFailureKind kind;
  final String message;

  @override
  String toString() => message;
}

abstract interface class TrainSearchRepository {
  Future<List<TrainStation>> stations(
    String query, {
    TrainSearchTrainType? type,
  });

  Future<TrainSearchResult> search(TrainSearchCriteria criteria);
}
