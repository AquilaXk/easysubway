import 'package:easysubway_mobile/core/external/kakao_map_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('릴리즈는 카카오맵 Native app key가 없으면 거부한다', () {
    expect(
      () =>
          validateKakaoMapConfiguration(nativeAppKey: ' ', isReleaseMode: true),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Kakao Map Native app key is required for release.',
        ),
      ),
    );
  });

  test('개발 빌드는 key 없이 명시적 unavailable 화면을 허용한다', () {
    expect(
      () =>
          validateKakaoMapConfiguration(nativeAppKey: '', isReleaseMode: false),
      returnsNormally,
    );
  });

  test('릴리즈는 설정된 Native app key를 허용한다', () {
    expect(
      () => validateKakaoMapConfiguration(
        nativeAppKey: 'test-native-map-key',
        isReleaseMode: true,
      ),
      returnsNormally,
    );
  });
}
