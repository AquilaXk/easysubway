import 'package:drift/drift.dart' show Variable;

import '../../../core/database/catalog/canonical_station_id.dart';
import '../../../core/database/catalog/catalog_database.dart';
import '../../../route_hedge_labels.dart';
import '../../../route_search.dart';
import '../../fare/official_od_fare_quote.dart';
import '../../fare/official_od_fare_repository.dart';
import '../../mobility_profile/mobility_preset_labels.dart';
import '../../mobility_profile/mobility_profile_policy.dart';
import '../application/network_graph.dart' as graph;
import '../application/route_engine.dart';
import '../domain/route_request.dart' as local;
import '../domain/route_result.dart' as local;
import '../domain/route_step.dart' as route_step;

class LocalRouteRepository implements RouteSearchRepository {
  LocalRouteRepository({
    required this.catalogDatabase,
    OfficialOdFareRepository? officialOdFareRepository,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now,
       officialOdFareRepository =
           officialOdFareRepository ??
           OfficialOdFareRepository(catalogDatabase: catalogDatabase);

  final CatalogDatabase catalogDatabase;
  final DateTime Function() now;
  final OfficialOdFareRepository officialOdFareRepository;

  Future<RouteSearchRequest> canonicalRequest(
    RouteSearchRequest request,
  ) async {
    final waypoint = request.waypointStationId?.trim();
    return RouteSearchRequest(
      originStationId: await catalogDatabase.resolveCanonicalStationId(
        request.originStationId.trim(),
      ),
      destinationStationId: await catalogDatabase.resolveCanonicalStationId(
        request.destinationStationId.trim(),
      ),
      mobilityType: request.mobilityType,
      constraintMode: request.constraintMode,
      waypointStationId: waypoint == null || waypoint.isEmpty
          ? waypoint
          : await catalogDatabase.resolveCanonicalStationId(waypoint),
      mobilityPreset: request.mobilityPreset,
      transportScope: request.transportScope,
    );
  }

  Future<RouteCapabilityMetadata> routeCapability(
    RouteSearchRequest request,
  ) async {
    final catalog = await _RouteCatalogSnapshot.load(catalogDatabase);
    final stationExists =
        catalog.hasStation(request.originStationId) &&
        catalog.hasStation(request.destinationStationId);
    final routeResult = stationExists
        ? catalog.routeResult(
            request.originStationId,
            request.destinationStationId,
            mobilityType: local.MobilityType.luggage,
            constraintMode: local.ConstraintMode.allowWithWarnings,
          )
        : null;
    final routeGraphConnected = routeResult?.status == local.RouteStatus.found;
    return RouteCapabilityMetadata(
      stationExists: stationExists,
      routeGraphConnected: routeGraphConnected,
      strictEvidenceSupported:
          stationExists &&
          catalog.strictEvidenceSupportedFor(
            request.originStationId,
            request.destinationStationId,
          ),
      realtimeSupported: catalog.realtimeSupported(
        request.originStationId,
        request.destinationStationId,
      ),
      plannedTimetableSupported:
          routeGraphConnected &&
          catalog.plannedTimetableSupported(
            request.originStationId,
            request.destinationStationId,
          ),
      outOfStationTransferAllowed:
          routeResult?.steps.any(
            (step) =>
                step.type == route_step.RouteStepType.outOfStationTransfer,
          ) ??
          false,
      regions: catalog.regionsFor(
        request.originStationId,
        request.destinationStationId,
      ),
      operatorIds: catalog.operatorIdsFor(
        request.originStationId,
        request.destinationStationId,
      ),
    );
  }

  Future<bool> canSearchRoute(RouteSearchRequest request) async {
    final catalog = await _RouteCatalogSnapshot.load(catalogDatabase);
    return catalog.hasStation(request.originStationId) &&
        catalog.hasStation(request.destinationStationId);
  }

  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest rawRequest) async {
    final catalog = await _RouteCatalogSnapshot.load(catalogDatabase);
    final request = catalog.canonicalRequest(rawRequest);
    final mobilityType = _mobilityType(request.mobilityType);
    final constraintMode = _constraintMode(request.effectiveConstraintMode);
    final objective = _localObjective(request.objective);
    // #1975: 경유 요청의 strict 강등 판정은 전역 strict 지원이 아니라 두 구간을
    // 각각 본다(한 구간만 미지원이어도 강등). 경유 없는 단일 구간은 엔진이 이미
    // 구간별 strict 근거를 강제하고 구체 사유를 내므로 전역 pre-filter를 유지한다.
    final blocksStairOnly = mobilityType.blocksStairOnlyAccess(constraintMode);
    final blocksStrictGlobally =
        blocksStairOnly && !catalog.strictEvidenceSupported;
    final waypointStationId = request.waypointStationId?.trim();
    final local.LocalRouteResult result;
    if (waypointStationId == null || waypointStationId.isEmpty) {
      result = blocksStrictGlobally
          ? local.LocalRouteResult.unknown(const [
              'STRICT_EVIDENCE_UNSUPPORTED',
            ])
          : LocalRouteEngine(graph: catalog.toGraph()).search(
              local.RouteRequest(
                originStationId: request.originStationId,
                destinationStationId: request.destinationStationId,
                mobilityType: mobilityType,
                constraintMode: constraintMode,
                searchMode: local
                    .RouteSearchMode
                    .stationToStationWithOutOfStationTransfers,
                objective: objective,
              ),
            );
    } else if (blocksStairOnly &&
        !(catalog.strictEvidenceSupportedFor(
              request.originStationId,
              waypointStationId,
            ) &&
            catalog.strictEvidenceSupportedFor(
              waypointStationId,
              request.destinationStationId,
            ))) {
      result = local.LocalRouteResult.unknown(const [
        'STRICT_EVIDENCE_UNSUPPORTED',
      ]);
    } else {
      final graphSnapshot = catalog.toGraph();
      final engine = LocalRouteEngine(graph: graphSnapshot);
      final first = engine.search(
        local.RouteRequest(
          originStationId: request.originStationId,
          destinationStationId: waypointStationId,
          mobilityType: mobilityType,
          constraintMode: constraintMode,
          searchMode:
              local.RouteSearchMode.stationToStationWithOutOfStationTransfers,
          objective: objective,
        ),
      );
      final second = engine.search(
        local.RouteRequest(
          originStationId: waypointStationId,
          destinationStationId: request.destinationStationId,
          mobilityType: mobilityType,
          constraintMode: constraintMode,
          searchMode:
              local.RouteSearchMode.stationToStationWithOutOfStationTransfers,
          objective: objective,
        ),
      );
      result = mergeWaypointRouteResults(first, second);
    }

    final plannedArrivals = await _plannedRideArrivals(result, catalog);
    final quote = await officialOdFareRepository.findExact(
      originStationId: request.originStationId,
      destinationStationId: request.destinationStationId,
    );
    return _toRouteSearchResult(
      request,
      result,
      catalog,
      plannedArrivals: plannedArrivals,
      officialOdFareQuote: quote,
    );
  }

  @override
  Future<RouteRefreshResult> refreshRoute(String routeSearchId) async {
    throw const RouteSearchException('로컬 경로는 새로고침할 수 없어요.');
  }

  RouteSearchResult _toRouteSearchResult(
    RouteSearchRequest request,
    local.LocalRouteResult result,
    _RouteCatalogSnapshot catalog, {
    required Map<int, String> plannedArrivals,
    required OfficialOdFareQuote? officialOdFareQuote,
  }) {
    final originName = catalog.stationName(request.originStationId);
    final destinationName = catalog.stationName(request.destinationStationId);
    final lineIds = result.lineIds;
    final primaryLineId = lineIds.isEmpty ? '' : lineIds.first;
    final primaryLineName = catalog.lineName(primaryLineId);
    // 이 검색에 적용할 보행 프리셋을 한 번 판정해 스텝 보정과 STEP_FREE 가산에
    // 재사용한다: 서버 문자열 우선, 없으면 대표 이동유형, 그래도 없으면 표준.
    final preset = _mobilityPresetFor(request);
    final steps = _toSteps(
      result,
      catalog,
      plannedArrivals: plannedArrivals,
      preset: preset,
    );
    // 스텝 표시분의 합(60초 단위)을 총 소요시간으로 쓴다. STEP_FREE는 승강기
    // 대기를 엔진 elevator 스텝 개수와 무관하게 경로당 정확히 1회만 가산해
    // backend ProfileWalkTimeCalculator(ceil(baseline*speedFactor) + STEP_FREE
    // 60초 1회)와 정합시킨다.
    var estimatedDurationSeconds = _estimatedDurationSeconds(steps);
    if (preset == MobilityPreset.stepFree) {
      estimatedDurationSeconds +=
          MobilityProfilePolicy.stepFreeElevatorWaitSeconds;
    }

    return RouteSearchResult(
      routeSearchId:
          'local-${request.originStationId}-${request.destinationStationId}',
      originStationId: request.originStationId,
      originStationName: originName,
      destinationStationId: request.destinationStationId,
      destinationStationName: destinationName,
      mobilityType: request.mobilityType,
      constraintMode: request.effectiveConstraintMode,
      status: _routeStatus(result.status),
      lineId: primaryLineId,
      lineName: primaryLineName,
      score: result.accessibilityScore,
      burdenCost: result.generalizedCost,
      estimatedDurationSeconds: estimatedDurationSeconds,
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
      etaSource: 'STATIC_LOCAL',
      etaConfidence: 'STATIC',
      sourceUpdatedAt: catalog.sourceUpdatedAt,
      officialOdFareQuote: officialOdFareQuote,
      transportScope: request.transportScope,
    );
  }

  /// 요청의 보행 프리셋을 판정한다: v2 서버 문자열(mobilityPreset)이 있으면 우선,
  /// 없거나 매핑 실패면 대표 이동유형(mobilityType)으로, 그래도 없으면 표준으로 폴백.
  MobilityPreset _mobilityPresetFor(RouteSearchRequest request) {
    final serverPreset = request.mobilityPreset;
    if (serverPreset != null) {
      final mapped = mobilityPresetFromServerString(serverPreset);
      if (mapped != null) {
        return mapped;
      }
    }
    return mobilityPresetFromRepresentativeMobilityType(request.mobilityType) ??
        MobilityPreset.standard;
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
    _RouteCatalogSnapshot catalog, {
    required Map<int, String> plannedArrivals,
    required MobilityPreset preset,
  }) {
    final speedFactor = MobilityProfilePolicy.presets[preset]!.speedFactor;
    return _collapseConsecutiveRideSteps(result.steps).indexed
        .map((entry) {
          final (index, step) = entry;
          // speedFactor는 보행 성분에만 곱한다. 주행 성분(ride/waypoint)의
          // durationSeconds는 실제 시간표 기반이므로 절대 보정하지 않는다.
          final isWalking =
              step.type != route_step.RouteStepType.ride &&
              step.type != route_step.RouteStepType.waypoint;
          final adjustedDurationSeconds =
              (isWalking && step.durationSeconds > 0)
              ? (step.durationSeconds * speedFactor).ceil()
              : step.durationSeconds;
          final fromStationId = catalog.stationIdForNode(step.fromNodeId);
          final toStationId = catalog.stationIdForNode(step.toNodeId);
          final fromName = catalog.stationName(fromStationId);
          final toName = catalog.stationName(toStationId);
          final lineName = catalog.lineName(step.lineId);
          final carDoorHint = step.type.name == 'ride'
              ? catalog.carDoorHintFor(
                  fromStationId: fromStationId,
                  toStationId: toStationId,
                  lineId: step.lineId,
                )
              : null;

          return RouteSearchStep(
            sequence: index + 1,
            stepType: step.type.name,
            title: _stepTitle(step.type.name, fromName, toName, lineName),
            description: _stepDescription(step.type.name, fromName, toName),
            lineId: step.lineId,
            lineName: lineName,
            fromStationId: fromStationId,
            toStationId: toStationId,
            estimatedMinutes: _estimatedMinutesFor(adjustedDurationSeconds),
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
            reason: step.type.name == 'waypoint' ? '' : _stepReason(),
            evidenceSources: step.evidenceSources,
            timeSource: step.timeSource,
            distanceSource: step.distanceSource,
            confidenceLabel: step.confidenceLabel,
            plannedArrivalTimeIso: plannedArrivals[step.sequence] ?? '',
            carDoorCarNumber: carDoorHint?.carNumber,
            carDoorDoorNumber: carDoorHint?.doorNumber,
            carDoorFacilityType: carDoorHint?.facilityType ?? '',
            // 오프라인 catalog는 지하철 전용이라 승차 leg의 운행 클래스는 SUBWAY로
            // 보존한다. 운행종별은 온라인 파서와 대칭으로 대문자 enum(LOCAL·EXPRESS)만
            // 정규화해 싣고, 그 외(공백·미상)는 null로 둬 급행 배지를 붙이지 않는다
            // (급행 정보가 없으면 배지 없음이 정상).
            serviceClass: step.type.name == 'ride' ? 'SUBWAY' : null,
            servicePattern: _normalizedRideServicePattern(step),
          );
        })
        .toList(growable: false);
  }

  Future<Map<int, String>> _plannedRideArrivals(
    local.LocalRouteResult result,
    _RouteCatalogSnapshot catalog,
  ) async {
    if (result.status != local.RouteStatus.found) {
      return const {};
    }
    final arrivals = <int, String>{};
    var cursor = now().toUtc();
    for (final step in _collapseConsecutiveRideSteps(result.steps)) {
      if (step.type != route_step.RouteStepType.ride) {
        cursor = cursor.add(Duration(seconds: step.durationSeconds));
        continue;
      }
      // 시간표 조회는 UI 투영과 같은 정규화 값을 쓴다. edge에 'express '(소문자·
      // 공백)가 와도 대문자 'EXPRESS' 시간표와 매칭되도록 정규화한 뒤 넘긴다.
      final rawServicePattern = step.servicePattern.trim();
      final normalizedServicePattern = _normalizedServicePattern(
        rawServicePattern,
      );
      // non-empty인데 화이트리스트 밖(미상)이면 어떤 시간표와도 신뢰성 있게 매칭할
      // 수 없으므로 도착 시각 조회를 포기한다(fail-safe: 빈 결과). 빈 값은 종전대로
      // 운행종별 필터 없이 조회한다(LOCAL/미표기 동작 보존).
      if (rawServicePattern.isNotEmpty && normalizedServicePattern == null) {
        return const {};
      }
      final arrival = await _nextTimetableArrival(
        fromStationId: catalog.stationIdForNode(step.fromNodeId),
        toStationId: catalog.stationIdForNode(step.toNodeId),
        lineId: step.lineId,
        servicePattern: normalizedServicePattern ?? '',
        cursor: cursor,
      );
      if (arrival == null) {
        return const {};
      }
      arrivals[step.sequence] = _koreaIso(arrival);
      cursor = arrival;
    }
    return arrivals;
  }

  Future<DateTime?> _nextTimetableArrival({
    required String fromStationId,
    required String toStationId,
    required String lineId,
    required String servicePattern,
    required DateTime cursor,
  }) async {
    final koreaNow = cursor.toUtc().add(const Duration(hours: 9));
    var firstServiceDate = DateTime.utc(
      koreaNow.year,
      koreaNow.month,
      koreaNow.day,
    );
    if (koreaNow.hour < 3) {
      firstServiceDate = firstServiceDate.subtract(const Duration(days: 1));
    }
    for (var dayOffset = 0; dayOffset <= 7; dayOffset += 1) {
      final serviceDate = firstServiceDate.add(Duration(days: dayOffset));
      final serviceMidnight = serviceDate.subtract(const Duration(hours: 9));
      final dateKey = _compactDate(serviceDate);
      final weekdayColumn = _weekdayColumn(serviceDate.weekday);
      final startMicroseconds = cursor
          .difference(serviceMidnight)
          .inMicroseconds;
      final startSeconds = startMicroseconds <= 0
          ? 0
          : (startMicroseconds + Duration.microsecondsPerSecond - 1) ~/
                Duration.microsecondsPerSecond;
      final servicePatternSql = servicePattern.isEmpty
          ? ''
          : 'AND trip.service_pattern = ?';
      final row = await catalogDatabase
          .customSelect(
            '''
        SELECT board.departure_seconds, alight.arrival_seconds
        FROM transit_trips trip
        INNER JOIN transit_routes route ON route.id = trip.route_id
        INNER JOIN service_calendars calendar
          ON calendar.service_id = trip.service_id
        INNER JOIN transit_stop_times board ON board.trip_id = trip.id
        INNER JOIN transit_stop_times alight ON alight.trip_id = trip.id
        WHERE (
            (
              calendar.start_date <= ?
              AND calendar.end_date >= ?
              AND calendar.$weekdayColumn != 0
            )
            OR EXISTS (
              SELECT 1
              FROM service_calendar_dates added
              WHERE added.service_id = trip.service_id
                AND added.date = ?
                AND added.exception_type = 1
            )
          )
          AND NOT EXISTS (
            SELECT 1
            FROM service_calendar_dates removed
            WHERE removed.service_id = trip.service_id
              AND removed.date = ?
              AND removed.exception_type = 2
          )
          AND trip.service_class = 'SUBWAY'
          AND route.line_id = ?
          $servicePatternSql
          AND board.station_id = ?
          AND board.line_id = ?
          AND board.pickup_type != 1
          AND alight.station_id = ?
          AND alight.line_id = ?
          AND alight.drop_off_type != 1
          AND alight.stop_sequence > board.stop_sequence
          AND board.departure_seconds >= ?
        ORDER BY board.departure_seconds, alight.arrival_seconds, trip.id
        LIMIT 1
      ''',
            variables: [
              Variable.withString(dateKey),
              Variable.withString(dateKey),
              Variable.withString(dateKey),
              Variable.withString(dateKey),
              Variable.withString(lineId),
              if (servicePattern.isNotEmpty)
                Variable.withString(servicePattern),
              Variable.withString(fromStationId),
              Variable.withString(lineId),
              Variable.withString(toStationId),
              Variable.withString(lineId),
              Variable.withInt(startSeconds),
            ],
          )
          .getSingleOrNull();
      if (row != null) {
        return serviceMidnight.add(
          Duration(seconds: row.read<int>('arrival_seconds')),
        );
      }
    }
    return null;
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
    // #1975: 경유 경계 마커(waypoint)는 실제 이동이 아닌 표식이므로 요약 집계에서
    // 제외한다. 마커의 0/기본값 메타가 실제 이동 근거를 강등하지 못하게 한다.
    final steps = result.steps
        .where((step) => step.type.name != 'waypoint')
        .toList(growable: false);
    if (steps.isEmpty) {
      return const [];
    }
    final requiresAccessibilityCheck = steps.any(
      (step) =>
          step.type.name == 'entry' ||
          step.type.name == 'exit' ||
          step.stairAccessState == 'unknown',
    );
    final hasDurationEstimate = steps.every((step) => step.durationSeconds > 0);
    final hasDistanceMeasure = steps.every((step) => step.distanceMeters > 0);
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
      'waypoint' => '$fromName 경유',
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
      'waypoint' => '내리지 않고 이 역을 지나가요',
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
      'waypoint' => '경유',
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
      'waypoint' => '이 역에서 내리지 않고 지나갑니다.',
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
      // 불확실성 헤지는 앱 공통 사전 한 벌로(#1577). 연결 미확인은 계단이 아니라
      // 경로 연결 문구로 바로잡는다(이전 매핑 불일치 수정).
      'STAIR_ONLY_ACCESS_UNKNOWN' => routeHedgeStepFreeUnknown,
      'GENERATED_CONNECTOR_UNVERIFIED' => routeHedgeConnectivityUnknown,
      // 보수중(실측)과 일반 이용 어려움을 정직하게 구분해 표시한다(#1996).
      'FACILITY_UNDER_MAINTENANCE' => routeFacilityUnderMaintenance,
      'FACILITY_UNAVAILABLE' => routeFacilityUnavailable,
      'ACCESSIBILITY_STATE_UNKNOWN' => routeHedgeAccessibilityUnknown,
      'STALE_ACCESSIBILITY_DATA' => '오래된 안내라 계단 없는 경로로 안내하지 않아요.',
      'BLOCKED_UNVERIFIED_EDGE' => '검증되지 않은 경로는 안내하지 않아요.',
      'BLOCKED_MISSING_EVIDENCE_HASH' => '검증 근거가 없는 경로는 안내하지 않아요.',
      'BLOCKED_PLACEHOLDER_EVIDENCE_HASH' => '임시 근거만 있는 경로는 안내하지 않아요.',
      'BLOCKED_UNSUPPORTED_SCOPE' => '지원 범위 밖 경로는 안내하지 않아요.',
      'STRICT_EVIDENCE_UNSUPPORTED' => '검증 근거가 부족해 계단 없는 경로로 안내하지 않아요.',
      'ROUTE_GRAPH_UNKNOWN' => routeHedgeConnectivityUnknown,
      _ => '안내할 수 있는 경로를 아직 찾지 못했어요.',
    };
  }

  local.MobilityType _mobilityType(String mobilityType) {
    return switch (mobilityType) {
      // STANDARD는 계단 회피 없는 표준 보행이나 local enum에 직접 대응이 없어,
      // preferStepFree(strict 아님)라 blocksStairOnlyAccess=false인 senior로 폴백한다.
      // speedFactor STANDARD=1.0이라 무보정이고, 이 폴백은 offline 결과의 mobilityType
      // 표기에만 영향을 줄 뿐 실제 필터링은 preferStepFree라 동일하다.
      'STANDARD' => local.MobilityType.senior,
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

  local.RouteObjective _localObjective(RouteObjective objective) {
    return switch (objective) {
      RouteObjective.fastest => local.RouteObjective.fastest,
      RouteObjective.fewestTransfers => local.RouteObjective.fewestTransfers,
    };
  }
}

/// 오프라인 catalog network edge의 운행종별 화이트리스트. 온라인 파서와 대칭으로
/// 대문자 enum({'LOCAL','EXPRESS'})만 인정한다.
const Set<String> _localRideServicePatterns = {'LOCAL', 'EXPRESS'};

/// ride 승차 leg의 servicePattern을 정규화한다. datapack 파이프라인은
/// network_edges.service_pattern에 대문자 enum을 강제하지 않으므로(build-datapack의
/// 삽입은 `row.servicePattern ?? ''`로 검증 없이 통과), 계약이 불명확한 값은
/// fail-safe로 null 처리해 급행 배지를 붙이지 않는다(온라인 파서의 fail-closed와
/// 달리 오프라인은 배지 없음이 정상 — 기존 로컬 정책 유지). ride가 아니거나 공백·
/// 미상 값도 모두 null.
String? _normalizedRideServicePattern(route_step.RouteStep step) {
  if (step.type.name != 'ride') {
    return null;
  }
  return _normalizedServicePattern(step.servicePattern);
}

/// raw servicePattern을 화이트리스트({'LOCAL','EXPRESS'}) 대문자 enum으로 정규화한다.
/// 공백·미상 값은 null. UI 투영과 시간표 조회가 같은 정규화를 쓰도록 공유한다.
String? _normalizedServicePattern(String raw) {
  final normalized = raw.trim().toUpperCase();
  return _localRideServicePatterns.contains(normalized) ? normalized : null;
}

/// 경유역 지원 1단계: 출발→경유, 경유→도착 두 구간의 탐색 결과를 하나로 합성한다.
/// 두 구간이 모두 성공(found)일 때만 경로를 이어 붙이고, 그 사이에 경계 마커
/// 스텝을 삽입해 후단 collapse가 서로 다른 구간의 승차를 병합하지 못하게 한다.
/// 한쪽이라도 성공이 아니면 더 나쁜 상태를 보수적으로 채택한다.
///
/// 테스트에서 순수 병합 로직을 직접 검증할 수 있도록 최상위 public 함수로 노출한다
/// (이 파일의 최상위 private 함수는 외부 테스트에서 접근할 수 없다).
local.LocalRouteResult mergeWaypointRouteResults(
  local.LocalRouteResult first,
  local.LocalRouteResult second,
) {
  final mergedCodes = _dedupInOrder([
    ...first.blockedReasonCodes,
    ...second.blockedReasonCodes,
  ]);
  final mergedWarnings = _dedupWarningsInOrder([
    ...first.warnings,
    ...second.warnings,
  ]);

  final worstRank =
      _routeStatusRank(first.status) <= _routeStatusRank(second.status)
      ? _routeStatusRank(first.status)
      : _routeStatusRank(second.status);

  if (worstRank != _routeStatusRank(local.RouteStatus.found)) {
    final worseStatus =
        _routeStatusRank(first.status) <= _routeStatusRank(second.status)
        ? first.status
        : second.status;
    return local.LocalRouteResult(
      status: worseStatus,
      totalCost: 0,
      steps: const [],
      warnings: mergedWarnings,
      blockedReasonCodes: mergedCodes,
    );
  }

  // 중간 경유는 개찰구를 나가지 않는 지점이므로, 1구간 꼬리의 도착 하차 후
  // 동선과 2구간 머리의 출발 진입 동선을 경계에서 제거하는 것이 기본이다.
  final firstTrimmed = _trimBoundaryAccessSteps(first.steps, fromTail: true);
  final secondTrimmed = _trimBoundaryAccessSteps(second.steps, fromTail: false);

  // #1975: trim 후 1구간 꼬리와 2구간 머리의 경계 노드가 일치할 때만(같은 승강장
  // 무하차 연결) 접근 동선을 제거한다. 경유역에서 노선이 바뀌어 경계 노드가
  // 어긋나면(개찰구 내 환승/연결 이동이 실제로 필요) 접근 동선을 보존해 총시간
  // 과소계상을 막는다.
  final trimmedBoundaryMatches =
      firstTrimmed.isNotEmpty &&
      secondTrimmed.isNotEmpty &&
      firstTrimmed.last.toNodeId == secondTrimmed.first.fromNodeId;

  final firstSteps = trimmedBoundaryMatches ? firstTrimmed : first.steps;
  final secondSteps = trimmedBoundaryMatches ? secondTrimmed : second.steps;

  final boundaryNodeId = firstSteps.isNotEmpty
      ? firstSteps.last.toNodeId
      : (secondSteps.isNotEmpty ? secondSteps.first.fromNodeId : '');
  final boundary = route_step.RouteStep(
    sequence: 0,
    edgeId: 'waypoint-boundary',
    fromNodeId: boundaryNodeId,
    toNodeId: boundaryNodeId,
    type: route_step.RouteStepType.waypoint,
    cost: 0,
    durationSeconds: 0,
    distanceMeters: 0,
    // #1975: 경계 마커는 실제 이동이 아닌 표식이므로 요약을 왜곡하지 않도록
    // 무해한 메타를 명시한다(기본값 'unknown'/'UNKNOWN'/기본 안내 문구 상속 차단).
    stairAccessState: 'stepFree',
    timeSource: '',
    distanceSource: '',
    confidenceLabel: '',
    evidenceSources: const [],
  );

  final flat = <route_step.RouteStep>[...firstSteps, boundary, ...secondSteps];
  final renumbered = <route_step.RouteStep>[];
  for (var index = 0; index < flat.length; index += 1) {
    final step = flat[index];
    renumbered.add(
      route_step.RouteStep(
        sequence: index + 1,
        edgeId: step.edgeId,
        fromNodeId: step.fromNodeId,
        toNodeId: step.toNodeId,
        type: step.type,
        cost: step.cost,
        durationSeconds: step.durationSeconds,
        distanceMeters: step.distanceMeters,
        lineId: step.lineId,
        servicePattern: step.servicePattern,
        transferStationId: step.transferStationId,
        includesStairs: step.includesStairs,
        stairAccessState: step.stairAccessState,
        evidenceSources: step.evidenceSources,
        timeSource: step.timeSource,
        distanceSource: step.distanceSource,
        confidenceLabel: step.confidenceLabel,
      ),
    );
  }

  return local.LocalRouteResult(
    status: local.RouteStatus.found,
    totalCost: first.totalCost + second.totalCost,
    steps: renumbered,
    warnings: mergedWarnings,
    blockedReasonCodes: mergedCodes,
  );
}

/// 경유 경계에서 제거하는 접근·연결 동선 타입 화이트리스트.
/// ride/transfer/inStationTransfer/outOfStationTransfer는 절대 제거하지 않는다.
const Set<route_step.RouteStepType> _boundaryAccessStepTypes = {
  route_step.RouteStepType.exit,
  route_step.RouteStepType.walkway,
  route_step.RouteStepType.elevator,
  route_step.RouteStepType.ramp,
  route_step.RouteStepType.stair,
  route_step.RouteStepType.escalator,
  route_step.RouteStepType.facilityConnector,
  route_step.RouteStepType.internal,
  route_step.RouteStepType.entry,
};

/// 경유 경계에 인접한 접근 동선을 제거한다.
/// [fromTail]이 true면 뒤에서부터(1구간 꼬리), false면 앞에서부터(2구간 머리)
/// 화이트리스트 타입이 연속되는 구간을 제거하고, 아닌 타입을 만나면 중단한다.
List<route_step.RouteStep> _trimBoundaryAccessSteps(
  List<route_step.RouteStep> steps, {
  required bool fromTail,
}) {
  if (steps.isEmpty) {
    return steps;
  }
  if (fromTail) {
    var end = steps.length;
    while (end > 0 && _boundaryAccessStepTypes.contains(steps[end - 1].type)) {
      end -= 1;
    }
    return steps.sublist(0, end);
  }
  var start = 0;
  while (start < steps.length &&
      _boundaryAccessStepTypes.contains(steps[start].type)) {
    start += 1;
  }
  return steps.sublist(start);
}

/// 상태 병합 우선순위. 낮을수록 나쁜(=우선 채택되는) 상태다.
int _routeStatusRank(local.RouteStatus status) {
  return switch (status) {
    local.RouteStatus.blocked => 0,
    local.RouteStatus.error => 1,
    local.RouteStatus.unsupported => 1,
    local.RouteStatus.unknown => 2,
    local.RouteStatus.found => 3,
  };
}

List<String> _dedupInOrder(List<String> codes) {
  final seen = <String>{};
  final result = <String>[];
  for (final code in codes) {
    if (seen.add(code)) {
      result.add(code);
    }
  }
  return result;
}

List<local.RouteWarning> _dedupWarningsInOrder(
  List<local.RouteWarning> warnings,
) {
  final seen = <String>{};
  final result = <local.RouteWarning>[];
  for (final warning in warnings) {
    if (seen.add(warning.code)) {
      result.add(warning);
    }
  }
  return result;
}

List<route_step.RouteStep> _collapseConsecutiveRideSteps(
  List<route_step.RouteStep> steps,
) {
  final collapsed = <route_step.RouteStep>[];
  for (final step in steps) {
    final previous = collapsed.isEmpty ? null : collapsed.last;
    final canMerge =
        previous != null &&
        previous.type == route_step.RouteStepType.ride &&
        step.type == route_step.RouteStepType.ride &&
        previous.toNodeId == step.fromNodeId &&
        previous.lineId == step.lineId &&
        previous.servicePattern.isNotEmpty &&
        previous.servicePattern == step.servicePattern;
    if (!canMerge) {
      collapsed.add(step);
      continue;
    }
    collapsed[collapsed.length - 1] = route_step.RouteStep(
      sequence: previous.sequence,
      edgeId: previous.edgeId,
      fromNodeId: previous.fromNodeId,
      toNodeId: step.toNodeId,
      type: route_step.RouteStepType.ride,
      cost: previous.cost + step.cost,
      durationSeconds: previous.durationSeconds + step.durationSeconds,
      distanceMeters: previous.distanceMeters + step.distanceMeters,
      lineId: previous.lineId,
      servicePattern: previous.servicePattern,
      includesStairs: previous.includesStairs || step.includesStairs,
      stairAccessState: previous.stairAccessState == step.stairAccessState
          ? previous.stairAccessState
          : 'unknown',
      evidenceSources: {
        ...previous.evidenceSources,
        ...step.evidenceSources,
      }.toList(growable: false),
      timeSource: previous.timeSource == step.timeSource
          ? previous.timeSource
          : 'UNKNOWN',
      distanceSource: previous.distanceSource == step.distanceSource
          ? previous.distanceSource
          : 'UNKNOWN',
      confidenceLabel: previous.confidenceLabel == step.confidenceLabel
          ? previous.confidenceLabel
          : '안내를 준비 중이에요',
    );
  }
  return collapsed;
}

class RouteCapabilityMetadata {
  const RouteCapabilityMetadata({
    required this.stationExists,
    required this.routeGraphConnected,
    required this.strictEvidenceSupported,
    required this.realtimeSupported,
    required this.plannedTimetableSupported,
    required this.outOfStationTransferAllowed,
    required this.regions,
    required this.operatorIds,
  });

  final bool stationExists;
  final bool routeGraphConnected;
  final bool strictEvidenceSupported;
  final bool realtimeSupported;
  final bool plannedTimetableSupported;
  final bool outOfStationTransferAllowed;
  final List<String> regions;
  final List<String> operatorIds;
}

class LocalFirstRouteSearchRepository implements RouteSearchRepository {
  const LocalFirstRouteSearchRepository({required this.localRepository});

  final LocalRouteRepository localRepository;

  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request) async {
    return localRepository.searchRoute(request);
  }

  @override
  Future<RouteRefreshResult> refreshRoute(String routeSearchId) async {
    return localRepository.refreshRoute(routeSearchId);
  }
}

class OnlineFirstRouteSearchRepository implements RouteSearchRepository {
  const OnlineFirstRouteSearchRepository({
    required this.onlineRepository,
    required this.localRepository,
    this.metrics,
  });

  final RouteSearchRepository onlineRepository;
  final LocalRouteRepository? localRepository;
  final RouteSearchOnlineFirstMetrics? metrics;

  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request) async {
    final canonicalRequest = localRepository == null
        ? request
        : await localRepository!.canonicalRequest(request);
    try {
      final onlineResult = await onlineRepository.searchRoute(canonicalRequest);
      final result = localRepository == null
          ? onlineResult
          : await localRepository!.resolveDisplayLabels(onlineResult);
      metrics?.recordOnlineSuccess();
      return result;
    } on RouteSearchOnlineException catch (error) {
      metrics?.recordOnlineFailure(error.failureReason);
      rethrow;
    }
  }

  @override
  Future<RouteRefreshResult> refreshRoute(String routeSearchId) async {
    final refresh = await onlineRepository.refreshRoute(routeSearchId);
    final local = localRepository;
    if (local == null) return refresh;
    return RouteRefreshResult(
      routeSearchId: refresh.routeSearchId,
      status: refresh.status,
      result: await local.resolveDisplayLabels(refresh.result),
      refreshedAt: refresh.refreshedAt,
      etaSource: refresh.etaSource,
      etaConfidence: refresh.etaConfidence,
      sourceLabel: refresh.sourceLabel,
      reasonCodes: refresh.reasonCodes,
    );
  }
}

extension _OnlineRouteDisplayLabels on LocalRouteRepository {
  Future<RouteSearchResult> resolveDisplayLabels(
    RouteSearchResult result,
  ) async {
    final catalog = await _RouteCatalogSnapshot.load(catalogDatabase);
    final steps = result.steps
        .map((step) {
          final fromName = catalog.stationName(step.fromStationId);
          final toName = catalog.stationName(step.toStationId);
          final lineName = catalog.lineName(step.lineId);
          final title = _onlineStepTitle(step.stepType, fromName, toName);
          return step.withDisplayLabels(
            title: title,
            lineName: lineName,
            actionDetail: _onlineStepActionDetail(
              step.stepType,
              fromName,
              toName,
              lineName,
            ),
          );
        })
        .toList(growable: false);
    return result.withDisplayLabels(
      originStationName: catalog.stationName(result.originStationId),
      destinationStationName: catalog.stationName(result.destinationStationId),
      lineName: catalog.lineName(result.lineId),
      steps: steps,
      officialOdFareQuote: result.transportScope == RouteTransportScope.subway
          ? await officialOdFareRepository.findExact(
              originStationId: result.originStationId,
              destinationStationId: result.destinationStationId,
            )
          : null,
    );
  }

  String _onlineStepTitle(String type, String fromName, String toName) {
    return switch (type) {
      'ride' => '$fromName에서 $toName까지 이동',
      'transfer' => '$fromName에서 환승',
      'entry' || 'access' => '$fromName 승강장 접근',
      'exit' || 'egress' => '$toName 출구 접근',
      _ => '$fromName에서 $toName까지 이동',
    };
  }

  String _onlineStepActionDetail(
    String type,
    String fromName,
    String toName,
    String lineName,
  ) {
    return switch (type) {
      'ride' =>
        '$fromName에서 $toName까지 ${lineName.isEmpty ? '열차' : lineName}를 이용합니다.',
      'transfer' => '$fromName에서 다음 노선으로 갈아탈 준비를 합니다.',
      'entry' || 'access' => '$fromName 승강장 접근 동선을 확인합니다.',
      'exit' || 'egress' => '$toName 출구 접근 동선을 확인합니다.',
      _ => '$fromName에서 $toName까지 이동합니다.',
    };
  }
}

class RouteSearchOnlineFirstMetrics {
  int onlineSuccessCount = 0;
  int onlineFailureCount = 0;
  final onlineFailureReasonCounts = <String, int>{};

  void recordOnlineSuccess() {
    onlineSuccessCount += 1;
  }

  void recordOnlineFailure(String reason) {
    onlineFailureCount += 1;
    onlineFailureReasonCounts[reason] =
        (onlineFailureReasonCounts[reason] ?? 0) + 1;
  }
}

/// line_sequence 증가 방향이 KRIC upbdnbSe(UP/DOWN) 어느 쪽에 대응하는지의
/// 노선별 규약. line_sequence↔UP/DOWN 매핑은 어떤 데이터 계약으로도 보장되지
/// 않으므로(모바일 catalog 스키마에 방향 규약·순환/wrap 플래그가 전파되지 않음),
/// 규약이 명시적으로 검증된 노선에서만 방향을 유추한다.
// ascendingIsUp: 현재 allowlist에 대응 노선이 없지만, 규약 검증된 노선이
// 오름차순=상행일 때를 위해 매핑 값으로 보존한다.
// ignore: unused_field
enum _SeqDirectionConvention { ascendingIsDown, ascendingIsUp }

/// 규약이 검증된 노선의 (증가방향→direction) 매핑. 여기에 없는 노선은
/// line_sequence 델타로 방향을 유추하지 않는다(방향 있는 hint 미매칭).
/// - seoul-4: 오이도 방면=큰 line_sequence=하행 → 오름차순=DOWN, 내림차순=UP.
///   (근거: datapack reconstruct-transit-trips.test.mjs의 오이도 방면 규약)
const Map<String, _SeqDirectionConvention> _carDoorSeqConventionByLine = {
  'seoul-4': _SeqDirectionConvention.ascendingIsDown,
};

class _RouteCatalogSnapshot {
  const _RouteCatalogSnapshot({
    required this.stationsById,
    required this.canonicalStationIdsByAlias,
    required this.regionsByStationId,
    required this.linesById,
    required this.operatorIdsByLineId,
    required this.stationLines,
    required this.networkEdges,
    required this.strictEvidenceSupported,
    required this.sourceUpdatedAt,
    required this.realtimeStationLineKeysByProvider,
    required this.plannedStationLineKeys,
    required this.carDoorHintsByStationLine,
  });

  final Map<String, String> stationsById;
  final Map<String, String> canonicalStationIdsByAlias;
  final Map<String, String> regionsByStationId;
  final Map<String, String> linesById;
  final Map<String, String> operatorIdsByLineId;
  final List<_StationLineSnapshot> stationLines;
  final List<_NetworkEdgeSnapshot> networkEdges;
  final bool strictEvidenceSupported;
  final String sourceUpdatedAt;
  final Map<String, Set<String>> realtimeStationLineKeysByProvider;
  final Set<String> plannedStationLineKeys;

  /// 키=_stationLineKey(stationId, lineId). 빠른 하차 안내(#2066)용, 오프라인
  /// 로컬 catalog에 station_car_door_hints가 있을 때만 채워진다.
  final Map<String, List<_CarDoorHintSnapshot>> carDoorHintsByStationLine;

  static Future<_RouteCatalogSnapshot> load(CatalogDatabase database) async {
    final sourceUpdatedAtRow = await database.customSelect('''
          SELECT MAX(CAST(updated_at AS INTEGER)) AS source_updated_at
          FROM catalog_metadata
          ''').getSingleOrNull();
    final stationRows = await database
        .customSelect('SELECT id, name_ko, region FROM stations')
        .get();
    final stationAliasRows = await database.customSelect('''
          SELECT alias, station_id
          FROM station_aliases
          WHERE alias LIKE 'station-%'
          ''').get();
    final stationIdsByAlias = <String, Set<String>>{};
    for (final row in stationAliasRows) {
      stationIdsByAlias
          .putIfAbsent(row.read<String>('alias'), () => <String>{})
          .add(row.read<String>('station_id'));
    }
    final lineRows = await database
        .customSelect('SELECT id, name_ko, operator_id FROM lines')
        .get();
    final stationLineRows = await database.customSelect('''
          SELECT station_id, line_id, line_sequence
          FROM station_lines
          ORDER BY line_id, line_sequence
          ''').get();
    final outOfStationTransferPolicy = await _OutOfStationTransferPolicy.load(
      database,
    );
    final realtimeRows = await database.customSelect('''
          SELECT station_mapping.provider_id, station_mapping.station_id,
            station_mapping.line_id
          FROM realtime_provider_station_mappings station_mapping
          INNER JOIN realtime_provider_line_mappings line_mapping
            ON line_mapping.provider_id = station_mapping.provider_id
            AND line_mapping.line_id = station_mapping.line_id
          WHERE station_mapping.supports_arrivals != 0
            AND line_mapping.supports_arrivals != 0
          ''').get();
    final realtimeStationLineKeysByProvider = <String, Set<String>>{};
    for (final row in realtimeRows) {
      realtimeStationLineKeysByProvider
          .putIfAbsent(row.read<String>('provider_id'), () => <String>{})
          .add(
            _stationLineKey(
              row.read<String>('station_id'),
              row.read<String>('line_id'),
            ),
          );
    }
    final plannedRows = await database.customSelect('''
          SELECT DISTINCT stop.station_id, stop.line_id
          FROM transit_stop_times stop
          INNER JOIN transit_trips trip ON trip.id = stop.trip_id
          WHERE trip.service_class = 'SUBWAY'
          ''').get();
    final plannedStationLineKeys = {
      for (final row in plannedRows)
        _stationLineKey(
          row.read<String>('station_id'),
          row.read<String>('line_id'),
        ),
    };
    final carDoorHintsByStationLine = <String, List<_CarDoorHintSnapshot>>{};
    if (await _tableExists(database, 'station_car_door_hints')) {
      final carDoorRows = await database.customSelect('''
            SELECT station_id, line_id, direction, target_facility_type,
              car_number, door_number
            FROM station_car_door_hints
            WHERE UPPER(verification_status) IN ('OFFICIAL', 'VERIFIED')
            ''').get();
      for (final row in carDoorRows) {
        carDoorHintsByStationLine
            .putIfAbsent(
              _stationLineKey(
                row.read<String>('station_id'),
                row.read<String>('line_id'),
              ),
              () => <_CarDoorHintSnapshot>[],
            )
            .add(
              _CarDoorHintSnapshot(
                direction: row.read<String>('direction'),
                facilityType: row.read<String>('target_facility_type'),
                carNumber: row.read<int>('car_number'),
                doorNumber: row.read<int>('door_number'),
              ),
            );
      }
    }
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
    final localPlannerServiceClassFilter =
        networkEdgeColumnNames.contains('service_class')
        ? "WHERE service_class = 'SUBWAY'"
        : '';
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
          $localPlannerServiceClassFilter
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
          final effectiveAccessibilityStatus = _effectiveAccessibilityStatus(
            accessibilityStatus,
            facility,
            facilityHasEligibleEvidence,
          );
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
            accessibilityStatus: effectiveAccessibilityStatus,
            isUnderMaintenance: _effectiveIsUnderMaintenance(
              accessibilityStatus,
              effectiveAccessibilityStatus,
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
        .where(
          (edge) =>
              edge.routeEdgeType != graph.RouteEdgeType.outOfStationTransfer ||
              outOfStationTransferPolicy.allows(edge),
        )
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
      canonicalStationIdsByAlias: {
        for (final entry in stationIdsByAlias.entries)
          if (entry.value.length == 1) entry.key: entry.value.single,
      },
      regionsByStationId: {
        for (final row in stationRows)
          row.read<String>('id'): row.read<String>('region'),
      },
      linesById: {
        for (final row in lineRows)
          row.read<String>('id'): row.read<String>('name_ko'),
      },
      operatorIdsByLineId: {
        for (final row in lineRows)
          row.read<String>('id'): row.read<String>('operator_id'),
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
      sourceUpdatedAt: _metadataUpdatedAtIso(
        sourceUpdatedAtRow?.readNullable<int>('source_updated_at'),
      ),
      realtimeStationLineKeysByProvider: realtimeStationLineKeysByProvider,
      plannedStationLineKeys: plannedStationLineKeys,
      carDoorHintsByStationLine: carDoorHintsByStationLine,
    );
  }

  local.LocalRouteResult routeResult(
    String originStationId,
    String destinationStationId, {
    required local.MobilityType mobilityType,
    required local.ConstraintMode constraintMode,
  }) {
    originStationId = canonicalStationId(originStationId);
    destinationStationId = canonicalStationId(destinationStationId);
    return LocalRouteEngine(graph: toGraph()).search(
      local.RouteRequest(
        originStationId: originStationId,
        destinationStationId: destinationStationId,
        mobilityType: mobilityType,
        constraintMode: constraintMode,
        searchMode:
            local.RouteSearchMode.stationToStationWithOutOfStationTransfers,
      ),
    );
  }

  bool strictEvidenceSupportedFor(
    String originStationId,
    String destinationStationId,
  ) {
    if (!strictEvidenceSupported) {
      return false;
    }
    return routeResult(
          originStationId,
          destinationStationId,
          mobilityType: local.MobilityType.wheelchair,
          constraintMode: local.ConstraintMode.strictStepFree,
        ).status ==
        local.RouteStatus.found;
  }

  bool plannedTimetableSupported(
    String originStationId,
    String destinationStationId,
  ) {
    final originKeys = _stationLineKeysFor(originStationId);
    final destinationKeys = _stationLineKeysFor(destinationStationId);
    return originKeys.any(plannedStationLineKeys.contains) &&
        destinationKeys.any(plannedStationLineKeys.contains);
  }

  bool realtimeSupported(String originStationId, String destinationStationId) {
    final originKeys = _stationLineKeysFor(originStationId);
    final destinationKeys = _stationLineKeysFor(destinationStationId);
    return realtimeStationLineKeysByProvider.values.any(
      (keys) =>
          originKeys.any(keys.contains) && destinationKeys.any(keys.contains),
    );
  }

  /// 빠른 하차 안내(#2066): 승차 step의 (from,to,line)에 맞는 하차 칸-문을 고른다.
  /// 규약이 검증된 노선(_carDoorSeqConventionByLine)에 한해 station_lines의
  /// line_sequence 델타를 노선별 규약으로 방향(UP/DOWN)으로 변환하고, 미검증
  /// 노선은 방향을 유추하지 않아 방향 있는 hint를 매칭하지 않는다.
  /// direction 게이트: 값 방향은 유추 방향과 일치할 때만, 빈 direction은 방향 무관.
  /// 후보가 여럿이면 시설 우선순위(ELEVATOR>ESCALATOR>STAIR>TRANSFER), 이어서
  /// carNumber·doorNumber 오름차순으로 결정적으로 하나를 고른다.
  ({int carNumber, int doorNumber, String facilityType})? carDoorHintFor({
    required String fromStationId,
    required String toStationId,
    required String lineId,
  }) {
    if (toStationId.isEmpty || lineId.isEmpty) {
      return null;
    }
    final candidates =
        carDoorHintsByStationLine[_stationLineKey(toStationId, lineId)] ??
        const <_CarDoorHintSnapshot>[];
    if (candidates.isEmpty) {
      return null;
    }
    final fromSeq = _lineSequenceFor(fromStationId, lineId);
    final toSeq = _lineSequenceFor(toStationId, lineId);
    final convention = _carDoorSeqConventionByLine[lineId];
    String? inferredDirection;
    if (convention != null && fromSeq != null && toSeq != null) {
      if (toSeq > fromSeq) {
        inferredDirection =
            convention == _SeqDirectionConvention.ascendingIsDown
            ? 'DOWN'
            : 'UP';
      } else if (toSeq < fromSeq) {
        inferredDirection =
            convention == _SeqDirectionConvention.ascendingIsDown
            ? 'UP'
            : 'DOWN';
      }
    }
    final matches = candidates
        .where((hint) {
          final direction = hint.direction.toUpperCase();
          if (direction.isEmpty) {
            return true;
          }
          if (direction == 'UP' || direction == 'DOWN') {
            return inferredDirection != null && inferredDirection == direction;
          }
          return false;
        })
        .toList(growable: false);
    if (matches.isEmpty) {
      return null;
    }
    matches.sort((a, b) {
      final priority = _carDoorFacilityPriority(
        a.facilityType,
      ).compareTo(_carDoorFacilityPriority(b.facilityType));
      if (priority != 0) {
        return priority;
      }
      final byCar = a.carNumber.compareTo(b.carNumber);
      if (byCar != 0) {
        return byCar;
      }
      return a.doorNumber.compareTo(b.doorNumber);
    });
    final best = matches.first;
    return (
      carNumber: best.carNumber,
      doorNumber: best.doorNumber,
      facilityType: best.facilityType,
    );
  }

  int? _lineSequenceFor(String stationId, String lineId) {
    for (final stationLine in stationLines) {
      if (stationLine.stationId == stationId && stationLine.lineId == lineId) {
        return stationLine.sequence;
      }
    }
    return null;
  }

  List<String> regionsFor(String originStationId, String destinationStationId) {
    originStationId = canonicalStationId(originStationId);
    destinationStationId = canonicalStationId(destinationStationId);
    return {
      if ((regionsByStationId[originStationId] ?? '').isNotEmpty)
        regionsByStationId[originStationId]!,
      if ((regionsByStationId[destinationStationId] ?? '').isNotEmpty)
        regionsByStationId[destinationStationId]!,
    }.toList(growable: false);
  }

  List<String> operatorIdsFor(
    String originStationId,
    String destinationStationId,
  ) {
    originStationId = canonicalStationId(originStationId);
    destinationStationId = canonicalStationId(destinationStationId);
    final lineIds = {
      ...stationLines
          .where(
            (stationLine) =>
                stationLine.stationId == originStationId ||
                stationLine.stationId == destinationStationId,
          )
          .map((stationLine) => stationLine.lineId),
    };
    return {
      for (final lineId in lineIds)
        if ((operatorIdsByLineId[lineId] ?? '').isNotEmpty)
          operatorIdsByLineId[lineId]!,
    }.toList(growable: false);
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
    return stationsById[canonicalStationId(stationId)] ?? '역 이름을 확인하고 있어요';
  }

  bool hasStation(String stationId) {
    return stationsById.containsKey(canonicalStationId(stationId));
  }

  List<String> _stationLineKeysFor(String stationId) {
    stationId = canonicalStationId(stationId);
    return stationLines
        .where((stationLine) => stationLine.stationId == stationId)
        .map((stationLine) => _stationLineKey(stationId, stationLine.lineId))
        .toList(growable: false);
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

  String canonicalStationId(String stationId) {
    return canonicalStationIdsByAlias[stationId] ?? stationId;
  }

  RouteSearchRequest canonicalRequest(RouteSearchRequest request) {
    final waypoint = request.waypointStationId?.trim();
    return RouteSearchRequest(
      originStationId: canonicalStationId(request.originStationId.trim()),
      destinationStationId: canonicalStationId(
        request.destinationStationId.trim(),
      ),
      mobilityType: request.mobilityType,
      constraintMode: request.constraintMode,
      waypointStationId: waypoint == null || waypoint.isEmpty
          ? waypoint
          : canonicalStationId(waypoint),
      mobilityPreset: request.mobilityPreset,
      transportScope: request.transportScope,
      objective: request.objective,
    );
  }
}

String _metadataUpdatedAtIso(int? updatedAtMillis) {
  if (updatedAtMillis == null || updatedAtMillis <= 0) {
    return '';
  }
  final normalizedMillis = updatedAtMillis < 100000000000
      ? updatedAtMillis * 1000
      : updatedAtMillis;
  return DateTime.fromMillisecondsSinceEpoch(
    normalizedMillis,
    isUtc: true,
  ).toIso8601String();
}

class _OutOfStationTransferPolicy {
  const _OutOfStationTransferPolicy({
    required this.enabled,
    required this.runtimeEnabled,
    required this.allowlist,
  });

  final bool enabled;
  final bool runtimeEnabled;
  final Set<String> allowlist;

  static Future<_OutOfStationTransferPolicy> load(
    CatalogDatabase database,
  ) async {
    final rows = await database.customSelect('''
      SELECT key, value
      FROM catalog_metadata
      WHERE key IN (
        'route.outOfStationTransfer.enabled',
        'route.outOfStationTransfer.runtimeEnabled',
        'route.outOfStationTransfer.allowlist'
      )
    ''').get();
    final values = {
      for (final row in rows)
        row.read<String>('key'): row.read<String>('value'),
    };
    return _OutOfStationTransferPolicy(
      enabled:
          values['route.outOfStationTransfer.enabled']?.toLowerCase() == 'true',
      runtimeEnabled:
          values['route.outOfStationTransfer.runtimeEnabled']?.toLowerCase() !=
          'false',
      allowlist: _parseOutOfStationTransferAllowlist(
        values['route.outOfStationTransfer.allowlist'] ?? '',
      ),
    );
  }

  bool allows(_NetworkEdgeSnapshot edge) {
    return enabled &&
        runtimeEnabled &&
        allowlist.contains(_edgePairKey(edge.fromNodeId, edge.toNodeId));
  }
}

Set<String> _parseOutOfStationTransferAllowlist(String value) {
  return value
      .split(RegExp(r'[\s,]+'))
      .map((pair) => pair.trim())
      .where((pair) => pair.isNotEmpty)
      .toSet();
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

int _carDoorFacilityPriority(String facilityType) {
  return switch (facilityType.toUpperCase()) {
    'ELEVATOR' => 0,
    'ESCALATOR' => 1,
    'STAIR' => 2,
    'TRANSFER' => 3,
    _ => 4,
  };
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
    servicePattern: networkEdge.servicePattern,
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
    isUnderMaintenance: networkEdge.isUnderMaintenance,
    safetyEvidence: networkEdge.safetyEvidence,
  );
}

int _estimatedMinutesFor(int durationSeconds) {
  if (durationSeconds <= 0) {
    return 0;
  }
  return (durationSeconds / 60).ceil().clamp(1, 999);
}

String _compactDate(DateTime date) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${date.year}${twoDigits(date.month)}${twoDigits(date.day)}';
}

String _weekdayColumn(int weekday) {
  return switch (weekday) {
    DateTime.monday => 'monday',
    DateTime.tuesday => 'tuesday',
    DateTime.wednesday => 'wednesday',
    DateTime.thursday => 'thursday',
    DateTime.friday => 'friday',
    DateTime.saturday => 'saturday',
    DateTime.sunday => 'sunday',
    _ => throw ArgumentError.value(weekday, 'weekday'),
  };
}

String _koreaIso(DateTime instant) {
  final local = instant.toUtc().add(const Duration(hours: 9));
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${local.year.toString().padLeft(4, '0')}-'
      '${twoDigits(local.month)}-${twoDigits(local.day)}T'
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}:'
      '${twoDigits(local.second)}+09:00';
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

class _CarDoorHintSnapshot {
  const _CarDoorHintSnapshot({
    required this.direction,
    required this.facilityType,
    required this.carNumber,
    required this.doorNumber,
  });

  final String direction;
  final String facilityType;
  final int carNumber;
  final int doorNumber;
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
    return expiresAt != null && expiresAt > 0 && expiresAt <= nowSeconds;
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

/// 데이터팩 network_edges.accessibility_status 어휘를 앱 표시 3종
/// (UNAVAILABLE / UNKNOWN / AVAILABLE)으로 정규화한다(#1996). 백엔드 게이트가
/// 확정한 상태값을 정직하게 매핑한다:
/// - UNDER_MAINTENANCE(보수중/점검/중지/공사, 실측된 비가용) → UNAVAILABLE.
///   절대 available로 흘러가면 안 되므로 unknown 이하가 아니라 확정 차단이다.
/// - NO_OFFICIAL_FEED(공식 상태 피드 부재) → UNKNOWN(확인 불가).
/// - 그 밖의 값은 원문 유지(기존 UNAVAILABLE/UNKNOWN/AVAILABLE).
String _normalizeEdgeAccessibilityStatus(String edgeStatus) {
  return switch (edgeStatus.toUpperCase()) {
    'UNDER_MAINTENANCE' => 'UNAVAILABLE',
    'NO_OFFICIAL_FEED' => 'UNKNOWN',
    _ => edgeStatus,
  };
}

/// 원본 edge 상태가 실측 보수중(UNDER_MAINTENANCE)인지 여부. 정규화 후에는
/// UNAVAILABLE로 합쳐지므로, 표시 단계에서 '보수중'을 별도 구분하려면 원본을 본다.
bool _isEdgeUnderMaintenance(String edgeStatus) {
  return edgeStatus.toUpperCase() == 'UNDER_MAINTENANCE';
}

String _effectiveAccessibilityStatus(
  String rawEdgeStatus,
  _FacilitySnapshot? facility,
  bool facilityHasEligibleEvidence,
) {
  final edgeStatus = _normalizeEdgeAccessibilityStatus(rawEdgeStatus);
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

/// 정규화된 접근성 상태가 UNAVAILABLE일 때, 그 비가용이 데이터팩 게이트가 확정한
/// edge-level 실측 보수중(UNDER_MAINTENANCE)에서 비롯됐는지 판정한다(#1996). 이
/// 확정 어휘만 '보수중'으로 구분 표시하고, 시설 스냅샷 계열(OUT_OF_SERVICE/BROKEN
/// 등)의 비가용은 기존대로 일반 '이용 어려움'으로 둔다(범위 확정 유지). UNAVAILABLE이
/// 아닌 경우엔 항상 false.
bool _effectiveIsUnderMaintenance(
  String rawEdgeStatus,
  String effectiveStatus,
) {
  if (effectiveStatus.toUpperCase() != 'UNAVAILABLE') {
    return false;
  }
  return _isEdgeUnderMaintenance(rawEdgeStatus);
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
  if (activeSnapshotConfidence != null) {
    score = score < activeSnapshotConfidence ? score : activeSnapshotConfidence;
  }
  if (facility?.activeStatusSnapshot == null &&
      facility?.expiredStatusSnapshot != null &&
      score > 60) {
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
    this.isUnderMaintenance = false,
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

  /// 정직 표시: 이 edge의 비가용이 실측 보수중에서 비롯됐는지(#1996).
  final bool isUnderMaintenance;

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
