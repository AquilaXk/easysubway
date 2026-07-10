import 'package:easysubway_mobile/core/database/user/user_database.dart';
import 'package:easysubway_mobile/features/get_off_alarm/data/get_off_alarm_state_repository.dart';
import 'package:easysubway_mobile/features/get_off_alarm/exact_alarm_permission.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_controller.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_notifier.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_schedule_mode.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_scheduler.dart';
import 'package:easysubway_mobile/notification_settings.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingNotifier implements GetOffAlarmNotifier {
  List<ScheduledGetOffAlarm>? scheduledAlarms;
  GetOffAlarmScheduleMode? scheduledMode;
  ScheduleDeliveryResult? result;
  int cancelAllCount = 0;

  @override
  Future<ScheduleDeliveryResult> scheduleAlarms(
    List<ScheduledGetOffAlarm> alarms, {
    required GetOffAlarmScheduleMode mode,
  }) async {
    scheduledAlarms = alarms;
    scheduledMode = mode;
    return result ??
        ScheduleDeliveryResult(scheduledCount: alarms.length, failedCount: 0);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
  }
}

class _StubExactAlarmGate implements ExactAlarmPermissionGate {
  _StubExactAlarmGate(this.permitted);

  final bool permitted;

  @override
  Future<bool> isExactAlarmPermitted() async => permitted;

  @override
  Future<bool> requestExactAlarmPermission() async => permitted;
}

class _StubNotificationPermissionProvider
    implements NotificationPermissionProvider {
  _StubNotificationPermissionProvider(this.status);

  final NotificationPermissionStatus status;

  @override
  Future<NotificationPermissionStatus> requestNotificationPermission() async =>
      status;
}

void main() {
  final now = DateTime(2026, 7, 6, 9, 0, 0);

  List<GetOffAlarmStop> stops() => [
    GetOffAlarmStop(
      stationId: 'transfer',
      stationName: '동작',
      arrivalAt: DateTime(2026, 7, 6, 9, 15, 0),
      kind: GetOffAlarmKind.transfer,
    ),
    GetOffAlarmStop(
      stationId: 'dest',
      stationName: '사당',
      arrivalAt: DateTime(2026, 7, 6, 9, 30, 0),
      kind: GetOffAlarmKind.destination,
    ),
  ];

  late UserDatabase db;
  late DriftGetOffAlarmStateRepository repository;
  late _RecordingNotifier notifier;

  setUp(() {
    db = UserDatabase.memory();
    repository = DriftGetOffAlarmStateRepository(userDatabase: db);
    notifier = _RecordingNotifier();
  });

  tearDown(() async {
    await db.close();
  });

  GetOffAlarmController controller({
    required bool exactPermitted,
    bool notificationPermitted = true,
  }) {
    return GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmGate(exactPermitted),
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        notificationPermitted
            ? NotificationPermissionStatus.granted
            : NotificationPermissionStatus.denied,
      ),
      repository: repository,
      now: () => now,
    );
  }

  test('정확 알람 권한이 있으면 exact 모드로 예약하고 상태를 켠다', () async {
    final c = controller(exactPermitted: true);

    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true);

    expect(notifier.scheduledMode, GetOffAlarmScheduleMode.exact);
    expect(notifier.scheduledAlarms, hasLength(2));
    expect(c.state.enabled, isTrue);
    expect(c.state.activeRouteId, 'r1');
    expect(c.state.inexactNotice, isNull);
    // 활성 구독이 영속 저장된다.
    expect(await repository.loadActive(), isNotNull);
  });

  test('정확 알람 권한이 없으면 inexact로 강등하고 오차 고지를 상태에 담는다', () async {
    final c = controller(exactPermitted: false);

    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true);

    expect(notifier.scheduledMode, GetOffAlarmScheduleMode.inexact);
    expect(c.state.inexactNotice, isNotNull);
    expect(c.state.inexactNotice, contains('오차'));
  });

  test('환승 알림을 끄면 환승 정차역은 예약하지 않는다', () async {
    final c = controller(exactPermitted: true);

    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: false);

    expect(notifier.scheduledAlarms, hasLength(1));
    expect(notifier.scheduledAlarms!.single.kind, GetOffAlarmKind.destination);
  });

  test('POST_NOTIFICATIONS 거부는 예약과 enabled 저장을 막는다', () async {
    final c = controller(exactPermitted: true, notificationPermitted: false);

    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true);

    expect(notifier.scheduledAlarms, isNull);
    expect(c.state.enabled, isFalse);
    expect(await repository.loadActive(), isNull);
  });

  test('부분 예약 실패는 실제 성공 수만 상태에 반영한다', () async {
    notifier.result = const ScheduleDeliveryResult(
      scheduledCount: 1,
      failedCount: 1,
    );
    final c = controller(exactPermitted: true);

    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true);

    expect(c.state.enabled, isTrue);
    expect(c.state.scheduledCount, 1);
    expect(await repository.loadActive(), isNotNull);
  });

  test('예약 성공이 0건이면 enabled와 활성 구독을 저장하지 않는다', () async {
    notifier.result = const ScheduleDeliveryResult(
      scheduledCount: 0,
      failedCount: 2,
    );
    final c = controller(exactPermitted: true);

    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true);

    expect(c.state.enabled, isFalse);
    expect(c.state.scheduledCount, 0);
    expect(await repository.loadActive(), isNull);
  });

  test('disable은 알림을 취소하고 영속 상태를 지우며 상태를 끈다', () async {
    final c = controller(exactPermitted: true);
    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true);

    await c.disable();

    expect(notifier.cancelAllCount, greaterThanOrEqualTo(1));
    expect(await repository.loadActive(), isNull);
    expect(c.state.enabled, isFalse);
    expect(c.state.activeRouteId, isNull);
  });

  test('destination 스톱이 없으면 예약·저장 없이 조기 반환한다', () async {
    final c = controller(exactPermitted: true);

    await c.enable(
      routeId: 'r1',
      stops: [
        GetOffAlarmStop(
          stationId: 'transfer',
          stationName: '동작',
          arrivalAt: DateTime(2026, 7, 6, 9, 15, 0),
          kind: GetOffAlarmKind.transfer,
        ),
      ],
      transferAlarmEnabled: true,
    );

    expect(notifier.scheduledAlarms, isNull);
    expect(c.state.enabled, isFalse);
    expect(await repository.loadActive(), isNull);
  });

  test('restore는 영속된 활성 구독을 켜진 상태로 복원한다', () async {
    final first = controller(exactPermitted: true);
    await first.enable(
      routeId: 'r1',
      stops: stops(),
      transferAlarmEnabled: true,
    );

    final restored = controller(exactPermitted: true);
    await restored.restore();

    expect(restored.state.enabled, isTrue);
    expect(restored.state.activeRouteId, 'r1');
  });
}
