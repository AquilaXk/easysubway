import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/user/user_database.dart' as user_db;
import '../../../notification_settings.dart';

const _localUserId = 'local-user';
const _notificationSettingsKey = 'notification_settings';

class DriftNotificationSettingsRepository
    implements NotificationSettingsRepository {
  DriftNotificationSettingsRepository({required this.userDatabase});

  final user_db.UserDatabase userDatabase;

  @override
  Future<NotificationSettings> getNotificationSettings() async {
    final row = await userDatabase
        .customSelect(
          'SELECT value FROM app_preferences WHERE key = ?',
          variables: [Variable.withString(_notificationSettingsKey)],
          readsFrom: {userDatabase.appPreferences},
        )
        .getSingleOrNull();
    if (row == null) {
      return _defaultSettings();
    }

    final decoded = jsonDecode(row.read<String>('value'));
    if (decoded is! Map<String, Object?>) {
      return _defaultSettings();
    }
    return NotificationSettings.fromJson(decoded);
  }

  @override
  Future<NotificationSettings> saveNotificationSettings(
    NotificationSettings settings,
  ) async {
    final savedAt = DateTime.now().toUtc();
    final nextSettings = settings.copyWith(
      userId: _localUserId,
      updatedAt: savedAt.toIso8601String(),
    );
    await userDatabase
        .into(userDatabase.appPreferences)
        .insertOnConflictUpdate(
          user_db.AppPreferencesCompanion.insert(
            key: _notificationSettingsKey,
            value: jsonEncode({
              ...nextSettings.toRequestJson(),
              'updatedAt': nextSettings.updatedAt,
            }),
            updatedAt: savedAt,
          ),
        );
    return nextSettings;
  }

  NotificationSettings _defaultSettings() {
    return NotificationSettings(
      userId: _localUserId,
      favoriteStationFacilityAlerts: false,
      favoriteRouteFacilityAlerts: false,
      reportStatusAlerts: false,
      dataQualityAlerts: false,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        0,
        isUtc: true,
      ).toIso8601String(),
    );
  }
}
