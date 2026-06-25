import 'package:easysubway_mobile/station_search.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('현재 위치 제공자는 정확도와 측정 시각과 권한 정밀도를 함께 읽는다', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('test/current-location-quality');
    final measuredAt = DateTime.utc(2026, 6, 21, 14);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      return {
        'latitude': 37.3028,
        'longitude': 126.8665,
        'accuracyMeters': 35.5,
        'measuredAtMillis': measuredAt.millisecondsSinceEpoch,
        'provider': 'gps',
        'isMocked': false,
        'permissionPrecision': 'precise',
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final provider = MethodChannelCurrentLocationProvider(channel: channel);

    final location = await provider.currentLocation();

    expect(location.accuracyMeters, 35.5);
    expect(location.measuredAt, measuredAt);
    expect(location.provider, 'gps');
    expect(location.isMocked, isFalse);
    expect(location.permissionPrecision, LocationPermissionPrecision.precise);
    expect(
      location.qualityStatus(now: measuredAt.add(const Duration(minutes: 1))),
      CurrentLocationQualityStatus.freshPrecise,
    );
  });

  test('현재 위치 제공자는 기존 좌표만 있는 응답을 자동 검색 불가 품질로 판정한다', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('test/current-location-legacy');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      return {'latitude': 37.3028, 'longitude': 126.8665};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final provider = MethodChannelCurrentLocationProvider(channel: channel);

    final location = await provider.currentLocation();

    expect(location.accuracyMeters, isNull);
    expect(location.measuredAt, isNull);
    expect(
      location.qualityStatus(now: DateTime.utc(2026, 6, 21, 14)),
      CurrentLocationQualityStatus.unavailable,
    );
    expect(
      location.canUseForNearbySearch(now: DateTime.utc(2026, 6, 21, 14)),
      isFalse,
    );
  });

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
          '휴대전화의 위치 기능을 켜 주세요. 가까운 역을 찾는 데 필요합니다.',
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
