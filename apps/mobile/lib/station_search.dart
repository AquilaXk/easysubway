import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'auth_headers.dart';
import 'facility_report.dart';
import 'internal_route.dart';
import 'map_adapter.dart';
import 'mobile_error_reporter.dart';

const _stationSearchTimeout = Duration(seconds: 8);
const _stationSearchErrorMessage = '역 정보를 불러오지 못했습니다.';
const _currentLocationDisabledMessage = '기기 위치(GPS)를 켜 주세요. 가까운 역을 찾는 데 필요합니다.';
const _nearbyLocationMaxAge = Duration(minutes: 5);
const _nearbyLocationMaxAccuracyMeters = 500.0;
const _locationQualityUnavailableMessage =
    '현재 위치 정확도 정보를 확인하지 못했어요. 출발역을 직접 선택해 주세요.';
const _locationQualityStaleMessage =
    '현재 위치가 오래되어 가까운 역을 정확히 찾기 어려워요. 출발역을 직접 선택해 주세요.';
const _locationQualityCoarseMessage =
    '현재 위치 정확도가 낮아 가까운 역을 정확히 찾기 어려워요. 출발역을 직접 선택해 주세요.';
const _locationQualityMockedMessage =
    '모의 위치는 가까운 역 찾기에 사용할 수 없어요. 출발역을 직접 선택해 주세요.';
const _locationPermissionRationaleTitle = '현재 위치 사용';
const _locationPermissionRationalePurpose =
    '가까운 역 찾기와 시설 신고 위치 확인에만 현재 위치를 사용합니다.';
const _locationPermissionRationaleFallback =
    '위치 권한을 거부해도 역명 검색, 즐겨찾기, 접근성 정보 조회는 계속 사용할 수 있습니다.';
const _stationSearchFailureNextAction = '역명으로 검색하면 위치 권한 없이도 계속 이용할 수 있습니다.';
const _stationSafetyGuidanceNotice = '이동 전 현장 안내와 역무원 안내를 확인해 주세요.';
const _favoriteStationTimeout = Duration(seconds: 8);
const _favoriteStationLoadErrorMessage = '즐겨찾기를 불러오지 못했습니다.';
const _favoriteStationStatusErrorMessage = '즐겨찾기를 확인하지 못했습니다.';
const _favoriteStationChangeErrorMessage = '즐겨찾기를 바꾸지 못했습니다.';

abstract class StationSearchRepository {
  Future<List<StationSearchResult>> searchStations(String query);

  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  });

  Future<StationDetail> getStationDetail(String stationId);

  Future<List<StationExitInfo>> listStationExits(String stationId);

  Future<List<StationFacilityInfo>> listStationFacilities(String stationId);
}

abstract class SearchHistoryRepository {
  Future<void> recordSearch(String query);

  Future<List<String>> listRecentQueries();
}

abstract class StationLineFilterRepository {
  Future<List<SubwayLineOption>> listLines();

  Future<List<StationSearchResult>> searchStationsOnLine(
    String query,
    String lineId,
  );
}

enum LocationPermissionPrecision { precise, approximate, unknown }

enum CurrentLocationQualityStatus {
  freshPrecise,
  unavailable,
  stale,
  coarse,
  mocked,
}

class CurrentLocation {
  const CurrentLocation({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.measuredAt,
    this.provider = 'unknown',
    this.isMocked = false,
    this.permissionPrecision = LocationPermissionPrecision.unknown,
  });

  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final DateTime? measuredAt;
  final String provider;
  final bool isMocked;
  final LocationPermissionPrecision permissionPrecision;

  CurrentLocationQualityStatus qualityStatus({
    DateTime? now,
    Duration maxAge = _nearbyLocationMaxAge,
    double maxAccuracyMeters = _nearbyLocationMaxAccuracyMeters,
  }) {
    if (isMocked) {
      return CurrentLocationQualityStatus.mocked;
    }
    final measuredAt = this.measuredAt;
    final accuracyMeters = this.accuracyMeters;
    if (measuredAt == null || accuracyMeters == null) {
      return CurrentLocationQualityStatus.unavailable;
    }
    final age = (now ?? DateTime.now()).difference(measuredAt);
    if (age > maxAge || age.isNegative) {
      return CurrentLocationQualityStatus.stale;
    }
    if (permissionPrecision == LocationPermissionPrecision.approximate ||
        accuracyMeters > maxAccuracyMeters) {
      return CurrentLocationQualityStatus.coarse;
    }
    return CurrentLocationQualityStatus.freshPrecise;
  }

  bool canUseForNearbySearch({DateTime? now}) {
    return qualityStatus(now: now) == CurrentLocationQualityStatus.freshPrecise;
  }

  String? nearbySearchBlockedMessage({DateTime? now}) {
    return switch (qualityStatus(now: now)) {
      CurrentLocationQualityStatus.freshPrecise => null,
      CurrentLocationQualityStatus.unavailable =>
        _locationQualityUnavailableMessage,
      CurrentLocationQualityStatus.stale => _locationQualityStaleMessage,
      CurrentLocationQualityStatus.coarse => _locationQualityCoarseMessage,
      CurrentLocationQualityStatus.mocked => _locationQualityMockedMessage,
    };
  }
}

abstract class CurrentLocationProvider {
  Future<bool> needsLocationPermissionRequest();

  Future<CurrentLocation> currentLocation();

  Future<bool> openLocationSettings();
}

class CurrentLocationException implements Exception {
  const CurrentLocationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MethodChannelCurrentLocationProvider implements CurrentLocationProvider {
  MethodChannelCurrentLocationProvider({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('com.easysubway.easysubway_mobile/location');

  final MethodChannel _channel;

  @override
  Future<bool> needsLocationPermissionRequest() async {
    try {
      return await _channel.invokeMethod<bool>(
            'needsLocationPermissionRequest',
          ) ??
          true;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '현재 위치 권한 상태 확인 중 예외가 발생했습니다.',
      );
      return true;
    }
  }

  @override
  Future<CurrentLocation> currentLocation() async {
    try {
      // 위치 권한과 센서 접근은 Android/iOS 네이티브 채널에 맡기고 화면은 같은 실패 문구를 사용한다.
      final response = await _channel.invokeMapMethod<String, Object?>(
        'currentLocation',
      );
      final latitude = _coordinateFrom(response, 'latitude');
      final longitude = _coordinateFrom(response, 'longitude');
      if (latitude == null || longitude == null) {
        throw const CurrentLocationException('현재 위치를 확인하지 못했습니다.');
      }
      return CurrentLocation(
        latitude: latitude,
        longitude: longitude,
        accuracyMeters: _doubleFrom(response, 'accuracyMeters'),
        measuredAt: _dateTimeFromMillis(response, 'measuredAtMillis'),
        provider: _stringFrom(response, 'provider') ?? 'unknown',
        isMocked: _boolFrom(response, 'isMocked') ?? false,
        permissionPrecision: _permissionPrecisionFrom(
          _stringFrom(response, 'permissionPrecision'),
        ),
      );
    } on CurrentLocationException {
      rethrow;
    } on PlatformException catch (error) {
      throw CurrentLocationException(_locationErrorMessage(error.code));
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '현재 위치 조회 중 예외가 발생했습니다.');
      throw const CurrentLocationException('현재 위치를 확인하지 못했습니다.');
    }
  }

  @override
  Future<bool> openLocationSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openLocationSettings') ?? false;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '위치 설정 화면 이동 중 예외가 발생했습니다.',
      );
      return false;
    }
  }

  double? _coordinateFrom(Map<String, Object?>? response, String key) {
    final value = response?[key];
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  double? _doubleFrom(Map<String, Object?>? response, String key) {
    final value = response?[key];
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  DateTime? _dateTimeFromMillis(Map<String, Object?>? response, String key) {
    final value = response?[key];
    final millis = switch (value) {
      int() => value,
      double() => value.round(),
      String() => int.tryParse(value),
      _ => null,
    };
    if (millis == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  String? _stringFrom(Map<String, Object?>? response, String key) {
    final value = response?[key];
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    return null;
  }

  bool? _boolFrom(Map<String, Object?>? response, String key) {
    final value = response?[key];
    if (value is bool) {
      return value;
    }
    return null;
  }

  LocationPermissionPrecision _permissionPrecisionFrom(String? value) {
    return switch (value) {
      'precise' => LocationPermissionPrecision.precise,
      'approximate' => LocationPermissionPrecision.approximate,
      _ => LocationPermissionPrecision.unknown,
    };
  }

  String _locationErrorMessage(String code) {
    return switch (code) {
      'permissionDenied' => '위치 권한을 확인해 주세요.',
      'locationDisabled' => _currentLocationDisabledMessage,
      'locationUnavailable' => '현재 위치를 확인하지 못했습니다.',
      _ => '현재 위치를 확인하지 못했습니다.',
    };
  }
}

class StationSearchApiRepository
    implements StationSearchRepository, StationLineFilterRepository {
  StationSearchApiRepository({required this.baseUri, HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final Uri baseUri;
  final HttpClient _httpClient;

  @override
  Future<List<StationSearchResult>> searchStations(String query) async {
    return _searchStations({'query': query});
  }

  @override
  Future<List<StationSearchResult>> searchStationsOnLine(
    String query,
    String lineId,
  ) {
    return _searchStations({'query': query, 'lineId': lineId});
  }

  Future<List<StationSearchResult>> _searchStations(
    Map<String, String> queryParameters,
  ) async {
    final uri = baseUri
        .resolve('/api/v1/stations')
        .replace(queryParameters: queryParameters);

    final data = await _getData(uri);
    if (data is! List<Object?>) {
      throw const StationSearchException(_stationSearchErrorMessage);
    }

    try {
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid station payload');
            }
            return StationSearchResult.fromJson(item);
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 검색 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const StationSearchException(_stationSearchErrorMessage);
    }
  }

  @override
  Future<List<SubwayLineOption>> listLines() async {
    final data = await _getData(baseUri.resolve('/api/v1/lines'));
    if (data is! List<Object?>) {
      throw const StationSearchException(_stationSearchErrorMessage);
    }

    try {
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid line payload');
            }
            return SubwayLineOption.fromJson(item);
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '노선 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const StationSearchException(_stationSearchErrorMessage);
    }
  }

  @override
  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  }) async {
    final uri = baseUri
        .resolve('/api/v1/stations/nearby')
        .replace(
          queryParameters: {
            'lat': location.latitude.toString(),
            'lng': location.longitude.toString(),
            'radiusMeters': radiusMeters.toString(),
            'limit': limit.toString(),
          },
        );

    final data = await _getData(uri);
    if (data is! List<Object?>) {
      throw const StationSearchException(_stationSearchErrorMessage);
    }

    try {
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid nearby station payload');
            }
            return StationSearchResult.fromJson(item);
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '주변 역 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const StationSearchException(_stationSearchErrorMessage);
    }
  }

  @override
  Future<StationDetail> getStationDetail(String stationId) async {
    final uri = baseUri.resolve(
      '/api/v1/stations/${Uri.encodeComponent(stationId)}',
    );
    final data = await _getData(uri);
    if (data is! Map<String, Object?>) {
      throw const StationSearchException(_stationSearchErrorMessage);
    }
    try {
      return StationDetail.fromJson(data);
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '역 상세 응답 처리 중 예외가 발생했습니다.');
      throw const StationSearchException(_stationSearchErrorMessage);
    }
  }

  @override
  Future<List<StationExitInfo>> listStationExits(String stationId) async {
    final uri = baseUri.resolve(
      '/api/v1/stations/${Uri.encodeComponent(stationId)}/exits',
    );
    final data = await _getData(uri);
    if (data is! List<Object?>) {
      throw const StationSearchException(_stationSearchErrorMessage);
    }
    try {
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid station exit payload');
            }
            return StationExitInfo.fromJson(item);
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 출구 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const StationSearchException(_stationSearchErrorMessage);
    }
  }

  @override
  Future<List<StationFacilityInfo>> listStationFacilities(
    String stationId,
  ) async {
    final uri = baseUri.resolve(
      '/api/v1/stations/${Uri.encodeComponent(stationId)}/facilities',
    );
    final data = await _getData(uri);
    if (data is! List<Object?>) {
      throw const StationSearchException(_stationSearchErrorMessage);
    }
    try {
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid station facility payload');
            }
            return StationFacilityInfo.fromJson(item);
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 시설 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const StationSearchException(_stationSearchErrorMessage);
    }
  }

  Future<Object?> _getData(Uri uri) async {
    try {
      final request = await _httpClient
          .getUrl(uri)
          .timeout(_stationSearchTimeout);
      final response = await request.close().timeout(_stationSearchTimeout);
      final body = await utf8
          .decodeStream(response)
          .timeout(_stationSearchTimeout);

      if (response.statusCode != HttpStatus.ok) {
        throw const StationSearchException(_stationSearchErrorMessage);
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?> || decoded['success'] != true) {
        throw const StationSearchException(_stationSearchErrorMessage);
      }

      final data = decoded['data'];
      return data;
    } on StationSearchException {
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 정보 API 요청 처리 중 예외가 발생했습니다.',
      );
      throw const StationSearchException(_stationSearchErrorMessage);
    }
  }
}

class StationSearchException implements Exception {
  const StationSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class FavoriteStationRepository {
  Future<List<FavoriteStation>> listFavoriteStations();

  Future<FavoriteStation> saveFavoriteStation(String stationId);

  Future<void> removeFavoriteStation(String stationId);
}

typedef FavoriteStationAuthProvider = AuthorizationHeaderProvider;

class NoFavoriteStationAuthProvider extends NoAuthorizationHeaderProvider {
  const NoFavoriteStationAuthProvider();
}

class BasicFavoriteStationAuthProvider
    extends BasicAuthorizationHeaderProvider {
  const BasicFavoriteStationAuthProvider({
    required super.username,
    required super.password,
  });
}

class FavoriteStationApiRepository implements FavoriteStationRepository {
  FavoriteStationApiRepository({
    required this.baseUri,
    required this.authProvider,
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  final Uri baseUri;
  final FavoriteStationAuthProvider authProvider;
  final HttpClient _httpClient;

  @override
  Future<List<FavoriteStation>> listFavoriteStations() async {
    final data = await _requestData(
      'GET',
      baseUri.resolve('/api/v1/me/favorites/stations'),
      errorMessage: _favoriteStationLoadErrorMessage,
    );
    if (data is! List<Object?>) {
      throw const FavoriteStationException(_favoriteStationLoadErrorMessage);
    }

    try {
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid favorite station payload');
            }
            return FavoriteStation.fromJson(item);
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '즐겨찾기 역 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const FavoriteStationException(_favoriteStationLoadErrorMessage);
    }
  }

  @override
  Future<FavoriteStation> saveFavoriteStation(String stationId) async {
    final uri = baseUri.resolve(
      '/api/v1/me/favorites/stations/${Uri.encodeComponent(stationId)}',
    );
    final data = await _requestData(
      'PUT',
      uri,
      errorMessage: _favoriteStationChangeErrorMessage,
    );
    if (data is! Map<String, Object?>) {
      throw const FavoriteStationException(_favoriteStationChangeErrorMessage);
    }

    try {
      return FavoriteStation.fromJson(data);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '즐겨찾기 역 저장 응답 처리 중 예외가 발생했습니다.',
      );
      throw const FavoriteStationException(_favoriteStationChangeErrorMessage);
    }
  }

  @override
  Future<void> removeFavoriteStation(String stationId) async {
    final uri = baseUri.resolve(
      '/api/v1/me/favorites/stations/${Uri.encodeComponent(stationId)}',
    );
    await _requestData(
      'DELETE',
      uri,
      errorMessage: _favoriteStationChangeErrorMessage,
    );
  }

  Future<Object?> _requestData(
    String method,
    Uri uri, {
    required String errorMessage,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final request = await _httpClient
            .openUrl(method, uri)
            .timeout(_favoriteStationTimeout);
        final authorizationHeader = await authProvider
            .authorizationHeader()
            .timeout(_favoriteStationTimeout);
        if (authorizationHeader != null) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            authorizationHeader,
          );
        }

        final response = await request.close().timeout(_favoriteStationTimeout);
        final body = await utf8
            .decodeStream(response)
            .timeout(_favoriteStationTimeout);

        if (response.statusCode == HttpStatus.unauthorized &&
            authorizationHeader != null &&
            attempt == 0) {
          // 저장된 인증이 서버에서 만료된 경우 지우고 한 번만 재시도한다.
          await authProvider.invalidateAuthorization().timeout(
            _favoriteStationTimeout,
          );
          continue;
        }

        if (response.statusCode < HttpStatus.ok ||
            response.statusCode >= HttpStatus.multipleChoices) {
          throw FavoriteStationException(errorMessage);
        }

        final decoded = jsonDecode(body);
        if (decoded is! Map<String, Object?> || decoded['success'] != true) {
          throw FavoriteStationException(errorMessage);
        }
        return decoded['data'];
      } on FavoriteStationException {
        rethrow;
      } catch (error, stackTrace) {
        reportMobileError(
          error,
          stackTrace,
          context: '즐겨찾기 역 API 요청 처리 중 예외가 발생했습니다.',
        );
        throw FavoriteStationException(errorMessage);
      }
    }
    throw FavoriteStationException(errorMessage);
  }
}

class FavoriteStationException implements Exception {
  const FavoriteStationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FavoriteStation {
  const FavoriteStation({
    required this.userId,
    required this.stationId,
    required this.nameKo,
    required this.nameEn,
    required this.region,
    required this.dataQualityLevel,
    this.dataSourceType = '',
    required this.lastVerifiedAt,
    required this.lines,
    required this.addedAt,
  });

  factory FavoriteStation.fromJson(Map<String, Object?> json) {
    final rawLines = json['lines'];
    if (rawLines is! List<Object?>) {
      throw const FormatException('Invalid favorite station lines payload');
    }

    return FavoriteStation(
      userId: _requiredString(json, 'userId'),
      stationId: _requiredString(json, 'stationId'),
      nameKo: _requiredString(json, 'nameKo'),
      nameEn: _requiredString(json, 'nameEn'),
      region: _requiredString(json, 'region'),
      dataQualityLevel: _requiredString(json, 'dataQualityLevel'),
      dataSourceType: _stringOrEmpty(json, 'dataSourceType'),
      lastVerifiedAt: _requiredString(json, 'lastVerifiedAt'),
      lines: rawLines
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException(
                'Invalid favorite station line payload',
              );
            }
            return StationSearchLine.fromJson(item);
          })
          .toList(growable: false),
      addedAt: _requiredString(json, 'addedAt'),
    );
  }

  final String userId;
  final String stationId;
  final String nameKo;
  final String nameEn;
  final String region;
  final String dataQualityLevel;
  final String dataSourceType;
  final String lastVerifiedAt;
  final List<StationSearchLine> lines;
  final String addedAt;

  String get dataQualityLabel => _dataQualityLabel(dataQualityLevel);

  String get dataSourceLabel => _dataSourceLabel(dataSourceType);

  String get lineLabel {
    if (lines.isEmpty) {
      return '노선 정보 없음';
    }
    return lines.map((line) => line.name).join(', ');
  }

  String get semanticLabel {
    return '즐겨찾기 역, $nameKo, $lineLabel, $region, $dataQualityLabel, $dataSourceLabel';
  }
}

class StationSearchResult {
  const StationSearchResult({
    required this.id,
    required this.nameKo,
    required this.nameEn,
    required this.region,
    required this.dataQualityLevel,
    this.dataSourceType = '',
    required this.lastVerifiedAt,
    this.distanceMeters,
    required this.lines,
  });

  factory StationSearchResult.fromJson(Map<String, Object?> json) {
    final rawLines = json['lines'];
    if (rawLines is! List<Object?>) {
      throw const FormatException('Invalid station lines payload');
    }

    return StationSearchResult(
      id: _requiredString(json, 'id'),
      nameKo: _requiredString(json, 'nameKo'),
      nameEn: _requiredString(json, 'nameEn'),
      region: _requiredString(json, 'region'),
      dataQualityLevel: _requiredString(json, 'dataQualityLevel'),
      dataSourceType: _stringOrEmpty(json, 'dataSourceType'),
      lastVerifiedAt: _requiredString(json, 'lastVerifiedAt'),
      distanceMeters: _optionalInt(json, 'distanceMeters'),
      lines: rawLines
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid station line payload');
            }
            return StationSearchLine.fromJson(item);
          })
          .toList(growable: false),
    );
  }

  final String id;
  final String nameKo;
  final String nameEn;
  final String region;
  final String dataQualityLevel;
  final String dataSourceType;
  final String lastVerifiedAt;
  final int? distanceMeters;
  final List<StationSearchLine> lines;

  String get dataQualityLabel {
    return _dataQualityLabel(dataQualityLevel);
  }

  String get dataSourceLabel => _dataSourceLabel(dataSourceType);

  String get lineLabel {
    if (lines.isEmpty) {
      return '노선 정보 없음';
    }
    return lines.map((line) => line.name).join(', ');
  }

  String get distanceLabel {
    final distance = distanceMeters;
    if (distance == null) {
      return '';
    }
    if (distance < 1000) {
      return '${distance}m 거리';
    }
    return '${(distance / 1000).toStringAsFixed(1)}km 거리';
  }

  String get semanticLabel {
    final distance = distanceLabel;
    if (distance.isEmpty) {
      return '$nameKo, $lineLabel, $region, $dataQualityLabel';
    }
    return '$nameKo, $distance, $lineLabel, $region, $dataQualityLabel';
  }
}

class StationDetail {
  const StationDetail({
    required this.id,
    required this.nameKo,
    required this.nameEn,
    required this.region,
    this.latitude,
    this.longitude,
    required this.dataQualityLevel,
    this.dataSourceType = '',
    required this.lastVerifiedAt,
    required this.lines,
  });

  factory StationDetail.fromJson(Map<String, Object?> json) {
    final rawLines = json['lines'];
    if (rawLines is! List<Object?>) {
      throw const FormatException('Invalid station detail lines payload');
    }

    return StationDetail(
      id: _requiredString(json, 'id'),
      nameKo: _requiredString(json, 'nameKo'),
      nameEn: _requiredString(json, 'nameEn'),
      region: _requiredString(json, 'region'),
      latitude: _optionalDouble(json, 'latitude'),
      longitude: _optionalDouble(json, 'longitude'),
      dataQualityLevel: _requiredString(json, 'dataQualityLevel'),
      dataSourceType: _stringOrEmpty(json, 'dataSourceType'),
      lastVerifiedAt: _requiredString(json, 'lastVerifiedAt'),
      lines: rawLines
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException(
                'Invalid station detail line payload',
              );
            }
            return StationSearchLine.fromJson(item);
          })
          .toList(growable: false),
    );
  }

  final String id;
  final String nameKo;
  final String nameEn;
  final String region;
  final double? latitude;
  final double? longitude;
  final String dataQualityLevel;
  final String dataSourceType;
  final String lastVerifiedAt;
  final List<StationSearchLine> lines;

  String get dataQualityLabel => _dataQualityLabel(dataQualityLevel);

  String get dataSourceLabel => _dataSourceLabel(dataSourceType);

  String get lineLabel {
    if (lines.isEmpty) {
      return '노선 정보 없음';
    }
    return lines.map((line) => line.name).join(', ');
  }

  String get semanticLabel {
    return '$nameKo역 상세 정보, $lineLabel, $dataQualityLabel, $dataSourceLabel, 마지막 확인 $lastVerifiedAt';
  }
}

class StationExitInfo {
  const StationExitInfo({
    required this.id,
    required this.stationId,
    required this.exitNumber,
    required this.name,
    this.latitude,
    this.longitude,
    required this.hasElevatorConnection,
    required this.hasStairOnlyPath,
    required this.dataConfidence,
    this.dataSourceType = '',
  });

  factory StationExitInfo.fromJson(Map<String, Object?> json) {
    return StationExitInfo(
      id: _requiredString(json, 'id'),
      stationId: _requiredString(json, 'stationId'),
      exitNumber: _requiredString(json, 'exitNumber'),
      name: _requiredString(json, 'name'),
      latitude: _optionalDouble(json, 'latitude'),
      longitude: _optionalDouble(json, 'longitude'),
      hasElevatorConnection: _requiredBool(json, 'hasElevatorConnection'),
      hasStairOnlyPath: _requiredBool(json, 'hasStairOnlyPath'),
      dataConfidence: _requiredString(json, 'dataConfidence'),
      dataSourceType: _stringOrEmpty(json, 'dataSourceType'),
    );
  }

  final String id;
  final String stationId;
  final String exitNumber;
  final String name;
  final double? latitude;
  final double? longitude;
  final bool hasElevatorConnection;
  final bool hasStairOnlyPath;
  final String dataConfidence;
  final String dataSourceType;

  String get elevatorConnectionLabel {
    return hasElevatorConnection ? '엘리베이터 연결' : '엘리베이터 연결 확인 필요';
  }

  String get stairPathLabel {
    return hasStairOnlyPath ? '계단만 있는 길 있음' : '계단 없는 이동 가능';
  }

  String get confidenceLabel => _dataConfidenceLabel(dataConfidence);

  String get dataSourceLabel => _dataSourceLabel(dataSourceType);

  String get semanticLabel {
    return '$name, $elevatorConnectionLabel, $stairPathLabel, $confidenceLabel, $dataSourceLabel';
  }
}

class StationFacilityInfo {
  const StationFacilityInfo({
    required this.id,
    required this.stationId,
    required this.exitId,
    required this.type,
    required this.name,
    required this.floorFrom,
    required this.floorTo,
    this.latitude,
    this.longitude,
    required this.description,
    required this.status,
    required this.dataConfidence,
    this.dataSourceType = '',
    required this.lastUpdatedAt,
  });

  factory StationFacilityInfo.fromJson(Map<String, Object?> json) {
    return StationFacilityInfo(
      id: _requiredString(json, 'id'),
      stationId: _requiredString(json, 'stationId'),
      exitId: _stringOrEmpty(json, 'exitId'),
      type: _requiredString(json, 'type'),
      name: _requiredString(json, 'name'),
      floorFrom: _stringOrEmpty(json, 'floorFrom'),
      floorTo: _stringOrEmpty(json, 'floorTo'),
      latitude: _optionalDouble(json, 'latitude'),
      longitude: _optionalDouble(json, 'longitude'),
      description: _stringOrEmpty(json, 'description'),
      status: _requiredString(json, 'status'),
      dataConfidence: _requiredString(json, 'dataConfidence'),
      dataSourceType: _stringOrEmpty(json, 'dataSourceType'),
      lastUpdatedAt: _requiredString(json, 'lastUpdatedAt'),
    );
  }

  final String id;
  final String stationId;
  final String exitId;
  final String type;
  final String name;
  final String floorFrom;
  final String floorTo;
  final double? latitude;
  final double? longitude;
  final String description;
  final String status;
  final String dataConfidence;
  final String dataSourceType;
  final String lastUpdatedAt;

  String get typeLabel {
    return switch (type) {
      'ELEVATOR' => '엘리베이터',
      'ESCALATOR' => '에스컬레이터',
      'WHEELCHAIR_LIFT' => '휠체어 리프트',
      'RAMP' => '경사로',
      'ACCESSIBLE_TOILET' => '장애인 화장실',
      'TOILET' => '화장실',
      'NURSING_ROOM' => '수유실',
      'CUSTOMER_CENTER' => '고객센터',
      'STATION_OFFICE' => '역무실',
      _ => '시설',
    };
  }

  bool get isLayoutSummaryTarget {
    return switch (type) {
      'ELEVATOR' ||
      'WHEELCHAIR_LIFT' ||
      'RAMP' ||
      'ACCESSIBLE_TOILET' ||
      'NURSING_ROOM' ||
      'CUSTOMER_CENTER' ||
      'STATION_OFFICE' => true,
      _ => false,
    };
  }

  IconData get layoutSummaryIcon {
    return switch (type) {
      'ELEVATOR' => Icons.elevator,
      'WHEELCHAIR_LIFT' => Icons.accessible_forward,
      'RAMP' => Icons.accessible,
      'ACCESSIBLE_TOILET' => Icons.wc,
      'NURSING_ROOM' => Icons.child_care,
      'CUSTOMER_CENTER' || 'STATION_OFFICE' => Icons.support_agent,
      _ => Icons.place,
    };
  }

  int get layoutSummaryPriority {
    return switch (type) {
      'ELEVATOR' => 10,
      'WHEELCHAIR_LIFT' => 20,
      'RAMP' => 30,
      'ACCESSIBLE_TOILET' => 40,
      'NURSING_ROOM' => 50,
      'CUSTOMER_CENTER' || 'STATION_OFFICE' => 60,
      _ => 90,
    };
  }

  String get statusLabel {
    return switch (status) {
      'NORMAL' => '정상',
      'BROKEN' => '고장',
      'UNDER_CONSTRUCTION' => '공사 중',
      'CONSTRUCTION' => '공사 중',
      'CLOSED' => '폐쇄',
      'UNKNOWN' => '확인 필요',
      'USER_REPORTED' => '제보됨',
      'ADMIN_VERIFIED' => '검수 완료',
      'NEEDS_REPORT' => '제보 필요',
      'NEEDS_CHECK' => '확인 필요',
      _ => '상태 확인 필요',
    };
  }

  bool get needsAttention => statusPriority < 40;

  int get statusPriority {
    return switch (status) {
      'BROKEN' || 'CLOSED' => 10,
      'UNDER_CONSTRUCTION' || 'CONSTRUCTION' => 20,
      'USER_REPORTED' || 'UNKNOWN' || 'NEEDS_REPORT' || 'NEEDS_CHECK' => 30,
      'NORMAL' || 'ADMIN_VERIFIED' => 40,
      _ => 30,
    };
  }

  String get confidenceLabel => _dataConfidenceLabel(dataConfidence);

  String get dataSourceLabel => _dataSourceLabel(dataSourceType);

  String get locationLabel {
    if (description.trim().isNotEmpty) {
      return description;
    }
    if (floorFrom.trim().isNotEmpty && floorTo.trim().isNotEmpty) {
      return '$floorFrom-$floorTo';
    }
    return '위치 확인 필요';
  }

  String get updatedLabel => '최근 확인 $lastUpdatedAt';

  String get semanticLabel {
    return '$name, $typeLabel, $statusLabel, $locationLabel, $updatedLabel, $confidenceLabel, $dataSourceLabel';
  }
}

class StationLayoutSummaryItem {
  const StationLayoutSummaryItem({required this.icon, required this.text});

  final IconData icon;
  final String text;
}

class StationSearchLine {
  const StationSearchLine({
    required this.id,
    required this.name,
    required this.color,
    required this.stationCode,
  });

  factory StationSearchLine.fromJson(Map<String, Object?> json) {
    return StationSearchLine(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      color: _requiredString(json, 'color'),
      stationCode: _requiredString(json, 'stationCode'),
    );
  }

  static const _knownBadgeLabels = <String, String>{
    '경의중앙': '경의중앙',
    '수인분당': '수인분당',
    '신분당': '신분당',
    '인천1': '인천1',
    '인천2': '인천2',
  };

  final String id;
  final String name;
  final String color;
  final String stationCode;

  String get badgeText => _lineBadgeText(name);

  Color get badgeColor {
    final normalized = color.trim().replaceFirst('#', '');
    if (normalized.length == 6) {
      final parsed = int.tryParse(normalized, radix: 16);
      if (parsed != null) {
        return Color(0xFF000000 | parsed);
      }
    }
    return const Color(0xFF006D77);
  }
}

class SubwayLineOption {
  const SubwayLineOption({
    required this.id,
    required this.name,
    required this.color,
    required this.region,
    required this.lineCode,
    required this.active,
  });

  factory SubwayLineOption.fromJson(Map<String, Object?> json) {
    return SubwayLineOption(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      color: _requiredString(json, 'color'),
      region: _requiredString(json, 'region'),
      lineCode: _stringOrEmpty(json, 'lineCode'),
      active: _requiredBool(json, 'active'),
    );
  }

  final String id;
  final String name;
  final String color;
  final String region;
  final String lineCode;
  final bool active;

  String get shortLabel {
    if (lineCode.trim().isNotEmpty) {
      return lineCode.trim();
    }
    return _lineBadgeText(name);
  }

  String get semanticLabel => name;

  Color get badgeColor {
    final normalized = color.trim().replaceFirst('#', '');
    if (normalized.length == 6) {
      final parsed = int.tryParse(normalized, radix: 16);
      if (parsed != null) {
        return Color(0xFF000000 | parsed);
      }
    }
    return const Color(0xFF006D77);
  }
}

String _lineBadgeText(String name) {
  for (final entry in StationSearchLine._knownBadgeLabels.entries) {
    if (name.contains(entry.key)) {
      return entry.value;
    }
  }

  final numberedLine = RegExp(r'(\d+)\s*호선').firstMatch(name);
  if (numberedLine != null) {
    return numberedLine.group(1) ?? name;
  }

  final compactName = name
      .replaceAll('수도권 ', '')
      .replaceAll('광역 ', '')
      .replaceAll('선', '')
      .trim();
  if (compactName.length <= 4) {
    return compactName;
  }
  return compactName.substring(0, 4);
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('Missing required station field: $key');
}

String _stringOrEmpty(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) {
    return value;
  }
  return '';
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('Missing required station boolean field: $key');
}

double? _optionalDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String && value.trim().isNotEmpty) {
    return double.tryParse(value);
  }
  return null;
}

int? _optionalInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    if (value % 1 == 0) {
      return value.toInt();
    }
    throw FormatException('Invalid integer station field: $key');
  }
  if (value is String && value.trim().isNotEmpty) {
    final parsed = int.tryParse(value);
    if (parsed == null) {
      throw FormatException('Invalid integer station field: $key');
    }
    return parsed;
  }
  return null;
}

String _dataQualityLabel(String dataQualityLevel) {
  return switch (dataQualityLevel) {
    'LEVEL_1' => '기본 정보만 있음',
    'LEVEL_2' => '시설 정보 확인됨',
    'LEVEL_3' => '쉬운 길 안내 가능',
    'LEVEL_4' => '고장·공사 반영됨',
    _ => '정보 확인 필요',
  };
}

String _dataConfidenceLabel(String dataConfidence) {
  return switch (dataConfidence) {
    'HIGH' => '정보 신뢰도 높음',
    'MEDIUM' => '정보 신뢰도 보통',
    'LOW' => '정보 확인 필요',
    _ => '정보 확인 필요',
  };
}

String _dataSourceLabel(String dataSourceType) {
  return switch (dataSourceType) {
    'OFFICIAL_API' => '출처 공공 API',
    'OFFICIAL_FILE' => '출처 공식 파일',
    'OPERATOR_PAGE' => '출처 운영기관 페이지',
    'USER_REPORT' => '출처 사용자 제보',
    'ADMIN_VERIFIED' => '출처 관리자 검수',
    'PARTNER_FEED' => '출처 제휴 데이터',
    _ => '출처 확인 필요',
  };
}

enum StationSearchStatus { idle, loading, success, empty, failure }

class StationSearchState {
  const StationSearchState({
    required this.status,
    required this.results,
    this.message = '',
  });

  const StationSearchState.idle()
    : status = StationSearchStatus.idle,
      results = const [],
      message = '';

  final StationSearchStatus status;
  final List<StationSearchResult> results;
  final String message;
}

class StationSearchController extends ChangeNotifier {
  StationSearchController({
    required this.repository,
    this.searchHistoryRepository,
  });

  final StationSearchRepository repository;
  final SearchHistoryRepository? searchHistoryRepository;

  StationSearchState _state = const StationSearchState.idle();
  int _searchRequestId = 0;
  bool _isDisposed = false;

  StationSearchState get state => _state;

  Future<void> search(String query, {String? lineId}) async {
    final requestId = ++_searchRequestId;
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      _state = const StationSearchState.idle();
      _notifyIfActive(requestId);
      return;
    }

    _state = const StationSearchState(
      status: StationSearchStatus.loading,
      results: [],
    );
    _notifyIfActive(requestId);

    try {
      final selectedLineId = lineId?.trim();
      final results =
          selectedLineId != null &&
              selectedLineId.isNotEmpty &&
              repository is StationLineFilterRepository
          ? await (repository as StationLineFilterRepository)
                .searchStationsOnLine(trimmedQuery, selectedLineId)
          : await repository.searchStations(trimmedQuery);
      if (!_isActiveRequest(requestId)) {
        return;
      }
      await _recordSearch(trimmedQuery);
      if (results.isEmpty) {
        _state = const StationSearchState(
          status: StationSearchStatus.empty,
          results: [],
          message: '검색 결과가 없습니다.',
        );
      } else {
        _state = StationSearchState(
          status: StationSearchStatus.success,
          results: results,
        );
      }
    } on StationSearchException catch (error) {
      if (!_isActiveRequest(requestId)) {
        return;
      }
      _state = StationSearchState(
        status: StationSearchStatus.failure,
        results: const [],
        message: error.message,
      );
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '역 검색 화면 처리 중 예외가 발생했습니다.');
      if (!_isActiveRequest(requestId)) {
        return;
      }
      _state = const StationSearchState(
        status: StationSearchStatus.failure,
        results: [],
        message: '역 정보를 불러오지 못했습니다.',
      );
    }
    _notifyIfActive(requestId);
  }

  Future<void> _recordSearch(String query) async {
    final repository = searchHistoryRepository;
    if (repository == null) {
      return;
    }
    try {
      await repository.recordSearch(query);
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '최근 검색어 저장 중 예외가 발생했습니다.');
    }
  }

  Future<void> searchNearby(CurrentLocationProvider locationProvider) async {
    final requestId = ++_searchRequestId;
    _state = const StationSearchState(
      status: StationSearchStatus.loading,
      results: [],
    );
    _notifyIfActive(requestId);

    try {
      final location = await locationProvider.currentLocation();
      final blockedMessage = location.nearbySearchBlockedMessage();
      if (blockedMessage != null) {
        if (!_isActiveRequest(requestId)) {
          return;
        }
        _state = StationSearchState(
          status: StationSearchStatus.failure,
          results: const [],
          message: blockedMessage,
        );
        _notifyIfActive(requestId);
        return;
      }
      final results = await repository.searchNearbyStations(location);
      if (!_isActiveRequest(requestId)) {
        return;
      }
      if (results.isEmpty) {
        _state = const StationSearchState(
          status: StationSearchStatus.empty,
          results: [],
          message: '주변 역을 찾지 못했습니다.',
        );
      } else {
        _state = StationSearchState(
          status: StationSearchStatus.success,
          results: results,
        );
      }
    } on CurrentLocationException catch (error) {
      if (!_isActiveRequest(requestId)) {
        return;
      }
      _state = StationSearchState(
        status: StationSearchStatus.failure,
        results: const [],
        message: error.message,
      );
    } on StationSearchException catch (error) {
      if (!_isActiveRequest(requestId)) {
        return;
      }
      _state = StationSearchState(
        status: StationSearchStatus.failure,
        results: const [],
        message: error.message,
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '주변 역 검색 화면 처리 중 예외가 발생했습니다.',
      );
      if (!_isActiveRequest(requestId)) {
        return;
      }
      _state = const StationSearchState(
        status: StationSearchStatus.failure,
        results: [],
        message: '역 정보를 불러오지 못했습니다.',
      );
    }
    _notifyIfActive(requestId);
  }

  bool _isActiveRequest(int requestId) {
    return !_isDisposed && requestId == _searchRequestId;
  }

  void _notifyIfActive(int requestId) {
    if (_isActiveRequest(requestId)) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _searchRequestId++;
    super.dispose();
  }
}

enum StationDetailStatus { loading, success, failure }

class StationDetailState {
  const StationDetailState({
    required this.status,
    this.detail,
    this.exits = const [],
    this.facilities = const [],
    this.message = '',
  });

  const StationDetailState.loading()
    : status = StationDetailStatus.loading,
      detail = null,
      exits = const [],
      facilities = const [],
      message = '';

  final StationDetailStatus status;
  final StationDetail? detail;
  final List<StationExitInfo> exits;
  final List<StationFacilityInfo> facilities;
  final String message;

  List<StationFacilityInfo> get prioritizedFacilities {
    final sorted = List<StationFacilityInfo>.of(facilities);
    sorted.sort((left, right) {
      // 이동에 영향을 주는 시설 상태를 먼저 보여 사용자가 우회 여부를 빨리 판단하게 한다.
      final priority = left.statusPriority.compareTo(right.statusPriority);
      if (priority != 0) {
        return priority;
      }
      return left.name.compareTo(right.name);
    });
    return List.unmodifiable(sorted);
  }

  int get attentionFacilityCount {
    return facilities.where((facility) => facility.needsAttention).length;
  }

  String get facilityAttentionSummary {
    final count = attentionFacilityCount;
    if (count == 0) {
      return '확인 필요 없음';
    }
    return '확인 필요 $count개';
  }

  String get facilityAttentionSemanticLabel {
    final count = attentionFacilityCount;
    if (count == 0) {
      return '확인이 필요한 시설 없음';
    }
    return '확인이 필요한 시설 $count개';
  }

  List<StationLayoutSummaryItem> get layoutSummaryItems {
    final items = <StationLayoutSummaryItem>[];
    // 역 전체 구조를 짧게 보여주기 위해 엘리베이터 연결 출구를 우선 시작점으로 삼는다.
    final accessibleExit = exits
        .where((exit) => exit.hasElevatorConnection)
        .firstOrNull;
    final firstExit = exits.isNotEmpty ? exits.first : null;
    final exit = accessibleExit ?? firstExit;
    if (exit != null) {
      items.add(
        StationLayoutSummaryItem(icon: Icons.exit_to_app, text: exit.name),
      );
    }

    for (final facility in _layoutSummaryFacilities()) {
      items.add(
        StationLayoutSummaryItem(
          icon: facility.layoutSummaryIcon,
          text: facility.typeLabel,
        ),
      );
    }

    if (items.isNotEmpty) {
      items.add(const StationLayoutSummaryItem(icon: Icons.train, text: '승강장'));
    }
    return List.unmodifiable(items);
  }

  String get layoutSummarySemanticLabel {
    final items = layoutSummaryItems;
    if (items.isEmpty) {
      return '이동 구조 정보 없음';
    }
    return '이동 구조, ${items.map((item) => item.text).join(', ')}';
  }

  List<StationFacilityInfo> _layoutSummaryFacilities() {
    final seenTypes = <String>{};
    final summaryFacilities = <StationFacilityInfo>[];
    final candidates = facilities
        .where((facility) => facility.isLayoutSummaryTarget)
        .toList();
    candidates.sort((left, right) {
      // 고장 여부보다 시설 유형 순서를 먼저 고정해 이동 흐름이 매번 같은 순서로 보이게 한다.
      final typePriority = left.layoutSummaryPriority.compareTo(
        right.layoutSummaryPriority,
      );
      if (typePriority != 0) {
        return typePriority;
      }
      final statusPriority = left.statusPriority.compareTo(
        right.statusPriority,
      );
      if (statusPriority != 0) {
        return statusPriority;
      }
      return left.name.compareTo(right.name);
    });

    for (final facility in candidates) {
      if (seenTypes.contains(facility.type)) {
        continue;
      }
      seenTypes.add(facility.type);
      summaryFacilities.add(facility);
      if (summaryFacilities.length == 3) {
        break;
      }
    }
    return summaryFacilities;
  }
}

class StationDetailController extends ChangeNotifier {
  StationDetailController({required this.repository});

  final StationSearchRepository repository;

  StationDetailState _state = const StationDetailState.loading();
  bool _isDisposed = false;

  StationDetailState get state => _state;

  Future<void> load(String stationId) async {
    _state = const StationDetailState.loading();
    notifyListeners();

    try {
      // 상세 화면은 기본 정보, 출구, 시설을 함께 읽되 느린 네트워크에서 대기 시간이 합산되지 않게 병렬로 요청한다.
      final responses = await Future.wait<Object>([
        repository.getStationDetail(stationId),
        repository.listStationExits(stationId),
        repository.listStationFacilities(stationId),
      ]);
      if (_isDisposed) {
        return;
      }
      _state = StationDetailState(
        status: StationDetailStatus.success,
        detail: responses[0] as StationDetail,
        exits: responses[1] as List<StationExitInfo>,
        facilities: responses[2] as List<StationFacilityInfo>,
      );
    } on StationSearchException {
      if (_isDisposed) {
        return;
      }
      _state = const StationDetailState(
        status: StationDetailStatus.failure,
        message: '역 상세 정보를 불러오지 못했습니다.',
      );
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '역 상세 화면 로드 중 예외가 발생했습니다.');
      if (_isDisposed) {
        return;
      }
      _state = const StationDetailState(
        status: StationDetailStatus.failure,
        message: '역 상세 정보를 불러오지 못했습니다.',
      );
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

enum FavoriteStationListStatus { loading, success, empty, failure }

class FavoriteStationListState {
  const FavoriteStationListState({
    required this.status,
    this.favorites = const [],
    this.message = '',
  });

  const FavoriteStationListState.loading()
    : status = FavoriteStationListStatus.loading,
      favorites = const [],
      message = '';

  final FavoriteStationListStatus status;
  final List<FavoriteStation> favorites;
  final String message;
}

class FavoriteStationListController extends ChangeNotifier {
  FavoriteStationListController({required this.repository});

  final FavoriteStationRepository repository;

  FavoriteStationListState _state = const FavoriteStationListState.loading();
  bool _isDisposed = false;

  FavoriteStationListState get state => _state;

  Future<void> load() async {
    _emitState(const FavoriteStationListState.loading());

    try {
      final favorites = await repository.listFavoriteStations();
      if (favorites.isEmpty) {
        _emitState(
          const FavoriteStationListState(
            status: FavoriteStationListStatus.empty,
            message: '저장한 역이 없습니다.',
          ),
        );
      } else {
        _emitState(
          FavoriteStationListState(
            status: FavoriteStationListStatus.success,
            favorites: favorites,
          ),
        );
      }
    } on FavoriteStationException catch (error) {
      _emitState(
        FavoriteStationListState(
          status: FavoriteStationListStatus.failure,
          message: error.message,
        ),
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '즐겨찾기 역 목록 화면 로드 중 예외가 발생했습니다.',
      );
      _emitState(
        const FavoriteStationListState(
          status: FavoriteStationListStatus.failure,
          message: _favoriteStationLoadErrorMessage,
        ),
      );
    }
  }

  void _emitState(FavoriteStationListState nextState) {
    if (_isDisposed) {
      return;
    }
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

enum StationFavoriteToggleStatus { checking, ready, saving, removing, failure }

class StationFavoriteToggleState {
  const StationFavoriteToggleState({
    required this.status,
    required this.isFavorite,
    this.message = '',
  });

  const StationFavoriteToggleState.ready({required this.isFavorite})
    : status = StationFavoriteToggleStatus.ready,
      message = '';

  const StationFavoriteToggleState.checking({required this.isFavorite})
    : status = StationFavoriteToggleStatus.checking,
      message = '';

  final StationFavoriteToggleStatus status;
  final bool isFavorite;
  final String message;

  bool get isBusy {
    return status == StationFavoriteToggleStatus.checking ||
        status == StationFavoriteToggleStatus.saving ||
        status == StationFavoriteToggleStatus.removing;
  }

  bool get isChanging {
    return status == StationFavoriteToggleStatus.saving ||
        status == StationFavoriteToggleStatus.removing;
  }
}

class StationFavoriteToggleController extends ChangeNotifier {
  StationFavoriteToggleController({
    required this.repository,
    required this.stationId,
    bool initiallyFavorite = false,
    bool initiallyChecking = false,
  }) : _state = initiallyChecking
           ? StationFavoriteToggleState.checking(isFavorite: initiallyFavorite)
           : StationFavoriteToggleState.ready(isFavorite: initiallyFavorite);

  final FavoriteStationRepository repository;
  final String stationId;

  StationFavoriteToggleState _state;
  bool _isDisposed = false;

  StationFavoriteToggleState get state => _state;

  Future<void> load() async {
    if (_state.isChanging) {
      return;
    }

    _emitState(
      StationFavoriteToggleState.checking(isFavorite: _state.isFavorite),
    );

    try {
      final favorites = await repository.listFavoriteStations();
      final isFavorite = favorites.any(
        (favorite) => favorite.stationId == stationId,
      );
      _emitState(StationFavoriteToggleState.ready(isFavorite: isFavorite));
    } on FavoriteStationException catch (error) {
      _emitFailure(error.message);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 즐겨찾기 상태 확인 중 예외가 발생했습니다.',
      );
      _emitFailure(_favoriteStationStatusErrorMessage);
    }
  }

  Future<void> save() async {
    if (_state.isBusy) {
      return;
    }

    _emitState(
      StationFavoriteToggleState(
        status: StationFavoriteToggleStatus.saving,
        isFavorite: _state.isFavorite,
      ),
    );

    try {
      await repository.saveFavoriteStation(stationId);
      _emitState(
        const StationFavoriteToggleState(
          status: StationFavoriteToggleStatus.ready,
          isFavorite: true,
          message: '즐겨찾기에 저장했습니다.',
        ),
      );
    } on FavoriteStationException catch (error) {
      _emitFailure(error.message);
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '역 즐겨찾기 저장 중 예외가 발생했습니다.');
      _emitFailure(_favoriteStationChangeErrorMessage);
    }
  }

  Future<void> remove() async {
    if (_state.isBusy) {
      return;
    }

    _emitState(
      StationFavoriteToggleState(
        status: StationFavoriteToggleStatus.removing,
        isFavorite: _state.isFavorite,
      ),
    );

    try {
      await repository.removeFavoriteStation(stationId);
      _emitState(
        const StationFavoriteToggleState(
          status: StationFavoriteToggleStatus.ready,
          isFavorite: false,
          message: '즐겨찾기에서 해제했습니다.',
        ),
      );
    } on FavoriteStationException catch (error) {
      _emitFailure(error.message);
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '역 즐겨찾기 해제 중 예외가 발생했습니다.');
      _emitFailure(_favoriteStationChangeErrorMessage);
    }
  }

  void _emitFailure(String message) {
    _emitState(
      StationFavoriteToggleState(
        status: StationFavoriteToggleStatus.failure,
        isFavorite: _state.isFavorite,
        message: message,
      ),
    );
  }

  void _emitState(StationFavoriteToggleState nextState) {
    if (_isDisposed) {
      return;
    }
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

class StationSearchScreen extends StatefulWidget {
  const StationSearchScreen({
    required this.repository,
    required this.reportRepository,
    required this.locationProvider,
    this.favoriteRepository,
    this.searchHistoryRepository,
    this.facilityReportDraftTargetStore,
    this.internalRouteRepository,
    this.internalRouteMobilityType = 'SENIOR',
    super.key,
  });

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final CurrentLocationProvider locationProvider;
  final FavoriteStationRepository? favoriteRepository;
  final SearchHistoryRepository? searchHistoryRepository;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final InternalRouteRepository? internalRouteRepository;
  final String internalRouteMobilityType;

  @override
  State<StationSearchScreen> createState() => _StationSearchScreenState();
}

class _StationSearchScreenState extends State<StationSearchScreen> {
  late final StationSearchController _controller;
  final TextEditingController _queryController = TextEditingController();
  Future<List<SubwayLineOption>>? _lineOptionsFuture;
  SubwayLineOption? _selectedLine;
  bool _isNearbySearchRunning = false;
  bool _isOpeningLocationSettings = false;

  @override
  void initState() {
    super.initState();
    _controller = StationSearchController(
      repository: widget.repository,
      searchHistoryRepository: widget.searchHistoryRepository,
    );
    _queryController.addListener(_handleQueryChanged);
    final lineRepository = _lineFilterRepository;
    if (lineRepository != null) {
      _lineOptionsFuture = lineRepository.listLines();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _queryController.removeListener(_handleQueryChanged);
    _queryController.dispose();
    super.dispose();
  }

  void _handleQueryChanged() {
    if (!mounted) {
      return;
    }
    if (!_hasSearchQuery &&
        !_isNearbySearchRunning &&
        _controller.state.status != StationSearchStatus.idle) {
      _controller.search('');
    }
    setState(() {});
  }

  bool get _hasSearchQuery => _queryController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('역 검색')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            if (_lineOptionsFuture != null) ...[
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final isSearching =
                      _controller.state.status == StationSearchStatus.loading;
                  return _StationLineFilterSection(
                    linesFuture: _lineOptionsFuture!,
                    selectedLine: _selectedLine,
                    enabled: !isSearching && !_isNearbySearchRunning,
                    onLineSelected: _selectLine,
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
            Semantics(
              label: '역 이름을 입력해 주세요',
              textField: true,
              child: TextField(
                key: const Key('stationSearchInput'),
                controller: _queryController,
                minLines: 1,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 20, height: 1.35),
                decoration: const InputDecoration(
                  labelText: '역 이름',
                  hintText: '역 이름을 입력해 주세요',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
                onSubmitted: _submit,
              ),
            ),
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final isSearching =
                    _controller.state.status == StationSearchStatus.loading;
                final isNearbyDisabled = isSearching || _isNearbySearchRunning;
                if (_hasSearchQuery) {
                  return FilledButton.icon(
                    key: const Key('stationSearchSubmitButton'),
                    onPressed: isSearching
                        ? null
                        : () => _submit(_queryController.text),
                    icon: const Icon(Icons.search),
                    label: const Text('검색'),
                  );
                }
                return OutlinedButton.icon(
                  key: const Key('nearbyStationSearchButton'),
                  onPressed: isNearbyDisabled ? null : _searchNearby,
                  icon: const Icon(Icons.my_location),
                  label: const Text('내 주변 역 찾기'),
                );
              },
            ),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return _StationSearchBody(
                  state: _controller.state,
                  onResultTap: _openStationDetail,
                  isOpeningLocationSettings: _isOpeningLocationSettings,
                  onOpenLocationSettings: _openLocationSettings,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _submit(String query) {
    if (_controller.state.status == StationSearchStatus.loading) {
      return;
    }
    _controller.search(query, lineId: _selectedLine?.id);
  }

  StationLineFilterRepository? get _lineFilterRepository {
    final Object repository = widget.repository;
    if (repository is StationLineFilterRepository) {
      return repository;
    }
    return null;
  }

  void _selectLine(SubwayLineOption? line) {
    setState(() => _selectedLine = line);
  }

  Future<void> _searchNearby() async {
    if (_controller.state.status == StationSearchStatus.loading ||
        _isNearbySearchRunning) {
      return;
    }
    setState(() => _isNearbySearchRunning = true);
    try {
      final shouldContinue = await _confirmLocationUseIfNeeded();
      if (!shouldContinue) {
        return;
      }
      await _controller.searchNearby(widget.locationProvider);
    } finally {
      if (mounted) {
        setState(() => _isNearbySearchRunning = false);
      }
    }
  }

  Future<bool> _confirmLocationUseIfNeeded() async {
    var needsPermissionRequest = true;
    try {
      needsPermissionRequest = await widget.locationProvider
          .needsLocationPermissionRequest();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '주변 역 위치 권한 사전 확인 중 예외가 발생했습니다.',
      );
    }
    if (!needsPermissionRequest) {
      return true;
    }
    if (!mounted) {
      return false;
    }
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text(_locationPermissionRationaleTitle),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_locationPermissionRationalePurpose),
                SizedBox(height: 8),
                Text(_locationPermissionRationaleFallback),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('계속'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _openLocationSettings() async {
    if (_isOpeningLocationSettings) {
      return;
    }
    setState(() => _isOpeningLocationSettings = true);
    try {
      await widget.locationProvider.openLocationSettings();
    } finally {
      if (mounted) {
        setState(() => _isOpeningLocationSettings = false);
      }
    }
  }

  void _openStationDetail(StationSearchResult result) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StationDetailScreen(
          repository: widget.repository,
          reportRepository: widget.reportRepository,
          favoriteRepository: widget.favoriteRepository,
          locationProvider: widget.locationProvider,
          stationId: result.id,
          facilityReportDraftTargetStore: widget.facilityReportDraftTargetStore,
          internalRouteRepository: widget.internalRouteRepository,
          internalRouteMobilityType: widget.internalRouteMobilityType,
        ),
      ),
    );
  }
}

class _StationLineFilterSection extends StatelessWidget {
  const _StationLineFilterSection({
    required this.linesFuture,
    required this.selectedLine,
    required this.enabled,
    required this.onLineSelected,
  });

  final Future<List<SubwayLineOption>> linesFuture;
  final SubwayLineOption? selectedLine;
  final bool enabled;
  final ValueChanged<SubwayLineOption?> onLineSelected;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SubwayLineOption>>(
      future: linesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 56,
            child: Align(
              alignment: Alignment.centerLeft,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          );
        }

        if (snapshot.hasError) {
          return Text(
            '노선을 불러오지 못했습니다.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF29484B),
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          );
        }

        final lines = (snapshot.data ?? const <SubwayLineOption>[])
            .where((line) => line.active)
            .toList(growable: false);
        if (lines.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '노선',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF102A2C),
                fontWeight: FontWeight.w900,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _StationLineFilterButton(
                  key: const Key('stationLineFilter-all'),
                  label: '전체',
                  semanticLabel: '전체 노선',
                  selected: selectedLine == null,
                  onPressed: enabled ? () => onLineSelected(null) : null,
                ),
                for (final line in lines)
                  _StationLineFilterButton(
                    key: Key('stationLineFilter-${line.id}'),
                    label: line.name,
                    semanticLabel: line.semanticLabel,
                    selected: selectedLine?.id == line.id,
                    badgeText: line.shortLabel,
                    badgeColor: line.badgeColor,
                    onPressed: enabled ? () => onLineSelected(line) : null,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _StationLineFilterButton extends StatelessWidget {
  const _StationLineFilterButton({
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.onPressed,
    this.badgeText,
    this.badgeColor,
    super.key,
  });

  final String label;
  final String semanticLabel;
  final bool selected;
  final VoidCallback? onPressed;
  final String? badgeText;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = selected ? const Color(0xFF007A80) : Colors.white;
    final foregroundColor = selected ? Colors.white : const Color(0xFF102A2C);
    final borderColor = selected
        ? const Color(0xFF007A80)
        : const Color(0xFF93C7C2);

    return Semantics(
      label: '$semanticLabel ${selected ? '선택됨' : '선택 안 됨'}',
      button: true,
      selected: selected,
      enabled: onPressed != null,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(96, 56),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            side: BorderSide(color: borderColor, width: selected ? 2 : 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badgeText != null && badgeColor != null) ...[
                _LineFilterBadge(text: badgeText!, color: badgeColor!),
                const SizedBox(width: 8),
              ],
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineFilterBadge extends StatelessWidget {
  const _LineFilterBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textColor = _higherContrastTextColor(color);
    final fontSize = RegExp(r'^\d+$').hasMatch(text) ? 20.0 : 12.0;

    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        text,
        maxLines: 2,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: textColor,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          height: 1.0,
        ),
      ),
    );
  }
}

class _StationSearchBody extends StatelessWidget {
  const _StationSearchBody({
    required this.state,
    required this.onResultTap,
    required this.isOpeningLocationSettings,
    required this.onOpenLocationSettings,
  });

  final StationSearchState state;
  final ValueChanged<StationSearchResult> onResultTap;
  final bool isOpeningLocationSettings;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    return switch (state.status) {
      StationSearchStatus.idle => const SizedBox.shrink(),
      StationSearchStatus.loading => Semantics(
        label: '역 검색 중',
        liveRegion: true,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
      StationSearchStatus.empty ||
      StationSearchStatus.failure => _StationSearchFailureMessage(
        message: state.message,
        isOpeningLocationSettings: isOpeningLocationSettings,
        onOpenLocationSettings: onOpenLocationSettings,
      ),
      StationSearchStatus.success => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: '검색 결과 ${state.results.length}개',
            liveRegion: true,
            child: const SizedBox.shrink(),
          ),
          for (final result in state.results)
            _StationSearchResultTile(
              result: result,
              onTap: () => onResultTap(result),
            ),
        ],
      ),
    };
  }
}

class _StationSearchFailureMessage extends StatelessWidget {
  const _StationSearchFailureMessage({
    required this.message,
    required this.isOpeningLocationSettings,
    required this.onOpenLocationSettings,
  });

  final String message;
  final bool isOpeningLocationSettings;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    final shouldShowLocationSettings =
        message == _currentLocationDisabledMessage;
    final shouldShowStationSearchFallback =
        _shouldShowStationSearchFailureNextAction(message);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StationSearchMessage(message: message, liveRegion: true),
        if (shouldShowStationSearchFallback) ...[
          const SizedBox(height: 8),
          Semantics(
            key: const Key('stationSearchFailureNextAction'),
            container: true,
            excludeSemantics: true,
            label: '다음 행동, $_stationSearchFailureNextAction',
            child: Text(
              _stationSearchFailureNextAction,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF506B6F),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
        if (shouldShowLocationSettings) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('stationSearchOpenLocationSettingsButton'),
            onPressed: isOpeningLocationSettings
                ? null
                : onOpenLocationSettings,
            icon: isOpeningLocationSettings
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.settings),
            label: const Text('위치 설정 열기'),
          ),
        ],
      ],
    );
  }
}

bool _shouldShowStationSearchFailureNextAction(String message) {
  return message == '위치 권한을 확인해 주세요.' ||
      message == _currentLocationDisabledMessage ||
      message == '현재 위치를 확인하지 못했습니다.' ||
      message == '주변 역을 찾지 못했습니다.';
}

class _StationSearchMessage extends StatelessWidget {
  const _StationSearchMessage({required this.message, this.liveRegion = false});

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

class _StationSearchResultTile extends StatelessWidget {
  const _StationSearchResultTile({required this.result, required this.onTap});

  final StationSearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final stationName = _stationResultDisplayName(result.nameKo);
    final semanticLabel = _stationResultSemanticLabel(result);

    return MergeSemantics(
      child: Semantics(
        label: semanticLabel,
        button: true,
        onTap: onTap,
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
              key: Key('stationSearchResult-${result.id}'),
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 88),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 72),
                        child: StationLineBadges(
                          lines: result.lines,
                          size: 32,
                          maxBadgeCount: 2,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stationName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.headlineSmall?.copyWith(
                                color: const Color(0xFF102A2C),
                                fontWeight: FontWeight.w900,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              result.distanceLabel.isEmpty
                                  ? result.lineLabel
                                  : '${result.distanceLabel} · ${result.lineLabel}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyLarge?.copyWith(
                                color: const Color(0xFF29484B),
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${result.dataQualityLabel} · ${result.dataSourceLabel}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF405A5D),
                                fontWeight: FontWeight.w800,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.chevron_right,
                        color: Color(0xFF405A5D),
                        size: 30,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _stationResultDisplayName(String name) {
  final trimmedName = name.trim();
  // 백엔드 역 이름은 접미사 없이 내려올 수 있어 검색 결과 화면에서만 보정한다.
  if (trimmedName.endsWith('역')) {
    return trimmedName;
  }
  return '$trimmedName역';
}

String _stationResultSemanticLabel(StationSearchResult result) {
  final stationName = _stationResultDisplayName(result.nameKo);
  final distance = result.distanceLabel;
  if (distance.isEmpty) {
    return '$stationName, ${result.lineLabel}, ${result.region}, ${result.dataQualityLabel}, ${result.dataSourceLabel}';
  }
  return '$stationName, $distance, ${result.lineLabel}, ${result.region}, ${result.dataQualityLabel}, ${result.dataSourceLabel}';
}

class FavoriteStationListScreen extends StatefulWidget {
  const FavoriteStationListScreen({
    required this.repository,
    required this.stationRepository,
    required this.reportRepository,
    this.locationProvider,
    this.facilityReportDraftTargetStore,
    this.internalRouteRepository,
    this.internalRouteMobilityType = 'SENIOR',
    super.key,
  });

  final FavoriteStationRepository repository;
  final StationSearchRepository stationRepository;
  final FacilityReportRepository reportRepository;
  final CurrentLocationProvider? locationProvider;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final InternalRouteRepository? internalRouteRepository;
  final String internalRouteMobilityType;

  @override
  State<FavoriteStationListScreen> createState() =>
      _FavoriteStationListScreenState();
}

class _FavoriteStationListScreenState extends State<FavoriteStationListScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('즐겨찾기 역')),
      body: FavoriteStationListContent(
        repository: widget.repository,
        stationRepository: widget.stationRepository,
        reportRepository: widget.reportRepository,
        locationProvider: widget.locationProvider,
        facilityReportDraftTargetStore: widget.facilityReportDraftTargetStore,
        internalRouteRepository: widget.internalRouteRepository,
        internalRouteMobilityType: widget.internalRouteMobilityType,
      ),
    );
  }
}

class FavoriteStationListContent extends StatefulWidget {
  const FavoriteStationListContent({
    required this.repository,
    required this.stationRepository,
    required this.reportRepository,
    this.locationProvider,
    this.facilityReportDraftTargetStore,
    this.internalRouteRepository,
    this.internalRouteMobilityType = 'SENIOR',
    super.key,
  });

  final FavoriteStationRepository repository;
  final StationSearchRepository stationRepository;
  final FacilityReportRepository reportRepository;
  final CurrentLocationProvider? locationProvider;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final InternalRouteRepository? internalRouteRepository;
  final String internalRouteMobilityType;

  @override
  State<FavoriteStationListContent> createState() =>
      _FavoriteStationListContentState();
}

class _FavoriteStationListContentState
    extends State<FavoriteStationListContent> {
  late final FavoriteStationListController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FavoriteStationListController(repository: widget.repository);
    _controller.load();
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
        builder: (context, _) {
          return _FavoriteStationListBody(
            state: _controller.state,
            onRetry: _controller.load,
            onFavoriteTap: _openStationDetail,
          );
        },
      ),
    );
  }

  Future<void> _openStationDetail(FavoriteStation favorite) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StationDetailScreen(
          repository: widget.stationRepository,
          reportRepository: widget.reportRepository,
          favoriteRepository: widget.repository,
          locationProvider: widget.locationProvider,
          stationId: favorite.stationId,
          facilityReportDraftTargetStore: widget.facilityReportDraftTargetStore,
          internalRouteRepository: widget.internalRouteRepository,
          internalRouteMobilityType: widget.internalRouteMobilityType,
          // 목록에서 들어온 역은 이미 저장된 상태로 보여 해제 동작을 바로 할 수 있게 한다.
          initiallyFavorite: true,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    _controller.load();
  }
}

class _FavoriteStationListBody extends StatelessWidget {
  const _FavoriteStationListBody({
    required this.state,
    required this.onRetry,
    required this.onFavoriteTap,
  });

  final FavoriteStationListState state;
  final VoidCallback onRetry;
  final ValueChanged<FavoriteStation> onFavoriteTap;

  @override
  Widget build(BuildContext context) {
    return switch (state.status) {
      FavoriteStationListStatus.loading => Semantics(
        label: '즐겨찾기 불러오는 중',
        liveRegion: true,
        child: const Center(child: CircularProgressIndicator()),
      ),
      FavoriteStationListStatus.empty => Padding(
        padding: const EdgeInsets.all(20),
        child: _StationSearchMessage(message: state.message, liveRegion: true),
      ),
      FavoriteStationListStatus.failure => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StationSearchMessage(message: state.message, liveRegion: true),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('favoriteStationsRetryButton'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 불러오기'),
            ),
          ],
        ),
      ),
      FavoriteStationListStatus.success => ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Semantics(
            label: '즐겨찾기 역 ${state.favorites.length}개',
            liveRegion: true,
            child: const SizedBox.shrink(),
          ),
          for (final favorite in state.favorites)
            _FavoriteStationTile(
              favorite: favorite,
              onTap: () => onFavoriteTap(favorite),
            ),
        ],
      ),
    };
  }
}

class _FavoriteStationTile extends StatelessWidget {
  const _FavoriteStationTile({required this.favorite, required this.onTap});

  final FavoriteStation favorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return MergeSemantics(
      child: Semantics(
        label: favorite.semanticLabel,
        button: true,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFD5E2E4)),
            ),
            child: InkWell(
              key: Key('favoriteStationTile-${favorite.stationId}'),
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      favorite.nameKo,
                      style: textTheme.titleLarge?.copyWith(
                        color: const Color(0xFF102A2C),
                        fontWeight: FontWeight.w900,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 10),
                    StationLineBadges(lines: favorite.lines),
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
                      favorite.region,
                      style: textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF405A5D),
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      favorite.dataQualityLabel,
                      style: textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF405A5D),
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      favorite.dataSourceLabel,
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
      ),
    );
  }
}

class StationDetailScreen extends StatefulWidget {
  const StationDetailScreen({
    required this.repository,
    required this.reportRepository,
    required this.stationId,
    this.favoriteRepository,
    this.locationProvider,
    this.initiallyFavorite,
    this.facilityReportDraftTargetStore,
    this.internalRouteRepository,
    this.internalRouteRequest,
    this.internalRouteMobilityType = 'SENIOR',
    super.key,
  });

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final FavoriteStationRepository? favoriteRepository;
  final CurrentLocationProvider? locationProvider;
  final String stationId;
  final bool? initiallyFavorite;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final InternalRouteRepository? internalRouteRepository;
  final InternalRouteRequest? internalRouteRequest;
  final String internalRouteMobilityType;

  @override
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends State<StationDetailScreen> {
  late final StationDetailController _controller;
  StationFavoriteToggleController? _favoriteController;
  InternalRouteController? _internalRouteController;

  @override
  void initState() {
    super.initState();
    _controller = StationDetailController(repository: widget.repository);
    final internalRouteRepository = widget.internalRouteRepository;
    final internalRouteRequest = widget.internalRouteRequest;
    if (internalRouteRepository != null) {
      _internalRouteController = InternalRouteController(
        repository: internalRouteRepository,
      );
      if (internalRouteRequest != null) {
        _internalRouteController!.load(internalRouteRequest);
      } else {
        _internalRouteController!.loadDefault(
          stationId: widget.stationId,
          mobilityType: widget.internalRouteMobilityType,
        );
      }
    }
    final favoriteRepository = widget.favoriteRepository;
    if (favoriteRepository != null) {
      final initiallyFavorite = widget.initiallyFavorite;
      _favoriteController = StationFavoriteToggleController(
        repository: favoriteRepository,
        stationId: widget.stationId,
        initiallyFavorite: initiallyFavorite ?? false,
        initiallyChecking: initiallyFavorite == null,
      );
      if (initiallyFavorite == null) {
        _favoriteController!.load();
      }
    }
    _controller.load(widget.stationId);
  }

  @override
  void dispose() {
    _controller.dispose();
    _favoriteController?.dispose();
    _internalRouteController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('역 상세')),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([_controller, ?_internalRouteController]),
          builder: (context, _) {
            return _StationDetailBody(
              state: _controller.state,
              internalRouteState: _internalRouteController?.state,
              reportRepository: widget.reportRepository,
              favoriteController: _favoriteController,
              locationProvider: widget.locationProvider,
              facilityReportDraftTargetStore:
                  widget.facilityReportDraftTargetStore,
            );
          },
        ),
      ),
    );
  }
}

class _StationDetailBody extends StatelessWidget {
  const _StationDetailBody({
    required this.state,
    required this.internalRouteState,
    required this.reportRepository,
    required this.favoriteController,
    required this.locationProvider,
    required this.facilityReportDraftTargetStore,
  });

  final StationDetailState state;
  final InternalRouteState? internalRouteState;
  final FacilityReportRepository reportRepository;
  final StationFavoriteToggleController? favoriteController;
  final CurrentLocationProvider? locationProvider;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;

  @override
  Widget build(BuildContext context) {
    return switch (state.status) {
      StationDetailStatus.loading => Semantics(
        label: '역 상세 정보 불러오는 중',
        liveRegion: true,
        child: const Center(child: CircularProgressIndicator()),
      ),
      StationDetailStatus.failure => Padding(
        padding: const EdgeInsets.all(20),
        child: _StationSearchMessage(message: state.message, liveRegion: true),
      ),
      StationDetailStatus.success => _StationDetailContent(
        detail: state.detail!,
        exits: state.exits,
        facilities: state.prioritizedFacilities,
        facilityAttentionSummary: state.facilityAttentionSummary,
        facilityAttentionSemanticLabel: state.facilityAttentionSemanticLabel,
        layoutSummaryItems: state.layoutSummaryItems,
        layoutSummarySemanticLabel: state.layoutSummarySemanticLabel,
        internalRouteState: internalRouteState,
        reportRepository: reportRepository,
        favoriteController: favoriteController,
        locationProvider: locationProvider,
        facilityReportDraftTargetStore: facilityReportDraftTargetStore,
      ),
    };
  }
}

class _StationDetailContent extends StatelessWidget {
  const _StationDetailContent({
    required this.detail,
    required this.exits,
    required this.facilities,
    required this.facilityAttentionSummary,
    required this.facilityAttentionSemanticLabel,
    required this.layoutSummaryItems,
    required this.layoutSummarySemanticLabel,
    required this.internalRouteState,
    required this.reportRepository,
    required this.favoriteController,
    required this.locationProvider,
    required this.facilityReportDraftTargetStore,
  });

  final StationDetail detail;
  final List<StationExitInfo> exits;
  final List<StationFacilityInfo> facilities;
  final String facilityAttentionSummary;
  final String facilityAttentionSemanticLabel;
  final List<StationLayoutSummaryItem> layoutSummaryItems;
  final String layoutSummarySemanticLabel;
  final InternalRouteState? internalRouteState;
  final FacilityReportRepository reportRepository;
  final StationFavoriteToggleController? favoriteController;
  final CurrentLocationProvider? locationProvider;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;

  @override
  Widget build(BuildContext context) {
    final mapMarkers = const EasySubwayMapAdapter().markersForStationDetail(
      station: detail,
      exits: exits,
      facilities: facilities,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        _StationDetailHeader(detail: detail),
        const SizedBox(height: 12),
        const _StationSafetyGuidanceNotice(),
        if (favoriteController != null) ...[
          const SizedBox(height: 16),
          _StationFavoriteControl(
            detail: detail,
            controller: favoriteController!,
          ),
        ],
        const SizedBox(height: 24),
        if (layoutSummaryItems.isNotEmpty) ...[
          const _StationDetailSectionTitle(title: '이동 구조'),
          const SizedBox(height: 12),
          _StationLayoutSummary(
            items: layoutSummaryItems,
            semanticLabel: layoutSummarySemanticLabel,
          ),
          const SizedBox(height: 24),
        ],
        if (internalRouteState != null) ...[
          const _StationDetailSectionTitle(title: '내부 이동 안내'),
          const SizedBox(height: 12),
          _StationInternalRouteGuidance(state: internalRouteState!),
          const SizedBox(height: 24),
        ],
        if (mapMarkers.isNotEmpty) ...[
          const _StationDetailSectionTitle(title: '지도 위치 목록'),
          const SizedBox(height: 12),
          _StationMapTextFallback(markers: mapMarkers),
          const SizedBox(height: 24),
        ],
        const _StationDetailSectionTitle(title: '출구'),
        const SizedBox(height: 12),
        if (exits.isEmpty)
          const _StationDetailEmptyMessage(message: '출구 정보가 아직 없습니다.')
        else
          for (final exit in exits) _StationExitCard(exit: exit),
        const SizedBox(height: 24),
        const _StationDetailSectionTitle(title: '시설'),
        const SizedBox(height: 12),
        if (facilities.isEmpty)
          const _StationDetailEmptyMessage(message: '시설 정보가 아직 없습니다.')
        else ...[
          _StationFacilityStatusSummary(
            text: facilityAttentionSummary,
            semanticLabel: facilityAttentionSemanticLabel,
          ),
          const SizedBox(height: 12),
          for (final facility in facilities)
            _StationFacilityCard(
              facility: facility,
              onReportTap: () => _openFacilityReport(context, facility),
            ),
        ],
      ],
    );
  }

  void _openFacilityReport(BuildContext context, StationFacilityInfo facility) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FacilityReportScreen(
          repository: reportRepository,
          locationLoader: _locationLoader(),
          needsLocationPermissionRequest: _locationPermissionRequestChecker(),
          openLocationSettings: _locationSettingsOpener(),
          draftTargetStore: facilityReportDraftTargetStore,
          target: FacilityReportTarget(
            stationId: detail.id,
            stationName: detail.nameKo,
            facilityId: facility.id,
            facilityName: facility.name,
            facilityTypeLabel: facility.typeLabel,
            facilityStatusLabel: facility.statusLabel,
          ),
        ),
      ),
    );
  }

  FacilityReportLocationLoader? _locationLoader() {
    final provider = locationProvider;
    if (provider == null) {
      return null;
    }
    return () async {
      final CurrentLocation location;
      try {
        location = await provider.currentLocation();
      } on CurrentLocationException catch (error) {
        throw FacilityReportLocationException(error.message);
      }
      return FacilityReportLocation(
        latitude: location.latitude,
        longitude: location.longitude,
      );
    };
  }

  FacilityReportLocationPermissionRequestChecker?
  _locationPermissionRequestChecker() {
    final provider = locationProvider;
    if (provider == null) {
      return null;
    }
    return provider.needsLocationPermissionRequest;
  }

  FacilityReportLocationSettingsOpener? _locationSettingsOpener() {
    final provider = locationProvider;
    if (provider == null) {
      return null;
    }
    return provider.openLocationSettings;
  }
}

class _StationMapTextFallback extends StatelessWidget {
  const _StationMapTextFallback({required this.markers});

  final List<MapMarker> markers;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          label: '지도 대체 위치 목록',
          child: const SizedBox.shrink(),
        ),
        Semantics(
          container: true,
          label: '지도를 열 수 없어도 아래 위치 목록으로 확인할 수 있습니다.',
          child: const ExcludeSemantics(
            child: _StationDetailInfoRow(
              icon: Icons.map_outlined,
              text: '지도를 열 수 없어도 아래 위치 목록으로 확인할 수 있습니다.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final marker in markers)
          _StationMapTextFallbackItem(marker: marker),
      ],
    );
  }
}

class _StationMapTextFallbackItem extends StatelessWidget {
  const _StationMapTextFallbackItem({required this.marker});

  final MapMarker marker;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: marker.semanticLabel,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _mapMarkerIcon(marker.type),
                size: 22,
                color: const Color(0xFF006D77),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  marker.title,
                  key: Key('stationMapTextFallbackItem-${marker.id}'),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF102A2C),
                    fontWeight: FontWeight.w800,
                    height: 1.3,
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

IconData _mapMarkerIcon(MapMarkerType type) {
  return switch (type) {
    MapMarkerType.station => Icons.train_outlined,
    MapMarkerType.exit => Icons.exit_to_app,
    MapMarkerType.facility => Icons.accessible_forward,
  };
}

class _StationLayoutSummary extends StatelessWidget {
  const _StationLayoutSummary({
    required this.items,
    required this.semanticLabel,
  });

  final List<StationLayoutSummaryItem> items;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final item in items)
                  _StationLayoutStep(
                    item: item,
                    textTheme: textTheme,
                    width: itemWidth,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StationLayoutStep extends StatelessWidget {
  const _StationLayoutStep({
    required this.item,
    required this.textTheme,
    required this.width,
  });

  final StationLayoutSummaryItem item;
  final TextTheme textTheme;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6F4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFB9D7D2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, color: const Color(0xFF006D77), size: 26),
          const SizedBox(height: 8),
          Text(
            item.text,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF102A2C),
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _StationFacilityStatusSummary extends StatelessWidget {
  const _StationFacilityStatusSummary({
    required this.text,
    required this.semanticLabel,
  });

  final String text;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: _StationDetailInfoRow(icon: Icons.priority_high, text: text),
      ),
    );
  }
}

class _StationDetailHeader extends StatelessWidget {
  const _StationDetailHeader({required this.detail});

  final StationDetail detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: detail.semanticLabel,
      header: true,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${detail.nameKo}역',
              style: textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF102A2C),
                fontWeight: FontWeight.w900,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            StationLineBadges(lines: detail.lines),
            const SizedBox(height: 10),
            Text(
              detail.lineLabel,
              style: textTheme.titleMedium?.copyWith(
                color: const Color(0xFF29484B),
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            _StationDetailInfoRow(
              icon: Icons.verified_outlined,
              text: detail.dataQualityLabel,
            ),
            const SizedBox(height: 6),
            _StationDetailInfoRow(
              icon: Icons.source_outlined,
              text: detail.dataSourceLabel,
            ),
            const SizedBox(height: 6),
            _StationDetailInfoRow(
              icon: Icons.event_available,
              text: '마지막 확인 ${detail.lastVerifiedAt}',
            ),
          ],
        ),
      ),
    );
  }
}

class _StationSafetyGuidanceNotice extends StatelessWidget {
  const _StationSafetyGuidanceNotice();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '안전 안내, $_stationSafetyGuidanceNotice',
      child: const ExcludeSemantics(
        child: _StationDetailInfoRow(
          icon: Icons.info_outline,
          text: _stationSafetyGuidanceNotice,
        ),
      ),
    );
  }
}

class _StationFavoriteControl extends StatelessWidget {
  const _StationFavoriteControl({
    required this.detail,
    required this.controller,
  });

  final StationDetail detail;
  final StationFavoriteToggleController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        final isFavorite = state.isFavorite;
        final label = _favoriteButtonLabel(state);
        final actionLabel = state.status == StationFavoriteToggleStatus.checking
            ? '즐겨찾기 확인 중'
            : isFavorite
            ? '즐겨찾기 해제'
            : '즐겨찾기 저장';
        final onPressed = state.isBusy
            ? null
            : isFavorite
            ? controller.remove
            : controller.save;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              container: true,
              label: '${detail.nameKo}역 $actionLabel',
              button: true,
              onTap: onPressed,
              child: ExcludeSemantics(
                child: OutlinedButton.icon(
                  key: const Key('stationFavoriteToggleButton'),
                  onPressed: onPressed,
                  icon: Icon(isFavorite ? Icons.star : Icons.star_border),
                  label: Text(label),
                ),
              ),
            ),
            if (state.message.isNotEmpty) ...[
              const SizedBox(height: 10),
              Semantics(
                label: state.message,
                liveRegion: true,
                child: Text(
                  state.message,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF102A2C),
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  String _favoriteButtonLabel(StationFavoriteToggleState state) {
    return switch (state.status) {
      StationFavoriteToggleStatus.checking => '확인 중',
      StationFavoriteToggleStatus.saving => '저장 중',
      StationFavoriteToggleStatus.removing => '해제 중',
      StationFavoriteToggleStatus.ready ||
      StationFavoriteToggleStatus.failure =>
        state.isFavorite ? '즐겨찾기 해제' : '즐겨찾기 저장',
    };
  }
}

class _StationInternalRouteGuidance extends StatelessWidget {
  const _StationInternalRouteGuidance({required this.state});

  final InternalRouteState state;

  @override
  Widget build(BuildContext context) {
    return switch (state.status) {
      InternalRouteViewStatus.loading => Semantics(
        label: '내부 이동 안내 불러오는 중',
        liveRegion: true,
        child: const _StationDetailInfoRow(
          icon: Icons.sync,
          text: '내부 이동 안내를 불러오는 중입니다.',
        ),
      ),
      InternalRouteViewStatus.failure => Semantics(
        label: state.message,
        liveRegion: true,
        child: _StationDetailInfoRow(
          icon: Icons.error_outline,
          text: state.message,
        ),
      ),
      InternalRouteViewStatus.success => _StationInternalRouteResultCard(
        result: state.result!,
      ),
    };
  }
}

class _StationInternalRouteResultCard extends StatelessWidget {
  const _StationInternalRouteResultCard({required this.result});

  final InternalRouteResult result;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: result.semanticLabel,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF8F6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFB7D8D2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StationDetailInfoRow(
                icon: result.statusIcon,
                text: result.statusLabel,
              ),
              const SizedBox(height: 8),
              Text(
                result.summaryLabel,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF102A2C),
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                result.totalBurdenLabel,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF2C5558),
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              if (result.warnings.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final warning in result.warnings)
                  _StationDetailInfoRow(
                    icon: Icons.warning_amber,
                    text: warning.message,
                  ),
              ],
              if (result.steps.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final step in result.steps)
                  _StationInternalRouteStepTile(step: step),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StationInternalRouteStepTile extends StatelessWidget {
  const _StationInternalRouteStepTile({required this.step});

  final InternalRouteStep step;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: step.semanticLabel,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF102A2C),
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                step.burdenLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF2C5558),
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                step.guidance,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF102A2C),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StationDetailInfoRow extends StatelessWidget {
  const _StationDetailInfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22, color: const Color(0xFF006D77)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF29484B),
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _StationDetailSectionTitle extends StatelessWidget {
  const _StationDetailSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: const Color(0xFF102A2C),
          fontWeight: FontWeight.w900,
          height: 1.25,
        ),
      ),
    );
  }
}

class _StationDetailEmptyMessage extends StatelessWidget {
  const _StationDetailEmptyMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: const Color(0xFF405A5D),
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
    );
  }
}

class _StationExitCard extends StatelessWidget {
  const _StationExitCard({required this.exit});

  final StationExitInfo exit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return MergeSemantics(
      child: Semantics(
        label: exit.semanticLabel,
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exit.name,
                    style: textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF102A2C),
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _StationDetailStatusPill(
                    icon: Icons.elevator,
                    text: exit.elevatorConnectionLabel,
                    positive: exit.hasElevatorConnection,
                  ),
                  const SizedBox(height: 8),
                  _StationDetailStatusPill(
                    icon: Icons.stairs_outlined,
                    text: exit.stairPathLabel,
                    positive: !exit.hasStairOnlyPath,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    exit.confidenceLabel,
                    style: textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF405A5D),
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    exit.dataSourceLabel,
                    style: textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF405A5D),
                      fontWeight: FontWeight.w700,
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

class _StationFacilityCard extends StatelessWidget {
  const _StationFacilityCard({
    required this.facility,
    required this.onReportTap,
  });

  final StationFacilityInfo facility;
  final VoidCallback onReportTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: facility.semanticLabel,
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                facility.name,
                style: textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF102A2C),
                  fontWeight: FontWeight.w900,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StationDetailTextPill(text: facility.typeLabel),
                  _StationDetailTextPill(text: facility.statusLabel),
                ],
              ),
              const SizedBox(height: 12),
              _StationDetailInfoRow(
                icon: Icons.place_outlined,
                text: facility.locationLabel,
              ),
              const SizedBox(height: 6),
              _StationDetailInfoRow(
                icon: Icons.event_available,
                text: facility.updatedLabel,
              ),
              const SizedBox(height: 6),
              Text(
                facility.confidenceLabel,
                style: textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF405A5D),
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                facility.dataSourceLabel,
                style: textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF405A5D),
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 14),
              Semantics(
                container: true,
                label: '${facility.name} 상태 신고',
                button: true,
                onTap: onReportTap,
                child: ExcludeSemantics(
                  child: OutlinedButton.icon(
                    key: Key('facilityReportButton-${facility.id}'),
                    onPressed: onReportTap,
                    icon: const Icon(Icons.report_outlined),
                    label: const Text('상태 신고'),
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

class _StationDetailStatusPill extends StatelessWidget {
  const _StationDetailStatusPill({
    required this.icon,
    required this.text,
    required this.positive,
  });

  final IconData icon;
  final String text;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final color = positive ? const Color(0xFF006D77) : const Color(0xFF8A4B00);

    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF102A2C),
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _StationDetailTextPill extends StatelessWidget {
  const _StationDetailTextPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE6F2F0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFB8D8D3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: const Color(0xFF102A2C),
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

class StationLineBadges extends StatelessWidget {
  const StationLineBadges({
    required this.lines,
    this.size = 40,
    this.maxBadgeCount,
    super.key,
  });

  final List<StationSearchLine> lines;
  final double size;
  final int? maxBadgeCount;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxCount = maxBadgeCount;
    final shouldCollapse = maxCount != null && lines.length > maxCount;
    final visibleLineCount = shouldCollapse
        ? (maxCount - 1).clamp(1, lines.length).toInt()
        : lines.length;
    final hiddenLineCount = lines.length - visibleLineCount;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final line in lines.take(visibleLineCount))
          StationLineBadge(line: line, size: size),
        if (hiddenLineCount > 0)
          _StationLineOverflowBadge(count: hiddenLineCount, size: size),
      ],
    );
  }
}

class StationLineBadge extends StatelessWidget {
  const StationLineBadge({required this.line, this.size = 40, super.key});

  final StationSearchLine line;
  final double size;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = line.badgeColor;
    final foregroundColor = _higherContrastTextColor(backgroundColor);
    final badgeText = line.badgeText;
    final scale = size / 40;
    final badgeFontSize = RegExp(r'^\d+$').hasMatch(badgeText)
        ? 25.0 * scale
        : 15.0 * scale;

    return Container(
      key: Key('stationLineBadge-${line.id}'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      child: Text(
        badgeText,
        textAlign: TextAlign.center,
        maxLines: 2,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: foregroundColor,
          fontSize: badgeFontSize,
          fontWeight: FontWeight.w900,
          height: 1.05,
        ),
      ),
    );
  }
}

class _StationLineOverflowBadge extends StatelessWidget {
  const _StationLineOverflowBadge({required this.count, required this.size});

  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('stationLineBadgeOverflow'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFE8F0F1),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFB8CACC)),
      ),
      child: Text(
        '+$count',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: const Color(0xFF29484B),
          fontSize: 13 * (size / 32),
          fontWeight: FontWeight.w900,
          height: 1.0,
        ),
      ),
    );
  }
}

Color _higherContrastTextColor(Color backgroundColor) {
  const darkText = Color(0xFF102A2C);
  final darkContrast = _contrastRatio(backgroundColor, darkText);
  final lightContrast = _contrastRatio(backgroundColor, Colors.white);
  return darkContrast >= lightContrast ? darkText : Colors.white;
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance() + 0.05;
  final secondLuminance = second.computeLuminance() + 0.05;
  if (firstLuminance > secondLuminance) {
    return firstLuminance / secondLuminance;
  }
  return secondLuminance / firstLuminance;
}

Uri defaultStationApiBaseUri() {
  const configuredBaseUrl = String.fromEnvironment('EASYSUBWAY_API_BASE_URL');
  return stationApiBaseUriForEnvironment(
    configuredBaseUrl: configuredBaseUrl,
    isAndroid: Platform.isAndroid,
    isReleaseMode: kReleaseMode,
  );
}

Uri? defaultOptionalStationApiBaseUri() {
  const configuredBaseUrl = String.fromEnvironment('EASYSUBWAY_API_BASE_URL');
  return optionalStationApiBaseUriForEnvironment(
    configuredBaseUrl: configuredBaseUrl,
    isAndroid: Platform.isAndroid,
    isReleaseMode: kReleaseMode,
  );
}

Uri? optionalStationApiBaseUriForEnvironment({
  required String configuredBaseUrl,
  required bool isAndroid,
  required bool isReleaseMode,
}) {
  if (configuredBaseUrl.trim().isEmpty && isReleaseMode) {
    return null;
  }
  return stationApiBaseUriForEnvironment(
    configuredBaseUrl: configuredBaseUrl,
    isAndroid: isAndroid,
    isReleaseMode: isReleaseMode,
  );
}

Uri stationApiBaseUriForEnvironment({
  required String configuredBaseUrl,
  required bool isAndroid,
  required bool isReleaseMode,
}) {
  final trimmedBaseUrl = configuredBaseUrl.trim();
  if (trimmedBaseUrl.isNotEmpty) {
    final baseUri = Uri.parse(trimmedBaseUrl);
    if (isReleaseMode && baseUri.scheme != 'https') {
      throw StateError('Release API base URL must use HTTPS.');
    }
    if (isReleaseMode && baseUri.host.isEmpty) {
      throw StateError('Release API base URL must include a host.');
    }
    return baseUri;
  }
  if (isReleaseMode) {
    // 운영 빌드는 로컬 개발 주소로 조용히 떨어지지 않게 빌드 설정 누락을 즉시 드러낸다.
    throw StateError('Release API base URL must be configured.');
  }
  if (isAndroid) {
    return Uri.parse('http://10.0.2.2:8080');
  }
  return Uri.parse('http://127.0.0.1:8080');
}
