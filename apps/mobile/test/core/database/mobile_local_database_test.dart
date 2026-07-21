import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:easysubway_mobile/app/app_bootstrap.dart';
import 'package:easysubway_mobile/app/app_dependencies.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database_opener.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database_opener.dart';
import 'package:easysubway_mobile/core/datapack/bundled_data_pack_freshness.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_update_state.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_updater.dart';
import 'package:easysubway_mobile/core/datapack/emergency_override_repository.dart';
import 'package:easysubway_mobile/features/routes/data/local_route_repository.dart';
import 'package:easysubway_mobile/features/stations/data/drift_station_repository.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('앱 부트스트랩 owner는 제거될 때 열린 DB 자원을 닫는다', (tester) async {
    final closeCalled = Completer<void>();

    await tester.pumpWidget(
      AppBootstrapLifecycle(
        close: () {
          closeCalled.complete();
          return Future<void>.value();
        },
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());

    await closeCalled.future;
    expect(closeCalled.isCompleted, isTrue);
  });

  test('route repository close가 실패해도 bootstrap은 나머지 DB를 닫는다', () async {
    final catalogDatabase = _CloseTrackingCatalogDatabase();
    final userDatabase = _CloseTrackingUserDatabase();
    addTearDown(() async {
      if (catalogDatabase.closeCount == 0) await catalogDatabase.close();
      if (userDatabase.closeCount == 0) await userDatabase.close();
    });
    final localRouteRepository = _AlwaysCloseFailingLocalRouteRepository(
      catalogDatabase,
    );
    final bootstrap = AppBootstrap(
      dependencies: AppDependencies.resolve(
        catalogDatabase: catalogDatabase,
        userDatabase: userDatabase,
        localRouteRepository: localRouteRepository,
        enablePushNotifications: false,
      ),
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      dataPackUpdate: Future<void>.value(),
      resumeDataPackUpdate: () async {},
      acceptMeteredDataPackUpdate: () async {},
      bundledDataPackFreshness: null,
      localRouteRepository: localRouteRepository,
    );

    await expectLater(
      bootstrap.close(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'route repository close failed',
        ),
      ),
    );

    expect(catalogDatabase.closeCount, 1);
    expect(userDatabase.closeCount, 1);
  });

  testWidgets('앱 lifecycle은 resumed에서 데이터팩 foreground update를 요청한다', (
    tester,
  ) async {
    final resumeCalled = Completer<void>();

    await tester.pumpWidget(
      AppBootstrapLifecycle(
        close: () => Future<void>.value(),
        resumeDataPackUpdate: () {
          resumeCalled.complete();
          return Future<void>.value();
        },
        child: const SizedBox.shrink(),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    await resumeCalled.future.timeout(const Duration(seconds: 5));
    expect(resumeCalled.isCompleted, isTrue);
  });

  testWidgets('앱 lifecycle은 resumed에서 하차 알림 상태를 재조정한다', (tester) async {
    final reconcileCalled = Completer<void>();

    await tester.pumpWidget(
      AppBootstrapLifecycle(
        close: () => Future<void>.value(),
        resumeGetOffAlarmState: () {
          reconcileCalled.complete();
          return Future<void>.value();
        },
        child: const SizedBox.shrink(),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    await reconcileCalled.future.timeout(const Duration(seconds: 5));
    expect(reconcileCalled.isCompleted, isTrue);
  });

  test('catalog DB는 앱 시작에 필요한 schema와 index를 만든다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);

    final objects = await database.customSelect('''
          SELECT name
          FROM sqlite_master
          WHERE type IN ('table', 'index')
            AND name NOT LIKE 'sqlite_%'
          ORDER BY name
          ''').get();
    final names = objects.map((row) => row.read<String>('name')).toSet();

    expect(
      names,
      containsAll({
        'catalog_metadata',
        'operators',
        'lines',
        'stations',
        'station_aliases',
        'station_lines',
        'fare_zones',
        'fare_rules',
        'fare_discounts',
        'station_fare_zones',
        'network_edges',
        'station_exits',
        'facilities',
        'station_accessibility_summaries',
        'internal_route_nodes',
        'internal_route_edges',
        'data_quality_records',
        'idx_stations_normalized_name',
        'idx_station_lines_line_sequence',
        'idx_network_edges_from_node',
        'idx_facilities_station',
        'idx_internal_route_edges_from',
      }),
    );
  });

  test(
    'catalog DB migration은 schema 16 station car door hint를 보존하고 v17-v18 table을 만든다',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'easysubway-catalog-v16-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/catalog.sqlite');
      final legacy = sqlite.sqlite3.open(file.path);
      legacy.execute('''
        CREATE TABLE station_car_door_hints (
          id TEXT NOT NULL PRIMARY KEY,
          station_id TEXT NOT NULL,
          line_id TEXT NOT NULL,
          direction TEXT NOT NULL DEFAULT '',
          target_facility_type TEXT NOT NULL,
          car_number INTEGER NOT NULL,
          door_number INTEGER NOT NULL,
          source_id TEXT NOT NULL DEFAULT '',
          source_snapshot_id TEXT NOT NULL DEFAULT '',
          provider_record_hash TEXT NOT NULL DEFAULT '',
          provenance_kind TEXT NOT NULL DEFAULT 'UNKNOWN',
          verification_status TEXT NOT NULL DEFAULT 'UNKNOWN',
          last_verified_at INTEGER,
          evidence_hash TEXT NOT NULL DEFAULT ''
        )
      ''');
      legacy.execute('''
        INSERT INTO station_car_door_hints (
          id, station_id, line_id, target_facility_type, car_number, door_number
        ) VALUES ('kept-hint', 'station-kept', 'line-kept', 'STAIR', 1, 1)
      ''');
      legacy.execute('PRAGMA user_version = 16');
      legacy.close();

      final database = CatalogDatabase.file(file);
      addTearDown(database.close);
      final fareCount = await database
          .customSelect('SELECT COUNT(*) AS count FROM official_od_fare_quotes')
          .getSingle();
      final hint = await database
          .customSelect('SELECT id FROM station_car_door_hints')
          .getSingle();

      expect(catalogDatabaseSchemaVersion, 18);
      expect(fareCount.read<int>('count'), 0);
      expect(hint.read<String>('id'), 'kept-hint');
    },
  );

  test(
    'catalog DB migration은 schema 15 데이터를 보존하고 v16-v18 table을 만든다',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'easysubway-catalog-v15-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/catalog.sqlite');
      final legacy = sqlite.sqlite3.open(file.path);
      legacy.execute('CREATE TABLE preserved_rows (value TEXT NOT NULL)');
      legacy.execute("INSERT INTO preserved_rows VALUES ('kept')");
      legacy.execute('PRAGMA user_version = 15');
      legacy.close();

      final database = CatalogDatabase.file(file);
      addTearDown(database.close);
      final fareCount = await database
          .customSelect('SELECT COUNT(*) AS count FROM official_od_fare_quotes')
          .getSingle();
      final hintCount = await database
          .customSelect('SELECT COUNT(*) AS count FROM station_car_door_hints')
          .getSingle();
      final preserved = await database
          .customSelect('SELECT value FROM preserved_rows')
          .getSingle();

      expect(catalogDatabaseSchemaVersion, 18);
      expect(fareCount.read<int>('count'), 0);
      expect(hintCount.read<int>('count'), 0);
      expect(preserved.read<String>('value'), 'kept');
    },
  );

  test(
    'catalog DB migration은 v17 route row를 보존하고 v18 service identity를 추가한다',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'easysubway-catalog-v17-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/catalog.sqlite');
      final legacy = sqlite.sqlite3.open(file.path);
      legacy.execute(
        'CREATE TABLE transit_trips (id TEXT NOT NULL PRIMARY KEY)',
      );
      legacy.execute(
        'CREATE TABLE network_edges (id TEXT NOT NULL PRIMARY KEY)',
      );
      legacy.execute("INSERT INTO transit_trips VALUES ('trip-kept')");
      legacy.execute("INSERT INTO network_edges VALUES ('edge-kept')");
      legacy.execute('PRAGMA user_version = 17');
      legacy.close();

      final database = CatalogDatabase.file(file);
      addTearDown(database.close);
      final trip = await database
          .customSelect(
            "SELECT id, service_class FROM transit_trips WHERE id = 'trip-kept'",
          )
          .getSingle();
      final edge = await database
          .customSelect(
            "SELECT id, service_class FROM network_edges WHERE id = 'edge-kept'",
          )
          .getSingle();
      final evidenceCount = await database
          .customSelect(
            'SELECT COUNT(*) AS count FROM route_service_artifact_evidence',
          )
          .getSingle();

      expect(catalogDatabaseSchemaVersion, 18);
      expect(trip.read<String>('service_class'), 'SUBWAY');
      expect(edge.read<String>('service_class'), 'SUBWAY');
      expect(evidenceCount.read<int>('count'), 0);
    },
  );

  test('내장 baseline 데이터팩은 schemaVersion과 상록수/사당 기본 데이터를 제공한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-catalog-',
    );
    addTearDown(() => directory.delete(recursive: true));

    final opener = CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    );
    final database = await opener.open();
    addTearDown(database.close);

    final metadata = await database.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'schemaVersion'
          ''').getSingle();
    final stations = await database.customSelect('''
          SELECT id, name_ko, latitude, longitude
          FROM stations
          WHERE id IN ('station-sangnoksu', 'station-sadang')
          ORDER BY name_ko
          ''').get();
    final aliases = await database.customSelect('''
          SELECT alias
          FROM station_aliases
          WHERE station_id = 'station-sangnoksu'
          ORDER BY alias
          ''').get();
    final exits = await database.customSelect('''
          SELECT exit_number, latitude, longitude, has_elevator_connection,
                 data_source_type, last_verified_at
          FROM station_exits
          WHERE station_id = 'station-sangnoksu'
          ''').get();
    final facilities = await database.customSelect('''
          SELECT id, type, name
          FROM facilities
          WHERE station_id = 'station-sangnoksu'
          ORDER BY id
          ''').get();
    final fieldValidationRecords = await database.customSelect('''
          SELECT target_type, target_id, quality_level, checked_at
          FROM data_quality_records
          WHERE target_id IN (
            'exit-sangnoksu-1',
            'facility-sangnoksu-elevator-1',
            'facility-sangnoksu-escalator-1',
            'facility-sangnoksu-accessible-toilet-1',
            'edge-sangnoksu-concourse-exit-1'
          )
          ORDER BY target_id
          ''').get();
    final networkEdges = await database.customSelect('''
          SELECT id, from_node_id, to_node_id, edge_type, service_pattern,
                 includes_stairs, accessibility_status, reliability_score,
                 facility_id, last_verified_at, distance_meters
          FROM network_edges
          WHERE id IN (
            'edge-sangnoksu-sadang-seoul-4',
            'edge-sadang-sangnoksu-seoul-4'
          )
          ORDER BY id
          ''').get();
    final internalRouteEdges = await database.customSelect('''
          SELECT id, edge_type, accessibility_status
          FROM internal_route_edges
          ORDER BY id
          ''').get();
    final routeMapPosition = await database.customSelect('''
          SELECT label_polygon, source_id, source_name, source_url,
                 license, license_status
          FROM route_map_positions
          WHERE station_id = 'station-sangnoksu'
            AND line_id = 'seoul-4'
          ''').getSingle();
    final fareTableCounts = await database.customSelect('''
          SELECT
            (SELECT COUNT(*) FROM fare_zones) AS fare_zone_count,
            (SELECT COUNT(*) FROM fare_rules) AS fare_rule_count,
            (SELECT COUNT(*) FROM fare_discounts) AS fare_discount_count,
            (SELECT COUNT(*)
             FROM station_fare_zones
             WHERE zone_id = 'capital-integrated') AS station_fare_zone_count
          ''').getSingle();

    expect(metadata.read<String>('value'), '1');
    expect(stations.map((row) => row.read<String>('name_ko')).toList(), [
      '사당',
      '상록수',
    ]);
    final sangnoksu = stations.firstWhere(
      (row) => row.read<String>('id') == 'station-sangnoksu',
    );
    expect(sangnoksu.read<double>('latitude'), closeTo(37.3028, 0.001));
    expect(sangnoksu.read<double>('longitude'), closeTo(126.8666, 0.001));
    expect(aliases.map((row) => row.read<String>('alias')), [
      '448',
      '4호선 상록수',
      'Sangnoksu',
      '상록수역',
    ]);
    expect(exits.single.read<String>('exit_number'), '1');
    expect(exits.single.read<double>('latitude'), closeTo(37.3021, 0.0001));
    expect(exits.single.read<double>('longitude'), closeTo(126.8661, 0.0001));
    expect(exits.single.read<int>('has_elevator_connection'), 1);
    expect(exits.single.read<String>('data_source_type'), 'OFFICIAL_FILE');
    expect(exits.single.read<int>('last_verified_at'), 1781827200);
    expect(facilities.map((row) => row.read<String>('type')).toSet(), {
      'ACCESSIBLE_TOILET',
      'ELEVATOR',
      'ESCALATOR',
    });
    expect(
      facilities.map((row) => row.read<String>('name')),
      containsAll(['1번 출구 엘리베이터', '1번 출구 에스컬레이터', '대합실 장애인 화장실']),
    );
    expect(
      fieldValidationRecords
          .map((row) => row.read<String>('target_type'))
          .toSet(),
      {'facility', 'internal_route_edge', 'station_exit'},
    );
    expect(
      fieldValidationRecords
          .map((row) => row.read<String>('quality_level'))
          .toSet(),
      {'FIELD_STALE', 'FIELD_UNKNOWN', 'FIELD_VERIFIED'},
    );
    final expectedFieldValidationRecords = {
      'exit-sangnoksu-1': ('station_exit', 'FIELD_VERIFIED'),
      'facility-sangnoksu-elevator-1': ('facility', 'FIELD_VERIFIED'),
      'facility-sangnoksu-escalator-1': ('facility', 'FIELD_UNKNOWN'),
      'facility-sangnoksu-accessible-toilet-1': ('facility', 'FIELD_STALE'),
      'edge-sangnoksu-concourse-exit-1': (
        'internal_route_edge',
        'FIELD_VERIFIED',
      ),
    };
    expect(
      fieldValidationRecords,
      hasLength(expectedFieldValidationRecords.length),
    );
    for (final row in fieldValidationRecords) {
      final targetId = row.read<String>('target_id');
      final expectedRecord = expectedFieldValidationRecords[targetId];
      expect(expectedRecord == null, isFalse, reason: targetId);
      expect(row.read<String>('target_type'), expectedRecord!.$1);
      final qualityLevel = row.read<String>('quality_level');
      expect(qualityLevel, expectedRecord.$2);
      if (qualityLevel == 'FIELD_VERIFIED') {
        expect(row.read<int?>('checked_at') == null, isFalse, reason: targetId);
      }
    }
    expect(networkEdges, hasLength(2));
    expect(networkEdges.map((row) => row.read<String>('edge_type')).toSet(), {
      'RIDE',
    });
    expect(
      networkEdges.map((row) => row.read<String>('service_pattern')).toSet(),
      {'LOCAL'},
    );
    expect(
      networkEdges.map((row) => row.read<bool>('includes_stairs')).toSet(),
      {false},
    );
    expect(
      networkEdges
          .map((row) => row.read<String>('accessibility_status'))
          .toSet(),
      {'AVAILABLE'},
    );
    expect(
      networkEdges.map((row) => row.read<int>('reliability_score')).toSet(),
      {90},
    );
    expect(
      networkEdges
          .map((row) => row.readNullable<String>('facility_id'))
          .toSet(),
      {null},
    );
    expect(
      networkEdges.map((row) => row.read<int>('last_verified_at')).toSet(),
      {1781827200},
    );
    expect(
      networkEdges.map((row) => row.read<int>('distance_meters')).toSet(),
      {18600},
    );
    expect(
      networkEdges
          .map(
            (row) =>
                '${row.read<String>('from_node_id')}->'
                '${row.read<String>('to_node_id')}',
          )
          .toSet(),
      {
        'station-sangnoksu:seoul-4->station-sadang:seoul-4',
        'station-sadang:seoul-4->station-sangnoksu:seoul-4',
      },
    );
    expect(
      internalRouteEdges
          .map((row) => row.read<String>('accessibility_status'))
          .toSet(),
      {'AVAILABLE'},
    );
    // [2026-07-11 #1950] 정본이 오너 자작 도식으로 교체되어 좌표가 바뀐다. 정확한
    // 폴리곤 대신 구조(닫힌 4점 사각형)를 검증한다(좌표 회귀는 route-map 게이트가 강제).
    final labelPolygon =
        (jsonDecode(routeMapPosition.read<String>('label_polygon'))
                as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(labelPolygon, hasLength(4));
    for (final point in labelPolygon) {
      expect(point['x'], isA<num>());
      expect(point['y'], isA<num>());
    }
    final displayedSourceValues = [
      routeMapPosition.read<String>('source_id'),
      routeMapPosition.read<String>('source_name'),
      routeMapPosition.read<String>('source_url'),
      routeMapPosition.read<String>('license'),
      routeMapPosition.read<String>('license_status'),
    ].join(' ').toLowerCase();
    expect(routeMapPosition.read<String>('source_name').trim(), isNotEmpty);
    // [#1950] 오너 자작 정본은 공개 URL이 없어 internal: 스킴으로 provenance를 표기한다.
    final routeMapSourceUrl = routeMapPosition.read<String>('source_url');
    expect(
      routeMapSourceUrl.startsWith('https://') ||
          routeMapSourceUrl.startsWith('internal:'),
      isTrue,
    );
    expect(displayedSourceValues, isNot(contains('fixture')));
    expect(displayedSourceValues, isNot(contains('easysubway.local')));
    expect(displayedSourceValues, isNot(contains('review-required')));
    expect(fareTableCounts.read<int>('fare_zone_count'), 0);
    expect(fareTableCounts.read<int>('fare_rule_count'), 0);
    expect(fareTableCounts.read<int>('fare_discount_count'), 0);
    expect(fareTableCounts.read<int>('station_fare_zone_count'), 0);
    expect(
      File('${directory.path}/datapacks/core.sqlite').existsSync(),
      isTrue,
    );
    expect(
      File('${directory.path}/datapacks/capital.sqlite').existsSync(),
      isTrue,
    );
  });

  test('내장 데이터팩은 #2135 ITX topology만 포함하고 timetable은 포함하지 않는다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-itx-topology-',
    );
    addTearDown(() => directory.delete(recursive: true));

    final database = await CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    ).open();
    addTearDown(database.close);

    final topology = await database.customSelect('''
          SELECT COUNT(*) AS edge_count,
                 COUNT(DISTINCT from_node_id) AS from_node_count,
                 MIN(duration_seconds) AS min_duration,
                 MAX(duration_seconds) AS max_duration
          FROM network_edges
          WHERE service_class = 'ITX_CHEONGCHUN'
            AND service_pattern = 'EXPRESS'
          ''').getSingle();
    final timetable = await database.customSelect('''
          SELECT COUNT(*) AS trip_count
          FROM transit_trips
          WHERE service_class = 'ITX_CHEONGCHUN'
          ''').getSingle();
    final admission = await database.customSelect('''
          SELECT admission_status, admission_eligible, fresh_until, source_issue
          FROM route_service_artifact_evidence
          WHERE service_class = 'ITX_CHEONGCHUN'
          ''').getSingle();

    expect(topology.read<int>('edge_count'), 48);
    expect(topology.read<int>('from_node_count'), greaterThan(0));
    expect(topology.read<int>('min_duration'), 0);
    expect(topology.read<int>('max_duration'), 0);
    expect(timetable.read<int>('trip_count'), 0);
    expect(admission.read<String>('admission_status'), 'ADMITTED');
    expect(admission.read<int>('admission_eligible'), 1);
    expect(admission.read<String>('fresh_until'), '2026-07-27T00:00:00+09:00');
    expect(admission.read<int>('source_issue'), 2135);
  });

  test('내장 데이터팩은 실제 open 경로에서 expiry 경계의 stale 상태를 기록한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-catalog-stale-bundled-',
    );
    addTearDown(() => directory.delete(recursive: true));

    final opener = CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
      now: () => DateTime.utc(2026, 8, 11),
    );
    final database = await opener.open();
    expect(opener.openedBundledDataPack, isTrue);
    final installedPack = File('${directory.path}/datapacks/capital.sqlite');
    final firstHash = sha256.convert(await installedPack.readAsBytes());
    await database.close();
    final state =
        jsonDecode(
              await File(
                '${directory.path}/datapacks/bundled-freshness.json',
              ).readAsString(),
            )
            as Map<String, Object?>;

    expect(state['status'], 'STALE');
    expect(state['reasonCode'], 'BUNDLED_PACK_EXPIRED');
    expect(state['labelKo'], '저장된 데이터 기준 · 갱신 필요');
    expect(state['freshnessExpiresAt'], '2026-08-11T00:00:00.000Z');
    final freshness = await BundledDataPackFreshness.read(directory);
    expect(freshness.staleLabel, '저장된 데이터 기준 · 갱신 필요');

    final reopened = await CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
      now: () => DateTime.utc(2026, 8, 11),
    ).open();
    addTearDown(reopened.close);
    expect(sha256.convert(await installedPack.readAsBytes()), firstHash);
  });

  test('기존 baseline 노선도 출처에 남은 fixture 문구를 정리한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);

    await database.seedBaselineIfEmpty();
    await database.customStatement('''
      UPDATE route_map_positions
      SET source_id = 'fixture-route-map-source-capital-review',
          source_name = '수도권 노선도 fixture 좌표 확인',
          source_url = 'https://easysubway.local/fixtures/catalog-fixture.json',
          license = 'fixture-only',
          license_status = 'fixture-only'
      WHERE station_id = 'station-sangnoksu'
        AND line_id = 'seoul-4'
      ''');

    await database.seedBaselineIfEmpty();

    final routeMapPosition = await database.customSelect('''
          SELECT source_id, source_name, source_url, license, license_status
          FROM route_map_positions
          WHERE station_id = 'station-sangnoksu'
            AND line_id = 'seoul-4'
          ''').getSingle();
    final displayedSourceValues = [
      routeMapPosition.read<String>('source_id'),
      routeMapPosition.read<String>('source_name'),
      routeMapPosition.read<String>('source_url'),
      routeMapPosition.read<String>('license'),
      routeMapPosition.read<String>('license_status'),
    ].join(' ').toLowerCase();

    expect(routeMapPosition.read<String>('source_name'), '수도권 도시철도 노선도');
    expect(
      routeMapPosition.read<String>('source_url'),
      'https://www.seoulmetro.co.kr/kr/cyberStation.do',
    );
    expect(displayedSourceValues, isNot(contains('fixture')));
    expect(displayedSourceValues, isNot(contains('easysubway.local')));
    expect(displayedSourceValues, isNot(contains('review-required')));
  });

  test('기존 baseline의 청소년 현금요금 1000원을 공식 1650원으로 보정한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);

    await database.seedBaselineIfEmpty();
    await database.customStatement('''
      UPDATE fare_discounts
      SET cash_fare = 1000
      WHERE id = 'capital-integrated-youth'
    ''');

    await database.seedBaselineIfEmpty();

    final youthFare = await database.customSelect('''
      SELECT cash_fare
      FROM fare_discounts
      WHERE id = 'capital-integrated-youth'
    ''').getSingle();
    expect(youthFare.read<int>('cash_fare'), 1650);
  });

  test('신규 baseline은 50km 초과 구간을 8km당100원 9단계로 시딩한다(#1911)', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);

    await database.seedBaselineIfEmpty();

    final fareRule = await database.customSelect('''
      SELECT additional_steps_json
      FROM fare_rules
      WHERE id = 'capital-integrated-standard'
    ''').getSingle();
    final additionalSteps =
        jsonDecode(fareRule.read<String>('additional_steps_json')) as List;

    expect(additionalSteps, hasLength(9));
    for (var index = 0; index < 8; index += 1) {
      expect((additionalSteps[index] as Map)['distanceMeters'], 5000);
    }
    expect((additionalSteps[8] as Map)['distanceMeters'], 8000);
  });

  test('기존 baseline에 남은 구버전 단일 단계 fare rule을 9단계로 갱신한다(#1911)', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);

    await database.seedBaselineIfEmpty();
    await database.customStatement('''
      UPDATE fare_rules
      SET additional_steps_json =
        '[{"distanceMeters":5000,"cardFare":100,"cashFare":100}]'
      WHERE id = 'capital-integrated-standard'
      ''');

    await database.seedBaselineIfEmpty();

    final fareRule = await database.customSelect('''
      SELECT additional_steps_json
      FROM fare_rules
      WHERE id = 'capital-integrated-standard'
      ''').getSingle();
    final additionalSteps =
        jsonDecode(fareRule.read<String>('additional_steps_json')) as List;

    expect(additionalSteps, hasLength(9));
    for (var index = 0; index < 8; index += 1) {
      expect((additionalSteps[index] as Map)['distanceMeters'], 5000);
    }
    expect((additionalSteps[8] as Map)['distanceMeters'], 8000);
  });

  test('내장 데이터팩은 로컬 역 검색 repository에서 역 번호 검색을 제공한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-catalog-search-',
    );
    addTearDown(() => directory.delete(recursive: true));

    final database = await CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    ).open();
    addTearDown(database.close);
    final repository = DriftStationRepository(database: database);

    final results = await repository.searchStations('448');

    expect(results, hasLength(1));
    expect(results.single.id, 'station-sangnoksu');
  });

  test('내장 데이터팩은 설치된 파일이 손상되어 있으면 번들 asset으로 교체한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-catalog-corrupt-',
    );
    addTearDown(() => directory.delete(recursive: true));

    final installedCapitalPack = File(
      '${directory.path}/datapacks/capital.sqlite',
    );
    await installedCapitalPack.create(recursive: true);
    await installedCapitalPack.writeAsString('broken sqlite file');

    final opener = CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    );
    final database = await opener.open();
    addTearDown(database.close);

    final metadata = await database.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'schemaVersion'
          ''').getSingle();

    expect(metadata.read<String>('value'), '1');
    expect(
      await installedCapitalPack.openRead(0, 16).first,
      'SQLite format 3'.codeUnits.followedBy([0]).toList(),
    );
  });

  test('catalog opener는 업데이트된 current pointer가 있으면 해당 데이터팩을 연다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-catalog-current-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final updatedPack = File('${catalogDirectory.path}/capital-v18.sqlite');
    final updatedDatabase = CatalogDatabase.file(updatedPack);
    await updatedDatabase.seedBaselineIfEmpty();
    await updatedDatabase
        .into(updatedDatabase.catalogMetadata)
        .insertOnConflictUpdate(
          CatalogMetadataCompanion.insert(
            key: 'activePack',
            value: 'capital-v18',
            updatedAt: Value(DateTime.utc(2026, 6, 19, 12)),
          ),
        );
    await updatedDatabase.close();
    await File('${catalogDirectory.path}/current.json').writeAsString(
      jsonEncode({
        'id': 'capital',
        'version': '18',
        'path': updatedPack.path,
        'sha256': 'local-fixture',
      }),
    );

    final opener = CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    );
    final database = await opener.open();
    addTearDown(database.close);

    final metadata = await database.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'activePack'
          ''').getSingle();

    expect(metadata.read<String>('value'), 'capital-v18');
    expect(opener.openedBundledDataPack, isFalse);
  });

  test('catalog opener는 설치된 current pack의 제거된 access edge를 보존한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-catalog-current-access-backfill-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final updatedPack = File('${catalogDirectory.path}/capital-v18.sqlite');
    final updatedDatabase = CatalogDatabase.file(updatedPack);
    await updatedDatabase.seedBaselineIfEmpty();
    await updatedDatabase.customStatement('''
      DELETE FROM network_edges
      WHERE edge_type IN ('ENTRY', 'EXIT')
    ''');
    await updatedDatabase.close();
    await File('${catalogDirectory.path}/current.json').writeAsString(
      jsonEncode({
        'id': 'capital',
        'version': '18',
        'path': updatedPack.path,
        'sha256': 'local-fixture',
      }),
    );

    final database = await CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    ).open();
    addTearDown(database.close);
    final accessEdgeCount = await database.customSelect('''
      SELECT COUNT(*) AS count
      FROM network_edges
      WHERE id IN (
        'entry-sangnoksu-seoul-4',
        'exit-sangnoksu-seoul-4',
        'entry-sadang-seoul-4',
        'exit-sadang-seoul-4'
      )
    ''').getSingle();
    final route = await LocalRouteRepository(catalogDatabase: database)
        .searchRoute(
          const RouteSearchRequest(
            originStationId: 'station-sangnoksu',
            destinationStationId: 'station-sadang',
            mobilityType: 'WHEELCHAIR',
          ),
        );

    expect(accessEdgeCount.read<int>('count'), 0);
    expect(route.status, 'UNKNOWN');
  });

  test('catalog opener는 부분 적용된 current pack access edge를 보존한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-catalog-current-access-backfill-partial-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final updatedPack = File('${catalogDirectory.path}/capital-v18.sqlite');
    final updatedDatabase = CatalogDatabase.file(updatedPack);
    await updatedDatabase.seedBaselineIfEmpty();
    await updatedDatabase.customStatement('''
      DELETE FROM network_edges
      WHERE edge_type IN ('ENTRY', 'EXIT')
    ''');
    await updatedDatabase.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        stair_access_state, accessibility_status, reliability_score,
        last_verified_at
      )
      VALUES (
        'entry-sangnoksu-seoul-4',
        'station-sangnoksu',
        'station-sangnoksu:seoul-4',
        90,
        'ENTRY',
        'STEP_FREE',
        'AVAILABLE',
        90,
        1781827200
      )
    ''');
    await updatedDatabase.close();
    await File('${catalogDirectory.path}/current.json').writeAsString(
      jsonEncode({
        'id': 'capital',
        'version': '18',
        'path': updatedPack.path,
        'sha256': 'local-fixture',
      }),
    );

    final database = await CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    ).open();
    addTearDown(database.close);
    final accessEdgeCount = await database.customSelect('''
      SELECT COUNT(*) AS count
      FROM network_edges
      WHERE id IN (
        'entry-sangnoksu-seoul-4',
        'exit-sangnoksu-seoul-4',
        'entry-sadang-seoul-4',
        'exit-sadang-seoul-4'
      )
    ''').getSingle();

    expect(accessEdgeCount.read<int>('count'), 1);
  });

  test(
    'catalog opener는 baseline보다 큰 current pack에 baseline access edge와 fare를 주입하지 않는다',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'easysubway-catalog-current-access-backfill-skip-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final catalogDirectory = Directory('${directory.path}/catalog');
      await catalogDirectory.create(recursive: true);
      final updatedPack = File('${catalogDirectory.path}/capital-v18.sqlite');
      final updatedDatabase = CatalogDatabase.file(updatedPack);
      await updatedDatabase.seedBaselineIfEmpty();
      await updatedDatabase.customStatement('''
      DELETE FROM network_edges
      WHERE edge_type IN ('ENTRY', 'EXIT')
    ''');
      await updatedDatabase
          .into(updatedDatabase.stations)
          .insert(
            StationsCompanion.insert(
              id: 'station-extra',
              nameKo: '추가역',
              normalizedName: '추가역',
            ),
          );
      await updatedDatabase.customStatement('DELETE FROM fare_rules');
      await updatedDatabase.close();
      await File('${catalogDirectory.path}/current.json').writeAsString(
        jsonEncode({
          'id': 'capital',
          'version': '18',
          'path': updatedPack.path,
          'sha256': 'local-fixture',
        }),
      );

      final database = await CatalogDatabaseOpener(
        databaseDirectory: directory,
        assetBundle: rootBundle,
      ).open();
      addTearDown(database.close);
      await database.seedBaselineIfEmpty();
      final accessEdgeCount = await database.customSelect('''
      SELECT COUNT(*) AS count
      FROM network_edges
      WHERE id IN (
        'entry-sangnoksu-seoul-4',
        'exit-sangnoksu-seoul-4',
        'entry-sadang-seoul-4',
        'exit-sadang-seoul-4'
      )
    ''').getSingle();
      final fareRuleCount = await database.customSelect('''
        SELECT COUNT(*) AS count
        FROM fare_rules
      ''').getSingle();
      final route = await LocalRouteRepository(catalogDatabase: database)
          .searchRoute(
            const RouteSearchRequest(
              originStationId: 'station-sangnoksu',
              destinationStationId: 'station-sadang',
              mobilityType: 'WHEELCHAIR',
            ),
          );

      expect(accessEdgeCount.read<int>('count'), 0);
      expect(fareRuleCount.read<int>('count'), 0);
      expect(route.status, 'UNKNOWN');
    },
  );

  test(
    'catalog opener는 이전 컨테이너 경로의 current pointer도 현재 catalog에서 복원한다',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'easysubway-catalog-current-relocated-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final catalogDirectory = Directory('${directory.path}/catalog');
      await catalogDirectory.create(recursive: true);
      final updatedPack = File('${catalogDirectory.path}/capital-v18.sqlite');
      final updatedDatabase = CatalogDatabase.file(updatedPack);
      await updatedDatabase.seedBaselineIfEmpty();
      await updatedDatabase
          .into(updatedDatabase.catalogMetadata)
          .insertOnConflictUpdate(
            CatalogMetadataCompanion.insert(
              key: 'activePack',
              value: 'capital-v18-relocated',
              updatedAt: Value(DateTime.utc(2026, 6, 19, 15)),
            ),
          );
      await updatedDatabase.close();
      await File('${catalogDirectory.path}/current.json').writeAsString(
        jsonEncode({
          'id': 'capital',
          'version': '18',
          'path': '/stale/mobile/container/catalog/capital-v18.sqlite',
          'sha256': 'local-fixture',
        }),
      );

      final database = await CatalogDatabaseOpener(
        databaseDirectory: directory,
        assetBundle: rootBundle,
      ).open();
      addTearDown(database.close);

      final metadata = await database.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'activePack'
          ''').getSingle();

      expect(metadata.read<String>('value'), 'capital-v18-relocated');
    },
  );

  test('catalog opener는 emergency override가 있으면 current보다 우선한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-catalog-override-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = UserDatabase.memory();
    addTearDown(userDatabase.close);
    final overrideRepository = EmergencyOverrideRepository(
      userDatabase: userDatabase,
    );
    await overrideRepository.saveOverride(
      const EmergencyDataPackOverride(
        id: 'capital',
        version: '17',
        reason: '시설 상태 긴급 정정',
      ),
    );
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final overridePack = File('${catalogDirectory.path}/capital-v17.sqlite');
    final currentPack = File('${catalogDirectory.path}/capital-v18.sqlite');
    for (final entry in [
      (file: overridePack, activePack: 'capital-v17'),
      (file: currentPack, activePack: 'capital-v18'),
    ]) {
      final database = CatalogDatabase.file(entry.file);
      await database.seedBaselineIfEmpty();
      if (entry.file == overridePack) {
        await database.customStatement('''
          DELETE FROM network_edges
          WHERE edge_type IN ('ENTRY', 'EXIT')
        ''');
      }
      await database
          .into(database.catalogMetadata)
          .insertOnConflictUpdate(
            CatalogMetadataCompanion.insert(
              key: 'activePack',
              value: entry.activePack,
              updatedAt: Value(DateTime.utc(2026, 6, 19, 14)),
            ),
          );
      await database.close();
    }
    await File('${catalogDirectory.path}/current.json').writeAsString(
      jsonEncode({
        'id': 'capital',
        'version': '18',
        'path': currentPack.path,
        'sha256': 'current-fixture',
      }),
    );

    final database = await CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
      emergencyOverrideRepository: overrideRepository,
    ).open();
    addTearDown(database.close);

    final metadata = await database.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'activePack'
          ''').getSingle();

    expect(metadata.read<String>('value'), 'capital-v17');
    final accessEdgeCount = await database.customSelect('''
          SELECT COUNT(*) AS count
          FROM network_edges
          WHERE id IN (
            'entry-sangnoksu-seoul-4',
            'exit-sangnoksu-seoul-4',
            'entry-sadang-seoul-4',
            'exit-sadang-seoul-4'
          )
          ''').getSingle();
    final route = await LocalRouteRepository(catalogDatabase: database)
        .searchRoute(
          const RouteSearchRequest(
            originStationId: 'station-sangnoksu',
            destinationStationId: 'station-sadang',
            mobilityType: 'WHEELCHAIR',
          ),
        );

    expect(accessEdgeCount.read<int>('count'), 0);
    expect(route.status, 'UNKNOWN');
  });

  test('catalog opener는 current pointer가 없어도 emergency override를 연다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-catalog-override-no-current-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = UserDatabase.memory();
    addTearDown(userDatabase.close);
    final overrideRepository = EmergencyOverrideRepository(
      userDatabase: userDatabase,
    );
    await overrideRepository.saveOverride(
      const EmergencyDataPackOverride(
        id: 'capital',
        version: '17',
        reason: '시설 상태 긴급 정정',
      ),
    );
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final overridePack = File('${catalogDirectory.path}/capital-v17.sqlite');
    final overrideDatabase = CatalogDatabase.file(overridePack);
    await overrideDatabase.seedBaselineIfEmpty();
    await overrideDatabase
        .into(overrideDatabase.catalogMetadata)
        .insertOnConflictUpdate(
          CatalogMetadataCompanion.insert(
            key: 'activePack',
            value: 'capital-v17',
            updatedAt: Value(DateTime.utc(2026, 6, 19, 16)),
          ),
        );
    await overrideDatabase.close();

    final database = await CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
      emergencyOverrideRepository: overrideRepository,
    ).open();
    addTearDown(database.close);

    final metadata = await database.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'activePack'
          ''').getSingle();

    expect(metadata.read<String>('value'), 'capital-v17');
  });

  test('앱 부트스트랩은 데이터팩 업데이트를 기다리지 않고 catalog를 연다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-bootstrap-nonblocking-update-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final updateStarted = Completer<void>();
    final finishUpdate = Completer<void>();
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final updatedPack = File('${catalogDirectory.path}/capital-v19.sqlite');
    final updatedDatabase = CatalogDatabase.file(updatedPack);
    await updatedDatabase.seedBaselineIfEmpty();
    await updatedDatabase
        .into(updatedDatabase.catalogMetadata)
        .insertOnConflictUpdate(
          CatalogMetadataCompanion.insert(
            key: 'activePack',
            value: 'capital-v19',
            updatedAt: Value(DateTime.utc(2026, 6, 19, 13)),
          ),
        );
    await updatedDatabase.close();

    AppBootstrap? bootstrap;
    addTearDown(() => bootstrap?.close());
    final bootstrapFuture = AppBootstrap.initialize(
      databaseDirectory: directory,
      assetBundle: rootBundle,
      dataPackUpdateRunner:
          ({
            required supportDirectory,
            required userDatabase,
            required trigger,
          }) async {
            updateStarted.complete();
            await finishUpdate.future;
            await File('${catalogDirectory.path}/current.json').writeAsString(
              jsonEncode({
                'id': 'capital',
                'version': '19',
                'path': updatedPack.path,
                'sha256': sha256
                    .convert(await updatedPack.readAsBytes())
                    .toString(),
              }),
            );
          },
      enablePushNotifications: false,
    );
    bootstrap = await bootstrapFuture.timeout(const Duration(seconds: 5));
    await updateStarted.future.timeout(const Duration(seconds: 5));
    expect(finishUpdate.isCompleted, isFalse);

    final metadata = await bootstrap.catalogDatabase.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'schemaVersion'
          ''').getSingle();

    expect(metadata.read<String>('value'), '1');
    finishUpdate.complete();
    await bootstrap.dataPackUpdate;

    final sessionRouteDatabase =
        bootstrap.localRouteRepository!.catalogDatabase;
    final activePack = await sessionRouteDatabase.customSelect('''
      SELECT value FROM catalog_metadata WHERE key = 'activePack'
      ''').getSingle();
    expect(activePack.read<String>('value'), 'capital');
  });

  test('앱 부트스트랩은 설치된 current pack의 manifest expiry를 stale 상태로 전달한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-bootstrap-installed-stale-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final installedPack = File('${catalogDirectory.path}/capital-v20.sqlite');
    final installedDatabase = CatalogDatabase.file(installedPack);
    await installedDatabase.seedBaselineIfEmpty();
    await installedDatabase.close();
    await File('${catalogDirectory.path}/current.json').writeAsString(
      jsonEncode({
        'id': 'capital',
        'version': '20',
        'path': installedPack.path,
        'sha256': sha256.convert(await installedPack.readAsBytes()).toString(),
      }),
    );
    final userDatabase = await UserDatabaseOpener(
      databaseDirectory: Directory('${directory.path}/user'),
    ).open();
    await DataPackUpdateStateRepository(
      userDatabase: userDatabase,
    ).saveManifestCache(
      etag: 'installed-v20',
      checkedAt: DateTime.utc(2000, 1, 1),
      ttl: const Duration(hours: 1),
      expiresAt: DateTime.utc(2000, 1, 2),
    );
    await userDatabase.close();

    final bootstrap = await AppBootstrap.initialize(
      databaseDirectory: directory,
      assetBundle: rootBundle,
      dataPackUpdateRunner:
          ({
            required supportDirectory,
            required userDatabase,
            required trigger,
          }) async {},
      enablePushNotifications: false,
    );
    addTearDown(bootstrap.close);

    expect(bootstrap.bundledDataPackFreshness, isA<BundledDataPackFreshness>());
    expect(
      bootstrap.bundledDataPackFreshness!.reasonCode,
      'PACK_PUBLISH_FRESHNESS_EXPIRED',
    );
    expect(
      bootstrap.bundledDataPackFreshness!.isStaleAt(DateTime.now()),
      isTrue,
    );
  });

  test('앱 부트스트랩은 시작과 resume 데이터팩 update trigger를 구분한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-bootstrap-update-trigger-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final triggers = <UpdateTrigger>[];

    AppBootstrap? bootstrap;
    addTearDown(() => bootstrap?.close());
    bootstrap = await AppBootstrap.initialize(
      databaseDirectory: directory,
      assetBundle: rootBundle,
      dataPackUpdateRunner:
          ({
            required supportDirectory,
            required userDatabase,
            required trigger,
          }) async {
            triggers.add(trigger);
          },
      enablePushNotifications: false,
    );
    await bootstrap.dataPackUpdate;
    await bootstrap.resumeDataPackUpdate();

    expect(triggers, [UpdateTrigger.appStart, UpdateTrigger.foregroundResume]);
  });

  test(
    'catalog opener는 current pointer가 깨지면 최신 known-good pack으로 복구한다',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'easysubway-catalog-known-good-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final catalogDirectory = Directory('${directory.path}/catalog');
      await catalogDirectory.create(recursive: true);
      final stalePack = File('${catalogDirectory.path}/capital-v17.sqlite');
      await stalePack.writeAsString('missing current target');
      final knownGoodPack = File('${catalogDirectory.path}/capital-v18.sqlite');
      final knownGoodDatabase = CatalogDatabase.file(knownGoodPack);
      await knownGoodDatabase.seedBaselineIfEmpty();
      await knownGoodDatabase
          .into(knownGoodDatabase.catalogMetadata)
          .insertOnConflictUpdate(
            CatalogMetadataCompanion.insert(
              key: 'activePack',
              value: 'capital-v18',
              updatedAt: Value(DateTime.utc(2026, 6, 19, 14)),
            ),
          );
      await knownGoodDatabase.close();
      await File('${catalogDirectory.path}/current.json').writeAsString(
        jsonEncode({
          'id': 'capital',
          'version': '19',
          'path': '${catalogDirectory.path}/capital-v19.sqlite',
          'sha256': 'missing',
        }),
      );

      final database = await CatalogDatabaseOpener(
        databaseDirectory: directory,
        assetBundle: rootBundle,
      ).open();
      addTearDown(database.close);

      final metadata = await database.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'activePack'
          ''').getSingle();

      expect(metadata.read<String>('value'), 'capital-v18');
    },
  );

  test(
    'catalog opener는 current id와 같은 known-good pack만 fallback으로 연다',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'easysubway-catalog-known-good-same-id-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final catalogDirectory = Directory('${directory.path}/catalog');
      await catalogDirectory.create(recursive: true);
      for (final entry in [
        (
          file: File('${catalogDirectory.path}/common-v99.sqlite'),
          activePack: 'common-v99',
        ),
        (
          file: File('${catalogDirectory.path}/capital-v18.sqlite'),
          activePack: 'capital-v18',
        ),
      ]) {
        final database = CatalogDatabase.file(entry.file);
        await database.seedBaselineIfEmpty();
        await database
            .into(database.catalogMetadata)
            .insertOnConflictUpdate(
              CatalogMetadataCompanion.insert(
                key: 'activePack',
                value: entry.activePack,
                updatedAt: Value(DateTime.utc(2026, 6, 19, 14)),
              ),
            );
        await database.close();
      }
      await File('${catalogDirectory.path}/current.json').writeAsString(
        jsonEncode({
          'id': 'capital',
          'version': '19',
          'path': '${catalogDirectory.path}/capital-v19.sqlite',
          'sha256': 'missing',
        }),
      );

      final database = await CatalogDatabaseOpener(
        databaseDirectory: directory,
        assetBundle: rootBundle,
      ).open();
      addTearDown(database.close);

      final metadata = await database.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'activePack'
          ''').getSingle();

      expect(metadata.read<String>('value'), 'capital-v18');
    },
  );

  test('catalog opener는 rollback pointer보다 최신 pack으로 fallback하지 않는다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-catalog-known-good-version-bound-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    for (final entry in [
      (
        file: File('${catalogDirectory.path}/capital-v17.sqlite'),
        activePack: 'capital-v17',
      ),
      (
        file: File('${catalogDirectory.path}/capital-v19.sqlite'),
        activePack: 'capital-v19',
      ),
    ]) {
      final database = CatalogDatabase.file(entry.file);
      await database.seedBaselineIfEmpty();
      await database
          .into(database.catalogMetadata)
          .insertOnConflictUpdate(
            CatalogMetadataCompanion.insert(
              key: 'activePack',
              value: entry.activePack,
              updatedAt: Value(DateTime.utc(2026, 6, 19, 14)),
            ),
          );
      await database.close();
    }
    await File('${catalogDirectory.path}/current.json').writeAsString(
      jsonEncode({
        'id': 'capital',
        'version': '18',
        'path': '${catalogDirectory.path}/capital-v18.sqlite',
        'sha256': 'missing',
      }),
    );

    final database = await CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    ).open();
    addTearDown(database.close);

    final metadata = await database.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'activePack'
          ''').getSingle();

    expect(metadata.read<String>('value'), 'capital-v17');
  });

  test('catalog opener는 설치 journal을 복구한 뒤 current pack을 연다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-catalog-journal-recovery-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final targetPack = File('${catalogDirectory.path}/capital-v19.sqlite');
    final database = CatalogDatabase.file(targetPack);
    await database.seedBaselineIfEmpty();
    await database
        .into(database.catalogMetadata)
        .insertOnConflictUpdate(
          CatalogMetadataCompanion.insert(
            key: 'activePack',
            value: 'capital-v19',
            updatedAt: Value(DateTime.utc(2026, 6, 19, 14)),
          ),
        );
    await database.close();
    await File(
      '${catalogDirectory.path}/current.json.installing',
    ).writeAsString(
      jsonEncode({
        'id': 'capital',
        'version': '19',
        'path': targetPack.path,
        'sha256': sha256.convert(await targetPack.readAsBytes()).toString(),
      }),
      flush: true,
    );

    final opened = await CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    ).open();
    addTearDown(opened.close);

    final metadata = await opened.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'activePack'
          ''').getSingle();

    expect(metadata.read<String>('value'), 'capital-v19');
    expect(
      await File('${catalogDirectory.path}/current.json').exists(),
      isTrue,
    );
    expect(
      await File('${catalogDirectory.path}/current.json.installing').exists(),
      isFalse,
    );
  });

  test(
    'catalog opener는 malformed current에서 다른 id pack으로 fallback하지 않는다',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'easysubway-catalog-malformed-current-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final catalogDirectory = Directory('${directory.path}/catalog');
      await catalogDirectory.create(recursive: true);
      final otherPack = File('${catalogDirectory.path}/common-v99.sqlite');
      final otherDatabase = CatalogDatabase.file(otherPack);
      await otherDatabase.seedBaselineIfEmpty();
      await otherDatabase
          .into(otherDatabase.catalogMetadata)
          .insertOnConflictUpdate(
            CatalogMetadataCompanion.insert(
              key: 'activePack',
              value: 'common-v99',
              updatedAt: Value(DateTime.utc(2026, 6, 19, 14)),
            ),
          );
      await otherDatabase.close();
      await File(
        '${catalogDirectory.path}/current.json',
      ).writeAsString(jsonEncode(['not-a-pointer']));

      final database = await CatalogDatabaseOpener(
        databaseDirectory: directory,
        assetBundle: rootBundle,
      ).open();
      addTearDown(database.close);

      final metadata = await database.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'activePack'
          ''').getSingleOrNull();

      expect(metadata?.read<String>('value'), isNot('common-v99'));
    },
  );

  test('앱 부트스트랩은 데이터팩 업데이트 실패 시 내장 catalog로 계속 시작한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-bootstrap-update-failure-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final reports = <FlutterErrorDetails>[];

    AppBootstrap? bootstrap;
    addTearDown(() => bootstrap?.close());
    bootstrap = await runWithMobileErrorReporter(
      reports.add,
      () => AppBootstrap.initialize(
        databaseDirectory: directory,
        assetBundle: rootBundle,
        dataPackUpdateRunner:
            ({
              required supportDirectory,
              required userDatabase,
              required trigger,
            }) async {
              throw const SocketException('manifest unavailable');
            },
        enablePushNotifications: false,
      ),
    );

    final metadata = await bootstrap!.catalogDatabase.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'schemaVersion'
          ''').getSingle();

    expect(metadata.read<String>('value'), '1');
    expect(reports, hasLength(1));
    expect(
      reports.single.context.toString(),
      contains('이동 정보 업데이트 확인 중 예외가 발생했습니다.'),
    );
  });

  test('앱 부트스트랩은 API와 데이터팩 base가 없어도 HTTP request를 열지 않는다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-bootstrap-no-network-',
    );
    addTearDown(() => directory.delete(recursive: true));
    var httpRequestCount = 0;

    AppBootstrap? bootstrap;
    addTearDown(() => bootstrap?.close());
    bootstrap = await HttpOverrides.runZoned(
      () => AppBootstrap.initialize(
        databaseDirectory: directory,
        assetBundle: rootBundle,
        enablePushNotifications: false,
      ),
      createHttpClient: (context) {
        return _RequestCountingHttpClient(() {
          httpRequestCount++;
        });
      },
    );

    final metadata = await bootstrap!.catalogDatabase.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'schemaVersion'
          ''').getSingle();

    expect(metadata.read<String>('value'), '1');
    expect(httpRequestCount, 0);
  });

  test('user DB는 catalog 데이터팩 교체와 독립적으로 즐겨찾기와 신고 receipt를 보존한다', () async {
    final directory = await Directory.systemTemp.createTemp('easysubway-user-');
    addTearDown(() => directory.delete(recursive: true));

    final first = await UserDatabaseOpener(databaseDirectory: directory).open();
    await first
        .into(first.favoriteStations)
        .insert(
          FavoriteStationsCompanion.insert(
            stationId: 'station-sangnoksu',
            addedAt: DateTime.parse('2026-06-19T10:00:00Z'),
          ),
        );
    await first
        .into(first.reportReceipts)
        .insert(
          ReportReceiptsCompanion.insert(
            receiptId: 'receipt-1',
            reportId: const Value('report-1'),
            status: 'RECEIVED',
            createdAt: DateTime.parse('2026-06-19T10:05:00Z'),
          ),
        );
    await first.close();

    final catalogFile = File('${directory.path}/datapacks/capital.sqlite');
    await catalogFile.create(recursive: true);
    await catalogFile.writeAsString('replaced catalog pack');

    final reopened = await UserDatabaseOpener(
      databaseDirectory: directory,
    ).open();
    addTearDown(reopened.close);

    final favorites = await reopened.select(reopened.favoriteStations).get();
    final receipts = await reopened.select(reopened.reportReceipts).get();

    expect(favorites, hasLength(1));
    expect(favorites.single.stationId, 'station-sangnoksu');
    expect(receipts, hasLength(1));
    expect(receipts.single.receiptId, 'receipt-1');
    expect(receipts.single.reportId, 'report-1');
    expect(receipts.single.status, 'RECEIVED');
  });

  test('user DB migration은 v1 사용자 데이터를 현재 schema로 보존한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-user-migration-',
    );
    addTearDown(() => directory.delete(recursive: true));

    final strategyDatabase = UserDatabase.memory();
    final strategy = strategyDatabase.migration;
    expect(strategy.beforeOpen, isNot(equals(null)));
    expect(strategy.onUpgrade, isNot(equals(null)));
    await strategyDatabase.close();

    final first = await UserDatabaseOpener(databaseDirectory: directory).open();
    await first
        .into(first.favoriteStations)
        .insert(
          FavoriteStationsCompanion.insert(
            stationId: 'station-sangnoksu',
            addedAt: DateTime.parse('2026-06-19T10:00:00Z'),
          ),
        );
    await first
        .into(first.searchHistory)
        .insert(
          SearchHistoryCompanion.insert(
            query: '상록수',
            searchedAt: DateTime.parse('2026-06-19T10:01:00Z'),
          ),
        );
    await first
        .into(first.reportReceipts)
        .insert(
          ReportReceiptsCompanion.insert(
            receiptId: 'receipt-migration-1',
            reportId: const Value('report-migration-1'),
            status: 'RECEIVED',
            createdAt: DateTime.parse('2026-06-19T10:05:00Z'),
          ),
        );
    await first.close();

    final reopened = await UserDatabaseOpener(
      databaseDirectory: directory,
    ).open();
    addTearDown(reopened.close);

    final favorites = await reopened.select(reopened.favoriteStations).get();
    final searchRows = await reopened
        .customSelect(
          'SELECT query FROM search_history ORDER BY searched_at DESC',
        )
        .get();
    final receipts = await reopened.select(reopened.reportReceipts).get();

    expect(favorites.single.stationId, 'station-sangnoksu');
    expect(searchRows.single.read<String>('query'), '상록수');
    expect(receipts.single.receiptId, 'receipt-migration-1');
    expect(receipts.single.reportId, 'report-migration-1');
  });

  test('user DB migration은 schema 2 → 3에서 region 컬럼·route_search_history를 만들고 '
      'region 없는 레거시 행을 정리한다(#2419)', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-user-v2-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/user.sqlite');
    final legacy = sqlite.sqlite3.open(file.path);
    legacy.execute('''
        CREATE TABLE search_history (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          query TEXT NOT NULL,
          searched_at INTEGER NOT NULL
        )
      ''');
    legacy.execute('''
        INSERT INTO search_history (query, searched_at)
        VALUES ('상록수', 1750320060)
      ''');
    legacy.execute('PRAGMA user_version = 2');
    legacy.close();

    final database = UserDatabase.file(file);
    addTearDown(database.close);

    final searchHistoryColumns = await database
        .customSelect('PRAGMA table_info(search_history)')
        .get();
    final routeSearchHistoryTable = await database.customSelect('''
        SELECT name FROM sqlite_master
        WHERE type = 'table' AND name = 'route_search_history'
      ''').get();
    final remainingSearchHistory = await database
        .customSelect('SELECT COUNT(*) AS count FROM search_history')
        .getSingle();

    expect(
      searchHistoryColumns.map((row) => row.read<String>('name')),
      contains('region'),
    );
    expect(routeSearchHistoryTable, hasLength(1));
    // v2에는 region 개념이 없어 ALTER 직후 기존 행은 모두 region이 비고,
    // v3 onUpgrade가 이를 마이그레이션 시점에 정리한다.
    expect(remainingSearchHistory.read<int>('count'), 0);
  });
}

final class _CloseTrackingCatalogDatabase extends CatalogDatabase {
  _CloseTrackingCatalogDatabase() : super(NativeDatabase.memory());

  var closeCount = 0;

  @override
  Future<void> close() async {
    closeCount += 1;
    await super.close();
  }
}

final class _CloseTrackingUserDatabase extends UserDatabase {
  _CloseTrackingUserDatabase() : super(NativeDatabase.memory());

  var closeCount = 0;

  @override
  Future<void> close() async {
    closeCount += 1;
    await super.close();
  }
}

final class _AlwaysCloseFailingLocalRouteRepository
    extends LocalRouteRepository {
  _AlwaysCloseFailingLocalRouteRepository(CatalogDatabase catalogDatabase)
    : super(catalogDatabase: catalogDatabase);

  @override
  Future<void> close() async {
    throw StateError('route repository close failed');
  }
}

class _RequestCountingHttpClient implements HttpClient {
  _RequestCountingHttpClient(this.onRequest);

  final void Function() onRequest;

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    onRequest();
    throw StateError('startup must not open HTTP request: $method $url');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
