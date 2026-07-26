import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../logging/app_logger.dart';
import 'user_database.dart';

/// 마이그레이션 실패 복구가 남기는 진단 신호.
///
/// 사용자에게 보여줄 문구는 만들지 않는다. 로그·테스트에서만 읽는다(#2546).
final class UserDatabaseRecoveryReport {
  const UserDatabaseRecoveryReport({
    required this.preservedFilePath,
    required this.salvagedTables,
    required this.salvagedRowCount,
    required this.droppedTables,
    required this.error,
    this.salvageError,
  });

  /// 삭제하지 않고 보관한 원본 DB 경로. 보관할 원본이 없었으면 null.
  final String? preservedFilePath;

  /// 실제로 한 행 이상 옮긴 테이블. 보존 우선순위 순서다.
  ///
  /// 보관본에 있었지만 비어 있던 테이블은 여기에도 [droppedTables]에도 없다.
  final List<String> salvagedTables;

  /// 새 DB로 옮긴 전체 행 수.
  final int salvagedRowCount;

  /// 보관본에는 있었지만 옮기지 못한 테이블.
  final List<String> droppedTables;

  /// 복구를 유발한 열기 실패 원인.
  final Object error;

  /// 보관본 자체를 열지 못해 복구를 시도조차 못 했을 때의 원인.
  final Object? salvageError;
}

class UserDatabaseOpener {
  UserDatabaseOpener({required this.databaseDirectory});

  /// 보관한 원본 DB 파일 이름의 접두사.
  ///
  /// 이 접두사로 시작하는 파일에는 사용자 데이터가 원본 그대로 들어 있다.
  /// 사용자 데이터 삭제 경로가 [deletePreservedDatabases]로 함께 지운다.
  static const preservedFilePrefix = 'user.db.migration-failed-';

  static const _databaseFileName = 'user.db';

  /// 열기 실패 시 총 시도 횟수. 일시적 잠금·I/O 실패를 한 번 흡수한다.
  static const _openAttempts = 2;

  static const _retryDelay = Duration(milliseconds: 200);

  /// 부분 복구 순서. 앞쪽일수록 유실 시 사용자에게 대체 수단이 없다.
  ///
  /// 접수증은 외부에 제출한 신고의 유일한 로컬 추적 수단이고 즐겨찾기는 사용자가
  /// 직접 쌓은 목록이라 1순위, 초안·설정은 체감되는 상태라 2순위, 검색 이력은
  /// 다시 쓰면 복원되므로 3순위다. 복구가 중간에 끊겨도 앞 순서가 살아남는다.
  ///
  /// `UserDatabase`가 선언한 테이블 전체와 일치해야 한다(테스트가 고정한다).
  static const preservationPriority = <String>[
    'report_receipts',
    'favorite_stations',
    'favorite_facilities',
    'favorite_routes',
    'report_drafts',
    'app_preferences',
    'installed_data_packs',
    'data_pack_update_state',
    'search_history',
    'route_search_history',
  ];

  /// 저널 사이드카 접미사. 보관·정리 시 본체와 함께 다룬다.
  static const _sidecarSuffixes = <String>['-wal', '-shm', '-journal'];

  /// DB 내용(스키마·손상) 결함으로 판정하는 sqlite primary result code.
  ///
  /// 잠금·I/O·권한·용량 실패는 원본이 멀쩡하다는 뜻이므로 여기에 없다.
  /// 분류되지 않는 실패도 복구하지 않는다 — 멀쩡한 DB를 치우는 쪽이 훨씬 나쁘다.
  static const _contentFailureResultCodes = <int>{
    1, // SQLITE_ERROR — no such table/column 등 마이그레이션 실패
    11, // SQLITE_CORRUPT
    17, // SQLITE_SCHEMA
    19, // SQLITE_CONSTRAINT
    20, // SQLITE_MISMATCH
    24, // SQLITE_FORMAT
    26, // SQLITE_NOTADB
  };

  static final _sqliteResultCodePattern = RegExp(r'SqliteException\((\d+)\)');

  final Directory databaseDirectory;

  UserDatabaseRecoveryReport? _lastRecovery;

  /// 직전 [open]에서 복구가 일어났으면 그 진단 보고. 아니면 null.
  UserDatabaseRecoveryReport? get lastRecovery => _lastRecovery;

  Future<UserDatabase> open() async {
    _lastRecovery = null;
    await databaseDirectory.create(recursive: true);
    final file = File(p.join(databaseDirectory.path, _databaseFileName));

    for (var attempt = 1; ; attempt++) {
      final database = UserDatabase.file(file);
      try {
        // 마이그레이션은 첫 질의에서 실행된다. 여기서 강제로 열어 실패가
        // 호출자가 아니라 복구 경로로 가게 한다(#2546).
        await database.customSelect('SELECT 1').get();
        return database;
      } on Object catch (error, stackTrace) {
        await _closeQuietly(database);
        if (!_isDatabaseContentFailure(error)) {
          // 잠금·I/O·권한 실패이거나 분류할 수 없는 실패다. 원본이 멀쩡한데
          // 치우면 다른 isolate가 쓰고 있던 데이터가 통째로 사라진다.
          if (attempt < _openAttempts) {
            await Future<void>.delayed(_retryDelay);
            continue;
          }
          appLog.e(
            '사용자 DB를 열지 못했다. DB 내용 결함이 아니라 복구하지 않는다.',
            error: error,
            stackTrace: stackTrace,
          );
          rethrow;
        }
        return _recover(file: file, error: error, stackTrace: stackTrace);
      }
    }
  }

  /// 보관해 둔 원본 DB 파일을 모두 지운다.
  ///
  /// 보관본에는 즐겨찾기·검색 이력·신고 초안·접수증이 원본 그대로 들어 있어
  /// 사용자 데이터 삭제 계약의 대상이다(#2546). 지운 파일 수를 돌려준다.
  static Future<int> deletePreservedDatabases(Directory directory) async {
    if (!await directory.exists()) {
      return 0;
    }
    var deleted = 0;
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      if (!p.basename(entity.path).startsWith(preservedFilePrefix)) {
        continue;
      }
      await entity.delete();
      deleted += 1;
    }
    return deleted;
  }

  /// 복구 경로는 하나다 — 원본 보관 → 새 DB 생성 → 우선순위대로 부분 복구.
  ///
  /// 재시도는 [open]에서 이미 끝났다. 여기까지 온 실패는 DB 내용 결함으로
  /// 판정된 것이며, 이 경로는 원본을 절대 지우지 않는다.
  Future<UserDatabase> _recover({
    required File file,
    required Object error,
    required StackTrace stackTrace,
  }) async {
    final File? preserved;
    try {
      preserved = await _preserveFailedDatabase(file);
    } on Object catch (preserveError, preserveStackTrace) {
      // 원본을 안전하게 치워두지 못하면 새 DB를 만들지 않고 원인을 그대로 올린다.
      appLog.e(
        '사용자 DB 원본 보관에 실패해 복구를 중단했다.',
        error: preserveError,
        stackTrace: preserveStackTrace,
        cause: error,
        causeStackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }

    final database = UserDatabase.file(file);
    final salvaged = <String, int>{};
    final dropped = <String>[];
    Object? salvageError;
    try {
      await database.customSelect('SELECT 1').get();
      if (preserved != null) {
        salvageError = await _salvage(database, preserved, salvaged, dropped);
      }
    } on Object catch (recoverError, recoverStackTrace) {
      await _closeQuietly(database);
      appLog.e(
        '사용자 DB 재생성에 실패해 복구를 중단했다.',
        error: recoverError,
        stackTrace: recoverStackTrace,
        cause: error,
        causeStackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }

    final report = UserDatabaseRecoveryReport(
      preservedFilePath: preserved?.path,
      salvagedTables: List.unmodifiable(salvaged.keys),
      salvagedRowCount: salvaged.values.fold(0, (sum, count) => sum + count),
      droppedTables: List.unmodifiable(dropped),
      error: error,
      salvageError: salvageError,
    );
    _lastRecovery = report;
    appLog.e(
      '사용자 DB 마이그레이션 실패를 복구했다. '
      'preserved=${preserved?.path ?? '(none)'} '
      'salvaged=${_formatRowCounts(salvaged)} dropped=${dropped.join(',')} '
      'salvageError=${salvageError ?? '(none)'}',
      error: error,
      stackTrace: stackTrace,
    );
    return database;
  }

  /// 원본 DB를 삭제하지 않고 이름만 바꿔 보관한다. 사후 복구 여지를 남긴다.
  Future<File?> _preserveFailedDatabase(File file) async {
    if (!await file.exists()) {
      return null;
    }
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp('[:.]'),
      '-',
    );
    final target = p.join(
      p.dirname(file.path),
      '$preservedFilePrefix$stamp${p.extension(file.path)}',
    );
    final preserved = await file.rename(target);
    // 저널 사이드카를 함께 옮겨야 보관본이 커밋된 내용을 그대로 갖는다.
    for (final suffix in _sidecarSuffixes) {
      final sidecar = File('${file.path}$suffix');
      if (await sidecar.exists()) {
        await sidecar.rename('$target$suffix');
      }
    }
    await _warnOnLeftoverSidecars(file);
    return preserved;
  }

  /// 본체를 옮긴 뒤 원래 경로에 사이드카가 남았는지 확인한다.
  ///
  /// 남은 사이드카는 곧 만들 새 `user.db` 옆에 놓이게 된다. 여기서 지우지는
  /// 않는다 — WAL에만 남은 커밋이 들어 있을 수 있어 삭제가 곧 유실이다.
  Future<void> _warnOnLeftoverSidecars(File file) async {
    for (final suffix in _sidecarSuffixes) {
      final sidecar = File('${file.path}$suffix');
      if (await sidecar.exists()) {
        appLog.w('보관하지 못한 사용자 DB 저널이 남았다: ${sidecar.path}');
      }
    }
  }

  /// 보관본에서 살릴 수 있는 테이블만 새 DB로 옮긴다.
  ///
  /// 보관본을 열지 못했으면 그 원인을 돌려준다.
  Future<Object?> _salvage(
    UserDatabase database,
    File preserved,
    Map<String, int> salvaged,
    List<String> dropped,
  ) async {
    try {
      await database.customStatement('ATTACH DATABASE ? AS legacy', [
        preserved.path,
      ]);
    } on Object catch (error) {
      // 보관본을 아예 열 수 없으면 어떤 테이블이 있었는지도 알 수 없다.
      // 목록을 추측해 채우지 않고 원인만 남긴다.
      return error;
    }
    try {
      for (final table in preservationPriority) {
        final copied = await _copyPreservedTable(database, table);
        if (copied > 0) {
          salvaged[table] = copied;
        } else if (copied < 0) {
          dropped.add(table);
        }
      }
    } finally {
      try {
        await database.customStatement('DETACH DATABASE legacy');
      } on Object {
        // 복구 결과를 되돌릴 이유는 없다.
      }
    }
    return null;
  }

  /// 옮긴 행 수. 보관본에 테이블이 없으면 0, 옮길 수 없으면 -1.
  Future<int> _copyPreservedTable(UserDatabase database, String table) async {
    try {
      final legacyColumns = await _columnNames(database, 'legacy', table);
      if (legacyColumns.isEmpty) {
        return 0;
      }
      final targetColumns = await _columnInfo(database, 'main', table);
      if (targetColumns.any(
        (column) => column.required && !legacyColumns.contains(column.name),
      )) {
        // 필수 컬럼이 없는 보관본은 현재 정의로 옮길 수 없다.
        return -1;
      }
      final copyable = targetColumns
          .where((column) => legacyColumns.contains(column.name))
          .toList();
      if (copyable.isEmpty) {
        return -1;
      }
      final names = copyable.map((column) => '"${column.name}"').join(', ');
      // v4 재작성과 같은 타입 정규화를 건다. INTEGER 컬럼(주로 DateTime)이
      // TEXT로 저장된 보관본을 그대로 옮기면 삽입은 되고 읽기에서 던진다.
      final values = copyable
          .map((column) => column.selectExpression)
          .join(', ');
      // 제약을 어기는 행만 건너뛰고 나머지는 최대한 살린다.
      return await database.customUpdate(
        'INSERT OR IGNORE INTO main."$table" ($names) '
        'SELECT $values FROM legacy."$table"',
      );
    } on Object {
      return -1;
    }
  }

  Future<Set<String>> _columnNames(
    UserDatabase database,
    String schema,
    String table,
  ) async {
    final rows = await database
        .customSelect('PRAGMA $schema.table_info("$table")')
        .get();
    return {for (final row in rows) row.read<String>('name')};
  }

  Future<List<_TargetColumn>> _columnInfo(
    UserDatabase database,
    String schema,
    String table,
  ) async {
    final rows = await database
        .customSelect('PRAGMA $schema.table_info("$table")')
        .get();
    final primaryKeyColumnCount = rows
        .where((row) => row.read<int>('pk') > 0)
        .length;
    return [
      for (final row in rows)
        _TargetColumn(
          name: row.read<String>('name'),
          type: row.read<String>('type'),
          required:
              row.read<int>('notnull') == 1 &&
              row.read<String?>('dflt_value') == null &&
              !_isRowIdAlias(
                row.read<int>('pk'),
                row.read<String>('type'),
                primaryKeyColumnCount,
              ),
        ),
    ];
  }

  /// `INTEGER PRIMARY KEY` 단일 키는 rowid 별칭이라 값이 없어도 sqlite가 채운다.
  bool _isRowIdAlias(int pk, String type, int primaryKeyColumnCount) {
    return primaryKeyColumnCount == 1 &&
        pk == 1 &&
        type.toUpperCase() == 'INTEGER';
  }

  /// DB 내용 결함으로 판정되는 실패만 복구 대상이다.
  bool _isDatabaseContentFailure(Object error) {
    if (error.toString().contains(unsupportedUserDatabaseSchemaVersionMarker)) {
      return true;
    }
    final resultCode = _sqliteResultCode(error);
    return resultCode != null &&
        _contentFailureResultCodes.contains(resultCode);
  }

  /// sqlite primary result code. 알 수 없으면 null.
  ///
  /// 백그라운드 isolate에서 온 실패는 `DriftRemoteException`으로 감싸이고 원인이
  /// 문자열로만 전달될 수 있다. 그 래퍼의 `toString()`은 원인 문구를 그대로
  /// 돌려주므로 타입 검사가 실패하면 문구에 남은 result code를 읽는다.
  int? _sqliteResultCode(Object error) {
    if (error is sqlite.SqliteException) {
      return error.resultCode;
    }
    final match = _sqliteResultCodePattern.firstMatch(error.toString());
    final extended = match == null ? null : int.tryParse(match.group(1)!);
    return extended == null ? null : extended & 0xFF;
  }

  String _formatRowCounts(Map<String, int> salvaged) {
    return salvaged.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(',');
  }

  Future<void> _closeQuietly(UserDatabase database) async {
    try {
      await database.close();
    } on Object {
      // 이미 실패한 핸들이라 닫기 실패는 복구를 막지 않는다.
    }
  }
}

final class _TargetColumn {
  const _TargetColumn({
    required this.name,
    required this.type,
    required this.required,
  });

  final String name;

  /// 선언된 sqlite 타입.
  final String type;

  /// 값을 주지 않으면 삽입이 실패하는 컬럼.
  final bool required;

  /// 보관본에서 읽어올 때 쓸 SELECT 식.
  String get selectExpression {
    return type.toUpperCase() == 'INTEGER'
        ? 'CAST("$name" AS INTEGER)'
        : '"$name"';
  }
}
