import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/core/error/error_code_catalog.dart';
import 'package:easysubway_mobile/core/error/server_error_mapper.dart';
import 'package:easysubway_mobile/core/network/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final repoRoot = _findRepoRoot();

  test('errorCodeCatalog mirrors contracts/error-codes.json wire fields', () {
    final contractPath = File('${repoRoot.path}/contracts/error-codes.json');
    expect(contractPath.existsSync(), isTrue);

    final contract = (jsonDecode(contractPath.readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    expect(errorCodeCatalog.length, contract.length);

    final byCode = {for (final entry in errorCodeCatalog) entry.code: entry};
    for (final raw in contract) {
      final code = raw['code'] as String;
      final entry = byCode[code];
      expect(entry, isNotNull, reason: 'missing mobile mirror for $code');
      expect(entry!.category.wireValue, raw['category']);
      expect(entry.httpStatus, raw['httpStatus']);
      expect(entry.koMessageKey, raw['koMessageKey']);
    }
  });

  test('errorCodeCatalog userMessage matches backend messages.properties', () {
    final properties = File(
      '${repoRoot.path}/backend/src/main/resources/messages.properties',
    ).readAsStringSync();
    final messages = <String, String>{};
    for (final line in properties.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('#') ||
          !trimmed.contains('=')) {
        continue;
      }
      final index = trimmed.indexOf('=');
      messages[trimmed.substring(0, index)] = trimmed.substring(index + 1);
    }

    for (final entry in errorCodeCatalog) {
      expect(
        messages[entry.koMessageKey],
        entry.userMessage,
        reason: entry.koMessageKey,
      );
    }
  });

  test('known code maps to contract message and preserves correlationId', () {
    final mapped = serverErrorMapper.fromApiResponse(
      const ApiResponse(
        statusCode: 429,
        jsonBody: {
          'success': false,
          'code': 'ROUTE_RATE_LIMITED',
          'correlationId': 'corr-123',
          'message': 'ignored-technical',
        },
      ),
    );
    expect(mapped.userMessage, '잠시 후 다시 시도');
    expect(mapped.code, 'ROUTE_RATE_LIMITED');
    expect(mapped.correlationId, 'corr-123');
    expect(mapped.userMessage.contains('ROUTE_'), isFalse);
  });

  test('unknown code falls back to category default message', () {
    final mapped = serverErrorMapper.resolve(
      code: 'TOTALLY_UNKNOWN_CODE',
      correlationId: 'corr-unknown',
      statusCode: 500,
    );
    expect(
      mapped.userMessage,
      errorCategoryFallbackMessages[ErrorCategory.system],
    );
    expect(mapped.correlationId, 'corr-unknown');
    expect(mapped.userMessage.contains('TOTALLY_UNKNOWN'), isFalse);
  });
}

Directory _findRepoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File('${dir.path}/contracts/error-codes.json').existsSync()) {
      return dir;
    }
    dir = dir.parent;
  }
  fail('contracts/error-codes.json not found from ${Directory.current.path}');
}
