import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/auth_headers.dart';
import 'package:easysubway_mobile/notification_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('기기 등록 API 저장소는 인증 헤더와 함께 플랫폼과 토큰을 보낸다', () async {
    late String requestedMethod;
    late Uri requestedUri;
    late String? authorizationHeader;
    late Map<String, Object?> requestBody;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      requestedMethod = request.method;
      requestedUri = request.uri;
      authorizationHeader = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      requestBody =
          jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': {
              'userId': 'anonymous-user-1',
              'platform': 'ANDROID',
              'deviceToken': 'android-device-token-1',
              'registeredAt': '2026-06-15T09:00:00',
            },
          }),
        );
      await request.response.close();
    });

    final repository = DeviceRegistrationApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: const BasicAuthorizationHeaderProvider(
        username: 'anonymous-user-1',
        password: 'user-test-password',
      ),
    );

    final registeredDevice = await repository.registerDevice(
      const DeviceRegistrationRequest(
        platform: DevicePlatform.android,
        deviceToken: ' android-device-token-1 ',
      ),
    );

    expect(requestedMethod, 'POST');
    expect(requestedUri.path, '/api/v1/devices');
    expect(
      authorizationHeader,
      'Basic ${base64Encode(utf8.encode('anonymous-user-1:user-test-password'))}',
    );
    expect(requestBody, {
      'platform': 'ANDROID',
      'deviceToken': 'android-device-token-1',
    });
    expect(registeredDevice.userId, 'anonymous-user-1');
    expect(registeredDevice.platform, DevicePlatform.android);
    expect(registeredDevice.deviceToken, 'android-device-token-1');
    expect(registeredDevice.registeredAt, '2026-06-15T09:00:00');
  });

  test('기기 등록 API 저장소는 인증 실패 시 인증을 지우고 한 번 재시도한다', () async {
    final authorizationHeaders = <String?>[];
    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      requestCount++;
      authorizationHeaders.add(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      await utf8.decodeStream(request);
      request.response.headers.contentType = ContentType.json;

      if (requestCount == 1) {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..write(jsonEncode({'success': false}));
        await request.response.close();
        return;
      }

      request.response
        ..statusCode = HttpStatus.ok
        ..write(
          jsonEncode({
            'success': true,
            'data': {
              'userId': 'anonymous-user-1',
              'platform': 'IOS',
              'deviceToken': 'ios-device-token-1',
              'registeredAt': '2026-06-15T09:05:00',
            },
          }),
        );
      await request.response.close();
    });

    final authProvider = RetryAuthorizationHeaderProvider();
    final repository = DeviceRegistrationApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: authProvider,
    );

    final registeredDevice = await repository.registerDevice(
      const DeviceRegistrationRequest(
        platform: DevicePlatform.ios,
        deviceToken: 'ios-device-token-1',
      ),
    );

    expect(registeredDevice.platform, DevicePlatform.ios);
    expect(authorizationHeaders, ['Basic stale-token', 'Basic fresh-token']);
    expect(authProvider.authorizationCount, 2);
    expect(authProvider.invalidateCount, 1);
  });

  test('기기 등록 API 저장소는 실패 응답을 쉬운 안내로 바꾼다', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      await utf8.decodeStream(request);
      request.response
        ..statusCode = HttpStatus.badRequest
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'success': false}));
      await request.response.close();
    });

    final repository = DeviceRegistrationApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: const NoAuthorizationHeaderProvider(),
    );

    await expectLater(
      repository.registerDevice(
        const DeviceRegistrationRequest(
          platform: DevicePlatform.android,
          deviceToken: 'android-device-token-1',
        ),
      ),
      throwsA(
        isA<NotificationSettingsException>().having(
          (error) => error.message,
          'message',
          '알림을 켜지 못했어요.',
        ),
      ),
    );
  });

  test('알림 설정 API 저장소는 인증 헤더와 함께 현재 설정을 요청한다', () async {
    late String? authorizationHeader;
    late Uri requestedUri;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
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
              'favoriteStationFacilityAlerts': true,
              'favoriteRouteFacilityAlerts': false,
              'reportStatusAlerts': true,
              'dataQualityAlerts': false,
              'updatedAt': '2026-06-14T09:00:00',
            },
          }),
        );
      await request.response.close();
    });

    final repository = NotificationSettingsApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: const BasicAuthorizationHeaderProvider(
        username: 'anonymous-user-1',
        password: 'user-test-password',
      ),
    );

    final settings = await repository.getNotificationSettings();

    expect(requestedUri.path, '/api/v1/me/notification-settings');
    expect(
      authorizationHeader,
      'Basic ${base64Encode(utf8.encode('anonymous-user-1:user-test-password'))}',
    );
    expect(settings.userId, 'anonymous-user-1');
    expect(settings.favoriteStationFacilityAlerts, isTrue);
    expect(settings.favoriteRouteFacilityAlerts, isFalse);
    expect(settings.reportStatusAlerts, isTrue);
    expect(settings.dataQualityAlerts, isFalse);
  });

  test('알림 설정 API 저장소는 바꾼 설정을 저장한다', () async {
    late String requestedMethod;
    late Uri requestedUri;
    late Map<String, Object?> requestBody;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      requestedMethod = request.method;
      requestedUri = request.uri;
      requestBody =
          jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': {
              'userId': 'anonymous-user-1',
              'favoriteStationFacilityAlerts': false,
              'favoriteRouteFacilityAlerts': true,
              'reportStatusAlerts': true,
              'dataQualityAlerts': true,
              'updatedAt': '2026-06-14T09:05:00',
            },
          }),
        );
      await request.response.close();
    });

    final repository = NotificationSettingsApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: const NoAuthorizationHeaderProvider(),
    );

    final savedSettings = await repository.saveNotificationSettings(
      const NotificationSettings(
        userId: 'anonymous-user-1',
        favoriteStationFacilityAlerts: false,
        favoriteRouteFacilityAlerts: true,
        reportStatusAlerts: true,
        dataQualityAlerts: true,
        updatedAt: '2026-06-14T09:00:00',
      ),
    );

    expect(requestedMethod, 'PUT');
    expect(requestedUri.path, '/api/v1/me/notification-settings');
    expect(requestBody, {
      'userId': 'anonymous-user-1',
      'favoriteStationFacilityAlerts': false,
      'favoriteRouteFacilityAlerts': true,
      'reportStatusAlerts': true,
      'dataQualityAlerts': true,
    });
    expect(savedSettings.favoriteRouteFacilityAlerts, isTrue);
    expect(savedSettings.dataQualityAlerts, isTrue);
    expect(savedSettings.updatedAt, '2026-06-14T09:05:00');
  });

  test('알림 설정 API 저장소는 인증 실패 시 인증을 지우고 한 번 재시도한다', () async {
    final authorizationHeaders = <String?>[];
    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      requestCount++;
      authorizationHeaders.add(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      request.response.headers.contentType = ContentType.json;

      if (requestCount == 1) {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..write(jsonEncode({'success': false}))
          ..close();
        return;
      }

      request.response
        ..statusCode = HttpStatus.ok
        ..write(
          jsonEncode({
            'success': true,
            'data': {
              'userId': 'anonymous-user-1',
              'favoriteStationFacilityAlerts': true,
              'favoriteRouteFacilityAlerts': true,
              'reportStatusAlerts': false,
              'dataQualityAlerts': false,
              'updatedAt': '2026-06-14T09:10:00',
            },
          }),
        )
        ..close();
    });

    final authProvider = RetryAuthorizationHeaderProvider();
    final repository = NotificationSettingsApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: authProvider,
    );

    final settings = await repository.getNotificationSettings();

    expect(settings.favoriteRouteFacilityAlerts, isTrue);
    expect(authorizationHeaders, ['Basic stale-token', 'Basic fresh-token']);
    expect(authProvider.authorizationCount, 2);
    expect(authProvider.invalidateCount, 1);
  });

  test('알림 설정 컨트롤러는 조회와 저장 상태를 구분한다', () async {
    final repository = FakeNotificationSettingsRepository();
    final controller = NotificationSettingsController(repository: repository);

    await controller.load();

    expect(controller.state.status, NotificationSettingsStatus.ready);
    expect(controller.state.settings?.favoriteStationFacilityAlerts, isTrue);

    controller.updateFavoriteStationFacilityAlerts(false);
    controller.updateFavoriteRouteFacilityAlerts(true);
    await controller.save();

    expect(repository.savedSettings, hasLength(1));
    expect(
      repository.savedSettings.single.favoriteStationFacilityAlerts,
      isFalse,
    );
    expect(repository.savedSettings.single.favoriteRouteFacilityAlerts, isTrue);
    expect(controller.state.message, '알림 설정을 저장했습니다.');
  });
}

class RetryAuthorizationHeaderProvider implements AuthorizationHeaderProvider {
  var authorizationCount = 0;
  var invalidateCount = 0;
  var _invalidated = false;

  @override
  Future<String?> authorizationHeader() async {
    authorizationCount++;
    return _invalidated ? 'Basic fresh-token' : 'Basic stale-token';
  }

  @override
  Future<void> invalidateAuthorization() async {
    invalidateCount++;
    _invalidated = true;
  }
}

class FakeNotificationSettingsRepository
    implements NotificationSettingsRepository {
  NotificationSettings settings = const NotificationSettings(
    userId: 'anonymous-user-1',
    favoriteStationFacilityAlerts: true,
    favoriteRouteFacilityAlerts: false,
    reportStatusAlerts: true,
    dataQualityAlerts: false,
    updatedAt: '2026-06-14T09:00:00',
  );
  final savedSettings = <NotificationSettings>[];

  @override
  Future<NotificationSettings> getNotificationSettings() async {
    return settings;
  }

  @override
  Future<NotificationSettings> saveNotificationSettings(
    NotificationSettings settings,
  ) async {
    savedSettings.add(settings);
    this.settings = settings.copyWith(updatedAt: '2026-06-14T09:05:00');
    return this.settings;
  }
}
