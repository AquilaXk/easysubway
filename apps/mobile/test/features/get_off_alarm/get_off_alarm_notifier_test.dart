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
      slot: index,
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
    test('목적지와 환승 알림은 canonical 한국어 역명 카피를 plugin에 전달한다', () async {
      final delivered = <({String title, String body})>[];
      final arrivalAt = DateTime(2026, 7, 10, 10);
      final notifier = LocalGetOffAlarmNotifier(
        FlutterLocalNotificationsPlugin(),
        isAndroid: true,
        initializePlugin: () async {},
        pendingIds: () async => const [],
        cancelId: (_) async {},
        scheduleAlarm: (_, title, body, _, _) async {
          delivered.add((title: title, body: body));
        },
      );

      await notifier.scheduleAlarms([
        ScheduledGetOffAlarm(
          stationId: 'station-sangnoksu',
          stationName: '상록수',
          kind: GetOffAlarmKind.destination,
          fireAt: arrivalAt.subtract(const Duration(minutes: 2)),
          arrivalAt: arrivalAt,
          slot: 0,
        ),
        ScheduledGetOffAlarm(
          stationId: 'station-geumjeong',
          stationName: '금정',
          kind: GetOffAlarmKind.transfer,
          fireAt: arrivalAt.subtract(const Duration(minutes: 5)),
          arrivalAt: arrivalAt,
          slot: 1,
        ),
      ], mode: GetOffAlarmScheduleMode.exact);

      expect(delivered, [
        (title: '곧 상록수 도착', body: '내릴 준비를 하세요.'),
        (title: '곧 금정 환승', body: '환승할 준비를 하세요.'),
      ]);
    });

    test('대기 건수는 전용 ID 범위만 세고 다른 알림을 취소하지 않는다', () async {
      final canceledIds = <int>[];
      final first = LocalGetOffAlarmNotifier.baseNotificationId;
      final last = first + LocalGetOffAlarmNotifier.notificationCapacity - 1;
      final notifier = LocalGetOffAlarmNotifier(
        FlutterLocalNotificationsPlugin(),
        isAndroid: true,
        initializePlugin: () async {},
        pendingIds: () async => [first - 1, first, last, last + 1],
        cancelId: (id) async => canceledIds.add(id),
      );

      final count = await notifier.pendingAlarmCount();

      expect(count, 2);
      expect(canceledIds, isEmpty);
    });

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

    test('예약 ID는 slot 기반이며 만료로 목록이 줄어도 같은 ID를 재사용한다', () async {
      final pending = <int>{};
      final base = LocalGetOffAlarmNotifier.baseNotificationId;
      final arrivalAt = DateTime(2026, 7, 10, 10);
      LocalGetOffAlarmNotifier build() => LocalGetOffAlarmNotifier(
        FlutterLocalNotificationsPlugin(),
        isAndroid: true,
        initializePlugin: () async {},
        pendingIds: () async => pending.toList(),
        cancelId: (id) async => pending.remove(id),
        scheduleAlarm: (id, _, _, _, _) async => pending.add(id),
      );

      await build().scheduleAlarms([
        ScheduledGetOffAlarm(
          stationId: 't',
          stationName: '환승',
          kind: GetOffAlarmKind.transfer,
          fireAt: arrivalAt.subtract(const Duration(minutes: 5)),
          arrivalAt: arrivalAt,
          slot: 0,
        ),
        ScheduledGetOffAlarm(
          stationId: 'd',
          stationName: '목적',
          kind: GetOffAlarmKind.destination,
          fireAt: arrivalAt.subtract(const Duration(minutes: 2)),
          arrivalAt: arrivalAt,
          slot: 1,
        ),
      ], mode: GetOffAlarmScheduleMode.exact);
      expect(pending, {base, base + 1});

      // 재부팅 후: transfer는 이미 만료돼 목록에서 빠지고 destination만 남지만
      // slot은 1로 고정. base+1을 재사용해 부팅 복원분과 겹쳐도 중복이 없다.
      await build().scheduleAlarms([
        ScheduledGetOffAlarm(
          stationId: 'd',
          stationName: '목적',
          kind: GetOffAlarmKind.destination,
          fireAt: arrivalAt.subtract(const Duration(minutes: 2)),
          arrivalAt: arrivalAt,
          slot: 1,
        ),
      ], mode: GetOffAlarmScheduleMode.exact);
      expect(pending, {base + 1});
    });

    test('공식 boot receiver와 reconcile은 실행 순서와 무관하게 중복 pending이 없다', () async {
      final base = LocalGetOffAlarmNotifier.baseNotificationId;
      final arrivalAt = DateTime(2026, 7, 10, 10);

      for (final reconcileFirst in [true, false]) {
        final pending = <int>{};
        LocalGetOffAlarmNotifier build() => LocalGetOffAlarmNotifier(
          FlutterLocalNotificationsPlugin(),
          isAndroid: true,
          initializePlugin: () async {},
          pendingIds: () async => pending.toList(),
          cancelId: (id) async => pending.remove(id),
          scheduleAlarm: (id, _, _, _, _) async => pending.add(id),
        );
        // 부팅 전 persisted 상태: destination(slot 1)만 예약돼 있었다.
        const prebootIds = {1};
        // 공식 ScheduledNotificationBootReceiver는 persisted ID를 그대로 되살린다.
        void bootRestore() => pending.addAll(prebootIds.map((s) => base + s));
        // WorkManager reconcile은 slot 기반으로 destination(slot 1)만 재예약한다.
        Future<void> reconcile() => build().scheduleAlarms([
          ScheduledGetOffAlarm(
            stationId: 'd',
            stationName: '목적',
            kind: GetOffAlarmKind.destination,
            fireAt: arrivalAt.subtract(const Duration(minutes: 2)),
            arrivalAt: arrivalAt,
            slot: 1,
          ),
        ], mode: GetOffAlarmScheduleMode.exact);

        if (reconcileFirst) {
          await reconcile();
          bootRestore();
        } else {
          bootRestore();
          await reconcile();
        }

        expect(pending, {base + 1});
      }
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
