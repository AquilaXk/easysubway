import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'catalog_tables.dart';

part 'catalog_database.g.dart';

// v18 is a reader-compatibility boundary for transitPassThroughStationIds.
// It intentionally adds no table migration; older apps must reject packs that
// use the new public-scope semantics instead of exposing pass-through stations.
const catalogDatabaseSchemaVersion = 18;

/// 수도권 통합요금 기본거리(10km) 초과분 요금 단계(#1911).
///
/// 10~50km 구간은 5km당 100원씩 8회, 50km 초과 구간은 8km당 100원씩
/// 반복 부과된다(마지막 단계만 반복 — `FareCalculator` dartdoc 참고).
/// `seedBaselineIfEmpty()`와 `_backfillBaselineFareRules()` 양쪽에서
/// 값이 어긋나지 않도록 이 상수 하나만 사용한다.
const capitalIntegratedAdditionalStepsJson =
    '[{"distanceMeters":5000,"cardFare":100,"cashFare":100},'
    '{"distanceMeters":5000,"cardFare":100,"cashFare":100},'
    '{"distanceMeters":5000,"cardFare":100,"cashFare":100},'
    '{"distanceMeters":5000,"cardFare":100,"cashFare":100},'
    '{"distanceMeters":5000,"cardFare":100,"cashFare":100},'
    '{"distanceMeters":5000,"cardFare":100,"cashFare":100},'
    '{"distanceMeters":5000,"cardFare":100,"cashFare":100},'
    '{"distanceMeters":5000,"cardFare":100,"cashFare":100},'
    '{"distanceMeters":8000,"cardFare":100,"cashFare":100}]';

@DriftDatabase(
  tables: [
    CatalogMetadata,
    Operators,
    Lines,
    Stations,
    StationAliases,
    StationLines,
    ServiceCalendars,
    ServiceCalendarDates,
    TransitRoutes,
    TransitTrips,
    TransitStopTimes,
    TransitFrequencies,
    FareZones,
    FareRules,
    FareDiscounts,
    StationFareZones,
    OfficialOdFareQuotes,
    RealtimeProviderLineMappings,
    RealtimeProviderStationMappings,
    NetworkEdges,
    StationExits,
    Facilities,
    StationFacilityEvidence,
    FacilityStatusSnapshots,
    StationAccessibilitySummaries,
    InternalRouteNodes,
    InternalRouteEdges,
    StationPathwayNodes,
    StationPathwayEdges,
    TransferRules,
    DataQualityRecords,
    StationCarDoorHints,
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
  int get schemaVersion => catalogDatabaseSchemaVersion;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) async {
        await migrator.createAll();
        await _createRouteMapPositionsTable();
        await _createRouteMapLineTracksTable();
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
        if (from < 9) {
          await migrator.createTable(serviceCalendars);
          await migrator.createTable(serviceCalendarDates);
          await migrator.createTable(transitRoutes);
          await migrator.createTable(transitTrips);
          await migrator.createTable(transitStopTimes);
          await migrator.createTable(transitFrequencies);
          await _createTransitScheduleIndexes();
        }
        if (from < 10) {
          await migrator.createTable(stationPathwayNodes);
          await migrator.createTable(stationPathwayEdges);
          await migrator.createTable(transferRules);
          await _createStationPathwayIndexes();
        }
        if (from < 11) {
          await migrator.createTable(facilityStatusSnapshots);
          await _createFacilityStatusSnapshotIndexes();
        }
        if (from < 12) {
          await _createRouteMapLineTracksTable();
        }
        if (from < 13) {
          await _addStationNameSubColumn();
        }
        if (from < 14) {
          await migrator.createTable(fareZones);
          await migrator.createTable(fareRules);
          await migrator.createTable(fareDiscounts);
          await migrator.createTable(stationFareZones);
        }
        if (from < 15) {
          await _addStationExitMapColumns();
        }
        if (from < 16) {
          await migrator.createTable(stationCarDoorHints);
          await _createStationCarDoorHintIndexes();
        }
        if (from < 17) {
          await migrator.createTable(officialOdFareQuotes);
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
      await _backfillBaselineNetworkEdgeEvidence();
      await _backfillBaselineRouteMapPositions();
      await _createFareTablesIfMissing();
      await _backfillBaselineFareRules();
      await _backfillBaselineStationExitMapData();
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
            lineSequence: 43,
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
            lineSequence: 28,
            platformInfo: const Value('당고개 방면 / 오이도 방면'),
          ),
        ]);
        batch.insertAllOnConflictUpdate(fareZones, [
          FareZonesCompanion.insert(
            id: 'capital-integrated',
            nameKo: '수도권 통합요금',
            region: '수도권',
            currencyCode: const Value('KRW'),
            sourceId: const Value('baseline-fixture'),
          ),
        ]);
        batch.insertAllOnConflictUpdate(fareRules, [
          FareRulesCompanion.insert(
            id: 'capital-integrated-standard',
            zoneId: 'capital-integrated',
            baseCardFare: 1550,
            baseCashFare: 1650,
            baseDistanceMeters: 10000,
            additionalStepsJson: const Value(
              capitalIntegratedAdditionalStepsJson,
            ),
          ),
        ]);
        batch.insertAllOnConflictUpdate(fareDiscounts, [
          FareDiscountsCompanion.insert(
            id: 'capital-integrated-youth',
            zoneId: 'capital-integrated',
            riderType: 'YOUTH',
            cardFare: const Value(900),
            cashFare: const Value(1650),
            descriptionKo: const Value('청소년 기준 요금'),
          ),
          FareDiscountsCompanion.insert(
            id: 'capital-integrated-child',
            zoneId: 'capital-integrated',
            riderType: 'CHILD',
            cardFare: const Value(550),
            cashFare: const Value(550),
            descriptionKo: const Value('어린이 기준 요금'),
          ),
          FareDiscountsCompanion.insert(
            id: 'capital-integrated-concession',
            zoneId: 'capital-integrated',
            riderType: 'CONCESSION',
            freeRide: const Value(true),
            descriptionKo: const Value('만 65세 이상·장애인·국가유공자 우대 무임'),
          ),
        ]);
        batch.insertAllOnConflictUpdate(stationFareZones, [
          StationFareZonesCompanion.insert(
            stationId: 'station-sangnoksu',
            lineId: 'seoul-4',
            zoneId: 'capital-integrated',
          ),
          StationFareZonesCompanion.insert(
            stationId: 'station-sadang',
            lineId: 'seoul-2',
            zoneId: 'capital-integrated',
          ),
          StationFareZonesCompanion.insert(
            stationId: 'station-sadang',
            lineId: 'seoul-4',
            zoneId: 'capital-integrated',
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
            latitude: const Value(37.3021),
            longitude: const Value(126.8661),
            hasElevatorConnection: const Value(true),
            sourceId: const Value('baseline-exit-source-capital'),
            sourceSnapshotId: const Value(
              'baseline-exit-source-capital-20260619',
            ),
            dataSourceType: const Value('OFFICIAL_FILE'),
            lastVerifiedAt: Value(DateTime.utc(2026, 6, 19)),
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

  Future<void> _backfillBaselineStationExitMapData() async {
    if (!await _isBaselineFixtureCatalog()) {
      return;
    }
    await _addStationExitMapColumns();
    await customStatement('''
      UPDATE station_exits
      SET latitude = 37.3021,
          longitude = 126.8661,
          has_elevator_connection = 1,
          source_id = 'baseline-exit-source-capital',
          source_snapshot_id = 'baseline-exit-source-capital-20260619',
          data_source_type = 'OFFICIAL_FILE',
          last_verified_at = 1781827200
      WHERE id = 'exit-sangnoksu-1'
      ''');
  }

  Future<void> _backfillBaselineFareRules() async {
    if (!await _isBaselineFixtureCatalog() ||
        !await _shouldBackfillBaselineFareRules()) {
      return;
    }
    await transaction(() async {
      await into(fareZones).insertOnConflictUpdate(
        FareZonesCompanion.insert(
          id: 'capital-integrated',
          nameKo: '수도권 통합요금',
          region: '수도권',
          currencyCode: const Value('KRW'),
          sourceId: const Value('baseline-fixture'),
        ),
      );
      await into(fareRules).insertOnConflictUpdate(
        FareRulesCompanion.insert(
          id: 'capital-integrated-standard',
          zoneId: 'capital-integrated',
          baseCardFare: 1550,
          baseCashFare: 1650,
          baseDistanceMeters: 10000,
          additionalStepsJson: const Value(
            capitalIntegratedAdditionalStepsJson,
          ),
        ),
      );
      await batch((batch) {
        batch.insertAllOnConflictUpdate(fareDiscounts, [
          FareDiscountsCompanion.insert(
            id: 'capital-integrated-youth',
            zoneId: 'capital-integrated',
            riderType: 'YOUTH',
            cardFare: const Value(900),
            cashFare: const Value(1650),
            descriptionKo: const Value('청소년 기준 요금'),
          ),
          FareDiscountsCompanion.insert(
            id: 'capital-integrated-child',
            zoneId: 'capital-integrated',
            riderType: 'CHILD',
            cardFare: const Value(550),
            cashFare: const Value(550),
            descriptionKo: const Value('어린이 기준 요금'),
          ),
          FareDiscountsCompanion.insert(
            id: 'capital-integrated-concession',
            zoneId: 'capital-integrated',
            riderType: 'CONCESSION',
            freeRide: const Value(true),
            descriptionKo: const Value('만 65세 이상·장애인·국가유공자 우대 무임'),
          ),
        ]);
      });
      await customStatement('''
        INSERT OR IGNORE INTO station_fare_zones (station_id, line_id, zone_id)
        SELECT station_id, line_id, 'capital-integrated'
        FROM station_lines
      ''');
    });
  }

  Future<void> _createFareTablesIfMissing() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS fare_zones (
        id TEXT NOT NULL PRIMARY KEY,
        name_ko TEXT NOT NULL,
        region TEXT NOT NULL,
        currency_code TEXT NOT NULL DEFAULT 'KRW',
        source_id TEXT NOT NULL DEFAULT ''
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS fare_rules (
        id TEXT NOT NULL PRIMARY KEY,
        zone_id TEXT NOT NULL,
        base_card_fare INTEGER NOT NULL,
        base_cash_fare INTEGER NOT NULL,
        base_distance_meters INTEGER NOT NULL,
        additional_steps_json TEXT NOT NULL DEFAULT '[]',
        FOREIGN KEY (zone_id) REFERENCES fare_zones(id),
        CHECK (base_card_fare >= 0),
        CHECK (base_cash_fare >= 0),
        CHECK (base_distance_meters >= 0)
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS fare_discounts (
        id TEXT NOT NULL PRIMARY KEY,
        zone_id TEXT NOT NULL,
        rider_type TEXT NOT NULL,
        card_fare INTEGER,
        cash_fare INTEGER,
        free_ride INTEGER NOT NULL DEFAULT 0 CHECK (free_ride IN (0, 1)),
        description_ko TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (zone_id) REFERENCES fare_zones(id),
        CHECK (card_fare IS NULL OR card_fare >= 0),
        CHECK (cash_fare IS NULL OR cash_fare >= 0)
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS station_fare_zones (
        station_id TEXT NOT NULL,
        line_id TEXT NOT NULL,
        zone_id TEXT NOT NULL,
        PRIMARY KEY (station_id, line_id),
        FOREIGN KEY (station_id, line_id)
          REFERENCES station_lines(station_id, line_id),
        FOREIGN KEY (zone_id) REFERENCES fare_zones(id)
      )
    ''');
  }

  Future<bool> _shouldBackfillBaselineFareRules() async {
    final rows = await customSelect('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name IN (
          'fare_zones',
          'fare_rules',
          'fare_discounts',
          'station_fare_zones'
        )
    ''').get();
    final names = {for (final row in rows) row.read<String>('name')};
    final hasFareTables = names.containsAll({
      'fare_zones',
      'fare_rules',
      'fare_discounts',
      'station_fare_zones',
    });
    if (!hasFareTables) {
      return false;
    }
    final row = await customSelect('''
      SELECT
        (SELECT value
         FROM catalog_metadata
         WHERE key = 'activePack') AS active_pack,
        (SELECT COUNT(*) FROM station_lines) AS station_line_count,
        (SELECT COUNT(*) FROM fare_rules) AS fare_rule_count,
        (SELECT cash_fare
         FROM fare_discounts
         WHERE id = 'capital-integrated-youth') AS youth_cash_fare,
        (SELECT additional_steps_json
         FROM fare_rules
         WHERE id = 'capital-integrated-standard') AS standard_additional_steps_json
    ''').getSingle();
    return row.readNullable<String>('active_pack') == 'capital' &&
        row.read<int>('station_line_count') > 0 &&
        (row.read<int>('fare_rule_count') == 0 ||
            row.readNullable<String>('standard_additional_steps_json') !=
                capitalIntegratedAdditionalStepsJson ||
            row.readNullable<int>('youth_cash_fare') == 1000);
  }

  Future<void> _seedBaselineRouteMapPositions() async {
    final updatedAt = DateTime.utc(2026, 6, 19).millisecondsSinceEpoch ~/ 1000;
    const sourceId = 'baseline-route-map-source-capital-review';
    const sourceName = '수도권 도시철도 노선도';
    const sourceUrl = 'https://www.seoulmetro.co.kr/kr/cyberStation.do';
    const license = 'public-reference';
    const licenseStatus = '기관 안내 자료를 바탕으로 함';
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
      'source_id',
      'source_snapshot_id',
      'provider_record_hash',
      'provenance_kind',
      'verification_status',
      'evidence_hash',
    };
    return columnNames.containsAll(requiredColumns);
  }

  Future<void> _backfillBaselineNetworkEdgeEvidence() async {
    if (!await _canBackfillBaselineNetworkEdgeEvidence()) {
      return;
    }
    if (!await _isBaselineFixtureCatalog()) {
      return;
    }
    await customStatement('''
      UPDATE network_edges
      SET source_id = CASE
            WHEN source_id = '' THEN 'baseline-route-source-capital'
            ELSE source_id
          END,
          source_snapshot_id = CASE
            WHEN source_snapshot_id = '' THEN 'baseline-route-source-capital-20260619'
            ELSE source_snapshot_id
          END,
          provider_record_hash = CASE
            WHEN provider_record_hash = '' THEN '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
            ELSE provider_record_hash
          END,
          provenance_kind = CASE
            WHEN UPPER(provenance_kind) = 'UNKNOWN' THEN 'OFFICIAL_SOURCE'
            ELSE provenance_kind
          END,
          verification_status = CASE
            WHEN verification_status = '' OR UPPER(verification_status) = 'UNKNOWN' THEN 'VERIFIED'
            ELSE verification_status
          END,
          evidence_hash = CASE
            WHEN evidence_hash = '' THEN 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890'
            ELSE evidence_hash
          END
      WHERE id IN (
        'edge-sangnoksu-sadang-seoul-4',
        'edge-sadang-sangnoksu-seoul-4',
        'entry-sangnoksu-seoul-4',
        'exit-sangnoksu-seoul-4',
        'entry-sadang-seoul-4',
        'exit-sadang-seoul-4'
      )
    ''');
  }

  Future<bool> _canBackfillBaselineNetworkEdgeEvidence() async {
    final columns = await customSelect(
      'PRAGMA table_info(network_edges)',
    ).get();
    final columnNames = {for (final row in columns) row.read<String>('name')};
    const requiredColumns = {
      'id',
      'source_id',
      'source_snapshot_id',
      'provider_record_hash',
      'provenance_kind',
      'verification_status',
      'evidence_hash',
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
        networkEdgeCount <= 20;
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
    await _createTransitScheduleIndexes();
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
    await _createFacilityStatusSnapshotIndexes();
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_internal_route_edges_from '
      'ON internal_route_edges(from_node_id)',
    );
    await _createStationPathwayIndexes();
    await _createStationCarDoorHintIndexes();
  }

  Future<void> _createStationCarDoorHintIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_station_car_door_hints_station '
      'ON station_car_door_hints(station_id, line_id)',
    );
  }

  Future<void> _createRealtimeProviderIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_realtime_provider_stations_internal '
      'ON realtime_provider_station_mappings(station_id, line_id)',
    );
  }

  Future<void> _createTransitScheduleIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_transit_stop_times_station_line_departure '
      'ON transit_stop_times(station_id, line_id, departure_seconds)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_transit_stop_times_trip_sequence '
      'ON transit_stop_times(trip_id, stop_sequence)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_transit_trips_route_service_pattern '
      'ON transit_trips(route_id, service_id, service_pattern)',
    );
  }

  Future<void> _createStationPathwayIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_station_pathway_nodes_station '
      'ON station_pathway_nodes(station_id, line_id, node_type)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_station_pathway_edges_from '
      'ON station_pathway_edges(from_node_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_transfer_rules_from_line '
      'ON transfer_rules(from_station_id, from_line_id)',
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

  /// 노선별 실제 track polyline(#1638). apply-route-map-line-tracks 스키마와 동일.
  /// 구팩(테이블 없음)에서도 열리도록 IF NOT EXISTS로 만든다.
  Future<void> _createRouteMapLineTracksTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS route_map_line_tracks (
        region TEXT NOT NULL,
        line_id TEXT NOT NULL,
        track_index INTEGER NOT NULL,
        path TEXT NOT NULL,
        svg_color TEXT NOT NULL DEFAULT '',
        source_id TEXT NOT NULL,
        source_name TEXT NOT NULL,
        source_url TEXT NOT NULL,
        license TEXT NOT NULL,
        license_status TEXT NOT NULL,
        commercial_use_allowed INTEGER NOT NULL DEFAULT 0 CHECK (commercial_use_allowed IN (0, 1)),
        attribution_required INTEGER NOT NULL DEFAULT 1 CHECK (attribution_required IN (0, 1)),
        updated_at INTEGER,
        PRIMARY KEY (region, line_id, track_index)
      )
      ''');
  }

  Future<void> _createStationFacilityEvidenceIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_station_facility_evidence_station '
      'ON station_facility_evidence(station_id, line_id)',
    );
  }

  Future<void> _createFacilityStatusSnapshotIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_facility_status_snapshots_facility '
      'ON facility_status_snapshots(facility_id, expires_at, observed_at)',
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

  // 부역명 필드(#1789 P0.2). 구팩(name_sub 없음)에서도 열리도록 idempotent.
  Future<void> _addStationNameSubColumn() async {
    await _addColumnIfMissing(
      'stations',
      'name_sub',
      "TEXT NOT NULL DEFAULT ''",
    );
  }

  Future<void> _addStationExitMapColumns() async {
    await _addColumnIfMissing('station_exits', 'latitude', 'REAL');
    await _addColumnIfMissing('station_exits', 'longitude', 'REAL');
    await _addColumnIfMissing(
      'station_exits',
      'has_elevator_connection',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      'station_exits',
      'source_id',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      'station_exits',
      'source_snapshot_id',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      'station_exits',
      'data_source_type',
      "TEXT NOT NULL DEFAULT 'OFFICIAL_FILE'",
    );
    await _addColumnIfMissing('station_exits', 'last_verified_at', 'INTEGER');
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
