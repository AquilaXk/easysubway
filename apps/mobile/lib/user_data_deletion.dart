import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'auth_headers.dart';
import 'mobile_error_reporter.dart';

const userDataDeletionErrorMessage = '데이터 삭제를 완료하지 못했습니다. 잠시 후 다시 시도해 주세요.';
const _userDataDeletionTimeout = Duration(seconds: 8);

abstract class UserDataDeletionRepository {
  Future<UserDataDeletionResult> deleteCurrentUserData();
}

class UserDataDeletionApiRepository implements UserDataDeletionRepository {
  UserDataDeletionApiRepository({
    required this.baseUri,
    required this.authProvider,
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  final Uri baseUri;
  final AuthorizationHeaderProvider authProvider;
  final HttpClient _httpClient;

  @override
  Future<UserDataDeletionResult> deleteCurrentUserData() async {
    try {
      return await _deleteCurrentUserDataWithAuthorizationRetry();
    } on UserDataDeletionException {
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '사용자 데이터 삭제 API 응답 처리 중 예외가 발생했습니다.',
      );
      throw const UserDataDeletionException(userDataDeletionErrorMessage);
    }
  }

  Future<UserDataDeletionResult>
  _deleteCurrentUserDataWithAuthorizationRetry() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final request = await _httpClient
          .deleteUrl(baseUri.resolve('/api/v1/me'))
          .timeout(_userDataDeletionTimeout);
      final authorizationHeader = await authProvider
          .authorizationHeader()
          .timeout(_userDataDeletionTimeout);
      if (authorizationHeader != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          authorizationHeader,
        );
      }

      final response = await request.close().timeout(_userDataDeletionTimeout);
      final body = await utf8
          .decodeStream(response)
          .timeout(_userDataDeletionTimeout);

      if (response.statusCode == HttpStatus.unauthorized &&
          authorizationHeader != null &&
          attempt == 0) {
        await authProvider.invalidateAuthorization().timeout(
          _userDataDeletionTimeout,
        );
        continue;
      }

      if (response.statusCode != HttpStatus.ok) {
        throw const UserDataDeletionException(userDataDeletionErrorMessage);
      }

      return UserDataDeletionResult.fromResponseBody(body);
    }
    throw const UserDataDeletionException(userDataDeletionErrorMessage);
  }
}

class UserDataDeletionResult {
  const UserDataDeletionResult({
    required this.userId,
    required this.deletedFavoriteStationCount,
    required this.deletedFavoriteFacilityCount,
    required this.deletedFavoriteRouteCount,
    required this.anonymizedRouteFeedbackCount,
    required this.notificationSettingsDeleted,
    required this.deletedRegisteredDeviceCount,
    required this.deletedPushNotificationCount,
    required this.mobilityProfileDeleted,
    required this.anonymizedReportCount,
    required this.anonymousCredentialsDeleted,
  });

  factory UserDataDeletionResult.fromResponseBody(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?> || decoded['success'] != true) {
      throw const UserDataDeletionException(userDataDeletionErrorMessage);
    }
    final data = decoded['data'];
    if (data is! Map<String, Object?>) {
      throw const UserDataDeletionException(userDataDeletionErrorMessage);
    }
    return UserDataDeletionResult.fromJson(data);
  }

  factory UserDataDeletionResult.fromJson(Map<String, Object?> json) {
    return UserDataDeletionResult(
      userId: _requiredDeletionString(json, 'userId'),
      deletedFavoriteStationCount: _requiredDeletionInt(
        json,
        'deletedFavoriteStationCount',
      ),
      deletedFavoriteFacilityCount: _requiredDeletionInt(
        json,
        'deletedFavoriteFacilityCount',
      ),
      deletedFavoriteRouteCount: _requiredDeletionInt(
        json,
        'deletedFavoriteRouteCount',
      ),
      anonymizedRouteFeedbackCount: _requiredDeletionInt(
        json,
        'anonymizedRouteFeedbackCount',
      ),
      notificationSettingsDeleted: _requiredDeletionBool(
        json,
        'notificationSettingsDeleted',
      ),
      deletedRegisteredDeviceCount: _requiredDeletionInt(
        json,
        'deletedRegisteredDeviceCount',
      ),
      deletedPushNotificationCount: _requiredDeletionInt(
        json,
        'deletedPushNotificationCount',
      ),
      mobilityProfileDeleted: _requiredDeletionBool(
        json,
        'mobilityProfileDeleted',
      ),
      anonymizedReportCount: _requiredDeletionInt(
        json,
        'anonymizedReportCount',
      ),
      anonymousCredentialsDeleted: _requiredDeletionBool(
        json,
        'anonymousCredentialsDeleted',
      ),
    );
  }

  final String userId;
  final int deletedFavoriteStationCount;
  final int deletedFavoriteFacilityCount;
  final int deletedFavoriteRouteCount;
  final int anonymizedRouteFeedbackCount;
  final bool notificationSettingsDeleted;
  final int deletedRegisteredDeviceCount;
  final int deletedPushNotificationCount;
  final bool mobilityProfileDeleted;
  final int anonymizedReportCount;
  final bool anonymousCredentialsDeleted;
}

class UserDataDeletionException implements Exception {
  const UserDataDeletionException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _requiredDeletionString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw const UserDataDeletionException(userDataDeletionErrorMessage);
  }
  return value.trim();
}

int _requiredDeletionInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw const UserDataDeletionException(userDataDeletionErrorMessage);
  }
  return value;
}

bool _requiredDeletionBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw const UserDataDeletionException(userDataDeletionErrorMessage);
  }
  return value;
}
