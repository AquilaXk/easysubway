import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/core/database/catalog/catalog_database_opener.dart';
import 'package:easysubway_mobile/features/routes/data/local_route_repository.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _warmupCount = 5;
const _repetitionCount = 40;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('실기기 local route search snapshot cache latency', (_) async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-route-search-benchmark-',
    );
    final database = await CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    ).open();
    try {
      final index =
          jsonDecode(await rootBundle.loadString('assets/datapacks/index.json'))
              as Map<String, Object?>;
      final packs = index['packs']! as List<Object?>;
      final capital = packs.cast<Map<String, Object?>>().singleWhere(
        (pack) => pack['id'] == 'capital',
      );
      final repository = LocalRouteRepository(catalogDatabase: database);
      const request = RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'STANDARD',
      );

      debugPrint(
        'ISSUE2253_METADATA '
        'pack_id=capital sqlite_sha256=${capital['sqliteSha256']} '
        'warmup=$_warmupCount repetitions=$_repetitionCount mode=profile',
      );
      for (var index = 0; index < _warmupCount; index += 1) {
        final result = await repository.searchRoute(request);
        expect(result.status, 'FOUND');
      }

      final samples = <int>[];
      for (var index = 0; index < _repetitionCount; index += 1) {
        final stopwatch = Stopwatch()..start();
        final result = await repository.searchRoute(request);
        stopwatch.stop();
        expect(result.status, 'FOUND');
        samples.add(stopwatch.elapsedMicroseconds);
        debugPrint(
          'ISSUE2253_SAMPLE index=$index elapsed_us=${stopwatch.elapsedMicroseconds}',
        );
      }
      final sorted = samples.toList()..sort();
      debugPrint(
        'ISSUE2253_SUMMARY repetitions=$_repetitionCount '
        'p50_us=${_percentile(sorted, 0.50)} '
        'p95_us=${_percentile(sorted, 0.95)} max_us=${sorted.last}',
      );
    } finally {
      await database.close();
      await directory.delete(recursive: true);
    }
  });
}

int _percentile(List<int> sorted, double percentile) {
  final index = (sorted.length * percentile).ceil() - 1;
  return sorted[index.clamp(0, sorted.length - 1)];
}
