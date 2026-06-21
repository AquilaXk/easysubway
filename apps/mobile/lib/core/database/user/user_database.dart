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
  int get schemaVersion => 1;

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
      },
      beforeOpen: (_) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }
}
