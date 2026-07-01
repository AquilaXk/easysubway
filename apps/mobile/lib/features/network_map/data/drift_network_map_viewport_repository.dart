import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';

import '../../../core/database/user/user_database.dart' as user_db;
import '../../../network_map.dart';

const _networkMapViewportKeyPrefix = 'network_map_viewport';

class DriftNetworkMapViewportRepository
    implements NetworkMapViewportRepository {
  DriftNetworkMapViewportRepository({required this.userDatabase});

  final user_db.UserDatabase userDatabase;

  @override
  Future<Rect?> loadViewport(String region) async {
    final row = await userDatabase
        .customSelect(
          'SELECT value FROM app_preferences WHERE key = ?',
          variables: [Variable.withString(_storageKey(region))],
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
    final left = _doubleFrom(decoded['left']);
    final top = _doubleFrom(decoded['top']);
    final right = _doubleFrom(decoded['right']);
    final bottom = _doubleFrom(decoded['bottom']);
    if (left == null || top == null || right == null || bottom == null) {
      return null;
    }
    if (right <= left || bottom <= top) {
      return null;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  Future<void> saveViewport({
    required String region,
    required Rect viewport,
  }) async {
    final now = DateTime.now().toUtc();
    await userDatabase
        .into(userDatabase.appPreferences)
        .insertOnConflictUpdate(
          user_db.AppPreferencesCompanion.insert(
            key: _storageKey(region),
            value: jsonEncode({
              'left': viewport.left,
              'top': viewport.top,
              'right': viewport.right,
              'bottom': viewport.bottom,
            }),
            updatedAt: now,
          ),
        );
  }

  String _storageKey(String region) => '$_networkMapViewportKeyPrefix:$region';
}

double? _doubleFrom(Object? value) {
  if (value is num) {
    final result = value.toDouble();
    return result.isFinite ? result : null;
  }
  return null;
}
