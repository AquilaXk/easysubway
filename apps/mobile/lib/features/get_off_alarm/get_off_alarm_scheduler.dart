/// 하차(도착) 알림의 순수·위치 미사용 스케줄링 로직.
///
/// 도착역과 환승역들의 계획/실시간 도착 시각을 받아, 로컬 알림이 울려야 할
/// 실제 시각을 계산한다. 위치·활동 인식·네트워크를 전혀 쓰지 않으며, 입력과
/// 현재 시각만으로 결정되는 순수 함수다. 이로써 트래커 #1762 / 이슈 #1766의
/// 무추적 불변을 지킨다.
library;

/// 알림이 최종 도착역인지 중간 환승역인지 구분.
enum GetOffAlarmKind { destination, transfer }

/// 알림 대상이 될 수 있는 활성 경로상의 정차역.
class GetOffAlarmStop {
  const GetOffAlarmStop({
    required this.stationId,
    required this.stationName,
    required this.arrivalAt,
    required this.kind,
  });

  final String stationId;
  final String stationName;
  final DateTime arrivalAt;
  final GetOffAlarmKind kind;
}

/// 알림 시각을 결정하는 리드타임 정책. 값의 출처는
/// `apps/mobile/release/get-off-alarm-policy.json`이다(기본값은
/// `get_off_alarm_policy.dart`의 [GetOffAlarmPolicyDefaults] 참조).
class GetOffAlarmPolicy {
  const GetOffAlarmPolicy({
    required this.destinationLead,
    required this.transferLead,
    required this.transferAlarmEnabled,
  });

  final Duration destinationLead;
  final Duration transferLead;
  final bool transferAlarmEnabled;

  GetOffAlarmPolicy copyWith({
    Duration? destinationLead,
    Duration? transferLead,
    bool? transferAlarmEnabled,
  }) {
    return GetOffAlarmPolicy(
      destinationLead: destinationLead ?? this.destinationLead,
      transferLead: transferLead ?? this.transferLead,
      transferAlarmEnabled: transferAlarmEnabled ?? this.transferAlarmEnabled,
    );
  }
}

/// 해당 정차역에 대해 [fireAt] 시각에 예약할 구체적 알림.
class ScheduledGetOffAlarm {
  const ScheduledGetOffAlarm({
    required this.stationId,
    required this.stationName,
    required this.kind,
    required this.fireAt,
    required this.arrivalAt,
    required this.slot,
  });

  final String stationId;
  final String stationName;
  final GetOffAlarmKind kind;
  final DateTime fireAt;
  final DateTime arrivalAt;

  /// 결정적 알림 슬롯. 입력 [stops] 목록에서의 위치로 정해지며, 만료된 알림이
  /// 목록에서 빠져도 값이 바뀌지 않는다. 알림 ID는 `baseNotificationId + slot`으로
  /// 매핑되어, 재부팅 복원과 WorkManager 재조정이 어떤 순서로 실행되든 같은
  /// 정차역이 같은 ID로 재예약(idempotent)되어 최종 중복이 생기지 않는다.
  final int slot;
}

/// [now]를 기준으로 [policy]에 따라 [stops]에 예약할 알림들을 계산한다. 환승
/// 알림이 꺼져 있으면 환승 정차역은 건너뛰고, 발화 시각이 현재보다 확실히
/// 미래가 아니면(=이미 지났으면) 예약 불가이므로 제외한다. 결과는 발화 시각
/// 오름차순으로 정렬한다.
List<ScheduledGetOffAlarm> computeGetOffAlarms({
  required List<GetOffAlarmStop> stops,
  required GetOffAlarmPolicy policy,
  required DateTime now,
}) {
  final alarms = <ScheduledGetOffAlarm>[];
  for (var index = 0; index < stops.length; index++) {
    final stop = stops[index];
    // slot은 필터링 전 원본 위치로 고정한다. 만료된 알림이 빠져 결과 목록이
    // 짧아져도 남은 정차역의 slot(=알림 ID)은 그대로여서 재예약이 idempotent하다.
    final slot = index;
    if (stop.kind == GetOffAlarmKind.transfer && !policy.transferAlarmEnabled) {
      continue;
    }
    final lead = stop.kind == GetOffAlarmKind.transfer
        ? policy.transferLead
        : policy.destinationLead;
    final fireAt = stop.arrivalAt.subtract(lead);
    if (!fireAt.isAfter(now)) {
      continue;
    }
    alarms.add(
      ScheduledGetOffAlarm(
        stationId: stop.stationId,
        stationName: stop.stationName,
        kind: stop.kind,
        fireAt: fireAt,
        arrivalAt: stop.arrivalAt,
        slot: slot,
      ),
    );
  }
  alarms.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return alarms;
}
