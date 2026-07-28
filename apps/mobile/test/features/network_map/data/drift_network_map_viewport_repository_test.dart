import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/features/network_map/data/drift_network_map_viewport_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('마지막 성공 지역을 trim해 저장하고 overwrite한다', () async {
    final database = user_db.UserDatabase.memory();
    addTearDown(database.close);
    final repository = DriftNetworkMapViewportRepository(
      userDatabase: database,
    );

    expect(await repository.loadSelectedRegion(), isNull);
    await repository.saveSelectedRegion(' 광주 ');
    expect(await repository.loadSelectedRegion(), '광주');
    await repository.saveSelectedRegion('부산');
    expect(await repository.loadSelectedRegion(), '부산');
    expect(() => repository.saveSelectedRegion('  '), throwsArgumentError);
  });

  test('저장된 빈 지역은 선택값으로 복원하지 않는다', () async {
    final database = user_db.UserDatabase.memory();
    addTearDown(database.close);
    final repository = DriftNetworkMapViewportRepository(
      userDatabase: database,
    );
    await database
        .into(database.appPreferences)
        .insert(
          user_db.AppPreferencesCompanion.insert(
            key: 'network_map_selected_region',
            value: '  ',
            updatedAt: DateTime.utc(2026, 7, 28),
          ),
        );

    expect(await repository.loadSelectedRegion(), isNull);
  });
}
