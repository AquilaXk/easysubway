enum FacilityStatusSeverity { blocked, caution, needsInfo, normal }

class FacilityStatusPresentation {
  const FacilityStatusPresentation({
    required this.severity,
    required this.severityLabel,
    required this.statusTitle,
    required this.nextActionLabel,
    required this.nextActionDescription,
    required this.priority,
  });

  final FacilityStatusSeverity severity;
  final String severityLabel;
  final String statusTitle;
  final String nextActionLabel;
  final String nextActionDescription;
  final int priority;

  bool get needsAttention => severity != FacilityStatusSeverity.normal;
}

const _blockedPresentation = FacilityStatusPresentation(
  severity: FacilityStatusSeverity.blocked,
  severityLabel: '고장·폐쇄',
  statusTitle: '이용 불가 확인',
  nextActionLabel: '대체 출구 보기',
  nextActionDescription: '이동 전 다른 출구와 역무원 안내를 확인하세요.',
  priority: 10,
);

const _cautionPresentation = FacilityStatusPresentation(
  severity: FacilityStatusSeverity.caution,
  severityLabel: '점검·제보',
  statusTitle: '현장 확인 필요',
  nextActionLabel: '역무원 도움 요청',
  nextActionDescription: '현장 안내를 확인하고 필요하면 역무원 도움을 요청하세요.',
  priority: 20,
);

const _needsInfoPresentation = FacilityStatusPresentation(
  severity: FacilityStatusSeverity.needsInfo,
  severityLabel: '정보 확인 필요',
  statusTitle: '정보 확인 필요',
  nextActionLabel: '시설 상세 보기',
  nextActionDescription: '최근 확인 시각과 출처를 보고 이동 전 현장 안내를 확인하세요.',
  priority: 30,
);

const _normalPresentation = FacilityStatusPresentation(
  severity: FacilityStatusSeverity.normal,
  severityLabel: '정상',
  statusTitle: '이용 가능',
  nextActionLabel: '상태 제보',
  nextActionDescription: '시설 상태가 다르면 제보해 주세요.',
  priority: 40,
);

FacilityStatusPresentation facilityStatusPresentation(String status) {
  return switch (status.trim().toUpperCase()) {
    'BROKEN' ||
    'CLOSED' ||
    'OUT_OF_SERVICE' ||
    'UNAVAILABLE' => _blockedPresentation,
    'UNDER_CONSTRUCTION' ||
    'CONSTRUCTION' ||
    'USER_REPORTED' => _cautionPresentation,
    'UNKNOWN' ||
    'NEEDS_REPORT' ||
    'NEEDS_CHECK' ||
    'CHECK_REQUIRED' => _needsInfoPresentation,
    'NORMAL' ||
    'ADMIN_VERIFIED' ||
    'AVAILABLE' ||
    'IN_SERVICE' ||
    'OPERATING' ||
    'OPEN' => _normalPresentation,
    _ => _needsInfoPresentation,
  };
}

String buildFacilityAttentionSummary(Iterable<String> statuses) {
  final counts = _attentionCounts(statuses);
  if (counts.isEmpty) {
    return '';
  }
  return counts.entries
      .map((entry) => '${entry.key.severityLabel} ${entry.value}개')
      .join(' · ');
}

String buildFacilityAttentionSemanticLabel(Iterable<String> statuses) {
  final counts = _attentionCounts(statuses);
  if (counts.isEmpty) {
    return '확인이 필요한 시설 없음';
  }
  final summary = counts.entries
      .map((entry) => '${entry.key.severityLabel} ${entry.value}개')
      .join(', ');
  return '확인이 필요한 시설, $summary';
}

String facilityStatusDisplayLabel({
  required String statusLabel,
  required String severityLabel,
}) {
  if (statusLabel == severityLabel) {
    return statusLabel;
  }
  return '$severityLabel · $statusLabel';
}

String facilityStatusSemanticLabel({
  required String statusLabel,
  required String severityLabel,
}) {
  if (statusLabel == severityLabel) {
    return statusLabel;
  }
  return '$statusLabel, $severityLabel';
}

Map<FacilityStatusPresentation, int> _attentionCounts(
  Iterable<String> statuses,
) {
  final counts = <FacilityStatusPresentation, int>{};
  for (final status in statuses) {
    final presentation = facilityStatusPresentation(status);
    if (!presentation.needsAttention) {
      continue;
    }
    counts[presentation] = (counts[presentation] ?? 0) + 1;
  }
  return {
    for (final presentation in const [
      _blockedPresentation,
      _cautionPresentation,
      _needsInfoPresentation,
    ])
      if (counts[presentation] != null) presentation: counts[presentation]!,
  };
}
