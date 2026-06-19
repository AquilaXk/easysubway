import 'package:easysubway_mobile/app/app_dependencies.dart';
import 'package:easysubway_mobile/anonymous_auth.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/features/favorites/data/drift_favorite_repositories.dart';
import 'package:easysubway_mobile/features/preferences/data/drift_notification_settings_repository.dart';
import 'package:easysubway_mobile/features/search_history/data/drift_search_history_repository.dart';
import 'package:easysubway_mobile/route_search.dart';
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
    expect(favorites.single.addedAt, '2026-06-19T09:00:00.000Z');
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
    expect(favorites.single.lineName, '수도권 4호선');
    expect(favorites.single.score, 92);

    await repository.removeFavoriteRoute(result.routeSearchId);

    expect(await repository.listFavoriteRoutes(), isEmpty);
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

  test('앱 기본 의존성은 user DB가 있으면 개인 데이터 API와 익명 인증을 만들지 않는다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);

    final dependencies = AppDependencies.resolve(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      enableAnonymousAuth: false,
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
    expect(dependencies.anonymousAuthSession, isNull);
  });

  test('즐겨찾기 저장과 조회는 익명 인증 발급 없이 user DB만 사용한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    final anonymousAuthRepository = CountingAnonymousAuthRepository();
    final anonymousAuthStore = CountingAnonymousAuthCredentialStore();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();

    final dependencies = AppDependencies.resolve(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      anonymousAuthRepository: anonymousAuthRepository,
      anonymousAuthCredentialStore: anonymousAuthStore,
      enableAnonymousAuth: true,
      enablePushNotifications: false,
    );

    await dependencies.favoriteRepository!.saveFavoriteStation(
      'station-sangnoksu',
    );
    await dependencies.favoriteRepository!.listFavoriteStations();

    expect(anonymousAuthRepository.issueCount, 0);
    expect(anonymousAuthRepository.refreshCount, 0);
    expect(anonymousAuthStore.readCount, 0);
    expect(anonymousAuthStore.writeCount, 0);
  });
}

class CountingAnonymousAuthRepository implements AnonymousAuthRepository {
  int issueCount = 0;
  int refreshCount = 0;

  @override
  bool get canReuseStoredCredentials => true;

  @override
  Future<AnonymousAuthCredentials> issueAnonymousUser() async {
    issueCount++;
    return const AnonymousAuthCredentials(
      userId: 'guest-user',
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    );
  }

  @override
  Future<AnonymousAuthCredentials> refreshAnonymousUser(
    String refreshToken,
  ) async {
    refreshCount++;
    return const AnonymousAuthCredentials(
      userId: 'guest-user',
      accessToken: 'refreshed-access-token',
      refreshToken: 'refreshed-refresh-token',
    );
  }
}

class CountingAnonymousAuthCredentialStore
    implements AnonymousAuthCredentialStore {
  int readCount = 0;
  int writeCount = 0;
  int clearCount = 0;

  @override
  Future<AnonymousAuthCredentials?> readCredentials() async {
    readCount++;
    return null;
  }

  @override
  Future<void> saveCredentials(AnonymousAuthCredentials credentials) async {
    writeCount++;
  }

  @override
  Future<void> clearCredentials() async {
    clearCount++;
  }
}
