import 'route_step.dart';

enum RouteStatus { found, blocked, unknown, unsupported, error }

class RouteWarning {
  const RouteWarning({required this.code, required this.message});

  final String code;
  final String message;
}

class LocalRouteResult {
  const LocalRouteResult({
    required this.status,
    required this.totalCost,
    required this.steps,
    required this.warnings,
    required this.blockedReasonCodes,
  });

  factory LocalRouteResult.blocked(List<String> blockedReasonCodes) {
    return LocalRouteResult(
      status: RouteStatus.blocked,
      totalCost: 0,
      steps: const [],
      warnings: const [],
      blockedReasonCodes: blockedReasonCodes,
    );
  }

  factory LocalRouteResult.unknown(List<String> blockedReasonCodes) {
    return LocalRouteResult(
      status: RouteStatus.unknown,
      totalCost: 0,
      steps: const [],
      warnings: const [],
      blockedReasonCodes: blockedReasonCodes,
    );
  }

  final RouteStatus status;
  final int totalCost;
  final List<RouteStep> steps;
  final List<RouteWarning> warnings;
  final List<String> blockedReasonCodes;

  int get generalizedCost => totalCost;

  int get accessibilityScore {
    if (status != RouteStatus.found) {
      return 0;
    }
    return (100 - (generalizedCost / 10).round()).clamp(0, 100).toInt();
  }

  List<String> get edgeIds => steps.map((step) => step.edgeId).toList();

  List<String> get lineIds {
    return steps
        .map((step) => step.lineId)
        .where((lineId) => lineId.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  List<String> get transferStationIds {
    return steps
        .map((step) => step.transferStationId)
        .where((stationId) => stationId.isNotEmpty)
        .toList(growable: false);
  }

  bool get includesStairs => steps.any((step) => step.includesStairs);

  List<String> get warningCodes {
    return warnings.map((warning) => warning.code).toList(growable: false);
  }
}

class LocalInternalRouteResult {
  const LocalInternalRouteResult({
    required this.status,
    required this.totalDistanceMeters,
    required this.totalEstimatedSeconds,
    required this.edgeIds,
    required this.warningCodes,
    required this.blockedReasonCodes,
    required this.includesStairs,
  });

  factory LocalInternalRouteResult.blocked(List<String> blockedReasonCodes) {
    return LocalInternalRouteResult(
      status: RouteStatus.blocked,
      totalDistanceMeters: 0,
      totalEstimatedSeconds: 0,
      edgeIds: const [],
      warningCodes: const [],
      blockedReasonCodes: blockedReasonCodes,
      includesStairs: false,
    );
  }

  final RouteStatus status;
  final int totalDistanceMeters;
  final int totalEstimatedSeconds;
  final List<String> edgeIds;
  final List<String> warningCodes;
  final List<String> blockedReasonCodes;
  final bool includesStairs;
}
