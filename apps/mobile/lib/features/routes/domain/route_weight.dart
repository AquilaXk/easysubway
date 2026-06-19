import 'route_request.dart';

class RouteWeight {
  const RouteWeight({
    required this.baseAccessCost,
    required this.lowDataConfidencePenalty,
    required this.stairOnlyAccessPenalty,
    required this.transferPenalty,
    required this.staleDataPenalty,
  });

  final int baseAccessCost;
  final int lowDataConfidencePenalty;
  final int stairOnlyAccessPenalty;
  final int transferPenalty;
  final int staleDataPenalty;

  factory RouteWeight.from(MobilityType mobilityType) {
    return switch (mobilityType) {
      MobilityType.senior => const RouteWeight(
        baseAccessCost: 18,
        lowDataConfidencePenalty: 24,
        stairOnlyAccessPenalty: 38,
        transferPenalty: 12,
        staleDataPenalty: 24,
      ),
      MobilityType.stroller => const RouteWeight(
        baseAccessCost: 20,
        lowDataConfidencePenalty: 28,
        stairOnlyAccessPenalty: 48,
        transferPenalty: 15,
        staleDataPenalty: 26,
      ),
      MobilityType.wheelchair => const RouteWeight(
        baseAccessCost: 24,
        lowDataConfidencePenalty: 36,
        stairOnlyAccessPenalty: 100,
        transferPenalty: 18,
        staleDataPenalty: 36,
      ),
      MobilityType.pregnant => const RouteWeight(
        baseAccessCost: 17,
        lowDataConfidencePenalty: 26,
        stairOnlyAccessPenalty: 42,
        transferPenalty: 14,
        staleDataPenalty: 26,
      ),
      MobilityType.temporaryInjury => const RouteWeight(
        baseAccessCost: 22,
        lowDataConfidencePenalty: 30,
        stairOnlyAccessPenalty: 52,
        transferPenalty: 17,
        staleDataPenalty: 30,
      ),
      MobilityType.luggage => const RouteWeight(
        baseAccessCost: 16,
        lowDataConfidencePenalty: 22,
        stairOnlyAccessPenalty: 34,
        transferPenalty: 10,
        staleDataPenalty: 22,
      ),
    };
  }
}
