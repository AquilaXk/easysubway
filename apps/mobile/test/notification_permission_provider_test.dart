import 'package:easysubway_mobile/notification_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('알림 권한 제공자는 네이티브 채널로 권한 요청을 보낸다', () async {
    const channel = MethodChannel('test/notification-permission');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final provider = MethodChannelNotificationPermissionProvider(
      channel: channel,
    );

    final result = await provider.requestNotificationPermission();

    expect(result, NotificationPermissionStatus.granted);
    expect(calls.single.method, 'requestNotificationPermission');
  });

  test('알림 권한 제공자는 권한 거부를 쉬운 상태로 바꾼다', () async {
    const channel = MethodChannel('test/notification-permission-denied');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => false);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final provider = MethodChannelNotificationPermissionProvider(
      channel: channel,
    );

    final result = await provider.requestNotificationPermission();

    expect(result, NotificationPermissionStatus.denied);
  });

  test('알림 권한 제공자는 네이티브 오류를 쉬운 안내로 바꾼다', () async {
    const channel = MethodChannel('test/notification-permission-error');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'notificationUnavailable');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final provider = MethodChannelNotificationPermissionProvider(
      channel: channel,
    );

    await expectLater(
      provider.requestNotificationPermission(),
      throwsA(
        isA<NotificationSettingsException>().having(
          (error) => error.message,
          'message',
          '알림 권한을 확인하지 못했습니다.',
        ),
      ),
    );
  });
}
