import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:easysubway_mobile/app/app_dependencies.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/features/favorites/data/drift_favorite_repositories.dart';
import 'package:easysubway_mobile/features/preferences/data/drift_notification_settings_repository.dart';
import 'package:easysubway_mobile/features/search_history/data/drift_search_history_repository.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:easysubway_mobile/user_data_deletion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('로컬 역 즐겨찾기는 user DB에 저장하고 catalog DB 정보로 목록을 만든다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteStationRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );

    final saved = await repository.saveFavoriteStation('station-sangnoksu');
    final favorites = await repository.listFavoriteStations();

    expect(saved.stationId, 'station-sangnoksu');
    expect(favorites.single.nameKo, '상록수');
    expect(favorites.single.lines.single.name, '수도권 4호선');

    await repository.removeFavoriteStation('station-sangnoksu');

    expect(await repository.listFavoriteStations(), isEmpty);
  });

  test('로컬 시설 즐겨찾기는 데이터팩 catalog 정보와 user DB 보관 시간을 조합한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    await userDatabase
        .into(userDatabase.favoriteFacilities)
        .insert(
          user_db.FavoriteFacilitiesCompanion.insert(
            facilityId: 'facility-sangnoksu-elevator-1',
            stationId: 'station-sangnoksu',
            addedAt: DateTime.utc(2026, 6, 19, 9),
          ),
        );
    final repository = DriftFavoriteFacilityRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );

    final favorites = await repository.listFavoriteFacilities();

    expect(favorites.single.facilityId, 'facility-sangnoksu-elevator-1');
    expect(favorites.single.stationNameKo, '상록수');
    expect(favorites.single.name, '1번 출구 엘리베이터');
    expect(favorites.single.verificationStatusLabel, '시설 상태가 확인됐어요');
    expect(favorites.single.lastUpdatedAt, '2026-06-19');
    expect(favorites.single.addedAt, '2026-06-19T09:00:00.000Z');
  });

  test('로컬 시설 즐겨찾기는 시설 field 검증 시각을 최근 확인일로 쓴다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    await userDatabase
        .into(userDatabase.favoriteFacilities)
        .insert(
          user_db.FavoriteFacilitiesCompanion.insert(
            facilityId: 'facility-sangnoksu-accessible-toilet-1',
            stationId: 'station-sangnoksu',
            addedAt: DateTime.utc(2026, 6, 19, 9),
          ),
        );
    final repository = DriftFavoriteFacilityRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );

    final favorites = await repository.listFavoriteFacilities();

    expect(
      favorites.single.facilityId,
      'facility-sangnoksu-accessible-toilet-1',
    );
    expect(favorites.single.verificationStatusLabel, '최신 상태를 준비 중이에요');
    expect(favorites.single.lastUpdatedAt, '2025-06-01');
  });

  test('로컬 시설 즐겨찾기는 시설 id로 저장하고 삭제한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteFacilityRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );

    final saved = await repository.saveFavoriteFacility(
      'facility-sangnoksu-elevator-1',
    );
    final favorites = await repository.listFavoriteFacilities();

    expect(saved.facilityId, 'facility-sangnoksu-elevator-1');
    expect(favorites.single.name, '1번 출구 엘리베이터');

    await repository.removeFavoriteFacility('facility-sangnoksu-elevator-1');

    expect(await repository.listFavoriteFacilities(), isEmpty);
  });

  test('로컬 경로 즐겨찾기는 검색 결과 요약을 user DB에 저장하고 삭제한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteRouteRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
    final result = RouteSearchResult(
      routeSearchId: 'local-station-sangnoksu-station-sadang',
      originStationId: 'station-sangnoksu',
      originStationName: '상록수',
      destinationStationId: 'station-sadang',
      destinationStationName: '사당',
      mobilityType: 'SENIOR',
      status: 'FOUND',
      lineId: 'seoul-4',
      lineName: '수도권 4호선',
      score: 92,
      burdenCost: 44,
      estimatedDurationSeconds: 600,
      walkingDistanceMeters: 120,
      transferCount: 1,
      evidenceSummary: const ['DURATION_ESTIMATED', 'DISTANCE_MEASURED'],
      steps: const [],
      warnings: const [],
      blockedReasons: const [],
      createdAt: '2026-06-19T09:00:00.000Z',
    );

    final saved = await repository.saveFavoriteRoute(
      result.routeSearchId,
      result: result,
    );
    final favorites = await repository.listFavoriteRoutes();

    expect(saved.summaryTitle, '상록수에서 사당까지');
    expect(saved.routeSearchId, result.routeSearchId);
    expect(favorites.single.lineName, '수도권 4호선');
    expect(favorites.single.score, 92);
    final snapshotRows = await userDatabase
        .customSelect(
          'SELECT value FROM app_preferences WHERE key = ?',
          variables: [
            Variable.withString(
              'favorite_route_snapshot:${result.routeSearchId}::SENIOR',
            ),
          ],
          readsFrom: {userDatabase.appPreferences},
        )
        .get();
    final snapshot =
        jsonDecode(snapshotRows.single.read<String>('value'))
            as Map<String, Object?>;
    expect(snapshot['burdenCost'], 44);
    expect(snapshot['accessibilityScore'], 92);
    expect(snapshot['estimatedDurationSeconds'], 600);
    expect(snapshot['walkingDistanceMeters'], 120);
    expect(snapshot['transferCount'], 1);
    expect(snapshot['evidenceSummary'], [
      'DURATION_ESTIMATED',
      'DISTANCE_MEASURED',
    ]);

    await repository.removeFavoriteRoute(saved.favoriteRouteId);

    expect(await repository.listFavoriteRoutes(), isEmpty);
  });

  test('로컬 경로 즐겨찾기는 같은 구간도 이동 조건별로 분리해 저장한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteRouteRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
    final seniorResult = RouteSearchResult(
      routeSearchId: 'local-station-sangnoksu-station-sadang',
      originStationId: 'station-sangnoksu',
      originStationName: '상록수',
      destinationStationId: 'station-sadang',
      destinationStationName: '사당',
      mobilityType: 'SENIOR',
      status: 'FOUND',
      lineId: 'seoul-4',
      lineName: '수도권 4호선',
      score: 92,
      steps: const [],
      warnings: const [],
      blockedReasons: const [],
      createdAt: '2026-06-19T09:00:00.000Z',
    );
    final wheelchairResult = RouteSearchResult(
      routeSearchId: 'local-station-sangnoksu-station-sadang',
      originStationId: 'station-sangnoksu',
      originStationName: '상록수',
      destinationStationId: 'station-sadang',
      destinationStationName: '사당',
      mobilityType: 'WHEELCHAIR',
      status: 'FOUND',
      lineId: 'seoul-4',
      lineName: '수도권 4호선',
      score: 88,
      steps: const [],
      warnings: const [],
      blockedReasons: const [],
      createdAt: '2026-06-19T09:01:00.000Z',
    );

    await repository.saveFavoriteRoute(
      seniorResult.routeSearchId,
      result: seniorResult,
    );
    await repository.saveFavoriteRoute(
      wheelchairResult.routeSearchId,
      result: wheelchairResult,
    );
    final favorites = await repository.listFavoriteRoutes();

    expect(favorites, hasLength(2));
    expect(favorites.map((favorite) => favorite.mobilityType).toSet(), {
      'SENIOR',
      'WHEELCHAIR',
    });
    expect(
      favorites.map((favorite) => favorite.favoriteRouteId).toSet(),
      hasLength(2),
    );
  });

  test('경로 즐겨찾기 snapshot이 없으면 요약 경로를 대체 생성하지 않는다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteRouteRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
    await userDatabase
        .into(userDatabase.favoriteRoutes)
        .insert(
          user_db.FavoriteRoutesCompanion.insert(
            routeId: 'legacy-route-without-snapshot',
            originStationId: 'station-sangnoksu',
            destinationStationId: 'station-sadang',
            mobilityProfile: 'WHEELCHAIR',
            addedAt: DateTime.utc(2026, 7),
          ),
        );

    await expectLater(
      repository.listFavoriteRoutes(),
      throwsA(isA<FavoriteRouteException>()),
    );
  });

  test('경로 즐겨찾기 snapshot이 손상되면 빈 요약 경로를 만들지 않는다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteRouteRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
    await userDatabase.transaction(() async {
      await userDatabase
          .into(userDatabase.favoriteRoutes)
          .insert(
            user_db.FavoriteRoutesCompanion.insert(
              routeId: 'route-with-corrupt-snapshot',
              originStationId: 'station-sangnoksu',
              destinationStationId: 'station-sadang',
              mobilityProfile: 'WHEELCHAIR',
              addedAt: DateTime.utc(2026, 7),
            ),
          );
      await userDatabase
          .into(userDatabase.appPreferences)
          .insert(
            user_db.AppPreferencesCompanion.insert(
              key: 'favorite_route_snapshot:route-with-corrupt-snapshot',
              value: '{}',
              updatedAt: DateTime.utc(2026, 7),
            ),
          );
    });

    await expectLater(
      repository.listFavoriteRoutes(),
      throwsA(isA<FavoriteRouteException>()),
    );
  });

  test('V2 경로 즐겨찾기는 ETA 출처와 step metadata를 snapshot에 보존한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteRouteRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
    final result = RouteSearchResult(
      routeSearchId: 'route-v2',
      originStationId: 'station-sangnoksu',
      originStationName: '상록수',
      destinationStationId: 'station-sadang',
      destinationStationName: '사당',
      mobilityType: 'WHEELCHAIR',
      status: 'FOUND',
      lineId: 'seoul-4',
      lineName: '수도권 4호선',
      score: 88,
      steps: const [
        RouteSearchStep(
          sequence: 1,
          stepType: 'ride',
          title: '상록수에서 사당까지 이동',
          description: '4호선 이동',
          lineId: 'seoul-4',
          lineName: '수도권 4호선',
          fromStationId: 'station-sangnoksu',
          toStationId: 'station-sadang',
          estimatedMinutes: 26,
          distanceMeters: 0,
          includesStairs: false,
          requiresAccessibilityCheck: false,
          timeSource: 'STATIC_BACKEND_V1',
          distanceSource: 'BACKEND_V2',
          confidenceLabel: 'LOW',
        ),
      ],
      warnings: const [],
      blockedReasons: const [],
      createdAt: '2026-07-01T09:00:00+09:00',
      etaSource: 'STATIC_BACKEND_V1',
    );

    final saved = await repository.saveFavoriteRoute(
      result.routeSearchId,
      result: result,
    );
    final favorites = await repository.listFavoriteRoutes();
    final snapshotRows = await userDatabase
        .customSelect(
          'SELECT value FROM app_preferences WHERE key = ?',
          variables: [
            Variable.withString(
              'favorite_route_snapshot:${saved.favoriteRouteId}',
            ),
          ],
          readsFrom: {userDatabase.appPreferences},
        )
        .get();
    final snapshot =
        jsonDecode(snapshotRows.single.read<String>('value'))
            as Map<String, Object?>;
    final steps = snapshot['steps'] as List<Object?>;
    final firstStep = steps.single as Map<String, Object?>;

    expect(favorites.single.routeSearchId, 'route-v2');
    expect(favorites.single.scoreBasisText, contains('시간표 기준'));
    expect(favorites.single.semanticLabel, contains('시간표 기준'));
    expect(snapshot['etaSource'], 'STATIC_BACKEND_V1');
    expect(firstStep['timeSource'], 'STATIC_BACKEND_V1');
    expect(firstStep['distanceSource'], 'BACKEND_V2');
    expect(firstStep['confidenceLabel'], 'LOW');
  });

  test('로컬 알림 설정과 최근 검색은 app_preferences와 search_history에 보관한다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final notificationRepository = DriftNotificationSettingsRepository(
      userDatabase: userDatabase,
    );
    final searchHistoryRepository = DriftSearchHistoryRepository(
      userDatabase: userDatabase,
      maxEntries: 2,
    );

    final defaultSettings = await notificationRepository
        .getNotificationSettings();
    final savedSettings = await notificationRepository.saveNotificationSettings(
      defaultSettings.copyWith(
        favoriteStationFacilityAlerts: true,
        favoriteRouteFacilityAlerts: true,
      ),
    );
    await searchHistoryRepository.recordSearch(' 상록수 ');
    await searchHistoryRepository.recordSearch('사당');
    await searchHistoryRepository.recordSearch('상록수');

    expect(defaultSettings.userId, 'local-user');
    expect(savedSettings.favoriteStationFacilityAlerts, isTrue);
    expect(
      (await notificationRepository.getNotificationSettings())
          .favoriteRouteFacilityAlerts,
      isTrue,
    );
    expect(await searchHistoryRepository.listRecentQueries(), ['상록수', '사당']);
  });

  test('앱 기본 의존성은 user DB가 있으면 개인 데이터 API를 만들지 않는다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);

    final dependencies = AppDependencies.resolve(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      enablePushNotifications: false,
    );

    expect(
      dependencies.favoriteRepository,
      isA<DriftFavoriteStationRepository>(),
    );
    expect(
      dependencies.favoriteFacilityRepository,
      isA<DriftFavoriteFacilityRepository>(),
    );
    expect(
      dependencies.favoriteRouteRepository,
      isA<DriftFavoriteRouteRepository>(),
    );
    expect(
      dependencies.userDataDeletionRepository,
      isA<UserDataDeletionLocalRepository>(),
    );
  });

  test('즐겨찾기 저장과 조회는 user DB만 사용한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();

    final dependencies = AppDependencies.resolve(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      enablePushNotifications: false,
    );

    await dependencies.favoriteRepository!.saveFavoriteStation(
      'station-sangnoksu',
    );
    await dependencies.favoriteRepository!.listFavoriteStations();

    expect(
      dependencies.userDataDeletionRepository,
      isA<UserDataDeletionLocalRepository>(),
    );
  });
}
