import 'dart:io';

import 'package:drift/native.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database_opener.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// `@DriftDatabase`가 선언한 사용자 테이블 전체.
const _declaredTables = <String>[
  'favorite_stations',
  'favorite_facilities',
  'favorite_routes',
  'search_history',
  'route_search_history',
  'app_preferences',
  'installed_data_packs',
  'data_pack_update_state',
  'report_receipts',
  'report_drafts',
];

const _legacyFavoriteStationsBeforeV4 = '''
  CREATE TABLE favorite_stations (
    station_id TEXT NOT NULL PRIMARY KEY,
    added_at INTEGER NOT NULL
  )
''';

const _legacyFavoriteStationsFromV4 = '''
  CREATE TABLE favorite_stations (
    station_id TEXT NOT NULL,
    line_id TEXT NOT NULL DEFAULT '',
    added_at INTEGER NOT NULL,
    PRIMARY KEY (station_id, line_id)
  )
''';

const _legacySearchHistoryBeforeV3 = '''
  CREATE TABLE search_history (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    query TEXT NOT NULL,
    searched_at INTEGER NOT NULL
  )
''';

const _legacySearchHistoryFromV3 = '''
  CREATE TABLE search_history (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    query TEXT NOT NULL,
    region TEXT,
    searched_at INTEGER NOT NULL
  )
''';

const _legacyRouteSearchHistoryFromV3 = '''
  CREATE TABLE route_search_history (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    origin_station_id TEXT NOT NULL,
    origin_station_name TEXT NOT NULL,
    waypoint_station_id TEXT NULL,
    waypoint_station_name TEXT NULL,
    destination_station_id TEXT NOT NULL,
    destination_station_name TEXT NOT NULL,
    region TEXT NOT NULL,
    searched_at INTEGER NOT NULL
  )
''';

const _legacyReportReceiptsBeforeV2 = '''
  CREATE TABLE report_receipts (
    receipt_id TEXT NOT NULL PRIMARY KEY,
    report_id TEXT,
    status TEXT NOT NULL,
    created_at INTEGER NOT NULL
  )
''';

const _legacyReportReceiptsFromV2 = '''
  CREATE TABLE report_receipts (
    receipt_id TEXT NOT NULL PRIMARY KEY,
    report_id TEXT,
    public_receipt_code TEXT,
    status TEXT NOT NULL,
    created_at INTEGER NOT NULL
  )
''';

const _legacyReportDrafts = '''
  CREATE TABLE report_drafts (
    draft_id TEXT NOT NULL PRIMARY KEY,
    station_id TEXT,
    facility_id TEXT,
    payload_json TEXT NOT NULL,
    updated_at INTEGER NOT NULL
  )
''';

const _legacyAppPreferences = '''
  CREATE TABLE app_preferences (
    key TEXT NOT NULL PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at INTEGER NOT NULL
  )
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('부분 생성 DB: report_receipts가 없어도 v1 사용자 DB가 열린다', () async {
    final file = await _legacyDatabase(
      prefix: 'easysubway-user-guard-receipts-',
      userVersion: 1,
      build: (legacy) {
        legacy.execute(_legacySearchHistoryBeforeV3);
        legacy.execute(
          "INSERT INTO search_history (query, searched_at) VALUES ('상록수', 1750320060)",
        );
        legacy.execute(_legacyFavoriteStationsBeforeV4);
        legacy.execute(
          "INSERT INTO favorite_stations (station_id, added_at) "
          "VALUES ('station-sangnoksu', 1750320000)",
        );
        legacy.execute(_legacyAppPreferences);
        legacy.execute(
          "INSERT INTO app_preferences (key, value, updated_at) "
          "VALUES ('region', '수도권', 1750320000)",
        );
      },
    );

    final database = await _openUserDatabase(file);

    final favorites = await database
        .customSelect('SELECT station_id, line_id FROM favorite_stations')
        .get();
    expect(favorites, hasLength(1));
    expect(favorites.single.read<String>('station_id'), 'station-sangnoksu');
    expect(favorites.single.read<String>('line_id'), '');

    final preferences = await database
        .customSelect('SELECT value FROM app_preferences')
        .get();
    expect(preferences.single.read<String>('value'), '수도권');

    // 결손 테이블은 현재 정의로 생성되어 이후 읽기 경로가 살아 있어야 한다.
    expect(await _tableNames(database), containsAll(_declaredTables));
    expect(await _columnNames(database, 'report_receipts'), <String>{
      'receipt_id',
      'report_id',
      'public_receipt_code',
      'status',
      'created_at',
    });
  });

  test('부분 생성 DB: search_history가 없어도 v2 사용자 DB가 열린다', () async {
    final file = await _legacyDatabase(
      prefix: 'easysubway-user-guard-search-',
      userVersion: 2,
      build: (legacy) {
        legacy.execute(_legacyReportReceiptsFromV2);
        legacy.execute(
          "INSERT INTO report_receipts (receipt_id, report_id, status, created_at) "
          "VALUES ('receipt-1', 'report-1', 'RECEIVED', 1750320300)",
        );
        legacy.execute(_legacyFavoriteStationsBeforeV4);
        legacy.execute(
          "INSERT INTO favorite_stations (station_id, added_at) "
          "VALUES ('station-sadang', 1750320000)",
        );
      },
    );

    final database = await _openUserDatabase(file);

    final receipts = await database
        .customSelect('SELECT receipt_id FROM report_receipts')
        .get();
    expect(receipts.single.read<String>('receipt_id'), 'receipt-1');

    final favorites = await database
        .customSelect('SELECT station_id FROM favorite_stations')
        .get();
    expect(favorites.single.read<String>('station_id'), 'station-sadang');

    expect(
      await _columnNames(database, 'search_history'),
      containsAll(<String>['region', 'station_id', 'line_id', 'station_code']),
    );
  });

  test('부분 생성 DB: route_search_history가 없어도 v4 사용자 DB가 열린다', () async {
    final file = await _legacyDatabase(
      prefix: 'easysubway-user-guard-route-',
      userVersion: 4,
      build: (legacy) {
        legacy.execute(_legacySearchHistoryFromV3);
        legacy.execute(
          "INSERT INTO search_history (query, region, searched_at) "
          "VALUES ('상록수', '수도권', 1750320060)",
        );
        legacy.execute(_legacyFavoriteStationsFromV4);
        legacy.execute(
          "INSERT INTO favorite_stations (station_id, line_id, added_at) "
          "VALUES ('station-sangnoksu', 'line-4', 1750320000)",
        );
        legacy.execute(_legacyReportReceiptsFromV2);
      },
    );

    final database = await _openUserDatabase(file);

    final searchRows = await database
        .customSelect('SELECT query, region FROM search_history')
        .get();
    expect(searchRows.single.read<String>('query'), '상록수');
    expect(searchRows.single.read<String>('region'), '수도권');

    final favorites = await database
        .customSelect('SELECT line_id FROM favorite_stations')
        .get();
    expect(favorites.single.read<String>('line_id'), 'line-4');

    expect(
      await _columnNames(database, 'route_search_history'),
      containsAll(<String>[
        'origin_line_id',
        'waypoint_station_code',
        'destination_line_color',
        'region',
      ]),
    );
  });

  test('부분 생성 DB: favorite_stations가 없어도 v3 사용자 DB가 열린다', () async {
    final file = await _legacyDatabase(
      prefix: 'easysubway-user-guard-favorites-',
      userVersion: 3,
      build: (legacy) {
        legacy.execute(_legacySearchHistoryFromV3);
        legacy.execute(
          "INSERT INTO search_history (query, region, searched_at) "
          "VALUES ('사당', '수도권', 1750320060)",
        );
        legacy.execute(_legacyRouteSearchHistoryFromV3);
        legacy.execute(
          "INSERT INTO route_search_history ("
          "origin_station_id, origin_station_name, destination_station_id, "
          "destination_station_name, region, searched_at) "
          "VALUES ('1001', '상록수', '1002', '사당', '수도권', 1750320120)",
        );
        legacy.execute(_legacyReportReceiptsFromV2);
      },
    );

    final database = await _openUserDatabase(file);

    final routeRows = await database
        .customSelect(
          'SELECT origin_station_name, origin_line_id FROM route_search_history',
        )
        .get();
    expect(routeRows.single.read<String>('origin_station_name'), '상록수');
    expect(routeRows.single.read<String?>('origin_line_id'), isNull);

    final searchRows = await database
        .customSelect('SELECT query FROM search_history')
        .get();
    expect(searchRows.single.read<String>('query'), '사당');

    final favorites = await database
        .customSelect('SELECT COUNT(*) AS count FROM favorite_stations')
        .getSingle();
    expect(favorites.read<int>('count'), 0);
  });

  test('부분 생성 DB: 최소 v1 fixture에서도 선언된 사용자 테이블이 모두 만들어진다', () async {
    final file = await _legacyDatabase(
      prefix: 'easysubway-user-guard-minimal-',
      userVersion: 1,
      build: (legacy) {
        legacy.execute(_legacySearchHistoryBeforeV3);
      },
    );

    final database = await _openUserDatabase(file);

    expect(await _tableNames(database), containsAll(_declaredTables));
  });

  test('v4 재작성이 RENAME 직전에 실패해도 원본 favorite_stations가 남는다', () async {
    final file = await _legacyDatabase(
      prefix: 'easysubway-user-atomic-',
      userVersion: 3,
      build: (legacy) {
        legacy.execute(_legacyFavoriteStationsBeforeV4);
        legacy.execute(
          "INSERT INTO favorite_stations (station_id, added_at) VALUES "
          "('station-sangnoksu', 1750320000), ('station-sadang', 1750320060)",
        );
        legacy.execute(_legacySearchHistoryFromV3);
        legacy.execute(_legacyRouteSearchHistoryFromV3);
        legacy.execute(_legacyReportReceiptsFromV2);
      },
    );

    final database = _RenameFailingUserDatabase(file);
    await expectLater(
      database.customSelect('SELECT 1').get(),
      throwsA(isA<Object>()),
    );
    await database.close();

    final raw = sqlite.sqlite3.open(file.path);
    addTearDown(raw.close);
    final tables = raw
        .select(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name LIKE 'favorite_stations%'",
        )
        .map((row) => row['name'] as String)
        .toSet();
    expect(tables, contains('favorite_stations'));
    expect(tables, isNot(contains('favorite_stations_v4')));

    final preserved = raw
        .select('SELECT station_id FROM favorite_stations ORDER BY station_id')
        .map((row) => row['station_id'] as String)
        .toList();
    expect(preserved, <String>['station-sadang', 'station-sangnoksu']);
  });

  test('복구 불가 마이그레이션 실패는 원본을 보관하고 우선순위대로 부분 복구한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-user-recovery-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/user.db');

    final legacy = sqlite.sqlite3.open(file.path);
    // added_at이 없는 favorite_stations는 v4 재작성 INSERT를 실패시킨다.
    legacy.execute('''
      CREATE TABLE favorite_stations (
        station_id TEXT NOT NULL PRIMARY KEY
      )
    ''');
    legacy.execute(
      "INSERT INTO favorite_stations (station_id) VALUES ('station-sangnoksu')",
    );
    legacy.execute(_legacyReportReceiptsBeforeV2);
    legacy.execute(
      "INSERT INTO report_receipts (receipt_id, report_id, status, created_at) "
      "VALUES ('receipt-1', 'report-1', 'RECEIVED', 1750320300)",
    );
    legacy.execute(_legacyReportDrafts);
    legacy.execute(
      "INSERT INTO report_drafts (draft_id, payload_json, updated_at) "
      "VALUES ('draft-1', '{}', 1750320300)",
    );
    legacy.execute(_legacyAppPreferences);
    legacy.execute(
      "INSERT INTO app_preferences (key, value, updated_at) "
      "VALUES ('region', '수도권', 1750320000)",
    );
    legacy.execute(_legacySearchHistoryBeforeV3);
    legacy.execute(
      "INSERT INTO search_history (query, searched_at) VALUES ('상록수', 1750320060)",
    );
    legacy.execute('PRAGMA user_version = 1');
    legacy.close();

    final opener = UserDatabaseOpener(databaseDirectory: directory);
    final database = await opener.open();
    addTearDown(database.close);

    final recovery = opener.lastRecovery;
    expect(recovery, isNotNull);
    expect(recovery!.salvagedTables, <String>[
      'report_receipts',
      'report_drafts',
      'app_preferences',
      'search_history',
    ]);
    expect(recovery.droppedTables, contains('favorite_stations'));

    final receipts = await database
        .customSelect('SELECT receipt_id FROM report_receipts')
        .get();
    expect(receipts.single.read<String>('receipt_id'), 'receipt-1');
    final drafts = await database
        .customSelect('SELECT draft_id FROM report_drafts')
        .get();
    expect(drafts.single.read<String>('draft_id'), 'draft-1');
    final preferences = await database
        .customSelect('SELECT value FROM app_preferences')
        .get();
    expect(preferences.single.read<String>('value'), '수도권');
    final searchRows = await database
        .customSelect('SELECT query FROM search_history')
        .get();
    expect(searchRows.single.read<String>('query'), '상록수');
    final favorites = await database
        .customSelect('SELECT COUNT(*) AS count FROM favorite_stations')
        .getSingle();
    expect(favorites.read<int>('count'), 0);

    // 원본은 삭제하지 않고 보관해 사후 복구 여지를 남긴다.
    final preservedPath = recovery.preservedFilePath;
    expect(preservedPath, isNotNull);
    expect(
      preservedPath,
      startsWith('${directory.path}/${UserDatabaseOpener.preservedFilePrefix}'),
    );
    final preserved = sqlite.sqlite3.open(preservedPath!);
    addTearDown(preserved.close);
    final preservedFavorites = preserved
        .select('SELECT station_id FROM favorite_stations')
        .map((row) => row['station_id'] as String)
        .toList();
    expect(preservedFavorites, <String>['station-sangnoksu']);
    // 실패한 마이그레이션은 통째로 되돌아간다. 보관본은 v1 그대로여야 한다.
    expect(preserved.select('PRAGMA user_version').single['user_version'], 1);
    expect(
      preserved
          .select('PRAGMA table_info(search_history)')
          .map((row) => row['name'] as String),
      isNot(contains('region')),
    );
    expect(
      preserved.select('SELECT COUNT(*) AS c FROM search_history').single['c'],
      1,
    );
  });
}

Future<File> _legacyDatabase({
  required String prefix,
  required int userVersion,
  required void Function(sqlite.Database legacy) build,
}) async {
  final directory = await Directory.systemTemp.createTemp(prefix);
  addTearDown(() => directory.delete(recursive: true));
  final file = File('${directory.path}/user.db');
  final legacy = sqlite.sqlite3.open(file.path);
  build(legacy);
  legacy.execute('PRAGMA user_version = $userVersion');
  legacy.close();
  return file;
}

Future<UserDatabase> _openUserDatabase(File file) async {
  final database = UserDatabase.file(file);
  addTearDown(database.close);
  await database.customSelect('SELECT 1').get();
  return database;
}

Future<Set<String>> _tableNames(UserDatabase database) async {
  final rows = await database
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  return {for (final row in rows) row.read<String>('name')};
}

Future<Set<String>> _columnNames(UserDatabase database, String table) async {
  final rows = await database.customSelect('PRAGMA table_info($table)').get();
  return {for (final row in rows) row.read<String>('name')};
}

/// v4 재작성의 RENAME 직전에 실패를 주입한다.
final class _RenameFailingUserDatabase extends UserDatabase {
  _RenameFailingUserDatabase(File file) : super(NativeDatabase(file));

  @override
  Future<void> customStatement(String statement, [List<dynamic>? args]) async {
    if (statement.contains('RENAME TO favorite_stations')) {
      throw StateError('injected failure before rename');
    }
    return super.customStatement(statement, args);
  }
}
