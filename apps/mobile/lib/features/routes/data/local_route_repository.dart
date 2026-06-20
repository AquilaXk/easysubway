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
    final routeGraph = catalog.toGraph();
    final engine = LocalRouteEngine(graph: routeGraph);
    final result = engine.search(
      local.RouteRequest(
        originStationId: request.originStationId,
        destinationStationId: request.destinationStationId,
        mobilityType: _mobilityType(request.mobilityType),
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

    return RouteSearchResult(
      routeSearchId:
          'local-${request.originStationId}-${request.destinationStationId}',
      originStationId: request.originStationId,
      originStationName: originName,
      destinationStationId: request.destinationStationId,
      destinationStationName: destinationName,
      mobilityType: request.mobilityType,
      status: result.status == local.RouteStatus.found ? 'FOUND' : 'BLOCKED',
      lineId: primaryLineId,
      lineName: primaryLineName,
      score: _scoreFromCost(result.totalCost),
      steps: _toSteps(result, catalog),
      warnings: result.warnings
          .map(
            (warning) => RouteSearchWarning(
              code: warning.code,
              message: warning.message,
            ),
          )
          .toList(growable: false),
      recommendationReasons: _recommendationReasons(request.mobilityType),
      blockedReasons: result.blockedReasonCodes
          .map(_blockedReasonMessage)
          .toList(growable: false),
      createdAt: DateTime.now().toIso8601String(),
    );
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
            title: _stepTitle(step.type.name, fromName, toName, lineName),
            description: _stepDescription(step.type.name, fromName, toName),
            lineId: step.lineId,
            lineName: lineName,
            fromStationId: fromStationId,
            toStationId: toStationId,
            estimatedMinutes: (step.durationSeconds / 60).ceil().clamp(1, 999),
            distanceMeters: step.cost * 2,
            includesStairs: step.includesStairs,
            requiresAccessibilityCheck:
                step.type.name == 'entry' || step.type.name == 'exit',
          );
        })
        .toList(growable: false);
  }

  String _stepTitle(
    String type,
    String fromName,
    String toName,
    String lineName,
  ) {
    return switch (type) {
      'ride' => '$fromName에서 $toName까지 $lineName 이동',
      'transfer' => '$fromName에서 환승',
      'entry' => '$fromName역 승강장 접근',
      'exit' => '$toName역 출구 접근',
      _ => '$fromName에서 $toName까지 이동',
    };
  }

  String _stepDescription(String type, String fromName, String toName) {
    return switch (type) {
      'ride' => '$fromName에서 $toName까지 열차를 이용합니다.',
      'transfer' => '$fromName에서 다른 노선으로 갈아탑니다.',
      'entry' => '계단 없는 동선을 우선해 승강장으로 이동합니다.',
      'exit' => '도착역에서 계단 없는 출구 동선을 확인합니다.',
      _ => '$fromName에서 $toName까지 이동합니다.',
    };
  }

  int _scoreFromCost(int cost) {
    if (cost <= 0) {
      return 0;
    }
    return (100 - (cost / 20).round()).clamp(1, 100);
  }

  List<String> _recommendationReasons(String mobilityType) {
    return [
      '현재 데이터 기준으로 이동 가능한 철도 구간을 계산했습니다.',
      '출구와 시설 상태는 현장 안내를 함께 확인해 주세요.',
      switch (mobilityType) {
        'WHEELCHAIR' => '휠체어 이동 조건에서 차단된 계단 구간은 제외했습니다.',
        'STROLLER' => '유모차 이동 조건에서 차단된 계단 구간은 제외했습니다.',
        'SENIOR' => '고령자 이동 조건의 접근 비용을 반영했습니다.',
        _ => '선택한 이동 조건의 접근 비용을 반영했습니다.',
      },
    ];
  }

  String _blockedReasonMessage(String code) {
    return switch (code) {
      'STAIR_ONLY_ACCESS' => '계단 없는 경로를 찾지 못했습니다.',
      'FACILITY_UNAVAILABLE' => '필수 접근성 시설을 사용할 수 없습니다.',
      _ => '안내 가능한 경로를 찾지 못했습니다.',
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
      _ => local.MobilityType.senior,
    };
  }
}

class FallbackRouteSearchRepository implements RouteSearchRepository {
  const FallbackRouteSearchRepository({required this.localRepository});

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
  });

  final Map<String, String> stationsById;
  final Map<String, String> linesById;
  final List<_StationLineSnapshot> stationLines;
  final List<_NetworkEdgeSnapshot> networkEdges;

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
    final includesStairsSql = _selectNetworkEdgeColumn(
      networkEdgeColumnNames,
      'includes_stairs',
      '0',
    );
    final accessibilityStatusSql = _selectNetworkEdgeColumn(
      networkEdgeColumnNames,
      'accessibility_status',
      "'UNKNOWN'",
    );
    final reliabilityScoreSql = _selectNetworkEdgeColumn(
      networkEdgeColumnNames,
      'reliability_score',
      '100',
    );
    final lastVerifiedAtSql = _selectNetworkEdgeColumn(
      networkEdgeColumnNames,
      'last_verified_at',
      'NULL',
    );
    final networkEdgeRows = await database.customSelect('''
          SELECT id, from_node_id, to_node_id, duration_seconds, edge_type,
                 $servicePatternSql AS service_pattern,
                 $includesStairsSql AS includes_stairs,
                 $accessibilityStatusSql AS accessibility_status,
                 $reliabilityScoreSql AS reliability_score,
                 $lastVerifiedAtSql AS last_verified_at
          FROM network_edges
          ORDER BY id
          ''').get();

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
      networkEdges: networkEdgeRows
          .map(
            (row) => _NetworkEdgeSnapshot(
              id: row.read<String>('id'),
              fromNodeId: row.read<String>('from_node_id'),
              toNodeId: row.read<String>('to_node_id'),
              durationSeconds: row.read<int>('duration_seconds'),
              edgeType: row.read<String>('edge_type'),
              servicePattern: row.read<String>('service_pattern'),
              includesStairs: row.read<int>('includes_stairs') != 0,
              accessibilityStatus: row.read<String>('accessibility_status'),
              reliabilityScore: row.read<int>('reliability_score'),
              lastVerifiedAtSeconds: row.readNullable<int>('last_verified_at'),
            ),
          )
          .toList(growable: false),
    );
  }

  graph.NetworkGraph toGraph() {
    final nodes = <graph.RouteNode>[];
    final edges = <graph.RouteEdge>[];
    final nodeKeysByStation = <String, Map<String, _RouteNodeKey>>{};
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
      if (networkEdge.routeEdgeType == graph.RouteEdgeType.transfer) {
        explicitTransferPairs.add(
          _edgePairKey(networkEdge.fromNodeId, networkEdge.toNodeId),
        );
        explicitTransferPairs.add(
          _edgePairKey(networkEdge.toNodeId, networkEdge.fromNodeId),
        );
        if (fromNode != null && toNode != null) {
          explicitTransferLinePairs.add(_lineTransferPairKey(fromNode, toNode));
          explicitTransferLinePairs.add(_lineTransferPairKey(toNode, fromNode));
        }
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
        edges.add(
          graph.RouteEdge(
            id: 'entry-${stationLine.stationId}-${stationLine.lineId}$accessEdgeSuffix',
            fromNodeId: stationLine.stationId,
            toNodeId: nodeKey.nodeId,
            type: graph.RouteEdgeType.entry,
            baseCost: 90,
          ),
        );
        edges.add(
          graph.RouteEdge(
            id: 'exit-${stationLine.stationId}-${stationLine.lineId}$accessEdgeSuffix',
            fromNodeId: nodeKey.nodeId,
            toNodeId: stationLine.stationId,
            type: graph.RouteEdgeType.exit,
            baseCost: 60,
          ),
        );
      }
    }

    for (final stationEntry in nodeKeysByStation.entries) {
      final stationId = stationEntry.key;
      final stationNodes = stationEntry.value.values.toList(growable: false);
      for (final from in stationNodes) {
        for (final to in stationNodes) {
          if (from.nodeId == to.nodeId) {
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
              type: graph.RouteEdgeType.transfer,
              baseCost: 140,
              transferStationId: stationId,
            ),
          );
        }
      }
    }

    for (final networkEdge in networkEdges) {
      final routeEdgeType = networkEdge.routeEdgeType;
      if (routeEdgeType == null) {
        continue;
      }
      edges.add(
        graph.RouteEdge(
          id: networkEdge.id,
          fromNodeId: networkEdge.fromNodeId,
          toNodeId: networkEdge.toNodeId,
          type: routeEdgeType,
          baseCost: networkEdge.durationSeconds <= 0
              ? 60
              : networkEdge.durationSeconds,
          lineId: networkEdge.lineId,
          includesStairs: networkEdge.includesStairs,
          reliabilityScore: networkEdge.effectiveReliabilityScore,
          isDataStale: networkEdge.isDataStale,
          isAvailable: networkEdge.isAvailable,
        ),
      );
    }

    return graph.NetworkGraph(nodes: nodes, edges: edges);
  }

  bool _hasStationLine(_RouteNodeKey nodeKey, Set<String> stationLineKeys) {
    return stationLineKeys.contains(
      _stationLineKey(nodeKey.stationId, nodeKey.lineId),
    );
  }

  String stationName(String stationId) {
    return stationsById[stationId] ?? '확인 필요 역';
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

bool _hasExplicitTransferPair(
  _RouteNodeKey from,
  _RouteNodeKey to,
  Set<String> explicitTransferPairs,
  Set<String> explicitTransferLinePairs,
) {
  return explicitTransferPairs.contains(_edgePairKey(from.nodeId, to.nodeId)) ||
      explicitTransferLinePairs.contains(_lineTransferPairKey(from, to));
}

String _lineTransferPairKey(_RouteNodeKey from, _RouteNodeKey to) {
  return '${_stationLineKey(from.stationId, from.lineId)}'
      '->${_stationLineKey(to.stationId, to.lineId)}';
}

String _stationLineKey(String stationId, String lineId) {
  return '$stationId:$lineId';
}

String _selectNetworkEdgeColumn(
  Set<String> columnNames,
  String columnName,
  String fallbackExpression,
) {
  return columnNames.contains(columnName) ? columnName : fallbackExpression;
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
      servicePattern: parts.length >= 3 ? parts[2] : '',
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
    required this.edgeType,
    required this.servicePattern,
    required this.includesStairs,
    required this.accessibilityStatus,
    required this.reliabilityScore,
    required this.lastVerifiedAtSeconds,
  });

  final String id;
  final String fromNodeId;
  final String toNodeId;
  final int durationSeconds;
  final String edgeType;
  final String servicePattern;
  final bool includesStairs;
  final String accessibilityStatus;
  final int reliabilityScore;
  final int? lastVerifiedAtSeconds;

  graph.RouteEdgeType? get routeEdgeType {
    return switch (edgeType.toUpperCase()) {
      'RIDE' => graph.RouteEdgeType.ride,
      'TRANSFER' => graph.RouteEdgeType.transfer,
      'ENTRY' => graph.RouteEdgeType.entry,
      'EXIT' => graph.RouteEdgeType.exit,
      _ => null,
    };
  }

  String get lineId {
    final parts = fromNodeId.split(':');
    if (parts.length < 2) {
      return '';
    }
    return parts[1];
  }

  String get _accessibilityStatusUpper => accessibilityStatus.toUpperCase();

  bool get isAvailable => _accessibilityStatusUpper != 'UNAVAILABLE';

  int get effectiveReliabilityScore {
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
}
