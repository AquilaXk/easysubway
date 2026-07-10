/// 운행 공지 심각도. disruption만 노선도 홈 상단 배너로 승격된다.
enum NoticeSeverity { info, disruption }

/// 공지 대상 범위.
enum NoticeScope { all, region, line }

/// 앱이 소비하는 운행 공지 한 건. 공개 API(`GET /api/notices/active`)의 활성
/// 공지를 표현한다.
class ServiceNotice {
  const ServiceNotice({
    required this.id,
    required this.scope,
    this.scopeValue,
    required this.title,
    required this.body,
    required this.severity,
    required this.publishedAt,
    this.expiresAt,
  });

  final String id;
  final NoticeScope scope;
  final String? scopeValue;
  final String title;
  final String body;
  final NoticeSeverity severity;
  final DateTime publishedAt;
  final DateTime? expiresAt;

  bool get isDisruption => severity == NoticeSeverity.disruption;

  /// API JSON 한 건을 파싱한다. 알 수 없는 enum·필수값 누락이면 null을 돌려준다
  /// (무음 실패 대신 목록에서 제외).
  static ServiceNotice? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    final id = json['id'];
    final title = json['title'];
    final body = json['body'];
    final severity = _severityFrom(json['severity']);
    final scope = _scopeFrom(json['scope']);
    final publishedAt = _dateFrom(json['publishedAt']);
    if (id is! String ||
        title is! String ||
        body is! String ||
        severity == null ||
        scope == null ||
        publishedAt == null) {
      return null;
    }
    final scopeValue = json['scopeValue'];
    return ServiceNotice(
      id: id,
      scope: scope,
      scopeValue: scopeValue is String ? scopeValue : null,
      title: title,
      body: body,
      severity: severity,
      publishedAt: publishedAt,
      expiresAt: _dateFrom(json['expiresAt']),
    );
  }

  /// `ApiResponse.jsonBody['data']` 배열을 파싱하고 잘못된 항목은 건너뛴다.
  static List<ServiceNotice> listFromApiData(Object? data) {
    if (data is! List) {
      return const [];
    }
    final notices = <ServiceNotice>[];
    for (final entry in data) {
      final notice = fromJson(entry);
      if (notice != null) {
        notices.add(notice);
      }
    }
    return notices;
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'scope': scope.name,
      'scopeValue': scopeValue,
      'title': title,
      'body': body,
      'severity': severity.name,
      'publishedAt': publishedAt.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
    };
  }

  static NoticeSeverity? _severityFrom(Object? value) {
    switch (value) {
      case 'INFO':
        return NoticeSeverity.info;
      case 'DISRUPTION':
        return NoticeSeverity.disruption;
      // 캐시 왕복(toJson) 값도 허용.
      case 'info':
        return NoticeSeverity.info;
      case 'disruption':
        return NoticeSeverity.disruption;
      default:
        return null;
    }
  }

  static NoticeScope? _scopeFrom(Object? value) {
    switch (value) {
      case 'ALL':
      case 'all':
        return NoticeScope.all;
      case 'REGION':
      case 'region':
        return NoticeScope.region;
      case 'LINE':
      case 'line':
        return NoticeScope.line;
      default:
        return null;
    }
  }

  static DateTime? _dateFrom(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    final hasOffset = RegExp(
      r'(?:[zZ]|[+-]\d{2}(?::?\d{2})?)$',
    ).hasMatch(value);

    // Backend는 UTC Clock의 LocalDateTime을 offset 없이 직렬화한다. 기기 로컬
    // 시각으로 먼저 해석하면 DST 결손 구간이 보정되므로 처음부터 UTC로 파싱한다.
    return DateTime.tryParse(hasOffset ? value : '${value}Z');
  }
}
