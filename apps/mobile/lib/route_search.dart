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
const _routeSearchErrorMessage = '경로 정보를 불러오지 못했어요.';
const _routeRefreshErrorMessage = '도착 시간을 새로 확인하지 못했어요.';
const _routeFeedbackErrorMessage = '의견을 보내지 못했어요.';
const _favoriteRouteErrorMessage = '즐겨찾기 경로를 바꾸지 못했어요.';
const _favoriteRouteLoadErrorMessage = '즐겨찾기 경로를 불러오지 못했어요.';
const _routeSafetyGuidanceNotice = '이동 전 현장 안내와 역무원 안내를 확인해 주세요.';
const _routeSearchFailureNextAction = '역을 다시 선택하거나 이동 조건을 바꾼 뒤 경로를 다시 찾아보세요.';
const _routeBlockedConfirmationNotice = '역무원이나 현장 안내를 확인한 뒤 이동해 주세요.';
const _routeFeedbackFailureNextAction = '잠시 후 다시 보내거나 경로 조건을 바꿔 다시 찾아보세요.';
const _favoriteRouteSaveFailureNextAction =
    '네트워크 상태를 확인한 뒤 자주 쓰는 경로 저장을 다시 눌러 주세요.';
const _favoriteRouteLoadFailureNextAction = '네트워크 상태를 확인한 뒤 다시 불러와 주세요.';
const _routeSearchPagePadding = EdgeInsets.only(
  left: 20,
  top: 20,
  right: 20,
  bottom: 32,
);
const _routeSearchSmallRadius = BorderRadius.all(Radius.circular(8));
const _routeSearchMediumRadius = BorderRadius.all(Radius.circular(14));
const _routeSearchLargeRadius = BorderRadius.all(Radius.circular(20));
const _routeSearchPillRadius = BorderRadius.all(Radius.circular(999));
const _routeTextPrimaryColor = Color(0xFF102A2C);
const _routeTextSecondaryColor = Color(0xFF29484B);
const _routeTextMutedColor = Color(0xFF405A5D);
const _routeTextSubtleColor = Color(0xFF50656F);
const _routeNextActionTextColor = Color(0xFF506B6F);
const _routeAccentColor = Color(0xFF006D77);
const _routeCardBorderColor = Color(0xFFD5E2E4);
const _routeDividerColor = Color(0xFFE0E7EC);
const _routeControlBorderColor = Color(0xFF9DB6BA);
const _routeSoftPanelColor = Color(0xFFE9F5F6);
const _routeSoftPanelBorderColor = Color(0xFFB9D4D8);
const _routeGuidanceDarkColor = Color(0xFF073245);
const _routeGuidanceSecondaryColor = Color(0xFFC7D8E3);
const _routeBlockedBorderColor = Color(0xFFEFCCCC);
const _routeCardShadowColor = Color(0x0F071B2F);
const _routeAccentShadowColor = Color(0x1A0D8A6D);
const _routeResultBorderColor = Color(0xFF0D8A6D);
const _routeStatusChipBackgroundColor = Color(0xFFDEF5E7);
const _routeTimelineColor = Color(0xFF27A6D9);
const _routeBlockedColor = Color(0xFFA93434);
const _routeBlockedSoftColor = Color(0xFFFFE7E7);
const _routeArrivalPanelColor = Color(0xFFE6F2F0);
const _routeArrivalBorderColor = Color(0xFF9FCACE);
const _routeArrivalTextColor = Color(0xFF004A50);
const _routeNoticePanelColor = Color(0xFFFFF7E0);
const _routeNoticeBorderColor = Color(0xFFE6C875);
const _routeNoticeIconColor = Color(0xFF7A4F00);
const _routeNoticeTextColor = Color(0xFF3C2F00);
const _routeMobilitySheetHeaderPadding = EdgeInsets.fromLTRB(20, 8, 20, 0);
const _routeMobilitySheetListPadding = EdgeInsets.fromLTRB(20, 0, 20, 8);
const _routeMobilitySheetActionPadding = EdgeInsets.fromLTRB(20, 8, 20, 20);
const _routePointSelectorPadding = EdgeInsets.fromLTRB(8, 8, 58, 8);
const _routeResultSectionPadding = EdgeInsets.fromLTRB(1, 0, 1, 11);

String _mobilityLabelFor(String mobilityType) {
  for (final option in mobilityProfileOptions) {
    if (option.mobilityType == mobilityType) {
      return option.title;
    }
  }
  return '이동 조건을 다시 선택해 주세요';
}

String _routeDateLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.length >= 10) {
    return '최근 확인 ${trimmed.substring(0, 10)}';
  }
  return '최근 확인일을 아직 알 수 없어요';
}

abstract class RouteSearchRepository {
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request);

  Future<RouteRefreshResult> refreshRoute(String routeSearchId);
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

  @override
  Future<RouteRefreshResult> refreshRoute(String routeSearchId) async {
    final trimmedRouteSearchId = routeSearchId.trim();
    if (trimmedRouteSearchId.isEmpty) {
      throw const RouteSearchException(_routeRefreshErrorMessage);
    }

    try {
      final response = await _apiClient.postJson(
        '/api/v2/routes/${Uri.encodeComponent(trimmedRouteSearchId)}/refresh',
        body: const <String, Object?>{},
      );

      if (!response.isOk) {
        throw const RouteSearchException(_routeRefreshErrorMessage);
      }

      final decoded = response.jsonBody;
      if (decoded is! Map<String, Object?> || decoded['success'] != true) {
        throw const RouteSearchException(_routeRefreshErrorMessage);
      }

      final data = decoded['data'];
      if (data is! Map<String, Object?>) {
        throw const RouteSearchException(_routeRefreshErrorMessage);
      }

      return RouteRefreshResult.fromJson(data);
    } on RouteSearchException {
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '경로 ETA refresh API 응답 처리 중 예외가 발생했습니다.',
      );
      throw const RouteSearchException(_routeRefreshErrorMessage);
    }
  }
}

class RouteSearchV2ApiRepository implements RouteSearchRepository {
  RouteSearchV2ApiRepository({
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
        '/api/v2/routes/search',
        body: routeRequest.toV2Json(),
      );
      if (!response.isSuccess) {
        throw RouteSearchOnlineException.http(response.statusCode);
      }
      final decoded = response.jsonBody;
      if (decoded is! Map<String, Object?> || decoded['success'] != true) {
        throw const RouteSearchOnlineException.unavailable();
      }
      final data = decoded['data'];
      if (data is! Map<String, Object?>) {
        throw const RouteSearchOnlineException.unavailable();
      }
      return RouteSearchResult.fromV2(RouteSearchV2Result.fromJson(data));
    } on RouteSearchOnlineException {
      rethrow;
    } on ApiException catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '경로 V2 API 요청 처리 중 예외가 발생했습니다.',
      );
      throw const RouteSearchOnlineException.unavailable(
        fallbackReason: 'network-unavailable',
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '경로 V2 API 응답 처리 중 예외가 발생했습니다.',
      );
      throw const RouteSearchOnlineException.unavailable();
    }
  }

  @override
  Future<RouteRefreshResult> refreshRoute(String routeSearchId) async {
    final trimmedRouteSearchId = routeSearchId.trim();
    if (trimmedRouteSearchId.isEmpty) {
      throw const RouteSearchException(_routeRefreshErrorMessage);
    }

    try {
      final response = await _apiClient.postJson(
        '/api/v2/routes/${Uri.encodeComponent(trimmedRouteSearchId)}/refresh',
        body: const <String, Object?>{},
      );
      if (!response.isSuccess) {
        throw const RouteSearchException(_routeRefreshErrorMessage);
      }
      final decoded = response.jsonBody;
      if (decoded is! Map<String, Object?> || decoded['success'] != true) {
        throw const RouteSearchException(_routeRefreshErrorMessage);
      }
      final data = decoded['data'];
      if (data is! Map<String, Object?>) {
        throw const RouteSearchException(_routeRefreshErrorMessage);
      }
      return RouteRefreshResult.fromJson(data);
    } on RouteSearchException {
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '경로 V2 ETA refresh API 응답 처리 중 예외가 발생했습니다.',
      );
      throw const RouteSearchException(_routeRefreshErrorMessage);
    }
  }
}

class RouteSearchOnlineException extends RouteSearchException {
  const RouteSearchOnlineException.unavailable({
    this.statusCode,
    this.fallbackReason = 'online-unavailable',
  }) : fallbackAllowed = true,
       super(_routeSearchErrorMessage);

  factory RouteSearchOnlineException.http(int statusCode) {
    final validationFailure =
        statusCode == HttpStatus.badRequest ||
        statusCode == HttpStatus.unprocessableEntity;
    return RouteSearchOnlineException._(
      statusCode: statusCode,
      fallbackAllowed: !validationFailure,
      fallbackReason: statusCode >= 500 ? 'backend-5xx' : 'backend-4xx',
    );
  }

  const RouteSearchOnlineException._({
    required this.statusCode,
    required this.fallbackAllowed,
    required this.fallbackReason,
  }) : super(_routeSearchErrorMessage);

  final int? statusCode;
  final bool fallbackAllowed;
  final String fallbackReason;
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

  String get lineLabel => lineName.isEmpty ? '노선을 아직 알 수 없어요' : lineName;

  String get scoreLabel => '다시 찾으면 자세히 볼 수 있어요';

  String get mobilityLabel => _mobilityLabelFor(mobilityType);

  String get scoreBasisText =>
      '$mobilityLabel 조건 · $lineLabel · ${_routeDateLabel(routeCreatedAt)}';

  String get scoreBasisSemanticLabel =>
      '$mobilityLabel 조건, $lineLabel, ${_routeDateLabel(routeCreatedAt)}';

  String get movementMetricLabel =>
      '예상 시간을 확인하고 있어요 · 환승 안내를 확인하고 있어요 · 걷는 거리를 확인하고 있어요';

  String get accessibilityMetricLabel =>
      '계단 여부를 아직 알 수 없어요 · 엘리베이터 연결을 아직 알 수 없어요';

  String get semanticLabel {
    return [
      '즐겨찾기 경로',
      summaryTitle,
      lineLabel,
      mobilityLabel,
      scoreLabel,
      scoreBasisSemanticLabel,
      '예상 시간을 확인하고 있어요',
      '환승 안내를 확인하고 있어요',
      '걷는 거리를 확인하고 있어요',
      '계단 여부를 아직 알 수 없어요',
      '엘리베이터 연결을 아직 알 수 없어요',
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
    this.constraintMode,
  });

  final String originStationId;
  final String destinationStationId;
  final String mobilityType;
  final String? constraintMode;

  String get effectiveConstraintMode =>
      constraintMode ?? _defaultConstraintMode(mobilityType);

  RouteSearchRequest trimmed() {
    return RouteSearchRequest(
      originStationId: originStationId.trim(),
      destinationStationId: destinationStationId.trim(),
      mobilityType: mobilityType,
      constraintMode: constraintMode?.trim(),
    );
  }

  Map<String, Object?> toJson() {
    final trimmedRequest = trimmed();
    return {
      'originStationId': trimmedRequest.originStationId,
      'destinationStationId': trimmedRequest.destinationStationId,
      'mobilityType': trimmedRequest.mobilityType,
      'constraintMode': trimmedRequest.effectiveConstraintMode,
    };
  }

  Map<String, Object?> toV2Json() {
    return {
      ...toJson(),
      'departureTime': _routeV2DepartureTimeNow(),
      'useRealtime': true,
      'maxTransfers': 3,
      'alternativeCount': 3,
    };
  }

  static String _defaultConstraintMode(String mobilityType) =>
      mobilityType == 'WHEELCHAIR' ? 'STRICT_STEP_FREE' : 'PREFER_STEP_FREE';
}

class RouteSearchV2Result {
  const RouteSearchV2Result({
    required this.contractVersion,
    required this.originStationId,
    required this.destinationStationId,
    required this.departureTime,
    required this.mobilityType,
    required this.constraintMode,
    required this.useRealtime,
    required this.maxTransfers,
    required this.alternativeCount,
    required this.statuses,
    required this.itineraries,
  });

  factory RouteSearchV2Result.fromJson(Map<String, Object?> json) {
    final rawItineraries = json['itineraries'];
    if (rawItineraries is! List<Object?>) {
      throw const FormatException('Invalid route v2 itinerary payload');
    }
    return RouteSearchV2Result(
      contractVersion: _requiredRouteString(json, 'contractVersion'),
      originStationId: _requiredRouteString(json, 'originStationId'),
      destinationStationId: _requiredRouteString(json, 'destinationStationId'),
      departureTime: _requiredRouteString(json, 'departureTime'),
      mobilityType: _requiredRouteString(json, 'mobilityType'),
      constraintMode: _requiredRouteString(json, 'constraintMode'),
      useRealtime: _requiredRouteBool(json, 'useRealtime'),
      maxTransfers: _requiredRouteInt(json, 'maxTransfers'),
      alternativeCount: _requiredRouteInt(json, 'alternativeCount'),
      statuses: _routeStringList(json['statuses'], 'route v2 status'),
      itineraries: rawItineraries
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid route v2 itinerary payload');
            }
            return RouteSearchV2Itinerary.fromJson(item);
          })
          .toList(growable: false),
    );
  }

  final String contractVersion;
  final String originStationId;
  final String destinationStationId;
  final String departureTime;
  final String mobilityType;
  final String constraintMode;
  final bool useRealtime;
  final int maxTransfers;
  final int alternativeCount;
  final List<String> statuses;
  final List<RouteSearchV2Itinerary> itineraries;
}

class RouteSearchV2Itinerary {
  const RouteSearchV2Itinerary({
    required this.itineraryId,
    required this.status,
    required this.plannedArrivalTime,
    required this.realtimeArrivalTime,
    required this.etaSource,
    required this.etaConfidence,
    required this.durationSeconds,
    required this.transferCount,
    required this.walkingDistanceMeters,
    required this.accessibilityRisk,
    required this.legs,
    required this.commercialEtaEligible,
  });

  factory RouteSearchV2Itinerary.fromJson(Map<String, Object?> json) {
    final rawLegs = json['legs'];
    final rawAccessibilityRisk = json['accessibilityRisk'];
    if (rawLegs is! List<Object?> ||
        rawAccessibilityRisk is! Map<String, Object?>) {
      throw const FormatException('Invalid route v2 itinerary payload');
    }
    return RouteSearchV2Itinerary(
      itineraryId: _requiredRouteString(json, 'itineraryId'),
      status: _requiredRouteString(json, 'status'),
      plannedArrivalTime: _requiredRouteString(json, 'plannedArrivalTime'),
      realtimeArrivalTime: _optionalNullableRouteString(
        json,
        'realtimeArrivalTime',
      ),
      etaSource: _requiredRouteString(json, 'etaSource'),
      etaConfidence: _requiredRouteString(json, 'etaConfidence'),
      durationSeconds: _requiredRouteInt(json, 'durationSeconds'),
      transferCount: _requiredRouteInt(json, 'transferCount'),
      walkingDistanceMeters: _requiredRouteInt(json, 'walkingDistanceMeters'),
      accessibilityRisk: RouteSearchV2AccessibilityRisk.fromJson(
        rawAccessibilityRisk,
      ),
      legs: rawLegs
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid route v2 leg payload');
            }
            return RouteSearchV2Leg.fromJson(item);
          })
          .toList(growable: false),
      commercialEtaEligible: _requiredRouteBool(json, 'commercialEtaEligible'),
    );
  }

  final String itineraryId;
  final String status;
  final String plannedArrivalTime;
  final String? realtimeArrivalTime;
  final String etaSource;
  final String etaConfidence;
  final int durationSeconds;
  final int transferCount;
  final int walkingDistanceMeters;
  final RouteSearchV2AccessibilityRisk accessibilityRisk;
  final List<RouteSearchV2Leg> legs;
  final bool commercialEtaEligible;
}

class RouteSearchV2Leg {
  const RouteSearchV2Leg({
    required this.legType,
    required this.fromStationId,
    required this.toStationId,
    required this.fromNodeId,
    required this.toNodeId,
    required this.lineId,
    required this.tripId,
    required this.trainNo,
    required this.plannedDepartureTime,
    required this.realtimeDepartureTime,
    required this.plannedArrivalTime,
    required this.realtimeArrivalTime,
    required this.waitTimeSeconds,
    required this.slackSeconds,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.etaSource,
    required this.confidence,
    required this.accessibilityRisk,
  });

  factory RouteSearchV2Leg.fromJson(Map<String, Object?> json) {
    final rawAccessibilityRisk = json['accessibilityRisk'];
    if (rawAccessibilityRisk is! Map<String, Object?>) {
      throw const FormatException('Invalid route v2 leg payload');
    }
    return RouteSearchV2Leg(
      legType: _requiredRouteString(json, 'legType'),
      fromStationId: _optionalRouteString(json, 'fromStationId'),
      toStationId: _optionalRouteString(json, 'toStationId'),
      fromNodeId: _optionalRouteString(json, 'fromNodeId'),
      toNodeId: _optionalRouteString(json, 'toNodeId'),
      lineId: _optionalRouteString(json, 'lineId'),
      tripId: _optionalRouteString(json, 'tripId'),
      trainNo: _optionalRouteString(json, 'trainNo'),
      plannedDepartureTime: _requiredRouteString(json, 'plannedDepartureTime'),
      realtimeDepartureTime: _optionalNullableRouteString(
        json,
        'realtimeDepartureTime',
      ),
      plannedArrivalTime: _requiredRouteString(json, 'plannedArrivalTime'),
      realtimeArrivalTime: _optionalNullableRouteString(
        json,
        'realtimeArrivalTime',
      ),
      waitTimeSeconds: _requiredRouteInt(json, 'waitTimeSeconds'),
      slackSeconds: _requiredRouteInt(json, 'slackSeconds'),
      durationSeconds: _requiredRouteInt(json, 'durationSeconds'),
      distanceMeters: _requiredRouteInt(json, 'distanceMeters'),
      etaSource: _requiredRouteString(json, 'etaSource'),
      confidence: _requiredRouteString(json, 'confidence'),
      accessibilityRisk: RouteSearchV2AccessibilityRisk.fromJson(
        rawAccessibilityRisk,
      ),
    );
  }

  final String legType;
  final String fromStationId;
  final String toStationId;
  final String fromNodeId;
  final String toNodeId;
  final String lineId;
  final String tripId;
  final String trainNo;
  final String plannedDepartureTime;
  final String? realtimeDepartureTime;
  final String plannedArrivalTime;
  final String? realtimeArrivalTime;
  final int waitTimeSeconds;
  final int slackSeconds;
  final int durationSeconds;
  final int distanceMeters;
  final String etaSource;
  final String confidence;
  final RouteSearchV2AccessibilityRisk accessibilityRisk;
}

class RouteSearchV2AccessibilityRisk {
  const RouteSearchV2AccessibilityRisk({
    required this.stairCount,
    required this.unknownAccessibilityCount,
    required this.generatedConnectorCount,
    required this.staleDataCount,
    required this.lowConfidenceCount,
    required this.unavailableFacilityCount,
    required this.riskLevel,
    required this.reasonCodes,
    required this.level,
    required this.reasons,
  });

  factory RouteSearchV2AccessibilityRisk.fromJson(Map<String, Object?> json) {
    final reasonCodes = _routeStringList(
      json['reasonCodes'] ?? json['reasons'],
      'route v2 accessibility risk reason',
    );
    final riskLevel = _optionalRouteString(
      json,
      'riskLevel',
      fallback: _optionalRouteString(json, 'level', fallback: 'UNKNOWN'),
    );
    return RouteSearchV2AccessibilityRisk(
      stairCount: _optionalRouteInt(json, 'stairCount') ?? 0,
      unknownAccessibilityCount:
          _optionalRouteInt(json, 'unknownAccessibilityCount') ?? 0,
      generatedConnectorCount:
          _optionalRouteInt(json, 'generatedConnectorCount') ?? 0,
      staleDataCount: _optionalRouteInt(json, 'staleDataCount') ?? 0,
      lowConfidenceCount: _optionalRouteInt(json, 'lowConfidenceCount') ?? 0,
      unavailableFacilityCount:
          _optionalRouteInt(json, 'unavailableFacilityCount') ?? 0,
      riskLevel: riskLevel,
      reasonCodes: reasonCodes,
      level: _requiredRouteString(json, 'level'),
      reasons: _routeStringList(
        json['reasons'],
        'route v2 accessibility risk reason',
      ),
    );
  }

  final int stairCount;
  final int unknownAccessibilityCount;
  final int generatedConnectorCount;
  final int staleDataCount;
  final int lowConfidenceCount;
  final int unavailableFacilityCount;
  final String riskLevel;
  final List<String> reasonCodes;
  final String level;
  final List<String> reasons;
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
    this.etaSource = '',
    this.fallbackReason = '',
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
      etaSource: _optionalRouteString(json, 'etaSource'),
      fallbackReason: _optionalRouteString(json, 'fallbackReason'),
    );
  }

  factory RouteSearchResult.fromV2(RouteSearchV2Result result) {
    final itinerary = result.itineraries.firstWhere(
      (candidate) => candidate.status == 'FOUND',
      orElse: () => result.itineraries.first,
    );
    final lineId = _routeV2SummaryLineId(itinerary.legs);
    return RouteSearchResult(
      routeSearchId: _routeV2RouteSearchId(itinerary.itineraryId),
      originStationId: result.originStationId,
      originStationName: result.originStationId,
      destinationStationId: result.destinationStationId,
      destinationStationName: result.destinationStationId,
      mobilityType: result.mobilityType,
      status: _routeV2Status(itinerary.status),
      lineId: lineId,
      lineName: lineId,
      score: _scoreFromRisk(itinerary.accessibilityRisk),
      burdenCost: itinerary.durationSeconds,
      estimatedDurationSeconds: itinerary.durationSeconds,
      walkingDistanceMeters: itinerary.walkingDistanceMeters,
      transferCount: itinerary.transferCount,
      evidenceSummary: [
        'ETA_${itinerary.etaSource}',
        'CONFIDENCE_${itinerary.etaConfidence}',
      ],
      steps: itinerary.legs
          .asMap()
          .entries
          .map((entry) => RouteSearchStep.fromV2(entry.key + 1, entry.value))
          .toList(growable: false),
      warnings: itinerary.accessibilityRisk.reasonCodes
          .map(
            (code) => RouteSearchWarning(
              code: code,
              message: _routeV2RiskMessage(code),
            ),
          )
          .toList(growable: false),
      recommendationReasons: itinerary.commercialEtaEligible
          ? const ['실시간 도착 정보를 반영했어요.']
          : const ['상용 ETA 품질 확인 전 경로입니다.'],
      blockedReasons: itinerary.status == 'FOUND'
          ? const []
          : itinerary.accessibilityRisk.reasonCodes,
      createdAt: result.departureTime,
      etaSource: itinerary.etaSource,
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
  final String etaSource;
  final String fallbackReason;

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
    return const ['선택한 길을 따라 안내합니다.'];
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
      return '계단 없는 길이에요';
    }
    return '계단 여부를 아직 알 수 없어요';
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
    final typedTransfers = steps.where(
      (step) => _isRouteTransferStepType(step.stepType),
    );
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
      _ => '경로 상태를 아직 알 수 없어요',
    };
  }

  String get scoreLabel => burdenLevelLabel;

  String get lineLabel => lineName.isEmpty ? '노선을 아직 알 수 없어요' : lineName;

  bool get isBlocked => status == 'BLOCKED';

  bool get needsConfirmation => !isBlocked && status != 'FOUND';

  bool get isLocalResult => routeSearchId.startsWith('local-');

  String get sourceNotice =>
      etaSource == 'STATIC_LOCAL' ? '실시간 미반영, 저장된 데이터 기준' : '';

  RouteSearchResult withSource({
    required String etaSource,
    String fallbackReason = '',
  }) {
    return withDisplayLabels(
      etaSource: etaSource,
      fallbackReason: fallbackReason,
    );
  }

  RouteSearchResult withDisplayLabels({
    String? originStationName,
    String? destinationStationName,
    String? lineName,
    List<RouteSearchStep>? steps,
    String? etaSource,
    String? fallbackReason,
  }) {
    return RouteSearchResult(
      routeSearchId: routeSearchId,
      originStationId: originStationId,
      originStationName: originStationName ?? this.originStationName,
      destinationStationId: destinationStationId,
      destinationStationName:
          destinationStationName ?? this.destinationStationName,
      mobilityType: mobilityType,
      status: status,
      lineId: lineId,
      lineName: lineName ?? this.lineName,
      score: score,
      accessibilityScore: _accessibilityScore,
      burdenCost: _burdenCost,
      estimatedDurationSeconds: _estimatedDurationSeconds,
      walkingDistanceMeters: _walkingDistanceMeters,
      transferCount: _transferCount,
      evidenceSummary: evidenceSummary,
      steps: steps ?? this.steps,
      warnings: warnings,
      recommendationReasons: recommendationReasons,
      blockedReasons: blockedReasons,
      createdAt: createdAt,
      etaSource: etaSource ?? this.etaSource,
      fallbackReason: fallbackReason ?? this.fallbackReason,
    );
  }

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
      return '살펴볼 내용';
    }
    return warnings.isEmpty ? '주의 안내가 없어요' : '주의 안내 보기';
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
      parts.add('다른 방법 $_routeSearchFailureNextAction');
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
      parts.add('이동 전 살펴보기 $_routeBlockedConfirmationNotice');
    }
    return parts.join(', ');
  }

  String get burdenLevelLabel {
    if (isBlocked) {
      return '이동 부담을 확인하고 있어요';
    }
    if (movementSteps.isEmpty) {
      return '이동 부담을 확인하고 있어요';
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

class RouteRefreshResult {
  const RouteRefreshResult({
    required this.routeSearchId,
    required this.status,
    required this.result,
    required this.refreshedAt,
    required this.etaSource,
    required this.etaConfidence,
    required this.sourceLabel,
    this.reasonCodes = const [],
  });

  factory RouteRefreshResult.fromJson(Map<String, Object?> json) {
    final route = json['route'];
    if (route is! Map<String, Object?>) {
      throw const FormatException('Invalid route refresh payload');
    }
    return RouteRefreshResult(
      routeSearchId: _requiredRouteString(json, 'routeSearchId'),
      status: _requiredRouteString(json, 'status'),
      result: RouteSearchResult.fromJson(route),
      refreshedAt: _requiredRouteString(json, 'refreshedAt'),
      etaSource: _requiredRouteString(json, 'etaSource'),
      etaConfidence: _requiredRouteString(json, 'etaConfidence'),
      sourceLabel: _requiredRouteString(json, 'sourceLabel'),
      reasonCodes: _routeStringList(
        json['reasonCodes'],
        'route refresh reason',
      ),
    );
  }

  final String routeSearchId;
  final String status;
  final RouteSearchResult result;
  final String refreshedAt;
  final String etaSource;
  final String etaConfidence;
  final String sourceLabel;
  final List<String> reasonCodes;

  String get userMessage {
    final statusLabel = switch (status) {
      'UPDATED_ETA' => '도착 시간을 새로 확인했어요.',
      'UNCHANGED' => '도착 시간이 그대로예요.',
      'STALE_FALLBACK' => '실시간 정보가 늦어 계획 시간으로 안내해요.',
      'REROUTE_REQUIRED' => '경로를 다시 찾아야 해요.',
      _ => '도착 시간을 확인했어요.',
    };
    final confidenceLabel = switch (etaConfidence) {
      'HIGH' => '신뢰도 높음',
      'MEDIUM' => '신뢰도 보통',
      'LOW' => '신뢰도 낮음',
      _ => '신뢰도 확인 중',
    };
    final source = sourceLabel.trim();
    return source.isEmpty
        ? '$statusLabel · $confidenceLabel'
        : '$statusLabel · $source · $confidenceLabel';
  }
}

int _scoreFromRisk(RouteSearchV2AccessibilityRisk risk) {
  final penalty =
      risk.stairCount * 30 +
      risk.unavailableFacilityCount * 30 +
      risk.generatedConnectorCount * 15 +
      risk.unknownAccessibilityCount * 15 +
      risk.staleDataCount * 10 +
      risk.lowConfidenceCount * 10;
  return (100 - penalty).clamp(0, 100);
}

String _routeV2DepartureTimeNow() {
  final timestamp = DateTime.now().toUtc().toIso8601String();
  return '${timestamp.split('.').first}Z';
}

String _routeV2RouteSearchId(String itineraryId) {
  for (final suffix in const ['-primary', '-review']) {
    if (itineraryId.endsWith(suffix)) {
      return itineraryId.substring(0, itineraryId.length - suffix.length);
    }
  }
  return itineraryId;
}

String _routeV2Status(String status) {
  return status == 'FOUND' ? 'FOUND' : 'BLOCKED';
}

String _routeV2SummaryLineId(List<RouteSearchV2Leg> legs) {
  for (final leg in legs) {
    if (leg.legType == 'RIDE' && leg.lineId.trim().isNotEmpty) {
      return leg.lineId;
    }
  }
  for (final leg in legs) {
    if (leg.lineId.trim().isNotEmpty) {
      return leg.lineId;
    }
  }
  return '';
}

bool _routeV2RiskRequiresCheck(RouteSearchV2AccessibilityRisk risk) {
  return risk.unknownAccessibilityCount > 0 ||
      risk.generatedConnectorCount > 0 ||
      risk.staleDataCount > 0 ||
      risk.lowConfidenceCount > 0 ||
      risk.unavailableFacilityCount > 0;
}

String _routeV2StairAccessState(RouteSearchV2AccessibilityRisk risk) {
  if (risk.stairCount > 0) {
    return 'stairOnly';
  }
  if (_routeV2RiskRequiresCheck(risk)) {
    return 'unknown';
  }
  return 'stepFree';
}

String _routeV2StepType(String legType) {
  return switch (legType) {
    'ACCESS' => 'entry',
    'EGRESS' => 'exit',
    'TRANSFER' => 'transfer',
    'RIDE' => 'ride',
    _ => legType.toLowerCase(),
  };
}

String _routeV2RiskMessage(String code) {
  return switch (code) {
    'STAIR_ONLY_ACCESS' => '계단 구간이 포함될 수 있어요.',
    'ACCESSIBILITY_CHECK_REQUIRED' => '현장 접근성 확인이 필요해요.',
    'STALE_ACCESSIBILITY_DATA' => '시설 상태 안내가 오래됐을 수 있어요.',
    'LOW_DATA_CONFIDENCE' => '경로 신뢰도가 낮아 현장 확인이 필요해요.',
    _ => '경로 상태를 현장에서 확인해 주세요.',
  };
}

String _routeV2LegTitle(RouteSearchV2Leg leg) {
  return switch (leg.legType) {
    'RIDE' => '${leg.fromStationId}에서 ${leg.toStationId}까지 이동',
    'TRANSFER' => '${leg.fromStationId}에서 환승',
    'ACCESS' => '${leg.fromStationId} 승강장 접근',
    'EGRESS' => '${leg.toStationId} 출구 접근',
    _ => '${leg.fromStationId}에서 ${leg.toStationId}까지 이동',
  };
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
        fallback: '안내를 준비 중이에요',
      ),
    );
  }

  factory RouteSearchStep.fromV2(int sequence, RouteSearchV2Leg leg) {
    final waitOrSlackSeconds = leg.waitTimeSeconds > leg.slackSeconds
        ? leg.waitTimeSeconds
        : leg.slackSeconds;
    final minutes = ((leg.durationSeconds + waitOrSlackSeconds) / 60).ceil();
    final title = _routeV2LegTitle(leg);
    return RouteSearchStep(
      sequence: sequence,
      stepType: _routeV2StepType(leg.legType),
      title: title,
      description: title,
      lineId: leg.lineId,
      lineName: leg.lineId,
      fromStationId: leg.fromStationId,
      toStationId: leg.toStationId,
      estimatedMinutes: minutes,
      distanceMeters: leg.distanceMeters,
      includesStairs: leg.accessibilityRisk.stairCount > 0,
      stairAccessState: _routeV2StairAccessState(leg.accessibilityRisk),
      requiresAccessibilityCheck: _routeV2RiskRequiresCheck(
        leg.accessibilityRisk,
      ),
      actionTitle: '',
      actionDetail: title,
      reason: leg.etaSource,
      timeSource: leg.etaSource,
      distanceSource: 'BACKEND_V2',
      confidenceLabel: leg.confidence,
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

  RouteSearchStep withDisplayLabels({
    required String title,
    required String lineName,
    required String actionDetail,
  }) {
    return RouteSearchStep(
      sequence: sequence,
      stepType: stepType,
      title: title,
      description: title,
      lineId: lineId,
      lineName: lineName,
      fromStationId: fromStationId,
      toStationId: toStationId,
      estimatedMinutes: estimatedMinutes,
      distanceMeters: distanceMeters,
      includesStairs: includesStairs,
      stairAccessState: stairAccessState,
      requiresAccessibilityCheck: requiresAccessibilityCheck,
      actionTitle: actionTitle,
      actionDetail: actionDetail,
      reason: reason,
      evidenceSources: evidenceSources,
      timeSource: timeSource,
      distanceSource: distanceSource,
      confidenceLabel: confidenceLabel,
    );
  }

  String get userReason => _routeStepReasonLabel(reason);

  String get userTitle => _routeStepTitleLabel(title);

  String get userActionTitle => _routeStepTitleLabel(actionTitle);

  String get userDescription => _routeStepDetailLabel(stepType: stepType);

  String get burdenLabel {
    final labels = <String>[
      _routeDurationLabel(estimatedMinutes),
      _routeDistanceLabel(distanceMeters),
      if (includesStairs) '계단 포함',
      if (requiresAccessibilityCheck) '엘리베이터 안내 준비 중',
    ];
    return labels.join(' · ');
  }

  String get semanticGuidanceLabel {
    final safeReason = _routeStepReasonLabel(reason);
    final labels = <String>[
      '$sequence번 ${userActionTitle.isEmpty ? userTitle : userActionTitle}',
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
      'entry' ||
      'exit' ||
      'transfer' ||
      'inStationTransfer' ||
      'outOfStationTransfer' ||
      'walkway' ||
      'elevator' ||
      'ramp' ||
      'stair' ||
      'escalator' ||
      'facilityConnector' ||
      'internal' => true,
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
      return '예상 시간·거리예요. 현장 안내를 먼저 확인해 주세요';
    }
    if (timeSource == 'UNKNOWN' || distanceSource == 'UNKNOWN') {
      return '시간 또는 거리를 확인하고 있어요';
    }
    if (timeSource == 'REALTIME') {
      return '실시간 도착 정보 기준이에요';
    }
    if (timeSource == 'PLANNED' || distanceSource == 'BACKEND_V2') {
      return '서버 경로 안내 기준이에요';
    }
    return '앱에 저장된 길 안내예요';
  }
}

String _routeDurationLabel(int estimatedMinutes) {
  if (estimatedMinutes <= 0) {
    return '시간을 확인하고 있어요';
  }
  return '약 $estimatedMinutes분';
}

String _routeDistanceLabel(int distanceMeters) {
  if (distanceMeters <= 0) {
    return '거리를 확인하고 있어요';
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
    'LOW_DATA_CONFIDENCE' => '일부 시설 안내를 준비 중이에요.',
    'STALE_ACCESSIBILITY_DATA' => '시설 상태 안내가 오래됐을 수 있어요.',
    'STAIR_ONLY_ACCESS' => '계단 포함 구간이 있습니다.',
    'STAIR_ONLY_ACCESS_UNKNOWN' => '계단 없는 길인지 아직 알 수 없어요.',
    'GENERATED_CONNECTOR_UNVERIFIED' =>
      '연결 위치를 아직 정확히 확인하지 못했어요. 현장 안내를 먼저 봐 주세요.',
    'DURATION_UNKNOWN' => '소요 시간을 확인하고 있어요.',
    'ROUTE_GRAPH_UNKNOWN' => '길이 이어지는지 아직 확인하지 못했어요.',
    'ACCESSIBILITY_STATE_UNKNOWN' => '엘리베이터와 통로 상태를 아직 알 수 없어요.',
    _ => '일부 이동 정보를 확인하지 못했어요.',
  };
}

String _routeBlockedReasonLabel(String reason) {
  final formalFailureSuffix = '${'못했'}습니다.';
  final normalizedReason = reason.trim().replaceAll(
    formalFailureSuffix,
    '못했어요.',
  );
  return switch (normalizedReason) {
    'STAIR_ONLY_ACCESS' => '계단 없는 경로를 아직 찾지 못했어요.',
    'STAIR_ONLY_ACCESS_UNKNOWN' => '계단 없는 길인지 아직 알 수 없어요.',
    'GENERATED_CONNECTOR_UNVERIFIED' => '계단 없는 길인지 아직 알 수 없어요.',
    'FACILITY_UNAVAILABLE' => '꼭 필요한 시설을 지금 이용하기 어려워요.',
    'ACCESSIBILITY_STATE_UNKNOWN' => '엘리베이터와 통로 상태를 아직 알 수 없어요.',
    'ROUTE_GRAPH_UNKNOWN' => '길이 이어지는지 아직 확인하지 못했어요.',
    '계단 없는 경로를 아직 찾지 못했어요.' => '계단 없는 경로를 아직 찾지 못했어요.',
    '계단 없는 길인지 아직 알 수 없어요.' => '계단 없는 길인지 아직 알 수 없어요.',
    '꼭 필요한 시설을 지금 이용하기 어려워요.' => '꼭 필요한 시설을 지금 이용하기 어려워요.',
    '엘리베이터와 통로 상태를 아직 알 수 없어요.' => '엘리베이터와 통로 상태를 아직 알 수 없어요.',
    '길이 이어지는지 아직 확인하지 못했어요.' => '길이 이어지는지 아직 확인하지 못했어요.',
    '계단 없는 경로를 찾지 못했어요.' => '계단 없는 경로를 아직 찾지 못했어요.',
    '계단 없는 동선 여부를 확인할 수 없습니다.' => '계단 없는 길인지 아직 알 수 없어요.',
    '필수 접근성 시설을 사용할 수 없습니다.' => '꼭 필요한 시설을 지금 이용하기 어려워요.',
    '접근성 시설 이용 가능 여부를 확인할 수 없습니다.' => '엘리베이터와 통로 상태를 아직 알 수 없어요.',
    '경로 연결 정보를 확인할 수 없습니다.' => '길이 이어지는지 아직 확인하지 못했어요.',
    _ => '안내할 수 있는 경로를 아직 찾지 못했어요.',
  };
}

String _routeStepReasonLabel(String reason) {
  if (reason.trim().isEmpty) {
    return '';
  }
  return '선택한 길을 따라 안내합니다.';
}

String _routeStepTitleLabel(String title) {
  return title.trim().replaceAll('접근성 정보', '엘리베이터와 통로 안내');
}

String _routeStepDetailLabel({required String stepType}) {
  return switch (stepType) {
    'entry' => '계단 없는 승강장 접근 동선을 확인해 이동합니다.',
    'exit' => '도착역에서 계단 없는 출구 동선을 확인합니다.',
    'transfer' || 'inStationTransfer' => '다음 노선으로 갈아탈 준비를 합니다.',
    'outOfStationTransfer' => '역 밖으로 이동해 다음 노선으로 갈아탑니다.',
    'walkway' => '확인된 통로를 따라 이동합니다.',
    'elevator' => '엘리베이터를 이용해 이동합니다.',
    'ramp' => '경사로를 따라 이동합니다.',
    'stair' => '계단 구간입니다. 계단 없는 조건에서는 안내하지 않습니다.',
    'escalator' => '에스컬레이터를 이용해 이동합니다.',
    'facilityConnector' => '역 시설 연결 동선을 따라 이동합니다.',
    'ride' => '열차를 이용해 이동합니다.',
    _ => '안내된 순서대로 이동합니다.',
  };
}

bool _isRouteTransferStepType(String stepType) {
  return stepType == 'transfer' ||
      stepType == 'inStationTransfer' ||
      stepType == 'outOfStationTransfer';
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
    this.isRefreshing = false,
    this.refreshMessage = '',
  });

  const RouteSearchState.idle()
    : status = RouteSearchViewStatus.idle,
      result = null,
      message = '',
      isRefreshing = false,
      refreshMessage = '';

  final RouteSearchViewStatus status;
  final RouteSearchResult? result;
  final String message;
  final bool isRefreshing;
  final String refreshMessage;

  RouteSearchState copyWith({
    RouteSearchViewStatus? status,
    RouteSearchResult? result,
    String? message,
    bool? isRefreshing,
    String? refreshMessage,
  }) {
    return RouteSearchState(
      status: status ?? this.status,
      result: result ?? this.result,
      message: message ?? this.message,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      refreshMessage: refreshMessage ?? this.refreshMessage,
    );
  }
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

  Future<void> refreshCurrentRoute() async {
    if (_disposed) {
      return;
    }
    final currentResult = _state.result;
    if (_state.status != RouteSearchViewStatus.success ||
        currentResult == null ||
        currentResult.isLocalResult ||
        _state.isRefreshing) {
      return;
    }

    final refreshRequestId = _searchRequestId;
    final refreshRouteSearchId = currentResult.routeSearchId;
    bool staleRefresh() =>
        _disposed ||
        refreshRequestId != _searchRequestId ||
        _state.result?.routeSearchId != refreshRouteSearchId;

    _emitState(_state.copyWith(isRefreshing: true));
    try {
      final refreshed = await repository.refreshRoute(refreshRouteSearchId);
      if (staleRefresh()) {
        return;
      }
      _emitState(
        RouteSearchState(
          status: RouteSearchViewStatus.success,
          result: refreshed.result,
          refreshMessage: refreshed.userMessage,
        ),
      );
    } on RouteSearchException catch (error) {
      if (staleRefresh()) {
        return;
      }
      _emitState(
        _state.copyWith(isRefreshing: false, refreshMessage: error.message),
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '경로 ETA refresh 처리 중 예외가 발생했습니다.',
      );
      if (staleRefresh()) {
        return;
      }
      _emitState(
        _state.copyWith(
          isRefreshing: false,
          refreshMessage: _routeRefreshErrorMessage,
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
    this.shellNavigationBar,
    this.onShellBackToHome,
    String? initialMobilityType,
    super.key,
  }) : initialMobilityType = _resolveInitialMobilityType(initialMobilityType);

  final RouteSearchRepository repository;
  final StationSearchRepository stationRepository;
  final RouteFeedbackRepository? routeFeedbackRepository;
  final FavoriteRouteRepository? favoriteRouteRepository;
  final RouteDraft? initialDraft;
  final Widget? shellNavigationBar;
  final VoidCallback? onShellBackToHome;
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

class _RouteSearchScreenState extends State<RouteSearchScreen>
    with WidgetsBindingObserver {
  late final RouteSearchController _controller;
  StationSearchResult? _originStation;
  StationSearchResult? _destinationStation;
  _RouteStationRole? _activeStationPicker;
  late String _selectedMobilityType;
  late String _selectedConstraintMode;
  String _validationMessage = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = RouteSearchController(repository: widget.repository);
    _originStation = _stationFromDraft(widget.initialDraft?.origin);
    _destinationStation = _stationFromDraft(widget.initialDraft?.destination);
    _selectedMobilityType = widget.initialMobilityType;
    _selectedConstraintMode = RouteSearchRequest._defaultConstraintMode(
      _selectedMobilityType,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.refreshCurrentRoute();
    }
  }

  @override
  Widget build(BuildContext context) {
    final submitButton = Padding(
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
                    borderRadius: _routeSearchSmallRadius,
                  ),
                ),
                child: Text(isLoading ? '경로 검색 중' : '길찾기'),
              ),
            ),
          );
        },
      ),
    );
    final scaffold = Scaffold(
      key: const Key('routeSearchScreen'),
      appBar: AppBar(title: const Text('길찾기')),
      bottomNavigationBar: widget.shellNavigationBar == null
          ? submitButton
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [submitButton, widget.shellNavigationBar!],
            ),
      body: SafeArea(
        child: RefreshIndicator(
          key: const Key('routeResultRefreshIndicator'),
          onRefresh: _controller.refreshCurrentRoute,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: _routeSearchPagePadding,
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
                          _selectedConstraintMode =
                              RouteSearchRequest._defaultConstraintMode(value);
                        });
                      },
                    ),
                  ),
                ),
              SwitchListTile(
                key: const Key('routeStrictStepFreeSwitch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('계단 없는 길만'),
                subtitle: const Text('켜면 경로가 줄거나 없을 수 있어요.'),
                value: _selectedConstraintMode == 'STRICT_STEP_FREE',
                onChanged: (value) {
                  setState(() {
                    _selectedConstraintMode = value
                        ? 'STRICT_STEP_FREE'
                        : 'PREFER_STEP_FREE';
                  });
                },
              ),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => _RouteSearchBody(
                  state: _controller.state,
                  routeFeedbackRepository: widget.routeFeedbackRepository,
                  favoriteRouteRepository: widget.favoriteRouteRepository,
                  onShellBackToHome: widget.onShellBackToHome,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final onShellBackToHome = widget.onShellBackToHome;
    if (onShellBackToHome == null) {
      return scaffold;
    }
    return AnimatedBuilder(
      animation: _controller,
      child: scaffold,
      builder: (context, child) {
        if (_controller.state.status == RouteSearchViewStatus.success) {
          return child!;
        }
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              onShellBackToHome();
            }
          },
          child: child!,
        );
      },
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
        constraintMode: _selectedConstraintMode,
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
                      padding: _routeMobilitySheetHeaderPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '이동 조건',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: _routeTextPrimaryColor,
                                  fontWeight: FontWeight.w900,
                                  height: 1.25,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '상황에 맞는 이동 조건을 고른 뒤 적용해 주세요.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: _routeTextSubtleColor,
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
                        padding: _routeMobilitySheetListPadding,
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
                      padding: _routeMobilitySheetActionPadding,
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
      _selectedConstraintMode = RouteSearchRequest._defaultConstraintMode(
        selectedMobilityType,
      );
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
        border: Border.all(color: _routeCardBorderColor),
        borderRadius: _routeSearchLargeRadius,
        boxShadow: const [
          BoxShadow(
            color: _routeCardShadowColor,
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          Padding(
            padding: _routePointSelectorPadding,
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
                const Divider(height: 1, color: _routeDividerColor),
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
                  color: _routeTextPrimaryColor,
                  style: IconButton.styleFrom(
                    fixedSize: const Size(48, 48),
                    side: const BorderSide(color: _routeControlBorderColor),
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
          borderRadius: _routeSearchMediumRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    stationName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _routeTextPrimaryColor,
                      fontSize: 22,
                      height: 1.2,
                    ),
                  ),
                ),
                const Icon(Icons.map_outlined, color: _routeTextSubtleColor),
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
              color: _routeTextPrimaryColor,
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
    _loadFavorites();
  }

  @override
  void didUpdateWidget(_RouteRecentDestinationList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _loadFavorites();
    }
  }

  void _loadFavorites() {
    _future = widget.repository?.listFavoriteRoutes();
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
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _RouteSearchMessage(
                message: '최근 도착지를 불러오지 못했어요.',
                liveRegion: true,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('routeRecentDestinationRetryButton'),
                onPressed: () => setState(_loadFavorites),
                icon: const Icon(Icons.refresh),
                label: const Text('다시 불러오기'),
              ),
              const SizedBox(height: 18),
            ],
          );
        }
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
                border: Border.all(color: _routeCardBorderColor),
                borderRadius: _routeSearchMediumRadius,
              ),
              child: Column(
                children: [
                  for (final entry in destinations.indexed) ...[
                    if (entry.$1 > 0)
                      const Divider(height: 1, color: _routeDividerColor),
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
          borderRadius: _routeSearchMediumRadius,
          child: ListTile(
            leading: const Icon(Icons.train_outlined, color: _routeAccentColor),
            title: Text(
              title,
              style: const TextStyle(
                color: _routeTextPrimaryColor,
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
            color: _routeTextSubtleColor,
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
            color: _routeTextPrimaryColor,
            fontWeight: FontWeight.w900,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          _routeMobilityConditionLabel(option),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: _routeTextSubtleColor,
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
          color: _routeSoftPanelColor,
          border: Border.all(color: _routeSoftPanelBorderColor),
          borderRadius: _routeSearchSmallRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      Icon(option.icon, color: _routeAccentColor, size: 26),
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
              borderRadius: _routeSearchSmallRadius,
              side: const BorderSide(color: _routeCardBorderColor),
            ),
            child: InkWell(
              onTap: () => onSelected(result),
              borderRadius: _routeSearchSmallRadius,
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
                              color: _routeTextPrimaryColor,
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
                              color: _routeTextSecondaryColor,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            result.dataQualityLabel,
                            style: textTheme.bodyMedium?.copyWith(
                              color: _routeTextMutedColor,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.chevron_right,
                      color: _routeAccentColor,
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
    required this.onShellBackToHome,
  });

  final RouteSearchState state;
  final RouteFeedbackRepository? routeFeedbackRepository;
  final FavoriteRouteRepository? favoriteRouteRepository;
  final VoidCallback? onShellBackToHome;

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
        refreshMessage: state.refreshMessage,
        isRefreshing: state.isRefreshing,
        routeFeedbackRepository: routeFeedbackRepository,
        favoriteRouteRepository: favoriteRouteRepository,
        onShellBackToHome: onShellBackToHome,
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
            label: '도움말, $_routeSearchFailureNextAction',
            child: Text(
              _routeSearchFailureNextAction,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _routeNextActionTextColor,
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
          color: _routeTextMutedColor,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}

class _RouteRefreshStatusBanner extends StatelessWidget {
  const _RouteRefreshStatusBanner({
    required this.message,
    required this.isRefreshing,
  });

  final String message;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    if (!isRefreshing && message.isEmpty) {
      return const SizedBox.shrink();
    }
    final text = isRefreshing ? '도착 시간을 확인하고 있어요.' : message;
    return Semantics(
      key: const Key('routeRefreshStatusBanner'),
      container: true,
      liveRegion: true,
      label: text,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _routeArrivalPanelColor,
          border: Border.all(color: _routeArrivalBorderColor),
          borderRadius: _routeSearchSmallRadius,
        ),
        child: Row(
          children: [
            if (isRefreshing) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: 10),
            ] else ...[
              const Icon(
                Icons.refresh,
                color: _routeArrivalTextColor,
                size: 22,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _routeArrivalTextColor,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
            ),
          ],
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
    required this.refreshMessage,
    required this.isRefreshing,
    required this.routeFeedbackRepository,
    required this.favoriteRouteRepository,
    required this.onShellBackToHome,
  });

  final RouteSearchResult result;
  final String refreshMessage;
  final bool isRefreshing;
  final RouteFeedbackRepository? routeFeedbackRepository;
  final FavoriteRouteRepository? favoriteRouteRepository;
  final VoidCallback? onShellBackToHome;

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
    final refreshMessage = widget.refreshMessage;
    if (result.isBlocked) {
      final content = _RouteBlockedWorkflow(result: result);
      final onShellBackToHome = widget.onShellBackToHome;
      if (onShellBackToHome == null) {
        return content;
      }
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            onShellBackToHome();
          }
        },
        child: content,
      );
    }

    final canUseRouteActions = _isRecommendedRoute(result);
    final canUseApiActions = !result.isLocalResult;
    final canSaveRoute =
        canUseApiActions &&
        widget.favoriteRouteRepository != null &&
        canUseRouteActions;
    final canOpenFeedback =
        canUseApiActions && widget.routeFeedbackRepository != null;

    final workflowContent = switch (_view) {
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
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RouteRefreshStatusBanner(
          message: refreshMessage,
          isRefreshing: widget.isRefreshing,
        ),
        workflowContent,
      ],
    );
    final onShellBackToHome = widget.onShellBackToHome;
    return PopScope(
      canPop: _view == _RouteWorkflowView.list && onShellBackToHome == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        if (_view == _RouteWorkflowView.list) {
          onShellBackToHome?.call();
          return;
        }
        setState(() {
          _view = switch (_view) {
            _RouteWorkflowView.detail => _RouteWorkflowView.list,
            _RouteWorkflowView.guidance => _RouteWorkflowView.detail,
            _RouteWorkflowView.internalRoute => _RouteWorkflowView.guidance,
            _RouteWorkflowView.feedback => _RouteWorkflowView.detail,
            _ => _RouteWorkflowView.list,
          };
        });
      },
      child: content,
    );
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
        if (result.sourceNotice.isNotEmpty) ...[
          _RouteSearchMessage(message: result.sourceNotice),
          const SizedBox(height: 8),
        ],
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
            color: _routeGuidanceDarkColor,
            borderRadius: _routeSearchLargeRadius,
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
                    borderRadius: _routeSearchLargeRadius,
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
                _RouteResultSection(
                  title: result.isBlocked
                      ? '안내 불가 이유'
                      : _isRecommendedRoute(result)
                      ? '추천 경로'
                      : result.statusLabel,
                  subtitle: result.isBlocked
                      ? '현재 조건에서 막힌 이유를 확인하세요'
                      : _isRecommendedRoute(result)
                      ? '시간·환승·걷기와 편한 정도를 확인하세요.'
                      : '이 경로는 이동 전에 안내를 살펴봐 주세요',
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: result.isBlocked
                          ? _routeBlockedBorderColor
                          : EasySubwayAccessibleColors.mint,
                      width: 2,
                    ),
                    borderRadius: _routeSearchLargeRadius,
                    boxShadow: const [
                      BoxShadow(
                        color: _routeAccentShadowColor,
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
                          const _RouteLinePath(),
                        ],
                        if (blockedReasonLabels.isNotEmpty) ...[
                          const SizedBox(height: 13),
                          for (final reason in blockedReasonLabels)
                            _RouteReasonBadge(text: reason, blocked: true),
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
        const Icon(Icons.warning_amber, size: 64, color: _routeBlockedColor),
        const SizedBox(height: 10),
        Text(
          '계단 없는 경로가 없습니다',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: _routeTextPrimaryColor,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        for (final reason in reasons)
          _RouteReasonBadge(text: reason, blocked: true),
        const SizedBox(height: 12),
        const _RouteNotice(
          key: Key('routeBlockedNextActionNotice'),
          title: '다른 방법',
          text: _routeSearchFailureNextAction,
          icon: Icons.refresh,
          semanticsLabel: '도움말, $_routeSearchFailureNextAction',
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
            color: _routeTextPrimaryColor,
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
            borderRadius: _routeSearchSmallRadius,
            child: Ink(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: _routeResultBorderColor, width: 2),
                borderRadius: _routeSearchSmallRadius,
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
                                  color: _routeTextPrimaryColor,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(_routeMetaLabel(result)),
                    const SizedBox(height: 12),
                    const _RouteLinePath(),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _RouteStatusChip(
                          label: _routeTransferLabel(result),
                          icon: Icons.route_outlined,
                        ),
                        _RouteStatusChip(
                          label: '걷기 ${_routeWalkingDistanceLabel(result)}',
                          icon: Icons.directions_walk,
                        ),
                        _RouteStatusChip(
                          key: const Key('routeGuidanceMobilityChip'),
                          label: result.mobilityLabel == '이동 조건을 다시 선택해 주세요'
                              ? result.mobilityLabel
                              : result.comfortLabel,
                          icon: Icons.accessible_forward,
                        ),
                        _RouteStatusChip(
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
        color: _routeGuidanceDarkColor,
        borderRadius: _routeSearchSmallRadius,
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
            Text(
              subtitle,
              style: const TextStyle(color: _routeGuidanceSecondaryColor),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final chip in chips)
                  _RouteStatusChip(
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
  return transfers == 0 ? '환승 없이 이동' : '환승 $transfers회';
}

String _routeWalkingDistanceLabel(RouteSearchResult result) {
  return _routeDistanceLabel(result.walkingDistanceMeters);
}

String _routeMetaLabel(RouteSearchResult result) {
  return '${_routeTransferLabel(result)} · 걷기 ${_routeWalkingDistanceLabel(result)}';
}

String _routeGuidanceMobilityHeaderLabel(RouteSearchResult result) {
  final mobilityLabel = result.mobilityLabel;
  if (mobilityLabel == '이동 조건을 다시 선택해 주세요') {
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
    '계단 없는 길이에요' => Icons.check,
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

class _RouteResultSection extends StatelessWidget {
  const _RouteResultSection({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _routeResultSectionPadding,
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

class _RouteStatusChip extends StatelessWidget {
  const _RouteStatusChip({super.key, required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _routeStatusChipBackgroundColor,
        borderRadius: _routeSearchPillRadius,
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

class _RouteLinePath extends StatelessWidget {
  const _RouteLinePath();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RouteLineNode(),
        Expanded(child: Container(height: 6, color: _routeTimelineColor)),
        _RouteLineNode(),
      ],
    );
  }
}

class _RouteLineNode extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: _routeTimelineColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(color: _routeTimelineColor, spreadRadius: 2),
        ],
      ),
    );
  }
}

class _RouteReasonBadge extends StatelessWidget {
  const _RouteReasonBadge({required this.text, this.blocked = false});

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
                ? _routeBlockedSoftColor
                : EasySubwayAccessibleColors.mintSoft,
            child: Text(
              blocked ? '!' : '✓',
              style: TextStyle(
                color: blocked
                    ? _routeBlockedColor
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
        color: _routeArrivalPanelColor,
        border: Border.all(color: _routeArrivalBorderColor),
        borderRadius: _routeSearchSmallRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.exit_to_app,
              color: _routeArrivalTextColor,
              size: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '도착 안내',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _routeArrivalTextColor,
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    step.userDescription,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _routeTextPrimaryColor,
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
          color: _routeNoticePanelColor,
          border: Border.all(color: _routeNoticeBorderColor),
          borderRadius: _routeSearchSmallRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: _routeNoticeIconColor, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: _routeNoticeTextColor,
                        fontWeight: FontWeight.w900,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      text,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: _routeNoticeTextColor,
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
            color: _routeTextPrimaryColor,
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
            backgroundColor: _routeAccentColor,
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
                if (step.userActionTitle.isNotEmpty) ...[
                  Text(
                    step.userActionTitle,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _routeArrivalTextColor,
                      fontWeight: FontWeight.w900,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  step.userTitle,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: _routeTextPrimaryColor,
                    fontWeight: FontWeight.w900,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  step.burdenLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _routeTextSecondaryColor,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  step.userDescription,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: _routeTextMutedColor,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                if (step.userReason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    step.userReason,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _routeTextMutedColor,
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
                color: _routeTextSecondaryColor,
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
            label: '도움말, $_routeFeedbackFailureNextAction',
            child: Text(
              _routeFeedbackFailureNextAction,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _routeNextActionTextColor,
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
                color: _routeTextSecondaryColor,
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
            label: '도움말, $_favoriteRouteSaveFailureNextAction',
            child: Text(
              _favoriteRouteSaveFailureNextAction,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _routeNextActionTextColor,
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
      padding: _routeSearchPagePadding,
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
                label: '도움말, $_favoriteRouteLoadFailureNextAction',
                child: Text(
                  _favoriteRouteLoadFailureNextAction,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _routeNextActionTextColor,
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
                  color: _routeTextMutedColor,
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
              borderRadius: _routeSearchSmallRadius,
              side: const BorderSide(color: _routeCardBorderColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    favorite.summaryTitle,
                    style: textTheme.titleLarge?.copyWith(
                      color: _routeTextPrimaryColor,
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    favorite.lineLabel,
                    style: textTheme.bodyLarge?.copyWith(
                      color: _routeTextSecondaryColor,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    favorite.mobilityLabel,
                    style: textTheme.bodyLarge?.copyWith(
                      color: _routeTextSecondaryColor,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    favorite.scoreLabel,
                    style: textTheme.bodyLarge?.copyWith(
                      color: _routeTextSecondaryColor,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    favorite.scoreBasisText,
                    style: textTheme.bodyMedium?.copyWith(
                      color: _routeTextMutedColor,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    favorite.movementMetricLabel,
                    style: textTheme.bodyMedium?.copyWith(
                      color: _routeTextMutedColor,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    favorite.accessibilityMetricLabel,
                    style: textTheme.bodyMedium?.copyWith(
                      color: _routeTextMutedColor,
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

String? _optionalNullableRouteString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  throw FormatException('Invalid route field: $key');
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
