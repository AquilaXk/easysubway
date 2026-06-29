import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _forbiddenUserCopy = <String>[
  '실기기 QA',
  '데이터팩',
  '공공 API',
  '공식 파일',
  '관리자 검수',
  '현장 검증',
  '정보 신뢰도',
  '높은 신뢰도',
  '보통 신뢰도',
  '낮은 신뢰도',
  '기본정보',
  '기본 정보',
  '기본 정보만 있음',
  '정보만',
  '기본 데이터',
  '데이터 품질',
  '확인 수준',
  '확인 필요',
  '확인이 필요',
  '확인 요청',
  '정보 확인 필요',
  '상태 확인 필요',
  '현장 확인 필요',
  '노선 정보 없음',
  '위치 확인 필요',
  '이용 불가 확인',
  '심각도',
  '다음 행동',
  '권장 행동',
  '기준:',
  '출처',
  '점검·제보',
  '취약점',
  '검수 완료',
  '제보 필요',
  '추정',
  '정적 추정',
  '측정값',
  '로그인 정보',
  '인증 정보',
  '계정 접근',
  '내부 이동 기준점',
  '기준점',
  '이동 점수',
  '이동 편의도',
  '점수',
  '최근 확인됨',
  '우선 적용',
  '기본 적용',
  'routeSearchId',
  'UUID',
  'token',
  'OFFICIAL_',
  'ADMIN_VERIFIED',
  'local-user',
];

void expectNoForbiddenUserCopy(WidgetTester tester) {
  final visibleCopy = <String>{};
  for (final widget in tester.allWidgets) {
    switch (widget) {
      case Text(:final data, :final textSpan):
        visibleCopy.add(data ?? textSpan?.toPlainText() ?? '');
      case Tooltip(:final message):
        visibleCopy.add(message ?? '');
      case Semantics(:final properties):
        visibleCopy.addAll([
          properties.label ?? '',
          properties.value ?? '',
          properties.hint ?? '',
        ]);
    }
  }

  for (final copy in visibleCopy.where((copy) => copy.trim().isNotEmpty)) {
    for (final forbidden in _forbiddenUserCopy) {
      expect(copy, isNot(contains(forbidden)));
    }
    expect(
      copy,
      isNot(matches(RegExp(r'(^|[^A-Za-z])(?:edge|node)([^A-Za-z]|$)'))),
    );
    expect(copy, isNot(matches(RegExp(r'\d+\s*점'))));
  }
}
