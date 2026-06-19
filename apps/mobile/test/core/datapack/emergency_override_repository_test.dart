import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/core/datapack/emergency_override_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('emergency override는 설치된 데이터팩 선택보다 우선한다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final repository = EmergencyOverrideRepository(userDatabase: userDatabase);
    await repository.saveOverride(
      const EmergencyDataPackOverride(
        id: 'capital',
        version: '17',
        reason: '시설 상태 긴급 정정',
      ),
    );

    final selected =
        await DataPackSelectionPolicy(
          emergencyOverrideRepository: repository,
        ).select(
          installed: const InstalledDataPackPointer(
            id: 'capital',
            version: '18',
            path: '/catalog/capital-v18.sqlite',
          ),
        );

    expect(selected.id, 'capital');
    expect(selected.version, '17');
    expect(selected.path, '/catalog/capital-v17.sqlite');
    expect(selected.reason, '시설 상태 긴급 정정');
  });
}
