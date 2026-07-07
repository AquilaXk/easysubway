import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/user/user_database.dart' as user_db;
import '../domain/service_notice.dart';
import 'notice_repository.dart';

/// 공지 캐시를 기존 `app_preferences`(key/value)에 JSON으로 저장하는 구현.
///
/// 새 테이블·마이그레이션을 추가하지 않고 기존 자산을 재사용한다
/// (network_map viewport·하차 알림 상태 저장과 동일 패턴). 앱 재시작 후에도
/// 오프라인 "N시간 전 기준" 라벨을 위해 수신 시각을 함께 저장한다.
class DriftNoticeCacheStore implements NoticeCacheStore {
  DriftNoticeCacheStore({required this.userDatabase});

  final user_db.UserDatabase userDatabase;

  static const String _storageKey = 'service_notice_cache';

  @override
  Future<NoticeCacheEntry?> load() async {
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
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final fetchedMs = decoded['fetchedAtEpochMs'];
    if (fetchedMs is! int) {
      return null;
    }
    final etag = decoded['etag'];
    return NoticeCacheEntry(
      etag: etag is String ? etag : null,
      notices: ServiceNotice.listFromApiData(decoded['notices']),
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedMs, isUtc: true),
    );
  }

  @override
  Future<void> save(NoticeCacheEntry entry) async {
    final payload = jsonEncode({
      'etag': entry.etag,
      'notices': entry.notices.map((notice) => notice.toJson()).toList(),
      'fetchedAtEpochMs': entry.fetchedAt.toUtc().millisecondsSinceEpoch,
    });
    await userDatabase
        .into(userDatabase.appPreferences)
        .insertOnConflictUpdate(
          user_db.AppPreferencesCompanion.insert(
            key: _storageKey,
            value: payload,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }
}
