import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'user_tables.dart';

part 'user_database.g.dart';

/// 지원하지 않는 스키마 버전을 만났을 때 던지는 오류 문구의 고정 접두사.
///
/// `UserDatabaseOpener`가 이 실패를 "DB 내용 결함"으로 분류하는 데 쓴다.
/// isolate 경계를 넘으면 예외 타입이 사라질 수 있어 타입 대신 문구로 판별한다.
const unsupportedUserDatabaseSchemaVersionMarker =
    'easysubway user database: unsupported schema version';

/// 파일 DB 연결 설정. isolate로 전달되므로 최상위 함수여야 한다.
void _setUpUserDatabaseConnection(sqlite.Database database) {
  // user.db는 foreground와 WorkManager isolate(홈 위젯·하차 알람)가 같은 경로로
  // 연다. busy timeout이 0이면 순간적인 쓰기 락도 즉시 SQLITE_BUSY로 떨어진다.
  database.execute('PRAGMA busy_timeout = 5000');
}

@DriftDatabase(
  tables: [
    FavoriteStations,
    FavoriteFacilities,
    FavoriteRoutes,
    SearchHistory,
    RouteSearchHistory,
    AppPreferences,
    InstalledDataPacks,
    DataPackUpdateState,
    ReportReceipts,
    ReportDrafts,
  ],
)
/// Enforces the user-data preservation contract.
///
/// App updates and catalog pack swaps must preserve favorites, search history,
/// report receipts, drafts, preferences, and installed-pack audit rows.
///
/// 계약 예외 — region이 없는 레거시 검색 이력은 v3 마이그레이션에서 정리한다
/// (#2419). 지역 필터 목록에 절대 나올 수 없어 보존해도 읽히지 않는 행이고,
/// 매 조회마다 지우던 방식을 마이그레이션 시점 1회로 옮긴 결정의 결과다.
/// 추정 region 백필은 틀린 지역이 필터 결과를 오염시키므로 택하지 않았다(#2546).
///
/// 마이그레이션이 실패해 DB를 열지 못하면 `UserDatabaseOpener`가 원본 파일을
/// 삭제하지 않고 보관한 뒤 보존 우선순위대로 부분 복구한다(#2546).
class UserDatabase extends _$UserDatabase {
  UserDatabase(super.executor);

  factory UserDatabase.file(File file) {
    return UserDatabase(
      NativeDatabase.createInBackground(
        file,
        setup: _setUpUserDatabaseConnection,
      ),
    );
  }

  factory UserDatabase.memory() {
    return UserDatabase(NativeDatabase.memory());
  }

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) async {
        await migrator.createAll();
      },
      onUpgrade: (migrator, from, to) async {
        if (from < 1 || from > to) {
          // downgrade도 drift가 onUpgrade로 보낸다. 걸러내지 않으면 상위 스키마
          // DB가 조용히 v5로 표시된다. 여기서 던지면 열기 실패로 이어져
          // UserDatabaseOpener가 원본을 보관한 뒤 새 DB로 부분 복구한다(#2546).
          throw StateError(
            '$unsupportedUserDatabaseSchemaVersionMarker (from=$from, to=$to)',
          );
        }
        // drift는 onUpgrade를 트랜잭션으로 감싸지 않는다. 전 단계를 한
        // 트랜잭션으로 묶어 어느 문장에서 실패하든 원본 스키마와 행이 그대로
        // 남게 한다. SQLite는 DDL도 트랜잭션 대상이라 CREATE·DROP·RENAME까지
        // 되돌아간다(#2546).
        await transaction(() async {
          await _upgradeFrom(migrator, from);
        });
      },
      beforeOpen: (_) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _upgradeFrom(Migrator migrator, int from) async {
    if (from < 2) {
      await _addColumnIfTableExists(
        'report_receipts',
        'public_receipt_code',
        'TEXT',
      );
    }
    if (from < 3) {
      if (await _tableExists('search_history')) {
        await _addColumnIfMissing('search_history', 'region', 'TEXT');
        // 지역 없는 레거시 행은 지역 필터 목록에 절대 나올 수 없으므로
        // 마이그레이션 시점에 한 번만 정리한다(#2419: 매 조회마다 지우던
        // 방식은 읽기 경로에 쓰기를 섞어 제거했다).
        await customStatement(
          "DELETE FROM search_history WHERE region IS NULL OR TRIM(region) = ''",
        );
      }
      // route_search_history는 이 단계에서 처음 생긴다. 결손 테이블 생성은
      // 아래 createAll 한 곳에서만 해 raw DDL과 테이블 정의가 갈리지 않게 한다.
    }
    if (from < 4) {
      await _splitFavoriteStationsByLine();
    }
    if (from < 5) {
      // 최근 검색·경로에 "선택한 호선"만 저장해 환승역 전 호선 마크를 막는다.
      for (final column in const [
        'station_id',
        'line_id',
        'line_name',
        'line_color',
        'station_code',
      ]) {
        await _addColumnIfTableExists('search_history', column, 'TEXT');
      }
      for (final column in const [
        'origin_line_id',
        'origin_line_name',
        'origin_line_color',
        'origin_station_code',
        'waypoint_line_id',
        'waypoint_line_name',
        'waypoint_line_color',
        'waypoint_station_code',
        'destination_line_id',
        'destination_line_name',
        'destination_line_color',
        'destination_station_code',
      ]) {
        await _addColumnIfTableExists('route_search_history', column, 'TEXT');
      }
    }
    // 위 단계가 건너뛴 결손 테이블을 현재 정의로 만든다. drift가
    // `CREATE TABLE IF NOT EXISTS`를 쓰므로 이미 있는 테이블은 이름만 보고
    // 건너뛴다 — 보장 범위는 "테이블 통째 결손"까지다. 마이그레이션이 손대지
    // 않는 테이블에 컬럼만 빠져 있는 경우는 여기서 교정되지 않는다(#2546).
    await migrator.createAll();
  }

  /// v4 즐겨찾기 역 분리. 기존 행은 `line_id=''`(역 전체)로 옮긴다.
  ///
  /// `DROP`과 `RENAME` 사이에서 실패하면 즐겨찾기 역이 통째로 사라지므로
  /// 재작성 4문장은 반드시 원자적이어야 한다. 원자성은 [migration]의 onUpgrade
  /// 트랜잭션이 보장한다(#2546).
  ///
  /// 원자성이 없던 구 코드에서 중단된 설치본은 `favorite_stations_v4` 잔재를
  /// 남겼을 수 있다. 두 잔재 상태를 모두 여기서 정리한다.
  Future<void> _splitFavoriteStationsByLine() async {
    final hasLeftoverRewrite = await _tableExists('favorite_stations_v4');
    if (!await _tableExists('favorite_stations')) {
      if (hasLeftoverRewrite) {
        // 구 코드가 DROP과 RENAME 사이에서 멈춘 설치본. 남은 재작성 테이블을
        // 인수해 즐겨찾기를 회수한다. 인수하지 않으면 아래 createAll이 빈
        // 테이블을 만들어 유실이 확정된다.
        await customStatement(
          'ALTER TABLE favorite_stations_v4 RENAME TO favorite_stations',
        );
        return;
      }
      // schema 2→3 최소 fixture처럼 favorite_stations가 없을 수 있다.
      // 결손 테이블은 onUpgrade 끝의 createAll이 현재 정의로 만든다.
      return;
    }
    if (await _columnExists('favorite_stations', 'line_id')) {
      // 이 단계까지 마치고 뒤 단계에서 실패해 user_version이 안 오른 DB.
      // 다시 재작성하면 호선별 즐겨찾기가 역 전체로 되돌아가므로 건너뛴다.
      return;
    }
    if (hasLeftoverRewrite) {
      // 구 코드가 CREATE·INSERT까지만 하고 멈춘 설치본. 잔재는 원본
      // favorite_stations의 부분 사본이라 버려도 손실이 없고, 그대로 두면
      // 아래 CREATE가 `table already exists`로 던진다.
      await customStatement('DROP TABLE favorite_stations_v4');
    }
    await customStatement('''
      CREATE TABLE favorite_stations_v4 (
        station_id TEXT NOT NULL,
        line_id TEXT NOT NULL DEFAULT '',
        added_at INTEGER NOT NULL,
        PRIMARY KEY (station_id, line_id)
      )
    ''');
    await customStatement('''
      INSERT INTO favorite_stations_v4 (station_id, line_id, added_at)
      SELECT station_id, '', CAST(added_at AS INTEGER)
      FROM favorite_stations
    ''');
    await customStatement('DROP TABLE favorite_stations');
    await customStatement(
      'ALTER TABLE favorite_stations_v4 RENAME TO favorite_stations',
    );
  }

  Future<bool> _tableExists(String tableName) async {
    final table = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable<String>(tableName)],
    ).getSingleOrNull();
    return table != null;
  }

  Future<bool> _columnExists(String tableName, String columnName) async {
    final columns = await customSelect(
      'PRAGMA main.table_info("$tableName")',
    ).get();
    return columns.any((row) => row.read<String>('name') == columnName);
  }

  Future<void> _addColumnIfMissing(
    String tableName,
    String columnName,
    String definition,
  ) async {
    if (await _columnExists(tableName, columnName)) {
      return;
    }
    await customStatement(
      'ALTER TABLE $tableName ADD COLUMN $columnName $definition',
    );
  }

  /// 대상 테이블이 없는 부분 생성 DB에서 `ALTER TABLE`이 던지지 않게 막는다.
  ///
  /// 컬럼 단위로도 확인해 앞선 실행이 중간에 실패한 DB에서 재실행해도
  /// `duplicate column name`으로 깨지지 않는다.
  Future<void> _addColumnIfTableExists(
    String tableName,
    String columnName,
    String definition,
  ) async {
    if (!await _tableExists(tableName)) {
      return;
    }
    await _addColumnIfMissing(tableName, columnName, definition);
  }
}
