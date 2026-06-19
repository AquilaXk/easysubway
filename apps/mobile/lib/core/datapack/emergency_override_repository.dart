import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../database/user/user_database.dart' as user_db;
import 'data_pack_installer.dart';

export 'data_pack_installer.dart' show InstalledDataPackPointer;

class EmergencyOverrideRepository {
  EmergencyOverrideRepository({required this.userDatabase});

  static const _overrideKey = 'datapack_emergency_override';

  final user_db.UserDatabase userDatabase;

  Future<void> saveOverride(EmergencyDataPackOverride override) async {
    await userDatabase
        .into(userDatabase.dataPackUpdateState)
        .insertOnConflictUpdate(
          user_db.DataPackUpdateStateCompanion.insert(
            key: _overrideKey,
            value: jsonEncode(override.toJson()),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<void> clearOverride() async {
    await userDatabase.customStatement(
      'DELETE FROM data_pack_update_state WHERE key = ?',
      [_overrideKey],
    );
  }

  Future<EmergencyDataPackOverride?> readOverride() async {
    final row = await userDatabase
        .customSelect(
          'SELECT value FROM data_pack_update_state WHERE key = ?',
          variables: [Variable<String>(_overrideKey)],
          readsFrom: {userDatabase.dataPackUpdateState},
        )
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    final decoded = jsonDecode(row.read<String>('value'));
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    return EmergencyDataPackOverride.fromJson(decoded);
  }
}

class EmergencyDataPackOverride {
  const EmergencyDataPackOverride({
    required this.id,
    required this.version,
    required this.reason,
  });

  factory EmergencyDataPackOverride.fromJson(Map<String, Object?> json) {
    return EmergencyDataPackOverride(
      id: _readFilenamePart(json, 'id'),
      version: _readFilenamePart(json, 'version'),
      reason: _readString(json, 'reason'),
    );
  }

  final String id;
  final String version;
  final String reason;

  Map<String, Object?> toJson() {
    return {'id': id, 'version': version, 'reason': reason};
  }
}

class DataPackSelectionPolicy {
  const DataPackSelectionPolicy({required this.emergencyOverrideRepository});

  final EmergencyOverrideRepository emergencyOverrideRepository;

  Future<InstalledDataPackPointer> select({
    required InstalledDataPackPointer installed,
  }) async {
    final override = await emergencyOverrideRepository.readOverride();
    if (override == null) {
      return installed;
    }
    return InstalledDataPackPointer(
      id: override.id,
      version: override.version,
      path: p.join(
        p.dirname(installed.path),
        '${override.id}-v${override.version}.sqlite',
      ),
      reason: override.reason,
    );
  }
}

String _readString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Invalid emergency data pack override.');
  }
  return value.trim();
}

String _readFilenamePart(Map<String, Object?> json, String key) {
  final value = _readString(json, key);
  final hasUnsafePathPart =
      value.contains('..') || value.contains('/') || value.contains('\\');
  if (hasUnsafePathPart || !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value)) {
    throw const FormatException('Invalid emergency data pack override.');
  }
  return value;
}
