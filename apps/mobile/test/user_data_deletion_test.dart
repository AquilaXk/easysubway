import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/auth_headers.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/user_data_deletion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('사용자 데이터 삭제 API 저장소는 인증 헤더로 DELETE /api/v1/me를 호출한다', () async {
    late String requestedMethod;
    late Uri requestedUri;
    late String? authorizationHeader;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      requestedMethod = request.method;
      requestedUri = request.uri;
      authorizationHeader = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': {
              'userId': 'anonymous-user-1',
              'deletedFavoriteStationCount': 1,
              'deletedFavoriteFacilityCount': 2,
              'deletedFavoriteRouteCount': 3,
              'anonymizedRouteFeedbackCount': 4,
              'notificationSettingsDeleted': true,
              'deletedRegisteredDeviceCount': 5,
              'deletedPushNotificationCount': 6,
              'mobilityProfileDeleted': true,
              'anonymizedReportCount': 7,
            },
          }),
        )
        ..close();
    });

    final repository = UserDataDeletionApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: const FixedAuthorizationHeaderProvider(
        'Bearer access-token-1',
      ),
    );

    final result = await repository.deleteCurrentUserData();

    expect(requestedMethod, 'DELETE');
    expect(requestedUri.path, '/api/v1/me');
    expect(authorizationHeader, 'Bearer access-token-1');
    expect(result.userId, 'anonymous-user-1');
    expect(result.deletedFavoriteStationCount, 1);
    expect(result.deletedFavoriteFacilityCount, 2);
    expect(result.deletedFavoriteRouteCount, 3);
    expect(result.anonymizedRouteFeedbackCount, 4);
    expect(result.notificationSettingsDeleted, isTrue);
    expect(result.deletedRegisteredDeviceCount, 5);
    expect(result.deletedPushNotificationCount, 6);
    expect(result.mobilityProfileDeleted, isTrue);
    expect(result.anonymizedReportCount, 7);
  });

  test('사용자 데이터 삭제 API 저장소는 기존 인증 갱신 성공 시 삭제를 한 번 재시도한다', () async {
    var requestCount = 0;
    final authorizationHeaders = <String?>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      requestCount++;
      authorizationHeaders.add(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      if (requestCount == 1) {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..write('expired')
          ..close();
        return;
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(_successfulDeletionBody())
        ..close();
    });

    final authProvider = RefreshingAuthorizationHeaderProvider(
      header: 'Bearer stale-access-token',
      refreshedHeader: 'Bearer fresh-access-token',
      refreshResult: true,
    );
    final repository = UserDataDeletionApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: authProvider,
      refreshExistingAuthorization: authProvider.refreshExistingAuthorization,
    );

    final result = await repository.deleteCurrentUserData();

    expect(result.userId, 'anonymous-user-1');
    expect(requestCount, 2);
    expect(authorizationHeaders, [
      'Bearer stale-access-token',
      'Bearer fresh-access-token',
    ]);
    expect(authProvider.refreshCount, 1);
    expect(authProvider.refreshedAuthorizationHeaders, [
      'Bearer stale-access-token',
    ]);
    expect(authProvider.invalidateCount, 0);
  });

  test('사용자 데이터 삭제 API 저장소는 기존 인증 갱신 실패 시 새 사용자 삭제로 처리하지 않는다', () async {
    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      requestCount++;
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..write('expired')
        ..close();
    });

    final authProvider = RefreshingAuthorizationHeaderProvider(
      header: 'Bearer stale-access-token',
      refreshedHeader: 'Bearer new-user-access-token',
      refreshResult: false,
    );
    final repository = UserDataDeletionApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: authProvider,
      refreshExistingAuthorization: authProvider.refreshExistingAuthorization,
    );

    await expectLater(
      repository.deleteCurrentUserData(),
      throwsA(isA<UserDataDeletionException>()),
    );
    expect(requestCount, 1);
    expect(authProvider.refreshCount, 1);
    expect(authProvider.refreshedAuthorizationHeaders, [
      'Bearer stale-access-token',
    ]);
    expect(authProvider.invalidateCount, 0);
  });

  test('사용자 데이터 삭제 API 저장소는 실패 응답에서 쉬운 오류를 던진다', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write('server error')
        ..close();
    });

    final repository = UserDataDeletionApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: const FixedAuthorizationHeaderProvider(
        'Bearer access-token-1',
      ),
    );

    await expectLater(
      repository.deleteCurrentUserData(),
      throwsA(
        isA<UserDataDeletionException>().having(
          (error) => error.message,
          'message',
          '정보 삭제를 완료하지 못했어요. 잠시 후 다시 시도해 주세요.',
        ),
      ),
    );
  });

  test('로컬 사용자 데이터 삭제 저장소는 user DB 개인 데이터를 비운다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final now = DateTime.utc(2026, 6, 19, 9);
    await userDatabase
        .into(userDatabase.favoriteStations)
        .insert(
          user_db.FavoriteStationsCompanion.insert(
            stationId: 'station-sangnoksu',
            addedAt: now,
          ),
        );
    await userDatabase
        .into(userDatabase.favoriteFacilities)
        .insert(
          user_db.FavoriteFacilitiesCompanion.insert(
            facilityId: 'facility-sangnoksu-elevator-1',
            stationId: 'station-sangnoksu',
            addedAt: now,
          ),
        );
    await userDatabase
        .into(userDatabase.favoriteRoutes)
        .insert(
          user_db.FavoriteRoutesCompanion.insert(
            routeId: 'local-station-sangnoksu-station-sadang::SENIOR',
            originStationId: 'station-sangnoksu',
            destinationStationId: 'station-sadang',
            mobilityProfile: 'SENIOR',
            addedAt: now,
          ),
        );
    await userDatabase
        .into(userDatabase.searchHistory)
        .insert(
          user_db.SearchHistoryCompanion.insert(query: '상록수', searchedAt: now),
        );
    await userDatabase
        .into(userDatabase.appPreferences)
        .insert(
          user_db.AppPreferencesCompanion.insert(
            key: 'notification_settings',
            value: '{}',
            updatedAt: now,
          ),
        );
    await userDatabase
        .into(userDatabase.reportReceipts)
        .insert(
          user_db.ReportReceiptsCompanion.insert(
            receiptId: 'receipt-1',
            status: 'SUBMITTED',
            createdAt: now,
          ),
        );
    await userDatabase
        .into(userDatabase.reportDrafts)
        .insert(
          user_db.ReportDraftsCompanion.insert(
            draftId: 'draft-1',
            payloadJson: '{}',
            updatedAt: now,
          ),
        );
    final repository = UserDataDeletionLocalRepository(
      userDatabase: userDatabase,
    );

    final result = await repository.deleteCurrentUserData();

    expect(result.userId, 'local-user');
    expect(result.deletedFavoriteStationCount, 1);
    expect(result.deletedFavoriteFacilityCount, 1);
    expect(result.deletedFavoriteRouteCount, 1);
    expect(result.notificationSettingsDeleted, isTrue);
    expect(result.anonymizedReportCount, 2);
    expect(
      await userDatabase.select(userDatabase.favoriteStations).get(),
      isEmpty,
    );
    expect(
      await userDatabase.select(userDatabase.favoriteFacilities).get(),
      isEmpty,
    );
    expect(
      await userDatabase.select(userDatabase.favoriteRoutes).get(),
      isEmpty,
    );
    expect(
      await userDatabase.select(userDatabase.searchHistory).get(),
      isEmpty,
    );
    expect(
      await userDatabase.select(userDatabase.appPreferences).get(),
      isEmpty,
    );
    expect(
      await userDatabase.select(userDatabase.reportReceipts).get(),
      isEmpty,
    );
    expect(await userDatabase.select(userDatabase.reportDrafts).get(), isEmpty);
  });

  test('합성 사용자 데이터 삭제 저장소는 서버 삭제 성공 후 로컬 삭제를 실행한다', () async {
    final calls = <String>[];
    final remoteRepository = RecordingUserDataDeletionRepository(
      label: 'remote',
      calls: calls,
      result: const UserDataDeletionResult(
        userId: 'anonymous-user-1',
        deletedFavoriteStationCount: 1,
        deletedFavoriteFacilityCount: 1,
        deletedFavoriteRouteCount: 1,
        anonymizedRouteFeedbackCount: 2,
        notificationSettingsDeleted: false,
        deletedRegisteredDeviceCount: 1,
        deletedPushNotificationCount: 1,
        mobilityProfileDeleted: true,
        anonymizedReportCount: 3,
      ),
    );
    final localRepository = RecordingUserDataDeletionRepository(
      label: 'local',
      calls: calls,
      result: const UserDataDeletionResult(
        userId: 'local-user',
        deletedFavoriteStationCount: 4,
        deletedFavoriteFacilityCount: 5,
        deletedFavoriteRouteCount: 6,
        anonymizedRouteFeedbackCount: 0,
        notificationSettingsDeleted: true,
        deletedRegisteredDeviceCount: 0,
        deletedPushNotificationCount: 0,
        mobilityProfileDeleted: false,
        anonymizedReportCount: 1,
      ),
    );
    final repository = UserDataDeletionCompositeRepository(
      remoteRepository: remoteRepository,
      localRepository: localRepository,
    );

    final result = await repository.deleteCurrentUserData();

    expect(calls, ['remote', 'local']);
    expect(result.userId, 'anonymous-user-1');
    expect(result.deletedFavoriteStationCount, 5);
    expect(result.deletedFavoriteFacilityCount, 6);
    expect(result.deletedFavoriteRouteCount, 7);
    expect(result.anonymizedRouteFeedbackCount, 2);
    expect(result.notificationSettingsDeleted, isTrue);
    expect(result.deletedRegisteredDeviceCount, 1);
    expect(result.deletedPushNotificationCount, 1);
    expect(result.mobilityProfileDeleted, isTrue);
    expect(result.anonymizedReportCount, 4);
  });

  test('합성 사용자 데이터 삭제 저장소는 서버 삭제 실패 시 로컬 데이터를 유지한다', () async {
    final calls = <String>[];
    final remoteRepository = RecordingUserDataDeletionRepository(
      label: 'remote',
      calls: calls,
      error: const UserDataDeletionException(userDataDeletionErrorMessage),
    );
    final localRepository = RecordingUserDataDeletionRepository(
      label: 'local',
      calls: calls,
      result: const UserDataDeletionResult(
        userId: 'local-user',
        deletedFavoriteStationCount: 1,
        deletedFavoriteFacilityCount: 1,
        deletedFavoriteRouteCount: 1,
        anonymizedRouteFeedbackCount: 0,
        notificationSettingsDeleted: true,
        deletedRegisteredDeviceCount: 0,
        deletedPushNotificationCount: 0,
        mobilityProfileDeleted: false,
        anonymizedReportCount: 0,
      ),
    );
    final repository = UserDataDeletionCompositeRepository(
      remoteRepository: remoteRepository,
      localRepository: localRepository,
    );

    await expectLater(
      repository.deleteCurrentUserData(),
      throwsA(isA<UserDataDeletionException>()),
    );

    expect(calls, ['remote']);
  });
}

String _successfulDeletionBody() {
  return jsonEncode({
    'success': true,
    'data': {
      'userId': 'anonymous-user-1',
      'deletedFavoriteStationCount': 1,
      'deletedFavoriteFacilityCount': 2,
      'deletedFavoriteRouteCount': 3,
      'anonymizedRouteFeedbackCount': 4,
      'notificationSettingsDeleted': true,
      'deletedRegisteredDeviceCount': 5,
      'deletedPushNotificationCount': 6,
      'mobilityProfileDeleted': true,
      'anonymizedReportCount': 7,
    },
  });
}

class FixedAuthorizationHeaderProvider implements AuthorizationHeaderProvider {
  const FixedAuthorizationHeaderProvider(this.header);

  final String header;

  @override
  Future<String?> authorizationHeader() async => header;

  @override
  Future<void> invalidateAuthorization() async {}
}

class RefreshingAuthorizationHeaderProvider
    implements AuthorizationHeaderProvider {
  RefreshingAuthorizationHeaderProvider({
    required this.header,
    required this.refreshedHeader,
    required this.refreshResult,
  });

  String header;
  final String refreshedHeader;
  final bool refreshResult;
  int refreshCount = 0;
  int invalidateCount = 0;
  final refreshedAuthorizationHeaders = <String>[];

  @override
  Future<String?> authorizationHeader() async => header;

  @override
  Future<void> invalidateAuthorization() async {
    invalidateCount++;
  }

  Future<bool> refreshExistingAuthorization(String authorizationHeader) async {
    refreshCount++;
    refreshedAuthorizationHeaders.add(authorizationHeader);
    if (!refreshResult) {
      return false;
    }
    header = refreshedHeader;
    return true;
  }
}

class RecordingUserDataDeletionRepository
    implements UserDataDeletionRepository {
  RecordingUserDataDeletionRepository({
    required this.label,
    required this.calls,
    this.result,
    this.error,
  });

  final String label;
  final List<String> calls;
  final UserDataDeletionResult? result;
  final UserDataDeletionException? error;

  @override
  Future<UserDataDeletionResult> deleteCurrentUserData() async {
    calls.add(label);
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return result!;
  }
}
