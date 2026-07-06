import 'get_off_alarm_scheduler.dart';

/// 하차 알림 정책의 정본 상수.
///
/// `apps/mobile/release/get-off-alarm-policy.json`을 그대로 반영하며, 그 JSON이
/// node 리포 계약 테스트와 `get_off_alarm_policy_test.dart` 양쪽에서 강제되는
/// 단일 진실 원본이다. JSON을 함께 바꾸지 않고 여기 값만 바꾸면(또는 그 반대)
/// 동기화 테스트가 실패한다.
class GetOffAlarmPolicyDefaults {
  const GetOffAlarmPolicyDefaults._();

  /// 도착역 도착 전 리드타임(초).
  static const int leadSeconds = 120;

  /// 환승역 도착 전 리드타임(초).
  static const int transferLeadSeconds = 120;

  /// 환승 알림 기본 on 여부.
  static const bool transferAlarmEnabled = true;

  /// 동시에 활성 알림을 가질 수 있는 최대 경로 수(v1: 단일 경로).
  static const int maxConcurrentRoutes = 1;

  /// 정확 알람 권한이 거부되어 부정확 예약으로 강등될 때 표시하는 고지 문구.
  static const String inexactNoticeKo = '정확 알람 권한이 없어 ±수 분 오차가 있을 수 있어요.';

  /// 스케줄러가 사용하는 기본 정책.
  static const GetOffAlarmPolicy policy = GetOffAlarmPolicy(
    destinationLead: Duration(seconds: leadSeconds),
    transferLead: Duration(seconds: transferLeadSeconds),
    transferAlarmEnabled: transferAlarmEnabled,
  );
}
