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

    // 경유역(중간 정차)은 요금상 하나의 연속 승차로 본다: 총 이동거리로 한 번에
    // 계산해야 하며, 구간별로 쪼개 계산한 뒤 합산하면 거리 누진 특성상 과다 청구된다.
    // 이 회귀 방지 테스트는 두 방식의 카드요금이 명확히 다름을 고정한다.
    test('중간 경유는 요금 연속(단일 승차) 정책이라 총거리 단일계산 ≠ 구간합산', () {
      const calculator = FareCalculator();
      const d1 = 8000;
      const d2 = 8000;

      // (a) 총 이동거리로 한 번에 계산 = 단일 승차 정책.
      final combined = calculator.calculate(
        distanceMeters: d1 + d2,
        rule: rule,
      );
      // (b) 구간별로 쪼개 계산한 뒤 합산.
      final splitSum =
          calculator.calculate(distanceMeters: d1, rule: rule).cardFare! +
          calculator.calculate(distanceMeters: d2, rule: rule).cardFare!;

      // 기본거리 10km rule에서 총 16km는 초과 6km만 과금(1550+200=1750),
      // 8km씩 따로면 각각 초과 0(1550)이라 합산 3100 → 명확히 다르다.
      expect(combined.cardFare, 1750);
      expect(splitSum, 3100);
      expect(combined.cardFare, isNot(splitSum));
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
