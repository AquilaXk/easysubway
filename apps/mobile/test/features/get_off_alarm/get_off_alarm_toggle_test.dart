import 'package:easysubway_mobile/features/get_off_alarm/exact_alarm_permission.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_controller.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_notifier.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_route_mapping.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_schedule_mode.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_scheduler.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_subscription.dart';
import 'package:easysubway_mobile/features/get_off_alarm/data/get_off_alarm_state_repository.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_toggle.dart';
import 'package:easysubway_mobile/notification_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingNotifier implements GetOffAlarmNotifier {
  List<ScheduledGetOffAlarm>? scheduled;
  int cancelCount = 0;

  @override
  Future<ScheduleDeliveryResult> scheduleAlarms(
    List<ScheduledGetOffAlarm> alarms, {
    required GetOffAlarmScheduleMode mode,
  }) async {
    scheduled = alarms;
    return ScheduleDeliveryResult(
      scheduledCount: alarms.length,
      failedCount: 0,
    );
  }

  @override
  Future<void> cancelAll() async {
    cancelCount++;
  }
}

class _StubGate implements ExactAlarmPermissionGate {
  _StubGate(this.permitted);
  final bool permitted;
  @override
  Future<bool> isExactAlarmPermitted() async => permitted;
  @override
  Future<bool> requestExactAlarmPermission() async => permitted;
}

class _GrantedNotificationPermissionProvider
    implements NotificationPermissionProvider {
  @override
  Future<NotificationPermissionStatus> requestNotificationPermission() async =>
      NotificationPermissionStatus.granted;
}

class _FakeRepo implements GetOffAlarmStateRepository {
  GetOffAlarmSubscription? _active;
  @override
  Future<GetOffAlarmSubscription?> loadActive() async => _active;
  @override
  Future<void> saveActive(GetOffAlarmSubscription subscription) async =>
      _active = subscription;
  @override
  Future<void> clearActive() async => _active = null;
}

void main() {
  testWidgets('토글을 켜면 컨트롤러가 알림을 예약하고 상태가 켜진다', (tester) async {
    final notifier = _RecordingNotifier();
    final controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubGate(true),
      notificationPermissionProvider: _GrantedNotificationPermissionProvider(),
      repository: _FakeRepo(),
      now: () => DateTime(2026, 7, 6, 9, 0, 0),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GetOffAlarmToggle(
            controller: controller,
            routeId: 'r1',
            rideLegs: const [
              RideLegArrival(
                toStationId: 'sadang',
                plannedArrivalIso: '2026-07-06T09:30:00',
              ),
            ],
            stationName: (id) => id == 'sadang' ? '사당' : id,
          ),
        ),
      ),
    );

    expect(find.text('하차 알림'), findsOneWidget);
    expect(controller.state.enabled, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(controller.state.enabled, isTrue);
    expect(controller.state.activeRouteId, 'r1');
    expect(notifier.scheduled, isNotNull);
    expect(notifier.scheduled!.single.stationName, '사당');
  });

  testWidgets('토글을 다시 끄면 disable로 알림을 취소하고 상태가 꺼진다', (tester) async {
    final notifier = _RecordingNotifier();
    final controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubGate(true),
      notificationPermissionProvider: _GrantedNotificationPermissionProvider(),
      repository: _FakeRepo(),
      now: () => DateTime(2026, 7, 6, 9, 0, 0),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GetOffAlarmToggle(
            controller: controller,
            routeId: 'r1',
            rideLegs: const [
              RideLegArrival(
                toStationId: 'sadang',
                plannedArrivalIso: '2026-07-06T09:30:00',
              ),
            ],
            stationName: (id) => id,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(controller.state.enabled, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(controller.state.enabled, isFalse);
    expect(notifier.cancelCount, greaterThanOrEqualTo(1));
  });

  testWidgets('exact 권한 거부 시 오차 고지 문구를 노출한다', (tester) async {
    final controller = GetOffAlarmController(
      notifier: _RecordingNotifier(),
      permissionGate: _StubGate(false),
      notificationPermissionProvider: _GrantedNotificationPermissionProvider(),
      repository: _FakeRepo(),
      now: () => DateTime(2026, 7, 6, 9, 0, 0),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GetOffAlarmToggle(
            controller: controller,
            routeId: 'r1',
            rideLegs: const [
              RideLegArrival(
                toStationId: 'sadang',
                plannedArrivalIso: '2026-07-06T09:30:00',
              ),
            ],
            stationName: (id) => id,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.textContaining('오차'), findsOneWidget);
  });
}
