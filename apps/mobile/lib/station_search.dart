import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'accessible_design.dart';
import 'adaptive_layout.dart';
import 'facility_status.dart';
import 'facility_report.dart';
import 'features/route_draft/application/route_draft_controller.dart';
import 'features/route_draft/domain/route_draft.dart';
import 'features/realtime/realtime_repository.dart';
import 'features/stations/domain/station_line.dart';
import 'features/stations/presentation/station_line_badges.dart';
import 'internal_route.dart';
import 'map_adapter.dart';
import 'mobile_error_reporter.dart';
import 'production_scope.dart';

export 'features/stations/domain/station_line.dart';

const _currentLocationDisabledMessage =
    '휴대전화의 위치 기능을 켜 주세요. 가까운 역을 찾는 데 필요합니다.';
const _currentLocationPermissionMessage = '현재 위치를 사용할 수 없어요.';
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
    '가까운 역 찾기와 시설 제보 위치 확인에만 현재 위치를 사용합니다.';
const _locationPermissionRationaleDenialNotice =
    '위치 사용을 허용하지 않아도 역명 검색, 즐겨찾기, 엘리베이터와 시설 안내는 계속 사용할 수 있습니다.';
const _stationSearchFailureNextAction =
    '역명으로 검색하면 현재 위치를 쓰지 않아도 계속 이용할 수 있습니다.';
const _stationSafetyGuidanceNotice = '이동 전 현장 안내와 역무원 안내를 확인해 주세요.';
const _favoriteStationLoadErrorMessage = '즐겨찾기를 불러오지 못했어요.';
const _favoriteStationStatusErrorMessage = '즐겨찾기를 확인하지 못했어요.';
const _favoriteStationChangeErrorMessage = '즐겨찾기를 바꾸지 못했어요.';
const _searchHistoryChangeErrorMessage = '최근 검색을 지우지 못했어요.';
const _stationSearchPagePadding = EdgeInsets.fromLTRB(20, 20, 20, 32);
const _stationSearchLargePagePadding = EdgeInsets.fromLTRB(24, 24, 24, 40);
const _stationLineSheetPadding = EdgeInsets.fromLTRB(20, 8, 20, 24);
const _stationRoleActionPadding = EdgeInsets.fromLTRB(12, 0, 12, 12);
const _stationSearchInputRadius = BorderRadius.all(Radius.circular(12));
const _stationCompactCardRadius = BorderRadius.all(Radius.circular(12));
const _stationLineRegionChipRadius = BorderRadius.all(Radius.circular(12));
const _stationLineFilterButtonRadius = BorderRadius.all(Radius.circular(12));
const _stationDetailInfoCardRadius = BorderRadius.all(Radius.circular(16));
const _stationDetailHelpCardRadius = BorderRadius.all(Radius.circular(16));
const _stationDetailActionButtonRadius = BorderRadius.all(Radius.circular(12));
const _stationDetailFacilityCardRadius = BorderRadius.all(Radius.circular(16));
const _stationDetailHeroCardRadius = BorderRadius.all(Radius.circular(16));
const _stationTextMutedColor = Color(0xFF405A5D);
const _stationTextSubtleColor = Color(0xFF506B6F);
const _stationDetailTextColor = Color(0xFF2C5558);
const _stationFacilityDividerColor = Color(0xFFC8D9E2);
const _stationDetailSoftPanelColor = Color(0xFFEAF6F4);
const _stationDetailSoftPanelBorderColor = Color(0xFFB9D7D2);
const _stationDetailMintPanelColor = Color(0xFFEFF8F6);
const _stationDetailMintPanelBorderColor = Color(0xFFB7D8D2);
const _stationDetailNoticeColor = Color(0xFFE6F2F0);
const _stationDetailNoticeBorderColor = Color(0xFFB8D8D3);
const _stationLineFilterSelectedColor = Color(0xFF007A80);
const _stationLineFilterBorderColor = Color(0xFF93C7C2);
const _stationDetailHeroSecondaryColor = Color(0xFFAFC6D4);
const _stationDetailCautionColor = Color(0xFF8A4B00);

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

  Future<void> removeSearch(String query);

  Future<void> clearSearches();
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
        throw const CurrentLocationException('현재 위치를 확인하지 못했어요.');
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
      throw const CurrentLocationException('현재 위치를 확인하지 못했어요.');
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
      'permissionDenied' => _currentLocationPermissionMessage,
      'locationDisabled' => _currentLocationDisabledMessage,
      'locationUnavailable' => '현재 위치를 확인하지 못했어요.',
      _ => '현재 위치를 확인하지 못했어요.',
    };
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
      return '노선을 아직 알 수 없어요';
    }
    return lines.map((line) => line.name).join(', ');
  }

  String get semanticLabel {
    return '즐겨찾기 역, $nameKo, $lineLabel, $region, $dataQualityLabel';
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
      return '노선을 아직 알 수 없어요';
    }
    return lines.map((line) => line.name).join(', ');
  }

  String get distanceLabel {
    final distance = distanceMeters;
    if (distance == null) {
      return '';
    }
    if (distance < 1000) {
      return '현재 위치에서 ${distance}m';
    }
    return '현재 위치에서 ${(distance / 1000).toStringAsFixed(1)}km';
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
      return '노선을 아직 알 수 없어요';
    }
    return lines.map((line) => line.name).join(', ');
  }

  String get semanticLabel {
    return '$nameKo역 자세한 안내, $lineLabel, $dataQualityLabel, 마지막 확인 $lastVerifiedAt';
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
    this.fieldValidationStatus = 'UNKNOWN',
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
      fieldValidationStatus: _stringOrDefault(
        json,
        'fieldValidationStatus',
        'UNKNOWN',
      ),
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
  final String fieldValidationStatus;

  String get elevatorConnectionLabel {
    return hasElevatorConnection ? '엘리베이터 연결' : '엘리베이터 연결을 아직 알 수 없어요';
  }

  String get stairPathLabel {
    return hasStairOnlyPath ? '계단만 있는 길 있음' : '계단 없는 이동 가능';
  }

  String get confidenceLabel => _dataConfidenceLabel(dataConfidence);

  String get dataSourceLabel => _dataSourceLabel(dataSourceType);

  String get fieldValidationLabel =>
      _fieldValidationLabel(fieldValidationStatus);

  String get verificationStatusLabel =>
      _fieldVerificationStatusLabel(fieldValidationStatus);

  String get semanticLabel {
    return '$name, $elevatorConnectionLabel, $stairPathLabel, $verificationStatusLabel';
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
    this.fieldValidationStatus = 'UNKNOWN',
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
      fieldValidationStatus: _stringOrDefault(
        json,
        'fieldValidationStatus',
        'UNKNOWN',
      ),
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
  final String fieldValidationStatus;

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
      'UNKNOWN' => '상태를 확인하고 있어요',
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

  String get confidenceLabel => _dataConfidenceLabel(dataConfidence);

  String get dataSourceLabel => _dataSourceLabel(dataSourceType);

  String get fieldValidationLabel =>
      _fieldValidationLabel(fieldValidationStatus);

  String get verificationStatusLabel =>
      _fieldVerificationStatusLabel(fieldValidationStatus);

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

  String get semanticLabel {
    return '$name, $typeLabel, $statusTitle, $locationLabel, $updatedLabel, $verificationStatusLabel, $nextActionLabel';
  }
}

class StationLayoutSummaryItem {
  const StationLayoutSummaryItem({required this.icon, required this.text});

  final IconData icon;
  final String text;
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

  String get semanticLabel => name;

  StationSearchLine get badgeLine => StationSearchLine(
    id: id,
    name: name,
    color: color,
    stationCode: lineCode,
  );
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
    'LEVEL_1' => '일부 정보는 확인 중이에요',
    'LEVEL_2' => '시설 정보를 함께 볼 수 있어요',
    'LEVEL_3' => '쉬운 길 안내를 볼 수 있어요',
    'LEVEL_4' => '고장·공사 소식이 반영됐어요',
    _ => '정보를 준비 중이에요',
  };
}

String _dataConfidenceLabel(String dataConfidence) {
  return switch (dataConfidence) {
    'HIGH' => '최근 확인된 정보예요',
    'MEDIUM' => '일부 확인된 정보예요',
    'LOW' => '안내를 준비 중이에요',
    _ => '안내를 준비 중이에요',
  };
}

String _fieldValidationLabel(String fieldValidationStatus) {
  final normalizedStatus = fieldValidationStatus.trim().toUpperCase();
  return switch (normalizedStatus) {
    'VERIFIED' => '최근 확인했어요',
    'STALE' => '최근 확인한 내용은 다시 봐 주세요',
    'UNKNOWN' => '최근 확인한 기록이 없어요',
    _ => '최근 확인한 기록이 없어요',
  };
}

String _fieldVerificationStatusLabel(String fieldValidationStatus) {
  final normalizedStatus = fieldValidationStatus.trim().toUpperCase();
  return switch (normalizedStatus) {
    'VERIFIED' => '시설 상태가 확인됐어요',
    'STALE' => '최신 상태를 준비 중이에요',
    _ => '최신 상태를 준비 중이에요',
  };
}

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

enum StationSearchStatus { idle, loading, success, empty, failure }

enum StationSearchResultSource { search, nearby }

class StationSearchState {
  const StationSearchState({
    required this.status,
    required this.results,
    this.message = '',
    this.source = StationSearchResultSource.search,
  });

  const StationSearchState.idle()
    : status = StationSearchStatus.idle,
      results = const [],
      message = '',
      source = StationSearchResultSource.search;

  final StationSearchStatus status;
  final List<StationSearchResult> results;
  final String message;
  final StationSearchResultSource source;
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
          source: StationSearchResultSource.search,
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
        message: '역 정보를 불러오지 못했어요.',
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
          message: '주변 역을 찾지 못했어요.',
        );
      } else {
        _state = StationSearchState(
          status: StationSearchStatus.success,
          results: results,
          source: StationSearchResultSource.nearby,
        );
      }
    } on CurrentLocationException catch (error) {
      if (!_isActiveRequest(requestId)) {
        return;
      }
      _state = StationSearchState(
        status: StationSearchStatus.failure,
        results: const [],
        message: _friendlyCurrentLocationErrorMessage(error.message),
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
        message: '역 정보를 불러오지 못했어요.',
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
    this.realtimeSnapshot = const RealtimeSnapshot.unavailable(),
    this.message = '',
  });

  const StationDetailState.loading()
    : status = StationDetailStatus.loading,
      detail = null,
      exits = const [],
      facilities = const [],
      realtimeSnapshot = const RealtimeSnapshot.unavailable(),
      message = '';

  final StationDetailStatus status;
  final StationDetail? detail;
  final List<StationExitInfo> exits;
  final List<StationFacilityInfo> facilities;
  final RealtimeSnapshot realtimeSnapshot;
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
      return '';
    }
    return buildFacilityAttentionSummary(
      facilities.map((facility) => facility.status),
    );
  }

  String get facilityAttentionSemanticLabel {
    final count = attentionFacilityCount;
    if (count == 0) {
      return '다시 볼 시설이 없어요';
    }
    return buildFacilityAttentionSemanticLabel(
      facilities.map((facility) => facility.status),
    );
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
      return '역 안 이동 안내가 아직 없어요';
    }
    return '역 안 이동 안내, ${items.map((item) => item.text).join(', ')}';
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
  StationDetailController({required this.repository, this.realtimeRepository});

  final StationSearchRepository repository;
  final RealtimeRepository? realtimeRepository;

  StationDetailState _state = const StationDetailState.loading();
  bool _isDisposed = false;

  StationDetailState get state => _state;

  Future<void> load(String stationId) async {
    _state = const StationDetailState.loading();
    notifyListeners();

    try {
      // 상세 화면은 요약, 출구, 시설을 함께 읽되 느린 네트워크에서 대기 시간이 합산되지 않게 병렬로 요청한다.
      final responses = await Future.wait<Object>([
        repository.getStationDetail(stationId),
        repository.listStationExits(stationId),
        repository.listStationFacilities(stationId),
      ]);
      if (_isDisposed) {
        return;
      }
      final detail = responses[0] as StationDetail;
      _state = StationDetailState(
        status: StationDetailStatus.success,
        detail: detail,
        exits: responses[1] as List<StationExitInfo>,
        facilities: responses[2] as List<StationFacilityInfo>,
        realtimeSnapshot: const RealtimeSnapshot.loading(),
      );
      notifyListeners();
      await _refreshRealtimeSnapshot(detail);
      return;
    } on StationSearchException {
      if (_isDisposed) {
        return;
      }
      _state = const StationDetailState(
        status: StationDetailStatus.failure,
        message: '역 안내를 불러오지 못했어요.',
      );
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '역 상세 화면 로드 중 예외가 발생했습니다.');
      if (_isDisposed) {
        return;
      }
      _state = const StationDetailState(
        status: StationDetailStatus.failure,
        message: '역 안내를 불러오지 못했어요.',
      );
    }

    notifyListeners();
  }

  Future<void> _refreshRealtimeSnapshot(StationDetail detail) async {
    final realtimeSnapshot = await _loadRealtimeSnapshot(detail);
    if (_isDisposed || _state.detail?.id != detail.id) {
      return;
    }
    _state = StationDetailState(
      status: _state.status,
      detail: _state.detail,
      exits: _state.exits,
      facilities: _state.facilities,
      realtimeSnapshot: realtimeSnapshot,
      message: _state.message,
    );
    notifyListeners();
  }

  Future<RealtimeSnapshot> _loadRealtimeSnapshot(StationDetail detail) async {
    final repository = realtimeRepository;
    if (repository == null) {
      return const RealtimeSnapshot.unavailable();
    }
    final firstLine = detail.lines.isEmpty ? null : detail.lines.first;
    if (firstLine == null) {
      return const RealtimeSnapshot(
        status: RealtimeSnapshotStatus.unsupported,
        fallbackCode: 'LINE_MAPPING_MISSING',
        message: '이 노선은 아직 실시간 열차 안내가 어려워요.',
        receivedAt: '',
        arrivals: [],
      );
    }
    try {
      return await repository.arrivals(
        RealtimeStationQuery(
          stationId: detail.id,
          lineId: firstLine.id,
          providerLineId: firstLine.stationCode.isEmpty
              ? firstLine.id
              : firstLine.stationCode,
          stationQueryName: detail.nameKo,
        ),
      );
    } on RealtimeException catch (error) {
      return RealtimeSnapshot(
        status: RealtimeSnapshotStatus.unavailable,
        fallbackCode: 'PROVIDER_ERROR',
        message: '${error.message} 역 정보와 경로 검색은 계속 이용할 수 있습니다.',
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 상세 실시간 열차 조회 중 예외가 발생했습니다.',
      );
      return const RealtimeSnapshot.unavailable();
    }
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
    this.removingIds = const {},
  });

  const FavoriteStationListState.loading()
    : status = FavoriteStationListStatus.loading,
      favorites = const [],
      message = '',
      removingIds = const {};

  final FavoriteStationListStatus status;
  final List<FavoriteStation> favorites;
  final String message;
  final Set<String> removingIds;

  FavoriteStationListState copyWith({
    FavoriteStationListStatus? status,
    List<FavoriteStation>? favorites,
    String? message,
    Set<String>? removingIds,
  }) {
    return FavoriteStationListState(
      status: status ?? this.status,
      favorites: favorites ?? this.favorites,
      message: message ?? this.message,
      removingIds: removingIds ?? this.removingIds,
    );
  }
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
            message: '즐겨찾기한 역이 없습니다.',
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

  Future<void> remove(FavoriteStation favorite) async {
    final stationId = favorite.stationId;
    if (_state.removingIds.contains(stationId)) {
      return;
    }

    _emitState(
      _state.copyWith(removingIds: {..._state.removingIds, stationId}),
    );

    try {
      await repository.removeFavoriteStation(stationId);
      final nextFavorites = _state.favorites
          .where((item) => item.stationId != stationId)
          .toList(growable: false);
      final nextRemovingIds = {..._state.removingIds}..remove(stationId);
      _emitState(
        nextFavorites.isEmpty
            ? FavoriteStationListState(
                status: FavoriteStationListStatus.empty,
                message: '즐겨찾기한 역이 없습니다.',
                removingIds: nextRemovingIds,
              )
            : FavoriteStationListState(
                status: FavoriteStationListStatus.success,
                favorites: nextFavorites,
                removingIds: nextRemovingIds,
              ),
      );
    } on FavoriteStationException catch (error) {
      _emitFailure(error.message, removingIdToClear: stationId);
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '즐겨찾기 역 해제 중 예외가 발생했습니다.');
      _emitFailure(
        _favoriteStationChangeErrorMessage,
        removingIdToClear: stationId,
      );
    }
  }

  void _emitFailure(String message, {String? removingIdToClear}) {
    final nextRemovingIds = {..._state.removingIds};
    if (removingIdToClear != null) {
      nextRemovingIds.remove(removingIdToClear);
    }
    _emitState(
      FavoriteStationListState(
        status: FavoriteStationListStatus.failure,
        favorites: _state.favorites,
        message: message,
        removingIds: nextRemovingIds,
      ),
    );
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
    this.realtimeRepository,
    this.facilityReportDraftTargetStore,
    this.internalRouteRepository,
    this.internalRouteMobilityType = 'SENIOR',
    this.routeDraftController,
    this.entryMode = StationSearchEntryMode.search,
    this.onOpenRouteSearch,
    this.bottomNavigationBar,
    super.key,
  });

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final CurrentLocationProvider locationProvider;
  final FavoriteStationRepository? favoriteRepository;
  final SearchHistoryRepository? searchHistoryRepository;
  final RealtimeRepository? realtimeRepository;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final InternalRouteRepository? internalRouteRepository;
  final String internalRouteMobilityType;
  final RouteDraftController? routeDraftController;
  final StationSearchEntryMode entryMode;
  final Future<void> Function()? onOpenRouteSearch;
  final Widget? bottomNavigationBar;

  @override
  State<StationSearchScreen> createState() => _StationSearchScreenState();
}

enum StationSearchEntryMode { search, recent, nearby }

class _StationSearchScreenState extends State<StationSearchScreen> {
  late final StationSearchController _controller;
  final TextEditingController _queryController = TextEditingController();
  Future<List<SubwayLineOption>>? _lineOptionsFuture;
  List<String> _recentQueries = const [];
  SubwayLineOption? _selectedLine;
  String? _selectedLineRegion;
  bool _isLineFilterExpanded = true;
  bool _isNearbySearchRunning = false;
  bool _isOpeningLocationSettings = false;

  @override
  void initState() {
    super.initState();
    _controller = StationSearchController(
      repository: widget.repository,
      searchHistoryRepository: widget.searchHistoryRepository,
    );
    _controller.addListener(_handleControllerChanged);
    _queryController.addListener(_handleQueryChanged);
    final lineRepository = _lineFilterRepository;
    if (lineRepository != null) {
      _lineOptionsFuture = lineRepository.listLines();
    }
    unawaited(_loadRecentQueries());
    if (widget.entryMode == StationSearchEntryMode.nearby) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_searchNearby());
        }
      });
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleControllerChanged)
      ..dispose();
    _queryController.removeListener(_handleQueryChanged);
    _queryController.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
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
    final isRecentEntry = widget.entryMode == StationSearchEntryMode.recent;
    final isNearbyEntry = widget.entryMode == StationSearchEntryMode.nearby;
    const showSearchInput = true;
    final showNearbyRetryButton = isNearbyEntry && !_hasSearchQuery;
    final searchInputSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSearchInput) ...[
          TextField(
            key: const Key('stationSearchInput'),
            controller: _queryController,
            minLines: 1,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 20, height: 1.35),
            decoration: InputDecoration(
              hintText: '역 이름을 입력해 주세요',
              floatingLabelBehavior: FloatingLabelBehavior.always,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _hasSearchQuery
                  ? IconButton(
                      tooltip: '검색어 지우기',
                      onPressed: _queryController.clear,
                      icon: const Icon(Icons.close),
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: _stationSearchInputRadius,
                borderSide: const BorderSide(
                  color: EasySubwayAccessibleColors.line,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: _stationSearchInputRadius,
                borderSide: const BorderSide(
                  color: EasySubwayAccessibleColors.line,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: _stationSearchInputRadius,
                borderSide: const BorderSide(
                  color: EasySubwayAccessibleColors.primary,
                  width: 2,
                ),
              ),
            ),
            onSubmitted: _submit,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
    final recentSearchSection = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final isSearching =
            _controller.state.status == StationSearchStatus.loading;
        if (isNearbyEntry || _hasSearchQuery) {
          return const SizedBox.shrink();
        }
        if (_recentQueries.isEmpty) {
          return isRecentEntry
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _StationRecentSearchEmptyState(
                    onSearchTap: _openStationSearch,
                  ),
                )
              : const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _StationRecentSearchSection(
            queries: _recentQueries,
            showTitle: !isRecentEntry,
            enabled: !isSearching && !_isNearbySearchRunning,
            onQuerySelected: _searchRecentQuery,
            onQueryRemoved: _removeRecentQuery,
            onClearAll: _clearRecentQueries,
          ),
        );
      },
    );
    final actionButtonSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final isSearching =
                _controller.state.status == StationSearchStatus.loading;
            final isNearbyDisabled = isSearching || _isNearbySearchRunning;
            if (showNearbyRetryButton) {
              return OutlinedButton.icon(
                key: const Key('nearbyStationSearchButton'),
                onPressed: isNearbyDisabled ? null : _searchNearby,
                icon: const Icon(Icons.my_location),
                label: const Text('내 주변 역 다시 찾기'),
              );
            }
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
      ],
    );
    final resultSection = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return _StationSearchBody(
          state: _controller.state,
          onResultTap: _openStationDetail,
          onSetOrigin: widget.routeDraftController == null
              ? null
              : _setRouteOrigin,
          onSetDestination: widget.routeDraftController == null
              ? null
              : _setRouteDestination,
          isOpeningLocationSettings: _isOpeningLocationSettings,
          onOpenLocationSettings: _openLocationSettings,
        );
      },
    );
    final lineFilterSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSearchInput && _lineOptionsFuture != null)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final isSearching =
                  _controller.state.status == StationSearchStatus.loading;
              final hasSearchResults =
                  _controller.state.status == StationSearchStatus.success &&
                  _controller.state.source == StationSearchResultSource.search;
              return _StationLineFilterPanel(
                expanded: !hasSearchResults || _isLineFilterExpanded,
                collapsible: hasSearchResults,
                onToggleExpanded: () {
                  setState(() {
                    _isLineFilterExpanded = !_isLineFilterExpanded;
                  });
                },
                child: _StationLineFilterSection(
                  linesFuture: _lineOptionsFuture!,
                  selectedLine: _selectedLine,
                  selectedRegion: _selectedLineRegion,
                  enabled: !isSearching && !_isNearbySearchRunning,
                  onRegionSelected: _selectLineRegion,
                  onLineSelected: _selectLine,
                ),
              );
            },
          ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(switch (widget.entryMode) {
              StationSearchEntryMode.recent => '최근 검색',
              StationSearchEntryMode.nearby => '가까운 역',
              StationSearchEntryMode.search => '역 검색',
            }),
            const Text(
              ProductionScopeCopy.supportedClaimKo,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          if (!isRecentEntry && !isNearbyEntry)
            TextButton.icon(
              key: const Key('nearbyStationAppBarButton'),
              onPressed: _isNearbySearchRunning ? null : _searchNearby,
              icon: const Icon(Icons.my_location),
              label: const Text('가까운 역'),
            ),
        ],
      ),
      bottomNavigationBar: widget.bottomNavigationBar,
      body: Semantics(
        container: true,
        label: ProductionScopeCopy.stationSearchNotice,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isLargeScreen = EasySubwayAdaptiveLayout.isLargeScreen(
                constraints,
                textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
              );
              return ListView(
                padding: isLargeScreen
                    ? _stationSearchLargePagePadding
                    : _stationSearchPagePadding,
                children: [
                  _StationSearchAdaptiveContent(
                    isLargeScreen: isLargeScreen,
                    searchInputSection: searchInputSection,
                    recentSearchSection: recentSearchSection,
                    actionButtonSection: actionButtonSection,
                    resultSection: resultSection,
                    lineFilterSection: lineFilterSection,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _submit(String query) {
    if (_controller.state.status == StationSearchStatus.loading) {
      return;
    }
    unawaited(_runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    await _controller.search(query, lineId: _selectedLine?.id);
    await _loadRecentQueries();
    if (mounted &&
        _controller.state.status == StationSearchStatus.success &&
        _controller.state.source == StationSearchResultSource.search) {
      setState(() => _isLineFilterExpanded = false);
    }
  }

  void _searchRecentQuery(String query) {
    _queryController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _submit(query);
  }

  void _openStationSearch() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => StationSearchScreen(
          repository: widget.repository,
          locationProvider: widget.locationProvider,
          reportRepository: widget.reportRepository,
          favoriteRepository: widget.favoriteRepository,
          searchHistoryRepository: widget.searchHistoryRepository,
          realtimeRepository: widget.realtimeRepository,
          routeDraftController: widget.routeDraftController,
          onOpenRouteSearch: widget.onOpenRouteSearch,
          facilityReportDraftTargetStore: widget.facilityReportDraftTargetStore,
          internalRouteRepository: widget.internalRouteRepository,
          internalRouteMobilityType: widget.internalRouteMobilityType,
        ),
      ),
    );
  }

  Future<void> _removeRecentQuery(String query) async {
    final repository = widget.searchHistoryRepository;
    if (repository == null) {
      return;
    }
    try {
      await repository.removeSearch(query);
      await _loadRecentQueries();
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '최근 검색어 삭제 중 예외가 발생했습니다.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(_searchHistoryChangeErrorMessage)),
        );
      }
    }
  }

  Future<void> _clearRecentQueries() async {
    final repository = widget.searchHistoryRepository;
    if (repository == null) {
      return;
    }
    try {
      await repository.clearSearches();
      await _loadRecentQueries();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '최근 검색어 전체 삭제 중 예외가 발생했습니다.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(_searchHistoryChangeErrorMessage)),
        );
      }
    }
  }

  Future<void> _loadRecentQueries() async {
    final repository = widget.searchHistoryRepository;
    if (repository == null) {
      return;
    }
    try {
      final queries = await repository.listRecentQueries();
      if (!mounted) {
        return;
      }
      setState(() => _recentQueries = queries);
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '최근 검색어 조회 중 예외가 발생했습니다.');
    }
  }

  StationLineFilterRepository? get _lineFilterRepository {
    final Object repository = widget.repository;
    if (repository is StationLineFilterRepository) {
      return repository;
    }
    return null;
  }

  void _selectLine(SubwayLineOption? line) {
    setState(() {
      _selectedLine = line;
      if (line != null) {
        _selectedLineRegion = line.region;
      }
    });
  }

  void _selectLineRegion(String region) {
    setState(() {
      _selectedLineRegion = region;
      if (_selectedLine?.region != region) {
        _selectedLine = null;
      }
    });
  }

  void _setRouteOrigin(StationSearchResult result) {
    final station = RouteDraftStation(id: result.id, nameKo: result.nameKo);
    widget.routeDraftController?.setOrigin(station);
    _showRouteDraftSnack('${station.displayName}을 출발역으로 설정했습니다');
  }

  void _setRouteDestination(StationSearchResult result) {
    final station = RouteDraftStation(id: result.id, nameKo: result.nameKo);
    widget.routeDraftController?.setDestination(station);
    _showRouteDraftSnack('${station.displayName}을 도착역으로 설정했습니다');
  }

  void _showRouteDraftSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: widget.onOpenRouteSearch == null
            ? null
            : SnackBarAction(
                label: '길찾기 보기',
                onPressed: () => unawaited(widget.onOpenRouteSearch!()),
              ),
      ),
    );
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
                Text(_locationPermissionRationaleDenialNotice),
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
          realtimeRepository: widget.realtimeRepository,
          locationProvider: widget.locationProvider,
          stationId: result.id,
          facilityReportDraftTargetStore: widget.facilityReportDraftTargetStore,
          internalRouteRepository: widget.internalRouteRepository,
          internalRouteMobilityType: widget.internalRouteMobilityType,
          routeDraftController: widget.routeDraftController,
        ),
      ),
    );
  }
}

class _StationRecentSearchSection extends StatelessWidget {
  const _StationRecentSearchSection({
    required this.queries,
    required this.showTitle,
    required this.enabled,
    required this.onQuerySelected,
    required this.onQueryRemoved,
    required this.onClearAll,
  });

  final List<String> queries;
  final bool showTitle;
  final bool enabled;
  final ValueChanged<String> onQuerySelected;
  final ValueChanged<String> onQueryRemoved;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('stationRecentSearchSection'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle) ...[
          Text(
            '최근 검색',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: EasySubwayAccessibleColors.text,
              fontWeight: FontWeight.w900,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: Semantics(
                excludeSemantics: true,
                label: '최근 사용 순서로 ${queries.length}개 표시',
                child: Text(
                  '최근 사용 순서 · ${queries.length}개',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: EasySubwayAccessibleColors.mutedText,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
            ),
            TextButton.icon(
              key: const Key('stationRecentSearchClearAllButton'),
              onPressed: enabled ? onClearAll : null,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('전체 삭제'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Column(
          children: [
            for (final entry in queries.indexed)
              _StationRecentSearchItem(
                query: entry.$2,
                order: entry.$1 + 1,
                enabled: enabled,
                onQuerySelected: onQuerySelected,
                onQueryRemoved: onQueryRemoved,
              ),
          ],
        ),
      ],
    );
  }
}

class _StationRecentSearchItem extends StatelessWidget {
  const _StationRecentSearchItem({
    required this.query,
    required this.order,
    required this.enabled,
    required this.onQuerySelected,
    required this.onQueryRemoved,
  });

  final String query;
  final int order;
  final bool enabled;
  final ValueChanged<String> onQuerySelected;
  final ValueChanged<String> onQueryRemoved;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: _stationCompactCardRadius,
          side: const BorderSide(color: EasySubwayAccessibleColors.line),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  label: '최근 검색어 $query 검색, 최근 사용 $order번째',
                  button: true,
                  enabled: enabled,
                  onTap: enabled ? () => onQuerySelected(query) : null,
                  child: ExcludeSemantics(
                    child: InkWell(
                      key: Key('stationRecentSearchQuery-$query'),
                      borderRadius: _stationCompactCardRadius,
                      onTap: enabled ? () => onQuerySelected(query) : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.history,
                              color: EasySubwayAccessibleColors.brand,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    query,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color:
                                              EasySubwayAccessibleColors.text,
                                          fontWeight: FontWeight.w800,
                                          height: 1.25,
                                        ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '최근 사용 $order번째',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: EasySubwayAccessibleColors
                                              .mutedText,
                                          fontWeight: FontWeight.w700,
                                          height: 1.3,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                key: Key('stationRecentSearchRemove-$query'),
                tooltip: '$query 최근 검색 삭제',
                onPressed: enabled ? () => onQueryRemoved(query) : null,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StationRecentSearchEmptyState extends StatelessWidget {
  const _StationRecentSearchEmptyState({required this.onSearchTap});

  final VoidCallback onSearchTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('stationRecentSearchEmptyState'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StationSearchMessage(
          message: '최근 검색한 역이 없습니다.',
          liveRegion: false,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('stationRecentSearchEmptySearchButton'),
          onPressed: onSearchTap,
          icon: const Icon(Icons.search),
          label: const Text('역 검색하기'),
        ),
      ],
    );
  }
}

class _StationLineFilterPanel extends StatelessWidget {
  const _StationLineFilterPanel({
    required this.expanded,
    required this.collapsible,
    required this.onToggleExpanded,
    required this.child,
  });

  final bool expanded;
  final bool collapsible;
  final VoidCallback onToggleExpanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('stationLineFilterPanel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (collapsible) ...[
          OutlinedButton.icon(
            key: const Key('stationLineFilterToggle'),
            onPressed: onToggleExpanded,
            icon: Icon(expanded ? Icons.expand_less : Icons.tune),
            label: Text(expanded ? '노선 필터 접기' : '노선 필터 펼치기'),
          ),
          if (expanded) const SizedBox(height: 12),
        ],
        if (expanded) child,
      ],
    );
  }
}

class _StationLineFilterSection extends StatelessWidget {
  const _StationLineFilterSection({
    required this.linesFuture,
    required this.selectedLine,
    required this.selectedRegion,
    required this.enabled,
    required this.onRegionSelected,
    required this.onLineSelected,
  });

  final Future<List<SubwayLineOption>> linesFuture;
  final SubwayLineOption? selectedLine;
  final String? selectedRegion;
  final bool enabled;
  final ValueChanged<String> onRegionSelected;
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
            '노선을 불러오지 못했어요.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: EasySubwayAccessibleColors.secondaryText,
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

        final seenRegions = <String>{};
        final regions = <String>[
          for (final line in lines)
            if (seenRegions.add(line.region)) line.region,
        ]..sort(_compareStationLineRegions);
        final currentRegion =
            selectedRegion ?? selectedLine?.region ?? regions.first;
        final visibleLines = lines
            .where((line) => line.region == currentRegion)
            .toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final region in regions) ...[
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _StationLineRegionButton(
                        key: Key('stationLineRegion-$region'),
                        label: region,
                        selected: region == currentRegion,
                        onPressed: enabled
                            ? () => onRegionSelected(region)
                            : null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StationLineFilterButton(
                  key: const Key('stationLineFilter-all'),
                  label: '전체 노선',
                  semanticLabel: '전체 노선',
                  selected: selectedLine == null,
                  onPressed: enabled ? () => onLineSelected(null) : null,
                ),
                for (final line in visibleLines)
                  _StationLineFilterButton(
                    key: Key('stationLineFilter-${line.id}'),
                    label: line.name,
                    semanticLabel: line.semanticLabel,
                    selected: selectedLine?.id == line.id,
                    badgeLine: line.badgeLine,
                    onPressed: enabled ? () => onLineSelected(line) : null,
                  ),
                OutlinedButton.icon(
                  key: const Key('stationLineFilterMoreButton'),
                  onPressed: enabled
                      ? () => _showAllLineSheet(context, lines)
                      : null,
                  icon: const Icon(Icons.list_alt),
                  label: const Text('전체 노선 보기'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAllLineSheet(
    BuildContext context,
    List<SubwayLineOption> lines,
  ) async {
    final selected = await showModalBottomSheet<Object?>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            key: const Key('stationLineAllSheet'),
            padding: _stationLineSheetPadding,
            children: [
              Text(
                '전체 노선 보기',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w900,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 12),
              _StationLineFilterButton(
                key: const Key('stationLineFilter-all'),
                label: '전체 노선',
                semanticLabel: '전체 노선',
                selected: selectedLine == null,
                onPressed: () => Navigator.of(context).pop(false),
              ),
              const SizedBox(height: 8),
              for (final line in lines) ...[
                _StationLineFilterButton(
                  key: Key('stationLineFilter-${line.id}'),
                  label: line.name,
                  semanticLabel: line.semanticLabel,
                  selected: selectedLine?.id == line.id,
                  badgeLine: line.badgeLine,
                  onPressed: () => Navigator.of(context).pop(line),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
    );
    if (selected is SubwayLineOption) {
      onLineSelected(selected);
    } else if (selected == false) {
      onLineSelected(null);
    }
  }
}

class _StationLineRegionButton extends StatelessWidget {
  const _StationLineRegionButton({
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label 지역 ${selected ? '선택됨' : '선택 안 됨'}',
      button: true,
      selected: selected,
      enabled: onPressed != null,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: onPressed == null ? null : (_) => onPressed?.call(),
          labelStyle: TextStyle(
            color: selected ? Colors.white : EasySubwayAccessibleColors.text,
            fontWeight: FontWeight.w800,
          ),
          selectedColor: _stationLineFilterSelectedColor,
          backgroundColor: Colors.white,
          side: const BorderSide(color: _stationLineFilterBorderColor),
          shape: const RoundedRectangleBorder(
            borderRadius: _stationLineRegionChipRadius,
          ),
        ),
      ),
    );
  }
}

int _compareStationLineRegions(String left, String right) {
  final leftRank = _stationLineRegionRank(left);
  final rightRank = _stationLineRegionRank(right);
  if (leftRank != rightRank) {
    return leftRank.compareTo(rightRank);
  }
  return left.compareTo(right);
}

int _stationLineRegionRank(String region) {
  const preferredRegions = ['수도권', '부산', '대구', '광주', '대전'];
  final index = preferredRegions.indexOf(region);
  return index == -1 ? preferredRegions.length : index;
}

class _StationLineFilterButton extends StatelessWidget {
  const _StationLineFilterButton({
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.onPressed,
    this.badgeLine,
    super.key,
  });

  final String label;
  final String semanticLabel;
  final bool selected;
  final VoidCallback? onPressed;
  final StationSearchLine? badgeLine;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = selected
        ? _stationLineFilterSelectedColor
        : Colors.white;
    final foregroundColor = selected
        ? Colors.white
        : EasySubwayAccessibleColors.text;
    final borderColor = selected
        ? _stationLineFilterSelectedColor
        : _stationLineFilterBorderColor;

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
            minimumSize: const Size(74, 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            side: BorderSide(color: borderColor, width: selected ? 2 : 1.5),
            shape: const RoundedRectangleBorder(
              borderRadius: _stationLineFilterButtonRadius,
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badgeLine != null) ...[
                StationLineBadge(line: badgeLine!, size: 26),
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

class _StationSearchAdaptiveContent extends StatelessWidget {
  const _StationSearchAdaptiveContent({
    required this.isLargeScreen,
    required this.searchInputSection,
    required this.recentSearchSection,
    required this.actionButtonSection,
    required this.resultSection,
    required this.lineFilterSection,
  });

  final bool isLargeScreen;
  final Widget searchInputSection;
  final Widget recentSearchSection;
  final Widget actionButtonSection;
  final Widget resultSection;
  final Widget lineFilterSection;

  @override
  Widget build(BuildContext context) {
    if (!isLargeScreen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          searchInputSection,
          recentSearchSection,
          actionButtonSection,
          resultSection,
          const SizedBox(height: 16),
          lineFilterSection,
        ],
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: EasySubwayAdaptiveLayout.largeScreenMaxContentWidth,
        ),
        child: Row(
          key: const Key('stationSearchLargeScreenLayout'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  searchInputSection,
                  actionButtonSection,
                  resultSection,
                ],
              ),
            ),
            const SizedBox(
              width: EasySubwayAdaptiveLayout.largeScreenColumnGap,
            ),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [recentSearchSection, lineFilterSection],
              ),
            ),
          ],
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
    this.onSetOrigin,
    this.onSetDestination,
  });

  final StationSearchState state;
  final ValueChanged<StationSearchResult> onResultTap;
  final bool isOpeningLocationSettings;
  final VoidCallback onOpenLocationSettings;
  final ValueChanged<StationSearchResult>? onSetOrigin;
  final ValueChanged<StationSearchResult>? onSetDestination;

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
            container: true,
            label: state.source == StationSearchResultSource.nearby
                ? '주변 역 ${state.results.length}개'
                : '검색 결과 ${state.results.length}개',
            liveRegion: true,
            child: const SizedBox(width: 1, height: 1),
          ),
          if (state.source == StationSearchResultSource.nearby) ...[
            if (state.results.isEmpty)
              _StationSearchFailureMessage(
                message: '주변 역을 찾지 못했어요.',
                isOpeningLocationSettings: isOpeningLocationSettings,
                onOpenLocationSettings: onOpenLocationSettings,
              )
            else ...[
              _NearbyStationOverview(
                result: state.results.first,
                onTap: () => onResultTap(state.results.first),
                onSetOrigin: onSetOrigin == null
                    ? null
                    : () => onSetOrigin!(state.results.first),
                onSetDestination: onSetDestination == null
                    ? null
                    : () => onSetDestination!(state.results.first),
              ),
              if (state.results.length > 1) ...[
                const SizedBox(height: 18),
                const _StationDetailSectionTitle(title: '다른 주변 역'),
                const SizedBox(height: 12),
              ],
            ],
          ] else ...[
            const _StationDetailSectionTitle(title: '검색 결과'),
            const SizedBox(height: 12),
          ],
          for (final result
              in state.source == StationSearchResultSource.nearby
                  ? state.results.skip(1)
                  : state.results)
            _StationSearchResultTile(
              result: result,
              onTap: () => onResultTap(result),
              onSetOrigin: onSetOrigin == null
                  ? null
                  : () => onSetOrigin!(result),
              onSetDestination: onSetDestination == null
                  ? null
                  : () => onSetDestination!(result),
            ),
        ],
      ),
    };
  }
}

class _NearbyStationOverview extends StatelessWidget {
  const _NearbyStationOverview({
    required this.result,
    required this.onTap,
    this.onSetOrigin,
    this.onSetDestination,
  });

  final StationSearchResult result;
  final VoidCallback onTap;
  final VoidCallback? onSetOrigin;
  final VoidCallback? onSetDestination;

  @override
  Widget build(BuildContext context) {
    final stationName = _stationResultDisplayName(result.nameKo);
    return Card(
      margin: EdgeInsets.zero,
      color: EasySubwayAccessibleColors.skySoft,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: _stationDetailFacilityCardRadius,
        side: const BorderSide(color: EasySubwayAccessibleColors.line),
      ),
      child: Column(
        children: [
          Semantics(
            container: true,
            button: true,
            label: '가장 가까운 역, ${_stationResultSemanticLabel(result)}',
            onTap: onTap,
            child: ExcludeSemantics(
              child: InkWell(
                key: const Key('nearbyStationPrimaryCard'),
                borderRadius: _stationDetailFacilityCardRadius,
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '가장 가까운 역',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: EasySubwayAccessibleColors.mutedText,
                                    fontWeight: FontWeight.w800,
                                    height: 1.25,
                                  ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              stationName,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    color: EasySubwayAccessibleColors.text,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              result.distanceLabel.isEmpty
                                  ? result.lineLabel
                                  : '${result.distanceLabel} · ${result.lineLabel}',
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: EasySubwayAccessibleColors.mutedText,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            _StationDetailTextPill(
                              text: result.dataQualityLabel,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      StationLineBadges(
                        lines: result.lines,
                        size: 38,
                        maxBadgeCount: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (onSetOrigin != null || onSetDestination != null)
            _StationRoleActionBar(
              stationId: result.id,
              stationName: stationName,
              onSetOrigin: onSetOrigin,
              onSetDestination: onSetDestination,
            ),
        ],
      ),
    );
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
    final shouldShowStationSearchNextAction =
        _shouldShowStationSearchFailureNextAction(message);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StationSearchMessage(message: message, liveRegion: true),
        if (shouldShowStationSearchNextAction) ...[
          const SizedBox(height: 8),
          Semantics(
            key: const Key('stationSearchFailureNextAction'),
            container: true,
            excludeSemantics: true,
            label: '도움말, $_stationSearchFailureNextAction',
            child: Text(
              _stationSearchFailureNextAction,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _stationTextSubtleColor,
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
  return message == _currentLocationPermissionMessage ||
      message == _currentLocationDisabledMessage ||
      message == '현재 위치를 확인하지 못했어요.' ||
      message == '주변 역을 찾지 못했어요.';
}

String _friendlyCurrentLocationErrorMessage(String message) {
  if (message.contains('권한')) {
    return _currentLocationPermissionMessage;
  }
  return message.isEmpty ? '현재 위치를 확인하지 못했어요.' : message;
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
          color: _stationTextMutedColor,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}

class _StationSearchResultTile extends StatelessWidget {
  const _StationSearchResultTile({
    required this.result,
    required this.onTap,
    this.onSetOrigin,
    this.onSetDestination,
  });

  final StationSearchResult result;
  final VoidCallback onTap;
  final VoidCallback? onSetOrigin;
  final VoidCallback? onSetDestination;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final stationName = _stationResultDisplayName(result.nameKo);
    final semanticLabel = _stationResultSemanticLabel(result);
    final hasRoleActions = onSetOrigin != null || onSetDestination != null;

    // 항목마다 테두리 박스를 두지 않고 하단 구분선만 둔 깔끔한 리스트 행으로 표시한다.
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: EasySubwayAccessibleColors.line),
        ),
      ),
      child: Column(
        children: [
          MergeSemantics(
            child: Semantics(
              label: semanticLabel,
              button: true,
              onTap: onTap,
              child: ExcludeSemantics(
                child: InkWell(
                  key: Key('stationSearchResult-${result.id}'),
                  onTap: onTap,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 78),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
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
                                  style: textTheme.titleLarge?.copyWith(
                                    color: EasySubwayAccessibleColors.text,
                                    fontWeight: FontWeight.w700,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  result.distanceLabel.isEmpty
                                      ? result.lineLabel
                                      : '${result.distanceLabel} · ${result.lineLabel}',
                                  style: textTheme.bodyLarge?.copyWith(
                                    color: EasySubwayAccessibleColors
                                        .secondaryText,
                                    fontWeight: FontWeight.w600,
                                    height: 1.25,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  result.dataQualityLabel,
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: _stationTextMutedColor,
                                    fontWeight: FontWeight.w600,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.chevron_right,
                            color: _stationTextMutedColor,
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
          if (hasRoleActions)
            _StationRoleActionBar(
              stationId: result.id,
              stationName: stationName,
              onSetOrigin: onSetOrigin,
              onSetDestination: onSetDestination,
            ),
        ],
      ),
    );
  }
}

class _StationRoleActionBar extends StatelessWidget {
  const _StationRoleActionBar({
    required this.stationId,
    required this.stationName,
    this.onSetOrigin,
    this.onSetDestination,
  });

  final String stationId;
  final String stationName;
  final VoidCallback? onSetOrigin;
  final VoidCallback? onSetDestination;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _stationRoleActionPadding,
      child: Row(
        children: [
          Expanded(
            child: _StationRoleButton(
              key: Key('stationRoleOrigin-$stationId'),
              icon: Icons.trip_origin,
              label: '출발',
              semanticLabel: '$stationName을 출발역으로 설정',
              onPressed: onSetOrigin,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StationRoleButton(
              key: Key('stationRoleDestination-$stationId'),
              icon: Icons.flag_outlined,
              label: '도착',
              semanticLabel: '$stationName을 도착역으로 설정',
              onPressed: onSetDestination,
            ),
          ),
        ],
      ),
    );
  }
}

class _StationRoleButton extends StatelessWidget {
  const _StationRoleButton({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: OutlinedButton.icon(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(EasySubwayTouchTarget.iconOnly),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
          icon: Icon(icon, size: 20),
          label: Text(label, textAlign: TextAlign.center),
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
    return '$stationName, ${result.lineLabel}, ${result.region}, ${result.dataQualityLabel}';
  }
  return '$stationName, $distance, ${result.lineLabel}, ${result.region}, ${result.dataQualityLabel}';
}

class FavoriteStationListScreen extends StatefulWidget {
  const FavoriteStationListScreen({
    required this.repository,
    required this.stationRepository,
    required this.reportRepository,
    this.locationProvider,
    this.realtimeRepository,
    this.facilityReportDraftTargetStore,
    this.internalRouteRepository,
    this.internalRouteMobilityType = 'SENIOR',
    this.routeDraftController,
    super.key,
  });

  final FavoriteStationRepository repository;
  final StationSearchRepository stationRepository;
  final FacilityReportRepository reportRepository;
  final CurrentLocationProvider? locationProvider;
  final RealtimeRepository? realtimeRepository;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final InternalRouteRepository? internalRouteRepository;
  final String internalRouteMobilityType;
  final RouteDraftController? routeDraftController;

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
        realtimeRepository: widget.realtimeRepository,
        facilityReportDraftTargetStore: widget.facilityReportDraftTargetStore,
        internalRouteRepository: widget.internalRouteRepository,
        internalRouteMobilityType: widget.internalRouteMobilityType,
        routeDraftController: widget.routeDraftController,
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
    this.realtimeRepository,
    this.facilityReportDraftTargetStore,
    this.internalRouteRepository,
    this.internalRouteMobilityType = 'SENIOR',
    this.routeDraftController,
    super.key,
  });

  final FavoriteStationRepository repository;
  final StationSearchRepository stationRepository;
  final FacilityReportRepository reportRepository;
  final CurrentLocationProvider? locationProvider;
  final RealtimeRepository? realtimeRepository;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final InternalRouteRepository? internalRouteRepository;
  final String internalRouteMobilityType;
  final RouteDraftController? routeDraftController;

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
            onFacilityStatusTap: _openStationDetail,
            onSetOrigin: widget.routeDraftController == null
                ? null
                : _setRouteOrigin,
            onSetDestination: widget.routeDraftController == null
                ? null
                : _setRouteDestination,
            onRemove: _controller.remove,
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
          realtimeRepository: widget.realtimeRepository,
          stationId: favorite.stationId,
          facilityReportDraftTargetStore: widget.facilityReportDraftTargetStore,
          internalRouteRepository: widget.internalRouteRepository,
          internalRouteMobilityType: widget.internalRouteMobilityType,
          routeDraftController: widget.routeDraftController,
          // 목록에서 들어온 역은 이미 저장된 상태로 보여 해제 동작을 바로 할 수 있게 한다.
          initiallyFavorite: true,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    unawaited(_controller.load());
  }

  void _setRouteOrigin(FavoriteStation favorite) {
    final routeDraftController = widget.routeDraftController;
    if (routeDraftController == null) {
      return;
    }
    final station = RouteDraftStation(
      id: favorite.stationId,
      nameKo: favorite.nameKo,
    );
    routeDraftController.setOrigin(station);
    _showRouteDraftSnack('${station.displayName}을 출발역으로 설정했습니다');
  }

  void _setRouteDestination(FavoriteStation favorite) {
    final routeDraftController = widget.routeDraftController;
    if (routeDraftController == null) {
      return;
    }
    final station = RouteDraftStation(
      id: favorite.stationId,
      nameKo: favorite.nameKo,
    );
    routeDraftController.setDestination(station);
    _showRouteDraftSnack('${station.displayName}을 도착역으로 설정했습니다');
  }

  void _showRouteDraftSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FavoriteStationListBody extends StatelessWidget {
  const _FavoriteStationListBody({
    required this.state,
    required this.onRetry,
    required this.onFavoriteTap,
    required this.onFacilityStatusTap,
    required this.onSetOrigin,
    required this.onSetDestination,
    required this.onRemove,
  });

  final FavoriteStationListState state;
  final VoidCallback onRetry;
  final ValueChanged<FavoriteStation> onFavoriteTap;
  final ValueChanged<FavoriteStation> onFacilityStatusTap;
  final ValueChanged<FavoriteStation>? onSetOrigin;
  final ValueChanged<FavoriteStation>? onSetDestination;
  final ValueChanged<FavoriteStation> onRemove;

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
        padding: _stationSearchPagePadding,
        children: [
          Semantics(
            label: '즐겨찾기 역 ${state.favorites.length}개',
            liveRegion: true,
            child: const SizedBox.shrink(),
          ),
          for (final favorite in state.favorites)
            _FavoriteStationTile(
              favorite: favorite,
              isRemoving: state.removingIds.contains(favorite.stationId),
              onOpenDetail: () => onFavoriteTap(favorite),
              onOpenFacilityStatus: () => onFacilityStatusTap(favorite),
              onSetOrigin: onSetOrigin == null
                  ? null
                  : () => onSetOrigin!(favorite),
              onSetDestination: onSetDestination == null
                  ? null
                  : () => onSetDestination!(favorite),
              onRemove: () => onRemove(favorite),
            ),
        ],
      ),
    };
  }
}

class _FavoriteStationTile extends StatelessWidget {
  const _FavoriteStationTile({
    required this.favorite,
    required this.isRemoving,
    required this.onOpenDetail,
    required this.onOpenFacilityStatus,
    required this.onSetOrigin,
    required this.onSetDestination,
    required this.onRemove,
  });

  final FavoriteStation favorite;
  final bool isRemoving;
  final VoidCallback onOpenDetail;
  final VoidCallback onOpenFacilityStatus;
  final VoidCallback? onSetOrigin;
  final VoidCallback? onSetDestination;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: _stationCompactCardRadius,
        side: const BorderSide(color: EasySubwayAccessibleColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MergeSemantics(
              child: Semantics(
                label: favorite.semanticLabel,
                button: true,
                onTap: onOpenDetail,
                child: ExcludeSemantics(
                  child: InkWell(
                    key: Key('favoriteStationTile-${favorite.stationId}'),
                    borderRadius: _stationCompactCardRadius,
                    onTap: onOpenDetail,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            favorite.nameKo,
                            style: textTheme.titleLarge?.copyWith(
                              color: EasySubwayAccessibleColors.text,
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
                              color: EasySubwayAccessibleColors.secondaryText,
                              fontWeight: FontWeight.w800,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            favorite.region,
                            style: textTheme.bodyMedium?.copyWith(
                              color: _stationTextMutedColor,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            favorite.dataQualityLabel,
                            style: textTheme.bodyMedium?.copyWith(
                              color: _stationTextMutedColor,
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onSetOrigin != null)
                  OutlinedButton.icon(
                    onPressed: onSetOrigin,
                    icon: const Icon(Icons.trip_origin),
                    label: const Text('출발지로 설정'),
                  ),
                if (onSetDestination != null)
                  OutlinedButton.icon(
                    onPressed: onSetDestination,
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('도착지로 설정'),
                  ),
                OutlinedButton.icon(
                  onPressed: onOpenDetail,
                  icon: const Icon(Icons.info_outline),
                  label: const Text('역 상세 보기'),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenFacilityStatus,
                  icon: const Icon(Icons.elevator_outlined),
                  label: const Text('시설 상태 확인'),
                ),
                OutlinedButton.icon(
                  onPressed: isRemoving ? null : onRemove,
                  icon: isRemoving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bookmark_remove_outlined),
                  label: Text(isRemoving ? '해제 중' : '즐겨찾기 해제'),
                ),
              ],
            ),
          ],
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
    this.realtimeRepository,
    this.locationProvider,
    this.initiallyFavorite,
    this.facilityReportDraftTargetStore,
    this.internalRouteRepository,
    this.internalRouteRequest,
    this.internalRouteMobilityType = 'SENIOR',
    this.routeDraftController,
    super.key,
  });

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final FavoriteStationRepository? favoriteRepository;
  final RealtimeRepository? realtimeRepository;
  final CurrentLocationProvider? locationProvider;
  final String stationId;
  final bool? initiallyFavorite;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final InternalRouteRepository? internalRouteRepository;
  final InternalRouteRequest? internalRouteRequest;
  final String internalRouteMobilityType;
  final RouteDraftController? routeDraftController;

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
    _controller = StationDetailController(
      repository: widget.repository,
      realtimeRepository: widget.realtimeRepository,
    );
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
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('역 상세'),
            Text(
              ProductionScopeCopy.supportedClaimKo,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      body: Semantics(
        container: true,
        label: ProductionScopeCopy.stationSearchNotice,
        child: SafeArea(
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _controller,
              ?_internalRouteController,
            ]),
            builder: (context, _) {
              return _StationDetailBody(
                state: _controller.state,
                internalRouteState: _internalRouteController?.state,
                reportRepository: widget.reportRepository,
                favoriteController: _favoriteController,
                routeDraftController: widget.routeDraftController,
                locationProvider: widget.locationProvider,
                facilityReportDraftTargetStore:
                    widget.facilityReportDraftTargetStore,
              );
            },
          ),
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
    required this.routeDraftController,
    required this.locationProvider,
    required this.facilityReportDraftTargetStore,
  });

  final StationDetailState state;
  final InternalRouteState? internalRouteState;
  final FacilityReportRepository reportRepository;
  final StationFavoriteToggleController? favoriteController;
  final RouteDraftController? routeDraftController;
  final CurrentLocationProvider? locationProvider;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;

  @override
  Widget build(BuildContext context) {
    return switch (state.status) {
      StationDetailStatus.loading => Semantics(
        label: '역 안내 불러오는 중',
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
        realtimeSnapshot: state.realtimeSnapshot,
        internalRouteState: internalRouteState,
        reportRepository: reportRepository,
        favoriteController: favoriteController,
        routeDraftController: routeDraftController,
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
    required this.realtimeSnapshot,
    required this.internalRouteState,
    required this.reportRepository,
    required this.favoriteController,
    required this.routeDraftController,
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
  final RealtimeSnapshot realtimeSnapshot;
  final InternalRouteState? internalRouteState;
  final FacilityReportRepository reportRepository;
  final StationFavoriteToggleController? favoriteController;
  final RouteDraftController? routeDraftController;
  final CurrentLocationProvider? locationProvider;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;

  @override
  Widget build(BuildContext context) {
    final mapMarkers = const EasySubwayMapAdapter().markersForStationDetail(
      station: detail,
      exits: exits,
      facilities: facilities,
    );

    final primaryChildren = <Widget>[
      _StationDetailHeader(detail: detail),
      const SizedBox(height: 12),
      _InfoBasisDisclosure(
        labels: [detail.dataSourceLabel, '마지막 확인 ${detail.lastVerifiedAt}'],
      ),
      const SizedBox(height: 12),
      if (facilityAttentionSummary.isNotEmpty) ...[
        _StationFacilityStatusSummary(
          text: facilityAttentionSummary,
          semanticLabel: facilityAttentionSemanticLabel,
        ),
        const SizedBox(height: 12),
      ],
      _StationDetailRouteActions(
        detail: detail,
        routeDraftController: routeDraftController,
      ),
      const SizedBox(height: 12),
      const _StationSafetyGuidanceNotice(),
      if (favoriteController != null) ...[
        const SizedBox(height: 16),
        _StationFavoriteControl(
          detail: detail,
          controller: favoriteController!,
        ),
      ],
    ];
    final detailChildren = <Widget>[
      if (layoutSummaryItems.isNotEmpty) ...[
        const _StationDetailSectionTitle(title: '역 안 이동 안내'),
        const SizedBox(height: 12),
        _StationLayoutSummary(
          items: layoutSummaryItems,
          semanticLabel: layoutSummarySemanticLabel,
        ),
        const SizedBox(height: 24),
      ],
      if (internalRouteState != null) ...[
        const _StationDetailSectionTitle(title: '역 안 이동 순서'),
        const SizedBox(height: 12),
        _StationInternalRouteGuidance(state: internalRouteState!),
        const SizedBox(height: 24),
      ],
      if (mapMarkers.isNotEmpty) ...[
        const _StationDetailSectionTitle(title: '지도 위치 목록'),
        const SizedBox(height: 12),
        _StationMapTextList(markers: mapMarkers),
        const SizedBox(height: 24),
      ],
      const _StationDetailSectionTitle(title: '출구'),
      const SizedBox(height: 12),
      if (exits.isEmpty)
        const _StationDetailEmptyMessage(message: '출구 안내를 준비 중이에요.')
      else
        for (final exit in exits) _StationExitCard(exit: exit),
      const SizedBox(height: 24),
      const _StationDetailSectionTitle(title: '시설'),
      const SizedBox(height: 12),
      if (facilities.isEmpty)
        const _StationDetailEmptyMessage(message: '시설 안내를 준비 중이에요.')
      else
        for (final facility in facilities)
          _StationFacilityCard(
            facility: facility,
            station: detail,
            onReportTap: () => _openFacilityReport(context, facility),
          ),
      const SizedBox(height: 24),
      const _StationDetailSectionTitle(title: '실시간 열차'),
      const SizedBox(height: 12),
      _StationRealtimeSummary(snapshot: realtimeSnapshot),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLargeScreen = EasySubwayAdaptiveLayout.isLargeScreen(
          constraints,
          textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
        );
        return ListView(
          key: const Key('stationDetailList'),
          padding: isLargeScreen
              ? _stationSearchLargePagePadding
              : _stationSearchPagePadding,
          children: isLargeScreen
              ? [
                  _StationDetailAdaptiveContent(
                    primaryChildren: primaryChildren,
                    detailChildren: detailChildren,
                  ),
                ]
              : [
                  ...primaryChildren,
                  const SizedBox(height: 24),
                  ...detailChildren,
                ],
        );
      },
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

class _StationDetailAdaptiveContent extends StatelessWidget {
  const _StationDetailAdaptiveContent({
    required this.primaryChildren,
    required this.detailChildren,
  });

  final List<Widget> primaryChildren;
  final List<Widget> detailChildren;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: EasySubwayAdaptiveLayout.largeScreenMaxContentWidth,
        ),
        child: Row(
          key: const Key('stationDetailLargeScreenLayout'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Column(
                key: const Key('stationDetailPrimaryColumn'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: primaryChildren,
              ),
            ),
            const SizedBox(
              width: EasySubwayAdaptiveLayout.largeScreenColumnGap,
            ),
            Expanded(
              flex: 5,
              child: Column(
                key: const Key('stationDetailDetailColumn'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: detailChildren,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationMapTextList extends StatelessWidget {
  const _StationMapTextList({required this.markers});

  final List<MapMarker> markers;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          label: '지도 위치 목록',
          child: const SizedBox.shrink(),
        ),
        for (final marker in markers) _StationMapTextListItem(marker: marker),
      ],
    );
  }
}

class _StationRealtimeSummary extends StatelessWidget {
  const _StationRealtimeSummary({required this.snapshot});

  final RealtimeSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final title = switch (snapshot.status) {
      RealtimeSnapshotStatus.fresh => '도착 정보',
      RealtimeSnapshotStatus.stale => '최근 도착 정보',
      RealtimeSnapshotStatus.unsupported => '지원 준비 중',
      RealtimeSnapshotStatus.unavailable => '실시간 정보 확인 불가',
      RealtimeSnapshotStatus.loading => '실시간 정보 확인 중',
    };
    final summary = snapshot.summaryText.trim().isEmpty
        ? '역 정보와 경로 검색은 계속 이용할 수 있습니다.'
        : snapshot.summaryText.trim();
    final updatedLabel = snapshot.receivedAt.trim().isEmpty
        ? ''
        : '마지막 갱신 ${snapshot.receivedAt}';
    final semanticParts = [
      '실시간 열차',
      title,
      summary,
      if (updatedLabel.isNotEmpty) updatedLabel,
      '열차 위치는 GPS가 아니라 열차 운행 안내를 바탕으로 보여줘요.',
    ];
    return Semantics(
      label: semanticParts.join(', '),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: _stationDetailInfoCardRadius,
          border: Border.all(color: EasySubwayAccessibleColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.schedule,
                  color: EasySubwayAccessibleColors.primary,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: EasySubwayAccessibleColors.text,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              summary,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: EasySubwayAccessibleColors.text,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (updatedLabel.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                updatedLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: EasySubwayAccessibleColors.mutedText,
                  height: 1.3,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '열차 위치는 GPS가 아니라 열차 운행 안내를 바탕으로 보여줘요.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: EasySubwayAccessibleColors.mutedText,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationDetailRouteActions extends StatelessWidget {
  const _StationDetailRouteActions({
    required this.detail,
    required this.routeDraftController,
  });

  final StationDetail detail;
  final RouteDraftController? routeDraftController;

  @override
  Widget build(BuildContext context) {
    final controller = routeDraftController;
    if (controller == null) {
      return const SizedBox.shrink();
    }
    final station = RouteDraftStation(id: detail.id, nameKo: detail.nameKo);
    return Row(
      children: [
        Expanded(
          child: _StationPointButton(
            key: const Key('stationDetailSetOriginButton'),
            symbol: '출',
            label: '출발로 설정',
            selectedColor: EasySubwayAccessibleColors.mint,
            onPressed: () {
              controller.setOrigin(station);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${station.displayName}을 출발역으로 설정했습니다')),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StationPointButton(
            key: const Key('stationDetailSetDestinationButton'),
            symbol: '도',
            label: '도착으로 설정',
            selectedColor: EasySubwayAccessibleColors.brand,
            onPressed: () {
              controller.setDestination(station);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${station.displayName}을 도착역으로 설정했습니다')),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StationPointButton extends StatelessWidget {
  const _StationPointButton({
    required this.symbol,
    required this.label,
    required this.selectedColor,
    required this.onPressed,
    super.key,
  });

  final String symbol;
  final String label;
  final Color selectedColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(62),
        backgroundColor: Colors.white,
        foregroundColor: EasySubwayAccessibleColors.text,
        side: const BorderSide(color: EasySubwayAccessibleColors.line),
        shape: const RoundedRectangleBorder(
          borderRadius: _stationDetailActionButtonRadius,
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      icon: CircleAvatar(
        radius: 16,
        backgroundColor: selectedColor,
        child: Text(
          symbol,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      label: Text(label),
    );
  }
}

class _StationMapTextListItem extends StatelessWidget {
  const _StationMapTextListItem({required this.marker});

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
                color: EasySubwayAccessibleColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  marker.title,
                  key: Key('stationMapTextListItem-${marker.id}'),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: EasySubwayAccessibleColors.text,
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
        color: _stationDetailSoftPanelColor,
        borderRadius: _stationDetailInfoCardRadius,
        border: Border.all(color: _stationDetailSoftPanelBorderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, color: EasySubwayAccessibleColors.primary, size: 26),
          const SizedBox(height: 8),
          Text(
            item.text,
            textAlign: TextAlign.center,
            style: textTheme.bodyLarge?.copyWith(
              color: EasySubwayAccessibleColors.text,
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
        child: Card(
          margin: EdgeInsets.zero,
          color: EasySubwayAccessibleColors.redSoft,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: _stationDetailFacilityCardRadius,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber,
                  color: EasySubwayAccessibleColors.red,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: EasySubwayAccessibleColors.red,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
        child: Card(
          margin: EdgeInsets.zero,
          color: EasySubwayAccessibleColors.brandDark,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: _stationDetailHeroCardRadius,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StationLineBadges(lines: detail.lines, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${detail.nameKo}역',
                        style: textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        detail.lineLabel,
                        style: textTheme.bodyLarge?.copyWith(
                          color: _stationFacilityDividerColor,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        detail.dataQualityLabel,
                        style: textTheme.bodyMedium?.copyWith(
                          color: _stationFacilityDividerColor,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '마지막 확인 ${detail.lastVerifiedAt}',
                        style: textTheme.bodyMedium?.copyWith(
                          color: _stationFacilityDividerColor,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
                    color: EasySubwayAccessibleColors.text,
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
        label: '역 안 이동 순서 불러오는 중',
        liveRegion: true,
        child: const _StationDetailInfoRow(
          icon: Icons.sync,
          text: '역 안 이동 순서를 불러오는 중입니다.',
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
            color: _stationDetailMintPanelColor,
            borderRadius: _stationDetailInfoCardRadius,
            border: Border.all(color: _stationDetailMintPanelBorderColor),
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
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                result.totalBurdenLabel,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: _stationDetailTextColor,
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
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                step.burdenLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _stationDetailTextColor,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                step.guidance,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: EasySubwayAccessibleColors.text,
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
        Icon(icon, size: 22, color: EasySubwayAccessibleColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: EasySubwayAccessibleColors.secondaryText,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoBasisDisclosure extends StatefulWidget {
  const _InfoBasisDisclosure({required this.labels});

  final List<String> labels;

  @override
  State<_InfoBasisDisclosure> createState() => _InfoBasisDisclosureState();
}

class _InfoBasisDisclosureState extends State<_InfoBasisDisclosure> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels
        .where((label) => label.trim().isNotEmpty)
        .toList(growable: false);
    if (labels.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: () => setState(() => _expanded = !_expanded),
          icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
          label: Text(_expanded ? '안내 확인 방법 접기' : '안내 확인 방법 보기'),
        ),
        if (_expanded) ...[
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: _stationDetailHelpCardRadius,
              side: BorderSide(color: EasySubwayAccessibleColors.line),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '안내 확인 방법',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: EasySubwayAccessibleColors.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final label in labels) ...[
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: EasySubwayAccessibleColors.mutedText,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    if (label != labels.last) const SizedBox(height: 4),
                  ],
                ],
              ),
            ),
          ),
        ],
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
          color: EasySubwayAccessibleColors.text,
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
        color: _stationTextMutedColor,
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
            shape: const RoundedRectangleBorder(
              borderRadius: _stationDetailInfoCardRadius,
              side: BorderSide(color: EasySubwayAccessibleColors.line),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exit.name,
                    style: textTheme.titleMedium?.copyWith(
                      color: EasySubwayAccessibleColors.text,
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
                    exit.verificationStatusLabel,
                    style: textTheme.bodyMedium?.copyWith(
                      color: _stationTextMutedColor,
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
    required this.station,
    required this.onReportTap,
  });

  final StationFacilityInfo facility;
  final StationDetail station;
  final VoidCallback onReportTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: facility.semanticLabel,
      button: true,
      onTap: () => _openFacilityDetail(context),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        color: Colors.white,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: _stationDetailFacilityCardRadius,
          side: BorderSide(color: EasySubwayAccessibleColors.line),
        ),
        child: InkWell(
          key: Key('stationFacilityCard-${facility.id}'),
          borderRadius: _stationDetailFacilityCardRadius,
          onTap: () => _openFacilityDetail(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  facility.name,
                  style: textTheme.titleMedium?.copyWith(
                    color: EasySubwayAccessibleColors.text,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StationDetailTextPill(text: facility.typeLabel),
                    _StationDetailTextPill(text: facility.statusTitle),
                    if (facility.severityLabel != facility.statusTitle)
                      _StationDetailTextPill(text: facility.severityLabel),
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
                  facility.verificationStatusLabel,
                  style: textTheme.bodyMedium?.copyWith(
                    color: _stationTextMutedColor,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        container: true,
                        label: '${facility.name} 시설 알려주기',
                        button: true,
                        onTap: onReportTap,
                        child: ExcludeSemantics(
                          child: OutlinedButton.icon(
                            key: Key('facilityReportButton-${facility.id}'),
                            onPressed: onReportTap,
                            icon: const Icon(Icons.report_outlined),
                            label: const Text('시설 알려주기'),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '상세 보기',
                      style: textTheme.bodyLarge?.copyWith(
                        color: EasySubwayAccessibleColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openFacilityDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FacilityDetailScreen(
          station: station,
          facility: facility,
          onReportTap: onReportTap,
        ),
      ),
    );
  }
}

class FacilityDetailScreen extends StatelessWidget {
  const FacilityDetailScreen({
    required this.station,
    required this.facility,
    required this.onReportTap,
    super.key,
  });

  final StationDetail station;
  final StationFacilityInfo facility;
  final VoidCallback onReportTap;

  @override
  Widget build(BuildContext context) {
    final statusBackgroundColor = _facilityStatusNoticeBackgroundColor(
      facility.statusPresentation.severity,
    );
    final statusIconColor = _facilityStatusNoticeIconColor(
      facility.statusPresentation.severity,
    );
    final statusIcon = _facilityStatusNoticeIcon(
      facility.statusPresentation.severity,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('시설 상세')),
      body: SafeArea(
        child: ListView(
          padding: _stationSearchPagePadding,
          children: [
            Card(
              margin: EdgeInsets.zero,
              color: EasySubwayAccessibleColors.brandDark,
              elevation: 0,
              shape: const RoundedRectangleBorder(
                borderRadius: _stationDetailHeroCardRadius,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 27,
                      backgroundColor: EasySubwayAccessibleColors.mintSoft,
                      child: Icon(
                        facility.layoutSummaryIcon,
                        color: EasySubwayAccessibleColors.mint,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${station.nameKo}역',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: _stationDetailHeroSecondaryColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            facility.name,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              key: Key('facilityDetailStatusNotice-${facility.id}'),
              margin: EdgeInsets.zero,
              color: statusBackgroundColor,
              elevation: 0,
              shape: const RoundedRectangleBorder(
                borderRadius: _stationDetailFacilityCardRadius,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(statusIcon, color: statusIconColor, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _facilityStatusTitle(facility),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: statusIconColor,
                                  fontWeight: FontWeight.w800,
                                  height: 1.25,
                                ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            facilityStatusDisplayLabel(
                              statusLabel: facility.statusLabel,
                              severityLabel: facility.severityLabel,
                            ),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: EasySubwayAccessibleColors.mutedText,
                                  fontWeight: FontWeight.w700,
                                  height: 1.3,
                                ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _facilityDetailStatusDescription(facility),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: EasySubwayAccessibleColors.mutedText,
                                  fontWeight: FontWeight.w700,
                                  height: 1.3,
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
            const _StationDetailSectionTitle(title: '위치'),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              color: Colors.white,
              elevation: 0,
              shape: const RoundedRectangleBorder(
                borderRadius: _stationDetailFacilityCardRadius,
                side: BorderSide(color: EasySubwayAccessibleColors.line),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _StationDetailInfoRow(
                      icon: Icons.stairs_outlined,
                      text: _facilityFloorLabel(facility),
                    ),
                    const SizedBox(height: 10),
                    _StationDetailInfoRow(
                      icon: Icons.place_outlined,
                      text: facility.locationLabel,
                    ),
                    const SizedBox(height: 10),
                    _StationDetailInfoRow(
                      icon: Icons.event_available,
                      text: facility.updatedLabel,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _InfoBasisDisclosure(
              labels: [
                facility.fieldValidationLabel,
                facility.confidenceLabel,
                facility.dataSourceLabel,
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: Key('facilityDetailReportButton-${facility.id}'),
              onPressed: () {
                Navigator.of(context).pop();
                onReportTap();
              },
              icon: const Icon(Icons.report_outlined),
              label: const Text('시설 알려주기'),
            ),
          ],
        ),
      ),
    );
  }
}

String _facilityFloorLabel(StationFacilityInfo facility) {
  final from = facility.floorFrom.trim();
  final to = facility.floorTo.trim();
  if (from.isEmpty && to.isEmpty) {
    return '연결 위치를 아직 알 수 없어요';
  }
  if (from.isEmpty || to.isEmpty) {
    return '연결 위치 ${from.isEmpty ? to : from}';
  }
  return '연결 위치 $from ↔ $to';
}

String _facilityDetailStatusDescription(StationFacilityInfo facility) {
  if (facility.needsAttention) {
    return '현장 안내와 다르면 시설 알려주기로 알려 주세요.';
  }
  return '시설 안내가 다르면 시설 알려주기로 알려 주세요.';
}

String _facilityStatusTitle(StationFacilityInfo facility) {
  return facility.statusTitle;
}

Color _facilityStatusNoticeBackgroundColor(FacilityStatusSeverity severity) {
  return switch (severity) {
    FacilityStatusSeverity.blocked => EasySubwayAccessibleColors.redSoft,
    FacilityStatusSeverity.caution => EasySubwayAccessibleColors.amberSoft,
    FacilityStatusSeverity.needsInfo => EasySubwayAccessibleColors.skySoft,
    FacilityStatusSeverity.normal => EasySubwayAccessibleColors.mintSoft,
  };
}

Color _facilityStatusNoticeIconColor(FacilityStatusSeverity severity) {
  return switch (severity) {
    FacilityStatusSeverity.blocked => EasySubwayAccessibleColors.red,
    FacilityStatusSeverity.caution => EasySubwayAccessibleColors.amber,
    FacilityStatusSeverity.needsInfo => EasySubwayAccessibleColors.brand,
    FacilityStatusSeverity.normal => EasySubwayAccessibleColors.mint,
  };
}

IconData _facilityStatusNoticeIcon(FacilityStatusSeverity severity) {
  return switch (severity) {
    FacilityStatusSeverity.blocked => Icons.warning_amber,
    FacilityStatusSeverity.caution => Icons.report_problem_outlined,
    FacilityStatusSeverity.needsInfo => Icons.info_outline,
    FacilityStatusSeverity.normal => Icons.check_circle,
  };
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
    final color = positive
        ? EasySubwayAccessibleColors.primary
        : _stationDetailCautionColor;

    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: EasySubwayAccessibleColors.text,
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
    return Container(
      decoration: BoxDecoration(
        color: _stationDetailNoticeColor,
        borderRadius: _stationDetailInfoCardRadius,
        border: Border.all(color: _stationDetailNoticeBorderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: EasySubwayAccessibleColors.text,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
      ),
    );
  }
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
  Uri? developmentBaseUri;
  assert(() {
    developmentBaseUri = Uri.parse(
      isAndroid ? 'http://10.0.2.2:8080' : 'http://127.0.0.1:8080',
    );
    return true;
  }());
  if (developmentBaseUri == null) {
    throw StateError('Development API base URL is only available in debug.');
  }
  return developmentBaseUri!;
}
