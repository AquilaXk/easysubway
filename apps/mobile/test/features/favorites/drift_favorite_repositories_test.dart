import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:easysubway_mobile/app/app_dependencies.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/features/favorites/data/drift_favorite_repositories.dart';
import 'package:easysubway_mobile/features/preferences/data/drift_notification_settings_repository.dart';
import 'package:easysubway_mobile/features/search_history/data/drift_search_history_repository.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:easysubway_mobile/features/routes/domain/route_identity.dart';
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

  test('호선 단위 즐겨찾기는 lineId로 저장하고 해당 호선만 해제한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteStationRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );

    final saved = await repository.saveFavoriteStation(
      'station-sangnoksu',
      lineId: 'seoul-4',
    );
    expect(saved.stationId, 'station-sangnoksu');
    expect(saved.lineId, 'seoul-4');

    final favorites = await repository.listFavoriteStations();
    expect(favorites.single.lineId, 'seoul-4');

    await repository.removeFavoriteStation(
      'station-sangnoksu',
      lineId: 'seoul-4',
    );
    expect(await repository.listFavoriteStations(), isEmpty);
  });

  test('레거시 line_id와 호선 단위 행이 공존하면 레거시는 목록에서 제외한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteStationRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );

    await repository.saveFavoriteStation('station-sangnoksu');
    await repository.saveFavoriteStation(
      'station-sangnoksu',
      lineId: 'seoul-4',
    );

    final favorites = await repository.listFavoriteStations();
    expect(favorites, hasLength(1));
    expect(favorites.single.lineId, 'seoul-4');
  });

  test('레거시 역 전체 즐겨찾기에서 한 호선만 해제하면 나머지로 펼친다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteStationRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );

    await repository.saveFavoriteStation('station-sadang');
    await repository.removeFavoriteStation('station-sadang', lineId: 'seoul-2');

    final favorites = await repository.listFavoriteStations();
    expect(favorites.map((favorite) => favorite.lineId), ['seoul-4']);
  });

  test('흡수 station ID 즐겨찾기는 대표 ID로 이관한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    await catalogDatabase.customStatement('''
      INSERT INTO station_aliases (station_id, alias, normalized_alias)
      VALUES ('station-sangnoksu', 'station-sangnoksu-old', 'station-sangnoksu-old')
    ''');
    await userDatabase.customStatement(
      'INSERT INTO favorite_stations (station_id, added_at) VALUES (?, ?), (?, ?)',
      [
        'station-sangnoksu-old',
        DateTime.utc(2026, 7, 13).millisecondsSinceEpoch ~/ 1000,
        'station-sangnoksu',
        DateTime.utc(2026, 7, 14).millisecondsSinceEpoch ~/ 1000,
      ],
    );
    final repository = DriftFavoriteStationRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );

    final favorites = await repository.listFavoriteStations();
    final stored = await userDatabase
        .customSelect('SELECT station_id FROM favorite_stations')
        .getSingle();

    expect(favorites.single.stationId, 'station-sangnoksu');
    expect(stored.read<String>('station_id'), 'station-sangnoksu');
  });

  test('흡수 station ID로 저장해도 대표 ID 즐겨찾기만 남긴다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    await catalogDatabase.customStatement('''
      INSERT INTO station_aliases (station_id, alias, normalized_alias)
      VALUES ('station-sangnoksu', 'station-sangnoksu-old', 'station-sangnoksu-old')
    ''');
    final repository = DriftFavoriteStationRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );

    final saved = await repository.saveFavoriteStation('station-sangnoksu-old');

    expect(saved.stationId, 'station-sangnoksu');
    final stored = await userDatabase
        .customSelect('SELECT station_id FROM favorite_stations')
        .getSingle();
    expect(stored.read<String>('station_id'), 'station-sangnoksu');
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
    expect(favorites.single.verificationStatusLabel, '');
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
    expect(favorites.single.verificationStatusLabel, '');
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
      providerRouteSearchId: 'provider-search-opaque',
      providerItineraryId: 'provider-itinerary-full-opaque',
      queryIdentity: RouteQueryIdentity(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'SENIOR',
        constraintMode: 'PREFER_STEP_FREE',
        transportScope: 'SUBWAY',
        objective: 'FASTEST',
      ),
      candidateIdentity: RouteCandidateIdentity(
        query: RouteQueryIdentity(
          originStationId: 'station-sangnoksu',
          destinationStationId: 'station-sadang',
          mobilityType: 'SENIOR',
          constraintMode: 'PREFER_STEP_FREE',
          transportScope: 'SUBWAY',
          objective: 'FASTEST',
        ),
        legs: [
          RouteCandidateLegSignature(
            stepType: 'RIDE',
            fromStationId: 'station-sangnoksu',
            toStationId: 'station-sadang',
            lineId: 'seoul-4',
          ),
        ],
      ),
    );

    final saved = await repository.saveFavoriteRoute(
      result.routeSearchId,
      result: result,
    );
    final favorites = await repository.listFavoriteRoutes();

    expect(saved.summaryTitle, '상록수에서 사당까지');
    expect(saved.routeSearchId, result.routeSearchId);
    expect(saved.favoriteRouteId, startsWith('rc:v1:'));
    expect(favorites.single.lineName, '수도권 4호선');
    expect(favorites.single.score, 92);
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
    expect(snapshot['burdenCost'], 44);
    expect(snapshot['accessibilityScore'], 92);
    expect(snapshot['estimatedDurationSeconds'], 600);
    expect(snapshot['walkingDistanceMeters'], 120);
    expect(snapshot['transferCount'], 1);
    expect(snapshot['evidenceSummary'], [
      'DURATION_ESTIMATED',
      'DISTANCE_MEASURED',
    ]);
    expect(snapshot['queryIdentity'], result.queryIdentity!.value);
    expect(snapshot['candidateIdentity'], result.candidateIdentity!.value);
    expect(snapshot['querySnapshot'], result.queryIdentity!.toSnapshot());
    expect(snapshot['providerRouteSearchId'], 'provider-search-opaque');
    expect(snapshot['providerItineraryId'], 'provider-itinerary-full-opaque');

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

  test('복원 가능한 레거시 경로 즐겨찾기는 identity로 한 번 이관되고 재시작 후에도 안정적이다', () async {
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
              routeId: 'local-legacy-route',
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
              key: 'favorite_route_snapshot:local-legacy-route',
              value: jsonEncode({
                'routeSearchId': 'local-legacy-route',
                'originStationId': 'station-sangnoksu',
                'originStationName': '상록수',
                'destinationStationId': 'station-sadang',
                'destinationStationName': '사당',
                'mobilityType': 'WHEELCHAIR',
                'status': 'FOUND',
                'score': 71,
                'createdAt': '2026-07-01T00:00:00.000Z',
                'objective': 'FASTEST',
                'steps': [
                  {
                    'stepType': 'RIDE',
                    'fromStationId': 'station-sangnoksu',
                    'toStationId': 'station-sadang',
                    'lineId': 'seoul-4',
                    'serviceClass': 'SUBWAY',
                    'servicePattern': 'LOCAL',
                  },
                ],
              }),
              updatedAt: DateTime.utc(2026, 7),
            ),
          );
    });

    final first = await repository.listFavoriteRoutes();
    final restarted = DriftFavoriteRouteRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
    final second = await restarted.listFavoriteRoutes();

    expect(first.single.favoriteRouteId, startsWith('rc:v1:'));
    expect(second.single.favoriteRouteId, first.single.favoriteRouteId);
    final migratedSnapshot =
        jsonDecode(
              (await userDatabase
                      .customSelect(
                        'SELECT value FROM app_preferences WHERE key = ?',
                        variables: [
                          Variable.withString(
                            'favorite_route_snapshot:${first.single.favoriteRouteId}',
                          ),
                        ],
                      )
                      .getSingle())
                  .read<String>('value'),
            )
            as Map<String, Object?>;
    expect(
      (migratedSnapshot['querySnapshot']
          as Map<String, Object?>)['mobilityPreset'],
      'STEP_FREE',
    );
    expect(
      await userDatabase
          .customSelect('SELECT route_id FROM favorite_routes')
          .get(),
      hasLength(1),
    );
    expect(
      await userDatabase
          .customSelect(
            'SELECT value FROM app_preferences WHERE key = ?',
            variables: [
              Variable.withString(
                'favorite_route_snapshot:${first.single.favoriteRouteId}',
              ),
            ],
          )
          .get(),
      hasLength(1),
    );
  });

  test('목록 조회 뒤 삭제된 레거시 경로는 candidate identity로 되살리지 않는다', () async {
    const legacyRouteId = 'local-concurrently-deleted';
    final interceptor = _DeleteLegacyBeforeMigrationTransaction(legacyRouteId);
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase(
      NativeDatabase.memory().interceptWith(interceptor),
    );
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
              routeId: legacyRouteId,
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
              key: 'favorite_route_snapshot:$legacyRouteId',
              value: jsonEncode({
                'routeSearchId': legacyRouteId,
                'originStationId': 'station-sangnoksu',
                'originStationName': '상록수',
                'destinationStationId': 'station-sadang',
                'destinationStationName': '사당',
                'mobilityType': 'WHEELCHAIR',
                'status': 'FOUND',
                'score': 71,
                'createdAt': '2026-07-01T00:00:00.000Z',
                'objective': 'FASTEST',
                'steps': [
                  {
                    'stepType': 'RIDE',
                    'fromStationId': 'station-sangnoksu',
                    'toStationId': 'station-sadang',
                    'lineId': 'seoul-4',
                    'serviceClass': 'SUBWAY',
                    'servicePattern': 'LOCAL',
                  },
                ],
              }),
              updatedAt: DateTime.utc(2026, 7),
            ),
          );
    });
    interceptor.arm();

    final favorites = await repository.listFavoriteRoutes();

    expect(favorites, isEmpty);
    expect(
      await userDatabase
          .customSelect('SELECT route_id FROM favorite_routes')
          .get(),
      isEmpty,
    );
    expect(
      await userDatabase
          .customSelect(
            "SELECT key FROM app_preferences WHERE key LIKE 'favorite_route_snapshot:%'",
          )
          .get(),
      isEmpty,
    );
  });

  test('orphan target snapshot이 있으면 legacy 행을 보존하고 다시 검색 필요로 표시한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteRouteRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
    final query = RouteQueryIdentity(
      originStationId: 'station-sangnoksu',
      destinationStationId: 'station-sadang',
      mobilityType: 'WHEELCHAIR',
      mobilityPreset: 'STEP_FREE',
      constraintMode: 'STRICT_STEP_FREE',
      transportScope: 'SUBWAY',
      objective: 'FASTEST',
    );
    final candidate = RouteCandidateIdentity(
      query: query,
      legs: [
        RouteCandidateLegSignature(
          stepType: 'RIDE',
          fromStationId: 'station-sangnoksu',
          toStationId: 'station-sadang',
          lineId: 'seoul-4',
          serviceClass: 'SUBWAY',
          servicePattern: 'LOCAL',
        ),
      ],
    );
    final legacySnapshot = jsonEncode({
      'routeSearchId': 'local-orphan-target',
      'originStationId': 'station-sangnoksu',
      'originStationName': '상록수',
      'destinationStationId': 'station-sadang',
      'destinationStationName': '사당',
      'mobilityType': 'WHEELCHAIR',
      'status': 'FOUND',
      'score': 71,
      'createdAt': '2026-07-01T00:00:00.000Z',
      'objective': 'FASTEST',
      'steps': [
        {
          'stepType': 'RIDE',
          'fromStationId': 'station-sangnoksu',
          'toStationId': 'station-sadang',
          'lineId': 'seoul-4',
          'serviceClass': 'SUBWAY',
          'servicePattern': 'LOCAL',
        },
      ],
    });
    await userDatabase.transaction(() async {
      await userDatabase
          .into(userDatabase.favoriteRoutes)
          .insert(
            user_db.FavoriteRoutesCompanion.insert(
              routeId: 'local-orphan-target',
              originStationId: 'station-sangnoksu',
              destinationStationId: 'station-sadang',
              mobilityProfile: 'WHEELCHAIR',
              addedAt: DateTime.utc(2026, 7),
            ),
          );
      for (final entry in {
        'favorite_route_snapshot:local-orphan-target': legacySnapshot,
        'favorite_route_snapshot:${candidate.value}': 'orphan',
      }.entries) {
        await userDatabase
            .into(userDatabase.appPreferences)
            .insert(
              user_db.AppPreferencesCompanion.insert(
                key: entry.key,
                value: entry.value,
                updatedAt: DateTime.utc(2026, 7),
              ),
            );
      }
    });

    final favorite = (await repository.listFavoriteRoutes()).single;

    expect(favorite.favoriteRouteId, 'local-orphan-target');
    expect(favorite.needsResearch, isTrue);
    expect(
      await userDatabase
          .customSelect('SELECT route_id FROM favorite_routes')
          .get(),
      hasLength(1),
    );
    expect(
      await userDatabase.customSelect('SELECT key FROM app_preferences').get(),
      hasLength(2),
    );
  });

  test('같은 출발지와 도착지의 레거시 경로도 identity 입력이 다르면 분리 이관한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteRouteRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
    for (final fixture in [
      ('local-legacy-fastest', 'FASTEST', 'RIDE'),
      ('local-legacy-transfer', 'FEWEST_TRANSFERS', 'WALK'),
    ]) {
      await userDatabase.transaction(() async {
        await userDatabase
            .into(userDatabase.favoriteRoutes)
            .insert(
              user_db.FavoriteRoutesCompanion.insert(
                routeId: fixture.$1,
                originStationId: 'station-sangnoksu',
                destinationStationId: 'station-sadang',
                mobilityProfile: 'SENIOR',
                addedAt: DateTime.utc(2026, 7),
              ),
            );
        await userDatabase
            .into(userDatabase.appPreferences)
            .insert(
              user_db.AppPreferencesCompanion.insert(
                key: 'favorite_route_snapshot:${fixture.$1}',
                value: jsonEncode({
                  'originStationId': 'station-sangnoksu',
                  'originStationName': '상록수',
                  'destinationStationId': 'station-sadang',
                  'destinationStationName': '사당',
                  'mobilityType': 'SENIOR',
                  'status': 'FOUND',
                  'score': 70,
                  'createdAt': '2026-07-01T00:00:00.000Z',
                  'objective': fixture.$2,
                  'steps': [
                    {
                      'stepType': fixture.$3,
                      'fromStationId': 'station-sangnoksu',
                      'toStationId': 'station-sadang',
                      if (fixture.$3 == 'RIDE') ...{
                        'serviceClass': 'SUBWAY',
                        'servicePattern': 'LOCAL',
                      },
                    },
                  ],
                }),
                updatedAt: DateTime.utc(2026, 7),
              ),
            );
      });
    }

    final favorites = await repository.listFavoriteRoutes();

    expect(favorites, hasLength(2));
    expect(
      favorites.every(
        (favorite) => favorite.favoriteRouteId.startsWith('rc:v1:'),
      ),
      isTrue,
    );
    expect(
      favorites.map((favorite) => favorite.favoriteRouteId).toSet(),
      hasLength(2),
    );
  });

  test('기존 candidate 대상은 보존하고 최종 추가 시각 순으로 정렬한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteRouteRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
    final query = RouteQueryIdentity(
      originStationId: 'station-sangnoksu',
      destinationStationId: 'station-sadang',
      mobilityType: 'SENIOR',
      mobilityPreset: 'SLOW',
      constraintMode: 'PREFER_STEP_FREE',
      transportScope: 'SUBWAY',
      objective: 'FASTEST',
    );
    final candidate = RouteCandidateIdentity(
      query: query,
      legs: [
        RouteCandidateLegSignature(
          stepType: 'RIDE',
          fromStationId: 'station-sangnoksu',
          toStationId: 'station-sadang',
          lineId: 'seoul-4',
          serviceClass: 'SUBWAY',
          servicePattern: 'LOCAL',
        ),
      ],
    );
    const targetSnapshot =
        '{"routeSearchId":"target-route","originStationId":"station-sangnoksu","originStationName":"대상 출발","destinationStationId":"station-sadang","destinationStationName":"대상 도착","mobilityType":"SENIOR","status":"FOUND","score":99,"createdAt":"2026-07-02T00:00:00.000Z","steps":[]}';
    await userDatabase.transaction(() async {
      await userDatabase
          .into(userDatabase.favoriteRoutes)
          .insert(
            user_db.FavoriteRoutesCompanion.insert(
              routeId: candidate.value,
              originStationId: 'target-origin',
              destinationStationId: 'target-destination',
              mobilityProfile: 'WHEELCHAIR',
              addedAt: DateTime.utc(2026, 7, 1),
            ),
          );
      await userDatabase
          .into(userDatabase.appPreferences)
          .insert(
            user_db.AppPreferencesCompanion.insert(
              key: 'favorite_route_snapshot:${candidate.value}',
              value: targetSnapshot,
              updatedAt: DateTime.utc(2026, 7, 1),
            ),
          );
      await userDatabase
          .into(userDatabase.favoriteRoutes)
          .insert(
            user_db.FavoriteRoutesCompanion.insert(
              routeId: 'middle-route',
              originStationId: 'middle-origin',
              destinationStationId: 'middle-destination',
              mobilityProfile: 'STANDARD',
              addedAt: DateTime.utc(2026, 7, 2),
            ),
          );
      await userDatabase
          .into(userDatabase.appPreferences)
          .insert(
            user_db.AppPreferencesCompanion.insert(
              key: 'favorite_route_snapshot:middle-route',
              value:
                  '{"routeSearchId":"middle-route","originStationId":"middle-origin","originStationName":"중간 출발","destinationStationId":"middle-destination","destinationStationName":"중간 도착","mobilityType":"STANDARD","status":"FOUND","score":50,"createdAt":"2026-07-02T00:00:00.000Z","steps":[]}',
              updatedAt: DateTime.utc(2026, 7, 2),
            ),
          );
      await userDatabase
          .into(userDatabase.favoriteRoutes)
          .insert(
            user_db.FavoriteRoutesCompanion.insert(
              routeId: 'local-duplicate',
              originStationId: 'station-sangnoksu',
              destinationStationId: 'station-sadang',
              mobilityProfile: 'SENIOR',
              addedAt: DateTime.utc(2026, 7, 3),
            ),
          );
      await userDatabase
          .into(userDatabase.appPreferences)
          .insert(
            user_db.AppPreferencesCompanion.insert(
              key: 'favorite_route_snapshot:local-duplicate',
              value: jsonEncode({
                'originStationId': 'station-sangnoksu',
                'originStationName': '레거시 출발',
                'destinationStationId': 'station-sadang',
                'destinationStationName': '레거시 도착',
                'mobilityType': 'SENIOR',
                'status': 'FOUND',
                'score': 1,
                'createdAt': '2026-07-01T00:00:00.000Z',
                'objective': 'FASTEST',
                'steps': [
                  {
                    'stepType': 'RIDE',
                    'fromStationId': 'station-sangnoksu',
                    'toStationId': 'station-sadang',
                    'lineId': 'seoul-4',
                    'serviceClass': 'SUBWAY',
                    'servicePattern': 'LOCAL',
                  },
                ],
              }),
              updatedAt: DateTime.utc(2026, 7, 1),
            ),
          );
    });

    final favorites = await repository.listFavoriteRoutes();

    expect(favorites.map((favorite) => favorite.favoriteRouteId), [
      'middle-route',
      candidate.value,
    ]);
    expect(favorites.last.addedAt, '2026-07-01T00:00:00.000Z');
    expect(favorites.last.originStationName, '대상 출발');
    final target = await userDatabase
        .customSelect(
          'SELECT value, CAST(updated_at AS INTEGER) AS updated_at_value FROM app_preferences WHERE key = ?',
          variables: [
            Variable.withString('favorite_route_snapshot:${candidate.value}'),
          ],
        )
        .getSingle();
    expect(target.read<String>('value'), targetSnapshot);
    expect(
      await userDatabase
          .customSelect(
            'SELECT route_id FROM favorite_routes WHERE route_id = ?',
            variables: [Variable.withString('local-duplicate')],
          )
          .get(),
      isEmpty,
    );
    expect(
      await userDatabase
          .customSelect(
            'SELECT key FROM app_preferences WHERE key = ?',
            variables: [
              Variable.withString('favorite_route_snapshot:local-duplicate'),
            ],
          )
          .get(),
      isEmpty,
    );
  });

  test('map이 아닌 querySnapshot이 있는 레거시 경로는 보존하고 다시 검색 필요로 표시한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteRouteRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
    const snapshot =
        '{"querySnapshot":"not-a-map","originStationId":"station-sangnoksu","originStationName":"상록수","destinationStationId":"station-sadang","destinationStationName":"사당","mobilityType":"SENIOR","status":"FOUND","score":1,"createdAt":"2026-07-01T00:00:00.000Z","steps":[{"stepType":"RIDE","fromStationId":"station-sangnoksu","toStationId":"station-sadang"}]}';
    await userDatabase.transaction(() async {
      await userDatabase
          .into(userDatabase.favoriteRoutes)
          .insert(
            user_db.FavoriteRoutesCompanion.insert(
              routeId: 'local-corrupt-query-snapshot',
              originStationId: 'station-sangnoksu',
              destinationStationId: 'station-sadang',
              mobilityProfile: 'SENIOR',
              addedAt: DateTime.utc(2026, 7),
            ),
          );
      await userDatabase
          .into(userDatabase.appPreferences)
          .insert(
            user_db.AppPreferencesCompanion.insert(
              key: 'favorite_route_snapshot:local-corrupt-query-snapshot',
              value: snapshot,
              updatedAt: DateTime.utc(2026, 7),
            ),
          );
    });

    final favorite = (await repository.listFavoriteRoutes()).single;

    expect(favorite.favoriteRouteId, 'local-corrupt-query-snapshot');
    expect(favorite.needsResearch, isTrue);
    expect(
      await userDatabase
          .customSelect('SELECT route_id FROM favorite_routes')
          .get(),
      hasLength(1),
    );
    expect(
      (await userDatabase
              .customSelect(
                'SELECT value FROM app_preferences WHERE key = ?',
                variables: [
                  Variable.withString(
                    'favorite_route_snapshot:local-corrupt-query-snapshot',
                  ),
                ],
              )
              .getSingle())
          .read<String>('value'),
      snapshot,
    );
  });

  test('손상된 기존 candidate 대상 fallback은 대상 행으로 제거할 수 있다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteRouteRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
    final candidate = RouteCandidateIdentity(
      query: RouteQueryIdentity(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'SENIOR',
        mobilityPreset: 'SLOW',
        constraintMode: 'PREFER_STEP_FREE',
        transportScope: 'SUBWAY',
        objective: 'FASTEST',
      ),
      legs: [
        RouteCandidateLegSignature(
          stepType: 'RIDE',
          fromStationId: 'station-sangnoksu',
          toStationId: 'station-sadang',
          serviceClass: 'SUBWAY',
          servicePattern: 'LOCAL',
        ),
      ],
    );
    await userDatabase.transaction(() async {
      await userDatabase
          .into(userDatabase.favoriteRoutes)
          .insert(
            user_db.FavoriteRoutesCompanion.insert(
              routeId: candidate.value,
              originStationId: 'target-origin',
              destinationStationId: 'target-destination',
              mobilityProfile: 'WHEELCHAIR',
              addedAt: DateTime.utc(2026, 7, 1),
            ),
          );
      await userDatabase
          .into(userDatabase.favoriteRoutes)
          .insert(
            user_db.FavoriteRoutesCompanion.insert(
              routeId: 'local-newer-duplicate',
              originStationId: 'station-sangnoksu',
              destinationStationId: 'station-sadang',
              mobilityProfile: 'SENIOR',
              addedAt: DateTime.utc(2026, 7, 2),
            ),
          );
      await userDatabase
          .into(userDatabase.appPreferences)
          .insert(
            user_db.AppPreferencesCompanion.insert(
              key: 'favorite_route_snapshot:local-newer-duplicate',
              value: jsonEncode({
                'originStationId': 'station-sangnoksu',
                'originStationName': '상록수',
                'destinationStationId': 'station-sadang',
                'destinationStationName': '사당',
                'mobilityType': 'SENIOR',
                'status': 'FOUND',
                'score': 1,
                'createdAt': '2026-07-02T00:00:00.000Z',
                'objective': 'FASTEST',
                'steps': [
                  {
                    'stepType': 'RIDE',
                    'fromStationId': 'station-sangnoksu',
                    'toStationId': 'station-sadang',
                    'serviceClass': 'SUBWAY',
                    'servicePattern': 'LOCAL',
                  },
                ],
              }),
              updatedAt: DateTime.utc(2026, 7, 2),
            ),
          );
    });

    final favorite = (await repository.listFavoriteRoutes()).single;

    expect(favorite.favoriteRouteId, candidate.value);
    expect(favorite.routeSearchId, candidate.value);
    expect(favorite.originStationId, 'target-origin');
    expect(favorite.destinationStationId, 'target-destination');
    expect(favorite.mobilityType, 'WHEELCHAIR');
    expect(favorite.addedAt, '2026-07-01T00:00:00.000Z');
    expect(favorite.needsResearch, isTrue);
    expect(
      await userDatabase
          .customSelect(
            'SELECT route_id FROM favorite_routes WHERE route_id = ?',
            variables: [Variable.withString('local-newer-duplicate')],
          )
          .get(),
      isEmpty,
    );
    expect(
      await userDatabase
          .customSelect(
            'SELECT key FROM app_preferences WHERE key = ?',
            variables: [
              Variable.withString('favorite_route_snapshot:${candidate.value}'),
            ],
          )
          .get(),
      isEmpty,
    );

    final restarted = DriftFavoriteRouteRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
    final reloaded = (await restarted.listFavoriteRoutes()).single;
    expect(reloaded.favoriteRouteId, candidate.value);
    expect(reloaded.originStationId, 'target-origin');
    expect(reloaded.destinationStationId, 'target-destination');
    expect(reloaded.mobilityType, 'WHEELCHAIR');
    expect(reloaded.addedAt, '2026-07-01T00:00:00.000Z');
    expect(reloaded.needsResearch, isTrue);

    await restarted.removeFavoriteRoute(reloaded.favoriteRouteId);

    expect(await repository.listFavoriteRoutes(), isEmpty);
  });

  test('복원할 수 없는 레거시 snapshot은 보존하고 다시 검색 필요로 표시한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    await catalogDatabase.customStatement(
      "UPDATE stations SET name_ko = ' 상록수 ' WHERE id = 'station-sangnoksu'",
    );
    final repository = DriftFavoriteRouteRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
    for (final fixture in [
      ('local-missing', null),
      ('local-invalid-json', '{'),
      ('local-invalid-shape', '[]'),
      (
        'local-missing-objective',
        jsonEncode({
          'originStationId': 'station-sangnoksu',
          'originStationName': '상록수',
          'destinationStationId': 'station-sadang',
          'destinationStationName': '사당',
          'mobilityType': 'WHEELCHAIR',
          'mobilityPreset': 'STEP_FREE',
          'constraintMode': 'STRICT_STEP_FREE',
          'transportScope': 'SUBWAY',
          'status': 'FOUND',
          'score': 1,
          'createdAt': '2026-07-01T00:00:00.000Z',
          'steps': [
            {
              'stepType': 'RIDE',
              'fromStationId': 'station-sangnoksu',
              'toStationId': 'station-sadang',
              'lineId': 'seoul-4',
              'serviceClass': 'SUBWAY',
              'servicePattern': 'LOCAL',
            },
          ],
        }),
      ),
      (
        'local-waypoint',
        jsonEncode({
          'originStationName': '저장 출발',
          'destinationStationName': '저장 도착',
          'waypointStationId': 'station-seonjeongneung',
          'transportScope': 'SUBWAY_AND_ITX_CHEONGCHUN',
        }),
      ),
      (
        'local-query-mismatch',
        jsonEncode({
          'originStationId': 'station-other',
          'originStationName': '다른 출발',
          'destinationStationId': 'station-sadang',
          'destinationStationName': '사당',
          'mobilityType': 'WHEELCHAIR',
          'status': 'FOUND',
          'score': 1,
          'createdAt': '2026-07-01T00:00:00.000Z',
          'steps': [
            {
              'stepType': 'RIDE',
              'fromStationId': 'station-other',
              'toStationId': 'station-sadang',
            },
          ],
        }),
      ),
      (
        'local-query-snapshot-mismatch',
        jsonEncode({
          'querySnapshot': RouteQueryIdentity(
            originStationId: 'station-sangnoksu',
            destinationStationId: 'station-sadang',
            mobilityType: 'WHEELCHAIR',
            constraintMode: 'STRICT_STEP_FREE',
            transportScope: 'SUBWAY',
            objective: 'FASTEST',
          ).toSnapshot(),
          'originStationId': 'station-other',
          'originStationName': '다른 출발',
          'destinationStationId': 'station-sadang',
          'destinationStationName': '사당',
          'mobilityType': 'WHEELCHAIR',
          'status': 'FOUND',
          'score': 1,
          'createdAt': '2026-07-01T00:00:00.000Z',
          'steps': [
            {
              'stepType': 'RIDE',
              'fromStationId': 'station-sangnoksu',
              'toStationId': 'station-sadang',
            },
          ],
        }),
      ),
      (
        'local-waypoint-number',
        jsonEncode({
          'originStationId': 'station-sangnoksu',
          'originStationName': '상록수',
          'destinationStationId': 'station-sadang',
          'destinationStationName': '사당',
          'mobilityType': 'WHEELCHAIR',
          'waypointStationId': 1,
          'status': 'FOUND',
          'score': 1,
          'createdAt': '2026-07-01T00:00:00.000Z',
          'steps': [
            {
              'stepType': 'RIDE',
              'fromStationId': 'station-sangnoksu',
              'toStationId': 'station-sadang',
            },
          ],
        }),
      ),
      (
        'local-invalid-step-type',
        jsonEncode({
          'originStationId': 'station-sangnoksu',
          'originStationName': '상록수',
          'destinationStationId': 'station-sadang',
          'destinationStationName': '사당',
          'mobilityType': 'WHEELCHAIR',
          'status': 'FOUND',
          'score': 1,
          'createdAt': '2026-07-01T00:00:00.000Z',
          'steps': [
            {
              'stepType': 'GARBAGE',
              'fromStationId': 'station-sangnoksu',
              'toStationId': 'station-sadang',
            },
          ],
        }),
      ),
      (
        'local-invalid-ride-service',
        jsonEncode({
          'originStationId': 'station-sangnoksu',
          'originStationName': '상록수',
          'destinationStationId': 'station-sadang',
          'destinationStationName': '사당',
          'mobilityType': 'WHEELCHAIR',
          'status': 'FOUND',
          'score': 1,
          'createdAt': '2026-07-01T00:00:00.000Z',
          'objective': 'FASTEST',
          'steps': [
            {
              'stepType': 'RIDE',
              'fromStationId': 'station-sangnoksu',
              'toStationId': 'station-sadang',
              'serviceClass': 'BUS',
              'servicePattern': 'RAPID',
            },
          ],
        }),
      ),
      (
        'local-non-ride-service',
        jsonEncode({
          'originStationId': 'station-sangnoksu',
          'originStationName': '상록수',
          'destinationStationId': 'station-sadang',
          'destinationStationName': '사당',
          'mobilityType': 'WHEELCHAIR',
          'status': 'FOUND',
          'score': 1,
          'createdAt': '2026-07-01T00:00:00.000Z',
          'objective': 'FASTEST',
          'steps': [
            {
              'stepType': 'WALK',
              'fromStationId': 'station-sangnoksu',
              'toStationId': 'station-sadang',
              'serviceClass': 'SUBWAY',
              'servicePattern': 'LOCAL',
            },
          ],
        }),
      ),
    ]) {
      await userDatabase
          .into(userDatabase.favoriteRoutes)
          .insert(
            user_db.FavoriteRoutesCompanion.insert(
              routeId: fixture.$1,
              originStationId: 'station-sangnoksu',
              destinationStationId: 'station-sadang',
              mobilityProfile: 'WHEELCHAIR',
              addedAt: DateTime.utc(2026, 7),
            ),
          );
      if (fixture.$2 case final String value) {
        await userDatabase
            .into(userDatabase.appPreferences)
            .insert(
              user_db.AppPreferencesCompanion.insert(
                key: 'favorite_route_snapshot:${fixture.$1}',
                value: value,
                updatedAt: DateTime.utc(2026, 7),
              ),
            );
      }
    }

    final favorites = await repository.listFavoriteRoutes();

    expect(favorites, hasLength(11));
    expect(favorites.every((favorite) => favorite.needsResearch), isTrue);
    expect(favorites.map((favorite) => favorite.statusLabel).toSet(), {
      '다시 검색 필요',
    });
    for (final favorite in favorites) {
      expect(favorite.routeSearchId, favorite.favoriteRouteId);
      expect(favorite.originStationId, 'station-sangnoksu');
      expect(favorite.destinationStationId, 'station-sadang');
      expect(favorite.mobilityType, 'WHEELCHAIR');
      expect(favorite.status, 'RESEARCH_REQUIRED');
      expect(favorite.lineId, isEmpty);
      expect(favorite.lineName, isEmpty);
      expect(favorite.etaSource, isEmpty);
      expect(favorite.score, 0);
      expect(favorite.routeCreatedAt, '2026-07-01T00:00:00.000Z');
      expect(favorite.addedAt, '2026-07-01T00:00:00.000Z');
    }
    final missing = favorites.singleWhere(
      (favorite) => favorite.favoriteRouteId == 'local-missing',
    );
    expect(missing.originStationName, '상록수');
    expect(missing.destinationStationName, '사당');
    expect(missing.transportScope, RouteTransportScope.subway);
    final waypoint = favorites.singleWhere(
      (favorite) => favorite.favoriteRouteId == 'local-waypoint',
    );
    expect(waypoint.originStationName, '저장 출발');
    expect(waypoint.destinationStationName, '저장 도착');
    expect(waypoint.transportScope, RouteTransportScope.subwayAndItxCheongchun);
    final queryMismatch = favorites.singleWhere(
      (favorite) => favorite.favoriteRouteId == 'local-query-mismatch',
    );
    expect(queryMismatch.originStationName, '상록수');

    await repository.removeFavoriteRoute('local-invalid-json');

    expect(
      await userDatabase
          .customSelect('SELECT route_id FROM favorite_routes')
          .get(),
      hasLength(10),
    );
    expect(
      await userDatabase
          .customSelect(
            'SELECT key FROM app_preferences WHERE key = ?',
            variables: [
              Variable.withString('favorite_route_snapshot:local-invalid-json'),
            ],
          )
          .get(),
      isEmpty,
    );
    expect(
      await userDatabase
          .customSelect(
            'SELECT route_id FROM favorite_routes WHERE route_id IN (?, ?)',
            variables: [
              Variable.withString('local-missing'),
              Variable.withString('local-waypoint'),
            ],
          )
          .get(),
      hasLength(2),
    );
    expect(
      await userDatabase
          .customSelect(
            'SELECT key FROM app_preferences WHERE key = ?',
            variables: [
              Variable.withString('favorite_route_snapshot:local-waypoint'),
            ],
          )
          .get(),
      hasLength(1),
    );
    expect(
      await userDatabase
          .customSelect(
            'SELECT route_id FROM favorite_routes WHERE route_id IN (?, ?)',
            variables: [
              Variable.withString('local-query-mismatch'),
              Variable.withString('local-waypoint-number'),
            ],
          )
          .get(),
      hasLength(2),
    );
  });

  test('손상된 레거시 행 하나가 정상 즐겨찾기 목록을 가리지 않는다', () async {
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
            routeId: 'bad',
            originStationId: 'station-sangnoksu',
            destinationStationId: 'station-sadang',
            mobilityProfile: 'SENIOR',
            addedAt: DateTime.utc(2026, 7),
          ),
        );
    await userDatabase
        .into(userDatabase.appPreferences)
        .insert(
          user_db.AppPreferencesCompanion.insert(
            key: 'favorite_route_snapshot:bad',
            value: '[]',
            updatedAt: DateTime.utc(2026, 7),
          ),
        );
    final saved = await repository.saveFavoriteRoute(
      'good',
      result: RouteSearchResult(
        routeSearchId: 'good',
        originStationId: 'station-sangnoksu',
        originStationName: '상록수',
        destinationStationId: 'station-sadang',
        destinationStationName: '사당',
        mobilityType: 'SENIOR',
        status: 'FOUND',
        lineId: '',
        lineName: '',
        score: 1,
        steps: const [],
        warnings: const [],
        blockedReasons: const [],
        createdAt: '2026-07-01T00:00:00.000Z',
      ),
    );

    final favorites = await repository.listFavoriteRoutes();

    expect(favorites, hasLength(2));
    expect(
      favorites.any(
        (favorite) => favorite.favoriteRouteId == saved.favoriteRouteId,
      ),
      isTrue,
    );
    expect(
      favorites
          .singleWhere((favorite) => favorite.favoriteRouteId == 'bad')
          .needsResearch,
      isTrue,
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
      transportScope: RouteTransportScope.subwayAndItxCheongchun,
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
    expect(saved.transportScope, RouteTransportScope.subwayAndItxCheongchun);
    expect(
      favorites.single.transportScope,
      RouteTransportScope.subwayAndItxCheongchun,
    );
    expect(snapshot['etaSource'], 'STATIC_BACKEND_V1');
    expect(snapshot['transportScope'], 'SUBWAY_AND_ITX_CHEONGCHUN');
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
    await searchHistoryRepository.recordSearch(' 상록수 ', region: '수도권');
    await searchHistoryRepository.recordSearch('사당', region: '수도권');
    await searchHistoryRepository.recordSearch('상록수', region: '수도권');

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

final class _DeleteLegacyBeforeMigrationTransaction extends QueryInterceptor {
  _DeleteLegacyBeforeMigrationTransaction(this.legacyRouteId);

  final String legacyRouteId;
  bool _armed = false;

  void arm() => _armed = true;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (_armed && executor is TransactionExecutor) {
      _armed = false;
      await executor.runDelete(
        'DELETE FROM favorite_routes WHERE route_id = ?',
        [legacyRouteId],
      );
      await executor.runDelete('DELETE FROM app_preferences WHERE key = ?', [
        'favorite_route_snapshot:$legacyRouteId',
      ]);
    }
    return executor.runSelect(statement, args);
  }
}
