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

    test('다단계 추가거리 요금은 이후 step까지 적용한다', () {
      const multiStepRule = FareRule(
        id: 'capital-integrated-standard',
        zoneId: 'capital-integrated',
        baseCardFare: 1550,
        baseCashFare: 1650,
        baseDistanceMeters: 10000,
        additionalSteps: [
          FareAdditionalStep(
            distanceMeters: 5000,
            cardFare: 100,
            cashFare: 100,
          ),
          FareAdditionalStep(
            distanceMeters: 8000,
            cardFare: 200,
            cashFare: 200,
          ),
        ],
      );

      final fare = const FareCalculator().calculate(
        distanceMeters: 19000,
        rule: multiStepRule,
      );

      expect(fare.status, FareStatus.available);
      expect(fare.cardFare, 1850);
      expect(fare.cashFare, 1950);
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

    test('이동 거리 0m는 결측값으로 보고 요금을 만들지 않는다', () {
      final fare = const FareCalculator().calculate(
        distanceMeters: 0,
        rule: rule,
      );

      expect(fare.status, FareStatus.unavailable);
      expect(fare.cardFare, isNull);
      expect(fare.cashFare, isNull);
    });

    group('수도권 통합요금 9단계 규칙 (10~50km 5km당100원 ×8, 50km 초과 8km당100원)', () {
      const capitalIntegratedRule = FareRule(
        id: 'capital-integrated-standard',
        zoneId: 'capital-integrated',
        baseCardFare: 1550,
        baseCashFare: 1650,
        baseDistanceMeters: 10000,
        additionalSteps: [
          FareAdditionalStep(distanceMeters: 5000, cardFare: 100, cashFare: 100),
          FareAdditionalStep(distanceMeters: 5000, cardFare: 100, cashFare: 100),
          FareAdditionalStep(distanceMeters: 5000, cardFare: 100, cashFare: 100),
          FareAdditionalStep(distanceMeters: 5000, cardFare: 100, cashFare: 100),
          FareAdditionalStep(distanceMeters: 5000, cardFare: 100, cashFare: 100),
          FareAdditionalStep(distanceMeters: 5000, cardFare: 100, cashFare: 100),
          FareAdditionalStep(distanceMeters: 5000, cardFare: 100, cashFare: 100),
          FareAdditionalStep(distanceMeters: 5000, cardFare: 100, cashFare: 100),
          FareAdditionalStep(distanceMeters: 8000, cardFare: 100, cashFare: 100),
        ],
      );

      final boundaryCases = <int, int>{
        10000: 1550, // 기본거리 이내
        12000: 1650, // 첫 5km 단계 1회
        50000: 2350, // 1550 + 8단계×100
        50001: 2450, // + 마지막 8km 단계 1단위
        58000: 2450, // 잔여 8km = 1단위 (이슈 #1911 기대값)
        58001: 2550, // 잔여 8,001m = 2단위
      };

      for (final entry in boundaryCases.entries) {
        test('${entry.key}m 이동 시 카드요금은 ${entry.value}원이다', () {
          final fare = const FareCalculator().calculate(
            distanceMeters: entry.key,
            rule: capitalIntegratedRule,
          );

          expect(fare.status, FareStatus.available);
          expect(fare.cardFare, entry.value);
        });
      }
    });
  });
}
