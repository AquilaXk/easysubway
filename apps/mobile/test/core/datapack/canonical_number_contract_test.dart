import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/core/datapack/canonical_json.dart';
import 'package:flutter_test/flutter_test.dart';

/// `contracts/datapack/canonical-number-contract.json` 은 Node·Java·Dart 세 구현이
/// 공유하는 정준 숫자 표기 계약이다. 기대 문자열은 세 런타임 실측으로 고정된 상수이며
/// 이 테스트는 구현을 복제하지 않고 저장된 상수와만 비교한다.
void main() {
  final contract = _loadContract();
  final formatting = (contract['formatting']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final rejectedLiterals = (contract['rejectedLiterals']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final rejectedSpecialValues =
      (contract['rejectedSpecialValues']! as List<Object?>)
          .cast<Map<String, Object?>>();

  test('fixture가 이슈 #2528이 요구한 경계값을 모두 담는다', () {
    final ids = {
      for (final entry in [
        ...formatting,
        ...rejectedLiterals,
        ...rejectedSpecialValues,
      ])
        entry['id']! as String,
    };
    expect(
      ids.length,
      formatting.length +
          rejectedLiterals.length +
          rejectedSpecialValues.length,
    );
    expect(contract['maxSafeIntegerMagnitude'], 9007199254740991);
  });

  for (final entry in formatting) {
    final id = entry['id']! as String;
    final literal = entry['literal']! as String;
    final canonical = entry['canonical']! as String;
    final withinSafeRange = entry['withinSafeRange']! as bool;

    test('formatting/$id: $literal 은 $canonical 로 표기된다', () {
      expect(ecmascriptNumberText(jsonDecode(literal) as num), canonical);
    });

    test('formatting/$id: $literal 의 매니페스트 정준화 결과', () {
      final document = <String, Object?>{'value': jsonDecode(literal)};
      if (withinSafeRange) {
        expect(canonicalDataPackJson(document), '{"value":$canonical}');
      } else {
        expect(
          () => canonicalDataPackJson(document),
          throwsA(isA<FormatException>()),
        );
      }
    });
  }

  for (final entry in rejectedLiterals) {
    final id = entry['id']! as String;
    final literal = entry['literal']! as String;

    test('rejectedLiterals/$id: $literal 은 정준화가 거부한다', () {
      expect(
        () => canonicalDataPackJson(<String, Object?>{
          'value': jsonDecode(literal),
        }),
        throwsA(isA<FormatException>()),
      );
    });
  }

  for (final entry in rejectedSpecialValues) {
    final id = entry['id']! as String;
    final value = _specialValue(entry['value']! as String);

    test('rejectedSpecialValues/$id: FormatException 으로 정규화된다', () {
      expect(
        () => canonicalDataPackJson(<String, Object?>{'value': value}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ecmascriptNumberText(value),
        throwsA(isA<FormatException>()),
      );
    });
  }

  test('키는 UTF-16 코드 유닛 순서로 정렬되고 공백 없이 이어붙인다', () {
    expect(
      canonicalDataPackJson(<String, Object?>{
        'b': <Object?>[1, true, null, 'x'],
        'A': 2,
        'a': <String, Object?>{'z': 3, 'y': 4},
      }),
      '{"A":2,"a":{"y":4,"z":3},"b":[1,true,null,"x"]}',
    );
  });

  test('지원하지 않는 값 유형은 FormatException 으로 거부한다', () {
    expect(
      () =>
          canonicalDataPackJson(<String, Object?>{'value': DateTime.utc(2026)}),
      throwsA(isA<FormatException>()),
    );
  });
}

double _specialValue(String value) {
  return switch (value) {
    'Infinity' => double.infinity,
    '-Infinity' => double.negativeInfinity,
    'NaN' => double.nan,
    _ => throw StateError('unknown special value: $value'),
  };
}

Map<String, Object?> _loadContract() {
  var directory = Directory.current;
  for (var depth = 0; depth < 8; depth += 1) {
    final file = File(
      '${directory.path}/contracts/datapack/canonical-number-contract.json',
    );
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    }
    directory = directory.parent;
  }
  fail(
    'contracts/datapack/canonical-number-contract.json not found from '
    '${Directory.current.path}',
  );
}
