import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../mobile_error_reporter.dart';
import 'get_off_alarm_schedule_mode.dart';
import 'get_off_alarm_scheduler.dart';

/// 계산된 하차 알림을 실제 로컬 알림으로 예약/취소하는 어댑터.
///
/// 순수 계산([computeGetOffAlarms])과 강등 판정
/// ([resolveGetOffAlarmScheduleMode])은 이 어댑터 밖에서 끝내고, 여기서는
/// 플랫폼 예약만 담당한다. 테스트에서는 이 인터페이스를 가짜로 대체한다.
abstract class GetOffAlarmNotifier {
  /// [alarms]를 [mode]에 맞춰 예약한다. 기존 활성 알림은 먼저 모두 취소한다
  /// (단일 경로 원칙).
  Future<void> scheduleAlarms(
    List<ScheduledGetOffAlarm> alarms, {
    required GetOffAlarmScheduleMode mode,
  });

  /// 활성 하차 알림을 모두 취소한다.
  Future<void> cancelAll();
}

/// [GetOffAlarmScheduleMode]를 flutter_local_notifications의
/// [AndroidScheduleMode]로 변환한다. inexact는 도즈 상태에서도 최대한 근접하게
/// 울리도록 allowWhileIdle 변형을 쓴다.
AndroidScheduleMode androidScheduleModeFor(GetOffAlarmScheduleMode mode) {
  switch (mode) {
    case GetOffAlarmScheduleMode.exact:
      return AndroidScheduleMode.exactAllowWhileIdle;
    case GetOffAlarmScheduleMode.inexact:
      return AndroidScheduleMode.inexactAllowWhileIdle;
  }
}

/// flutter_local_notifications 기반 실제 구현.
class LocalGetOffAlarmNotifier implements GetOffAlarmNotifier {
  LocalGetOffAlarmNotifier(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  /// 하차 알림에 할당하는 알림 ID 기준값. 단일 경로에서 알림 수는 적으므로
  /// 이 기준값부터 순차 부여하고 취소 시 전부 지운다.
  static const int _baseNotificationId = 47660;

  static const String _channelId = 'get_off_alarm';
  static const String _channelName = '하차 알림';
  static const String _channelDescription = '도착·환승역 하차 시각을 알려줍니다.';

  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.navigation,
      );

  List<int> _activeIds = const [];
  bool _initialized = false;

  /// 첫 예약 전에 플러그인·타임존을 1회 초기화한다. 앱 시작 경로를 무겁게 하지
  /// 않도록 지연 초기화한다.
  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _initialized = true;
  }

  @override
  Future<void> scheduleAlarms(
    List<ScheduledGetOffAlarm> alarms, {
    required GetOffAlarmScheduleMode mode,
  }) async {
    await _ensureInitialized();
    await cancelAll();
    final scheduleMode = androidScheduleModeFor(mode);
    final assignedIds = <int>[];
    for (var index = 0; index < alarms.length; index++) {
      final alarm = alarms[index];
      final id = _baseNotificationId + index;
      try {
        await _plugin.zonedSchedule(
          id: id,
          title: _titleFor(alarm),
          body: _bodyFor(alarm),
          scheduledDate: tz.TZDateTime.from(alarm.fireAt, tz.local),
          notificationDetails: const NotificationDetails(
            android: _androidDetails,
          ),
          androidScheduleMode: scheduleMode,
        );
        assignedIds.add(id);
      } on Exception catch (error, stackTrace) {
        reportMobileError(error, stackTrace, context: '하차 알림 예약 중 예외가 발생했습니다.');
      }
    }
    _activeIds = assignedIds;
  }

  @override
  Future<void> cancelAll() async {
    for (final id in _activeIds) {
      try {
        await _plugin.cancel(id: id);
      } on Exception catch (error, stackTrace) {
        reportMobileError(error, stackTrace, context: '하차 알림 취소 중 예외가 발생했습니다.');
      }
    }
    _activeIds = const [];
  }

  String _titleFor(ScheduledGetOffAlarm alarm) {
    switch (alarm.kind) {
      case GetOffAlarmKind.destination:
        return '곧 ${alarm.stationName} 도착';
      case GetOffAlarmKind.transfer:
        return '곧 ${alarm.stationName} 환승';
    }
  }

  String _bodyFor(ScheduledGetOffAlarm alarm) {
    switch (alarm.kind) {
      case GetOffAlarmKind.destination:
        return '내릴 준비를 하세요.';
      case GetOffAlarmKind.transfer:
        return '환승할 준비를 하세요.';
    }
  }
}
