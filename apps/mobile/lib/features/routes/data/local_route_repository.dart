import '../../../core/database/catalog/catalog_database.dart';
import '../../../route_search.dart';
import '../application/network_graph.dart' as graph;
import '../application/route_engine.dart';
import '../domain/route_request.dart' as local;
import '../domain/route_result.dart' as local;

class LocalRouteRepository implements RouteSearchRepository {
  LocalRouteRepository({required this.catalogDatabase});

  final CatalogDatabase catalogDatabase;

  Future<bool> canSearchRoute(RouteSearchRequest request) async {
    final catalog = await _RouteCatalogSnapshot.load(catalogDatabase);
    return catalog.hasStation(request.originStationId) &&
        catalog.hasStation(request.destinationStationId);
  }

  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request) async {
    final catalog = await _RouteCatalogSnapshot.load(catalogDatabase);
    final mobilityType = _mobilityType(request.mobilityType);
    final constraintMode = _constraintMode(request.effectiveConstraintMode);
    final result =
        mobilityType.blocksStairOnlyAccess(constraintMode) &&
            !catalog.strictEvidenceSupported
        ? local.LocalRouteResult.unknown(const ['STRICT_EVIDENCE_UNSUPPORTED'])
        : LocalRouteEngine(graph: catalog.toGraph()).search(
            local.RouteRequest(
              originStationId: request.originStationId,
              destinationStationId: request.destinationStationId,
              mobilityType: mobilityType,
              constraintMode: constraintMode,
              searchMode: local
                  .RouteSearchMode
                  .stationToStationWithOutOfStationTransfers,
            ),
          );

    return _toRouteSearchResult(request, result, catalog);
  }

  RouteSearchResult _toRouteSearchResult(
    RouteSearchRequest request,
    local.LocalRouteResult result,
    _RouteCatalogSnapshot catalog,
  ) {
    final originName = catalog.stationName(request.originStationId);
    final destinationName = catalog.stationName(request.destinationStationId);
    final lineIds = result.lineIds;
    final primaryLineId = lineIds.isEmpty ? '' : lineIds.first;
    final primaryLineName = catalog.lineName(primaryLineId);
    final steps = _toSteps(result, catalog);

    return RouteSearchResult(
      routeSearchId:
          'local-${request.originStationId}-${request.destinationStationId}',
      originStationId: request.originStationId,
      originStationName: originName,
      destinationStationId: request.destinationStationId,
      destinationStationName: destinationName,
      mobilityType: request.mobilityType,
      status: _routeStatus(result.status),
      lineId: primaryLineId,
      lineName: primaryLineName,
      score: result.accessibilityScore,
      burdenCost: result.generalizedCost,
      estimatedDurationSeconds: _estimatedDurationSeconds(steps),
      walkingDistanceMeters: _walkingDistanceMeters(steps),
      transferCount: _transferCount(steps),
      evidenceSummary: _evidenceSummary(result),
      steps: steps,
      warnings: result.warnings
          .map(
            (warning) => RouteSearchWarning(
              code: warning.code,
              message: warning.message,
            ),
          )
          .toList(growable: false),
      recommendationReasons: _recommendationReasons(result),
      blockedReasons: result.blockedReasonCodes
          .map(_blockedReasonMessage)
          .toList(growable: false),
      createdAt: DateTime.now().toIso8601String(),
    );
  }

  String _routeStatus(local.RouteStatus status) {
    return switch (status) {
      local.RouteStatus.found => 'FOUND',
      local.RouteStatus.blocked => 'BLOCKED',
      local.RouteStatus.unknown => 'UNKNOWN',
      local.RouteStatus.unsupported => 'UNSUPPORTED',
      local.RouteStatus.error => 'ERROR',
    };
  }

  List<RouteSearchStep> _toSteps(
    local.LocalRouteResult result,
    _RouteCatalogSnapshot catalog,
  ) {
    return result.steps
        .map((step) {
          final fromStationId = catalog.stationIdForNode(step.fromNodeId);
          final toStationId = catalog.stationIdForNode(step.toNodeId);
          final fromName = catalog.stationName(fromStationId);
          final toName = catalog.stationName(toStationId);
          final lineName = catalog.lineName(step.lineId);

          return RouteSearchStep(
            sequence: step.sequence,
            stepType: step.type.name,
            title: _stepTitle(step.type.name, fromName, toName, lineName),
            description: _stepDescription(step.type.name, fromName, toName),
            lineId: step.lineId,
            lineName: lineName,
            fromStationId: fromStationId,
            toStationId: toStationId,
            estimatedMinutes: _estimatedMinutesFor(step.durationSeconds),
            distanceMeters: step.distanceMeters,
            includesStairs: step.includesStairs,
            stairAccessState: step.stairAccessState,
            requiresAccessibilityCheck:
                step.type.name == 'entry' || step.type.name == 'exit',
            actionTitle: _stepActionTitle(step.type.name),
            actionDetail: _stepActionDetail(
              step.type.name,
              fromName,
              toName,
              lineName,
            ),
            reason: _stepReason(),
            evidenceSources: step.evidenceSources,
            timeSource: step.timeSource,
            distanceSource: step.distanceSource,
            confidenceLabel: step.confidenceLabel,
          );
        })
        .toList(growable: false);
  }

  int _estimatedDurationSeconds(List<RouteSearchStep> steps) {
    return steps.fold<int>(
      0,
      (sum, step) =>
          sum + (step.estimatedMinutes < 0 ? 0 : step.estimatedMinutes * 60),
    );
  }

  int _walkingDistanceMeters(List<RouteSearchStep> steps) {
    return steps.fold<int>(
      0,
      (sum, step) => step.isWalkingStep ? sum + step.distanceMeters : sum,
    );
  }

  int _transferCount(List<RouteSearchStep> steps) {
    final typedTransfers = steps.where(
      (step) => _isRouteTransferStepType(step.stepType),
    );
    if (typedTransfers.isNotEmpty) {
      return typedTransfers.length;
    }
    var previousLine = '';
    var changes = 0;
    for (final step in steps) {
      final line = step.lineId.isNotEmpty ? step.lineId : step.lineName;
      if (line.isEmpty) {
        continue;
      }
      if (previousLine.isNotEmpty && previousLine != line) {
        changes += 1;
      }
      previousLine = line;
    }
    return changes;
  }

  List<String> _evidenceSummary(local.LocalRouteResult result) {
    if (result.steps.isEmpty) {
      return const [];
    }
    final requiresAccessibilityCheck = result.steps.any(
      (step) =>
          step.type.name == 'entry' ||
          step.type.name == 'exit' ||
          step.stairAccessState == 'unknown',
    );
    final hasDurationEstimate = result.steps.every(
      (step) => step.durationSeconds > 0,
    );
    final hasDistanceMeasure = result.steps.every(
      (step) => step.distanceMeters > 0,
    );
    return [
      requiresAccessibilityCheck
          ? 'ACCESSIBILITY_CHECK_REQUIRED'
          : 'ACCESSIBILITY_VERIFIED',
      hasDurationEstimate ? 'DURATION_ESTIMATED' : 'DURATION_UNKNOWN',
      hasDistanceMeasure ? 'DISTANCE_MEASURED' : 'DISTANCE_UNKNOWN',
    ];
  }

  String _stepTitle(
    String type,
    String fromName,
    String toName,
    String lineName,
  ) {
    return switch (type) {
      'ride' => '$fromName에서 $toName까지 $lineName 이동',
      'transfer' || 'inStationTransfer' => '$fromName에서 환승',
      'outOfStationTransfer' => '역 밖으로 이동해 $toName에서 환승',
      'entry' => '$fromName역 승강장 접근',
      'exit' => '$toName역 출구 접근',
      'walkway' => '$fromName에서 $toName까지 통로 이동',
      'elevator' => '$fromName에서 $toName까지 엘리베이터 이동',
      'ramp' => '$fromName에서 $toName까지 경사로 이동',
      'stair' => '$fromName에서 $toName까지 계단 이동',
      'escalator' => '$fromName에서 $toName까지 에스컬레이터 이동',
      'facilityConnector' => '$fromName에서 $toName까지 시설 연결 통로 이동',
      _ => '$fromName에서 $toName까지 이동',
    };
  }

  String _stepDescription(String type, String fromName, String toName) {
    return switch (type) {
      'ride' => '$fromName에서 $toName까지 열차를 이용합니다.',
      'transfer' || 'inStationTransfer' => '$fromName에서 다른 노선으로 갈아탑니다.',
      'outOfStationTransfer' => '역 밖으로 이동해 $toName에서 다른 노선으로 갈아탑니다.',
      'entry' => '계단 없는 동선을 우선해 승강장으로 이동합니다.',
      'exit' => '도착역에서 계단 없는 출구 동선을 확인합니다.',
      'walkway' => '확인된 통로를 따라 이동합니다.',
      'elevator' => '엘리베이터를 이용해 이동합니다.',
      'ramp' => '경사로를 따라 이동합니다.',
      'stair' => '계단 구간입니다. 계단 없는 조건에서는 안내하지 않습니다.',
      'escalator' => '에스컬레이터를 이용해 이동합니다.',
      'facilityConnector' => '역 시설 연결 동선을 따라 이동합니다.',
      _ => '$fromName에서 $toName까지 이동합니다.',
    };
  }

  String _stepActionTitle(String type) {
    return switch (type) {
      'ride' => '열차 이동',
      'transfer' || 'inStationTransfer' => '환승',
      'outOfStationTransfer' => '역외 환승',
      'entry' => '승강장 접근',
      'exit' => '출구 접근',
      'walkway' => '통로 이동',
      'elevator' => '엘리베이터 이동',
      'ramp' => '경사로 이동',
      'stair' => '계단 이동',
      'escalator' => '에스컬레이터 이동',
      'facilityConnector' => '시설 연결 이동',
      _ => '이동',
    };
  }

  String _stepActionDetail(
    String type,
    String fromName,
    String toName,
    String lineName,
  ) {
    return switch (type) {
      'ride' =>
        '$fromName에서 $toName까지 ${lineName.isEmpty ? '열차' : lineName}를 이용합니다.',
      'transfer' || 'inStationTransfer' => '$fromName에서 다음 노선으로 갈아탈 준비를 합니다.',
      'outOfStationTransfer' => '역 밖으로 이동해 $toName에서 다음 노선으로 갈아탑니다.',
      'entry' => '$fromName역에서 계단 없는 승강장 접근 동선을 이용합니다.',
      'exit' => '$toName역에서 계단 없는 출구 동선을 확인합니다.',
      'walkway' => '$fromName에서 $toName까지 통로를 따라 이동합니다.',
      'elevator' => '$fromName에서 $toName까지 엘리베이터를 이용합니다.',
      'ramp' => '$fromName에서 $toName까지 경사로를 이용합니다.',
      'stair' => '$fromName에서 $toName까지 계단으로 이동하는 구간입니다.',
      'escalator' => '$fromName에서 $toName까지 에스컬레이터를 이용합니다.',
      'facilityConnector' => '$fromName에서 $toName까지 역 시설 연결 동선을 이용합니다.',
      _ => '$fromName에서 $toName까지 이동합니다.',
    };
  }

  bool _isRouteTransferStepType(String stepType) {
    return stepType == 'transfer' ||
        stepType == 'inStationTransfer' ||
        stepType == 'outOfStationTransfer';
  }

  String _stepReason() {
    return '선택한 길을 따라 안내합니다.';
  }

  List<String> _recommendationReasons(local.LocalRouteResult result) {
    if (result.status != local.RouteStatus.found) {
      return const [];
    }

    return [
      '현재 저장된 안내로 경로 단계를 계산했어요.',
      '출구와 시설 상태는 현장 안내를 함께 확인해 주세요.',
      if (result.warnings.isNotEmpty) '다시 볼 구간은 주의 안내와 함께 표시합니다.',
    ];
  }

  String _blockedReasonMessage(String code) {
    return switch (code) {
      'STAIR_ONLY_ACCESS' => '계단 없는 경로를 아직 찾지 못했어요.',
      'STAIR_ONLY_ACCESS_UNKNOWN' => '계단 없는 길인지 아직 알 수 없어요.',
      'GENERATED_CONNECTOR_UNVERIFIED' => '계단 없는 길인지 아직 알 수 없어요.',
      'FACILITY_UNAVAILABLE' => '꼭 필요한 시설을 지금 이용하기 어려워요.',
      'ACCESSIBILITY_STATE_UNKNOWN' => '엘리베이터와 통로 상태를 아직 알 수 없어요.',
      'STALE_ACCESSIBILITY_DATA' => '오래된 안내라 계단 없는 경로로 안내하지 않아요.',
      'BLOCKED_UNVERIFIED_EDGE' => '검증되지 않은 경로는 안내하지 않아요.',
      'BLOCKED_MISSING_EVIDENCE_HASH' => '검증 근거가 없는 경로는 안내하지 않아요.',
      'BLOCKED_PLACEHOLDER_EVIDENCE_HASH' => '임시 근거만 있는 경로는 안내하지 않아요.',
      'BLOCKED_UNSUPPORTED_SCOPE' => '지원 범위 밖 경로는 안내하지 않아요.',
      'STRICT_EVIDENCE_UNSUPPORTED' => '검증 근거가 부족해 계단 없는 경로로 안내하지 않아요.',
      'ROUTE_GRAPH_UNKNOWN' => '길이 이어지는지 아직 확인하지 못했어요.',
      _ => '안내할 수 있는 경로를 아직 찾지 못했어요.',
    };
  }

  local.MobilityType _mobilityType(String mobilityType) {
    return switch (mobilityType) {
      'SENIOR' => local.MobilityType.senior,
      'STROLLER' => local.MobilityType.stroller,
      'WHEELCHAIR' => local.MobilityType.wheelchair,
      'PREGNANT' => local.MobilityType.pregnant,
      'TEMPORARY_INJURY' => local.MobilityType.temporaryInjury,
      'LUGGAGE' => local.MobilityType.luggage,
      _ => throw const RouteSearchException('지원하지 않는 이동 조건입니다.'),
    };
  }

  local.ConstraintMode _constraintMode(String constraintMode) {
    return switch (constraintMode) {
      'STRICT_STEP_FREE' => local.ConstraintMode.strictStepFree,
      'PREFER_STEP_FREE' => local.ConstraintMode.preferStepFree,
      'ALLOW_WITH_WARNINGS' => local.ConstraintMode.allowWithWarnings,
      _ => throw const RouteSearchException('지원하지 않는 이동 제약 조건입니다.'),
    };
  }
}

class LocalFirstRouteSearchRepository implements RouteSearchRepository {
  const LocalFirstRouteSearchRepository({required this.localRepository});

  final LocalRouteRepository localRepository;

  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request) async {
    return localRepository.searchRoute(request);
  }
}

class _RouteCatalogSnapshot {
  const _RouteCatalogSnapshot({
    required this.stationsById,
    required this.linesById,
    required this.stationLines,
    required this.networkEdges,
    required this.strictEvidenceSupported,
  });

  final Map<String, String> stationsById;
  final Map<String, String> linesById;
  final List<_StationLineSnapshot> stationLines;
  final List<_NetworkEdgeSnapshot> networkEdges;
  final bool strictEvidenceSupported;

  static Future<_RouteCatalogSnapshot> load(CatalogDatabase database) async {
    final stationRows = await database
        .customSelect('SELECT id, name_ko FROM stations')
        .get();
    final lineRows = await database
        .customSelect('SELECT id, name_ko FROM lines')
        .get();
    final stationLineRows = await database.customSelect('''
          SELECT station_id, line_id, line_sequence
          FROM station_lines
          ORDER BY line_id, line_sequence
          ''').get();
    final networkEdgeColumns = await database
        .customSelect('PRAGMA table_info(network_edges)')
        .get();
    final networkEdgeColumnNames = {
      for (final row in networkEdgeColumns) row.read<String>('name'),
    };
    final servicePatternSql = _selectNetworkEdgeColumn(
      networkEdgeColumnNames,
      'service_pattern',
      "''",
    );
    final edgeTypeSql = _selectNetworkEdgeColumn(
      networkEdgeColumnNames,
      'edge_type',
      "'UNKNOWN'",
    );
    final includesStairsSql = _selectNetworkEdgeColumn(
      networkEdgeColumnNames,
      'includes_stairs',
      '0',
    );
    final stairAccessStateSql =
        networkEdgeColumnNames.contains('stair_access_state')
        ? 'stair_access_state'
        : "CASE WHEN $includesStairsSql != 0 THEN 'STAIR_ONLY' ELSE 'UNKNOWN' END";
    final accessibilityStatusSql = _selectNetworkEdgeColumn(
      networkEdgeColumnNames,
      'accessibility_status',
      "'UNKNOWN'",
    );
    final reliabilityScoreSql = _selectNetworkEdgeColumn(
      networkEdgeColumnNames,
      'reliability_score',
      '40',
    );
    final lastVerifiedAtSql = _selectNetworkEdgeColumn(
      networkEdgeColumnNames,
      'last_verified_at',
      'NULL',
    );
    final sourceIdSql = _selectNetworkEdgeColumn(
      networkEdgeColumnNames,
      'source_id',
      "''",
    );
    final sourceSnapshotIdSql = _selectNetworkEdgeColumn(
      networkEdgeColumnNames,
      'source_snapshot_id',
      "''",
    );
    final providerRecordHashSql = _selectNetworkEdgeColumn(
      networkEdgeColumnNames,
      'provider_record_hash',
      "''",
    );
    final provenanceKindSql = _selectNetworkEdgeColumn(
      networkEdgeColumnNames,
      'provenance_kind',
      "'UNKNOWN'",
    );
    final verificationStatusSql = _selectNetworkEdgeColumn(
      networkEdgeColumnNames,
      'verification_status',
      "'UNKNOWN'",
    );
    final evidenceHashSql = _selectNetworkEdgeColumn(
      networkEdgeColumnNames,
      'evidence_hash',
      "''",
    );
    final distanceMetersSql = _selectNetworkEdgeColumn(
      networkEdgeColumnNames,
      'distance_meters',
      '0',
    );
    final facilityIdSql = _selectNetworkEdgeColumn(
      networkEdgeColumnNames,
      'facility_id',
      'NULL',
    );
    final facilityColumns = await database
        .customSelect('PRAGMA table_info(facilities)')
        .get();
    final facilityColumnNames = {
      for (final row in facilityColumns) row.read<String>('name'),
    };
    final operationalStatusSql = _selectFacilityColumn(
      facilityColumnNames,
      'operational_status',
      'NULL',
    );
    final hasDataQualityRecords = await _tableExists(
      database,
      'data_quality_records',
    );
    final facilityRows = await database
        .customSelect(
          hasDataQualityRecords
              ? '''
          SELECT f.id,
                 f.station_id,
                 f.type,
                 f.status,
                 $operationalStatusSql AS operational_status,
                 (
                   SELECT q.quality_level
                   FROM data_quality_records q
                   WHERE UPPER(q.target_type) = 'FACILITY'
                     AND q.target_id = f.id
                   ORDER BY q.checked_at IS NULL, q.checked_at DESC, q.id DESC
                   LIMIT 1
                 ) AS quality_level,
                 (
                   SELECT q.checked_at
                   FROM data_quality_records q
                   WHERE UPPER(q.target_type) = 'FACILITY'
                     AND q.target_id = f.id
                   ORDER BY q.checked_at IS NULL, q.checked_at DESC, q.id DESC
                   LIMIT 1
                 ) AS checked_at
          FROM facilities f
          ORDER BY f.id
          '''
              : '''
          SELECT f.id,
                 f.station_id,
                 f.type,
                 f.status,
                 $operationalStatusSql AS operational_status,
                 NULL AS quality_level,
                 NULL AS checked_at
          FROM facilities f
          ORDER BY f.id
          ''',
        )
        .get();
    final facilitiesById = {
      for (final row in facilityRows)
        row.read<String>('id'): _FacilitySnapshot(
          id: row.read<String>('id'),
          stationId: row.read<String>('station_id'),
          type: row.read<String>('type'),
          status: row.read<String>('status'),
          operationalStatus: row.readNullable<String>('operational_status'),
          qualityLevel: row.readNullable<String>('quality_level'),
          checkedAtSeconds: row.readNullable<int>('checked_at'),
          activeStatusSnapshot: null,
          expiredStatusSnapshot: null,
        ),
    };
    final facilityStatusSnapshots = await _facilityStatusSnapshots(database);
    final facilitiesWithStatusSnapshotsById = {
      for (final entry in facilitiesById.entries)
        entry.key: entry.value.copyWithStatusSnapshots(
          activeStatusSnapshot:
              facilityStatusSnapshots.activeByFacilityId[entry.key],
          expiredStatusSnapshot:
              facilityStatusSnapshots.expiredByFacilityId[entry.key],
        ),
    };
    final eligibleFacilityEvidence = await _eligibleFacilityEvidence(database);
    final networkEdgeRows = await database.customSelect('''
          SELECT id, from_node_id, to_node_id, duration_seconds,
                 $edgeTypeSql AS edge_type,
                 $distanceMetersSql AS distance_meters,
                 $servicePatternSql AS service_pattern,
                 $includesStairsSql AS includes_stairs,
                 $stairAccessStateSql AS stair_access_state,
                 $accessibilityStatusSql AS accessibility_status,
                 $reliabilityScoreSql AS reliability_score,
                 $lastVerifiedAtSql AS last_verified_at,
                 $sourceIdSql AS source_id,
                 $sourceSnapshotIdSql AS source_snapshot_id,
                 $providerRecordHashSql AS provider_record_hash,
                 $provenanceKindSql AS provenance_kind,
                 $verificationStatusSql AS verification_status,
                 $evidenceHashSql AS evidence_hash,
                 $facilityIdSql AS facility_id
          FROM network_edges
          ORDER BY id
          ''').get();
    final networkEdges = networkEdgeRows
        .map((row) {
          final facility =
              facilitiesWithStatusSnapshotsById[row.readNullable<String>(
                'facility_id',
              )];
          final facilityHasEligibleEvidence =
              facility == null ||
              eligibleFacilityEvidence.contains(
                _stationFacilityEvidenceKey(
                  stationId: facility.stationId,
                  lineId: _facilityLineIdForEdge(
                    row.read<String>('from_node_id'),
                    row.read<String>('to_node_id'),
                  ),
                  facilityType: facility.type,
                ),
              );
          final accessibilityStatus = row.read<String>('accessibility_status');
          final reliabilityScore = row.read<int>('reliability_score');
          final lastVerifiedAtSeconds = row.readNullable<int>(
            'last_verified_at',
          );
          return _NetworkEdgeSnapshot(
            id: row.read<String>('id'),
            fromNodeId: row.read<String>('from_node_id'),
            toNodeId: row.read<String>('to_node_id'),
            durationSeconds: row.read<int>('duration_seconds'),
            distanceMeters: row.read<int>('distance_meters'),
            edgeType: row.read<String>('edge_type'),
            servicePattern: row.read<String>('service_pattern'),
            includesStairs: row.read<int>('includes_stairs') != 0,
            stairAccessState: row.read<String>('stair_access_state'),
            accessibilityStatus: _effectiveAccessibilityStatus(
              accessibilityStatus,
              facility,
              facilityHasEligibleEvidence,
            ),
            reliabilityScore: _effectiveReliabilityScore(
              reliabilityScore,
              facility,
            ),
            lastVerifiedAtSeconds: _effectiveLastVerifiedAtSeconds(
              lastVerifiedAtSeconds,
              facility,
            ),
            sourceId:
                facility?.activeStatusSnapshot?.sourceId ??
                row.read<String>('source_id'),
            sourceSnapshotId:
                facility?.activeStatusSnapshot?.sourceSnapshotId ??
                row.read<String>('source_snapshot_id'),
            providerRecordHash:
                facility?.activeStatusSnapshot?.providerRecordHash ??
                row.read<String>('provider_record_hash'),
            provenanceKind:
                facility?.activeStatusSnapshot?.provenanceKind ??
                row.read<String>('provenance_kind'),
            verificationStatus:
                facility?.activeStatusSnapshot?.verificationStatus ??
                row.read<String>('verification_status'),
            evidenceHash:
                facility?.activeStatusSnapshot?.evidenceHash ??
                row.read<String>('evidence_hash'),
          );
        })
        .toList(growable: false);
    final strictEvidenceSupported =
        networkEdgeColumnNames.containsAll({
          'source_id',
          'provenance_kind',
          'verification_status',
          'evidence_hash',
        }) &&
        networkEdges.any((edge) => edge.safetyEvidence.strictRouteEligible);

    return _RouteCatalogSnapshot(
      stationsById: {
        for (final row in stationRows)
          row.read<String>('id'): row.read<String>('name_ko'),
      },
      linesById: {
        for (final row in lineRows)
          row.read<String>('id'): row.read<String>('name_ko'),
      },
      stationLines: stationLineRows
          .map(
            (row) => _StationLineSnapshot(
              stationId: row.read<String>('station_id'),
              lineId: row.read<String>('line_id'),
              sequence: row.read<int>('line_sequence'),
            ),
          )
          .toList(growable: false),
      networkEdges: networkEdges,
      strictEvidenceSupported: strictEvidenceSupported,
    );
  }

  graph.NetworkGraph toGraph() {
    final nodes = <graph.RouteNode>[];
    final edges = <graph.RouteEdge>[];
    final nodeKeysByStation = <String, Map<String, _RouteNodeKey>>{};
    final explicitAccessPairs = <String>{};
    final actualExplicitTransferPairs = <String>{};
    final explicitTransferPairs = <String>{};
    final explicitTransferLinePairs = <String>{};
    final stationLineKeys = {
      for (final stationLine in stationLines)
        _stationLineKey(stationLine.stationId, stationLine.lineId),
    };

    for (final stationLine in stationLines) {
      _addRouteNodeKey(nodeKeysByStation, stationLine.routeNodeKey);
    }

    for (final networkEdge in networkEdges) {
      if (networkEdge.routeEdgeType == null) {
        continue;
      }
      final fromNode = _RouteNodeKey.tryParse(networkEdge.fromNodeId);
      final toNode = _RouteNodeKey.tryParse(networkEdge.toNodeId);
      if (fromNode != null && _hasStationLine(fromNode, stationLineKeys)) {
        _addRouteNodeKey(nodeKeysByStation, fromNode);
      }
      if (toNode != null && _hasStationLine(toNode, stationLineKeys)) {
        _addRouteNodeKey(nodeKeysByStation, toNode);
      }
      final routeEdgeType = networkEdge.routeEdgeType;
      if (routeEdgeType == graph.RouteEdgeType.entry ||
          routeEdgeType == graph.RouteEdgeType.exit) {
        explicitAccessPairs.add(
          _edgePairKey(networkEdge.fromNodeId, networkEdge.toNodeId),
        );
      }
    }

    for (final networkEdge in networkEdges) {
      final routeEdgeType = networkEdge.routeEdgeType;
      if (routeEdgeType == null ||
          !graph.isRouteTransferEdgeType(routeEdgeType)) {
        continue;
      }
      final fromNode = _RouteNodeKey.tryParse(networkEdge.fromNodeId);
      final toNode = _RouteNodeKey.tryParse(networkEdge.toNodeId);
      if (fromNode == null || toNode == null) {
        continue;
      }
      actualExplicitTransferPairs.add(
        _edgePairKey(networkEdge.fromNodeId, networkEdge.toNodeId),
      );
      for (final pair in _expandedExplicitEdgePairs(
        networkEdge,
        nodeKeysByStation,
      )) {
        explicitTransferPairs.add(_edgePairKey(pair.fromNodeId, pair.toNodeId));
      }
      explicitTransferPairs.add(_edgePairKey(fromNode.nodeId, toNode.nodeId));
      if (routeEdgeType == graph.RouteEdgeType.inStationTransfer) {
        explicitTransferPairs.add(_edgePairKey(toNode.nodeId, fromNode.nodeId));
      }
      if (_isBaseStationLineNode(fromNode) && _isBaseStationLineNode(toNode)) {
        explicitTransferLinePairs.add(_lineTransferPairKey(fromNode, toNode));
        explicitTransferLinePairs.add(_lineTransferPairKey(toNode, fromNode));
      }
    }

    final expandedExplicitEdges = <graph.RouteEdge>[];
    for (final networkEdge in networkEdges) {
      final routeEdgeType = networkEdge.routeEdgeType;
      if (routeEdgeType == null) {
        continue;
      }
      if (routeEdgeType != graph.RouteEdgeType.entry &&
          routeEdgeType != graph.RouteEdgeType.exit &&
          !graph.isRouteTransferEdgeType(routeEdgeType)) {
        continue;
      }
      for (final pair in _expandedExplicitEdgePairs(
        networkEdge,
        nodeKeysByStation,
      )) {
        if (pair.fromNodeId == networkEdge.fromNodeId &&
            pair.toNodeId == networkEdge.toNodeId) {
          continue;
        }
        final pairKey = _edgePairKey(pair.fromNodeId, pair.toNodeId);
        if (graph.isRouteTransferEdgeType(routeEdgeType) &&
            actualExplicitTransferPairs.contains(pairKey)) {
          continue;
        }
        if (routeEdgeType == graph.RouteEdgeType.entry ||
            routeEdgeType == graph.RouteEdgeType.exit) {
          if (explicitAccessPairs.contains(pairKey)) {
            continue;
          }
          explicitAccessPairs.add(pairKey);
        }
        expandedExplicitEdges.add(
          _toGraphRouteEdge(
            networkEdge,
            routeEdgeType,
            id: '${networkEdge.id}@$pairKey',
            fromNodeId: pair.fromNodeId,
            toNodeId: pair.toNodeId,
          ),
        );
      }
    }

    for (final stationLine in stationLines) {
      final stationNodes = nodeKeysByStation[stationLine.stationId]?.values;
      if (stationNodes == null) {
        continue;
      }
      for (final nodeKey in stationNodes.where(
        (nodeKey) => nodeKey.lineId == stationLine.lineId,
      )) {
        nodes.add(
          graph.RouteNode(
            id: nodeKey.nodeId,
            stationId: nodeKey.stationId,
            lineId: nodeKey.lineId,
          ),
        );
        final accessEdgeSuffix = nodeKey.accessEdgeSuffix;
        if (!explicitAccessPairs.contains(
          _edgePairKey(stationLine.stationId, nodeKey.nodeId),
        )) {
          edges.add(
            graph.RouteEdge(
              id: 'entry-${stationLine.stationId}-${stationLine.lineId}$accessEdgeSuffix',
              fromNodeId: stationLine.stationId,
              toNodeId: nodeKey.nodeId,
              type: graph.RouteEdgeType.entry,
              baseCost: 90,
              stairAccessState: graph.RouteStairAccessState.unknown,
              isGeneratedConnector: true,
            ),
          );
        }
        if (!explicitAccessPairs.contains(
          _edgePairKey(nodeKey.nodeId, stationLine.stationId),
        )) {
          edges.add(
            graph.RouteEdge(
              id: 'exit-${stationLine.stationId}-${stationLine.lineId}$accessEdgeSuffix',
              fromNodeId: nodeKey.nodeId,
              toNodeId: stationLine.stationId,
              type: graph.RouteEdgeType.exit,
              baseCost: 60,
              stairAccessState: graph.RouteStairAccessState.unknown,
              isGeneratedConnector: true,
            ),
          );
        }
      }
    }

    // route contract: synthetic connector edge
    // These fixture-derived entry, exit, and transfer edges only connect known
    // station-line nodes when explicit source edges are absent. They are
    // UNKNOWN for strict mobility profiles because they are not proof of
    // field-verified elevator or ramp availability.
    for (final stationEntry in nodeKeysByStation.entries) {
      final stationId = stationEntry.key;
      final stationNodes = stationEntry.value.values.toList(growable: false);
      for (final from in stationNodes) {
        for (final to in stationNodes) {
          if (from.nodeId == to.nodeId) {
            continue;
          }
          if (!_isStationLineTransferAllowed(from, to, explicitAccessPairs)) {
            continue;
          }
          if (_hasExplicitTransferPair(
            from,
            to,
            explicitTransferPairs,
            explicitTransferLinePairs,
          )) {
            continue;
          }
          edges.add(
            graph.RouteEdge(
              id: 'transfer-$stationId-${from.transferEdgeSuffix}-${to.transferEdgeSuffix}',
              fromNodeId: from.nodeId,
              toNodeId: to.nodeId,
              type: graph.RouteEdgeType.inStationTransfer,
              baseCost: 140,
              transferStationId: stationId,
              stairAccessState: graph.RouteStairAccessState.unknown,
              isGeneratedConnector: true,
            ),
          );
        }
      }
    }

    edges.addAll(expandedExplicitEdges);

    for (final networkEdge in networkEdges) {
      final routeEdgeType = networkEdge.routeEdgeType;
      if (routeEdgeType == null) {
        continue;
      }
      edges.add(_toGraphRouteEdge(networkEdge, routeEdgeType));
    }

    return graph.NetworkGraph(nodes: nodes, edges: edges);
  }

  bool _hasStationLine(_RouteNodeKey nodeKey, Set<String> stationLineKeys) {
    return stationLineKeys.contains(
      _stationLineKey(nodeKey.stationId, nodeKey.lineId),
    );
  }

  String stationName(String stationId) {
    return stationsById[stationId] ?? '역 이름을 아직 알 수 없어요';
  }

  bool hasStation(String stationId) {
    return stationsById.containsKey(stationId);
  }

  String lineName(String lineId) {
    if (lineId.isEmpty) {
      return '';
    }
    return linesById[lineId] ?? lineId;
  }

  String stationIdForNode(String nodeId) {
    if (!nodeId.contains(':')) {
      return nodeId;
    }
    return nodeId.split(':').first;
  }
}

String _edgePairKey(String fromNodeId, String toNodeId) {
  return '$fromNodeId->$toNodeId';
}

List<({String fromNodeId, String toNodeId})> _expandedExplicitEdgePairs(
  _NetworkEdgeSnapshot networkEdge,
  Map<String, Map<String, _RouteNodeKey>> nodeKeysByStation,
) {
  final routeEdgeType = networkEdge.routeEdgeType;
  if (routeEdgeType == graph.RouteEdgeType.entry) {
    final toNode = _RouteNodeKey.tryParse(networkEdge.toNodeId);
    if (toNode == null) {
      return const [];
    }
    return [
      for (final candidate in _matchingNodeKeys(toNode, nodeKeysByStation))
        (fromNodeId: networkEdge.fromNodeId, toNodeId: candidate.nodeId),
    ];
  }
  if (routeEdgeType == graph.RouteEdgeType.exit) {
    final fromNode = _RouteNodeKey.tryParse(networkEdge.fromNodeId);
    if (fromNode == null) {
      return const [];
    }
    return [
      for (final candidate in _matchingNodeKeys(fromNode, nodeKeysByStation))
        (fromNodeId: candidate.nodeId, toNodeId: networkEdge.toNodeId),
    ];
  }
  if (routeEdgeType != null && graph.isRouteTransferEdgeType(routeEdgeType)) {
    final fromNode = _RouteNodeKey.tryParse(networkEdge.fromNodeId);
    final toNode = _RouteNodeKey.tryParse(networkEdge.toNodeId);
    if (fromNode == null || toNode == null) {
      return const [];
    }
    return [
      for (final from in _matchingNodeKeys(fromNode, nodeKeysByStation))
        for (final to in _matchingNodeKeys(toNode, nodeKeysByStation))
          if (from.nodeId != to.nodeId)
            (fromNodeId: from.nodeId, toNodeId: to.nodeId),
      if (routeEdgeType == graph.RouteEdgeType.inStationTransfer)
        for (final to in _matchingNodeKeys(toNode, nodeKeysByStation))
          for (final from in _matchingNodeKeys(fromNode, nodeKeysByStation))
            if (from.nodeId != to.nodeId)
              (fromNodeId: to.nodeId, toNodeId: from.nodeId),
    ];
  }
  return const [];
}

bool _isStationLineTransferAllowed(
  _RouteNodeKey from,
  _RouteNodeKey to,
  Set<String> explicitAccessPairs,
) {
  if (from.lineId != to.lineId) {
    return true;
  }
  if (from.servicePattern == to.servicePattern) {
    return false;
  }
  if (from.servicePattern.isNotEmpty && to.servicePattern.isNotEmpty) {
    return true;
  }

  final patternNode = from.servicePattern.isEmpty ? to : from;
  return !explicitAccessPairs.contains(
        _edgePairKey(patternNode.stationId, patternNode.nodeId),
      ) &&
      !explicitAccessPairs.contains(
        _edgePairKey(patternNode.nodeId, patternNode.stationId),
      );
}

List<_RouteNodeKey> _matchingNodeKeys(
  _RouteNodeKey nodeKey,
  Map<String, Map<String, _RouteNodeKey>> nodeKeysByStation,
) {
  if (nodeKey.servicePattern.isNotEmpty) {
    return [nodeKey];
  }
  return nodeKeysByStation[nodeKey.stationId]?.values
          .where((candidate) => candidate.lineId == nodeKey.lineId)
          .toList(growable: false) ??
      [nodeKey];
}

bool _hasExplicitTransferPair(
  _RouteNodeKey from,
  _RouteNodeKey to,
  Set<String> explicitTransferPairs,
  Set<String> explicitTransferLinePairs,
) {
  return explicitTransferPairs.contains(_edgePairKey(from.nodeId, to.nodeId)) ||
      explicitTransferLinePairs.contains(_lineTransferPairKey(from, to));
}

bool _isBaseStationLineNode(_RouteNodeKey nodeKey) {
  return nodeKey.servicePattern.isEmpty;
}

String _lineTransferPairKey(_RouteNodeKey from, _RouteNodeKey to) {
  return '${_stationLineKey(from.stationId, from.lineId)}'
      '->${_stationLineKey(to.stationId, to.lineId)}';
}

String _stationLineKey(String stationId, String lineId) {
  return '$stationId:$lineId';
}

graph.RouteEdge _toGraphRouteEdge(
  _NetworkEdgeSnapshot networkEdge,
  graph.RouteEdgeType routeEdgeType, {
  String? id,
  String? fromNodeId,
  String? toNodeId,
}) {
  final effectiveFromNodeId = fromNodeId ?? networkEdge.fromNodeId;

  // route contract: local metric fallback
  // Source durations of 0 keep `durationSeconds` at 0 so UI can say the time
  // needs checking, while `baseCost` gets a conservative 60-second routing
  // weight so the graph remains searchable.
  return graph.RouteEdge(
    id: id ?? networkEdge.id,
    fromNodeId: effectiveFromNodeId,
    toNodeId: toNodeId ?? networkEdge.toNodeId,
    type: routeEdgeType,
    baseCost: networkEdge.durationSeconds <= 0
        ? 60
        : networkEdge.durationSeconds,
    durationSeconds: networkEdge.durationSeconds <= 0
        ? 0
        : networkEdge.durationSeconds,
    lineId: _lineIdForNode(effectiveFromNodeId),
    distanceMeters: networkEdge.distanceMeters,
    includesStairs:
        routeEdgeType == graph.RouteEdgeType.stair ||
        networkEdge.includesStairs,
    stairAccessState: routeEdgeType == graph.RouteEdgeType.stair
        ? graph.RouteStairAccessState.stairOnly
        : networkEdge.routeStairAccessState,
    reliabilityScore: networkEdge.effectiveReliabilityScore,
    isDataStale: networkEdge.isDataStale,
    accessibilityState: networkEdge.accessibilityState,
    safetyEvidence: networkEdge.safetyEvidence,
  );
}

int _estimatedMinutesFor(int durationSeconds) {
  if (durationSeconds <= 0) {
    return 0;
  }
  return (durationSeconds / 60).ceil().clamp(1, 999);
}

String _lineIdForNode(String nodeId) {
  final parts = nodeId.split(':');
  if (parts.length < 2) {
    return '';
  }
  return parts[1];
}

String _selectNetworkEdgeColumn(
  Set<String> columnNames,
  String columnName,
  String fallbackExpression,
) {
  return columnNames.contains(columnName) ? columnName : fallbackExpression;
}

Future<bool> _tableExists(CatalogDatabase database, String tableName) async {
  final row = await database.customSelect('''
        SELECT name
        FROM sqlite_schema
        WHERE type = 'table'
          AND name = '$tableName'
        LIMIT 1
        ''').getSingleOrNull();
  return row != null;
}

class _StationLineSnapshot {
  const _StationLineSnapshot({
    required this.stationId,
    required this.lineId,
    required this.sequence,
  });

  final String stationId;
  final String lineId;
  final int sequence;

  _RouteNodeKey get routeNodeKey =>
      _RouteNodeKey(stationId: stationId, lineId: lineId, servicePattern: '');
}

class _FacilitySnapshot {
  const _FacilitySnapshot({
    required this.id,
    required this.stationId,
    required this.type,
    required this.status,
    required this.operationalStatus,
    required this.qualityLevel,
    required this.checkedAtSeconds,
    required this.activeStatusSnapshot,
    required this.expiredStatusSnapshot,
  });

  final String id;
  final String stationId;
  final String type;
  final String status;
  final String? operationalStatus;
  final String? qualityLevel;
  final int? checkedAtSeconds;
  final _FacilityStatusSnapshot? activeStatusSnapshot;
  final _FacilityStatusSnapshot? expiredStatusSnapshot;

  _FacilitySnapshot copyWithStatusSnapshots({
    required _FacilityStatusSnapshot? activeStatusSnapshot,
    required _FacilityStatusSnapshot? expiredStatusSnapshot,
  }) {
    return _FacilitySnapshot(
      id: id,
      stationId: stationId,
      type: type,
      status: status,
      operationalStatus: operationalStatus,
      qualityLevel: qualityLevel,
      checkedAtSeconds: checkedAtSeconds,
      activeStatusSnapshot: activeStatusSnapshot,
      expiredStatusSnapshot: expiredStatusSnapshot,
    );
  }
}

class _FacilityStatusSnapshot {
  const _FacilityStatusSnapshot({
    required this.facilityId,
    required this.providerId,
    required this.sourceId,
    required this.sourceSnapshotId,
    required this.providerRecordHash,
    required this.evidenceHash,
    required this.provenanceKind,
    required this.verificationStatus,
    required this.status,
    required this.operationalStatus,
    required this.confidence,
    required this.observedAtSeconds,
    required this.expiresAtSeconds,
  });

  final String facilityId;
  final String providerId;
  final String sourceId;
  final String sourceSnapshotId;
  final String providerRecordHash;
  final String evidenceHash;
  final String provenanceKind;
  final String verificationStatus;
  final String status;
  final String operationalStatus;
  final int confidence;
  final int? observedAtSeconds;
  final int? expiresAtSeconds;

  bool get isOperatorOverride {
    final normalized = providerId.toUpperCase().replaceAll('-', '_');
    return normalized == 'OPERATOR_OVERRIDE' || normalized == 'MANUAL_OVERRIDE';
  }

  bool isExpiredAt(int nowSeconds) {
    final expiresAt = expiresAtSeconds;
    return expiresAt != null && expiresAt > 0 && expiresAt < nowSeconds;
  }
}

class _FacilityStatusSnapshotIndex {
  const _FacilityStatusSnapshotIndex({
    required this.activeByFacilityId,
    required this.expiredByFacilityId,
  });

  const _FacilityStatusSnapshotIndex.empty()
    : activeByFacilityId = const {},
      expiredByFacilityId = const {};

  final Map<String, _FacilityStatusSnapshot> activeByFacilityId;
  final Map<String, _FacilityStatusSnapshot> expiredByFacilityId;
}

String _effectiveAccessibilityStatus(
  String edgeStatus,
  _FacilitySnapshot? facility,
  bool facilityHasEligibleEvidence,
) {
  final edgeStatusUpper = edgeStatus.toUpperCase();
  if (facility == null || edgeStatusUpper == 'UNAVAILABLE') {
    return edgeStatus;
  }
  final activeStatusSnapshot = facility.activeStatusSnapshot;
  if (activeStatusSnapshot != null) {
    final activeSnapshotStatus = _effectiveFacilityStatus(
      status: activeStatusSnapshot.status,
      operationalStatus: activeStatusSnapshot.operationalStatus,
    );
    if (activeSnapshotStatus == 'UNAVAILABLE') {
      return activeSnapshotStatus;
    }
    if (activeSnapshotStatus == 'UNKNOWN') {
      return activeSnapshotStatus;
    }
    if (activeSnapshotStatus == 'AVAILABLE') {
      if (!facilityHasEligibleEvidence) {
        return 'UNKNOWN';
      }
      return edgeStatus;
    }
  }
  final staticFacilityStatus = _effectiveFacilityStatus(
    status: facility.status,
    operationalStatus: facility.operationalStatus,
    fallbackForAvailable: edgeStatus,
  );
  if (staticFacilityStatus == 'UNAVAILABLE') {
    return staticFacilityStatus;
  }
  if (!facilityHasEligibleEvidence) {
    return 'UNKNOWN';
  }
  return staticFacilityStatus;
}

String _effectiveFacilityStatus({
  required String? status,
  required String? operationalStatus,
  String fallbackForAvailable = 'AVAILABLE',
}) {
  final operationalStatusUpper = operationalStatus?.toUpperCase();
  if (operationalStatusUpper == 'UNAVAILABLE' ||
      operationalStatusUpper == 'OUT_OF_SERVICE') {
    return 'UNAVAILABLE';
  }
  final statusUpper = status?.toUpperCase();
  if (statusUpper == 'BROKEN' ||
      statusUpper == 'UNDER_CONSTRUCTION' ||
      statusUpper == 'CLOSED' ||
      statusUpper == 'UNAVAILABLE' ||
      statusUpper == 'OUT_OF_SERVICE') {
    return 'UNAVAILABLE';
  }
  if (operationalStatusUpper == 'UNKNOWN' ||
      operationalStatusUpper == 'CHECK_REQUIRED' ||
      statusUpper == 'UNKNOWN' ||
      statusUpper == 'CHECK_REQUIRED' ||
      statusUpper == null) {
    return 'UNKNOWN';
  }
  if (statusUpper == 'NORMAL' ||
      statusUpper == 'AVAILABLE' ||
      statusUpper == 'IN_SERVICE' ||
      statusUpper == 'OPERATING' ||
      statusUpper == 'OPEN' ||
      statusUpper == 'ADMIN_VERIFIED') {
    return fallbackForAvailable;
  }
  return 'UNAVAILABLE';
}

Future<Set<String>> _eligibleFacilityEvidence(CatalogDatabase database) async {
  if (!await _tableExists(database, 'station_facility_evidence')) {
    return const {};
  }
  final rows = await database.customSelect('''
        SELECT station_id, line_id, facility_type
        FROM station_facility_evidence
        WHERE strict_route_eligible != 0
          AND UPPER(evidence_kind) = 'EXISTS'
        ''').get();
  return {
    for (final row in rows)
      _stationFacilityEvidenceKey(
        stationId: row.read<String>('station_id'),
        lineId: row.read<String>('line_id'),
        facilityType: row.read<String>('facility_type'),
      ),
  };
}

Future<_FacilityStatusSnapshotIndex> _facilityStatusSnapshots(
  CatalogDatabase database,
) async {
  if (!await _tableExists(database, 'facility_status_snapshots')) {
    return const _FacilityStatusSnapshotIndex.empty();
  }
  final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  final rows = await database.customSelect('''
        SELECT facility_id, provider_id, source_id, source_snapshot_id,
               provider_record_hash, evidence_hash, provenance_kind,
               verification_status, status, operational_status, confidence,
               observed_at, expires_at
        FROM facility_status_snapshots
        ORDER BY facility_id
        ''').get();
  final activeByFacilityId = <String, _FacilityStatusSnapshot>{};
  final expiredByFacilityId = <String, _FacilityStatusSnapshot>{};
  for (final row in rows) {
    final snapshot = _FacilityStatusSnapshot(
      facilityId: row.read<String>('facility_id'),
      providerId: row.read<String>('provider_id'),
      sourceId: row.read<String>('source_id'),
      sourceSnapshotId: row.read<String>('source_snapshot_id'),
      providerRecordHash: row.read<String>('provider_record_hash'),
      evidenceHash: row.read<String>('evidence_hash'),
      provenanceKind: row.read<String>('provenance_kind'),
      verificationStatus: row.read<String>('verification_status'),
      status: row.read<String>('status'),
      operationalStatus: row.read<String>('operational_status'),
      confidence: row.read<int>('confidence'),
      observedAtSeconds: row.readNullable<int>('observed_at'),
      expiresAtSeconds: row.readNullable<int>('expires_at'),
    );
    final targetMap = snapshot.isExpiredAt(nowSeconds)
        ? expiredByFacilityId
        : activeByFacilityId;
    final current = targetMap[snapshot.facilityId];
    if (current == null ||
        _compareFacilityStatusSnapshot(snapshot, current) > 0) {
      targetMap[snapshot.facilityId] = snapshot;
    }
  }
  return _FacilityStatusSnapshotIndex(
    activeByFacilityId: activeByFacilityId,
    expiredByFacilityId: expiredByFacilityId,
  );
}

int _compareFacilityStatusSnapshot(
  _FacilityStatusSnapshot left,
  _FacilityStatusSnapshot right,
) {
  final leftOverride = left.isOperatorOverride ? 1 : 0;
  final rightOverride = right.isOperatorOverride ? 1 : 0;
  if (leftOverride != rightOverride) {
    return leftOverride.compareTo(rightOverride);
  }
  final leftObservedAt = left.observedAtSeconds ?? 0;
  final rightObservedAt = right.observedAtSeconds ?? 0;
  if (leftObservedAt != rightObservedAt) {
    return leftObservedAt.compareTo(rightObservedAt);
  }
  return left.confidence.compareTo(right.confidence);
}

String _stationFacilityEvidenceKey({
  required String stationId,
  required String lineId,
  required String facilityType,
}) {
  return '$stationId:$lineId:${facilityType.toUpperCase()}';
}

String _facilityLineIdForEdge(String fromNodeId, String toNodeId) {
  final fromLineId = _lineIdForNode(fromNodeId);
  if (fromLineId.isNotEmpty) {
    return fromLineId;
  }
  return _lineIdForNode(toNodeId);
}

String _selectFacilityColumn(
  Set<String> columnNames,
  String columnName,
  String fallbackExpression,
) {
  return columnNames.contains(columnName)
      ? 'f.$columnName'
      : fallbackExpression;
}

int _effectiveReliabilityScore(
  int edgeReliabilityScore,
  _FacilitySnapshot? facility,
) {
  var score = edgeReliabilityScore;
  final activeSnapshotConfidence = facility?.activeStatusSnapshot?.confidence;
  if (activeSnapshotConfidence != null && activeSnapshotConfidence > 0) {
    score = score < activeSnapshotConfidence ? score : activeSnapshotConfidence;
  }
  if (facility?.expiredStatusSnapshot != null && score > 60) {
    score = 60;
  }
  final facilityReliabilityScore = _facilityQualityScore(
    facility?.qualityLevel,
  );
  if (facilityReliabilityScore != null && facilityReliabilityScore < score) {
    score = facilityReliabilityScore;
  }
  return score;
}

int? _effectiveLastVerifiedAtSeconds(
  int? edgeLastVerifiedAtSeconds,
  _FacilitySnapshot? facility,
) {
  final activeSnapshotObservedAt =
      facility?.activeStatusSnapshot?.observedAtSeconds;
  if (activeSnapshotObservedAt != null && activeSnapshotObservedAt > 0) {
    return _olderSecond(edgeLastVerifiedAtSeconds, activeSnapshotObservedAt);
  }
  final facilityCheckedAtSeconds = facility?.checkedAtSeconds;
  if (facilityCheckedAtSeconds == null) {
    return edgeLastVerifiedAtSeconds;
  }
  return _olderSecond(edgeLastVerifiedAtSeconds, facilityCheckedAtSeconds);
}

int _olderSecond(int? left, int right) {
  if (left == null) {
    return right;
  }
  return left < right ? left : right;
}

int? _facilityQualityScore(String? qualityLevel) {
  return switch (qualityLevel?.toUpperCase()) {
    'LEVEL_1' => 40,
    'LEVEL_2' => 60,
    'LEVEL_3' => 80,
    'LEVEL_4' => 100,
    'UNKNOWN' => 60,
    null => null,
    _ => 60,
  };
}

void _addRouteNodeKey(
  Map<String, Map<String, _RouteNodeKey>> nodeKeysByStation,
  _RouteNodeKey nodeKey,
) {
  nodeKeysByStation
      .putIfAbsent(nodeKey.stationId, () => <String, _RouteNodeKey>{})
      .putIfAbsent(nodeKey.nodeId, () => nodeKey);
}

class _RouteNodeKey {
  const _RouteNodeKey({
    required this.stationId,
    required this.lineId,
    required this.servicePattern,
  });

  final String stationId;
  final String lineId;
  final String servicePattern;

  static _RouteNodeKey? tryParse(String nodeId) {
    final parts = nodeId.split(':');
    if (parts.length < 2 || parts[0].isEmpty || parts[1].isEmpty) {
      return null;
    }
    return _RouteNodeKey(
      stationId: parts[0],
      lineId: parts[1],
      servicePattern: parts.length >= 3 ? parts.skip(2).join(':') : '',
    );
  }

  String get nodeId {
    if (servicePattern.isEmpty) {
      return '$stationId:$lineId';
    }
    return '$stationId:$lineId:$servicePattern';
  }

  String get accessEdgeSuffix {
    if (servicePattern.isEmpty) {
      return '';
    }
    return '-${servicePattern.toLowerCase()}';
  }

  String get transferEdgeSuffix {
    if (servicePattern.isEmpty) {
      return lineId;
    }
    return '$lineId-${servicePattern.toLowerCase()}';
  }
}

class _NetworkEdgeSnapshot {
  const _NetworkEdgeSnapshot({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.edgeType,
    required this.servicePattern,
    required this.includesStairs,
    required this.stairAccessState,
    required this.accessibilityStatus,
    required this.reliabilityScore,
    required this.lastVerifiedAtSeconds,
    required this.sourceId,
    required this.sourceSnapshotId,
    required this.providerRecordHash,
    required this.provenanceKind,
    required this.verificationStatus,
    required this.evidenceHash,
  });

  final String id;
  final String fromNodeId;
  final String toNodeId;
  final int durationSeconds;
  final int distanceMeters;
  final String edgeType;
  final String servicePattern;
  final bool includesStairs;
  final String stairAccessState;
  final String accessibilityStatus;
  final int reliabilityScore;
  final int? lastVerifiedAtSeconds;
  final String sourceId;
  final String sourceSnapshotId;
  final String providerRecordHash;
  final String provenanceKind;
  final String verificationStatus;
  final String evidenceHash;

  graph.RouteEdgeType? get routeEdgeType =>
      graph.routeEdgeTypeFromCatalogValue(edgeType);

  String get _accessibilityStatusUpper => accessibilityStatus.toUpperCase();

  String get _stairAccessStateUpper => stairAccessState.toUpperCase();

  graph.RouteStairAccessState get routeStairAccessState {
    return switch (_stairAccessStateUpper) {
      'STEP_FREE' => graph.RouteStairAccessState.stepFree,
      'STAIR_ONLY' => graph.RouteStairAccessState.stairOnly,
      _ => graph.RouteStairAccessState.unknown,
    };
  }

  graph.RouteAccessibilityState get accessibilityState {
    return switch (_accessibilityStatusUpper) {
      'UNAVAILABLE' => graph.RouteAccessibilityState.unavailable,
      'UNKNOWN' => graph.RouteAccessibilityState.unknown,
      _ => graph.RouteAccessibilityState.available,
    };
  }

  int get effectiveReliabilityScore {
    // UNKNOWN accessibility is stale by definition and cannot carry a high
    // confidence score into accessibility-safe routing.
    if (_accessibilityStatusUpper == 'UNKNOWN' && reliabilityScore > 60) {
      return 60;
    }
    return reliabilityScore;
  }

  bool get isDataStale {
    if (_accessibilityStatusUpper == 'UNKNOWN') {
      return true;
    }
    final verifiedAt = lastVerifiedAtSeconds;
    if (verifiedAt == null) {
      return false;
    }
    final verifiedDate = DateTime.fromMillisecondsSinceEpoch(
      verifiedAt * 1000,
      isUtc: true,
    );
    return verifiedDate.isBefore(
      DateTime.now().toUtc().subtract(const Duration(days: 365)),
    );
  }

  graph.RouteEdgeSafetyEvidence get safetyEvidence {
    final verifiedAt = lastVerifiedAtSeconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            lastVerifiedAtSeconds! * 1000,
            isUtc: true,
          );
    final evidenceHashValid = _isValidEvidenceHash(evidenceHash);
    final isPlaceholderEvidence = _isPlaceholderEvidenceHash(evidenceHash);
    final blockerReasons = _strictRouteBlockerReasons(
      sourceId: sourceId,
      sourceSnapshotId: sourceSnapshotId,
      providerRecordHash: providerRecordHash,
      provenanceKind: provenanceKind,
      verificationStatus: verificationStatus,
      evidenceHash: evidenceHash,
      lastVerifiedAt: verifiedAt,
      evidenceHashValid: evidenceHashValid,
      isPlaceholderEvidence: isPlaceholderEvidence,
    );
    return graph.RouteEdgeSafetyEvidence(
      sourceId: sourceId,
      sourceSnapshotId: sourceSnapshotId,
      providerRecordHash: providerRecordHash,
      provenanceKind: provenanceKind,
      verificationStatus: verificationStatus,
      evidenceHash: evidenceHash,
      evidenceHashValid: evidenceHashValid,
      isPlaceholderEvidence: isPlaceholderEvidence,
      lastVerifiedAt: verifiedAt,
      isStale: isDataStale,
      isGeneratedConnector: false,
      strictRouteEligible: blockerReasons.isEmpty,
      blockerReasons: blockerReasons,
    );
  }
}

List<String> _strictRouteBlockerReasons({
  required String sourceId,
  required String sourceSnapshotId,
  required String providerRecordHash,
  required String provenanceKind,
  required String verificationStatus,
  required String evidenceHash,
  required DateTime? lastVerifiedAt,
  required bool evidenceHashValid,
  required bool isPlaceholderEvidence,
}) {
  if (sourceId.isEmpty || sourceSnapshotId.isEmpty || lastVerifiedAt == null) {
    return const ['BLOCKED_UNVERIFIED_EDGE'];
  }
  if (verificationStatus.toUpperCase() != 'VERIFIED') {
    return const ['BLOCKED_UNVERIFIED_EDGE'];
  }
  if (!_allowedStrictProvenanceKinds.contains(provenanceKind.toUpperCase())) {
    return const ['BLOCKED_UNSUPPORTED_SCOPE'];
  }
  if (!evidenceHashValid || !_isValidEvidenceHash(providerRecordHash)) {
    return const ['BLOCKED_MISSING_EVIDENCE_HASH'];
  }
  if (isPlaceholderEvidence) {
    return const ['BLOCKED_PLACEHOLDER_EVIDENCE_HASH'];
  }
  return const [];
}

const _allowedStrictProvenanceKinds = {
  'OFFICIAL_SOURCE',
  'OPERATOR_CONFIRMED',
  'FIELD_SURVEY',
};

bool _isValidEvidenceHash(String value) {
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
}

bool _isPlaceholderEvidenceHash(String value) {
  return RegExp(r'^([0-9a-f])\1{63}$').hasMatch(value);
}
