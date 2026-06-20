import '../domain/route_request.dart';
import '../domain/route_weight.dart';
import 'network_graph.dart';

class AccessibilityCost {
  const AccessibilityCost({
    required this.cost,
    this.isBlocked = false,
    this.warningCodes = const [],
  });

  final int cost;
  final bool isBlocked;
  final List<String> warningCodes;
}

class AccessibilityCostCalculator {
  const AccessibilityCostCalculator();

  AccessibilityCost costFor(RouteEdge edge, MobilityType mobilityType) {
    final weight = RouteWeight.from(mobilityType);
    final warningCodes = <String>[];

    if (edge.accessibilityState == RouteAccessibilityState.unavailable) {
      return const AccessibilityCost(
        cost: 0,
        isBlocked: true,
        warningCodes: ['FACILITY_UNAVAILABLE'],
      );
    }
    if (edge.accessibilityState == RouteAccessibilityState.unknown) {
      if (mobilityType.blocksStairOnlyAccess) {
        return const AccessibilityCost(
          cost: 0,
          isBlocked: true,
          warningCodes: ['ACCESSIBILITY_STATE_UNKNOWN'],
        );
      }
      warningCodes.add('ACCESSIBILITY_STATE_UNKNOWN');
    }

    if (edge.includesStairs && mobilityType.blocksStairOnlyAccess) {
      return const AccessibilityCost(
        cost: 0,
        isBlocked: true,
        warningCodes: ['STAIR_ONLY_ACCESS'],
      );
    }

    var cost = edge.baseCost;
    if (edge.type == RouteEdgeType.transfer) {
      cost += weight.transferPenalty;
    }
    if (edge.includesStairs) {
      cost += weight.stairOnlyAccessPenalty;
      warningCodes.add('STAIR_ONLY_ACCESS');
    }
    if (edge.accessibilityState == RouteAccessibilityState.unknown) {
      cost += weight.lowDataConfidencePenalty;
    }
    if (edge.reliabilityScore < 80) {
      cost += weight.lowDataConfidencePenalty;
      warningCodes.add('LOW_DATA_CONFIDENCE');
    }
    if (edge.isDataStale) {
      cost += weight.staleDataPenalty;
      warningCodes.add('STALE_ACCESSIBILITY_DATA');
    }

    return AccessibilityCost(cost: cost, warningCodes: warningCodes);
  }
}
