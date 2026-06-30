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
    RealtimeProviderLineMappings,
    RealtimeProviderStationMappings,
    NetworkEdges,
    StationExits,
    Facilities,
    StationFacilityEvidence,
    StationAccessibilitySummaries,
    InternalRouteNodes,
    InternalRouteEdges,
    DataQualityRecords,
  ],
)
/// The catalog database is replaceable installed-pack state.
///
/// Data pack updates may swap station, route, facility, and quality records,
/// but must not store user-owned favorites, receipts, drafts, or preferences.
class CatalogDatabase extends _$CatalogDatabase {
  CatalogDatabase(super.executor);

  factory CatalogDatabase.file(File file) {
    return CatalogDatabase(NativeDatabase.createInBackground(file));
  }

  factory CatalogDatabase.memory() {
    return CatalogDatabase(NativeDatabase.memory());
  }

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) async {
        await migrator.createAll();
        await _createRouteMapPositionsTable();
        await _createIndexes();
      },
      onUpgrade: (migrator, from, to) async {
        if (from < 2) {
          await migrator.createTable(realtimeProviderLineMappings);
          await migrator.createTable(realtimeProviderStationMappings);
          await _createRealtimeProviderIndexes();
        }
        if (from < 3) {
          await _createRouteMapPositionsTable();
        }
        if (from < 4) {
          await _addRouteMapPathColumns();
        }
        if (from < 5) {
          await _addRouteMapLabelPolygonColumn();
        }
        if (from < 6) {
          await _addRelease100ProvenanceColumns();
        }
        if (from < 7) {
          await _addSourceEvidenceProvenanceColumns();
        }
        if (from < 8) {
          await migrator.createTable(stationFacilityEvidence);
          await _createStationFacilityEvidenceIndexes();
        }
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
      await _backfillBaselineAccessEdges();
      await _backfillBaselineRouteMapPositions();
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
            sourceId: const Value('baseline-route-source-capital'),
            sourceSnapshotId: const Value(
              'baseline-route-source-capital-20260619',
            ),
            providerRecordHash: const Value(
              '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
            ),
            provenanceKind: const Value('OFFICIAL_SOURCE'),
            verificationStatus: const Value('VERIFIED'),
            lastVerifiedAt: Value(DateTime.utc(2026, 6, 19)),
            evidenceHash: const Value(
              'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
            ),
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
            sourceId: const Value('baseline-route-source-capital'),
            sourceSnapshotId: const Value(
              'baseline-route-source-capital-20260619',
            ),
            providerRecordHash: const Value(
              '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
            ),
            provenanceKind: const Value('OFFICIAL_SOURCE'),
            verificationStatus: const Value('VERIFIED'),
            lastVerifiedAt: Value(DateTime.utc(2026, 6, 19)),
            evidenceHash: const Value(
              'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
            ),
          ),
          ..._baselineAccessEdges(),
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
            status: const Value('NORMAL'),
            operationalStatus: const Value('AVAILABLE'),
            installationStatus: const Value('INSTALLED'),
            floorFrom: const Value('B1'),
            floorTo: const Value('1F'),
            description: const Value('대합실과 1번 출구 지상을 연결'),
          ),
          FacilitiesCompanion.insert(
            id: 'facility-sangnoksu-escalator-1',
            stationId: 'station-sangnoksu',
            exitId: const Value('exit-sangnoksu-1'),
            type: 'ESCALATOR',
            name: '1번 출구 에스컬레이터',
            status: const Value('UNKNOWN'),
            operationalStatus: const Value('UNKNOWN'),
            installationStatus: const Value('INSTALLED'),
            floorFrom: const Value('B1'),
            floorTo: const Value('1F'),
            description: const Value('안내를 준비 중인 이동 보조 시설'),
          ),
          FacilitiesCompanion.insert(
            id: 'facility-sangnoksu-accessible-toilet-1',
            stationId: 'station-sangnoksu',
            exitId: const Value(null),
            type: 'ACCESSIBLE_TOILET',
            name: '대합실 장애인 화장실',
            status: const Value('UNKNOWN'),
            operationalStatus: const Value('UNKNOWN'),
            installationStatus: const Value('INSTALLED'),
            floorFrom: const Value('B1'),
            floorTo: const Value('B1'),
            description: const Value('대합실 내부'),
          ),
        ]);
        batch.insertAllOnConflictUpdate(dataQualityRecords, [
          DataQualityRecordsCompanion.insert(
            id: 'quality-exit-sangnoksu-1-field',
            targetType: 'station_exit',
            targetId: 'exit-sangnoksu-1',
            qualityLevel: 'FIELD_VERIFIED',
            checkedAt: Value(DateTime.utc(2026, 6, 19)),
          ),
          DataQualityRecordsCompanion.insert(
            id: 'quality-facility-sangnoksu-elevator-1-field',
            targetType: 'facility',
            targetId: 'facility-sangnoksu-elevator-1',
            qualityLevel: 'FIELD_VERIFIED',
            checkedAt: Value(DateTime.utc(2026, 6, 19)),
          ),
          DataQualityRecordsCompanion.insert(
            id: 'quality-facility-sangnoksu-escalator-1-field',
            targetType: 'facility',
            targetId: 'facility-sangnoksu-escalator-1',
            qualityLevel: 'FIELD_UNKNOWN',
            checkedAt: const Value(null),
          ),
          DataQualityRecordsCompanion.insert(
            id: 'quality-facility-sangnoksu-accessible-toilet-1-field',
            targetType: 'facility',
            targetId: 'facility-sangnoksu-accessible-toilet-1',
            qualityLevel: 'FIELD_STALE',
            checkedAt: Value(DateTime.utc(2025, 6, 1)),
          ),
        ]);
      });
      await _seedBaselineRouteMapPositions();
    });
  }

  Future<void> _backfillBaselineRouteMapPositions() async {
    if (!await _isBaselineFixtureCatalog()) {
      return;
    }
    await transaction(_seedBaselineRouteMapPositions);
  }

  Future<void> _seedBaselineRouteMapPositions() async {
    final updatedAt = DateTime.utc(2026, 6, 19).millisecondsSinceEpoch ~/ 1000;
    const sourceId = 'baseline-route-map-source-capital-review';
    const sourceName = '수도권 도시철도 노선도';
    const sourceUrl = 'https://www.seoulmetro.co.kr/kr/cyberStation.do';
    const license = 'public-reference';
    const licenseStatus = '출처 표기 필요';
    final rows = [
      ['station-sangnoksu', 'seoul-4', '수도권', 156, 250],
      ['station-sadang', 'seoul-4', '수도권', 390, 320],
      ['station-sadang', 'seoul-2', '수도권', 390, 320],
    ];
    for (final row in rows) {
      await customStatement(
        '''
        INSERT OR IGNORE INTO route_map_positions (
          station_id, line_id, region, x, y, source_id, source_name,
          source_url, license, license_status, commercial_use_allowed,
          attribution_required, reviewed_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          row[0],
          row[1],
          row[2],
          row[3],
          row[4],
          sourceId,
          sourceName,
          sourceUrl,
          license,
          licenseStatus,
          0,
          1,
          updatedAt,
          updatedAt,
        ],
      );
      await customStatement(
        '''
        UPDATE route_map_positions
        SET source_id = ?, source_name = ?, source_url = ?,
            license = ?, license_status = ?, updated_at = ?
        WHERE station_id = ?
          AND line_id = ?
          AND (
            source_id = 'fixture-route-map-source-capital-review'
            OR source_url LIKE '%easysubway.local/fixtures%'
            OR license_status = 'fixture-only'
          )
        ''',
        [
          sourceId,
          sourceName,
          sourceUrl,
          license,
          licenseStatus,
          updatedAt,
          row[0],
          row[1],
        ],
      );
    }
  }

  Future<void> _backfillBaselineAccessEdges() async {
    if (!await _canBackfillBaselineAccessEdges()) {
      return;
    }
    if (!await _isBaselineFixtureCatalog()) {
      return;
    }
    await transaction(() async {
      for (final edge in _baselineAccessEdges()) {
        await into(networkEdges).insert(edge, mode: InsertMode.insertOrIgnore);
      }
    });
  }

  Future<bool> _canBackfillBaselineAccessEdges() async {
    final columns = await customSelect(
      'PRAGMA table_info(network_edges)',
    ).get();
    final columnNames = {for (final row in columns) row.read<String>('name')};
    const requiredColumns = {
      'id',
      'from_node_id',
      'to_node_id',
      'duration_seconds',
      'edge_type',
      'stair_access_state',
      'accessibility_status',
      'reliability_score',
      'last_verified_at',
    };
    return columnNames.containsAll(requiredColumns);
  }

  Future<bool> _isBaselineFixtureCatalog() async {
    final row = await customSelect('''
      SELECT
        (SELECT value
         FROM catalog_metadata
         WHERE key = 'activePack') AS active_pack,
        (SELECT COUNT(*) FROM operators) AS operator_count,
        (SELECT COUNT(*) FROM lines) AS line_count,
        (SELECT COUNT(*) FROM stations) AS station_count,
        (SELECT COUNT(*) FROM station_lines) AS station_line_count,
        (SELECT COUNT(*) FROM network_edges) AS network_edge_count,
        (SELECT COUNT(*)
         FROM station_lines
         WHERE (station_id = 'station-sangnoksu' AND line_id = 'seoul-4')
            OR (station_id = 'station-sadang' AND line_id = 'seoul-4'))
        +
        (SELECT COUNT(*)
         FROM network_edges
         WHERE id IN (
           'edge-sangnoksu-sadang-seoul-4',
           'edge-sadang-sangnoksu-seoul-4'
         )) AS match_count
    ''').getSingle();
    if (row.readNullable<String>('active_pack') != 'capital') {
      return false;
    }
    if (row.read<int>('match_count') != 4) {
      return false;
    }
    final operatorCount = row.read<int>('operator_count');
    final lineCount = row.read<int>('line_count');
    final stationCount = row.read<int>('station_count');
    final stationLineCount = row.read<int>('station_line_count');
    final networkEdgeCount = row.read<int>('network_edge_count');
    final localSeedBaseline =
        operatorCount == 2 &&
        lineCount == 2 &&
        stationCount == 2 &&
        stationLineCount == 3 &&
        networkEdgeCount >= 2 &&
        networkEdgeCount <= 6;
    final bundledFixture =
        operatorCount == 2 &&
        lineCount == 4 &&
        stationCount == 6 &&
        stationLineCount == 9 &&
        networkEdgeCount >= 15 &&
        networkEdgeCount <= 19;
    return localSeedBaseline || bundledFixture;
  }

  List<NetworkEdgesCompanion> _baselineAccessEdges() {
    return [
      NetworkEdgesCompanion.insert(
        id: 'entry-sangnoksu-seoul-4',
        fromNodeId: 'station-sangnoksu',
        toNodeId: _catalogNodeId('station-sangnoksu', 'seoul-4'),
        durationSeconds: const Value(90),
        edgeType: const Value('ENTRY'),
        stairAccessState: const Value('STEP_FREE'),
        accessibilityStatus: const Value('AVAILABLE'),
        reliabilityScore: const Value(90),
        sourceId: const Value('baseline-route-source-capital'),
        sourceSnapshotId: const Value('baseline-route-source-capital-20260619'),
        providerRecordHash: const Value(
          '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        ),
        provenanceKind: const Value('OFFICIAL_SOURCE'),
        verificationStatus: const Value('VERIFIED'),
        lastVerifiedAt: Value(DateTime.utc(2026, 6, 19)),
        evidenceHash: const Value(
          'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        ),
      ),
      NetworkEdgesCompanion.insert(
        id: 'exit-sangnoksu-seoul-4',
        fromNodeId: _catalogNodeId('station-sangnoksu', 'seoul-4'),
        toNodeId: 'station-sangnoksu',
        durationSeconds: const Value(60),
        edgeType: const Value('EXIT'),
        stairAccessState: const Value('STEP_FREE'),
        accessibilityStatus: const Value('AVAILABLE'),
        reliabilityScore: const Value(90),
        sourceId: const Value('baseline-route-source-capital'),
        sourceSnapshotId: const Value('baseline-route-source-capital-20260619'),
        providerRecordHash: const Value(
          '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        ),
        provenanceKind: const Value('OFFICIAL_SOURCE'),
        verificationStatus: const Value('VERIFIED'),
        lastVerifiedAt: Value(DateTime.utc(2026, 6, 19)),
        evidenceHash: const Value(
          'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        ),
      ),
      NetworkEdgesCompanion.insert(
        id: 'entry-sadang-seoul-4',
        fromNodeId: 'station-sadang',
        toNodeId: _catalogNodeId('station-sadang', 'seoul-4'),
        durationSeconds: const Value(90),
        edgeType: const Value('ENTRY'),
        stairAccessState: const Value('STEP_FREE'),
        accessibilityStatus: const Value('AVAILABLE'),
        reliabilityScore: const Value(90),
        sourceId: const Value('baseline-route-source-capital'),
        sourceSnapshotId: const Value('baseline-route-source-capital-20260619'),
        providerRecordHash: const Value(
          '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        ),
        provenanceKind: const Value('OFFICIAL_SOURCE'),
        verificationStatus: const Value('VERIFIED'),
        lastVerifiedAt: Value(DateTime.utc(2026, 6, 19)),
        evidenceHash: const Value(
          'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        ),
      ),
      NetworkEdgesCompanion.insert(
        id: 'exit-sadang-seoul-4',
        fromNodeId: _catalogNodeId('station-sadang', 'seoul-4'),
        toNodeId: 'station-sadang',
        durationSeconds: const Value(60),
        edgeType: const Value('EXIT'),
        stairAccessState: const Value('STEP_FREE'),
        accessibilityStatus: const Value('AVAILABLE'),
        reliabilityScore: const Value(90),
        sourceId: const Value('baseline-route-source-capital'),
        sourceSnapshotId: const Value('baseline-route-source-capital-20260619'),
        providerRecordHash: const Value(
          '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        ),
        provenanceKind: const Value('OFFICIAL_SOURCE'),
        verificationStatus: const Value('VERIFIED'),
        lastVerifiedAt: Value(DateTime.utc(2026, 6, 19)),
        evidenceHash: const Value(
          'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        ),
      ),
    ];
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
    await _createRealtimeProviderIndexes();
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_network_edges_from_node '
      'ON network_edges(from_node_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_route_map_positions_region_line '
      'ON route_map_positions(region, line_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_facilities_station '
      'ON facilities(station_id)',
    );
    await _createStationFacilityEvidenceIndexes();
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_internal_route_edges_from '
      'ON internal_route_edges(from_node_id)',
    );
  }

  Future<void> _createRealtimeProviderIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_realtime_provider_stations_internal '
      'ON realtime_provider_station_mappings(station_id, line_id)',
    );
  }

  Future<void> _createRouteMapPositionsTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS route_map_positions (
        station_id TEXT NOT NULL,
        line_id TEXT NOT NULL,
        region TEXT NOT NULL DEFAULT '',
        x INTEGER NOT NULL CHECK (x >= 0),
        y INTEGER NOT NULL CHECK (y >= 0),
        label_dx INTEGER NOT NULL DEFAULT 0,
        label_dy INTEGER NOT NULL DEFAULT 0,
        label_polygon TEXT NOT NULL DEFAULT '',
        up_path TEXT NOT NULL DEFAULT '',
        down_path TEXT NOT NULL DEFAULT '',
        source_id TEXT NOT NULL,
        source_name TEXT NOT NULL,
        source_url TEXT NOT NULL,
        license TEXT NOT NULL,
        license_status TEXT NOT NULL,
        commercial_use_allowed INTEGER NOT NULL DEFAULT 0 CHECK (commercial_use_allowed IN (0, 1)),
        attribution_required INTEGER NOT NULL DEFAULT 1 CHECK (attribution_required IN (0, 1)),
        reviewed_at INTEGER,
        updated_at INTEGER,
        PRIMARY KEY (station_id, line_id, region)
      )
      ''');
  }

  Future<void> _createStationFacilityEvidenceIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_station_facility_evidence_station '
      'ON station_facility_evidence(station_id, line_id)',
    );
  }

  Future<void> _addRouteMapPathColumns() async {
    await _addRouteMapLabelPolygonColumn();
    await _addColumnIfMissing(
      'route_map_positions',
      'up_path',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      'route_map_positions',
      'down_path',
      "TEXT NOT NULL DEFAULT ''",
    );
  }

  Future<void> _addRouteMapLabelPolygonColumn() async {
    await _addColumnIfMissing(
      'route_map_positions',
      'label_polygon',
      "TEXT NOT NULL DEFAULT ''",
    );
  }

  Future<void> _addRelease100ProvenanceColumns() async {
    await _addColumnIfMissing(
      'network_edges',
      'source_id',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      'network_edges',
      'provenance_kind',
      "TEXT NOT NULL DEFAULT 'UNKNOWN'",
    );
    await _addColumnIfMissing(
      'network_edges',
      'verification_status',
      "TEXT NOT NULL DEFAULT 'UNKNOWN'",
    );
    await _addColumnIfMissing(
      'network_edges',
      'evidence_hash',
      "TEXT NOT NULL DEFAULT ''",
    );

    await _addColumnIfMissing(
      'facilities',
      'source_id',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      'facilities',
      'provider_facility_ref',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      'facilities',
      'provenance_kind',
      "TEXT NOT NULL DEFAULT 'UNKNOWN'",
    );
    await _addColumnIfMissing(
      'facilities',
      'verified_at',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      'facilities',
      'retrieved_at',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      'facilities',
      'evidence_hash',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      'facilities',
      'status_meaning',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      'facilities',
      'operational_status',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      'facilities',
      'installation_status',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      'facilities',
      'confidence',
      'INTEGER NOT NULL DEFAULT 0',
    );

    await _addColumnIfMissing(
      'internal_route_edges',
      'source_id',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      'internal_route_edges',
      'provenance_kind',
      "TEXT NOT NULL DEFAULT 'UNKNOWN'",
    );
    await _addColumnIfMissing(
      'internal_route_edges',
      'verification_status',
      "TEXT NOT NULL DEFAULT 'UNKNOWN'",
    );
    await _addColumnIfMissing('internal_route_edges', 'facility_id', 'TEXT');
    await _addColumnIfMissing(
      'internal_route_edges',
      'last_verified_at',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      'internal_route_edges',
      'evidence_hash',
      "TEXT NOT NULL DEFAULT ''",
    );
  }

  Future<void> _addSourceEvidenceProvenanceColumns() async {
    await _addColumnIfMissing(
      'network_edges',
      'source_snapshot_id',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      'network_edges',
      'provider_record_hash',
      "TEXT NOT NULL DEFAULT ''",
    );

    await _addColumnIfMissing(
      'facilities',
      'source_snapshot_id',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      'facilities',
      'provider_record_hash',
      "TEXT NOT NULL DEFAULT ''",
    );

    await _addColumnIfMissing(
      'internal_route_edges',
      'source_snapshot_id',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      'internal_route_edges',
      'provider_record_hash',
      "TEXT NOT NULL DEFAULT ''",
    );
  }

  Future<void> _addColumnIfMissing(
    String tableName,
    String columnName,
    String definition,
  ) async {
    final existing = await customSelect('PRAGMA table_info($tableName)').get();
    if (existing.any((row) => row.read<String>('name') == columnName)) {
      return;
    }
    await customStatement(
      'ALTER TABLE $tableName ADD COLUMN $columnName $definition',
    );
  }
}

String _catalogNodeId(String stationId, String lineId) => '$stationId:$lineId';
