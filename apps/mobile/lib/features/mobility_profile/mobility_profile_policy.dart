/// 보행 프로필 프리셋 정책의 정본 상수.
///
/// `apps/mobile/release/mobility-profile-policy.json`을 그대로 반영하며, 그 JSON이
/// node 리포 계약 테스트와 `mobility_profile_policy_test.dart` 양쪽에서 강제되는
/// 단일 진실 원본이다. JSON을 함께 바꾸지 않고 여기 값만 바꾸면(또는 그 반대)
/// 동기화 테스트가 실패한다.
///
/// backend `ProfileWalkTimeCalculator.MobilityPreset`(정수 speedFactorPercent)와도
/// 같은 계약 테스트가 소수 speedFactor로 상호 고정한다. UI·위젯·상태관리는 담지
/// 않으며, #1703 온보딩 UI가 소비할 상수·타입만 노출한다.
library;

/// 보행 프리셋 종류.
enum MobilityPreset {
  standard,
  slow,
  noStairs,
  stepFree,
}

/// 프리셋별 시설 제약.
enum FacilityConstraint {
  none,
  noStairs,
  elevatorOnly,
}

/// 사용자가 선택하는 이동 유형(온보딩·프로필 입력값).
enum MobilityType {
  senior,
  pregnant,
  temporaryInjury,
  luggage,
  stroller,
  wheelchair,
}

/// 단일 프리셋의 파생 상수.
class MobilityPresetSpec {
  const MobilityPresetSpec({
    required this.speedFactor,
    required this.facilityConstraint,
    this.elevatorWaitSeconds,
  });

  /// baseline 보행 초에 곱하는 계수(1.0 = 표준 속도).
  final double speedFactor;

  /// 이 프리셋이 요구하는 시설 제약.
  final FacilityConstraint facilityConstraint;

  /// STEP_FREE 승강기 대기 가산 초(다른 프리셋은 null).
  final int? elevatorWaitSeconds;
}

/// 보행 프로필 정책의 정본 상수 모음.
class MobilityProfilePolicy {
  const MobilityProfilePolicy._();

  /// 기준 보행 속도(m/s).
  static const double anchorWalkSpeedMps = 1.2;

  /// STEP_FREE 승강기 대기 가산 초.
  static const int stepFreeElevatorWaitSeconds = 60;

  /// 프리셋별 파생 상수.
  static const Map<MobilityPreset, MobilityPresetSpec> presets =
      <MobilityPreset, MobilityPresetSpec>{
    MobilityPreset.standard: MobilityPresetSpec(
      speedFactor: 1.0,
      facilityConstraint: FacilityConstraint.none,
    ),
    MobilityPreset.slow: MobilityPresetSpec(
      speedFactor: 1.35,
      facilityConstraint: FacilityConstraint.none,
    ),
    MobilityPreset.noStairs: MobilityPresetSpec(
      speedFactor: 1.2,
      facilityConstraint: FacilityConstraint.noStairs,
    ),
    MobilityPreset.stepFree: MobilityPresetSpec(
      speedFactor: 1.0,
      facilityConstraint: FacilityConstraint.elevatorOnly,
      elevatorWaitSeconds: stepFreeElevatorWaitSeconds,
    ),
  };

  /// 이동 유형 → 기본 프리셋 매핑.
  static const Map<MobilityType, MobilityPreset> mobilityTypeMapping =
      <MobilityType, MobilityPreset>{
    MobilityType.senior: MobilityPreset.slow,
    MobilityType.pregnant: MobilityPreset.slow,
    MobilityType.temporaryInjury: MobilityPreset.slow,
    MobilityType.luggage: MobilityPreset.noStairs,
    MobilityType.stroller: MobilityPreset.stepFree,
    MobilityType.wheelchair: MobilityPreset.stepFree,
  };
}
