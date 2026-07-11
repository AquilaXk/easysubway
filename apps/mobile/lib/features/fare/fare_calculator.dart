import 'dart:math' as math;

/// 기본거리 초과분에 요금 [FareRule.additionalSteps]를 순서대로 적용해
/// 카드/현금 요금을 계산한다.
///
/// 데이터 작성자를 위한 [FareRule.additionalSteps] 인코딩 규칙:
/// - **마지막이 아닌 단계**는 `min(잔여거리, step.distanceMeters)`만큼만
///   과금되어 **정확히 1회** 적용된다. 즉 해당 구간의 실제 폭이
///   `step.distanceMeters`보다 넓어도 반복 부과되지 않는다.
/// - **마지막 단계만** `ceil(잔여거리 / step.distanceMeters)`로 **반복
///   부과**되어, 그 이후 모든 초과거리를 해당 단위로 커버한다.
///
/// 따라서 "구간별로 다른 단가가 적용되다가 특정 거리 이후로는 동일한
/// 단가가 무한히 반복되는" 실제 요금표(예: 수도권 통합요금 10~50km
/// 구간은 5km당 100원씩 8회, 50km 초과는 8km당 100원씩 반복)를
/// 인코딩할 때는 반복 구간 직전까지의 각 단계를 1회성 항목으로
/// 나열하고, 마지막에만 반복시킬 단계를 리스트의 마지막 원소로 둔다.
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
