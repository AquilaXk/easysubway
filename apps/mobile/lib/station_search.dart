import 'dart:io';

import 'package:flutter/foundation.dart';

export 'features/stations/application/station_detail_controller.dart';
export 'features/stations/application/station_search_controller.dart';
export 'features/stations/data/current_location_provider.dart';
export 'features/stations/domain/station_line.dart';
export 'features/stations/domain/station_models.dart';
export 'features/stations/domain/station_repositories.dart';
export 'features/stations/presentation/station_recent_search_section.dart';
export 'features/stations/presentation/station_search_body.dart';
export 'features/stations/presentation/station_timetable_screen.dart';

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
