import '../network/api_client.dart';
import 'error_code_catalog.dart';

class MappedServerError {
  const MappedServerError({
    required this.userMessage,
    required this.category,
    this.code,
    this.correlationId,
    this.statusCode,
  });

  final String userMessage;
  final ErrorCategory category;
  final String? code;
  final String? correlationId;
  final int? statusCode;
}

/// 서버 `code`·`correlationId`를 계약 기반으로 사용자 문구로 매핑한다.
class ServerErrorMapper {
  const ServerErrorMapper();

  MappedServerError fromApiResponse(
    ApiResponse response, {
    String defaultMessage = '요청을 처리하지 못했어요. 잠시 후 다시 시도해 주세요.',
  }) {
    final body = response.jsonBody;
    final map = body is Map ? Map<String, Object?>.from(body) : null;
    final code = map?['code'];
    final correlationId = map?['correlationId'];
    return resolve(
      code: code is String ? code : null,
      correlationId: correlationId is String ? correlationId : null,
      statusCode: response.statusCode,
      defaultMessage: defaultMessage,
    );
  }

  MappedServerError resolve({
    String? code,
    String? correlationId,
    int? statusCode,
    String defaultMessage = '요청을 처리하지 못했어요. 잠시 후 다시 시도해 주세요.',
  }) {
    final entry = code == null ? null : errorCodeByWire[code];
    if (entry != null) {
      return MappedServerError(
        userMessage: entry.userMessage,
        category: entry.category,
        code: entry.code,
        correlationId: _normalizeCorrelationId(correlationId),
        statusCode: statusCode ?? entry.httpStatus,
      );
    }

    final category = _categoryForUnknown(statusCode: statusCode, code: code);
    return MappedServerError(
      userMessage: errorCategoryFallbackMessages[category] ?? defaultMessage,
      category: category,
      code: code,
      correlationId: _normalizeCorrelationId(correlationId),
      statusCode: statusCode,
    );
  }

  ErrorCategory _categoryForUnknown({int? statusCode, String? code}) {
    final upper = code?.toUpperCase() ?? '';
    if (upper.startsWith('DEP_') || upper.contains('UNAVAILABLE')) {
      return ErrorCategory.dependency;
    }
    if (upper.startsWith('SYS_') || upper.contains('INTERNAL')) {
      return ErrorCategory.system;
    }
    if (statusCode != null) {
      if (statusCode == 502 || statusCode == 503 || statusCode == 504) {
        return ErrorCategory.dependency;
      }
      if (statusCode >= 500) {
        return ErrorCategory.system;
      }
      if (statusCode >= 400) {
        return ErrorCategory.user;
      }
    }
    return ErrorCategory.system;
  }

  String? _normalizeCorrelationId(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}

const serverErrorMapper = ServerErrorMapper();
