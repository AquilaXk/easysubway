import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../mobile_error_reporter.dart';

/// 정확 알람(SCHEDULE_EXACT_ALARM) 권한 게이트.
///
/// POST_NOTIFICATIONS 권한은 기존 [NotificationPermissionProvider]가 담당하고,
/// 여기서는 Android 12+의 정확 알람 권한만 다룬다. 거부 시 무음 실패 대신
/// 부정확 예약으로 강등하므로(강등 사다리), 이 게이트는 판정만 돌려준다.
abstract class ExactAlarmPermissionGate {
  /// 정확 알람 예약이 현재 가능한지.
  Future<bool> isExactAlarmPermitted();

  /// 정확 알람 권한을 요청한다. 최종 허용 여부를 돌려준다.
  Future<bool> requestExactAlarmPermission();
}

/// flutter_local_notifications의 Android 구현으로 뒷받침되는 게이트.
class PluginExactAlarmPermissionGate implements ExactAlarmPermissionGate {
  PluginExactAlarmPermissionGate(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<bool> isExactAlarmPermitted() async {
    try {
      return await _android?.canScheduleExactNotifications() ?? false;
    } on Exception catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '정확 알람 권한 확인 중 예외가 발생했습니다.',
      );
      return false;
    }
  }

  @override
  Future<bool> requestExactAlarmPermission() async {
    try {
      return await _android?.requestExactAlarmsPermission() ?? false;
    } on Exception catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '정확 알람 권한 요청 중 예외가 발생했습니다.',
      );
      return false;
    }
  }
}
