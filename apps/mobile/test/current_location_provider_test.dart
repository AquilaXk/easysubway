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
}
