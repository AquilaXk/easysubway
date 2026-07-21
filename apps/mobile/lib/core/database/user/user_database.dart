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
  int get schemaVersion => 3;

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
      },
      beforeOpen: (_) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }
}
