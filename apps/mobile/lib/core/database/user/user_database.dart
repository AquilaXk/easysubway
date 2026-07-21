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
