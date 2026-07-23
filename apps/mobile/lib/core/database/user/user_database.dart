import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'user_tables.dart';

part 'user_database.g.dart';

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
class UserDatabase extends _$UserDatabase {
  UserDatabase(super.executor);

  factory UserDatabase.file(File file) {
    return UserDatabase(NativeDatabase.createInBackground(file));
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
      onUpgrade: (_, from, to) async {
        if (from < 1) {
          throw StateError('Unsupported user database schema version: $from');
        }
        if (from < 2) {
          await customStatement(
            'ALTER TABLE report_receipts ADD COLUMN public_receipt_code TEXT',
          );
        }
        if (from < 3) {
          await customStatement(
            'ALTER TABLE search_history ADD COLUMN region TEXT',
          );
          // 지역 없는 레거시 행은 지역 필터 목록에 절대 나올 수 없으므로
          // 마이그레이션 시점에 한 번만 정리한다(#2419: 매 조회마다 지우던
          // 방식은 읽기 경로에 쓰기를 섞어 제거했다).
          await customStatement(
            "DELETE FROM search_history WHERE region IS NULL OR TRIM(region) = ''",
          );
          await customStatement('''
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
          ''');
        }
        if (from < 4) {
          // 즐겨찾기 역을 호선+역 단위로 분리한다. 기존 행은 line_id=''(역 전체).
          // schema 2→3 최소 fixture처럼 favorite_stations가 없을 수 있다.
          final existingFavoriteStations = await customSelect('''
            SELECT name FROM sqlite_master
            WHERE type = 'table' AND name = 'favorite_stations'
          ''').get();
          if (existingFavoriteStations.isEmpty) {
            await customStatement('''
              CREATE TABLE favorite_stations (
                station_id TEXT NOT NULL,
                line_id TEXT NOT NULL DEFAULT '',
                added_at INTEGER NOT NULL,
                PRIMARY KEY (station_id, line_id)
              )
            ''');
          } else {
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
        }
        if (from < 5) {
          // 최근 검색·경로에 "선택한 호선"만 저장해 환승역 전 호선 마크를 막는다.
          await customStatement(
            'ALTER TABLE search_history ADD COLUMN station_id TEXT',
          );
          await customStatement(
            'ALTER TABLE search_history ADD COLUMN line_id TEXT',
          );
          await customStatement(
            'ALTER TABLE search_history ADD COLUMN line_name TEXT',
          );
          await customStatement(
            'ALTER TABLE search_history ADD COLUMN line_color TEXT',
          );
          await customStatement(
            'ALTER TABLE search_history ADD COLUMN station_code TEXT',
          );
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
            await customStatement(
              'ALTER TABLE route_search_history ADD COLUMN $column TEXT',
            );
          }
        }
      },
      beforeOpen: (_) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }
}
