import 'dart:io';

import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/features/routes/data/local_route_repository.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('번들 수도권 팩은 흡수 ID로도 노선 선택 없이 대표 OD를 탐색한다', () async {
    final directory = Directory.systemTemp.createTempSync(
      'canonical-station-pack-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final sqlite = File('${directory.path}/capital.sqlite')
      ..writeAsBytesSync(
        gzip.decode(
          File('assets/datapacks/capital.sqlite.gz').readAsBytesSync(),
        ),
      );
    final database = CatalogDatabase.file(sqlite);
    addTearDown(database.close);
    final repository = LocalRouteRepository(catalogDatabase: database);

    for (final request in const [
      RouteSearchRequest(
        originStationId: 'station-f4a450b35d91',
        destinationStationId: 'station-37866f28b417',
        mobilityType: 'STANDARD',
      ),
      RouteSearchRequest(
        originStationId: 'station-37866f28b417',
        destinationStationId: 'station-7423a5270c95',
        mobilityType: 'STANDARD',
      ),
      RouteSearchRequest(
        originStationId: 'station-7423a5270c95',
        destinationStationId: 'station-2af75c3d707b',
        mobilityType: 'STANDARD',
      ),
    ]) {
      final result = await repository.searchRoute(request);
      expect(result.status, 'FOUND', reason: request.toString());
      expect(result.originStationId, isNot(request.originStationId));
    }
  });
}
