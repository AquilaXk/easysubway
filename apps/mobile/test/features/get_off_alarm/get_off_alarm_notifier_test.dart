import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_notifier.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_schedule_mode.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_scheduler.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ScheduledGetOffAlarm alarm(int index) {
    final arrivalAt = DateTime(2026, 7, 10, 10).add(Duration(minutes: index));
    return ScheduledGetOffAlarm(
      stationId: 'station-$index',
      stationName: '테스트역',
      kind: GetOffAlarmKind.transfer,
      fireAt: arrivalAt.subtract(const Duration(minutes: 2)),
      arrivalAt: arrivalAt,
    );
  }

  group('androidScheduleModeFor', () {
    test('exact 모드는 exactAllowWhileIdle로 예약', () {
      expect(
        androidScheduleModeFor(GetOffAlarmScheduleMode.exact),
        AndroidScheduleMode.exactAllowWhileIdle,
      );
    });

    test('inexact 모드는 inexactAllowWhileIdle로 강등 예약', () {
      expect(
        androidScheduleModeFor(GetOffAlarmScheduleMode.inexact),
        AndroidScheduleMode.inexactAllowWhileIdle,
      );
    });
  });

  group('LocalGetOffAlarmNotifier', () {
    test('재시작 후 pending 목록에서 전용 ID 범위만 취소한다', () async {
      final canceledIds = <int>[];
      final first = LocalGetOffAlarmNotifier.baseNotificationId;
      final last = first + LocalGetOffAlarmNotifier.notificationCapacity - 1;
      final notifier = LocalGetOffAlarmNotifier(
        FlutterLocalNotificationsPlugin(),
        isAndroid: true,
        initializePlugin: () async {},
        pendingIds: () async => [first - 1, first, last, last + 1, 99999],
        cancelId: (id) async => canceledIds.add(id),
      );

      await notifier.cancelAll();

      expect(canceledIds, [first, last]);
    });

    test('전용 ID capacity 초과 알림은 실패 수에 반영하고 예약하지 않는다', () async {
      final scheduledIds = <int>[];
      final capacity = LocalGetOffAlarmNotifier.notificationCapacity;
      final alarms = List.generate(capacity + 2, alarm);
      final notifier = LocalGetOffAlarmNotifier(
        FlutterLocalNotificationsPlugin(),
        isAndroid: true,
        initializePlugin: () async {},
        pendingIds: () async => const [],
        cancelId: (_) async {},
        scheduleAlarm: (id, _, _, _, _) async => scheduledIds.add(id),
      );

      final result = await notifier.scheduleAlarms(
        alarms,
        mode: GetOffAlarmScheduleMode.exact,
      );

      expect(scheduledIds, hasLength(capacity));
      expect(scheduledIds.first, LocalGetOffAlarmNotifier.baseNotificationId);
      expect(
        scheduledIds.last,
        LocalGetOffAlarmNotifier.baseNotificationId + capacity - 1,
      );
      expect(result.scheduledCount, capacity);
      expect(result.failedCount, 2);
    });

    test('개별 예약 실패는 실제 성공과 실패 수에 반영한다', () async {
      final first = LocalGetOffAlarmNotifier.baseNotificationId;
      final notifier = LocalGetOffAlarmNotifier(
        FlutterLocalNotificationsPlugin(),
        isAndroid: true,
        initializePlugin: () async {},
        pendingIds: () async => const [],
        cancelId: (_) async {},
        scheduleAlarm: (id, _, _, _, _) async {
          if (id == first + 1) {
            throw Exception('schedule failed');
          }
        },
      );

      late ScheduleDeliveryResult result;
      await runWithMobileErrorReporter(
        (_) {},
        () async => result = await notifier.scheduleAlarms(
          List.generate(3, alarm),
          mode: GetOffAlarmScheduleMode.inexact,
        ),
      );

      expect(result.scheduledCount, 2);
      expect(result.failedCount, 1);
    });

    test('pending 목록 조회 실패를 취소 성공으로 삼키지 않는다', () async {
      final error = StateError('pending query failed');
      final notifier = LocalGetOffAlarmNotifier(
        FlutterLocalNotificationsPlugin(),
        isAndroid: true,
        initializePlugin: () async {},
        pendingIds: () async => throw error,
        cancelId: (_) async {},
      );

      await expectLater(notifier.cancelAll(), throwsA(same(error)));
    });

    test('전용 ID 취소 실패를 성공으로 삼키지 않는다', () async {
      final error = StateError('cancel failed');
      final notifier = LocalGetOffAlarmNotifier(
        FlutterLocalNotificationsPlugin(),
        isAndroid: true,
        initializePlugin: () async {},
        pendingIds: () async => [LocalGetOffAlarmNotifier.baseNotificationId],
        cancelId: (_) async => throw error,
      );

      await expectLater(notifier.cancelAll(), throwsA(same(error)));
    });
  });
}
