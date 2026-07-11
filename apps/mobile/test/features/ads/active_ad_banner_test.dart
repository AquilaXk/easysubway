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
  _StubApiClient(
    this.response, {
    this.error,
    this.eventResponse,
    this.eventError,
  }) : super(baseUri: Uri.parse('https://api.easysubway.example'));

  final Future<ApiResponse> response;
  final Object? error;
  final Future<ApiResponse>? eventResponse;
  final Object? eventError;
  final eventBodies = <Map<String, Object?>>[];
  var getCalls = 0;

  @override
  Future<ApiResponse> getJson(
    String path, {
    Map<String, String> headers = const {},
  }) async {
    getCalls++;
    if (error != null) {
      throw error!;
    }
    return response;
  }

  @override
  Future<ApiResponse> postJson(
    String path, {
    required Map<String, Object?> body,
    Map<String, String> headers = const {},
  }) async {
    eventBodies.add(Map<String, Object?>.of(body));
    if (eventError != null) {
      throw eventError!;
    }
    if (eventResponse != null) {
      return eventResponse!;
    }
    return const ApiResponse(statusCode: 204, jsonBody: null);
  }
}

class _SequencedApiClient extends ApiClient {
  _SequencedApiClient(this.responses)
    : super(baseUri: Uri.parse('https://api.easysubway.example'));

  final List<Future<ApiResponse>> responses;
  var calls = 0;

  @override
  Future<ApiResponse> getJson(
    String path, {
    Map<String, String> headers = const {},
  }) {
    return responses[calls++];
  }

  @override
  Future<ApiResponse> postJson(
    String path, {
    required Map<String, Object?> body,
    Map<String, String> headers = const {},
  }) async {
    return const ApiResponse(statusCode: 204, jsonBody: null);
  }
}

enum _ReloadDependency { repository, placement, imageLoader }

ApiResponse _creativeResponse({
  String placement = 'route-result-bottom',
  String imageUrl = 'https://cdn.easysubway.app/banner.png',
  String advertiserName = '이지상점',
  String altText = '여름 할인 배너',
  Object? endsAt = '2099-12-31T23:59:59Z',
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
      'endsAt': endsAt,
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

DateTime _utcNow() => DateTime.now().toUtc();

Future<void> _pumpBanner(
  WidgetTester tester, {
  Future<ApiResponse>? response,
  required AdImageLoader imageLoader,
  AdLauncher? launcher,
  DateTime Function() now = _utcNow,
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
                  AdRepository(_StubApiClient(response!, error: apiError)),
              placement: placement,
              imageLoader: imageLoader,
              launcher: launcher ?? _launchSuccess,
              now: now,
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

    image.completeError(Exception('decode failed'));
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

  testWidgets('impression은 decode와 실제 frame render 뒤 생명주기당 한 번 보낸다', (
    tester,
  ) async {
    final image = Completer<ImageProvider<Object>>();
    final client = _StubApiClient(Future.value(_creativeResponse()));
    await _pumpBanner(
      tester,
      repository: AdRepository(client),
      imageLoader: (_, _) => image.future,
    );
    await tester.pump();

    expect(find.byType(AdBannerSlot), findsNothing);
    expect(client.eventBodies, isEmpty);

    image.complete(_image);
    await tester.pump();
    await tester.pump();

    expect(find.byType(AdBannerSlot), findsOneWidget);
    expect(client.eventBodies, [
      {
        'placement': 'route-result-bottom',
        'creativeId': 'creative-1',
        'eventType': 'IMPRESSION',
      },
    ]);

    await tester.pump();
    expect(client.eventBodies, hasLength(1));
  });

  testWidgets('render 상태 설치 뒤 post-frame callback 전에 만료되면 impression을 생략한다', (
    tester,
  ) async {
    final image = Completer<ImageProvider<Object>>();
    var now = DateTime.utc(2026, 7, 12, 1);
    final endsAt = now.add(const Duration(minutes: 1));
    final client = _StubApiClient(
      Future.value(_creativeResponse(endsAt: endsAt.toIso8601String())),
    );
    await _pumpBanner(
      tester,
      repository: AdRepository(client),
      imageLoader: (_, _) => image.future,
      now: () => now,
    );
    await tester.pump();

    tester.binding.addPostFrameCallback((_) => image.complete(_image));
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(client.eventBodies, isEmpty);

    now = endsAt;
    await tester.pump();

    final impressions = client.eventBodies
        .where((body) => body['eventType'] == 'IMPRESSION')
        .toList();
    await tester.pumpWidget(const SizedBox.shrink());

    expect(impressions, isEmpty);
  });

  testWidgets('tap마다 click을 fire-and-forget하고 event 대기와 무관하게 landing을 연다', (
    tester,
  ) async {
    final pendingEvent = Completer<ApiResponse>();
    final client = _StubApiClient(
      Future.value(_creativeResponse()),
      eventResponse: pendingEvent.future,
    );
    final launches = <Uri>[];
    await _pumpBanner(
      tester,
      repository: AdRepository(client),
      imageLoader: (_, _) async => _image,
      launcher: (uri, {required mode}) async {
        launches.add(uri);
        return true;
      },
    );
    await tester.pump();
    await tester.pump();

    final target = find.byKey(const Key('activeAdBannerTapTarget'));
    await tester.tap(target);
    await tester.tap(target);
    await tester.pump();

    expect(
      client.eventBodies.where((body) => body['eventType'] == 'CLICK'),
      hasLength(2),
    );
    expect(launches, [
      Uri.parse('https://advertiser.example/campaign'),
      Uri.parse('https://advertiser.example/campaign'),
    ]);

    pendingEvent.complete(const ApiResponse(statusCode: 204, jsonBody: null));
  });

  testWidgets('click event 실패는 외부 browser landing을 막지 않는다', (tester) async {
    final client = _StubApiClient(
      Future.value(_creativeResponse()),
      eventError: const ApiException('offline'),
    );
    var launches = 0;
    await _pumpBanner(
      tester,
      repository: AdRepository(client),
      imageLoader: (_, _) async => _image,
      launcher: (uri, {required mode}) async {
        launches++;
        return true;
      },
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('activeAdBannerTapTarget')));
    await tester.pump();

    expect(launches, 1);
    expect(
      client.eventBodies.where((body) => body['eventType'] == 'CLICK'),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('이미 만료된 creative는 decode, render, impression을 모두 생략한다', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 12, 1);
    final client = _StubApiClient(
      Future.value(
        _creativeResponse(
          endsAt: now.subtract(const Duration(seconds: 1)).toIso8601String(),
        ),
      ),
    );
    var decodeCalls = 0;
    await _pumpBanner(
      tester,
      repository: AdRepository(client),
      imageLoader: (_, _) async {
        decodeCalls++;
        return _image;
      },
      now: () => now,
    );
    await tester.pump();

    expect(decodeCalls, 0);
    expect(find.byType(AdBannerSlot), findsNothing);
    expect(client.eventBodies, isEmpty);
  });

  testWidgets('미래 endsAt에 즉시 collapse하고 자동 refetch하지 않는다', (tester) async {
    var now = DateTime.utc(2026, 7, 12, 1);
    final endsAt = now.add(const Duration(seconds: 5));
    final client = _StubApiClient(
      Future.value(_creativeResponse(endsAt: endsAt.toIso8601String())),
    );
    await _pumpBanner(
      tester,
      repository: AdRepository(client),
      imageLoader: (_, _) async => _image,
      now: () => now,
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(AdBannerSlot), findsOneWidget);

    now = endsAt;
    await tester.pump(const Duration(seconds: 5));

    expect(find.byType(AdBannerSlot), findsNothing);
    expect(client.getCalls, 1);
  });

  testWidgets(
    'endsAt 이후 timer cleanup 전 tap은 collapse하고 click과 landing을 생략한다',
    (tester) async {
      var now = DateTime.utc(2026, 7, 12, 1);
      final endsAt = now.add(const Duration(minutes: 1));
      final client = _StubApiClient(
        Future.value(_creativeResponse(endsAt: endsAt.toIso8601String())),
      );
      var launches = 0;
      await _pumpBanner(
        tester,
        repository: AdRepository(client),
        imageLoader: (_, _) async => _image,
        now: () => now,
        launcher: (uri, {required mode}) async {
          launches++;
          return true;
        },
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(AdBannerSlot), findsOneWidget);

      final onTap = tester
          .widget<Semantics>(find.byKey(const Key('activeAdBannerTapTarget')))
          .properties
          .onTap!;
      now = endsAt;
      onTap();
      await tester.pump();

      final collapsed = find.byType(AdBannerSlot).evaluate().isEmpty;
      await tester.pumpWidget(const SizedBox.shrink());

      expect(collapsed, isTrue);
      expect(
        client.eventBodies.where((body) => body['eventType'] == 'CLICK'),
        isEmpty,
      );
      expect(launches, 0);
    },
  );

  testWidgets(
    'widget 교체는 이전 expiry Timer를 cancel하고 dispose 뒤 callback을 남기지 않는다',
    (tester) async {
      const bannerKey = ValueKey('expiry-generation-banner');
      var now = DateTime.utc(2026, 7, 12, 1);
      final firstEndsAt = now.add(const Duration(seconds: 5));
      final replacementEndsAt = now.add(const Duration(hours: 1));
      final firstClient = _StubApiClient(
        Future.value(
          _creativeResponse(
            advertiserName: '이전 광고',
            endsAt: firstEndsAt.toIso8601String(),
          ),
        ),
      );
      await _pumpBanner(
        tester,
        bannerKey: bannerKey,
        repository: AdRepository(firstClient),
        imageLoader: (_, _) async => _image,
        now: () => now,
      );
      await tester.pump();
      await tester.pump();

      final replacementClient = _StubApiClient(
        Future.value(
          _creativeResponse(
            advertiserName: '현재 광고',
            endsAt: replacementEndsAt.toIso8601String(),
          ),
        ),
      );
      await _pumpBanner(
        tester,
        bannerKey: bannerKey,
        repository: AdRepository(replacementClient),
        imageLoader: (_, _) async => _image,
        now: () => now,
      );
      await tester.pump();
      await tester.pump();
      now = firstEndsAt;
      await tester.pump(const Duration(seconds: 5));

      expect(find.text('현재 광고'), findsOneWidget);
      expect(find.text('이전 광고'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      now = replacementEndsAt;
      await tester.pump(const Duration(hours: 1));
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets('이전 decode 대기 중 widget 교체 뒤 늦은 이미지 완료를 무시한다', (tester) async {
    const bannerKey = ValueKey('mutable-ad-banner');
    final routeResponse = Completer<ApiResponse>();
    final stationResponse = Completer<ApiResponse>();
    final routeImage = Completer<ImageProvider<Object>>();
    final stationImage = Completer<ImageProvider<Object>>();
    final routeRepository = AdRepository(_StubApiClient(routeResponse.future));
    final stationRepository = AdRepository(
      _StubApiClient(stationResponse.future),
    );
    final requestedImages = <Uri>[];
    Future<ImageProvider<Object>> imageLoader(Uri uri, BuildContext context) {
      requestedImages.add(uri);
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

    routeResponse.complete(
      _creativeResponse(
        imageUrl: 'https://cdn.easysubway.app/route.png',
        advertiserName: '이전 경로 광고',
      ),
    );
    await tester.pump();

    expect(requestedImages, [
      Uri.parse('https://cdn.easysubway.app/route.png'),
    ]);
    expect(find.byType(AdBannerSlot), findsNothing);

    await _pumpBanner(
      tester,
      response: stationResponse.future,
      repository: stationRepository,
      placement: AdPlacement.stationDetailBottom,
      bannerKey: bannerKey,
      imageLoader: imageLoader,
    );

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

  testWidgets('dispose 뒤 늦은 조회와 decode 완료가 setState를 호출하지 않는다', (tester) async {
    final fetch = Completer<ApiResponse>();
    final fetchRepository = AdRepository(_StubApiClient(fetch.future));

    await _pumpBanner(
      tester,
      bannerKey: const ValueKey('late-fetch-banner'),
      repository: fetchRepository,
      placement: AdPlacement.routeResultBottom,
      imageLoader: (_, _) async => _image,
    );
    await tester.pumpWidget(const SizedBox.shrink());

    fetch.complete(_creativeResponse());
    await tester.pump();

    expect(tester.takeException(), isNull);

    final decode = Completer<ImageProvider<Object>>();
    var decodeStarted = false;
    await _pumpBanner(
      tester,
      bannerKey: const ValueKey('late-decode-banner'),
      repository: AdRepository(
        _StubApiClient(Future.value(_creativeResponse())),
      ),
      placement: AdPlacement.routeResultBottom,
      imageLoader: (_, _) {
        decodeStarted = true;
        return decode.future;
      },
    );
    await tester.pump();
    expect(decodeStarted, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());

    decode.complete(_image);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  for (final dependency in _ReloadDependency.values) {
    testWidgets('${dependency.name}만 교체하면 기존 배너를 지우고 다시 조회한다', (tester) async {
      const bannerKey = ValueKey('single-dependency-banner');
      final nextResponse = Completer<ApiResponse>();
      final initialClient = _SequencedApiClient([
        Future.value(
          _creativeResponse(
            imageUrl: 'https://cdn.easysubway.app/first.png',
            advertiserName: '기존 광고',
          ),
        ),
        if (dependency != _ReloadDependency.repository) nextResponse.future,
      ]);
      final replacementClient = dependency == _ReloadDependency.repository
          ? _SequencedApiClient([nextResponse.future])
          : initialClient;
      final initialRepository = AdRepository(initialClient);
      final replacementRepository = dependency == _ReloadDependency.repository
          ? AdRepository(replacementClient)
          : initialRepository;
      final replacementPlacement = dependency == _ReloadDependency.placement
          ? AdPlacement.stationDetailBottom
          : AdPlacement.routeResultBottom;
      var initialLoaderCalls = 0;
      var replacementLoaderCalls = 0;
      Future<ImageProvider<Object>> initialLoader(
        Uri uri,
        BuildContext context,
      ) async {
        initialLoaderCalls++;
        return _image;
      }

      Future<ImageProvider<Object>> replacementLoader(
        Uri uri,
        BuildContext context,
      ) async {
        replacementLoaderCalls++;
        return _image;
      }

      await _pumpBanner(
        tester,
        bannerKey: bannerKey,
        repository: initialRepository,
        placement: AdPlacement.routeResultBottom,
        imageLoader: initialLoader,
      );
      await tester.pump();

      expect(find.text('기존 광고'), findsOneWidget);
      expect(initialLoaderCalls, 1);

      await _pumpBanner(
        tester,
        bannerKey: bannerKey,
        repository: replacementRepository,
        placement: replacementPlacement,
        imageLoader: dependency == _ReloadDependency.imageLoader
            ? replacementLoader
            : initialLoader,
      );

      expect(find.byType(AdBannerSlot), findsNothing);
      expect(find.text('기존 광고'), findsNothing);

      nextResponse.complete(
        _creativeResponse(
          placement: replacementPlacement.id,
          imageUrl: 'https://cdn.easysubway.app/current.png',
          advertiserName: '현재 광고',
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('현재 광고'), findsOneWidget);
      expect(find.text('기존 광고'), findsNothing);
      expect(
        initialClient.calls +
            (identical(initialClient, replacementClient)
                ? 0
                : replacementClient.calls),
        2,
      );
      expect(
        replacementLoaderCalls,
        dependency == _ReloadDependency.imageLoader ? 1 : 0,
      );
    });
  }

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
        throw Exception('browser unavailable');
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
