import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/features/search_history/data/drift_search_history_repository.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('최근 검색은 지역별로 분리 저장·조회되고 타 지역 항목을 섞지 않는다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final repository = DriftSearchHistoryRepository(userDatabase: userDatabase);

    await repository.recordSearch('중앙', region: '수도권');
    await repository.recordSearch('중앙', region: '부산');
    await repository.recordSearch('해운대', region: '부산');
    // 지역 없는 기록은 저장되지 않는다.
    await repository.recordSearch('유령', region: null);

    final capital = await repository.listRecentEntries(region: '수도권');
    expect(
      capital.map(
        (entry) => switch (entry) {
          RecentStationSearchEntry(:final query) => query,
          RecentRouteSearchEntry() => entry.displayLabel,
        },
      ),
      ['중앙'],
    );

    final busan = await repository.listRecentEntries(region: '부산');
    expect(
      busan.map(
        (entry) => switch (entry) {
          RecentStationSearchEntry(:final query) => query,
          RecentRouteSearchEntry() => entry.displayLabel,
        },
      ),
      ['해운대', '중앙'],
    );

    await repository.removeSearch('중앙', region: '수도권');
    expect((await repository.listRecentEntries(region: '수도권')), isEmpty);
    expect(
      (await repository.listRecentEntries(region: '부산')).map(
        (entry) => switch (entry) {
          RecentStationSearchEntry(:final query) => query,
          RecentRouteSearchEntry() => entry.displayLabel,
        },
      ),
      ['해운대', '중앙'],
    );
  });
}
