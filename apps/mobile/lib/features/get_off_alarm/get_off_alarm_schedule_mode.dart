import 'get_off_alarm_policy.dart';

/// 로컬 알림 예약의 정확도 모드. Android 12+의 정확 알람 정책에 대응한다.
enum GetOffAlarmScheduleMode { exact, inexact }

/// 예약 모드 판정 결과. [inexactNotice]가 있으면 사용자에게 오차를 고지해야
/// 한다(무음 실패 금지).
class GetOffAlarmScheduleResolution {
  const GetOffAlarmScheduleResolution({required this.mode, this.inexactNotice});

  final GetOffAlarmScheduleMode mode;
  final String? inexactNotice;
}

/// 정확 알람 권한 여부([exactAlarmPermitted])에 따라 예약 모드를 정한다.
///
/// 권한이 있으면 exact 모드로 예약하고 별도 고지가 필요 없다. 권한이 없으면
/// inexact로 강등하되, 강등 사다리 원칙에 따라 반드시 오차 고지 문구를 함께
/// 돌려준다(무음 실패 금지).
GetOffAlarmScheduleResolution resolveGetOffAlarmScheduleMode({
  required bool exactAlarmPermitted,
}) {
  if (exactAlarmPermitted) {
    return const GetOffAlarmScheduleResolution(
      mode: GetOffAlarmScheduleMode.exact,
    );
  }
  return const GetOffAlarmScheduleResolution(
    mode: GetOffAlarmScheduleMode.inexact,
    inexactNotice: GetOffAlarmPolicyDefaults.inexactNoticeKo,
  );
}
