import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth_headers.dart';
import 'facility_report.dart';
import 'mobile_error_reporter.dart';

const _stationSearchTimeout = Duration(seconds: 8);
const _stationSearchErrorMessage = '역 정보를 불러오지 못했습니다.';
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

class CurrentLocation {
  const CurrentLocation({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

abstract class CurrentLocationProvider {
  Future<CurrentLocation> currentLocation();
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
      return CurrentLocation(latitude: latitude, longitude: longitude);
    } on CurrentLocationException {
      rethrow;
    } on PlatformException catch (error) {
      throw CurrentLocationException(_locationErrorMessage(error.code));
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '현재 위치 조회 중 예외가 발생했습니다.');
      throw const CurrentLocationException('현재 위치를 확인하지 못했습니다.');
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

  String _locationErrorMessage(String code) {
    return switch (code) {
      'permissionDenied' => '위치 권한을 확인해 주세요.',
      'locationDisabled' => '기기 위치를 켜 주세요.',
      'locationUnavailable' => '현재 위치를 확인하지 못했습니다.',
      _ => '현재 위치를 확인하지 못했습니다.',
    };
  }
}

class StationSearchApiRepository implements StationSearchRepository {
  StationSearchApiRepository({required this.baseUri, HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final Uri baseUri;
  final HttpClient _httpClient;

  @override
  Future<List<StationSearchResult>> searchStations(String query) async {
    final uri = baseUri
        .resolve('/api/v1/stations')
        .replace(queryParameters: {'query': query});

    final data = await _getData(uri);
    if (data is! List) {
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
    if (data is! List) {
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
    if (data is! List) {
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
    if (data is! List) {
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
    if (data is! List) {
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
          // 저장된 익명 인증이 서버에서 만료된 경우 지우고 새 인증으로 한 번만 재시도한다.
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
    if (rawLines is! List) {
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
    if (rawLines is! List) {
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
    if (rawLines is! List) {
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

  String get badgeText {
    for (final entry in _knownBadgeLabels.entries) {
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
    'LEVEL_1' => '기본 정보만 확인됨',
    'LEVEL_2' => '접근성 시설 확인됨',
    'LEVEL_3' => '쉬운 경로 안내 가능',
    'LEVEL_4' => '실시간 상태 반영됨',
    _ => '확인 정보 부족',
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
  StationSearchController({required this.repository});

  final StationSearchRepository repository;

  StationSearchState _state = const StationSearchState.idle();
  int _searchRequestId = 0;
  bool _isDisposed = false;

  StationSearchState get state => _state;

  Future<void> search(String query) async {
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
      final results = await repository.searchStations(trimmedQuery);
      if (!_isActiveRequest(requestId)) {
        return;
      }
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

  Future<void> searchNearby(CurrentLocationProvider locationProvider) async {
    final requestId = ++_searchRequestId;
    _state = const StationSearchState(
      status: StationSearchStatus.loading,
      results: [],
    );
    _notifyIfActive(requestId);

    try {
      final location = await locationProvider.currentLocation();
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
    super.key,
  });

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final CurrentLocationProvider locationProvider;
  final FavoriteStationRepository? favoriteRepository;

  @override
  State<StationSearchScreen> createState() => _StationSearchScreenState();
}

class _StationSearchScreenState extends State<StationSearchScreen> {
  late final StationSearchController _controller;
  final TextEditingController _queryController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = StationSearchController(repository: widget.repository);
  }

  @override
  void dispose() {
    _controller.dispose();
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('역 검색')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Semantics(
              label: '역 이름 입력',
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
                final isLoading =
                    _controller.state.status == StationSearchStatus.loading;
                return FilledButton.icon(
                  key: const Key('stationSearchSubmitButton'),
                  onPressed: isLoading
                      ? null
                      : () => _submit(_queryController.text),
                  icon: const Icon(Icons.search),
                  label: const Text('검색'),
                );
              },
            ),
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final isLoading =
                    _controller.state.status == StationSearchStatus.loading;
                return OutlinedButton.icon(
                  key: const Key('nearbyStationSearchButton'),
                  onPressed: isLoading ? null : _searchNearby,
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
    _controller.search(query);
  }

  void _searchNearby() {
    if (_controller.state.status == StationSearchStatus.loading) {
      return;
    }
    _controller.searchNearby(widget.locationProvider);
  }

  void _openStationDetail(StationSearchResult result) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StationDetailScreen(
          repository: widget.repository,
          reportRepository: widget.reportRepository,
          favoriteRepository: widget.favoriteRepository,
          stationId: result.id,
        ),
      ),
    );
  }
}

class _StationSearchBody extends StatelessWidget {
  const _StationSearchBody({required this.state, required this.onResultTap});

  final StationSearchState state;
  final ValueChanged<StationSearchResult> onResultTap;

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
      StationSearchStatus.empty || StationSearchStatus.failure =>
        _StationSearchMessage(message: state.message, liveRegion: true),
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

class _StationSearchMessage extends StatelessWidget {
  const _StationSearchMessage({required this.message, this.liveRegion = false});

  final String message;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
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

    return MergeSemantics(
      child: Semantics(
        label: result.semanticLabel,
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
              key: Key('stationSearchResult-${result.id}'),
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.nameKo,
                      style: textTheme.titleLarge?.copyWith(
                        color: const Color(0xFF102A2C),
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 10),
                    StationLineBadges(lines: result.lines),
                    if (result.distanceLabel.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        result.distanceLabel,
                        style: textTheme.bodyLarge?.copyWith(
                          color: const Color(0xFF006D77),
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      result.lineLabel,
                      style: textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF29484B),
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      result.region,
                      style: textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF405A5D),
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
            ),
          ),
        ),
      ),
    );
  }
}

class FavoriteStationListScreen extends StatefulWidget {
  const FavoriteStationListScreen({
    required this.repository,
    required this.stationRepository,
    required this.reportRepository,
    super.key,
  });

  final FavoriteStationRepository repository;
  final StationSearchRepository stationRepository;
  final FacilityReportRepository reportRepository;

  @override
  State<FavoriteStationListScreen> createState() =>
      _FavoriteStationListScreenState();
}

class _FavoriteStationListScreenState extends State<FavoriteStationListScreen> {
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
    return Scaffold(
      appBar: AppBar(title: const Text('즐겨찾기 역')),
      body: SafeArea(
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
          stationId: favorite.stationId,
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
    this.initiallyFavorite,
    super.key,
  });

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final FavoriteStationRepository? favoriteRepository;
  final String stationId;
  final bool? initiallyFavorite;

  @override
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends State<StationDetailScreen> {
  late final StationDetailController _controller;
  StationFavoriteToggleController? _favoriteController;

  @override
  void initState() {
    super.initState();
    _controller = StationDetailController(repository: widget.repository);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('역 상세')),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return _StationDetailBody(
              state: _controller.state,
              reportRepository: widget.reportRepository,
              favoriteController: _favoriteController,
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
    required this.reportRepository,
    required this.favoriteController,
  });

  final StationDetailState state;
  final FacilityReportRepository reportRepository;
  final StationFavoriteToggleController? favoriteController;

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
        reportRepository: reportRepository,
        favoriteController: favoriteController,
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
    required this.reportRepository,
    required this.favoriteController,
  });

  final StationDetail detail;
  final List<StationExitInfo> exits;
  final List<StationFacilityInfo> facilities;
  final String facilityAttentionSummary;
  final String facilityAttentionSemanticLabel;
  final FacilityReportRepository reportRepository;
  final StationFavoriteToggleController? favoriteController;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        _StationDetailHeader(detail: detail),
        if (favoriteController != null) ...[
          const SizedBox(height: 16),
          _StationFavoriteControl(
            detail: detail,
            controller: favoriteController!,
          ),
        ],
        const SizedBox(height: 24),
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
  const StationLineBadges({required this.lines, super.key});

  final List<StationSearchLine> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final line in lines) StationLineBadge(line: line)],
    );
  }
}

class StationLineBadge extends StatelessWidget {
  const StationLineBadge({required this.line, super.key});

  final StationSearchLine line;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = line.badgeColor;
    final foregroundColor = _higherContrastTextColor(backgroundColor);
    final badgeText = line.badgeText;
    final badgeFontSize = RegExp(r'^\d+$').hasMatch(badgeText) ? 24.0 : 15.0;

    return Container(
      key: Key('stationLineBadge-${line.id}'),
      width: 40,
      height: 40,
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
  if (configuredBaseUrl.isNotEmpty) {
    return Uri.parse(configuredBaseUrl);
  }
  if (Platform.isAndroid) {
    return Uri.parse('http://10.0.2.2:8080');
  }
  return Uri.parse('http://127.0.0.1:8080');
}
