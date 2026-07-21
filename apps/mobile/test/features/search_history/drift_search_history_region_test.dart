import 'package:drift/drift.dart' show Value;
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

  test('region 없는 레거시 행은 조회 결과에 안 나오고 조회가 더 이상 지우지 않는다(#2419)', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final repository = DriftSearchHistoryRepository(userDatabase: userDatabase);

    await repository.recordSearch('정상', region: '수도권');
    // v2 → v3 마이그레이션 이전에 쌓인 legacy 행을 재현한다(region 없이는
    // recordSearch로 저장할 수 없으므로 companion insert로 region을 비운다).
    await userDatabase
        .into(userDatabase.searchHistory)
        .insert(
          user_db.SearchHistoryCompanion.insert(
            query: '레거시',
            searchedAt: DateTime.now().toUtc(),
          ),
        );

    final entries = await repository.listRecentEntries(region: '수도권');

    expect(
      entries.map(
        (entry) => switch (entry) {
          RecentStationSearchEntry(:final query) => query,
          RecentRouteSearchEntry() => entry.displayLabel,
        },
      ),
      ['정상'],
    );
    // #2419: listRecentEntries는 더 이상 legacy 행을 지우지 않는다(정리는
    // v3 마이그레이션에서만 일어난다).
    final rawCount = await userDatabase
        .customSelect(
          "SELECT COUNT(*) AS count FROM search_history WHERE region IS NULL",
        )
        .getSingle();
    expect(rawCount.read<int>('count'), 1);
  });

  test(
    '동일 searched_at에서 kind 편향으로 route만 먼저 잘리지 않는다(Bugbot 리뷰 finding)',
    () async {
      final userDatabase = user_db.UserDatabase.memory();
      addTearDown(userDatabase.close);
      final repository = DriftSearchHistoryRepository(
        userDatabase: userDatabase,
        maxEntries: 3,
      );

      final tiedAt = DateTime.utc(2026, 7, 1, 12, 0, 0);
      // search_history id=1, id=2 (station 2건)를 동일 시각으로 직접 넣는다.
      await userDatabase
          .into(userDatabase.searchHistory)
          .insert(
            user_db.SearchHistoryCompanion.insert(
              query: '역A',
              region: const Value('수도권'),
              searchedAt: tiedAt,
            ),
          );
      await userDatabase
          .into(userDatabase.searchHistory)
          .insert(
            user_db.SearchHistoryCompanion.insert(
              query: '역B',
              region: const Value('수도권'),
              searchedAt: tiedAt,
            ),
          );
      // route_search_history id=1 (route 1건)을 같은 시각으로 넣는다.
      await userDatabase
          .into(userDatabase.routeSearchHistory)
          .insert(
            user_db.RouteSearchHistoryCompanion.insert(
              originStationId: 'station-origin',
              originStationName: '출발',
              destinationStationId: 'station-dest',
              destinationStationName: '도착',
              region: '수도권',
              searchedAt: tiedAt,
            ),
          );

      // 새 검색으로 통합 prune을 트리거한다. maxEntries=3인데 현재 4건이므로
      // 정렬 순서상 가장 뒤로 밀리는 1건만 삭제된다. kind가 정렬을 좌우하면
      // 동일 시각 그룹에서 route가 항상 밀려 삭제된다(버그).
      await repository.recordSearch('트리거', region: '수도권');

      final remainingRoutes = await userDatabase
          .select(userDatabase.routeSearchHistory)
          .get();
      expect(
        remainingRoutes,
        isNotEmpty,
        reason: 'kind 편향으로 동일 시각의 경로가 항상 먼저 삭제되면 안 된다',
      );
    },
  );

  test(
    'null/빈 region 레거시 행은 unified prune 슬롯을 차지하지 않는다(Bugbot 리뷰 finding)',
    () async {
      final userDatabase = user_db.UserDatabase.memory();
      addTearDown(userDatabase.close);
      final repository = DriftSearchHistoryRepository(
        userDatabase: userDatabase,
        maxEntries: 2,
      );

      // v3 마이그레이션 이전에 쌓인 것과 같은 legacy 행(region 없음)을 재현한다.
      await userDatabase
          .into(userDatabase.searchHistory)
          .insert(
            user_db.SearchHistoryCompanion.insert(
              query: '레거시',
              searchedAt: DateTime.now().toUtc(),
            ),
          );

      await repository.recordSearch('A', region: '수도권');
      await repository.recordSearch('B', region: '수도권');

      // legacy 행이 prune 슬롯(maxEntries=2)을 차지했다면 A/B 중 하나가
      // 잘렸을 것이다. legacy 행이 먼저 삭제되므로 A·B 둘 다 남아야 한다.
      final entries = await repository.listRecentEntries(
        region: '수도권',
        limit: 10,
      );
      expect(
        entries.map(
          (entry) => switch (entry) {
            RecentStationSearchEntry(:final query) => query,
            RecentRouteSearchEntry() => entry.displayLabel,
          },
        ),
        containsAll(<String>['A', 'B']),
      );
      final legacyCount = await userDatabase
          .customSelect(
            "SELECT COUNT(*) AS count FROM search_history WHERE region IS NULL",
          )
          .getSingle();
      expect(legacyCount.read<int>('count'), 0);
    },
  );
}
