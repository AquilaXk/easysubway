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
    await userDatabase
        .transaction(() async {
          await userDatabase.into(userDatabase.favoriteRoutes).insert(
            user_db.FavoriteRoutesCompanion.insert(
              routeId: 'local-legacy-route',
              originStationId: 'station-sangnoksu',
              destinationStationId: 'station-sadang',
              mobilityProfile: 'WHEELCHAIR',
              addedAt: DateTime.utc(2026, 7),
            ),
          );
          await userDatabase.into(userDatabase.appPreferences).insert(
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
                'steps': [
                  {
                    'stepType': 'RIDE',
                    'fromStationId': 'station-sangnoksu',
                    'toStationId': 'station-sadang',
                    'lineId': 'seoul-4',
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
        await userDatabase.into(userDatabase.favoriteRoutes).insert(
          user_db.FavoriteRoutesCompanion.insert(
            routeId: fixture.$1,
            originStationId: 'station-sangnoksu',
            destinationStationId: 'station-sadang',
            mobilityProfile: 'SENIOR',
            addedAt: DateTime.utc(2026, 7),
          ),
        );
        await userDatabase.into(userDatabase.appPreferences).insert(
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
    expect(favorites.map((favorite) => favorite.favoriteRouteId).toSet(), hasLength(2));
  });

  test('복원할 수 없는 레거시 snapshot은 보존하고 다시 검색 필요로 표시한다', () async {
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
      ('missing', null),
      ('invalid', '{'),
      ('waypoint', jsonEncode({
        'originStationName': '상록수',
        'destinationStationName': '사당',
        'waypointStationId': 'station-seonjeongneung',
      })),
    ]) {
      await userDatabase.into(userDatabase.favoriteRoutes).insert(
        user_db.FavoriteRoutesCompanion.insert(
          routeId: fixture.$1,
          originStationId: 'station-sangnoksu',
          destinationStationId: 'station-sadang',
          mobilityProfile: 'WHEELCHAIR',
          addedAt: DateTime.utc(2026, 7),
        ),
      );
      if (fixture.$2 case final String value) {
        await userDatabase.into(userDatabase.appPreferences).insert(
          user_db.AppPreferencesCompanion.insert(
            key: 'favorite_route_snapshot:${fixture.$1}',
            value: value,
            updatedAt: DateTime.utc(2026, 7),
          ),
        );
      }
    }

    final favorites = await repository.listFavoriteRoutes();

    expect(favorites, hasLength(3));
    expect(favorites.every((favorite) => favorite.needsResearch), isTrue);
    expect(favorites.map((favorite) => favorite.statusLabel).toSet(), {'다시 검색 필요'});
    expect(await userDatabase.customSelect('SELECT route_id FROM favorite_routes').get(), hasLength(3));
    expect(await userDatabase.customSelect('SELECT key FROM app_preferences').get(), hasLength(2));
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
    await userDatabase.into(userDatabase.favoriteRoutes).insert(
      user_db.FavoriteRoutesCompanion.insert(
        routeId: 'bad',
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityProfile: 'SENIOR',
        addedAt: DateTime.utc(2026, 7),
      ),
    );
    await userDatabase.into(userDatabase.appPreferences).insert(
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
    expect(favorites.any((favorite) => favorite.favoriteRouteId == saved.favoriteRouteId), isTrue);
    expect(favorites.singleWhere((favorite) => favorite.favoriteRouteId == 'bad').needsResearch, isTrue);
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
