import 'package:easysubway_mobile/features/fare/fare_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FareCalculator', () {
    const rule = FareRule(
      id: 'capital-integrated-standard',
      zoneId: 'capital-integrated',
      baseCardFare: 1550,
      baseCashFare: 1650,
      baseDistanceMeters: 10000,
      additionalSteps: [
        FareAdditionalStep(distanceMeters: 5000, cardFare: 100, cashFare: 100),
      ],
    );

    test('수도권 기본거리 안에서는 기본 카드·현금 요금만 표시한다', () {
      final fare = const FareCalculator().calculate(
        distanceMeters: 9800,
        rule: rule,
      );

      expect(fare.status, FareStatus.available);
      expect(fare.cardFare, 1550);
      expect(fare.cashFare, 1650);
      expect(fare.label, '카드 1,550원');
    });

    test('기본거리 초과분은 추가거리 단위로 올림 계산한다', () {
      final fare = const FareCalculator().calculate(
        distanceMeters: 10100,
        rule: rule,
      );

      expect(fare.status, FareStatus.available);
      expect(fare.cardFare, 1650);
      expect(fare.cashFare, 1750);
      expect(fare.disclaimer, '성인 교통카드 기준 요금입니다.');
    });

    test('거리나 규칙이 없으면 값을 만들지 않고 강등한다', () {
      final missingDistance = const FareCalculator().calculate(
        distanceMeters: null,
        rule: rule,
      );
      final missingRule = const FareCalculator().calculate(
        distanceMeters: 10000,
        rule: null,
      );

      expect(missingDistance.status, FareStatus.unavailable);
      expect(missingRule.status, FareStatus.unavailable);
      expect(missingDistance.cardFare, isNull);
      expect(missingRule.cardFare, isNull);
    });
  });
}
