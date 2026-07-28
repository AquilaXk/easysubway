const kakaoMapNativeAppKey = String.fromEnvironment(
  'EASYSUBWAY_KAKAO_MAP_NATIVE_APP_KEY',
);

bool _kakaoMapSdkInitialized = false;
bool get kakaoMapSdkInitialized => _kakaoMapSdkInitialized;
void markKakaoMapSdkInitialized() => _kakaoMapSdkInitialized = true;

void validateKakaoMapConfiguration({
  required String nativeAppKey,
  required bool isReleaseMode,
}) {
  if (isReleaseMode && nativeAppKey.trim().isEmpty) {
    throw StateError('Kakao Map Native app key is required for release.');
  }
}
