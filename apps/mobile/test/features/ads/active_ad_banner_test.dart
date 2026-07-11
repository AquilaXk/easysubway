import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:easysubway_mobile/ad_slot.dart';
import 'package:easysubway_mobile/core/network/api_client.dart';
import 'package:easysubway_mobile/features/ads/active_ad_banner.dart';
import 'package:easysubway_mobile/features/ads/ad_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

class _StubApiClient extends ApiClient {
  _StubApiClient(this.response, {this.error})
    : super(baseUri: Uri.parse('https://api.easysubway.example'));

  final Future<ApiResponse> response;
  final Object? error;

  @override
  Future<ApiResponse> getJson(
    String path, {
    Map<String, String> headers = const {},
  }) async {
    if (error != null) {
      throw error!;
    }
    return response;
  }
}

ApiResponse _creativeResponse({
  String placement = 'route-result-bottom',
  String imageUrl = 'https://cdn.easysubway.app/banner.png',
  String advertiserName = '이지상점',
  String altText = '여름 할인 배너',
}) => ApiResponse(
  statusCode: 200,
  jsonBody: <String, Object?>{
    'success': true,
    'data': <String, Object?>{
      'placement': placement,
      'creativeId': 'creative-1',
      'imageUrl': imageUrl,
      'landingUrl': 'https://advertiser.example/campaign',
      'advertiserName': advertiserName,
      'altText': altText,
    },
  },
);

final _image = MemoryImage(
  Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
  ),
);

Future<bool> _launchSuccess(Uri uri, {required LaunchMode mode}) async => true;

Future<void> _pumpBanner(
  WidgetTester tester, {
  required Future<ApiResponse> response,
  required AdImageLoader imageLoader,
  AdLauncher? launcher,
  Object? apiError,
  AdRepository? repository,
  AdPlacement placement = AdPlacement.routeResultBottom,
  Key? bannerKey,
  double width = 400,
  double textScale = 1,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Center(
          child: SizedBox(
            width: width,
            child: ActiveAdBanner(
              key: bannerKey,
              repository:
                  repository ??
                  AdRepository(_StubApiClient(response, error: apiError)),
              placement: placement,
              imageLoader: imageLoader,
              launcher: launcher ?? _launchSuccess,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('소재 조회 중에는 debug placeholder까지 완전히 숨긴다', (tester) async {
    final response = Completer<ApiResponse>();

    await _pumpBanner(
      tester,
      response: response.future,
      imageLoader: (_, _) async => _image,
    );

    expect(find.byType(AdBannerSlot), findsNothing);
    expect(find.text('광고 미리보기 (개발용)'), findsNothing);
  });

  testWidgets('소재가 없거나 조회에 실패하면 완전히 숨긴다', (tester) async {
    await _pumpBanner(
      tester,
      response: Future.value(
        const ApiResponse(statusCode: 204, jsonBody: null),
      ),
      imageLoader: (_, _) async => _image,
    );
    await tester.pump();

    expect(find.byType(AdBannerSlot), findsNothing);

    await _pumpBanner(
      tester,
      response: Future.value(_creativeResponse()),
      imageLoader: (_, _) async => _image,
      apiError: const ApiException('offline'),
    );
    await tester.pump();

    expect(find.byType(AdBannerSlot), findsNothing);
    expect(find.text('광고 미리보기 (개발용)'), findsNothing);
  });

  testWidgets('이미지 decode 완료 전과 실패 뒤에는 완전히 숨긴다', (tester) async {
    final image = Completer<ImageProvider<Object>>();
    await _pumpBanner(
      tester,
      response: Future.value(_creativeResponse()),
      imageLoader: (_, _) => image.future,
    );
    await tester.pump();

    expect(find.byType(AdBannerSlot), findsNothing);

    image.completeError(StateError('decode failed'));
    await tester.pump();

    expect(find.byType(AdBannerSlot), findsNothing);
    expect(find.text('광고 미리보기 (개발용)'), findsNothing);
  });

  testWidgets('이미지 decode 성공 뒤에만 96dp 실제 배너를 표시한다', (tester) async {
    final image = Completer<ImageProvider<Object>>();
    await _pumpBanner(
      tester,
      response: Future.value(_creativeResponse()),
      imageLoader: (_, _) => image.future,
    );
    await tester.pump();

    expect(find.byType(AdBannerSlot), findsNothing);

    image.complete(_image);
    await tester.pump();
    await tester.pump();

    expect(find.byType(AdBannerSlot), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('activeAdBannerSlot'))).height,
      kAdBannerSlotStandardHeight,
    );
    expect(find.text('광고'), findsOneWidget);
    expect(find.text('이지상점'), findsOneWidget);
    expect(find.text('여름 할인 배너'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    expect(find.text('광고 미리보기 (개발용)'), findsNothing);
  });

  testWidgets('TalkBack은 광고와 altText를 한 번 전달하고 전체 96dp가 클릭 영역이다', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final launches = <(Uri, LaunchMode)>[];
    await _pumpBanner(
      tester,
      response: Future.value(_creativeResponse()),
      imageLoader: (_, _) async => _image,
      launcher: (uri, {required mode}) async {
        launches.add((uri, mode));
        return true;
      },
    );
    await tester.pump();

    final target = find.byKey(const Key('activeAdBannerTapTarget'));
    final cta = find.byKey(const Key('activeAdBannerExternalCta'));
    expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(cta), const Size(48, 48));
    expect(
      tester.getSemantics(target),
      matchesSemantics(
        label: '광고, 여름 할인 배너',
        isButton: true,
        hasTapAction: true,
      ),
    );
    expect(find.bySemanticsLabel('광고, 여름 할인 배너'), findsOneWidget);
    expect(find.bySemanticsLabel('광고'), findsNothing);
    expect(find.bySemanticsLabel('여름 할인 배너'), findsNothing);

    await tester.tap(target);
    await tester.pump();

    expect(launches, [
      (
        Uri.parse('https://advertiser.example/campaign'),
        LaunchMode.externalApplication,
      ),
    ]);
    semantics.dispose();
  });

  testWidgets('repository와 placement 교체 뒤 늦은 이전 응답과 decode를 무시한다', (
    tester,
  ) async {
    const bannerKey = ValueKey('mutable-ad-banner');
    final routeResponse = Completer<ApiResponse>();
    final stationResponse = Completer<ApiResponse>();
    final routeImage = Completer<ImageProvider<Object>>();
    final stationImage = Completer<ImageProvider<Object>>();
    final routeRepository = AdRepository(_StubApiClient(routeResponse.future));
    final stationRepository = AdRepository(
      _StubApiClient(stationResponse.future),
    );
    Future<ImageProvider<Object>> imageLoader(Uri uri, BuildContext context) {
      return uri.path.endsWith('route.png')
          ? routeImage.future
          : stationImage.future;
    }

    await _pumpBanner(
      tester,
      response: routeResponse.future,
      repository: routeRepository,
      placement: AdPlacement.routeResultBottom,
      bannerKey: bannerKey,
      imageLoader: imageLoader,
    );
    await _pumpBanner(
      tester,
      response: stationResponse.future,
      repository: stationRepository,
      placement: AdPlacement.stationDetailBottom,
      bannerKey: bannerKey,
      imageLoader: imageLoader,
    );

    routeResponse.complete(
      _creativeResponse(
        imageUrl: 'https://cdn.easysubway.app/route.png',
        advertiserName: '이전 경로 광고',
      ),
    );
    await tester.pump();
    routeImage.complete(_image);
    await tester.pump();
    await tester.pump();

    expect(find.text('이전 경로 광고'), findsNothing);
    expect(find.byType(AdBannerSlot), findsNothing);

    stationResponse.complete(
      _creativeResponse(
        placement: 'station-detail-bottom',
        imageUrl: 'https://cdn.easysubway.app/station.png',
        advertiserName: '현재 역 광고',
      ),
    );
    await tester.pump();
    stationImage.complete(_image);
    await tester.pump();
    await tester.pump();

    expect(find.text('현재 역 광고'), findsOneWidget);
    expect(find.text('이전 경로 광고'), findsNothing);
  });

  testWidgets('외부 브라우저 실패나 예외에 fallback을 만들지 않는다', (tester) async {
    var calls = 0;
    await _pumpBanner(
      tester,
      response: Future.value(_creativeResponse()),
      imageLoader: (_, _) async => _image,
      launcher: (uri, {required mode}) async {
        calls++;
        return false;
      },
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('activeAdBannerTapTarget')));
    await tester.pump();

    expect(calls, 1);
    expect(tester.takeException(), isNull);

    await _pumpBanner(
      tester,
      response: Future.value(_creativeResponse()),
      imageLoader: (_, _) async => _image,
      launcher: (uri, {required mode}) async {
        calls++;
        throw StateError('browser unavailable');
      },
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('activeAdBannerTapTarget')));
    await tester.pump();

    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('긴 광고 문구도 text scale 2.0을 축소하지 않고 full semantics를 유지한다', (
    tester,
  ) async {
    const advertiser = '아주 긴 이름을 사용하는 공식 광고주 주식회사';
    const alt = '출퇴근 이용자를 위한 여름철 대중교통 안전 캠페인 전체 안내 문구';
    final semantics = tester.ensureSemantics();
    await _pumpBanner(
      tester,
      response: Future.value(
        _creativeResponse(advertiserName: advertiser, altText: alt),
      ),
      imageLoader: (_, _) async => _image,
      width: 320,
      textScale: 2,
    );
    await tester.pump();

    expect(
      find.ancestor(
        of: find.text(advertiser),
        matching: find.byType(FittedBox),
      ),
      findsNothing,
    );
    expect(find.bySemanticsLabel('광고, $alt'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
