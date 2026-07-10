import 'dart:async';

import 'package:easysubway_mobile/core/database/user/user_database.dart';
import 'package:easysubway_mobile/features/get_off_alarm/data/get_off_alarm_state_repository.dart';
import 'package:easysubway_mobile/features/get_off_alarm/exact_alarm_permission.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_controller.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_notifier.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_schedule_mode.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_scheduler.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_subscription.dart';
import 'package:easysubway_mobile/main.dart' as app;
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:easysubway_mobile/notification_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingNotifier implements GetOffAlarmNotifier {
  List<ScheduledGetOffAlarm>? scheduledAlarms;
  GetOffAlarmScheduleMode? scheduledMode;
  ScheduleDeliveryResult? result;
  int cancelAllCount = 0;
  Completer<void>? cancelBarrier;
  Object? cancelErrorOnce;

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
    final error = cancelErrorOnce;
    cancelErrorOnce = null;
    if (error != null) {
      throw error;
    }
    await cancelBarrier?.future;
  }
}

class _RecordingStateRepository implements GetOffAlarmStateRepository {
  _RecordingStateRepository({this.loadError});

  GetOffAlarmSubscription? active;
  Object? loadError;
  int clearCount = 0;

  @override
  Future<void> clearActive() async {
    clearCount += 1;
    active = null;
  }

  @override
  Future<GetOffAlarmSubscription?> loadActive() async {
    final error = loadError;
    if (error != null) {
      throw error;
    }
    return active;
  }

  @override
  Future<void> saveActive(GetOffAlarmSubscription subscription) async {
    active = subscription;
  }
}

class _StubExactAlarmGate implements ExactAlarmPermissionGate {
  _StubExactAlarmGate(this.permitted);

  bool permitted;
  int isPermittedCalls = 0;
  int requestCalls = 0;

  @override
  Future<bool> isExactAlarmPermitted() async {
    isPermittedCalls += 1;
    return permitted;
  }

  @override
  Future<bool> requestExactAlarmPermission() async {
    requestCalls += 1;
    return permitted;
  }
}

class _BlockingRefreshExactAlarmGate implements ExactAlarmPermissionGate {
  final isPermittedStarted = Completer<void>();
  final permitted = Completer<bool>();
  int isPermittedCalls = 0;

  @override
  Future<bool> isExactAlarmPermitted() {
    isPermittedCalls += 1;
    if (!isPermittedStarted.isCompleted) {
      isPermittedStarted.complete();
    }
    return permitted.future;
  }

  @override
  Future<bool> requestExactAlarmPermission() async => true;
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
  late _StubExactAlarmGate exactAlarmGate;

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
    exactAlarmGate = _StubExactAlarmGate(exactPermitted);
    return GetOffAlarmController(
      notifier: notifier,
      permissionGate: exactAlarmGate,
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
    expect(c.state.permissionNotice, '휴대전화 알림 권한을 허용해 주세요.');
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
    expect((await repository.loadActive())!.scheduledCount, 1);
  });

  test('부분 예약 성공 수는 저장되고 restore에서도 그대로 복원된다', () async {
    notifier.result = const ScheduleDeliveryResult(
      scheduledCount: 1,
      failedCount: 1,
    );
    final first = controller(exactPermitted: true);
    await first.enable(
      routeId: 'r1',
      stops: stops(),
      transferAlarmEnabled: true,
    );

    final restored = controller(exactPermitted: true);
    await restored.restore();

    expect(restored.state.enabled, isTrue);
    expect(restored.state.scheduledCount, 1);
  });

  test('restore는 저장된 inexact 강등 상태와 고지를 복원한다', () async {
    final first = controller(exactPermitted: false);
    await first.enable(
      routeId: 'r1',
      stops: stops(),
      transferAlarmEnabled: true,
    );

    final restored = controller(exactPermitted: true);
    await restored.restore();

    expect(restored.state.enabled, isTrue);
    expect(restored.state.scheduleMode, GetOffAlarmScheduleMode.inexact);
    expect(restored.state.inexactNotice, contains('오차'));
  });

  test('refresh는 exact 권한 상태만 확인하고 권한을 다시 요청하지 않는다', () async {
    final c = controller(exactPermitted: true);
    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true);
    expect(exactAlarmGate.requestCalls, 1);
    expect(exactAlarmGate.isPermittedCalls, 0);

    exactAlarmGate.permitted = false;
    await c.refresh(stops: stops(), transferAlarmEnabled: true);

    expect(exactAlarmGate.requestCalls, 1);
    expect(exactAlarmGate.isPermittedCalls, 1);
    expect(c.state.scheduleMode, GetOffAlarmScheduleMode.inexact);
    expect(c.state.inexactNotice, contains('오차'));
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

  test('startup restore 예외는 앱 시작 경계 밖으로 전파하지 않는다', () async {
    final error = StateError('database unavailable');
    final startupController = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmGate(true),
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: _RecordingStateRepository(loadError: error),
      now: () => now,
    );
    addTearDown(startupController.dispose);
    final reports = <FlutterErrorDetails>[];

    await runWithMobileErrorReporter(
      reports.add,
      () => app.restoreGetOffAlarmState(startupController),
    );

    expect(reports, hasLength(1));
    expect(reports.single.exception, same(error));
    expect(reports.single.context.toString(), isNot(contains('route')));
  });

  test('restore에서 active가 없으면 pending 알림과 저장값을 정리한다', () async {
    final stateRepository = _RecordingStateRepository();
    final restored = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmGate(true),
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => now,
    );
    addTearDown(restored.dispose);

    await restored.restore();

    expect(notifier.cancelAllCount, 1);
    expect(stateRepository.clearCount, 1);
    expect(restored.state.enabled, isFalse);
  });

  test('진행 중 refresh 뒤 disable은 마지막 cancel clear off 상태를 보장한다', () async {
    final gate = _BlockingRefreshExactAlarmGate();
    final stateRepository = _RecordingStateRepository();
    final c = GetOffAlarmController(
      notifier: notifier,
      permissionGate: gate,
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => now,
    );
    addTearDown(c.dispose);
    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true);

    final refresh = c.refresh(stops: stops(), transferAlarmEnabled: true);
    await gate.isPermittedStarted.future;
    final disable = c.disable();
    gate.permitted.complete(true);
    await Future.wait([refresh, disable]);

    expect(notifier.cancelAllCount, 1);
    expect(stateRepository.active, isNull);
    expect(c.state.enabled, isFalse);
    expect(c.state.activeRouteId, isNull);
  });

  test('disable 뒤 queued refresh는 off 상태를 재확인하고 no-op 한다', () async {
    final gate = _StubExactAlarmGate(true);
    final stateRepository = _RecordingStateRepository();
    final c = GetOffAlarmController(
      notifier: notifier,
      permissionGate: gate,
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => now,
    );
    addTearDown(c.dispose);
    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true);
    notifier.cancelBarrier = Completer<void>();

    final disable = c.disable();
    await Future<void>.delayed(Duration.zero);
    final refresh = c.refresh(stops: stops(), transferAlarmEnabled: true);
    await Future<void>.delayed(Duration.zero);
    notifier.cancelBarrier!.complete();
    await Future.wait([disable, refresh]);

    expect(gate.isPermittedCalls, 0);
    expect(stateRepository.active, isNull);
    expect(c.state.enabled, isFalse);
  });

  test('앞선 mutation 오류가 다음 disable queue를 poison하지 않는다', () async {
    final stateRepository = _RecordingStateRepository();
    final c = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmGate(true),
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => now,
    );
    addTearDown(c.dispose);
    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true);
    notifier.cancelErrorOnce = StateError('cancel failed');

    await expectLater(c.disable(), throwsStateError);
    await c.disable();

    expect(notifier.cancelAllCount, 2);
    expect(stateRepository.active, isNull);
    expect(c.state.enabled, isFalse);
  });
}
