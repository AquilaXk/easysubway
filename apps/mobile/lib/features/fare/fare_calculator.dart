import 'dart:math' as math;

class FareCalculator {
  const FareCalculator();

  FareEstimate calculate({
    required int? distanceMeters,
    required FareRule? rule,
  }) {
    if (distanceMeters == null || distanceMeters <= 0 || rule == null) {
      return const FareEstimate.unavailable();
    }
    final extraDistance = math.max(0, distanceMeters - rule.baseDistanceMeters);
    var cardFare = rule.baseCardFare;
    var cashFare = rule.baseCashFare;
    var remainingDistance = extraDistance;
    for (var index = 0; index < rule.additionalSteps.length; index += 1) {
      if (remainingDistance <= 0) {
        break;
      }
      final step = rule.additionalSteps[index];
      if (step.distanceMeters <= 0) {
        return const FareEstimate.unavailable();
      }
      final isLastStep = index == rule.additionalSteps.length - 1;
      final chargedDistance = isLastStep
          ? remainingDistance
          : math.min(remainingDistance, step.distanceMeters);
      final units = (chargedDistance / step.distanceMeters).ceil();
      cardFare += units * step.cardFare;
      cashFare += units * step.cashFare;
      remainingDistance -= chargedDistance;
    }
    return FareEstimate.available(cardFare: cardFare, cashFare: cashFare);
  }
}

class FareRule {
  const FareRule({
    required this.id,
    required this.zoneId,
    required this.baseCardFare,
    required this.baseCashFare,
    required this.baseDistanceMeters,
    required this.additionalSteps,
  });

  final String id;
  final String zoneId;
  final int baseCardFare;
  final int baseCashFare;
  final int baseDistanceMeters;
  final List<FareAdditionalStep> additionalSteps;
}

class FareAdditionalStep {
  const FareAdditionalStep({
    required this.distanceMeters,
    required this.cardFare,
    required this.cashFare,
  });

  final int distanceMeters;
  final int cardFare;
  final int cashFare;
}

class FareEstimate {
  const FareEstimate.available({required this.cardFare, required this.cashFare})
    : status = FareStatus.available;

  const FareEstimate.unavailable()
    : status = FareStatus.unavailable,
      cardFare = null,
      cashFare = null;

  final FareStatus status;
  final int? cardFare;
  final int? cashFare;

  String get label {
    final fare = cardFare;
    if (fare == null) {
      return '요금 정보 없음';
    }
    return '카드 ${_formatWon(fare)}원';
  }

  String get disclaimer => '성인 교통카드 기준 요금입니다.';

  static String _formatWon(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index += 1) {
      final remaining = digits.length - index;
      buffer.write(digits[index]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }
}

enum FareStatus { available, unavailable }
