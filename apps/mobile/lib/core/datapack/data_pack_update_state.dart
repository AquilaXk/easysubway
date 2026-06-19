import 'package:drift/drift.dart';

import '../database/user/user_database.dart' as user_db;

class DataPackUpdateStateRepository {
  DataPackUpdateStateRepository({
    required this.userDatabase,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const _manifestEtagKey = 'datapack_manifest_etag';
  static const _manifestCheckedAtKey = 'datapack_manifest_checked_at_ms';
  static const _manifestTtlKey = 'datapack_manifest_ttl_seconds';

  final user_db.UserDatabase userDatabase;
  final DateTime Function() _now;

  Future<DataPackManifestCache?> readManifestCache() async {
    final rows = await userDatabase
        .customSelect(
          'SELECT key, value FROM data_pack_update_state WHERE key IN (?, ?, ?)',
          variables: [
            Variable<String>(_manifestEtagKey),
            Variable<String>(_manifestCheckedAtKey),
            Variable<String>(_manifestTtlKey),
          ],
          readsFrom: {userDatabase.dataPackUpdateState},
        )
        .get();
    final values = {
      for (final row in rows)
        row.read<String>('key'): row.read<String>('value'),
    };
    final checkedAtMs = int.tryParse(values[_manifestCheckedAtKey] ?? '');
    final ttlSeconds = int.tryParse(values[_manifestTtlKey] ?? '');
    if (checkedAtMs == null || ttlSeconds == null || ttlSeconds <= 0) {
      return null;
    }
    return DataPackManifestCache(
      etag: values[_manifestEtagKey],
      checkedAt: DateTime.fromMillisecondsSinceEpoch(checkedAtMs, isUtc: true),
      ttl: Duration(seconds: ttlSeconds),
    );
  }

  Future<void> saveManifestCache({
    required String? etag,
    required DateTime checkedAt,
    required Duration ttl,
  }) async {
    await userDatabase.transaction(() async {
      if (etag == null || etag.isEmpty) {
        await userDatabase.customStatement(
          'DELETE FROM data_pack_update_state WHERE key = ?',
          [_manifestEtagKey],
        );
      } else {
        await _put(_manifestEtagKey, etag, checkedAt);
      }
      await _put(
        _manifestCheckedAtKey,
        checkedAt.toUtc().millisecondsSinceEpoch.toString(),
        checkedAt,
      );
      await _put(_manifestTtlKey, ttl.inSeconds.toString(), checkedAt);
    });
  }

  bool isFresh(DataPackManifestCache cache) {
    return !_now().toUtc().isAfter(cache.checkedAt.add(cache.ttl));
  }

  Future<void> _put(String key, String value, DateTime updatedAt) async {
    await userDatabase
        .into(userDatabase.dataPackUpdateState)
        .insertOnConflictUpdate(
          user_db.DataPackUpdateStateCompanion.insert(
            key: key,
            value: value,
            updatedAt: updatedAt.toUtc(),
          ),
        );
  }
}

class DataPackManifestCache {
  const DataPackManifestCache({
    required this.checkedAt,
    required this.ttl,
    this.etag,
  });

  final String? etag;
  final DateTime checkedAt;
  final Duration ttl;
}
