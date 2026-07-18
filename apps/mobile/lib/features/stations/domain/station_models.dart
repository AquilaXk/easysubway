import '../../../facility_status.dart';
import 'station_line.dart';

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

enum StationTimetableDayType {
  weekday('평일'),
  saturday('토요일'),
  sundayHoliday('일요일·공휴일');

  const StationTimetableDayType(this.label);

  final String label;
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
    this.servicePattern = 'LOCAL',
    this.serviceClass = 'SUBWAY',
  });

  final String directionName;
  final int seconds;

  /// 운행종별(예: `LOCAL`·`EXPRESS`). 선택 컨트롤이 아니라 실제 운행 정보다.
  final String servicePattern;

  /// 운행 클래스(예: `SUBWAY`).
  final String serviceClass;

  /// 지하철 급행 운행 여부. 이 값이 참일 때만 `급행` 배지를 노출한다.
  bool get isExpress => serviceClass == 'SUBWAY' && servicePattern == 'EXPRESS';

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
    final expressLabel = isExpress ? '급행, ' : '';
    return '$directionName, $expressLabel$prefix'
        '${hour.toString().padLeft(2, '0')}시 '
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
      return '노선 미확인';
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
      return '노선 미확인';
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
      return '노선 미확인';
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
    return hasElevatorConnection ? '엘리베이터 연결' : '엘리베이터 연결 미확인';
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
      'NEEDS_CHECK' => '상태 미확인',
      _ => '상태 미확인',
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
