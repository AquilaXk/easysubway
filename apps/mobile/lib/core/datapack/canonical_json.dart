import 'dart:convert';

/// 매니페스트 정준 직렬화가 허용하는 숫자 절댓값 상한(2^53-1).
///
/// Node는 JSON 숫자를 IEEE-754 배정도로만 표현하므로 이 범위 밖 리터럴을 왕복시키지
/// 못한다. 세 언어가 같은 정준 문자열을 만들려면 범위 밖 숫자를 매니페스트에서
/// 금지해야 한다. 계약 원본은 `contracts/datapack/canonical-number-contract.json`.
const int maxSafeCanonicalNumberMagnitude = 9007199254740991;

/// 매니페스트 서명 대상 정준 JSON 문자열을 만든다.
///
/// 키는 UTF-16 코드 유닛 순서로 정렬하고 공백 없이 이어붙이며, 숫자는
/// [ecmascriptNumberText] 표기를 쓴다. 유한하지 않거나
/// [maxSafeCanonicalNumberMagnitude]를 넘는 숫자, 정준화할 수 없는 값 유형은
/// [FormatException]으로 거부한다. `dart:convert`의 `JsonUnsupportedObjectError`는
/// `Error`라서 `data_pack_client.dart`의 `on FormatException` 핸들러를 우회하므로
/// 이 경로에서는 절대 새어 나가지 않아야 한다.
String canonicalDataPackJson(Object? value) {
  final buffer = StringBuffer();
  _writeCanonical(value, buffer);
  return buffer.toString();
}

/// ECMAScript `Number::toString`(= Node `JSON.stringify`)의 숫자 표기를 재현한다.
///
/// Dart 기본 표기와 다른 점은 두 가지뿐이다. 정수값 double의 `.0` 꼬리를 떼고,
/// `-0`을 `0`으로 통일한다. plain 표기와 지수 표기의 경계(1e-6 이상 1e21 미만은
/// plain)와 최단 왕복 자릿수는 Dart `double.toString()`이 이미 ECMAScript와 같다.
String ecmascriptNumberText(num value) {
  if (value is int) {
    return value.toString();
  }
  final number = value.toDouble();
  if (!number.isFinite) {
    throw const FormatException('Data pack canonical number must be finite.');
  }
  final text = number.toString();
  final plain = text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  return plain == '-0' ? '0' : plain;
}

void _writeCanonical(Object? value, StringBuffer out) {
  switch (value) {
    case null:
      out.write('null');
    case final bool flag:
      out.write(flag ? 'true' : 'false');
    case final num number:
      out.write(_canonicalNumberText(number));
    case final String text:
      out.write(jsonEncode(text));
    case final List<Object?> items:
      out.write('[');
      for (var index = 0; index < items.length; index += 1) {
        if (index > 0) {
          out.write(',');
        }
        _writeCanonical(items[index], out);
      }
      out.write(']');
    case final Map<String, Object?> entries:
      final keys = entries.keys.toList()..sort();
      out.write('{');
      for (var index = 0; index < keys.length; index += 1) {
        if (index > 0) {
          out.write(',');
        }
        out
          ..write(jsonEncode(keys[index]))
          ..write(':');
        _writeCanonical(entries[keys[index]], out);
      }
      out.write('}');
    default:
      throw const FormatException(
        'Invalid data pack manifest canonical value.',
      );
  }
}

String _canonicalNumberText(num value) {
  if (value is double && !value.isFinite) {
    throw const FormatException('Data pack canonical number must be finite.');
  }
  if (value > maxSafeCanonicalNumberMagnitude ||
      value < -maxSafeCanonicalNumberMagnitude) {
    throw const FormatException(
      'Data pack canonical number must be within the safe integer range.',
    );
  }
  return ecmascriptNumberText(value);
}
