import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/features/stations/data/drift_station_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// wall-clock을 assert하지 않는다. 로그는 Stage 0/재측정 근거용이다.
void main() {
  test('검색 warm 경로 대표 질의 소요시간을 기록한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();

    final buffer = StringBuffer();
    for (var i = 0; i < 800; i++) {
      if (i > 0) {
        buffer.write(', ');
      }
      final syllable = String.fromCharCode(0xAC00 + (i % 11172));
      final name = '$syllable역$i';
      buffer.write(
        "('station-perf-$i', '$name', 'En$i', '', '$name', "
        "'수도권', 'LEVEL_1', 'OFFICIAL_FILE')",
      );
    }
    await database.customStatement(
      "INSERT INTO stations "
      "(id, name_ko, name_en, name_sub, normalized_name, region, "
      "data_quality_level, data_source_type) "
      "VALUES ${buffer.toString()}",
    );

    final repository = DriftStationRepository(database: database);
    final warmSw = Stopwatch()..start();
    await repository.warmSearchCache();
    warmSw.stop();

    Future<int> micros(String query) async {
      final samples = <int>[];
      for (var i = 0; i < 8; i++) {
        final sw = Stopwatch()..start();
        await repository.searchStations(query);
        sw.stop();
        samples.add(sw.elapsedMicroseconds);
      }
      samples.sort();
      return samples[samples.length ~/ 2];
    }

    final queries = ['ㅅ', 'ㅅㅂ', '상', '상록', 'sang', '없는역xyz'];
    final lines = <String>['warm_index_build_us=${warmSw.elapsedMicroseconds}'];
    for (final query in queries) {
      final medianUs = await micros(query);
      lines.add('query=$query median_us=$medianUs');
    }

    // ignore: avoid_print
    print('EASY_SUBWAY_SEARCH_BENCH ${lines.join(' | ')}');
    expect(lines, isNotEmpty);
  });
}
