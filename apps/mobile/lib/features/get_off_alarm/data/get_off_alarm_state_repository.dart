import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/user/user_database.dart' as user_db;
import '../get_off_alarm_subscription.dart';

/// 활성 하차 알림 구독을 로컬에 영속 저장하는 리포지토리.
abstract class GetOffAlarmStateRepository {
  Future<GetOffAlarmSubscription?> loadActive();

  Future<void> saveActive(GetOffAlarmSubscription subscription);

  Future<void> clearActive();
}

/// 기존 `app_preferences`(key/value) 테이블에 JSON으로 저장하는 구현.
///
/// 새 테이블·마이그레이션을 추가하지 않고 기존 자산을 재사용한다
/// (network_map viewport·알림 설정 저장과 동일 패턴). 단일 경로 원칙에 따라
/// 활성 구독은 항상 하나의 키에만 존재한다.
class DriftGetOffAlarmStateRepository implements GetOffAlarmStateRepository {
  DriftGetOffAlarmStateRepository({required this.userDatabase});

  final user_db.UserDatabase userDatabase;

  static const String _storageKey = 'get_off_alarm_active';

  @override
  Future<GetOffAlarmSubscription?> loadActive() async {
    final row = await userDatabase
        .customSelect(
          'SELECT value FROM app_preferences WHERE key = ?',
          variables: [Variable.withString(_storageKey)],
          readsFrom: {userDatabase.appPreferences},
        )
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(row.read<String>('value'));
    } on FormatException {
      return null;
    }
    return GetOffAlarmSubscription.fromJson(decoded);
  }

  @override
  Future<void> saveActive(GetOffAlarmSubscription subscription) async {
    await userDatabase
        .into(userDatabase.appPreferences)
        .insertOnConflictUpdate(
          user_db.AppPreferencesCompanion.insert(
            key: _storageKey,
            value: jsonEncode(subscription.toJson()),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }

  @override
  Future<void> clearActive() async {
    await userDatabase.customStatement(
      'DELETE FROM app_preferences WHERE key = ?',
      [_storageKey],
    );
  }
}
