import 'package:drift/drift.dart';

import '../../../core/database/user/user_database.dart' as user_db;
import '../../../station_search.dart';

class DriftSearchHistoryRepository implements SearchHistoryRepository {
  DriftSearchHistoryRepository({
    required this.userDatabase,
    this.maxEntries = 10,
  });

  final user_db.UserDatabase userDatabase;
  final int maxEntries;

  @override
  Future<void> recordSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return;
    }

    await userDatabase.transaction(() async {
      await userDatabase.customStatement(
        'DELETE FROM search_history WHERE query = ?',
        [trimmed],
      );
      await userDatabase
          .into(userDatabase.searchHistory)
          .insert(
            user_db.SearchHistoryCompanion.insert(
              query: trimmed,
              searchedAt: DateTime.now().toUtc(),
            ),
          );
      await userDatabase.customStatement(
        '''
        DELETE FROM search_history
        WHERE id NOT IN (
          SELECT id
          FROM search_history
          ORDER BY searched_at DESC, id DESC
          LIMIT ?
        )
        ''',
        [maxEntries],
      );
    });
  }

  @override
  Future<List<String>> listRecentQueries() async {
    final rows = await userDatabase
        .customSelect(
          '''
          SELECT query
          FROM search_history
          ORDER BY searched_at DESC, id DESC
          LIMIT ?
          ''',
          variables: [Variable.withInt(maxEntries)],
          readsFrom: {userDatabase.searchHistory},
        )
        .get();
    return rows.map((row) => row.read<String>('query')).toList(growable: false);
  }
}
