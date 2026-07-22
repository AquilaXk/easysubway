import 'dart:async';

import 'package:flutter/foundation.dart';

import 'core/crashlytics/mobile_crash_reporting.dart';
import 'core/logging/app_logger.dart';

typedef MobileErrorReporter = void Function(FlutterErrorDetails details);

const _mobileErrorReporterZoneKey = #easysubwayMobileErrorReporter;

void reportMobileError(
  Object error,
  StackTrace stackTrace, {
  required String context,
}) {
  final details = FlutterErrorDetails(
    exception: error,
    stack: stackTrace,
    library: 'easysubway mobile',
    context: ErrorDescription(context),
  );

  final zoneReporter = Zone.current[_mobileErrorReporterZoneKey];
  if (zoneReporter is MobileErrorReporter) {
    zoneReporter(details);
    return;
  }

  FlutterError.reportError(details);
}

Future<T> runWithMobileErrorReporter<T>(
  MobileErrorReporter reporter,
  Future<T> Function() body,
) {
  return runZoned(body, zoneValues: {_mobileErrorReporterZoneKey: reporter});
}

/// 전역 핸들러 3면 배선. 기존 `runWithMobileErrorReporter` zone 계약은 유지한다.
void installMobileErrorHandlers() {
  FlutterError.onError = (details) {
    final zoneReporter = Zone.current[_mobileErrorReporterZoneKey];
    if (zoneReporter is MobileErrorReporter) {
      zoneReporter(details);
      return;
    }

    appLog.e(
      details.context?.toDescription() ?? 'Flutter framework error',
      error: details.exception,
      stackTrace: details.stack,
    );
    // 미초기화·테스트 환경에서도 예외를 던지지 않는다.
    unawaited(recordFatalFlutterError(details));
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    final zoneReporter = Zone.current[_mobileErrorReporterZoneKey];
    if (zoneReporter is MobileErrorReporter) {
      zoneReporter(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'easysubway mobile',
          context: ErrorDescription('PlatformDispatcher.onError'),
        ),
      );
      return true;
    }

    appLog.e('Unhandled platform/async error', error: error, stackTrace: stack);
    unawaited(
      recordFatalError(error, stack, reason: 'PlatformDispatcher.onError'),
    );
    return true;
  };
}
