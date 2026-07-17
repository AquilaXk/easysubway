import 'package:drift/drift.dart';

import '../../../core/database/user/user_database.dart' as user_db;

/// 하차 알림이 headless reconcile에서 알림 권한 거부로 정리됐음을 다음 UI init에
/// 한 번만 알리기 위한 one-shot 복구 안내 플래그.
///
/// headless isolate는 UI를 띄울 수 없으므로 정리 시 플래그만 기록하고, 다음
/// 포그라운드 init이 이를 소비해 안내를 한 번 표시한 뒤 즉시 지운다.
abstract class GetOffAlarmRecoveryNoticeStore {
  /// 복구 안내가 필요함을 기록한다(idempotent).
  Future<void> record();

  /// 플래그가 있으면 지우고 true를, 없으면 false를 돌려준다(one-shot 소비).
  Future<bool> consume();
}

/// 기존 `app_preferences`(key/value) 테이블을 재사용하는 구현. 새 테이블·마이그레이션을
/// 추가하지 않는다(하차 알림 활성 구독 저장과 동일 패턴).
class DriftGetOffAlarmRecoveryNoticeStore
    implements GetOffAlarmRecoveryNoticeStore {
  DriftGetOffAlarmRecoveryNoticeStore({required this.userDatabase});

  final user_db.UserDatabase userDatabase;

  static const String _storageKey = 'get_off_alarm_recovery_notice';

  @override
  Future<void> record() async {
    await userDatabase
        .into(userDatabase.appPreferences)
        .insertOnConflictUpdate(
          user_db.AppPreferencesCompanion.insert(
            key: _storageKey,
            value: 'true',
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }

  @override
  Future<bool> consume() async {
    final row = await userDatabase
        .customSelect(
          'SELECT value FROM app_preferences WHERE key = ?',
          variables: [Variable.withString(_storageKey)],
          readsFrom: {userDatabase.appPreferences},
        )
        .getSingleOrNull();
    if (row == null) {
      return false;
    }
    await userDatabase.customStatement(
      'DELETE FROM app_preferences WHERE key = ?',
      [_storageKey],
    );
    return row.read<String>('value') == 'true';
  }
}
