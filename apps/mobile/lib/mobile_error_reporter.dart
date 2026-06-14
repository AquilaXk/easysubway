import 'dart:async';

import 'package:flutter/foundation.dart';

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
