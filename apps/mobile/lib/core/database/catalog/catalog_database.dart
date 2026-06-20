import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'catalog_tables.dart';

part 'catalog_database.g.dart';

@DriftDatabase(
  tables: [
    CatalogMetadata,
    Operators,
    Lines,
    Stations,
    StationAliases,
    StationLines,
    NetworkEdges,
    StationExits,
    Facilities,
    StationAccessibilitySummaries,
    InternalRouteNodes,
    InternalRouteEdges,
    DataQualityRecords,
  ],
)
class CatalogDatabase extends _$CatalogDatabase {
  CatalogDatabase(super.executor);

  factory CatalogDatabase.file(File file) {
    return CatalogDatabase(NativeDatabase.createInBackground(file));
  }

  factory CatalogDatabase.memory() {
    return CatalogDatabase(NativeDatabase.memory());
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) async {
        await migrator.createAll();
        await _createIndexes();
      },
      beforeOpen: (_) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> seedBaselineIfEmpty() async {
    final existing = await customSelect(
      "SELECT value FROM catalog_metadata WHERE key = 'schemaVersion'",
    ).getSingleOrNull();
    if (existing != null) {
      return;
    }

    await transaction(() async {
      await batch((batch) {
        batch.insertAllOnConflictUpdate(catalogMetadata, [
          CatalogMetadataCompanion.insert(
            key: 'schemaVersion',
            value: '1',
            updatedAt: Value(DateTime.utc(2026, 6, 19)),
          ),
          CatalogMetadataCompanion.insert(
            key: 'activePack',
            value: 'capital',
            updatedAt: Value(DateTime.utc(2026, 6, 19)),
          ),
        ]);
        batch.insertAllOnConflictUpdate(operators, [
          OperatorsCompanion.insert(
            id: 'seoul-metro',
            nameKo: '서울교통공사',
            nameEn: const Value('Seoul Metro'),
          ),
          OperatorsCompanion.insert(
            id: 'korail',
            nameKo: '한국철도공사',
            nameEn: const Value('KORAIL'),
          ),
        ]);
        batch.insertAllOnConflictUpdate(lines, [
          LinesCompanion.insert(
            id: 'seoul-2',
            operatorId: 'seoul-metro',
            nameKo: '수도권 2호선',
            nameEn: const Value('Seoul Subway Line 2'),
            color: const Value('#00A84D'),
          ),
          LinesCompanion.insert(
            id: 'seoul-4',
            operatorId: 'seoul-metro',
            nameKo: '수도권 4호선',
            nameEn: const Value('Seoul Subway Line 4'),
            color: const Value('#00A5DE'),
          ),
        ]);
        batch.insertAllOnConflictUpdate(stations, [
          StationsCompanion.insert(
            id: 'station-sangnoksu',
            nameKo: '상록수',
            nameEn: const Value('Sangnoksu'),
            normalizedName: '상록수',
            region: const Value('수도권'),
            latitude: const Value(37.3028),
            longitude: const Value(126.8666),
            dataQualityLevel: const Value('LEVEL_2'),
            dataSourceType: const Value('OFFICIAL_FILE'),
            lastVerifiedAt: Value(DateTime.utc(2026, 6, 19)),
          ),
          StationsCompanion.insert(
            id: 'station-sadang',
            nameKo: '사당',
            nameEn: const Value('Sadang'),
            normalizedName: '사당',
            region: const Value('수도권'),
            latitude: const Value(37.4766),
            longitude: const Value(126.9816),
            dataQualityLevel: const Value('LEVEL_2'),
            dataSourceType: const Value('OFFICIAL_FILE'),
            lastVerifiedAt: Value(DateTime.utc(2026, 6, 19)),
          ),
        ]);
        batch.insertAll(stationAliases, [
          StationAliasesCompanion.insert(
            stationId: 'station-sangnoksu',
            alias: '상록수역',
            normalizedAlias: '상록수역',
          ),
          StationAliasesCompanion.insert(
            stationId: 'station-sangnoksu',
            alias: 'Sangnoksu',
            normalizedAlias: 'sangnoksu',
          ),
          StationAliasesCompanion.insert(
            stationId: 'station-sangnoksu',
            alias: '448',
            normalizedAlias: '448',
          ),
          StationAliasesCompanion.insert(
            stationId: 'station-sangnoksu',
            alias: '4호선 상록수',
            normalizedAlias: '4호선상록수',
          ),
        ]);
        batch.insertAllOnConflictUpdate(stationLines, [
          StationLinesCompanion.insert(
            stationId: 'station-sangnoksu',
            lineId: 'seoul-4',
            stationCode: const Value('448'),
            lineSequence: 48,
            platformInfo: const Value('당고개 방면 / 오이도 방면'),
          ),
          StationLinesCompanion.insert(
            stationId: 'station-sadang',
            lineId: 'seoul-2',
            stationCode: const Value('226'),
            lineSequence: 26,
            platformInfo: const Value('내선 / 외선'),
          ),
          StationLinesCompanion.insert(
            stationId: 'station-sadang',
            lineId: 'seoul-4',
            stationCode: const Value('433'),
            lineSequence: 33,
            platformInfo: const Value('당고개 방면 / 오이도 방면'),
          ),
        ]);
        batch.insertAllOnConflictUpdate(networkEdges, [
          NetworkEdgesCompanion.insert(
            id: 'edge-sangnoksu-sadang-seoul-4',
            fromNodeId: _catalogNodeId('station-sangnoksu', 'seoul-4'),
            toNodeId: _catalogNodeId('station-sadang', 'seoul-4'),
            durationSeconds: const Value(420),
            edgeType: const Value('RIDE'),
            servicePattern: const Value('LOCAL'),
            stairAccessState: const Value('STEP_FREE'),
            accessibilityStatus: const Value('AVAILABLE'),
            reliabilityScore: const Value(90),
            lastVerifiedAt: Value(DateTime.utc(2026, 6, 19)),
          ),
          NetworkEdgesCompanion.insert(
            id: 'edge-sadang-sangnoksu-seoul-4',
            fromNodeId: _catalogNodeId('station-sadang', 'seoul-4'),
            toNodeId: _catalogNodeId('station-sangnoksu', 'seoul-4'),
            durationSeconds: const Value(420),
            edgeType: const Value('RIDE'),
            servicePattern: const Value('LOCAL'),
            stairAccessState: const Value('STEP_FREE'),
            accessibilityStatus: const Value('AVAILABLE'),
            reliabilityScore: const Value(90),
            lastVerifiedAt: Value(DateTime.utc(2026, 6, 19)),
          ),
        ]);
        batch.insertAllOnConflictUpdate(stationExits, [
          StationExitsCompanion.insert(
            id: 'exit-sangnoksu-1',
            stationId: 'station-sangnoksu',
            exitNumber: '1',
            description: const Value('상록수역 1번 출구'),
          ),
        ]);
        batch.insertAllOnConflictUpdate(facilities, [
          FacilitiesCompanion.insert(
            id: 'facility-sangnoksu-elevator-1',
            stationId: 'station-sangnoksu',
            exitId: const Value('exit-sangnoksu-1'),
            type: 'ELEVATOR',
            name: '1번 출구 엘리베이터',
            floorFrom: const Value('B1'),
            floorTo: const Value('1F'),
            description: const Value('대합실과 1번 출구 지상을 연결'),
          ),
        ]);
      });
    });
  }

  Future<void> _createIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_stations_normalized_name '
      'ON stations(normalized_name)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_station_lines_line_sequence '
      'ON station_lines(line_id, line_sequence)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_network_edges_from_node '
      'ON network_edges(from_node_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_facilities_station '
      'ON facilities(station_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_internal_route_edges_from '
      'ON internal_route_edges(from_node_id)',
    );
  }
}

String _catalogNodeId(String stationId, String lineId) => '$stationId:$lineId';
