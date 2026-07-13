import 'package:easysubway_mobile/features/mobility_profile/mobility_preset_labels.dart';
import 'package:easysubway_mobile/features/mobility_profile/mobility_profile_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('프리셋 서버 문자열', () {
    test('프리셋 → 서버 문자열이 계약 값과 일치한다', () {
      expect(mobilityPresetServerString(MobilityPreset.standard), 'STANDARD');
      expect(mobilityPresetServerString(MobilityPreset.slow), 'SLOW');
      expect(mobilityPresetServerString(MobilityPreset.noStairs), 'NO_STAIRS');
      expect(mobilityPresetServerString(MobilityPreset.stepFree), 'STEP_FREE');
    });

    test('서버 문자열 → 프리셋 역파싱', () {
      expect(mobilityPresetFromServerString('STANDARD'), MobilityPreset.standard);
      expect(mobilityPresetFromServerString('SLOW'), MobilityPreset.slow);
      expect(mobilityPresetFromServerString('NO_STAIRS'), MobilityPreset.noStairs);
      expect(mobilityPresetFromServerString('STEP_FREE'), MobilityPreset.stepFree);
      expect(mobilityPresetFromServerString('UNKNOWN'), isNull);
    });

    test('서버 문자열 왕복이 안정적이다', () {
      for (final preset in MobilityPreset.values) {
        expect(
          mobilityPresetFromServerString(mobilityPresetServerString(preset)),
          preset,
        );
      }
    });
  });

  group('대표 이동 유형 문자열', () {
    test('프리셋 → 대표 이동 유형이 계약 값과 일치한다', () {
      expect(
        mobilityPresetRepresentativeMobilityType(MobilityPreset.standard),
        'STANDARD',
      );
      expect(
        mobilityPresetRepresentativeMobilityType(MobilityPreset.slow),
        'SENIOR',
      );
      expect(
        mobilityPresetRepresentativeMobilityType(MobilityPreset.noStairs),
        'LUGGAGE',
      );
      expect(
        mobilityPresetRepresentativeMobilityType(MobilityPreset.stepFree),
        'WHEELCHAIR',
      );
    });

    test('대표 이동 유형 → 프리셋 역산', () {
      expect(
        mobilityPresetFromRepresentativeMobilityType('STANDARD'),
        MobilityPreset.standard,
      );
      expect(
        mobilityPresetFromRepresentativeMobilityType('SENIOR'),
        MobilityPreset.slow,
      );
      expect(
        mobilityPresetFromRepresentativeMobilityType('LUGGAGE'),
        MobilityPreset.noStairs,
      );
      expect(
        mobilityPresetFromRepresentativeMobilityType('WHEELCHAIR'),
        MobilityPreset.stepFree,
      );
      expect(mobilityPresetFromRepresentativeMobilityType('PREGNANT'), isNull);
    });
  });

  group('구 profileId 마이그레이션', () {
    test('6종 구 프로필 id를 데이터 소실 없이 프리셋으로 승계한다', () {
      expect(mobilityPresetFromLegacyProfileId('elderly'), MobilityPreset.slow);
      expect(mobilityPresetFromLegacyProfileId('pregnant'), MobilityPreset.slow);
      expect(mobilityPresetFromLegacyProfileId('injured'), MobilityPreset.slow);
      expect(
        mobilityPresetFromLegacyProfileId('luggage'),
        MobilityPreset.noStairs,
      );
      expect(
        mobilityPresetFromLegacyProfileId('stroller'),
        MobilityPreset.stepFree,
      );
      expect(
        mobilityPresetFromLegacyProfileId('wheelchair'),
        MobilityPreset.stepFree,
      );
      expect(mobilityPresetFromLegacyProfileId('unknown'), isNull);
    });
  });

  group('표시 문구', () {
    test('표시명이 확정 문구와 일치한다', () {
      expect(mobilityPresetDisplayName(MobilityPreset.standard), '보통 걸음');
      expect(mobilityPresetDisplayName(MobilityPreset.slow), '천천히');
      expect(mobilityPresetDisplayName(MobilityPreset.noStairs), '계단 없이');
      expect(mobilityPresetDisplayName(MobilityPreset.stepFree), '휠체어 이용');
    });

    test('부가설명이 확정 문구와 일치한다', () {
      expect(
        mobilityPresetDescription(MobilityPreset.standard),
        '일반적인 걸음 속도로 안내해요',
      );
      expect(
        mobilityPresetDescription(MobilityPreset.slow),
        '여유 있는 걸음 속도로 시간을 계산해요',
      );
      expect(
        mobilityPresetDescription(MobilityPreset.noStairs),
        '계단 대신 에스컬레이터·엘리베이터로 안내해요',
      );
      expect(
        mobilityPresetDescription(MobilityPreset.stepFree),
        '엘리베이터로만 이동하는 길을 안내해요 · 유아차와 함께일 때도 좋아요',
      );
    });
  });
}
