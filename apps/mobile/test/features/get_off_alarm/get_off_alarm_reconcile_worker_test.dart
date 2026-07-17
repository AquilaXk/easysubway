import 'package:drift/native.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart';
import 'package:easysubway_mobile/features/get_off_alarm/data/get_off_alarm_state_repository.dart';
import 'package:easysubway_mobile/features/get_off_alarm/exact_alarm_permission.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_controller.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_notifier.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_reconcile_worker.dart';
import 'package:easysubway_mobile/notification_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// 컨트롤러 조립에 필요한 협력자들의 no-op 대역. reconcile을 오버라이드한
/// 테스트 컨트롤러에서는 실제로 호출되지 않으므로 noSuchMethod로 일괄 대체한다.
class _NoopDeps
    implements
        GetOffAlarmNotifier,
        ExactAlarmPermissionGate,
        NotificationPermissionProvider,
        GetOffAlarmStateRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final _noopDeps = _NoopDeps();

/// reconcile 동작을 주입받고 dispose 호출을 기록하는 테스트 컨트롤러.
class _RecordingReconcileController extends GetOffAlarmController {
  _RecordingReconcileController({required this.onReconcile})
    : super(
        notifier: _noopDeps,
        permissionGate: _noopDeps,
        notificationPermissionProvider: _noopDeps,
        repository: _noopDeps,
      );

  final Future<void> Function() onReconcile;
  int disposeCount = 0;

  @override
  Future<void> reconcile() => onReconcile();

  @override
  void dispose() {
    disposeCount += 1;
    super.dispose();
  }
}

/// close 호출을 기록하는 인메모리 user DB.
class _RecordingUserDatabase extends UserDatabase {
  _RecordingUserDatabase() : super(NativeDatabase.memory());

  int closeCount = 0;

  @override
  Future<void> close() {
    closeCount += 1;
    return super.close();
  }
}

void main() {
  test('reconcile 성공은 true를 돌려주고 finally에서 리소스를 닫는다', () async {
    var reconcileCount = 0;
    var closeCount = 0;
    final errors = <Object>[];

    final result = await reconcileGetOffAlarmHeadless(
      reconcile: () async => reconcileCount += 1,
      close: () async => closeCount += 1,
      reportError: (error, _) => errors.add(error),
    );

    expect(result, isTrue);
    expect(reconcileCount, 1);
    expect(closeCount, 1);
    expect(errors, isEmpty);
  });

  test('reconcile 예외는 fail-closed(false)로 삼키고 리소스를 반드시 닫는다', () async {
    final failure = StateError('reconcile failed');
    var closeCount = 0;
    final errors = <Object>[];

    final result = await reconcileGetOffAlarmHeadless(
      reconcile: () async => throw failure,
      close: () async => closeCount += 1,
      reportError: (error, _) => errors.add(error),
    );

    expect(result, isFalse);
    expect(closeCount, 1);
    expect(errors.single, same(failure));
  });

  test('close 자체가 실패해도 성공 결과를 유지한 채 예외를 전파한다', () async {
    final closeFailure = StateError('close failed');

    await expectLater(
      reconcileGetOffAlarmHeadless(
        reconcile: () async {},
        close: () async => throw closeFailure,
        reportError: (_, _) {},
      ),
      throwsA(same(closeFailure)),
    );
  });

  test(
    '프로덕션 진입점은 성공 경로에서 열린 DB로 컨트롤러를 조립하고 close에서 dispose·DB close를 부른다',
    () async {
      final db = _RecordingUserDatabase();
      final controller = _RecordingReconcileController(
        onReconcile: () async {},
      );
      UserDatabase? passedToFactory;
      final errors = <Object>[];

      final result = await runGetOffAlarmReconcileTask(
        reportError: (error, _) => errors.add(error),
        openUserDatabase: () async => db,
        createController: (userDatabase) {
          passedToFactory = userDatabase;
          return controller;
        },
      );

      expect(result, isTrue);
      // 컨트롤러 factory는 열린 DB를 그대로 전달받는다.
      expect(passedToFactory, same(db));
      // close 경로가 성공 후에도 두 리소스를 모두 닫는다.
      expect(controller.disposeCount, 1);
      expect(db.closeCount, 1);
      expect(errors, isEmpty);
    },
  );

  test(
    '프로덕션 진입점은 예외 경로에서도 close에서 dispose·DB close를 부르고 fail-closed한다',
    () async {
      final db = _RecordingUserDatabase();
      final failure = StateError('reconcile boom');
      final controller = _RecordingReconcileController(
        onReconcile: () async => throw failure,
      );
      final errors = <Object>[];

      final result = await runGetOffAlarmReconcileTask(
        reportError: (error, _) => errors.add(error),
        openUserDatabase: () async => db,
        createController: (_) => controller,
      );

      expect(result, isFalse);
      expect(controller.disposeCount, 1);
      expect(db.closeCount, 1);
      expect(errors.single, same(failure));
    },
  );

  test('reconcile work 예약 계약 상수는 15분·전용 unique·task 이름을 고정한다', () {
    expect(getOffAlarmReconcileFrequency, const Duration(minutes: 15));
    expect(getOffAlarmReconcileUniqueName, 'get-off-alarm-reconcile');
    expect(getOffAlarmReconcileTask, 'getOffAlarmReconcile');
  });
}
