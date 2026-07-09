import 'package:easysubway_mobile/core/external/kakao_map_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('카카오맵 look 딥링크는 API key 없이 앱 URI와 웹 fallback URI를 만든다', () {
    final target = const KakaoMapTarget(
      label: '상록수역 1번 출구',
      latitude: 37.3021,
      longitude: 126.8661,
    );

    expect(
      kakaoMapLookAppUri(target).toString(),
      'kakaomap://look?p=37.3021,126.8661',
    );
    expect(
      kakaoMapLookWebUri(target).toString(),
      'https://map.kakao.com/link/map/%EC%83%81%EB%A1%9D%EC%88%98%EC%97%AD%201%EB%B2%88%20%EC%B6%9C%EA%B5%AC,37.3021,126.8661',
    );
  });

  test('카카오맵 도보 경로 딥링크는 현재 위치와 출구 좌표만 사용한다', () {
    final route = const KakaoWalkingRouteTarget(
      start: KakaoMapPoint(latitude: 37.303, longitude: 126.867),
      end: KakaoMapTarget(
        label: '상록수역 1번 출구',
        latitude: 37.3021,
        longitude: 126.8661,
      ),
    );

    expect(
      kakaoMapWalkingRouteAppUri(route).toString(),
      'kakaomap://route?sp=37.303,126.867&ep=37.3021,126.8661&by=FOOT',
    );
    expect(
      kakaoMapWalkingRouteWebUri(route).toString(),
      'https://map.kakao.com/link/to/%EC%83%81%EB%A1%9D%EC%88%98%EC%97%AD%201%EB%B2%88%20%EC%B6%9C%EA%B5%AC,37.3021,126.8661',
    );
  });

  test('지도 열기 실패 시 좌표 복사 fallback까지 시도한다', () async {
    final openedUris = <Uri>[];
    final copiedTexts = <String>[];
    final launcher = UrlLauncherKakaoMapLauncher(
      openExternal: (uri) async {
        openedUris.add(uri);
        return false;
      },
      copyText: (text) async => copiedTexts.add(text),
    );

    final result = await launcher.openLook(
      const KakaoMapTarget(
        label: '상록수역 1번 출구',
        latitude: 37.3021,
        longitude: 126.8661,
      ),
    );

    expect(result, KakaoMapLaunchResult.copied);
    expect(openedUris.map((uri) => uri.scheme), ['kakaomap', 'https']);
    expect(copiedTexts, ['상록수역 1번 출구 37.3021, 126.8661']);
  });

  test('앱 URI 실패 후 웹 URI 성공 시 web 결과를 반환한다', () async {
    final openedUris = <Uri>[];
    final copiedTexts = <String>[];
    final launcher = UrlLauncherKakaoMapLauncher(
      openExternal: (uri) async {
        openedUris.add(uri);
        return uri.scheme == 'https';
      },
      copyText: (text) async => copiedTexts.add(text),
    );

    final result = await launcher.openLook(
      const KakaoMapTarget(
        label: '상록수역 1번 출구',
        latitude: 37.3021,
        longitude: 126.8661,
      ),
    );

    expect(result, KakaoMapLaunchResult.web);
    expect(openedUris.map((uri) => uri.scheme), ['kakaomap', 'https']);
    expect(copiedTexts, isEmpty);
  });

  test('지도 열기 예외도 좌표 복사 fallback으로 처리한다', () async {
    final copiedTexts = <String>[];
    final launcher = UrlLauncherKakaoMapLauncher(
      openExternal: (_) async => throw StateError('launcher unavailable'),
      copyText: (text) async => copiedTexts.add(text),
    );

    final result = await launcher.openLook(
      const KakaoMapTarget(
        label: '상록수역 1번 출구',
        latitude: 37.3021,
        longitude: 126.8661,
      ),
    );

    expect(result, KakaoMapLaunchResult.copied);
    expect(copiedTexts, ['상록수역 1번 출구 37.3021, 126.8661']);
  });
}
