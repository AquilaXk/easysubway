import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'accessible_design.dart';
import 'ad_slot.dart';
import 'auth_headers.dart';
import 'core/network/api_client.dart';
import 'features/ads/active_ad_banner.dart';
import 'features/ads/ad_repository.dart';
import 'features/fare/official_od_fare_quote.dart';
import 'features/route_draft/domain/route_draft.dart';
import 'features/stations/presentation/service_pattern_badge.dart';
import 'features/stations/presentation/station_line_badges.dart';
import 'mobile_error_reporter.dart';
import 'features/get_off_alarm/get_off_alarm_controller.dart';
import 'features/get_off_alarm/get_off_alarm_route_mapping.dart';
import 'features/get_off_alarm/get_off_alarm_toggle.dart';
import 'features/mobility_profile/mobility_preset_labels.dart';
import 'features/mobility_profile/mobility_preset_picker.dart';
import 'features/mobility_profile/mobility_profile_policy.dart';
import 'route_hedge_labels.dart';
import 'route_share_summary.dart';
import 'station_search.dart';

typedef RouteShareInvoker =
    Future<void> Function(String text, Rect sharePositionOrigin);

const _routeSearchTimeout = Duration(seconds: 8);
const _routeSearchErrorMessage = '경로 정보를 불러오지 못했어요.';
const _routeOnlineSearchErrorMessage = '실시간/서버 경로를 확인하지 못했어요.';
const _routeRefreshErrorMessage = '도착 시간을 새로 확인하지 못했어요.';
const _getOffAlarmRefreshRollbackMessage = '하차 알림을 갱신하지 못해 이전 경로를 유지해요.';
const _getOffAlarmRefreshFailureMessage = '하차 알림을 새로 맞추지 못했어요. 이전 경로를 유지해요.';
const _routeFeedbackErrorMessage = '의견을 보내지 못했어요.';
const _favoriteRouteErrorMessage = '즐겨찾기 경로를 바꾸지 못했어요.';
const _favoriteRouteLoadErrorMessage = '즐겨찾기 경로를 불러오지 못했어요.';
const _routeSafetyGuidanceNotice = '이동 전 현장 안내와 역무원 안내를 확인해 주세요.';
const _routeSearchFailureNextAction = '역을 다시 선택하거나 이동 조건을 바꾼 뒤 경로를 다시 찾아보세요.';
const _routeFeedbackFailureNextAction = '잠시 후 다시 보내거나 경로 조건을 바꿔 다시 찾아보세요.';
const _favoriteRouteSaveFailureNextAction =
    '네트워크 상태를 확인한 뒤 자주 쓰는 경로 저장을 다시 눌러 주세요.';
const _routeSearchPagePadding = EdgeInsets.only(
  left: 20,
  top: 20,
  right: 20,
  bottom: 32,
);
const _routeSearchSmallRadius = BorderRadius.all(Radius.circular(8));
const _routeSearchMediumRadius = BorderRadius.all(Radius.circular(8));
const _routeSearchPickerRadius = BorderRadius.all(Radius.circular(8));
const _routeSearchPillRadius = BorderRadius.all(Radius.circular(8));
const _routePointRailWidth = 30.0;
const _routePointSelectorPadding = EdgeInsets.fromLTRB(4, 4, 12, 4);
const _routeResultSectionPadding = EdgeInsets.fromLTRB(1, 0, 1, 11);

String _mobilityLabelFor(String mobilityType) {
  final preset = mobilityPresetFromRepresentativeMobilityType(mobilityType);
  if (preset != null) {
    return mobilityPresetDisplayName(preset);
  }
  return '이동 조건을 다시 선택해 주세요';
}

String _routeDateLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.length >= 10) {
    return '최근 확인 ${trimmed.substring(0, 10)}';
  }
  return '최근 확인일이 아직 없어요';
}

const routeEtaSourceLabels = <String, String>{
  'REALTIME': '실시간 도착정보',
  'MIXED': '일부 실시간 도착정보',
  'PLANNED': '시간표 기준',
  'STATIC_BACKEND_ESTIMATE': '시간표 기준',
  'STATIC_BACKEND_V1': '시간표 기준',
  'STATIC_LOCAL': '저장된 데이터 기준',
  'STATIC_ESTIMATE': '정적 추정',
  'FALLBACK': '실시간 미지원',
  'UNSUPPORTED': '실시간 미지원',
  'STALE': '저장된 데이터 기준',
};

String routeEtaSourceLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '도착 정보를 확인하고 있어요';
  }
  return routeEtaSourceLabels[trimmed] ?? '도착 정보를 확인하고 있어요';
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

enum RouteEtaOffsetBucket {
  earlyOver3Minutes('EARLY_OVER_3_MINUTES'),
  early1To3Minutes('EARLY_1_TO_3_MINUTES'),
  onTime('ON_TIME'),
  late1To3Minutes('LATE_1_TO_3_MINUTES'),
  lateOver3Minutes('LATE_OVER_3_MINUTES'),
  notProvided('NOT_PROVIDED');

  const RouteEtaOffsetBucket(this.serverValue);

  final String serverValue;
}

class RouteFeedbackRequest {
  const RouteFeedbackRequest({
    required this.routeSearchId,
    required this.rating,
    required this.comment,
    this.itineraryId = '',
    this.mobilityType = '',
    this.constraintMode = '',
    this.etaSource = '',
    this.etaOffsetBucket = RouteEtaOffsetBucket.notProvided,
    this.etaFeedbackOptedIn = false,
  });

  final String routeSearchId;
  final RouteFeedbackRating rating;
  final String comment;
  final String itineraryId;
  final String mobilityType;
  final String constraintMode;
  final String etaSource;
  final RouteEtaOffsetBucket etaOffsetBucket;
  final bool etaFeedbackOptedIn;

  RouteFeedbackRequest trimmed() {
    return RouteFeedbackRequest(
      routeSearchId: routeSearchId.trim(),
      rating: rating,
      comment: comment.trim(),
      itineraryId: itineraryId.trim(),
      mobilityType: mobilityType.trim(),
      constraintMode: constraintMode.trim(),
      etaSource: etaSource.trim(),
      etaOffsetBucket: etaOffsetBucket,
      etaFeedbackOptedIn: etaFeedbackOptedIn,
    );
  }

  Map<String, Object?> toJson({required String userId}) {
    final trimmedRequest = trimmed();
    final payload = <String, Object?>{
      'userId': userId.trim(),
      'rating': trimmedRequest.rating.serverValue,
      'comment': trimmedRequest.comment,
    };
    if (trimmedRequest.etaFeedbackOptedIn) {
      payload.addAll({
        'itineraryId': trimmedRequest.itineraryId,
        'mobilityType': trimmedRequest.mobilityType,
        'constraintMode': trimmedRequest.constraintMode,
        'etaSource': trimmedRequest.etaSource,
        'etaOffsetBucket': trimmedRequest.etaOffsetBucket.serverValue,
        'etaFeedbackOptedIn': true,
      });
    }
    return payload;
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

      return RouteSearchResult.fromJson(
        data,
        constraintMode: routeRequest.effectiveConstraintMode,
        objective: RouteObjective.fastest,
      );
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
    this.bearerTokenProvider,
    this.bearerTokenInvalidator,
  }) : _apiClient =
           apiClient ?? ApiClient(baseUri: baseUri, httpClient: httpClient);

  final Uri baseUri;
  final ApiClient _apiClient;
  final Future<String> Function()? bearerTokenProvider;
  final void Function()? bearerTokenInvalidator;

  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest routeRequest) async {
    try {
      final bearerToken = await bearerTokenProvider?.call();
      final response = await _apiClient.postJson(
        '/api/v2/routes/search',
        body: routeRequest.toV2Json(),
        headers: {
          if (bearerToken != null)
            HttpHeaders.authorizationHeader: 'Bearer $bearerToken',
        },
      );
      if (!response.isSuccess) {
        if (response.statusCode == HttpStatus.unauthorized) {
          bearerTokenInvalidator?.call();
        }
        throw RouteSearchOnlineException.response(response);
      }
      final decoded = response.jsonBody;
      if (decoded is! Map<String, Object?> || decoded['success'] != true) {
        throw const RouteSearchOnlineException.unavailable();
      }
      final data = decoded['data'];
      if (data is! Map<String, Object?>) {
        throw const RouteSearchOnlineException.unavailable();
      }
      return RouteSearchResult.fromV2(
        RouteSearchV2Result.fromJson(data),
        objective: routeRequest.objective,
      );
    } on RouteSearchOnlineException {
      rethrow;
    } on ApiException catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '경로 V2 API 요청 처리 중 예외가 발생했습니다.',
      );
      throw const RouteSearchOnlineException.unavailable(
        failureReason: 'network-unavailable',
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
  Future<RouteRefreshResult> refreshRoute(String routeSearchId) {
    // #2153 production ingress는 session/search 두 경로만 열고 legacy refresh는 계속 닫는다.
    return Future.error(const RouteSearchException(_routeRefreshErrorMessage));
  }
}

class RouteSearchOnlineException extends RouteSearchException {
  const RouteSearchOnlineException.unavailable({
    this.statusCode,
    this.failureReason = 'online-unavailable',
    String message = _routeOnlineSearchErrorMessage,
  }) : super(message);

  factory RouteSearchOnlineException.http(int statusCode) {
    final backend4xxFailure = statusCode >= 400 && statusCode < 500;
    final backend5xxFailure = statusCode >= 500;
    return RouteSearchOnlineException._(
      statusCode: statusCode,
      failureReason: backend5xxFailure
          ? 'backend-5xx'
          : backend4xxFailure
          ? 'backend-4xx'
          : 'backend-unexpected',
    );
  }

  factory RouteSearchOnlineException.response(ApiResponse response) {
    final body = response.jsonBody;
    final code = body is Map<String, Object?> ? body['code'] : null;
    const messages = <String, String>{
      'ROUTE_SESSION_ATTESTATION_REJECTED': 'ITX 시간표를 불러올 수 없어요',
      'ROUTE_SESSION_ATTESTATION_UNAVAILABLE': 'ITX 시간표를 불러올 수 없어요',
      'ROUTE_SESSION_REQUIRED': '다시 시도',
      'ROUTE_SCOPE_INVALID': '지원하지 않는 경로예요',
      'ROUTE_RATE_LIMITED': '잠시 후 다시 시도',
      'ITX_TIMETABLE_UNAVAILABLE': 'ITX 시간표를 불러올 수 없어요',
    };
    if (code is String && messages.containsKey(code)) {
      return RouteSearchOnlineException._(
        statusCode: response.statusCode,
        failureReason: code,
        message: messages[code]!,
      );
    }
    return RouteSearchOnlineException.http(response.statusCode);
  }

  const RouteSearchOnlineException._({
    required this.statusCode,
    required this.failureReason,
    String message = _routeOnlineSearchErrorMessage,
  }) : super(message);

  final int? statusCode;
  final String failureReason;
}

enum RouteTransportScope {
  subway('SUBWAY'),
  subwayAndItxCheongchun('SUBWAY_AND_ITX_CHEONGCHUN');

  const RouteTransportScope(this.serverValue);

  final String serverValue;
}

RouteTransportScope _routeTransportScopeFromValue(Object? value) {
  return switch (value) {
    'SUBWAY_AND_ITX_CHEONGCHUN' => RouteTransportScope.subwayAndItxCheongchun,
    _ => RouteTransportScope.subway,
  };
}

/// 길찾기 최적화 목표. 선택 컨트롤이지만 실제 운행 정보(급행 여부)와는 무관한
/// 별개 차원이다. 서버는 null을 FASTEST로 해석하므로 기본값도 FASTEST다.
enum RouteObjective {
  fastest('FASTEST', '최단시간'),
  fewestTransfers('FEWEST_TRANSFERS', '최소환승');

  const RouteObjective(this.serverValue, this.label);

  final String serverValue;
  final String label;
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
    this.etaSource = '',
    this.transportScope = RouteTransportScope.subway,
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
      etaSource: _optionalRouteString(json, 'etaSource'),
      transportScope: _routeTransportScopeFromValue(json['transportScope']),
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
  final String etaSource;
  final RouteTransportScope transportScope;

  String get summaryTitle => '$originStationName에서 $destinationStationName까지';

  /// 노선명(모르면 빈 문자열 — 호출부에서 줄 자체를 숨긴다).
  String get lineLabel => lineName;

  bool get hasLine => lineName.isNotEmpty;

  String get mobilityLabel => _mobilityLabelFor(mobilityType);

  String get etaSourceLabel => routeEtaSourceLabel(etaSource);

  /// 확정 정보만: 이동 조건 · 노선(있을 때) · 최근 확인일 · 출처.
  String get scoreBasisText {
    return [
      '$mobilityLabel 조건',
      if (hasLine) lineLabel,
      _routeDateLabel(routeCreatedAt),
      if (etaSourceLabel.isNotEmpty) etaSourceLabel,
    ].join(' · ');
  }

  String get scoreBasisSemanticLabel {
    return [
      '$mobilityLabel 조건',
      if (hasLine) lineLabel,
      _routeDateLabel(routeCreatedAt),
      if (etaSourceLabel.isNotEmpty) etaSourceLabel,
    ].join(', ');
  }

  String get semanticLabel {
    return [
      '즐겨찾기 경로',
      summaryTitle,
      if (hasLine) lineLabel,
      mobilityLabel,
      scoreBasisSemanticLabel,
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
    this.waypointStationId,
    this.mobilityPreset,
    this.transportScope = RouteTransportScope.subway,
    this.objective = RouteObjective.fastest,
  });

  final String originStationId;
  final String destinationStationId;
  final String mobilityType;
  final String? constraintMode;
  final String? waypointStationId;

  /// v2 요청에만 실리는 보행 프리셋 서버 문자열(하위호환으로 mobilityType도 유지).
  final String? mobilityPreset;
  final RouteTransportScope transportScope;

  /// 최적화 목표(FASTEST·FEWEST_TRANSFERS). 급행 여부와는 무관한 별개 차원이며,
  /// 요청 serialization에는 이 값만 싣고 servicePattern/expressOnly는 싣지 않는다.
  final RouteObjective objective;

  String get effectiveConstraintMode =>
      constraintMode ?? _defaultConstraintMode(mobilityType);

  RouteSearchRequest trimmed() {
    return RouteSearchRequest(
      originStationId: originStationId.trim(),
      destinationStationId: destinationStationId.trim(),
      mobilityType: mobilityType,
      constraintMode: constraintMode?.trim(),
      waypointStationId: waypointStationId?.trim(),
      mobilityPreset: mobilityPreset?.trim(),
      transportScope: transportScope,
      objective: objective,
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
    final trimmedPreset = mobilityPreset?.trim();
    return {
      ...toJson(),
      if (trimmedPreset != null && trimmedPreset.isNotEmpty)
        'mobilityPreset': trimmedPreset,
      'objective': objective.serverValue,
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
    this.nextServiceTime = '',
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
      nextServiceTime:
          _optionalNullableRouteString(json, 'nextServiceTime') ?? '',
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
  final String nextServiceTime;
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
    this.objectiveTags = const [],
    this.officialFare,
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
      objectiveTags: _routeStringList(
        json['objectiveTags'] ?? const <Object?>[],
        'route v2 objective tag',
      ),
      officialFare: switch (json['officialFare']) {
        null => null,
        Map<String, Object?> value => RouteSearchOfficialFare.fromJson(value),
        _ => throw const FormatException('Invalid route v2 official fare'),
      },
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
  final RouteSearchOfficialFare? officialFare;

  /// 백엔드가 dual-tag dedupe한 대표 itinerary에 붙이는 objective 태그
  /// (FASTEST·FEWEST_TRANSFERS). 두 objective가 같은 경로면 두 태그를 모두 담는다.
  final List<String> objectiveTags;

  bool matchesObjective(RouteObjective objective) =>
      objectiveTags.contains(objective.serverValue);
}

class RouteSearchOfficialFare {
  const RouteSearchOfficialFare({
    required this.adultFareWon,
    required this.currency,
    required this.policy,
    required this.sourceIds,
    required this.sourceSnapshotIds,
  });

  factory RouteSearchOfficialFare.fromJson(Map<String, Object?> json) {
    final fare = RouteSearchOfficialFare(
      adultFareWon: _requiredRouteInt(json, 'adultFareWon'),
      currency: _requiredRouteString(json, 'currency'),
      policy: _requiredRouteString(json, 'policy'),
      sourceIds: _routeStringList(json['sourceIds'], 'official fare source'),
      sourceSnapshotIds: _routeStringList(
        json['sourceSnapshotIds'],
        'official fare source snapshot',
      ),
    );
    if (fare.adultFareWon <= 0 ||
        fare.currency != 'KRW' ||
        fare.policy != 'SUM_OF_OFFICIAL_RIDE_OD_FARES' ||
        fare.sourceIds.isEmpty ||
        fare.sourceSnapshotIds.isEmpty) {
      throw const FormatException('Invalid route v2 official fare');
    }
    return fare;
  }

  final int adultFareWon;
  final String currency;
  final String policy;
  final List<String> sourceIds;
  final List<String> sourceSnapshotIds;
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
    this.serviceClass,
    this.servicePattern,
  });

  factory RouteSearchV2Leg.fromJson(Map<String, Object?> json) {
    final rawAccessibilityRisk = json['accessibilityRisk'];
    if (rawAccessibilityRisk is! Map<String, Object?>) {
      throw const FormatException('Invalid route v2 leg payload');
    }
    final legType = _requiredRouteString(json, 'legType');
    final (serviceClass, servicePattern) = _routeV2LegServiceFields(
      legType,
      json['serviceClass'],
      json['servicePattern'],
    );
    return RouteSearchV2Leg(
      legType: legType,
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
      serviceClass: serviceClass,
      servicePattern: servicePattern,
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

  /// 운행 클래스(SUBWAY·ITX_CHEONGCHUN). RIDE leg에서만 채워지고, 그 외에는 null.
  final String? serviceClass;

  /// 운행종별(LOCAL·EXPRESS). RIDE leg에서만 채워지고, 그 외에는 null.
  final String? servicePattern;

  /// 지하철 급행 leg 여부. `급행` 배지를 노출하는 유일한 조건이다.
  bool get isSubwayExpress =>
      serviceClass == 'SUBWAY' && servicePattern == 'EXPRESS';
}

const _routeV2ServiceClasses = {'SUBWAY', 'ITX_CHEONGCHUN'};
const _routeV2ServicePatterns = {'LOCAL', 'EXPRESS'};

/// RIDE leg의 serviceClass·servicePattern을 필수 enum으로 검증하고, non-ride leg은
/// null만 허용한다. unknown·blank·non-ride 값 존재는 payload error로 처리해
/// LOCAL 추정 없이 unavailable로 흐르게 한다.
(String?, String?) _routeV2LegServiceFields(
  String legType,
  Object? rawServiceClass,
  Object? rawServicePattern,
) {
  final isRide = legType == 'RIDE';
  if (!isRide) {
    if (rawServiceClass != null || rawServicePattern != null) {
      throw const FormatException(
        'Non-ride route v2 leg must not carry service fields',
      );
    }
    return (null, null);
  }
  if (rawServiceClass is! String ||
      !_routeV2ServiceClasses.contains(rawServiceClass)) {
    throw const FormatException('Invalid route v2 ride serviceClass');
  }
  if (rawServicePattern is! String ||
      !_routeV2ServicePatterns.contains(rawServicePattern)) {
    throw const FormatException('Invalid route v2 ride servicePattern');
  }
  return (rawServiceClass, rawServicePattern);
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
    this.constraintMode = '',
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
    this.etaConfidence = '',
    this.accessibilityRiskLevel = '',
    this.transferSlackSeconds,
    this.hasOutOfStationTransfer = false,
    this.commercialEtaEligible = false,
    this.sourceUpdatedAt = '',
    this.officialOdFareQuote,
    this.supportsRefresh = true,
    this.nextServiceTime = '',
    this.transportScope = RouteTransportScope.subway,
    this.objective = RouteObjective.fastest,
    this.departureTimeIso = '',
    this.arrivalTimeIso = '',
    this.officialFare,
  }) : // `burdenCost`는 API contract 이름이고 저장 필드는 private 값이다.
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

  factory RouteSearchResult.fromJson(
    Map<String, Object?> json, {
    String? constraintMode,
    RouteObjective objective = RouteObjective.fastest,
  }) {
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
      constraintMode: constraintMode?.trim().isNotEmpty == true
          ? constraintMode!.trim()
          : _optionalRouteString(json, 'constraintMode'),
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
      etaConfidence: _optionalRouteString(json, 'etaConfidence'),
      accessibilityRiskLevel: _optionalRouteString(
        json,
        'accessibilityRiskLevel',
      ),
      transferSlackSeconds: _optionalRouteInt(json, 'transferSlackSeconds'),
      hasOutOfStationTransfer:
          _optionalRouteBool(json, 'hasOutOfStationTransfer') ?? false,
      commercialEtaEligible:
          _optionalRouteBool(json, 'commercialEtaEligible') ?? false,
      sourceUpdatedAt: _optionalRouteString(json, 'sourceUpdatedAt'),
      nextServiceTime: _optionalRouteString(json, 'nextServiceTime'),
      transportScope: _routeTransportScopeFromValue(json['transportScope']),
      objective: objective,
    );
  }

  factory RouteSearchResult.fromV2(
    RouteSearchV2Result result, {
    RouteObjective objective = RouteObjective.fastest,
  }) {
    if (result.itineraries.isEmpty) {
      if (result.statuses.isEmpty) {
        throw const FormatException(
          'Route v2 response has neither status nor itinerary',
        );
      }
      return RouteSearchResult(
        routeSearchId:
            'route-v2-${result.originStationId}-${result.destinationStationId}-${result.departureTime}',
        originStationId: result.originStationId,
        originStationName: result.originStationId,
        destinationStationId: result.destinationStationId,
        destinationStationName: result.destinationStationId,
        mobilityType: result.mobilityType,
        constraintMode: result.constraintMode,
        status: 'BLOCKED',
        lineId: '',
        lineName: '',
        score: 0,
        burdenCost: 0,
        estimatedDurationSeconds: 0,
        walkingDistanceMeters: 0,
        transferCount: 0,
        evidenceSummary: result.statuses,
        steps: const [],
        warnings: const [],
        blockedReasons: result.statuses,
        createdAt: result.departureTime,
        etaSource: result.nextServiceTime.isEmpty ? 'UNSUPPORTED' : 'PLANNED',
        sourceUpdatedAt: result.departureTime,
        supportsRefresh: false,
        nextServiceTime: result.nextServiceTime,
        transportScope: RouteTransportScope.subwayAndItxCheongchun,
        objective: objective,
        departureTimeIso: result.departureTime,
      );
    }
    final itinerary = _selectRouteV2Itinerary(result.itineraries, objective);
    final lineId = _routeV2SummaryLineId(itinerary.legs);
    return RouteSearchResult(
      routeSearchId: _routeV2RouteSearchId(itinerary.itineraryId),
      originStationId: result.originStationId,
      originStationName: result.originStationId,
      destinationStationId: result.destinationStationId,
      destinationStationName: result.destinationStationId,
      mobilityType: result.mobilityType,
      constraintMode: result.constraintMode,
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
          : const [],
      blockedReasons: itinerary.status == 'FOUND'
          ? const []
          : itinerary.accessibilityRisk.reasonCodes.isEmpty
          ? [itinerary.status]
          : itinerary.accessibilityRisk.reasonCodes,
      createdAt: result.departureTime,
      etaSource: itinerary.etaSource,
      etaConfidence: itinerary.etaConfidence,
      accessibilityRiskLevel: itinerary.accessibilityRisk.riskLevel,
      transferSlackSeconds: _routeV2TransferSlackSeconds(itinerary.legs),
      hasOutOfStationTransfer: itinerary.legs.any(
        (leg) => leg.legType == 'OUT_OF_STATION_TRANSFER',
      ),
      commercialEtaEligible: itinerary.commercialEtaEligible,
      sourceUpdatedAt: result.departureTime,
      supportsRefresh: false,
      transportScope: RouteTransportScope.subwayAndItxCheongchun,
      objective: objective,
      departureTimeIso: result.departureTime,
      arrivalTimeIso:
          itinerary.realtimeArrivalTime ?? itinerary.plannedArrivalTime,
      officialFare: itinerary.officialFare,
    );
  }

  final String routeSearchId;
  final String originStationId;
  final String originStationName;
  final String destinationStationId;
  final String destinationStationName;
  final String mobilityType;
  final String constraintMode;
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
  final String etaConfidence;
  final String accessibilityRiskLevel;
  final int? transferSlackSeconds;
  final bool hasOutOfStationTransfer;
  final bool commercialEtaEligible;
  final String sourceUpdatedAt;
  final OfficialOdFareQuote? officialOdFareQuote;
  final bool supportsRefresh;
  final String nextServiceTime;
  final RouteTransportScope transportScope;
  final RouteObjective objective;
  final String departureTimeIso;
  final String arrivalTimeIso;
  final RouteSearchOfficialFare? officialFare;

  bool get hasOfficialOdFareQuote => officialOdFareQuote != null;

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
    return [
      ...blockedReasons.map(_routeBlockedReasonLabel),
      if (nextServiceTime.isNotEmpty)
        _routeNextServiceTimeLabel(nextServiceTime),
    ];
  }

  String get stairAccessLabel {
    if (steps.any((step) => _routeStepStairState(step) == 'stairOnly')) {
      return '계단 포함';
    }
    if (steps.isNotEmpty &&
        steps.every((step) => _routeStepStairState(step) == 'stepFree')) {
      return '계단 없는 길이에요';
    }
    return '계단 여부를 확인하고 있어요';
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
      _ => '경로 상태를 확인하고 있어요',
    };
  }

  String get scoreLabel => burdenLevelLabel;

  String get lineLabel => lineName.isEmpty ? '노선 미확인' : lineName;

  bool get isBlocked => status == 'BLOCKED';

  bool get needsConfirmation => !isBlocked && status != 'FOUND';

  bool get isLocalResult => routeSearchId.startsWith('local-');

  String get sourceNotice {
    if (isLocalResult && etaSource == 'STATIC_LOCAL') {
      final updatedAt = sourceUpdatedAt.trim();
      final freshness = updatedAt.isEmpty
          ? ''
          : ' · ${_routeDateLabel(updatedAt)}';
      return '예상 소요시간: 저장된 데이터 기준$freshness';
    }
    return '예상 소요시간: ${routeEtaSourceLabel(etaSource)}';
  }

  /// #1933 E: 결과-우선 헤더용 짧은 안내. 강등 사다리의 정직함(저장된 데이터
  /// 기준·실시간/시간표 미표기)은 그대로 두되, "예상 소요시간:" 접두와 긴 날짜
  /// 문장을 떼어 작은 캡션 한 줄로 만든다. 시맨틱·기타 문맥은 `sourceNotice` 유지.
  String get sourceNoticeCaption => routeEtaSourceLabel(etaSource);

  String get etaBadgeLabel => routeEtaSourceLabel(etaSource);

  String get accessibilityBadgeLabel {
    if (isBlocked) {
      return '엘리베이터 상태를 살펴봐 주세요';
    }
    final risk = accessibilityRiskLevel.trim().toUpperCase();
    if (risk == 'HIGH' ||
        risk == 'UNKNOWN' ||
        steps.any((step) => step.requiresAccessibilityCheck)) {
      return '엘리베이터 상태를 살펴봐 주세요';
    }
    if (stairAccessLabel == '계단 없는 길이에요') {
      return '계단 없는 경로 확인';
    }
    return '일부 이동 정보를 살펴봐 주세요';
  }

  String get transferBadgeLabel {
    if (hasOutOfStationTransfer) {
      return '역 밖 환승';
    }
    final slackSeconds = transferSlackSeconds;
    if (slackSeconds == null) {
      return '';
    }
    return slackSeconds <= 90 ? '환승 빠듯함' : '환승 여유 충분';
  }

  List<String> get badgeLabels {
    return [
      etaBadgeLabel,
      accessibilityBadgeLabel,
      transferBadgeLabel,
    ].where((label) => label.trim().isNotEmpty).toList(growable: false);
  }

  RouteSearchResult withDisplayLabels({
    String? originStationName,
    String? destinationStationName,
    String? lineName,
    List<RouteSearchStep>? steps,
    String? etaSource,
    OfficialOdFareQuote? officialOdFareQuote,
    RouteObjective? objective,
  }) {
    return RouteSearchResult(
      routeSearchId: routeSearchId,
      originStationId: originStationId,
      originStationName: originStationName ?? this.originStationName,
      destinationStationId: destinationStationId,
      destinationStationName:
          destinationStationName ?? this.destinationStationName,
      mobilityType: mobilityType,
      constraintMode: constraintMode,
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
      etaConfidence: etaConfidence,
      accessibilityRiskLevel: accessibilityRiskLevel,
      transferSlackSeconds: transferSlackSeconds,
      hasOutOfStationTransfer: hasOutOfStationTransfer,
      commercialEtaEligible: commercialEtaEligible,
      sourceUpdatedAt: sourceUpdatedAt,
      officialOdFareQuote: officialOdFareQuote ?? this.officialOdFareQuote,
      supportsRefresh: supportsRefresh,
      nextServiceTime: nextServiceTime,
      transportScope: transportScope,
      objective: objective ?? this.objective,
      departureTimeIso: departureTimeIso,
      arrivalTimeIso: arrivalTimeIso,
      officialFare: officialFare,
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

  // 여러 주의 코드를 케이스별 카드로 누적하지 않고 각주 한 줄로 합친다(#1577).
  // 같은 문구는 한 번만 남긴다.
  String get warningNoticeText {
    if (warnings.isEmpty) {
      return '';
    }
    final seen = <String>{};
    final messages = <String>[];
    for (final warning in warnings) {
      final message = warning.userMessage;
      if (message.isEmpty || !seen.add(message)) {
        continue;
      }
      messages.add(message);
    }
    return messages.join(' · ');
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
      ...badgeLabels,
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
      parts.add('주의 $warningNoticeText');
    }
    if (sourceNotice.isNotEmpty) {
      parts.add(sourceNotice);
    }
    final stepsForGuidance = movementSteps;
    if (stepsForGuidance.isNotEmpty) {
      parts.add(
        '이동 안내 ${stepsForGuidance.map((step) => step.semanticGuidanceLabel).join(', ')}',
      );
    }
    // 면책·주의 안내는 '안전 안내' 한 곳으로 통합한다. '이동 전 살펴보기'는
    // 같은 의미의 이중 고지라 시맨틱에서 제거한다(#1577).
    parts.add('안전 안내 $_routeSafetyGuidanceNotice');
    return parts.join(', ');
  }

  String get burdenLevelLabel {
    if (isBlocked) {
      return '이동 부담 미확인';
    }
    if (movementSteps.isEmpty) {
      return '이동 부담 미확인';
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

/// objective-tagged 대표 itinerary 중 현재 목표에 맞는 것을 고른다. 백엔드가 두
/// objective를 하나로 dedupe하면 그 하나가 두 태그를 모두 달고 있어 어느 목표에서도
/// 선택된다. FOUND itinerary가 전부 무태그(레거시)일 때만 첫 FOUND, 그마저 없으면 첫
/// itinerary로 폴백해 기존 동작을 보존한다. 태그가 하나라도 있는데 요청 objective와
/// 매칭되는 FOUND가 없으면 silent fallback(계약 위반)을 피해 payload 오류로 fail
/// closed한다(generic unavailable 흐름으로 흐른다).
RouteSearchV2Itinerary _selectRouteV2Itinerary(
  List<RouteSearchV2Itinerary> itineraries,
  RouteObjective objective,
) {
  final foundItineraries = itineraries
      .where((itinerary) => itinerary.status == 'FOUND')
      .toList(growable: false);
  for (final itinerary in foundItineraries) {
    if (itinerary.matchesObjective(objective)) {
      return itinerary;
    }
  }
  final hasTaggedFound = foundItineraries.any(
    (itinerary) => itinerary.objectiveTags.isNotEmpty,
  );
  if (hasTaggedFound) {
    throw const FormatException(
      'Route v2 FOUND itineraries missing requested objective tag',
    );
  }
  return itineraries.firstWhere(
    (candidate) => candidate.status == 'FOUND',
    orElse: () => itineraries.first,
  );
}

int _scoreFromRisk(RouteSearchV2AccessibilityRisk risk) {
  final penalty =
      risk.stairCount * 30 +
      risk.unavailableFacilityCount * 30 +
      risk.generatedConnectorCount * 15 +
      risk.unknownAccessibilityCount * 15 +
      risk.staleDataCount * 10 +
      risk.lowConfidenceCount * 10;
  return (100 - penalty).clamp(0, 100).toInt();
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

String _carDoorFacilityLabel(String facilityType) {
  return switch (facilityType.toUpperCase()) {
    'STAIR' => '계단 가까움',
    'ELEVATOR' => '엘리베이터 가까움',
    'ESCALATOR' => '에스컬레이터 가까움',
    'TRANSFER' => '빠른 환승',
    _ => '',
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
    this.plannedArrivalTimeIso = '',
    this.realtimeArrivalTimeIso = '',
    this.plannedDepartureTimeIso = '',
    this.realtimeDepartureTimeIso = '',
    this.carDoorCarNumber,
    this.carDoorDoorNumber,
    this.carDoorFacilityType = '',
    this.serviceClass,
    this.servicePattern,
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
        fallback: '',
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
      plannedArrivalTimeIso: leg.plannedArrivalTime,
      realtimeArrivalTimeIso: leg.realtimeArrivalTime ?? '',
      plannedDepartureTimeIso: leg.plannedDepartureTime,
      realtimeDepartureTimeIso: leg.realtimeDepartureTime ?? '',
      serviceClass: leg.serviceClass,
      servicePattern: leg.servicePattern,
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

  /// 하차 알림(#1766)용 절대 도착 시각(ISO). V2 승차 leg에서만 채워지고,
  /// 그 외 경로/step에서는 빈 문자열이다.
  final String plannedArrivalTimeIso;
  final String realtimeArrivalTimeIso;
  final String plannedDepartureTimeIso;
  final String realtimeDepartureTimeIso;
  final String actionTitle;
  final String actionDetail;
  final String reason;
  final List<String> evidenceSources;
  final String timeSource;
  final String distanceSource;
  final String confidenceLabel;

  /// 오프라인 로컬 catalog의 빠른 하차 안내(#2066)용. 로컬 승차 step에서만 채워지고,
  /// 데이터가 없으면 null(칸·문)·빈 문자열(시설)로 남아 안내 줄을 그리지 않는다.
  final int? carDoorCarNumber;
  final int? carDoorDoorNumber;
  final String carDoorFacilityType;

  /// 승차 leg의 운행 클래스·운행종별(실제 운행 정보). 급행 배지 노출 판단에만 쓰고,
  /// 선택 컨트롤·요청 identity에는 싣지 않는다. 승차가 아닌 step에서는 null이다.
  final String? serviceClass;
  final String? servicePattern;

  /// 승차 정보 영역에 `급행` 배지를 노출하는 유일한 조건.
  bool get isSubwayExpress =>
      serviceClass == 'SUBWAY' && servicePattern == 'EXPRESS';

  /// 승차 정보 영역에 `ITX-청춘` 서비스 식별 배지를 노출하는 유일한 조건. 별도
  /// 운임의 좌석 지정 서비스라 같은 노선의 일반 전동차와 구분해 표시한다.
  bool get isItxCheongchun => serviceClass == 'ITX_CHEONGCHUN';

  RouteSearchStep withDisplayLabels({
    required String title,
    required String lineName,
    required String actionDetail,
    String? plannedArrivalTimeIso,
    String? realtimeArrivalTimeIso,
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
      plannedArrivalTimeIso:
          plannedArrivalTimeIso ?? this.plannedArrivalTimeIso,
      realtimeArrivalTimeIso:
          realtimeArrivalTimeIso ?? this.realtimeArrivalTimeIso,
      plannedDepartureTimeIso: plannedDepartureTimeIso,
      realtimeDepartureTimeIso: realtimeDepartureTimeIso,
      carDoorCarNumber: carDoorCarNumber,
      carDoorDoorNumber: carDoorDoorNumber,
      carDoorFacilityType: carDoorFacilityType,
      serviceClass: serviceClass,
      servicePattern: servicePattern,
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
      if (requiresAccessibilityCheck) '엘리베이터 안내 미확인',
    ];
    return labels.join(' · ');
  }

  bool get hasCarDoorHint =>
      carDoorCarNumber != null && carDoorDoorNumber != null;

  String get carDoorHintLabel {
    final suffix = _carDoorFacilityLabel(carDoorFacilityType);
    final base = '빠른 하차 $carDoorCarNumber-$carDoorDoorNumber칸';
    return suffix.isEmpty ? base : '$base · $suffix';
  }

  String get carDoorHintSemanticLabel {
    final suffix = _carDoorFacilityLabel(carDoorFacilityType);
    final base = '빠른 하차 $carDoorCarNumber번 칸 $carDoorDoorNumber번 문';
    return suffix.isEmpty ? base : '$base, $suffix';
  }

  String get semanticGuidanceLabel {
    final safeReason = _routeStepReasonLabel(reason);
    final labels = <String>[
      '$sequence번 ${stepType == 'waypoint' ? userTitle : (userActionTitle.isEmpty ? userTitle : userActionTitle)}',
      _routeStepDetailLabel(stepType: stepType),
      if (safeReason.isNotEmpty) safeReason,
      if (stepType != 'waypoint') burdenLabel,
      if (stepType != 'waypoint' && confidenceLabel.isNotEmpty) confidenceLabel,
      if (stepType != 'waypoint' && hasMetricSourceMetadata) metricSourceLabel,
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
      'waypoint' => false,
      _ => requiresAccessibilityCheck,
    };
  }

  String get metricSourceLabel {
    if (!hasMetricSourceMetadata) {
      return '';
    }
    if (timeSource == 'ESTIMATED_CONSTANT' ||
        distanceSource == 'ESTIMATED_CONSTANT') {
      // 값만 남긴다. 예상치임의 면책은 결과 하단 안전 안내 각주 1줄이 담당(#1577).
      return '예상 시간·거리예요';
    }
    if (timeSource == 'UNKNOWN' || distanceSource == 'UNKNOWN') {
      return '시간·거리 정보 미확인';
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
    return '시간 미확인';
  }
  return '약 $estimatedMinutes분';
}

String _routeDistanceLabel(int distanceMeters) {
  if (distanceMeters <= 0) {
    return '거리 미확인';
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

// 하드 블록(경로를 실제로 못 찾음)은 헤지가 아니라 결과이므로 별도 문구로 안내한다.
const _routeBlockedNoStepFreeRoute = '계단 없는 경로를 아직 찾지 못했어요.';
const _routeBlockedFacilityUnavailable = '꼭 필요한 시설을 지금 이용하기 어려워요.';
const _routeBlockedGeneric = '안내할 수 있는 경로를 아직 찾지 못했어요.';
const _routeBlockedNoTimetableService = '이 시간에는 운행하는 열차가 없어요.';

String _routeBlockedReasonLabel(String reason) {
  final normalizedReason = reason.trim().replaceAll('못했습니다.', '못했어요.');
  return switch (normalizedReason) {
    // 하드 블록.
    'STAIR_ONLY_ACCESS' => _routeBlockedNoStepFreeRoute,
    'FACILITY_UNAVAILABLE' => _routeBlockedFacilityUnavailable,
    'NO_TIMETABLE_SERVICE' => _routeBlockedNoTimetableService,
    // 불확실성 계열은 헤지 사전 한 벌로 위임한다(#1577).
    'STAIR_ONLY_ACCESS_UNKNOWN' => routeHedgeStepFreeUnknown,
    'GENERATED_CONNECTOR_UNVERIFIED' ||
    'ROUTE_GRAPH_UNKNOWN' => routeHedgeConnectivityUnknown,
    'ACCESSIBILITY_STATE_UNKNOWN' => routeHedgeAccessibilityUnknown,
    // 이미 번역된 라벨(레거시·재매핑·과거 문구)도 같은 사전으로 정규화해 멱등하게.
    _routeBlockedNoStepFreeRoute ||
    '계단 없는 경로를 찾지 못했어요.' => _routeBlockedNoStepFreeRoute,
    _routeBlockedFacilityUnavailable ||
    '필수 접근성 시설을 사용할 수 없습니다.' => _routeBlockedFacilityUnavailable,
    routeHedgeStepFreeUnknown ||
    '계단 없는 길인지 아직 알 수 없어요.' ||
    '계단 없는 동선 여부를 확인할 수 없습니다.' => routeHedgeStepFreeUnknown,
    routeHedgeAccessibilityUnknown ||
    '엘리베이터와 통로 상태를 아직 알 수 없어요.' ||
    '접근성 시설 이용 가능 여부를 확인할 수 없습니다.' => routeHedgeAccessibilityUnknown,
    routeHedgeConnectivityUnknown ||
    '길이 이어지는지 아직 확인하지 못했어요.' ||
    '경로 연결 정보를 확인할 수 없습니다.' => routeHedgeConnectivityUnknown,
    _ => _routeBlockedGeneric,
  };
}

String _routeNextServiceTimeLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.length < 16) {
    return '다음 운행 시각을 확인해 주세요.';
  }
  return '다음 운행 ${trimmed.substring(0, 10)} ${trimmed.substring(11, 16)}';
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
    'waypoint' => '내리지 않고 이 역을 지나가요',
    _ => '안내된 순서대로 이동합니다.',
  };
}

bool _isRouteTransferStepType(String stepType) {
  return stepType == 'transfer' ||
      stepType == 'inStationTransfer' ||
      stepType == 'outOfStationTransfer';
}

int? _routeV2TransferSlackSeconds(List<RouteSearchV2Leg> legs) {
  final transferSlacks = legs
      .where(
        (leg) =>
            leg.legType == 'TRANSFER' ||
            leg.legType == 'IN_STATION_TRANSFER' ||
            leg.legType == 'LEGACY_TRANSFER' ||
            leg.legType == 'OUT_OF_STATION_TRANSFER',
      )
      .map((leg) => leg.slackSeconds)
      .toList(growable: false);
  if (transferSlacks.isEmpty) {
    return null;
  }
  transferSlacks.sort();
  return transferSlacks.first;
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

  String get userMessage => routeWarningLabel(code);
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

class RouteRefreshOutcome {
  const RouteRefreshOutcome({
    required this.result,
    required this.refreshed,
    required this.alarmRefreshRequired,
  });

  final RouteSearchResult? result;
  final bool refreshed;
  final bool alarmRefreshRequired;
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

  Future<RouteRefreshOutcome> refreshCurrentRoute() async {
    if (_disposed) {
      return RouteRefreshOutcome(
        result: _state.result,
        refreshed: false,
        alarmRefreshRequired: false,
      );
    }
    final currentResult = _state.result;
    if (_state.status != RouteSearchViewStatus.success ||
        currentResult == null ||
        currentResult.isLocalResult ||
        !currentResult.supportsRefresh ||
        _state.isRefreshing) {
      return RouteRefreshOutcome(
        result: currentResult,
        refreshed: false,
        alarmRefreshRequired: false,
      );
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
        return RouteRefreshOutcome(
          result: _state.result,
          refreshed: false,
          alarmRefreshRequired: false,
        );
      }
      final refreshedResult = _preserveGetOffAlarmArrivalTimes(
        next: refreshed.result,
        previous: currentResult,
      );
      _emitState(
        RouteSearchState(
          status: RouteSearchViewStatus.success,
          result: refreshedResult,
          refreshMessage: refreshed.userMessage,
        ),
      );
      return RouteRefreshOutcome(
        result: refreshedResult,
        refreshed: true,
        alarmRefreshRequired: true,
      );
    } on RouteSearchException catch (error) {
      if (staleRefresh()) {
        return RouteRefreshOutcome(
          result: _state.result,
          refreshed: false,
          alarmRefreshRequired: false,
        );
      }
      _emitState(
        _state.copyWith(isRefreshing: false, refreshMessage: error.message),
      );
      return RouteRefreshOutcome(
        result: _state.result,
        refreshed: false,
        alarmRefreshRequired: true,
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '경로 ETA refresh 처리 중 예외가 발생했습니다.',
      );
      if (staleRefresh()) {
        return RouteRefreshOutcome(
          result: _state.result,
          refreshed: false,
          alarmRefreshRequired: false,
        );
      }
      _emitState(
        _state.copyWith(
          isRefreshing: false,
          refreshMessage: _routeRefreshErrorMessage,
        ),
      );
      return RouteRefreshOutcome(
        result: _state.result,
        refreshed: false,
        alarmRefreshRequired: true,
      );
    }
  }

  bool rollbackRefreshAfterAlarmFailure({
    required RouteSearchState previousState,
    required RouteSearchResult expectedCurrentResult,
    required String refreshMessage,
  }) {
    if (_disposed || !identical(_state.result, expectedCurrentResult)) {
      return false;
    }
    _emitState(
      previousState.copyWith(
        isRefreshing: false,
        refreshMessage: refreshMessage,
      ),
    );
    return true;
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
    this.adRepository,
    this.simpleViewEnabled = true,
    this.itxTransportScopeEnabled = const bool.fromEnvironment(
      'EASYSUBWAY_ROUTE_V2_ONLINE_FIRST_ENABLED',
      defaultValue: false,
    ),
    this.initialDraft,
    this.initialTransportScope = RouteTransportScope.subway,
    this.shellNavigationBar,
    this.onShellBackToHome,
    this.getOffAlarmController,
    this.routeShareInvoker,
    String? initialMobilityType,
    super.key,
  }) : initialMobilityType = _resolveInitialMobilityType(initialMobilityType);

  final RouteSearchRepository repository;
  final StationSearchRepository stationRepository;
  final RouteFeedbackRepository? routeFeedbackRepository;
  final FavoriteRouteRepository? favoriteRouteRepository;
  final AdRepository? adRepository;
  final GetOffAlarmController? getOffAlarmController;
  final RouteShareInvoker? routeShareInvoker;
  final RouteDraft? initialDraft;
  final RouteTransportScope initialTransportScope;
  final Widget? shellNavigationBar;
  final VoidCallback? onShellBackToHome;
  final String initialMobilityType;
  final bool simpleViewEnabled;
  final bool itxTransportScopeEnabled;

  @override
  State<RouteSearchScreen> createState() => _RouteSearchScreenState();
}

String _resolveInitialMobilityType(String? mobilityType) {
  const standardMobilityType = 'STANDARD';
  if (mobilityType == null) {
    return standardMobilityType;
  }

  // 서버에 보내는 이동 조건은 프리셋 대표 이동 유형으로만 제한한다.
  final preset = mobilityPresetFromRepresentativeMobilityType(mobilityType);
  return preset == null
      ? standardMobilityType
      : mobilityPresetRepresentativeMobilityType(preset);
}

class _RouteSearchScreenState extends State<RouteSearchScreen>
    with WidgetsBindingObserver {
  late final RouteSearchController _controller;
  StationSearchResult? _originStation;
  StationSearchResult? _destinationStation;
  StationSearchResult? _waypointStation;
  _RouteStationRole? _activeStationPicker;
  late MobilityPreset _selectedPreset;
  late String _selectedMobilityType;
  late String _selectedConstraintMode;
  late RouteTransportScope _selectedTransportScope;
  // objective/scope 선택은 현재 검색 화면 lifecycle 동안만 유지하고 app restart에
  // 영속화하지 않는다. 기본값은 FASTEST(+ SUBWAY).
  RouteObjective _selectedObjective = RouteObjective.fastest;
  String _validationMessage = '';

  /// #1933 C: 출발·도착이 모두 채워진 draft로 진입하면 별도 "길찾기" 버튼을 누르지
  /// 않아도 자동으로 결과 타임라인까지 연결한다. 같은 draft로 중복 검색이 돌지
  /// 않도록 마지막으로 자동 검색한 조합의 서명을 기억한다. 사용자가 역을 바꾸거나
  /// 되돌아와 다시 완성하면 서명이 달라져 새로 자동 검색한다.
  String? _autoSearchedSignature;

  /// #1933 D: 검색이 성공해 실제 이동 경로(타임라인)가 화면에 있는 상태. 이때만 화면을
  /// "결과-우선"으로 재구성한다(하단 중복 "길찾기" 버튼 제거, 이동 조건·계단 토글을
  /// 조용한 칩으로 강등, 이동 순서 타임라인 인라인 노출).
  ///
  /// blocked 결과는 안내할 경로가 없어 사용자가 역·조건을 바꿔 다시 찾아야 하므로
  /// 결과-우선이 아니라 입력 폼(하단 "길찾기" 버튼 포함)을 그대로 유지한다.
  bool get _hasResult {
    final state = _controller.state;
    return state.status == RouteSearchViewStatus.success &&
        state.result != null &&
        !state.result!.isBlocked;
  }

  /// #1933 요구 3: 노선도가 유일한 허브다. 별도 길찾기 폼 페이지는 없앴으므로,
  /// 이 화면에 도달하는 정당한 경로는 출발·도착이 모두 채워진 draft(자동 검색)뿐이다.
  bool get _hasCompleteDraft =>
      _originStation != null && _destinationStation != null;

  bool get _itxTransportScopeAvailable =>
      widget.itxTransportScopeEnabled &&
      _selectedMobilityType != 'WHEELCHAIR' &&
      _selectedConstraintMode != 'STRICT_STEP_FREE';

  /// 완성된 draft 없이(=출발·도착 미완) 이 화면에 들어온 경우, 폼을 보여주지 않고
  /// 곧바로 노선도로 되돌린다. 리다이렉트를 한 번만 예약하기 위한 플래그.
  bool _redirectToMapScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = RouteSearchController(repository: widget.repository);
    _originStation = _stationFromDraft(widget.initialDraft?.origin);
    _destinationStation = _stationFromDraft(widget.initialDraft?.destination);
    _waypointStation = _stationFromDraft(widget.initialDraft?.waypoint);
    _selectedPreset =
        mobilityPresetFromRepresentativeMobilityType(
          widget.initialMobilityType,
        ) ??
        MobilityPreset.standard;
    _applyPresetDerivedState(_selectedPreset);
    _selectedTransportScope = _itxTransportScopeAvailable
        ? widget.initialTransportScope
        : RouteTransportScope.subway;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoSearchFromDraft();
    });
  }

  @override
  void didUpdateWidget(RouteSearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 노선도 오버레이에서 출발·도착을 새로 완성해 다시 진입하면(같은 탭 재빌드)
    // 갱신된 draft로 자동 검색을 이어간다.
    if (!identical(widget.initialDraft, oldWidget.initialDraft)) {
      final draft = widget.initialDraft;
      _originStation = _stationFromDraft(draft?.origin);
      _destinationStation = _stationFromDraft(draft?.destination);
      _waypointStation = _stationFromDraft(draft?.waypoint);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeAutoSearchFromDraft();
      });
    }
    if (widget.initialTransportScope != oldWidget.initialTransportScope ||
        widget.itxTransportScopeEnabled != oldWidget.itxTransportScopeEnabled) {
      _selectedTransportScope = _itxTransportScopeAvailable
          ? widget.initialTransportScope
          : RouteTransportScope.subway;
      _autoSearchedSignature = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeAutoSearchFromDraft();
      });
    }
  }

  /// draft에 출발·도착이 모두 있으면 현재 이동 조건·계단 토글 상태로 자동 검색한다.
  /// 이미 같은 조합을 자동 검색했다면(로딩·성공 상태 유지 중) 다시 돌리지 않는다.
  String? _draftSignature() {
    final origin = _originStation;
    final destination = _destinationStation;
    if (origin == null || destination == null) {
      return null;
    }
    final waypoint = _waypointStation;
    final waypointSegment = waypoint == null ? '' : '${waypoint.id} ';
    return '${origin.id} $waypointSegment${destination.id} '
        '$_selectedMobilityType $_selectedConstraintMode '
        '${_selectedTransportScope.serverValue} ${_selectedObjective.serverValue}';
  }

  void _maybeAutoSearchFromDraft() {
    if (!mounted) {
      return;
    }
    final signature = _draftSignature();
    if (signature == null || signature == _autoSearchedSignature) {
      return;
    }
    if (_controller.state.status == RouteSearchViewStatus.loading) {
      return;
    }
    // 하차 알림이 켜진 채로는 자동 검색이 진행 중인 이동을 조용히 취소해 버릴 수
    // 있으므로, 이때는 자동 검색하지 않고 사용자가 직접 "길찾기"를 누르게 둔다.
    if (widget.getOffAlarmController?.state.enabled ?? false) {
      return;
    }
    _autoSearchedSignature = signature;
    unawaited(_submit());
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
      unawaited(_refreshCurrentRouteAndAlarm());
    }
  }

  Future<void> _refreshCurrentRouteAndAlarm() async {
    final previousState = _controller.state;
    final outcome = await _controller.refreshCurrentRoute();
    if (!mounted) {
      return;
    }
    if (!outcome.alarmRefreshRequired) {
      return;
    }
    final getOffAlarmController = widget.getOffAlarmController;
    final result = outcome.result;
    if (getOffAlarmController == null ||
        !getOffAlarmController.state.enabled ||
        result == null) {
      return;
    }
    if (getOffAlarmController.state.activeRouteId != result.routeSearchId) {
      return;
    }
    final rideLegs = _rideLegArrivalsFromResult(result);
    final source =
        outcome.refreshed &&
            rideLegs.any((leg) => leg.realtimeArrivalIso?.isNotEmpty ?? false)
        ? GetOffAlarmTimeSource.realtime
        : GetOffAlarmTimeSource.planned;
    try {
      final activeSubscription = await getOffAlarmController.repository
          .loadActive();
      if (!mounted ||
          !getOffAlarmController.state.enabled ||
          getOffAlarmController.state.activeRouteId != result.routeSearchId ||
          activeSubscription?.routeId != result.routeSearchId) {
        return;
      }
      final stationNames = <String, String>{};
      for (final leg in rideLegs) {
        final stationId = leg.toStationId;
        if (stationNames.containsKey(stationId)) {
          continue;
        }
        final stationName = await _resolveGetOffAlarmStationName(
          stationId: stationId,
          stationRepository: widget.stationRepository,
        );
        if (stationName == null) {
          throw StateError('하차 알림 역명을 확인하지 못했습니다.');
        }
        stationNames[stationId] = stationName;
      }
      if (!mounted ||
          !identical(_controller.state.result, result) ||
          !getOffAlarmController.state.enabled) {
        return;
      }
      final stops = getOffAlarmStopsFromRideLegs(
        rideLegs: rideLegs,
        stationName: (id) => stationNames[id]!,
        source: source,
      );
      final previousArrivalAt = activeSubscription?.destination.arrivalAt;
      final deltaSeconds = previousArrivalAt == null || stops.isEmpty
          ? 0
          : stops.last.arrivalAt.difference(previousArrivalAt).inSeconds;
      final changed =
          previousArrivalAt != null && stops.isNotEmpty && deltaSeconds != 0;
      final refreshResult = await getOffAlarmController.refresh(
        routeId: result.routeSearchId,
        stops: stops,
      );
      if (refreshResult == GetOffAlarmRefreshResult.routeMismatch) {
        return;
      }
      if (kDebugMode && getOffAlarmController.state.enabled) {
        debugPrint(
          'get_off_alarm foreground_refresh changed=$changed '
          'delta_seconds=$deltaSeconds source=${source.name} '
          'mode=${getOffAlarmController.state.scheduleMode?.name} '
          'scheduled_count=${getOffAlarmController.state.scheduledCount}',
        );
      }
    } catch (error, stackTrace) {
      final rolledBack =
          outcome.refreshed &&
          _rollbackRouteAfterAlarmFailure(
            previousState: previousState,
            expectedCurrentResult: result,
          );
      reportMobileError(
        error,
        stackTrace,
        context: '하차 알림 foreground 재예약 중 예외가 발생했습니다.',
      );
      if (mounted && rolledBack) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text(_getOffAlarmRefreshFailureMessage)),
        );
      }
    }
  }

  bool _rollbackRouteAfterAlarmFailure({
    required RouteSearchState previousState,
    required RouteSearchResult expectedCurrentResult,
  }) {
    return _controller.rollbackRefreshAfterAlarmFailure(
      previousState: previousState,
      expectedCurrentResult: expectedCurrentResult,
      refreshMessage: _getOffAlarmRefreshRollbackMessage,
    );
  }

  /// #1933 요구 3: 완성된 draft 없이 이 화면에 도달하면(폼 페이지가 사라졌으므로)
  /// 노선도로 되돌린다. 되돌릴 셸 콜백이 없으면(직접 임베드된 경우) 폼 대신
  /// 최소한의 안내만 보여 준다.
  void _maybeRedirectToMap() {
    // 사용자가 얇은 헤더에서 출발/도착을 편집(인라인 역 검색)하는 중이면 되돌리지
    // 않는다. 잠시 한쪽이 비어도 새 역을 고르면 다시 완성되는 정상 편집 흐름이다.
    if (_hasResult ||
        _hasCompleteDraft ||
        _activeStationPicker != null ||
        _redirectToMapScheduled) {
      return;
    }
    final onShellBackToHome = widget.onShellBackToHome;
    if (onShellBackToHome == null) {
      return;
    }
    _redirectToMapScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      onShellBackToHome();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // #1933 D: 검색이 성공하면 결과-우선 화면으로 재구성한다. 이동 조건·계단 토글을
        // 상단의 조용한 칩으로 강등하고, 이동 순서 타임라인을 결과 안에 인라인으로 편다.
        final hasResult = _hasResult;
        // #1933 요구 3: 별도 길찾기 폼 페이지는 제거됐다. 완성된 draft 없이(=출발·도착
        // 미완) 이 화면에 들어오면 폼을 보여 주지 않고 노선도로 되돌린다.
        _maybeRedirectToMap();
        // 편집 중(인라인 역 검색 열림)이면 얇은 헤더 화면을 유지해 새 역을 고르게
        // 한다. 그 외에 결과도 완성된 draft도 없으면 폼 대신 안내만 보여 준다.
        if (!hasResult && !_hasCompleteDraft && _activeStationPicker == null) {
          return _RouteSearchEmptyRedirect(
            shellNavigationBar: widget.shellNavigationBar,
          );
        }
        return Scaffold(
          key: const Key('routeSearchScreen'),
          appBar: AppBar(title: const Text('길찾기')),
          bottomNavigationBar: widget.shellNavigationBar,
          body: Semantics(
            container: true,
            child: SafeArea(
              child: RefreshIndicator(
                key: const Key('routeResultRefreshIndicator'),
                onRefresh: _refreshCurrentRouteAndAlarm,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: _routeSearchPagePadding,
                  children: [
                    _RoutePointPickerCard(
                      key: const Key('routePointPickerCard'),
                      // #1933 요구 3: 폼이 사라졌으므로 항상 얇은 헤더로 축소한다.
                      // 역명 탭 → 인라인 역 검색으로 편집(→ 재검색)만 남긴다.
                      compact: true,
                      originStation: _originStation,
                      destinationStation: _destinationStation,
                      originPicker:
                          _activeStationPicker == _RouteStationRole.origin
                          ? _buildRouteStationPicker(_RouteStationRole.origin)
                          : null,
                      destinationPicker:
                          _activeStationPicker == _RouteStationRole.destination
                          ? _buildRouteStationPicker(
                              _RouteStationRole.destination,
                            )
                          : null,
                      onOriginTap: () =>
                          _openStationPicker(_RouteStationRole.origin),
                      onDestinationTap: () =>
                          _openStationPicker(_RouteStationRole.destination),
                      onSwap: _swapStations,
                    ),
                    const SizedBox(height: 18),
                    if (_validationMessage.isNotEmpty) ...[
                      _RouteSearchMessage(
                        message: _validationMessage,
                        liveRegion: true,
                      ),
                      const SizedBox(height: 16),
                    ],
                    // 현재 보행 프리셋은 언제나 조용한 칩 한 개로만 노출한다.
                    // 바꾸면 그 자리에서 바로 재검색한다(별도 폼·버튼 없음).
                    _RouteConditionChips(
                      preset: _selectedPreset,
                      objective: _selectedObjective,
                      transportScope: _selectedTransportScope,
                      itxTransportScopeEnabled: _itxTransportScopeAvailable,
                      loading:
                          _controller.state.status ==
                          RouteSearchViewStatus.loading,
                      onChangePreset: _showMobilityPresetPicker,
                      onChangeObjective: _changeObjective,
                      onChangeTransportScope: _changeTransportScope,
                    ),
                    _RouteSearchBody(
                      state: _controller.state,
                      onSearchSubwayOnly:
                          _selectedTransportScope ==
                              RouteTransportScope.subwayAndItxCheongchun
                          ? () => _changeTransportScope(
                              RouteTransportScope.subway,
                            )
                          : null,
                      routeFeedbackRepository: widget.routeFeedbackRepository,
                      favoriteRouteRepository: widget.favoriteRouteRepository,
                      adRepository: widget.adRepository,
                      onShellBackToHome: widget.onShellBackToHome == null
                          ? null
                          : _endRoute,
                      getOffAlarmController: widget.getOffAlarmController,
                      stationRepository: widget.stationRepository,
                      routeShareInvoker: widget.routeShareInvoker,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
          onPopInvokedWithResult: (didPop, _) async {
            if (!didPop) {
              await _endRoute();
            }
          },
          child: child!,
        );
      },
    );
  }

  Future<bool> _disableActiveGetOffAlarm() async {
    final getOffAlarmController = widget.getOffAlarmController;
    if (getOffAlarmController == null) {
      return true;
    }
    try {
      await getOffAlarmController.disable();
      return true;
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '하차 알림 취소 중 예외가 발생했습니다.');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('하차 알림을 취소하지 못했어요. 다시 시도해 주세요.')),
        );
      }
      return false;
    }
  }

  Future<void> _endRoute() async {
    if (!await _disableActiveGetOffAlarm()) {
      return;
    }
    if (!mounted) {
      return;
    }
    _controller.reset();
    widget.onShellBackToHome?.call();
  }

  /// [alarmAlreadyDisabled]가 true면 호출자가 이미 활성 하차 알림을 취소했으므로
  /// 여기서 다시 취소하지 않는다(#1933 D: 이동 조건 칩 재검색 시 이중 취소 방지).
  Future<void> _submit({bool alarmAlreadyDisabled = false}) async {
    if (_controller.state.status == RouteSearchViewStatus.loading) {
      return;
    }
    if (_originStation == null || _destinationStation == null) {
      if (!alarmAlreadyDisabled && !await _disableActiveGetOffAlarm()) {
        return;
      }
      if (!mounted) {
        return;
      }
      _controller.reset();
      setState(() {
        _validationMessage = '출발역과 도착역을 검색 결과에서 선택해 주세요.';
      });
      return;
    }
    if (_selectedTransportScope == RouteTransportScope.subwayAndItxCheongchun &&
        _waypointStation != null) {
      _controller.reset();
      setState(() {
        _validationMessage = 'ITX-청춘 경로는 경유역을 지원하지 않아요. 경유역을 빼거나 지하철만 이용해 주세요.';
      });
      return;
    }
    if (_selectedTransportScope == RouteTransportScope.subwayAndItxCheongchun &&
        !_itxTransportScopeAvailable) {
      _controller.reset();
      setState(() {
        _selectedTransportScope = RouteTransportScope.subway;
        _validationMessage = '선택한 이동 조건에서는 지하철 경로만 이용할 수 있어요.';
      });
      return;
    }
    setState(() {
      _validationMessage = '';
    });
    if (!alarmAlreadyDisabled && !await _disableActiveGetOffAlarm()) {
      return;
    }
    if (!mounted) {
      return;
    }

    // 화면에는 역 이름을 보여주지만 API에는 안정적인 station id만 전달한다.
    await _controller.search(
      RouteSearchRequest(
        originStationId: _originStation!.id,
        destinationStationId: _destinationStation!.id,
        mobilityType: _selectedMobilityType,
        constraintMode: _selectedConstraintMode,
        waypointStationId: _waypointStation?.id,
        mobilityPreset: mobilityPresetServerString(_selectedPreset),
        transportScope: _selectedTransportScope,
        objective: _selectedObjective,
      ),
    );
  }

  Future<void> _changeObjective(RouteObjective objective) async {
    if (objective == _selectedObjective ||
        _controller.state.status == RouteSearchViewStatus.loading) {
      return;
    }
    if (!await _disableActiveGetOffAlarm()) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedObjective = objective;
      _autoSearchedSignature = null;
    });
    await _submit(alarmAlreadyDisabled: true);
  }

  Future<void> _changeTransportScope(RouteTransportScope scope) async {
    if (scope == _selectedTransportScope ||
        _controller.state.status == RouteSearchViewStatus.loading) {
      return;
    }
    if (scope == RouteTransportScope.subwayAndItxCheongchun &&
        _waypointStation != null) {
      setState(() {
        _validationMessage = 'ITX-청춘 경로는 경유역을 지원하지 않아요. 경유역을 빼거나 지하철만 이용해 주세요.';
      });
      return;
    }
    if (!await _disableActiveGetOffAlarm()) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedTransportScope = scope;
      _autoSearchedSignature = null;
    });
    await _submit(alarmAlreadyDisabled: true);
  }

  Widget _buildRouteStationPicker(_RouteStationRole role) {
    final isOrigin = role == _RouteStationRole.origin;
    return _RouteStationPicker(
      isOrigin: isOrigin,
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

  Future<void> _updateOriginStation(StationSearchResult? station) async {
    if (!await _disableActiveGetOffAlarm()) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _originStation = station;
      if (station != null) {
        _activeStationPicker = null;
      }
      _validationMessage = '';
    });
    _controller.reset();
  }

  Future<void> _updateDestinationStation(StationSearchResult? station) async {
    if (!await _disableActiveGetOffAlarm()) {
      return;
    }
    if (!mounted) {
      return;
    }
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

  Future<void> _swapStations() async {
    if (!await _disableActiveGetOffAlarm()) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      final origin = _originStation;
      _originStation = _destinationStation;
      _destinationStation = origin;
      _activeStationPicker = null;
      _validationMessage = '';
    });
    _controller.reset();
  }

  /// 프리셋에서 서버로 보내는 이동 유형·시설 제약을 파생한다. STANDARD는 계단
  /// 회피가 아니므로 constraintMode가 PREFER_STEP_FREE(WHEELCHAIR 프리셋만 STRICT).
  void _applyPresetDerivedState(MobilityPreset preset) {
    _selectedMobilityType = mobilityPresetRepresentativeMobilityType(preset);
    _selectedConstraintMode = RouteSearchRequest._defaultConstraintMode(
      _selectedMobilityType,
    );
  }

  /// #1933 D: 결과가 이미 보이는 상태(결과-우선 화면)에서 프리셋을 바꾸면 별도 버튼
  /// 없이 그 자리에서 바로 재검색한다. 아직 결과가 없는 입력 상태에서는 기존처럼
  /// 초기화만 하고, 사용자가 출발·도착을 마저 채우게 둔다.
  Future<void> _rerunOrResetAfterConditionChange() async {
    if (_hasResult && _originStation != null && _destinationStation != null) {
      // 자동 검색 서명을 새 조건으로 갱신해 재검색이 조용히 무시되지 않게 한다.
      _autoSearchedSignature = _draftSignature();
      // 호출자가 이미 활성 하차 알림을 취소했으니 _submit에서 다시 취소하지 않는다.
      await _submit(alarmAlreadyDisabled: true);
      return;
    }
    _controller.reset();
  }

  Future<void> _showMobilityPresetPicker() async {
    final selectedPreset = await showMobilityPresetSheet(
      context,
      current: _selectedPreset,
    );

    if (!mounted || selectedPreset == null) {
      return;
    }
    if (selectedPreset == _selectedPreset) {
      return;
    }
    if (!await _disableActiveGetOffAlarm()) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedPreset = selectedPreset;
      _applyPresetDerivedState(selectedPreset);
      if (!_itxTransportScopeAvailable) {
        _selectedTransportScope = RouteTransportScope.subway;
      }
    });
    // 결과-우선 화면에서 프리셋을 바꾸면 그 자리에서 바로 재검색한다. 활성 하차
    // 알림은 위에서 이미 취소했으므로 _submit에서 다시 취소하지 않는다.
    await _rerunOrResetAfterConditionChange();
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
    this.compact = false,
    super.key,
  });

  final StationSearchResult? originStation;
  final StationSearchResult? destinationStation;
  final Widget? originPicker;
  final Widget? destinationPicker;
  final VoidCallback onOriginTap;
  final VoidCallback onDestinationTap;
  final VoidCallback onSwap;

  /// #1933 E: 결과-우선 화면에서는 이 카드를 얇은 헤더로 강등한다(역명 작게·세로
  /// 패딩 축소). 입력 상태에서는 기존 큰 피커 크기를 그대로 둔다(false 기본).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // 출발(○)-도착(●) 노드는 각 역 행 안쪽에 두어 역명이 노드 뒤로
    // 들여써지도록 한다. 입력 피커가 열리면 해당 행의 노드는 접힌다.
    final originChild =
        originPicker ??
        _RoutePointRow(
          key: const Key('routeOriginPointButton'),
          isOrigin: true,
          station: originStation,
          fallback: '출발역 선택',
          onTap: onOriginTap,
          compact: compact,
        );
    final destinationChild =
        destinationPicker ??
        _RoutePointRow(
          key: const Key('routeDestinationPointButton'),
          isOrigin: false,
          station: destinationStation,
          fallback: '도착역 선택',
          onTap: onDestinationTap,
          compact: compact,
        );
    final rows = Column(
      children: [
        originChild,
        const Divider(
          height: 1,
          indent: _routePointRailWidth,
          color: EasySubwayAccessibleColors.line,
        ),
        destinationChild,
      ],
    );
    // v4 경량화(#1930): 큰 박스 카드·큰 원형 스왑 버튼 대신 옅은 채움 위에
    // 얇은 2줄 필드 + 좌측의 작은 스왑 아이콘(두 줄 사이 세로 중앙)으로 둔다.
    final swapButton = Semantics(
      button: true,
      label: '출발 도착 바꾸기',
      onTap: onSwap,
      child: ExcludeSemantics(
        child: IconButton(
          key: const Key('routeSwapStationsButton'),
          onPressed: onSwap,
          icon: const Icon(Icons.swap_vert, size: 20),
          color: EasySubwayAccessibleColors.text,
          style: IconButton.styleFrom(
            minimumSize: const Size(48, 48),
            backgroundColor: EasySubwayAccessibleColors.scaffoldSurface,
          ),
        ),
      ),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: EasySubwayAccessibleColors.scaffoldSurface,
        borderRadius: _routeSearchPickerRadius,
      ),
      child: Padding(
        padding: _routePointSelectorPadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            swapButton,
            const SizedBox(width: 4),
            Expanded(child: rows),
          ],
        ),
      ),
    );
  }
}

class _RoutePointNodeColumn extends StatelessWidget {
  const _RoutePointNodeColumn({required this.isOrigin});

  final bool isOrigin;

  @override
  Widget build(BuildContext context) {
    Widget connector() => Center(
      child: Container(width: 2, color: EasySubwayAccessibleColors.line),
    );
    // 출발 노드는 아래로, 도착 노드는 위로 연결선을 뻗어 두 행 사이에서 만난다.
    return SizedBox(
      width: _routePointRailWidth,
      child: Column(
        children: [
          Expanded(child: isOrigin ? const SizedBox.shrink() : connector()),
          _RoutePointNode(filled: !isOrigin),
          Expanded(child: isOrigin ? connector() : const SizedBox.shrink()),
        ],
      ),
    );
  }
}

class _RoutePointNode extends StatelessWidget {
  const _RoutePointNode({required this.filled});

  final bool filled;

  @override
  Widget build(BuildContext context) {
    const color = EasySubwayAccessibleColors.primary;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: filled ? color : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 3),
      ),
    );
  }
}

class _RoutePointRow extends StatelessWidget {
  const _RoutePointRow({
    required this.isOrigin,
    required this.station,
    required this.fallback,
    required this.onTap,
    this.compact = false,
    super.key,
  });

  final bool isOrigin;
  final StationSearchResult? station;
  final String fallback;
  final VoidCallback onTap;

  /// #1933 E: 결과-우선 헤더에서는 역명을 작게·세로 패딩을 좁혀 얇은 줄로 만든다.
  /// 노드/연결선/지도 편집 어포던스·키·시맨틱·탭 편집은 그대로 둔다.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = isOrigin ? '출발' : '도착';
    final stationName = station == null
        ? fallback
        : _routeStationDisplayName(station!);
    final semanticsLabel = station == null
        ? stationName
        : '$label $stationName';
    // 얇은 헤더에서도 편집 탭 타깃은 최소 44 이상을 유지한다(접근성).
    final verticalPadding = compact ? 10.0 : 14.0;
    final nameFontSize = compact ? 17.0 : 22.0;
    return Semantics(
      button: true,
      label: semanticsLabel,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: _routeSearchMediumRadius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RoutePointNodeColumn(isOrigin: isOrigin),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: verticalPadding),
                      child: Text(
                        stationName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: station == null
                                  ? EasySubwayAccessibleColors.mutedText
                                  : EasySubwayAccessibleColors.text,
                              fontSize: nameFontSize,
                              height: 1.2,
                            ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: verticalPadding),
                    child: const Icon(
                      Icons.map_outlined,
                      color: EasySubwayAccessibleColors.mutedText,
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

/// #1933 요구 3: 별도 길찾기 폼 페이지를 없앴다. 완성된 draft(출발·도착) 없이 이
/// 화면에 도달하면 셸이 노선도로 되돌리는 게 정상 흐름이고, 그 사이(또는 되돌릴
/// 셸이 없을 때)는 폼 대신 최소한의 안내만 보여 준다.
class _RouteSearchEmptyRedirect extends StatelessWidget {
  const _RouteSearchEmptyRedirect({this.shellNavigationBar});

  final Widget? shellNavigationBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('routeSearchScreen'),
      appBar: AppBar(title: const Text('길찾기')),
      bottomNavigationBar: shellNavigationBar,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              '지도에서 출발·도착을 정해 주세요.',
              key: const Key('routeSearchEmptyRedirectMessage'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: EasySubwayAccessibleColors.mutedText,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
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
              color: EasySubwayAccessibleColors.text,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

String _routeLineColor(String name) => fallbackLineColorHex(lineName: name);

/// 기본 레벨(LEVEL_1)·미확정 품질 필러는 목록에서 감춘다(#1477과 동일 규칙).
bool _showsRouteDataQualityLabel(String dataQualityLevel) {
  return dataQualityLevel == 'LEVEL_2' ||
      dataQualityLevel == 'LEVEL_3' ||
      dataQualityLevel == 'LEVEL_4';
}

class _RouteStationPicker extends StatefulWidget {
  const _RouteStationPicker({
    required this.isOrigin,
    required this.labelText,
    required this.inputKey,
    required this.searchButtonKey,
    required this.optionKeyPrefix,
    required this.selectedStation,
    required this.repository,
    required this.onSelected,
  });

  final bool isOrigin;
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
    // v4 전면 재설계(#1930): 활성 입력도 비활성 요약 행(_RoutePointRow)과 같은
    // 얇은 필드 언어(옅은 채움·테두리 없음)를 쓴다. 노드 열도 그대로 두어
    // 활성/비활성 전환 때 높이·정렬이 튀지 않게 한다.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RoutePointNodeColumn(isOrigin: widget.isOrigin),
              Expanded(
                child: Semantics(
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
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      labelText: labelText,
                      hintText: '역 이름을 입력해 주세요',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      filled: true,
                      fillColor: EasySubwayAccessibleColors.scaffoldSurface,
                      border: const UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: EasySubwayAccessibleColors.line,
                        ),
                      ),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: EasySubwayAccessibleColors.line,
                        ),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: EasySubwayAccessibleColors.primary,
                        ),
                      ),
                      suffixIcon: AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) {
                          final isLoading =
                              _controller.state.status ==
                              StationSearchStatus.loading;
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
              ),
            ],
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
          for (final entry in state.results.indexed) ...[
            if (entry.$1 > 0)
              const Divider(height: 1, color: EasySubwayAccessibleColors.line),
            _RouteStationOptionTile(
              key: Key('$optionKeyPrefix-${entry.$2.id}'),
              labelText: labelText,
              result: entry.$2,
              onSelected: onSelected,
            ),
          ],
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

    // v4 전면 재설계(#1930): 박스 카드 대신 역검색(#1929)과 같은 박스 없는
    // 행 + 구분선 언어로 통일한다.
    return MergeSemantics(
      child: Semantics(
        label: '$labelText 선택, ${result.semanticLabel}',
        button: true,
        onTap: () => onSelected(result),
        child: ExcludeSemantics(
          child: InkWell(
            onTap: () => onSelected(result),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
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
                              color: EasySubwayAccessibleColors.text,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 8),
                          StationLineBadges(lines: result.lines),
                          const SizedBox(height: 8),
                          Text(
                            result.lineLabel,
                            style: textTheme.bodyLarge?.copyWith(
                              color: EasySubwayAccessibleColors.secondaryText,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                          if (_showsRouteDataQualityLabel(
                            result.dataQualityLevel,
                          )) ...[
                            const SizedBox(height: 4),
                            Text(
                              result.dataQualityLabel,
                              style: textTheme.bodyMedium?.copyWith(
                                color: EasySubwayAccessibleColors.secondaryText,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.chevron_right,
                      color: EasySubwayAccessibleColors.primary,
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
    this.onSearchSubwayOnly,
    required this.routeFeedbackRepository,
    required this.favoriteRouteRepository,
    required this.adRepository,
    required this.onShellBackToHome,
    required this.getOffAlarmController,
    required this.stationRepository,
    required this.routeShareInvoker,
  });

  final RouteSearchState state;
  final AsyncCallback? onSearchSubwayOnly;
  final RouteFeedbackRepository? routeFeedbackRepository;
  final FavoriteRouteRepository? favoriteRouteRepository;
  final AdRepository? adRepository;
  final AsyncCallback? onShellBackToHome;
  final GetOffAlarmController? getOffAlarmController;
  final StationSearchRepository stationRepository;
  final RouteShareInvoker? routeShareInvoker;

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
        onSearchSubwayOnly: onSearchSubwayOnly,
      ),
      RouteSearchViewStatus.success => _RouteSearchResultCard(
        result: state.result!,
        refreshMessage: state.refreshMessage,
        isRefreshing: state.isRefreshing,
        routeFeedbackRepository: routeFeedbackRepository,
        favoriteRouteRepository: favoriteRouteRepository,
        adRepository: adRepository,
        onShellBackToHome: onShellBackToHome,
        getOffAlarmController: getOffAlarmController,
        stationRepository: stationRepository,
        routeShareInvoker: routeShareInvoker,
      ),
    };
  }
}

class _RouteSearchFailureMessage extends StatelessWidget {
  const _RouteSearchFailureMessage({
    required this.message,
    this.onSearchSubwayOnly,
  });

  final String message;
  final AsyncCallback? onSearchSubwayOnly;

  @override
  Widget build(BuildContext context) {
    final shouldShowNextAction = _shouldShowRouteSearchFailureNextAction(
      message,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RouteSearchMessage(message: message, liveRegion: true),
        if (onSearchSubwayOnly != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('routeSearchSubwayOnlyAction'),
            onPressed: onSearchSubwayOnly,
            child: const Text('지하철만 보기'),
          ),
        ],
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
                color: EasySubwayAccessibleColors.mutedText,
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
          color: EasySubwayAccessibleColors.secondaryText,
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
          border: Border.all(color: EasySubwayAccessibleColors.line),
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
                color: EasySubwayAccessibleColors.iconMuted,
                size: 22,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: EasySubwayAccessibleColors.mutedText,
                  fontWeight: FontWeight.w700,
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

class _RouteSearchResultCard extends StatefulWidget {
  const _RouteSearchResultCard({
    required this.result,
    required this.refreshMessage,
    required this.isRefreshing,
    required this.routeFeedbackRepository,
    required this.favoriteRouteRepository,
    required this.adRepository,
    required this.onShellBackToHome,
    required this.getOffAlarmController,
    required this.stationRepository,
    required this.routeShareInvoker,
  });

  final RouteSearchResult result;
  final String refreshMessage;
  final bool isRefreshing;
  final RouteFeedbackRepository? routeFeedbackRepository;
  final FavoriteRouteRepository? favoriteRouteRepository;
  final AdRepository? adRepository;
  final AsyncCallback? onShellBackToHome;
  final GetOffAlarmController? getOffAlarmController;
  final StationSearchRepository stationRepository;
  final RouteShareInvoker? routeShareInvoker;

  @override
  State<_RouteSearchResultCard> createState() => _RouteSearchResultCardState();
}

class _RouteSearchResultCardState extends State<_RouteSearchResultCard> {
  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    if (result.isBlocked) {
      return _wrapShellBack(_RouteBlockedWorkflow(result: result));
    }

    // 결과 목록만 이 화면에 남기고, 상세·안내·역 안 이동·피드백은 표준
    // 내비게이션 스택에 별도 화면으로 push한다(뒤로가기는 시스템 back에 위임).
    return _wrapShellBack(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RouteRefreshStatusBanner(
            message: widget.refreshMessage,
            isRefreshing: widget.isRefreshing,
          ),
          _RouteResultsListView(
            result: result,
            onOpenDetail: () => _openDetail(result),
            adRepository: widget.adRepository,
          ),
          if (widget.getOffAlarmController != null)
            _GetOffAlarmEntryPoint(
              controller: widget.getOffAlarmController!,
              result: result,
              stationRepository: widget.stationRepository,
            ),
        ],
      ),
    );
  }

  bool get _canUseRouteActions => _isRecommendedRoute(widget.result);
  bool get _canUseApiActions => !widget.result.isLocalResult;
  bool get _canSaveRoute =>
      _canUseApiActions &&
      widget.favoriteRouteRepository != null &&
      _canUseRouteActions;
  bool get _canOpenFeedback =>
      _canUseApiActions && widget.routeFeedbackRepository != null;

  // 목록 화면에서 시스템 back은 탭 셸 홈으로(탭 셸이 아닐 땐 화면 pop).
  Widget _wrapShellBack(Widget content) {
    final onShellBackToHome = widget.onShellBackToHome;
    if (onShellBackToHome == null) {
      return content;
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          await onShellBackToHome();
        }
      },
      child: content,
    );
  }

  void _pushStage(Widget child) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _RouteStageScaffold(child: child),
      ),
    );
  }

  void _openDetail(RouteSearchResult result) {
    _pushStage(
      _RouteDetailWorkflowView(
        result: result,
        onBack: () => Navigator.of(context).pop(),
        onStartGuidance: !_canUseRouteActions
            ? null
            : () => _openGuidance(result),
        onOpenFeedback: !_canOpenFeedback ? null : () => _openFeedback(result),
        favoriteSaveButton: _canSaveRoute
            ? _RouteFavoriteSaveButton(
                result: result,
                repository: widget.favoriteRouteRepository!,
              )
            : null,
        adRepository: widget.adRepository,
        routeShareInvoker: widget.routeShareInvoker,
      ),
    );
  }

  void _openGuidance(RouteSearchResult result) {
    _pushStage(
      _RouteGuidanceWorkflowView(
        result: result,
        onBack: () => Navigator.of(context).pop(),
        onOpenInternalRoute: () => _openInternal(result),
        onOpenBlocked: !_canOpenFeedback ? null : () => _openFeedback(result),
        onOpenFeedback: !_canOpenFeedback ? null : () => _openFeedback(result),
      ),
    );
  }

  void _openInternal(RouteSearchResult result) {
    _pushStage(
      _RouteInternalWorkflowView(
        result: result,
        onBack: () => Navigator.of(context).pop(),
      ),
    );
  }

  void _openFeedback(RouteSearchResult result) {
    _pushStage(
      _RouteFeedbackWorkflowView(
        result: result,
        repository: widget.routeFeedbackRepository,
        onBack: () => Navigator.of(context).pop(),
      ),
    );
  }
}

/// push된 길찾기 단계(상세·안내·역 안 이동·피드백) 화면 껍데기.
/// 시스템 back과 각 뷰의 상단 back 버튼이 이 라우트를 pop한다.
class _RouteStageScaffold extends StatelessWidget {
  const _RouteStageScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EasySubwayAccessibleColors.scaffoldSurface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: child,
        ),
      ),
    );
  }
}

/// 하차 알림(#1766) 임시 진입점. 경로 결과의 승차 step을 도착역·도착시각으로
/// 투영해 하차 알림 토글에 넘긴다. 승차 step에 절대 도착시각이 없으면(레거시
/// 경로 등) 노출하지 않는다. #1704 타임라인 개편 시 이 위젯 삽입을 그 컴포넌트로
/// 이동하면 되며(재작성 불필요), 투영·토글 로직은 features/get_off_alarm/에 있다.
class _GetOffAlarmEntryPoint extends StatelessWidget {
  const _GetOffAlarmEntryPoint({
    required this.controller,
    required this.result,
    required this.stationRepository,
  });

  final GetOffAlarmController controller;
  final RouteSearchResult result;
  final StationSearchRepository stationRepository;

  @override
  Widget build(BuildContext context) {
    final rideLegs = _rideLegArrivalsFromResult(result);
    if (rideLegs.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GetOffAlarmToggle(
        controller: controller,
        routeId: result.routeSearchId,
        rideLegs: rideLegs,
        stationName: (id) => _resolveGetOffAlarmStationName(
          stationId: id,
          stationRepository: stationRepository,
        ),
      ),
    );
  }
}

Future<String?> _resolveGetOffAlarmStationName({
  required String stationId,
  required StationSearchRepository stationRepository,
}) async {
  final detail = await stationRepository.getStationDetail(stationId);
  if (detail.id != stationId) {
    return null;
  }
  return _usableGetOffAlarmStationName(detail.nameKo, stationId);
}

String? _usableGetOffAlarmStationName(String? rawName, String stationId) {
  final stationName = rawName?.trim();
  if (stationName == null || stationName.isEmpty || stationName == stationId) {
    return null;
  }
  return stationName;
}

List<RideLegArrival> _rideLegArrivalsFromResult(RouteSearchResult result) {
  final rideSteps = result.steps
      .where((step) => step.stepType == 'ride')
      .toList(growable: false);
  if (rideSteps.isEmpty ||
      rideSteps.any((step) => step.plannedArrivalTimeIso.isEmpty)) {
    return const [];
  }
  final rideLegs = <RideLegArrival>[];
  for (final step in rideSteps) {
    rideLegs.add(
      RideLegArrival(
        toStationId: step.toStationId,
        plannedArrivalIso: step.plannedArrivalTimeIso,
        realtimeArrivalIso: step.realtimeArrivalTimeIso,
      ),
    );
  }
  return rideLegs;
}

RouteSearchResult _preserveGetOffAlarmArrivalTimes({
  required RouteSearchResult next,
  required RouteSearchResult previous,
}) {
  final objectivePreserved = next.withDisplayLabels(
    objective: previous.objective,
  );
  if (_rideLegArrivalsFromResult(previous).isEmpty) {
    return objectivePreserved;
  }
  final previousRideSteps = previous.steps
      .where(
        (step) =>
            step.stepType == 'ride' && step.plannedArrivalTimeIso.isNotEmpty,
      )
      .toList(growable: false);
  var changed = false;
  final steps = objectivePreserved.steps
      .map((step) {
        if (step.stepType != 'ride' || step.plannedArrivalTimeIso.isNotEmpty) {
          return step;
        }
        final matched = _matchingPreviousRideStep(
          step: step,
          previousRideSteps: previousRideSteps,
        );
        if (matched == null) {
          return step;
        }
        changed = true;
        return step.withDisplayLabels(
          title: step.title,
          lineName: step.lineName,
          actionDetail: step.actionDetail,
          plannedArrivalTimeIso: matched.plannedArrivalTimeIso,
          realtimeArrivalTimeIso: step.realtimeArrivalTimeIso,
        );
      })
      .toList(growable: false);
  if (!changed) {
    return objectivePreserved;
  }
  return objectivePreserved.withDisplayLabels(steps: steps);
}

RouteSearchStep? _matchingPreviousRideStep({
  required RouteSearchStep step,
  required List<RouteSearchStep> previousRideSteps,
}) {
  for (final previousStep in previousRideSteps) {
    if (previousStep.fromStationId == step.fromStationId &&
        previousStep.toStationId == step.toStationId &&
        previousStep.lineId == step.lineId) {
      return previousStep;
    }
  }
  return null;
}

class _RouteResultsListView extends StatelessWidget {
  const _RouteResultsListView({
    required this.result,
    required this.onOpenDetail,
    required this.adRepository,
  });

  final RouteSearchResult result;
  final VoidCallback onOpenDetail;
  final AdRepository? adRepository;

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
        // #1933 E: 긴 두 줄 문장("예상 소요시간: 저장된 데이터 기준 · 최근 확인 …")
        // 대신 작은 캡션 한 줄("저장된 데이터 기준")로 축약한다. 강등 사다리의
        // 정직함은 라벨 로직(routeEtaSourceLabel) 그대로 유지된다.
        if (result.sourceNoticeCaption.isNotEmpty) ...[
          // 상세 안내는 상단 Semantics(semanticLabel)에 이미 sourceNotice로
          // 담겨 있으므로 시각 캡션은 시맨틱에서 제외해 이중 안내를 막는다.
          ExcludeSemantics(
            child: Text(
              result.sourceNoticeCaption,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: EasySubwayAccessibleColors.mutedText,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        _RouteResultListButton(result: result, onPressed: onOpenDetail),
        // #1933 D: 결과-우선 화면은 요약 카드를 탭해야만 보이던 이동 순서 타임라인
        // (#1704)을 그 자리에 인라인으로 편다. 사용자가 티저 카드가 아니라 실제
        // 여정을 바로 보게 한다. 상세(안내 시작·피드백·저장)는 카드 탭으로 계속 연다.
        if (result.movementSteps.isNotEmpty) ...[
          const SizedBox(height: 16),
          _RouteStepSection(steps: result.movementSteps),
          if (result.arrivalGuidanceStep case final arrivalStep?) ...[
            const SizedBox(height: 8),
            _RouteArrivalGuidance(step: arrivalStep),
          ],
        ],
        // 경로 확인 휴지점(결과 목록 끝)에만 광고 슬롯. 안내 진행 화면에는 없음.
        const SizedBox(height: 16),
        if (adRepository case final repository?)
          ActiveAdBanner(
            key: const Key('routeResultListAdBanner'),
            repository: repository,
            placement: AdPlacement.routeResultBottom,
          )
        else
          const AdBannerSlot(slotKey: Key('routeResultListAdBanner')),
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
    required this.adRepository,
    required this.routeShareInvoker,
  });

  final RouteSearchResult result;
  final VoidCallback onBack;
  final VoidCallback? onStartGuidance;
  final VoidCallback? onOpenFeedback;
  final Widget? favoriteSaveButton;
  final AdRepository? adRepository;
  final RouteShareInvoker? routeShareInvoker;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RouteWorkflowBackButton(label: '경로 목록', onPressed: onBack),
        const SizedBox(height: 8),
        _RouteDarkSummaryCard(
          title: _routeWorkflowSummaryTitle(result),
          subtitle: _routeWorkflowSummarySubtitle(result),
          chips: [
            _RouteSummaryChip(label: result.comfortLabel),
            _RouteSummaryChip(
              label: result.stairAccessLabel,
              icon: _routeStairAccessIcon(result),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _OfficialOdFareSection(quote: result.officialOdFareQuote),
        const SizedBox(height: 16),
        _RouteStepSection(steps: result.movementSteps),
        if (result.arrivalGuidanceStep case final arrivalStep?) ...[
          const SizedBox(height: 8),
          _RouteArrivalGuidance(step: arrivalStep),
        ],
        if (result.warnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          _RouteNotice(
            title: '주의 확인',
            text: result.warningNoticeText,
            icon: Icons.warning_amber,
          ),
        ],
        const SizedBox(height: 12),
        _RouteShareButton(result: result, invoker: routeShareInvoker),
        const SizedBox(height: 10),
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
        // 상세 뷰 스크롤 끝에만 광고 슬롯(안내·역 안 이동·피드백에는 없음).
        const SizedBox(height: 16),
        if (adRepository case final repository?)
          ActiveAdBanner(
            key: const Key('routeDetailAdBanner'),
            repository: repository,
            placement: AdPlacement.routeResultBottom,
          )
        else
          const AdBannerSlot(slotKey: Key('routeDetailAdBanner')),
      ],
    );
  }
}

class _RouteShareButton extends StatefulWidget {
  const _RouteShareButton({required this.result, required this.invoker});

  final RouteSearchResult result;
  final RouteShareInvoker? invoker;

  @override
  State<_RouteShareButton> createState() => _RouteShareButtonState();
}

class _RouteShareButtonState extends State<_RouteShareButton> {
  var _isSharing = false;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (buttonContext) {
        final onShare = _isSharing ? null : () => _share(buttonContext);
        return Semantics(
          button: true,
          label: '경로 요약 공유',
          onTap: onShare,
          excludeSemantics: true,
          child: OutlinedButton.icon(
            key: const Key('routeShareButton'),
            onPressed: onShare,
            icon: const Icon(Icons.share_outlined),
            label: const Text('공유'),
          ),
        );
      },
    );
  }

  Future<void> _share(BuildContext context) async {
    if (_isSharing) {
      return;
    }
    setState(() => _isSharing = true);
    try {
      final renderBox = context.findRenderObject();
      if (renderBox is! RenderBox || !renderBox.hasSize) {
        throw StateError('Route share trigger is unavailable');
      }
      final origin = renderBox.localToGlobal(Offset.zero) & renderBox.size;
      final text = buildRouteShareSummary(_routeShareSnapshot(widget.result));
      final invoke = widget.invoker;
      if (invoke != null) {
        await invoke(text, origin);
      } else {
        await SharePlus.instance.share(
          ShareParams(text: text, sharePositionOrigin: origin),
        );
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('경로 요약을 공유하지 못했어요.')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }
}

RouteShareSnapshot _routeShareSnapshot(RouteSearchResult result) {
  if (result.isBlocked || result.status != 'FOUND') {
    throw StateError('Route is unavailable');
  }
  final originName = result.originStationName.trim();
  final destinationName = result.destinationStationName.trim();
  if (originName.isEmpty ||
      destinationName.isEmpty ||
      originName == result.originStationId ||
      destinationName == result.destinationStationId) {
    throw StateError('Canonical station names are unavailable');
  }

  final steps = result.movementSteps;
  if (steps.isEmpty) {
    throw StateError('Route itinerary is unavailable');
  }
  final forbiddenIdentifiers = <String>{
    result.routeSearchId,
    result.originStationId,
    result.destinationStationId,
    for (final step in steps) ...[
      step.fromStationId,
      step.toStationId,
      step.lineId,
    ],
  }.where((value) => value.trim().isNotEmpty).toSet();
  final legs = steps
      .map((step) {
        final description = step.title.trim();
        if (description.isEmpty ||
            forbiddenIdentifiers.any(description.contains)) {
          throw StateError('Route leg display labels are unavailable');
        }
        var departureTimeSource = step.realtimeDepartureTimeIso.isNotEmpty
            ? step.realtimeDepartureTimeIso
            : step.plannedDepartureTimeIso;
        var arrivalTimeSource = step.realtimeArrivalTimeIso.isNotEmpty
            ? step.realtimeArrivalTimeIso
            : step.plannedArrivalTimeIso;
        if (result.isLocalResult) {
          final duration = Duration(minutes: step.estimatedMinutes);
          if (departureTimeSource.isEmpty && arrivalTimeSource.isNotEmpty) {
            departureTimeSource = _shiftRouteShareTime(
              arrivalTimeSource,
              -duration,
            );
          } else if (arrivalTimeSource.isEmpty &&
              departureTimeSource.isNotEmpty) {
            arrivalTimeSource = _shiftRouteShareTime(
              departureTimeSource,
              duration,
            );
          }
        }
        return RouteShareLeg(
          description: description,
          departureTime: _routeShareTime(departureTimeSource, allowEmpty: true),
          arrivalTime: _routeShareTime(arrivalTimeSource, allowEmpty: true),
        );
      })
      .toList(growable: false);

  var departureSource = result.departureTimeIso.isNotEmpty
      ? result.departureTimeIso
      : _firstRouteShareDeparture(steps);
  var arrivalSource = result.arrivalTimeIso.isNotEmpty
      ? result.arrivalTimeIso
      : _lastRouteShareArrival(steps);
  final durationMinutes = (result.estimatedDurationSeconds / 60).ceil();
  final duration = Duration(seconds: result.estimatedDurationSeconds);
  if (departureSource.isEmpty && arrivalSource.isEmpty) {
    departureSource = _routeShareTime(result.createdAt);
    arrivalSource = _shiftRouteShareTime(departureSource, duration);
  } else if (result.isLocalResult) {
    if (departureSource.isEmpty) {
      departureSource = _shiftRouteShareTime(arrivalSource, -duration);
    } else if (arrivalSource.isEmpty) {
      arrivalSource = _shiftRouteShareTime(departureSource, duration);
    }
  }

  RouteShareFare? fare;
  if (result.officialFare case final officialFare?) {
    fare = RouteShareFare(
      adultFareWon: officialFare.adultFareWon,
      currency: officialFare.currency,
    );
  } else if (result.transportScope ==
      RouteTransportScope.subwayAndItxCheongchun) {
    throw StateError('Official ITX fare is unavailable');
  } else if (result.officialOdFareQuote case final quote?) {
    fare = RouteShareFare(adultFareWon: quote.gnrlCardFare, currency: 'KRW');
  }

  return RouteShareSnapshot(
    // 실제 역명과 leg 표시명은 아직 한국어 canonical만 제공한다.
    languageCode: 'ko',
    originName: originName,
    destinationName: destinationName,
    objective: switch (result.objective) {
      RouteObjective.fastest => RouteShareObjective.fastest,
      RouteObjective.fewestTransfers => RouteShareObjective.fewestTransfers,
    },
    transportScope: switch (result.transportScope) {
      RouteTransportScope.subway => RouteShareTransportScope.subway,
      RouteTransportScope.subwayAndItxCheongchun =>
        RouteShareTransportScope.subwayAndItxCheongchun,
    },
    departureTime: _routeShareTime(departureSource),
    arrivalTime: _routeShareTime(arrivalSource),
    durationMinutes: durationMinutes,
    transferCount: result.transferCount,
    freshness: switch (result.etaSource) {
      'REALTIME' => RouteShareFreshness.realtime,
      'MIXED' => RouteShareFreshness.mixed,
      'STATIC_LOCAL' ||
      'STATIC_ESTIMATE' ||
      'STALE' => RouteShareFreshness.staticData,
      _ => RouteShareFreshness.planned,
    },
    legs: legs,
    fare: fare,
  );
}

String _firstRouteShareDeparture(List<RouteSearchStep> steps) {
  for (final step in steps) {
    if (step.realtimeDepartureTimeIso.isNotEmpty) {
      return step.realtimeDepartureTimeIso;
    }
    if (step.plannedDepartureTimeIso.isNotEmpty) {
      return step.plannedDepartureTimeIso;
    }
  }
  return '';
}

String _lastRouteShareArrival(List<RouteSearchStep> steps) {
  for (final step in steps.reversed) {
    if (step.realtimeArrivalTimeIso.isNotEmpty) {
      return step.realtimeArrivalTimeIso;
    }
    if (step.plannedArrivalTimeIso.isNotEmpty) {
      return step.plannedArrivalTimeIso;
    }
  }
  return '';
}

String _routeShareTime(String value, {bool allowEmpty = false}) {
  final trimmed = value.trim();
  if (allowEmpty && trimmed.isEmpty) {
    return '';
  }
  if (RegExp(r'(?:[zZ]|[+-]\d{2}:\d{2})$').hasMatch(trimmed)) {
    final instant = DateTime.tryParse(trimmed);
    if (instant == null) {
      throw StateError('Route time is unavailable');
    }
    final koreanTime = instant.toUtc().add(const Duration(hours: 9));
    return '${koreanTime.hour.toString().padLeft(2, '0')}:${koreanTime.minute.toString().padLeft(2, '0')}';
  }
  final match = RegExp(r'(?:T|^)(\d{2}):(\d{2})').firstMatch(trimmed);
  if (match == null) {
    throw StateError('Route time is unavailable');
  }
  return '${match.group(1)}:${match.group(2)}';
}

String _shiftRouteShareTime(String value, Duration offset) {
  final match = RegExp(
    r'(?:T|^)(\d{2}):(\d{2})(?::(\d{2}))?',
  ).firstMatch(value.trim());
  if (match == null) {
    throw StateError('Route time is unavailable');
  }
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final second = int.parse(match.group(3) ?? '0');
  if (hour > 23 || minute > 59 || second > 59) {
    throw StateError('Route time is unavailable');
  }
  final shifted = DateTime.utc(2000, 1, 2, hour, minute, second).add(offset);
  return '${shifted.hour.toString().padLeft(2, '0')}:${shifted.minute.toString().padLeft(2, '0')}';
}

class _OfficialOdFareSection extends StatelessWidget {
  const _OfficialOdFareSection({required this.quote});

  final OfficialOdFareQuote? quote;

  @override
  Widget build(BuildContext context) {
    final quote = this.quote;
    if (quote == null) {
      return Semantics(
        container: true,
        label:
            '공식 OD 요금 정보 없음, 오프라인 공식 자료에 없는 경로입니다. 연락운송 경계 등 승인되지 않은 경로는 요금을 임의로 계산하지 않습니다.',
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('공식 OD 요금 정보 없음'),
            Text('오프라인 공식 자료에 없는 경로입니다.'),
            Text('연락운송 경계 등 승인되지 않은 경로는 요금을 임의로 계산하지 않습니다.'),
          ],
        ),
      );
    }
    final alternativeFareMedium = quote.alternativeFareMediumLabel;
    final values = [
      ('일반 카드', quote.gnrlCardFare),
      ('일반 $alternativeFareMedium', quote.gnrlCashFare),
      ('청소년 카드', quote.yungCardFare),
      ('청소년 $alternativeFareMedium', quote.yungCashFare),
      ('어린이 카드', quote.childCardFare),
      ('어린이 $alternativeFareMedium', quote.childCashFare),
    ];
    return Semantics(
      container: true,
      label: '공식 OD 요금, 오프라인 공식 자료',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _RouteSectionHeader(title: '공식 OD 요금'),
          const SizedBox(height: 8),
          for (final value in values)
            Semantics(
              container: true,
              label: '${value.$1}, ${value.$2}원, 오프라인 공식 자료',
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text(value.$1), Text('${value.$2}원')],
                ),
              ),
            ),
          const SizedBox(height: 4),
          const Text('오프라인 공식 자료 기준'),
        ],
      ),
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
          decoration: const BoxDecoration(
            color: EasySubwayAccessibleColors.surface,
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: textScale >= 2
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${result.originStationName} → ${result.destinationStationName}',
                              style: textTheme.titleMedium?.copyWith(
                                color: EasySubwayAccessibleColors.text,
                                fontWeight: FontWeight.w700,
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
                                      fontWeight: FontWeight.w700,
                                      height: 1.25,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _routeGuidanceMobilityHeaderLabel(result),
                                    key: const Key('routeGuidanceMobilityChip'),
                                    style: textTheme.bodySmall?.copyWith(
                                      color:
                                          EasySubwayAccessibleColors.mutedText,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
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
                  decoration: result.isBlocked
                      ? const BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: EasySubwayAccessibleColors.red,
                              width: 3,
                            ),
                          ),
                        )
                      : null,
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
                                  fontWeight: FontWeight.w700,
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
                                  fontWeight: FontWeight.w700,
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
                                        fontWeight: FontWeight.w700,
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
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        if (_isRecommendedRoute(result) &&
                            result.movementSteps.isNotEmpty) ...[
                          const SizedBox(height: 15),
                          _RouteLinePath(steps: result.movementSteps),
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
                          _RouteNotice(
                            title: '주의 확인',
                            text: result.warningNoticeText,
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
            text: nextStep.userTitle,
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
        const Icon(
          Icons.warning_amber,
          size: 64,
          color: EasySubwayAccessibleColors.red,
        ),
        const SizedBox(height: 10),
        Text(
          '계단 없는 경로가 없습니다',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: EasySubwayAccessibleColors.text,
            fontWeight: FontWeight.w700,
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
            color: EasySubwayAccessibleColors.text,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 14),
        if (feedbackRepository == null)
          const _RouteNotice(
            title: '의견을 지금 받을 수 없어요',
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
      label: [
        result.summaryTitle,
        _routeMetaLabel(result),
        result.comfortLabel,
        result.stairAccessLabel,
        ...result.badgeLabels,
      ].join(', '),
      onTap: onPressed,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const Key('routeResultListItem'),
            onTap: onPressed,
            borderRadius: _routeSearchSmallRadius,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            // #1915 톤 라이트닝: 요약을 두르던 2px primary 박스를 걷어내고
            // 콘텐츠를 플랫하게 흘린다(탭 가능성은 InkWell로 유지).
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
                                color: EasySubwayAccessibleColors.text,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _routeMetaLabel(result),
                    style: const TextStyle(
                      color: EasySubwayAccessibleColors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _RouteLinePath(steps: result.movementSteps),
                  const SizedBox(height: 12),
                  // #1933 E: 총 소요시간 아래 메타 줄(환승·걷기)과 상단 이동조건
                  // 칩이 이미 같은 신호를 전하므로, 카드에서 환승·걷기 칩을
                  // 걷어내 "요약 한 번 → 타임라인"의 위계를 만든다. 타임라인·
                  // 상단 칩에 없는 신호(이동 조건 경고·계단·정직한 안내 배지)만 남긴다.
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
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
                      for (final label in result.badgeLabels)
                        _RouteStatusChip(
                          key: Key('routeResultBadge-$label'),
                          label: label,
                          icon: _routeBadgeIcon(label),
                        ),
                    ],
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

IconData _routeBadgeIcon(String label) {
  if (routeEtaSourceLabels.containsValue(label) ||
      label == routeEtaSourceLabel('')) {
    return Icons.schedule;
  }
  return switch (label) {
    '계단 없는 경로 확인' => Icons.check_circle_outline,
    '엘리베이터 상태를 살펴봐 주세요' || '일부 이동 정보를 살펴봐 주세요' => Icons.accessible_forward,
    '환승 여유 충분' || '환승 빠듯함' || '역 밖 환승' => Icons.compare_arrows,
    _ => Icons.info_outline,
  };
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
    // #1915 톤 라이트닝: surface+line 박스를 걷어내고 제목/부제/칩을 플랫하게 편다.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: EasySubwayAccessibleColors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: EasySubwayAccessibleColors.secondaryText,
            ),
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
  final preset = mobilityPresetFromRepresentativeMobilityType(
    result.mobilityType,
  );
  if (preset == null) {
    return mobilityLabel;
  }
  final description = mobilityPresetDescription(preset);
  return description.isEmpty ? mobilityLabel : '$mobilityLabel · $description';
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
      : result.guidanceLabel;
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
              fontWeight: FontWeight.w700,
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
    // 환승·걷기·이동조건 등 비상태 정보는 민트 틴트 대신 중립 아이콘+텍스트로.
    return Container(
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.surface,
        borderRadius: _routeSearchPillRadius,
        border: Border.all(color: EasySubwayAccessibleColors.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Wrap(
        spacing: 5,
        runSpacing: 3,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(icon, size: 13, color: EasySubwayAccessibleColors.secondaryText),
          Text(
            label,
            style: const TextStyle(
              color: EasySubwayAccessibleColors.secondaryText,
              fontSize: 11,
              fontWeight: FontWeight.w700,
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

/// #1933 D: 결과-우선 화면 상단의 조용한 프리셋 칩 한 개. 폼(드롭다운 + 스위치)
/// 대신 결과 위에 얇게 얹히고, 다른 프리셋을 고르면 그 자리에서 바로 재검색한다.
/// (별도 "길찾기" 버튼 없음.) 프리셋이 이동 유형·시설 제약을 모두 결정하므로 계단
/// 토글 칩은 두지 않는다(#1703).
class _RouteConditionChips extends StatelessWidget {
  const _RouteConditionChips({
    required this.preset,
    required this.objective,
    required this.transportScope,
    required this.itxTransportScopeEnabled,
    required this.loading,
    required this.onChangePreset,
    required this.onChangeObjective,
    required this.onChangeTransportScope,
  });

  final MobilityPreset preset;
  final RouteObjective objective;
  final RouteTransportScope transportScope;
  final bool itxTransportScopeEnabled;
  // 재검색 로딩 중에는 objective·교통범위 변경 핸들러가 입력을 조용히 무시하므로,
  // 해당 칩을 시각·semantics 모두 비활성으로 표기해 활성으로 보이지 않게 한다.
  final bool loading;
  final VoidCallback onChangePreset;
  final ValueChanged<RouteObjective> onChangeObjective;
  final ValueChanged<RouteTransportScope> onChangeTransportScope;

  @override
  Widget build(BuildContext context) {
    final displayName = mobilityPresetDisplayName(preset);
    // 일반 폭에서는 한 행에 배치되고, 큰 글자·좁은 폭에서는 objective 행 다음으로
    // scope 행이 자연스럽게 내려가도록 Wrap이 재배치한다.
    return Padding(
      key: const Key('routeConditionChips'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _RouteConditionChipButton(
            buttonKey: const Key('routeConditionMobilityChip'),
            icon: mobilityPresetIcon(preset),
            label: '$displayName 기준',
            semanticLabel: '경로 시간 기준, $displayName',
            active: false,
            onTap: onChangePreset,
          ),
          // objective 탭: 기존 transport toggle 세그먼트 패턴을 재사용(무채색·radius 8·
          // 그림자 0). 좌측에 놓고 항상 노출한다(기본값 FASTEST).
          _RouteConditionChipButton(
            buttonKey: const Key('routeObjectiveFastestChip'),
            icon: Icons.bolt,
            label: RouteObjective.fastest.label,
            semanticLabel: '경로 목표, ${RouteObjective.fastest.label}',
            active: objective == RouteObjective.fastest,
            enabled: !loading,
            onTap: () => onChangeObjective(RouteObjective.fastest),
          ),
          _RouteConditionChipButton(
            buttonKey: const Key('routeObjectiveFewestTransfersChip'),
            icon: Icons.swap_calls,
            label: RouteObjective.fewestTransfers.label,
            semanticLabel: '경로 목표, ${RouteObjective.fewestTransfers.label}',
            active: objective == RouteObjective.fewestTransfers,
            enabled: !loading,
            onTap: () => onChangeObjective(RouteObjective.fewestTransfers),
          ),
          if (itxTransportScopeEnabled) ...[
            _RouteConditionChipButton(
              buttonKey: const Key('routeScopeSubwayChip'),
              icon: Icons.subway,
              label: '지하철만',
              semanticLabel: '교통 범위, 지하철만',
              active: transportScope == RouteTransportScope.subway,
              enabled: !loading,
              onTap: () => onChangeTransportScope(RouteTransportScope.subway),
            ),
            _RouteConditionChipButton(
              buttonKey: const Key('routeScopeItxChip'),
              icon: Icons.train,
              label: '지하철 + ITX-청춘',
              semanticLabel: '교통 범위, 지하철과 ITX-청춘',
              active:
                  transportScope == RouteTransportScope.subwayAndItxCheongchun,
              enabled: !loading,
              onTap: () => onChangeTransportScope(
                RouteTransportScope.subwayAndItxCheongchun,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RouteConditionChipButton extends StatelessWidget {
  const _RouteConditionChipButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.active,
    this.enabled = true,
    required this.onTap,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final String semanticLabel;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 비활성(재검색 로딩 중)일 때는 무채색 원칙 안에서 기존 muted 토큰만 재사용해
    // 흐리게 표기하고 tap·semantics 모두 막는다(새 색·새 디자인 없음).
    final foreground = !enabled
        ? EasySubwayAccessibleColors.iconMuted
        : active
        ? EasySubwayAccessibleColors.primary
        : EasySubwayAccessibleColors.secondaryText;
    final tapHandler = enabled ? onTap : null;
    return Semantics(
      button: true,
      enabled: enabled,
      toggled: active,
      label: semanticLabel,
      onTap: tapHandler,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: buttonKey,
            onTap: tapHandler,
            borderRadius: _routeSearchPillRadius,
            child: Ink(
              decoration: BoxDecoration(
                color: EasySubwayAccessibleColors.surface,
                borderRadius: _routeSearchPillRadius,
                border: Border.all(
                  color: !enabled
                      ? EasySubwayAccessibleColors.line
                      : active
                      ? EasySubwayAccessibleColors.primary
                      : EasySubwayAccessibleColors.line,
                  width: active && enabled ? 2 : 1,
                ),
              ),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: foreground),
                    const SizedBox(width: 8),
                    // 좁은 화면·큰 글자에서도 넘치지 않게 라벨이 줄바꿈되도록 둔다.
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (active) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.check,
                        size: 16,
                        color: enabled
                            ? EasySubwayAccessibleColors.primary
                            : EasySubwayAccessibleColors.iconMuted,
                      ),
                    ],
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

/// 미니 진행 바(#1915 톤 라이트닝): 굵은 검정 primary 바 대신 중립 레일 위에
/// 탑승(ride) 구간만 노선색을 얹는다. 도보/환승 구간은 중립 회색으로 남겨
/// 세로 타임라인(_RouteStepTile)의 노선색 규칙과 신호를 맞춘다.
class _RouteLinePath extends StatelessWidget {
  const _RouteLinePath({this.steps = const []});

  final List<RouteSearchStep> steps;

  @override
  Widget build(BuildContext context) {
    final rideSteps = steps.where((step) => !step.isWalkingStep).toList();
    final segmentColors = rideSteps.isEmpty
        ? const <Color>[EasySubwayAccessibleColors.line]
        : [
            for (final step in rideSteps)
              stationLineColor(_routeLineColor(step.lineName)),
          ];
    return Row(
      children: [
        _RouteLineNode(color: segmentColors.first),
        for (var index = 0; index < segmentColors.length; index += 1) ...[
          Expanded(child: Container(height: 4, color: segmentColors[index])),
          if (index < segmentColors.length - 1)
            _RouteLineNode(
              color: EasySubwayAccessibleColors.iconMuted,
              small: true,
            ),
        ],
        _RouteLineNode(color: segmentColors.last),
      ],
    );
  }
}

class _RouteLineNode extends StatelessWidget {
  const _RouteLineNode({
    this.color = EasySubwayAccessibleColors.iconMuted,
    this.small = false,
  });

  final Color color;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final size = small ? 8.0 : 14.0;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: small ? 2 : 3),
        ),
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
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            child: Icon(
              blocked ? Icons.priority_high_rounded : Icons.check_rounded,
              size: 14,
              color: blocked
                  ? EasySubwayAccessibleColors.red
                  : EasySubwayAccessibleColors.mintDark,
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
        border: Border.all(color: EasySubwayAccessibleColors.line),
        borderRadius: _routeSearchSmallRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.exit_to_app,
              color: EasySubwayAccessibleColors.iconMuted,
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
                      color: EasySubwayAccessibleColors.mutedText,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    step.userDescription,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: EasySubwayAccessibleColors.text,
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
          border: Border.all(color: EasySubwayAccessibleColors.line),
          borderRadius: _routeSearchSmallRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: EasySubwayAccessibleColors.amber, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: EasySubwayAccessibleColors.text,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      text,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: EasySubwayAccessibleColors.text,
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
            color: EasySubwayAccessibleColors.text,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < steps.length; index += 1)
          _RouteStepTile(step: steps[index], isLast: index == steps.length - 1),
      ],
    );
  }
}

/// 세로 타임라인 좌측 레일 폭(시각 칸 + 노선색 배지가 정렬되는 고정폭).
const double _routeTimelineRailWidth = 64;

/// 노선색 배지 지름 · 연결선 두께 · 최소 터치 타깃(#1704 접근성 48).
const double _routeTimelineBadgeSize = 40;
const double _routeTimelineConnectorWidth = 4;
const double _routeTimelineMinTouchTarget = 48;

/// #1975: 경유 노드는 승차 배지가 아니므로 시각 반경 ≤8(직경 16)으로 축소한다.
/// 터치 타깃은 여전히 48을 유지한다.
const double _routeTimelineWaypointNodeSize = 16;

/// 세로 타임라인 한 스텝. 좌측(시각·노선색 배지·연결선) + 우측(역명·구간 요약).
///
/// 데이터 경계(#1704): 노선색·역명·구간 요약·(있을 때만) 시각만 그린다.
/// 빠른 하차 칸-문 안내(#2066)는 오프라인 로컬 catalog에 데이터가 있을 때만 그린다.
/// 빠른 환승 칸번호·내리는 문은 여전히 데이터 경계로 줄 자체를 그리지 않는다.
class _RouteStepTile extends StatelessWidget {
  const _RouteStepTile({required this.step, this.isLast = false});

  final RouteSearchStep step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isWalking = step.isWalkingStep;
    final isWaypoint = step.stepType == 'waypoint';
    // 노선색은 우리 데이터로 가능한 유일한 유채색(#1915). 도보/환승 구간은 노선색이
    // 없으므로 중립 회색 점선으로 강등한다.
    final lineColor = isWalking
        ? EasySubwayAccessibleColors.line
        : stationLineColor(_routeLineColor(step.lineName));
    final badgeText = _routeTimelineBadgeText(step);
    final clockLabel = _routeStepClockLabel(step);

    final rail = SizedBox(
      width: _routeTimelineRailWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (clockLabel.isNotEmpty) ...[
            Text(
              clockLabel,
              key: Key('routeStepTime-${step.sequence}'),
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: EasySubwayAccessibleColors.mutedText,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 4),
          ],
          _RouteTimelineBadge(
            badgeKey: Key('routeStepNumber-${step.sequence}'),
            label: badgeText,
            color: isWalking
                ? EasySubwayAccessibleColors.scaffoldSurface
                : lineColor,
            isWalking: isWalking,
            isWaypoint: isWaypoint,
          ),
          if (!isLast)
            Expanded(
              child: _RouteTimelineConnector(
                color: lineColor,
                dashed: isWalking,
              ),
            ),
        ],
      ),
    );

    final content = Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 역명(굵게) + ">" 어포던스: 참고 앱 타임라인의 역명 행.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  step.userTitle,
                  style: textTheme.bodyLarge?.copyWith(
                    color: EasySubwayAccessibleColors.text,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 6, top: 2),
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: EasySubwayAccessibleColors.mutedText,
                ),
              ),
            ],
          ),
          if (!isWaypoint && step.userActionTitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              step.userActionTitle,
              style: textTheme.bodyMedium?.copyWith(
                color: EasySubwayAccessibleColors.secondaryText,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ],
          // 승차 정보 영역에만 급행 배지를 붙인다(요약 카드 전체가 아니라 leg별).
          // SUBWAY/EXPRESS만 대상이고, ITX-청춘·LOCAL은 배지 없음. 배지는 장식이라
          // ExcludeSemantics로 두고 TalkBack용 `급행`은 이 Semantics가 한 번만 준다.
          if (step.stepType == 'ride' && step.isSubwayExpress) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                label: '급행',
                child: const ServicePatternBadge.express(),
              ),
            ),
          ],
          // ITX-청춘 승차 leg는 별도 운임의 좌석 지정 서비스라 같은 노선 일반 전동차와
          // 구분해 표시한다. serviceClass=SUBWAY와 상호 배타라 급행 배지와 동시에
          // 붙지 않는다. 배지는 장식이라 ExcludeSemantics로 두고 TalkBack용
          // `ITX-청춘`은 이 Semantics가 한 번만 준다.
          if (step.stepType == 'ride' && step.isItxCheongchun) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                label: 'ITX-청춘',
                child: const ServicePatternBadge.itxCheongchun(),
              ),
            ),
          ],
          // 경유(waypoint) 마커는 시간·거리가 0이라 placeholder만 나오므로
          // 구간 요약 줄 자체를 그리지 않는다(#1948).
          if (!isWaypoint) ...[
            const SizedBox(height: 4),
            // 구간 요약: "약 M분 · 거리 · 계단" (기존 burdenLabel 재사용).
            Text(
              step.burdenLabel,
              style: textTheme.bodyMedium?.copyWith(
                color: EasySubwayAccessibleColors.secondaryText,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ],
          // 빠른 하차 칸-문 안내(#2066): 오프라인 로컬 catalog에 데이터가 있을 때만.
          if (step.stepType == 'ride' && step.hasCarDoorHint) ...[
            const SizedBox(height: 4),
            Semantics(
              label: step.carDoorHintSemanticLabel,
              child: Text(
                step.carDoorHintLabel,
                key: Key('routeStepCarDoor-${step.sequence}'),
                style: textTheme.bodyMedium?.copyWith(
                  color: EasySubwayAccessibleColors.secondaryText,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            step.userDescription,
            style: textTheme.bodyLarge?.copyWith(
              color: EasySubwayAccessibleColors.secondaryText,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          if (step.userReason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              step.userReason,
              style: textTheme.bodyMedium?.copyWith(
                color: EasySubwayAccessibleColors.secondaryText,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          rail,
          const SizedBox(width: 12),
          Expanded(child: content),
        ],
      ),
    );
  }
}

/// 타임라인 노선색 원형 배지. 승차는 노선색+노선번호, 도보/환승은 중립 걷기 아이콘.
class _RouteTimelineBadge extends StatelessWidget {
  const _RouteTimelineBadge({
    required this.badgeKey,
    required this.label,
    required this.color,
    required this.isWalking,
    this.isWaypoint = false,
  });

  final Key badgeKey;
  final String label;
  final Color color;
  final bool isWalking;

  /// #1948: 경유 노드는 승차 배지·도보 아이콘이 아니라 무채색 경유 노드로 그린다.
  final bool isWaypoint;

  @override
  Widget build(BuildContext context) {
    // #1948: 경유 노드는 무채색 진회색 원에 more_horiz 아이콘. isWalking보다 우선.
    if (isWaypoint) {
      return SizedBox(
        width: _routeTimelineMinTouchTarget,
        height: _routeTimelineMinTouchTarget,
        child: Center(
          child: Container(
            key: badgeKey,
            width: _routeTimelineWaypointNodeSize,
            height: _routeTimelineWaypointNodeSize,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: EasySubwayAccessibleColors.mutedText,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.more_horiz, size: 12, color: Colors.white),
          ),
        ),
      );
    }
    // 터치 타깃 48 보장: 시각적 배지는 40이지만 최소 48 박스로 감싼다.
    return SizedBox(
      width: _routeTimelineMinTouchTarget,
      height: _routeTimelineMinTouchTarget,
      child: Center(
        child: Container(
          key: badgeKey,
          width: _routeTimelineBadgeSize,
          height: _routeTimelineBadgeSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: isWalking
                ? Border.all(color: EasySubwayAccessibleColors.line)
                : null,
          ),
          child: isWalking
              ? const Icon(
                  Icons.directions_walk,
                  size: 20,
                  color: EasySubwayAccessibleColors.mutedText,
                )
              : Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    color: stationLineTextColor(color),
                    fontSize: label.length > 2 ? 12 : 16,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
        ),
      ),
    );
  }
}

/// 타임라인 세로 연결선. 승차 구간은 노선색 실선, 도보/환승 구간은 회색 점선.
class _RouteTimelineConnector extends StatelessWidget {
  const _RouteTimelineConnector({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    if (!dashed) {
      return Center(
        child: Container(width: _routeTimelineConnectorWidth, color: color),
      );
    }
    // 점선을 LayoutBuilder로 그리면 IntrinsicHeight(부모 타임라인 타일)가 세로 크기를
    // 물을 때 예외가 난다. 결과-우선 화면에서 타임라인을 인라인으로 펴려면(#1933 D)
    // 이 연결선이 intrinsic 측정을 견뎌야 하므로, CustomPaint로 크기에 맞춰 그린다.
    return Center(
      child: SizedBox(
        width: _routeTimelineConnectorWidth,
        child: CustomPaint(
          size: const Size(_routeTimelineConnectorWidth, double.infinity),
          painter: _RouteTimelineDashedPainter(color: color),
        ),
      ),
    );
  }
}

/// 세로 점선 연결선 페인터. 사용 가능한 높이에 맞춰 4px 대시 + 4px 간격으로 그린다.
class _RouteTimelineDashedPainter extends CustomPainter {
  const _RouteTimelineDashedPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dashHeight = 4.0;
    const gap = 4.0;
    final paint = Paint()..color = color;
    final centerX = size.width / 2;
    var y = 0.0;
    while (y < size.height) {
      canvas.drawRect(
        Rect.fromLTWH(
          centerX - _routeTimelineConnectorWidth / 2,
          y,
          _routeTimelineConnectorWidth,
          dashHeight.clamp(0, size.height - y),
        ),
        paint,
      );
      y += dashHeight + gap;
    }
  }

  @override
  bool shouldRepaint(_RouteTimelineDashedPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 노선색 배지에 얹을 라벨. 노선번호(예: "4")·짧은 노선명·없으면 스텝 순번.
String _routeTimelineBadgeText(RouteSearchStep step) {
  final lineName = step.lineName.trim();
  if (lineName.isNotEmpty) {
    final badge = stationLineBadgeText(lineName).trim();
    if (badge.isNotEmpty) {
      return badge;
    }
  }
  return '${step.sequence}';
}

/// 스텝의 절대 시각(ISO)을 "오전 5:19" 형태로. 실시간 우선, 없으면 PLANNED,
/// 둘 다 없거나 파싱 불가면 빈 문자열(→ 시각 칸 자체를 그리지 않는다, #1704 경계).
String _routeStepClockLabel(RouteSearchStep step) {
  final iso = step.realtimeArrivalTimeIso.trim().isNotEmpty
      ? step.realtimeArrivalTimeIso.trim()
      : step.plannedArrivalTimeIso.trim();
  if (iso.isEmpty) {
    return '';
  }
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) {
    return '';
  }
  final local = parsed.toLocal();
  final isMorning = local.hour < 12;
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '${isMorning ? '오전' : '오후'} $hour12:$minute';
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
                color: EasySubwayAccessibleColors.secondaryText,
                fontWeight: FontWeight.w700,
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
                color: EasySubwayAccessibleColors.mutedText,
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
          itineraryId: '${widget.result.routeSearchId}-primary',
          mobilityType: widget.result.mobilityType,
          constraintMode: widget.result.constraintMode,
          etaSource: widget.result.etaSource.isEmpty
              ? 'PLANNED'
              : widget.result.etaSource,
          etaOffsetBucket: RouteEtaOffsetBucket.notProvided,
          etaFeedbackOptedIn: true,
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
                color: EasySubwayAccessibleColors.secondaryText,
                fontWeight: FontWeight.w700,
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
                color: EasySubwayAccessibleColors.mutedText,
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

bool? _optionalRouteBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  return null;
}
