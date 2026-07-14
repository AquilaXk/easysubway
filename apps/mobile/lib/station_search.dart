import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'accessible_design.dart';
import 'adaptive_layout.dart';
import 'core/external/kakao_map_launcher.dart';
import 'design_tokens.dart';
import 'facility_status.dart';
import 'facility_report.dart';
import 'features/ads/active_ad_banner.dart';
import 'features/ads/ad_repository.dart';
import 'features/route_draft/application/route_draft_controller.dart';
import 'features/route_draft/domain/route_draft.dart';
import 'features/realtime/realtime_repository.dart';
import 'features/stations/domain/station_line.dart';
import 'features/stations/presentation/station_line_badges.dart';
import 'internal_route.dart';
import 'mobile_error_reporter.dart';
import 'search_field.dart';

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
const _stationSearchFailureNextAction =
    '역명으로 검색하면 현재 위치를 쓰지 않아도 계속 이용할 수 있습니다.';
const _favoriteStationStatusErrorMessage = '즐겨찾기를 확인하지 못했어요.';
const _favoriteStationChangeErrorMessage = '즐겨찾기를 바꾸지 못했어요.';
const _searchHistoryChangeErrorMessage = '최근 검색을 지우지 못했어요.';
const _stationSearchPagePadding = EdgeInsets.fromLTRB(20, 20, 20, 32);
const _stationSearchLargePagePadding = EdgeInsets.fromLTRB(24, 24, 24, 40);
const _stationRoleActionPadding = EdgeInsets.fromLTRB(12, 0, 12, 12);
const _stationDetailInfoCardRadius = BorderRadius.all(Radius.circular(16));
const _stationDetailHelpCardRadius = BorderRadius.all(Radius.circular(16));
const _stationDetailActionButtonRadius = BorderRadius.all(Radius.circular(12));
const _stationDetailFacilityCardRadius = BorderRadius.all(Radius.circular(16));

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

enum StationTimetableDayType {
  weekday('평일'),
  saturday('토요일'),
  sundayHoliday('일요일·공휴일');

  const StationTimetableDayType(this.label);

  final String label;
}

abstract class StationTimetableRepository {
  Future<StationTimetable> loadStationTimetable({
    required String stationId,
    required String lineId,
    required StationTimetableDayType dayType,
    required DateTime referenceDate,
  });

  Future<StationTimetable> loadStationTimetableForDate({
    required String stationId,
    required String lineId,
    required DateTime date,
  });
}

class StationTimetable {
  const StationTimetable({
    required this.stationId,
    required this.lineId,
    required this.dayType,
    required this.directions,
  });

  final String stationId;
  final String lineId;
  final StationTimetableDayType dayType;
  final List<StationTimetableDirection> directions;

  bool get isAvailable => directions.isNotEmpty;
}

class StationTimetableDirection {
  const StationTimetableDirection({
    required this.name,
    required this.departures,
  });

  final String name;
  final List<StationTimetableDeparture> departures;

  StationTimetableDeparture get firstDeparture => departures.first;

  StationTimetableDeparture get lastDeparture => departures.last;
}

class StationTimetableDeparture {
  const StationTimetableDeparture({
    required this.directionName,
    required this.seconds,
  });

  final String directionName;
  final int seconds;

  String get timeLabel {
    final prefix = seconds >= Duration.secondsPerDay ? '다음 날 ' : '';
    return '$prefix${_clockLabel(seconds)}';
  }

  String get semanticLabel {
    final normalized = seconds % Duration.secondsPerDay;
    final hour = normalized ~/ Duration.secondsPerHour;
    final minute =
        (normalized % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
    final prefix = seconds >= Duration.secondsPerDay ? '다음 날 ' : '';
    return '$directionName, $prefix${hour.toString().padLeft(2, '0')}시 '
        '${minute.toString().padLeft(2, '0')}분 출발';
  }
}

String _clockLabel(int seconds) {
  final normalized = seconds % Duration.secondsPerDay;
  final hour = normalized ~/ Duration.secondsPerHour;
  final minute =
      (normalized % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
  return '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}';
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
      return '노선을 확인하고 있어요';
    }
    return lines.map((line) => line.name).join(', ');
  }

  String get semanticLabel {
    return '즐겨찾기 역, $nameKo, $lineLabel, $region';
  }
}

class StationSearchResult {
  const StationSearchResult({
    required this.id,
    required this.nameKo,
    required this.nameEn,
    this.nameSub = '',
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
      nameSub: _stringOrEmpty(json, 'nameSub'),
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
  final String nameSub;
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
      return '노선을 확인하고 있어요';
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
      return '$nameKo, $lineLabel, $region';
    }
    return '$nameKo, $distance, $lineLabel, $region';
  }
}

class StationDetail {
  const StationDetail({
    required this.id,
    required this.nameKo,
    required this.nameEn,
    this.nameSub = '',
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
      nameSub: _stringOrEmpty(json, 'nameSub'),
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
  final String nameSub;
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
      return '노선을 확인하고 있어요';
    }
    return lines.map((line) => line.name).join(', ');
  }

  String get semanticLabel {
    return '$nameKo역 자세한 안내, $lineLabel, '
        '마지막 확인 ${stationVerifiedRelativeLabel(lastVerifiedAt)}';
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
    this.lastVerifiedAt = '',
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
      lastVerifiedAt: _stringOrEmpty(json, 'lastVerifiedAt'),
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
  final String lastVerifiedAt;

  bool get hasCoordinate => latitude != null && longitude != null;

  String get elevatorConnectionLabel {
    return hasElevatorConnection ? '엘리베이터 연결' : '엘리베이터 연결을 확인하고 있어요';
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
    final parts = <String>[name, elevatorConnectionLabel, stairPathLabel];
    final verifiedAt = lastVerifiedAt.trim();
    if (verifiedAt.isNotEmpty) {
      parts.add('최근 확인 ${stationVerifiedRelativeLabel(verifiedAt)}');
    }
    return parts.join(', ');
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

  String get updatedLabel =>
      '최근 확인 ${stationVerifiedRelativeLabel(lastUpdatedAt)}';

  String get semanticLabel {
    return '$name, $typeLabel, $statusTitle, $locationLabel, $updatedLabel, $nextActionLabel';
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

  /// 지역 접두어를 뗀 짧은 노선명(지역이 이미 상단에 표시될 때 사용).
  String get shortName {
    final prefix = '$region ';
    if (region.isNotEmpty && name.startsWith(prefix)) {
      final stripped = name.substring(prefix.length).trim();
      if (stripped.isNotEmpty) {
        return stripped;
      }
    }
    return name;
  }

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

// #1578 전역 원칙: 내부 데이터 품질·검증 상태 라벨은 사용자에게 노출하지 않는다.
// 소스(라벨 함수)를 중립화해 모든 화면이 이를 상속한다. 화면 구조 정리(빈
// 위젯·조건 제거)는 #1566/#1567/#1569에서 다룬다. 정상·확인됨·준비 중은 무표시,
// 시점 정보는 별도의 "최근 확인 …" 표현으로만 제공한다.
String _dataQualityLabel(String dataQualityLevel) => '';

String _dataConfidenceLabel(String dataConfidence) => '';

String _fieldValidationLabel(String fieldValidationStatus) => '';

String _fieldVerificationStatusLabel(String fieldValidationStatus) => '';

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

/// 확인 시점 상대 표현의 기준 시각. 테스트에서 고정할 수 있게 주입 지점을 둔다.
@visibleForTesting
DateTime Function() debugStationVerifiedClock = DateTime.now;

/// 확인 시점('YYYY-MM-DD' 또는 ISO datetime)을 오늘 기준 상대 표현으로 바꾼다.
/// '오늘 / 어제 / n일 전 / n주 전'으로 최신성을 한눈에 보여주고, 파싱 불가·미래·
/// 4주 이상 과거는 원문 날짜를 그대로 둬 오래된 안내는 정확한 날짜로 드러낸다.
String stationVerifiedRelativeLabel(String rawVerifiedAt) {
  final raw = rawVerifiedAt.trim();
  if (raw.isEmpty) {
    return raw;
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }
  final now = debugStationVerifiedClock();
  final today = DateTime(now.year, now.month, now.day);
  final verifiedDay = DateTime(parsed.year, parsed.month, parsed.day);
  final days = today.difference(verifiedDay).inDays;
  if (days < 0) {
    return raw;
  }
  if (days == 0) {
    return '오늘';
  }
  if (days == 1) {
    return '어제';
  }
  if (days < 7) {
    return '$days일 전';
  }
  if (days < 28) {
    return '${days ~/ 7}주 전';
  }
  return raw;
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

  Future<void> search(
    String query, {
    String? lineId,
    bool recordHistory = true,
  }) async {
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
      // 디바운스 타이핑 검색은 최근 검색에 기록하지 않는다(부분 입력 기록 방지).
      // 키보드 검색·최근 검색 선택 등 명시적 검색만 기록한다.
      if (recordHistory) {
        await _recordSearch(trimmedQuery);
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

  // 실시간 조회가 실패로 끝났을 때 사용자가 직접 다시 시도할 수 있게 한다.
  // 현재 역 상세를 유지한 채 실시간만 로딩 상태로 되돌린 뒤 재조회한다.
  Future<void> retryRealtime() async {
    final detail = _state.detail;
    if (_isDisposed || detail == null) {
      return;
    }
    _state = StationDetailState(
      status: _state.status,
      detail: detail,
      exits: _state.exits,
      facilities: _state.facilities,
      realtimeSnapshot: const RealtimeSnapshot.loading(),
      message: _state.message,
    );
    notifyListeners();
    await _refreshRealtimeSnapshot(detail);
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
    this.adRepository,
    this.searchHistoryRepository,
    this.realtimeRepository,
    this.facilityReportDraftTargetStore,
    this.internalRouteRepository,
    this.internalRouteMobilityType = 'SENIOR',
    this.routeDraftController,
    this.entryMode = StationSearchEntryMode.search,
    this.pickSlot,
    required this.regionLabel,
    this.bottomNavigationBar,
    super.key,
  });

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final CurrentLocationProvider locationProvider;
  final FavoriteStationRepository? favoriteRepository;
  final AdRepository? adRepository;
  final SearchHistoryRepository? searchHistoryRepository;
  final RealtimeRepository? realtimeRepository;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final InternalRouteRepository? internalRouteRepository;
  final String internalRouteMobilityType;
  final RouteDraftController? routeDraftController;
  final StationSearchEntryMode entryMode;

  /// 특정 칸(출발/도착)을 채우려고 검색을 연 경우의 대상 칸. 지정되면 결과를 한 번
  /// 탭하는 즉시 [routeDraftController]의 해당 칸을 설정하고 이 화면을 닫는다. 지도
  /// 탭 경로와 완전히 같은 draft 상태로 수렴시키기 위한 "칸 채우기" 모드다. null이면
  /// 기존 둘러보기(출발/도착 버튼이 각 결과에 딸린 형태) 그대로 동작한다.
  final RouteDraftSlot? pickSlot;

  /// #2082: 검색 화면 상단 필드 우측에 표시하는 현재 지역명. 홈 idle 상단바
  /// [≡ | 검색필드 | 지역표시] 구성과 정합하기 위해, 검색 화면(← + 필드)에도
  /// 같은 위치·스타일의 지역 표시를 둔다. 검색 맥락에서는 지역 변경 UI를 새로
  /// 만들지 않고 표시 전용으로 둔다(오너 지시: "변경은 못해도 알려는 줘야"). 호출부가
  /// 홈이 들고 있는 실제 선택 지역 표시명을 반드시 넘겨야 한다(#2090 배선 누락 수정).
  final String regionLabel;
  final Widget? bottomNavigationBar;

  @override
  State<StationSearchScreen> createState() => _StationSearchScreenState();
}

enum StationSearchEntryMode { search, nearby }

class _StationSearchScreenState extends State<StationSearchScreen> {
  late final StationSearchController _controller;
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<String> _recentQueries = const [];
  Timer? _searchDebounce;
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
    unawaited(_loadRecentQueries());
    if (widget.entryMode == StationSearchEntryMode.nearby) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_searchNearby());
        }
      });
    }
    // 검색 진입은 화면을 여는 즉시 입력 모드로 들어간다(별도 타이틀 화면 없이 바로
    // 키보드가 뜬다). 이 즉시 포커스는 검색 필드의 autofocus: !isNearbyEntry 가
    // 담당하므로 여기서 별도 requestFocus 는 두지 않는다. 가까운 역 진입은 위치
    // 조회를 먼저 하고 autofocus 도 꺼져 포커스를 가로채지 않는다.
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleControllerChanged)
      ..dispose();
    _queryController.removeListener(_handleQueryChanged);
    _queryController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
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
    _searchDebounce?.cancel();
    if (!_hasSearchQuery) {
      if (!_isNearbySearchRunning &&
          _controller.state.status != StationSearchStatus.idle) {
        _controller.search('');
      }
    } else {
      // 타이핑 즉시(디바운스) 검색으로 통일한다. 부분 입력은 최근 검색에 기록하지 않는다.
      final query = _queryController.text;
      _searchDebounce = Timer(
        const Duration(milliseconds: 300),
        () => unawaited(_runSearch(query, recordHistory: false)),
      );
    }
    setState(() {});
  }

  bool get _hasSearchQuery => _queryController.text.trim().isNotEmpty;

  /// pickSlot·entryMode 조합에 따른 입력 힌트. 큰 타이틀 화면을 없앤 대신, 입력
  /// 필드 자체의 힌트/시맨틱에 "무엇을 고르는 중인지"를 인코딩해 TalkBack이 출발/
  /// 도착/일반 검색 의도를 그대로 전달하게 한다.
  String get _searchInputHint => switch (widget.pickSlot) {
    // #2083 오너 확정: 슬롯 검색 진입 placeholder는 슬롯명 단독.
    RouteDraftSlot.origin => '출발역',
    RouteDraftSlot.destination => '도착역',
    RouteDraftSlot.waypoint => '경유역',
    null => '역 이름을 입력해 주세요',
  };

  @override
  Widget build(BuildContext context) {
    final isNearbyEntry = widget.entryMode == StationSearchEntryMode.nearby;
    final showNearbyRetryButton = isNearbyEntry && !_hasSearchQuery;
    // #2083 홈 편집 모드와 동일한 공용 검색 필드를 쓴다. pickSlot별 힌트는
    // hintText로 전달돼 placeholder이자 TalkBack 라벨 역할을 유지하고, 즉시
    // (디바운스) 검색은 _queryController를, 지우기는 onClear를 통해 보존된다.
    // AppBar leading(자동 뒤로가기)은 title 왼쪽에 그대로 남아 "← + 46px 필드"
    // 구성이 홈 편집 모드와 일치한다.
    final searchInputField = EasySubwaySearchField(
      controller: _queryController,
      focusNode: _searchFocusNode,
      hintText: _searchInputHint,
      // #2090: hint는 입력이 있으면 InputDecorator가 지워 "출발/도착/경유역 이름을
      // 입력해 주세요" 슬롯 맥락이 입력 후 스크린리더에서 소실된다. floating label
      // 회귀(#1933) 없이 맥락을 유지하도록 동일 문구를 semantics 라벨로 전달해
      // 필드를 감싼다. 홈 검색은 이 파라미터를 쓰지 않아 라벨 이중 낭독이 없다.
      semanticsLabel: _searchInputHint,
      autofocus: !isNearbyEntry,
      onSubmitted: _submit,
      onClear: _queryController.clear,
    );
    // 공용 필드는 56 터치타겟 안에 46px 시각 박스를 배치하고, 그 안 단일 줄
    // TextField가 입력 텍스트(fontSize 17)를 세로 contentPadding으로 감싼다. AppBar
    // 기본 toolbarHeight(56)에 그대로 넣으면 시스템 글자 크기를 키웠을 때 필드가
    // 세로로 잘리므로 필드 실제 렌더 높이에 맞춰 툴바를 키운다. 축소는 하지 않아
    // 기본 배율의 레이아웃은 불변이고, titleSpacing·즉시 입력·뒤로가기 leading
    // 동작은 유지된다.
    final textScaler = MediaQuery.textScalerOf(context);
    // #2090: 공용 필드(EasySubwaySearchField)는 배율에 비례해 바깥 터치타겟(56),
    // 시각 박스(46), 입력 필드(48)를 함께 키운다. 필드가 실제로 차지하는 세로
    // 높이는 이 셋의 최댓값이며 항상 터치타겟(56*배율)이 지배한다. 이전
    // 보정 상수(scale(17*1.2)+30)는 새 필드 메트릭을 과소평가해 확대 시 필드가
    // 툴바 아래로 잘렸으므로, 공용 위젯이 쓰는 것과 동일한 상수·산식으로 필드
    // 높이를 재도출해 정합한다.
    final scaledFieldHeight = math.max(
      math.max(
        EasySubwayTouchTarget.general,
        textScaler.scale(EasySubwayTouchTarget.general),
      ),
      math.max(
        easySubwaySearchFieldVisualHeight,
        textScaler.scale(easySubwaySearchFieldVisualHeight),
      ),
    );
    // #2082: title Row를 홈 search row와 동일하게 상하 6px 패딩으로 감싸므로,
    // 툴바 높이도 그만큼(12) 키워 필드가 잘리지 않게 한다(홈 상단바 60 = 필드
    // 46/터치타겟 대비 여백과 같은 원리).
    const stationSearchToolbarVerticalPadding = 12.0;
    final toolbarHeight = math.max(
      kToolbarHeight,
      scaledFieldHeight + stationSearchToolbarVerticalPadding,
    );
    final recentSearchSection = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final isSearching =
            _controller.state.status == StationSearchStatus.loading;
        if (isNearbyEntry || _hasSearchQuery || _recentQueries.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: StationRecentSearchSection(
            queries: _recentQueries,
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
              return TextButton.icon(
                key: const Key('nearbyStationSearchButton'),
                style: TextButton.styleFrom(
                  foregroundColor: EasySubwayAccessibleColors.text,
                  alignment: Alignment.centerLeft,
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: isNearbyDisabled ? null : _searchNearby,
                icon: const Icon(Icons.my_location),
                label: const Text('내 주변 역 다시 찾기'),
              );
            }
            if (_hasSearchQuery) {
              // 즉시(디바운스) 검색으로 통일했으므로 별도 검색 버튼을 두지 않는다.
              return const SizedBox.shrink();
            }
            return TextButton.icon(
              key: const Key('nearbyStationSearchButton'),
              style: TextButton.styleFrom(
                foregroundColor: EasySubwayAccessibleColors.text,
                alignment: Alignment.centerLeft,
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: isNearbyDisabled ? null : _searchNearby,
              icon: const Icon(Icons.my_location),
              label: const Text('내 주변 역 찾기'),
            );
          },
        ),
        const SizedBox(height: 20),
      ],
    );
    final isPicking = widget.pickSlot != null;
    final resultSection = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return StationSearchBody(
          state: _controller.state,
          // 칸 채우기 모드에서는 결과 한 번 탭 = 해당 칸 설정 후 닫기. 지도 탭과 동일
          // 하게 "출발역 선택 → 도착역 선택" UX로 수렴시킨다. 둘러보기 모드에서는
          // 종전대로 역 상세로 이동한다.
          onResultTap: isPicking ? _pickStation : _returnStationToMap,
          onSetOrigin: isPicking || widget.routeDraftController == null
              ? null
              : _setRouteOrigin,
          onSetDestination: isPicking || widget.routeDraftController == null
              ? null
              : _setRouteDestination,
          isOpeningLocationSettings: _isOpeningLocationSettings,
          onOpenLocationSettings: _openLocationSettings,
        );
      },
    );
    return Scaffold(
      // 큰 타이틀 화면(예: "역 검색")을 없애고 입력 필드 자체가 헤더가 된다. 열리는
      // 즉시 입력 모드로 들어가 탭 두 번을 요구하던 랜딩 단계를 지운다. 뒤로가기는
      // AppBar 기본 leading을 그대로 쓴다(자동 back 버튼 → 입력 필드 순서 유지).
      appBar: AppBar(
        titleSpacing: 0,
        toolbarHeight: toolbarHeight,
        // #2082: 검색 화면 상단바를 홈 idle 상단바 [≡ | 검색필드 | 지역표시]와
        // 픽셀 단위로 정합한다. AppBar 기본 leading/titleSpacing 대신 홈의 search
        // row 구조(Padding.fromLTRB(10,6,10,6) 안 Row[뒤로 56, SB 4, Expanded 필드,
        // SB 8, 지역표시])를 그대로 재현해, ← 버튼이 홈의 ≡ 슬롯과 같은 x를 차지하고
        // 필드의 좌우 시작·끝 x가 홈 idle 필드와 일치하며, 지역 표시가 필드 우측에
        // 홈과 같은 위치·스타일로 온다. 뒤로가기 아이콘·색·탭타깃도 홈 ≡ 버튼과
        // 동일 규격이다. 지역 표시는 홈 지역 선택기 스타일이되 검색 맥락에선 표시
        // 전용이다(오너 지시: "변경은 못해도 알려는 줘야").
        //
        // automaticallyImplyLeading: false + 커스텀 IconButton(아래)을 쓰는 이유:
        // ① 이 앱은 한국어 한정 서비스라(오너 결정) 자동 BackButton이 제공하는
        // MaterialLocalizations 지역화 툴팁("Back" 등)이 불필요하고, 커스텀
        // IconButton으로 한글 tooltip('뒤로')을 직접 지정하는 편이 맥락에 맞는다.
        // ② 자동 BackButton은 크기·패딩이 Material 기본 규격을 따라 위 홈 ≡ 슬롯
        // (56 정사각 탭타깃)과 폭이 정합되지 않는다. 여기서는 minimumSize·
        // tapTargetSize·padding을 홈 ≡ 버튼과 동일 규격으로 명시 통제해야 위 주석의
        // 픽셀 정합이 성립한다. "코드 정리" 목적으로 automaticallyImplyLeading을
        // true로 되돌리거나 IconButton을 BackButton으로 바꾸면 이 폭 정합이 깨진다.
        automaticallyImplyLeading: false,
        title: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Row(
            children: [
              IconButton(
                key: const Key('stationSearchBackButton'),
                tooltip: '뒤로',
                onPressed: () => Navigator.of(context).maybePop(),
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(EasySubwayTouchTarget.general),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(
                  Icons.arrow_back,
                  size: 26,
                  color: Color(0xFF4B4B4B),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(child: searchInputField),
              const SizedBox(width: 8),
              _StationSearchRegionIndicator(regionLabel: widget.regionLabel),
            ],
          ),
        ),
      ),
      bottomNavigationBar: widget.bottomNavigationBar,
      body: Semantics(
        container: true,
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
                    recentSearchSection: recentSearchSection,
                    actionButtonSection: actionButtonSection,
                    resultSection: resultSection,
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
    // 키보드 검색 액션 등 명시적 검색: 디바운스를 취소하고 최근 검색에 기록한다.
    _searchDebounce?.cancel();
    if (_controller.state.status == StationSearchStatus.loading) {
      return;
    }
    unawaited(_runSearch(query));
  }

  Future<void> _runSearch(String query, {bool recordHistory = true}) async {
    await _controller.search(query, recordHistory: recordHistory);
    // 최근 검색 목록은 기록한 경우에만 바뀌므로, 디바운스 타이핑 검색에서는
    // 불필요한 재조회를 하지 않는다.
    if (recordHistory) {
      await _loadRecentQueries();
    }
  }

  void _searchRecentQuery(String query) {
    _queryController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _submit(query);
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

  /// 칸 채우기 모드: 결과를 탭하면 지정된 칸을 [routeDraftController]에 설정하고
  /// 화면을 닫으면서 선택한 역을 반환한다. 지도 탭 경로와 같은 컨트롤러·같은 draft로
  /// 수렴한다.
  void _pickStation(StationSearchResult result) {
    final slot = widget.pickSlot;
    if (slot == null) {
      return;
    }
    final station = RouteDraftStation(id: result.id, nameKo: result.nameKo);
    switch (slot) {
      case RouteDraftSlot.origin:
        widget.routeDraftController?.setOrigin(station);
      case RouteDraftSlot.destination:
        widget.routeDraftController?.setDestination(station);
      case RouteDraftSlot.waypoint:
        widget.routeDraftController?.setWaypoint(station);
    }
    Navigator.of(context).pop(station);
  }

  /// #2109 둘러보기(비픽) 모드: 결과를 탭하면 상세를 밀지 않고 선택한 역 id를
  /// 반환하며 화면을 닫는다. 호출부(main.dart openStationSearch)가 이 id를
  /// 받아 노선도 focus + 팬 메뉴 + 해당 역 하단 패널을 트리거한다(임베디드
  /// 검색과 동일한 흐름으로 수렴).
  void _returnStationToMap(StationSearchResult result) {
    Navigator.of(context).pop(result);
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
    // #1933 요구 3: 별도 길찾기 폼 페이지를 없앴다. 출발·도착을 설정하면 draft로
    // 수렴하고, 둘 다 채워지면 셸이 자동으로 결과 타임라인을 연다. 폼으로 보내던
    // "길찾기 보기" 스낵바 액션은 더 이상 두지 않는다.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _searchNearby() async {
    if (_controller.state.status == StationSearchStatus.loading ||
        _isNearbySearchRunning) {
      return;
    }
    setState(() => _isNearbySearchRunning = true);
    try {
      // 사전 안내 다이얼로그 없이 바로 위치를 요청한다. 거부 시에는 결과 영역의
      // 실패 안내와 '위치 설정 열기'로 재안내하므로 별도 사전 고지가 필요 없다.
      await _controller.searchNearby(widget.locationProvider);
    } finally {
      if (mounted) {
        setState(() => _isNearbySearchRunning = false);
      }
    }
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
}

/// #2082: 검색 화면 상단 필드 우측 지역 표시. 홈 idle 상단바의 지역 선택기와
/// 같은 위치·스타일(maxWidth 148, 17·w600 회색 텍스트 + 아래 화살표)을 쓰되,
/// 검색 맥락에서는 지역 변경 UI를 새로 열지 않는 표시 전용이다(오너 지시). 탭
/// 동작이 없으므로 스크린리더에는 현재 지역명을 읽어 주는 라벨만 노출한다.
class _StationSearchRegionIndicator extends StatelessWidget {
  const _StationSearchRegionIndicator({required this.regionLabel});

  final String regionLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('stationSearchRegionIndicator'),
      container: true,
      label: '지역: $regionLabel',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 148),
          child: SizedBox(
            height: EasySubwayTouchTarget.general,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    regionLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF606060),
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.keyboard_arrow_down,
                  color: Color(0xFF606060),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StationRecentSearchSection extends StatelessWidget {
  const StationRecentSearchSection({
    super.key,
    required this.queries,
    required this.enabled,
    required this.onQuerySelected,
    required this.onQueryRemoved,
    required this.onClearAll,
  });

  final List<String> queries;
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
        Row(
          children: [
            Expanded(
              child: Text(
                '최근 검색',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
            TextButton.icon(
              key: const Key('stationRecentSearchClearAllButton'),
              style: TextButton.styleFrom(
                foregroundColor: EasySubwayAccessibleColors.mutedText,
              ),
              onPressed: enabled ? onClearAll : null,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('전체 삭제'),
            ),
          ],
        ),
        const Divider(
          height: EasySubwaySpacing.lg,
          color: EasySubwayAccessibleColors.line,
        ),
        Column(
          children: [
            for (final entry in queries.indexed) ...[
              if (entry.$1 > 0)
                const Divider(
                  height: 1,
                  color: EasySubwayAccessibleColors.line,
                ),
              _StationRecentSearchItem(
                query: entry.$2,
                order: entry.$1 + 1,
                enabled: enabled,
                onQuerySelected: onQuerySelected,
                onQueryRemoved: onQueryRemoved,
              ),
            ],
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
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
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
                  onTap: enabled ? () => onQuerySelected(query) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: EasySubwaySpacing.md,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.history,
                          color: EasySubwayAccessibleColors.iconMuted,
                        ),
                        const SizedBox(width: EasySubwaySpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                query,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: EasySubwayAccessibleColors.text,
                                      fontWeight: FontWeight.w700,
                                      height: 1.25,
                                    ),
                              ),
                              Text(
                                '최근 사용 $order번째',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: EasySubwayAccessibleColors.caption,
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
    );
  }
}

class _StationSearchAdaptiveContent extends StatelessWidget {
  const _StationSearchAdaptiveContent({
    required this.isLargeScreen,
    required this.recentSearchSection,
    required this.actionButtonSection,
    required this.resultSection,
  });

  final bool isLargeScreen;
  final Widget recentSearchSection;
  final Widget actionButtonSection;
  final Widget resultSection;

  @override
  Widget build(BuildContext context) {
    if (!isLargeScreen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [recentSearchSection, actionButtonSection, resultSection],
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
                children: [actionButtonSection, resultSection],
              ),
            ),
            const SizedBox(
              width: EasySubwayAdaptiveLayout.largeScreenColumnGap,
            ),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [recentSearchSection],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StationSearchBody extends StatelessWidget {
  const StationSearchBody({
    super.key,
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
          ],
          for (final result
              in state.source == StationSearchResultSource.nearby
                  ? state.results.skip(1)
                  : state.results)
            _StationSearchResultTile(
              result: result,
              onTap: () => onResultTap(result),
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
      color: EasySubwayAccessibleColors.surface,
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
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              stationName,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    color: EasySubwayAccessibleColors.text,
                                    fontWeight: FontWeight.w700,
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
                color: EasySubwayAccessibleColors.mutedText,
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
          color: EasySubwayAccessibleColors.secondaryText,
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
    final stationName = _stationResultDisplayName(result.nameKo);
    // 역이 지나는 노선마다 한 행씩 표시한다. 각 행은 하단 구분선만 두고
    // 좌측에 무채색 역명, 우측에 해당 노선 배지를 둔다(추가 텍스트·화살표 없음).
    final lines = result.lines;
    if (lines.isEmpty) {
      return _StationSearchResultLineRow(
        key: Key('stationSearchResult-${result.id}'),
        stationName: stationName,
        line: null,
        semanticLabel: '$stationName, 선택',
        onTap: onTap,
      );
    }
    return Column(
      children: [
        for (var i = 0; i < lines.length; i++)
          // 한 역이 여러 노선을 지나면 시각적으로는 노선마다 한 행씩 펼치지만,
          // 각 행이 "역명, 노선명, 선택" 버튼 시맨틱을 노출하면 스크린리더에 같은
          // 선택 버튼이 노선 수만큼 뜬다. 첫 행만 시맨틱 버튼으로 남기고 이후
          // 행들은 ExcludeSemantics 로 감싸 시각 렌더만 유지한다.
          if (i == 0)
            _StationSearchResultLineRow(
              // 첫 행에만 대표 키를 두어 기존 테스트가 단일 위젯을 찾도록 한다.
              key: Key('stationSearchResult-${result.id}'),
              stationName: stationName,
              line: lines[i],
              semanticLabel: '$stationName, ${lines[i].name}, 선택',
              onTap: onTap,
            )
          else
            ExcludeSemantics(
              child: _StationSearchResultLineRow(
                stationName: stationName,
                line: lines[i],
                semanticLabel: '$stationName, ${lines[i].name}, 선택',
                onTap: onTap,
              ),
            ),
      ],
    );
  }
}

class _StationSearchResultLineRow extends StatelessWidget {
  const _StationSearchResultLineRow({
    required this.stationName,
    required this.line,
    required this.semanticLabel,
    required this.onTap,
    super.key,
  });

  final String stationName;
  final StationSearchLine? line;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final line = this.line;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: EasySubwayAccessibleColors.line),
        ),
      ),
      child: MergeSemantics(
        child: Semantics(
          label: semanticLabel,
          button: true,
          onTap: onTap,
          child: ExcludeSemantics(
            child: InkWell(
              onTap: onTap,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          stationName,
                          style: const TextStyle(
                            color: EasySubwayAccessibleColors.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (line != null) ...[
                        const SizedBox(width: 12),
                        StationLineBadge(line: line, size: 32),
                      ],
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
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
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
    return '$stationName, ${result.lineLabel}, ${result.region}';
  }
  return '$stationName, $distance, ${result.lineLabel}, ${result.region}';
}

class StationDetailScreen extends StatefulWidget {
  const StationDetailScreen({
    required this.repository,
    required this.reportRepository,
    required this.stationId,
    this.favoriteRepository,
    this.adRepository,
    this.realtimeRepository,
    this.locationProvider,
    this.initiallyFavorite,
    this.facilityReportDraftTargetStore,
    this.internalRouteRepository,
    this.internalRouteRequest,
    this.internalRouteMobilityType = 'SENIOR',
    this.routeDraftController,
    this.mapLauncher = const UrlLauncherKakaoMapLauncher(),
    super.key,
  });

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final FavoriteStationRepository? favoriteRepository;
  final AdRepository? adRepository;
  final RealtimeRepository? realtimeRepository;
  final CurrentLocationProvider? locationProvider;
  final String stationId;
  final bool? initiallyFavorite;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final InternalRouteRepository? internalRouteRepository;
  final InternalRouteRequest? internalRouteRequest;
  final String internalRouteMobilityType;
  final RouteDraftController? routeDraftController;
  final KakaoMapLauncher mapLauncher;

  @override
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class StationTimetableScreen extends StatefulWidget {
  const StationTimetableScreen({
    required this.stationId,
    required this.stationName,
    required this.lines,
    this.repository,
    super.key,
  });

  final String stationId;
  final String stationName;
  final List<StationSearchLine> lines;
  final StationTimetableRepository? repository;

  @override
  State<StationTimetableScreen> createState() => _StationTimetableScreenState();
}

class _StationTimetableScreenState extends State<StationTimetableScreen> {
  late String? _lineId;
  late StationTimetableDayType _dayType;
  StationTimetable? _timetable;
  String? _directionName;
  var _loading = false;
  var _requestId = 0;

  @override
  void initState() {
    super.initState();
    _lineId = widget.lines.firstOrNull?.id;
    final now = debugStationVerifiedClock();
    _dayType = _todayTimetableDayType(now);
    if (widget.repository != null && _lineId != null) {
      unawaited(_load(date: now, findCoverage: true));
    }
  }

  Future<void> _load({DateTime? date, bool findCoverage = false}) async {
    final repository = widget.repository;
    final lineId = _lineId;
    if (repository == null || lineId == null) {
      return;
    }
    final requestId = ++_requestId;
    setState(() => _loading = true);
    try {
      final timetable = findCoverage
          ? await _loadFirstAvailableStationTimetable(
              stationId: widget.stationId,
              lines: widget.lines,
              repository: repository,
              date: date!,
            )
          : date == null
          ? await repository.loadStationTimetable(
              stationId: widget.stationId,
              lineId: lineId,
              dayType: _dayType,
              referenceDate: debugStationVerifiedClock(),
            )
          : await repository.loadStationTimetableForDate(
              stationId: widget.stationId,
              lineId: lineId,
              date: date,
            );
      if (!mounted || requestId != _requestId) {
        return;
      }
      if (timetable == null) {
        setState(() => _loading = false);
        return;
      }
      final directionNames = timetable.directions
          .map((direction) => direction.name)
          .toSet();
      setState(() {
        _timetable = timetable;
        _lineId = timetable.lineId;
        _dayType = timetable.dayType;
        _directionName = directionNames.contains(_directionName)
            ? _directionName
            : timetable.directions.firstOrNull?.name;
        _loading = false;
      });
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '역 시간표 조회 중 예외가 발생했습니다.');
      if (!mounted || requestId != _requestId) {
        return;
      }
      setState(() {
        _timetable = null;
        _directionName = null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final timetable = _timetable;
    final direction = timetable?.directions
        .where((item) => item.name == _directionName)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.stationName} 시간표')),
      body: SafeArea(
        child: ListView(
          padding: _stationSearchPagePadding,
          children: [
            if (widget.lines.length > 1) ...[
              const _StationDetailSectionTitle(title: '노선'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final line in widget.lines)
                    ChoiceChip(
                      key: Key('stationTimetableLine-${line.id}'),
                      label: Text(line.name),
                      selected: _lineId == line.id,
                      onSelected: (_) {
                        setState(() => _lineId = line.id);
                        unawaited(_load());
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
            ],
            const _StationDetailSectionTitle(title: '운행일'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final dayType in StationTimetableDayType.values)
                  ChoiceChip(
                    key: Key('stationTimetableDay-${dayType.name}'),
                    label: Text(dayType.label),
                    selected: _dayType == dayType,
                    onSelected: (_) {
                      setState(() => _dayType = dayType);
                      unawaited(_load());
                    },
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (timetable == null || !timetable.isAvailable)
              const _StationDetailEmptyMessage(message: '시간표를 준비 중이에요.')
            else ...[
              const _StationDetailSectionTitle(title: '방향'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in timetable.directions)
                    ChoiceChip(
                      key: Key('stationTimetableDirection-${item.name}'),
                      label: Text(item.name),
                      selected: _directionName == item.name,
                      onSelected: (_) =>
                          setState(() => _directionName = item.name),
                    ),
                ],
              ),
              if (direction != null) ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  children: [
                    Text('첫차 ${direction.firstDeparture.timeLabel}'),
                    Text('막차 ${direction.lastDeparture.timeLabel}'),
                  ],
                ),
                const SizedBox(height: 12),
                for (
                  var index = 0;
                  index < direction.departures.length;
                  index++
                ) ...[
                  if (index > 0) const Divider(height: 1),
                  Semantics(
                    label: direction.departures[index].semanticLabel,
                    child: ExcludeSemantics(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(direction.departures[index].timeLabel),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }
}

StationTimetableDayType _todayTimetableDayType(DateTime now) {
  return switch (now.weekday) {
    DateTime.saturday => StationTimetableDayType.saturday,
    DateTime.sunday => StationTimetableDayType.sundayHoliday,
    _ => StationTimetableDayType.weekday,
  };
}

Future<StationTimetable?> _loadFirstAvailableStationTimetable({
  required String stationId,
  required List<StationSearchLine> lines,
  required StationTimetableRepository repository,
  required DateTime date,
}) async {
  StationTimetable? firstResult;
  for (final line in lines) {
    final timetable = await repository.loadStationTimetableForDate(
      stationId: stationId,
      lineId: line.id,
      date: date,
    );
    firstResult ??= timetable;
    if (timetable.isAvailable) {
      return timetable;
    }
  }
  return firstResult;
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
      appBar: AppBar(title: const Text('역 상세')),
      body: Semantics(
        container: true,
        child: SafeArea(
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _controller,
              ?_internalRouteController,
            ]),
            builder: (context, _) {
              return _StationDetailBody(
                state: _controller.state,
                onRetryRealtime: _controller.retryRealtime,
                internalRouteState: _internalRouteController?.state,
                reportRepository: widget.reportRepository,
                favoriteController: _favoriteController,
                adRepository: widget.adRepository,
                routeDraftController: widget.routeDraftController,
                locationProvider: widget.locationProvider,
                mapLauncher: widget.mapLauncher,
                facilityReportDraftTargetStore:
                    widget.facilityReportDraftTargetStore,
                timetableRepository:
                    widget.repository is StationTimetableRepository
                    ? widget.repository as StationTimetableRepository
                    : null,
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
    required this.onRetryRealtime,
    required this.internalRouteState,
    required this.reportRepository,
    required this.favoriteController,
    required this.adRepository,
    required this.routeDraftController,
    required this.locationProvider,
    required this.mapLauncher,
    required this.facilityReportDraftTargetStore,
    required this.timetableRepository,
  });

  final StationDetailState state;
  final VoidCallback onRetryRealtime;
  final InternalRouteState? internalRouteState;
  final FacilityReportRepository reportRepository;
  final StationFavoriteToggleController? favoriteController;
  final AdRepository? adRepository;
  final RouteDraftController? routeDraftController;
  final CurrentLocationProvider? locationProvider;
  final KakaoMapLauncher mapLauncher;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final StationTimetableRepository? timetableRepository;

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
        onRetryRealtime: onRetryRealtime,
        internalRouteState: internalRouteState,
        reportRepository: reportRepository,
        favoriteController: favoriteController,
        adRepository: adRepository,
        routeDraftController: routeDraftController,
        locationProvider: locationProvider,
        mapLauncher: mapLauncher,
        facilityReportDraftTargetStore: facilityReportDraftTargetStore,
        timetableRepository: timetableRepository,
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
    required this.onRetryRealtime,
    required this.internalRouteState,
    required this.reportRepository,
    required this.favoriteController,
    required this.adRepository,
    required this.routeDraftController,
    required this.locationProvider,
    required this.mapLauncher,
    required this.facilityReportDraftTargetStore,
    required this.timetableRepository,
  });

  final StationDetail detail;
  final List<StationExitInfo> exits;
  final List<StationFacilityInfo> facilities;
  final String facilityAttentionSummary;
  final String facilityAttentionSemanticLabel;
  final List<StationLayoutSummaryItem> layoutSummaryItems;
  final String layoutSummarySemanticLabel;
  final RealtimeSnapshot realtimeSnapshot;
  final VoidCallback onRetryRealtime;
  final InternalRouteState? internalRouteState;
  final FacilityReportRepository reportRepository;
  final StationFavoriteToggleController? favoriteController;
  final AdRepository? adRepository;
  final RouteDraftController? routeDraftController;
  final CurrentLocationProvider? locationProvider;
  final KakaoMapLauncher mapLauncher;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final StationTimetableRepository? timetableRepository;

  @override
  Widget build(BuildContext context) {
    // 정보구조 다이어트(#1497): 첫 화면에서 역 이름·고장 여부·실시간 도착·주요
    // 행동이 보이도록 실시간을 위로, 메타는 맨 아래로, 중복 "지도 위치 목록"과
    // 상시 안전 안내는 제거, "역 안 이동 안내"+"순서"는 한 섹션으로 통합한다.
    final primaryChildren = <Widget>[
      _StationDetailHeader(detail: detail),
      const SizedBox(height: 12),
      if (facilityAttentionSummary.isNotEmpty) ...[
        _StationFacilityStatusSummary(
          text: facilityAttentionSummary,
          semanticLabel: facilityAttentionSemanticLabel,
        ),
        const SizedBox(height: 16),
      ],
      const _StationDetailSectionTitle(title: '실시간 열차'),
      const SizedBox(height: 12),
      _StationRealtimeSummary(
        snapshot: realtimeSnapshot,
        onRetry: onRetryRealtime,
      ),
      const SizedBox(height: 20),
      _StationDetailRouteActions(
        detail: detail,
        routeDraftController: routeDraftController,
        favoriteController: favoriteController,
      ),
      const SizedBox(height: 20),
      _StationTimetableEntry(detail: detail, repository: timetableRepository),
    ];
    // 데이터 부재(unavailable) 상태는 화면에 아무것도 그리지 않으므로
    // 역 안 이동 섹션 노출 여부·간격 계산에서도 빈 안내로 취급한다(#1577).
    final internalRouteStateValue = internalRouteState;
    final hasInternalRouteGuidance =
        internalRouteStateValue != null &&
        internalRouteStateValue.status != InternalRouteViewStatus.unavailable;
    final detailChildren = <Widget>[
      if (layoutSummaryItems.isNotEmpty || hasInternalRouteGuidance) ...[
        const _StationDetailSectionTitle(title: '역 안 이동'),
        const SizedBox(height: 12),
        if (layoutSummaryItems.isNotEmpty) ...[
          _StationLayoutSummary(
            items: layoutSummaryItems,
            semanticLabel: layoutSummarySemanticLabel,
          ),
          if (hasInternalRouteGuidance) const SizedBox(height: 16),
        ],
        if (hasInternalRouteGuidance)
          _StationInternalRouteGuidance(state: internalRouteState!),
        const SizedBox(height: 24),
      ],
      const _StationDetailSectionTitle(title: '출구'),
      const SizedBox(height: 12),
      if (exits.isEmpty)
        const _StationDetailEmptyMessage(message: '출구 안내를 준비 중이에요.')
      else
        for (final exit in exits)
          _StationExitCard(
            station: detail,
            exit: exit,
            mapLauncher: mapLauncher,
            locationProvider: locationProvider,
          ),
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
      // 메타 정보(안내 출처·마지막 확인)는 맨 아래로.
      _InfoBasisDisclosure(
        labels: [
          detail.dataSourceLabel,
          '마지막 확인 ${stationVerifiedRelativeLabel(detail.lastVerifiedAt)}',
        ],
      ),
      if (adRepository case final repository?) ...[
        const SizedBox(height: 24),
        ActiveAdBanner(
          key: const Key('stationDetailBottomAdBanner'),
          repository: repository,
          placement: AdPlacement.stationDetailBottom,
        ),
      ],
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

class _StationTimetableEntry extends StatefulWidget {
  const _StationTimetableEntry({required this.detail, this.repository});

  final StationDetail detail;
  final StationTimetableRepository? repository;

  @override
  State<_StationTimetableEntry> createState() => _StationTimetableEntryState();
}

class _StationTimetableEntryState extends State<_StationTimetableEntry> {
  StationTimetable? _timetable;

  @override
  void initState() {
    super.initState();
    final repository = widget.repository;
    if (repository != null && widget.detail.lines.isNotEmpty) {
      unawaited(_load(repository, widget.detail.lines));
    }
  }

  Future<void> _load(
    StationTimetableRepository repository,
    List<StationSearchLine> lines,
  ) async {
    try {
      final timetable = await _loadFirstAvailableStationTimetable(
        stationId: widget.detail.id,
        lines: lines,
        repository: repository,
        date: debugStationVerifiedClock(),
      );
      if (mounted && timetable != null) {
        setState(() => _timetable = timetable);
      }
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 상세 시간표 요약 조회 중 예외가 발생했습니다.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final timetable = _timetable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StationDetailSectionTitle(title: '시간표'),
        const SizedBox(height: 8),
        if (timetable != null && timetable.isAvailable)
          for (final direction in timetable.directions)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${direction.name} · 첫차 ${direction.firstDeparture.timeLabel} · '
                '막차 ${direction.lastDeparture.timeLabel}',
              ),
            )
        else
          const Text('시간표를 준비 중이에요.'),
        const SizedBox(height: 4),
        TextButton.icon(
          key: const Key('stationTimetableButton'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => StationTimetableScreen(
                stationId: widget.detail.id,
                stationName: widget.detail.nameKo,
                lines: widget.detail.lines,
                repository: widget.repository,
              ),
            ),
          ),
          icon: const Icon(Icons.schedule),
          label: const Text('시간표 보기'),
        ),
      ],
    );
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

class _StationRealtimeSummary extends StatelessWidget {
  const _StationRealtimeSummary({
    required this.snapshot,
    required this.onRetry,
  });

  final RealtimeSnapshot snapshot;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final title = switch (snapshot.status) {
      RealtimeSnapshotStatus.fresh => '도착 정보',
      RealtimeSnapshotStatus.stale => '최근 도착 정보',
      RealtimeSnapshotStatus.unsupported => '지원 준비 중',
      RealtimeSnapshotStatus.unavailable => '실시간 정보 확인 불가',
      RealtimeSnapshotStatus.loading => '실시간 정보 확인 중',
    };
    // 실시간 조회가 실패로 끝난 경우에만 다시 시도를 권한다. 미지원 노선은
    // 재시도해도 결과가 같으므로 버튼을 노출하지 않는다.
    final canRetry = snapshot.status == RealtimeSnapshotStatus.unavailable;
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
      if (canRetry) '다시 시도할 수 있어요',
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
                      fontWeight: FontWeight.w700,
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
            if (canRetry) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('stationRealtimeRetryButton'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 20),
                  label: const Text('다시 시도'),
                ),
              ),
            ],
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
    required this.favoriteController,
  });

  final StationDetail detail;
  final RouteDraftController? routeDraftController;
  final StationFavoriteToggleController? favoriteController;

  @override
  Widget build(BuildContext context) {
    // 상용 지도·교통 앱(카카오맵·구글맵)처럼 출발·도착·저장(즐겨찾기)을 한 줄의
    // 동등한 액션으로 묶는다. 즐겨찾기는 별도 큰 버튼이 아니라 이 행의 피어다.
    final draftController = routeDraftController;
    final favController = favoriteController;
    final station = RouteDraftStation(id: detail.id, nameKo: detail.nameKo);
    final buttons = <Widget>[
      if (draftController != null) ...[
        _StationPointButton(
          key: const Key('stationDetailSetOriginButton'),
          icon: Icons.trip_origin,
          label: '출발',
          onPressed: () {
            draftController.setOrigin(station);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${station.displayName}을 출발역으로 설정했습니다')),
            );
          },
        ),
        _StationPointButton(
          key: const Key('stationDetailSetDestinationButton'),
          icon: Icons.flag_outlined,
          label: '도착',
          onPressed: () {
            draftController.setDestination(station);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${station.displayName}을 도착역으로 설정했습니다')),
            );
          },
        ),
      ],
      if (favController != null)
        _StationFavoriteButton(detail: detail, controller: favController),
    ];
    if (buttons.isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: buttons[i]),
        ],
      ],
    );
  }
}

class _StationFavoriteButton extends StatelessWidget {
  const _StationFavoriteButton({
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
        final label = switch (state.status) {
          StationFavoriteToggleStatus.checking => '확인 중',
          StationFavoriteToggleStatus.saving => '저장 중',
          StationFavoriteToggleStatus.removing => '해제 중',
          StationFavoriteToggleStatus.ready ||
          StationFavoriteToggleStatus.failure => isFavorite ? '저장됨' : '저장',
        };
        final actionLabel = state.status == StationFavoriteToggleStatus.checking
            ? '즐겨찾기 확인 중'
            : isFavorite
            ? '즐겨찾기 해제'
            : '즐겨찾기 저장';
        final onPressed = state.isBusy
            ? null
            : () async {
                if (isFavorite) {
                  await controller.remove();
                } else {
                  await controller.save();
                }
                if (!context.mounted) {
                  return;
                }
                // 저장·해제 결과(및 실패 사유)는 상용 앱과 동일하게 스낵바로 알린다.
                // 직전 스낵바는 지워 연속 토글 시 최신 결과가 바로 보이게 한다.
                final message = controller.state.message;
                if (message.isNotEmpty) {
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(SnackBar(content: Text(message)));
                }
              };
        return Semantics(
          container: true,
          label: '${detail.nameKo}역 $actionLabel',
          button: true,
          onTap: onPressed,
          child: ExcludeSemantics(
            child: _StationPointButton(
              key: const Key('stationFavoriteToggleButton'),
              icon: isFavorite ? Icons.star : Icons.star_border,
              label: label,
              onPressed: onPressed,
            ),
          ),
        );
      },
    );
  }
}

class _StationPointButton extends StatelessWidget {
  const _StationPointButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // 같은 성격 행동은 화면이 달라도 같은 패턴: 검색 결과의 _StationRoleButton과
    // 동일하게 아웃라인 아이콘 + 라벨, 단일 primary 계열.
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(EasySubwayTouchTarget.general),
        backgroundColor: Colors.white,
        foregroundColor: EasySubwayAccessibleColors.primary,
        side: const BorderSide(color: EasySubwayAccessibleColors.line),
        shape: const RoundedRectangleBorder(
          borderRadius: _stationDetailActionButtonRadius,
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      icon: Icon(icon, size: 22),
      label: Text(label),
    );
  }
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
    // 상용 앱 리스트 밀도에 맞춰 세로 타일을 아이콘+텍스트 가로 행으로 낮춰
    // 높이를 줄인다(고정 minHeight 제거).
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.surface,
        borderRadius: _stationDetailInfoCardRadius,
        border: Border.all(color: EasySubwayAccessibleColors.line),
      ),
      child: Row(
        children: [
          Icon(item.icon, color: EasySubwayAccessibleColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.text,
              style: textTheme.bodyLarge?.copyWith(
                color: EasySubwayAccessibleColors.text,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
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
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
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
                        color: EasySubwayAccessibleColors.text,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    // 부역명(#1789 P0.2). name_ko에서 분리한 부역명을 역명 아래
                    // 보조 표기로 노출한다(있을 때만).
                    if (detail.nameSub.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail.nameSub,
                        style: textTheme.bodyMedium?.copyWith(
                          color: EasySubwayAccessibleColors.secondaryText,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      detail.lineLabel,
                      style: textTheme.bodyLarge?.copyWith(
                        color: EasySubwayAccessibleColors.secondaryText,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    '마지막 확인',
                    style: TextStyle(
                      color: EasySubwayAccessibleColors.mutedText,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stationVerifiedRelativeLabel(detail.lastVerifiedAt),
                    style: const TextStyle(
                      color: EasySubwayAccessibleColors.mutedText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
      // 데이터 부재는 사과 문구 없이 숨긴다(#1577).
      InternalRouteViewStatus.unavailable => const SizedBox.shrink(),
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
            color: EasySubwayAccessibleColors.surface,
            borderRadius: _stationDetailInfoCardRadius,
            border: Border.all(color: EasySubwayAccessibleColors.line),
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
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                result.totalBurdenLabel,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: EasySubwayAccessibleColors.secondaryText,
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
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                step.burdenLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: EasySubwayAccessibleColors.secondaryText,
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
          icon: Icon(
            _expanded ? Icons.expand_less : Icons.expand_more,
            size: 24,
          ),
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
                      fontWeight: FontWeight.w700,
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
          fontWeight: FontWeight.w700,
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
        color: EasySubwayAccessibleColors.secondaryText,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
    );
  }
}

class _StationExitCard extends StatefulWidget {
  const _StationExitCard({
    required this.station,
    required this.exit,
    required this.mapLauncher,
    required this.locationProvider,
  });

  final StationDetail station;
  final StationExitInfo exit;
  final KakaoMapLauncher mapLauncher;
  final CurrentLocationProvider? locationProvider;

  @override
  State<_StationExitCard> createState() => _StationExitCardState();
}

class _StationExitCardState extends State<_StationExitCard> {
  CurrentLocation? _walkingRouteStart;
  String _locationMessage = '';
  bool _isLoadingLocation = false;
  bool _isOpeningWalkingRoute = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final station = widget.station;
    final exit = widget.exit;
    final mapTarget = _stationExitMapTarget(station: station, exit: exit);
    final walkingRouteStart = _walkingRouteStart;
    final distanceMeters = walkingRouteStart == null || mapTarget == null
        ? null
        : _coordinateDistanceMeters(
            fromLatitude: walkingRouteStart.latitude,
            fromLongitude: walkingRouteStart.longitude,
            toLatitude: mapTarget.target.latitude,
            toLongitude: mapTarget.target.longitude,
          );

    return Card(
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
            Semantics(
              container: true,
              label: exit.semanticLabel,
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exit.name,
                      style: textTheme.titleMedium?.copyWith(
                        color: EasySubwayAccessibleColors.text,
                        fontWeight: FontWeight.w700,
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
                    if (exit.lastVerifiedAt.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _StationDetailInfoRow(
                        icon: Icons.verified_outlined,
                        text:
                            '최근 확인 ${stationVerifiedRelativeLabel(exit.lastVerifiedAt)}',
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (mapTarget?.usesStationFallback ?? false) ...[
              const SizedBox(height: 8),
              const _StationDetailInfoRow(
                icon: Icons.info_outline,
                text: '출구 좌표가 없어 역 위치 기준으로 안내합니다.',
              ),
            ],
            if (distanceMeters != null) ...[
              const SizedBox(height: 8),
              _StationDetailInfoRow(
                icon: Icons.straighten,
                text: _exitDistanceLabel(
                  distanceMeters,
                  usesStationFallback: mapTarget!.usesStationFallback,
                ),
              ),
            ],
            if (_locationMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: _StationDetailInfoRow(
                  icon: Icons.info_outline,
                  text: _locationMessage,
                ),
              ),
            ],
            if (mapTarget != null) ...[
              const SizedBox(height: 12),
              Semantics(
                container: true,
                button: true,
                label: mapTarget.usesStationFallback
                    ? '${exit.name} 카카오맵에서 보기, 출구 좌표가 없어 역 위치 기준으로 새 앱이 열립니다'
                    : '${exit.name} 카카오맵에서 보기, 새 앱이 열립니다',
                onTap: () => _openExitMap(context),
                child: SizedBox(
                  width: double.infinity,
                  child: ExcludeSemantics(
                    child: OutlinedButton.icon(
                      key: Key('stationExitMapButton-${exit.id}'),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('카카오맵에서 보기'),
                      onPressed: () => _openExitMap(context),
                    ),
                  ),
                ),
              ),
            ],
            if (mapTarget != null && widget.locationProvider != null) ...[
              const SizedBox(height: 8),
              Semantics(
                container: true,
                button: true,
                enabled: !_isLoadingLocation,
                label: mapTarget.usesStationFallback
                    ? '${exit.name} 역 위치 기준 직선거리 보기'
                    : '${exit.name}까지 직선거리 보기',
                onTap: _isLoadingLocation ? null : _loadCurrentLocationForExit,
                child: SizedBox(
                  width: double.infinity,
                  child: ExcludeSemantics(
                    child: OutlinedButton.icon(
                      key: Key('stationExitDistanceButton-${exit.id}'),
                      icon: _isLoadingLocation
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.near_me_outlined),
                      label: Text(
                        _isLoadingLocation
                            ? '현재 위치 확인 중'
                            : mapTarget.usesStationFallback
                            ? '역까지 거리 보기'
                            : '출구까지 거리 보기',
                      ),
                      onPressed: _isLoadingLocation
                          ? null
                          : _loadCurrentLocationForExit,
                    ),
                  ),
                ),
              ),
            ],
            if (mapTarget != null && walkingRouteStart != null) ...[
              const SizedBox(height: 8),
              Semantics(
                container: true,
                button: true,
                enabled: !_isOpeningWalkingRoute,
                label: mapTarget.usesStationFallback
                    ? '${exit.name} 역 위치 기준 카카오맵 도보 길안내, 현재 위치와 역 좌표만 사용합니다'
                    : '${exit.name}까지 카카오맵 도보 길안내, 현재 위치와 출구 좌표만 사용합니다',
                onTap: _isOpeningWalkingRoute
                    ? null
                    : () => _openWalkingRoute(context),
                child: SizedBox(
                  width: double.infinity,
                  child: ExcludeSemantics(
                    child: FilledButton.icon(
                      key: Key('stationExitWalkingRouteButton-${exit.id}'),
                      icon: _isOpeningWalkingRoute
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.directions_walk),
                      label: Text(
                        _isOpeningWalkingRoute ? '길안내 여는 중' : '도보 길안내',
                      ),
                      onPressed: _isOpeningWalkingRoute
                          ? null
                          : () => _openWalkingRoute(context),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _loadCurrentLocationForExit() async {
    if (_isLoadingLocation) {
      return;
    }
    final provider = widget.locationProvider;
    if (provider == null) {
      return;
    }
    setState(() {
      _isLoadingLocation = true;
      _locationMessage = '';
    });
    try {
      await _loadUsableCurrentLocationForExit();
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
      }
    }
  }

  Future<CurrentLocation?> _loadUsableCurrentLocationForExit() async {
    final provider = widget.locationProvider;
    if (provider == null) {
      return null;
    }
    try {
      final location = await provider.currentLocation();
      final blockedMessage = _exitWalkingLocationBlockedMessage(location);
      if (!mounted) {
        return null;
      }
      if (blockedMessage != null) {
        setState(() {
          _walkingRouteStart = null;
          _locationMessage = blockedMessage;
        });
        return null;
      }
      setState(() {
        _walkingRouteStart = location;
        _locationMessage = '';
      });
      return location;
    } on CurrentLocationException catch (error) {
      if (!mounted) {
        return null;
      }
      setState(() {
        _walkingRouteStart = null;
        _locationMessage = _exitWalkingLocationExceptionMessage(error);
      });
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '출구 도보 길안내 현재 위치 확인 중 예외가 발생했습니다.',
      );
      if (!mounted) {
        return null;
      }
      setState(() {
        _walkingRouteStart = null;
        _locationMessage = '현재 위치를 확인하지 못했어요.';
      });
    }
    return null;
  }

  Future<void> _openExitMap(BuildContext context) async {
    final mapTarget = _stationExitMapTarget(
      station: widget.station,
      exit: widget.exit,
    );
    if (mapTarget == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final result = await widget.mapLauncher.openLook(mapTarget.target);
    if (!context.mounted) {
      return;
    }
    final message = switch (result) {
      KakaoMapLaunchResult.app || KakaoMapLaunchResult.web => '카카오맵을 열었습니다.',
      KakaoMapLaunchResult.copied => '좌표를 복사했습니다. 지도 앱에서 붙여넣어 주세요.',
      KakaoMapLaunchResult.failed => '지도 앱을 열지 못했어요. 잠시 후 다시 시도해 주세요.',
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openWalkingRoute(BuildContext context) async {
    if (_isOpeningWalkingRoute || _isLoadingLocation) {
      return;
    }
    final mapTarget = _stationExitMapTarget(
      station: widget.station,
      exit: widget.exit,
    );
    if (mapTarget == null) {
      return;
    }
    setState(() {
      _isOpeningWalkingRoute = true;
      _locationMessage = '';
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final start = await _loadUsableCurrentLocationForExit();
      if (!mounted || start == null) {
        return;
      }
      final result = await widget.mapLauncher.openWalkingRoute(
        KakaoWalkingRouteTarget(
          start: KakaoMapPoint(
            latitude: start.latitude,
            longitude: start.longitude,
          ),
          end: mapTarget.target,
        ),
      );
      if (!mounted) {
        return;
      }
      final message = switch (result) {
        KakaoMapLaunchResult.app ||
        KakaoMapLaunchResult.web => '카카오맵 도보 길안내를 열었습니다.',
        KakaoMapLaunchResult.copied =>
          mapTarget.usesStationFallback
              ? '역 좌표를 복사했습니다. 지도 앱에서 붙여넣어 주세요.'
              : '출구 좌표를 복사했습니다. 지도 앱에서 붙여넣어 주세요.',
        KakaoMapLaunchResult.failed => '도보 길안내를 열지 못했어요. 잠시 후 다시 시도해 주세요.',
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _isOpeningWalkingRoute = false);
      }
    }
  }
}

String? _exitWalkingLocationBlockedMessage(CurrentLocation location) {
  return switch (location.qualityStatus()) {
    CurrentLocationQualityStatus.freshPrecise => null,
    CurrentLocationQualityStatus.unavailable =>
      '현재 위치 정확도 정보를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.',
    CurrentLocationQualityStatus.stale =>
      '현재 위치가 오래되어 출구까지 안내하기 어려워요. 다시 확인해 주세요.',
    CurrentLocationQualityStatus.coarse =>
      '현재 위치 정확도가 낮아 출구까지 안내하기 어려워요. 정확한 위치 권한을 허용해 주세요.',
    CurrentLocationQualityStatus.mocked => '모의 위치는 출구 도보 길안내에 사용할 수 없어요.',
  };
}

String _exitWalkingLocationExceptionMessage(CurrentLocationException error) {
  if (error.message == _currentLocationDisabledMessage) {
    return '휴대전화의 위치 기능을 켜 주세요. 출구까지 안내하는 데 필요합니다.';
  }
  return error.message;
}

class _StationExitMapTarget {
  const _StationExitMapTarget({
    required this.target,
    required this.usesStationFallback,
  });

  final KakaoMapTarget target;
  final bool usesStationFallback;
}

_StationExitMapTarget? _stationExitMapTarget({
  required StationDetail station,
  required StationExitInfo exit,
}) {
  final exitLatitude = exit.latitude;
  final exitLongitude = exit.longitude;
  if (exitLatitude != null && exitLongitude != null) {
    return _StationExitMapTarget(
      target: KakaoMapTarget(
        label: '${station.nameKo}역 ${exit.name}',
        latitude: exitLatitude,
        longitude: exitLongitude,
      ),
      usesStationFallback: false,
    );
  }

  final stationLatitude = station.latitude;
  final stationLongitude = station.longitude;
  if (stationLatitude == null || stationLongitude == null) {
    return null;
  }
  return _StationExitMapTarget(
    target: KakaoMapTarget(
      label: '${station.nameKo}역',
      latitude: stationLatitude,
      longitude: stationLongitude,
    ),
    usesStationFallback: true,
  );
}

String _exitDistanceLabel(
  int distanceMeters, {
  required bool usesStationFallback,
}) {
  final target = usesStationFallback ? '역까지 ' : '';
  if (distanceMeters < 1000) {
    return '현재 위치에서 $target직선 ${distanceMeters}m';
  }
  return '현재 위치에서 $target직선 ${(distanceMeters / 1000).toStringAsFixed(1)}km';
}

int _coordinateDistanceMeters({
  required double fromLatitude,
  required double fromLongitude,
  required double toLatitude,
  required double toLongitude,
}) {
  const earthRadiusMeters = 6371000.0;
  final fromLatRadians = _degreesToRadians(fromLatitude);
  final toLatRadians = _degreesToRadians(toLatitude);
  final deltaLat = _degreesToRadians(toLatitude - fromLatitude);
  final deltaLon = _degreesToRadians(toLongitude - fromLongitude);
  final haversine =
      math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
      math.cos(fromLatRadians) *
          math.cos(toLatRadians) *
          math.sin(deltaLon / 2) *
          math.sin(deltaLon / 2);
  return (earthRadiusMeters *
          2 *
          math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine)))
      .round();
}

double _degreesToRadians(double degrees) => degrees * math.pi / 180;

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
                // 정상 시설은 필 없이 조용히 표시하고, 문제(고장·공사)일 때만
                // 상태 필 하나만 노출한다. 시설 종류는 이름에 이미 포함되고,
                // '이용 가능'='정상' 중복과 종류 필은 제거한다.
                if (facility.needsAttention) ...[
                  const SizedBox(height: 10),
                  _StationDetailTextPill(text: facility.statusTitle),
                ],
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
                const SizedBox(height: 8),
                // 상용 리스트 항목처럼 카드 전체 탭으로 상세에 들어가고(우측 ›로
                // 암시), 보조 액션 '시설 알려주기'는 텍스트 버튼 수준으로 낮춘다.
                // 카드 탭과 중복되던 '상세 보기' 텍스트는 제거한다.
                Row(
                  children: [
                    Semantics(
                      container: true,
                      label: '${facility.name} 시설 알려주기',
                      button: true,
                      onTap: onReportTap,
                      child: ExcludeSemantics(
                        child: TextButton.icon(
                          key: Key('facilityReportButton-${facility.id}'),
                          onPressed: onReportTap,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                          icon: const Icon(Icons.report_outlined, size: 20),
                          label: const Text('시설 알려주기'),
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.chevron_right,
                      color: EasySubwayAccessibleColors.mutedText,
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    facility.layoutSummaryIcon,
                    color: EasySubwayAccessibleColors.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${station.nameKo}역',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: EasySubwayAccessibleColors.mutedText,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          facility.name,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: EasySubwayAccessibleColors.text,
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
            const SizedBox(height: 16),
            Container(
              key: Key('facilityDetailStatusNotice-${facility.id}'),
              decoration: BoxDecoration(
                color: EasySubwayAccessibleColors.surface,
                borderRadius: _stationDetailFacilityCardRadius,
                border: Border.all(color: EasySubwayAccessibleColors.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 4, color: statusIconColor),
                    Expanded(
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: statusIconColor,
                                          fontWeight: FontWeight.w700,
                                          height: 1.25,
                                        ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    facilityStatusDisplayLabel(
                                      statusLabel: facility.statusLabel,
                                      severityLabel: facility.severityLabel,
                                    ),
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
                                  const SizedBox(height: 3),
                                  Text(
                                    _facilityDetailStatusDescription(facility),
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
    return '연결 위치를 확인하고 있어요';
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
        : EasySubwayAccessibleColors.amber;

    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: EasySubwayAccessibleColors.text,
              fontWeight: FontWeight.w700,
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
    // 유형·품질 라벨은 상태 의미가 없으므로 틴트 필 대신 중립 아웃라인으로.
    return Container(
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.surface,
        borderRadius: _stationDetailInfoCardRadius,
        border: Border.all(color: EasySubwayAccessibleColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: EasySubwayAccessibleColors.secondaryText,
            fontWeight: FontWeight.w700,
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
