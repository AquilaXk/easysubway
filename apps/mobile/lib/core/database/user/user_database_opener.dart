import 'dart:io';

import 'package:path/path.dart' as p;

import '../../logging/app_logger.dart';
import 'user_database.dart';

/// 마이그레이션 실패 복구가 남기는 진단 신호.
///
/// 사용자에게 보여줄 문구는 만들지 않는다. 로그·테스트에서만 읽는다(#2546).
final class UserDatabaseRecoveryReport {
  const UserDatabaseRecoveryReport({
    required this.preservedFilePath,
    required this.salvagedTables,
    required this.droppedTables,
    required this.error,
  });

  /// 삭제하지 않고 보관한 원본 DB 경로. 보관에 실패했으면 null.
  final String? preservedFilePath;

  /// 새 DB로 옮긴 테이블. 보존 우선순위 순서다.
  final List<String> salvagedTables;

  /// 원본에는 있었지만 옮기지 못한 테이블.
  final List<String> droppedTables;

  /// 복구를 유발한 열기 실패 원인.
  final Object error;
}

class UserDatabaseOpener {
  UserDatabaseOpener({required this.databaseDirectory});

  /// 보관한 원본 DB 파일 이름의 접두사.
  static const preservedFilePrefix = 'user.db.migration-failed-';

  static const _databaseFileName = 'user.db';

  /// 부분 복구 순서. 앞쪽일수록 유실 시 사용자에게 대체 수단이 없다.
  ///
  /// 접수증은 외부에 제출한 신고의 유일한 로컬 추적 수단이고 즐겨찾기는 사용자가
  /// 직접 쌓은 목록이라 1순위, 초안·설정은 체감되는 상태라 2순위, 검색 이력은
  /// 다시 쓰면 복원되므로 3순위다. 복구가 중간에 끊겨도 앞 순서가 살아남는다.
  static const _preservationPriority = <String>[
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

  final Directory databaseDirectory;

  UserDatabaseRecoveryReport? _lastRecovery;

  /// 직전 [open]에서 복구가 일어났으면 그 진단 보고. 아니면 null.
  UserDatabaseRecoveryReport? get lastRecovery => _lastRecovery;

  Future<UserDatabase> open() async {
    _lastRecovery = null;
    await databaseDirectory.create(recursive: true);
    final file = File(p.join(databaseDirectory.path, _databaseFileName));
    final database = UserDatabase.file(file);
    try {
      // 마이그레이션은 첫 질의에서 실행된다. 여기서 강제로 열어 실패가
      // 호출자가 아니라 복구 경로로 가게 한다(#2546).
      await database.customSelect('SELECT 1').get();
      return database;
    } on Object catch (error, stackTrace) {
      await _closeQuietly(database);
      return _recover(file: file, error: error, stackTrace: stackTrace);
    }
  }

  /// 복구 경로는 하나다 — 원본 보관 → 새 DB 생성 → 우선순위대로 부분 복구.
  ///
  /// 재시도는 하지 않는다. 일시적 I/O 실패와 스키마 불일치를 구분할 신뢰할 만한
  /// 신호가 없고, 재시도가 통할 상황이면 다음 실행에서 정상 경로가 열린다.
  /// 이 경로는 원본을 절대 지우지 않으므로 오판해도 데이터가 사라지지 않는다.
  Future<UserDatabase> _recover({
    required File file,
    required Object error,
    required StackTrace stackTrace,
  }) async {
    final File? preserved;
    try {
      preserved = await _preserveFailedDatabase(file);
    } on Object {
      // 원본을 안전하게 치워두지 못하면 새 DB를 만들지 않고 원인을 그대로 올린다.
      Error.throwWithStackTrace(error, stackTrace);
    }

    final database = UserDatabase.file(file);
    final salvaged = <String>[];
    final dropped = <String>[];
    try {
      await database.customSelect('SELECT 1').get();
      if (preserved != null) {
        await _salvage(database, preserved, salvaged, dropped);
      }
    } on Object {
      await _closeQuietly(database);
      Error.throwWithStackTrace(error, stackTrace);
    }

    final report = UserDatabaseRecoveryReport(
      preservedFilePath: preserved?.path,
      salvagedTables: List.unmodifiable(salvaged),
      droppedTables: List.unmodifiable(dropped),
      error: error,
    );
    _lastRecovery = report;
    appLog.e(
      '사용자 DB 마이그레이션 실패를 복구했다. '
      'preserved=${preserved?.path ?? '(none)'} '
      'salvaged=${salvaged.join(',')} dropped=${dropped.join(',')}',
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
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      final sidecar = File('${file.path}$suffix');
      if (await sidecar.exists()) {
        await sidecar.rename('$target$suffix');
      }
    }
    return preserved;
  }

  Future<void> _salvage(
    UserDatabase database,
    File preserved,
    List<String> salvaged,
    List<String> dropped,
  ) async {
    try {
      await database.customStatement('ATTACH DATABASE ? AS legacy', [
        preserved.path,
      ]);
    } on Object {
      // 보관본을 아예 열 수 없으면 어떤 테이블도 옮기지 못한다.
      dropped.addAll(_preservationPriority);
      return;
    }
    try {
      for (final table in _preservationPriority) {
        switch (await _copyPreservedTable(database, table)) {
          case _SalvageOutcome.copied:
            salvaged.add(table);
          case _SalvageOutcome.dropped:
            dropped.add(table);
          case _SalvageOutcome.absent:
            break;
        }
      }
    } finally {
      try {
        await database.customStatement('DETACH DATABASE legacy');
      } on Object {
        // 복구 결과를 되돌릴 이유는 없다.
      }
    }
  }

  Future<_SalvageOutcome> _copyPreservedTable(
    UserDatabase database,
    String table,
  ) async {
    try {
      final legacyColumns = await _columnNames(database, 'legacy', table);
      if (legacyColumns.isEmpty) {
        return _SalvageOutcome.absent;
      }
      final targetColumns = await _columnInfo(database, 'main', table);
      if (targetColumns.any(
        (column) => column.required && !legacyColumns.contains(column.name),
      )) {
        // 필수 컬럼이 없는 보관본은 현재 정의로 옮길 수 없다.
        return _SalvageOutcome.dropped;
      }
      final copyable = targetColumns
          .where((column) => legacyColumns.contains(column.name))
          .map((column) => '"${column.name}"')
          .join(', ');
      if (copyable.isEmpty) {
        return _SalvageOutcome.dropped;
      }
      // 제약을 어기는 행만 건너뛰고 나머지는 최대한 살린다.
      await database.customStatement(
        'INSERT OR IGNORE INTO main."$table" ($copyable) '
        'SELECT $copyable FROM legacy."$table"',
      );
      return _SalvageOutcome.copied;
    } on Object {
      return _SalvageOutcome.dropped;
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

  Future<void> _closeQuietly(UserDatabase database) async {
    try {
      await database.close();
    } on Object {
      // 이미 실패한 핸들이라 닫기 실패는 복구를 막지 않는다.
    }
  }
}

enum _SalvageOutcome { copied, dropped, absent }

final class _TargetColumn {
  const _TargetColumn({required this.name, required this.required});

  final String name;

  /// 값을 주지 않으면 삽입이 실패하는 컬럼.
  final bool required;
}
