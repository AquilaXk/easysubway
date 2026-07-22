import 'package:easysubway_mobile/core/crashlytics/crashlytics_gateway.dart';
import 'package:easysubway_mobile/core/crashlytics/mobile_crash_reporting.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingCrashlytics implements CrashlyticsGateway {
  bool collectionEnabled = false;
  final flutterFatals = <FlutterErrorDetails>[];
  final errors = <Object>[];

  @override
  bool get isCollectionEnabled => collectionEnabled;

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    collectionEnabled = enabled;
  }

  @override
  Future<void> recordFlutterFatalError(FlutterErrorDetails details) async {
    flutterFatals.add(details);
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  }) async {
    errors.add(error);
  }
}

void main() {
  late FlutterExceptionHandler? originalOnError;
  late bool Function(Object error, StackTrace stack)? originalPlatformOnError;

  setUp(() {
    originalOnError = FlutterError.onError;
    originalPlatformOnError = PlatformDispatcher.instance.onError;
    resetCrashlyticsGateway();
  });

  tearDown(() {
    FlutterError.onError = originalOnError;
    PlatformDispatcher.instance.onError = originalPlatformOnError;
    resetCrashlyticsGateway();
  });

  test('release enables Crashlytics collection; debug disables it', () async {
    final releaseGateway = _RecordingCrashlytics();
    final releaseReady = await initializeMobileCrashReporting(
      isReleaseMode: true,
      ensureFirebaseReady: () async {},
      createGateway: () => releaseGateway,
    );
    expect(releaseReady, isTrue);
    expect(releaseGateway.collectionEnabled, isTrue);

    final debugGateway = _RecordingCrashlytics();
    final debugReady = await initializeMobileCrashReporting(
      isReleaseMode: false,
      ensureFirebaseReady: () async {},
      createGateway: () => debugGateway,
    );
    expect(debugReady, isTrue);
    expect(debugGateway.collectionEnabled, isFalse);
  });

  test('initializeMobileCrashReporting soft-fails without throwing', () async {
    final ready = await initializeMobileCrashReporting(
      isReleaseMode: true,
      ensureFirebaseReady: () async {
        throw StateError('missing google-services.json');
      },
    );
    expect(ready, isFalse);
    expect(crashlyticsGateway, isA<NoopCrashlyticsGateway>());
  });

  test(
    'FlutterError.onError records via Crashlytics when no zone reporter',
    () async {
      final gateway = _RecordingCrashlytics();
      replaceCrashlyticsGatewayForTest(gateway);
      final originalPresent = FlutterError.presentError;
      FlutterError.presentError = (_) {};
      addTearDown(() {
        FlutterError.presentError = originalPresent;
      });
      installMobileErrorHandlers();

      final details = FlutterErrorDetails(
        exception: StateError('sync-boom'),
        stack: StackTrace.current,
        library: 'test',
      );
      FlutterError.onError?.call(details);
      await pumpEventQueue();

      expect(gateway.flutterFatals, hasLength(1));
      expect(gateway.flutterFatals.single.exception, isA<StateError>());
    },
  );

  test('PlatformDispatcher.onError records fatal errors', () async {
    final gateway = _RecordingCrashlytics();
    replaceCrashlyticsGatewayForTest(gateway);
    installMobileErrorHandlers();

    final handled = PlatformDispatcher.instance.onError?.call(
      StateError('async-boom'),
      StackTrace.current,
    );
    await pumpEventQueue();

    expect(handled, isTrue);
    expect(gateway.errors, hasLength(1));
  });

  test('runWithMobileErrorReporter keeps zone injection contract', () async {
    final reported = <FlutterErrorDetails>[];
    await runWithMobileErrorReporter(reported.add, () async {
      reportMobileError(
        StateError('zoned'),
        StackTrace.current,
        context: 'zone test',
      );
    });
    expect(reported, hasLength(1));
    expect(reported.single.exception, isA<StateError>());
  });

  test(
    'zone reporter short-circuits Crashlytics on FlutterError.onError',
    () async {
      final gateway = _RecordingCrashlytics();
      replaceCrashlyticsGatewayForTest(gateway);
      installMobileErrorHandlers();

      final reported = <FlutterErrorDetails>[];
      await runWithMobileErrorReporter(reported.add, () async {
        FlutterError.onError?.call(
          FlutterErrorDetails(
            exception: StateError('zoned-flutter'),
            stack: StackTrace.current,
          ),
        );
      });
      await pumpEventQueue();

      expect(reported, hasLength(1));
      expect(gateway.flutterFatals, isEmpty);
    },
  );
}
