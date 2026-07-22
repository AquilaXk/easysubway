import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../logging/app_logger.dart';
import 'crashlytics_gateway.dart';

/// Firebase Crashlytics 초기화. 키 파일·플랫폼 미구성 시 예외 없이 no-op.
Future<bool> initializeMobileCrashReporting({
  bool isReleaseMode = kReleaseMode,
  Future<void> Function()? ensureFirebaseReady,
  CrashlyticsGateway Function()? createGateway,
}) async {
  try {
    if (ensureFirebaseReady != null) {
      await ensureFirebaseReady();
    } else {
      await Firebase.initializeApp();
    }
    final gateway = createGateway?.call() ?? FirebaseCrashlyticsGateway();
    crashlyticsGateway = gateway;
    // debug/profile에서는 전송 비활성. release만 수집.
    await gateway.setCollectionEnabled(isReleaseMode);
    appLog.i(
      'Crashlytics collection enabled=${gateway.isCollectionEnabled} '
      '(release=$isReleaseMode)',
    );
    return true;
  } catch (error, stackTrace) {
    crashlyticsGateway = const NoopCrashlyticsGateway();
    appLog.w(
      'Crashlytics unavailable; continuing without crash reporting.',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  }
}

Future<void> recordFatalFlutterError(FlutterErrorDetails details) {
  return crashlyticsGateway.recordFlutterFatalError(details);
}

Future<void> recordFatalError(
  Object error,
  StackTrace stackTrace, {
  String? reason,
}) {
  return crashlyticsGateway.recordError(
    error,
    stackTrace,
    fatal: true,
    reason: reason,
  );
}
