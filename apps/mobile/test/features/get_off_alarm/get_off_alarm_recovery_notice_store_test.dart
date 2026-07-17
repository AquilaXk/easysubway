import 'package:easysubway_mobile/core/database/user/user_database.dart';
import 'package:easysubway_mobile/features/get_off_alarm/data/get_off_alarm_recovery_notice_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late UserDatabase db;
  late DriftGetOffAlarmRecoveryNoticeStore store;

  setUp(() {
    db = UserDatabase.memory();
    store = DriftGetOffAlarmRecoveryNoticeStore(userDatabase: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('기록이 없으면 consume은 false를 돌려준다', () async {
    expect(await store.consume(), isFalse);
  });

  test('record 후 첫 consume만 true이고 이후에는 false다(one-shot)', () async {
    await store.record();

    expect(await store.consume(), isTrue);
    expect(await store.consume(), isFalse);
  });

  test('record는 idempotent하며 단일 플래그로 유지된다', () async {
    await store.record();
    await store.record();

    expect(await store.consume(), isTrue);
    expect(await store.consume(), isFalse);
  });
}
