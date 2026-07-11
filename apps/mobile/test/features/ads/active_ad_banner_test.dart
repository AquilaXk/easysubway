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

ApiResponse _creativeResponse() => const ApiResponse(
  statusCode: 200,
  jsonBody: {
    'success': true,
    'data': {
      'placement': 'route-result-bottom',
      'creativeId': 'creative-1',
      'imageUrl': 'https://cdn.easysubway.app/banner.png',
      'landingUrl': 'https://advertiser.example/campaign',
      'advertiserName': '이지상점',
      'altText': '여름 할인 배너',
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
              repository: AdRepository(
                _StubApiClient(response, error: apiError),
              ),
              placement: AdPlacement.routeResultBottom,
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
    expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
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

  testWidgets('320dp와 text scale 2.0에서도 overflow가 없다', (tester) async {
    await _pumpBanner(
      tester,
      response: Future.value(_creativeResponse()),
      imageLoader: (_, _) async => _image,
      width: 320,
      textScale: 2,
    );
    await tester.pump();

    expect(find.byType(AdBannerSlot), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
