import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_reconcile_worker.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('reconcile work 예약 계약 상수는 15분·전용 unique·task 이름을 고정한다', () {
    expect(getOffAlarmReconcileFrequency, const Duration(minutes: 15));
    expect(getOffAlarmReconcileUniqueName, 'get-off-alarm-reconcile');
    expect(getOffAlarmReconcileTask, 'getOffAlarmReconcile');
  });
}
