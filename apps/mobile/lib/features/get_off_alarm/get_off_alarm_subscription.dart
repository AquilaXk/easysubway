import 'get_off_alarm_schedule_mode.dart';

/// 활성 경로 하나에 대한 하차 알림 구독 상태.
///
/// 앱 재시작 후에도 "알림 켜짐" 상태를 복원하고 새 경로 탐색 시 이전 알림을
/// 취소할 수 있도록, 활성 구독을 로컬에 영속 저장한다(단일 경로 원칙).
class GetOffAlarmSubscription {
  const GetOffAlarmSubscription({
    required this.routeId,
    required this.transferAlarmEnabled,
    required this.scheduledCount,
    required this.scheduleMode,
    required this.inexactNotice,
    required this.destination,
    required this.transfers,
  });

  final String routeId;
  final bool transferAlarmEnabled;
  final int scheduledCount;
  final GetOffAlarmScheduleMode scheduleMode;
  final String? inexactNotice;
  final GetOffAlarmStopRef destination;
  final List<GetOffAlarmStopRef> transfers;

  Map<String, Object?> toJson() {
    return {
      'routeId': routeId,
      'transferAlarmEnabled': transferAlarmEnabled,
      'scheduledCount': scheduledCount,
      'scheduleMode': scheduleMode.name,
      'inexactNotice': inexactNotice,
      'destination': destination.toJson(),
      'transfers': transfers.map((stop) => stop.toJson()).toList(),
    };
  }

  /// JSON에서 복원한다. 형식이 어긋나면 null(강등 사다리: 무음 실패 대신 없음).
  static GetOffAlarmSubscription? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    final routeId = json['routeId'];
    final destination = GetOffAlarmStopRef.fromJson(json['destination']);
    if (routeId is! String || destination == null) {
      return null;
    }
    final transfersJson = json['transfers'];
    if (transfersJson is! List) {
      return null;
    }
    final transfers = <GetOffAlarmStopRef>[];
    for (final entry in transfersJson) {
      final stop = GetOffAlarmStopRef.fromJson(entry);
      if (stop == null) {
        return null;
      }
      transfers.add(stop);
    }
    final transferAlarmEnabled = json['transferAlarmEnabled'];
    if (transferAlarmEnabled is! bool) {
      return null;
    }
    final maxScheduledCount = 1 + (transferAlarmEnabled ? transfers.length : 0);
    final scheduledCount = json.containsKey('scheduledCount')
        ? json['scheduledCount']
        : maxScheduledCount;
    if (scheduledCount is! int ||
        scheduledCount <= 0 ||
        scheduledCount > maxScheduledCount) {
      return null;
    }
    final scheduleMode = switch (json['scheduleMode']) {
      'exact' => GetOffAlarmScheduleMode.exact,
      'inexact' => GetOffAlarmScheduleMode.inexact,
      _ => null,
    };
    final Object? rawInexactNotice = json['inexactNotice'];
    final String? inexactNotice;
    if (rawInexactNotice == null) {
      inexactNotice = null;
    } else if (rawInexactNotice is String) {
      inexactNotice = rawInexactNotice;
    } else {
      return null;
    }
    if (scheduleMode == null ||
        (scheduleMode == GetOffAlarmScheduleMode.exact &&
            inexactNotice != null) ||
        (scheduleMode == GetOffAlarmScheduleMode.inexact &&
            (inexactNotice == null || inexactNotice.isEmpty))) {
      return null;
    }
    return GetOffAlarmSubscription(
      routeId: routeId,
      transferAlarmEnabled: transferAlarmEnabled,
      scheduledCount: scheduledCount,
      scheduleMode: scheduleMode,
      inexactNotice: inexactNotice,
      destination: destination,
      transfers: transfers,
    );
  }
}

/// 하차 알림 대상 정차역의 최소 참조(역·도착 시각).
class GetOffAlarmStopRef {
  const GetOffAlarmStopRef({
    required this.stationId,
    required this.stationName,
    required this.arrivalAt,
  });

  final String stationId;
  final String stationName;
  final DateTime arrivalAt;

  Map<String, Object?> toJson() {
    return {
      'stationId': stationId,
      'stationName': stationName,
      'arrivalAtEpochMs': arrivalAt.toUtc().millisecondsSinceEpoch,
    };
  }

  static GetOffAlarmStopRef? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    final stationId = json['stationId'];
    final stationName = json['stationName'];
    final epochMs = json['arrivalAtEpochMs'];
    if (stationId is! String || stationName is! String || epochMs is! int) {
      return null;
    }
    return GetOffAlarmStopRef(
      stationId: stationId,
      stationName: stationName,
      arrivalAt: DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true),
    );
  }
}
