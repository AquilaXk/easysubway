import 'package:drift/drift.dart';

import '../../../core/database/catalog/catalog_database.dart'
    hide InternalRouteNode;
import '../../../internal_route.dart';
import '../../routes/domain/route_request.dart' as local;
import '../../routes/domain/route_result.dart' as local;
import '../application/internal_route_engine.dart' as engine;

class LocalInternalRouteRepository implements InternalRouteRepository {
  LocalInternalRouteRepository({required this.catalogDatabase});

  final CatalogDatabase catalogDatabase;

  Future<bool> hasRouteNodes(String stationId) async {
    final rows = await _routeNodeRows(stationId);
    return rows.isNotEmpty;
  }

  @override
  Future<List<InternalRouteNode>> listRouteNodes(String stationId) async {
    final rows = await _routeNodeRows(stationId);

    return rows
        .map(
          (row) => InternalRouteNode(
            id: row.read<String>('id'),
            stationId: row.read<String>('station_id'),
            type: row.read<String>('node_type'),
            name: row.read<String>('label'),
            facilityId: '',
            displayLabel: row.read<String>('label'),
          ),
        )
        .toList(growable: false);
  }

  Future<List<QueryRow>> _routeNodeRows(String stationId) {
    return catalogDatabase
        .customSelect(
          '''
      SELECT id, station_id, label, node_type
      FROM internal_route_nodes
      WHERE station_id = ?
      ORDER BY id
      ''',
          variables: [Variable.withString(stationId.trim())],
        )
        .get();
  }

  @override
  Future<InternalRouteResult> searchInternalRoute(
    InternalRouteRequest request,
  ) async {
    final snapshot = await _InternalRouteSnapshot.load(
      catalogDatabase,
      request.stationId,
    );
    final result = engine.LocalInternalRouteEngine(graph: snapshot.toGraph())
        .search(
          local.InternalRouteSearchRequest(
            stationId: request.stationId,
            fromNodeId: request.fromNodeId,
            toNodeId: request.toNodeId,
            mobilityType: _mobilityType(request.mobilityType),
          ),
        );

    if (result.status == local.RouteStatus.blocked) {
      return _blockedResult(request, snapshot, result.blockedReasonCodes);
    }

    final steps = <InternalRouteStep>[];
    for (final edgeId in result.edgeIds) {
      final edge = snapshot.edgesById[edgeId];
      if (edge == null) {
        continue;
      }
      steps.add(
        InternalRouteStep(
          sequence: steps.length + 1,
          edgeId: edge.id,
          fromNodeId: edge.fromNodeId,
          fromNodeName: snapshot.nodeName(edge.fromNodeId),
          toNodeId: edge.toNodeId,
          toNodeName: snapshot.nodeName(edge.toNodeId),
          edgeType: edge.edgeType,
          distanceMeters: edge.distanceMeters,
          estimatedSeconds: edge.estimatedSeconds,
          includesStairs: edge.includesStairs,
          requiresElevator: edge.requiresElevator,
          requiresEscalator: edge.requiresEscalator,
          slopeLevel: edge.slopeLevel,
          widthLevel: edge.widthLevel,
          reliabilityScore: edge.reliabilityScore,
          guidance: edge.guidance,
          fieldValidationStatus: edge.fieldValidationStatus,
        ),
      );
    }

    return InternalRouteResult(
      stationId: request.stationId,
      stationName: snapshot.stationName,
      fromNodeId: request.fromNodeId,
      fromNodeName: snapshot.nodeName(request.fromNodeId),
      toNodeId: request.toNodeId,
      toNodeName: snapshot.nodeName(request.toNodeId),
      mobilityType: request.mobilityType,
      status: 'FOUND',
      totalDistanceMeters: result.totalDistanceMeters,
      totalEstimatedSeconds: result.totalEstimatedSeconds,
      steps: steps,
      warnings: result.warningCodes
          .map(
            (code) => InternalRouteWarning(
              code: code,
              message: '역 내부 이동 전 현장 안내를 확인해 주세요.',
            ),
          )
          .toList(growable: false),
      blockedReasons: const [],
    );
  }

  InternalRouteResult _blockedResult(
    InternalRouteRequest request,
    _InternalRouteSnapshot snapshot,
    List<String> blockedReasonCodes,
  ) {
    return InternalRouteResult(
      stationId: request.stationId,
      stationName: snapshot.stationName,
      fromNodeId: request.fromNodeId,
      fromNodeName: snapshot.nodeName(request.fromNodeId),
      toNodeId: request.toNodeId,
      toNodeName: snapshot.nodeName(request.toNodeId),
      mobilityType: request.mobilityType,
      status: 'BLOCKED',
      totalDistanceMeters: 0,
      totalEstimatedSeconds: 0,
      steps: const [],
      warnings: const [],
      blockedReasons: blockedReasonCodes
          .map(
            (code) => switch (code) {
              'STAIR_ONLY_ACCESS' => '계단 없는 내부 이동 경로가 없습니다.',
              'ACCESSIBILITY_STATE_UNKNOWN' => '내부 이동 경로 접근성 상태를 확인할 수 없습니다.',
              'FACILITY_UNAVAILABLE' => '필수 내부 이동 시설을 사용할 수 없습니다.',
              _ => '내부 이동 경로가 차단되었습니다.',
            },
          )
          .toList(growable: false),
    );
  }

  local.MobilityType _mobilityType(String mobilityType) {
    return switch (mobilityType) {
      'SENIOR' => local.MobilityType.senior,
      'STROLLER' => local.MobilityType.stroller,
      'WHEELCHAIR' => local.MobilityType.wheelchair,
      'PREGNANT' => local.MobilityType.pregnant,
      'TEMPORARY_INJURY' => local.MobilityType.temporaryInjury,
      'LUGGAGE' => local.MobilityType.luggage,
      _ => local.MobilityType.senior,
    };
  }
}

class FallbackInternalRouteRepository implements InternalRouteRepository {
  const FallbackInternalRouteRepository({required this.localRepository});

  final LocalInternalRouteRepository localRepository;

  @override
  Future<List<InternalRouteNode>> listRouteNodes(String stationId) async {
    return localRepository.listRouteNodes(stationId);
  }

  @override
  Future<InternalRouteResult> searchInternalRoute(
    InternalRouteRequest request,
  ) async {
    return localRepository.searchInternalRoute(request);
  }
}

class _InternalRouteSnapshot {
  const _InternalRouteSnapshot({
    required this.stationName,
    required this.nodesById,
    required this.edgesById,
  });

  final String stationName;
  final Map<String, String> nodesById;
  final Map<String, engine.InternalRouteEdge> edgesById;

  static Future<_InternalRouteSnapshot> load(
    CatalogDatabase database,
    String stationId,
  ) async {
    final station = await database
        .customSelect(
          'SELECT name_ko FROM stations WHERE id = ?',
          variables: [Variable.withString(stationId.trim())],
        )
        .getSingleOrNull();
    final nodeRows = await database
        .customSelect(
          '''
      SELECT id, label
      FROM internal_route_nodes
      WHERE station_id = ?
      ''',
          variables: [Variable.withString(stationId.trim())],
        )
        .get();
    final edgeColumns = await database
        .customSelect('PRAGMA table_info(internal_route_edges)')
        .get();
    final edgeColumnNames = {
      for (final row in edgeColumns) row.read<String>('name'),
    };
    final edgeTypeSql = _selectInternalRouteEdgeColumn(
      edgeColumnNames,
      'edge_type',
      "'WALK'",
    );
    final distanceMetersSql = _selectInternalRouteEdgeColumn(
      edgeColumnNames,
      'distance_meters',
      '0',
    );
    final includesStairsSql = _selectInternalRouteEdgeColumn(
      edgeColumnNames,
      'includes_stairs',
      '0',
    );
    final requiresElevatorSql = _selectInternalRouteEdgeColumn(
      edgeColumnNames,
      'requires_elevator',
      '0',
    );
    final requiresEscalatorSql = _selectInternalRouteEdgeColumn(
      edgeColumnNames,
      'requires_escalator',
      '0',
    );
    final slopeLevelSql = _selectInternalRouteEdgeColumn(
      edgeColumnNames,
      'slope_level',
      '1',
    );
    final widthLevelSql = _selectInternalRouteEdgeColumn(
      edgeColumnNames,
      'width_level',
      '2',
    );
    final reliabilityScoreSql = _selectInternalRouteEdgeColumn(
      edgeColumnNames,
      'reliability_score',
      '100',
    );
    final accessibilityStatusSql = _selectInternalRouteEdgeColumn(
      edgeColumnNames,
      'accessibility_status',
      "'UNKNOWN'",
    );
    final edgeRows = await database
        .customSelect(
          '''
      SELECT e.id,
             e.from_node_id,
             e.to_node_id,
             $edgeTypeSql AS edge_type,
             $distanceMetersSql AS distance_meters,
             e.duration_seconds,
             $includesStairsSql AS includes_stairs,
             $requiresElevatorSql AS requires_elevator,
             $requiresEscalatorSql AS requires_escalator,
             $slopeLevelSql AS slope_level,
             $widthLevelSql AS width_level,
             $reliabilityScoreSql AS reliability_score,
             $accessibilityStatusSql AS accessibility_status,
             dqr.quality_level AS field_quality_level,
             CAST(dqr.checked_at AS INTEGER) AS field_checked_at_value,
             e.instruction
      FROM internal_route_edges e
      JOIN internal_route_nodes n ON n.id = e.from_node_id
      LEFT JOIN data_quality_records dqr
        ON dqr.target_type = 'internal_route_edge'
       AND dqr.target_id = e.id
      WHERE n.station_id = ?
      ''',
          variables: [Variable.withString(stationId.trim())],
        )
        .get();

    final edges = {
      for (final row in edgeRows)
        row.read<String>('id'): engine.InternalRouteEdge(
          id: row.read<String>('id'),
          fromNodeId: row.read<String>('from_node_id'),
          toNodeId: row.read<String>('to_node_id'),
          edgeType: row.read<String>('edge_type'),
          distanceMeters: row.read<int>('distance_meters'),
          estimatedSeconds: row.read<int>('duration_seconds'),
          includesStairs: row.read<bool>('includes_stairs'),
          requiresElevator: row.read<bool>('requires_elevator'),
          requiresEscalator: row.read<bool>('requires_escalator'),
          slopeLevel: row.read<int>('slope_level'),
          widthLevel: row.read<int>('width_level'),
          reliabilityScore: row.read<int>('reliability_score'),
          accessibilityStatus: row.read<String>('accessibility_status'),
          fieldValidationStatus: _fieldValidationStatus(
            row.read<String?>('field_quality_level'),
            row.read<int?>('field_checked_at_value'),
          ),
          guidance: row.read<String>('instruction'),
        ),
    };

    return _InternalRouteSnapshot(
      stationName: station?.read<String>('name_ko') ?? stationId,
      nodesById: {
        for (final row in nodeRows)
          row.read<String>('id'): row.read<String>('label'),
      },
      edgesById: edges,
    );
  }

  engine.InternalRouteGraph toGraph() {
    return engine.InternalRouteGraph(
      nodes: nodesById.entries
          .map(
            (entry) => engine.InternalRouteNode(
              id: entry.key,
              stationId: '',
              name: entry.value,
            ),
          )
          .toList(growable: false),
      edges: edgesById.values.toList(growable: false),
    );
  }

  String nodeName(String nodeId) {
    return nodesById[nodeId] ?? nodeId;
  }
}

String _selectInternalRouteEdgeColumn(
  Set<String> columnNames,
  String columnName,
  String fallbackExpression,
) {
  return columnNames.contains(columnName)
      ? 'e.$columnName'
      : fallbackExpression;
}

String _fieldValidationStatus(String? qualityLevel, int? checkedAt) {
  final normalizedLevel = qualityLevel?.trim().toUpperCase();
  return switch (normalizedLevel) {
    'FIELD_VERIFIED' when checkedAt != null => 'VERIFIED',
    'FIELD_STALE' => 'STALE',
    'FIELD_UNKNOWN' => 'UNKNOWN',
    _ => 'UNKNOWN',
  };
}
