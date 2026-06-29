import 'package:drift/drift.dart';

import '../database/user/user_database.dart' as user_db;
import 'data_pack_manifest.dart';

class DataPackUpdateStateRepository {
  DataPackUpdateStateRepository({
    required this.userDatabase,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const _manifestEtagKey = 'datapack_manifest_etag';
  static const _manifestCheckedAtKey = 'datapack_manifest_checked_at_ms';
  static const _manifestTtlKey = 'datapack_manifest_ttl_seconds';
  static const _manifestExpiresAtKey = 'datapack_manifest_expires_at_ms';
  static const _acceptedSequencePrefix = 'datapack_manifest_accepted_sequence_';
  static const _acceptedHashPrefix = 'datapack_manifest_accepted_hash_';
  static const _acceptedAtPrefix = 'datapack_manifest_accepted_at_ms_';

  final user_db.UserDatabase userDatabase;
  final DateTime Function() _now;

  Future<DataPackManifestCache?> readManifestCache() async {
    final rows = await userDatabase
        .customSelect(
          'SELECT key, value FROM data_pack_update_state WHERE key IN (?, ?, ?, ?)',
          variables: [
            Variable<String>(_manifestEtagKey),
            Variable<String>(_manifestCheckedAtKey),
            Variable<String>(_manifestTtlKey),
            Variable<String>(_manifestExpiresAtKey),
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
    final expiresAtMs = int.tryParse(values[_manifestExpiresAtKey] ?? '');
    if (checkedAtMs == null || ttlSeconds == null || ttlSeconds <= 0) {
      return null;
    }
    return DataPackManifestCache(
      etag: values[_manifestEtagKey],
      checkedAt: DateTime.fromMillisecondsSinceEpoch(checkedAtMs, isUtc: true),
      ttl: Duration(seconds: ttlSeconds),
      expiresAt: expiresAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expiresAtMs, isUtc: true),
    );
  }

  Future<void> saveManifestCache({
    required String? etag,
    required DateTime checkedAt,
    required Duration ttl,
    DateTime? expiresAt,
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
      if (expiresAt == null) {
        await userDatabase.customStatement(
          'DELETE FROM data_pack_update_state WHERE key = ?',
          [_manifestExpiresAtKey],
        );
      } else {
        await _put(
          _manifestExpiresAtKey,
          expiresAt.toUtc().millisecondsSinceEpoch.toString(),
          checkedAt,
        );
      }
    });
  }

  Future<void> ensureManifestCanBeAccepted(DataPackManifest manifest) async {
    if (!manifest.hasReplayProtection) {
      if (await hasAcceptedManifestState()) {
        throw const DataPackManifestReplayException(
          '앱 이동 정보를 안전하게 확인하지 못했습니다.',
        );
      }
      return;
    }
    final channel = manifest.channel!;
    final sequence = manifest.releaseSequence!;
    final hash = manifest.manifestHash!;
    final accepted = await readAcceptedManifestState(channel);
    if (accepted == null) {
      return;
    }
    if (sequence < accepted.releaseSequence) {
      throw const DataPackManifestReplayException('앱 이동 정보가 오래된 버전입니다.');
    }
    if (sequence == accepted.releaseSequence && hash != accepted.manifestHash) {
      throw const DataPackManifestReplayException('앱 이동 정보가 서로 맞지 않습니다.');
    }
  }

  Future<DataPackAcceptedManifestState?> readAcceptedManifestState(
    String channel,
  ) async {
    final rows = await userDatabase
        .customSelect(
          'SELECT key, value FROM data_pack_update_state WHERE key IN (?, ?, ?)',
          variables: [
            Variable<String>(_acceptedSequenceKey(channel)),
            Variable<String>(_acceptedHashKey(channel)),
            Variable<String>(_acceptedAtKey(channel)),
          ],
          readsFrom: {userDatabase.dataPackUpdateState},
        )
        .get();
    final values = {
      for (final row in rows)
        row.read<String>('key'): row.read<String>('value'),
    };
    final sequence = int.tryParse(values[_acceptedSequenceKey(channel)] ?? '');
    final hash = values[_acceptedHashKey(channel)];
    final acceptedAtMs = int.tryParse(values[_acceptedAtKey(channel)] ?? '');
    if (sequence == null ||
        sequence <= 0 ||
        hash == null ||
        hash.isEmpty ||
        acceptedAtMs == null) {
      return null;
    }
    return DataPackAcceptedManifestState(
      channel: channel,
      releaseSequence: sequence,
      manifestHash: hash,
      acceptedAt: DateTime.fromMillisecondsSinceEpoch(
        acceptedAtMs,
        isUtc: true,
      ),
    );
  }

  Future<bool> hasAcceptedManifestState() async {
    final row = await userDatabase
        .customSelect(
          'SELECT COUNT(*) AS count FROM data_pack_update_state WHERE key LIKE ?',
          variables: [Variable<String>('$_acceptedSequencePrefix%')],
          readsFrom: {userDatabase.dataPackUpdateState},
        )
        .getSingle();
    return row.read<int>('count') > 0;
  }

  Future<void> saveAcceptedManifestState(DataPackManifest manifest) async {
    if (!manifest.hasReplayProtection) {
      return;
    }
    await ensureManifestCanBeAccepted(manifest);
    final channel = manifest.channel!;
    final acceptedAt = _now().toUtc();
    await userDatabase.transaction(() async {
      await _put(
        _acceptedSequenceKey(channel),
        manifest.releaseSequence!.toString(),
        acceptedAt,
      );
      await _put(_acceptedHashKey(channel), manifest.manifestHash!, acceptedAt);
      await _put(
        _acceptedAtKey(channel),
        acceptedAt.millisecondsSinceEpoch.toString(),
        acceptedAt,
      );
    });
  }

  bool isFresh(DataPackManifestCache cache) {
    final now = _now().toUtc();
    final expiresAt = cache.expiresAt;
    if (expiresAt != null && !now.isBefore(expiresAt)) {
      return false;
    }
    return !now.isAfter(cache.checkedAt.add(cache.ttl));
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

String _acceptedSequenceKey(String channel) =>
    '${DataPackUpdateStateRepository._acceptedSequencePrefix}$channel';

String _acceptedHashKey(String channel) =>
    '${DataPackUpdateStateRepository._acceptedHashPrefix}$channel';

String _acceptedAtKey(String channel) =>
    '${DataPackUpdateStateRepository._acceptedAtPrefix}$channel';

class DataPackManifestCache {
  const DataPackManifestCache({
    required this.checkedAt,
    required this.ttl,
    this.etag,
    this.expiresAt,
  });

  final String? etag;
  final DateTime checkedAt;
  final Duration ttl;
  final DateTime? expiresAt;
}

class DataPackAcceptedManifestState {
  const DataPackAcceptedManifestState({
    required this.channel,
    required this.releaseSequence,
    required this.manifestHash,
    required this.acceptedAt,
  });

  final String channel;
  final int releaseSequence;
  final String manifestHash;
  final DateTime acceptedAt;
}

class DataPackManifestReplayException implements Exception {
  const DataPackManifestReplayException(this.message);

  final String message;

  @override
  String toString() => message;
}
