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

  @override
  Future<List<InternalRouteNode>> listRouteNodes(String stationId) async {
    final rows = await catalogDatabase
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
          edgeType: 'WALK',
          distanceMeters: edge.distanceMeters,
          estimatedSeconds: edge.estimatedSeconds,
          includesStairs: edge.includesStairs,
          requiresElevator: edge.requiresElevator,
          requiresEscalator: edge.requiresEscalator,
          slopeLevel: 1,
          widthLevel: 2,
          reliabilityScore: edge.reliabilityScore,
          guidance: edge.guidance,
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
            (code) => code == 'STAIR_ONLY_ACCESS'
                ? '계단 없는 내부 이동 경로가 없습니다.'
                : '내부 이동 경로가 차단되었습니다.',
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
    final edgeRows = await database
        .customSelect(
          '''
      SELECT e.id, e.from_node_id, e.to_node_id, e.duration_seconds, e.instruction
      FROM internal_route_edges e
      JOIN internal_route_nodes n ON n.id = e.from_node_id
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
          distanceMeters: 0,
          estimatedSeconds: row.read<int>('duration_seconds'),
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
