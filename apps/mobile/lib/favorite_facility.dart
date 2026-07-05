import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'auth_headers.dart';
import 'facility_status.dart';
import 'mobile_error_reporter.dart';

const _favoriteFacilityTimeout = Duration(seconds: 8);
const _favoriteFacilityLoadErrorMessage = '즐겨찾기 시설을 불러오지 못했어요.';
const _favoriteFacilityChangeErrorMessage = '즐겨찾기 시설을 바꾸지 못했어요.';

abstract class FavoriteFacilityRepository {
  Future<List<FavoriteFacility>> listFavoriteFacilities();

  Future<FavoriteFacility> saveFavoriteFacility(String facilityId);

  Future<void> removeFavoriteFacility(String facilityId);
}

class FavoriteFacilityApiRepository implements FavoriteFacilityRepository {
  FavoriteFacilityApiRepository({
    required this.baseUri,
    required this.authProvider,
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  final Uri baseUri;
  final AuthorizationHeaderProvider authProvider;
  final HttpClient _httpClient;

  @override
  Future<List<FavoriteFacility>> listFavoriteFacilities() async {
    final data = await _requestData(
      'GET',
      baseUri.resolve('/api/v1/me/favorites/facilities'),
      errorMessage: _favoriteFacilityLoadErrorMessage,
    );
    if (data is! List<Object?>) {
      throw const FavoriteFacilityException(_favoriteFacilityLoadErrorMessage);
    }

    try {
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid favorite facility payload');
            }
            return FavoriteFacility.fromJson(item);
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '즐겨찾기 시설 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const FavoriteFacilityException(_favoriteFacilityLoadErrorMessage);
    }
  }

  @override
  Future<FavoriteFacility> saveFavoriteFacility(String facilityId) async {
    final data = await _requestData(
      'PUT',
      baseUri.resolve(
        '/api/v1/me/favorites/facilities/${Uri.encodeComponent(facilityId)}',
      ),
      errorMessage: _favoriteFacilityChangeErrorMessage,
    );
    if (data is! Map<String, Object?>) {
      throw const FavoriteFacilityException(
        _favoriteFacilityChangeErrorMessage,
      );
    }

    try {
      return FavoriteFacility.fromJson(data);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '즐겨찾기 시설 저장 응답 처리 중 예외가 발생했습니다.',
      );
      throw const FavoriteFacilityException(
        _favoriteFacilityChangeErrorMessage,
      );
    }
  }

  @override
  Future<void> removeFavoriteFacility(String facilityId) async {
    await _requestData(
      'DELETE',
      baseUri.resolve(
        '/api/v1/me/favorites/facilities/${Uri.encodeComponent(facilityId)}',
      ),
      errorMessage: _favoriteFacilityChangeErrorMessage,
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
            .timeout(_favoriteFacilityTimeout);
        final authorizationHeader = await authProvider
            .authorizationHeader()
            .timeout(_favoriteFacilityTimeout);
        if (authorizationHeader != null) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            authorizationHeader,
          );
        }

        final response = await request.close().timeout(
          _favoriteFacilityTimeout,
        );
        final body = await utf8
            .decodeStream(response)
            .timeout(_favoriteFacilityTimeout);

        if (response.statusCode == HttpStatus.unauthorized &&
            authorizationHeader != null &&
            attempt == 0) {
          // 저장된 인증이 만료된 경우 비우고 한 번만 다시 시도한다.
          await authProvider.invalidateAuthorization().timeout(
            _favoriteFacilityTimeout,
          );
          continue;
        }

        if (response.statusCode < HttpStatus.ok ||
            response.statusCode >= HttpStatus.multipleChoices) {
          throw FavoriteFacilityException(errorMessage);
        }

        final decoded = jsonDecode(body);
        if (decoded is! Map<String, Object?> || decoded['success'] != true) {
          throw FavoriteFacilityException(errorMessage);
        }
        return decoded['data'];
      } on FavoriteFacilityException {
        rethrow;
      } catch (error, stackTrace) {
        reportMobileError(
          error,
          stackTrace,
          context: '즐겨찾기 시설 API 요청 처리 중 예외가 발생했습니다.',
        );
        throw FavoriteFacilityException(errorMessage);
      }
    }
    throw FavoriteFacilityException(errorMessage);
  }
}

class FavoriteFacilityException implements Exception {
  const FavoriteFacilityException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FavoriteFacility {
  const FavoriteFacility({
    required this.userId,
    required this.facilityId,
    required this.stationId,
    required this.stationNameKo,
    required this.stationNameEn,
    required this.exitId,
    required this.type,
    required this.name,
    required this.floorFrom,
    required this.floorTo,
    required this.description,
    required this.status,
    required this.dataConfidence,
    this.dataSourceType = '',
    this.fieldValidationStatus = 'UNKNOWN',
    required this.lastUpdatedAt,
    required this.addedAt,
  });

  factory FavoriteFacility.fromJson(Map<String, Object?> json) {
    return FavoriteFacility(
      userId: _requiredString(json, 'userId'),
      facilityId: _requiredString(json, 'facilityId'),
      stationId: _requiredString(json, 'stationId'),
      stationNameKo: _requiredString(json, 'stationNameKo'),
      stationNameEn: _requiredString(json, 'stationNameEn'),
      exitId: _stringOrEmpty(json, 'exitId'),
      type: _requiredString(json, 'type'),
      name: _requiredString(json, 'name'),
      floorFrom: _stringOrEmpty(json, 'floorFrom'),
      floorTo: _stringOrEmpty(json, 'floorTo'),
      description: _stringOrEmpty(json, 'description'),
      status: _requiredString(json, 'status'),
      dataConfidence: _requiredString(json, 'dataConfidence'),
      dataSourceType: _stringOrEmpty(json, 'dataSourceType'),
      fieldValidationStatus: _stringOrDefault(
        json,
        'fieldValidationStatus',
        'UNKNOWN',
      ),
      lastUpdatedAt: _requiredString(json, 'lastUpdatedAt'),
      addedAt: _requiredString(json, 'addedAt'),
    );
  }

  final String userId;
  final String facilityId;
  final String stationId;
  final String stationNameKo;
  final String stationNameEn;
  final String exitId;
  final String type;
  final String name;
  final String floorFrom;
  final String floorTo;
  final String description;
  final String status;
  final String dataConfidence;
  final String dataSourceType;
  final String fieldValidationStatus;
  final String lastUpdatedAt;
  final String addedAt;

  String get stationLabel => '$stationNameKo역';

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
      'UNKNOWN' => '설치 확인 · 운행상태 미확인',
      'USER_REPORTED' => '제보됨',
      'ADMIN_VERIFIED' => '확인 완료',
      'NEEDS_REPORT' => '알려 주세요',
      'NEEDS_CHECK' => '상태를 확인하고 있어요',
      _ => '상태를 확인하고 있어요',
    };
  }

  FacilityStatusPresentation get statusPresentation =>
      facilityStatusPresentation(status);

  String get severityLabel => statusPresentation.severityLabel;

  String get statusTitle => statusPresentation.statusTitle;

  String get nextActionLabel => statusPresentation.nextActionLabel;

  String get nextActionDescription => statusPresentation.nextActionDescription;

  bool get needsAttention => statusPresentation.needsAttention;

  int get statusPriority => statusPresentation.priority;

  String get verificationStatusLabel =>
      _facilityVerificationStatusLabel(fieldValidationStatus);

  String get confidenceLabel => _dataConfidenceLabel(dataConfidence);

  String get dataSourceLabel => _dataSourceLabel(dataSourceType);

  String get locationLabel {
    if (description.trim().isNotEmpty) {
      final descriptionLabel = _facilityUserLocationLabel(description);
      if (descriptionLabel.isNotEmpty) {
        return descriptionLabel;
      }
    }
    if (floorFrom.trim().isNotEmpty && floorTo.trim().isNotEmpty) {
      return '$floorFrom-$floorTo';
    }
    return '위치 안내를 준비 중이에요';
  }

  String get updatedLabel => '최근 확인 $lastUpdatedAt';

  String get semanticLabel =>
      '즐겨찾기 시설, $name, $stationLabel, $typeLabel, $statusTitle, $locationLabel, $updatedLabel, $nextActionLabel';
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('Missing required favorite facility field: $key');
}

String _stringOrEmpty(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is String ? value : '';
}

String _stringOrDefault(
  Map<String, Object?> json,
  String key,
  String defaultValue,
) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  return defaultValue;
}

// #1578: 내부 데이터 품질·검증 상태 라벨은 사용자에게 노출하지 않는다(소스 중립화).
String _dataConfidenceLabel(String dataConfidence) => '';

String _facilityVerificationStatusLabel(String fieldValidationStatus) => '';

String _facilityUserLocationLabel(String description) {
  var label = description.trim();
  label = label.replaceAll(RegExp(r'현장\s*(검[증]됨|검[증] 전|재확인\s*필요)'), '');
  label = label.replaceAll(RegExp(r'관리자\s*검[수]'), '');
  label = label.replaceAll(RegExp(r'\s+'), ' ').trim();
  return label;
}

String _dataSourceLabel(String dataSourceType) {
  return switch (dataSourceType) {
    'OFFICIAL_API' => '공식 안내',
    'OFFICIAL_FILE' => '공식 안내',
    'OPERATOR_PAGE' => '운영기관 안내',
    'USER_REPORT' => '이용자 제보',
    'ADMIN_VERIFIED' => '확인된 안내',
    'PARTNER_FEED' => '연계 안내',
    _ => '안내를 준비 중이에요',
  };
}
