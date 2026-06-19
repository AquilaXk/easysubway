import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/auth_headers.dart';
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
              'anonymousCredentialsDeleted': true,
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
    expect(result.anonymousCredentialsDeleted, isTrue);
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
          '데이터 삭제를 완료하지 못했습니다. 잠시 후 다시 시도해 주세요.',
        ),
      ),
    );
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
      'anonymousCredentialsDeleted': true,
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

  @override
  Future<String?> authorizationHeader() async => header;

  @override
  Future<void> invalidateAuthorization() async {
    invalidateCount++;
  }

  Future<bool> refreshExistingAuthorization() async {
    refreshCount++;
    if (!refreshResult) {
      return false;
    }
    header = refreshedHeader;
    return true;
  }
}
