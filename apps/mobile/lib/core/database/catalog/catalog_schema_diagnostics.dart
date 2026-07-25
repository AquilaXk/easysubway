import 'package:flutter/foundation.dart';

import '../../logging/app_logger.dart';

/// 카탈로그 테이블 결측으로 조회를 건너뛸 때 남기는 진단 신호(#2527).
///
/// 결측 가드는 예외를 던지지 않고 빈 결과를 돌려주므로, 접근성 근거가 없는 상태가 정상 안내와
/// 구분되지 않은 채 나간다. 로그도 지표도 없으면 운영에서 탐지할 수단이 없다. 사용자에게 보이는
/// 문구는 그대로 두고 진단 신호만 남긴다.
///
/// 신호는 역 단위로 폭주하면 안 된다. 경로 탐색은 역마다 같은 조회를 반복하므로 로그는
/// 테이블당 세션 1회로 상한을 두고, 발생 빈도는 카운터로만 누적한다.
class CatalogSchemaDiagnostics {
  CatalogSchemaDiagnostics._(this._log);

  static CatalogSchemaDiagnostics instance = CatalogSchemaDiagnostics._(
    _defaultLog,
  );

  final void Function(String message) _log;
  final Map<String, int> _missingTableReads = <String, int>{};

  /// 결측 테이블별 조회 시도 횟수. 상한 없이 누적하되 출력하지 않는다.
  Map<String, int> get missingTableReadCounts =>
      Map.unmodifiable(_missingTableReads);

  void recordMissingTableRead(String tableName) {
    final previous = _missingTableReads[tableName] ?? 0;
    _missingTableReads[tableName] = previous + 1;
    if (previous > 0) {
      return;
    }
    _log('카탈로그 테이블 결측으로 조회를 건너뜀: table=$tableName');
  }

  static void _defaultLog(String message) {
    appLog.w(message);
  }

  @visibleForTesting
  static void replaceForTest(void Function(String message) log) {
    instance = CatalogSchemaDiagnostics._(log);
  }

  @visibleForTesting
  static void reset() {
    instance = CatalogSchemaDiagnostics._(_defaultLog);
  }
}
