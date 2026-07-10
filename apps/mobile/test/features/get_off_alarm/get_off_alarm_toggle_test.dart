import 'dart:async';

import 'package:easysubway_mobile/features/get_off_alarm/exact_alarm_permission.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_controller.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_notifier.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_route_mapping.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_schedule_mode.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_scheduler.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_subscription.dart';
import 'package:easysubway_mobile/features/get_off_alarm/data/get_off_alarm_state_repository.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_toggle.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
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

  @override
  Future<int> pendingAlarmCount() async => scheduled?.length ?? 0;
}

class _StubGate implements ExactAlarmPermissionGate {
  _StubGate(this.permitted);
  final bool permitted;
  @override
  Future<bool> isExactAlarmPermitted() async => permitted;
  @override
  Future<bool> requestExactAlarmPermission() async => permitted;
}

class _StubNotificationPermissionProvider
    implements NotificationPermissionProvider {
  const _StubNotificationPermissionProvider([
    this.status = NotificationPermissionStatus.granted,
  ]);

  final NotificationPermissionStatus status;

  @override
  Future<NotificationPermissionStatus> notificationPermissionStatus() async =>
      status;

  @override
  Future<NotificationPermissionStatus> requestNotificationPermission() async =>
      status;
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
      notificationPermissionProvider:
          const _StubNotificationPermissionProvider(),
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
            stationName: (id) async => id == 'sadang' ? '사당' : null,
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
      notificationPermissionProvider:
          const _StubNotificationPermissionProvider(),
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
            stationName: (_) async => '사당',
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

  testWidgets('토글은 여러 승차 구간의 역명을 비동기로 해소해 예약과 구독에 저장한다', (tester) async {
    final notifier = _RecordingNotifier();
    final repository = _FakeRepo();
    final controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubGate(true),
      notificationPermissionProvider:
          const _StubNotificationPermissionProvider(),
      repository: repository,
      now: () => DateTime(2026, 7, 6, 9, 0),
    );
    addTearDown(controller.dispose);
    final resolvedStationIds = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GetOffAlarmToggle(
            controller: controller,
            routeId: 'r1',
            rideLegs: const [
              RideLegArrival(
                toStationId: 'geumjeong',
                plannedArrivalIso: '2026-07-06T09:15:00',
              ),
              RideLegArrival(
                toStationId: 'sadang',
                plannedArrivalIso: '2026-07-06T09:30:00',
              ),
            ],
            stationName: (id) async {
              resolvedStationIds.add(id);
              return switch (id) {
                'geumjeong' => ' 금정 ',
                'sadang' => '사당',
                _ => null,
              };
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(resolvedStationIds, ['geumjeong', 'sadang']);
    expect(notifier.scheduled?.map((alarm) => alarm.stationName), ['금정', '사당']);
    final active = await repository.loadActive();
    expect(active?.transfers.map((stop) => stop.stationName), ['금정']);
    expect(active?.destination.stationName, '사당');
  });

  testWidgets('역명이 비어 있으면 하차 알림을 예약하거나 저장하지 않는다', (tester) async {
    final notifier = _RecordingNotifier();
    final repository = _FakeRepo();
    final controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubGate(true),
      notificationPermissionProvider:
          const _StubNotificationPermissionProvider(),
      repository: repository,
      now: () => DateTime(2026, 7, 6, 9, 0),
    );
    addTearDown(controller.dispose);
    final reports = <FlutterErrorDetails>[];

    await runWithMobileErrorReporter(reports.add, () async {
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
              stationName: (_) async => '   ',
            ),
          ),
        ),
      );

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
    });

    expect(reports, hasLength(1));
    expect(find.text('하차 알림을 바꾸지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    expect(notifier.scheduled, isNull);
    expect(await repository.loadActive(), isNull);
    expect(controller.state.enabled, isFalse);
  });

  testWidgets('역명 해소가 실패하면 하차 알림을 예약하거나 저장하지 않는다', (tester) async {
    final notifier = _RecordingNotifier();
    final repository = _FakeRepo();
    final controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubGate(true),
      notificationPermissionProvider:
          const _StubNotificationPermissionProvider(),
      repository: repository,
      now: () => DateTime(2026, 7, 6, 9, 0),
    );
    addTearDown(controller.dispose);
    final reports = <FlutterErrorDetails>[];
    final lookupError = StateError('lookup failed');

    await runWithMobileErrorReporter(reports.add, () async {
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
              stationName: (_) async => throw lookupError,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
    });

    expect(reports, hasLength(1));
    expect(reports.single.exception, same(lookupError));
    expect(find.text('하차 알림을 바꾸지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    expect(notifier.scheduled, isNull);
    expect(await repository.loadActive(), isNull);
    expect(controller.state.enabled, isFalse);
  });

  testWidgets('역명 조회 중 외부 disable이 완료되면 오래된 enable을 실행하지 않는다', (tester) async {
    final notifier = _RecordingNotifier();
    final repository = _FakeRepo();
    final stationName = Completer<String?>();
    final controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubGate(true),
      notificationPermissionProvider:
          const _StubNotificationPermissionProvider(),
      repository: repository,
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
            stationName: (_) => stationName.future,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await controller.disable();

    stationName.complete('사당');
    await tester.pumpAndSettle();

    expect(controller.state.enabled, isFalse);
    expect(await repository.loadActive(), isNull);
    expect(notifier.scheduled, isNull);
    expect(notifier.cancelCount, 1);
  });

  testWidgets('exact 권한 거부 시 오차 고지 문구를 노출한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final controller = GetOffAlarmController(
      notifier: _RecordingNotifier(),
      permissionGate: _StubGate(false),
      notificationPermissionProvider:
          const _StubNotificationPermissionProvider(),
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
            stationName: (_) async => '사당',
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final noticeFinder = find.textContaining('오차');
    expect(noticeFinder, findsOneWidget);
    expect(
      tester.getSemantics(noticeFinder),
      isSemantics(label: '정확 알람 권한이 없어 ±수 분 오차가 있을 수 있어요.', isLiveRegion: true),
    );
    semanticsHandle.dispose();
  });

  testWidgets('알림 권한 거부는 off 상태에서 휴대전화 알림 권한 안내를 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final controller = GetOffAlarmController(
      notifier: _RecordingNotifier(),
      permissionGate: _StubGate(true),
      notificationPermissionProvider: const _StubNotificationPermissionProvider(
        NotificationPermissionStatus.denied,
      ),
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
            stationName: (_) async => '사당',
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(controller.state.enabled, isFalse);
    final noticeFinder = find.text('휴대전화 알림 권한을 허용해 주세요.');
    expect(noticeFinder, findsOneWidget);
    expect(
      tester.getSemantics(noticeFinder),
      isSemantics(label: '휴대전화 알림 권한을 허용해 주세요.', isLiveRegion: true),
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    semanticsHandle.dispose();
  });
}
