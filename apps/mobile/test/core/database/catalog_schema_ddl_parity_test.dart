import 'dart:io';

import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:flutter_test/flutter_test.dart';

/// 앱이 구제로 만드는 테이블의 DDL이 팩 스키마 원본과 어긋나지 않는지 고정한다(#2527).
///
/// 구제 테이블은 "팩 산출본"과 "앱 구제본" 두 형태로 갈라질 수 있는데, 정합 게이트는 이름
/// 집합만 비교하므로 제약 차이는 CI에서 드러나지 않는다. 지금은 빈 테이블이라 데이터 영향이
/// 없지만 구제 테이블에 쓰기가 생기는 순간 제약 차이가 동작 차이가 된다.
///
/// 남은 차이는 아래 ledger에만 있어야 한다. ledger에 없는 차이가 생기거나 ledger 항목이
/// 해소되면 이 테스트가 실패해 차이가 조용히 자라지 못한다.
const _knownColumnDifferences = <String, Map<String, String>>{
  'station_facility_evidence': {
    'verified_at':
        '앱 INTEGER(nullable) / 팩 INTEGER NOT NULL DEFAULT 0. drift 컬럼 nullability를 바꾸면 '
        '생성 데이터 클래스 API가 바뀌고, 스키마 버전을 올리지 않는 한 기존 설치본은 옛 형태를 '
        '유지해 onCreate 산출물만 갈라진다. 그 갈라짐이 제약 차이보다 위험해 남겨 둔다.',
    'retrieved_at':
        '앱 INTEGER(nullable) / 팩 INTEGER NOT NULL DEFAULT 0. verified_at과 같은 사유.',
  },
  'station_pathway_edges': {
    'last_verified_at':
        '앱 INTEGER(nullable) / 팩 INTEGER NOT NULL DEFAULT 0. verified_at과 같은 사유.',
  },
};

void main() {
  test('구제 테이블 DDL은 팩 스키마 원본과 제약이 같다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    final rows = await database
        .customSelect(
          "SELECT name, sql FROM sqlite_master "
          "WHERE type = 'table' AND sql IS NOT NULL",
        )
        .get();
    final appDefinitions = {
      for (final row in rows)
        row.read<String>('name'): _parseCreateTable(row.read<String>('sql')),
    };
    final packDefinitions = _parsePackSchema(
      File('../../tools/datapack/schema/catalog-schema.sql').readAsStringSync(),
    );

    final differences = <String, Map<String, String>>{};
    for (final tableName in rescuableCatalogTableNames.toList()..sort()) {
      final app = appDefinitions[tableName];
      final pack = packDefinitions[tableName];
      expect(app, isNotNull, reason: '$tableName: 앱이 만들지 않는다');
      expect(pack, isNotNull, reason: '$tableName: 팩 스키마 원본에 없다');
      expect(
        app!.primaryKey,
        pack!.primaryKey,
        reason: '$tableName: PRIMARY KEY 불일치',
      );
      expect(
        app.foreignKeys,
        pack.foreignKeys,
        reason: '$tableName: FOREIGN KEY 불일치',
      );
      expect(app.checks, pack.checks, reason: '$tableName: CHECK 불일치');
      expect(
        app.columns.keys.toSet(),
        pack.columns.keys.toSet(),
        reason: '$tableName: 컬럼 집합 불일치',
      );
      for (final column in app.columns.keys) {
        if (app.columns[column] == pack.columns[column]) {
          continue;
        }
        differences.putIfAbsent(tableName, () => <String, String>{})[column] =
            '앱 ${app.columns[column]} / 팩 ${pack.columns[column]}';
      }
    }

    expect(
      {
        for (final entry in differences.entries)
          entry.key: entry.value.keys.toSet(),
      },
      {
        for (final entry in _knownColumnDifferences.entries)
          entry.key: entry.value.keys.toSet(),
      },
      reason: 'ledger에 없는 컬럼 차이: $differences',
    );
  });

  test('구제 대상은 앱이 요구하는 필수 테이블 안에 있다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);

    expect(
      database.requiredCatalogTableNames,
      containsAll(rescuableCatalogTableNames),
    );
    expect(
      database.requiredCatalogTableNames,
      containsAll(absenceTolerantCatalogTableNames),
    );
    expect(
      rescuableCatalogTableNames.intersection(absenceTolerantCatalogTableNames),
      isEmpty,
    );
  });
}

class _TableDefinition {
  const _TableDefinition({
    required this.columns,
    required this.primaryKey,
    required this.foreignKeys,
    required this.checks,
  });

  final Map<String, String> columns;
  final List<String> primaryKey;
  final Set<String> foreignKeys;
  final Set<String> checks;
}

Map<String, _TableDefinition> _parsePackSchema(String schemaSql) {
  final definitions = <String, _TableDefinition>{};
  final pattern = RegExp(
    r'CREATE TABLE\s+([a-z0-9_]+)\s*\(',
    caseSensitive: false,
  );
  for (final match in pattern.allMatches(schemaSql)) {
    var depth = 0;
    var index = match.end - 1;
    while (index < schemaSql.length) {
      if (schemaSql[index] == '(') depth++;
      if (schemaSql[index] == ')') {
        depth--;
        if (depth == 0) break;
      }
      index++;
    }
    definitions[match.group(1)!] = _parseCreateTable(
      schemaSql.substring(match.start, index + 1),
    );
  }
  return definitions;
}

/// CREATE TABLE 문을 비교 가능한 제약 집합으로 쪼갠다.
///
/// 표기만 다르고 의미가 같은 형태(컬럼 인라인 PRIMARY KEY vs 테이블 제약, 생략 가능한 NULL
/// 키워드, 공백·따옴표)는 정규화해 없앤다.
_TableDefinition _parseCreateTable(String sql) {
  final open = sql.indexOf('(');
  final body = sql.substring(open + 1, sql.lastIndexOf(')'));
  final columns = <String, String>{};
  final foreignKeys = <String>{};
  final checks = <String>{};
  final primaryKey = <String>[];
  for (final clause in _splitTopLevel(body)) {
    final normalized = clause.replaceAll(RegExp(r'\s+'), ' ').trim();
    final upper = normalized.toUpperCase();
    if (upper.startsWith('PRIMARY KEY')) {
      primaryKey.addAll(_columnList(normalized));
      continue;
    }
    if (upper.startsWith('FOREIGN KEY')) {
      foreignKeys.add(_normalizeExpression(normalized));
      continue;
    }
    if (upper.startsWith('CHECK')) {
      checks.add(_normalizeExpression(normalized));
      continue;
    }
    if (upper.startsWith('UNIQUE') || upper.startsWith('CONSTRAINT')) {
      continue;
    }
    // drift는 식별자를 큰따옴표로 감싸고 팩 스키마 원본은 감싸지 않는다. 표기 차이일 뿐이므로
    // 이름과 정의를 나누기 전에 없앤다.
    final unquoted = normalized.replaceAll('"', '');
    final name = unquoted.split(' ').first;
    var definition = unquoted.substring(name.length).trim();
    for (final check in RegExp(
      r'CHECK\s*\(',
      caseSensitive: false,
    ).allMatches(definition).toList().reversed) {
      var depth = 0;
      var index = check.end - 1;
      while (index < definition.length) {
        if (definition[index] == '(') depth++;
        if (definition[index] == ')') {
          depth--;
          if (depth == 0) break;
        }
        index++;
      }
      checks.add(
        _normalizeExpression(definition.substring(check.start, index + 1)),
      );
      definition = definition.replaceRange(check.start, index + 1, '');
    }
    if (RegExp(r'\bPRIMARY KEY\b', caseSensitive: false).hasMatch(definition)) {
      primaryKey.add(name);
      definition = definition.replaceAll(
        RegExp(r'\bPRIMARY KEY\b', caseSensitive: false),
        '',
      );
    }
    definition = definition
        .replaceAll(RegExp(r'(?<!NOT )\bNULL\b(?! )', caseSensitive: false), '')
        .replaceAll(RegExp(r'(?<!NOT )\bNULL\b ', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    columns[name] = definition;
  }
  return _TableDefinition(
    columns: columns,
    primaryKey: primaryKey,
    foreignKeys: foreignKeys,
    checks: checks,
  );
}

List<String> _columnList(String clause) {
  final open = clause.indexOf('(');
  if (open < 0) {
    return const [];
  }
  return clause
      .substring(open + 1, clause.lastIndexOf(')'))
      .split(',')
      .map((value) => value.trim().replaceAll('"', ''))
      .where((value) => value.isNotEmpty)
      .toList();
}

String _normalizeExpression(String value) => value
    .replaceAll('"', '')
    .replaceAll(RegExp(r'\s*([(),])\s*'), r'$1')
    .replaceAll(RegExp(r'\s+'), ' ')
    .toUpperCase()
    .trim();

List<String> _splitTopLevel(String body) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var depth = 0;
  var quoted = false;
  for (final rune in body.runes) {
    final char = String.fromCharCode(rune);
    if (char == "'") quoted = !quoted;
    if (!quoted && char == '(') depth++;
    if (!quoted && char == ')') depth--;
    if (!quoted && char == ',' && depth == 0) {
      parts.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  if (buffer.isNotEmpty) parts.add(buffer.toString());
  return parts
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
}
