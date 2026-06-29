import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'accessible_design.dart';
import 'auth_headers.dart';
import 'core/network/api_client.dart';
import 'features/route_draft/domain/route_draft.dart';
import 'features/stations/presentation/station_line_badges.dart';
import 'mobile_error_reporter.dart';
import 'mobility_profile.dart';
import 'station_search.dart';

const _routeSearchTimeout = Duration(seconds: 8);
const _routeSearchErrorMessage = '경로 정보를 불러오지 못했습니다.';
const _routeFeedbackErrorMessage = '의견을 보내지 못했습니다.';
const _favoriteRouteErrorMessage = '즐겨찾기 경로를 처리하지 못했습니다.';
const _favoriteRouteLoadErrorMessage = '즐겨찾기 경로를 불러오지 못했습니다.';
const _routeSafetyGuidanceNotice = '이동 전 현장 안내와 역무원 안내를 확인해 주세요.';
const _routeSearchFailureNextAction = '역을 다시 선택하거나 이동 조건을 바꾼 뒤 경로를 다시 찾아보세요.';
const _routeBlockedConfirmationNotice = '역무원이나 현장 안내를 확인한 뒤 이동해 주세요.';
const _routeFeedbackFailureNextAction = '잠시 후 다시 보내거나 경로 조건을 바꿔 다시 찾아보세요.';
const _favoriteRouteSaveFailureNextAction =
    '네트워크 상태를 확인한 뒤 자주 쓰는 경로 저장을 다시 눌러 주세요.';
const _favoriteRouteLoadFailureNextAction = '네트워크 상태를 확인한 뒤 다시 불러와 주세요.';

String _mobilityLabelFor(String mobilityType) {
  for (final option in mobilityProfileOptions) {
    if (option.mobilityType == mobilityType) {
      return option.title;
    }
  }
  return '이동 조건 확인 필요';
}

String _routeDateLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.length >= 10) {
    return trimmed.substring(0, 10);
  }
  return '확인 필요';
}

abstract class RouteSearchRepository {
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request);
}

abstract class RouteFeedbackRepository {
  Future<void> submitRouteFeedback(RouteFeedbackRequest request);
}

enum RouteFeedbackRating {
  helpful('HELPFUL'),
  notHelpful('NOT_HELPFUL'),
  blockedByRealWorld('BLOCKED_BY_REAL_WORLD');

  const RouteFeedbackRating(this.serverValue);

  final String serverValue;
}

class RouteFeedbackRequest {
  const RouteFeedbackRequest({
    required this.routeSearchId,
    required this.rating,
    required this.comment,
  });

  final String routeSearchId;
  final RouteFeedbackRating rating;
  final String comment;

  RouteFeedbackRequest trimmed() {
    return RouteFeedbackRequest(
      routeSearchId: routeSearchId.trim(),
      rating: rating,
      comment: comment.trim(),
    );
  }

  Map<String, Object?> toJson({required String userId}) {
    final trimmedRequest = trimmed();
    return {
      'userId': userId.trim(),
      'rating': trimmedRequest.rating.serverValue,
      'comment': trimmedRequest.comment,
    };
  }
}

class RouteSearchApiRepository implements RouteSearchRepository {
  RouteSearchApiRepository({
    required this.baseUri,
    ApiClient? apiClient,
    HttpClient? httpClient,
  }) : _apiClient =
           apiClient ?? ApiClient(baseUri: baseUri, httpClient: httpClient);

  final Uri baseUri;
  final ApiClient _apiClient;

  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest routeRequest) async {
    try {
      final response = await _apiClient.postJson(
        '/api/v1/routes/search',
        body: routeRequest.toJson(),
      );

      if (!response.isOk) {
        throw const RouteSearchException(_routeSearchErrorMessage);
      }

      final decoded = response.jsonBody;
      if (decoded is! Map<String, Object?> || decoded['success'] != true) {
        throw const RouteSearchException(_routeSearchErrorMessage);
      }

      final data = decoded['data'];
      if (data is! Map<String, Object?>) {
        throw const RouteSearchException(_routeSearchErrorMessage);
      }

      return RouteSearchResult.fromJson(data);
    } on RouteSearchException {
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '경로 검색 API 응답 처리 중 예외가 발생했습니다.',
      );
      throw const RouteSearchException(_routeSearchErrorMessage);
    }
  }
}

class RouteFeedbackApiRepository implements RouteFeedbackRepository {
  RouteFeedbackApiRepository({
    required this.baseUri,
    required this.authProvider,
    ApiClient? apiClient,
    HttpClient? httpClient,
  }) : _apiClient =
           apiClient ?? ApiClient(baseUri: baseUri, httpClient: httpClient);

  final Uri baseUri;
  final AuthorizationHeaderProvider authProvider;
  final ApiClient _apiClient;

  @override
  Future<void> submitRouteFeedback(RouteFeedbackRequest feedbackRequest) async {
    final trimmedRequest = feedbackRequest.trimmed();
    if (trimmedRequest.routeSearchId.isEmpty) {
      throw const RouteFeedbackException(_routeFeedbackErrorMessage);
    }

    final path =
        '/api/v1/routes/${Uri.encodeComponent(trimmedRequest.routeSearchId)}/feedback';

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final authorizationHeader = await authProvider
            .authorizationHeader()
            .timeout(_routeSearchTimeout);
        // Basic 인증의 username을 사용자 식별자로 사용한다.
        final userId = _userIdFromAuthorizationHeader(authorizationHeader);
        if (userId == null) {
          throw const RouteFeedbackException(_routeFeedbackErrorMessage);
        }

        final response = await _apiClient.postJson(
          path,
          body: trimmedRequest.toJson(userId: userId),
          headers: {HttpHeaders.authorizationHeader: authorizationHeader!},
        );

        // 저장된 인증이 만료된 경우 한 번만 재시도한다.
        if (response.isUnauthorized && attempt == 0) {
          await authProvider.invalidateAuthorization().timeout(
            _routeSearchTimeout,
          );
          continue;
        }

        if (!response.isOk) {
          throw const RouteFeedbackException(_routeFeedbackErrorMessage);
        }

        final decoded = response.jsonBody;
        if (decoded is! Map<String, Object?> || decoded['success'] != true) {
          throw const RouteFeedbackException(_routeFeedbackErrorMessage);
        }
        return;
      } on RouteFeedbackException {
        rethrow;
      } catch (error, stackTrace) {
        reportMobileError(
          error,
          stackTrace,
          context: '경로 피드백 API 요청 처리 중 예외가 발생했습니다.',
        );
        throw const RouteFeedbackException(_routeFeedbackErrorMessage);
      }
    }
    throw const RouteFeedbackException(_routeFeedbackErrorMessage);
  }

  String? _userIdFromAuthorizationHeader(String? authorizationHeader) {
    const prefix = 'Basic ';
    if (authorizationHeader == null ||
        !authorizationHeader.startsWith(prefix)) {
      return null;
    }

    try {
      final decoded = utf8.decode(
        base64Decode(authorizationHeader.substring(prefix.length)),
      );
      final separatorIndex = decoded.indexOf(':');
      if (separatorIndex <= 0) {
        return null;
      }
      final userId = decoded.substring(0, separatorIndex).trim();
      return userId.isEmpty ? null : userId;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '경로 피드백 사용자 식별자 처리 중 예외가 발생했습니다.',
      );
      return null;
    }
  }
}

class RouteFeedbackException implements Exception {
  const RouteFeedbackException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class FavoriteRouteRepository {
  Future<List<FavoriteRoute>> listFavoriteRoutes();

  Future<FavoriteRoute> saveFavoriteRoute(
    String routeSearchId, {
    RouteSearchResult? result,
  });

  Future<void> removeFavoriteRoute(String favoriteRouteId);
}

class FavoriteRouteApiRepository implements FavoriteRouteRepository {
  FavoriteRouteApiRepository({
    required this.baseUri,
    required this.authProvider,
    ApiClient? apiClient,
    HttpClient? httpClient,
  }) : _apiClient =
           apiClient ?? ApiClient(baseUri: baseUri, httpClient: httpClient);

  final Uri baseUri;
  final AuthorizationHeaderProvider authProvider;
  final ApiClient _apiClient;

  @override
  Future<List<FavoriteRoute>> listFavoriteRoutes() async {
    final data = await _requestData(
      'GET',
      '/api/v1/me/favorites/routes',
      errorMessage: _favoriteRouteLoadErrorMessage,
    );
    if (data is! List<Object?>) {
      throw const FavoriteRouteException(_favoriteRouteLoadErrorMessage);
    }

    try {
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid favorite route payload');
            }
            return FavoriteRoute.fromJson(item);
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '즐겨찾기 경로 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const FavoriteRouteException(_favoriteRouteLoadErrorMessage);
    }
  }

  @override
  Future<FavoriteRoute> saveFavoriteRoute(
    String routeSearchId, {
    RouteSearchResult? result,
  }) async {
    final data = await _requestData(
      'POST',
      '/api/v1/me/favorites/routes',
      body: {'routeSearchId': routeSearchId},
      errorMessage: _favoriteRouteErrorMessage,
    );
    if (data is! Map<String, Object?>) {
      throw const FavoriteRouteException(_favoriteRouteErrorMessage);
    }

    try {
      return FavoriteRoute.fromJson(data);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '즐겨찾기 경로 저장 응답 처리 중 예외가 발생했습니다.',
      );
      throw const FavoriteRouteException(_favoriteRouteErrorMessage);
    }
  }

  @override
  Future<void> removeFavoriteRoute(String favoriteRouteId) async {
    await _requestData(
      'DELETE',
      '/api/v1/me/favorites/routes/$favoriteRouteId',
      errorMessage: _favoriteRouteErrorMessage,
    );
  }

  Future<Object?> _requestData(
    String method,
    String path, {
    Map<String, Object?>? body,
    required String errorMessage,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final authorizationHeader = await authProvider
            .authorizationHeader()
            .timeout(_routeSearchTimeout);
        final headers = <String, String>{};
        if (authorizationHeader != null) {
          headers[HttpHeaders.authorizationHeader] = authorizationHeader;
        }

        final response = await switch (method) {
          'GET' => _apiClient.getJson(path, headers: headers),
          'POST' => _apiClient.postJson(path, body: body!, headers: headers),
          'DELETE' => _apiClient.deleteJson(path, headers: headers),
          _ => throw FavoriteRouteException(errorMessage),
        };

        if (response.isUnauthorized &&
            authorizationHeader != null &&
            attempt == 0) {
          // 만료된 인증은 비우고 한 번만 다시 시도한다.
          await authProvider.invalidateAuthorization().timeout(
            _routeSearchTimeout,
          );
          continue;
        }

        if (!response.isSuccess) {
          throw FavoriteRouteException(errorMessage);
        }

        final decoded = response.jsonBody;
        if (decoded is! Map<String, Object?> || decoded['success'] != true) {
          throw FavoriteRouteException(errorMessage);
        }
        return decoded['data'];
      } on FavoriteRouteException {
        rethrow;
      } catch (error, stackTrace) {
        reportMobileError(
          error,
          stackTrace,
          context: '즐겨찾기 경로 API 요청 처리 중 예외가 발생했습니다.',
        );
        throw FavoriteRouteException(errorMessage);
      }
    }
    throw FavoriteRouteException(errorMessage);
  }
}

class FavoriteRouteException implements Exception {
  const FavoriteRouteException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FavoriteRoute {
  const FavoriteRoute({
    required this.userId,
    required this.favoriteRouteId,
    required this.routeSearchId,
    required this.originStationId,
    required this.originStationName,
    required this.destinationStationId,
    required this.destinationStationName,
    required this.mobilityType,
    required this.status,
    required this.lineId,
    required this.lineName,
    required this.score,
    required this.routeCreatedAt,
    required this.addedAt,
  });

  factory FavoriteRoute.fromJson(Map<String, Object?> json) {
    return FavoriteRoute(
      userId: _requiredRouteString(json, 'userId'),
      favoriteRouteId: _requiredRouteString(json, 'favoriteRouteId'),
      routeSearchId: _requiredRouteString(json, 'routeSearchId'),
      originStationId: _requiredRouteString(json, 'originStationId'),
      originStationName: _requiredRouteString(json, 'originStationName'),
      destinationStationId: _requiredRouteString(json, 'destinationStationId'),
      destinationStationName: _requiredRouteString(
        json,
        'destinationStationName',
      ),
      mobilityType: _requiredRouteString(json, 'mobilityType'),
      status: _requiredRouteString(json, 'status'),
      lineId: _optionalRouteString(json, 'lineId'),
      lineName: _optionalRouteString(json, 'lineName'),
      score: _requiredRouteInt(json, 'score'),
      routeCreatedAt: _requiredRouteString(json, 'routeCreatedAt'),
      addedAt: _requiredRouteString(json, 'addedAt'),
    );
  }

  final String userId;
  final String favoriteRouteId;
  final String routeSearchId;
  final String originStationId;
  final String originStationName;
  final String destinationStationId;
  final String destinationStationName;
  final String mobilityType;
  final String status;
  final String lineId;
  final String lineName;
  final int score;
  final String routeCreatedAt;
  final String addedAt;

  String get summaryTitle => '$originStationName에서 $destinationStationName까지';

  String get lineLabel => lineName.isEmpty ? '노선 확인 필요' : lineName;

  String get scoreLabel => '상세 이동 정보는 다시 검색해 확인';

  String get mobilityLabel => _mobilityLabelFor(mobilityType);

  String get scoreBasisText =>
      '기준: $mobilityLabel, $lineLabel, 최근 확인 ${_routeDateLabel(routeCreatedAt)}';

  String get scoreBasisSemanticLabel =>
      '기준 $mobilityLabel, $lineLabel, 최근 확인 ${_routeDateLabel(routeCreatedAt)}';

  String get movementMetricLabel => '예상 시간 확인 필요 · 환승 확인 필요 · 도보 확인 필요';

  String get accessibilityMetricLabel => '계단 정보 확인 필요 · 엘리베이터 연결 확인 필요';

  String get semanticLabel {
    return [
      '즐겨찾기 경로',
      summaryTitle,
      lineLabel,
      mobilityLabel,
      scoreLabel,
      scoreBasisSemanticLabel,
      '예상 시간 확인 필요',
      '환승 확인 필요',
      '도보 확인 필요',
      '계단 정보 확인 필요',
      '엘리베이터 연결 확인 필요',
    ].join(', ');
  }
}

class RouteSearchException implements Exception {
  const RouteSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RouteSearchRequest {
  const RouteSearchRequest({
    required this.originStationId,
    required this.destinationStationId,
    required this.mobilityType,
  });

  final String originStationId;
  final String destinationStationId;
  final String mobilityType;

  RouteSearchRequest trimmed() {
    return RouteSearchRequest(
      originStationId: originStationId.trim(),
      destinationStationId: destinationStationId.trim(),
      mobilityType: mobilityType,
    );
  }

  Map<String, Object?> toJson() {
    final trimmedRequest = trimmed();
    return {
      'originStationId': trimmedRequest.originStationId,
      'destinationStationId': trimmedRequest.destinationStationId,
      'mobilityType': trimmedRequest.mobilityType,
    };
  }
}

class RouteSearchResult {
  const RouteSearchResult({
    required this.routeSearchId,
    required this.originStationId,
    required this.originStationName,
    required this.destinationStationId,
    required this.destinationStationName,
    required this.mobilityType,
    required this.status,
    required this.lineId,
    required this.lineName,
    required this.score,
    int? accessibilityScore,
    int? burdenCost,
    int? estimatedDurationSeconds,
    int? walkingDistanceMeters,
    int? transferCount,
    this.evidenceSummary = const [],
    required this.steps,
    required this.warnings,
    this.recommendationReasons = const [],
    required this.blockedReasons,
    required this.createdAt,
  }) : // `burdenCost`는 API contract 이름이고 저장 필드는 fallback용 private 값이다.
       // ignore: prefer_initializing_formals
       _accessibilityScore = accessibilityScore,
       // ignore: prefer_initializing_formals
       _burdenCost = burdenCost,
       // ignore: prefer_initializing_formals
       _estimatedDurationSeconds = estimatedDurationSeconds,
       // ignore: prefer_initializing_formals
       _walkingDistanceMeters = walkingDistanceMeters,
       // ignore: prefer_initializing_formals
       _transferCount = transferCount;

  factory RouteSearchResult.fromJson(Map<String, Object?> json) {
    final rawSteps = json['steps'];
    final rawWarnings = json['warnings'];
    final rawRecommendationReasons = json['recommendationReasons'];
    final rawBlockedReasons = json['blockedReasons'];
    final legacyScore = _optionalRouteInt(json, 'score');
    final accessibilityScore = _optionalRouteInt(json, 'accessibilityScore');
    final burdenCost =
        _optionalRouteInt(json, 'burdenCost') ??
        legacyScore ??
        (throw const FormatException(
          'Missing required route field: burdenCost',
        ));
    if (rawSteps is! List<Object?> ||
        rawWarnings is! List<Object?> ||
        (rawRecommendationReasons != null &&
            rawRecommendationReasons is! List<Object?>) ||
        rawBlockedReasons is! List<Object?>) {
      throw const FormatException('Invalid route payload');
    }

    return RouteSearchResult(
      routeSearchId: _requiredRouteString(json, 'routeSearchId'),
      originStationId: _requiredRouteString(json, 'originStationId'),
      originStationName: _requiredRouteString(json, 'originStationName'),
      destinationStationId: _requiredRouteString(json, 'destinationStationId'),
      destinationStationName: _requiredRouteString(
        json,
        'destinationStationName',
      ),
      mobilityType: _requiredRouteString(json, 'mobilityType'),
      status: _requiredRouteString(json, 'status'),
      lineId: _optionalRouteString(json, 'lineId'),
      lineName: _optionalRouteString(json, 'lineName'),
      score: accessibilityScore ?? legacyScore ?? burdenCost,
      accessibilityScore: accessibilityScore ?? legacyScore,
      burdenCost: burdenCost,
      estimatedDurationSeconds: _optionalRouteInt(
        json,
        'estimatedDurationSeconds',
      ),
      walkingDistanceMeters: _optionalRouteInt(json, 'walkingDistanceMeters'),
      transferCount: _optionalRouteInt(json, 'transferCount'),
      steps: rawSteps
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid route step payload');
            }
            return RouteSearchStep.fromJson(item);
          })
          .toList(growable: false),
      warnings: rawWarnings
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid route warning payload');
            }
            return RouteSearchWarning.fromJson(item);
          })
          .toList(growable: false),
      recommendationReasons: _routeStringList(
        rawRecommendationReasons,
        'recommendation reason',
      ),
      evidenceSummary: _routeStringList(
        json['evidenceSummary'],
        'route evidence summary',
      ),
      blockedReasons: rawBlockedReasons
          .map((item) {
            if (item is! String || item.trim().isEmpty) {
              throw const FormatException('Invalid blocked reason payload');
            }
            return item;
          })
          .toList(growable: false),
      createdAt: _requiredRouteString(json, 'createdAt'),
    );
  }

  final String routeSearchId;
  final String originStationId;
  final String originStationName;
  final String destinationStationId;
  final String destinationStationName;
  final String mobilityType;
  final String status;
  final String lineId;
  final String lineName;
  final int score;
  final int? _accessibilityScore;
  final int? _burdenCost;
  final int? _estimatedDurationSeconds;
  final int? _walkingDistanceMeters;
  final int? _transferCount;
  final List<String> evidenceSummary;
  final List<RouteSearchStep> steps;
  final List<RouteSearchWarning> warnings;
  final List<String> recommendationReasons;
  final List<String> blockedReasons;
  final String createdAt;

  int get accessibilityScore => _accessibilityScore ?? score;

  int get burdenCost => _burdenCost ?? score;

  int get estimatedDurationSeconds {
    return _estimatedDurationSeconds ??
        steps.fold<int>(
          0,
          (sum, step) =>
              sum +
              (step.estimatedMinutes < 0 ? 0 : step.estimatedMinutes * 60),
        );
  }

  List<String> get recommendationReasonLabels {
    if (recommendationReasons.isEmpty) {
      return const [];
    }
    return const ['선택한 경로 기준으로 안내합니다.'];
  }

  List<String> get blockedReasonLabels {
    return blockedReasons.map(_routeBlockedReasonLabel).toList(growable: false);
  }

  String get stairAccessLabel {
    if (steps.any((step) => _routeStepStairState(step) == 'stairOnly')) {
      return '계단 포함';
    }
    if (steps.isNotEmpty &&
        steps.every((step) => _routeStepStairState(step) == 'stepFree')) {
      return '계단 없음 확인';
    }
    return '계단 여부 확인 필요';
  }

  int get walkingDistanceMeters {
    return _walkingDistanceMeters ??
        steps.fold<int>(
          0,
          (sum, step) => step.isWalkingStep ? sum + step.distanceMeters : sum,
        );
  }

  int get transferCount {
    if (_transferCount != null) {
      return _transferCount;
    }
    final typedTransfers = steps.where((step) => step.stepType == 'transfer');
    if (typedTransfers.isNotEmpty) {
      return typedTransfers.length;
    }
    var previousLine = '';
    var changes = 0;
    for (final step in movementSteps) {
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

  String get summaryTitle => '$originStationName에서 $destinationStationName까지';

  String get statusLabel {
    return switch (status) {
      'FOUND' => '경로를 찾았습니다',
      'BLOCKED' => '안내할 수 있는 경로가 없습니다',
      _ => '확인이 필요합니다',
    };
  }

  String get scoreLabel => burdenLevelLabel;

  String get lineLabel => lineName.isEmpty ? '노선 확인 필요' : lineName;

  bool get isBlocked => status == 'BLOCKED';

  bool get needsConfirmation => !isBlocked && status != 'FOUND';

  bool get isLocalResult => routeSearchId.startsWith('local-');

  RouteSearchStep? get arrivalGuidanceStep {
    for (final step in steps.reversed) {
      final isDestinationAccessStep =
          step.requiresAccessibilityCheck &&
          step.fromStationId == destinationStationId &&
          step.toStationId == destinationStationId;
      if (isDestinationAccessStep) {
        return step;
      }
    }
    return null;
  }

  List<RouteSearchStep> get movementSteps {
    final arrivalStep = arrivalGuidanceStep;
    if (arrivalStep == null) {
      return steps;
    }
    return steps.where((step) => !identical(step, arrivalStep)).toList();
  }

  String get mobilityLabel => _mobilityLabelFor(mobilityType);

  String get comfortLabel {
    if (isBlocked) {
      return '다른 경로 필요';
    }
    return burdenLevelLabel;
  }

  String get guidanceLabel {
    if (isBlocked) {
      return '현재 조건으로 안내 어려움';
    }
    if (status == 'FOUND' && warnings.isEmpty) {
      return '안내 가능';
    }
    return '확인 후 이동';
  }

  IconData get guidanceIcon {
    if (isBlocked) {
      return Icons.priority_high;
    }
    return guidanceLabel == '안내 가능' ? Icons.check_circle : Icons.warning_amber;
  }

  String get attentionLabel {
    if (isBlocked) {
      return '안내 불가 이유';
    }
    if (needsConfirmation) {
      return '확인 필요 이유';
    }
    return warnings.isEmpty ? '주의 없음' : '주의 확인';
  }

  String get semanticLabel {
    // 결과 첫 문장은 사용자가 이동 가능 여부를 바로 판단할 수 있게 구성한다.
    final parts = <String>[
      '경로 검색 결과',
      guidanceLabel,
      mobilityLabel,
      summaryTitle,
      lineLabel,
      comfortLabel,
      stairAccessLabel,
    ];
    if (!isBlocked && warnings.isNotEmpty) {
      parts.add(attentionLabel);
    }
    final safeRecommendationReasons = recommendationReasonLabels;
    if (!isBlocked && safeRecommendationReasons.isNotEmpty) {
      parts.add('추천 이유 ${safeRecommendationReasons.join(', ')}');
    }
    final arrivalStep = arrivalGuidanceStep;
    if (arrivalStep != null) {
      parts.add('도착 안내 ${arrivalStep.userDescription}');
    }
    final safeBlockedReasons = blockedReasonLabels;
    if (safeBlockedReasons.isNotEmpty) {
      parts.add('$attentionLabel ${safeBlockedReasons.join(', ')}');
    }
    if (isBlocked) {
      parts.add('다음 행동 $_routeSearchFailureNextAction');
    }
    if (warnings.isNotEmpty) {
      parts.add(
        '주의 ${warnings.map((warning) => warning.userMessage).join(', ')}',
      );
    }
    final stepsForGuidance = movementSteps;
    if (stepsForGuidance.isNotEmpty) {
      parts.add(
        '이동 안내 ${stepsForGuidance.map((step) => step.semanticGuidanceLabel).join(', ')}',
      );
    }
    parts.add('안전 안내 $_routeSafetyGuidanceNotice');
    if (isBlocked) {
      parts.add('확인 요청 $_routeBlockedConfirmationNotice');
    }
    return parts.join(', ');
  }

  String get burdenLevelLabel {
    if (isBlocked) {
      return '이동 부담 확인 필요';
    }
    if (movementSteps.isEmpty) {
      return '이동 부담 확인 필요';
    }
    if (_hasHighBurdenFact) {
      return '이동 부담 높음';
    }
    if (_hasMediumBurdenFact) {
      return '이동 부담 보통';
    }
    return '이동 부담 낮음';
  }

  bool get _hasHighBurdenFact {
    return walkingDistanceMeters >= 1000 ||
        transferCount >= 2 ||
        movementSteps.any(
          (step) =>
              step.includesStairs || _routeStepStairState(step) == 'stairOnly',
        );
  }

  bool get _hasMediumBurdenFact {
    return walkingDistanceMeters >= 400 ||
        transferCount >= 1 ||
        movementSteps.any(
          (step) =>
              step.requiresAccessibilityCheck ||
              _routeStepStairState(step) == 'unknown',
        );
  }
}

class RouteSearchStep {
  const RouteSearchStep({
    required this.sequence,
    this.stepType = '',
    required this.title,
    required this.description,
    required this.lineId,
    required this.lineName,
    required this.fromStationId,
    required this.toStationId,
    required this.estimatedMinutes,
    required this.distanceMeters,
    required this.includesStairs,
    this.stairAccessState = '',
    required this.requiresAccessibilityCheck,
    this.actionTitle = '',
    this.actionDetail = '',
    this.reason = '',
    this.evidenceSources = const [],
    this.timeSource = '',
    this.distanceSource = '',
    this.confidenceLabel = '',
  });

  factory RouteSearchStep.fromJson(Map<String, Object?> json) {
    final title = _requiredRouteString(json, 'title');
    final description = _requiredRouteString(json, 'description');
    final includesStairs = _requiredRouteBool(json, 'includesStairs');
    return RouteSearchStep(
      sequence: _requiredRouteInt(json, 'sequence'),
      stepType: _optionalRouteString(json, 'stepType'),
      title: title,
      description: description,
      lineId: _optionalRouteString(json, 'lineId'),
      lineName: _optionalRouteString(json, 'lineName'),
      fromStationId: _optionalRouteString(json, 'fromStationId'),
      toStationId: _optionalRouteString(json, 'toStationId'),
      estimatedMinutes: _requiredRouteInt(json, 'estimatedMinutes'),
      distanceMeters: _requiredRouteInt(json, 'distanceMeters'),
      includesStairs: includesStairs,
      stairAccessState: _routeStepStairAccessStateFromJson(
        json,
        includesStairs,
      ),
      requiresAccessibilityCheck: _requiredRouteBool(
        json,
        'requiresAccessibilityCheck',
      ),
      actionTitle: _optionalRouteString(json, 'actionTitle'),
      actionDetail: _optionalRouteString(json, 'actionDetail').isEmpty
          ? description
          : _optionalRouteString(json, 'actionDetail'),
      reason: _optionalRouteString(json, 'reason'),
      evidenceSources: _routeStringList(
        json['evidenceSources'],
        'route step evidence source',
      ),
      timeSource: _optionalRouteString(json, 'timeSource', fallback: 'UNKNOWN'),
      distanceSource: _optionalRouteString(
        json,
        'distanceSource',
        fallback: 'UNKNOWN',
      ),
      confidenceLabel: _optionalRouteString(
        json,
        'confidenceLabel',
        fallback: '확인 필요',
      ),
    );
  }

  final int sequence;
  final String stepType;
  final String title;
  final String description;
  final String lineId;
  final String lineName;
  final String fromStationId;
  final String toStationId;
  final int estimatedMinutes;
  final int distanceMeters;
  final bool includesStairs;
  final String stairAccessState;
  final bool requiresAccessibilityCheck;
  final String actionTitle;
  final String actionDetail;
  final String reason;
  final List<String> evidenceSources;
  final String timeSource;
  final String distanceSource;
  final String confidenceLabel;

  String get userReason => _routeStepReasonLabel(reason);

  String get userDescription => _routeStepDetailLabel(stepType: stepType);

  String get burdenLabel {
    final labels = <String>[
      _routeDurationLabel(estimatedMinutes),
      _routeDistanceLabel(distanceMeters),
      if (includesStairs) '계단 포함',
      if (requiresAccessibilityCheck) '접근성 확인',
    ];
    return labels.join(' · ');
  }

  String get semanticGuidanceLabel {
    final safeReason = _routeStepReasonLabel(reason);
    final labels = <String>[
      '$sequence번 ${actionTitle.isEmpty ? title : actionTitle}',
      _routeStepDetailLabel(stepType: stepType),
      if (safeReason.isNotEmpty) safeReason,
      burdenLabel,
      if (confidenceLabel.isNotEmpty) confidenceLabel,
      if (hasMetricSourceMetadata) metricSourceLabel,
    ];
    return labels.join(', ');
  }

  bool get hasMetricSourceMetadata =>
      timeSource.isNotEmpty ||
      distanceSource.isNotEmpty ||
      confidenceLabel.isNotEmpty;

  bool get isWalkingStep {
    return switch (stepType) {
      'entry' || 'exit' || 'transfer' || 'internal' => true,
      'ride' => false,
      _ => requiresAccessibilityCheck,
    };
  }

  String get metricSourceLabel {
    if (!hasMetricSourceMetadata) {
      return '';
    }
    if (timeSource == 'ESTIMATED_CONSTANT' ||
        distanceSource == 'ESTIMATED_CONSTANT') {
      return '추정 시간과 거리, 현장 안내 우선';
    }
    if (timeSource == 'UNKNOWN' || distanceSource == 'UNKNOWN') {
      return '시간 또는 거리 확인 필요';
    }
    return '앱 경로 데이터 기준';
  }
}

String _routeDurationLabel(int estimatedMinutes) {
  if (estimatedMinutes <= 0) {
    return '시간 확인 필요';
  }
  return '약 $estimatedMinutes분';
}

String _routeDistanceLabel(int distanceMeters) {
  if (distanceMeters <= 0) {
    return '거리 확인 필요';
  }
  if (distanceMeters < 1000) {
    return '${distanceMeters}m';
  }

  final kilometers = distanceMeters / 1000;
  if (distanceMeters % 1000 == 0) {
    return '${kilometers.toStringAsFixed(0)}km';
  }
  return '${kilometers.toStringAsFixed(1)}km';
}

String _routeWarningLabel(String code) {
  return switch (code.trim()) {
    'LOW_DATA_CONFIDENCE' => '일부 시설 정보는 확인이 필요합니다.',
    'STALE_ACCESSIBILITY_DATA' => '접근성 시설 정보가 최근 확인되지 않았습니다.',
    'STAIR_ONLY_ACCESS' => '계단 포함 구간이 있습니다.',
    'STAIR_ONLY_ACCESS_UNKNOWN' => '계단 없는 동선 여부를 확인할 수 없습니다.',
    'GENERATED_CONNECTOR_UNVERIFIED' => '연결 추정 구간입니다. 현장 확인이 필요합니다.',
    'DURATION_UNKNOWN' => '소요 시간 확인이 필요한 구간입니다.',
    'ROUTE_GRAPH_UNKNOWN' => '경로 연결 정보를 확인할 수 없습니다.',
    'ACCESSIBILITY_STATE_UNKNOWN' => '접근성 시설 이용 가능 여부를 확인할 수 없습니다.',
    _ => '일부 이동 정보를 확인하지 못했어요.',
  };
}

String _routeBlockedReasonLabel(String reason) {
  return switch (reason.trim()) {
    'STAIR_ONLY_ACCESS' => '계단 없는 경로를 찾지 못했습니다.',
    'STAIR_ONLY_ACCESS_UNKNOWN' => '계단 없는 동선 여부를 확인할 수 없습니다.',
    'GENERATED_CONNECTOR_UNVERIFIED' => '계단 없는 동선 여부를 확인할 수 없습니다.',
    'FACILITY_UNAVAILABLE' => '필수 접근성 시설을 사용할 수 없습니다.',
    'ACCESSIBILITY_STATE_UNKNOWN' => '접근성 시설 이용 가능 여부를 확인할 수 없습니다.',
    'ROUTE_GRAPH_UNKNOWN' => '경로 연결 정보를 확인할 수 없습니다.',
    '계단 없는 경로를 찾지 못했습니다.' => '계단 없는 경로를 찾지 못했습니다.',
    '계단 없는 동선 여부를 확인할 수 없습니다.' => '계단 없는 동선 여부를 확인할 수 없습니다.',
    '필수 접근성 시설을 사용할 수 없습니다.' => '필수 접근성 시설을 사용할 수 없습니다.',
    '접근성 시설 이용 가능 여부를 확인할 수 없습니다.' => '접근성 시설 이용 가능 여부를 확인할 수 없습니다.',
    '경로 연결 정보를 확인할 수 없습니다.' => '경로 연결 정보를 확인할 수 없습니다.',
    _ => '안내 가능한 경로를 찾지 못했습니다.',
  };
}

String _routeStepReasonLabel(String reason) {
  if (reason.trim().isEmpty) {
    return '';
  }
  return '선택한 경로 기준으로 안내합니다.';
}

String _routeStepDetailLabel({required String stepType}) {
  return switch (stepType) {
    'entry' => '계단 없는 승강장 접근 동선을 확인해 이동합니다.',
    'exit' => '도착역에서 계단 없는 출구 동선을 확인합니다.',
    'transfer' => '다음 노선으로 갈아탈 준비를 합니다.',
    'ride' => '열차를 이용해 이동합니다.',
    _ => '안내된 순서대로 이동합니다.',
  };
}

class RouteSearchWarning {
  const RouteSearchWarning({required this.code, this.message = ''});

  factory RouteSearchWarning.fromJson(Map<String, Object?> json) {
    return RouteSearchWarning(
      code: _requiredRouteString(json, 'code'),
      message: _optionalRouteString(json, 'message'),
    );
  }

  final String code;
  final String message;

  String get userMessage => _routeWarningLabel(code);
}

enum RouteSearchViewStatus { idle, loading, success, failure }

class RouteSearchState {
  const RouteSearchState({
    required this.status,
    this.result,
    this.message = '',
  });

  const RouteSearchState.idle()
    : status = RouteSearchViewStatus.idle,
      result = null,
      message = '';

  final RouteSearchViewStatus status;
  final RouteSearchResult? result;
  final String message;
}

class RouteSearchController extends ChangeNotifier {
  RouteSearchController({required this.repository});

  final RouteSearchRepository repository;

  RouteSearchState _state = const RouteSearchState.idle();
  int _searchRequestId = 0;
  bool _disposed = false;

  RouteSearchState get state => _state;

  Future<void> search(RouteSearchRequest request) async {
    if (_disposed) {
      return;
    }

    final requestId = ++_searchRequestId;
    final trimmedRequest = request.trimmed();
    if (trimmedRequest.originStationId.isEmpty ||
        trimmedRequest.destinationStationId.isEmpty) {
      _emitState(
        const RouteSearchState(
          status: RouteSearchViewStatus.failure,
          message: '출발역과 도착역을 입력해 주세요.',
        ),
      );
      return;
    }

    _emitState(const RouteSearchState(status: RouteSearchViewStatus.loading));

    try {
      final result = await repository.searchRoute(trimmedRequest);
      if (_disposed || requestId != _searchRequestId) {
        return;
      }
      _emitState(
        RouteSearchState(status: RouteSearchViewStatus.success, result: result),
      );
    } on RouteSearchException catch (error) {
      if (_disposed || requestId != _searchRequestId) {
        return;
      }
      _emitState(
        RouteSearchState(
          status: RouteSearchViewStatus.failure,
          message: error.message,
        ),
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '경로 검색 화면 처리 중 예외가 발생했습니다.',
      );
      if (_disposed || requestId != _searchRequestId) {
        return;
      }
      _emitState(
        const RouteSearchState(
          status: RouteSearchViewStatus.failure,
          message: _routeSearchErrorMessage,
        ),
      );
    }
  }

  void reset() {
    if (_disposed) {
      return;
    }
    _searchRequestId += 1;
    _emitState(const RouteSearchState.idle());
  }

  void _emitState(RouteSearchState nextState) {
    if (_disposed) {
      return;
    }
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    // 화면을 떠난 뒤 도착한 네트워크 응답이 dispose된 리스너를 깨우지 않게 막는다.
    _disposed = true;
    super.dispose();
  }
}

class RouteSearchScreen extends StatefulWidget {
  RouteSearchScreen({
    required this.repository,
    required this.stationRepository,
    this.routeFeedbackRepository,
    this.favoriteRouteRepository,
    this.simpleViewEnabled = true,
    this.initialDraft,
    String? initialMobilityType,
    super.key,
  }) : initialMobilityType = _resolveInitialMobilityType(initialMobilityType);

  final RouteSearchRepository repository;
  final StationSearchRepository stationRepository;
  final RouteFeedbackRepository? routeFeedbackRepository;
  final FavoriteRouteRepository? favoriteRouteRepository;
  final RouteDraft? initialDraft;
  final String initialMobilityType;
  final bool simpleViewEnabled;

  @override
  State<RouteSearchScreen> createState() => _RouteSearchScreenState();
}

String _resolveInitialMobilityType(String? mobilityType) {
  if (mobilityType == null) {
    return mobilityProfileOptions.first.mobilityType;
  }

  final isKnownMobilityType = mobilityProfileOptions.any(
    (option) => option.mobilityType == mobilityType,
  );

  // 서버에 보내는 이동 조건은 화면 드롭다운에 있는 값으로만 제한한다.
  return isKnownMobilityType
      ? mobilityType
      : mobilityProfileOptions.first.mobilityType;
}

class _RouteSearchScreenState extends State<RouteSearchScreen> {
  late final RouteSearchController _controller;
  StationSearchResult? _originStation;
  StationSearchResult? _destinationStation;
  _RouteStationRole? _activeStationPicker;
  late String _selectedMobilityType;
  String _validationMessage = '';

  @override
  void initState() {
    super.initState();
    _controller = RouteSearchController(repository: widget.repository);
    _originStation = _stationFromDraft(widget.initialDraft?.origin);
    _destinationStation = _stationFromDraft(widget.initialDraft?.destination);
    _selectedMobilityType = widget.initialMobilityType;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('길찾기')),
      bottomNavigationBar: Padding(
        padding: easySubwayBottomActionInsets(context),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final isLoading =
                _controller.state.status == RouteSearchViewStatus.loading;
            final canSubmit =
                _originStation != null && _destinationStation != null;
            final submitLabel = isLoading
                ? '경로 검색 중'
                : canSubmit
                ? '길찾기'
                : '길찾기, 출발역과 도착역을 먼저 선택해 주세요';
            return Semantics(
              button: true,
              enabled: canSubmit && !isLoading,
              label: submitLabel,
              child: ExcludeSemantics(
                child: FilledButton(
                  key: const Key('routeSearchSubmitButton'),
                  onPressed: canSubmit && !isLoading ? _submit : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(60),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(isLoading ? '경로 검색 중' : '길찾기'),
                ),
              ),
            );
          },
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            _RoutePointPickerCard(
              key: const Key('routePointPickerCard'),
              originStation: _originStation,
              destinationStation: _destinationStation,
              originPicker: _activeStationPicker == _RouteStationRole.origin
                  ? _buildRouteStationPicker(_RouteStationRole.origin)
                  : null,
              destinationPicker:
                  _activeStationPicker == _RouteStationRole.destination
                  ? _buildRouteStationPicker(_RouteStationRole.destination)
                  : null,
              onOriginTap: () => _openStationPicker(_RouteStationRole.origin),
              onDestinationTap: () =>
                  _openStationPicker(_RouteStationRole.destination),
              onSwap: _swapStations,
            ),
            const SizedBox(height: 18),
            _RouteRecentDestinationList(
              repository: widget.favoriteRouteRepository,
              onSelected: _updateDestinationStation,
            ),
            if (_validationMessage.isNotEmpty) ...[
              _RouteSearchMessage(
                message: _validationMessage,
                liveRegion: true,
              ),
              const SizedBox(height: 16),
            ],
            _RouteSectionHeader(
              title: widget.simpleViewEnabled ? '이동 조건' : '검색 조건',
            ),
            const SizedBox(height: 8),
            // 단순 보기에서는 드롭다운 대신 현재 조건을 크게 보여주고, 필요할 때만 바꿀 수 있게 한다.
            if (widget.simpleViewEnabled)
              _RouteMobilityTypeSummary(
                mobilityType: _selectedMobilityType,
                onChangeRequested: _showMobilityTypePicker,
              )
            else
              InputDecorator(
                key: const Key('routeMobilityTypeInput'),
                decoration: const InputDecoration(
                  labelText: '이동 조건',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedMobilityType,
                    isExpanded: true,
                    items: [
                      for (final option in mobilityProfileOptions)
                        DropdownMenuItem<String>(
                          value: option.mobilityType,
                          child: Text(option.title),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _selectedMobilityType = value;
                      });
                    },
                  ),
                ),
              ),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => _RouteSearchBody(
                state: _controller.state,
                routeFeedbackRepository: widget.routeFeedbackRepository,
                favoriteRouteRepository: widget.favoriteRouteRepository,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (_controller.state.status == RouteSearchViewStatus.loading) {
      return;
    }
    if (_originStation == null || _destinationStation == null) {
      _controller.reset();
      setState(() {
        _validationMessage = '출발역과 도착역을 검색 결과에서 선택해 주세요.';
      });
      return;
    }
    setState(() {
      _validationMessage = '';
    });

    // 화면에는 역 이름을 보여주지만 API에는 안정적인 station id만 전달한다.
    _controller.search(
      RouteSearchRequest(
        originStationId: _originStation!.id,
        destinationStationId: _destinationStation!.id,
        mobilityType: _selectedMobilityType,
      ),
    );
  }

  Widget _buildRouteStationPicker(_RouteStationRole role) {
    final isOrigin = role == _RouteStationRole.origin;
    return _RouteStationPicker(
      labelText: isOrigin ? '출발역' : '도착역',
      inputKey: isOrigin
          ? const Key('routeOriginStationInput')
          : const Key('routeDestinationStationInput'),
      searchButtonKey: isOrigin
          ? const Key('routeOriginStationSearchButton')
          : const Key('routeDestinationStationSearchButton'),
      optionKeyPrefix: isOrigin
          ? 'routeOriginStationOption'
          : 'routeDestinationStationOption',
      selectedStation: isOrigin ? _originStation : _destinationStation,
      repository: widget.stationRepository,
      onSelected: isOrigin ? _updateOriginStation : _updateDestinationStation,
    );
  }

  void _updateOriginStation(StationSearchResult? station) {
    setState(() {
      _originStation = station;
      if (station != null) {
        _activeStationPicker = null;
      }
      _validationMessage = '';
    });
    _controller.reset();
  }

  void _updateDestinationStation(StationSearchResult? station) {
    setState(() {
      _destinationStation = station;
      if (station != null) {
        _activeStationPicker = null;
      }
      _validationMessage = '';
    });
    _controller.reset();
  }

  void _openStationPicker(_RouteStationRole role) {
    setState(() {
      _activeStationPicker = _activeStationPicker == role ? null : role;
      _validationMessage = '';
    });
  }

  void _swapStations() {
    setState(() {
      final origin = _originStation;
      _originStation = _destinationStation;
      _destinationStation = origin;
      _activeStationPicker = null;
      _validationMessage = '';
    });
    _controller.reset();
  }

  Future<void> _showMobilityTypePicker() async {
    final selectedMobilityType = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        var pendingMobilityType = _selectedMobilityType;
        return SafeArea(
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              return FractionallySizedBox(
                heightFactor: 0.78,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '이동 조건',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: const Color(0xFF102A2C),
                                  fontWeight: FontWeight.w900,
                                  height: 1.25,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '상황에 맞는 이동 조건을 고른 뒤 적용해 주세요.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: const Color(0xFF50656F),
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        key: const Key('routeMobilityOptionsList'),
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        children: [
                          for (final option in mobilityProfileOptions)
                            _RouteMobilityTypeOptionButton(
                              key: Key(
                                'routeMobilityOption-${option.mobilityType}',
                              ),
                              option: option,
                              selected:
                                  option.mobilityType == pendingMobilityType,
                              onSelected: () {
                                setSheetState(() {
                                  pendingMobilityType = option.mobilityType;
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      child: FilledButton.icon(
                        key: const Key('routeMobilityApplyButton'),
                        onPressed: () =>
                            Navigator.of(context).pop(pendingMobilityType),
                        icon: const Icon(Icons.check),
                        label: const Text('적용'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    if (!mounted || selectedMobilityType == null) {
      return;
    }
    setState(() {
      _selectedMobilityType = selectedMobilityType;
    });
    _controller.reset();
  }
}

StationSearchResult? _stationFromDraft(RouteDraftStation? station) {
  if (station == null) {
    return null;
  }
  return StationSearchResult(
    id: station.id,
    nameKo: station.nameKo,
    nameEn: '',
    region: '',
    dataQualityLevel: '',
    lastVerifiedAt: '',
    lines: const [],
  );
}

enum _RouteStationRole { origin, destination }

class _RoutePointPickerCard extends StatelessWidget {
  const _RoutePointPickerCard({
    required this.originStation,
    required this.destinationStation,
    required this.originPicker,
    required this.destinationPicker,
    required this.onOriginTap,
    required this.onDestinationTap,
    required this.onSwap,
    super.key,
  });

  final StationSearchResult? originStation;
  final StationSearchResult? destinationStation;
  final Widget? originPicker;
  final Widget? destinationPicker;
  final VoidCallback onOriginTap;
  final VoidCallback onDestinationTap;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD5E2E4)),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F071B2F),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 58, 8),
            child: Column(
              children: [
                originPicker ??
                    _RoutePointRow(
                      key: const Key('routeOriginPointButton'),
                      label: '출발',
                      station: originStation,
                      fallback: '출발역 선택',
                      onTap: onOriginTap,
                    ),
                const Divider(height: 1, color: Color(0xFFE0E7EC)),
                destinationPicker ??
                    _RoutePointRow(
                      key: const Key('routeDestinationPointButton'),
                      label: '도착',
                      station: destinationStation,
                      fallback: '도착역 선택',
                      onTap: onDestinationTap,
                    ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 9),
            child: Semantics(
              button: true,
              label: '출발 도착 바꾸기',
              onTap: onSwap,
              child: ExcludeSemantics(
                child: IconButton.outlined(
                  key: const Key('routeSwapStationsButton'),
                  onPressed: onSwap,
                  icon: const Icon(Icons.swap_vert),
                  color: const Color(0xFF102A2C),
                  style: IconButton.styleFrom(
                    fixedSize: const Size(48, 48),
                    side: const BorderSide(color: Color(0xFF9DB6BA)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutePointRow extends StatelessWidget {
  const _RoutePointRow({
    required this.label,
    required this.station,
    required this.fallback,
    required this.onTap,
    super.key,
  });

  final String label;
  final StationSearchResult? station;
  final String fallback;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stationName = station == null
        ? fallback
        : _routeStationDisplayName(station!);
    final semanticsLabel = station == null
        ? stationName
        : '$label $stationName';
    return Semantics(
      button: true,
      label: semanticsLabel,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    stationName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF102A2C),
                      fontSize: 22,
                      height: 1.2,
                    ),
                  ),
                ),
                const Icon(Icons.map_outlined, color: Color(0xFF50656F)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteSectionHeader extends StatelessWidget {
  const _RouteSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF102A2C),
              fontWeight: FontWeight.w900,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

class _RouteRecentDestinationList extends StatefulWidget {
  const _RouteRecentDestinationList({
    required this.repository,
    required this.onSelected,
  });

  final FavoriteRouteRepository? repository;
  final ValueChanged<StationSearchResult> onSelected;

  @override
  State<_RouteRecentDestinationList> createState() =>
      _RouteRecentDestinationListState();
}

class _RouteRecentDestinationListState
    extends State<_RouteRecentDestinationList> {
  Future<List<FavoriteRoute>>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository?.listFavoriteRoutes();
  }

  @override
  void didUpdateWidget(_RouteRecentDestinationList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _future = widget.repository?.listFavoriteRoutes();
    }
  }

  @override
  Widget build(BuildContext context) {
    final future = _future;
    if (future == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<List<FavoriteRoute>>(
      future: future,
      builder: (context, snapshot) {
        final routes = snapshot.data ?? const <FavoriteRoute>[];
        final destinations = _routeRecentDestinations(routes);
        if (destinations.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _RouteSectionHeader(title: '최근 도착지'),
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFD5E2E4)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  for (final entry in destinations.indexed) ...[
                    if (entry.$1 > 0)
                      const Divider(height: 1, color: Color(0xFFE0E7EC)),
                    _RouteRecentDestinationRow(
                      route: entry.$2,
                      onSelected: () => widget.onSelected(
                        _stationFromFavoriteDestination(entry.$2),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
        );
      },
    );
  }
}

List<FavoriteRoute> _routeRecentDestinations(List<FavoriteRoute> routes) {
  final seen = <String>{};
  final destinations = <FavoriteRoute>[];
  for (final route in routes) {
    if (seen.add(route.destinationStationId)) {
      destinations.add(route);
    }
    if (destinations.length == 2) {
      break;
    }
  }
  return destinations;
}

StationSearchResult _stationFromFavoriteDestination(FavoriteRoute route) {
  final lineName = route.lineName;
  return StationSearchResult(
    id: route.destinationStationId,
    nameKo: route.destinationStationName,
    nameEn: '',
    region: '',
    dataQualityLevel: '',
    lastVerifiedAt: '',
    lines: lineName.isEmpty ? const [] : [_routeRecentLine(lineName)],
  );
}

StationSearchLine _routeRecentLine(String name) {
  final id = 'line-${stationLineBadgeText(name)}';
  return StationSearchLine(
    id: id,
    name: name,
    color: _routeLineColor(name),
    stationCode: '',
  );
}

String _routeLineColor(String name) {
  const colors = {
    '1호선': '#263C96',
    '2호선': '#00A84D',
    '3호선': '#EF7C1C',
    '4호선': '#00A5DE',
    '5호선': '#996CAC',
    '6호선': '#CD7C2F',
    '7호선': '#747F00',
    '8호선': '#E6186C',
    '9호선': '#BDB092',
    '경의중앙선': '#77C4A3',
    '수인분당선': '#F5A200',
    '신분당선': '#D4003B',
    '공항철도': '#0090D2',
  };
  for (final entry in colors.entries) {
    if (name.contains(entry.key)) {
      return entry.value;
    }
  }
  return '#006D77';
}

class _RouteRecentDestinationRow extends StatelessWidget {
  const _RouteRecentDestinationRow({
    required this.route,
    required this.onSelected,
  });

  final FavoriteRoute route;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final title = _routeStationNameDisplay(route.destinationStationName);
    final lines = route.lineName.isEmpty
        ? const <StationSearchLine>[]
        : [_routeRecentLine(route.lineName)];
    final lineLabel = lines.isEmpty
        ? route.lineLabel
        : lines.map((line) => line.name).join(', ');
    return Semantics(
      button: true,
      label: '$title, $lineLabel, 선택',
      onTap: onSelected,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(14),
          child: ListTile(
            leading: const Icon(Icons.train_outlined, color: Color(0xFF006D77)),
            title: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF102A2C),
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: lines.isEmpty
                  ? Text(lineLabel)
                  : Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        for (final line in lines) _RouteRecentLine(line: line),
                      ],
                    ),
            ),
            trailing: const Text('선택'),
          ),
        ),
      ),
    );
  }
}

class _RouteRecentLine extends StatelessWidget {
  const _RouteRecentLine({required this.line});

  final StationSearchLine line;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: Key('routeRecentLineMark-${line.id}'),
          child: StationLineBadge(line: line, size: 16),
        ),
        const SizedBox(width: 5),
        Text(
          line.name,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF50656F),
            fontSize: 16,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _RouteMobilityTypeSummary extends StatelessWidget {
  const _RouteMobilityTypeSummary({
    required this.mobilityType,
    required this.onChangeRequested,
  });

  final String mobilityType;
  final VoidCallback onChangeRequested;

  @override
  Widget build(BuildContext context) {
    final option = _mobilityOptionFor(mobilityType);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          option.title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: const Color(0xFF102A2C),
            fontWeight: FontWeight.w900,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          _routeMobilityConditionLabel(option),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF50656F),
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),
      ],
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label:
          '현재 이동 조건 ${option.title}, ${_routeMobilityConditionLabel(option)}',
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFE9F5F6),
          border: Border.all(color: const Color(0xFFB9D4D8)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      Icon(
                        option.icon,
                        color: const Color(0xFF006D77),
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: content),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Semantics(
                button: true,
                label: '이동 조건 바꾸기, 현재 ${option.title}',
                onTap: onChangeRequested,
                child: ExcludeSemantics(
                  child: OutlinedButton(
                    key: const Key('routeSimpleMobilityTypeButton'),
                    onPressed: onChangeRequested,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(64, 48),
                    ),
                    child: const Text('변경'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteMobilityTypeOptionButton extends StatelessWidget {
  const _RouteMobilityTypeOptionButton({
    required this.option,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final MobilityProfileOption option;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final style = selected
        ? FilledButton.styleFrom(minimumSize: const Size.fromHeight(64))
        : OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(64));
    final label = Row(
      children: [
        Icon(option.icon),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                option.title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                option.summary,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _routeMobilityConditionLabel(option),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
        if (selected)
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Icon(Icons.check_circle),
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        label: _routeMobilityOptionSemanticsLabel(option, selected),
        button: true,
        selected: selected,
        child: selected
            ? FilledButton(onPressed: onSelected, style: style, child: label)
            : OutlinedButton(onPressed: onSelected, style: style, child: label),
      ),
    );
  }
}

MobilityProfileOption _mobilityOptionFor(String mobilityType) {
  return mobilityProfileOptions.firstWhere(
    (option) => option.mobilityType == mobilityType,
    orElse: () => mobilityProfileOptions.first,
  );
}

String _routeMobilityConditionLabel(MobilityProfileOption option) {
  return option.conditionSummary;
}

String _routeMobilityOptionSemanticsLabel(
  MobilityProfileOption option,
  bool selected,
) {
  final state = selected ? '현재 선택' : '선택 가능';
  return '${option.title} $state, ${option.summary}, ${_routeMobilityConditionLabel(option)}';
}

class _RouteStationPicker extends StatefulWidget {
  const _RouteStationPicker({
    required this.labelText,
    required this.inputKey,
    required this.searchButtonKey,
    required this.optionKeyPrefix,
    required this.selectedStation,
    required this.repository,
    required this.onSelected,
  });

  final String labelText;
  final Key inputKey;
  final Key searchButtonKey;
  final String optionKeyPrefix;
  final StationSearchResult? selectedStation;
  final StationSearchRepository repository;
  final ValueChanged<StationSearchResult?> onSelected;

  @override
  State<_RouteStationPicker> createState() => _RouteStationPickerState();
}

class _RouteStationPickerState extends State<_RouteStationPicker> {
  late final StationSearchController _controller;
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = StationSearchController(repository: widget.repository);
    _syncTextWithSelectedStation();
    _textController.addListener(_clearSelectedStationIfNeeded);
  }

  @override
  void didUpdateWidget(_RouteStationPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedStation?.id != oldWidget.selectedStation?.id) {
      _syncTextWithSelectedStation();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedStation = widget.selectedStation;
    final labelText = selectedStation == null
        ? widget.labelText
        : '${widget.labelText.replaceAll('역', '')} ${_routeStationDisplayName(selectedStation)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: selectedStation == null
              ? '${widget.labelText} 입력'
              : '${widget.labelText} 선택됨, ${selectedStation.nameKo}',
          textField: true,
          liveRegion: selectedStation != null,
          child: TextField(
            key: widget.inputKey,
            controller: _textController,
            minLines: 1,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 20, height: 1.35),
            decoration: InputDecoration(
              labelText: labelText,
              hintText: '역 이름을 입력해 주세요',
              floatingLabelBehavior: FloatingLabelBehavior.always,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              suffixIcon: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final isLoading =
                      _controller.state.status == StationSearchStatus.loading;
                  return IconButton(
                    key: widget.searchButtonKey,
                    tooltip: '${widget.labelText} 검색',
                    onPressed: isLoading ? null : _search,
                    icon: const Icon(Icons.search),
                  );
                },
              ),
            ),
            onSubmitted: (_) => _search(),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return _RouteStationSearchBody(
              labelText: widget.labelText,
              optionKeyPrefix: widget.optionKeyPrefix,
              state: _controller.state,
              onSelected: _selectStation,
            );
          },
        ),
      ],
    );
  }

  void _search() {
    if (_controller.state.status == StationSearchStatus.loading) {
      return;
    }
    _controller.search(_textController.text);
  }

  void _selectStation(StationSearchResult station) {
    widget.onSelected(station);
    _textController.text = station.nameKo;
    // 선택 후 후보 목록을 접어 다음 입력을 바로 찾을 수 있게 한다.
    unawaited(_controller.search(''));
  }

  void _syncTextWithSelectedStation() {
    final selectedStation = widget.selectedStation;
    if (selectedStation == null ||
        _textController.text == selectedStation.nameKo) {
      return;
    }
    _textController.text = selectedStation.nameKo;
  }

  void _clearSelectedStationIfNeeded() {
    final selectedStation = widget.selectedStation;
    if (selectedStation == null) {
      return;
    }
    if (_textController.text.trim() == selectedStation.nameKo) {
      return;
    }
    widget.onSelected(null);
  }
}

String _routeStationDisplayName(StationSearchResult station) {
  return _routeStationNameDisplay(station.nameKo);
}

String _routeStationNameDisplay(String value) {
  final name = value.trim();
  return name.endsWith('역') ? name : '$name역';
}

class _RouteStationSearchBody extends StatelessWidget {
  const _RouteStationSearchBody({
    required this.labelText,
    required this.optionKeyPrefix,
    required this.state,
    required this.onSelected,
  });

  final String labelText;
  final String optionKeyPrefix;
  final StationSearchState state;
  final ValueChanged<StationSearchResult> onSelected;

  @override
  Widget build(BuildContext context) {
    return switch (state.status) {
      StationSearchStatus.idle => const SizedBox.shrink(),
      StationSearchStatus.loading => Semantics(
        label: '$labelText 검색 중',
        liveRegion: true,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
      StationSearchStatus.empty || StationSearchStatus.failure =>
        _RouteSearchMessage(message: state.message, liveRegion: true),
      StationSearchStatus.success => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: '$labelText 검색 결과 ${state.results.length}개',
            liveRegion: true,
            child: const SizedBox.shrink(),
          ),
          for (final result in state.results)
            _RouteStationOptionTile(
              key: Key('$optionKeyPrefix-${result.id}'),
              labelText: labelText,
              result: result,
              onSelected: onSelected,
            ),
        ],
      ),
    };
  }
}

class _RouteStationOptionTile extends StatelessWidget {
  const _RouteStationOptionTile({
    required this.labelText,
    required this.result,
    required this.onSelected,
    super.key,
  });

  final String labelText;
  final StationSearchResult result;
  final ValueChanged<StationSearchResult> onSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return MergeSemantics(
      child: Semantics(
        label: '$labelText 선택, ${result.semanticLabel}',
        button: true,
        onTap: () => onSelected(result),
        child: ExcludeSemantics(
          child: Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFD5E2E4)),
            ),
            child: InkWell(
              onTap: () => onSelected(result),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            result.nameKo,
                            style: textTheme.titleMedium?.copyWith(
                              color: const Color(0xFF102A2C),
                              fontWeight: FontWeight.w900,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 8),
                          StationLineBadges(lines: result.lines),
                          const SizedBox(height: 8),
                          Text(
                            result.lineLabel,
                            style: textTheme.bodyLarge?.copyWith(
                              color: const Color(0xFF29484B),
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            result.dataQualityLabel,
                            style: textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF405A5D),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.chevron_right,
                      color: Color(0xFF006D77),
                      size: 32,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteSearchBody extends StatelessWidget {
  const _RouteSearchBody({
    required this.state,
    required this.routeFeedbackRepository,
    required this.favoriteRouteRepository,
  });

  final RouteSearchState state;
  final RouteFeedbackRepository? routeFeedbackRepository;
  final FavoriteRouteRepository? favoriteRouteRepository;

  @override
  Widget build(BuildContext context) {
    return switch (state.status) {
      RouteSearchViewStatus.idle => const SizedBox.shrink(),
      RouteSearchViewStatus.loading => Semantics(
        label: '경로 검색 중',
        liveRegion: true,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
      RouteSearchViewStatus.failure => _RouteSearchFailureMessage(
        message: state.message,
      ),
      RouteSearchViewStatus.success => _RouteSearchResultCard(
        result: state.result!,
        routeFeedbackRepository: routeFeedbackRepository,
        favoriteRouteRepository: favoriteRouteRepository,
      ),
    };
  }
}

class _RouteSearchFailureMessage extends StatelessWidget {
  const _RouteSearchFailureMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final shouldShowNextAction = _shouldShowRouteSearchFailureNextAction(
      message,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RouteSearchMessage(message: message, liveRegion: true),
        if (shouldShowNextAction) ...[
          const SizedBox(height: 8),
          Semantics(
            key: const Key('routeSearchFailureNextAction'),
            container: true,
            excludeSemantics: true,
            liveRegion: true,
            label: '다음 행동, $_routeSearchFailureNextAction',
            child: Text(
              _routeSearchFailureNextAction,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF506B6F),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

bool _shouldShowRouteSearchFailureNextAction(String message) {
  return message != '출발역과 도착역을 입력해 주세요.' &&
      message != '출발역과 도착역을 검색 결과에서 선택해 주세요.';
}

class _RouteSearchMessage extends StatelessWidget {
  const _RouteSearchMessage({required this.message, this.liveRegion = false});

  final String message;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: liveRegion,
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: const Color(0xFF405A5D),
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}

enum _RouteWorkflowView {
  list,
  detail,
  guidance,
  internalRoute,
  blocked,
  feedback,
}

class _RouteSearchResultCard extends StatefulWidget {
  const _RouteSearchResultCard({
    required this.result,
    required this.routeFeedbackRepository,
    required this.favoriteRouteRepository,
  });

  final RouteSearchResult result;
  final RouteFeedbackRepository? routeFeedbackRepository;
  final FavoriteRouteRepository? favoriteRouteRepository;

  @override
  State<_RouteSearchResultCard> createState() => _RouteSearchResultCardState();
}

class _RouteSearchResultCardState extends State<_RouteSearchResultCard> {
  _RouteWorkflowView _view = _RouteWorkflowView.list;

  @override
  void didUpdateWidget(_RouteSearchResultCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result.routeSearchId != widget.result.routeSearchId) {
      _view = _RouteWorkflowView.list;
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    if (result.isBlocked) {
      return _RouteBlockedWorkflow(result: result);
    }

    final canUseRouteActions = _isRecommendedRoute(result);
    final canUseApiActions = !result.isLocalResult;
    final canSaveRoute =
        canUseApiActions &&
        widget.favoriteRouteRepository != null &&
        canUseRouteActions;
    final canOpenFeedback =
        canUseApiActions && widget.routeFeedbackRepository != null;

    return switch (_view) {
      _RouteWorkflowView.list => _RouteResultsListView(
        result: result,
        onOpenDetail: () => setState(() => _view = _RouteWorkflowView.detail),
      ),
      _RouteWorkflowView.detail => _RouteDetailWorkflowView(
        result: result,
        onBack: () => setState(() => _view = _RouteWorkflowView.list),
        onStartGuidance: !canUseRouteActions
            ? null
            : () => setState(() => _view = _RouteWorkflowView.guidance),
        onOpenFeedback: !canOpenFeedback
            ? null
            : () => setState(() => _view = _RouteWorkflowView.feedback),
        favoriteSaveButton: canSaveRoute
            ? _RouteFavoriteSaveButton(
                result: result,
                repository: widget.favoriteRouteRepository!,
              )
            : null,
      ),
      _RouteWorkflowView.guidance => _RouteGuidanceWorkflowView(
        result: result,
        onBack: () => setState(() => _view = _RouteWorkflowView.detail),
        onOpenInternalRoute: () =>
            setState(() => _view = _RouteWorkflowView.internalRoute),
        onOpenBlocked: !canOpenFeedback
            ? null
            : () => setState(() => _view = _RouteWorkflowView.feedback),
        onOpenFeedback: !canOpenFeedback
            ? null
            : () => setState(() => _view = _RouteWorkflowView.feedback),
      ),
      _RouteWorkflowView.internalRoute => _RouteInternalWorkflowView(
        result: result,
        onBack: () => setState(() => _view = _RouteWorkflowView.guidance),
      ),
      _RouteWorkflowView.blocked => _RouteBlockedWorkflow(result: result),
      _RouteWorkflowView.feedback => _RouteFeedbackWorkflowView(
        result: result,
        repository: widget.routeFeedbackRepository,
        onBack: () => setState(() => _view = _RouteWorkflowView.detail),
      ),
    };
  }
}

class _RouteResultsListView extends StatelessWidget {
  const _RouteResultsListView({
    required this.result,
    required this.onOpenDetail,
  });

  final RouteSearchResult result;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: result.semanticLabel,
          liveRegion: true,
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RouteSectionHeader(title: '추천 경로'),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        _RouteResultListButton(result: result, onPressed: onOpenDetail),
      ],
    );
  }
}

class _RouteDetailWorkflowView extends StatelessWidget {
  const _RouteDetailWorkflowView({
    required this.result,
    required this.onBack,
    required this.onStartGuidance,
    required this.onOpenFeedback,
    required this.favoriteSaveButton,
  });

  final RouteSearchResult result;
  final VoidCallback onBack;
  final VoidCallback? onStartGuidance;
  final VoidCallback? onOpenFeedback;
  final Widget? favoriteSaveButton;

  @override
  Widget build(BuildContext context) {
    final totalMinutes = _routeTotalMinutes(result);
    final meta = _routeMetaLabel(result);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RouteWorkflowBackButton(label: '경로 목록', onPressed: onBack),
        const SizedBox(height: 8),
        _RouteDarkSummaryCard(
          title: totalMinutes > 0 ? '$totalMinutes분' : result.statusLabel,
          subtitle: meta,
          chips: [
            _RouteSummaryChip(label: result.comfortLabel),
            _RouteSummaryChip(
              label: result.stairAccessLabel,
              icon: _routeStairAccessIcon(result),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _RouteStepSection(steps: result.movementSteps),
        if (result.arrivalGuidanceStep case final arrivalStep?) ...[
          const SizedBox(height: 8),
          _RouteArrivalGuidance(step: arrivalStep),
        ],
        if (result.warnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final warning in result.warnings)
            _RouteNotice(
              title: '주의 확인',
              text: warning.userMessage,
              icon: Icons.warning_amber,
            ),
        ],
        const SizedBox(height: 12),
        ?favoriteSaveButton,
        if (onStartGuidance != null) ...[
          const SizedBox(height: 10),
          FilledButton(
            key: const Key('routeStartGuidanceButton'),
            onPressed: onStartGuidance,
            child: const Text('안내 시작'),
          ),
        ],
        if (onOpenFeedback != null) ...[
          const SizedBox(height: 8),
          TextButton(
            key: const Key('routeOpenFeedbackButton'),
            onPressed: onOpenFeedback,
            child: const Text('경로 피드백'),
          ),
        ],
      ],
    );
  }
}

class _RouteGuidanceWorkflowView extends StatelessWidget {
  const _RouteGuidanceWorkflowView({
    required this.result,
    required this.onBack,
    required this.onOpenInternalRoute,
    required this.onOpenBlocked,
    required this.onOpenFeedback,
  });

  final RouteSearchResult result;
  final VoidCallback onBack;
  final VoidCallback onOpenInternalRoute;
  final VoidCallback? onOpenBlocked;
  final VoidCallback? onOpenFeedback;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final steps = result.movementSteps;
    final nextStep = steps.length > 1 ? steps[1] : result.arrivalGuidanceStep;
    final blockedReasonLabels = result.blockedReasonLabels;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RouteWorkflowBackButton(label: '경로 상세', onPressed: onBack),
        const SizedBox(height: 8),
        _RouteSectionHeader(title: '단계별 안내'),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF073245),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: EasySubwayAccessibleColors.mintSoft,
                    border: Border.all(
                      color: EasySubwayAccessibleColors.mintBorder,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: textScale >= 2
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${result.originStationName} → ${result.destinationStationName}',
                                style: textTheme.titleMedium?.copyWith(
                                  color: EasySubwayAccessibleColors.text,
                                  fontWeight: FontWeight.w900,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _routeGuidanceMobilityHeaderLabel(result),
                                key: const Key('routeGuidanceMobilityChip'),
                                style: textTheme.bodySmall?.copyWith(
                                  color: EasySubwayAccessibleColors.mutedText,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${result.originStationName} → ${result.destinationStationName}',
                                      style: textTheme.titleMedium?.copyWith(
                                        color: EasySubwayAccessibleColors.text,
                                        fontWeight: FontWeight.w900,
                                        height: 1.25,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _routeGuidanceMobilityHeaderLabel(result),
                                      key: const Key(
                                        'routeGuidanceMobilityChip',
                                      ),
                                      style: textTheme.bodySmall?.copyWith(
                                        color: EasySubwayAccessibleColors
                                            .mutedText,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 22),
                _RoutePrototypeSection(
                  title: result.isBlocked
                      ? '안내 불가 이유'
                      : _isRecommendedRoute(result)
                      ? '추천 경로'
                      : result.statusLabel,
                  subtitle: result.isBlocked
                      ? '현재 조건에서 막힌 이유를 확인하세요'
                      : _isRecommendedRoute(result)
                      ? '시간·환승·걷기와 편한 정도를 확인하세요.'
                      : '이 경로는 이동 전 확인이 필요합니다',
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: result.isBlocked
                          ? const Color(0xFFEFCCCC)
                          : EasySubwayAccessibleColors.mint,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A0D8A6D),
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (textScale >= 2)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _routeWorkflowSummaryTitle(result),
                                style: textTheme.headlineSmall?.copyWith(
                                  color: EasySubwayAccessibleColors.text,
                                  fontWeight: FontWeight.w900,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _routeWorkflowSummarySubtitle(result),
                                style: textTheme.bodySmall?.copyWith(
                                  color: EasySubwayAccessibleColors.mutedText,
                                  height: 1.4,
                                ),
                              ),
                              Text(
                                result.comfortLabel,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: EasySubwayAccessibleColors.mintDark,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          )
                        else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _routeWorkflowSummaryTitle(result),
                                      style: textTheme.headlineSmall?.copyWith(
                                        color: EasySubwayAccessibleColors.text,
                                        fontWeight: FontWeight.w900,
                                        height: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _routeWorkflowSummarySubtitle(result),
                                      style: textTheme.bodySmall?.copyWith(
                                        color: EasySubwayAccessibleColors
                                            .mutedText,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    result.comfortLabel,
                                    style: textTheme.bodyMedium?.copyWith(
                                      color:
                                          EasySubwayAccessibleColors.mintDark,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        if (_isRecommendedRoute(result) &&
                            result.movementSteps.isNotEmpty) ...[
                          const SizedBox(height: 15),
                          const _RoutePrototypeLinePath(),
                        ],
                        if (blockedReasonLabels.isNotEmpty) ...[
                          const SizedBox(height: 13),
                          for (final reason in blockedReasonLabels)
                            _RoutePrototypeReason(text: reason, blocked: true),
                        ],
                        if (result.arrivalGuidanceStep != null) ...[
                          const SizedBox(height: 16),
                          _RouteArrivalGuidance(
                            step: result.arrivalGuidanceStep!,
                          ),
                        ],
                        if (result.warnings.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          for (final warning in result.warnings)
                            _RouteNotice(
                              title: '주의 확인',
                              text: warning.userMessage,
                              icon: Icons.warning_amber,
                            ),
                        ],
                        if (result.movementSteps.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          _RouteStepSection(steps: result.movementSteps),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (nextStep != null)
          _RouteNotice(
            title: '다음',
            text: nextStep.title,
            icon: Icons.near_me_outlined,
          ),
        if (onOpenBlocked case final openBlocked?)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('routeOpenInternalRouteButton'),
                  onPressed: onOpenInternalRoute,
                  child: const Text('전체 순서'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  key: const Key('routeOpenBlockedButton'),
                  onPressed: openBlocked,
                  child: const Text('길이 막혔어요'),
                ),
              ),
            ],
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const Key('routeOpenInternalRouteButton'),
              onPressed: onOpenInternalRoute,
              child: const Text('전체 순서'),
            ),
          ),
        if (onOpenFeedback != null) ...[
          const SizedBox(height: 8),
          TextButton(
            key: const Key('routeGuidanceFeedbackButton'),
            onPressed: onOpenFeedback,
            child: const Text('안내 피드백'),
          ),
        ],
      ],
    );
  }
}

class _RouteInternalWorkflowView extends StatelessWidget {
  const _RouteInternalWorkflowView({
    required this.result,
    required this.onBack,
  });

  final RouteSearchResult result;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RouteWorkflowBackButton(label: '단계별 안내', onPressed: onBack),
        const SizedBox(height: 8),
        _RouteDarkSummaryCard(
          title:
              '${result.originStationName} → ${result.lineName.isEmpty ? '승강장' : result.lineName}',
          subtitle: _routeMetaLabel(result),
          chips: [
            _RouteSummaryChip(
              label: result.stairAccessLabel,
              icon: _routeStairAccessIcon(result),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _RouteSectionHeader(title: '역 안 이동 순서'),
        const SizedBox(height: 8),
        _RouteStepSection(steps: result.movementSteps),
      ],
    );
  }
}

class _RouteBlockedWorkflow extends StatelessWidget {
  const _RouteBlockedWorkflow({required this.result});

  final RouteSearchResult result;

  @override
  Widget build(BuildContext context) {
    final reasons = result.blockedReasonLabels.isNotEmpty
        ? result.blockedReasonLabels
        : result.warnings.map((warning) => warning.userMessage);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.warning_amber, size: 64, color: Color(0xFFA93434)),
        const SizedBox(height: 10),
        Text(
          '계단 없는 경로가 없습니다',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: const Color(0xFF102A2C),
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        for (final reason in reasons)
          _RoutePrototypeReason(text: reason, blocked: true),
        const SizedBox(height: 12),
        const _RouteNotice(
          key: Key('routeBlockedNextActionNotice'),
          title: '다른 방법',
          text: _routeSearchFailureNextAction,
          icon: Icons.refresh,
          semanticsLabel: '다음 행동, $_routeSearchFailureNextAction',
        ),
        const _RouteNotice(
          title: '안전 안내',
          text: _routeSafetyGuidanceNotice,
          icon: Icons.shield_outlined,
        ),
      ],
    );
  }
}

class _RouteFeedbackWorkflowView extends StatelessWidget {
  const _RouteFeedbackWorkflowView({
    required this.result,
    required this.repository,
    required this.onBack,
  });

  final RouteSearchResult result;
  final RouteFeedbackRepository? repository;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final feedbackRepository = repository;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RouteWorkflowBackButton(label: '경로 상세', onPressed: onBack),
        const SizedBox(height: 8),
        Text(
          '방금 안내가\n실제 이동에 도움이 됐나요?',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: const Color(0xFF102A2C),
            fontWeight: FontWeight.w900,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 14),
        if (feedbackRepository == null)
          const _RouteNotice(
            title: '피드백 준비 중',
            text: '잠시 후 다시 시도해 주세요.',
            icon: Icons.info_outline,
          )
        else
          _RouteFeedbackButtons(result: result, repository: feedbackRepository),
      ],
    );
  }
}

class _RouteResultListButton extends StatelessWidget {
  const _RouteResultListButton({required this.result, required this.onPressed});

  final RouteSearchResult result;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final totalMinutes = _routeTotalMinutes(result);
    return Semantics(
      button: true,
      label:
          '${result.summaryTitle}, ${_routeMetaLabel(result)}, ${result.comfortLabel}, ${result.stairAccessLabel}',
      onTap: onPressed,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const Key('routeResultListItem'),
            onTap: onPressed,
            borderRadius: BorderRadius.circular(8),
            child: Ink(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFF0D8A6D), width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            totalMinutes > 0 ? '$totalMinutes분' : '시간 확인',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: const Color(0xFF102A2C),
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(_routeMetaLabel(result)),
                    const SizedBox(height: 12),
                    const _RoutePrototypeLinePath(),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _RoutePrototypeChip(
                          label: _routeTransferLabel(result),
                          icon: Icons.route_outlined,
                        ),
                        _RoutePrototypeChip(
                          label: '걷기 ${_routeWalkingDistanceLabel(result)}',
                          icon: Icons.directions_walk,
                        ),
                        _RoutePrototypeChip(
                          key: const Key('routeGuidanceMobilityChip'),
                          label: result.mobilityLabel == '이동 조건 확인 필요'
                              ? result.mobilityLabel
                              : result.comfortLabel,
                          icon: Icons.accessible_forward,
                        ),
                        _RoutePrototypeChip(
                          label: result.stairAccessLabel,
                          icon: _routeStairAccessIcon(result),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteDarkSummaryCard extends StatelessWidget {
  const _RouteDarkSummaryCard({
    required this.title,
    required this.subtitle,
    required this.chips,
  });

  final String title;
  final String subtitle;
  final List<_RouteSummaryChip> chips;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF073245),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Color(0xFFC7D8E3))),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final chip in chips)
                  _RoutePrototypeChip(
                    key: Key('routeDarkSummaryChip-${chip.label}'),
                    label: chip.label,
                    icon: chip.icon,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteWorkflowBackButton extends StatelessWidget {
  const _RouteWorkflowBackButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_back),
        label: Text(label),
      ),
    );
  }
}

int _routeTotalMinutes(RouteSearchResult result) {
  return result.steps.fold<int>(0, (sum, step) => sum + step.estimatedMinutes);
}

String _routeTransferLabel(RouteSearchResult result) {
  final transfers = result.transferCount;
  return transfers == 0 ? '환승 없음' : '환승 $transfers회';
}

String _routeWalkingDistanceLabel(RouteSearchResult result) {
  return _routeDistanceLabel(result.walkingDistanceMeters);
}

String _routeMetaLabel(RouteSearchResult result) {
  return '${_routeTransferLabel(result)} · 걷기 ${_routeWalkingDistanceLabel(result)}';
}

String _routeGuidanceMobilityHeaderLabel(RouteSearchResult result) {
  final mobilityLabel = result.mobilityLabel;
  if (mobilityLabel == '이동 조건 확인 필요') {
    return mobilityLabel;
  }
  final condition = _routeMobilityConditionLabel(
    _mobilityOptionFor(result.mobilityType),
  );
  return condition.isEmpty ? mobilityLabel : '$mobilityLabel · $condition';
}

bool _isRecommendedRoute(RouteSearchResult result) {
  return result.status == 'FOUND' && !result.isBlocked;
}

String _routeWorkflowSummaryTitle(RouteSearchResult result) {
  final totalMinutes = _routeTotalMinutes(result);
  // route contract: realtime ETA fallback
  if (_isRecommendedRoute(result) && totalMinutes > 0) {
    return '$totalMinutes분';
  }
  return result.isBlocked ? result.guidanceLabel : result.statusLabel;
}

String _routeWorkflowSummarySubtitle(RouteSearchResult result) {
  return _isRecommendedRoute(result)
      ? _routeMetaLabel(result)
      : result.statusLabel;
}

IconData _routeStairAccessIcon(RouteSearchResult result) {
  return switch (result.stairAccessLabel) {
    '계단 없음 확인' => Icons.check,
    '계단 포함' => Icons.stairs_outlined,
    _ => Icons.help_outline,
  };
}

String _routeStepStairAccessStateFromJson(
  Map<String, Object?> json,
  bool includesStairs,
) {
  final raw = _optionalRouteString(json, 'stairAccessState');
  if (raw.isEmpty) {
    return includesStairs ? 'stairOnly' : 'unknown';
  }
  return _normalizeRouteStairState(raw);
}

String _routeStepStairState(RouteSearchStep step) {
  if (step.includesStairs) {
    return 'stairOnly';
  }
  return _normalizeRouteStairState(step.stairAccessState);
}

String _normalizeRouteStairState(String value) {
  return switch (value.trim().toUpperCase()) {
    'STEP_FREE' || 'STEPFREE' => 'stepFree',
    'STAIR_ONLY' || 'STAIRONLY' => 'stairOnly',
    _ => 'unknown',
  };
}

class _RoutePrototypeSection extends StatelessWidget {
  const _RoutePrototypeSection({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(1, 0, 1, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: EasySubwayAccessibleColors.text,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: EasySubwayAccessibleColors.mutedText,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutePrototypeChip extends StatelessWidget {
  const _RoutePrototypeChip({
    super.key,
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFDEF5E7),
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Wrap(
        spacing: 5,
        runSpacing: 3,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(icon, size: 13, color: EasySubwayAccessibleColors.mintDark),
          Text(
            label,
            style: const TextStyle(
              color: EasySubwayAccessibleColors.mintDark,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteSummaryChip {
  const _RouteSummaryChip({required this.label, this.icon = Icons.check});

  final String label;
  final IconData icon;
}

class _RoutePrototypeLinePath extends StatelessWidget {
  const _RoutePrototypeLinePath();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoutePrototypeNode(),
        Expanded(child: Container(height: 6, color: const Color(0xFF27A6D9))),
        _RoutePrototypeNode(),
      ],
    );
  }
}

class _RoutePrototypeNode extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: const Color(0xFF27A6D9),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Color(0xFF27A6D9), spreadRadius: 2)],
      ),
    );
  }
}

class _RoutePrototypeReason extends StatelessWidget {
  const _RoutePrototypeReason({required this.text, this.blocked = false});

  final String text;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          CircleAvatar(
            radius: 9,
            backgroundColor: blocked
                ? const Color(0xFFFFE7E7)
                : EasySubwayAccessibleColors.mintSoft,
            child: Text(
              blocked ? '!' : '✓',
              style: TextStyle(
                color: blocked
                    ? const Color(0xFFA93434)
                    : EasySubwayAccessibleColors.mintDark,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: EasySubwayAccessibleColors.mutedText,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteArrivalGuidance extends StatelessWidget {
  const _RouteArrivalGuidance({required this.step});

  final RouteSearchStep step;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE6F2F0),
        border: Border.all(color: const Color(0xFF9FCACE)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.exit_to_app, color: Color(0xFF004A50), size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '도착 안내',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF004A50),
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    step.userDescription,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF102A2C),
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteNotice extends StatelessWidget {
  const _RouteNotice({
    super.key,
    required this.title,
    required this.text,
    required this.icon,
    this.semanticsLabel,
  });

  final String title;
  final String text;
  final IconData icon;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final notice = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7E0),
          border: Border.all(color: const Color(0xFFE6C875)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: const Color(0xFF7A4F00), size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF3C2F00),
                        fontWeight: FontWeight.w900,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      text,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF3C2F00),
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final label = semanticsLabel;
    if (label == null) {
      return notice;
    }
    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(child: notice),
    );
  }
}

class _RouteStepSection extends StatelessWidget {
  const _RouteStepSection({required this.steps});

  final List<RouteSearchStep> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '이동 순서',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: const Color(0xFF102A2C),
            fontWeight: FontWeight.w900,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 12),
        for (final step in steps) _RouteStepTile(step: step),
      ],
    );
  }
}

class _RouteStepTile extends StatelessWidget {
  const _RouteStepTile({required this.step});

  final RouteSearchStep step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            key: Key('routeStepNumber-${step.sequence}'),
            radius: 22,
            backgroundColor: const Color(0xFF006D77),
            child: Text(
              '${step.sequence}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (step.actionTitle.isNotEmpty) ...[
                  Text(
                    step.actionTitle,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF004A50),
                      fontWeight: FontWeight.w900,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  step.title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF102A2C),
                    fontWeight: FontWeight.w900,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  step.burdenLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF29484B),
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  step.userDescription,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF405A5D),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                if (step.userReason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    step.userReason,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF405A5D),
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteFeedbackButtons extends StatefulWidget {
  const _RouteFeedbackButtons({required this.result, required this.repository});

  final RouteSearchResult result;
  final RouteFeedbackRepository repository;

  @override
  State<_RouteFeedbackButtons> createState() => _RouteFeedbackButtonsState();
}

class _RouteFeedbackButtonsState extends State<_RouteFeedbackButtons> {
  bool _submitting = false;
  bool _submitted = false;
  String _message = '';
  bool _isFailure = false;

  @override
  void didUpdateWidget(_RouteFeedbackButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result.routeSearchId != widget.result.routeSearchId) {
      _submitting = false;
      _submitted = false;
      _message = '';
      _isFailure = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final shouldShowNextAction = _isFailure && _message.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('routeFeedbackHelpfulButton'),
                onPressed: _canSubmit
                    ? () => _submit(RouteFeedbackRating.helpful, '추천이 도움이 됐어요')
                    : null,
                icon: const Icon(Icons.thumb_up_alt_outlined),
                label: Text(_submitting ? '보내는 중' : '도움 됐어요'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('routeFeedbackNotHelpfulButton'),
                onPressed: _canSubmit
                    ? () => _submit(
                        RouteFeedbackRating.notHelpful,
                        '경로가 실제 이동과 맞지 않아요',
                      )
                    : null,
                icon: const Icon(Icons.report_problem_outlined),
                label: const Text('맞지 않아요'),
              ),
            ),
          ],
        ),
        if (_message.isNotEmpty) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              _message,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF29484B),
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ),
        ],
        if (shouldShowNextAction) ...[
          const SizedBox(height: 6),
          Semantics(
            key: const Key('routeFeedbackFailureNextAction'),
            container: true,
            excludeSemantics: true,
            liveRegion: true,
            label: '다음 행동, $_routeFeedbackFailureNextAction',
            child: Text(
              _routeFeedbackFailureNextAction,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF506B6F),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ],
    );
  }

  bool get _canSubmit => !_submitting && !_submitted;

  Future<void> _submit(RouteFeedbackRating rating, String comment) async {
    setState(() {
      _submitting = true;
      _message = '';
      _isFailure = false;
    });

    try {
      await widget.repository.submitRouteFeedback(
        RouteFeedbackRequest(
          routeSearchId: widget.result.routeSearchId,
          rating: rating,
          comment: comment,
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _submitted = true;
        _message = '의견을 보냈습니다.';
        _isFailure = false;
      });
    } on RouteFeedbackException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _message = error.message;
        _isFailure = true;
      });
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '경로 피드백 화면 처리 중 예외가 발생했습니다.',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _message = _routeFeedbackErrorMessage;
        _isFailure = true;
      });
    }
  }
}

class _RouteFavoriteSaveButton extends StatefulWidget {
  const _RouteFavoriteSaveButton({
    required this.result,
    required this.repository,
  });

  final RouteSearchResult result;
  final FavoriteRouteRepository repository;

  @override
  State<_RouteFavoriteSaveButton> createState() =>
      _RouteFavoriteSaveButtonState();
}

class _RouteFavoriteSaveButtonState extends State<_RouteFavoriteSaveButton> {
  bool _saving = false;
  String _message = '';
  bool _isFailure = false;

  @override
  void didUpdateWidget(_RouteFavoriteSaveButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result.routeSearchId != widget.result.routeSearchId) {
      _saving = false;
      _message = '';
      _isFailure = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final shouldShowNextAction = _isFailure && _message.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const Key('routeFavoriteSaveButton'),
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.bookmark_add_outlined),
          label: Text(_saving ? '저장 중' : '자주 쓰는 경로 저장'),
        ),
        if (_message.isNotEmpty) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              _message,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF29484B),
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ),
        ],
        if (shouldShowNextAction) ...[
          const SizedBox(height: 6),
          Semantics(
            key: const Key('favoriteRouteSaveFailureNextAction'),
            container: true,
            excludeSemantics: true,
            liveRegion: true,
            label: '다음 행동, $_favoriteRouteSaveFailureNextAction',
            child: Text(
              _favoriteRouteSaveFailureNextAction,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF506B6F),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _message = '';
      _isFailure = false;
    });

    try {
      await widget.repository.saveFavoriteRoute(
        widget.result.routeSearchId,
        result: widget.result,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _message = '자주 쓰는 경로에 저장했습니다.';
        _isFailure = false;
      });
    } on FavoriteRouteException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _message = error.message;
        _isFailure = true;
      });
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '경로 즐겨찾기 저장 화면 처리 중 예외가 발생했습니다.',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _message = _favoriteRouteErrorMessage;
        _isFailure = true;
      });
    }
  }
}

enum FavoriteRouteListStatus { loading, success, empty, failure }

class FavoriteRouteListState {
  const FavoriteRouteListState({
    required this.status,
    required this.favorites,
    this.message = '',
    this.removingIds = const {},
  });

  const FavoriteRouteListState.loading()
    : status = FavoriteRouteListStatus.loading,
      favorites = const [],
      message = '',
      removingIds = const {};

  final FavoriteRouteListStatus status;
  final List<FavoriteRoute> favorites;
  final String message;
  final Set<String> removingIds;

  FavoriteRouteListState copyWith({
    FavoriteRouteListStatus? status,
    List<FavoriteRoute>? favorites,
    String? message,
    Set<String>? removingIds,
  }) {
    return FavoriteRouteListState(
      status: status ?? this.status,
      favorites: favorites ?? this.favorites,
      message: message ?? this.message,
      removingIds: removingIds ?? this.removingIds,
    );
  }
}

class FavoriteRouteListController extends ChangeNotifier {
  FavoriteRouteListController({required this.repository});

  final FavoriteRouteRepository repository;
  FavoriteRouteListState _state = const FavoriteRouteListState.loading();
  bool _disposed = false;

  FavoriteRouteListState get state => _state;

  Future<void> load() async {
    _emitState(const FavoriteRouteListState.loading());
    try {
      final favorites = await repository.listFavoriteRoutes();
      if (_disposed) {
        return;
      }
      _emitState(
        favorites.isEmpty
            ? const FavoriteRouteListState(
                status: FavoriteRouteListStatus.empty,
                favorites: [],
                message: '즐겨찾기한 경로가 없습니다.',
              )
            : FavoriteRouteListState(
                status: FavoriteRouteListStatus.success,
                favorites: favorites,
              ),
      );
    } on FavoriteRouteException catch (error) {
      _emitFailure(error.message);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '즐겨찾기 경로 목록 화면 처리 중 예외가 발생했습니다.',
      );
      _emitFailure(_favoriteRouteLoadErrorMessage);
    }
  }

  Future<void> remove(FavoriteRoute favorite) async {
    final favoriteRouteId = favorite.favoriteRouteId;
    if (_state.removingIds.contains(favoriteRouteId)) {
      return;
    }

    _emitState(
      _state.copyWith(removingIds: {..._state.removingIds, favoriteRouteId}),
    );

    try {
      await repository.removeFavoriteRoute(favoriteRouteId);
      if (_disposed) {
        return;
      }
      final nextFavorites = _state.favorites
          .where((item) => item.favoriteRouteId != favoriteRouteId)
          .toList(growable: false);
      final nextRemovingIds = {..._state.removingIds}..remove(favoriteRouteId);
      _emitState(
        nextFavorites.isEmpty
            ? FavoriteRouteListState(
                status: FavoriteRouteListStatus.empty,
                favorites: const [],
                message: '즐겨찾기한 경로가 없습니다.',
                removingIds: nextRemovingIds,
              )
            : FavoriteRouteListState(
                status: FavoriteRouteListStatus.success,
                favorites: nextFavorites,
                removingIds: nextRemovingIds,
              ),
      );
    } on FavoriteRouteException catch (error) {
      _emitFailure(error.message, removingIdToClear: favoriteRouteId);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '즐겨찾기 경로 삭제 처리 중 예외가 발생했습니다.',
      );
      _emitFailure(
        _favoriteRouteErrorMessage,
        removingIdToClear: favoriteRouteId,
      );
    }
  }

  void _emitFailure(String message, {String? removingIdToClear}) {
    final nextRemovingIds = {..._state.removingIds};
    if (removingIdToClear != null) {
      nextRemovingIds.remove(removingIdToClear);
    }
    _emitState(
      FavoriteRouteListState(
        status: FavoriteRouteListStatus.failure,
        favorites: _state.favorites,
        message: message,
        removingIds: nextRemovingIds,
      ),
    );
  }

  void _emitState(FavoriteRouteListState nextState) {
    if (_disposed) {
      return;
    }
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class FavoriteRouteListScreen extends StatefulWidget {
  const FavoriteRouteListScreen({
    required this.repository,
    this.onSearchAgain,
    super.key,
  });

  final FavoriteRouteRepository repository;
  final ValueChanged<FavoriteRoute>? onSearchAgain;

  @override
  State<FavoriteRouteListScreen> createState() =>
      _FavoriteRouteListScreenState();
}

class _FavoriteRouteListScreenState extends State<FavoriteRouteListScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('즐겨찾기 경로')),
      body: FavoriteRouteListContent(
        repository: widget.repository,
        onSearchAgain: widget.onSearchAgain,
      ),
    );
  }
}

class FavoriteRouteListContent extends StatefulWidget {
  const FavoriteRouteListContent({
    required this.repository,
    this.onSearchAgain,
    super.key,
  });

  final FavoriteRouteRepository repository;
  final ValueChanged<FavoriteRoute>? onSearchAgain;

  @override
  State<FavoriteRouteListContent> createState() =>
      _FavoriteRouteListContentState();
}

class _FavoriteRouteListContentState extends State<FavoriteRouteListContent> {
  late final FavoriteRouteListController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FavoriteRouteListController(repository: widget.repository);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => _FavoriteRouteListBody(
          state: _controller.state,
          onRetry: _controller.load,
          onRemove: _controller.remove,
          onSearchAgain: widget.onSearchAgain,
        ),
      ),
    );
  }
}

class _FavoriteRouteListBody extends StatelessWidget {
  const _FavoriteRouteListBody({
    required this.state,
    required this.onRetry,
    required this.onRemove,
    required this.onSearchAgain,
  });

  final FavoriteRouteListState state;
  final VoidCallback onRetry;
  final ValueChanged<FavoriteRoute> onRemove;
  final ValueChanged<FavoriteRoute>? onSearchAgain;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        switch (state.status) {
          FavoriteRouteListStatus.loading => Semantics(
            label: '즐겨찾기 경로 불러오는 중',
            liveRegion: true,
            child: const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(),
              ),
            ),
          ),
          FavoriteRouteListStatus.empty => _RouteSearchMessage(
            message: state.message,
            liveRegion: true,
          ),
          FavoriteRouteListStatus.failure => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RouteSearchMessage(message: state.message, liveRegion: true),
              const SizedBox(height: 6),
              Semantics(
                key: const Key('favoriteRouteLoadFailureNextAction'),
                container: true,
                excludeSemantics: true,
                liveRegion: true,
                label: '다음 행동, $_favoriteRouteLoadFailureNextAction',
                child: Text(
                  _favoriteRouteLoadFailureNextAction,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF506B6F),
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('favoriteRoutesRetryButton'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('다시 불러오기'),
              ),
            ],
          ),
          FavoriteRouteListStatus.success => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label: '즐겨찾기 경로 ${state.favorites.length}개',
                liveRegion: true,
                child: const SizedBox.shrink(),
              ),
              for (final favorite in state.favorites)
                _FavoriteRouteTile(
                  favorite: favorite,
                  isRemoving: state.removingIds.contains(
                    favorite.favoriteRouteId,
                  ),
                  onRemove: onRemove,
                  onSearchAgain: onSearchAgain,
                ),
            ],
          ),
        },
      ],
    );
  }
}

class _FavoriteRouteTile extends StatelessWidget {
  const _FavoriteRouteTile({
    required this.favorite,
    required this.isRemoving,
    required this.onRemove,
    required this.onSearchAgain,
  });

  final FavoriteRoute favorite;
  final bool isRemoving;
  final ValueChanged<FavoriteRoute> onRemove;
  final ValueChanged<FavoriteRoute>? onSearchAgain;

  @override
  Widget build(BuildContext context) {
    final menuButtonKey =
        GlobalKey<PopupMenuButtonState<_FavoriteRouteMenuAction>>();
    final moreSemanticLabel =
        '${favorite.summaryTitle} 더 보기${isRemoving ? ', 삭제 중' : ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FavoriteRouteSummaryCard(favorite: favorite),
        Row(
          children: [
            if (onSearchAgain != null) ...[
              Expanded(
                child: OutlinedButton.icon(
                  key: Key(
                    'favoriteRouteSearchAgain-${favorite.favoriteRouteId}',
                  ),
                  onPressed: isRemoving ? null : () => onSearchAgain!(favorite),
                  icon: const Icon(Icons.search),
                  label: const Text('최신 경로 다시 찾기'),
                ),
              ),
              const SizedBox(width: 8),
            ] else
              const Spacer(),
            if (isRemoving) ...[
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                '삭제 중',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF405A5D),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Semantics(
              key: Key('favoriteRouteMore-${favorite.favoriteRouteId}'),
              container: true,
              label: moreSemanticLabel,
              button: true,
              enabled: !isRemoving,
              onTap: isRemoving
                  ? null
                  : () => menuButtonKey.currentState?.showButtonMenu(),
              child: ExcludeSemantics(
                child: PopupMenuButton<_FavoriteRouteMenuAction>(
                  key: menuButtonKey,
                  enabled: !isRemoving,
                  tooltip: '경로 더 보기',
                  onSelected: (action) {
                    switch (action) {
                      case _FavoriteRouteMenuAction.remove:
                        unawaited(_confirmRemove(context));
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<_FavoriteRouteMenuAction>(
                      key: Key(
                        'favoriteRouteRemove-${favorite.favoriteRouteId}',
                      ),
                      value: _FavoriteRouteMenuAction.remove,
                      child: const Text('삭제'),
                    ),
                  ],
                  icon: const Icon(Icons.more_vert),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('즐겨찾기 경로 삭제'),
          content: Text('${favorite.summaryTitle} 경로를 즐겨찾기에서 삭제할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              key: Key(
                'favoriteRouteRemoveConfirm-${favorite.favoriteRouteId}',
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );
    if (confirmed == true && context.mounted) {
      onRemove(favorite);
    }
  }
}

enum _FavoriteRouteMenuAction { remove }

class _FavoriteRouteSummaryCard extends StatelessWidget {
  const _FavoriteRouteSummaryCard({required this.favorite});

  final FavoriteRoute favorite;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return MergeSemantics(
      child: Semantics(
        label: favorite.semanticLabel,
        child: ExcludeSemantics(
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFD5E2E4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    favorite.summaryTitle,
                    style: textTheme.titleLarge?.copyWith(
                      color: const Color(0xFF102A2C),
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    favorite.lineLabel,
                    style: textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF29484B),
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    favorite.mobilityLabel,
                    style: textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF29484B),
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    favorite.scoreLabel,
                    style: textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF29484B),
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    favorite.scoreBasisText,
                    style: textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF405A5D),
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    favorite.movementMetricLabel,
                    style: textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF405A5D),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    favorite.accessibilityMetricLabel,
                    style: textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF405A5D),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _requiredRouteString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('Missing required route field: $key');
}

String _optionalRouteString(
  Map<String, Object?> json,
  String key, {
  String fallback = '',
}) {
  final value = json[key];
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }
  return fallback;
}

List<String> _routeStringList(Object? value, String label) {
  if (value == null) {
    return const [];
  }
  if (value is! List<Object?>) {
    throw FormatException('Invalid $label payload');
  }
  return value
      .map((item) {
        if (item is! String || item.trim().isEmpty) {
          throw FormatException('Invalid $label payload');
        }
        return item.trim();
      })
      .toList(growable: false);
}

int _requiredRouteInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  throw FormatException('Missing required route field: $key');
}

int? _optionalRouteInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  return null;
}

bool _requiredRouteBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('Missing required route field: $key');
}
