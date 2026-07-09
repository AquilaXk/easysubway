import 'dart:convert';
import 'dart:math';

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
  static const _rolloutSaltKey = 'datapack_rollout_salt';
  static const _policyStateKey = 'datapack_update_policy_state';

  final user_db.UserDatabase userDatabase;
  final DateTime Function() _now;
  final _secureRandom = Random.secure();

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
        throw const DataPackManifestReplayException('앱 이동 정보를 안전하게 확인하지 못했어요.');
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

  Future<String?> _readValue(String key) async {
    final rows = await userDatabase
        .customSelect(
          'SELECT value FROM data_pack_update_state WHERE key = ?',
          variables: [Variable<String>(key)],
          readsFrom: {userDatabase.dataPackUpdateState},
        )
        .get();
    if (rows.isEmpty) return null;
    return rows.single.read<String>('value');
  }

  /// 단말별 rollout 버킷 판정용 salt를 로컬에서 1회 생성·영속한다.
  /// 재호출 시 동일 값 반환(안정). salt는 절대 네트워크로 전송하지 않는다.
  Future<String> readOrCreateRolloutSalt() async {
    final existing = await _readValue(_rolloutSaltKey);
    if (existing != null && RegExp(r'^[a-f0-9]{32}$').hasMatch(existing)) {
      return existing;
    }
    final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
    final salt = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _put(_rolloutSaltKey, salt, _now());
    return salt;
  }

  Future<DataPackUpdatePolicyState> readPolicyState() async {
    final raw = await _readValue(_policyStateKey);
    if (raw == null || raw.isEmpty) {
      return const DataPackUpdatePolicyState();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return DataPackUpdatePolicyState.fromJson(decoded);
      }
    } on FormatException {
      // Corrupt local policy state should not block offline data use.
    }
    return const DataPackUpdatePolicyState();
  }

  Future<void> savePolicyState(DataPackUpdatePolicyState state) async {
    await _put(_policyStateKey, jsonEncode(state.toJson()), _now());
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

class DataPackUpdatePolicyState {
  const DataPackUpdatePolicyState({
    this.lastCheckAt,
    this.backoffUntil,
    this.backoffAttempts = 0,
    this.pendingConsentBytes,
    this.lastFailureReason,
  });

  factory DataPackUpdatePolicyState.fromJson(Map<String, Object?> json) {
    return DataPackUpdatePolicyState(
      lastCheckAt: _dateFromMs(json['lastCheckAtMs']),
      backoffUntil: _dateFromMs(json['backoffUntilMs']),
      backoffAttempts: _nonNegativeInt(json['backoffAttempts']),
      pendingConsentBytes: _positiveIntOrNull(json['pendingConsentBytes']),
      lastFailureReason: _stringOrNull(json['lastFailureReason']),
    );
  }

  final DateTime? lastCheckAt;
  final DateTime? backoffUntil;
  final int backoffAttempts;
  final int? pendingConsentBytes;
  final String? lastFailureReason;

  Map<String, Object?> toJson() => {
    if (lastCheckAt != null)
      'lastCheckAtMs': lastCheckAt!.toUtc().millisecondsSinceEpoch,
    if (backoffUntil != null)
      'backoffUntilMs': backoffUntil!.toUtc().millisecondsSinceEpoch,
    'backoffAttempts': backoffAttempts,
    if (pendingConsentBytes != null) 'pendingConsentBytes': pendingConsentBytes,
    if (lastFailureReason != null) 'lastFailureReason': lastFailureReason,
  };

  DataPackUpdatePolicyState copyWith({
    DateTime? lastCheckAt,
    DateTime? backoffUntil,
    int? backoffAttempts,
    int? pendingConsentBytes,
    String? lastFailureReason,
    bool clearBackoff = false,
    bool clearPendingConsent = false,
    bool clearLastFailure = false,
  }) {
    return DataPackUpdatePolicyState(
      lastCheckAt: lastCheckAt ?? this.lastCheckAt,
      backoffUntil: clearBackoff ? null : backoffUntil ?? this.backoffUntil,
      backoffAttempts: clearBackoff
          ? 0
          : backoffAttempts ?? this.backoffAttempts,
      pendingConsentBytes: clearPendingConsent
          ? null
          : pendingConsentBytes ?? this.pendingConsentBytes,
      lastFailureReason: clearLastFailure
          ? null
          : lastFailureReason ?? this.lastFailureReason,
    );
  }
}

class DataPackManifestReplayException implements Exception {
  const DataPackManifestReplayException(this.message);

  final String message;

  @override
  String toString() => message;
}

DateTime? _dateFromMs(Object? value) {
  if (value is! int) return null;
  return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
}

int _nonNegativeInt(Object? value) {
  if (value is int && value > 0) return value;
  return 0;
}

int? _positiveIntOrNull(Object? value) {
  if (value is int && value > 0) return value;
  return null;
}

String? _stringOrNull(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  return null;
}
