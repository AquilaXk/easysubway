import 'package:easysubway_mobile/station_search.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('현재 위치 제공자는 권한 요청 필요 여부를 네이티브 채널로 확인한다', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('test/current-location');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final requestedMethods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      requestedMethods.add(call.method);
      return false;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final provider = MethodChannelCurrentLocationProvider(channel: channel);

    expect(await provider.needsLocationPermissionRequest(), isFalse);
    expect(requestedMethods, ['needsLocationPermissionRequest']);
  });

  test('현재 위치 제공자는 GPS 꺼짐 오류를 쉬운 안내 문구로 바꾼다', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('test/current-location-disabled');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'locationDisabled');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final provider = MethodChannelCurrentLocationProvider(channel: channel);

    await expectLater(
      provider.currentLocation(),
      throwsA(
        isA<CurrentLocationException>().having(
          (error) => error.message,
          'message',
          '기기 위치(GPS)를 켜 주세요. 가까운 역을 찾는 데 필요합니다.',
        ),
      ),
    );
  });

  test('현재 위치 제공자는 위치 설정 열기를 네이티브 채널에 요청한다', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('test/current-location-settings');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final requestedMethods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      requestedMethods.add(call.method);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final provider = MethodChannelCurrentLocationProvider(channel: channel);

    expect(await provider.openLocationSettings(), isTrue);
    expect(requestedMethods, ['openLocationSettings']);
  });
}
