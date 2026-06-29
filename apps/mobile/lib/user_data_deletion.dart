import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'auth_headers.dart';
import 'core/database/user/user_database.dart';
import 'core/network/api_client.dart';
import 'mobile_error_reporter.dart';

const userDataDeletionErrorMessage = '데이터 삭제를 완료하지 못했어요. 잠시 후 다시 시도해 주세요.';
const _userDataDeletionTimeout = defaultApiTimeout;

abstract class UserDataDeletionRepository {
  Future<UserDataDeletionResult> deleteCurrentUserData();
}

class UserDataDeletionApiRepository implements UserDataDeletionRepository {
  UserDataDeletionApiRepository({
    required this.baseUri,
    required this.authProvider,
    this.refreshExistingAuthorization,
    ApiClient? apiClient,
    HttpClient? httpClient,
  }) : assert(apiClient == null || httpClient == null),
       _apiClient =
           apiClient ?? ApiClient(baseUri: baseUri, httpClient: httpClient);

  final Uri baseUri;
  final AuthorizationHeaderProvider authProvider;
  final Future<bool> Function(String authorizationHeader)?
  refreshExistingAuthorization;
  final ApiClient _apiClient;

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
      final authorizationHeader = await authProvider
          .authorizationHeader()
          .timeout(_userDataDeletionTimeout);
      final response = await _apiClient.deleteJson(
        '/api/v1/me',
        headers: authorizationHeader == null
            ? const {}
            : {HttpHeaders.authorizationHeader: authorizationHeader},
      );

      if (response.isUnauthorized &&
          authorizationHeader != null &&
          attempt == 0) {
        final refreshedAuthorization = await _refreshExistingAuthorization(
          authorizationHeader,
        ).timeout(_userDataDeletionTimeout);
        if (!refreshedAuthorization) {
          throw const UserDataDeletionException(userDataDeletionErrorMessage);
        }
        continue;
      }

      if (!response.isOk) {
        throw const UserDataDeletionException(userDataDeletionErrorMessage);
      }

      return UserDataDeletionResult.fromResponseJson(response.jsonBody);
    }
    throw const UserDataDeletionException(userDataDeletionErrorMessage);
  }

  Future<bool> _refreshExistingAuthorization(String authorizationHeader) async {
    final refresh = refreshExistingAuthorization;
    if (refresh == null) {
      return false;
    }
    return refresh(authorizationHeader);
  }
}

class UserDataDeletionLocalRepository implements UserDataDeletionRepository {
  UserDataDeletionLocalRepository({required this.userDatabase});

  final UserDatabase userDatabase;

  @override
  Future<UserDataDeletionResult> deleteCurrentUserData() async {
    try {
      late final int deletedFavoriteStationCount;
      late final int deletedFavoriteFacilityCount;
      late final int deletedFavoriteRouteCount;
      late final int deletedAppPreferenceCount;
      late final int deletedReportReceiptCount;
      late final int deletedReportDraftCount;
      await userDatabase.transaction(() async {
        deletedFavoriteStationCount = await userDatabase
            .delete(userDatabase.favoriteStations)
            .go();
        deletedFavoriteFacilityCount = await userDatabase
            .delete(userDatabase.favoriteFacilities)
            .go();
        deletedFavoriteRouteCount = await userDatabase
            .delete(userDatabase.favoriteRoutes)
            .go();
        await userDatabase.delete(userDatabase.searchHistory).go();
        deletedAppPreferenceCount = await userDatabase
            .delete(userDatabase.appPreferences)
            .go();
        deletedReportReceiptCount = await userDatabase
            .delete(userDatabase.reportReceipts)
            .go();
        deletedReportDraftCount = await userDatabase
            .delete(userDatabase.reportDrafts)
            .go();
      });

      return UserDataDeletionResult(
        userId: 'local-user',
        deletedFavoriteStationCount: deletedFavoriteStationCount,
        deletedFavoriteFacilityCount: deletedFavoriteFacilityCount,
        deletedFavoriteRouteCount: deletedFavoriteRouteCount,
        anonymizedRouteFeedbackCount: 0,
        notificationSettingsDeleted: deletedAppPreferenceCount > 0,
        deletedRegisteredDeviceCount: 0,
        deletedPushNotificationCount: 0,
        mobilityProfileDeleted: false,
        anonymizedReportCount:
            deletedReportReceiptCount + deletedReportDraftCount,
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '로컬 사용자 데이터 삭제 처리 중 예외가 발생했습니다.',
      );
      throw const UserDataDeletionException(userDataDeletionErrorMessage);
    }
  }
}

class UserDataDeletionCompositeRepository
    implements UserDataDeletionRepository {
  UserDataDeletionCompositeRepository({
    required this.remoteRepository,
    required this.localRepository,
  });

  final UserDataDeletionRepository remoteRepository;
  final UserDataDeletionRepository localRepository;

  @override
  Future<UserDataDeletionResult> deleteCurrentUserData() async {
    final remoteResult = await remoteRepository.deleteCurrentUserData();
    final localResult = await localRepository.deleteCurrentUserData();
    return UserDataDeletionResult(
      userId: remoteResult.userId,
      deletedFavoriteStationCount:
          remoteResult.deletedFavoriteStationCount +
          localResult.deletedFavoriteStationCount,
      deletedFavoriteFacilityCount:
          remoteResult.deletedFavoriteFacilityCount +
          localResult.deletedFavoriteFacilityCount,
      deletedFavoriteRouteCount:
          remoteResult.deletedFavoriteRouteCount +
          localResult.deletedFavoriteRouteCount,
      anonymizedRouteFeedbackCount:
          remoteResult.anonymizedRouteFeedbackCount +
          localResult.anonymizedRouteFeedbackCount,
      notificationSettingsDeleted:
          remoteResult.notificationSettingsDeleted ||
          localResult.notificationSettingsDeleted,
      deletedRegisteredDeviceCount:
          remoteResult.deletedRegisteredDeviceCount +
          localResult.deletedRegisteredDeviceCount,
      deletedPushNotificationCount:
          remoteResult.deletedPushNotificationCount +
          localResult.deletedPushNotificationCount,
      mobilityProfileDeleted:
          remoteResult.mobilityProfileDeleted ||
          localResult.mobilityProfileDeleted,
      anonymizedReportCount:
          remoteResult.anonymizedReportCount +
          localResult.anonymizedReportCount,
    );
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
  });

  factory UserDataDeletionResult.fromResponseBody(String body) {
    final decoded = jsonDecode(body);
    return UserDataDeletionResult.fromResponseJson(decoded);
  }

  factory UserDataDeletionResult.fromResponseJson(Object? decoded) {
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
