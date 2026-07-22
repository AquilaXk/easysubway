/// `contracts/error-codes.json` + backend `messages.properties` 수동 미러.
/// 동기화는 `test/core/error/error_codes_contract_test.dart`가 강제한다.
library;

enum ErrorCategory {
  user('USER'),
  system('SYSTEM'),
  dependency('DEPENDENCY');

  const ErrorCategory(this.wireValue);

  final String wireValue;

  static ErrorCategory fromWire(String value) {
    return ErrorCategory.values.firstWhere(
      (item) => item.wireValue == value,
      orElse: () => ErrorCategory.system,
    );
  }
}

class ErrorCodeEntry {
  const ErrorCodeEntry({
    required this.code,
    required this.category,
    required this.httpStatus,
    required this.koMessageKey,
    required this.userMessage,
  });

  final String code;
  final ErrorCategory category;
  final int httpStatus;
  final String koMessageKey;
  final String userMessage;
}

/// 서버 계약 코드 → 사용자 문구. 코드 원문은 UI에 노출하지 않는다.
const errorCodeCatalog = <ErrorCodeEntry>[
  ErrorCodeEntry(
    code: 'INVALID_REQUEST',
    category: ErrorCategory.user,
    httpStatus: 400,
    koMessageKey: 'error.invalid-request',
    userMessage: '요청 값을 확인해야 합니다.',
  ),
  ErrorCodeEntry(
    code: 'RESOURCE_NOT_FOUND',
    category: ErrorCategory.user,
    httpStatus: 404,
    koMessageKey: 'error.resource-not-found',
    userMessage: '요청한 리소스를 찾을 수 없습니다.',
  ),
  ErrorCodeEntry(
    code: 'CONFLICT',
    category: ErrorCategory.user,
    httpStatus: 409,
    koMessageKey: 'error.conflict',
    userMessage: '요청을 처리할 수 없습니다. 잠시 후 다시 시도해 주세요.',
  ),
  ErrorCodeEntry(
    code: 'UNREADABLE_BODY',
    category: ErrorCategory.user,
    httpStatus: 400,
    koMessageKey: 'error.unreadable-body',
    userMessage: '요청 본문을 확인해야 합니다.',
  ),
  ErrorCodeEntry(
    code: 'INTERNAL_ERROR',
    category: ErrorCategory.system,
    httpStatus: 500,
    koMessageKey: 'error.internal-error',
    userMessage: '일시적인 문제가 발생했어요. 잠시 후 다시 시도해 주세요.',
  ),
  ErrorCodeEntry(
    code: 'ROUTE_SESSION_ATTESTATION_REJECTED',
    category: ErrorCategory.user,
    httpStatus: 403,
    koMessageKey: 'error.route-session-attestation-rejected',
    userMessage: 'ITX 시간표를 불러올 수 없어요',
  ),
  ErrorCodeEntry(
    code: 'ROUTE_SESSION_ATTESTATION_UNAVAILABLE',
    category: ErrorCategory.dependency,
    httpStatus: 503,
    koMessageKey: 'error.route-session-attestation-unavailable',
    userMessage: 'ITX 시간표를 불러올 수 없어요',
  ),
  ErrorCodeEntry(
    code: 'ITX_TIMETABLE_UNAVAILABLE',
    category: ErrorCategory.dependency,
    httpStatus: 503,
    koMessageKey: 'error.itx-timetable-unavailable',
    userMessage: 'ITX 시간표를 불러올 수 없어요',
  ),
  ErrorCodeEntry(
    code: 'ROUTE_SCOPE_INVALID',
    category: ErrorCategory.user,
    httpStatus: 422,
    koMessageKey: 'error.route-scope-invalid',
    userMessage: '지원하지 않는 경로예요',
  ),
  ErrorCodeEntry(
    code: 'ROUTE_SESSION_REQUIRED',
    category: ErrorCategory.user,
    httpStatus: 401,
    koMessageKey: 'error.route-session-required',
    userMessage: '다시 시도',
  ),
  ErrorCodeEntry(
    code: 'ROUTE_RATE_LIMITED',
    category: ErrorCategory.user,
    httpStatus: 429,
    koMessageKey: 'error.route-rate-limited',
    userMessage: '잠시 후 다시 시도',
  ),
  ErrorCodeEntry(
    code: 'ROUTE_ORIGIN_FORBIDDEN',
    category: ErrorCategory.user,
    httpStatus: 403,
    koMessageKey: 'error.route-origin-forbidden',
    userMessage: '접근이 제한되었어요',
  ),
];

const Map<ErrorCategory, String> errorCategoryFallbackMessages = {
  ErrorCategory.user: '요청을 처리하지 못했어요. 잠시 후 다시 시도해 주세요.',
  ErrorCategory.system: '일시적인 문제가 발생했어요. 잠시 후 다시 시도해 주세요.',
  ErrorCategory.dependency: '외부 서비스를 잠시 사용할 수 없어요. 잠시 후 다시 시도해 주세요.',
};

final Map<String, ErrorCodeEntry> errorCodeByWire = {
  for (final entry in errorCodeCatalog) entry.code: entry,
};
