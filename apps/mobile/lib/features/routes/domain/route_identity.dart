import 'dart:convert';

import 'package:crypto/crypto.dart';

class RouteQueryIdentity {
  RouteQueryIdentity({
    required String originStationId,
    required String destinationStationId,
    required String mobilityType,
    required String constraintMode,
    String? waypointStationId,
    String? mobilityPreset,
    required String transportScope,
    required String objective,
  }) : originStationId = _required(originStationId),
       destinationStationId = _required(destinationStationId),
       mobilityType = _required(mobilityType),
       constraintMode = _required(constraintMode),
       waypointStationId = _optional(waypointStationId),
       mobilityPreset = _optional(mobilityPreset),
       transportScope = _required(transportScope),
       objective = _required(objective);

  factory RouteQueryIdentity.fromSnapshot(Map<String, Object?> snapshot) =>
      RouteQueryIdentity(
        originStationId: snapshot['originStationId'] as String,
        destinationStationId: snapshot['destinationStationId'] as String,
        mobilityType: snapshot['mobilityType'] as String,
        constraintMode: snapshot['constraintMode'] as String,
        waypointStationId: snapshot['waypointStationId'] as String?,
        mobilityPreset: snapshot['mobilityPreset'] as String?,
        transportScope: snapshot['transportScope'] as String,
        objective: snapshot['objective'] as String,
      );

  final String originStationId;
  final String destinationStationId;
  final String mobilityType;
  final String constraintMode;
  final String? waypointStationId;
  final String? mobilityPreset;
  final String transportScope;
  final String objective;

  List<Object?> get _canonical => [
    'route-query-v1',
    originStationId,
    destinationStationId,
    waypointStationId,
    mobilityType,
    mobilityPreset,
    constraintMode,
    transportScope,
    objective,
  ];
  List<int> get canonicalBytes => utf8.encode(jsonEncode(_canonical));
  String get value => 'rq:v1:${sha256.convert(canonicalBytes)}';
  Map<String, Object?> toSnapshot() => {'originStationId': originStationId, 'destinationStationId': destinationStationId, 'mobilityType': mobilityType, 'constraintMode': constraintMode, 'waypointStationId': waypointStationId, 'mobilityPreset': mobilityPreset, 'transportScope': transportScope, 'objective': objective};
  @override bool operator ==(Object other) => other is RouteQueryIdentity && value == other.value;
  @override int get hashCode => value.hashCode;
}

class RouteCandidateLegSignature {
  RouteCandidateLegSignature({required this.stepType, required this.fromStationId, required this.toStationId, this.fromNodeId = '', this.toNodeId = '', this.edgeId = '', this.lineId = '', this.serviceClass = '', this.servicePattern = ''});
  final String stepType, fromStationId, toStationId, fromNodeId, toNodeId, edgeId, lineId, serviceClass, servicePattern;
  List<String> get canonical => [stepType, fromStationId, toStationId, fromNodeId, toNodeId, edgeId, lineId, serviceClass, servicePattern].map((value) => value.trim()).toList(growable: false);
}

class RouteCandidateIdentity {
  RouteCandidateIdentity({required this.query, required List<RouteCandidateLegSignature> legs}) : legs = List.unmodifiable(legs) { if (legs.isEmpty) throw ArgumentError.value(legs, 'legs', 'must not be empty'); }
  final RouteQueryIdentity query;
  final List<RouteCandidateLegSignature> legs;
  List<int> get canonicalBytes => utf8.encode(jsonEncode(['route-candidate-v1', query._canonical, [for (final leg in legs) leg.canonical]]));
  String get value => 'rc:v1:${sha256.convert(canonicalBytes)}';
}

String _required(String value) { final normalized = value.trim(); if (normalized.isEmpty) throw ArgumentError.value(value, 'value', 'must not be blank'); return normalized; }
String? _optional(String? value) { final normalized = value?.trim() ?? ''; return normalized.isEmpty ? null : normalized; }
