import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/features/preferences/data/drift_notification_settings_repository.dart';
import 'package:easysubway_mobile/features/search_history/data/drift_search_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('로컬 알림 설정은 user DB app_preferences에 저장된다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final repository = DriftNotificationSettingsRepository(
      userDatabase: userDatabase,
    );

    final defaultSettings = await repository.getNotificationSettings();
    final savedSettings = await repository.saveNotificationSettings(
      defaultSettings.copyWith(
        favoriteStationFacilityAlerts: true,
        favoriteRouteFacilityAlerts: true,
      ),
    );

    expect(defaultSettings.userId, 'local-user');
    expect(savedSettings.favoriteStationFacilityAlerts, isTrue);
    expect(
      (await repository.getNotificationSettings()).favoriteRouteFacilityAlerts,
      isTrue,
    );
  });

  test('최근 검색은 중복 검색어를 최신순으로 보관하고 최대 개수를 지킨다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final repository = DriftSearchHistoryRepository(
      userDatabase: userDatabase,
      maxEntries: 2,
    );

    await repository.recordSearch(' 상록수 ');
    await repository.recordSearch('사당');
    await repository.recordSearch('상록수');

    expect(await repository.listRecentQueries(), ['상록수', '사당']);
  });
}
