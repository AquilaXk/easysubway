import 'dart:io';

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
  /// (단일 경로 원칙). 반환값은 실제 예약 성공·실패 건수다.
  Future<ScheduleDeliveryResult> scheduleAlarms(
    List<ScheduledGetOffAlarm> alarms, {
    required GetOffAlarmScheduleMode mode,
  });

  /// 활성 하차 알림을 모두 취소한다.
  Future<void> cancelAll();

  /// 하차 알림 전용 ID 범위에 남은 OS 대기 알림 건수만 반환한다.
  Future<int> pendingAlarmCount();
}

/// 플랫폼에 전달한 하차 알림 예약의 실제 결과.
class ScheduleDeliveryResult {
  const ScheduleDeliveryResult({
    required this.scheduledCount,
    required this.failedCount,
  });

  final int scheduledCount;
  final int failedCount;
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
  LocalGetOffAlarmNotifier(
    FlutterLocalNotificationsPlugin plugin, {
    bool? isAndroid,
    Future<void> Function()? initializePlugin,
    Future<List<int>> Function()? pendingIds,
    Future<void> Function(int id)? cancelId,
    Future<void> Function(
      int id,
      String title,
      String body,
      DateTime fireAt,
      AndroidScheduleMode mode,
    )?
    scheduleAlarm,
  }) : _isAndroid = isAndroid ?? Platform.isAndroid,
       _initializePlugin =
           initializePlugin ??
           (() async {
             await plugin.initialize(
               settings: const InitializationSettings(
                 android: AndroidInitializationSettings('@mipmap/ic_launcher'),
               ),
             );
           }),
       _pendingIds =
           pendingIds ??
           (() async {
             final pending = await plugin.pendingNotificationRequests();
             return pending.map((request) => request.id).toList();
           }),
       _cancelId = cancelId ?? ((id) => plugin.cancel(id: id)),
       _scheduleAlarm =
           scheduleAlarm ??
           ((id, title, body, fireAt, mode) => plugin.zonedSchedule(
             id: id,
             title: title,
             body: body,
             scheduledDate: tz.TZDateTime.from(fireAt, tz.local),
             notificationDetails: const NotificationDetails(
               android: _androidDetails,
             ),
             androidScheduleMode: mode,
           ));

  final bool _isAndroid;
  final Future<void> Function() _initializePlugin;
  final Future<List<int>> Function() _pendingIds;
  final Future<void> Function(int id) _cancelId;
  final Future<void> Function(
    int id,
    String title,
    String body,
    DateTime fireAt,
    AndroidScheduleMode mode,
  )
  _scheduleAlarm;

  /// 하차 알림 전용 ID 범위 `[baseNotificationId, base + capacity)`.
  static const int baseNotificationId = 47660;
  static const int notificationCapacity = 64;

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

  Future<void>? _initialization;

  /// 첫 예약 전에 플러그인·타임존을 1회 초기화한다. 진행 중인 초기화 Future를
  /// 캐싱해, 연속 호출(예: 토글 빠른 재탭) 시 initialize가 중복 실행되지 않게
  /// 한다(TOCTOU 방지). 앱 시작 경로를 무겁게 하지 않도록 지연 초기화한다.
  Future<void> _ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    // Android 전용 초기화(iOS는 #571 DEFERRED). iOS 진입은 아래 platform 가드가 막는다.
    await _initializePlugin();
  }

  @override
  Future<ScheduleDeliveryResult> scheduleAlarms(
    List<ScheduledGetOffAlarm> alarms, {
    required GetOffAlarmScheduleMode mode,
  }) async {
    if (!_isAndroid) {
      return ScheduleDeliveryResult(
        scheduledCount: 0,
        failedCount: alarms.length,
      );
    }
    await _ensureInitialized();
    await cancelAll();
    final scheduleMode = androidScheduleModeFor(mode);
    var scheduledCount = 0;
    final attemptCount = alarms.length < notificationCapacity
        ? alarms.length
        : notificationCapacity;
    for (var index = 0; index < attemptCount; index++) {
      final alarm = alarms[index];
      final id = baseNotificationId + index;
      try {
        await _scheduleAlarm(
          id,
          _titleFor(alarm),
          _bodyFor(alarm),
          alarm.fireAt,
          scheduleMode,
        );
        scheduledCount += 1;
      } on Exception catch (error, stackTrace) {
        reportMobileError(error, stackTrace, context: '하차 알림 예약 중 예외가 발생했습니다.');
      }
    }
    return ScheduleDeliveryResult(
      scheduledCount: scheduledCount,
      failedCount: alarms.length - scheduledCount,
    );
  }

  @override
  Future<void> cancelAll() async {
    if (!_isAndroid) {
      return;
    }
    await _ensureInitialized();
    final pendingIds = await _pendingIds();
    for (final id in pendingIds) {
      if (_isOwnedNotificationId(id)) {
        await _cancelId(id);
      }
    }
  }

  @override
  Future<int> pendingAlarmCount() async {
    if (!_isAndroid) {
      return 0;
    }
    await _ensureInitialized();
    final pendingIds = await _pendingIds();
    return pendingIds.where(_isOwnedNotificationId).length;
  }

  bool _isOwnedNotificationId(int id) {
    return id >= baseNotificationId &&
        id < baseNotificationId + notificationCapacity;
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
