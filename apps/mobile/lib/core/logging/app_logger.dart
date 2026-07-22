import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// 앱 공통 로거. release는 WARN 이상, debug는 상세(cause 포함) 출력.
class AppLogger {
  AppLogger._(this._logger);

  final Logger _logger;

  static AppLogger instance = AppLogger._(_createLogger());

  static Logger _createLogger() {
    return Logger(
      level: kReleaseMode ? Level.warning : Level.debug,
      printer: PrettyPrinter(
        methodCount: kReleaseMode ? 0 : 2,
        errorMethodCount: kReleaseMode ? 4 : 8,
        lineLength: 100,
        colors: !kReleaseMode,
        printEmojis: false,
        dateTimeFormat: DateTimeFormat.none,
      ),
      output: _DebugPrintOutput(),
    );
  }

  @visibleForTesting
  static void replaceForTest(AppLogger logger) {
    instance = logger;
  }

  @visibleForTesting
  static void reset() {
    instance = AppLogger._(_createLogger());
  }

  void d(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Object? cause,
    StackTrace? causeStackTrace,
  }) {
    _logger.d(
      _compose(message, cause: cause, causeStackTrace: causeStackTrace),
      error: error,
      stackTrace: stackTrace,
    );
  }

  void i(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  void w(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Object? cause,
    StackTrace? causeStackTrace,
  }) {
    _logger.w(
      _compose(message, cause: cause, causeStackTrace: causeStackTrace),
      error: error,
      stackTrace: stackTrace,
    );
  }

  void e(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Object? cause,
    StackTrace? causeStackTrace,
  }) {
    _logger.e(
      _compose(message, cause: cause, causeStackTrace: causeStackTrace),
      error: error,
      stackTrace: stackTrace,
    );
  }

  String _compose(
    String message, {
    Object? cause,
    StackTrace? causeStackTrace,
  }) {
    if (!kDebugMode || (cause == null && causeStackTrace == null)) {
      return message;
    }
    final buffer = StringBuffer(message);
    if (cause != null) {
      buffer.write(' | cause=$cause');
    }
    if (causeStackTrace != null) {
      buffer.write(' | causeStack=$causeStackTrace');
    }
    return buffer.toString();
  }
}

class _DebugPrintOutput extends LogOutput {
  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      debugPrint(line);
    }
  }
}

AppLogger get appLog => AppLogger.instance;
