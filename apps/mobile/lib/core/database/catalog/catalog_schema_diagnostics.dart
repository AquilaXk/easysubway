import 'package:flutter/foundation.dart';

import '../../logging/app_logger.dart';

/// 설치 팩이 조용히 강등되는 지점을 관측 가능하게 남긴다(#2527, #2532).
///
/// 여기서 다루는 넷은 모두 예외 없이 진행되므로 신호가 없으면 운영에서 탐지할 수단이 없다.
/// - 결측 테이블 조회 건너뜀: 접근성 근거가 없는 상태로 안내가 정상처럼 나간다.
/// - 결측 테이블 구제: 근거가 "빈 테이블"로 대체되면서 조회 건너뜀 신호가 더 이상 발화하지
///   않는다. 강등 자체는 그대로이므로 구제 사실을 별도로 남긴다.
/// - 설치 팩 거부: 사용자는 최신 팩을 쓴다고 믿는데 실제로는 구 팩 또는 번들로 동작한다.
/// - 무결성 거부(#2532): 설치된 파일이 기대 해시와 어긋나 재활성화하지 않은 경우. 스키마
///   거부와 원인은 다르지만 사용자가 겪는 결과(구 팩·번들 강등)와 필요한 신호는 같으므로
///   같은 진단 체계에 둔다.
///
/// 사용자에게 보이는 문구는 바꾸지 않는다. 신호는 역·호출 단위로 폭주하면 안 되므로 로그는
/// 키(테이블 이름·팩 파일 이름)당 세션 1회로 상한을 두고, 발생 빈도는 카운터로만 누적한다.
class CatalogSchemaDiagnostics {
  CatalogSchemaDiagnostics._(this._log);

  static CatalogSchemaDiagnostics instance = CatalogSchemaDiagnostics._(
    _defaultLog,
  );

  final void Function(String message) _log;
  final Map<String, int> _missingTableReads = <String, int>{};
  final Map<String, int> _rescuedTables = <String, int>{};
  final Map<String, int> _rejectedPacks = <String, int>{};
  bool _loggedSchemaRescue = false;

  /// 결측 테이블별 조회 시도 횟수. 상한 없이 누적하되 출력하지 않는다.
  Map<String, int> get missingTableReadCounts =>
      Map.unmodifiable(_missingTableReads);

  /// 빈 테이블로 구제된 테이블별 횟수.
  Map<String, int> get rescuedTableCounts => Map.unmodifiable(_rescuedTables);

  /// 구제 불가 결측으로 거부된 팩 파일별 횟수.
  Map<String, int> get rejectedPackCounts => Map.unmodifiable(_rejectedPacks);

  void recordMissingTableRead(String tableName) {
    final previous = _missingTableReads[tableName] ?? 0;
    _missingTableReads[tableName] = previous + 1;
    if (previous > 0) {
      return;
    }
    _log('카탈로그 테이블 결측으로 조회를 건너뜀: table=$tableName');
  }

  /// 결측 테이블을 빈 테이블로 만들었음을 기록한다. 로그는 세션당 1회.
  void recordSchemaRescue(Set<String> tableNames) {
    if (tableNames.isEmpty) {
      return;
    }
    for (final tableName in tableNames) {
      _rescuedTables[tableName] = (_rescuedTables[tableName] ?? 0) + 1;
    }
    if (_loggedSchemaRescue) {
      return;
    }
    _loggedSchemaRescue = true;
    _log('카탈로그 결측 테이블을 빈 테이블로 구제함: tables=${_sorted(tableNames)}');
  }

  /// 구제 불가 결측으로 설치 팩을 열지 않았음을 기록한다. 로그는 팩 파일당 세션 1회.
  void recordPackRejected({
    required String artifact,
    required Set<String> blockingTableNames,
  }) {
    final previous = _rejectedPacks[artifact] ?? 0;
    _rejectedPacks[artifact] = previous + 1;
    if (previous > 0) {
      return;
    }
    _log(
      '카탈로그 필수 테이블 결측으로 설치 팩을 열지 않고 강등함: '
      'pack=$artifact tables=${_sorted(blockingTableNames)}',
    );
  }

  /// 설치 파일이 기대 해시와 어긋나 재활성화하지 않았음을 기록한다(#2532).
  ///
  /// 거부 횟수는 스키마 거부와 같은 카운터에 누적한다. 어느 쪽이든 "이 팩 파일을 열지
  /// 않았다"는 같은 사건이고, 운영에서 한 지표로 보는 편이 원인 추적에 낫다.
  /// 로그는 팩 파일당 세션 1회.
  void recordPackIntegrityRejected({
    required String artifact,
    required String? expectedSha256,
    required String actualSha256,
  }) {
    final previous = _rejectedPacks[artifact] ?? 0;
    _rejectedPacks[artifact] = previous + 1;
    if (previous > 0) {
      return;
    }
    _log(
      '설치 팩 무결성 대조 실패로 재활성화하지 않고 강등함: '
      'pack=$artifact expected=${_shortHash(expectedSha256)} '
      'actual=${_shortHash(actualSha256)}',
    );
  }

  static String _shortHash(String? value) {
    if (value == null || value.isEmpty) {
      return '없음';
    }
    return value.length <= 12 ? value : value.substring(0, 12);
  }

  static String _sorted(Set<String> values) {
    final sorted = values.toList()..sort();
    return sorted.join(',');
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
