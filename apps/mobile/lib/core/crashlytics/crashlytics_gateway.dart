import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Crashlytics 전송 게이트웨이. 테스트·미초기화 환경은 no-op.
abstract class CrashlyticsGateway {
  bool get isCollectionEnabled;

  Future<void> setCollectionEnabled(bool enabled);

  Future<void> recordFlutterFatalError(FlutterErrorDetails details);

  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  });
}

class NoopCrashlyticsGateway implements CrashlyticsGateway {
  const NoopCrashlyticsGateway();

  @override
  bool get isCollectionEnabled => false;

  @override
  Future<void> setCollectionEnabled(bool enabled) async {}

  @override
  Future<void> recordFlutterFatalError(FlutterErrorDetails details) async {}

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  }) async {}
}

class FirebaseCrashlyticsGateway implements CrashlyticsGateway {
  FirebaseCrashlyticsGateway({FirebaseCrashlytics? crashlytics})
    : _crashlytics = crashlytics ?? FirebaseCrashlytics.instance;

  final FirebaseCrashlytics _crashlytics;

  @override
  bool get isCollectionEnabled => _crashlytics.isCrashlyticsCollectionEnabled;

  @override
  Future<void> setCollectionEnabled(bool enabled) {
    return _crashlytics.setCrashlyticsCollectionEnabled(enabled);
  }

  @override
  Future<void> recordFlutterFatalError(FlutterErrorDetails details) {
    return _crashlytics.recordFlutterFatalError(details);
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  }) {
    return _crashlytics.recordError(
      error,
      stackTrace,
      fatal: fatal,
      reason: reason,
    );
  }
}

CrashlyticsGateway crashlyticsGateway = const NoopCrashlyticsGateway();

@visibleForTesting
void replaceCrashlyticsGatewayForTest(CrashlyticsGateway gateway) {
  crashlyticsGateway = gateway;
}

@visibleForTesting
void resetCrashlyticsGateway() {
  crashlyticsGateway = const NoopCrashlyticsGateway();
}
